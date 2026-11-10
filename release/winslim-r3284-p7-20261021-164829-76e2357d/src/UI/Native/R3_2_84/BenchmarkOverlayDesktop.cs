using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;

namespace WinSlim.NativeUI
{
    internal sealed class BenchmarkOverlayMonitor
    {
        internal string Id;
        internal BenchmarkGameWindow.Bounds Bounds;
        internal bool Primary;
    }
    internal sealed class BenchmarkOverlayPosition
    {
        internal int Left, Top;
        internal BenchmarkOverlayMonitor Monitor;
    }

    internal static class BenchmarkOverlayGeometry
    {
        private static void Validate(BenchmarkOverlayMonitor[] monitors, int width, int height)
        {
            if (monitors == null || monitors.Length == 0 || width <= 0 || height <= 0 || monitors.Any(m => m == null || String.IsNullOrEmpty(m.Id) || m.Bounds.Right <= m.Bounds.Left || m.Bounds.Bottom <= m.Bounds.Top)
                || monitors.Select(m => m.Id).Distinct(StringComparer.OrdinalIgnoreCase).Count() != monitors.Length) throw new IOException("Monitor topology unavailable or invalid.");
        }
        private static double Distance(BenchmarkGameWindow.Bounds bounds, int x, int y)
        {
            double dx = Math.Max(bounds.Left - (double)x, Math.Max(0, x - (double)bounds.Right));
            double dy = Math.Max(bounds.Top - (double)y, Math.Max(0, y - (double)bounds.Bottom));
            return dx * dx + dy * dy;
        }
        private static BenchmarkOverlayPosition Clamp(BenchmarkOverlayMonitor monitor, int left, int top, int width, int height)
        {
            return new BenchmarkOverlayPosition { Monitor = monitor,
                Left = Math.Max(monitor.Bounds.Left, Math.Min(left, monitor.Bounds.Right - width)),
                Top = Math.Max(monitor.Bounds.Top, Math.Min(top, monitor.Bounds.Bottom - height)) };
        }
        internal static BenchmarkOverlayPosition Restore(BenchmarkOverlayPlacement placement, BenchmarkOverlayMonitor[] monitors, BenchmarkGameWindow.Bounds home, int width, int height)
        {
            Validate(monitors, width, height);
            BenchmarkOverlayMonitor monitor = monitors.FirstOrDefault(m => String.Equals(m.Id, placement.MonitorId, StringComparison.OrdinalIgnoreCase));
            if (monitor != null) return Clamp(monitor, monitor.Bounds.Left + (int)Math.Round(placement.X * Math.Max(0, monitor.Bounds.Right - monitor.Bounds.Left - width)),
                monitor.Bounds.Top + (int)Math.Round(placement.Y * Math.Max(0, monitor.Bounds.Bottom - monitor.Bounds.Top - height)), width, height);
            if (placement.Schema == 1) {
                monitor = monitors.OrderBy(m => Distance(m.Bounds, home.Left, home.Top)).First();
                return Clamp(monitor, monitor.Bounds.Left + (int)Math.Round(placement.X * Math.Max(0, monitor.Bounds.Right - monitor.Bounds.Left - width)),
                    monitor.Bounds.Top + (int)Math.Round(placement.Y * Math.Max(0, monitor.Bounds.Bottom - monitor.Bounds.Top - height)), width, height);
            }
            monitor = monitors.OrderBy(m => Distance(m.Bounds, placement.LastLeft, placement.LastTop)).First();
            return Clamp(monitor, placement.LastLeft, placement.LastTop, width, height);
        }
        internal static BenchmarkOverlayPosition FinishMove(BenchmarkOverlayMonitor[] monitors, int left, int top, int width, int height)
        {
            Validate(monitors, width, height);
            // Choose the monitor containing the largest part, then the nearest one across a gap.
            BenchmarkOverlayMonitor monitor = monitors.OrderByDescending(m =>
                Math.Max(0L, Math.Min((long)left + width, m.Bounds.Right) - Math.Max((long)left, m.Bounds.Left)) *
                Math.Max(0L, Math.Min((long)top + height, m.Bounds.Bottom) - Math.Max((long)top, m.Bounds.Top)))
                .ThenBy(m => Distance(m.Bounds, left, top)).First();
            return Clamp(monitor, left, top, width, height);
        }
        internal static void Remember(BenchmarkOverlayPlacement placement, BenchmarkOverlayPosition position, int width, int height)
        {
            placement.Schema = 2; placement.MonitorId = position.Monitor.Id; placement.LastLeft = position.Left; placement.LastTop = position.Top;
            placement.X = BenchmarkOverlayPlacement.Clamp((position.Left - position.Monitor.Bounds.Left) / (double)Math.Max(1, position.Monitor.Bounds.Right - position.Monitor.Bounds.Left - width));
            placement.Y = BenchmarkOverlayPlacement.Clamp((position.Top - position.Monitor.Bounds.Top) / (double)Math.Max(1, position.Monitor.Bounds.Bottom - position.Monitor.Bounds.Top - height));
        }
    }

