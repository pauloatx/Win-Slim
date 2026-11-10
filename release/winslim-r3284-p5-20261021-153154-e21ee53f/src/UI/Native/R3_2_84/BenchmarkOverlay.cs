using System;
using System.Globalization;
using System.IO;
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

namespace WinSlim.NativeUI
{
    public sealed class BenchmarkOverlayPlacement
    {
        public int Schema { get; set; }
        public double X { get; set; }
        public double Y { get; set; }
        public bool Medium { get; set; }
        public bool Locked { get; set; }
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
            if (value == null || value.Schema != 1 || value.X != Clamp(value.X) || value.Y != Clamp(value.Y)) throw new InvalidDataException("Invalid overlay settings.");
            return value;
        }
        internal void Save(string path)
        {
            if (Schema != 1 || X != Clamp(X) || Y != Clamp(Y)) throw new InvalidDataException("Invalid overlay position.");
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path));
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp", backup = temporary + ".previous";
            try {
                File.WriteAllText(temporary, new JavaScriptSerializer().Serialize(this), new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temporary, path, backup); else File.Move(temporary, path);
            } finally { if (File.Exists(temporary)) File.Delete(temporary); if (File.Exists(backup)) File.Delete(backup); }
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
        private Point? _dragStart;
        private BenchmarkGameWindow.Bounds _dragBounds;
        private BenchmarkLiveSnapshot _snapshot;
        private IntPtr _handle;
        private bool _savingFailed;
        internal bool Medium { get { return _placement.Medium; } }
        internal bool Locked { get { return _placement.Locked; } }
        internal int MetricCount { get { return _values.Length; } }
        internal bool ChartVisible { get { return _chart.Visibility == Visibility.Visible; } }
        internal string MetricText(int index) { return _values[index].Text; }
        internal int ChartPointCount { get { return _chart.Children.Count > 1 ? ((Polyline)_chart.Children[1]).Points.Count : 0; } }
        internal BenchmarkOverlay(string root, BenchmarkGame game, Action<string> log)
        {
            _game = game; _log = log; _settingsPath = BenchmarkOverlayPlacement.PathFor(root, game.Identity);
            try { _placement = BenchmarkOverlayPlacement.Load(_settingsPath); }
            catch (Exception ex) { _log(ex.Message); _placement = new BenchmarkOverlayPlacement { Schema = 1, X = .02, Y = .03, Locked = true }; }
            Title = "Win-Slim · " + game.Name;
            WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; ShowActivated = false;
            Topmost = true; Background = Brushes.Transparent; AllowsTransparency = true; SizeToContent = SizeToContent.Height;
            Foreground = Brushes.White; FontFamily = new FontFamily("Segoe UI"); FontSize = 11;
            StackPanel panel = new StackPanel();
            Border frame = new Border { Background = new SolidColorBrush(Color.FromArgb(237, 12, 15, 16)), BorderBrush = new SolidColorBrush(Color.FromRgb(255, 128, 0)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(7), Padding = new Thickness(9), Child = panel };
            Content = frame;
            _drag = new Border { Background = Brushes.Transparent, Padding = new Thickness(0, 1, 0, 7), Child = new TextBlock { Text = "Win-Slim · " + game.Name, TextTrimming = TextTrimming.CharacterEllipsis } };
            panel.Children.Add(_drag);
            StackPanel controls = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 7) };
            _small = Control("Pequeno", delegate { SetMedium(false); }); _small.Name = "OverlaySmall";
            _medium = Control("Médio", delegate { SetMedium(true); }); _medium.Name = "OverlayMedium";
            _move = Control("Mover", delegate { SetLocked(!Locked); }); _move.Name = "OverlayMove";
            controls.Children.Add(_small); controls.Children.Add(_medium); controls.Children.Add(_move); panel.Children.Add(controls);
            Grid metrics = new Grid();
            for (int i = 0; i < 4; i++) metrics.ColumnDefinitions.Add(new ColumnDefinition());
            string[] labels = { "FPS médio", "1% low FPS", "FrameTime ms", "P99 ms" };
            for (int i = 0; i < 4; i++) {
                StackPanel cell = new StackPanel { Margin = new Thickness(0, 0, 6, 0) }; Grid.SetColumn(cell, i);
                cell.Children.Add(new TextBlock { Text = UiLanguage.Text(labels[i]), FontSize = 10, Foreground = Brushes.LightGray });
                _values[i] = new TextBlock { Text = "—", FontSize = 20, Foreground = i == 0 ? Brushes.DarkOrange : Brushes.White };
                cell.Children.Add(_values[i]); metrics.Children.Add(cell);
            }
            panel.Children.Add(metrics);
            _chart = new Canvas { Height = 86, Margin = new Thickness(0, 7, 0, 0), ClipToBounds = true, Background = new SolidColorBrush(Color.FromRgb(22, 25, 26)) };
            _chart.SizeChanged += delegate { Draw(); };
            panel.Children.Add(_chart);
            _status = new TextBlock { Text = UiLanguage.Text("Aguardando quadros…"), Foreground = Brushes.LightGray, FontSize = 10, Margin = new Thickness(0, 6, 0, 0), TextWrapping = TextWrapping.Wrap }; panel.Children.Add(_status);
            SourceInitialized += delegate {
                _handle = new WindowInteropHelper(this).Handle;
                HwndSource source = HwndSource.FromHwnd(_handle);
                source.AddHook(delegate(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled) {
                    if (msg == 0x21) { handled = true; return new IntPtr(3); } // MA_NOACTIVATE: controls never steal the game focus.
                    return IntPtr.Zero;
                });
            };
            SizeChanged += delegate { Place(); Draw(); };
            _drag.MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e) {
                if (Locked) return;
                BeginMove(PointToScreen(e.GetPosition(this))); _drag.CaptureMouse(); e.Handled = true;
            };
            _drag.MouseMove += delegate(object sender, MouseEventArgs e) {
                if (!_dragStart.HasValue || e.LeftButton != MouseButtonState.Pressed) return;
                ContinueMove(PointToScreen(e.GetPosition(this)));
            };
            _drag.MouseLeftButtonUp += delegate { EndMove(); _drag.ReleaseMouseCapture(); };
            _drag.LostMouseCapture += delegate { EndMove(); };
            ApplyMode(); ApplyLock();
        }
        private Button Control(string label, Action action)
        {
            Button button = new Button { Content = UiLanguage.Text(label), Focusable = false, Padding = new Thickness(9, 3, 9, 3), Margin = new Thickness(0, 0, 5, 0), Foreground = Brushes.White, Background = new SolidColorBrush(Color.FromRgb(35, 39, 41)), BorderBrush = Brushes.DimGray };
            // Explicit template avoids the system's light hover/selected surface on the dark overlay.
            var border = new FrameworkElementFactory(typeof(Border)); border.SetValue(Border.CornerRadiusProperty, new CornerRadius(3));
            border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background") { RelativeSource = RelativeSource.TemplatedParent });
            var content = new FrameworkElementFactory(typeof(ContentPresenter)); content.SetValue(FrameworkElement.MarginProperty, new Thickness(9, 4, 9, 4)); border.AppendChild(content);
            button.Template = new ControlTemplate(typeof(Button)) { VisualTree = border };
            button.Click += delegate { action(); }; return button;
        }
        internal void SetMedium(bool medium) { _placement.Medium = medium; ApplyMode(); Persist(); }
        internal void SetLocked(bool locked) { _placement.Locked = locked; ApplyLock(); Persist(); }
        private void ApplyMode()
        {
            Width = Medium ? 420 : 360; _chart.Visibility = Medium ? Visibility.Visible : Visibility.Collapsed;
            _small.Background = Medium ? Brushes.DimGray : Brushes.DarkOrange; _medium.Background = Medium ? Brushes.DarkOrange : Brushes.DimGray;
            UpdateLayout(); Place(); Draw();
        }
        private void ApplyLock() { _move.Content = UiLanguage.Text(Locked ? "Mover" : "Travar"); _drag.Cursor = Locked ? Cursors.Arrow : Cursors.SizeAll; }
        private void Persist()
        {
            try { _placement.Save(_settingsPath); _savingFailed = false; }
            catch (Exception ex) { _savingFailed = true; _log(ex.Message); _status.Text = UiLanguage.Text("Não foi possível salvar a posição."); }
        }
        private void RememberPosition()
        {
            BenchmarkGameWindow.Bounds bounds;
            if (_handle == IntPtr.Zero || !BenchmarkGameWindow.GetWindowRect(_handle, out bounds)) return;
            BenchmarkGameWindow.Bounds monitor = BenchmarkGameWindow.MonitorBounds(_handle);
            _placement.X = BenchmarkOverlayPlacement.Clamp((bounds.Left - monitor.Left) / (double)Math.Max(1, monitor.Right - monitor.Left - (bounds.Right - bounds.Left)));
            _placement.Y = BenchmarkOverlayPlacement.Clamp((bounds.Top - monitor.Top) / (double)Math.Max(1, monitor.Bottom - monitor.Top - (bounds.Bottom - bounds.Top)));
            Persist();
        }
        private void MoveTo(int x, int y)
        {
            BenchmarkGameWindow.Bounds bounds;
            if (_handle == IntPtr.Zero || !BenchmarkGameWindow.GetWindowRect(_handle, out bounds)) return;
            BenchmarkGameWindow.Bounds monitor = BenchmarkGameWindow.MonitorBounds(_game.Window);
            x = Math.Max(monitor.Left, Math.Min(x, monitor.Right - (bounds.Right - bounds.Left)));
            y = Math.Max(monitor.Top, Math.Min(y, monitor.Bottom - (bounds.Bottom - bounds.Top)));
            BenchmarkGameWindow.SetWindowPos(_handle, new IntPtr(-1), x, y, 0, 0, 0x11); // NOSIZE | NOACTIVATE
        }
        internal void BeginMove(Point screen)
        {
            if (Locked || _handle == IntPtr.Zero) return;
            if (BenchmarkGameWindow.GetWindowRect(_handle, out _dragBounds)) _dragStart = screen;
        }
        internal void ContinueMove(Point screen)
        {
            if (Locked || !_dragStart.HasValue) return;
            MoveTo(_dragBounds.Left + (int)(screen.X - _dragStart.Value.X), _dragBounds.Top + (int)(screen.Y - _dragStart.Value.Y));
        }
        internal void EndMove() { if (_dragStart.HasValue) { _dragStart = null; RememberPosition(); } }
        internal void Place()
        {
            if (_handle == IntPtr.Zero || _dragStart.HasValue) return;
            BenchmarkGameWindow.Bounds monitor = BenchmarkGameWindow.MonitorBounds(_game.Window), bounds;
            if (!BenchmarkGameWindow.GetWindowRect(_handle, out bounds)) return;
            MoveTo(monitor.Left + (int)(_placement.X * Math.Max(0, monitor.Right - monitor.Left - (bounds.Right - bounds.Left))),
                monitor.Top + (int)(_placement.Y * Math.Max(0, monitor.Bottom - monitor.Top - (bounds.Bottom - bounds.Top))));
        }
        internal void Update(BenchmarkLiveSnapshot snapshot)
        {
            _snapshot = snapshot;
            double[] numbers = snapshot == null ? null : new double[] { snapshot.Fps, snapshot.Low, snapshot.Mean, snapshot.P99 };
            for (int i = 0; i < 4; i++) _values[i].Text = numbers == null ? "—" : numbers[i].ToString(i < 2 ? "F1" : "F2", CultureInfo.CurrentCulture);
            if (!_savingFailed) _status.Text = UiLanguage.Text(snapshot == null ? "Aguardando quadros…" : "Ao vivo · últimos 240 quadros");
            Draw();
        }
        private void Draw()
        {
            _chart.Children.Clear();
            if (!Medium || _snapshot == null || _snapshot.Times.Length < 2 || _chart.ActualWidth <= 0) return;
            double max = 1; foreach (double time in _snapshot.Times) max = Math.Max(max, time);
            TextBlock label = new TextBlock { Text = "FrameTime · " + max.ToString("F1", CultureInfo.CurrentCulture) + " ms", FontSize = 10, Foreground = Brushes.LightGray };
            _chart.Children.Add(label);
            Polyline line = new Polyline { Stroke = Brushes.DarkOrange, StrokeThickness = 1.3 };
            for (int i = 0; i < _snapshot.Times.Length; i++) line.Points.Add(new Point(2 + i * (_chart.ActualWidth - 4) / (_snapshot.Times.Length - 1), 20 + (1 - _snapshot.Times[i] / max) * 62));
            _chart.Children.Add(line);
        }
    }
}
