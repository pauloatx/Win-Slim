using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shell;
using System.Windows.Threading;

namespace WinSlim.NativeUI
{
    internal sealed class MainWindowController : IDisposable
    {
        private readonly Window _window;
        private readonly string _rootPath;
        private readonly string _logPath;
        private readonly BridgeClient _bridge;
        private readonly Dictionary<string, FrameworkElement> _pages;
        private readonly Dictionary<string, Button> _navButtons;
        private readonly Dictionary<string, ToggleButton> _overlayButtons;
        private readonly HashSet<string> _highRiskProfiles;
        private readonly DispatcherTimer _performanceTimer;
        private string _currentPage;
        private string _selectedPreset;
        private bool _allowHighRisk;
        private bool _performanceBusy;
        private bool _disposed;
        private int _resolveVersion;

        public MainWindowController(Window window, string rootPath, string logPath)
        {
            _window = window;
            _rootPath = rootPath;
            _logPath = logPath;
            _bridge = new BridgeClient(rootPath);
            _pages = new Dictionary<string, FrameworkElement>(StringComparer.OrdinalIgnoreCase);
            _navButtons = new Dictionary<string, Button>(StringComparer.OrdinalIgnoreCase);
            _overlayButtons = new Dictionary<string, ToggleButton>(StringComparer.OrdinalIgnoreCase);
            _highRiskProfiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            _highRiskProfiles.Add("HW-CS2-P-CORES");
            _highRiskProfiles.Add("HW-GPU-IRQ-AFFINITY");
            _performanceTimer = new DispatcherTimer(DispatcherPriority.Background);
            _performanceTimer.Interval = TimeSpan.FromSeconds(3);
            _selectedPreset = "Balanceado";
            _currentPage = String.Empty;
        }

        public void Initialize()
        {
            TextOptions.SetTextFormattingMode(_window, TextFormattingMode.Display);
            TextOptions.SetTextRenderingMode(_window, TextRenderingMode.Auto);
            _window.Opacity = 0.0;

            WindowChrome chrome = new WindowChrome();
            chrome.CaptionHeight = 0;
            chrome.ResizeBorderThickness = new Thickness(6);
            chrome.GlassFrameThickness = new Thickness(0);
            chrome.CornerRadius = new CornerRadius(0);
            chrome.UseAeroCaptionButtons = false;
            WindowChrome.SetWindowChrome(_window, chrome);

            CachePagesAndNavigation();
            CacheOverlayButtons();
            WireWindowChrome();
            WireNavigation();
            WirePresetInteractions();
            WirePrototypeFlow();

            _performanceTimer.Tick += async delegate { await RefreshPerformanceAsync(); };
            _window.SourceInitialized += delegate { TryEnableDwmVisuals(); };
            _window.Loaded += async delegate
            {
                FadeInWindow();
                Navigate("Presets", true);
                SelectPreset("Balanceado", false);
                await InitializeBridgeAsync();
            };
            _window.Closed += delegate { Dispose(); };
        }

        private void CachePagesAndNavigation()
        {
            AddPage("Dashboard", "PageDashboard");
            AddPage("Presets", "PagePresets");
            AddPage("Preview", "PagePreview");
            AddPage("Apply", "PageApply");
            AddPage("Result", "PageResult");
            AddPage("Backup", "PageBackup");
            AddPage("Custom", "PageCustom");
            AddPage("TweakDetail", "PageTweakDetail");
            AddPage("Analysis", "PageAnalysis");
            AddPage("Settings", "PageSettings");
            AddPage("About", "PageAbout");

            AddNav("Dashboard", "NavInicio");
            AddNav("Presets", "NavPresets");
            AddNav("Custom", "NavPersonalizado");
            AddNav("Backup", "NavBackup");
            AddNav("Analysis", "NavAnalise");
            AddNav("Settings", "NavConfiguracoes");
            AddNav("About", "NavSobre");
        }

        private void AddPage(string key, string controlName)
        {
            FrameworkElement element = Find<FrameworkElement>(controlName);
            if (element == null) throw new InvalidOperationException("Página XAML ausente: " + controlName);
            _pages[key] = element;
        }

