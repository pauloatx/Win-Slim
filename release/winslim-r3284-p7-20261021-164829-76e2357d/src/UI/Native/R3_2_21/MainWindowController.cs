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
        private DispatcherTimer _applyDemoTimer;
        private int _applyDemoProgress;
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

            Find<Button>("BtnPreviewFromPreset").Click += async delegate { try { await PreparePreviewAsync(); } catch { } };
        }

        private void WirePrototypeFlow()
        {
            Button dashAnalyze = Find<Button>("BtnDashAnalyze");
            Button previewBack = Find<Button>("BtnPreviewBack");
            Button dashDetails = Find<Button>("BtnDashDetails");
            if (dashDetails != null) dashDetails.Click += delegate { Navigate("Analysis", false); };
            if (dashAnalyze != null) dashAnalyze.Click += delegate { Navigate("Analysis", false); };
            if (previewBack != null) previewBack.Click += delegate { _previewVersion++; Navigate("Presets", false); };
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
            Find<Button>("BtnResultRestartNow").IsEnabled = false;
            Navigate("Result", true);
        }

        private void ShowResultDemoReport()
        {
            Window dialog = CreateDetailWindow("Relatório de conclusão — demonstração");
            dialog.Content = new TextBox {
                Text = "DEMONSTRAÇÃO VISUAL — R3.2.21\n\nNenhuma transação foi executada. Nenhum backup foi criado.\nOs números abaixo são ilustrativos, usados para conferir o layout.\n\nPreset selecionado: " + (_selectedPreset == "Balanceado" ? "Equilibrado" : _selectedPreset) +
                    "\nAplicadas (exemplo): 51\nAguardando reinício (exemplo): 3 ajustes\nFalhas (exemplo): 0\nConflitos (exemplo): 0\n\nA tela receberá os resultados reais na integração da aplicação.\nReiniciar agora permanece indisponível nesta demonstração.",
                IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontSize = 13,
                Background = Brush("#0D1012"), Foreground = Brush("#E5E7EB"), Margin = new Thickness(18), VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };
            dialog.ShowDialog();
        }

        internal void NavigatePreviewValidation() { Navigate("Preview", false); }

        internal async Task PreparePreviewAsync()
        {
            int version = ++_previewVersion;
            int selectionVersion = _resolveVersion;
            _previewDetails = null;
            Navigate("Preview", false);
            foreach (string name in new string[] { "TxtPreviewCount", "TxtPreviewRestart", "TxtPreviewRisk" }) SetText(name, "—");
            Find<StackPanel>("PreviewCategoryRows").Children.Clear();
            Find<Button>("BtnPreviewDetails").IsEnabled = false;
            SetText("TxtPreviewSelection", "Analisando " + (_selectedPreset == "Balanceado" ? "Equilibrado" : _selectedPreset) + "...");
            SetText("TxtPreviewConflicts", "○ Verificando conflitos...");
            SetText("TxtPreviewHardware", "○ Verificando Windows e hardware...");
            SetText("TxtPreviewState", "Preparando o plano em modo de consulta...");
            Dictionary<string, object> payload = new Dictionary<string, object>();
            payload["presetName"] = _selectedPreset;
            payload["conditionalProfiles"] = _overlayButtons.Where(p => p.Value.IsChecked == true).Select(p => p.Key).ToArray();
            payload["allowHighRisk"] = _allowHighRisk;
            try
            {
                Dictionary<string, object> data = await _bridge.SendAsync("preview", payload, 60000);
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
                SetText("TxtPreviewSelection", (_selectedPreset == "Balanceado" ? "Equilibrado" : _selectedPreset) + " · " + GetInt(summary, "Selected", 0) + " selecionados · " + count + " aptos · " + skipped + " ignorados · " + blocked + " bloqueados");
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
            Window dialog = CreateDetailWindow("Detalhes da pré-visualização");
            dialog.Content = new TextBox { Text = PrettyPresetJson(_previewDetails), IsReadOnly = true, AcceptsReturn = true, FontFamily = new FontFamily("Consolas"), FontSize = 12, Background = Brush("#0D1012"), Foreground = Brush("#E5E7EB"), Margin = new Thickness(14), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
            dialog.ShowDialog();
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
                String.Equals(_currentPage, "Dashboard", StringComparison.OrdinalIgnoreCase);
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
            foreach (string key0 in new string[] { "General", "Advanced", "Logs", "About" })
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
            if (!new string[] { "General", "Advanced", "Logs", "About" }.Contains(key)) key = "General";
            foreach (string other in new string[] { "General", "Advanced", "Logs", "About" })
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
            return System.IO.Path.Combine(_rootPath, "config", "presets-ui-r3.2.21.json");
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
            report["version"] = "R3.2.21";
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
                var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "WinSlim-Presets-R3.2.21.json", Filter = "JSON (*.json)|*.json", DefaultExt = ".json" };
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
                var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "WinSlim-Logs-R3.2.21.log", Filter = "Log (*.log)|*.log", DefaultExt = ".log" };
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

        private void Navigate(string pageKey, bool immediate)
        {
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

        private Window CreateDetailWindow(string title)
        {
            return new Window {
                Title = title, Owner = _window.IsLoaded ? _window : null, Width = 1180, Height = 760,
                MinWidth = 1040, MinHeight = 680, Background = Brush("#111111"),
                WindowStartupLocation = WindowStartupLocation.CenterOwner
            };
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
            Window detail = CreateDetailWindow("Validacao de dimensoes");
            if (detail.Width != width || detail.Height != height)
                throw new InvalidDataException("Janela de detalhes com dimensoes diferentes.");
            detail.Close();
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
