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
        public BenchmarkOverlayPlacement() { PanelScale = 1; BackgroundOpacity = .93; }
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
            return (Schema == 1 || (Schema == 2 && !String.IsNullOrWhiteSpace(MonitorId) && MonitorId.Length <= 128 && Math.Abs((long)LastLeft) <= 1000000 && Math.Abs((long)LastTop) <= 1000000))
                && X == Clamp(X) && Y == Clamp(Y) && PanelScale >= .75 && PanelScale <= 1.75 && BackgroundOpacity >= .35 && BackgroundOpacity <= 1;
        }
    }

    internal sealed class BenchmarkOverlay : Window
    {
        private readonly string _settingsPath;
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
            _game = game; _log = log; _settingsPath = BenchmarkOverlayPlacement.PathFor(root, game.Identity);
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
            string[] labels = { "FPS médio\nFPS", "Quedas de fluidez\n1% low · FPS", "Tempo por quadro\nmédia · ms", "Picos de demora\nP99 · ms" };
            for (int i = 0; i < 4; i++) {
                StackPanel cell = new StackPanel { Margin = new Thickness(0, 0, 6, 0) }; Grid.SetColumn(cell, i);
                TextBlock caption = new TextBlock { Text = UiLanguage.Text(labels[i]), FontSize = 9, Foreground = Brushes.LightGray };
                if (i == 0) _fpsLabel = caption;
                cell.Children.Add(caption);
                _values[i] = new TextBlock { Text = "—", FontSize = 20, Foreground = i == 0 ? Brushes.DarkOrange : Brushes.White };
                cell.Children.Add(_values[i]); metrics.Children.Add(cell);
            }
            panel.Children.Add(metrics);
            _sensors = new TextBlock { Foreground = Brushes.LightGray, FontSize = 10, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 7, 0, 0) }; panel.Children.Add(_sensors);
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
        internal void SetSensors(string text) { _sensors.Text = text; }
        internal void ApplyPreferences(bool save = true)
        {
            _fpsLabel.Text = _placement.CurrentFps ? "FPS atual\nFPS · 1 s" : "FPS médio\nFPS · 5 s";
            _fpsMode.Content = _placement.CurrentFps ? "FPS: atual" : "FPS: médio";
            _sensors.Visibility = _placement.Sensors ? Visibility.Visible : Visibility.Collapsed;
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
                foreach (DependencyProperty property in new DependencyProperty[] { ContentControl.ContentProperty, Control.BackgroundProperty, Control.ForegroundProperty, Control.FontWeightProperty })
                    proxy.SetBinding(property, new Binding { Source = original, Path = new PropertyPath(property) });
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
            Button button = new Button { Content = UiLanguage.Text(label), Focusable = false, Padding = new Thickness(9, 3, 9, 3), Margin = new Thickness(0, 0, 5, 0), Foreground = Brushes.White, Background = new SolidColorBrush(Color.FromRgb(35, 39, 41)), BorderBrush = Brushes.DimGray };
            // Explicit template avoids the system's light hover/selected surface on the dark overlay.
            var border = new FrameworkElementFactory(typeof(Border)); border.SetValue(Border.CornerRadiusProperty, new CornerRadius(3));
            border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = RelativeSource.TemplatedParent });
            var content = new FrameworkElementFactory(typeof(ContentPresenter)); content.SetValue(FrameworkElement.MarginProperty, new Thickness(6, 4, 6, 4)); border.AppendChild(content);
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
                _small.Background = Medium ? Brushes.DimGray : Brushes.DarkOrange; _medium.Background = Medium ? Brushes.DarkOrange : Brushes.DimGray;
                _small.FontWeight = Medium ? FontWeights.Normal : FontWeights.Bold; _medium.FontWeight = Medium ? FontWeights.Bold : FontWeights.Normal;
                UpdateLayout(); Place(); Draw(); SyncControls();
            } finally { _applyingMode = false; }
        }
        private void ApplyLock()
        {
            _move.Content = UiLanguage.Text(Locked ? "Mover" : "Travar"); Cursor = _drag.Cursor = Locked ? Cursors.Arrow : Cursors.SizeAll;
            if (_handle != IntPtr.Zero) BenchmarkOverlayDesktop.InputStyle(_handle, Locked);
            UpdateLayout(); SyncControls();
        }
        private void Persist()
        {
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
