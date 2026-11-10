using System;
using System.Collections.Generic;
using System.ComponentModel;
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
using System.Windows.Automation;
using Microsoft.Win32;
using Path = System.IO.Path;

namespace WinSlim.NativeUI
{
    // Per-overlay resources keep a game's draft independent of the main window.
    internal sealed class BenchmarkOverlayPalette
    {
        private sealed class PaletteColor : INotifyPropertyChanged
        {
            public Color Value { get; private set; }
            public event PropertyChangedEventHandler PropertyChanged;
            internal void Set(Color value){Value=value;var changed=PropertyChanged;if(changed!=null)changed(this,new PropertyChangedEventArgs("Value"));}
        }
        private readonly Dictionary<string, SolidColorBrush> _brushes = new Dictionary<string, SolidColorBrush>();
        private readonly Dictionary<string, PaletteColor> _colors = new Dictionary<string, PaletteColor>();
        internal bool Light { get; private set; }
        internal static bool ValidMode(string mode) { return mode == "auto" || mode == "light" || mode == "dark"; }
        internal static bool SystemLight() { return Convert.ToInt32(Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1)) != 0; }
        internal static string SavedAppMode(string root)
        {
            try {
                string path=Path.Combine(root,"config","WinSlim-theme.json");
                if(!File.Exists(path)||new FileInfo(path).Length>4096)return "auto";
                var data=new JavaScriptSerializer().DeserializeObject(File.ReadAllText(path,Encoding.UTF8)) as Dictionary<string,object>;
                object value;string mode=data!=null&&data.TryGetValue("theme",out value)?Convert.ToString(value):"auto";
                return ValidMode(mode)?mode:"auto";
            } catch { return "auto"; }
        }
        internal Color Color(string hex)
        {
            string value=hex;
            if(Light) {
                switch(hex.ToUpperInvariant()) {
                    case "#080808": value="#FAFBFD";break;
                    case "#0C0F10": case "#161B1F": value="#FFFFFF";break;
                    case "#111619": case "#171C20": case "#16191A": value="#EDF1F6";break;
                    case "#1D2327": case "#232729": value="#E3E9F1";break;
                    case "#323A40": value="#DAE3EF";break;
                    case "#30363B": case "#424B52": value="#8795A8";break;
                    case "#535E66": case "#69757E": value="#5B6C82";break;
                    case "#F5F5F5": case "#FFFFFF": case "#E5E7EB": value="#17212F";break;
                    case "#A9AFB8": case "#D4D8DC": case "#D3D3D3": value="#45556B";break;
                    case "#FFAA4D": case "#FFB25C": value="#854000";break;
                    case "#FF8C00": value="#A54700";break;
                    case "#87CEFA": value="#1466A0";break;
                }
            }
            return (Color)ColorConverter.ConvertFromString(value);
        }
        internal Brush Brush(string hex)
        {
            SolidColorBrush brush;
            if(!_brushes.TryGetValue(hex,out brush)){
                var color=new PaletteColor();color.Set(Color(hex));brush=new SolidColorBrush();
                BindingOperations.SetBinding(brush,SolidColorBrush.ColorProperty,new Binding("Value"){Source=color});
                _brushes.Add(hex,brush);_colors.Add(hex,color);
            }
            return brush;
        }
        internal void Apply(bool light) { Light=light;foreach(var entry in _colors)entry.Value.Set(Color(entry.Key)); }
    }
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
        public bool ShowReference { get; set; }
        public string[] Hotkeys { get; set; }
        public string ThemeMode { get; set; }
        public const string GeneralIdentity = "winslim:default-overlay";
        public BenchmarkOverlayPlacement() { PanelScale = 1; BackgroundOpacity = .93; ShowCpu = ShowGpu = ShowVram = ShowRam = ShowReference = true; }
        internal BenchmarkOverlayPlacement Clone() { var result=(BenchmarkOverlayPlacement)MemberwiseClone(); if(Hotkeys!=null)result.Hotkeys=(string[])Hotkeys.Clone(); return result; }
        internal void CopyFrom(BenchmarkOverlayPlacement other)
        {
            Schema=other.Schema; X=other.X; Y=other.Y; Medium=other.Medium; Locked=other.Locked; MonitorId=other.MonitorId; LastLeft=other.LastLeft; LastTop=other.LastTop;
            PanelScale=other.PanelScale; BackgroundOpacity=other.BackgroundOpacity; CurrentFps=other.CurrentFps; Sensors=other.Sensors;
            ShowCpu=other.ShowCpu; ShowGpu=other.ShowGpu; ShowVram=other.ShowVram; ShowRam=other.ShowRam; Hotkeys=other.Hotkeys==null?null:(string[])other.Hotkeys.Clone();
            ShowReference=other.ShowReference;
            ThemeMode=other.ThemeMode;
        }
        internal void CopyAppearance(BenchmarkOverlayPlacement other)
        {
            var position=Clone();CopyFrom(other);Schema=position.Schema;X=position.X;Y=position.Y;Locked=position.Locked;
            MonitorId=position.MonitorId;LastLeft=position.LastLeft;LastTop=position.LastTop;
        }
        internal static BenchmarkOverlayPlacement LoadFor(string root,string identity)
        {
            string path=PathFor(root,identity);
            if(File.Exists(path)||identity==GeneralIdentity)return Load(path);
            var value=Load(PathFor(root,GeneralIdentity));value.Schema=1;value.X=.02;value.Y=.03;value.Locked=true;value.MonitorId=null;value.LastLeft=value.LastTop=0;return value;
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
            if(ThemeMode!=null&&!BenchmarkOverlayPalette.ValidMode(ThemeMode))return false;
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
        private readonly BenchmarkOverlayPalette _palette = new BenchmarkOverlayPalette();
        private readonly Func<bool> _systemTheme;
        private bool _themeReadFailed;
        internal event Action ThemeChanged;
        internal event Action<BenchmarkOverlay> ThemePreferenceChanged;
        internal bool ThemeIsLight { get { return _palette.Light; } }
        internal string ThemeMode { get { return _placement.ThemeMode; } }
        internal Brush ThemeBrush(string hex) { return _palette.Brush(hex); }
        private readonly TextBlock[] _values = new TextBlock[4];
        private readonly TextBlock _status;
        private readonly Canvas _chart;
        private readonly Button _small, _medium, _move, _referenceToggle, _themeToggle;
        private readonly Border _drag;
        private readonly StackPanel _controls;
        private readonly Window _controlsWindow;
        private readonly Func<BenchmarkOverlayMonitor[]> _monitors;
        private double[] _reference;
        private readonly TextBlock _fpsLabel;
        private readonly StackPanel _sensors;
        private readonly Button _fpsMode;
        private readonly Border _frame;
        private string _liveState = "Coletando amostras";
        private double _effectiveScale = 1;
        private bool _editing;
        private string _sensorReadings = "CPU: Indisponível\nGPU: Indisponível\nVRAM: Indisponível\nRAM: Indisponível";
        internal string GameName { get { return _game.Name; } }
        internal string GameIdentity { get { return _game.Identity; } }
        internal bool General { get { return GameIdentity==BenchmarkOverlayPlacement.GeneralIdentity; } }
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
        internal BenchmarkOverlay(string root, BenchmarkGame game, Action<string> log, double[] reference = null, Func<BenchmarkOverlayMonitor[]> monitors = null, Func<bool> systemTheme = null)
        {
            _root = root; _game = game; _log = log; _settingsPath = BenchmarkOverlayPlacement.PathFor(root, game.Identity);
            _systemTheme=systemTheme??BenchmarkOverlayPalette.SystemLight;
            _monitors = monitors ?? BenchmarkOverlayDesktop.Monitors;
            _reference = ValidSeries(reference) ? (double[])reference.Clone() : null;
            try { _placement = BenchmarkOverlayPlacement.LoadFor(root,game.Identity); }
            catch (Exception ex) { _log(ex.Message); _placement = new BenchmarkOverlayPlacement { Schema = 1, X = .02, Y = .03, Locked = true }; }
            if(_placement.ThemeMode==null)_placement.ThemeMode=BenchmarkOverlayPalette.SavedAppMode(root);
            _palette.Apply(ReadTheme(true));
            Title = "Win-Slim · " + game.Name;
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; ShowActivated = false;
            Topmost = true; Background = Brushes.Transparent; AllowsTransparency = true; SizeToContent = SizeToContent.Height;
            Foreground = ThemeBrush("#FFFFFF"); FontFamily = new FontFamily("Segoe UI"); FontSize = 11;
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
            _referenceToggle=CreateControl("Ref.",delegate{SetReferenceVisible(!_placement.ShowReference);});_referenceToggle.Name="OverlayReferenceToggle";
            _themeToggle=CreateControl("☀",delegate{SetThemeMode(ThemeIsLight?"dark":"light");});_themeToggle.Name="OverlayTheme";_themeToggle.Width=30;_themeToggle.FontSize=16;
            _controls.Children.Add(_small); _controls.Children.Add(new TextBlock { Text = "|", Margin = new Thickness(0, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center }); _controls.Children.Add(_medium); _controls.Children.Add(_move); panel.Children.Add(_controls);
            _controls.Children.Add(_fpsMode);
            _controls.Children.Add(_referenceToggle);
            _controls.Children.Add(_themeToggle);
            Grid metrics = new Grid { ToolTip = "FPS de apresentação. Janela móvel de até 5 s e 4096 quadros. FPS atual: até 1 s. 1% low: FPS dos intervalos mais lentos (1%). P99: 99% dos intervalos ficam abaixo deste tempo. Benchmark usa a captura completa." };
            for (int i = 0; i < 4; i++) metrics.ColumnDefinitions.Add(new ColumnDefinition());
            string[] labels = { "FPS médio", "1% low", "Quadro médio", "P99" };
            string[] units = { "FPS", "FPS", "ms", "ms" };
            for (int i = 0; i < 4; i++) {
                StackPanel cell = new StackPanel { Margin = new Thickness(0, 0, 6, 0) }; Grid.SetColumn(cell, i);
                TextBlock caption = new TextBlock { Text = UiLanguage.Text(labels[i]), FontSize = 10, Height = 20, Foreground = ThemeBrush("#D3D3D3") };
                if (i == 0) _fpsLabel = caption;
                cell.Children.Add(caption);
                _values[i] = new TextBlock { Text = "—", FontSize = 26, FontWeight=FontWeights.SemiBold, Foreground = ThemeBrush(i==0?"#FF8C00":"#FFFFFF") };
                System.Windows.Documents.Typography.SetNumeralAlignment(_values[i],FontNumeralAlignment.Tabular);
                cell.Children.Add(new Viewbox {Child=_values[i], Height=34, Stretch=Stretch.Uniform, StretchDirection=StretchDirection.DownOnly, HorizontalAlignment=HorizontalAlignment.Left});
                cell.Children.Add(new TextBlock {Text=units[i],FontSize=10,Foreground=ThemeBrush("#D3D3D3"),Margin=new Thickness(0,2,0,0)}); metrics.Children.Add(cell);
            }
            panel.Children.Add(metrics);
            _sensors = new StackPanel { Margin = new Thickness(0, 8, 0, 0), ToolTip="Uso e VRAM do computador/adaptador, não exclusivos do jogo. Temperatura indisponível: não há leitura confiável neste momento." }; panel.Children.Add(_sensors);
            _chart = new Canvas { Height = 110, Margin = new Thickness(0, 7, 0, 0), ClipToBounds = true, Background = ThemeBrush("#16191A"), ToolTip = "Posição relativa das amostras; não representa o mesmo instante nas duas capturas. Acima de 360 amostras, mostra o máximo de cada faixa, preservando picos. Estatísticas usam todos os intervalos." };
            _chart.SizeChanged += delegate { Draw(); };
            panel.Children.Add(_chart);
            _status = new TextBlock { Foreground = ThemeBrush("#D3D3D3"), FontSize = 10, Margin = new Thickness(0, 6, 0, 0), TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed }; panel.Children.Add(_status);
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
            Closed += delegate { _closed = true; SystemEvents.UserPreferenceChanged-=SystemThemeChanged; _moveTimer.Stop(); _controlsWindow.Close(); };
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
            SystemEvents.UserPreferenceChanged+=SystemThemeChanged;
        }
        private bool ReadTheme(bool fallback)
        {
            if(ThemeMode=="light")return true;if(ThemeMode=="dark")return false;
            try { bool light=_systemTheme();_themeReadFailed=false;return light; }
            catch(Exception ex){if(!_themeReadFailed){_log("Tema do Windows indisponível: "+ex.Message);_themeReadFailed=true;}return fallback;}
        }
        internal void RefreshSystemTheme()
        {
            if(_closed)return;
            _palette.Apply(ReadTheme(_palette.Light));
            Color background=_palette.Color("#0C0F10");background.A=(byte)Math.Round(_placement.BackgroundOpacity*255);_frame.Background=new SolidColorBrush(background);
            Foreground=ThemeBrush("#FFFFFF");_status.Foreground=ThemeBrush("#D3D3D3");
            _small.Background=Medium?ThemeBrush("#232729"):Brushes.DarkOrange;_small.Foreground=Medium?ThemeBrush("#FFFFFF"):Brushes.Black;
            _medium.Background=Medium?Brushes.DarkOrange:ThemeBrush("#232729");_medium.Foreground=Medium?Brushes.Black:ThemeBrush("#FFFFFF");
            _move.Background=Locked?ThemeBrush("#232729"):Brushes.DarkOrange;_move.Foreground=Locked?ThemeBrush("#FFFFFF"):Brushes.Black;
            _referenceToggle.Foreground=ThemeBrush(_placement.ShowReference?"#87CEFA":"#D3D3D3");
            _themeToggle.Content=ThemeIsLight?"☀":"☾";
            string description="Tema "+(ThemeIsLight?"claro":"escuro")+(ThemeMode=="auto"?" (automático)":"")+". Alternar para "+(ThemeIsLight?"escuro":"claro")+".";
            _themeToggle.ToolTip=description;AutomationProperties.SetName(_themeToggle,description);AutomationProperties.SetHelpText(_themeToggle,description);
            Draw();var changed=ThemeChanged;if(changed!=null)changed();
        }
        internal bool SetThemeMode(string mode)
        {
            if(!BenchmarkOverlayPalette.ValidMode(mode))throw new ArgumentException("Tema inválido.");
            if(mode==ThemeMode)return true;
            string previous=ThemeMode;_placement.ThemeMode=mode;
            if(!_editing){try{_placement.Save(_settingsPath);_savingFailed=false;}catch(Exception ex){_placement.ThemeMode=previous;_savingFailed=true;_log(ex.Message);RefreshStatus();return false;}}
            RefreshSystemTheme();RefreshStatus();var changed=ThemePreferenceChanged;if(changed!=null)changed(this);return true;
        }
        private void SystemThemeChanged(object sender,UserPreferenceChangedEventArgs args)
        {
            if(_closed||ThemeMode!="auto"||Dispatcher.HasShutdownStarted)return;
            Dispatcher.BeginInvoke(new Action(delegate{if(!_closed&&ThemeMode=="auto")RefreshSystemTheme();}));
        }
        internal void SetReference(double[] reference) { _reference = ValidSeries(reference) ? (double[])reference.Clone() : null; ApplyReferenceControl(); Draw(); }
        internal void SetReferenceVisible(bool visible){_placement.ShowReference=visible;ApplyReferenceControl();Draw();Persist();}
        private void ApplyReferenceControl(){_referenceToggle.Visibility=Medium&&_reference!=null?Visibility.Visible:Visibility.Collapsed;_referenceToggle.Content=_placement.ShowReference?"Ref. ✓":"Ref. —";_referenceToggle.ToolTip=_placement.ShowReference?"Ocultar referência sem apagá-la":"Mostrar referência · comparação por posição relativa";_referenceToggle.Foreground=ThemeBrush(_placement.ShowReference?"#87CEFA":"#D3D3D3");SyncControls();}
        internal void SetState(string state) { _liveState = state; RefreshStatus(); }
        internal string StatusText { get { return _status.Text; } }
        internal void SetSensors(string text) { _sensorReadings=text; RenderSensors(); }
        private void RenderSensors()
        {
            bool[] enabled={_placement.ShowCpu,_placement.ShowGpu,_placement.ShowVram,_placement.ShowRam};string[] names={"CPU:","GPU:","VRAM", "RAM:"};
            _sensors.Children.Clear();
            foreach(string name in names.Where((name,i)=>enabled[i])){
                string line=(_sensorReadings??"").Split('\n').FirstOrDefault(value=>value.StartsWith(name,StringComparison.Ordinal))??name+" Indisponível";
                int separator=line.IndexOf(':');string text=separator<0?"Indisponível":line.Substring(separator+1).Trim();
                var row=new Grid {Margin=new Thickness(0,1,0,1)};row.ColumnDefinitions.Add(new ColumnDefinition {Width=new GridLength(84)});row.ColumnDefinitions.Add(new ColumnDefinition());
                row.Children.Add(new TextBlock {Text=name.StartsWith("VRAM")?"VRAM adapt.":name.TrimEnd(':'),FontSize=11,Foreground=ThemeBrush("#D3D3D3")});
                var reading=new TextBlock {Text=text,FontSize=11,Foreground=ThemeBrush("#FFFFFF"),TextWrapping=TextWrapping.Wrap};Grid.SetColumn(reading,1);row.Children.Add(reading);_sensors.Children.Add(row);
            }
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
        internal void CommitPreferencesEdit(bool save=true) { if(save)_placement.Save(_settingsPath); _savingFailed=false; _editing=false; RefreshStatus(); }
        internal void CancelPreferencesEdit(BenchmarkOverlayPlacement original) { _placement.CopyFrom(original); ApplyPreferences(false); ApplyLock(); _editing=false; }
        internal BenchmarkOverlay CreateIllustrativePreview()
        {
            var preview=new BenchmarkOverlay(_root,_game,_log,_reference==null?null:new double[]{18,22,19,25,20,23},_monitors,_systemTheme);
            preview.BeginPreferencesEdit(); preview.Preferences.CopyFrom(_placement);preview.ApplyPreferences(false);
            preview.Update(new BenchmarkLiveSnapshot {Fps=60,CurrentFps=64,Low=48,Mean=16.67,P99=24.8,Times=new double[]{16,17,15,18,16,24,17,16},UpdatedUtc=DateTime.UtcNow});
            preview.SetState("Prévia — valores ilustrativos");
            preview.SetSensors("CPU: 32% · 62 °C\nGPU: 76% · 68 °C\nVRAM do adaptador: 4,29 GB\nRAM: 54%");return preview;
        }
        internal FrameworkElement DetachPreviewContent() { var content=(FrameworkElement)Content; Content=null;content.IsHitTestVisible=false;return content; }
        internal void ApplyPreferences(bool save = true)
        {
            _fpsLabel.Text = UiLanguage.Text(_placement.CurrentFps ? "FPS atual" : "FPS médio");
            _fpsMode.Content = _placement.CurrentFps ? "FPS: atual" : "FPS: médio";
            _fpsMode.Foreground=Brushes.Black;_fpsMode.Background=Brushes.DarkOrange;_fpsMode.ToolTip="Clique para alternar FPS atual e médio. O rótulo indica a seleção ativa.";
            _sensors.Visibility = _placement.Sensors ? Visibility.Visible : Visibility.Collapsed;
            RenderSensors();
            RefreshSystemTheme();
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
            _placement.ThemeMode="auto";
            ApplyPreferences(); ApplyLock();
        }
        private IntPtr NoActivation(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled)
        {
            if((msg==0x1A||msg==0x31A)&&ThemeMode=="auto")RefreshSystemTheme();
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
                if (original == null) { panel.Children.Add(new TextBlock { Text = "|", Foreground = ThemeBrush("#D3D3D3"), FontSize = FontSize, Margin = element.Margin, VerticalAlignment = VerticalAlignment.Center }); continue; }
                Button proxy = new Button { Name = original.Name, Focusable = false, IsTabStop = false, Margin = original.Margin, Template = original.Template, FontSize = FontSize };
                foreach (DependencyProperty property in new DependencyProperty[] { ContentControl.ContentProperty, Control.BackgroundProperty, Control.ForegroundProperty, Control.FontWeightProperty, FrameworkElement.ToolTipProperty, UIElement.VisibilityProperty, AutomationProperties.NameProperty, AutomationProperties.HelpTextProperty })
                    proxy.SetBinding(property, new Binding { Source = original, Path = new PropertyPath(property) });
                proxy.Width=original.Width;proxy.Height=original.Height;proxy.FontSize=original.FontSize;
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
            double width = _controls.Children.OfType<FrameworkElement>().Where(e=>e.Visibility==Visibility.Visible).Sum(e => e.ActualWidth + e.Margin.Left + e.Margin.Right);
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
            Button button = new Button { Content = UiLanguage.Text(label), Focusable = false, FontSize=10, Height=28,Width=label=="Pequeno"?58:label=="Médio"?48:label=="Mover"?88:label=="Ref."?54:78, Padding = new Thickness(3), Margin = new Thickness(0, 0, 3, 0), Foreground = ThemeBrush("#FFFFFF"), Background = ThemeBrush("#232729"), BorderBrush = ThemeBrush("#69757E") };
            // Explicit template avoids the system's light hover/selected surface on the dark overlay.
            var border = new FrameworkElementFactory(typeof(Border)); border.SetValue(Border.CornerRadiusProperty, new CornerRadius(3));
            border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = RelativeSource.TemplatedParent });
            border.SetBinding(Border.BorderBrushProperty,new Binding("BorderBrush"){RelativeSource=RelativeSource.TemplatedParent});border.SetValue(Border.BorderThicknessProperty,new Thickness(1));
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
                Brush inactive=ThemeBrush("#232729"),active=new SolidColorBrush(Color.FromRgb(255,128,0));
                _small.Background = Medium ? inactive : active; _medium.Background = Medium ? active : inactive;
                _small.Foreground=Medium?ThemeBrush("#FFFFFF"):Brushes.Black;_medium.Foreground=Medium?Brushes.Black:ThemeBrush("#FFFFFF");
                _small.FontWeight = Medium ? FontWeights.Normal : FontWeights.Bold; _medium.FontWeight = Medium ? FontWeights.Bold : FontWeights.Normal;
                ApplyReferenceControl();
                UpdateLayout(); Place(); Draw(); SyncControls();
            } finally { _applyingMode = false; }
        }
        private void ApplyLock()
        {
            _move.Content = Locked ? "\U0001F512 Travado" : "\U0001F513 Destravado"; Cursor = _drag.Cursor = Locked ? Cursors.Arrow : Cursors.SizeAll;
            _move.Background=Locked?ThemeBrush("#232729"):new SolidColorBrush(Color.FromRgb(255,128,0));_move.Foreground=Locked?ThemeBrush("#FFFFFF"):Brushes.Black;
            _move.ToolTip=Locked?"Travado. Clique para destravar e arrastar entre monitores.":"Destravado. Clique para travar e passar os cliques das métricas ao jogo.";
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
            _status.Text = UiLanguage.Text(_geometryError != null ? "Monitores indisponíveis. Posição preservada." : _savingFailed ? "Não foi possível salvar as preferências." : _liveState);
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
            double max = 1; if (_snapshot != null) max = Math.Max(max, _snapshot.Times.Max()); if (_reference != null&&_placement.ShowReference) max = Math.Max(max, _reference.Max());
            TextBlock label = new TextBlock { Text = "FrameTime · " + max.ToString("F1", CultureInfo.CurrentCulture) + " ms", FontSize = 10, Foreground = ThemeBrush("#D3D3D3") };
            _chart.Children.Add(label);
            for(int i=0;i<3;i++){double y=34+i*29;_chart.Children.Add(new Line {X1=2,X2=_chart.ActualWidth-2,Y1=y,Y2=y,Stroke=new SolidColorBrush(Color.FromArgb(45,180,190,200)),StrokeThickness=.5,IsHitTestVisible=false});}
            var domain=new TextBlock {Text="0–100% · posição relativa das amostras",FontSize=9,Foreground=ThemeBrush("#D3D3D3")};Canvas.SetTop(domain,96);Canvas.SetLeft(domain,2);_chart.Children.Add(domain);
            Brush current = new SolidColorBrush(Color.FromRgb(255, 128, 0)), reference = new SolidColorBrush(Color.FromRgb(83, 174, 255));
            Legend(2, UiLanguage.Text("Atual"), current, false);
            if (_reference != null&&_placement.ShowReference) { Legend(80, UiLanguage.Text("Referência"), reference, true); Series(_reference, max, reference, true); }
            if (_snapshot != null) Series(_snapshot.Times, max, current, false);
        }
        private void Legend(double left, string text, Brush brush, bool reference)
        {
            Line sample = new Line { X1 = left, X2 = left + 14, Y1 = 23, Y2 = 23, Stroke = brush, StrokeThickness = 1.5, IsHitTestVisible = false };
            if (reference) sample.StrokeDashArray = new DoubleCollection { 4, 3 };
            _chart.Children.Add(sample);
            TextBlock label = new TextBlock { Text = text, Foreground = ThemeBrush("#D3D3D3"), FontSize = 9, IsHitTestVisible = false };
            Canvas.SetLeft(label, left + 18); Canvas.SetTop(label, 16); _chart.Children.Add(label);
        }
        private void Series(double[] samples, double maximum, Brush brush, bool reference)
        {
            Polyline line = new Polyline { Stroke = brush, StrokeThickness = 1.3, IsHitTestVisible = false, Tag = reference ? "OverlayReference" : "OverlayCurrent" };
            if (reference) line.StrokeDashArray = new DoubleCollection { 4, 3 };
            for (int i = 0; i < samples.Length; i++) line.Points.Add(new Point(2 + i * (_chart.ActualWidth - 4) / (samples.Length - 1), 34 + (1 - samples[i] / maximum) * Math.Max(1, _chart.ActualHeight - 52)));
            // Preserve the approved orange/blue values and dashes, adding a contrast
            // edge on pale backgrounds without changing samples or the shared scale.
            if(ThemeIsLight){var edge=new Polyline {Points=new PointCollection(line.Points),Stroke=ThemeBrush("#FFFFFF"),StrokeThickness=2.8,IsHitTestVisible=false};if(reference)edge.StrokeDashArray=new DoubleCollection {4,3};_chart.Children.Add(edge);}
            _chart.Children.Add(line);
        }
    }
}
