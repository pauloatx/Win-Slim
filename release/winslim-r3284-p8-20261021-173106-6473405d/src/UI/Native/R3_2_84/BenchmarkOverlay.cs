using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Path = System.IO.Path;

namespace WinSlim.NativeUI
{
    public sealed class BenchmarkOverlayPlacement
    {
        public int Schema { get; set; }
        public double X { get; set; }
        public double Y { get; set; }
        public bool Medium { get; set; }
        public bool Locked { get; set; }
        public string MonitorId { get; set; }
        public int LastLeft { get; set; }
        public int LastTop { get; set; }
        public double PanelScale { get; set; }
        public double BackgroundOpacity { get; set; }
        public bool CurrentFps { get; set; }
        public bool Sensors { get; set; }
        public bool ShowCpu { get; set; }
        public bool ShowGpu { get; set; }
        public bool ShowVram { get; set; }
        public bool ShowRam { get; set; }
        public string[] Hotkeys { get; set; }
        public BenchmarkOverlayPlacement() { PanelScale = 1; BackgroundOpacity = .93; ShowCpu = ShowGpu = ShowVram = ShowRam = true; }
        internal BenchmarkOverlayPlacement Clone() { var result=(BenchmarkOverlayPlacement)MemberwiseClone(); if(Hotkeys!=null)result.Hotkeys=(string[])Hotkeys.Clone(); return result; }
        internal void CopyFrom(BenchmarkOverlayPlacement other)
        {
            Schema=other.Schema; X=other.X; Y=other.Y; Medium=other.Medium; Locked=other.Locked; MonitorId=other.MonitorId; LastLeft=other.LastLeft; LastTop=other.LastTop;
            PanelScale=other.PanelScale; BackgroundOpacity=other.BackgroundOpacity; CurrentFps=other.CurrentFps; Sensors=other.Sensors;
            ShowCpu=other.ShowCpu; ShowGpu=other.ShowGpu; ShowVram=other.ShowVram; ShowRam=other.ShowRam; Hotkeys=other.Hotkeys==null?null:(string[])other.Hotkeys.Clone();
        }
        internal static double Clamp(double value) { return Double.IsNaN(value) || Double.IsInfinity(value) ? 0 : Math.Max(0, Math.Min(1, value)); }
        internal static string PathFor(string root, string game)
        {
            if (String.IsNullOrWhiteSpace(game)) throw new ArgumentException("Game identity required.");
            using (SHA256 sha = SHA256.Create()) {
                string key = BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(game.ToLowerInvariant()))).Replace("-", "");
                return System.IO.Path.Combine(root, "config", "benchmark-overlay", key + ".json");
            }
        }
        internal static BenchmarkOverlayPlacement Load(string path)
        {
            if (!File.Exists(path)) return new BenchmarkOverlayPlacement { Schema = 1, X = .02, Y = .03, Locked = true };
            if (new FileInfo(path).Length > 4096) throw new InvalidDataException("Overlay settings exceed limit.");
            BenchmarkOverlayPlacement value = new JavaScriptSerializer().Deserialize<BenchmarkOverlayPlacement>(File.ReadAllText(path, Encoding.UTF8));
            if (value == null || !value.Valid()) throw new InvalidDataException("Invalid overlay settings.");
            return value;
        }
        internal void Save(string path)
        {
            if (!Valid()) throw new InvalidDataException("Invalid overlay position.");
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path));
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp", backup = temporary + ".previous";
            try {
                File.WriteAllText(temporary, new JavaScriptSerializer().Serialize(this), new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temporary, path, backup); else File.Move(temporary, path);
            } finally { if (File.Exists(temporary)) File.Delete(temporary); if (File.Exists(backup)) File.Delete(backup); }
        }
        private bool Valid()
        {
            if(Hotkeys!=null){if(Hotkeys.Length!=3)return false;foreach(string binding in Hotkeys){if(binding==null || binding.Length>64)return false;try{uint mod,key;BenchmarkHotkeys.Parse(binding,out mod,out key);}catch(ArgumentException){return false;}}}
            return (Schema == 1 || (Schema == 2 && !String.IsNullOrWhiteSpace(MonitorId) && MonitorId.Length <= 128 && Math.Abs((long)LastLeft) <= 1000000 && Math.Abs((long)LastTop) <= 1000000))
                && X == Clamp(X) && Y == Clamp(Y) && PanelScale >= .75 && PanelScale <= 1.75 && BackgroundOpacity >= .35 && BackgroundOpacity <= 1;
        }
    }

    internal sealed class BenchmarkOverlay : Window
    {
        private readonly string _settingsPath;
        private readonly string _root;
        private readonly BenchmarkGame _game;
        private readonly Action<string> _log;
        private readonly BenchmarkOverlayPlacement _placement;
        private readonly TextBlock[] _values = new TextBlock[4];
        private readonly TextBlock _status;
        private readonly Canvas _chart;
        private readonly Button _small, _medium, _move;
        private readonly Border _drag;
        private readonly StackPanel _controls;
        private readonly Window _controlsWindow;
        private readonly Func<BenchmarkOverlayMonitor[]> _monitors;
        private double[] _reference;
        private readonly TextBlock _fpsLabel, _sensors;
        private readonly Button _fpsMode;
        private readonly Border _frame;
        private string _liveState = "Coletando amostras";
        private double _effectiveScale = 1;
        private bool _editing;
        private string _sensorReadings = "CPU: Indisponível\nGPU: Indisponível\nVRAM: Indisponível\nRAM: Indisponível";
        internal string GameName { get { return _game.Name; } }
        internal string GameIdentity { get { return _game.Identity; } }
        internal bool PreferencesSaved { get { return !_savingFailed; } }
        internal BenchmarkOverlayPlacement Preferences { get { return _placement; } }
        private readonly DispatcherTimer _moveTimer;
        private Point? _dragStart;
        private BenchmarkGameWindow.Bounds _dragBounds;
        private BenchmarkLiveSnapshot _snapshot;
        private IntPtr _handle;
        private bool _savingFailed, _placing, _applyingMode, _closed;
        private string _geometryError;
        internal Window ControlsWindow { get { return _controlsWindow; } }
        internal bool Medium { get { return _placement.Medium; } }
        internal bool Locked { get { return _placement.Locked; } }
        internal int MetricCount { get { return _values.Length; } }
        internal bool ChartVisible { get { return _chart.Visibility == Visibility.Visible; } }
        internal string MetricText(int index) { return _values[index].Text; }
        internal Polyline ChartCurve(bool reference) { return _chart.Children.OfType<Polyline>().FirstOrDefault(p => Convert.ToString(p.Tag) == (reference ? "OverlayReference" : "OverlayCurrent")); }
        internal int ChartPointCount { get { Polyline curve = ChartCurve(false); return curve == null ? 0 : curve.Points.Count; } }
        internal int ReferenceCount { get { return _reference == null ? 0 : _reference.Length; } }
        internal BenchmarkOverlay(string root, BenchmarkGame game, Action<string> log, double[] reference = null, Func<BenchmarkOverlayMonitor[]> monitors = null)
        {
            _root = root; _game = game; _log = log; _settingsPath = BenchmarkOverlayPlacement.PathFor(root, game.Identity);
            _monitors = monitors ?? BenchmarkOverlayDesktop.Monitors;
            _reference = ValidSeries(reference) ? (double[])reference.Clone() : null;
            try { _placement = BenchmarkOverlayPlacement.Load(_settingsPath); }
            catch (Exception ex) { _log(ex.Message); _placement = new BenchmarkOverlayPlacement { Schema = 1, X = .02, Y = .03, Locked = true }; }
            Title = "Win-Slim · " + game.Name;
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; ShowActivated = false;
            Topmost = true; Background = Brushes.Transparent; AllowsTransparency = true; SizeToContent = SizeToContent.Height;
            Foreground = Brushes.White; FontFamily = new FontFamily("Segoe UI"); FontSize = 11;
            StackPanel panel = new StackPanel();
            Border frame = new Border { Background = new SolidColorBrush(Color.FromArgb(237, 12, 15, 16)), BorderBrush = new SolidColorBrush(Color.FromRgb(255, 128, 0)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(7), Padding = new Thickness(9), Child = panel };
            Content = frame; _frame = frame;
            _drag = new Border { Background = Brushes.Transparent, Padding = new Thickness(0, 1, 0, 7), Child = new TextBlock { Text = "Win-Slim · " + game.Name, TextTrimming = TextTrimming.CharacterEllipsis } };
            panel.Children.Add(_drag);
            _controls = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 7) };
            _small = CreateControl("Pequeno", delegate { SetMedium(false); }); _small.Name = "OverlaySmall";
            _medium = CreateControl("Médio", delegate { SetMedium(true); }); _medium.Name = "OverlayMedium";
            _move = CreateControl("Mover", delegate { SetLocked(!Locked); }); _move.Name = "OverlayMove";
            _fpsMode = CreateControl("FPS: médio", delegate { _placement.CurrentFps = !_placement.CurrentFps; ApplyPreferences(); }); _fpsMode.Name = "OverlayFpsMode";
            _controls.Children.Add(_small); _controls.Children.Add(new TextBlock { Text = "|", Margin = new Thickness(0, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center }); _controls.Children.Add(_medium); _controls.Children.Add(_move); panel.Children.Add(_controls);
            _controls.Children.Add(_fpsMode);
            Grid metrics = new Grid { ToolTip = "FPS de apresentação. Médio, 1% low, média e P99: últimos 5 s (até 4096 quadros). FPS atual: último 1 s. Benchmark usa a captura completa." };
            for (int i = 0; i < 4; i++) metrics.ColumnDefinitions.Add(new ColumnDefinition());
            string[] labels = { "FPS médio", "Quedas de\nfluidez", "Tempo por\nquadro", "Picos de\ndemora" };
            string[] units = { "FPS", "1% low · FPS", "média · ms", "P99 · ms" };
            for (int i = 0; i < 4; i++) {
                StackPanel cell = new StackPanel { Margin = new Thickness(0, 0, 6, 0) }; Grid.SetColumn(cell, i);
                TextBlock caption = new TextBlock { Text = UiLanguage.Text(labels[i]), FontSize = 10, Height = 28, TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightGray };
                if (i == 0) _fpsLabel = caption;
                cell.Children.Add(caption);
                _values[i] = new TextBlock { Text = "—", FontSize = 26, FontWeight=FontWeights.SemiBold, Foreground = i == 0 ? Brushes.DarkOrange : Brushes.White };
                System.Windows.Documents.Typography.SetNumeralAlignment(_values[i],FontNumeralAlignment.Tabular);
                cell.Children.Add(new Viewbox {Child=_values[i], Height=34, Stretch=Stretch.Uniform, StretchDirection=StretchDirection.DownOnly, HorizontalAlignment=HorizontalAlignment.Left});
                cell.Children.Add(new TextBlock {Text=units[i],FontSize=10,Foreground=Brushes.LightGray,Margin=new Thickness(0,2,0,0)}); metrics.Children.Add(cell);
            }
            panel.Children.Add(metrics);
            _sensors = new TextBlock { Foreground = Brushes.LightGray, FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0), ToolTip="Indisponível: esta leitura não está disponível no computador neste momento." }; panel.Children.Add(_sensors);
            _chart = new Canvas { Height = 110, Margin = new Thickness(0, 7, 0, 0), ClipToBounds = true, Background = new SolidColorBrush(Color.FromRgb(22, 25, 26)), ToolTip = UiLanguage.Text("Posição relativa das amostras; não representa o mesmo instante nas duas capturas.") };
            _chart.SizeChanged += delegate { Draw(); };
            panel.Children.Add(_chart);
            _status = new TextBlock { Foreground = Brushes.LightGray, FontSize = 10, Margin = new Thickness(0, 6, 0, 0), TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed }; panel.Children.Add(_status);
            _controlsWindow = CreateControlsWindow();
            _moveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
            _moveTimer.Tick += delegate {
                if (_closed || Locked || !_dragStart.HasValue || !BenchmarkOverlayDesktop.DragButtonDown) { EndMove(); ReleaseMouseCapture(); return; }
                try { ContinueMove(BenchmarkOverlayDesktop.CursorPoint()); }
                catch (Exception ex) { GeometryFailed(ex); EndMove(); ReleaseMouseCapture(); }
            };
            SourceInitialized += delegate {
                _handle = new WindowInteropHelper(this).Handle;
                HwndSource source = HwndSource.FromHwnd(_handle);
                source.AddHook(NoActivation);
                ApplyLock();
                _controlsWindow.Owner = this;
                new WindowInteropHelper(_controlsWindow).EnsureHandle();
                Place();
            };
            SizeChanged += delegate { Place(); Draw(); SyncControls(); };
            LocationChanged += delegate { SyncControls(); };
            Closing += delegate { EndMove(); ReleaseMouseCapture(); };
            Closed += delegate { _closed = true; _moveTimer.Stop(); _controlsWindow.Close(); };
            IsVisibleChanged += delegate { if (!IsVisible) _controlsWindow.Hide(); };
            MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e) {
                if (Locked) return;
                try { BeginMove(BenchmarkOverlayDesktop.CursorPoint()); CaptureMouse(); e.Handled = true; }
                catch (Exception ex) { GeometryFailed(ex); }
            };
            MouseMove += delegate(object sender, MouseEventArgs e) {
                if (!_dragStart.HasValue || e.LeftButton != MouseButtonState.Pressed) return;
                try { ContinueMove(BenchmarkOverlayDesktop.CursorPoint()); }
                catch (Exception ex) { GeometryFailed(ex); }
            };
            MouseLeftButtonUp += delegate { EndMove(); ReleaseMouseCapture(); };
            LostMouseCapture += delegate { EndMove(); };
            ApplyPreferences(false); ApplyLock();
        }
        internal void SetReference(double[] reference) { _reference = ValidSeries(reference) ? (double[])reference.Clone() : null; Draw(); }
        internal void SetState(string state) { _liveState = state; RefreshStatus(); }
        internal string StatusText { get { return _status.Text; } }
        internal void SetSensors(string text) { _sensorReadings=text; RenderSensors(); }
        private void RenderSensors()
        {
            bool[] enabled={_placement.ShowCpu,_placement.ShowGpu,_placement.ShowVram,_placement.ShowRam};string[] names={"CPU:","GPU:","VRAM", "RAM:"};
            _sensors.Text=String.Join("\n",names.Where((name,i)=>enabled[i]).Select(name=>(_sensorReadings??"").Split('\n').FirstOrDefault(line=>line.StartsWith(name,StringComparison.Ordinal)) ?? name+" Indisponível"));
        }
        internal BenchmarkOverlayPlacement BeginPreferencesEdit() { if(_editing)throw new InvalidOperationException("Configuração já aberta."); EndMove(); _editing=true; return _placement.Clone(); }
        internal void ApplyEditedPreferences()
        {
            BenchmarkGameWindow.Bounds anchor=new BenchmarkGameWindow.Bounds();bool anchored=_handle!=IntPtr.Zero&&!_closed;
            if(anchored)anchor=BenchmarkOverlayDesktop.Rect(_handle);
            ApplyPreferences(false);
            if(anchored){try{
                _placing=true;_frame.Measure(new Size(Width,Double.PositiveInfinity));_frame.Arrange(new Rect(0,0,Width,_frame.DesiredSize.Height));_frame.UpdateLayout();
                double sx=1,sy=1;var source=PresentationSource.FromVisual(this);if(source!=null&&source.CompositionTarget!=null){sx=source.CompositionTarget.TransformToDevice.M11;sy=source.CompositionTarget.TransformToDevice.M22;}
                int width=(int)Math.Ceiling(Width*sx),height=(int)Math.Ceiling(_frame.DesiredSize.Height*sy);
                var at=BenchmarkOverlayGeometry.FinishMove(_monitors(),anchor.Left,anchor.Top,width,height);BenchmarkOverlayDesktop.Move(_handle,at.Left,at.Top,width,height,true);BenchmarkOverlayGeometry.Remember(_placement,at,width,height);
            }catch(Exception ex){GeometryFailed(ex);}finally{_placing=false;}Place();}
        }
        internal void CommitPreferencesEdit() { _placement.Save(_settingsPath); _savingFailed=false; _editing=false; RefreshStatus(); }
        internal void CancelPreferencesEdit(BenchmarkOverlayPlacement original) { _placement.CopyFrom(original); ApplyPreferences(false); ApplyLock(); _editing=false; }
        internal BenchmarkOverlay CreateIllustrativePreview()
        {
            var preview=new BenchmarkOverlay(_root,_game,_log,_reference==null?null:new double[]{18,22,19,25,20,23},_monitors);
            preview.BeginPreferencesEdit(); preview.Preferences.CopyFrom(_placement);preview.ApplyPreferences(false);
            preview.Update(new BenchmarkLiveSnapshot {Fps=60,CurrentFps=64,Low=48,Mean=16.67,P99=24.8,Times=new double[]{16,17,15,18,16,24,17,16},UpdatedUtc=DateTime.UtcNow});
            preview.SetState("Prévia — valores ilustrativos");
            preview.SetSensors("CPU: 32% · 62 °C\nGPU: 76% · 68 °C\nVRAM: 4096 MiB\nRAM: 54%");return preview;
        }
        internal FrameworkElement DetachPreviewContent() { var content=(FrameworkElement)Content; Content=null;content.IsHitTestVisible=false;return content; }
        internal void ApplyPreferences(bool save = true)
        {
            _fpsLabel.Text = UiLanguage.Text(_placement.CurrentFps ? "FPS atual" : "FPS médio");
            _fpsMode.Content = _placement.CurrentFps ? "FPS: atual" : "FPS: médio";
            _sensors.Visibility = _placement.Sensors ? Visibility.Visible : Visibility.Collapsed;
            RenderSensors();
            _frame.Background = new SolidColorBrush(Color.FromArgb((byte)Math.Round(_placement.BackgroundOpacity * 255), 12, 15, 16));
            FontSize = 11;
            _effectiveScale = _placement.PanelScale;
            _frame.LayoutTransform = new ScaleTransform(_effectiveScale, _effectiveScale);
            _frame.Width = Medium ? 420 : 360;
            if (_controlsWindow != null) ((FrameworkElement)_controlsWindow.Content).LayoutTransform = new ScaleTransform(_placement.PanelScale, _placement.PanelScale);
            ApplyMode(); Update(_snapshot); if (save) Persist();
        }
        internal void ResetPreferences()
        {
            EndMove(); _placement.Schema = 1; _placement.X = .02; _placement.Y = .03; _placement.Medium = false; _placement.Locked = true;
            _placement.PanelScale = 1; _placement.BackgroundOpacity = .93; _placement.CurrentFps = false; _placement.Sensors = false;
            ApplyPreferences(); ApplyLock();
        }
        private static IntPtr NoActivation(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled)
        {
            if (msg == 0x21) { handled = true; return new IntPtr(3); } // MA_NOACTIVATE
            return IntPtr.Zero;
        }
        private Window CreateControlsWindow()
        {
            // The layered metrics HWND passes input through to other processes when locked.
            // A separate, tightly fitted HWND keeps only the visible controls interactive.
            StackPanel panel = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (FrameworkElement element in _controls.Children) {
                Button original = element as Button;
                if (original == null) { panel.Children.Add(new TextBlock { Text = "|", Foreground = Brushes.White, FontSize = FontSize, Margin = element.Margin, VerticalAlignment = VerticalAlignment.Center }); continue; }
                Button proxy = new Button { Name = original.Name, Focusable = false, IsTabStop = false, Margin = original.Margin, Template = original.Template, FontSize = FontSize };
                foreach (DependencyProperty property in new DependencyProperty[] { ContentControl.ContentProperty, Control.BackgroundProperty, Control.ForegroundProperty, Control.FontWeightProperty, FrameworkElement.ToolTipProperty })
                    proxy.SetBinding(property, new Binding { Source = original, Path = new PropertyPath(property) });
                proxy.Width=original.Width;proxy.Height=original.Height;
                proxy.Click += delegate { original.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); };
                panel.Children.Add(proxy);
            }
            Window window = new Window { Title = "Win-Slim overlay controls", WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, AllowsTransparency = true,
                Background = Brushes.Transparent, Content = panel, SizeToContent = SizeToContent.WidthAndHeight, ShowActivated = false, ShowInTaskbar = false, Topmost = true };
            window.SourceInitialized += delegate {
                IntPtr handle = new WindowInteropHelper(window).Handle;
                HwndSource.FromHwnd(handle).AddHook(NoActivation); BenchmarkOverlayDesktop.InputStyle(handle, false);
            };
            return window;
        }
        private void SyncControls()
        {
            if (_closed || _handle == IntPtr.Zero || _controlsWindow == null || _controls.ActualHeight <= 0) return;
            FrameworkElement content = (FrameworkElement)Content;
            if (content.ActualWidth <= 0 || content.ActualHeight <= 0) return;
            IntPtr handle = new WindowInteropHelper(_controlsWindow).Handle;
            if (handle == IntPtr.Zero) return;
            BenchmarkGameWindow.Bounds bounds = BenchmarkOverlayDesktop.Rect(_handle);
            Point at = _controls.TranslatePoint(new Point(), content);
            double sx = (bounds.Right - bounds.Left) / content.ActualWidth, sy = (bounds.Bottom - bounds.Top) / content.ActualHeight;
            double width = _controls.Children.OfType<FrameworkElement>().Sum(e => e.ActualWidth + e.Margin.Left + e.Margin.Right);
            BenchmarkOverlayDesktop.Move(handle, bounds.Left + (int)Math.Round(at.X * sx), bounds.Top + (int)Math.Round(at.Y * sy),
                Math.Max(1, (int)Math.Ceiling(width * sx)), Math.Max(1, (int)Math.Ceiling(_controls.ActualHeight * sy)), true);
        }
        public new void Show() { base.Show(); Place(); _controlsWindow.Show(); SyncControls(); }
        public new void Hide() { EndMove(); ReleaseMouseCapture(); _controlsWindow.Hide(); base.Hide(); }
        internal static double[] ReferenceForGame(BenchmarkResult reference, string application, int seconds)
        {
            if (reference == null || !ValidSeries(reference.FrameTimesMs)) return null;
            try { PresentMonBenchmark.Compare(reference, new BenchmarkResult { Application = application, RequestedSeconds = seconds }); return (double[])reference.FrameTimesMs.Clone(); }
            catch (InvalidOperationException) { return null; }
        }
        private static bool ValidSeries(double[] samples) { return samples != null && samples.Length >= 2 && samples.Length <= 100000 && samples.All(v => !Double.IsNaN(v) && !Double.IsInfinity(v) && v > 0 && v <= 120000); }
        internal static void CleanupStateFixture(string directory, Action<string> delete = null, Action<int> delay = null)
        {
            string full = Path.GetFullPath(directory), parent = Path.GetDirectoryName(full), prefix = "winslim-overlay-state-", name = Path.GetFileName(full);
            Guid id;
            if (!String.Equals(parent, Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)
                || !name.StartsWith(prefix, StringComparison.Ordinal) || !Guid.TryParseExact(name.Substring(prefix.Length), "N", out id)) throw new ArgumentException("Fixture cleanup target is outside its dedicated temporary directory.");
            if (delete == null) delete = delegate(string path) { Directory.Delete(path, true); };
            if (delay == null) delay = System.Threading.Thread.Sleep;
            for (int attempt = 0; attempt < 10; attempt++) {
                try { if (Directory.Exists(full)) delete(full); return; }
                catch (IOException) { if (attempt == 9) throw; delay(50); }
            }
        }
        private Button CreateControl(string label, Action action)
        {
            Button button = new Button { Content = UiLanguage.Text(label), Focusable = false, Height=28,Width=label=="Pequeno"?68:label=="Médio"?56:label=="Mover"?64:102, Padding = new Thickness(6, 3, 6, 3), Margin = new Thickness(0, 0, 4, 0), Foreground = Brushes.White, Background = new SolidColorBrush(Color.FromRgb(35, 39, 41)), BorderBrush = Brushes.DimGray };
            // Explicit template avoids the system's light hover/selected surface on the dark overlay.
            var border = new FrameworkElementFactory(typeof(Border)); border.SetValue(Border.CornerRadiusProperty, new CornerRadius(3));
            border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = RelativeSource.TemplatedParent });
            var content = new FrameworkElementFactory(typeof(ContentPresenter)); content.SetValue(FrameworkElement.HorizontalAlignmentProperty,HorizontalAlignment.Center);content.SetValue(FrameworkElement.VerticalAlignmentProperty,VerticalAlignment.Center);border.AppendChild(content);
            button.Template = new ControlTemplate(typeof(Button)) { VisualTree = border };
            button.Click += delegate { action(); }; return button;
        }
        internal void SetMedium(bool medium) { _placement.Medium = medium; ApplyMode(); Persist(); }
        internal void SetLocked(bool locked) { if (locked) EndMove(); _placement.Locked = locked; ApplyLock(); Persist(); }
        private void ApplyMode()
        {
            _applyingMode = true;
            try {
                _frame.Width = Medium ? 420 : 360; Width = (Medium ? 420 : 360) * _effectiveScale; _chart.Visibility = Medium ? Visibility.Visible : Visibility.Collapsed;
                Brush inactive=new SolidColorBrush(Color.FromRgb(35,39,41)),active=new SolidColorBrush(Color.FromRgb(255,128,0));
                _small.Background = Medium ? inactive : active; _medium.Background = Medium ? active : inactive;
                _small.Foreground=Medium?Brushes.White:Brushes.Black;_medium.Foreground=Medium?Brushes.Black:Brushes.White;
                _small.FontWeight = Medium ? FontWeights.Normal : FontWeights.Bold; _medium.FontWeight = Medium ? FontWeights.Bold : FontWeights.Normal;
                UpdateLayout(); Place(); Draw(); SyncControls();
            } finally { _applyingMode = false; }
        }
        private void ApplyLock()
        {
            _move.Content = UiLanguage.Text(Locked ? "Mover" : "Travar"); Cursor = _drag.Cursor = Locked ? Cursors.Arrow : Cursors.SizeAll;
            _move.Background=Locked?new SolidColorBrush(Color.FromRgb(35,39,41)):new SolidColorBrush(Color.FromRgb(255,128,0));_move.Foreground=Locked?Brushes.White:Brushes.Black;
            _move.ToolTip=Locked?"Posição travada. Use Mover para arrastar.":"Movimento livre. Use Travar para fixar a posição.";
            if (_handle != IntPtr.Zero) BenchmarkOverlayDesktop.InputStyle(_handle, Locked);
            UpdateLayout(); SyncControls();
        }
        private void Persist()
        {
            if(_editing)return;
            try { _placement.Save(_settingsPath); _savingFailed = false; }
            catch (Exception ex) { _savingFailed = true; _log(ex.Message); }
            RefreshStatus();
        }
        private void RememberPosition()
        {
            if (_handle == IntPtr.Zero) return;
            try {
                BenchmarkGameWindow.Bounds bounds = BenchmarkOverlayDesktop.Rect(_handle);
                int width = bounds.Right - bounds.Left, height = bounds.Bottom - bounds.Top;
                BenchmarkOverlayPosition position = BenchmarkOverlayGeometry.FinishMove(_monitors(), bounds.Left, bounds.Top, width, height);
                MoveTo(position.Left, position.Top);
                BenchmarkOverlayGeometry.Remember(_placement, position, width, height); Persist();
            } catch (Exception ex) { GeometryFailed(ex); }
        }
        private void MoveTo(int x, int y)
        {
            if (_handle == IntPtr.Zero) return;
            BenchmarkOverlayDesktop.Move(_handle, x, y, 0, 0, false); SyncControls();
        }
        internal void BeginMove(Point screen)
        {
            if (Locked || _handle == IntPtr.Zero) return;
            _dragBounds = BenchmarkOverlayDesktop.Rect(_handle); _dragStart = screen; _moveTimer.Start();
        }
        internal void ContinueMove(Point screen)
        {
            if (Locked || !_dragStart.HasValue) return;
            MoveTo(_dragBounds.Left + (int)(screen.X - _dragStart.Value.X), _dragBounds.Top + (int)(screen.Y - _dragStart.Value.Y));
        }
        internal void EndMove() { _moveTimer.Stop(); if (_dragStart.HasValue) { _dragStart = null; RememberPosition(); } }
        internal void Place()
        {
            if (_closed || _placing || _handle == IntPtr.Zero || _dragStart.HasValue) return;
            _placing = true;
            try {
                BenchmarkGameWindow.Bounds bounds = BenchmarkOverlayDesktop.Rect(_handle);
                int width = bounds.Right - bounds.Left, height = bounds.Bottom - bounds.Top;
                BenchmarkOverlayMonitor[] monitors = _monitors();
                if (monitors == null || monitors.Length == 0) throw new IOException("Monitor topology unavailable.");
                BenchmarkGameWindow.Bounds home = monitors[0].Bounds;
                if (_placement.Schema == 1 && _game.Window != IntPtr.Zero) {
                    try { home = BenchmarkOverlayDesktop.Rect(_game.Window); } catch (IOException) { }
                }
                BenchmarkOverlayPosition position = BenchmarkOverlayGeometry.Restore(_placement, monitors, home, width, height);
                // Keep the configured scale, but fit its effective rendering when DPI or
                // monitor dimensions would otherwise hide the interactive controls.
                double fit = Math.Min(_placement.PanelScale, Math.Min(_effectiveScale * Math.Max(1,position.Monitor.Bounds.Right-position.Monitor.Bounds.Left-2) / width,
                    _effectiveScale * Math.Max(1,position.Monitor.Bounds.Bottom-position.Monitor.Bounds.Top-2) / height));
                if (Math.Abs(fit - _effectiveScale) > .01) {
                    _effectiveScale = Math.Max(.1, fit);
                    _frame.LayoutTransform = new ScaleTransform(_effectiveScale,_effectiveScale);
                    ((FrameworkElement)_controlsWindow.Content).LayoutTransform = new ScaleTransform(_effectiveScale,_effectiveScale);
                    Width = (Medium ? 420 : 360) * _effectiveScale;
                    UpdateLayout();
                    width = Math.Max(1,(int)Math.Round(Width));
                    height = Math.Max(1,(int)Math.Round(((FrameworkElement)Content).DesiredSize.Height));
                    var transform = PresentationSource.FromVisual(this);
                    if (transform != null && transform.CompositionTarget != null) { width = (int)Math.Ceiling(Width * transform.CompositionTarget.TransformToDevice.M11); height = (int)Math.Ceiling(((FrameworkElement)Content).DesiredSize.Height * transform.CompositionTarget.TransformToDevice.M22); }
                    BenchmarkOverlayDesktop.Move(_handle,bounds.Left,bounds.Top,width,height,true);
                    position = BenchmarkOverlayGeometry.Restore(_placement,monitors,home,width,height);
                }
                bool changed = _placement.Schema != 2 || _placement.MonitorId != position.Monitor.Id || _placement.LastLeft != position.Left || _placement.LastTop != position.Top;
                if (bounds.Left != position.Left || bounds.Top != position.Top) MoveTo(position.Left, position.Top);
                BenchmarkOverlayGeometry.Remember(_placement, position, width, height);
                _geometryError = null;
                RefreshStatus();
                if (changed && !_applyingMode) Persist();
                SyncControls();
            } catch (Exception ex) { GeometryFailed(ex); }
            finally { _placing = false; }
        }
        private void GeometryFailed(Exception error)
        {
            if (_geometryError != error.Message) _log(error.Message);
            _geometryError = error.Message; RefreshStatus();
        }
        private void RefreshStatus()
        {
            _status.Text = UiLanguage.Text(_geometryError != null ? "Monitores indisponíveis. Posição preservada." : _savingFailed ? "Não foi possível salvar a posição." : _liveState);
            _status.Visibility = Visibility.Visible;
        }
        internal void Update(BenchmarkLiveSnapshot snapshot)
        {
            if (snapshot != null && (!ValidSeries(snapshot.Times) || new double[] { snapshot.Fps, snapshot.Low, snapshot.Mean, snapshot.P99 }.Any(v => Double.IsNaN(v) || Double.IsInfinity(v) || v <= 0))) snapshot = null;
            _snapshot = snapshot;
            double[] numbers = snapshot == null ? null : new double[] { _placement.CurrentFps ? snapshot.CurrentFps : snapshot.Fps, snapshot.Low, snapshot.Mean, snapshot.P99 };
            for (int i = 0; i < 4; i++) _values[i].Text = numbers == null || numbers[i] <= 0 ? "—" : numbers[i].ToString(i < 2 ? "F1" : "F2", CultureInfo.CurrentCulture);
            RefreshStatus();
            Draw();
        }
        private void Draw()
        {
            _chart.Children.Clear();
            if (!Medium || _chart.ActualWidth < 4) return;
            double max = 1; if (_snapshot != null) max = Math.Max(max, _snapshot.Times.Max()); if (_reference != null) max = Math.Max(max, _reference.Max());
            TextBlock label = new TextBlock { Text = "FrameTime · " + max.ToString("F1", CultureInfo.CurrentCulture) + " ms", FontSize = 10, Foreground = Brushes.LightGray };
            _chart.Children.Add(label);
            Brush current = new SolidColorBrush(Color.FromRgb(255, 128, 0)), reference = new SolidColorBrush(Color.FromRgb(83, 174, 255));
            Legend(2, UiLanguage.Text("Atual"), current, false);
            if (_reference != null) { Legend(80, UiLanguage.Text("Referência"), reference, true); Series(_reference, max, reference, true); }
            if (_snapshot != null) Series(_snapshot.Times, max, current, false);
        }
        private void Legend(double left, string text, Brush brush, bool reference)
        {
            Line sample = new Line { X1 = left, X2 = left + 14, Y1 = 23, Y2 = 23, Stroke = brush, StrokeThickness = 1.5, IsHitTestVisible = false };
            if (reference) sample.StrokeDashArray = new DoubleCollection { 4, 3 };
            _chart.Children.Add(sample);
            TextBlock label = new TextBlock { Text = text, Foreground = Brushes.LightGray, FontSize = 9, IsHitTestVisible = false };
            Canvas.SetLeft(label, left + 18); Canvas.SetTop(label, 16); _chart.Children.Add(label);
        }
        private void Series(double[] samples, double maximum, Brush brush, bool reference)
        {
            Polyline line = new Polyline { Stroke = brush, StrokeThickness = 1.3, IsHitTestVisible = false, Tag = reference ? "OverlayReference" : "OverlayCurrent" };
            if (reference) line.StrokeDashArray = new DoubleCollection { 4, 3 };
            for (int i = 0; i < samples.Length; i++) line.Points.Add(new Point(2 + i * (_chart.ActualWidth - 4) / (samples.Length - 1), 34 + (1 - samples[i] / maximum) * Math.Max(1, _chart.ActualHeight - 38)));
            _chart.Children.Add(line);
        }
    }
}
