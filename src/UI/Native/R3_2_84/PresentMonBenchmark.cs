using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace WinSlim.NativeUI
{
    internal sealed class BenchmarkResult
    {
        public string Application, SwapChain, CsvPath, Session, StartedUtc;
        public int ProcessId, Frames, InvalidFrames, RequestedSeconds;
        public double AverageFps, MeanFrameMs, P99FrameMs, OnePercentLowFps;
        public string Metric = "MsBetweenPresents";
        public string CollectorVersion = "unknown (imported CSV)";
        public bool Cancelled = false;
        public double[] FrameTimesMs;
        internal string Describe()
        {
            return String.Format(CultureInfo.InvariantCulture,
                "{0} / PID {1}\n{2} quadros / swap chain {3}\nFPS de apresentação: {4:F2}\nTempo médio por quadro: {5:F2} ms\nP99: {6:F2} ms\n1% low: {7:F2} FPS (média do 1% de intervalos mais lentos)\nIntervalos inválidos ignorados: {8}\nCSV: {9}",
                Application, ProcessId, Frames, SwapChain, AverageFps, MeanFrameMs, P99FrameMs, OnePercentLowFps, InvalidFrames, CsvPath);
        }
    }

    internal static class PresentMonBenchmark
    {
        internal const string BinaryHash = "b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af";
        internal static string Hash(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream input = File.OpenRead(path))
                return BitConverter.ToString(sha.ComputeHash(input)).Replace("-", "").ToLowerInvariant();
        }
        internal static string BinaryPath(string root)
        {
            return Path.Combine(root, "third_party", "PresentMon", "PresentMon-2.6.0-x64.exe");
        }
        internal static string VerifiedBinary(string root, string requested = null)
        {
            string official = Path.GetFullPath(BinaryPath(root));
            if (!Environment.Is64BitOperatingSystem ||
                (requested != null && !String.Equals(Path.GetFullPath(requested), official, StringComparison.OrdinalIgnoreCase)) ||
                !File.Exists(official) || Hash(official) != BinaryHash)
                throw new InvalidDataException("PresentMon oficial ausente, incompatível ou com hash diferente. Extraia novamente a candidata.");
            return official;
        }
        internal static Task<BenchmarkResult> CaptureAsync(string root, int pid, string application, int seconds, CancellationToken token, Action<BenchmarkLiveSnapshot> preview = null)
        {
            return Task.Run(async delegate {
                string binary = VerifiedBinary(root);
                PresentMonMonitor monitor = PresentMonMonitor.StartCore(root,binary,pid,application);
                try {
                    Task<BenchmarkResult> recording = monitor.RecordAsync(seconds,token);
                    return await ObserveRecording(recording, delegate { return monitor.Snapshot; }, preview).ConfigureAwait(false);
                } finally { monitor.StopAsync().GetAwaiter().GetResult(); }
            });
        }
        internal static async Task<BenchmarkResult> ObserveRecording(Task<BenchmarkResult> recording, Func<BenchmarkLiveSnapshot> snapshot, Action<BenchmarkLiveSnapshot> preview)
        {
            while (!recording.IsCompleted) {
                await Task.Delay(250).ConfigureAwait(false);
                if (preview != null) { try { preview(snapshot()); } catch { preview = null; } }
            }
            return await recording.ConfigureAwait(false);
        }
        private static string Quoted(string value)
        {
            if (value.IndexOfAny(new char[] { '"', '\r', '\n' }) >= 0 || value.EndsWith("\\", StringComparison.Ordinal))
                throw new ArgumentException("Caminho inválido para o coletor.");
            return "\"" + value + "\"";
        }
        internal static string CaptureArguments(int pid, int seconds, string csv, string session)
        {
            if (pid <= 0 || seconds < 10 || seconds > 120 || !session.StartsWith("WinSlim-", StringComparison.Ordinal) || session.Length != 40)
                throw new ArgumentException("PID, duração ou sessão inválidos.");
            Guid id;
            if (!Guid.TryParseExact(session.Substring(8), "N", out id)) throw new ArgumentException("Sessão inválida.");
            return "--process_id " + pid.ToString(CultureInfo.InvariantCulture) + " --timed " + seconds.ToString(CultureInfo.InvariantCulture)
                + " --terminate_after_timed --no_console_stats --v1_metrics --no_track_gpu --no_track_display --no_track_input --session_name " + session
                + " --output_file " + Quoted(csv);
        }
        internal static Process NewProcess(string binary, string arguments)
        {
            Process p = new Process();
            p.StartInfo = new ProcessStartInfo(binary, arguments) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
            return p;
        }
        internal static void StopSession(string binary, string session)
        {
            // Validate ownership before launching even the official stop command.
            CaptureArguments(1, 10, "unused.csv", session);
            if (!File.Exists(binary) || Hash(binary) != BinaryHash)
                throw new InvalidDataException("O coletor oficial mudou antes de encerrar a sessão.");
            using (Process stop = NewProcess(binary, "--session_name " + session + " --terminate_existing_session")) {
                if (!stop.Start()) throw new IOException("Não foi possível encerrar a sessão do benchmark.");
                Task<string> stdout = stop.StandardOutput.ReadToEndAsync();
                Task<string> stderr = stop.StandardError.ReadToEndAsync();
                if (!stop.WaitForExit(5000)) { stop.Kill(); stop.WaitForExit(); throw new TimeoutException("O coletor não encerrou a sessão no prazo."); }
                stdout.GetAwaiter().GetResult(); stderr.GetAwaiter().GetResult();
            }
        }
        // Legacy file capture, retained for source history. Every launch now requires the same official provider.
        internal static BenchmarkResult CaptureCore(string binary, string root, int pid, string application, int seconds, CancellationToken token, Action<BenchmarkLiveSnapshot> preview = null)
        {
            token.ThrowIfCancellationRequested();
            binary = VerifiedBinary(root, binary);
            string session = "WinSlim-" + Guid.NewGuid().ToString("N");
            string arguments;
            string directory = Path.Combine(root, "Benchmarks", DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N"));
            string csv = Path.Combine(directory, "frames.csv");
            arguments = CaptureArguments(pid, seconds, csv, session);
            Directory.CreateDirectory(directory);
            string started = DateTime.UtcNow.ToString("o");
            using (Process collector = NewProcess(binary, arguments)) {
                bool startedProcess = false;
                try {
                    if (!collector.Start()) throw new IOException("O PresentMon não iniciou.");
                    startedProcess = true;
                    Task<string> stdout = collector.StandardOutput.ReadToEndAsync();
                    Task<string> stderr = collector.StandardError.ReadToEndAsync();
                    Stopwatch clock = Stopwatch.StartNew();
                    BenchmarkLiveReader live = preview == null ? null : new BenchmarkLiveReader(pid, application);
                    double nextPreview = 0;
                    while (!collector.WaitForExit(100)) {
                        if (token.IsCancellationRequested || clock.Elapsed.TotalSeconds > seconds + 20) {
                            StopSession(binary, session);
                            if (!collector.WaitForExit(5000)) { collector.Kill(); collector.WaitForExit(); }
                            token.ThrowIfCancellationRequested();
                            throw new TimeoutException("Captura excedeu o prazo. Verifique as permissões de rastreamento ETW.");
                        }
                        if (live != null && clock.Elapsed.TotalSeconds >= nextPreview) {
                            nextPreview = clock.Elapsed.TotalSeconds + .25;
                            try { preview(live.Poll(csv, DateTime.UtcNow)); }
                            catch (Exception ex) {
                                // Preview failure cannot change the accepted result or the collector lifecycle.
                                live = null;
                                try { preview(null); File.WriteAllText(Path.Combine(directory, "live-preview.log"), ex.Message, Encoding.UTF8); } catch (Exception) { }
                            }
                        }
                    }
                    File.WriteAllText(Path.Combine(directory, "stdout.log"), stdout.GetAwaiter().GetResult(), Encoding.UTF8);
                    string errors = stderr.GetAwaiter().GetResult();
                    File.WriteAllText(Path.Combine(directory, "stderr.log"), errors, Encoding.UTF8);
                    token.ThrowIfCancellationRequested();
                    if (collector.ExitCode != 0) throw new IOException("PresentMon retornou " + collector.ExitCode + ". " + errors + " Consulte " + directory);
                    BenchmarkResult result = ReadCsv(csv, pid);
                    result.Session = session; result.StartedUtc = started; result.RequestedSeconds = seconds; result.CollectorVersion = "2.6.0";
                    if (!String.IsNullOrWhiteSpace(application) && !String.Equals(Path.GetFileName(result.Application), Path.GetFileName(application), StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("O nome do processo capturado difere do selecionado. Atualize a lista e selecione o jogo novamente.");
                    return result;
                } finally {
                    if (startedProcess && !collector.HasExited) {
                        try { StopSession(binary, session); } finally { if (!collector.WaitForExit(5000)) { collector.Kill(); collector.WaitForExit(); } }
                    }
                }
            }
        }
        internal static List<string> CsvFields(string line)
        {
            List<string> fields = new List<string>(); StringBuilder value = new StringBuilder(); bool quoted = false;
            for (int i = 0; i < line.Length; i++) {
                char c = line[i];
                if (c == '"') {
                    if (quoted && i + 1 < line.Length && line[i + 1] == '"') { value.Append('"'); i++; }
                    else quoted = !quoted;
                } else if (c == ',' && !quoted) { fields.Add(value.ToString()); value.Length = 0; }
                else value.Append(c);
            }
            if (quoted) throw new InvalidDataException("CSV truncado: aspas sem fechamento.");
            fields.Add(value.ToString()); return fields;
        }
        private sealed class StreamFrames
        {
            internal string Application, SwapChain;
            internal int ProcessId, Invalid;
            internal readonly List<double> Times = new List<double>();
        }
        internal static BenchmarkResult ReadCsv(string path, int requiredPid)
        {
            FileInfo info = new FileInfo(path);
            if (!info.Exists || info.Length == 0 || info.Length > 268435456) throw new InvalidDataException("CSV ausente, vazio ou maior que 256 MB.");
            Dictionary<string, StreamFrames> streams = new Dictionary<string, StreamFrames>(StringComparer.Ordinal);
            using (StreamReader reader = new StreamReader(path, Encoding.UTF8, true)) {
                string first = reader.ReadLine();
                if (first == null) throw new InvalidDataException("CSV vazio.");
                List<string> headers = CsvFields(first.TrimStart('\uFEFF'));
                if (headers.Distinct(StringComparer.OrdinalIgnoreCase).Count() != headers.Count) throw new InvalidDataException("CSV com colunas duplicadas.");
                int app = headers.FindIndex(x => x.Equals("Application", StringComparison.OrdinalIgnoreCase));
                int pid = headers.FindIndex(x => x.Equals("ProcessID", StringComparison.OrdinalIgnoreCase));
                int chain = headers.FindIndex(x => x.Equals("SwapChainAddress", StringComparison.OrdinalIgnoreCase));
                int ms = headers.FindIndex(x => x.Equals("MsBetweenPresents", StringComparison.OrdinalIgnoreCase));
                if (app < 0 || pid < 0 || chain < 0 || ms < 0) throw new InvalidDataException("CSV incompatível. Use a captura incorporada ou CSV PresentMon com --v1_metrics.");
                string line; int count = 0;
                while ((line = reader.ReadLine()) != null) {
                    if (String.IsNullOrWhiteSpace(line)) continue;
                    if (++count > 2000000) throw new InvalidDataException("CSV excede dois milhões de quadros.");
                    List<string> row = CsvFields(line);
                    if (row.Count != headers.Count) throw new InvalidDataException("CSV truncado ou com número incorreto de colunas.");
                    int process;
                    if (!Int32.TryParse(row[pid], NumberStyles.Integer, CultureInfo.InvariantCulture, out process) || process <= 0) throw new InvalidDataException("PID inválido no CSV.");
                    if (requiredPid > 0 && requiredPid != process) continue;
                    string key = process.ToString(CultureInfo.InvariantCulture) + "|" + row[chain];
                    StreamFrames stream;
                    if (!streams.TryGetValue(key, out stream)) {
                        if (streams.Count >= 256) throw new InvalidDataException("CSV contém mais de 256 fluxos de apresentação.");
                        stream = new StreamFrames { ProcessId = process, Application = row[app], SwapChain = row[chain] }; streams.Add(key, stream);
                    }
                    double time;
                    if (!Double.TryParse(row[ms], NumberStyles.Float, CultureInfo.InvariantCulture, out time) || Double.IsNaN(time) || Double.IsInfinity(time) || time <= 0 || time > 120000) { stream.Invalid++; continue; }
                    stream.Times.Add(time);
                }
            }
            StreamFrames selected = streams.Values.OrderByDescending(x => x.Times.Count).ThenBy(x => x.ProcessId).ThenBy(x => x.SwapChain, StringComparer.Ordinal).FirstOrDefault();
            if (selected == null || selected.Times.Count < 30) throw new InvalidDataException("Menos de 30 intervalos válidos. Mantenha o jogo renderizando durante a captura.");
            double[] timeline = BenchmarkChartSamples.Peaks(selected.Times);
            selected.Times.Sort();
            int n = selected.Times.Count; double mean = selected.Times.Average(); int slow = Math.Max(1, (int)Math.Ceiling(n * 0.01));
            return new BenchmarkResult { Application = selected.Application, ProcessId = selected.ProcessId, SwapChain = selected.SwapChain, Frames = n, InvalidFrames = selected.Invalid, MeanFrameMs = mean,
                AverageFps = 1000.0 / mean, P99FrameMs = selected.Times[(int)Math.Ceiling(n * 0.99) - 1], OnePercentLowFps = 1000.0 / selected.Times.Skip(n - slow).Average(), CsvPath = Path.GetFullPath(path), FrameTimesMs = timeline };
        }
        internal static double Compare(BenchmarkResult before, BenchmarkResult after)
        {
            if (before == null || after == null || before.Cancelled || after.Cancelled || before.RequestedSeconds < 10 || after.RequestedSeconds < 10 || before.Metric != after.Metric || before.RequestedSeconds != after.RequestedSeconds
                || !String.Equals(before.Application, after.Application, StringComparison.OrdinalIgnoreCase) || before.AverageFps <= 0)
                throw new InvalidOperationException("Compare capturas do mesmo aplicativo, duração e métrica, usando a mesma cena e configurações gráficas.");
            return (after.AverageFps / before.AverageFps - 1) * 100.0;
        }
    }
}
