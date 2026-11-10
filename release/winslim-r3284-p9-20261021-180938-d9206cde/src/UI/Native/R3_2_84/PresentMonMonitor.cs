using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace WinSlim.NativeUI
{
    // One owned ETW session. Stdout is flushed by PresentMon 2.6.0 for each row;
    // output_file is deliberately absent (it takes precedence over output_stdout).
    internal sealed class PresentMonMonitor
    {
        private readonly object _sync = new object();
        private readonly CancellationTokenSource _stop = new CancellationTokenSource();
        private readonly BenchmarkLiveReader _reader;
        private readonly string _root, _binary, _application;
        private readonly int _pid;
        private Recorder _recorder;
        private bool _ended;
        private int _stopRequested;
        private string _error;
        private sealed class Recorder
        {
            internal readonly List<string> Rows = new List<string>();
            internal long Bytes;
            internal Exception Error;
        }
        internal readonly string Session = "WinSlim-" + Guid.NewGuid().ToString("N");
        internal Task Completion { get; private set; }
        internal bool Running { get { lock (_sync) return !_ended; } }
        internal int BufferedCount { get { lock (_sync) return _reader.BufferedCount; } }
        internal string Error { get { lock (_sync) return _error; } }
        internal string State { get { lock (_sync) return _ended ? "Coleta interrompida" : _reader.Snapshot(DateTime.UtcNow) != null ? "Ao vivo · janela móvel" : _everSample ? "Dados desatualizados · aguardando quadros" : "Coletando amostras"; } }
        private bool _everSample;
        internal BenchmarkLiveSnapshot Snapshot { get { lock (_sync) { if (_ended) return null; var value = _reader.Snapshot(DateTime.UtcNow); if (value != null) _everSample = true; return value; } } }
        private PresentMonMonitor(string root, string binary, int pid, string application)
        {
            if (pid <= 0 || String.IsNullOrWhiteSpace(application)) throw new ArgumentException("Jogo inválido.");
            _root = root; _binary = binary; _pid = pid; _application = application;
            _reader = new BenchmarkLiveReader(pid, application, true);
            _reader.RowAccepted = delegate(string row) {
                if (_recorder == null || _recorder.Error != null) return;
                _recorder.Bytes += row.Length * 2L;
                if (_recorder.Rows.Count >= 2000000 || _recorder.Bytes > 134217728) { _recorder.Error = new InvalidDataException("Benchmark excedeu o limite de memória; monitoramento preservado."); return; }
                _recorder.Rows.Add(row);
            };
        }
        internal static Task<PresentMonMonitor> StartAsync(string root, int pid, string application)
        {
            return Task.Run(delegate {
                string binary = PresentMonBenchmark.BinaryPath(root);
                if (!Environment.Is64BitOperatingSystem || !File.Exists(binary) || PresentMonBenchmark.Hash(binary) != PresentMonBenchmark.BinaryHash)
                    throw new InvalidDataException("PresentMon oficial ausente, incompatível ou com hash diferente. Extraia novamente a candidata.");
                return StartCore(root, binary, pid, application);
            });
        }
        // Disposable fake process injection; never used by the production entry.
        internal static PresentMonMonitor StartCore(string root, string binary, int pid, string application)
        {
            var monitor = new PresentMonMonitor(root, binary, pid, application);
            monitor.Completion = Task.Run((Action)monitor.Run);
            return monitor;
        }
        internal static string Arguments(int pid, string session)
        {
            PresentMonBenchmark.CaptureArguments(pid, 10, "unused.csv", session); // same validation/ownership contract
            return "--process_id " + pid.ToString(CultureInfo.InvariantCulture) + " --output_stdout --no_console_stats --v1_metrics --no_track_gpu --no_track_display --no_track_input --session_name " + session;
        }
        private void Run()
        {
            using (Process process = PresentMonBenchmark.NewProcess(_binary, Arguments(_pid, Session))) {
                bool started = false;
                try {
                    if (_stop.IsCancellationRequested) return;
                    if (!process.Start()) throw new IOException("PresentMon não iniciou.");
                    started = true;
                    Task input = Task.Run(async delegate {
                        char[] chunk = new char[4096]; StringBuilder pending = new StringBuilder(); int count;
                        while ((count = await process.StandardOutput.ReadAsync(chunk, 0, chunk.Length).ConfigureAwait(false)) > 0) {
                            for (int i = 0; i < count; i++) {
                                if (chunk[i] == '\n') {
                                    string line = pending.ToString().TrimEnd('\r'); pending.Clear();
                                    lock (_sync) _reader.Accept(line, DateTime.UtcNow);
                                } else { pending.Append(chunk[i]); if (pending.Length > 65536) throw new InvalidDataException("Linha do coletor excede 64 KB."); }
                            }
                        }
                        if (pending.Length > 0) throw new InvalidDataException("Fluxo do coletor truncado.");
                    });
                    string errors = "";
                    Task stderr = Task.Run(async delegate {
                        char[] data = new char[1024]; int count;
                        while ((count = await process.StandardError.ReadAsync(data, 0, data.Length).ConfigureAwait(false)) > 0) {
                            if (errors.Length < 4096) errors += new string(data, 0, Math.Min(count, 4096 - errors.Length));
                        }
                    });
                    while (!process.WaitForExit(100)) {
                        if (_stop.IsCancellationRequested) break;
                        if (input.IsFaulted) input.GetAwaiter().GetResult();
                    }
                    if (_stop.IsCancellationRequested && !process.HasExited) {
                        PresentMonBenchmark.StopSession(_binary, Session);
                        if (!process.WaitForExit(3000)) { process.Kill(); process.WaitForExit(); }
                    }
                    input.GetAwaiter().GetResult(); stderr.GetAwaiter().GetResult();
                    if (!_stop.IsCancellationRequested) throw new IOException("PresentMon encerrou (" + process.ExitCode + "). " + errors);
                } catch (Exception ex) { lock (_sync) _error = ex.Message; }
                finally {
                    try {
                        if (started && !process.HasExited) {
                            try { PresentMonBenchmark.StopSession(_binary, Session); }
                            finally { if (!process.WaitForExit(3000)) { process.Kill(); process.WaitForExit(); } }
                        }
                    } catch (Exception ex) { lock (_sync) _error = ex.Message; }
                    lock (_sync) { _ended = true; if (_recorder != null) _recorder.Error = new IOException(_error ?? "Coleta encerrada durante o benchmark."); }
                }
            }
        }
        internal async Task StopAsync() { bool first = Interlocked.Exchange(ref _stopRequested,1) == 0; if (first) _stop.Cancel(); await Completion.ConfigureAwait(false); if (first) _stop.Dispose(); }
        internal async Task<BenchmarkResult> RecordAsync(int seconds, CancellationToken token)
        {
            if (seconds < 10 || seconds > 120) throw new ArgumentOutOfRangeException("seconds");
            token.ThrowIfCancellationRequested();
            Recorder capture = new Recorder(); string started = DateTime.UtcNow.ToString("o"), header;
            lock (_sync) { if (_ended || _recorder != null) throw new InvalidOperationException("Coleta indisponível ou benchmark já ativo."); _recorder = capture; }
            try {
                Stopwatch clock = Stopwatch.StartNew();
                while (clock.Elapsed.TotalSeconds < seconds) {
                    await Task.Delay(100, token).ConfigureAwait(false);
                    lock (_sync) { if (capture.Error != null) throw capture.Error; }
                }
                token.ThrowIfCancellationRequested();
                lock (_sync) { _recorder = null; header = _reader.Header; if (capture.Error != null) throw capture.Error; }
                return await Task.Run(delegate {
                    token.ThrowIfCancellationRequested();
                    if (header == null || capture.Rows.Count < 30) throw new InvalidDataException("Menos de 30 intervalos válidos. Mantenha o jogo renderizando.");
                    string directory = Path.Combine(_root, "Benchmarks", DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N"));
                    Directory.CreateDirectory(directory); string csv = Path.Combine(directory, "frames.csv");
                    using (var writer = new StreamWriter(csv, false, new UTF8Encoding(false))) { writer.WriteLine(header); foreach (string row in capture.Rows) { token.ThrowIfCancellationRequested(); writer.WriteLine(row); } }
                    token.ThrowIfCancellationRequested();
                    BenchmarkResult result = PresentMonBenchmark.ReadCsv(csv, _pid);
                    result.RequestedSeconds = seconds; result.StartedUtc = started; result.Session = Session; result.CollectorVersion = "2.6.0";
                    token.ThrowIfCancellationRequested(); return result;
                }, token).ConfigureAwait(false);
            } finally { lock (_sync) if (Object.ReferenceEquals(_recorder, capture)) _recorder = null; }
        }
    }
}
