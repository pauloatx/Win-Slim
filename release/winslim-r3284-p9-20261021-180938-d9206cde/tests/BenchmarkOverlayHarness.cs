using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace WinSlim.NativeUI
{
    internal static class BenchmarkOverlayHarness
    {
        [DllImport("user32.dll", EntryPoint="GetWindowLongW")] private static extern int WindowStyle(IntPtr window, int index);
        [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wp, IntPtr lp);
        private static void Check(bool success, string label) { if (!success) throw new Exception(label); Console.WriteLine("[OK] " + label); }
        private static void Reject(Action action, string label) { bool rejected = false; try { action(); } catch { rejected = true; } Check(rejected, label); }
        private static Button Button(DependencyObject root, string name)
        {
            Button found = root as Button; if (found != null && found.Name == name) return found;
            foreach (object child in LogicalTreeHelper.GetChildren(root)) { DependencyObject obj = child as DependencyObject; if (obj != null) { found = Button(obj, name); if (found != null) return found; } }
            return null;
        }
        private static void Layout(BenchmarkOverlay overlay)
        {
            FrameworkElement content = (FrameworkElement)overlay.Content;
            content.Measure(new Size(overlay.Width, Double.PositiveInfinity)); content.Arrange(new Rect(0, 0, overlay.Width, content.DesiredSize.Height)); content.UpdateLayout();
            // A hidden WPF HWND retains its default system height until Show. Use the actual
            // measured fixture size for native positioning, without opening a window on the user's game.
            IntPtr handle = new WindowInteropHelper(overlay).Handle;
            if (handle != IntPtr.Zero) {
                BenchmarkGameWindow.Bounds bounds = BenchmarkOverlayDesktop.Rect(handle);
                BenchmarkOverlayDesktop.Move(handle, bounds.Left, bounds.Top, (int)Math.Ceiling(overlay.Width), (int)Math.Ceiling(content.DesiredSize.Height), true);
                overlay.Place();
            }
        }
        private static void Preview(BenchmarkOverlay overlay, string directory, string name)
        {
            if (String.IsNullOrEmpty(directory)) return;
            Directory.CreateDirectory(directory);
            FrameworkElement content = (FrameworkElement)overlay.Content;
            RenderTargetBitmap bitmap = new RenderTargetBitmap((int)Math.Ceiling(content.ActualWidth), (int)Math.Ceiling(content.ActualHeight), 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(content); PngBitmapEncoder encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (FileStream file = File.Create(Path.Combine(directory, name + ".png"))) encoder.Save(file);
        }
        [STAThread]
        private static int Main(string[] args)
        {
            string temp = Path.Combine(Path.GetTempPath(), "WinSlim overlay teste " + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temp);
            try {
                new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
                if (args.Length > 0) UiLanguage.Initialize(args[0], true);
                BenchmarkGameWindow.Bounds monitor = new BenchmarkGameWindow.Bounds { Left = -1920, Top = 0, Right = 0, Bottom = 1080 };
                Check(BenchmarkGameWindow.CoversMonitor(monitor, monitor), "fullscreen on negative-origin secondary monitor");
                Check(!BenchmarkGameWindow.CoversMonitor(new BenchmarkGameWindow.Bounds { Left = -1920, Top = 0, Right = 0, Bottom = 1040 }, monitor), "maximized window with taskbar is not fullscreen");
                Check(!BenchmarkGameWindow.CoversMonitor(new BenchmarkGameWindow.Bounds { Left = -3840, Top = 0, Right = 0, Bottom = 1080 }, monitor), "spanning or unrelated bounds not accepted");
                using (Process process = Process.GetCurrentProcess()) {
                    BenchmarkGame current = BenchmarkGame.FromProcess(process, IntPtr.Zero);
                    Check(current.IsAlive(), "selected process identity includes start time"); current.Started--;
                    Check(!current.IsAlive(), "reused PID or changed process rejected");
                }
                string gameA = BenchmarkOverlayPlacement.PathFor(temp, @"C:\Games\A\Game.exe"), gameB = BenchmarkOverlayPlacement.PathFor(temp, @"C:\Games\B\Game.exe");
                Check(gameA != gameB && gameA == BenchmarkOverlayPlacement.PathFor(temp, @"c:\games\a\game.exe"), "position scoped by executable path, independent of PID and casing");
                BenchmarkOverlayPlacement original = new BenchmarkOverlayPlacement { Schema = 1, X = .7, Y = .8, Medium = true, Locked = true }; original.Save(gameA);
                Check(BenchmarkOverlayPlacement.Load(gameA).X == .7 && !File.Exists(gameB), "save and reopen preserve position without altering other game");
                byte[] settings = File.ReadAllBytes(gameA);
                using (FileStream locked = new FileStream(gameA, FileMode.Open, FileAccess.Read, FileShare.None)) Reject(delegate { new BenchmarkOverlayPlacement { Schema = 1, X = .1, Y = .2 }.Save(gameA); }, "locked profile fails save");
                Check(settings.SequenceEqual(File.ReadAllBytes(gameA)), "failed save preserves prior profile bytes");
                File.WriteAllText(gameB, "{\"Schema\":1,\"X\":2,\"Y\":0}"); Reject(delegate { BenchmarkOverlayPlacement.Load(gameB); }, "corrupt/outside position rejected");
                Check(BenchmarkOverlayPlacement.Clamp(Double.NaN) == 0 && BenchmarkOverlayPlacement.Clamp(-1) == 0 && BenchmarkOverlayPlacement.Clamp(9) == 1, "position clamp prevents inaccessible placement");
                BenchmarkGame game = new BenchmarkGame { Name = "Fixture.exe", Identity = @"C:\Games\Fixture.exe", Window = IntPtr.Zero };
                string profile = BenchmarkOverlayPlacement.PathFor(temp, game.Identity);
                double[] times = Enumerable.Range(0, 100).Select(i => i == 55 ? 40.0 : 16.0).ToArray();
                BenchmarkLiveSnapshot snapshot = new BenchmarkLiveSnapshot { Fps = 60, Low = 25, Mean = 16.4, P99 = 40, Times = times, UpdatedUtc = DateTime.UtcNow };
                IntPtr foreground = BenchmarkGameWindow.GetForegroundWindow();
                using (OverlayLifetime lifetime = new OverlayLifetime(new BenchmarkOverlay(temp, game, Console.WriteLine))) {
                    BenchmarkOverlay overlay = lifetime.Window;
                    new WindowInteropHelper(overlay).EnsureHandle(); Layout(overlay);
                    Check((WindowStyle(new WindowInteropHelper(overlay).Handle, -20) & 0x20) != 0, "locked metrics use native cross-process mouse passthrough");
                    Check(overlay.MetricCount == 4 && !overlay.Medium && !overlay.ChartVisible && overlay.Locked && !overlay.ShowActivated && !overlay.ShowInTaskbar, "small: four metrics, no chart, locked and no focus activation");
                    overlay.Update(snapshot); Layout(overlay); Preview(overlay, args.Length > 1 ? args[1] : null, "overlay-pequeno");
                    Check(overlay.MetricText(0) == 60.0.ToString("F1") && overlay.MetricText(3) == 40.0.ToString("F2"), "small displays all live numeric values");
                    Button(overlay, "OverlayMedium").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); Layout(overlay);
                    Check(overlay.Medium && overlay.ChartVisible && overlay.ChartPointCount == 100 && overlay.MetricText(0) == 60.0.ToString("F1"), "overlay selector switches immediately to medium, preserves metrics and plots FrameTime");
                    Preview(overlay, args.Length > 1 ? args[1] : null, "overlay-medio");
                    BenchmarkGameWindow.Bounds before, after; BenchmarkGameWindow.GetWindowRect(new WindowInteropHelper(overlay).Handle, out before);
                    overlay.BeginMove(new Point()); overlay.ContinueMove(new Point(50, 30)); overlay.EndMove(); BenchmarkGameWindow.GetWindowRect(new WindowInteropHelper(overlay).Handle, out after);
                    Check(before.Left == after.Left && before.Top == after.Top, "locked overlay rejects movement");
                    Button(overlay, "OverlayMove").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
                    overlay.BeginMove(new Point()); overlay.ContinueMove(new Point(50, 30)); overlay.EndMove(); BenchmarkGameWindow.GetWindowRect(new WindowInteropHelper(overlay).Handle, out after);
                    Check(!overlay.Locked && (before.Left != after.Left || before.Top != after.Top), "move control enables free movement");
                    Button(overlay, "OverlayMove").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
                    Check(overlay.Locked && BenchmarkOverlayPlacement.Load(profile).Locked, "lock control saves position and locks again");
                    overlay.Update(null); Check(overlay.MetricText(0) == "—" && overlay.ChartPointCount == 0, "unavailable preview clears metrics and graph without fake zero");
                    Button(overlay, "OverlaySmall").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); Layout(overlay);
                    Check(!overlay.Medium && !overlay.ChartVisible, "medium to small is immediate");
                }
                BenchmarkOverlayPlacement saved = BenchmarkOverlayPlacement.Load(profile);
                using (OverlayLifetime next = new OverlayLifetime(new BenchmarkOverlay(temp, game, Console.WriteLine))) Check(next.Window.Locked && !next.Window.Medium && BenchmarkOverlayPlacement.Load(profile).X == saved.X, "new overlay reloads same-game position, size and lock");
                Check(BenchmarkGameWindow.GetForegroundWindow() == foreground, "native overlay handle and interactions do not change foreground window");
                File.WriteAllText(profile, "invalid json");
                using (OverlayLifetime invalid = new OverlayLifetime(new BenchmarkOverlay(temp, game, delegate { }))) Check(invalid.Window.Locked, "unavailable/corrupt profile falls back safely");
                Check(settings.SequenceEqual(File.ReadAllBytes(gameA)), "overlay operations preserve unrelated saved game");
                TestComplement(temp, args.Length > 1 ? args[1] : null);
                return 0;
            } catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
            finally { Directory.Delete(temp, true); }
        }
        private static BenchmarkOverlayMonitor Screen(string id, int left, int top, int width, int height)
        {
            return new BenchmarkOverlayMonitor { Id = id, Bounds = new BenchmarkGameWindow.Bounds { Left = left, Top = top, Right = left + width, Bottom = top + height } };
        }
        private static bool Inside(BenchmarkGameWindow.Bounds window, BenchmarkGameWindow.Bounds monitor)
        {
            return window.Left >= monitor.Left && window.Top >= monitor.Top && window.Right <= monitor.Right && window.Bottom <= monitor.Bottom;
        }
        private static void TestComplement(string root, string previews)
        {
            TestSettings(root);
            string cleanup = Path.Combine(Path.GetTempPath(), "winslim-overlay-state-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(cleanup); File.WriteAllText(Path.Combine(cleanup, "sentinel"), "preserve");
            int attempts = 0;
            try {
                BenchmarkOverlay.CleanupStateFixture(cleanup, delegate(string path) { if (++attempts < 3) throw new IOException("transient directory busy"); Directory.Delete(path, true); }, delegate { });
                Check(attempts == 3 && !Directory.Exists(cleanup), "fixture cleanup retries transient Windows IO and really removes the directory");
                Directory.CreateDirectory(cleanup); File.WriteAllText(Path.Combine(cleanup, "sentinel"), "preserve"); attempts = 0;
                Reject(delegate { BenchmarkOverlay.CleanupStateFixture(cleanup, delegate { attempts++; throw new IOException("persistently busy"); }, delegate { }); }, "persistent fixture cleanup error still fails");
                Check(attempts == 10 && File.ReadAllText(Path.Combine(cleanup, "sentinel")) == "preserve", "failed cleanup is bounded and leaves evidence intact");
                bool touched = false;
                Reject(delegate { BenchmarkOverlay.CleanupStateFixture(root, delegate { touched = true; }, delegate { }); }, "cleanup rejects paths outside its own disposable fixture");
                Check(!touched && Directory.Exists(root), "cleanup never mutates an unrelated directory");
            } finally { BenchmarkOverlay.CleanupStateFixture(cleanup); }
            BenchmarkOverlayMonitor primary = Screen("primary", 0, 0, 1920, 1080), left = Screen("left", -1920, 0, 1920, 1080);
            BenchmarkOverlayMonitor[] topology = { primary, left };
            BenchmarkOverlayPlacement placement = new BenchmarkOverlayPlacement { Schema = 1, X = .7, Y = .8, Locked = true };
            BenchmarkOverlayPosition position = BenchmarkOverlayGeometry.Restore(placement, topology, primary.Bounds, 360, 130);
            Check(position.Monitor.Id == "primary" && position.Left >= 0, "legacy game-relative position migrates on the game's monitor");
            position = BenchmarkOverlayGeometry.FinishMove(topology, -1700, 120, 360, 130);
            BenchmarkOverlayGeometry.Remember(placement, position, 360, 130);
            Check(placement.Schema == 2 && placement.MonitorId == "left", "drag can select a monitor other than the game's monitor");
            position = BenchmarkOverlayGeometry.Restore(placement, topology, primary.Bounds, 360, 130);
            Check(position.Left == -1700 && position.Top == 120, "saved other-monitor position is restored exactly");
            position = BenchmarkOverlayGeometry.Restore(placement, new BenchmarkOverlayMonitor[] { primary, Screen("left", -2560, -300, 2560, 1440) }, primary.Bounds, 420, 250);
            Check(position.Left < 0 && position.Top >= -300 && position.Left + 420 <= 0 && position.Top + 250 <= 1140, "resolution/origin and size changes keep placement inside the saved monitor");
            position = BenchmarkOverlayGeometry.Restore(placement, new BenchmarkOverlayMonitor[] { primary }, primary.Bounds, 420, 250);
            Check(position.Left >= 0 && position.Left + 420 <= 1920, "disconnected monitor falls back visibly to a remaining monitor");
            string serialized = new System.Web.Script.Serialization.JavaScriptSerializer().Serialize(placement);
            Reject(delegate { BenchmarkOverlayGeometry.Restore(placement, new BenchmarkOverlayMonitor[0], primary.Bounds, 360, 130); }, "unavailable monitor topology is rejected");
            Reject(delegate { BenchmarkOverlayGeometry.FinishMove(new BenchmarkOverlayMonitor[] { primary, primary }, 0, 0, 360, 130); }, "duplicate monitor topology is rejected");
            Check(serialized == new System.Web.Script.Serialization.JavaScriptSerializer().Serialize(placement), "unavailable topology preserves the saved placement");
            BenchmarkResult baseline = new BenchmarkResult { Application = "Complement.exe", RequestedSeconds = 30, AverageFps = 50, FrameTimesMs = new double[] { 16, 32, 80 } };
            double[] originalReference = (double[])baseline.FrameTimesMs.Clone();
            double[] reference = BenchmarkOverlay.ReferenceForGame(baseline, "Complement.exe", 30);
            Check(reference != null && !Object.ReferenceEquals(reference, baseline.FrameTimesMs), "compatible reference copied without changing baseline");
            Check(BenchmarkOverlay.ReferenceForGame(baseline, "Other.exe", 30) == null && BenchmarkOverlay.ReferenceForGame(baseline, "Complement.exe", 60) == null, "incompatible application/duration is not drawn as a reference");
            BenchmarkGame game = new BenchmarkGame { Pid = 321, Name = "Complement.exe", Identity = @"C:\Games\Complement.exe" };
            BenchmarkLiveSnapshot live = new BenchmarkLiveSnapshot { Fps = 60, Low = 30, Mean = 16, P99 = 32, Times = new double[] { 16, 32, 16 }, UpdatedUtc = DateTime.UtcNow };
            IntPtr foreground = BenchmarkGameWindow.GetForegroundWindow();
            using (OverlayLifetime lifetime = new OverlayLifetime(new BenchmarkOverlay(root, game, delegate { }, reference, delegate { return topology; }))) {
                BenchmarkOverlay overlay = lifetime.Window;
                IntPtr body = new WindowInteropHelper(overlay).EnsureHandle(), controls = new WindowInteropHelper(overlay.ControlsWindow).EnsureHandle();
                Layout(overlay); overlay.Update(live);
                Check((WindowStyle(body, -20) & (0x80000 | 0x20 | 0x08000000)) == (0x80000 | 0x20 | 0x08000000) && (WindowStyle(controls, -20) & 0x20) == 0, "locked layered body passes native input through while controls stay interactive");
                Check(SendMessage(body, 0x21, IntPtr.Zero, IntPtr.Zero).ToInt32() == 3 && SendMessage(controls, 0x21, IntPtr.Zero, IntPtr.Zero).ToInt32() == 3, "both native windows decline mouse activation");
                overlay.Place();
                BenchmarkGameWindow.Bounds inputRect = BenchmarkOverlayDesktop.Rect(controls), bodyRect = BenchmarkOverlayDesktop.Rect(body);
                Check(Inside(inputRect, bodyRect) && inputRect.Bottom - inputRect.Top < 40 && inputRect.Right - inputRect.Left < bodyRect.Right - bodyRect.Left, "interactive native window covers only the compact controls, not the metrics");
                Button(overlay.ControlsWindow, "OverlayMedium").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); Layout(overlay);
                System.Windows.Shapes.Polyline current = overlay.ChartCurve(false), before = overlay.ChartCurve(true);
                Check(overlay.Medium && current != null && before != null && current.StrokeDashArray.Count == 0 && before.StrokeDashArray.Count > 0 && ((SolidColorBrush)current.Stroke).Color == Color.FromRgb(255,128,0) && ((SolidColorBrush)before.Stroke).Color == Color.FromRgb(83,174,255), "interactive medium selector draws orange solid current and blue dashed reference");
                Check(Math.Abs(current.Points[1].Y - before.Points[1].Y) < .001 && before.Points.All(p => p.X >= 0 && p.X <= 400 && p.Y >= 0 && p.Y <= 110), "live/reference graph shares a scale and keeps all points visible");
                Button(overlay.ControlsWindow.Content as DependencyObject,"OverlayReferenceToggle").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));Layout(overlay);
                Check(overlay.ChartCurve(true)==null&&overlay.ChartCurve(false)!=null&&overlay.ReferenceCount==3&&baseline.FrameTimesMs.SequenceEqual(originalReference),"reference control hides only the curve, preserving reference and current data");
                overlay.SetReferenceVisible(true);Layout(overlay);Check(overlay.ChartCurve(true)!=null&&Math.Abs(overlay.ChartCurve(false).Points[1].Y-overlay.ChartCurve(true).Points[1].Y)<.001,"show reference restores its shared vertical scale immediately");
                Preview(overlay, previews, "overlay-medio-referencia");
                for (int i = 0; i < 8; i++) {
                    Button(overlay.ControlsWindow, i % 2 == 0 ? "OverlaySmall" : "OverlayMedium").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent)); Layout(overlay);
                    Check(overlay.MetricText(0) == 60.0.ToString("F1") && overlay.ReferenceCount == 3 && game.Pid == 321 && (WindowStyle(body,-20)&0x20) != 0, "size toggle preserves live data, reference, target and passthrough");
                }
                Button(overlay.ControlsWindow, "OverlayMove").RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
                Check(!overlay.Locked && (WindowStyle(body,-20)&0x20) == 0, "move mode enables input on the overlay body");
                overlay.BeginMove(new Point()); overlay.ContinueMove(new Point(-1800, 30));
                Check(BenchmarkOverlayDesktop.Rect(body).Left < 0, "native drag crosses the game monitor boundary before release");
                overlay.EndMove();
                string profile = BenchmarkOverlayPlacement.PathFor(root, game.Identity);
                Check(BenchmarkOverlayPlacement.Load(profile).MonitorId == "left", "cross-monitor drag saves selected monitor per game");
                overlay.SetMedium(false); Layout(overlay); overlay.Place();
                Check(Inside(BenchmarkOverlayDesktop.Rect(body), left.Bounds), "small stays inside the user-selected second monitor");
                overlay.SetMedium(true); Layout(overlay); overlay.Place();
                Check(Inside(BenchmarkOverlayDesktop.Rect(body), left.Bounds), "medium stays inside the user-selected second monitor");
                game.Window = new IntPtr(-1234); overlay.Place();
                Check(Inside(BenchmarkOverlayDesktop.Rect(body), left.Bounds), "saved position survives replacement of the game's native window");
                overlay.SetLocked(true);
                BenchmarkGameWindow.Bounds fixedPosition = BenchmarkOverlayDesktop.Rect(body);
                overlay.BeginMove(new Point()); overlay.ContinueMove(new Point(500, 500)); overlay.EndMove();
                Check(BenchmarkOverlayDesktop.Rect(body).Left == fixedPosition.Left && (WindowStyle(body,-20)&0x20) != 0, "lock fixes the position and restores input passthrough");
                overlay.Update(null); Layout(overlay);
                Check(overlay.MetricText(0) == "—" && overlay.ChartCurve(false) == null && overlay.ChartCurve(true) != null && baseline.FrameTimesMs.SequenceEqual(originalReference), "missing live input clears only current values and preserves reference");
                overlay.Update(live);
                topology = new BenchmarkOverlayMonitor[] { Screen("primary", 0, 0, 1280, 720) };
                overlay.Place();
                BenchmarkGameWindow.Bounds removed = BenchmarkOverlayDesktop.Rect(body);
                Check(Inside(removed, topology[0].Bounds) && BenchmarkOverlayPlacement.Load(profile).MonitorId == "primary" && overlay.ReferenceCount == 3 && overlay.MetricText(0) == 60.0.ToString("F1"), "monitor removal during capture repositions visibly without losing data: rect=" + removed.Left + "," + removed.Top + "," + removed.Right + "," + removed.Bottom + "; monitor=" + BenchmarkOverlayPlacement.Load(profile).MonitorId + "; fps=" + overlay.MetricText(0));
                byte[] saved = File.ReadAllBytes(profile);
                topology = new BenchmarkOverlayMonitor[0]; overlay.Place();
                Check(saved.SequenceEqual(File.ReadAllBytes(profile)) && overlay.ReferenceCount == 3, "temporary display unavailability preserves profile and reference");
                topology = new BenchmarkOverlayMonitor[] { primary, left }; overlay.Place();
                Check(foreground == BenchmarkGameWindow.GetForegroundWindow(), "size, drag, live updates and display changes never activate the overlay");
            }
            using (OverlayLifetime reopened = new OverlayLifetime(new BenchmarkOverlay(root, game, delegate { }, reference, delegate { return topology; }))) {
                new WindowInteropHelper(reopened.Window).EnsureHandle(); Layout(reopened.Window); reopened.Window.Place();
                Check(reopened.Window.Medium && reopened.Window.Locked && reopened.Window.ReferenceCount == 3, "new selection reloads size, lock and monitor preference");
                reopened.Window.Update(live); Layout(reopened.Window);
                Check(reopened.Window.ChartCurve(true) != null && reopened.Window.ChartPointCount == 3, "reopened medium restores live/reference graph");
            }
            using (OverlayLifetime different = new OverlayLifetime(new BenchmarkOverlay(root, game, delegate { }, new double[] { 10, 15, 20, 60, 80 }, delegate { return topology; }))) {
                new WindowInteropHelper(different.Window).EnsureHandle(); different.Window.SetMedium(true); different.Window.Update(live); Layout(different.Window);
                System.Windows.Shapes.Polyline current = different.Window.ChartCurve(false), before = different.Window.ChartCurve(true);
                Check(current.Points.Count == 3 && before.Points.Count == 5 && Math.Abs(current.Points.Last().X - before.Points.Last().X) < .001, "different reference/live lengths preserve every sample and share plot bounds");
            }
        }
        private sealed class OverlayLifetime : IDisposable
        {
            internal BenchmarkOverlay Window;
            internal OverlayLifetime(BenchmarkOverlay window) { Window = window; }
            public void Dispose() { Window.Close(); }
        }
        private static void TestSettings(string root)
        {
            var installed = new System.Collections.Generic.Dictionary<int,uint>();
            using (var hotkeys = new BenchmarkHotkeys(delegate(int id,uint mod,uint key) { if (key == 0x79) return false; installed[id] = key; return true; },delegate(int id) { installed.Remove(id); })) {
                hotkeys.Apply(new string[] { "Ctrl+Alt+F9", "", "Ctrl+Shift+M" },false);
                Check(installed.Count == 2,"configurable hotkeys support disabled entries");
                Reject(delegate { hotkeys.Apply(new string[] { "Ctrl+Alt+F9", "Alt+Ctrl+F9", "" },false); },"semantically duplicate hotkeys rejected before changing registrations");
                Check(installed.Count==2,"invalid bindings preserve previous registrations");
                Reject(delegate { hotkeys.Apply(new string[] { "Ctrl+Alt+F10", "", "" },false); },"system hotkey conflict is reported");
                Check(installed.Count==2 && hotkeys.Bindings[0]=="Ctrl+Alt+F9","registration conflict rolls back previous available bindings");
                Reject(delegate { hotkeys.Apply(new string[]{"F9","",""},false); },"unmodified key rejected");
                hotkeys.Apply(new string[]{"","",""},false); Check(installed.Count==0,"all hotkeys can be disabled and unregistered");
            }
            BenchmarkGame game=new BenchmarkGame {Name="SettingsFixture.exe",Identity=@"C:\Games\SettingsFixture.exe"};
            var screen=Screen("settings",0,0,1280,720);
            using (var lifetime=new OverlayLifetime(new BenchmarkOverlay(root,game,Console.WriteLine,new double[]{10,30},delegate{return new[]{screen};}))) {
                var overlay=lifetime.Window; new WindowInteropHelper(overlay).EnsureHandle();
                var live=new BenchmarkLiveSnapshot {Fps=60,CurrentFps=90,Low=40,Mean=16.6,P99=25,Times=new double[]{10,20,30},UpdatedUtc=DateTime.UtcNow};
                overlay.Update(live); overlay.Preferences.PanelScale=1.5; overlay.Preferences.BackgroundOpacity=.6; overlay.Preferences.CurrentFps=true; overlay.Preferences.Sensors=true; overlay.ApplyPreferences(); Layout(overlay);
                Check(overlay.MetricCount==4 && overlay.MetricText(0)==90.0.ToString("F1") && overlay.ReferenceCount==2,"current FPS replaces first metric; scaling and opacity preserve four metrics/data/reference");
                overlay.SetState("Dados desatualizados · aguardando quadros"); overlay.Update(null); Check(overlay.StatusText.Contains("desatualizados") && overlay.MetricText(0)=="—","stale status clears values and remains readable");
                var saved=BenchmarkOverlayPlacement.Load(BenchmarkOverlayPlacement.PathFor(root,game.Identity));
                Check(saved.PanelScale==1.5 && saved.BackgroundOpacity==.6 && saved.CurrentFps && saved.Sensors,"scale, background, first FPS and optional sensors saved per executable");
                Reject(delegate { saved.PanelScale=Double.NaN; saved.Save(BenchmarkOverlayPlacement.PathFor(root,game.Identity)); },"invalid scale cannot overwrite saved preferences");
                overlay.Preferences.PanelScale=1.75; overlay.SetMedium(true); overlay.ApplyPreferences(); Layout(overlay);
                screen=Screen("settings",0,0,500,300); overlay.Place(); Layout(overlay); overlay.Place();
                Check(Inside(BenchmarkOverlayDesktop.Rect(new WindowInteropHelper(overlay).Handle),screen.Bounds),"effective scale fits smaller monitor while preserving configured scale");
                Check(overlay.Preferences.PanelScale==1.75,"display fitting does not overwrite user scale preference");
                overlay.ResetPreferences(); Check(overlay.Locked && !overlay.Medium && !overlay.Preferences.CurrentFps && !overlay.Preferences.Sensors && overlay.Preferences.PanelScale==1,"reset restores default four metrics, size, position mode and appearance");
            }
        }
    }
}
