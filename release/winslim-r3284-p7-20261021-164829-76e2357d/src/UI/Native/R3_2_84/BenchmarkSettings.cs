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
                for (int i = 0; i < 3; i++) if (keys[i] != 0 && !_register(0x5710 + i, mods[i], keys[i])) throw new IOException("Atalho em uso ou indisponível: " + values[i] + ". Escolha outro ou deixe vazio.");
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
            int index = wp.ToInt32() - 0x5710;
            if (msg == 0x312 && index >= 0 && index < 3) { handled = true; _action(index); }
            return IntPtr.Zero;
        }
        public void Dispose() { for (int i = 0; i < 3; i++) _unregister(0x5710 + i); if (_source != null) _source.RemoveHook(Hook); }
    }
    internal static class BenchmarkSettings
    {
        internal static void Show(Window owner, BenchmarkOverlay overlay, BenchmarkHotkeys hotkeys)
        {
            var panel = new StackPanel { Margin = new Thickness(18) };
            var window = new Window { Owner = owner, Title = "Configurações do overlay · por jogo", Width = 490, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Background = new SolidColorBrush(Color.FromRgb(12,15,16)), Foreground = Brushes.White, Content = panel, ShowInTaskbar = false };
            panel.Children.Add(new TextBlock { Text = "Overlay · " + overlay.Title, FontSize = 18, Foreground = Brushes.DarkOrange, Margin = new Thickness(0,0,0,12) });
            panel.Children.Add(new TextBlock { Text = "Escala do painel e texto (75% a 175%)" });
            var scale = new Slider { Minimum = .75, Maximum = 1.75, Value = overlay.Preferences.PanelScale, TickFrequency = .05, IsSnapToTickEnabled = true }; panel.Children.Add(scale);
            panel.Children.Add(new TextBlock { Text = "Opacidade do fundo (35% a 100%)", Margin = new Thickness(0,10,0,0) });
            var opacity = new Slider { Minimum = .35, Maximum = 1, Value = overlay.Preferences.BackgroundOpacity, TickFrequency = .05, IsSnapToTickEnabled = true }; panel.Children.Add(opacity);
            var fps = new CheckBox { Content = "Primeiro indicador: FPS atual (desmarcado: médio)", IsChecked = overlay.Preferences.CurrentFps, Foreground = Brushes.White, Margin = new Thickness(0,14,0,0) }; panel.Children.Add(fps);
            var sensors = new CheckBox { Content = "Sensores opcionais: CPU, GPU, VRAM e RAM", IsChecked = overlay.Preferences.Sensors, Foreground = Brushes.White, Margin = new Thickness(0,10,0,0) }; panel.Children.Add(sensors);
            panel.Children.Add(new TextBlock { Text = "Leitura a cada 5 s. Temperaturas e VRAM indisponíveis sem provedor confiável. Nenhum driver é instalado.", TextWrapping = TextWrapping.Wrap, Foreground = Brushes.LightGray, Margin = new Thickness(0,6,0,12) });
            panel.Children.Add(new TextBlock { Text = "Atalhos globais · vazio desativa · exemplo Ctrl+Alt+F9", Foreground = Brushes.DarkOrange });
            string[] labels = { "Mostrar/ocultar overlay", "Iniciar/cancelar benchmark", "Alternar Mover/Travar" }, bindings = hotkeys == null ? new string[] { "", "", "" } : hotkeys.Bindings;
            var inputs = new TextBox[3];
            for (int i = 0; i < 3; i++) { panel.Children.Add(new TextBlock { Text = labels[i], Margin = new Thickness(0,8,0,3) }); inputs[i] = new TextBox { Text = bindings[i], Padding = new Thickness(6), Background = Brushes.Black, Foreground = Brushes.White }; panel.Children.Add(inputs[i]); }
            var status = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DarkOrange, Margin = new Thickness(0,10,0,6) }; panel.Children.Add(status);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal }; panel.Children.Add(buttons);
            var save = new Button { Content = "Salvar", Padding = new Thickness(18,7,18,7), Background = Brushes.DarkOrange }; buttons.Children.Add(save);
            var reset = new Button { Content = "Restaurar padrão", Margin = new Thickness(8,0,0,0), Padding = new Thickness(12,7,12,7) }; buttons.Children.Add(reset);
            save.Click += delegate {
                try {
                    if (hotkeys != null) hotkeys.Apply(inputs.Select(x => x.Text).ToArray());
                    overlay.Preferences.PanelScale = scale.Value; overlay.Preferences.BackgroundOpacity = opacity.Value; overlay.Preferences.CurrentFps = fps.IsChecked == true; overlay.Preferences.Sensors = sensors.IsChecked == true; overlay.ApplyPreferences();
                    status.Text = overlay.PreferencesSaved ? "Configuração aplicada e salva. Coleta preservada." : "Configuração aplicada, mas não foi possível salvar o perfil. Verifique a pasta de configurações.";
                } catch (Exception ex) { status.Text = ex.Message; }
            };
            reset.Click += delegate { overlay.ResetPreferences(); scale.Value = 1; opacity.Value = .93; fps.IsChecked = sensors.IsChecked = false; status.Text = "Padrão do jogo restaurado. Atalhos globais preservados."; };
            window.ShowDialog();
        }
    }
}
