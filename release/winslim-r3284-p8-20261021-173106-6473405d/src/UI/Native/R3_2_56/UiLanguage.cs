using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;

namespace WinSlim.NativeUI
{
    // Presentation-only translations. IDs, planner payloads, JSON exports and logs keep their source values.
    internal static class UiLanguage
    {
        private static string _root, _systemCulture;
        private static bool _english, _registered;
        private static Dictionary<string, string> _englishText;
        private static Dictionary<string, string> _fragments;
        private static Regex _fragmentPattern;
        private static readonly Dictionary<string, string> _cache = new Dictionary<string, string>(StringComparer.Ordinal);
        private static readonly ConditionalWeakTable<DependencyObject, TextState> _states = new ConditionalWeakTable<DependencyObject, TextState>();
        private sealed class TextState { public readonly Dictionary<DependencyProperty, string[]> Values = new Dictionary<DependencyProperty, string[]>(); }
        internal static string Mode { get; private set; }
        internal static string EffectiveLanguage { get { return _english ? "en" : "pt-BR"; } }
        internal static string Resolve(string mode, string culture)
        {
            if (mode == "en" || mode == "pt-BR") return mode;
            return !String.IsNullOrEmpty(culture) && culture.StartsWith("pt", StringComparison.OrdinalIgnoreCase) ? "pt-BR" : "en";
        }
        internal static void Initialize(string root, bool selfTest)
        {
            _root = root; _systemCulture = CultureInfo.CurrentUICulture.Name;
            JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = 4 * 1024 * 1024 };
            Dictionary<string, object> resource = json.DeserializeObject(File.ReadAllText(Path.Combine(root, "src", "UI", "Native", "R3_2_56", "Strings.en.json"), Encoding.UTF8)) as Dictionary<string, object>;
            if (resource == null) throw new InvalidDataException("Arquivo de idioma invalido.");
            _englishText = ReadMap(resource, "text"); _fragments = ReadMap(resource, "fragments");
            string pattern = "(?<![\\p{L}\\p{N}_])(?:" + String.Join("|", _fragments.Keys.OrderByDescending(k => k.Length).Select(Regex.Escape)) + ")(?![\\p{L}\\p{N}_])";
            _fragmentPattern = new Regex(pattern, RegexOptions.Compiled | RegexOptions.CultureInvariant);
            string choice = "auto";
            if (!selfTest) {
                try {
                    string file = Path.Combine(root, "config", "WinSlim-language.json");
                    if (File.Exists(file)) {
                        Dictionary<string, object> saved = json.DeserializeObject(File.ReadAllText(file, Encoding.UTF8)) as Dictionary<string, object>;
                        if (saved != null && saved.ContainsKey("language")) choice = Convert.ToString(saved["language"], CultureInfo.InvariantCulture);
                    }
                } catch { choice = "auto"; }
            }
            SetMode(selfTest ? "pt-BR" : choice, false);
            if (!_registered) {
                EventManager.RegisterClassHandler(typeof(FrameworkElement), FrameworkElement.LoadedEvent, new RoutedEventHandler(OnLoaded));
                _registered = true;
            }
        }
        private static Dictionary<string, string> ReadMap(Dictionary<string, object> source, string key)
        {
            Dictionary<string, object> raw = source[key] as Dictionary<string, object>;
            if (raw == null) throw new InvalidDataException("Mapa de idioma ausente: " + key);
            return raw.ToDictionary(p => p.Key, p => Convert.ToString(p.Value, CultureInfo.InvariantCulture), StringComparer.Ordinal);
        }
        internal static void SetMode(string mode, bool persist)
        {
            if (mode != "auto" && mode != "pt-BR" && mode != "en") mode = "auto";
            if (persist) {
                string dir = Path.Combine(_root, "config"); Directory.CreateDirectory(dir);
                string file = Path.Combine(dir, "WinSlim-language.json"), temp = file + "." + Guid.NewGuid().ToString("N") + ".tmp";
                try {
                    File.WriteAllText(temp, new JavaScriptSerializer().Serialize(new Dictionary<string, object> { { "schemaVersion", 1 }, { "language", mode } }), new UTF8Encoding(false));
                    if (File.Exists(file)) File.Replace(temp, file, null); else File.Move(temp, file);
                } finally { if (File.Exists(temp)) File.Delete(temp); }
            }
            Mode = mode; _english = Resolve(mode, _systemCulture) == "en";
        }
        internal static string Text(string value)
        {
            if (String.IsNullOrEmpty(value) || _englishText == null) return value;
            // Do not rewrite technical documents, logs, saved presets or user input.
            string trimmed = value.TrimStart();
            if (trimmed.StartsWith("{") || trimmed.StartsWith("[") || trimmed.StartsWith("\"") || value.Length > 8192) return value;
            string source = value;
            if (!_english) return source;
            string result;
            if (!_cache.TryGetValue(source, out result)) {
                if (!_englishText.TryGetValue(source, out result)) {
                    if (source.IndexOf('\n') >= 0) result = String.Join("\n", source.Split('\n').Select(Text));
                    else result = _fragmentPattern.Replace(source, m => _fragments[m.Value]);
                }
                if (_cache.Count < 2048) _cache[source] = result;
            }
            return result;
        }
        internal static object Content(object value) { string text = value as string; return text == null ? value : Text(text); }
        internal static void SetText(TextBlock target, string source) { SetDisplay(target, TextBlock.TextProperty, source); }
        internal static void SetContent(ContentControl target, string source) { SetDisplay(target, ContentControl.ContentProperty, source); }
        private static void SetDisplay(DependencyObject target, DependencyProperty property, string source)
        {
            if (target == null) return;
            string translated = Text(source ?? String.Empty);
            _states.GetValue(target, key => new TextState()).Values[property] = new string[] { source ?? String.Empty, translated };
            if (!Object.Equals(target.GetValue(property), translated)) target.SetCurrentValue(property, translated);
        }
        private static void OnLoaded(object sender, RoutedEventArgs e) { ApplyElement(sender as DependencyObject); }
        private static void ApplyProperty(DependencyObject target, DependencyProperty property)
        {
            string current = target.GetValue(property) as string;
            if (String.IsNullOrEmpty(current)) return;
            TextState state = _states.GetValue(target, key => new TextState()); string[] value;
            if (!state.Values.TryGetValue(property, out value) || current != value[1]) {
                value = new string[] { current, current }; state.Values[property] = value;
            }
            string next = Text(value[0]);
            if (current != next) target.SetCurrentValue(property, next);
            value[1] = next;
        }
        private static void ApplyElement(DependencyObject element)
        {
            if (element == null) return;
            if (element is TextBlock) ApplyProperty(element, TextBlock.TextProperty);
            TextBox report = element as TextBox;
            if (report != null && report.IsReadOnly && Object.Equals(report.Tag, "UiLocalizedReport")) ApplyProperty(report, TextBox.TextProperty);
            if (element is ContentControl) ApplyProperty(element, ContentControl.ContentProperty);
            if (element is HeaderedContentControl) ApplyProperty(element, HeaderedContentControl.HeaderProperty);
            if (element is FrameworkElement) {
                ApplyProperty(element, FrameworkElement.ToolTipProperty);
                DependencyObject tip = ((FrameworkElement)element).ToolTip as DependencyObject;
                if (tip != null) ApplyTree(tip);
            }
        }
        internal static void ApplyTree(DependencyObject root)
        {
            if (root == null) return;
            ApplyElement(root);
            foreach (object child in LogicalTreeHelper.GetChildren(root)) { DependencyObject item = child as DependencyObject; if (item != null) ApplyTree(item); }
        }
        internal static void SelfTest()
        {
            string previous = Mode;
            try {
                if (Resolve("auto", "pt-PT") != "pt-BR" || Resolve("auto", "pt-BR") != "pt-BR" || Resolve("auto", "en-US") != "en" || Resolve("auto", "de-DE") != "en" || Resolve("pt-BR", "en-US") != "pt-BR") throw new InvalidDataException("Deteccao de idioma invalida.");
                TextBlock label = new TextBlock { Text = "Configurações" }; ToggleButtonProbe(label);
                string raw = "{\"presetName\":\"Balanceado\",\"selectedIds\":[\"PERF-001\"]}";
                SetMode("en", false); if (Text(raw) != raw || Text("Desativado") != "Disabled" || Text("Ativado") != "Enabled") throw new InvalidDataException("Idioma alterou documento tecnico ou estado da chave.");
            } finally { SetMode(previous, false); }
        }
        private static void ToggleButtonProbe(TextBlock label)
        {
            SetMode("en", false); ApplyTree(label); if (label.Text != "Settings") throw new InvalidDataException("Traducao inglesa invalida.");
            SetMode("pt-BR", false); ApplyTree(label); if (label.Text != "Configurações") throw new InvalidDataException("Troca reversivel de idioma invalida.");
        }
    }
}