        private void AddNav(string pageKey, string controlName)
        {
            Button button = Find<Button>(controlName);
            if (button == null) throw new InvalidOperationException("Navegação XAML ausente: " + controlName);
            _navButtons[pageKey] = button;
        }

        private void CacheOverlayButtons()
        {
            string[] names = new string[]
            {
                "OverlayHags", "OverlayMsiGpu", "OverlayCoreParking", "OverlayGpuIrq",
                "OverlayCs2PCores", "OverlayValorant", "OverlayCs2", "OverlayApex",
                "OverlayFortnite", "OverlayGtav", "OverlayFso", "OverlayStreaming",
                "OverlayVideo", "OverlayDesign", "OverlayProgramming", "OverlayDefenderDev"
            };
            foreach (string name in names)
            {
                ToggleButton button = Find<ToggleButton>(name);
                if (button == null) throw new InvalidOperationException("Overlay XAML ausente: " + name);
                string profile = Convert.ToString(button.Tag, CultureInfo.InvariantCulture);
                if (String.IsNullOrWhiteSpace(profile)) throw new InvalidOperationException("Overlay sem Tag de profile: " + name);
                _overlayButtons[profile] = button;
            }
        }

        private void WireWindowChrome()
        {
            Button min = Find<Button>("BtnMinimize");
            Button max = Find<Button>("BtnMaximize");
            Button close = Find<Button>("BtnClose");
            FrameworkElement titleBar = Find<FrameworkElement>("TitleBar");

            min.Click += delegate { _window.WindowState = WindowState.Minimized; };
            max.Click += delegate { ToggleMaximize(); };
            close.Click += delegate { _window.Close(); };

            titleBar.MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e)
            {
                if (FindVisualParent<Button>(e.OriginalSource as DependencyObject) != null) return;
                if (e.ClickCount == 2) ToggleMaximize();
                else
                {
                    try { _window.DragMove(); } catch { }
                }
            };
        }

        private void WireNavigation()
        {
            foreach (KeyValuePair<string, Button> pair in _navButtons)
            {
                string page = pair.Key;
                pair.Value.Click += delegate { Navigate(page, false); };
            }
        }

        private void WirePresetInteractions()
        {
            Find<Button>("BtnPresetBalanced").Click += delegate { SelectPreset("Balanceado", true); };
            Find<Button>("BtnPresetGamer").Click += delegate { SelectPreset("Gamer", true); };
            Find<Button>("BtnPresetExtreme").Click += delegate { SelectPreset("Extremo", true); };

            foreach (ToggleButton overlay in _overlayButtons.Values)
            {
                overlay.Checked += delegate { ScheduleResolve(); };
                overlay.Unchecked += delegate { ScheduleResolve(); };
            }

            Find<Button>("BtnResetOverlays").Click += delegate
            {
                _allowHighRisk = false;
                foreach (ToggleButton overlay in _overlayButtons.Values) overlay.IsChecked = false;
                Find<FrameworkElement>("HighRiskBanner").Visibility = Visibility.Collapsed;
                ScheduleResolve();
            };

            Find<Button>("BtnGrantHighRisk").Click += delegate
            {
                _allowHighRisk = true;
                Find<FrameworkElement>("HighRiskBanner").Visibility = Visibility.Collapsed;
                ScheduleResolve();
            };

            Find<Button>("BtnPreviewFromPreset").Click += delegate { Navigate("Preview", false); };
        }

        private void WirePrototypeFlow()
        {
            Button dashAnalyze = Find<Button>("BtnDashAnalyze");
            Button dashPresets = Find<Button>("BtnDashPresets");
            Button previewBack = Find<Button>("BtnPreviewBack");
            if (dashAnalyze != null) dashAnalyze.Click += delegate { Navigate("Analysis", false); };
            if (dashPresets != null) dashPresets.Click += delegate { Navigate("Presets", false); };
            if (previewBack != null) previewBack.Click += delegate { Navigate("Presets", false); };
        }

