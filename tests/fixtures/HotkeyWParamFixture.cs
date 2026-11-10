using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;

namespace WinSlim.NativeUI
{
    // Library only. Uses the actual private production Hook through its native delegate.
    public static class HotkeyWParamFixture
    {
        [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp);
        private static void Check(List<string> results, string name, Action test)
        {
            try { test(); results.Add("[OK] " + name); }
            catch (Exception error) { results.Add("[FAIL] " + name + ": " + error.GetType().Name + " - " + error.Message); }
        }
        private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
        private static HwndSourceHook Bind(BenchmarkHotkeys keys)
        {
            return (HwndSourceHook)Delegate.CreateDelegate(typeof(HwndSourceHook), keys,
                typeof(BenchmarkHotkeys).GetMethod("Hook", BindingFlags.NonPublic | BindingFlags.Instance));
        }
        public static string[] RunAll(string root)
        {
            if (IntPtr.Size != 8) throw new PlatformNotSupportedException("64-bit host required; do not skip native-width cases.");
            List<string> results = new List<string>();
            Exception failure = null;
            Thread thread = new Thread(delegate() {
                try { RunSta(root, results); } catch (Exception error) { failure = error; }
                finally { System.Windows.Threading.Dispatcher.CurrentDispatcher.InvokeShutdown(); }
            });
            thread.IsBackground = true;
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            if (!thread.Join(30000)) throw new TimeoutException("STA fixture did not finish.");
            if (failure != null) results.Add("[FAIL] STA fixture: " + failure);
            return results.ToArray();
        }
        private static void RunSta(string root, List<string> results)
        {
            Directory.CreateDirectory(root);
            var actions = new List<int>();
            var captures = new List<string>();
            Window window = new Window { Title = "WinSlim isolated hotkey regression", ShowInTaskbar = false, Width = 100, Height = 100 };
            BenchmarkHotkeys keys = null;
            try {
                keys = new BenchmarkHotkeys(window, root, delegate(int index) { actions.Add(index); });
                HwndSourceHook hook = Bind(keys);
                IntPtr hwnd = new WindowInteropHelper(window).Handle;
                Check(results, "real WPF HWND on STA", delegate { Require(hwnd != IntPtr.Zero && Thread.CurrentThread.GetApartmentState() == ApartmentState.STA, "Missing STA HWND"); });
                keys.Apply(new string[] { "", "", "" });
                string path = Path.Combine(root, "config", "benchmark-hotkeys.json");
                byte[] saved = File.ReadAllBytes(path);
                long[] values = { 0, 0x5710, Int32.MaxValue, Int32.MinValue, 0x100000000L, 0x100005710L, Int64.MaxValue, Int64.MinValue };
                foreach (int message in new int[] { 0, 0x10, 0x3D, 0x400 }) {
                    foreach (long value in values) {
                        foreach (bool initial in new bool[] { false, true }) {
                            int msg = message; long wp = value; bool original = initial;
                            Check(results, "foreign msg=" + msg + " wp=" + wp + " handled=" + original, delegate {
                                int before = actions.Count; bool handled = original;
                                IntPtr returned = hook(hwnd, msg, new IntPtr(wp), new IntPtr(Int64.MinValue), ref handled);
                                Require(returned == IntPtr.Zero && handled == original && actions.Count == before, "Foreign message changed dispatch/handled/result");
                            });
                        }
                    }
                }
                foreach (long value in new long[] { 0, -1, 0x570F, 0x5713, Int32.MinValue, Int32.MaxValue, Int64.MinValue, Int64.MaxValue, 0x100005710L, 0x100005711L, 0x100005712L, -0x100000000L + 0x5710 }) {
                    foreach (bool initial in new bool[] { false, true }) {
                        long wp = value; bool original = initial;
                        Check(results, "invalid WM_HOTKEY wp=" + wp + " handled=" + original, delegate {
                            int before = actions.Count; bool handled = original;
                            Require(hook(IntPtr.Zero, 0x312, new IntPtr(wp), IntPtr.Zero, ref handled) == IntPtr.Zero, "Unexpected return");
                            Require(handled == original && actions.Count == before, "Invalid ID dispatched/truncated or changed handled");
                        });
                    }
                }
                for (int state = 0; state < 4; state++) {
                    keys.Suspended = (state & 1) != 0;
                    keys.Capture = (state & 2) != 0 ? (Action<string>)delegate(string text) { captures.Add(text); } : null;
                    for (int index = 0; index < 3; index++) {
                        int current = index;
                        Check(results, "valid WM_HOTKEY state=" + state + " index=" + index, delegate {
                            int a = actions.Count, c = captures.Count; bool handled = false;
                            Require(hook(hwnd, 0x312, new IntPtr(0x5710 + current), new IntPtr(Int64.MaxValue), ref handled) == IntPtr.Zero && handled, "Valid ID not handled");
                            Require(actions.Count == a + (keys.Suspended ? 0 : 1), "Wrong action count");
                            Require(captures.Count == c + (keys.Suspended && keys.Capture != null ? 1 : 0), "Wrong capture count");
                            if (!keys.Suspended) Require(actions.Last() == current, "Wrong command index");
                            if (keys.Suspended && keys.Capture != null) Require(captures.Last() == keys.Bindings[current], "Wrong captured binding");
                        });
                    }
                    Check(results, "invalid/foreign messages never capture state=" + state, delegate {
                        int a = actions.Count, c = captures.Count; bool handled = false;
                        hook(hwnd, 0x312, new IntPtr(0x100005710L), IntPtr.Zero, ref handled);
                        hook(hwnd, 0x3D, new IntPtr(Int64.MaxValue), IntPtr.Zero, ref handled);
                        Require(!handled && a == actions.Count && c == captures.Count, "Unexpected capture/action");
                    });
                }
                keys.Suspended = false; keys.Capture = null;
                Check(results, "native source delivers WM_HOTKEY before Dispose", delegate {
                    int before = actions.Count;
                    SendMessage(hwnd, 0x312, new IntPtr(0x5712), IntPtr.Zero);
                    Require(actions.Count == before + 1 && actions.Last() == 2, "Source hook not attached");
                });
                Check(results, "invalid Apply preserves bindings and saved bytes", delegate {
                    try { keys.Apply(new string[] { "Ctrl+F9", "Ctrl+F9", "" }); throw new InvalidOperationException("Duplicate accepted"); }
                    catch (ArgumentException) { }
                    Require(keys.Bindings.SequenceEqual(new string[] { "", "", "" }) && saved.SequenceEqual(File.ReadAllBytes(path)), "Invalid Apply changed state");
                });
                Check(results, "message matrix preserves bindings and saved bytes", delegate {
                    Require(keys.Bindings.SequenceEqual(new string[] { "", "", "" }) && saved.SequenceEqual(File.ReadAllBytes(path)), "Hook changed persisted state");
                });
                Check(results, "Dispose removes real source hook and preserves storage", delegate {
                    keys.Dispose(); int before = actions.Count;
                    SendMessage(hwnd, 0x312, new IntPtr(0x5710), IntPtr.Zero);
                    Require(actions.Count == before && saved.SequenceEqual(File.ReadAllBytes(path)), "Disposed source dispatched or changed file");
                });
            } finally { if (keys != null) keys.Dispose(); window.Close(); }

            // Registration failure is simulated; no global shortcut or production setting is changed.
            var registered = new Dictionary<int, uint>();
            bool deny = false;
            using (var simulated = new BenchmarkHotkeys(delegate(int id, uint mod, uint key) {
                if (deny && key == 0x59) return false;
                registered[id] = key; return true;
            }, delegate(int id) { registered.Remove(id); })) {
                simulated.Apply(new string[] { "Ctrl+Alt+F9", "Shift+F10", "" }, false);
                string[] previous = simulated.Bindings;
                Check(results, "injected unavailable registration restores all previous IDs", delegate {
                    deny = true;
                    try { simulated.Apply(new string[] { "Ctrl+X", "Ctrl+Y", "Ctrl+Z" }, false); throw new InvalidOperationException("Unavailable registration accepted"); }
                    catch (BenchmarkHotkeyException error) { Require(error.Index == 1, "Wrong failed field"); }
                    Require(simulated.Bindings.SequenceEqual(previous) && registered.Count == 2 && registered[0x5710] == 0x78 && registered[0x5711] == 0x79, "Rollback failed");
                });
                Check(results, "null/wrong-length/malformed Apply preserve registrations", delegate {
                    foreach (string[] invalid in new string[][] { null, new string[0], new string[] { "Ctrl+F12", "", "" } }) {
                        try { simulated.Apply(invalid, false); throw new InvalidOperationException("Invalid input accepted"); } catch (ArgumentException) { }
                    }
                    Require(simulated.Bindings.SequenceEqual(previous) && registered.Count == 2, "Input failure changed state");
                });
                Check(results, "suspended capture retains nonempty binding after rollback", delegate {
                    string captured = null; simulated.Suspended = true; simulated.Capture = delegate(string text) { captured = text; };
                    bool handled = false; Bind(simulated)(IntPtr.Zero, 0x312, new IntPtr(0x5711), IntPtr.Zero, ref handled);
                    Require(handled && captured == previous[1], "Capture/rollback binding lost");
                });
                Check(results, "Dispose unregisters all simulated IDs", delegate { simulated.Dispose(); Require(registered.Count == 0, "Leaked registration"); });
            }
        }
    }
}
