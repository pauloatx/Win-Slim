using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
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
        private Dictionary<string, object> _analysisSnapshot;
        private readonly Window _window;
        private readonly object _shellContent;
        private object _customPreviousContent;

        private readonly string _rootPath;
        private readonly string _logPath;
        private readonly BridgeClient _bridge;
        private readonly Dictionary<string, FrameworkElement> _pages;
        private readonly Dictionary<string, Button> _navButtons;
        private readonly Dictionary<string, ToggleButton> _overlayButtons;
        private readonly HashSet<string> _highRiskProfiles;
        private readonly DispatcherTimer _performanceTimer;
        private DispatcherTimer _applyDemoTimer;
        private int _applyDemoProgress;
        private UserControl _customWindow;
        private UserControl _tweakDetailWindow;
        internal Window TweakDetailWindow { get { return _window; } }

        private object[] _customCatalog;
        private readonly HashSet<string> _customBaseIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, int> _customLevels = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        private string _customBaseFingerprint = "";
        private string _customBaseName = "Balanceado";
        private string _customName = "Equilibrado personalizado";
        private string[] _customPreviewIds;
        private string _customPreviewName;

        private string _customCategory = "Performance";
        private readonly HashSet<string> _customSelected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, Button> _customCategoryButtons = new Dictionary<string, Button>();
        internal Window CustomWindow { get { return _window; } }

        private readonly List<BackupViewEntry> _backupEntries = new List<BackupViewEntry>();
        private bool _backupDemo;
        private bool _backupTweaksTab;
        private int _backupLoadVersion;
        private BackupViewEntry _selectedBackup;

        private sealed class BackupViewEntry
        {
            public string Date, Profile, Id, Path, Status;
            public bool Demo;
            public DateTime SortDate;
            public readonly List<Dictionary<string, object>> Tweaks = new List<Dictionary<string, object>>();
            public Dictionary<string, object> Metadata;
        }

        private string _currentPage;
        private string _selectedPreset;
        private bool _allowHighRisk;
        private bool _performanceBusy;
        private bool _disposed;
        private int _resolveVersion;
        private Dictionary<string, object> _presetDetails;
        private Dictionary<string, object> _previewDetails;
        private int _previewVersion;
        private bool _loadingPresetOptions;
        private readonly TaskCompletionSource<bool> _ready = new TaskCompletionSource<bool>();
        internal Task Ready { get { return _ready.Task; } }

        public MainWindowController(Window window, string rootPath, string logPath)
        {
            _window = window;
            _shellContent = window.Content;
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
            WirePresetTabs();
            WireBackupInteractions();

            _performanceTimer.Tick += async delegate { await RefreshPerformanceAsync(); };
            _window.SourceInitialized += delegate { TryEnableDwmVisuals(); };
            _window.Loaded += async delegate
            {
                FadeInWindow();
                Navigate("Dashboard", true);
                SelectPreset("Balanceado", false);
                try { await InitializeBridgeAsync(); }
                finally { _ready.TrySetResult(true); }
            };
            _window.StateChanged += delegate { UpdatePerformancePolling(); };
            _window.Closed += delegate { Dispose(); };
        }

        internal void PrepareDashboardValidation()
        {
            Navigate("Dashboard", true);
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
                SetOverlayHelp(button, profile, String.Empty);
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
                if (page == "Custom") pair.Value.Click += async delegate { await OpenCustomWindowAsync(); };
                else pair.Value.Click += delegate { Navigate(page, false); };
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

            Find<Button>("BtnPreviewFromPreset").Click += async delegate { try { await PreparePreviewAsync(); } catch { } };
        }

        private void WirePrototypeFlow()
        {
            Find<Button>("BtnAnalysisReport").Click += delegate { ShowAnalysisReport(); };
            Button dashAnalyze = Find<Button>("BtnDashAnalyze");
            Button previewBack = Find<Button>("BtnPreviewBack");
            Button dashDetails = Find<Button>("BtnDashDetails");
            if (dashDetails != null) dashDetails.Click += delegate { Navigate("Analysis", false); };
            if (dashAnalyze != null) dashAnalyze.Click += delegate { Navigate("Analysis", false); };
            if (previewBack != null) previewBack.Click += async delegate {
                _previewVersion++; Navigate("Presets", false);
                if (_customPreviewIds != null) await OpenCustomWindowAsync();
            };
            Find<Button>("BtnPreviewDetails").Click += delegate { ShowPreviewDetails(); };
            Find<Button>("BtnPreviewResultDemo").Click += delegate { PrepareApplyDemo(); };
            Find<Button>("BtnApplyDemoStart").Click += delegate { StartApplyDemo(); };
            Find<Button>("BtnApplyCancel").Click += delegate { CancelApplyDemo(); };
            Find<Button>("BtnResultRestartLater").Click += delegate { Navigate("Presets", false); };
            Find<Button>("BtnResultReport").Click += delegate { ShowResultDemoReport(); };

        }

        internal void PrepareApplyDemo()
        {
            StopApplyDemo();
            Navigate("Apply", true);
            RenderApplyDemo(67);
            Find<Button>("BtnApplyCancel").IsEnabled = true;
            Find<Button>("BtnApplyDemoStart").IsEnabled = true;
        }

        private void RenderApplyDemo(int progress)
        {
            _applyDemoProgress = progress;
            Find<ProgressBar>("ApplyProgress").Value = progress;
            SetText("TxtApplyPercent", progress.ToString(CultureInfo.InvariantCulture) + "%");
            int stage = progress < 20 ? 0 : progress < 50 ? 1 : progress < 75 ? 2 : progress < 90 ? 3 : 4;
            for (int i = 0; i < 5; i++)
            {
                bool done = i < stage || progress == 100;
                bool active = i == stage && progress < 100;
                string color = done ? "#14C767" : active ? "#FF9A2E" : "#A9AFB8";
                SetText("ApplyStageMark" + i, done ? "✓" : active ? "●" : "○");
                Find<TextBlock>("ApplyStageMark" + i).Foreground = Brush(color);
                Find<Border>("ApplyStageIcon" + i).Background = Brush(done ? "#14C767" : "#082617");
                if (done) Find<TextBlock>("ApplyStageMark" + i).Foreground = Brush("#082617");
                SetText("ApplyStageStatus" + i, done ? "(concluído)" : active ? "(em andamento)" : "(pendente)");
                Find<TextBlock>("ApplyStageStatus" + i).Foreground = Brush(color);
            }
            string[] current = { "Criando backup do sistema", "PERF-016 — MSI Mode GPU", "Configuração de rede e internet", "Configuração de serviços", "Otimizações avançadas" };
            // The reference's MSI label is kept at the 67% fixture for visual comparison.
            if (_customPreviewIds != null && _previewDetails != null) {
                object[] items = GetArray(PreviewObject(_previewDetails, "preview"), "Items") ?? new object[0];
                Dictionary<string, object> item = items.Length == 0 ? null : items[Math.Min(items.Length - 1, progress * items.Length / 100)] as Dictionary<string, object>;
                SetText("TxtApplyCurrent", item == null ? "Nenhum ajuste apto" : GetString(item, "TweakId", "") + " — " + GetString(item, "Name", ""));
                SetText("TxtApplyOperation", "Demonstração");
                SetText("TxtApplyStatus", "Simulando " + _customPreviewName + ". Nenhuma alteração no Windows.");
                return;
            }
            SetText("TxtApplyCurrent", progress == 67 ? "PERF-016 — MSI Mode GPU" : current[stage]);
            SetText("TxtApplyOperation", "Em andamento");
            Find<TextBlock>("TxtApplyOperation").Foreground = Brush("#FF9A2E");
            SetText("TxtApplyStatus", progress == 67 ? "Operação atual: aplicando alteração no dispositivo GPU." : "Demonstração: " + current[stage] + ".");
        }

        private void StartApplyDemo()
        {
            StopApplyDemo();
            RenderApplyDemo(0);
            Find<Button>("BtnApplyCancel").IsEnabled = true;
            Find<Button>("BtnApplyDemoStart").IsEnabled = false;
            _applyDemoTimer = new DispatcherTimer(DispatcherPriority.Background);
            _applyDemoTimer.Interval = TimeSpan.FromMilliseconds(500);
            _applyDemoTimer.Tick += delegate {
                RenderApplyDemo(Math.Min(100, _applyDemoProgress + 2));
                if (_applyDemoProgress == 100) { StopApplyDemo(); PrepareResultDemo(); }
            };
            _applyDemoTimer.Start();
        }

        private void StopApplyDemo()
        {
            if (_applyDemoTimer != null) { _applyDemoTimer.Stop(); _applyDemoTimer = null; }
        }

        internal void CancelApplyDemo()
        {
            StopApplyDemo();
            SetText("TxtApplyOperation", "Cancelada");
            Find<TextBlock>("TxtApplyOperation").Foreground = Brush("#FF6B6B");
            SetText("TxtApplyStatus", "Demonstração cancelada. Nenhuma alteração foi aplicada no Windows.");
            Find<Button>("BtnApplyCancel").IsEnabled = false;
            Find<Button>("BtnApplyDemoStart").IsEnabled = true;
        }

        internal void PrepareResultDemo()
        {
            // This fixture only previews the requested layout; it never runs a transaction.
            SetText("TxtResultTitle", "Otimização concluída!");
            SetText("TxtResultSubtitle", "Exemplo de conclusão bem-sucedida · preset " + (_selectedPreset == "Balanceado" ? "Equilibrado" : _selectedPreset) + ".");
            SetText("TxtResultApplied", "51");
            SetText("TxtResultRestart", "3");
            SetText("TxtResultFailed", "0");
            SetText("TxtResultConflicts", "0");
            if (_customPreviewIds != null && _previewDetails != null) {
                Dictionary<string, object> summary = PreviewObject(PreviewObject(_previewDetails, "preview"), "Summary");
                SetText("TxtResultTitle", "Demonstração concluída!");
                SetText("TxtResultSubtitle", _customPreviewName + " · seleção personalizada simulada; nenhuma alteração no Windows.");
                SetText("TxtResultApplied", GetInt(summary, "Executable", 0).ToString());
                SetText("TxtResultRestart", GetInt(_previewDetails, "restartCount", 0).ToString());
            }
            Find<Button>("BtnResultRestartNow").IsEnabled = false;
            Navigate("Result", true);
        }

        private void ShowResultDemoReport()
        {
            UserControl dialog = CreateDetailWindow("Relatório de conclusão — demonstração");
            dialog.Content = new TextBox {
                Text = "DEMONSTRAÇÃO VISUAL — R3.2.33\n\nNenhuma transação foi executada. Nenhum backup foi criado.\nOs números abaixo são ilustrativos, usados para conferir o layout.\n\nPreset selecionado: " + (_selectedPreset == "Balanceado" ? "Equilibrado" : _selectedPreset) +
                    "\nAplicadas (exemplo): 51\nAguardando reinício (exemplo): 3 ajustes\nFalhas (exemplo): 0\nConflitos (exemplo): 0\n\nA tela receberá os resultados reais na integração da aplicação.\nReiniciar agora permanece indisponível nesta demonstração.",
                IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontSize = 13,
                Background = Brush("#0D1012"), Foreground = Brush("#E5E7EB"), Margin = new Thickness(18), VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
            if (_customPreviewIds != null && _previewDetails != null) {
                ((TextBox)dialog.Content).Text = "DEMONSTRAÇÃO — nenhuma alteração executada, nenhum backup criado.\n\nPreset: " + _customPreviewName + "\n\nSeleção: " + String.Join(", ", _customPreviewIds) + "\n\nPré-visualização consultada:\n" + PrettyPresetJson(_previewDetails);
            }
            ShowReportView(dialog);
        }

        internal void NavigatePreviewValidation() { Navigate("Preview", false); }

        internal Task PreparePreviewAsync() { return PreparePreviewCoreAsync(null, null); }

        private async Task PreparePreviewCoreAsync(string[] customIds, string customName)
        {
            _customPreviewIds = customIds == null ? null : (string[])customIds.Clone();
            _customPreviewName = customName;
            string displayName = customIds == null ? (_selectedPreset == "Balanceado" ? "Equilibrado" : _selectedPreset) : customName;
            Find<Button>("BtnPreviewBack").Content = customIds == null ? "← Voltar aos Presets" : "← Voltar ao Personalizado";
            Find<Button>("BtnPreviewResultDemo").IsEnabled = false;
            int version = ++_previewVersion;
            int selectionVersion = _resolveVersion;
            _previewDetails = null;
            Navigate("Preview", false);
            foreach (string name in new string[] { "TxtPreviewCount", "TxtPreviewRestart", "TxtPreviewRisk" }) SetText(name, "—");
            Find<StackPanel>("PreviewCategoryRows").Children.Clear();
            Find<Button>("BtnPreviewDetails").IsEnabled = false;
            SetText("TxtPreviewSelection", "Analisando " + displayName + "...");
            SetText("TxtPreviewConflicts", "○ Verificando conflitos...");
            SetText("TxtPreviewHardware", "○ Verificando Windows e hardware...");
            SetText("TxtPreviewState", "Preparando o plano em modo de consulta...");
            Dictionary<string, object> payload = new Dictionary<string, object>();
            payload["presetName"] = _selectedPreset;
            payload["conditionalProfiles"] = _overlayButtons.Where(p => p.Value.IsChecked == true).Select(p => p.Key).ToArray();
            payload["allowHighRisk"] = _allowHighRisk;
            try
            {
                if (customIds != null) { payload["selectedIds"] = customIds; payload["customName"] = customName; payload["levelSelections"] = EffectiveCustomLevels().Where(pair => customIds.Contains(pair.Key, StringComparer.OrdinalIgnoreCase)).ToDictionary(pair => pair.Key, pair => pair.Value); }
                Dictionary<string, object> data = await _bridge.SendAsync(customIds == null ? "preview" : "customPreview", payload, 60000);
                if (_disposed || version != _previewVersion || selectionVersion != _resolveVersion) return;
                Dictionary<string, object> preview = PreviewObject(data, "preview");
                if (preview == null || !GetBool(data, "readOnly", false)) throw new InvalidOperationException("Resposta de pré-visualização inválida.");
                _previewDetails = data;
                Dictionary<string, object> summary = PreviewObject(preview, "Summary");
                Dictionary<string, object> risk = PreviewObject(preview, "RiskSummary");
                int count = GetInt(summary, "Executable", 0), skipped = GetInt(summary, "Skipped", 0), blocked = GetInt(summary, "Blocked", 0);
                SetText("TxtPreviewCount", count.ToString(CultureInfo.InvariantCulture));
                SetText("TxtPreviewRestart", GetInt(data, "restartCount", 0).ToString(CultureInfo.InvariantCulture));
                string highest = GetString(risk, "Highest", "None");
                string riskText = highest == "High" || highest == "Alto" ? "Alto" : highest == "Medium" || highest == "Médio" || highest == "Medio" ? "Médio" : highest == "Low" || highest == "Baixo" ? "Baixo" : "Nenhum";
                SetText("TxtPreviewRisk", riskText);
                Find<TextBlock>("TxtPreviewRisk").Foreground = Brush(riskText == "Alto" ? "#FF1744" : riskText == "Médio" ? "#FF9A2E" : "#14C767");
                SetText("TxtPreviewSelection", displayName + " · " + GetInt(summary, "Selected", 0) + " selecionados · " + count + " aptos · " + skipped + " ignorados · " + blocked + " bloqueados");
                object[] categories = GetArray(data, "categories");
                if (categories != null) foreach (object value in categories)
                {
                    Dictionary<string, object> row = value as Dictionary<string, object>; if (row == null) continue;
                    Grid grid = new Grid { Margin = new Thickness(12, 0, 12, 0), MinHeight = 35 };
                    grid.ColumnDefinitions.Add(new ColumnDefinition());
                    foreach (double width in new double[] { 90, 120, 120 }) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(width) });
                    string[] texts = new string[] { GetString(row, "name", "Outros"), GetInt(row, "count", 0).ToString(), GetString(row, "risk", "—"), GetInt(row, "restartCount", 0).ToString() };
                    for (int i = 0; i < texts.Length; i++)
                    {
                        TextBlock label = new TextBlock { Text = texts[i], VerticalAlignment = VerticalAlignment.Center, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, ToolTip = texts[i] };
                        if (i == 2) label.Foreground = Brush(texts[i] == "Alto" ? "#FF1744" : texts[i] == "Médio" ? "#FF9A2E" : "#14C767");
                        Grid.SetColumn(label, i); grid.Children.Add(label);
                    }
                    Find<StackPanel>("PreviewCategoryRows").Children.Add(new Border { Child = grid, BorderBrush = Brush("#242B30"), BorderThickness = new Thickness(0,0,0,1) });
                }
                if (count == 0) Find<StackPanel>("PreviewCategoryRows").Children.Add(new TextBlock { Text = "Nenhum ajuste apto para este plano. Consulte os detalhes.", Margin = new Thickness(12) });
                object[] blocks = GetArray(preview, "BlockedTweaks"), policyBlocks = GetArray(data, "policyBlocked");
                int conflicts = 0;
                foreach (object value in blocks ?? new object[0]) { Dictionary<string, object> row = value as Dictionary<string, object>; if (row != null && GetString(row,"ReasonCode", "").IndexOf("Conflict", StringComparison.OrdinalIgnoreCase) >= 0) conflicts++; }
                SetText("TxtPreviewConflicts", conflicts == 0 ? "✓ Nenhum conflito bloqueante detectado" : "⚠ " + conflicts + " conflito(s) bloqueante(s) · ver detalhes");
                Find<TextBlock>("TxtPreviewConflicts").Foreground = Brush(conflicts == 0 ? "#14C767" : "#FF9A2E");
                SetText("TxtPreviewHardware", skipped == 0 && blocked == 0 && (policyBlocks == null || policyBlocks.Length == 0) ? "✓ Verificações do Planner concluídas para Windows e hardware" : "⚠ Há ajustes ignorados ou bloqueados · ver detalhes");
                Find<TextBlock>("TxtPreviewHardware").Foreground = Brush(skipped == 0 && blocked == 0 ? "#14C767" : "#FF9A2E");
                SetText("TxtPreviewState", "Modo de consulta · contagem de reinício por ajuste, não por reinicialização do PC.");
                Find<Button>("BtnPreviewDetails").IsEnabled = true;
                Find<Button>("BtnPreviewResultDemo").IsEnabled = GetBool(preview, "TransactionReady", false);
                Program.SafeLog(_logPath, "Preview", "Aptos=" + count + "; bloqueados=" + blocked + "; fingerprint=" + GetString(preview, "PreviewFingerprint", ""));
            }
            catch (Exception ex)
            {
                if (_disposed || version != _previewVersion) return;
                SetText("TxtPreviewState", "Não foi possível preparar o plano: " + ex.Message);
                SetText("TxtPreviewConflicts", "○ Verificações não concluídas");
                SetText("TxtPreviewHardware", "○ Compatibilidade não confirmada");
                Program.SafeLog(_logPath, "PreviewError", ex.ToString());
                throw;
            }
        }
        private static Dictionary<string, object> PreviewObject(Dictionary<string, object> data, string key)
        {
            object value; return data != null && data.TryGetValue(key, out value) ? value as Dictionary<string, object> : null;
        }
        private void ShowPreviewDetails()
        {
            if (_previewDetails == null) return;
            UserControl dialog = CreateDetailWindow("Detalhes da pré-visualização");
            dialog.Content = new TextBox { Text = PrettyPresetJson(_previewDetails), IsReadOnly = true, AcceptsReturn = true, FontFamily = new FontFamily("Consolas"), FontSize = 12, Background = Brush("#0D1012"), Foreground = Brush("#E5E7EB"), Margin = new Thickness(14), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
            ShowReportView(dialog);
        }

        private async Task InitializeBridgeAsync()
        {
            TextBlock bridgeState = Find<TextBlock>("TxtBridgeState");
            TextBlock statusBar = Find<TextBlock>("TxtStatusBar");
            try
            {
                bridgeState.Text = "Carregando catálogo...";
                statusBar.Text = "Carregando backend aprovado...";
                _bridge.Start();

                Dictionary<string, object> handshake = await _bridge.SendAsync("handshake", null, 20000);
                int backendCount = GetInt(handshake, "backendCount", 0);
                bool planner = GetBool(handshake, "plannerPromoted", false);
                bool transaction = GetBool(handshake, "transactionPromoted", false);
                if (backendCount != 230)
                    throw new InvalidOperationException("Bridge reportou backend inesperado: " + backendCount.ToString(CultureInfo.InvariantCulture));

                bridgeState.Text = "Catálogo disponível · 230 ajustes";
                statusBar.Text = "Catálogo carregado";
                // Applied counts require transaction history; catalog size is not an applied count.

                Dictionary<string, object> overlayResponse = await _bridge.SendAsync("overlays", null, 25000);
                ApplyOverlayMetadata(GetArray(overlayResponse, "value"));

                Dictionary<string, object> snapshot = await _bridge.SendAsync("snapshot", null, 25000);
                ApplySystemSnapshot(snapshot);

                await ResolvePresetAsync();
                UpdatePerformancePolling();
                await RefreshPerformanceAsync();
            }
            catch (Exception ex)
            {
                bridgeState.Text = "Catálogo indisponível";
                bridgeState.Foreground = Brush("#FF6B7E");
                statusBar.Text = "Falha no bridge: " + ex.Message;
                SetText("TxtResolveState", "Runtime indisponível. " + ex.Message);
                Program.SafeLog(_logPath, "BridgeInit", ex.ToString());
            }
        }

        private static readonly Dictionary<string, string> OverlayHelp = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
                { "HW-HAGS-ON", "Passa parte da organização das tarefas gráficas para a placa de vídeo. O resultado varia conforme a placa e o driver; pode exigir reinício." },
                { "HW-MSI-GPU", "Muda a forma como a placa de vídeo avisa o processador que precisa de atenção. Pode ajudar em pequenas travadas, dependendo do hardware. Exige reinício." },
                { "HW-CORE-PARKING-100", "Mantém os núcleos do processador disponíveis, evitando que o Windows os coloque em descanso. Pode aumentar o consumo de energia e a temperatura." },
                { "HW-CS2-P-CORES", "Direciona o CS2 aos núcleos de maior desempenho em processadores com núcleos de tipos diferentes. Depende de hardware compatível. Alto risco: exige confirmação extra." },
                { "HW-GPU-IRQ-AFFINITY", "Direciona os avisos da placa de vídeo para núcleos específicos do processador. Depende da organização dos núcleos e exige ao menos 8 processadores lógicos. Alto risco: exige confirmação extra." },
                { "WL-VALORANT", "Dá mais prioridade ao VALORANT no uso do processador quando outros programas estão rodando. Pode afetar tarefas em segundo plano." },
                { "WL-CS2", "Dá mais prioridade ao Counter-Strike 2 no uso do processador quando outros programas estão rodando. Pode afetar tarefas em segundo plano." },
                { "WL-APEX", "Dá mais prioridade ao Apex Legends no uso do processador quando outros programas estão rodando. Pode afetar tarefas em segundo plano." },
                { "WL-FORTNITE", "Dá mais prioridade ao Fortnite no uso do processador quando outros programas estão rodando. Pode afetar tarefas em segundo plano." },
                { "WL-GTAV", "Dá mais prioridade ao GTA V no uso do processador quando outros programas estão rodando. Pode afetar tarefas em segundo plano." },
                { "WL-FSO-OFF", "Desliga as otimizações de tela cheia do Windows. Pode ajudar em problemas de compatibilidade ou demora na resposta dos jogos; o resultado varia por jogo." },
                { "WL-STREAMING", "Dá mais prioridade ao OBS e ao Streamlabs no uso do processador durante transmissões e gravações. Pode afetar outros programas abertos." },
                { "WL-VIDEO-EDITING", "Dá mais prioridade aos editores de vídeo incluídos neste perfil no uso do processador. Pode afetar outros programas abertos." },
                { "WL-DESIGN", "Dá mais prioridade aos programas de design incluídos neste perfil no uso do processador. Pode afetar outros programas abertos." },
                { "WL-PROGRAMMING", "Dá mais prioridade aos editores de código incluídos neste perfil no uso do processador. Pode afetar outros programas abertos." },
                { "WL-DEFENDER-DEV-EXCLUSIONS", "Cria exceções no Defender para alguns programas e pastas de desenvolvimento, reduzindo a verificação de arquivos nesses locais. Isso reduz a proteção nessas exceções; revise a lista antes de aplicar." }
        };
        private void SetOverlayHelp(ToggleButton button, string profile, string eligibilityReason)
        {
            string explanation;
            if (!OverlayHelp.TryGetValue(profile, out explanation)) explanation = "Adiciona ajustes específicos deste perfil à seleção.";
            string text = Convert.ToString(button.Content, CultureInfo.InvariantCulture) + "\n\n" + explanation;
            if (!String.IsNullOrWhiteSpace(eligibilityReason)) text += "\n\nDisponibilidade: " + eligibilityReason;
            button.ToolTip = new ToolTip
            {
                Background = Brush("#111111"), Foreground = Brush("#E5E7EB"),
                BorderBrush = Brush("#FF7A00"), BorderThickness = new Thickness(1), Padding = new Thickness(12),
                Placement = PlacementMode.MousePoint,
                Content = new TextBlock { Text = text, Width = 300, TextWrapping = TextWrapping.Wrap, FontSize = 12, Foreground = Brush("#E5E7EB") }
            };
            ToolTipService.SetInitialShowDelay(button, 800);
            ToolTipService.SetShowDuration(button, 20000);
            ToolTipService.SetBetweenShowDelay(button, 200);
            ToolTipService.SetShowOnDisabled(button, true);
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
                SetOverlayHelp(button, name, reason);
            }
        }

        private void ApplySystemSnapshot(Dictionary<string, object> snapshot)
        {
            if (snapshot == null) return;
            _analysisSnapshot = snapshot;
            string os = GetString(snapshot, "OSName", "Windows");
            string build = GetString(snapshot, "Build", "—");
            string cpu = GetString(snapshot, "CPUName", "CPU não identificado");
            string gpu = GetString(snapshot, "GPUName", "GPU não identificada");
            int ram = GetInt(snapshot, "RamGB", 0);
            string storage = GetString(snapshot, "StorageType", "Storage");
            string model = GetString(snapshot, "StorageModel", String.Empty);

            SetText("TxtDashWindows", os);
            SetText("TxtDashBuild", "Build " + build);
            int cores = GetInt(snapshot, "CPUCores", 0);
            int threads = GetInt(snapshot, "CPUThreads", 0);
            SetText("TxtDashCores", cores > 0 && threads > 0 ? cores.ToString(CultureInfo.InvariantCulture) + " núcleos / " + threads.ToString(CultureInfo.InvariantCulture) + " threads" : "Núcleos / threads · —");
            SetText("TxtDashDriver", "Driver · " + GetString(snapshot, "GPUDriver", "—"));
            bool admin = GetBool(snapshot, "IsAdmin", false);
            SetText("TxtDashAdmin", admin ? "Administrador\ndetectado" : "Sem privilégios\nde administrador");
            Find<TextBlock>("IconDashAdmin").Foreground = Brush(admin ? "#14C767" : "#FFC107");
            int buildNumber;
            bool compatible = Int32.TryParse(build, out buildNumber) && buildNumber >= 10240 &&
                (os.IndexOf("Windows 10", StringComparison.OrdinalIgnoreCase) >= 0 || os.IndexOf("Windows 11", StringComparison.OrdinalIgnoreCase) >= 0);
            SetText("TxtDashCompatible", compatible ? "Sistema\ncompatível" : "Compatibilidade\nnão confirmada");
            Find<TextBlock>("IconDashCompatible").Text = compatible ? "\uE73E" : "\uE946";
            Find<TextBlock>("IconDashCompatible").Foreground = Brush(compatible ? "#14C767" : "#FFC107");
            SetText("TxtDashCpu", cpu);
            Find<TextBlock>("TxtDashCpu").ToolTip = cpu;
            SetText("TxtDashGpu", gpu);
            Find<TextBlock>("TxtDashGpu").ToolTip = gpu;
            SetText("TxtDashRam", ram > 0 ? "RAM · " + ram.ToString(CultureInfo.InvariantCulture) + " GB" : "RAM · —");
            int sizeGB = GetInt(snapshot, "StorageSizeGB", 0);
            SetText("TxtDashStorage", storage + (sizeGB > 0 ? " · " + sizeGB.ToString(CultureInfo.InvariantCulture) + " GB" : String.Empty));
            Find<TextBlock>("TxtDashStorage").ToolTip = model;
        }

        private async Task RefreshPerformanceAsync()
        {
            if (_performanceBusy || _disposed || !_bridge.IsRunning) return;
            if (!_window.IsVisible || _window.WindowState == WindowState.Minimized) return;
            if (!String.Equals(_currentPage, "Dashboard", StringComparison.OrdinalIgnoreCase) || (_window.Content != _shellContent)) return;

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
                SetMetric("TxtMetricCpu", null, "CPU");
                SetMetric("TxtMetricGpu", null, "GPU");
                SetMetric("TxtMetricRam", null, "RAM");
                SetMetric("TxtMetricDisk", null, "Disk");
                Program.SafeLog(_logPath, "Performance", ex.Message);
            }
            finally
            {
                _performanceBusy = false;
            }
        }

        private void UpdatePerformancePolling()
        {
            if (_disposed) return;
            bool active = _bridge.IsRunning && _window.IsVisible &&
                _window.WindowState != WindowState.Minimized &&
                String.Equals(_currentPage, "Dashboard", StringComparison.OrdinalIgnoreCase) && (_window.Content == _shellContent);
            if (active) _performanceTimer.Start();
            else _performanceTimer.Stop();
        }

        private void SetMetric(string control, Dictionary<string, object> perf, string key)
        {
            object value;
            double number = 0;
            bool valid = perf != null && perf.TryGetValue(key, out value) && value != null &&
                Double.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), NumberStyles.Any,
                    CultureInfo.InvariantCulture, out number) && !Double.IsNaN(number) && !Double.IsInfinity(number);
            double percent = valid ? number : 0;
            percent = Math.Max(0, Math.Min(100, percent));
            SetText(control, valid ? Math.Round(percent).ToString(CultureInfo.InvariantCulture) + "%" : "—");
            string suffix = control.Substring("TxtMetric".Length);
            System.Windows.Shapes.Path arc = Find<System.Windows.Shapes.Path>("ArcMetric" + suffix);
            if (arc == null) return;
            arc.Data = null;
            if (!valid || percent <= 0) return;
            // Center (44,44), radius 40: the same geometry as the background ellipse.
            double angle = (Math.Min(percent, 99.999) / 100.0) * Math.PI * 2.0;
            Point start = new Point(44, 4);
            Point end = new Point(44 + 40 * Math.Sin(angle), 44 - 40 * Math.Cos(angle));
            PathFigure figure = new PathFigure();
            figure.StartPoint = start;
            figure.IsClosed = false;
            figure.IsFilled = false;
            figure.Segments.Add(new ArcSegment(end, new Size(40, 40), 0, percent > 50,
                SweepDirection.Clockwise, true));
            PathGeometry geometry = new PathGeometry();
            geometry.Figures.Add(figure);
            geometry.Freeze();
            arc.Data = geometry;
        }

        private void SelectPreset(string preset, bool resolve)
        {
            _selectedPreset = preset;
            SetText("TxtSummaryPreset", preset == "Balanceado" ? "Equilibrado" : preset);
            UpdatePresetCardVisuals();
            if (resolve) ScheduleResolve();
        }

        private void UpdatePresetCardVisuals()
        {
            SetTextButton("BtnPresetBalanced", _selectedPreset == "Balanceado" ? "✓ Equilibrado selecionado" : "Selecionar Equilibrado");
            SetTextButton("BtnPresetGamer", _selectedPreset == "Gamer" ? "✓ Gamer selecionado" : "Selecionar Gamer");
            SetTextButton("BtnPresetExtreme", _selectedPreset == "Extremo" ? "✓ Extremo selecionado" : "Selecionar Extremo");
            Border balanced = Find<Border>("CardPresetBalanced");
            Border gamer = Find<Border>("CardPresetGamer");
            Border extreme = Find<Border>("CardPresetExtreme");

            ApplyCardState(balanced, String.Equals(_selectedPreset, "Balanceado", StringComparison.OrdinalIgnoreCase), "#14C767", "#0C1410", "#1B7D49");
            ApplyCardState(gamer, String.Equals(_selectedPreset, "Gamer", StringComparison.OrdinalIgnoreCase), "#FF7A00", "#16110C", "#6A3A14");
            ApplyCardState(extreme, String.Equals(_selectedPreset, "Extremo", StringComparison.OrdinalIgnoreCase), "#FF3152", "#170B0E", "#743040");
        }

        private readonly string[] _presetOptionNames = new string[] { "Developer", "Commands", "Registry", "Providers", "Hardware", "Dependencies", "Conflicts", "AutoReport", "DetailedLog" };

        private bool PresetOption(string name)
        {
            if (name == "Developer") return Find<ToggleButton>("OptDeveloper").IsChecked == true;
            return Find<CheckBox>("Opt" + name).IsChecked == true;
        }

        private Dictionary<string, object> PresetOptionsData()
        {
            Dictionary<string, object> options = new Dictionary<string, object>();
            foreach (string name in _presetOptionNames) options[name] = PresetOption(name);
            options["DryRun"] = true;
            options["ConfirmHighRisk"] = true;
            return options;
        }

        private void WirePresetTabs()
        {
            foreach (string key0 in new string[] { "General", "Advanced", "Logs" })
            {
                string key = key0;
                Find<Button>("BtnPresetTab" + key).Click += delegate { SelectPresetTab(key); };
            }
            LoadPresetOptions();
            foreach (string name in _presetOptionNames)
            {
                ToggleButton control = name == "Developer" ? (ToggleButton)Find<ToggleButton>("OptDeveloper") : (ToggleButton)Find<CheckBox>("Opt" + name);
                control.Checked += delegate { PresetOptionsChanged(); };
                control.Unchecked += delegate { PresetOptionsChanged(); };
            }
            Find<Button>("BtnExportPresetOptions").Click += delegate { ExportPresetOptions(); };
            Find<Button>("BtnRefreshPresetLogs").Click += async delegate { await RefreshPresetLogsAsync(); };
            Find<Button>("BtnExportPresetLogs").Click += delegate { ExportPresetLogs(); };
            SelectPresetTab("General");
            UpdatePresetDiagnostics();
        }

        internal void SelectPresetTab(string key)
        {
            if (!new string[] { "General", "Advanced", "Logs" }.Contains(key)) key = "General";
            foreach (string other in new string[] { "General", "Advanced", "Logs" })
            {
                Find<FrameworkElement>("PresetTab" + other).Visibility = other == key ? Visibility.Visible : Visibility.Collapsed;
                Button button = Find<Button>("BtnPresetTab" + other);
                button.Background = Brush(other == key ? "#482406" : "#101215");
                button.BorderBrush = Brush(other == key ? "#FF7A00" : "#343A42");
                button.Foreground = Brush(other == key ? "#FF9A2E" : "#C8CDD5");
            }
            if (key == "Logs") RefreshPresetLogsAsync();
        }

        private string PresetOptionsPath()
        {
            return System.IO.Path.Combine(_rootPath, "config", "presets-ui-r3.2.33.json");
        }

        private void LoadPresetOptions()
        {
            _loadingPresetOptions = true;
            try
            {
                if (System.IO.File.Exists(PresetOptionsPath()))
                {
                    var serializer = new System.Web.Script.Serialization.JavaScriptSerializer();
                    var values = serializer.Deserialize<Dictionary<string, object>>(System.IO.File.ReadAllText(PresetOptionsPath()));
                    foreach (string name in _presetOptionNames)
                    {
                        if (!values.ContainsKey(name) || !(values[name] is bool)) continue;
                        ToggleButton control = name == "Developer" ? (ToggleButton)Find<ToggleButton>("OptDeveloper") : (ToggleButton)Find<CheckBox>("Opt" + name);
                        control.IsChecked = (bool)values[name];
                    }
                }
            }
            catch (Exception ex) { Program.SafeLog(_logPath, "OptionsLoad", ex.Message); }
            finally { _loadingPresetOptions = false; }
        }

        private void PresetOptionsChanged()
        {
            if (_loadingPresetOptions) return;
            UpdatePresetDiagnostics();
            try
            {
                WritePresetJson(PresetOptionsPath(), PresetOptionsData());
                SetText("TxtAdvancedStatus", "Opções de exibição salvas neste computador.");
            }
            catch (Exception ex)
            {
                SetText("TxtAdvancedStatus", "Não foi possível salvar as opções: " + ex.Message);
                Program.SafeLog(_logPath, "OptionsSave", ex.Message);
            }
        }

        private void UpdatePresetDiagnostics()
        {
            bool developer = PresetOption("Developer");
            Find<ToggleButton>("OptDeveloper").Content = developer ? "Ativado" : "Desativado";
            Find<FrameworkElement>("DeveloperOptions").IsEnabled = developer;
            TextBox target = Find<TextBox>("TxtPresetDiagnostics");
            if (!developer) { target.Text = "Ative o modo desenvolvedor para consultar os detalhes."; return; }
            if (_presetDetails == null) { target.Text = "Aguardando a resolução da seleção atual..."; return; }
            List<object> rows = new List<object>();
            object[] tweaks = GetArray(_presetDetails, "selectedTweaks");
            if (tweaks != null) foreach (object item in tweaks)
            {
                Dictionary<string, object> source = item as Dictionary<string, object>;
                if (source == null) continue;
                Dictionary<string, object> row = new Dictionary<string, object>();
                foreach (string field in new string[] { "id", "name", "risk", "type", "windowsVersion" })
                    if (source.ContainsKey(field)) row[field] = source[field];
                AddPresetDiagnosticFields(row, source, "Commands", new string[] { "commands", "undoCommands" });
                AddPresetDiagnosticFields(row, source, "Registry", new string[] { "registry" });
                AddPresetDiagnosticFields(row, source, "Providers", new string[] { "provider" });
                AddPresetDiagnosticFields(row, source, "Hardware", new string[] { "hardwareRules" });
                AddPresetDiagnosticFields(row, source, "Dependencies", new string[] { "dependencies" });
                AddPresetDiagnosticFields(row, source, "Conflicts", new string[] { "conflicts" });
                rows.Add(row);
            }
            Dictionary<string, object> output = new Dictionary<string, object>();
            output["preset"] = _selectedPreset == "Balanceado" ? "Equilibrado" : _selectedPreset;
            output["selectedTweaks"] = rows;
            output["warnings"] = GetArray(_presetDetails, "warnings");
            output["blockedRequests"] = GetArray(_presetDetails, "blockedRequests");
            target.Text = PrettyPresetJson(output);
        }

        private void AddPresetDiagnosticFields(Dictionary<string, object> target, Dictionary<string, object> source, string option, string[] fields)
        {
            if (!PresetOption(option)) return;
            foreach (string field in fields) if (source.ContainsKey(field) && source[field] != null) target[field] = source[field];
        }

        private Dictionary<string, object> PresetReportData()
        {
            Dictionary<string, object> report = new Dictionary<string, object>();
            report["version"] = "R3.2.33";
            report["createdUtc"] = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture);
            report["options"] = PresetOptionsData();
            report["resolvedSelection"] = _presetDetails;
            report["selectedPreset"] = _selectedPreset;
            report["requestedProfiles"] = _overlayButtons.Where(pair => pair.Value.IsChecked == true).Select(pair => pair.Key).ToArray();
            report["readOnly"] = true;
            return report;
        }

        private static string PrettyPresetJson(object value)
        {
            string raw = new System.Web.Script.Serialization.JavaScriptSerializer().Serialize(value);
            System.Text.StringBuilder output = new System.Text.StringBuilder();
            int indent = 0; bool quoted = false; bool escaped = false;
            foreach (char c in raw)
            {
                if (quoted)
                {
                    output.Append(c);
                    if (escaped) escaped = false;
                    else if (c == '\\') escaped = true;
                    else if (c == '"') quoted = false;
                    continue;
                }
                if (c == '"') { quoted = true; output.Append(c); }
                else if (c == '{' || c == '[') { output.Append(c).AppendLine(); indent++; output.Append(' ', indent * 2); }
                else if (c == '}' || c == ']') { output.AppendLine(); indent--; output.Append(' ', indent * 2).Append(c); }
                else if (c == ',') { output.Append(c).AppendLine().Append(' ', indent * 2); }
                else if (c == ':') output.Append(": ");
                else output.Append(c);
            }
            return output.ToString();
        }

        private static void WritePresetJson(string path, object value)
        {
            System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path));
            System.IO.File.WriteAllText(path, PrettyPresetJson(value), new System.Text.UTF8Encoding(false));
        }

        private void ExportPresetOptions()
        {
            try
            {
                var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "WinSlim-Presets-R3.2.33.json", Filter = "JSON (*.json)|*.json", DefaultExt = ".json" };
                if (dialog.ShowDialog(_window) != true) return;
                WritePresetJson(dialog.FileName, PresetReportData());
                SetText("TxtAdvancedStatus", "Configurações exportadas: " + dialog.FileName);
            }
            catch (Exception ex) { SetText("TxtAdvancedStatus", "Falha ao exportar: " + ex.Message); Program.SafeLog(_logPath, "OptionsExport", ex.Message); }
        }

        private void LogPresetSelection(Dictionary<string, object> resolved)
        {
            string detail = "Perfil=" + _selectedPreset;
            if (PresetOption("DetailedLog")) detail += "; total=" + GetInt(resolved, "selectedCount", 0) + "; overlays=" + GetInt(resolved, "enabledOverlayCount", 0) + "; fingerprint=" + GetString(resolved, "fingerprint", "—");
            Program.SafeLog(_logPath, "Selection", detail);
            if (PresetOption("AutoReport"))
            {
                try
                {
                    WritePresetJson(System.IO.Path.Combine(_rootPath, "reports", "preset-selection-latest.json"), PresetReportData());
                    SetText("TxtAdvancedStatus", "Relatório atualizado em reports/preset-selection-latest.json.");
                }
                catch (Exception ex) { SetText("TxtAdvancedStatus", "Falha no relatório automático: " + ex.Message); Program.SafeLog(_logPath, "AutoReport", ex.Message); }
            }
        }

        private async Task RefreshPresetLogsAsync()
        {
            try
            {
                string text = await Task.Run(delegate
                {
                    if (!System.IO.File.Exists(_logPath)) return "Nenhum evento registrado nesta versão.";
                    Queue<string> lines = new Queue<string>();
                    foreach (string line in System.IO.File.ReadLines(_logPath)) { lines.Enqueue(line); if (lines.Count > 200) lines.Dequeue(); }
                    return String.Join(Environment.NewLine, lines);
                });
                if (_disposed) return;
                Find<TextBox>("TxtPresetLogs").Text = text;
                SetText("TxtPresetLogStatus", "Atualizado às " + DateTime.Now.ToString("HH:mm:ss") + " · últimas 200 linhas.");
            }
            catch (Exception ex) { if (!_disposed) SetText("TxtPresetLogStatus", "Falha ao ler logs: " + ex.Message); }
        }

        private void ExportPresetLogs()
        {
            try
            {
                if (!System.IO.File.Exists(_logPath)) { SetText("TxtPresetLogStatus", "Nenhum arquivo de log disponível para exportar."); return; }
                var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "WinSlim-Logs-R3.2.33.log", Filter = "Log (*.log)|*.log", DefaultExt = ".log" };
                if (dialog.ShowDialog(_window) != true) return;
                if (!String.Equals(System.IO.Path.GetFullPath(dialog.FileName), System.IO.Path.GetFullPath(_logPath), StringComparison.OrdinalIgnoreCase)) System.IO.File.Copy(_logPath, dialog.FileName, true);
                SetText("TxtPresetLogStatus", "Logs exportados: " + dialog.FileName);
            }
            catch (Exception ex) { SetText("TxtPresetLogStatus", "Falha ao exportar logs: " + ex.Message); }
        }

        private void SetTextButton(string name, string text)
        {
            Find<Button>(name).Content = text;
        }

        internal void PreparePresetsValidation()
        {
            Navigate("Presets", true);
            SelectPresetTab("General");
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
            _presetDetails = null;
            UpdatePresetDiagnostics();
            SetText("TxtResolveState", "Calculando seleção...");
            Find<Button>("BtnPreviewFromPreset").IsEnabled = false;
            SetText("TxtSummaryTotal", "Calculando...");
            SetText("TxtSummaryFingerprint", "—");
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
            int requestVersion = _resolveVersion;
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
                if (requestVersion != _resolveVersion || _disposed) return;
                int enabledOverlayCount = GetInt(resolved, "enabledOverlayCount", 0);
                int selectedCount = GetInt(resolved, "selectedCount", 0);
                int blockedCount = GetInt(resolved, "blockedCount", 0);
                int warningCount = GetInt(resolved, "warningCount", 0);
                bool canResolve = GetBool(resolved, "canResolve", false);
                string fingerprint = GetString(resolved, "fingerprint", "—");

                SetText("TxtSummaryOverlays", enabledOverlayCount.ToString(CultureInfo.InvariantCulture));
                SetText("TxtSummaryTotal", selectedCount.ToString(CultureInfo.InvariantCulture) + " tweaks");
                _presetDetails = resolved;
                SyncCustomPreset(resolved);
                UpdatePresetDiagnostics();
                LogPresetSelection(resolved);
                SetText("TxtSummaryFingerprint", fingerprint);
                Find<TextBlock>("TxtSummaryFingerprint").ToolTip = fingerprint;

                bool highRiskRequested = selectedProfiles.Any(delegate(string p) { return _highRiskProfiles.Contains(p); });
                bool needsConsent = ContainsBlockedCode(resolved, "HighRiskConsentRequired");
                FrameworkElement banner = Find<FrameworkElement>("HighRiskBanner");
                banner.Visibility = needsConsent ? Visibility.Visible : Visibility.Collapsed;

                if (needsConsent || warningCount > 0 || (highRiskRequested && _allowHighRisk)) SetRisk("Alto", "#FF6B7E");
                else if (enabledOverlayCount > 0) SetRisk("Médio", "#FFC107");
                else SetRisk("Baixo", "#14C767");

                Button preview = Find<Button>("BtnPreviewFromPreset");
                preview.IsEnabled = canResolve;
                if (canResolve)
                    SetText("TxtResolveState", "✓ Seleção pronta para revisão. Nenhuma alteração aplicada.");
                else
                    SetText("TxtResolveState", "⚠ " + blockedCount.ToString(CultureInfo.InvariantCulture) + " bloqueio(s). Revise consentimento/conflitos.");
            }
            catch (Exception ex)
            {
                if (requestVersion != _resolveVersion || _disposed) return;
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

        private void WireBackupInteractions()
        {
            Find<Button>("NavBackup").Click += async delegate { await LoadBackupsAsync(); };
            Find<Button>("BtnBackupRefresh").Click += async delegate { await LoadBackupsAsync(); };
            Find<Button>("BtnBackupDemo").Click += async delegate {
                if (_backupDemo) await LoadBackupsAsync(); else PrepareBackupDemo();
            };
            Find<Button>("BtnBackupTabBackups").Click += delegate { SelectBackupTab(false); };
            Find<Button>("BtnBackupTabTweaks").Click += delegate { SelectBackupTab(true); };
            Find<ListBox>("ListBackups").SelectionChanged += delegate {
                ListBoxItem item = Find<ListBox>("ListBackups").SelectedItem as ListBoxItem;
                _selectedBackup = item == null ? null : item.Tag as BackupViewEntry;
                RenderBackupTweaks(); UpdateBackupSelection();
            };
            Find<ListBox>("ListBackupTweaks").SelectionChanged += delegate { UpdateBackupSelection(); };
            Find<Button>("BtnBackupDetails").Click += delegate { ShowBackupDetails(); };
        }

        internal void PrepareBackupDemo()
        {
            _backupLoadVersion++;
            _backupDemo = true;
            _backupEntries.Clear();
            string[] dates = { "24/09/2026 16:20", "23/09/2026 21:43", "21/09/2026 16:12", "20/09/2026 12:05" };
            string[] profiles = { "Gamer", "Equilibrado", "Custom", "Gamer" };
            int[] counts = { 54, 31, 15, 46 };
            for (int i = 0; i < dates.Length; i++)
            {
                BackupViewEntry entry = new BackupViewEntry { Date = dates[i], Profile = profiles[i], Id = "DEMO-BACKUP-" + (i + 1), Demo = true, Status = "✓ Verificado", Path = "Exemplo visual; nenhum arquivo de backup foi criado." };
                for (int t = 0; t < counts[i]; t++)
                    entry.Tweaks.Add(new Dictionary<string, object> { { "TweakId", "DEMO-" + (t + 1).ToString("D3") }, { "Name", "Ajuste de exemplo " + (t + 1) }, { "BackupFile", "Exemplo visual" }, { "Status", "Exemplo" } });
                _backupEntries.Add(entry);
            }
            RenderBackups(); SelectBackupTab(false); Navigate("Backup", true);
            SetText("TxtBackupState", "Demonstração visual · backups, contagens e verificação ilustrativos · nenhuma alteração no Windows.");
        }

        private async Task LoadBackupsAsync()
        {
            int version = ++_backupLoadVersion;
            _backupDemo = false;
            Find<Button>("BtnBackupRefresh").IsEnabled = false;
            Find<Button>("BtnBackupDemo").IsEnabled = false;
            _backupEntries.Clear(); RenderBackups();
            SetText("TxtBackupState", "Consultando os backups existentes...");
            try
            {
                int skipped = 0;
                List<BackupViewEntry> entries = await Task.Run(delegate { return ReadBackupInventory(System.IO.Path.Combine(_rootPath, "Transactions"), out skipped); });
                if (_disposed || version != _backupLoadVersion) return;
                _backupEntries.AddRange(entries); RenderBackups();
                SetText("TxtBackupState", "Modo de consulta · " + entries.Count + " backups com referência salva · integridade não verificada." +
                    (skipped > 0 ? " " + skipped + " registros não puderam ser lidos." : ""));
            }
            catch (Exception ex)
            {
                if (!_disposed && version == _backupLoadVersion)
                {
                    SetText("TxtBackupEmpty", "Não foi possível consultar os backups. Clique em Atualizar para tentar novamente.");
                    SetText("TxtBackupState", "Falha na consulta: " + ex.Message);
                }
            }
            finally
            {
                if (!_disposed && version == _backupLoadVersion)
                {
                    Find<Button>("BtnBackupRefresh").IsEnabled = true;
                    Find<Button>("BtnBackupDemo").IsEnabled = true;
                }
            }
        }

        private static List<BackupViewEntry> ReadBackupInventory(string directory, out int skipped)
        {
            skipped = 0;
            List<BackupViewEntry> entries = new List<BackupViewEntry>();
            if (!Directory.Exists(directory)) return entries;
            foreach (string folder in Directory.EnumerateDirectories(directory))
            {
                try
                {
                    // Only JSON metadata is read. Backup payloads are never executed or deserialized.
                    if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0) continue;
                    string metadataFile = System.IO.Path.Combine(folder, "transaction.json");
                    string operationsFile = System.IO.Path.Combine(folder, "operations.json");
                    if (!File.Exists(metadataFile) || !File.Exists(operationsFile)) continue;
                    Dictionary<string, object> metadata = ReadBackupJson(metadataFile) as Dictionary<string, object>;
                    object[] operations = ReadBackupJson(operationsFile) as object[];
                    if (metadata == null || operations == null) throw new InvalidDataException("Formato de backup inválido.");
                    if (!String.Equals(GetString(metadata, "Mode", ""), "Apply", StringComparison.OrdinalIgnoreCase)) continue;
                    BackupViewEntry entry = new BackupViewEntry { Id = GetString(metadata, "Id", System.IO.Path.GetFileName(folder)), Date = GetString(metadata, "CreatedAt", "Não informado"), Profile = "Não informado", Status = "Não verificado", Path = folder, Metadata = metadata };
                    DateTime timestamp;
                    if (DateTime.TryParse(entry.Date, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out timestamp))
                    { entry.SortDate = timestamp; entry.Date = timestamp.ToLocalTime().ToString("dd/MM/yyyy HH:mm"); }
                    foreach (object value in operations)
                    {
                        Dictionary<string, object> step = value as Dictionary<string, object>;
                        if (step == null || String.IsNullOrWhiteSpace(GetString(step, "BackupFile", ""))) continue;
                        Dictionary<string, object> tweak;
                        object tweakValue;
                        tweak = step.TryGetValue("Tweak", out tweakValue) ? tweakValue as Dictionary<string, object> : null;
                        entry.Tweaks.Add(new Dictionary<string, object> {
                            { "TweakId", GetString(step, "TweakId", "Não informado") },
                            { "Name", tweak == null ? "Nome não informado" : GetString(tweak, "name", "Nome não informado") },
                            { "BackupFile", GetString(step, "BackupFile", "") }, { "Status", GetString(step, "Status", "Não informado") }
                        });
                    }
                    if (entry.Tweaks.Count > 0) entries.Add(entry);
                }
                catch (Exception) { skipped++; }
            }
            return entries.OrderByDescending(e => e.SortDate).ThenBy(e => e.Id).ToList();
        }

        internal static void ValidateBackupInventoryReader()
        {
            string temp = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "WinSlim-Backup-SelfTest-" + Guid.NewGuid().ToString("N"));
            try
            {
                string folder = System.IO.Path.Combine(temp, "apply"); Directory.CreateDirectory(folder);
                File.WriteAllText(System.IO.Path.Combine(folder, "transaction.json"), "{\"Id\":\"test-apply\",\"Mode\":\"Apply\",\"CreatedAt\":\"2026-09-24T16:20:00+00:00\"}");
                File.WriteAllText(System.IO.Path.Combine(folder, "operations.json"), "[{\"TweakId\":\"TEST-001\",\"Tweak\":{\"name\":\"Ajuste salvo\"},\"BackupFile\":\"example.clixml\",\"Status\":\"Applied\"},{\"TweakId\":\"TEST-002\",\"BackupFile\":null}]");
                string undo = System.IO.Path.Combine(temp, "undo"); Directory.CreateDirectory(undo);
                File.WriteAllText(System.IO.Path.Combine(undo, "transaction.json"), "{\"Mode\":\"Undo\"}");
                File.WriteAllText(System.IO.Path.Combine(undo, "operations.json"), "[]");
                string broken = System.IO.Path.Combine(temp, "broken"); Directory.CreateDirectory(broken);
                File.WriteAllText(System.IO.Path.Combine(broken, "transaction.json"), "invalid-json");
                File.WriteAllText(System.IO.Path.Combine(broken, "operations.json"), "[]");
                int skipped;
                List<BackupViewEntry> entries = ReadBackupInventory(temp, out skipped);
                if (entries.Count != 1 || skipped != 1 || entries[0].Demo || entries[0].Profile != "Não informado" ||
                    entries[0].Status != "Não verificado" || entries[0].Tweaks.Count != 1 || GetString(entries[0].Tweaks[0], "Name", "") != "Ajuste salvo")
                    throw new InvalidDataException("Backup: leitura de metadados deve filtrar Undo, dados invalidos e passos sem referencia, sem declarar integridade.");
                if (ReadBackupInventory(System.IO.Path.Combine(temp, "missing"), out skipped).Count != 0 || skipped != 0)
                    throw new InvalidDataException("Backup: inventario ausente deve ficar vazio.");
            }
            finally { if (Directory.Exists(temp)) Directory.Delete(temp, true); }
        }

        private static object ReadBackupJson(string path)
        {
            FileInfo info = new FileInfo(path);
            if (info.Length > 16 * 1024 * 1024 || (info.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Arquivo de metadados não suportado.");
            System.Web.Script.Serialization.JavaScriptSerializer serializer = new System.Web.Script.Serialization.JavaScriptSerializer();
            serializer.MaxJsonLength = 16 * 1024 * 1024;
            return serializer.DeserializeObject(File.ReadAllText(path));
        }

        private ListBoxItem BackupRow(object tag, string[] cells, bool verified)
        {
            Grid grid = new Grid();
            foreach (double weight in new double[] { 2, 1.3, 1, 1.3 }) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(weight, GridUnitType.Star) });
            for (int i = 0; i < cells.Length; i++)
            {
                TextBlock text = new TextBlock { Text = cells[i], Margin = new Thickness(i == 0 ? 0 : 12, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, FontSize = 12, Foreground = Brush(i == 3 ? (verified ? "#14C767" : "#FF9A2E") : "#F5F5F5"), ToolTip = cells[i] };
                if (i == 0)
                {
                    Grid first = new Grid();
                    first.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) }); first.ColumnDefinitions.Add(new ColumnDefinition());
                    Border icon = new Border { Width = 18, Height = 18, CornerRadius = new CornerRadius(4), BorderBrush = Brush("#FF7A00"), BorderThickness = new Thickness(1), HorizontalAlignment = HorizontalAlignment.Left, Child = new TextBlock { Text = "▣", Foreground = Brush("#FF9A2E"), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
                    first.Children.Add(icon); Grid.SetColumn(text, 1); first.Children.Add(text); grid.Children.Add(first);
                }
                else { Grid.SetColumn(text, i); grid.Children.Add(text); }
            }
            return new ListBoxItem { Content = grid, Tag = tag };
        }

        private void RenderBackups()
        {
            _selectedBackup = null;
            ListBox list = Find<ListBox>("ListBackups"); list.Items.Clear();
            foreach (BackupViewEntry entry in _backupEntries)
                list.Items.Add(BackupRow(entry, new string[] { entry.Date, entry.Profile, entry.Tweaks.Count.ToString(), entry.Status }, entry.Demo));
            Find<Button>("BtnBackupDemo").Content = _backupDemo ? "Ver backups reais" : "Ver demonstração";
            if (list.Items.Count > 0) list.SelectedIndex = 0;
            else { RenderBackupTweaks(); UpdateBackupSelection(); }
        }

        internal void SelectBackupTab(bool tweaks)
        {
            _backupTweaksTab = tweaks;
            Find<ListBox>("ListBackups").Visibility = tweaks ? Visibility.Collapsed : Visibility.Visible;
            Find<ListBox>("ListBackupTweaks").Visibility = tweaks ? Visibility.Visible : Visibility.Collapsed;
            Find<Button>("BtnBackupTabBackups").Style = (Style)_window.FindResource(tweaks ? "SecondaryButton" : "PrimaryButton");
            Find<Button>("BtnBackupTabTweaks").Style = (Style)_window.FindResource(tweaks ? "PrimaryButton" : "SecondaryButton");
            string[] labels = tweaks ? new string[] { "ID do tweak", "Ajuste", "Cópia salva", "Status" } : new string[] { "Data / Hora", "Perfil", "Alterações", "Status" };
            for (int i = 0; i < labels.Length; i++) SetText("TxtBackupColumn" + i, labels[i]);
            SetText("TxtBackupHint", tweaks ? "Ajustes do backup selecionado. Volte à aba Backups para escolher outro backup." : "Selecione um backup para consultar os detalhes.");
            UpdateBackupSelection();
        }

        private void RenderBackupTweaks()
        {
            ListBox list = Find<ListBox>("ListBackupTweaks"); list.Items.Clear();
            if (_selectedBackup != null)
                foreach (Dictionary<string, object> tweak in _selectedBackup.Tweaks)
                    list.Items.Add(BackupRow(tweak, new string[] { GetString(tweak, "TweakId", ""), GetString(tweak, "Name", ""), _selectedBackup.Demo ? "Exemplo" : "Referenciada", _selectedBackup.Demo ? "✓ Verificado" : "Não verificado" }, _selectedBackup.Demo));
            if (list.Items.Count > 0) list.SelectedIndex = 0;
        }

        private void UpdateBackupSelection()
        {
            ListBox list = Find<ListBox>(_backupTweaksTab ? "ListBackupTweaks" : "ListBackups");
            Find<Button>("BtnBackupDetails").IsEnabled = _selectedBackup != null && (!_backupTweaksTab || list.SelectedItem != null);
            Find<TextBlock>("TxtBackupEmpty").Visibility = list.Items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            SetText("TxtBackupEmpty", _backupTweaksTab ? "Selecione um backup na aba Backups para consultar os ajustes salvos." : "Nenhum backup encontrado. Os backups reais aparecerão aqui após a integração da aplicação.");
        }

        private void ShowBackupDetails()
        {
            if (_selectedBackup == null) return;
            Dictionary<string, object> details = new Dictionary<string, object> {
                { "modo", _selectedBackup.Demo ? "Demonstração visual; nenhuma cópia foi criada." : "Consulta; integridade e restauração não verificadas." },
                { "id", _selectedBackup.Id }, { "data", _selectedBackup.Date }, { "perfil", _selectedBackup.Profile },
                { "alteracoes", _selectedBackup.Tweaks.Count }, { "local", _selectedBackup.Path }, { "metadados", _selectedBackup.Metadata }
            };
            ListBoxItem selected = Find<ListBox>("ListBackupTweaks").SelectedItem as ListBoxItem;
            details["ajustes"] = _backupTweaksTab && selected != null ? selected.Tag : (object)_selectedBackup.Tweaks;
            UserControl dialog = CreateDetailWindow(_backupTweaksTab ? "Detalhes do tweak salvo" : "Detalhes do backup");
            dialog.Content = new TextBox { Text = PrettyPresetJson(details), IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.NoWrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, Background = Brush("#0C0F10"), Foreground = Brush("#C8CDD5"), BorderBrush = Brush("#2A343C"), FontFamily = new FontFamily("Consolas"), FontSize = 12, Margin = new Thickness(16), Padding = new Thickness(12) };
            ShowReportView(dialog);
        }

        private T CustomFind<T>(string name) where T : class
        {
            return _customWindow.FindName(name) as T;
        }

        private void EnsureCustomWindow()
        {
            if (_customWindow != null) return;
            System.Xml.XmlReaderSettings settings = new System.Xml.XmlReaderSettings();
            settings.DtdProcessing = System.Xml.DtdProcessing.Prohibit; settings.XmlResolver = null;
            using (FileStream stream = File.OpenRead(System.IO.Path.Combine(_rootPath, "src", "UI", "Native", "R3_2_33", "WinSlimCustom.xaml")))
            using (System.Xml.XmlReader reader = System.Xml.XmlReader.Create(stream, settings))
                _customWindow = System.Windows.Markup.XamlReader.Load(reader) as UserControl;
            if (_customWindow == null) throw new InvalidDataException("A janela Personalizado não pôde ser carregada.");
            UserControl current = _customWindow;
            CustomFind<Button>("BtnCustomClose").Click += delegate { _window.Close(); };
            CustomFind<Button>("BtnCustomBack").Click += delegate { LeaveCustomView(); };
            CustomFind<Button>("BtnCustomMinimize").Click += delegate { _window.WindowState = WindowState.Minimized; };
            CustomFind<Button>("BtnCustomMaximize").Click += delegate { ToggleMainWindowSize(); };
            WirePageTitleBar(CustomFind<FrameworkElement>("CustomTitleBar"));
            CustomFind<TextBox>("TxtCustomSearch").TextChanged += delegate { RenderCustomRows(); };
            CustomFind<Button>("BtnCustomClearSearch").Click += delegate { CustomFind<TextBox>("TxtCustomSearch").Clear(); };
            CustomFind<Button>("BtnCustomReset").Click += delegate { ResetCustomSelection(); };
            CustomFind<Button>("BtnCustomEnableCategory").Click += delegate { EnableCustomCategory(); };
            CustomFind<Button>("BtnCustomSave").Click += delegate { SaveCustomPreset(); };
            CustomFind<Button>("BtnCustomImport").Click += delegate { ImportCustomPreset(); };
            CustomFind<Button>("BtnCustomApply").Click += async delegate {
                if (_customSelected.Count == 0) return;
                string[] ids = _customSelected.OrderBy(id => id, StringComparer.OrdinalIgnoreCase).ToArray();
                LeaveCustomView();
                try { await PreparePreviewCoreAsync(ids, _customName); } catch { }
            };

        }

        internal async Task OpenCustomWindowAsync()
        {
            EnsureCustomWindow();
            if (_window.Content != _customWindow) {
                if (_window.Content != _tweakDetailWindow) _customPreviousContent = _window.Content;
                ShowPage(_customWindow);
            }
            UpdatePerformancePolling();

            UserControl target = _customWindow;
            try
            {
                await Ready;
                if (_customCatalog != null) { if (_customWindow == target && _customCategoryButtons.Count == 0) { RenderCustomCategories(); RenderCustomRows(); } return; }
                Dictionary<string, object> catalog = await _bridge.SendAsync("catalog", null, 20000);
                object[] tweaks = GetArray(catalog, "tweaks");
                if (!GetBool(catalog, "readOnly", false)) throw new InvalidDataException("Catálogo deve estar em modo de consulta.");
                SetCustomCatalog(tweaks);
                if (_customWindow == target) { RenderCustomCategories(); RenderCustomRows(); }
            }
            catch (Exception ex)
            {
                if (_customWindow == target)
                {
                    CustomFind<TextBlock>("TxtCustomEmpty").Text = "Não foi possível carregar os ajustes. Feche esta janela e abra Personalizado novamente.";
                    CustomFind<TextBlock>("TxtCustomStatus").Text = "Falha no catálogo: " + ex.Message;
                }
                Program.SafeLog(_logPath, "Custom", ex.ToString());
            }
        }

        internal void SetCustomCatalog(object[] tweaks)
        {
            if (tweaks == null || tweaks.Length != 230) throw new InvalidDataException("Personalizado exige os 230 ajustes do catálogo aprovado.");
            HashSet<string> ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (object value in tweaks)
            {
                Dictionary<string, object> item = value as Dictionary<string, object>;
                string id = item == null ? "" : GetString(item, "id", "");
                if (String.IsNullOrWhiteSpace(id) || !ids.Add(id)) throw new InvalidDataException("Catálogo Personalizado contém ID ausente ou repetido.");
            }
            _customCatalog = tweaks;
        }

        private static string CustomCategoryName(Dictionary<string, object> tweak)
        {
            string category = GetString(tweak, "category", "Outros");
            switch (category)
            {
                case "Responsividade": return "Performance";
                case "Jogos / Workload": return "Gaming";
                case "Performance / CPU": case "Jogos / CPU": return "CPU";
                case "Performance / GPU": return "GPU";
                case "Debloat UWP": return "Apps";
                case "Seguranca": return "Segurança";
                case "UI/QoL": return "UI / QoL";
                case "Extras / Manutenção": return "Manutenção";
                case "Workload": return "Produtividade";
                default: return category;
            }
        }

        private void RenderCustomCategories()
        {
            if (_customWindow == null || _customCatalog == null) return;
            StackPanel panel = CustomFind<StackPanel>("CustomCategories"); panel.Children.Clear(); _customCategoryButtons.Clear();
            List<Dictionary<string, object>> all = _customCatalog.Cast<Dictionary<string, object>>().ToList();
            string[] order = { "Performance", "Gaming", "CPU", "GPU", "Rede", "Privacidade", "Segurança", "Serviços", "UI / QoL", "Windows Update", "Apps", "Microsoft Edge", "Produtividade", "Pesquisa", "Manutenção" };
            List<string> categories = all.Select(CustomCategoryName).Distinct().OrderBy(k => Array.IndexOf(order, k) < 0 ? 999 : Array.IndexOf(order, k)).ThenBy(k => k).ToList();
            if (!categories.Contains(_customCategory)) _customCategory = categories[0];
            foreach (string name in categories)
            {
                string key = name;
                Grid row = new Grid(); row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) }); row.ColumnDefinitions.Add(new ColumnDefinition()); row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(26) });
                TextBlock icon = new TextBlock { Text = CustomCategoryIcon(name), Foreground = Brush("#A9AFB8"), VerticalAlignment = VerticalAlignment.Center, FontSize = 15 };
                TextBlock label = new TextBlock { Text = name, FontSize = 11.5, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
                TextBlock count = new TextBlock { Text = all.Count(t => CustomCategoryName(t) == key).ToString(), FontSize = 11, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right };
                Grid.SetColumn(label, 1); Grid.SetColumn(count, 2); row.Children.Add(icon); row.Children.Add(label); row.Children.Add(count);
                Button button = new Button { Content = row, Style = (Style)_customWindow.FindResource("CustomCategory"), HorizontalContentAlignment = HorizontalAlignment.Stretch, ToolTip = name };
                button.Click += delegate { _customCategory = key; RenderCustomRows(); };
                panel.Children.Add(button); _customCategoryButtons.Add(key, button);
            }
            CustomFind<TextBlock>("TxtCustomCategorySummary").Text = "230 ajustes · " + categories.Count + " categorias";
        }

        private static string CustomCategoryIcon(string category)
        {
            switch (category) { case "Performance": return "ϟ"; case "Gaming": return "♧"; case "CPU": case "GPU": return "▣"; case "Rede": return "◎"; case "Segurança": return "◇"; case "Apps": return "▦"; default: return "⚙"; }
        }

        private void RenderCustomRows(bool preserveScroll = false)
        {
            if (_customWindow == null) return;
            double previousOffset = CustomFind<ScrollViewer>("CustomRowsScroll").VerticalOffset;
            string query = CustomFind<TextBox>("TxtCustomSearch").Text.Trim();
            CustomFind<TextBlock>("CustomSearchPlaceholder").Visibility = query.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            if (_customCatalog == null) return;
            foreach (KeyValuePair<string, Button> pair in _customCategoryButtons)
            { pair.Value.Background = Brush(pair.Key == _customCategory ? "#3A1E0B" : "Transparent"); pair.Value.Foreground = Brush(pair.Key == _customCategory ? "#FF9A2E" : "#C7CCD4"); }
            List<Dictionary<string, object>> category = _customCatalog.Cast<Dictionary<string, object>>().Where(t => CustomCategoryName(t) == _customCategory).ToList();
            List<Dictionary<string, object>> visible = category.Where(t => CustomMatches(t, query)).ToList();
            StackPanel rows = CustomFind<StackPanel>("CustomRows"); rows.Children.Clear();
            foreach (Dictionary<string, object> tweak in visible) rows.Children.Add(CreateCustomTweakRow(tweak));
            if (preserveScroll) CustomFind<ScrollViewer>("CustomRowsScroll").ScrollToVerticalOffset(previousOffset);
            else CustomFind<ScrollViewer>("CustomRowsScroll").ScrollToTop();
            CustomFind<TextBlock>("TxtCustomHeading").Text = "Personalizar Tweaks — " + _customCategory;
            CustomFind<TextBlock>("TxtCustomCount").Text = visible.Count + " de " + category.Count + " ajustes nesta categoria";
            CustomFind<TextBlock>("TxtCustomEmpty").Visibility = visible.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            CustomFind<TextBlock>("TxtCustomEmpty").Text = "Nenhum ajuste corresponde à busca nesta categoria.";
            UpdateCustomSelectionSummary();
        }

        private static bool CustomMatches(Dictionary<string, object> tweak, string query)
        {
            foreach (string field in new string[] { "id", "name", "plainName", "description" })
                if (CultureInfo.GetCultureInfo("pt-BR").CompareInfo.IndexOf(GetString(tweak, field, ""), query, CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace) >= 0) return true;
            return false;
        }

        private FrameworkElement CreateCustomTweakRow(Dictionary<string, object> tweak)
        {
            string id = GetString(tweak, "id", ""); string name = GetString(tweak, "name", id); string risk = GetString(tweak, "risk", "Não informado");
            Grid grid = new Grid { Margin = new Thickness(12, 10, 12, 10), MinHeight = 56 };
            foreach (GridLength width in new GridLength[] { new GridLength(28), new GridLength(1, GridUnitType.Star), new GridLength(70), new GridLength(134) }) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
            TextBlock icon = new TextBlock { Text = "▣", Foreground = Brush("#FF9A2E"), FontSize = 18, VerticalAlignment = VerticalAlignment.Center };
            StackPanel text = new StackPanel { Margin = new Thickness(0, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(new TextBlock { Text = name, FontSize = 13, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, Foreground = Brush("#E5E7EB") });
            text.Children.Add(new TextBlock { Text = GetString(tweak, "plainName", GetString(tweak, "description", "Descrição não informada.")), FontSize = 11, TextWrapping = TextWrapping.Wrap, Foreground = Brush("#A9AFB8"), Margin = new Thickness(0, 4, 0, 0) });
            if (GetBool(tweak, "requiresRestart", false)) text.Children.Add(new TextBlock { Text = "↻ Requer reinício após aplicar", Foreground = Brush("#9099A5"), FontSize = 10, Margin = new Thickness(0, 4, 0, 0) });
            bool low = String.Equals(risk, "Baixo", StringComparison.OrdinalIgnoreCase);
            bool medium = String.Equals(risk, "Médio", StringComparison.OrdinalIgnoreCase) || String.Equals(risk, "Medio", StringComparison.OrdinalIgnoreCase);
            Border badge = new Border { Background = Brush(low ? "#182414" : medium ? "#322608" : "#331215"), BorderBrush = Brush(low ? "#33462B" : medium ? "#695013" : "#73242F"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(4), Padding = new Thickness(7, 3, 7, 3), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Child = new TextBlock { Text = risk, FontSize = 11, Foreground = Brush(low ? "#B2CC88" : medium ? "#FFC107" : "#FF5A61") } };
            ToggleButton toggle = new ToggleButton { Tag = id, Style = (Style)_customWindow.FindResource("CustomTweakSwitch"), IsChecked = _customSelected.Contains(id), Content = _customSelected.Contains(id) ? "Ativado" : "Desativado", VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right };
            System.Windows.Automation.AutomationProperties.SetName(toggle, name);
            toggle.Checked += delegate { _customSelected.Add(id); toggle.Content = "Ativado"; UpdateCustomSelectionSummary(); };
            toggle.Unchecked += delegate { _customSelected.Remove(id); toggle.Content = "Desativado"; UpdateCustomSelectionSummary(); };
            Grid.SetColumn(text, 1); Grid.SetColumn(badge, 2); Grid.SetColumn(toggle, 3);
            grid.Children.Add(icon); grid.Children.Add(text); grid.Children.Add(badge); grid.Children.Add(toggle);
            Border row = new Border { Background = Brush("#0B0E10"), BorderBrush = Brush("#242B30"), BorderThickness = new Thickness(0, 0, 0, 1), Child = grid, Tag = id };
            SetCustomTweakHelp(row, tweak);
            SetCustomTweakHelp(toggle, tweak);
            row.Focusable = true; row.Cursor = Cursors.Hand;
            System.Windows.Automation.AutomationProperties.SetName(row, "Ver detalhes de " + name);
            row.MouseLeftButtonUp += async delegate(object sender, MouseButtonEventArgs e) {
                if (FindVisualParent<ToggleButton>(e.OriginalSource as DependencyObject) != null) return;
                e.Handled = true; await OpenTweakDetailAsync(id);
            };
            row.KeyDown += async delegate(object sender, KeyEventArgs e) {
                if ((e.Key != Key.Enter && e.Key != Key.Space) || FindVisualParent<ToggleButton>(e.OriginalSource as DependencyObject) != null) return;
                e.Handled = true; await OpenTweakDetailAsync(id);
            };
            return row;
        }

        private UserControl LoadTweakDetailWindow(string id)
        {
            System.Xml.XmlReaderSettings settings = new System.Xml.XmlReaderSettings { DtdProcessing = System.Xml.DtdProcessing.Prohibit, XmlResolver = null };
            UserControl dialog;
            using (FileStream stream = File.OpenRead(System.IO.Path.Combine(_rootPath, "src", "UI", "Native", "R3_2_33", "WinSlimTweakDetail.xaml")))
            using (System.Xml.XmlReader reader = System.Xml.XmlReader.Create(stream, settings)) dialog = System.Windows.Markup.XamlReader.Load(reader) as UserControl;
            if (dialog == null) throw new InvalidDataException("Janela de detalhes inválida.");
            dialog.Tag = id;
            ((Button)dialog.FindName("BtnTweakClose")).Click += delegate { _window.Close(); };
            ((Button)dialog.FindName("BtnTweakBack")).Click += delegate { ReturnFromTweak(); };
            ((Button)dialog.FindName("BtnTweakMinimize")).Click += delegate { _window.WindowState = WindowState.Minimized; };
            ((Button)dialog.FindName("BtnTweakMaximize")).Click += delegate { ToggleMainWindowSize(); };
            WirePageTitleBar((FrameworkElement)dialog.FindName("TweakTitleBar"));
            ((Button)dialog.FindName("BtnTweakUndo")).IsEnabled = _customSelected.Contains(id);
            ((Button)dialog.FindName("BtnTweakApply")).IsEnabled = false;
            SetTweakDetailState(dialog, id);
            ((Button)dialog.FindName("BtnTweakUndo")).Click += delegate {
                _customSelected.Remove(id); SetTweakDetailState(dialog, id);
                ((TextBlock)dialog.FindName("TxtTweakDetailStatus")).Text = "Ajuste retirado da seleção · nenhuma configuração do Windows foi restaurada nesta demonstração.";
                if (_customWindow != null) RenderCustomRows(true);
            };
            ((Button)dialog.FindName("BtnTweakApply")).Click += async delegate {
                _customSelected.Add(id);
                if (_customWindow != null) RenderCustomRows(true);
                ReturnFromTweak(); LeaveCustomView();
                try { await PreparePreviewCoreAsync(new string[] { id }, "Personalizado · " + id); } catch { }
            };

            return dialog;
        }

        internal async Task OpenTweakDetailAsync(string id)
        {
            UserControl pendingView = null;
            try {
                if (_tweakDetailWindow != null && _window.Content == _tweakDetailWindow) return;
                if (_customCatalog == null) await OpenCustomWindowAsync();
                Dictionary<string, object> tweak = _customCatalog == null ? null : _customCatalog.Cast<Dictionary<string, object>>().FirstOrDefault(t => GetString(t, "id", "").Equals(id, StringComparison.OrdinalIgnoreCase));
                if (tweak == null) throw new InvalidDataException("Ajuste não encontrado: " + id);
                UserControl dialog = LoadTweakDetailWindow(id); pendingView = dialog; _tweakDetailWindow = dialog;
                ((TextBlock)dialog.FindName("TxtTweakName")).Text = GetString(tweak, "name", id);
                ((TextBlock)dialog.FindName("TxtTweakDescription")).Text = GetString(tweak, "description", GetString(tweak, "plainName", ""));
                ShowPage(dialog);
                await Ready;
                Dictionary<string, object> request = new Dictionary<string, object> { { "tweakId", id } };
                Dictionary<string, object> data = await _bridge.SendAsync("tweakDetails", request, 60000);
                if (_disposed || _tweakDetailWindow != dialog) return;
                RenderTweakDetail(dialog, data, id);
            } catch (Exception ex) {
                if (pendingView != null && _tweakDetailWindow == pendingView) {
                    ((TextBlock)_tweakDetailWindow.FindName("TxtTweakWarning")).Text = "Não foi possível verificar os detalhes: " + ex.Message;
                    ((Button)_tweakDetailWindow.FindName("BtnTweakApply")).IsEnabled = false;
                }
                Program.SafeLog(_logPath, "TweakDetail", ex.ToString());
            }
        }

        private void SetTweakDetailState(UserControl dialog, string id)
        {
            bool selected = _customSelected.Contains(id);
            ((TextBlock)dialog.FindName("TxtTweakState")).Text = selected ? "Ativo" : "Inativo";
            ((TextBlock)dialog.FindName("TxtTweakState")).Foreground = Brush(selected ? "#36E493" : "#A9AFB8");
            ((System.Windows.Shapes.Ellipse)dialog.FindName("TweakStateDot")).Fill = Brush(selected ? "#00C853" : "#717780");
            ((Border)dialog.FindName("TweakStateBadge")).Background = Brush(selected ? "#052415" : "#171A1D");
            ((Border)dialog.FindName("TweakStateBadge")).BorderBrush = Brush(selected ? "#095D32" : "#42474D");
            ((Button)dialog.FindName("BtnTweakUndo")).IsEnabled = selected;
        }

        private void RenderTweakDetail(UserControl dialog, Dictionary<string, object> data, string id)
        {
            Dictionary<string, object> tweak = PreviewObject(data, "tweak"), app = PreviewObject(data, "applicability");
            if (!GetBool(data, "readOnly", false) || tweak == null || app == null || GetString(tweak, "id", "") != id) throw new InvalidDataException("Resposta de detalhes inválida.");
            ((TextBlock)dialog.FindName("TxtTweakName")).Text = GetString(tweak, "name", id);
            ((TextBlock)dialog.FindName("TxtTweakDescription")).Text = GetString(tweak, "description", GetString(tweak, "plainName", "Descrição não informada."));
            ((TextBlock)dialog.FindName("TxtTweakBadge")).Text = GetBool(tweak, "experimental", false) ? "◈ Experimental" : "◈ " + CustomCategoryName(tweak);
            string risk = GetString(tweak, "risk", "Não informado");
            TextBlock riskText = (TextBlock)dialog.FindName("TxtTweakRisk"); riskText.Text = risk;
            riskText.Foreground = Brush(risk == "Baixo" ? "#00C853" : risk == "Alto" ? "#FF1744" : "#FFC107");
            ((TextBlock)dialog.FindName("TxtTweakRestart")).Text = GetBool(tweak, "requiresRestart", false) ? "Sim" : "Não";
            ((TextBlock)dialog.FindName("TxtTweakRollback")).Text = GetString(data, "rollbackText", "Não informado");
            bool compatible = GetString(app, "Decision", "") == "Apply";
            TextBlock compatibility = (TextBlock)dialog.FindName("TxtTweakCompatibility");
            compatibility.Text = compatible ? "✓ Compatível" : GetString(app, "Decision", "") == "Skip" ? "Não compatível" : "Não confirmado / bloqueado";
            compatibility.Foreground = Brush(compatible ? "#00C853" : "#FFC107");
            ((TextBlock)dialog.FindName("TxtTweakHardware")).Text = GetString(data, "hardwareText", "Não informado");
            ((TextBlock)dialog.FindName("TxtTweakDependencies")).Text = DetailNames(data, "dependencyNames", "Nenhuma");
            ((TextBlock)dialog.FindName("TxtTweakConflicts")).Text = DetailNames(data, "conflictNames", "Nenhum");
            ((TextBlock)dialog.FindName("TxtTweakWarning")).Text = GetString(data, "warning", "Confira o risco antes de continuar.");
            ((Button)dialog.FindName("BtnTweakApply")).IsEnabled = true; // Preview remains available even when applicability is blocked.
            SetTweakDetailState(dialog, id);
        }

        private static string DetailNames(Dictionary<string, object> data, string key, string empty)
        {
            object[] values = GetArray(data, key) ?? new object[0];
            return values.Length == 0 ? empty : String.Join(", ", values.Select(value => Convert.ToString(value)).ToArray());
        }

        internal void ValidateTweakDetail(Dictionary<string, object> data)
        {
            Dictionary<string, object> tweak = PreviewObject(data, "tweak"); string id = GetString(tweak, "id", "");
            _customSelected.Add(id);
            UserControl dialog = LoadTweakDetailWindow(id); RenderTweakDetail(dialog, data, id);
            FrameworkElement content = dialog.Content as FrameworkElement;
            content.Measure(new Size(1178, 758)); content.Arrange(new Rect(0, 0, 1178, 758)); content.UpdateLayout();
            if (_window.Width != 1180 || _window.Height != 760 || ((TextBlock)dialog.FindName("TxtTweakName")).Text != GetString(tweak, "name", ""))
                throw new InvalidDataException("Detalhe: dimensão ou nome incorreto.");
            foreach (string name in new string[] { "Risk", "Restart", "Rollback", "Compatibility", "Hardware", "Dependencies", "Conflicts" })
                if (String.IsNullOrWhiteSpace(((TextBlock)dialog.FindName("TxtTweak" + name)).Text)) throw new InvalidDataException("Detalhe sem informação: " + name);
            ((Button)dialog.FindName("BtnTweakUndo")).IsEnabled = true;
            ((Button)dialog.FindName("BtnTweakUndo")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if (_customSelected.Contains(id) || ((TextBlock)dialog.FindName("TxtTweakState")).Text != "Inativo") throw new InvalidDataException("Desfazer deve retirar o ID e atualizar o estado.");
        }

        private void SyncCustomPreset(Dictionary<string, object> resolved)
        {
            string fingerprint = GetString(resolved, "fingerprint", "");
            if (!GetBool(resolved, "canResolve", false) || fingerprint.Length == 0 || fingerprint == _customBaseFingerprint) return;
            object[] tweaks = GetArray(resolved, "selectedTweaks") ?? new object[0];
            HashSet<string> ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (Dictionary<string, object> tweak in tweaks.Cast<Dictionary<string, object>>())
            {
                string id = GetString(tweak, "id", "");
                if (id.Length == 0 || !ids.Add(id)) throw new InvalidDataException("Seleção do preset inválida.");
            }
            _customLevels.Clear();
            Dictionary<string, object> levels = PreviewObject(resolved, "levelSelections");
            if (levels != null) foreach (KeyValuePair<string, object> pair in levels) _customLevels[pair.Key] = Convert.ToInt32(pair.Value, CultureInfo.InvariantCulture);
            _customBaseFingerprint = fingerprint;
            _customBaseName = GetString(resolved, "presetName", "Balanceado");
            _customName = (_customBaseName == "Balanceado" ? "Equilibrado" : _customBaseName) + " personalizado";
            _customBaseIds.Clear(); _customBaseIds.UnionWith(ids);
            _customSelected.Clear(); _customSelected.UnionWith(ids);
            if (_customWindow != null && _customCatalog != null) RenderCustomRows();
        }

        private Dictionary<string, int> EffectiveCustomLevels()
        {
            Dictionary<string, int> levels = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            if (_customCatalog == null) return levels;
            foreach (Dictionary<string, object> tweak in _customCatalog.Cast<Dictionary<string, object>>()) {
                string id = GetString(tweak, "id", "");
                if (!_customSelected.Contains(id) || CustomLevelCount(tweak) == 0) continue;
                int level; levels[id] = _customLevels.TryGetValue(id, out level) ? level : 0;
            }
            return levels;
        }

        private static int CustomLevelCount(Dictionary<string, object> tweak)
        {
            object[] levels = GetArray(tweak, "levels");
            return GetInt(tweak, "levelCount", levels == null ? 0 : levels.Length);
        }

        private Dictionary<string, object> CreateCustomPresetDocument()
        {
            return new Dictionary<string, object> {
                { "schema", "WinSlim.CustomPreset/v1" }, { "name", _customName },
                { "basePreset", _customBaseName }, { "catalogCount", 230 },
                { "selectedIds", _customSelected.OrderBy(id => id, StringComparer.OrdinalIgnoreCase).ToArray() }, { "levelSelections", EffectiveCustomLevels() }
            };
        }

        private void LoadCustomPresetDocument(Dictionary<string, object> document)
        {
            if (_customCatalog == null || document == null || GetString(document, "schema", "") != "WinSlim.CustomPreset/v1")
                throw new InvalidDataException("Este arquivo não é um preset personalizado compatível.");
            string[] allowed = { "schema", "name", "basePreset", "catalogCount", "selectedIds", "levelSelections" };
            if (document.Keys.Any(key => !allowed.Contains(key))) throw new InvalidDataException("O arquivo contém campos não permitidos. Exporte apenas a seleção dos ajustes.");
            object[] values = GetArray(document, "selectedIds");
            if (values == null || values.Length > 230) throw new InvalidDataException("A lista de ajustes é inválida.");
            HashSet<string> known = new HashSet<string>(_customCatalog.Cast<Dictionary<string, object>>().Select(t => GetString(t, "id", "")), StringComparer.OrdinalIgnoreCase);
            HashSet<string> ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (object value in values)
            {
                string id = value as string;
                if (id == null || !known.Contains(id) || !ids.Add(id)) throw new InvalidDataException("Ajuste desconhecido ou repetido: " + Convert.ToString(value));
            }
            Dictionary<string, int> levels = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            Dictionary<string, object> inputLevels = PreviewObject(document, "levelSelections");
            if (document.ContainsKey("levelSelections") && inputLevels == null) throw new InvalidDataException("Níveis dos ajustes inválidos.");
            if (inputLevels != null) foreach (KeyValuePair<string, object> pair in inputLevels) {
                Dictionary<string, object> tweak = _customCatalog.Cast<Dictionary<string, object>>().FirstOrDefault(t => GetString(t, "id", "").Equals(pair.Key, StringComparison.OrdinalIgnoreCase));
                if (!ids.Contains(pair.Key) || tweak == null || !(pair.Value is int) || (int)pair.Value < 0 || (int)pair.Value >= CustomLevelCount(tweak))
                    throw new InvalidDataException("Nível desconhecido ou inválido: " + pair.Key);
                levels[pair.Key] = (int)pair.Value;
            }
            string name = GetString(document, "name", "Preset importado").Trim();
            if (name.Length == 0 || name.Length > 80 || name.Any(char.IsControl)) throw new InvalidDataException("O nome do preset deve ter entre 1 e 80 caracteres.");
            string baseName = GetString(document, "basePreset", "Custom");
            if (!new string[] { "Balanceado", "Gamer", "Extremo", "Custom" }.Contains(baseName)) throw new InvalidDataException("Preset base inválido.");
            // Validate the entire document before changing any selection. No code is imported.
            _customSelected.Clear(); _customSelected.UnionWith(ids);
            _customBaseIds.Clear(); _customBaseIds.UnionWith(ids);
            _customBaseName = baseName; _customName = name;
            _customLevels.Clear(); foreach (KeyValuePair<string, int> pair in levels) _customLevels[pair.Key] = pair.Value;
            if (_customWindow != null) RenderCustomRows();
        }

        private void SaveCustomPreset()
        {
            if (_customCatalog == null || _customWindow == null) return;
            Microsoft.Win32.SaveFileDialog dialog = new Microsoft.Win32.SaveFileDialog {
                Title = "Salvar preset para usar em outro sistema", Filter = "Preset Win-Slim (*.json)|*.json", DefaultExt = ".json", AddExtension = true,
                FileName = "WinSlim-Preset-Custom.json", OverwritePrompt = true
            };
            if (dialog.ShowDialog(_window) != true) return;
            try {
                File.WriteAllText(dialog.FileName, PrettyPresetJson(CreateCustomPresetDocument()), new System.Text.UTF8Encoding(false));
                CustomFind<TextBlock>("TxtCustomStatus").Text = "Preset salvo. No outro PC, use Importar preset e confira a pré-visualização.";
            } catch (Exception ex) { MessageBox.Show(_window, "Não foi possível salvar: " + ex.Message, "Salvar preset", MessageBoxButton.OK, MessageBoxImage.Error); }
        }

        private void ImportCustomPreset()
        {
            if (_customCatalog == null || _customWindow == null) return;
            Microsoft.Win32.OpenFileDialog dialog = new Microsoft.Win32.OpenFileDialog { Title = "Importar preset personalizado", Filter = "Preset Win-Slim (*.json)|*.json", CheckFileExists = true };
            if (dialog.ShowDialog(_window) != true) return;
            try {
                if (new FileInfo(dialog.FileName).Length > 1024 * 1024) throw new InvalidDataException("O arquivo excede o tamanho permitido de 1 MB.");
                LoadCustomPresetDocument(ReadBackupJson(dialog.FileName) as Dictionary<string, object>);
                CustomFind<TextBlock>("TxtCustomStatus").Text = "Preset importado · confira os ajustes e a compatibilidade na pré-visualização.";
            } catch (Exception ex) { MessageBox.Show(_window, "Não foi possível importar: " + ex.Message, "Importar preset", MessageBoxButton.OK, MessageBoxImage.Error); }
        }

        internal void ValidateCustomPresetIntegration(Dictionary<string, object> resolved)
        {
            SyncCustomPreset(resolved);
            HashSet<string> expected = new HashSet<string>((GetArray(resolved, "selectedTweaks") ?? new object[0]).Cast<Dictionary<string, object>>().Select(t => GetString(t, "id", "")), StringComparer.OrdinalIgnoreCase);
            if (!_customSelected.SetEquals(expected)) throw new InvalidDataException("Personalizado não foi inicializado com os IDs do preset.");
            string removed = expected.First(); _customSelected.Remove(removed);
            string added = _customCatalog.Cast<Dictionary<string, object>>().Select(t => GetString(t, "id", "")).First(id => !expected.Contains(id));
            _customSelected.Add(added); HashSet<string> edited = new HashSet<string>(_customSelected, StringComparer.OrdinalIgnoreCase);
            SyncCustomPreset(resolved);
            if (!_customSelected.SetEquals(edited)) throw new InvalidDataException("Nova resolução do mesmo preset perdeu as edições.");
            EnsureCustomWindow(); RenderCustomCategories(); RenderCustomRows();
            if (!CustomFind<Button>("BtnCustomApply").IsEnabled) throw new InvalidDataException("Seleção customizada deve permitir continuar para a prévia.");
            ResetCustomSelection();
            if (!_customSelected.SetEquals(expected)) throw new InvalidDataException("Restaurar padrão deve recuperar o preset base.");
            _customSelected.Clear(); _customSelected.UnionWith(edited);
            string levelsBefore = PrettyPresetJson(EffectiveCustomLevels());
            string json = PrettyPresetJson(CreateCustomPresetDocument());
            System.Web.Script.Serialization.JavaScriptSerializer serializer = new System.Web.Script.Serialization.JavaScriptSerializer();
            Dictionary<string, object> portable = serializer.DeserializeObject(json) as Dictionary<string, object>;
            LoadCustomPresetDocument(portable);
            if (!_customSelected.SetEquals(edited) || PrettyPresetJson(EffectiveCustomLevels()) != levelsBefore) throw new InvalidDataException("Exportação/importação alterou os IDs ou os níveis.");
            foreach (object[] badIds in new object[][] { new object[] { "UNKNOWN-999" }, new object[] { removed, removed }, new object[] { 123 } }) {
                Dictionary<string, object> bad = new Dictionary<string, object>(portable); bad["selectedIds"] = badIds;
                bool rejected = false; try { LoadCustomPresetDocument(bad); } catch (InvalidDataException) { rejected = true; }
                if (!rejected || !_customSelected.SetEquals(edited)) throw new InvalidDataException("Importação inválida deve preservar a seleção atual.");
            }
            Dictionary<string, object> unsafeDoc = new Dictionary<string, object>(portable); unsafeDoc["commands"] = "unexpected";
            bool unsafeRejected = false; try { LoadCustomPresetDocument(unsafeDoc); } catch (InvalidDataException) { unsafeRejected = true; }
            if (!unsafeRejected) throw new InvalidDataException("Importação deve rejeitar código/ campos extras.");
            LeaveCustomView();
            _customBaseFingerprint = "";
        }

        private void SetCustomTweakHelp(FrameworkElement target, Dictionary<string, object> tweak)
        {
            string name = GetString(tweak, "name", GetString(tweak, "id", "Ajuste"));
            string explanation = GetString(tweak, "plainName", GetString(tweak, "description", "Descrição não informada."));
            string text = name + "\n\n" + explanation + "\n\nRisco: " + GetString(tweak, "risk", "Não informado") + ".";
            if (GetBool(tweak, "requiresRestart", false)) text += " Requer reiniciar o PC após aplicar.";
            target.ToolTip = new ToolTip {
                Background = Brush("#111111"), Foreground = Brush("#E5E7EB"),
                BorderBrush = Brush("#FF7A00"), BorderThickness = new Thickness(1), Padding = new Thickness(12),
                Placement = PlacementMode.MousePoint,
                Content = new TextBlock { Text = text, Width = 300, TextWrapping = TextWrapping.Wrap, FontSize = 12, Foreground = Brush("#E5E7EB") }
            };
            ToolTipService.SetInitialShowDelay(target, 800);
            ToolTipService.SetShowDuration(target, 20000);
            ToolTipService.SetBetweenShowDelay(target, 200);
            ToolTipService.SetShowOnDisabled(target, true);
        }

        private void UpdateCustomSelectionSummary()
        {
            if (_customWindow == null) return;
            int categoryTotal = _customCatalog == null ? 0 : _customCatalog.Cast<Dictionary<string, object>>().Count(t => CustomCategoryName(t) == _customCategory);
            int categorySelected = _customCatalog == null ? 0 : _customCatalog.Cast<Dictionary<string, object>>().Count(t => CustomCategoryName(t) == _customCategory && _customSelected.Contains(GetString(t, "id", "")));
            CustomFind<Button>("BtnCustomEnableCategory").IsEnabled = categoryTotal > 0 && categorySelected < categoryTotal;
            if (_tweakDetailWindow != null) SetTweakDetailState(_tweakDetailWindow, Convert.ToString(_tweakDetailWindow.Tag));
            CustomFind<TextBlock>("TxtCustomSelection").Text = _customSelected.Count + " selecionados · " + categorySelected + " de " + categoryTotal + " nesta categoria";
            CustomFind<Button>("BtnCustomApply").IsEnabled = _customCatalog != null && _customSelected.Count > 0;
            CustomFind<Button>("BtnCustomSave").IsEnabled = _customCatalog != null;
            CustomFind<Button>("BtnCustomImport").IsEnabled = _customCatalog != null;
            CustomFind<TextBlock>("TxtCustomStatus").Text = _customName + " · " + _customSelected.Count + " selecionados · revisar antes de continuar";
        }

        private void EnableCustomCategory()
        {
            if (_customCatalog == null || _customWindow == null) return;
            foreach (Dictionary<string, object> tweak in _customCatalog.Cast<Dictionary<string, object>>())
                if (CustomCategoryName(tweak) == _customCategory) _customSelected.Add(GetString(tweak, "id", ""));
            RenderCustomRows();
        }

        private void ResetCustomSelection()
        {
            _customSelected.Clear(); _customSelected.UnionWith(_customBaseIds); RenderCustomRows();
        }

        internal void ValidateCustomWindow()
        {
            // Read identical metadata from the approved files for the offline visual self-test.
            List<object> all = new List<object>();
            foreach (string relative in new string[] { "catalog.json", "catalogs/Game-Workload.json", "catalogs/validated/Advanced-Catalog.json", "catalogs/validated/Expansion-R4.json", "catalogs/validated/Expansion-R4.1.json", "catalogs/validated/Expansion-R4.2.json" })
            {
                object parsed = ReadBackupJson(System.IO.Path.Combine(_rootPath, relative.Replace('/', System.IO.Path.DirectorySeparatorChar)));
                object[] tweaks = parsed as object[];
                if (tweaks == null) tweaks = GetArray(parsed as Dictionary<string, object>, "tweaks");
                if (tweaks == null) throw new InvalidDataException("Catálogo inválido no teste de Personalizado.");
                all.AddRange(tweaks);
            }
            SetCustomCatalog(all.ToArray()); EnsureCustomWindow(); RenderCustomCategories(); RenderCustomRows();
            if (_window.Width != 1180 || _window.Height != 760 || CustomFind<Button>("BtnCustomApply").IsEnabled)
                throw new InvalidDataException("Personalizado: janela deve ser padronizada e aplicação bloqueada.");
            int categoriesCount = _customCategoryButtons.Count;
            if (_customWindow.FindName("BtnCustomResetIcon") != null || CustomFind<Button>("BtnCustomReset") == null)
                throw new InvalidDataException("Personalizado: manter apenas Restaurar padrao no rodape.");
            foreach (string key in _customCategoryButtons.Keys.ToArray())
            {
                _customCategory = key; RenderCustomRows();
                FrameworkElement content = _customWindow.Content as FrameworkElement;
                content.Measure(new Size(1178, 758)); content.Arrange(new Rect(0, 0, 1178, 758)); content.UpdateLayout();
                if (CustomFind<StackPanel>("CustomRows").Children.Count != all.Cast<Dictionary<string, object>>().Count(t => CustomCategoryName(t) == key))
                    throw new InvalidDataException("Personalizado: categoria perdeu ajustes: " + key);
                foreach (Border row in CustomFind<StackPanel>("CustomRows").Children.OfType<Border>())
                {
                    Dictionary<string, object> tweak = all.Cast<Dictionary<string, object>>().Single(t => GetString(t, "id", "") == Convert.ToString(row.Tag));
                    ToggleButton toggleTip = ((Grid)row.Child).Children.OfType<ToggleButton>().Single();
                    foreach (FrameworkElement target in new FrameworkElement[] { row, toggleTip })
                    {
                        ToolTip help = target.ToolTip as ToolTip;
                        TextBlock helpText = help == null ? null : help.Content as TextBlock;
                        SolidColorBrush helpBorder = help == null ? null : help.BorderBrush as SolidColorBrush;
                        if (helpText == null || !helpText.Text.Contains(GetString(tweak, "plainName", "")) ||
                            helpText.TextWrapping != TextWrapping.Wrap || helpText.Width != 300 ||
                            helpBorder == null || helpBorder.Color != (Color)ColorConverter.ConvertFromString("#FF7A00") ||
                            ToolTipService.GetInitialShowDelay(target) != 800 || ToolTipService.GetShowDuration(target) != 20000)
                            throw new InvalidDataException("Personalizado: dica deve explicar o ajuste e usar o modelo dos overlays: " + row.Tag);
                    }
                }

                if (CustomFind<Button>("BtnCustomApply").ActualWidth < 190 || CustomFind<ScrollViewer>("CustomRowsScroll").ActualWidth < 650)
                    throw new InvalidDataException("Personalizado: layout cortado: " + key);
            }
            _customCategory = "Performance"; RenderCustomRows();
            Border first = CustomFind<StackPanel>("CustomRows").Children[0] as Border;
            ToggleButton toggle = ((Grid)first.Child).Children.OfType<ToggleButton>().Single();
            string id = Convert.ToString(toggle.Tag); toggle.IsChecked = true;
            _customCategory = "Privacidade"; RenderCustomRows(); _customCategory = "Performance"; RenderCustomRows();
            ToggleButton returned = ((Grid)((Border)CustomFind<StackPanel>("CustomRows").Children[0]).Child).Children.OfType<ToggleButton>().Single();
            if (!returned.IsChecked.GetValueOrDefault() || !_customSelected.Contains(id) || returned.Content.ToString() != "Ativado")
                throw new InvalidDataException("Personalizado: seleção não sobrevive à troca de categoria.");
            _window.Width = 1230; _window.Height = 800;
            _customCategory = "Rede"; RenderCustomRows();
            if (_window.Width != 1230 || _window.Height != 800)
                throw new InvalidDataException("Personalizado: trocar categoria não deve alterar tamanho manual.");
            LeaveCustomView(); _window.Width = 1180; _window.Height = 760; EnsureCustomWindow(); RenderCustomCategories();
            _customCategory = "Performance"; RenderCustomRows();
            ToggleButton reopened = ((Grid)((Border)CustomFind<StackPanel>("CustomRows").Children[0]).Child).Children.OfType<ToggleButton>().Single();
            if (!reopened.IsChecked.GetValueOrDefault() || !_customSelected.Contains(id))
                throw new InvalidDataException("Personalizado: seleção não sobrevive ao fechamento/reabertura na mesma sessão.");
            CustomFind<TextBox>("TxtCustomSearch").Text = id;
            int expectedMatches = all.Cast<Dictionary<string, object>>().Count(t => CustomCategoryName(t) == _customCategory && CustomMatches(t, id));
            if (CustomFind<StackPanel>("CustomRows").Children.Count != expectedMatches ||
                !CustomFind<StackPanel>("CustomRows").Children.OfType<Border>().Any(row => Convert.ToString(row.Tag) == id))
                throw new InvalidDataException("Personalizado: busca por ID/descricao deve preservar todos os resultados validos.");
            CustomFind<TextBox>("TxtCustomSearch").Text = "zzzz_no_match";
            if (CustomFind<StackPanel>("CustomRows").Children.Count != 0 || CustomFind<TextBlock>("TxtCustomEmpty").Visibility != Visibility.Visible)
                throw new InvalidDataException("Personalizado: busca sem resultados inválida.");
            CustomFind<TextBox>("TxtCustomSearch").Clear(); ResetCustomSelection();
            if (_customSelected.Count != 0 || categoriesCount < 10) throw new InvalidDataException("Personalizado: seleção padrão inválida.");
            // Batch selection must include filtered rows, preserve other categories and update green switches.
            _customCategory = "Privacidade"; RenderCustomRows();
            ToggleButton privacyToggle = ((Grid)((Border)CustomFind<StackPanel>("CustomRows").Children[0]).Child).Children.OfType<ToggleButton>().Single();
            string privacyId = Convert.ToString(privacyToggle.Tag); privacyToggle.IsChecked = true;
            _customCategory = "Performance"; RenderCustomRows(); CustomFind<TextBox>("TxtCustomSearch").Text = "zzzz_no_match";
            CustomFind<Button>("BtnCustomEnableCategory").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            int performanceCount = all.Cast<Dictionary<string, object>>().Count(t => CustomCategoryName(t) == "Performance");
            if (_customSelected.Count != performanceCount + 1 || !_customSelected.Contains(privacyId) || CustomFind<Button>("BtnCustomEnableCategory").IsEnabled)
                throw new InvalidDataException("Personalizado: ativar categoria deve incluir os ocultos e preservar selecao de outras categorias.");
            EnableCustomCategory();
            if (_customSelected.Count != performanceCount + 1) throw new InvalidDataException("Personalizado: ativar todos nao deve duplicar IDs.");
            CustomFind<TextBox>("TxtCustomSearch").Clear();
            foreach (Border row in CustomFind<StackPanel>("CustomRows").Children.OfType<Border>())
            {
                ToggleButton itemToggle = ((Grid)row.Child).Children.OfType<ToggleButton>().Single();
                itemToggle.ApplyTemplate();
                Border track = itemToggle.Template.FindName("CustomSwitchTrack", itemToggle) as Border;
                SolidColorBrush color = track == null ? null : track.Background as SolidColorBrush;
                if (!itemToggle.IsChecked.GetValueOrDefault() || color == null || color.Color != (Color)ColorConverter.ConvertFromString("#00C853"))
                    throw new InvalidDataException("Personalizado: chaves selecionadas devem ficar verdes.");
            }
            ToggleButton one = ((Grid)((Border)CustomFind<StackPanel>("CustomRows").Children[0]).Child).Children.OfType<ToggleButton>().Single();
            one.IsChecked = false;
            if (!CustomFind<Button>("BtnCustomEnableCategory").IsEnabled) throw new InvalidDataException("Personalizado: ativar todos deve voltar a ficar disponivel quando um ajuste e desativado.");
            EnableCustomCategory(); ResetCustomSelection();
            if (_customSelected.Count != 0) throw new InvalidDataException("Personalizado: reset deve limpar selecao em lote.");

            LeaveCustomView();
        }

        private void Navigate(string pageKey, bool immediate)
        {
            if (_window.Content != _shellContent) { _tweakDetailWindow = null; ShowPage(_shellContent); }
            if (pageKey != "Apply") StopApplyDemo();
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
            UpdatePerformancePolling();
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

        internal void ValidateSingleWindowNavigation()
        {
            int windows = Application.Current.Windows.Count;
            EnsureCustomWindow();
            UserControl custom = _customWindow;
            string category = _customCategory;
            string search = CustomFind<TextBox>("TxtCustomSearch").Text;
            HashSet<string> selected = new HashSet<string>(_customSelected, StringComparer.OrdinalIgnoreCase);
            _customPreviousContent = _shellContent;
            ShowPage(custom);
            CustomFind<TextBox>("TxtCustomSearch").Text = "PERF-001";
            string activeCategory = _customCategory;
            UserControl detail = LoadTweakDetailWindow("PERF-001"); _tweakDetailWindow = detail;
            ShowPage(detail);
            ((Button)detail.FindName("BtnTweakBack")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if (_window.Content != custom || _customCategory != activeCategory || CustomFind<TextBox>("TxtCustomSearch").Text != "PERF-001" || !_customSelected.SetEquals(selected))
                throw new InvalidDataException("Voltar dos detalhes perdeu o contexto de Personalizado.");
            UserControl report = CreateDetailWindow("Relatorio de teste"); report.Content = new TextBlock { Text = "Consulta" };
            ShowReportView(report);
            DockPanel reportHeader = ((Grid)report.Content).Children.OfType<DockPanel>().Single();
            reportHeader.Children.OfType<Button>().First().RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if (_window.Content != custom || Application.Current.Windows.Count != windows)
                throw new InvalidDataException("Navegacao criou outra janela nativa.");
            CustomFind<Button>("BtnCustomBack").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if (_window.Content != _shellContent || _customWindow != custom)
                throw new InvalidDataException("Voltar deve recuperar a tela anterior e preservar a pagina customizada.");
            _customCategory = category; CustomFind<TextBox>("TxtCustomSearch").Text = search; RenderCustomRows();
            Navigate("Presets", true);
        }

        private void ToggleMainWindowSize()
        {
            _window.WindowState = _window.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        }

        private void WirePageTitleBar(FrameworkElement titleBar)
        {
            titleBar.MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e) {
                if (FindVisualParent<Button>(e.OriginalSource as DependencyObject) != null) return;
                if (e.ClickCount == 2) ToggleMainWindowSize();
                else { try { _window.DragMove(); } catch { } }
            };
        }

        private void ShowPage(object view)
        {
            _window.Content = view;
            UpdatePerformancePolling();
        }

        private void LeaveCustomView()
        {
            _tweakDetailWindow = null;
            if (_window.Content == _customWindow) ShowPage(_customPreviousContent ?? _shellContent);
        }

        private void ReturnFromTweak()
        {
            _tweakDetailWindow = null;
            ShowPage(_customWindow == null ? _shellContent : _customWindow);
        }

        internal void ShowAnalysisPage() { Navigate("Analysis", true); }

        private void ShowAnalysisReport()
        {
            UserControl report = CreateDetailWindow("Relatório completo — Análise do Sistema");
            string text = "ANÁLISE DO SISTEMA — R3.2.33\n\nDEMONSTRAÇÃO VISUAL\nOs 12 indicadores OK são exemplos de apresentação, não uma aprovação do computador. Nenhuma alteração foi aplicada ao Windows.\n\n";
            string[] labels = new string[] { "Windows (versão e build)", "CPU e temperatura", "GPU e driver", "Memória (RAM)", "Armazenamento (SSD/NVMe)", "Laptop / Desktop", "Secure Boot", "BitLocker", "VBS / HVCI", "Hyper-V", "Serviços relevantes", "Estado dos tweaks" };
            string[] notes = new string[] {
                "Confere a versão e a compilação do Windows para identificar os ajustes compatíveis.",
                "Identifica o processador e verifica sua temperatura. A leitura de temperatura ainda não está integrada.",
                "Identifica a placa de vídeo e a versão do driver instalado.",
                "Verifica a memória instalada e disponível para os programas.",
                "Identifica o tipo e a capacidade do armazenamento; saúde e desempenho precisam de verificações próprias.",
                "Identifica se o computador é portátil ou de mesa para orientar opções de energia.",
                "Verifica a proteção que permite iniciar somente software autorizado.",
                "Verifica se a unidade usa criptografia para proteger seus arquivos.",
                "Verifica as proteções de memória e virtualização do Windows.",
                "Verifica os recursos usados para executar máquinas virtuais.",
                "Consulta os serviços necessários para os ajustes escolhidos.",
                "Confere quais ajustes estão efetivamente aplicados. Chave ativada em Personalizado indica apenas seleção."
            };
            for (int i = 0; i < labels.Length; i++) text += (i + 1).ToString(CultureInfo.InvariantCulture) + ". " + labels[i] + "\n" + notes[i] + "\nStatus: exemplo visual; verificação completa pendente.\n\n";
            text += "DADOS REAIS DISPONÍVEIS NA CONSULTA DO DASHBOARD\n";
            text += _analysisSnapshot == null ? "Consulta ainda indisponível. Reabra o aplicativo e confira o log se o Dashboard também não carregar.\n" : PrettyPresetJson(_analysisSnapshot);
            report.Content = new TextBox { Text = text, IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontSize = 13, Background = Brush("#0D1012"), Foreground = Brush("#E5E7EB"), Margin = new Thickness(18), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
            ShowReportView(report);
        }

        internal void ValidateAnalysisLayout()
        {
            if (Find<StackPanel>("AnalysisCheckRows").Children.Count != 12)
                throw new InvalidDataException("Analise deve apresentar 12 verificacoes.");
            if (!Find<TextBlock>("TxtAnalysisDemo").Text.Contains("ilustrativos"))
                throw new InvalidDataException("Analise demonstrativa precisa identificar indicadores ilustrativos.");
            int count = Application.Current.Windows.Count;
            ShowAnalysisPage();
            Find<Button>("BtnAnalysisReport").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            UserControl report = _window.Content as UserControl;
            if (report == null || !(Convert.ToString(report.Tag).Contains("Análise do Sistema")))
                throw new InvalidDataException("Botao de relatorio da analise sem navegacao.");
            Grid layout = (Grid)report.Content;
            DockPanel header = (DockPanel)layout.Children[0];
            ((Button)header.Children[0]).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            if (_window.Content != _shellContent || _currentPage != "Analysis" || Application.Current.Windows.Count != count)
                throw new InvalidDataException("Relatorio da analise deve retornar na mesma janela.");
            Navigate("Presets", true);
        }

        private UserControl CreateDetailWindow(string title)
        {
            return new UserControl { Tag = title, Background = Brush("#111111") };
        }

        private void ShowReportView(UserControl report)
        {
            object previous = _window.Content;
            object body = report.Content; report.Content = null;
            Grid layout = new Grid();
            layout.RowDefinitions.Add(new RowDefinition { Height = new GridLength(46) });
            layout.RowDefinitions.Add(new RowDefinition());
            DockPanel header = new DockPanel { Background = Brush("#080808"), LastChildFill = true };
            Button back = new Button { Content = "← Voltar", Style = (Style)_window.FindResource("SecondaryButton"), Margin = new Thickness(12, 6, 12, 6) };
            back.Click += delegate { ShowPage(previous); };
            header.Children.Add(back);
            Button close = new Button { Content = "×", Style = (Style)_window.FindResource("CloseButton") };
            close.Click += delegate { _window.Close(); }; DockPanel.SetDock(close, Dock.Right); header.Children.Add(close);
            header.Children.Add(new TextBlock { Text = Convert.ToString(report.Tag), VerticalAlignment = VerticalAlignment.Center, Foreground = Brush("#FF9A2E") });
            WirePageTitleBar(header); layout.Children.Add(header);
            ContentControl content = new ContentControl { Content = body }; Grid.SetRow(content, 1); layout.Children.Add(content);
            report.Content = layout; ShowPage(report);
        }

        internal void ValidateUniformWindowSize()
        {
            double width = _window.Width;
            double height = _window.Height;
            if (width != 1180 || height != 760)
                throw new InvalidDataException("Janela inicial deve medir 1180x760.");
            foreach (string page in _pages.Keys)
            {
                Navigate(page, true);
                if (_window.Width != width || _window.Height != height)
                    throw new InvalidDataException("Navegacao alterou o tamanho: " + page);
            }
            // A manually chosen size must also survive navigation.
            _window.Width = 1230;
            _window.Height = 800;
            foreach (string page in _pages.Keys)
            {
                Navigate(page, true);
                if (_window.Width != 1230 || _window.Height != 800)
                    throw new InvalidDataException("Navegacao perdeu o tamanho manual: " + page);
            }
            _window.Width = width;
            _window.Height = height;
            UserControl detail = CreateDetailWindow("Validacao de dimensoes");
            ShowReportView(detail);
            if (_window.Width != width || _window.Height != height)
                throw new InvalidDataException("Relatorio alterou a dimensao da janela principal.");
            Navigate("Dashboard", true);
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
            StopApplyDemo();
            if (_disposed) return;
            _disposed = true;
            try { _performanceTimer.Stop(); } catch { }
            _bridge.Dispose();
        }
    }
}
