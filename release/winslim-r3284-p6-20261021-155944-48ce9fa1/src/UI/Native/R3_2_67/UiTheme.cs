using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace WinSlim.NativeUI
{
    internal static class UiTheme
    {
        private static Application _app;
        private static string _root;
        private static Dictionary<string, object> _light;
        private static readonly Dictionary<string, SolidColorBrush> _brushes = new Dictionary<string, SolidColorBrush>(StringComparer.OrdinalIgnoreCase);
        private static bool _listening, _disposed;
        internal static string Mode { get; private set; }
        internal static bool IsLight { get; private set; }
        internal static int SharedBrushCount { get { return _brushes.Count; } }
        internal static event Action Changed;
        internal static bool Resolve(string mode, bool systemLight) { return mode == "light" || (mode == "auto" && systemLight); }
        private static bool SystemLight()
        {
            try { return Convert.ToInt32(Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1)) != 0; }
            catch { return false; }
        }
        internal static void Initialize(string root, Application app, bool selfTest)
        {
            _root = root; _app = app; _disposed = false;
            JavaScriptSerializer serializer = new JavaScriptSerializer { MaxJsonLength = 1024 * 1024 };
            Dictionary<string, object> resource = serializer.DeserializeObject(File.ReadAllText(Path.Combine(root, "src", "UI", "Native", "R3_2_67", "Theme.palette.json"), Encoding.UTF8)) as Dictionary<string, object>;
            if (resource == null || !resource.ContainsKey("light")) throw new InvalidDataException("Paleta de tema ausente.");
            _light = resource["light"] as Dictionary<string, object>;
            if (_light == null) throw new InvalidDataException("Paleta de tema invalida.");
            string mode = "auto";
            if (!selfTest) {
                try {
                    string file = Path.Combine(root, "config", "WinSlim-theme.json");
                    if (File.Exists(file)) {
                        Dictionary<string, object> data = serializer.DeserializeObject(File.ReadAllText(file, Encoding.UTF8)) as Dictionary<string, object>;
                        if (data != null && data.ContainsKey("theme")) mode = Convert.ToString(data["theme"]);
                    }
                } catch { mode = "auto"; }
            }
            SetMode(selfTest ? "dark" : mode, false);
            if (!_listening) { SystemEvents.UserPreferenceChanged += OnSystemPreference; _listening = true; }
        }
        internal static Color Color(string original)
        {
            object mapped;
            string hex = IsLight && _light != null && _light.TryGetValue(original, out mapped) ? Convert.ToString(mapped) : original;
            return (Color)ColorConverter.ConvertFromString(hex);
        }
        internal static Brush Brush(string original)
        {
            SolidColorBrush brush;
            if (!_brushes.TryGetValue(original, out brush)) { brush = new SolidColorBrush(Color(original)); _brushes.Add(original, brush); }
            return brush;
        }
        internal static void SetMode(string mode, bool persist)
        {
            if (mode != "auto" && mode != "dark" && mode != "light") mode = "auto";
            if (persist) {
                string dir = Path.Combine(_root, "config"); Directory.CreateDirectory(dir);
                string file = Path.Combine(dir, "WinSlim-theme.json"), temp = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
                try {
                    File.WriteAllText(temp, new JavaScriptSerializer().Serialize(new Dictionary<string, object> { { "schemaVersion", 1 }, { "theme", mode } }), new UTF8Encoding(false));
                    if (File.Exists(file)) File.Replace(temp, file, null); else File.Move(temp, file);
                } finally { if (File.Exists(temp)) File.Delete(temp); }
            }
            Mode = mode;
            Apply(Resolve(mode, SystemLight()));
        }
        private static void Apply(bool light)
        {
            IsLight = light;
            // DynamicResource updates template triggers and cached pages without rebuilding controls.
            foreach (string original in _light.Keys) {
                Color color = Color(original);
                SolidColorBrush brush = new SolidColorBrush(color); brush.Freeze();
                _app.Resources["ThemeBrush_" + original.Substring(1)] = brush;
                _app.Resources["ThemeColor_" + original.Substring(1)] = color;
            }
            SolidColorBrush accent = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#FF7A00")); accent.Freeze();
            _app.Resources["ThemeAccent"] = accent;
            SolidColorBrush tintText = new SolidColorBrush((Color)ColorConverter.ConvertFromString(IsLight ? "#17212F" : "#FFFFFF")); tintText.Freeze();
            _app.Resources["ThemeTintText"] = tintText;
            // Programmatic rows/reports share these brushes. They update in place too.
            foreach (KeyValuePair<string, SolidColorBrush> pair in _brushes) { if (!pair.Value.IsFrozen) pair.Value.Color = Color(pair.Key); }
            Action changed = Changed; if (changed != null) changed();
        }
        private static void OnSystemPreference(object sender, UserPreferenceChangedEventArgs e)
        {
            if (_disposed || _app == null || _app.Dispatcher.HasShutdownStarted) return;
            _app.Dispatcher.BeginInvoke(new Action(delegate { if (!_disposed && Mode == "auto") { bool light = SystemLight(); if (light != IsLight) Apply(light); } }));
        }
        private static double Luminance(Color c)
        {
            double[] values = { c.R / 255.0, c.G / 255.0, c.B / 255.0 };
            for (int i = 0; i < values.Length; i++) values[i] = values[i] <= 0.04045 ? values[i] / 12.92 : Math.Pow((values[i] + 0.055) / 1.055, 2.4);
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722;
        }
        internal static void SelfTest()
        {
            string previous = Mode;
            try {
                if (!Resolve("auto", true) || Resolve("auto", false) || Resolve("dark", true) || !Resolve("light", false)) throw new InvalidDataException("Deteccao de tema invalida.");
                Brush shared = Brush("#080808");
                Brush sharedAccent = Brush("#FF7A00");
                if (shared.IsFrozen || sharedAccent.IsFrozen || !shared.CheckAccess()) throw new InvalidDataException("Pinceis de controles dinamicos precisam permitir atualizacao na thread da UI.");
                SetMode("light", false);
                foreach (string text in new string[] { "#F5F5F5", "#A9AFB8", "#00C853", "#FF1744", "#FFC107", "#FF9A2E" }) {
                    double ratio = (1.05) / (Luminance(Color(text)) + 0.05);
                    if (ratio < 4.5) throw new InvalidDataException("Contraste insuficiente no tema claro: " + text);
                }
                if (!Object.ReferenceEquals(shared, Brush("#080808")) || ((SolidColorBrush)shared).Color != Color("#080808")) throw new InvalidDataException("Tema deve atualizar pinceis existentes.");
                if (!Object.ReferenceEquals(sharedAccent, Brush("#FF7A00")) || ((SolidColorBrush)sharedAccent).Color != Color("#FF7A00")) throw new InvalidDataException("Destaque deve atualizar sem alocar novo pincel.");
                SolidColorBrush resource = _app.Resources["ThemeBrush_080808"] as SolidColorBrush;
                if (resource == null || !resource.IsFrozen || resource.Color != Color("#080808")) throw new InvalidDataException("Recursos de templates devem permanecer congelados e usar a paleta atual.");
                Color tintText = ((SolidColorBrush)_app.Resources["ThemeTintText"]).Color;
                foreach (string background in new string[] { "#4A2407", "#18130F", "#171717", "#3A1E0B" }) {
                    double ratio = (Luminance(Color(background)) + 0.05) / (Luminance(tintText) + 0.05);
                    if (ratio < 4.5) throw new InvalidDataException("Texto selecionado/hover sem contraste no tema claro: " + background);
                }
                SetMode("dark", false);
                if (((SolidColorBrush)_app.Resources["ThemeTintText"]).Color != Colors.White) throw new InvalidDataException("Texto selecionado original deve permanecer branco no modo escuro.");
                if (!Object.ReferenceEquals(shared, Brush("#080808")) || ((SolidColorBrush)shared).Color != Color("#080808")) throw new InvalidDataException("Pincel deve restaurar o tema escuro sem substituicao.");
                if (Color("#080808") != (Color)ColorConverter.ConvertFromString("#080808")) throw new InvalidDataException("Tema escuro original deve ser preservado.");
            } finally { SetMode(previous, false); }
        }
        internal static void Dispose()
        {
            _disposed = true;
            if (_listening) { SystemEvents.UserPreferenceChanged -= OnSystemPreference; _listening = false; }
            Changed = null;
        }
    }
}
