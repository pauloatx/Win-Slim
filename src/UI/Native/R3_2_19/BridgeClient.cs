using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace WinSlim.NativeUI
{
    internal sealed class BridgeClient : IDisposable
    {
        private readonly string _rootPath;
        private readonly string _bridgeScript;
        private readonly JavaScriptSerializer _json;
        private readonly SemaphoreSlim _gate;
        private Process _process;
        private bool _disposed;

        public BridgeClient(string rootPath)
        {
            _rootPath = rootPath;
            _bridgeScript = Path.Combine(rootPath, "src", "UI", "Native", "R3_2_19", "WinSlim.UiBridge.ps1");
            _json = new JavaScriptSerializer();
            _json.MaxJsonLength = 16 * 1024 * 1024;
            _json.RecursionLimit = 128;
            _gate = new SemaphoreSlim(1, 1);
        }

        public bool IsRunning
        {
            get { return _process != null && !_process.HasExited; }
        }

        public void Start()
        {
            ThrowIfDisposed();
            if (IsRunning) return;
            if (!File.Exists(_bridgeScript))
                throw new FileNotFoundException("Bridge PowerShell não encontrado.", _bridgeScript);

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + _bridgeScript + "\" -Server -RootPath \"" + _rootPath + "\"";
            psi.WorkingDirectory = _rootPath;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = new UTF8Encoding(false);
            psi.StandardErrorEncoding = new UTF8Encoding(false);

            _process = new Process();
            _process.StartInfo = psi;
            _process.EnableRaisingEvents = true;
            if (!_process.Start())
                throw new InvalidOperationException("Não foi possível iniciar o bridge PowerShell.");
            _process.StandardInput.AutoFlush = true;
        }

        public async Task<Dictionary<string, object>> SendAsync(string action, IDictionary<string, object> payload, int timeoutMs)
        {
            ThrowIfDisposed();
            if (!IsRunning) Start();

            await _gate.WaitAsync().ConfigureAwait(false);
            try
            {
                if (!IsRunning)
                    throw new InvalidOperationException("Bridge PowerShell encerrou inesperadamente.");

                Dictionary<string, object> request = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                request["id"] = Guid.NewGuid().ToString("N");
                request["action"] = action;
                if (payload != null)
                {
                    foreach (KeyValuePair<string, object> pair in payload)
                        request[pair.Key] = pair.Value;
                }

                string line = _json.Serialize(request);
                await _process.StandardInput.WriteLineAsync(line).ConfigureAwait(false);
                await _process.StandardInput.FlushAsync().ConfigureAwait(false);

                Task<string> readTask = _process.StandardOutput.ReadLineAsync();
                Task delayTask = Task.Delay(timeoutMs);
                Task completed = await Task.WhenAny(readTask, delayTask).ConfigureAwait(false);
                if (completed != readTask)
                    throw new TimeoutException("Timeout aguardando resposta do bridge para '" + action + "'.");

                string responseLine = await readTask.ConfigureAwait(false);
                if (String.IsNullOrWhiteSpace(responseLine))
                {
                    string stderr = String.Empty;
                    try { stderr = await _process.StandardError.ReadToEndAsync().ConfigureAwait(false); } catch { }
                    throw new InvalidOperationException("Bridge retornou resposta vazia. " + stderr);
                }

                object parsed = _json.DeserializeObject(responseLine);
                Dictionary<string, object> envelope = parsed as Dictionary<string, object>;
                if (envelope == null)
                    throw new InvalidDataException("Envelope JSON inválido retornado pelo bridge.");

                object okObj;
                bool ok = envelope.TryGetValue("ok", out okObj) && Convert.ToBoolean(okObj);
                if (!ok)
                {
                    object errObj;
                    string error = envelope.TryGetValue("error", out errObj) && errObj != null ? Convert.ToString(errObj) : "Erro desconhecido no bridge.";
                    throw new InvalidOperationException(error);
                }

                object dataObj;
                if (!envelope.TryGetValue("data", out dataObj) || dataObj == null)
                    return new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

                Dictionary<string, object> data = dataObj as Dictionary<string, object>;
                if (data != null) return data;

                Dictionary<string, object> wrapper = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                wrapper["value"] = dataObj;
                return wrapper;
            }
            finally
            {
                _gate.Release();
            }
        }

        public Task<Dictionary<string, object>> SendAsync(string action, IDictionary<string, object> payload)
        {
            return SendAsync(action, payload, 15000);
        }

        private void ThrowIfDisposed()
        {
            if (_disposed) throw new ObjectDisposedException("BridgeClient");
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try
            {
                if (_process != null && !_process.HasExited)
                {
                    try { _process.StandardInput.Close(); } catch { }
                    if (!_process.WaitForExit(800))
                    {
                        try { _process.Kill(); } catch { }
                    }
                }
            }
            catch { }
            finally
            {
                if (_process != null) _process.Dispose();
                _gate.Dispose();
            }
        }
    }
}
