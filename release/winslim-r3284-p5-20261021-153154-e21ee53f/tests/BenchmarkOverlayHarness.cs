using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace WinSlim.NativeUI
{
    internal static class BenchmarkOverlayHarness
    {
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
                return 0;
            } catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
            finally { Directory.Delete(temp, true); }
        }
        private sealed class OverlayLifetime : IDisposable
        {
            internal BenchmarkOverlay Window;
            internal OverlayLifetime(BenchmarkOverlay window) { Window = window; }
            public void Dispose() { Window.Close(); }
        }
    }
}
