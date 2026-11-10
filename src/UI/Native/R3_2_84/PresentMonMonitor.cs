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
    // Tests exercise lifecycle/data with in-process streams; no substitute collector executable.
    internal interface IPresentMonTransport : IDisposable
    {
        TextReader Output { get; }
        TextReader Errors { get; }
        bool Start();
        bool WaitForExit(int milliseconds);
        bool HasExited { get; }
        int ExitCode { get; }
        void StopOwnedSession();
        void KillOwnedProcess();
    }
    internal sealed class OfficialPresentMonTransport : IPresentMonTransport
    {
        private readonly Process _process;
        private readonly string _binary, _session;
        internal OfficialPresentMonTransport(string binary, int pid, string session)
        {
            _binary = binary; _session = session;
            _process = PresentMonBenchmark.NewProcess(binary, PresentMonMonitor.Arguments(pid, session));
        }
        public TextReader Output { get { return _process.StandardOutput; } }
        public TextReader Errors { get { return _process.StandardError; } }
        public bool Start() { return _process.Start(); }
        public bool WaitForExit(int milliseconds) { return _process.WaitForExit(milliseconds); }
        public bool HasExited { get { return _process.HasExited; } }
        public int ExitCode { get { return _process.ExitCode; } }
        public void StopOwnedSession() { PresentMonBenchmark.StopSession(_binary, _session); }
        public void KillOwnedProcess() { _process.Kill(); _process.WaitForExit(); }
        public void Dispose() { _process.Dispose(); }
    }
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
                string binary = PresentMonBenchmark.VerifiedBinary(root);
                return StartCore(root, binary, pid, application);
            });
        }
        // All process-based entry points require the pinned official provider, including internal callers.
        internal static PresentMonMonitor StartCore(string root, string binary, int pid, string application)
        {
            binary = PresentMonBenchmark.VerifiedBinary(root, binary);
            var monitor = new PresentMonMonitor(root, binary, pid, application);
            monitor.Completion = Task.Run((Action)monitor.Run);
            return monitor;
        }
        // Data ingestion is independent of process creation. Deterministic fixtures feed rows here only.
        internal void AcceptFrameLine(string line, DateTime now)
        {
            lock (_sync) { if (!_ended) _reader.Accept(line, now); }
        }
        internal void EndFrameStream(string error)
        {
            lock (_sync) {
                _error = error; _ended = true;
                if (_recorder != null) _recorder.Error = new IOException(error ?? "Coleta encerrada durante o benchmark.");
            }
        }
        internal async Task ReadFrameStreamAsync(TextReader output)
        {
            char[] chunk = new char[4096]; StringBuilder pending = new StringBuilder(); int count;
            while ((count = await output.ReadAsync(chunk, 0, chunk.Length).ConfigureAwait(false)) > 0) {
                for (int i = 0; i < count; i++) {
                    if (chunk[i] == '\n') {
                        string line = pending.ToString().TrimEnd('\r'); pending.Clear();
                        AcceptFrameLine(line, DateTime.UtcNow);
                    } else { pending.Append(chunk[i]); if (pending.Length > 65536) throw new InvalidDataException("Linha do coletor excede 64 KB."); }
                }
            }
            if (pending.Length > 0) throw new InvalidDataException("Fluxo do coletor truncado.");
        }
        internal static async Task<string> ReadErrorStreamAsync(TextReader error)
        {
            string errors = ""; char[] data = new char[1024]; int count;
            while ((count = await error.ReadAsync(data, 0, data.Length).ConfigureAwait(false)) > 0) {
                if (errors.Length < 4096) errors += new string(data, 0, Math.Min(count, 4096 - errors.Length));
            }
            return errors;
        }
        internal static string Arguments(int pid, string session)
        {
            PresentMonBenchmark.CaptureArguments(pid, 10, "unused.csv", session); // same validation/ownership contract
            return "--process_id " + pid.ToString(CultureInfo.InvariantCulture) + " --output_stdout --no_console_stats --v1_metrics --no_track_gpu --no_track_display --no_track_input --session_name " + session;
        }
        private void Run()
        {
            using (var transport = new OfficialPresentMonTransport(_binary, _pid, Session)) RunTransport(transport);
        }
        internal void RunTransport(IPresentMonTransport transport)
        {
                bool started = false;
                try {
                    if (_stop.IsCancellationRequested) return;
                    if (!transport.Start()) throw new IOException("PresentMon não iniciou.");
                    started = true;
                    Task input = Task.Run(async delegate { await ReadFrameStreamAsync(transport.Output).ConfigureAwait(false); });
                    Task<string> stderr = Task.Run(async delegate { return await ReadErrorStreamAsync(transport.Errors).ConfigureAwait(false); });
                    while (!transport.WaitForExit(100)) {
                        if (_stop.IsCancellationRequested) break;
                        if (input.IsFaulted) input.GetAwaiter().GetResult();
                        if (stderr.IsFaulted) stderr.GetAwaiter().GetResult();
                        if (input.IsCompleted) throw new IOException("Fluxo stdout encerrado antes do processo coletor.");
                    }
                    if (_stop.IsCancellationRequested && !transport.HasExited) {
                        transport.StopOwnedSession();
                        if (!transport.WaitForExit(3000)) transport.KillOwnedProcess();
                    }
                    input.GetAwaiter().GetResult(); string errors = stderr.GetAwaiter().GetResult();
                    if (!_stop.IsCancellationRequested) throw new IOException("PresentMon encerrou (" + transport.ExitCode + "). " + errors);
                } catch (Exception ex) { lock (_sync) _error = ex.Message; }
                finally {
                    try {
                        if (started && !transport.HasExited) {
                            try { transport.StopOwnedSession(); }
                            finally { if (!transport.WaitForExit(3000)) transport.KillOwnedProcess(); }
                        }
                    } catch (Exception ex) { lock (_sync) _error = ex.Message; }
                    EndFrameStream(_error);
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