        private async Task InitializeBridgeAsync()
        {
            TextBlock bridgeState = Find<TextBlock>("TxtBridgeState");
            TextBlock statusBar = Find<TextBlock>("TxtStatusBar");
            try
            {
                bridgeState.Text = "Inicializando bridge read-only...";
                statusBar.Text = "Carregando backend aprovado...";
                _bridge.Start();

                Dictionary<string, object> handshake = await _bridge.SendAsync("handshake", null, 20000);
                int backendCount = GetInt(handshake, "backendCount", 0);
                bool planner = GetBool(handshake, "plannerPromoted", false);
                bool transaction = GetBool(handshake, "transactionPromoted", false);
                if (backendCount != 230)
                    throw new InvalidOperationException("Bridge reportou backend inesperado: " + backendCount.ToString(CultureInfo.InvariantCulture));

                bridgeState.Text = "Backend 230 · Planner " + (planner ? "OK" : "Legacy") + " · Transaction " + (transaction ? "OK" : "Legacy");
                statusBar.Text = "Native UI conectada — bridge persistente read-only";
                SetText("TxtDashTweaks", backendCount.ToString(CultureInfo.InvariantCulture) + " / 230");

                Dictionary<string, object> overlayResponse = await _bridge.SendAsync("overlays", null, 25000);
                ApplyOverlayMetadata(GetArray(overlayResponse, "value"));

                Dictionary<string, object> snapshot = await _bridge.SendAsync("snapshot", null, 25000);
                ApplySystemSnapshot(snapshot);

                await ResolvePresetAsync();
                _performanceTimer.Start();
            }
            catch (Exception ex)
            {
                bridgeState.Text = "Bridge indisponível — UI permanece em modo visual";
                bridgeState.Foreground = Brush("#FF6B7E");
                statusBar.Text = "Falha no bridge: " + ex.Message;
                SetText("TxtResolveState", "Runtime indisponível. " + ex.Message);
                Program.SafeLog(_logPath, "BridgeInit", ex.ToString());
            }
        }

        private void ApplyOverlayMetadata(object[] items)
        {
            if (items == null) return;
            foreach (object item in items)
            {
                Dictionary<string, object> data = item as Dictionary<string, object>;
                if (data == null) continue;
                string name = GetString(data, "name", String.Empty);
                ToggleButton button;
                if (!_overlayButtons.TryGetValue(name, out button)) continue;
                bool eligible = GetBool(data, "eligible", true);
                string reason = GetString(data, "eligibilityReason", String.Empty);
                button.IsEnabled = eligible;
                if (!String.IsNullOrWhiteSpace(reason)) button.ToolTip = reason;
            }
        }

        private void ApplySystemSnapshot(Dictionary<string, object> snapshot)
        {
            if (snapshot == null) return;
            string os = GetString(snapshot, "OSName", "Windows");
            string build = GetString(snapshot, "Build", "—");
            string cpu = GetString(snapshot, "CPUName", "CPU não identificado");
            string gpu = GetString(snapshot, "GPUName", "GPU não identificada");
            int ram = GetInt(snapshot, "RamGB", 0);
            string storage = GetString(snapshot, "StorageType", "Storage");
            string model = GetString(snapshot, "StorageModel", String.Empty);

            SetText("TxtDashWindows", os + " · build " + build);
            SetText("TxtDashCpu", cpu);
            SetText("TxtDashGpu", gpu);
            SetText("TxtDashRam", ram > 0 ? "RAM · " + ram.ToString(CultureInfo.InvariantCulture) + " GB" : "RAM · —");
            SetText("TxtDashStorage", storage + (String.IsNullOrWhiteSpace(model) ? String.Empty : " · " + model));
        }

        private async Task RefreshPerformanceAsync()
        {
            if (_performanceBusy || _disposed || !_bridge.IsRunning) return;
            if (!_window.IsVisible || _window.WindowState == WindowState.Minimized) return;
            if (!String.Equals(_currentPage, "Dashboard", StringComparison.OrdinalIgnoreCase)) return;

            _performanceBusy = true;
            try
            {
                Dictionary<string, object> perf = await _bridge.SendAsync("performance", null, 8000);
                SetMetric("TxtMetricCpu", perf, "CPU");
                SetMetric("TxtMetricGpu", perf, "GPU");
                SetMetric("TxtMetricRam", perf, "RAM");
                SetMetric("TxtMetricDisk", perf, "Disk");
            }
            catch (Exception ex)
            {
                Program.SafeLog(_logPath, "Performance", ex.Message);
            }
            finally
            {
                _performanceBusy = false;
            }
        }

