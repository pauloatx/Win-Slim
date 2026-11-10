using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace WinSlim.NativeUI
{
    internal static class BenchmarkSensorText
    {
        internal static string Format(Dictionary<string,object> data)
        {
            Func<string,double,double?> read=delegate(string key,double max){object value;double number;return data!=null&&data.TryGetValue(key,out value)&&value!=null&&Double.TryParse(Convert.ToString(value,System.Globalization.CultureInfo.InvariantCulture),System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out number)&&!Double.IsNaN(number)&&!Double.IsInfinity(number)&&number>=0&&number<=max?(double?)number:null;};
            Func<string,string> usage=delegate(string key){var n=read(key,100);return n.HasValue?n.Value.ToString("F0")+"%":"Uso indisponível";};
            Func<string,string> temperature=delegate(string key){var n=read(key,130);return n.HasValue?n.Value.ToString("F1")+" °C":"Temperatura indisponível";};
            var vram=read("VramMiB",1048576);
            return "CPU: "+usage("CPU")+" · "+temperature("CpuTemperature")+"\nGPU: "+usage("GPU")+" · "+temperature("GpuTemperature")+"\nVRAM do adaptador: "+(vram.HasValue?(vram.Value*1048576/1000000000).ToString("F2")+" GB":"Indisponível")+"\nRAM: "+usage("RAM");
        }
    }
    internal sealed class BenchmarkHotkeyException : IOException
    {
        internal int Index { get; private set; }
        internal BenchmarkHotkeyException(int index,string message):base(message){Index=index;}
    }
    internal sealed class BenchmarkHotkeys : IDisposable
    {
        [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
        [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr window, int id);
        private readonly IntPtr _handle;
        private readonly HwndSource _source;
        private readonly Action<int> _action;
        private readonly string _path;
        private readonly Func<int, uint, uint, bool> _register;
        private readonly Action<int> _unregister;
        private string[] _bindings = new string[3] { "", "", "" };
        private string[] _defaults = new string[3] { "", "", "" };
        internal bool Suspended;
        internal Action<string> Capture;
        internal string[] Bindings { get { return (string[])_bindings.Clone(); } }
        internal BenchmarkHotkeys(Window window, string root, Action<int> action)
        {
            _handle = new WindowInteropHelper(window).EnsureHandle(); _source = HwndSource.FromHwnd(_handle); _action = action;
            _register = delegate(int id, uint mod, uint key) { return RegisterHotKey(_handle, id, mod | 0x4000, key); };
            _unregister = delegate(int id) { UnregisterHotKey(_handle, id); };
            _source.AddHook(Hook); _path = Path.Combine(root, "config", "benchmark-hotkeys.json");
        }
        internal BenchmarkHotkeys(Func<int,uint,uint,bool> register, Action<int> unregister) { _register = register; _unregister = unregister; }
        internal void Load()
        {
            if (!File.Exists(_path)) return;
            if (new FileInfo(_path).Length > 4096) throw new InvalidDataException("Configuração de atalhos inválida.");
            Apply(new JavaScriptSerializer().Deserialize<string[]>(File.ReadAllText(_path, Encoding.UTF8)), false);
            _defaults=Bindings;
        }
        internal void ActivateGame(string[] values) {try{Apply(values??_defaults,false);}catch{Apply(new string[]{"","",""},false);throw;}}
        internal static string Combination(Key key,ModifierKeys modifiers)
        {
            string value=((modifiers&ModifierKeys.Control)!=0?"Ctrl+":"")+((modifiers&ModifierKeys.Alt)!=0?"Alt+":"")+((modifiers&ModifierKeys.Shift)!=0?"Shift+":"")+key;
            if((modifiers&ModifierKeys.Windows)!=0)throw new ArgumentException("Use Ctrl, Alt ou Shift com uma letra ou tecla F.");
            uint mod,virtualKey;Parse(value,out mod,out virtualKey);return value;
        }
        internal static void Parse(string text, out uint mod, out uint key)
        {
            mod = 0; key = 0; if (String.IsNullOrWhiteSpace(text)) return;
            string[] parts = text.Split('+').Select(p => p.Trim().ToUpperInvariant()).ToArray();
            if (parts.Length < 2 || parts.Distinct().Count() != parts.Length) throw new ArgumentException("Use Ctrl+Alt+F9, por exemplo; vazio desativa.");
            for (int i = 0; i < parts.Length - 1; i++) {
                switch (parts[i]) { case "CTRL": mod |= 2; break; case "ALT": mod |= 1; break; case "SHIFT": mod |= 4; break; default: throw new ArgumentException("Modificador inválido: " + parts[i]); }
            }
            Key parsed;
            if (!Enum.TryParse<Key>(parts[parts.Length - 1], true, out parsed) || !((parsed >= Key.A && parsed <= Key.Z) || (parsed >= Key.F1 && parsed <= Key.F24)) || parsed == Key.F12)
                throw new ArgumentException("Escolha uma letra ou F1–F24, exceto F12 reservado pelo Windows.");
            key = (uint)KeyInterop.VirtualKeyFromKey(parsed);
        }
        internal void Apply(string[] values, bool save = true)
        {
            if (values == null || values.Length != 3) throw new ArgumentException("Informe os três atalhos.");
            uint[] mods = new uint[3], keys = new uint[3];
            for (int i = 0; i < 3; i++) Parse(values[i], out mods[i], out keys[i]);
            for (int i = 0; i < 3; i++) for (int j = i + 1; j < 3; j++) if (keys[i] != 0 && keys[i] == keys[j] && mods[i] == mods[j]) throw new ArgumentException("Dois comandos usam o mesmo atalho.");
            for (int i = 0; i < 3; i++) _unregister(0x5710 + i);
            try {
                for (int i = 0; i < 3; i++) if (keys[i] != 0 && !_register(0x5710 + i, mods[i], keys[i])) throw new BenchmarkHotkeyException(i,"Atalho em uso ou indisponível. Escolha outra combinação ou use Limpar.");
                if (save && _path != null) {
                    Directory.CreateDirectory(Path.GetDirectoryName(_path));
                    string temp = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
                    try { File.WriteAllText(temp, new JavaScriptSerializer().Serialize(values), new UTF8Encoding(false)); if (File.Exists(_path)) File.Replace(temp, _path, null); else File.Move(temp, _path); }
                    finally { if (File.Exists(temp)) File.Delete(temp); }
                }
                _bindings = values.Select(v => v ?? "").ToArray();
            } catch {
                for (int i = 0; i < 3; i++) _unregister(0x5710 + i);
                for (int i = 0; i < 3; i++) { uint m,k; Parse(_bindings[i], out m, out k); if (k != 0 && !_register(0x5710 + i,m,k)) _bindings[i] = ""; }
                throw;
            }
        }
        private IntPtr Hook(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled)
        {
            if (msg != 0x312) return IntPtr.Zero;
            long id = wp.ToInt64();
            if (id >= 0x5710 && id <= 0x5712) { handled = true; Dispatch((int)(id - 0x5710)); }
            return IntPtr.Zero;
        }
        internal void Dispatch(int index) { if(Suspended){if(Capture!=null)Capture(_bindings[index]);}else if(_action!=null)_action(index); }
        public void Dispose() { for (int i = 0; i < 3; i++) _unregister(0x5710 + i); if (_source != null) _source.RemoveHook(Hook); }
    }
}
