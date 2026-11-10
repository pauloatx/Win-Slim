using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace WinSlim.NativeUI
{
    internal sealed class BenchmarkGame
    {
        internal int Pid;
        internal string Name, Identity;
        internal long Started;
        internal IntPtr Window;
        internal bool IsAlive()
        {
            try { using (Process p = Process.GetProcessById(Pid)) return !p.HasExited && p.StartTime.ToUniversalTime().Ticks == Started && String.Equals(p.ProcessName + ".exe", Name, StringComparison.OrdinalIgnoreCase); }
            catch (ArgumentException) { return false; }
            catch (InvalidOperationException) { return false; }
            catch (System.ComponentModel.Win32Exception) { return false; }
        }
        internal static BenchmarkGame FromProcess(Process process, IntPtr window)
        {
            string name = process.ProcessName + ".exe", identity;
            try { identity = process.MainModule.FileName; }
            catch (System.ComponentModel.Win32Exception) { identity = name; }
            return new BenchmarkGame { Pid = process.Id, Name = name, Identity = identity.ToLowerInvariant(), Started = process.StartTime.ToUniversalTime().Ticks, Window = window };
        }
    }

    internal static class BenchmarkGameWindow
    {
        [StructLayout(LayoutKind.Sequential)] internal struct Bounds { internal int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { internal int Size; internal Bounds Monitor, Work; internal uint Flags; }
        [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] internal static extern bool GetWindowRect(IntPtr window, out Bounds rect);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")] private static extern IntPtr GetShellWindow();
        [DllImport("user32.dll")] private static extern IntPtr GetDesktopWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out int pid);
        [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
        [DllImport("user32.dll")] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
        private delegate bool EnumWindow(IntPtr window, IntPtr data);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindow callback, IntPtr data);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out int value, int size);
        [DllImport("user32.dll")] internal static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
        internal static Bounds MonitorBounds(IntPtr window)
        {
            MonitorInfo info = new MonitorInfo { Size = Marshal.SizeOf(typeof(MonitorInfo)) };
            if (!GetMonitorInfo(MonitorFromWindow(window, 2), ref info)) throw new IOException("Monitor indisponível.");
            return info.Monitor;
        }
        internal static bool CoversMonitor(Bounds window, Bounds monitor)
        {
            return monitor.Right > monitor.Left && monitor.Bottom > monitor.Top && Math.Abs((long)window.Left - monitor.Left) <= 8 && Math.Abs((long)window.Top - monitor.Top) <= 8
                && Math.Abs((long)window.Right - monitor.Right) <= 8 && Math.Abs((long)window.Bottom - monitor.Bottom) <= 8;
        }
        internal static BenchmarkGame ForegroundGame()
        {
            return GameForWindow(GetForegroundWindow());
        }
        internal static BenchmarkGame SingleFullscreenGame()
        {
            // Initial discovery also works when Win-Slim was opened after a borderless game.
            // More than one possible target requires foreground observation or manual choice.
            BenchmarkGame selected = null; bool ambiguous = false;
            EnumWindows(delegate(IntPtr window, IntPtr data) {
                BenchmarkGame candidate = GameForWindow(window);
                if (candidate == null) return true;
                if (selected != null && selected.Pid != candidate.Pid) { ambiguous = true; return false; }
                selected = candidate; return true;
            }, IntPtr.Zero);
            return ambiguous ? null : selected;
        }
        private static BenchmarkGame GameForWindow(IntPtr window)
        {
            if (window == IntPtr.Zero || window == GetShellWindow() || window == GetDesktopWindow() || !IsWindowVisible(window) || IsIconic(window)) return null;
            int pid, cloaked;
            GetWindowThreadProcessId(window, out pid);
            if (pid <= 0 || pid == Process.GetCurrentProcess().Id) return null;
            if (DwmGetWindowAttribute(window, 14, out cloaked, sizeof(int)) == 0 && cloaked != 0) return null;
            Bounds bounds;
            if (!GetWindowRect(window, out bounds) || !CoversMonitor(bounds, MonitorBounds(window))) return null;
            try {
                using (Process process = Process.GetProcessById(pid)) {
                    string name = process.ProcessName;
                    if (name.Equals("explorer", StringComparison.OrdinalIgnoreCase) || name.Equals("ApplicationFrameHost", StringComparison.OrdinalIgnoreCase) || name.Equals("dwm", StringComparison.OrdinalIgnoreCase)) return null;
                    return BenchmarkGame.FromProcess(process, window);
                }
            } catch (ArgumentException) { return null; }
            catch (InvalidOperationException) { return null; }
            catch (System.ComponentModel.Win32Exception) { return null; }
        }
        internal static bool IsForeground(BenchmarkGame game)
        {
            int pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid);
            return game != null && pid == game.Pid && game.IsAlive();
        }
    }
}