        private void SetMetric(string control, Dictionary<string, object> perf, string key)
        {
            object value;
            if (perf != null && perf.TryGetValue(key, out value) && value != null)
            {
                double number;
                if (Double.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), NumberStyles.Any, CultureInfo.InvariantCulture, out number))
                    SetText(control, Math.Round(number).ToString(CultureInfo.InvariantCulture) + "%");
                else SetText(control, "—");
            }
            else SetText(control, "—");
        }

        private void SelectPreset(string preset, bool resolve)
        {
            _selectedPreset = preset;
            SetText("TxtSummaryPreset", preset);
            UpdatePresetCardVisuals();
            if (resolve) ScheduleResolve();
        }

        private void UpdatePresetCardVisuals()
        {
            Border balanced = Find<Border>("CardPresetBalanced");
            Border gamer = Find<Border>("CardPresetGamer");
            Border extreme = Find<Border>("CardPresetExtreme");

            ApplyCardState(balanced, String.Equals(_selectedPreset, "Balanceado", StringComparison.OrdinalIgnoreCase), "#14C767", "#0C1410", "#1B7D49");
            ApplyCardState(gamer, String.Equals(_selectedPreset, "Gamer", StringComparison.OrdinalIgnoreCase), "#FF7A00", "#16110C", "#6A3A14");
            ApplyCardState(extreme, String.Equals(_selectedPreset, "Extremo", StringComparison.OrdinalIgnoreCase), "#FF3152", "#170B0E", "#743040");
        }

        private void ApplyCardState(Border card, bool selected, string accent, string activeBackground, string idleBorder)
        {
            if (card == null) return;
            card.BorderThickness = selected ? new Thickness(2.0) : new Thickness(1.0);
            card.BorderBrush = Brush(selected ? accent : idleBorder);
            card.Background = Brush(selected ? activeBackground : "#111111");
        }

        private void ScheduleResolve()
        {
            int version = ++_resolveVersion;
            SetText("TxtResolveState", "Resolvendo seleção...");
            ResolveAfterDelayAsync(version);
        }

        private async void ResolveAfterDelayAsync(int version)
        {
            await Task.Delay(90);
            if (version != _resolveVersion || _disposed) return;
            await ResolvePresetAsync();
        }

        private async Task ResolvePresetAsync()
        {
            if (!_bridge.IsRunning) return;
            List<string> selectedProfiles = new List<string>();
            foreach (KeyValuePair<string, ToggleButton> pair in _overlayButtons)
            {
                if (pair.Value.IsChecked == true) selectedProfiles.Add(pair.Key);
            }

            SetText("TxtSummaryOverlays", selectedProfiles.Count.ToString(CultureInfo.InvariantCulture));
            if (selectedProfiles.Count == 0)
            {
                SetRisk("Baixo", "#14C767");
                Find<FrameworkElement>("HighRiskBanner").Visibility = Visibility.Collapsed;
            }

            Dictionary<string, object> payload = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
            payload["presetName"] = _selectedPreset;
            payload["conditionalProfiles"] = selectedProfiles.ToArray();
            payload["allowHighRisk"] = _allowHighRisk;

            try
            {
                Dictionary<string, object> resolved = await _bridge.SendAsync("resolvePreset", payload, 12000);
                int enabledOverlayCount = GetInt(resolved, "enabledOverlayCount", 0);
                int selectedCount = GetInt(resolved, "selectedCount", 0);
                int blockedCount = GetInt(resolved, "blockedCount", 0);
                int warningCount = GetInt(resolved, "warningCount", 0);
                bool canResolve = GetBool(resolved, "canResolve", false);
                string fingerprint = GetString(resolved, "fingerprint", "—");

                SetText("TxtSummaryOverlays", enabledOverlayCount.ToString(CultureInfo.InvariantCulture));
                SetText("TxtSummaryTotal", selectedCount.ToString(CultureInfo.InvariantCulture) + " tweaks");
                SetText("TxtSummaryFingerprint", fingerprint);

                bool highRiskRequested = selectedProfiles.Any(delegate(string p) { return _highRiskProfiles.Contains(p); });
                bool needsConsent = ContainsBlockedCode(resolved, "HighRiskConsentRequired");
                FrameworkElement banner = Find<FrameworkElement>("HighRiskBanner");
                banner.Visibility = needsConsent ? Visibility.Visible : Visibility.Collapsed;

                if (warningCount > 0 || (highRiskRequested && _allowHighRisk)) SetRisk("Alto", "#FF6B7E");
                else if (enabledOverlayCount > 0) SetRisk("Médio", "#FFC107");
                else SetRisk("Baixo", "#14C767");

                Button preview = Find<Button>("BtnPreviewFromPreset");
                preview.IsEnabled = canResolve;
                if (canResolve)
                    SetText("TxtResolveState", "✓ Seleção resolvida pelo PresetRuntime · nenhuma alteração aplicada");
                else
                    SetText("TxtResolveState", "⚠ " + blockedCount.ToString(CultureInfo.InvariantCulture) + " bloqueio(s). Revise consentimento/conflitos.");
            }
            catch (Exception ex)
            {
                SetText("TxtResolveState", "Falha ao resolver: " + ex.Message);
                Find<Button>("BtnPreviewFromPreset").IsEnabled = false;
                Program.SafeLog(_logPath, "ResolvePreset", ex.ToString());
            }
        }

        private bool ContainsBlockedCode(Dictionary<string, object> resolved, string code)
        {
            object[] blocked = GetArray(resolved, "blockedRequests");
            if (blocked == null) return false;
            foreach (object item in blocked)
            {
                Dictionary<string, object> row = item as Dictionary<string, object>;
                if (row != null && String.Equals(GetString(row, "code", String.Empty), code, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        private void SetRisk(string text, string color)
        {
            TextBlock control = Find<TextBlock>("TxtSummaryRisk");
            if (control == null) return;
            control.Text = text;
            control.Foreground = Brush(color);
        }

        private void Navigate(string pageKey, bool immediate)
        {
            FrameworkElement target;
            if (!_pages.TryGetValue(pageKey, out target)) return;
            if (String.Equals(_currentPage, pageKey, StringComparison.OrdinalIgnoreCase)) return;

            foreach (KeyValuePair<string, FrameworkElement> pair in _pages)
            {
                if (!String.Equals(pair.Key, pageKey, StringComparison.OrdinalIgnoreCase))
                {
                    pair.Value.Visibility = Visibility.Collapsed;
                    pair.Value.Opacity = 1.0;
                    pair.Value.RenderTransform = Transform.Identity;
                }
            }

            target.Visibility = Visibility.Visible;
            _currentPage = pageKey;
            UpdateNavVisual(pageKey);
            Find<TextBlock>("TxtStatusBar").Text = "Pronto — " + FriendlyPageName(pageKey);

            if (immediate)
            {
                target.Opacity = 1.0;
                target.RenderTransform = Transform.Identity;
                return;
            }

            target.Opacity = 0.0;
            TranslateTransform translate = new TranslateTransform(10, 0);
            target.RenderTransform = translate;
            target.RenderTransformOrigin = new Point(0.5, 0.5);

            CubicEase ease = new CubicEase();
            ease.EasingMode = EasingMode.EaseOut;
            DoubleAnimation fade = new DoubleAnimation(0.0, 1.0, TimeSpan.FromMilliseconds(160));
            fade.EasingFunction = ease;
            DoubleAnimation slide = new DoubleAnimation(10.0, 0.0, TimeSpan.FromMilliseconds(170));
            slide.EasingFunction = ease;
            target.BeginAnimation(UIElement.OpacityProperty, fade);
            translate.BeginAnimation(TranslateTransform.XProperty, slide);
        }

        private void UpdateNavVisual(string pageKey)
        {
            string effective = pageKey;
            if (pageKey == "Preview" || pageKey == "Apply" || pageKey == "Result" || pageKey == "TweakDetail") effective = "Presets";

            foreach (KeyValuePair<string, Button> pair in _navButtons)
            {
                bool active = String.Equals(pair.Key, effective, StringComparison.OrdinalIgnoreCase);
                pair.Value.Background = active ? Brush("#3A1E0B") : Brushes.Transparent;
                pair.Value.Foreground = active ? Brush("#FF9A2E") : Brush("#C7CCD4");
            }
        }

        private string FriendlyPageName(string pageKey)
        {
            switch (pageKey)
            {
                case "Dashboard": return "Início";
                case "Presets": return "Presets";
                case "Preview": return "Pré-visualização";
                case "Apply": return "Aplicação";
                case "Result": return "Conclusão";
                case "Backup": return "Backup / Restore";
                case "Custom": return "Personalizado";
                case "TweakDetail": return "Detalhe de tweak";
                case "Analysis": return "Análise do Sistema";
                case "Settings": return "Configurações";
                case "About": return "Sobre";
                default: return pageKey;
            }
        }

        private void FadeInWindow()
        {
            CubicEase ease = new CubicEase();
            ease.EasingMode = EasingMode.EaseOut;
            DoubleAnimation animation = new DoubleAnimation(0.0, 1.0, TimeSpan.FromMilliseconds(190));
            animation.EasingFunction = ease;
            _window.BeginAnimation(Window.OpacityProperty, animation);
        }

        private void ToggleMaximize()
        {
            _window.WindowState = _window.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        }

        private T Find<T>(string name) where T : class
        {
            return _window.FindName(name) as T;
        }

        private void SetText(string controlName, string value)
        {
            TextBlock tb = Find<TextBlock>(controlName);
            if (tb != null) tb.Text = value == null ? String.Empty : value;
        }

        private static Brush Brush(string hex)
        {
            return (Brush)new BrushConverter().ConvertFromString(hex);
        }

        private static T FindVisualParent<T>(DependencyObject child) where T : DependencyObject
        {
            DependencyObject current = child;
            while (current != null)
            {
                T match = current as T;
                if (match != null) return match;
                try { current = VisualTreeHelper.GetParent(current); }
                catch { return null; }
            }
            return null;
        }

        private static string GetString(Dictionary<string, object> data, string key, string fallback)
        {
            object value;
            if (data != null && data.TryGetValue(key, out value) && value != null) return Convert.ToString(value, CultureInfo.InvariantCulture);
            return fallback;
        }

        private static int GetInt(Dictionary<string, object> data, string key, int fallback)
        {
            object value;
            if (data != null && data.TryGetValue(key, out value) && value != null)
            {
                try { return Convert.ToInt32(value, CultureInfo.InvariantCulture); } catch { }
            }
            return fallback;
        }

        private static bool GetBool(Dictionary<string, object> data, string key, bool fallback)
        {
            object value;
            if (data != null && data.TryGetValue(key, out value) && value != null)
            {
                try { return Convert.ToBoolean(value, CultureInfo.InvariantCulture); } catch { }
            }
            return fallback;
        }

        private static object[] GetArray(Dictionary<string, object> data, string key)
        {
            object value;
            if (data == null || !data.TryGetValue(key, out value) || value == null) return null;
            object[] array = value as object[];
            if (array != null) return array;
            System.Collections.ArrayList list = value as System.Collections.ArrayList;
            if (list != null) return list.ToArray();
            return null;
        }

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        private void TryEnableDwmVisuals()
        {
            try
            {
                System.Windows.Interop.WindowInteropHelper helper = new System.Windows.Interop.WindowInteropHelper(_window);
                int dark = 1;
                DwmSetWindowAttribute(helper.Handle, 20, ref dark, sizeof(int));
                int rounded = 2;
                DwmSetWindowAttribute(helper.Handle, 33, ref rounded, sizeof(int));
            }
            catch { }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try { _performanceTimer.Stop(); } catch { }
            _bridge.Dispose();
        }
    }
}
