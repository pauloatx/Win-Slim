using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.IO.Pipes;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace WinSlim.NativeUI
{
    // DLL-only fixture. No Main, executable generation, Process.Start, ETW or collector CLI emulation.
    internal static class CaptureTransportFixture
    {
        private static readonly List<string> Results = new List<string>();
        private static void Check(bool value, string label) { Results.Add((value ? "[OK] " : "[FAIL] ") + label); }
        private sealed class PendingReader : TextReader
        {
            private readonly TaskCompletionSource<int> _read = new TaskCompletionSource<int>();
            public override Task<int> ReadAsync(char[] buffer, int index, int count) { return _read.Task; }
            protected override void Dispose(bool disposing) { _read.TrySetResult(0); base.Dispose(disposing); }
        }
        private sealed class FailedReader : TextReader
        {
            public override Task<int> ReadAsync(char[] buffer, int index, int count) { throw new IOException("injected reader failure"); }
        }
        private sealed class Streams : IPresentMonTransport
        {
            internal readonly string Mode;
            private readonly ManualResetEventSlim _exited = new ManualResetEventSlim(false);
            private volatile bool _stopped;
            private AnonymousPipeServerStream _outPipe, _errPipe;
            private TextReader _output, _errors;
            private Task _writers;
            internal int StopCalls, KillCalls;
            internal long OutputBytes, ErrorBytes;
            internal Streams(string mode) { Mode = mode; }
            public TextReader Output { get { return _output; } }
            public TextReader Errors { get { return _errors; } }
            public bool HasExited { get { return _exited.IsSet; } }
            public int ExitCode { get { return Mode == "exit7" ? 7 : 0; } }
            public bool Start()
            {
                if (Mode == "denied") throw new Win32Exception(5, "injected access denied, no binary executed");
                if (Mode == "not-started") return false;
                if (Mode == "stderr-fault" || Mode == "stdout-fault" || Mode == "closed-output" || Mode == "stop-fault") {
                    _output = Mode == "stdout-fault" ? (TextReader)new FailedReader() : Mode == "closed-output" ? (TextReader)new StringReader("") : new PendingReader();
                    _errors = Mode == "stderr-fault" ? (TextReader)new FailedReader() : new PendingReader();
                    return true;
                }
                _outPipe = new AnonymousPipeServerStream(PipeDirection.Out, HandleInheritability.None, 4096);
                _errPipe = new AnonymousPipeServerStream(PipeDirection.Out, HandleInheritability.None, 4096);
                _output = new StreamReader(new AnonymousPipeClientStream(PipeDirection.In, _outPipe.ClientSafePipeHandle), Encoding.UTF8);
                _errors = new StreamReader(new AnonymousPipeClientStream(PipeDirection.In, _errPipe.ClientSafePipeHandle), Encoding.UTF8);
                Task output = Task.Run(delegate {
                    try {
                        using (var writer = new StreamWriter(_outPipe, new UTF8Encoding(false))) {
                            if (Mode == "malformed") writer.WriteLine("broken,header");
                            else {
                                writer.WriteLine("Application,ProcessID,SwapChainAddress,MsBetweenPresents");
                                int count = Mode == "pressure" ? 30000 : Mode == "cancel-pressure" ? 2000000 : 100;
                                for (int i = 0; i < count && !_stopped; i++) { writer.WriteLine("game.exe,7301,0x1,10"); OutputBytes += 21; if (i % 100 == 0) writer.Flush(); }
                            }
                        }
                    } catch (Exception) { if (!_stopped) throw; }
                });
                Task error = Task.Run(delegate {
                    try {
                        using (var writer = new StreamWriter(_errPipe, new UTF8Encoding(false))) {
                            int count = Mode == "cancel-pressure" ? 1000000 : 80;
                            string text = new string('e', 4096);
                            for (int i = 0; i < count && !_stopped; i++) { writer.Write(text); ErrorBytes += text.Length; writer.Flush(); }
                        }
                    } catch (Exception) { if (!_stopped) throw; }
                });
                _writers = Task.WhenAll(output, error);
                _writers.ContinueWith(delegate(Task ignored) { _exited.Set(); });
                return true;
            }
            public bool WaitForExit(int milliseconds) { return _exited.Wait(Mode == "stop-fault" ? Math.Min(milliseconds, 25) : milliseconds); }
            public void StopOwnedSession()
            {
                StopCalls++;
                if (Mode == "stop-fault") throw new IOException("injected owned stop failure");
                Close();
            }
            public void KillOwnedProcess() { KillCalls++; Close(); }
            private void Close()
            {
                _stopped = true;
                if (_output != null) _output.Dispose();
                if (_errors != null) _errors.Dispose();
                if (_outPipe != null) _outPipe.Dispose();
                if (_errPipe != null) _errPipe.Dispose();
                _exited.Set();
            }
            public void Dispose() { Close(); if (_writers != null) { try { _writers.Wait(3000); } catch (AggregateException) { } } }
            internal bool WritersFinished { get { return _writers == null || _writers.IsCompleted; } }
        }
        private static PresentMonMonitor NewMonitor(string root)
        {
            return (PresentMonMonitor)Activator.CreateInstance(typeof(PresentMonMonitor), BindingFlags.Instance | BindingFlags.NonPublic, null,
                new object[] { root, Path.Combine(root, "absent-not-executed"), 7301, "game.exe" }, null);
        }
        private static Task Run(PresentMonMonitor monitor, Streams transport)
        {
            Task task = Task.Run(delegate { monitor.RunTransport(transport); });
            typeof(PresentMonMonitor).GetProperty("Completion", BindingFlags.Instance | BindingFlags.NonPublic).SetValue(monitor, task, null);
            return task;
        }
        internal static string[] RunAll(string root)
        {
            Results.Clear(); Directory.CreateDirectory(root);
            string reference = Path.Combine(root, "reference.csv");
            var rows = new List<string> { "Application,ProcessID,SwapChainAddress,MsBetweenPresents" };
            for (int i = 0; i < 100; i++) rows.Add("game.exe,7301,0x1,10");
            File.WriteAllLines(reference, rows); string originalHash = PresentMonBenchmark.Hash(reference);
            foreach (string mode in new[] { "not-started", "denied", "exit7", "malformed", "stdout-fault", "stderr-fault", "closed-output", "stop-fault", "pressure", "cancel-pressure" }) {
                using (var transport = new Streams(mode)) {
                    PresentMonMonitor monitor = NewMonitor(root);
                    Task<BenchmarkResult> recording;
                    using (var token = new CancellationTokenSource()) {
                        recording = monitor.RecordAsync(10, token.Token);
                        Task run = Run(monitor, transport);
                        if (mode == "cancel-pressure") {
                            Thread.Sleep(300); token.Cancel();
                            bool cancelled = false; try { recording.GetAwaiter().GetResult(); } catch (OperationCanceledException) { cancelled = true; }
                            Check(cancelled && monitor.Running, "cancel under OS-pipe pressure preserves live transport until explicit stop");
                            monitor.StopAsync().GetAwaiter().GetResult();
                        } else if (mode == "stop-fault") {
                            Thread.Sleep(150); monitor.StopAsync().GetAwaiter().GetResult();
                        }
                        bool timely = run.Wait(2000);
                        if (!timely) { transport.KillOwnedProcess(); Check(run.Wait(3000), mode + ": timeout cleanup joins fixture"); }
                        Check(timely, mode + ": transport reaches terminal state promptly");
                        if (mode != "cancel-pressure") {
                            bool rejected = false; try { recording.GetAwaiter().GetResult(); } catch (Exception) { rejected = true; }
                            Check(rejected, mode + ": no successful partial benchmark");
                        }
                        Check(!monitor.Running && monitor.Snapshot == null, mode + ": ended transport clears live state");
                        if (mode == "stderr-fault" || mode == "stdout-fault") Check(monitor.Error != null && monitor.Error.Contains("injected reader failure"), mode + ": exact IO failure retained");
                        if (mode == "closed-output") Check(monitor.Error != null && monitor.Error.Contains("stdout"), "closed stdout is identified while process lifecycle is still active");
                        if (mode == "exit7") Check(monitor.Error != null && monitor.Error.Contains("(7)") && monitor.Error.Contains("eeee"), "nonzero exit retains code and stderr; never accepted");
                        if (mode == "stop-fault") Check(transport.KillCalls == 1 && monitor.Error.Contains("owned stop failure"), "owned stop failure uses only owned kill fallback and reports error");
                        if (mode == "pressure") Check(transport.OutputBytes > 600000 && transport.ErrorBytes >= 327680 && transport.WritersFinished && transport.StopCalls == 0 && monitor.BufferedCount == 4096, "both real OS pipes drained concurrently above buffer capacity without deadlock");
                        Check(PresentMonBenchmark.Hash(reference) == originalHash, mode + ": unrelated completed reference unchanged");
                    }
                }
            }
            PreviewCases();
            return Results.ToArray();
        }
        private static void PreviewCases()
        {
            foreach (string mode in new[] { "preview-throws", "snapshot-throws", "unavailable", "recording-fault", "recording-cancel" }) {
                var completion = new TaskCompletionSource<BenchmarkResult>(); var accepted = new BenchmarkResult { Frames = 100 };
                int calls = 0;
                Func<BenchmarkLiveSnapshot> snapshot = delegate { if (mode == "snapshot-throws") throw new IOException("snapshot unavailable"); return null; };
                Action<BenchmarkLiveSnapshot> preview = delegate(BenchmarkLiveSnapshot value) { calls++; if (mode == "preview-throws") throw new IOException("preview unavailable"); };
                Task<BenchmarkResult> observer = PresentMonBenchmark.ObserveRecording(completion.Task, snapshot, preview);
                Thread.Sleep(600);
                Check(!observer.IsCompleted && !completion.Task.IsCompleted, mode + ": preview does not complete or cancel pending recording");
                if (mode == "recording-fault") completion.SetException(new IOException("recording source failure"));
                else if (mode == "recording-cancel") completion.SetCanceled();
                else completion.SetResult(accepted);
                try { Check(Object.ReferenceEquals(observer.GetAwaiter().GetResult(), accepted), mode + ": original accepted result preserved"); }
                catch (Exception ex) { Check(mode == "recording-fault" ? ex is IOException && ex.Message == "recording source failure" : mode == "recording-cancel" && ex is OperationCanceledException, mode + ": recording failure/cancellation propagated"); }
                if (mode == "preview-throws") Check(calls == 1, "throwing preview callback disabled after first failure");
            }
        }
    }
}
