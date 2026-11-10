using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
namespace WinSlim.NativeUI
{
    internal static class PresentMonHarness
    {
        private static void Check(bool ok, string label) { if (!ok) throw new Exception(label); Console.WriteLine("[OK] " + label); }
        private static void Reject(Action action, string label) { bool rejected = false; try { action(); } catch { rejected = true; } Check(rejected, label); }
        private static string Argument(string[] args, string key) { int i = Array.IndexOf(args, key); return i >= 0 && i + 1 < args.Length ? args[i + 1] : ""; }
        private static string Csv(int pid, int frames)
        {
            string text = "Application,ProcessID,SwapChainAddress,MsBetweenPresents\n";
            for (int i = 0; i < frames; i++) text += "\"Game, test.exe\"," + pid + ",0x1," + (i == frames - 1 ? "100" : "10") + "\n";
            return text;
        }
        private static int Fake(string[] args)
        {
            string session = Argument(args, "--session_name");
            string stop = Path.Combine(Path.GetTempPath(), session + ".fake-stop");
            if (args.Contains("--terminate_existing_session")) { File.WriteAllText(stop, "stop"); return 0; }
            int pid = Int32.Parse(Argument(args, "--process_id"), CultureInfo.InvariantCulture);
            if (pid == 4244) { Console.Error.WriteLine("simulated collector error"); return 7; }
            if (pid == 4246 || pid == 4247) {
                string csv = Argument(args, "--output_file");
                using (FileStream file = new FileStream(csv, FileMode.Create, FileAccess.Write, FileShare.ReadWrite))
                using (StreamWriter writer = new StreamWriter(file, new System.Text.UTF8Encoding(false))) {
                    writer.Write(Csv(pid, 100).Replace("\"Game, test.exe\"", "game.exe")); writer.Flush();
                    if (pid == 4246) Thread.Sleep(1200);
                    else {
                        Stopwatch clock = Stopwatch.StartNew();
                        while (!File.Exists(stop) && clock.Elapsed.TotalSeconds < 15) Thread.Sleep(20);
                        if (File.Exists(stop)) File.Delete(stop);
                    }
                }
                return 0;
            }
            if (pid == 4243) {
                Stopwatch clock = Stopwatch.StartNew();
                while (!File.Exists(stop) && clock.Elapsed.TotalSeconds < 15) Thread.Sleep(20);
                if (File.Exists(stop)) File.Delete(stop);
                return 0;
            }
            Console.WriteLine(new string('x', 200000)); Console.Error.WriteLine(new string('y', 200000));
            File.WriteAllText(Argument(args, "--output_file"), Csv(pid == 4245 ? 99 : pid, 100).Replace("\"Game, test.exe\"", "game.exe"));
            return 0;
        }
        private static int Main(string[] args)
        {
            if (args.Length > 0 && args[0].StartsWith("--", StringComparison.Ordinal)) return Fake(args);
            string temp = Path.Combine(Path.GetTempPath(), "PresentMon teste acentuação " + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(temp);
            try {
                CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("pt-BR");
                string csv = Path.Combine(temp, "frames.csv");
                File.WriteAllText(csv, Csv(42, 100) + "Game.exe,42,0x1,0\nGame.exe,42,0x1,-1\nGame.exe,42,0x1,NaN\nGame.exe,42,0x1,Infinity\n" + Csv(99, 200).Substring(Csv(99, 200).IndexOf('\n') + 1));
                BenchmarkResult r = PresentMonBenchmark.ReadCsv(csv, 42);
                Check(r.Frames == 100 && r.InvalidFrames == 4 && r.ProcessId == 42 && r.Application == "Game, test.exe", "quoted CSV, invalid intervals and PID isolation");
                Check(Math.Abs(r.MeanFrameMs - 10.9) < 0.000001 && Math.Abs(r.AverageFps - 1000.0 / 10.9) < 0.000001 && r.P99FrameMs == 10 && r.OnePercentLowFps == 10, "mean FPS, nearest-rank P99 and slowest-one-percent mean");
                Check(r.FrameTimesMs.Length == 100 && r.FrameTimesMs[99] == 100, "timeline preserves capture order");
                Check(PresentMonBenchmark.ReadCsv(csv, 0).ProcessId == 99, "dominant stream selected without mixing processes");
                string alternate = Csv(42, 50).Replace("0x1", "0x2");
                File.WriteAllText(csv, Csv(42, 100) + alternate.Substring(alternate.IndexOf('\n') + 1));
                Check(PresentMonBenchmark.ReadCsv(csv, 42).Frames == 100, "swap chains remain separate");
                foreach (string invalid in new string[] { "", "ProcessID,CPUFrameTime\n42,10", "Application,ProcessID,SwapChainAddress,MsBetweenPresents\n\"broken", Csv(42, 2), "Application,ProcessID,SwapChainAddress,MsBetweenPresents,MsBetweenPresents\n", Csv(42, 100) + "bad,row\n" }) {
                    File.WriteAllText(csv, invalid); Reject(delegate { PresentMonBenchmark.ReadCsv(csv, 42); }, "malformed, unsupported or insufficient CSV rejected");
                }
                string session = "WinSlim-" + Guid.NewGuid().ToString("N");
                string command = PresentMonBenchmark.CaptureArguments(42, 30, Path.Combine(temp, "frames.csv"), session);
                Check(command.Contains("--process_id 42") && command.Contains("--v1_metrics") && command.Contains("--session_name " + session) && !command.Contains("--stop_existing_session") && !command.Contains("--restart_as_admin"), "pinned metrics, target PID, unique session and no global takeover");
                Reject(delegate { PresentMonBenchmark.CaptureArguments(0, 30, csv, session); }, "invalid PID rejected");
                Reject(delegate { PresentMonBenchmark.CaptureArguments(42, 121, csv, session); }, "unbounded duration rejected");
                Reject(delegate { PresentMonBenchmark.CaptureArguments(42, 30, csv, "PresentMon"); }, "foreign session rejected");
                Reject(delegate { PresentMonBenchmark.CaptureArguments(42, 30, "x\" --process_id 1", session); }, "argument injection rejected");
                Reject(delegate { PresentMonBenchmark.CaptureAsync(temp, 42, "game.exe", 10, CancellationToken.None).GetAwaiter().GetResult(); }, "missing collector never silently replaced");
                string binary = PresentMonBenchmark.BinaryPath(temp); Directory.CreateDirectory(Path.GetDirectoryName(binary)); File.WriteAllText(binary, "tampered");
                Reject(delegate { PresentMonBenchmark.CaptureAsync(temp, 42, "game.exe", 10, CancellationToken.None).GetAwaiter().GetResult(); }, "tampered collector rejected before execution");
                string executable = Process.GetCurrentProcess().MainModule.FileName;
                BenchmarkResult capture = PresentMonBenchmark.CaptureCore(executable, temp, 4242, "game.exe", 10, CancellationToken.None);
                Check(capture.Frames == 100 && capture.RequestedSeconds == 10 && capture.Session.StartsWith("WinSlim-", StringComparison.Ordinal) && File.Exists(capture.CsvPath), "actual process capture with fake collector and durable CSV");
                Check(new FileInfo(Path.Combine(Path.GetDirectoryName(capture.CsvPath), "stdout.log")).Length > 65536 && new FileInfo(Path.Combine(Path.GetDirectoryName(capture.CsvPath), "stderr.log")).Length > 65536, "stdout/stderr drained without deadlock");
                Reject(delegate { PresentMonBenchmark.CaptureCore(executable, temp, 4244, "game.exe", 10, CancellationToken.None); }, "collector exit 7 rejects capture");
                Reject(delegate { PresentMonBenchmark.CaptureCore(executable, temp, 4245, "game.exe", 10, CancellationToken.None); }, "CSV from another PID rejected");
                Reject(delegate { PresentMonBenchmark.CaptureCore(executable, temp, 4242, "other.exe", 10, CancellationToken.None); }, "reused PID with different process name rejected");
                int previews = 0;
                BenchmarkResult liveCapture = PresentMonBenchmark.CaptureCore(executable, temp, 4246, "game.exe", 10, CancellationToken.None, delegate(BenchmarkLiveSnapshot snapshot) { if (snapshot != null) previews++; });
                Check(previews > 0 && liveCapture.Frames == 100, "live metrics arrive while collector is running without changing final capture");
                using (CancellationTokenSource cancellation = new CancellationTokenSource()) {
                    cancellation.CancelAfter(750); bool cancelled = false; previews = 0;
                    try { PresentMonBenchmark.CaptureCore(executable, temp, 4247, "game.exe", 10, cancellation.Token, delegate(BenchmarkLiveSnapshot snapshot) { if (snapshot != null) previews++; }); }
                    catch (OperationCanceledException) { cancelled = true; }
                    Check(cancelled && previews > 0 && liveCapture.Frames == 100, "cancelling a live preview accepts no partial capture and preserves previous result");
                }
                Check(PresentMonBenchmark.CaptureCore(executable, temp, 4242, "game.exe", 10, CancellationToken.None).Frames == 100, "capture again after live cancellation");
                Check(PresentMonBenchmark.CaptureCore(executable, temp, 4246, "game.exe", 10, CancellationToken.None, delegate { throw new IOException("preview unavailable"); }).Frames == 100, "unavailable preview preserves collector completion");
                TestLiveReader(temp);
                using (CancellationTokenSource cancellation = new CancellationTokenSource()) {
                    cancellation.CancelAfter(250); bool cancelled = false; Stopwatch clock = Stopwatch.StartNew();
                    try { PresentMonBenchmark.CaptureCore(executable, temp, 4243, "game.exe", 10, cancellation.Token); } catch (OperationCanceledException) { cancelled = true; }
                    Check(cancelled && clock.Elapsed.TotalSeconds < 8, "cancellation stops only owned session and yields no accepted partial result");
                }
                BenchmarkResult before = new BenchmarkResult { Application = "game.exe", RequestedSeconds = 10, AverageFps = 100 };
                BenchmarkResult after = new BenchmarkResult { Application = "game.exe", RequestedSeconds = 10, AverageFps = 110 };
                Check(Math.Abs(PresentMonBenchmark.Compare(before, after) - 10) < 0.000001, "before/after percentage");
                after.Application = "other.exe"; Reject(delegate { PresentMonBenchmark.Compare(before, after); }, "unrelated app comparison rejected");
                after.Application = before.Application; after.RequestedSeconds = 30; Reject(delegate { PresentMonBenchmark.Compare(before, after); }, "different duration comparison rejected");
                after.RequestedSeconds = 0; Reject(delegate { PresentMonBenchmark.Compare(before, after); }, "import with unknown duration not compared");
                return 0;
            } catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
            finally { Directory.Delete(temp, true); }
        }
        private static void TestLiveReader(string root)
        {
            string path = Path.Combine(root, "live.csv");
            DateTime now = DateTime.UtcNow;
            BenchmarkLiveReader reader = new BenchmarkLiveReader(42, "game.exe");
            Check(reader.Poll(path, now) == null, "live missing CSV is unavailable, not zero FPS");
            string data = Csv(42, 100).Replace("\"Game, test.exe\"", "game.exe");
            File.WriteAllText(path, data + "game.exe,42,0x1,2");
            BenchmarkLiveSnapshot snapshot = reader.Poll(path, now);
            Check(snapshot != null && Math.Abs(snapshot.Mean - 10.9) < .000001 && snapshot.P99 == 10 && snapshot.Low == 10 && snapshot.Times.Length == 100, "live four metrics use capture formulas and withhold incomplete row");
            File.AppendAllText(path, "0\n" + Csv(99, 200).Substring(Csv(99, 200).IndexOf('\n') + 1) + "other.exe,42,0x1,500\ngame.exe,42,0x2,500\ngame.exe,42,0x1,NaN\n");
            snapshot = reader.Poll(path, now.AddMilliseconds(500));
            Check(snapshot.Times.Length == 101 && snapshot.Times[100] == 20, "live incremental rows isolate PID, name, swap chain and invalid values");
            Check(reader.Poll(path, now.AddSeconds(4)) == null, "stale live metrics cleared during render pause");
            File.AppendAllText(path, data.Substring(data.IndexOf('\n') + 1));
            Check(reader.Poll(path, now.AddSeconds(5)).Times.Length == 100, "live resumes with fresh frames after pause");
            File.AppendAllText(path, data.Substring(data.IndexOf('\n') + 1) + data.Substring(data.IndexOf('\n') + 1));
            Check(reader.Poll(path, now.AddSeconds(5.5)).Times.Length == 240, "live rolling history is bounded");
            byte[] bytes = File.ReadAllBytes(path); File.WriteAllText(path, "bad");
            Reject(delegate { reader.Poll(path, now); }, "truncated live file rejected");
            File.WriteAllBytes(path, bytes);
            Check(new BenchmarkLiveReader(42, "game.exe").Poll(path, now) != null, "new live session starts without old offset");
            File.WriteAllText(path, "Application,ProcessID,SwapChainAddress,MsBetweenPresents\nbad,row\n");
            Reject(delegate { new BenchmarkLiveReader(42, "game.exe").Poll(path, now); }, "malformed complete live row rejected");
        }
    }
}
