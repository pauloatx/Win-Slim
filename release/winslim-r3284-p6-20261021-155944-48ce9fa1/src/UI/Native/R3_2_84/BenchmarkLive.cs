using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

namespace WinSlim.NativeUI
{
    // Preview only: never used as a completed capture, baseline or export.
    internal sealed class BenchmarkLiveSnapshot
    {
        internal double Fps, Low, Mean, P99;
        internal double[] Times;
        internal DateTime UpdatedUtc;
    }

    internal sealed class BenchmarkLiveReader
    {
        private readonly int _pid;
        private readonly string _application;
        private long _offset;
        private string _pending = "";
        private readonly Decoder _decoder = Encoding.UTF8.GetDecoder();
        private int _app = -1, _process = -1, _chain = -1, _ms = -1, _columns;
        private sealed class Stream
        {
            internal readonly Queue<double> Times = new Queue<double>();
            internal DateTime Updated;
        }
        private readonly Dictionary<string, Stream> _streams = new Dictionary<string, Stream>(StringComparer.Ordinal);
        internal BenchmarkLiveReader(int pid, string application) { _pid = pid; _application = application; }
        internal BenchmarkLiveSnapshot Poll(string path, DateTime now)
        {
            // PresentMon may not have created/flushed its file yet. Keep partial rows until newline.
            try {
                using (FileStream input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
                    if (input.Length < _offset) throw new InvalidDataException("Live CSV was truncated.");
                    input.Position = _offset;
                    byte[] bytes = new byte[65536];
                    int read, budget = 1048576;
                    while (budget > 0 && (read = input.Read(bytes, 0, Math.Min(bytes.Length, budget))) > 0) {
                        _offset += read; budget -= read;
                        char[] chars = new char[Encoding.UTF8.GetMaxCharCount(read)];
                        _pending += new string(chars, 0, _decoder.GetChars(bytes, 0, read, chars, 0, false));
                        int end;
                        while ((end = _pending.IndexOf('\n')) >= 0) {
                            string line = _pending.Substring(0, end).TrimEnd('\r');
                            _pending = _pending.Substring(end + 1);
                            Accept(line, now);
                        }
                        if (_pending.Length > 65536) throw new InvalidDataException("Live CSV row exceeds limit.");
                    }
                }
            } catch (FileNotFoundException) { return null; }
            catch (DirectoryNotFoundException) { return null; }
            Stream selected = _streams.Values.Where(s => (now - s.Updated).TotalSeconds <= 2)
                .OrderByDescending(s => s.Times.Count).FirstOrDefault();
            if (selected == null || selected.Times.Count < 30) return null;
            double[] times = selected.Times.ToArray(), sorted = times.OrderBy(x => x).ToArray();
            double mean = times.Average();
            return new BenchmarkLiveSnapshot { Fps = 1000 / mean, Low = 1000 / sorted.Skip(sorted.Length - Math.Max(1, (int)Math.Ceiling(sorted.Length * .01))).Average(),
                Mean = mean, P99 = sorted[(int)Math.Ceiling(sorted.Length * .99) - 1], Times = times, UpdatedUtc = selected.Updated };
        }
        private void Accept(string line, DateTime now)
        {
            if (String.IsNullOrWhiteSpace(line)) return;
            List<string> fields = PresentMonBenchmark.CsvFields(line.TrimStart('\uFEFF'));
            if (_columns == 0) {
                _columns = fields.Count;
                if (fields.Distinct(StringComparer.OrdinalIgnoreCase).Count() != fields.Count) throw new InvalidDataException("Duplicate live CSV columns.");
                _app = fields.FindIndex(x => x.Equals("Application", StringComparison.OrdinalIgnoreCase));
                _process = fields.FindIndex(x => x.Equals("ProcessID", StringComparison.OrdinalIgnoreCase));
                _chain = fields.FindIndex(x => x.Equals("SwapChainAddress", StringComparison.OrdinalIgnoreCase));
                _ms = fields.FindIndex(x => x.Equals("MsBetweenPresents", StringComparison.OrdinalIgnoreCase));
                if (_app < 0 || _process < 0 || _chain < 0 || _ms < 0) throw new InvalidDataException("Unsupported live CSV.");
                return;
            }
            if (fields.Count != _columns) throw new InvalidDataException("Malformed live CSV.");
            int pid; double ms;
            if (!Int32.TryParse(fields[_process], out pid) || pid != _pid || !String.Equals(fields[_app], _application, StringComparison.OrdinalIgnoreCase)) return;
            if (!Double.TryParse(fields[_ms], NumberStyles.Float, CultureInfo.InvariantCulture, out ms) || Double.IsNaN(ms) || Double.IsInfinity(ms) || ms <= 0 || ms > 120000) return;
            Stream stream;
            if (!_streams.TryGetValue(fields[_chain], out stream)) {
                if (_streams.Count >= 256) return;
                stream = new Stream(); _streams.Add(fields[_chain], stream);
            }
            // A long pause starts a fresh window rather than showing old frames as current.
            if ((now - stream.Updated).TotalSeconds > 2) stream.Times.Clear();
            stream.Times.Enqueue(ms); while (stream.Times.Count > 240) stream.Times.Dequeue();
            stream.Updated = now;
        }
    }
}