    internal static class BenchmarkOverlayDesktop
    {
        internal const int Transparent = 0x20, NoActivate = 0x08000000;
        private delegate bool EnumMonitor(IntPtr monitor, IntPtr dc, IntPtr rect, IntPtr data);
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] private struct MonitorInfo
        {
            internal int Size; internal BenchmarkGameWindow.Bounds Monitor, Work; internal uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] internal string Device;
        }
        [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, EnumMonitor callback, IntPtr data);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
        [DllImport("user32.dll", EntryPoint="GetWindowLongW")] internal static extern int ExtendedStyle(IntPtr window, int index);
        [DllImport("user32.dll", EntryPoint="SetWindowLongW", SetLastError=true)] private static extern int SetWindowLong(IntPtr window, int index, int value);
        [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [StructLayout(LayoutKind.Sequential)] private struct Cursor { internal int X, Y; }
        [DllImport("user32.dll")] private static extern bool GetPhysicalCursorPos(out Cursor cursor);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        internal static bool DragButtonDown { get { return (GetAsyncKeyState(1) & 0x8000) != 0; } }
        internal static Point CursorPoint()
        {
            Cursor cursor; if (!GetPhysicalCursorPos(out cursor)) throw new IOException("Cursor unavailable."); return new Point(cursor.X, cursor.Y);
        }
        private sealed class PhysicalCoordinates : IDisposable
        {
            private IntPtr _previous;
            internal PhysicalCoordinates()
            {
                try { _previous = SetThreadDpiAwarenessContext(new IntPtr(-4)); if (_previous == IntPtr.Zero) _previous = SetThreadDpiAwarenessContext(new IntPtr(-3)); }
                catch (EntryPointNotFoundException) { }
            }
            public void Dispose() { if (_previous != IntPtr.Zero) SetThreadDpiAwarenessContext(_previous); }
        }
        internal static BenchmarkOverlayMonitor[] Monitors()
        {
            using (new PhysicalCoordinates()) {
                List<BenchmarkOverlayMonitor> monitors = new List<BenchmarkOverlayMonitor>();
                bool ok = EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr handle, IntPtr dc, IntPtr rect, IntPtr data) {
                    MonitorInfo info = new MonitorInfo { Size = Marshal.SizeOf(typeof(MonitorInfo)) };
                    if (!GetMonitorInfo(handle, ref info)) return true;
                    monitors.Add(new BenchmarkOverlayMonitor { Id = info.Device, Bounds = info.Monitor, Primary = (info.Flags & 1) != 0 }); return true;
                }, IntPtr.Zero);
                if (!ok || monitors.Count == 0) throw new IOException("Monitor topology unavailable.");
                return monitors.OrderByDescending(m => m.Primary).ToArray();
            }
        }
        internal static BenchmarkGameWindow.Bounds Rect(IntPtr handle)
        {
            using (new PhysicalCoordinates()) {
                BenchmarkGameWindow.Bounds bounds;
                if (!BenchmarkGameWindow.GetWindowRect(handle, out bounds)) throw new IOException("Overlay window unavailable.");
                return bounds;
            }
        }
        internal static void Move(IntPtr window, int left, int top, int width, int height, bool resize)
        {
            using (new PhysicalCoordinates()) {
                if (!BenchmarkGameWindow.SetWindowPos(window, new IntPtr(-1), left, top, width, height, resize ? 0x10u : 0x11u)) throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
        internal static void InputStyle(IntPtr window, bool passthrough)
        {
            int style = ExtendedStyle(window, -20) | NoActivate | 0x80; // TOOLWINDOW
            style = passthrough ? style | Transparent : style & ~Transparent;
            SetWindowLong(window, -20, style);
            if (ExtendedStyle(window, -20) != style) throw new Win32Exception("Overlay input style was not applied.");
        }
    }
}
