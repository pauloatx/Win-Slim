using System;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Markup;
using System.Xml;
using System.Web.Script.Serialization;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace WinSlim.NativeUI
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            string capturePath;
            bool captureRequested = TryGetArgument(args, "--capture-dashboard", out capturePath);
            string presetsCapturePath;
            bool capturePresetsRequested = TryGetArgument(args, "--capture-presets", out presetsCapturePath);
            if (capturePresetsRequested) { captureRequested = true; capturePath = presetsCapturePath; }
            string previewCapturePath;
            bool capturePreviewRequested = TryGetArgument(args, "--capture-preview", out previewCapturePath);
            if (capturePreviewRequested) { captureRequested = true; capturePath = previewCapturePath; }
            string resultCapturePath;
            bool captureResultRequested = TryGetArgument(args, "--capture-result", out resultCapturePath);
            if (captureResultRequested) { captureRequested = true; capturePath = resultCapturePath; }
            bool showResultDemo = Array.IndexOf(args, "--show-result-demo") >= 0;
            string applyCapturePath;
            bool captureApplyRequested = TryGetArgument(args, "--capture-apply", out applyCapturePath);
            if (captureApplyRequested) { captureRequested = true; capturePath = applyCapturePath; }
            bool showApplyDemo = Array.IndexOf(args, "--show-apply-demo") >= 0;
            string backupCapturePath;
            bool captureBackupsRequested = TryGetArgument(args, "--capture-backups", out backupCapturePath);
            if (captureBackupsRequested) { captureRequested = true; capturePath = backupCapturePath; }
            bool showBackupDemo = Array.IndexOf(args, "--show-backup-demo") >= 0;
            string customCapturePath;
            bool captureCustomRequested = TryGetArgument(args, "--capture-custom", out customCapturePath);
            if (captureCustomRequested) { captureRequested = true; capturePath = customCapturePath; }
            bool showCustom = Array.IndexOf(args, "--show-custom") >= 0;
            string tweakCapturePath;
            bool captureTweakRequested = TryGetArgument(args, "--capture-tweak-detail", out tweakCapturePath);
            if (captureTweakRequested) { captureRequested = true; capturePath = tweakCapturePath; }
            string showTweakId;
            bool showTweakRequested = TryGetArgument(args, "--show-tweak-detail", out showTweakId);
            string tweakId;
            if (!TryGetArgument(args, "--tweak-id", out tweakId)) tweakId = "PERF-004";
            string selfTestArgument;
            bool selfTestRequested = TryGetArgument(args, "--self-test", out selfTestArgument);
            string rootPath = ResolveRootPath(args);
            string logDir = Path.Combine(rootPath, "logs");
            string logPath = Path.Combine(logDir, "ui-native-r3.2.32.log");
            try
            {
                if (!Directory.Exists(logDir)) Directory.CreateDirectory(logDir);
            }
            catch { }

            TryEnablePerMonitorDpi();

            AppDomain.CurrentDomain.UnhandledException += delegate(object sender, UnhandledExceptionEventArgs e)
            {
                Exception ex = e.ExceptionObject as Exception;
                SafeLog(logPath, "AppDomain", ex == null ? Convert.ToString(e.ExceptionObject, CultureInfo.InvariantCulture) : ex.ToString());
            };

            try
            {
                string xamlPath = Path.Combine(rootPath, "src", "UI", "Native", "R3_2_32", "WinSlimShell.xaml");
                if (!File.Exists(xamlPath))
                    throw new FileNotFoundException("XAML da Native UI não encontrado.", xamlPath);

                Application app = new Application();
                XmlReaderSettings themeSettings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null };
                using (FileStream themeStream = File.OpenRead(Path.Combine(rootPath, "src", "UI", "Native", "R3_2_32", "WinSlimScrollbars.xaml")))
                using (XmlReader themeReader = XmlReader.Create(themeStream, themeSettings)) {
                    ResourceDictionary theme = XamlReader.Load(themeReader) as ResourceDictionary;
                    if (theme == null) throw new InvalidDataException("Tema das barras de rolagem inválido.");
                    app.Resources.MergedDictionaries.Add(theme);
                }
                app.ShutdownMode = ShutdownMode.OnMainWindowClose;
                app.DispatcherUnhandledException += delegate(object sender, System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
                {
                    SafeLog(logPath, "Dispatcher", e.Exception.ToString());
                    MessageBox.Show(
                        "A Native UI encontrou um erro inesperado.\n\n" + e.Exception.Message + "\n\nConsulte logs\\ui-native-r3.2.32.log.",
                        "Win-Slim Suite",
                        MessageBoxButton.OK,
                        MessageBoxImage.Error);
                    e.Handled = true;
                };

                Window window;
                XmlReaderSettings settings = new XmlReaderSettings();
                settings.DtdProcessing = DtdProcessing.Prohibit;
                settings.XmlResolver = null;
                using (FileStream stream = File.OpenRead(xamlPath))
                using (XmlReader reader = XmlReader.Create(stream, settings))
                {
                    window = XamlReader.Load(reader) as Window;
                }
                if (window == null)
                    throw new InvalidDataException("O XAML não produziu uma Window válida.");

                if (selfTestRequested)
                {
                    DictionarySelfTest(window, rootPath, selfTestArgument);
                    try { window.Close(); } catch { }
                    try { app.Shutdown(); } catch { }
                    return 0;
                }

                MainWindowController controller = new MainWindowController(window, rootPath, logPath);
                controller.Initialize();
                if (showResultDemo && !captureRequested)
                    window.Loaded += async delegate { await controller.Ready; controller.PrepareResultDemo(); };
                if (showApplyDemo && !captureRequested)
                    window.Loaded += async delegate { await controller.Ready; controller.PrepareApplyDemo(); };
                if (showBackupDemo && !captureRequested)
                    window.Loaded += async delegate { await controller.Ready; controller.PrepareBackupDemo(); };
                if (showTweakRequested && !captureRequested)
                    window.Loaded += async delegate { await controller.Ready; await controller.OpenTweakDetailAsync(showTweakId); };
                if (showCustom && !captureRequested)
                    window.Loaded += async delegate { await controller.Ready; await controller.OpenCustomWindowAsync(); };
                if (captureRequested)
                {
                    window.Loaded += async delegate
                    {
                        try
                        {
                            await controller.Ready;
                            if (capturePresetsRequested)
                            {
                                controller.PreparePresetsValidation();
                                string presetTab;
                                if (TryGetArgument(args, "--capture-preset-tab", out presetTab)) controller.SelectPresetTab(presetTab);
                            }
                            if (capturePreviewRequested) await controller.PreparePreviewAsync();
                            if (captureResultRequested) controller.PrepareResultDemo();
                            if (captureApplyRequested) controller.PrepareApplyDemo();
                            if (captureBackupsRequested) {
                                controller.PrepareBackupDemo();
                                if (Array.IndexOf(args, "--backup-tweaks") >= 0) controller.SelectBackupTab(true);
                            }
                            if (captureCustomRequested) await controller.OpenCustomWindowAsync();
                            if (captureTweakRequested) await controller.OpenTweakDetailAsync(tweakId);
                            await Task.Delay(250);
                            Window captureTarget = captureTweakRequested ? controller.TweakDetailWindow : captureCustomRequested ? controller.CustomWindow : window;
                            captureTarget.UpdateLayout();
                            CaptureWindow(captureTarget, capturePath);
                            app.Shutdown(0);
                        }
                        catch (Exception captureError)
                        {
                            SafeLog(logPath, "Capture", captureError.ToString());
                            app.Shutdown(1);
                        }
                    };
                }
                app.MainWindow = window;
                return app.Run(window);
            }
            catch (Exception ex)
            {
                SafeLog(logPath, "Startup", ex.ToString());
                if (!selfTestRequested)
                {
                    MessageBox.Show(
                        "Não foi possível iniciar a Native UI do Win-Slim.\n\n" + ex.Message + "\n\nConsulte logs\\ui-native-r3.2.32.log.",
                        "Win-Slim Suite",
                        MessageBoxButton.OK,
                        MessageBoxImage.Error);
                }
                return 1;
            }
        }



        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SetProcessDPIAware();

        private static void TryEnablePerMonitorDpi()
        {
            try
            {
                // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4 (Windows 10 1703+).
                if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return;
            }
            catch (EntryPointNotFoundException) { }
            catch { }

            try { SetProcessDPIAware(); }
            catch { }
        }

        private static bool TryGetArgument(string[] args, string name, out string value)
        {
            value = null;
            if (args == null) return false;
            for (int i = 0; i < args.Length; i++)
            {
                if (!String.Equals(args[i], name, StringComparison.OrdinalIgnoreCase)) continue;
                if (i + 1 < args.Length) value = args[i + 1].Trim('\"');
                return true;
            }
            return false;
        }

        private static void CaptureWindow(Window window, string outputPath)
        {
            if (String.IsNullOrWhiteSpace(outputPath)) throw new ArgumentException("--capture-dashboard exige um caminho PNG.");
            PresentationSource source = PresentationSource.FromVisual(window);
            double scaleX = source == null ? 1.0 : source.CompositionTarget.TransformToDevice.M11;
            double scaleY = source == null ? 1.0 : source.CompositionTarget.TransformToDevice.M22;
            RenderTargetBitmap bitmap = new RenderTargetBitmap(
                (int)Math.Ceiling(window.ActualWidth * scaleX), (int)Math.Ceiling(window.ActualHeight * scaleY),
                96 * scaleX, 96 * scaleY, PixelFormats.Pbgra32);
            bitmap.Render(window);
            PngBitmapEncoder encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            string fullPath = Path.GetFullPath(outputPath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath));
            using (FileStream file = File.Create(fullPath)) encoder.Save(file);
        }

        private static void DictionarySelfTest(Window window, string rootPath, string outputPath)
        {
            if (String.IsNullOrWhiteSpace(outputPath))
                throw new ArgumentException("--self-test exige um caminho de saída.");

            string[] dashboardNames = new string[] {
                "TxtDashWindows", "TxtDashBuild", "TxtDashCpu", "TxtDashCores", "TxtDashRam",
                "TxtDashGpu", "TxtDashDriver", "TxtDashStorage", "TxtDashCompatible", "TxtDashAdmin",
                "TxtDashBackup", "TxtDashTweaks", "TxtDashPending", "TxtDashLastBackup", "TxtDashLastOptimization",
                "TxtMetricCpu", "TxtMetricGpu", "TxtMetricRam", "TxtMetricDisk",
                "ArcMetricCpu", "ArcMetricGpu", "ArcMetricRam", "ArcMetricDisk", "BtnDashAnalyze", "BtnDashDetails"
            };
            foreach (string name in dashboardNames)
                if (window.FindName(name) == null) throw new InvalidDataException("Dashboard: controle ausente: " + name);
            string[] tabNames = new string[] { "BtnPresetTabGeneral", "BtnPresetTabAdvanced", "BtnPresetTabLogs", "PresetTabGeneral", "PresetTabAdvanced", "PresetTabLogs", "TxtPresetDiagnostics", "TxtPresetLogs", "BtnExportPresetOptions", "BtnExportPresetLogs" };
            foreach (string name in tabNames)
                if (window.FindName(name) == null) throw new InvalidDataException("Aba de Presets ausente: " + name);
            foreach (string name in new string[] { "TxtPreviewCount", "TxtPreviewRestart", "TxtPreviewRisk", "PreviewCategoryRows", "TxtPreviewBackup", "TxtPreviewConflicts", "TxtPreviewHardware", "TxtPreviewState", "BtnPreviewDetails", "BtnPreviewBack", "BtnPreviewApplyDemo" })
                if (window.FindName(name) == null) throw new InvalidDataException("Controle de pre-visualizacao ausente: " + name);
            string[] presetNames = new string[] { "CardPresetBalanced", "CardPresetGamer", "CardPresetExtreme", "BtnPresetBalanced", "BtnPresetGamer", "BtnPresetExtreme", "TxtSummaryPreset", "TxtSummaryOverlays", "TxtSummaryTotal", "TxtSummaryRisk", "TxtSummaryFingerprint", "TxtResolveState", "HighRiskBanner", "BtnGrantHighRisk", "BtnResetOverlays", "BtnPreviewFromPreset" };
            foreach (string name in presetNames)
                if (window.FindName(name) == null) throw new InvalidDataException("Presets: controle ausente: " + name);
            using (MainWindowController controller = new MainWindowController(window, rootPath, Path.Combine(rootPath, "logs", "selftest-r3.2.32.log")))
            {
                controller.Initialize();
                controller.ValidateUniformWindowSize();
                controller.ValidateCustomWindow();
                controller.ValidateSingleWindowNavigation();
                MainWindowController.ValidateBackupInventoryReader();
                controller.PrepareBackupDemo();
                FrameworkElement backupContent = window.Content as FrameworkElement;
                backupContent.Measure(new Size(1178, 758)); backupContent.Arrange(new Rect(0, 0, 1178, 758)); backupContent.UpdateLayout();
                System.Windows.Controls.ListBox backups = window.FindName("ListBackups") as System.Windows.Controls.ListBox;
                System.Windows.Controls.ListBox backupTweaks = window.FindName("ListBackupTweaks") as System.Windows.Controls.ListBox;
                if (backups == null || backups.Items.Count != 4 || backups.ActualWidth < 700 || backups.ActualHeight < 250)
                    throw new InvalidDataException("Backup: tabela de exemplos invalida.");
                foreach (string name in new string[] { "BtnBackupDetails", "BtnBackupRestore", "BtnBackupDelete" })
                    if ((window.FindName(name) as FrameworkElement).ActualWidth < 200)
                        throw new InvalidDataException("Backup: acao cortada: " + name);
                if ((window.FindName("BtnBackupRestore") as System.Windows.Controls.Button).IsEnabled ||
                    (window.FindName("BtnBackupDelete") as System.Windows.Controls.Button).IsEnabled ||
                    !(window.FindName("BtnBackupDetails") as System.Windows.Controls.Button).IsEnabled)
                    throw new InvalidDataException("Backup: consulta deve preservar bloqueio de restauracao/exclusao.");
                controller.SelectBackupTab(true);
                if (backupTweaks.Visibility != Visibility.Visible || backups.Visibility != Visibility.Collapsed || backupTweaks.Items.Count != 54)
                    throw new InvalidDataException("Backup: aba por tweak invalida.");
                backups.SelectedIndex = 2;
                if (backupTweaks.Items.Count != 15)
                    throw new InvalidDataException("Backup: ajustes nao acompanham o backup selecionado.");
                controller.SelectBackupTab(false);
                if (backups.Visibility != Visibility.Visible || backupTweaks.Visibility != Visibility.Collapsed)
                    throw new InvalidDataException("Backup: retorno a lista invalido.");
                int overlayTips = 0;
                foreach (string name in new string[] { "OverlayHags", "OverlayMsiGpu", "OverlayCoreParking", "OverlayGpuIrq", "OverlayCs2PCores", "OverlayValorant", "OverlayCs2", "OverlayApex", "OverlayFortnite", "OverlayGtav", "OverlayFso", "OverlayStreaming", "OverlayVideo", "OverlayDesign", "OverlayProgramming", "OverlayDefenderDev" })
                {
                    System.Windows.Controls.Primitives.ToggleButton button = window.FindName(name) as System.Windows.Controls.Primitives.ToggleButton;
                    System.Windows.Controls.ToolTip tip = button == null ? null : button.ToolTip as System.Windows.Controls.ToolTip;
                    System.Windows.Controls.TextBlock text = tip == null ? null : tip.Content as System.Windows.Controls.TextBlock;
                    if (text == null || String.IsNullOrWhiteSpace(text.Text) || text.TextWrapping != TextWrapping.Wrap ||
                        !System.Windows.Controls.ToolTipService.GetShowOnDisabled(button) || System.Windows.Controls.ToolTipService.GetInitialShowDelay(button) != 800)
                        throw new InvalidDataException("Dica de overlay ausente ou invalida: " + name);
                    overlayTips++;
                }
                controller.PrepareDashboardValidation();
                FrameworkElement content = window.Content as FrameworkElement;
                content.Measure(new Size(1038, 678));
                content.Arrange(new Rect(0, 0, 1038, 678));
                content.UpdateLayout();
                foreach (string labelName in new string[] { "NavLabelAnalysis", "NavLabelBackup" })
                {
                    System.Windows.Controls.TextBlock label = window.FindName(labelName) as System.Windows.Controls.TextBlock;
                    if (label == null || label.DesiredSize.Width > 107)
                        throw new InvalidDataException("Sidebar: legenda excede espaco reservado: " + labelName);
                }
                controller.PreparePresetsValidation();
                foreach (string key in new string[] { "Advanced", "Logs", "General" })
                {
                    System.Windows.Controls.Button tabButton = window.FindName("BtnPresetTab" + key) as System.Windows.Controls.Button;
                    tabButton.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
                    foreach (string other in new string[] { "Advanced", "Logs", "General" })
                        if (((FrameworkElement)window.FindName("PresetTab" + other)).Visibility != (key == other ? Visibility.Visible : Visibility.Collapsed))
                            throw new InvalidDataException("Navegacao de abas incorreta: " + key);
                }
                controller.SelectPresetTab("Advanced");
                content.Measure(new Size(1178, 758));
                content.Arrange(new Rect(0, 0, 1178, 758));
                content.UpdateLayout();
                FrameworkElement options = window.FindName("PanelPresetAdvancedOptions") as FrameworkElement;
                FrameworkElement details = window.FindName("PanelPresetAdvancedDetails") as FrameworkElement;
                FrameworkElement advanced = window.FindName("PresetTabAdvanced") as FrameworkElement;
                if (options == null || details == null || advanced == null ||
                    System.Windows.Controls.Grid.GetColumn(options) != 0 || System.Windows.Controls.Grid.GetColumn(details) != 1 ||
                    options.ActualWidth < 300 || details.ActualWidth < 300)
                    throw new InvalidDataException("Avancado: colunas dos paineis invalidas.");
                Point optionsPosition = options.TranslatePoint(new Point(0, 0), advanced);
                Point detailsPosition = details.TranslatePoint(new Point(0, 0), advanced);
                if (optionsPosition.X + options.ActualWidth > detailsPosition.X + 1 ||
                    detailsPosition.X + details.ActualWidth > advanced.ActualWidth + 1)
                    throw new InvalidDataException("Avancado: paineis sobrepostos ou fora da area disponivel.");
                controller.NavigatePreviewValidation();
                content.Measure(new Size(1178, 758));
                content.Arrange(new Rect(0, 0, 1178, 758));
                content.UpdateLayout();
                System.Windows.Controls.Button apply = window.FindName("BtnPreviewApplyDemo") as System.Windows.Controls.Button;
                if (apply == null || apply.IsEnabled || apply.ActualWidth < 200)
                    throw new InvalidDataException("Pre-visualizacao: acao de aplicar deve estar desabilitada e visivel.");
                controller.PrepareApplyDemo();
                content.Measure(new Size(1178, 758));
                content.Arrange(new Rect(0, 0, 1178, 758));
                content.UpdateLayout();
                foreach (string name in new string[] { "ApplyProgress", "TxtApplyPercent", "TxtApplyCurrent", "TxtApplyOperation", "TxtApplyStatus", "BtnApplyCancel", "BtnApplyDemoStart", "TxtApplyDemo" })
                    if (window.FindName(name) == null) throw new InvalidDataException("Aplicacao: controle ausente: " + name);
                for (int i = 0; i < 5; i++)
                    if (window.FindName("ApplyStageStatus" + i) == null || window.FindName("ApplyStageIcon" + i) == null || window.FindName("ApplyStageMark" + i) == null)
                        throw new InvalidDataException("Aplicacao: etapa ausente: " + i);
                System.Windows.Controls.ProgressBar progress = window.FindName("ApplyProgress") as System.Windows.Controls.ProgressBar;
                System.Windows.Controls.TextBlock applyDemo = window.FindName("TxtApplyDemo") as System.Windows.Controls.TextBlock;
                if (progress.Value != 67 || progress.ActualWidth < 500 || applyDemo.ActualHeight < 10)
                    throw new InvalidDataException("Aplicacao: progresso ou identificacao da demonstracao invalidos.");
                controller.CancelApplyDemo();
                if ((window.FindName("BtnApplyCancel") as System.Windows.Controls.Button).IsEnabled ||
                    (window.FindName("TxtApplyOperation") as System.Windows.Controls.TextBlock).Text != "Cancelada")
                    throw new InvalidDataException("Aplicacao: cancelamento da demonstracao invalido.");
                controller.PrepareResultDemo();
                content.Measure(new Size(1178, 758));
                content.Arrange(new Rect(0, 0, 1178, 758));
                content.UpdateLayout();
                foreach (string name in new string[] { "TxtResultTitle", "TxtResultSubtitle", "TxtResultApplied", "TxtResultRestart", "TxtResultFailed", "TxtResultConflicts", "PanelResultRestart", "BtnResultRestartNow", "BtnResultRestartLater", "BtnResultReport", "TxtResultDemo", "BtnPreviewResultDemo" })
                    if (window.FindName(name) == null) throw new InvalidDataException("Conclusao: controle ausente: " + name);
                System.Windows.Controls.Button restart = window.FindName("BtnResultRestartNow") as System.Windows.Controls.Button;
                System.Windows.Controls.Button report = window.FindName("BtnResultReport") as System.Windows.Controls.Button;
                System.Windows.Controls.TextBlock demo = window.FindName("TxtResultDemo") as System.Windows.Controls.TextBlock;
                if (restart.IsEnabled || report.ActualWidth < 500 || demo.Visibility != Visibility.Visible || demo.ActualHeight < 10)
                    throw new InvalidDataException("Conclusao: demonstracao deve estar identificada, com reinicio bloqueado e relatorio visivel.");
                controller.PreparePresetsValidation();
                content.Measure(new Size(1178, 758));
                content.Arrange(new Rect(0, 0, 1178, 758));
                content.UpdateLayout();
                System.Windows.Controls.TextBlock recommendation = window.FindName("TxtPresetRecommendation") as System.Windows.Controls.TextBlock;
                if (recommendation == null || recommendation.ActualWidth + 1 < recommendation.DesiredSize.Width)
                    throw new InvalidDataException("Presets: selo RECOMENDADO cortado.");
                foreach (string listName in new string[] { "ListPresetBalanced", "ListPresetGamer", "ListPresetExtreme" })
                {
                    System.Windows.Controls.StackPanel list = window.FindName(listName) as System.Windows.Controls.StackPanel;
                    System.Windows.Controls.Border container = list == null ? null : list.Parent as System.Windows.Controls.Border;
                    if (container == null || list.DesiredSize.Height > container.ActualHeight - container.Padding.Top - container.Padding.Bottom - 2 + 1)
                        throw new InvalidDataException("Presets: lista de beneficios excede o card: " + listName);
                }
            }
            using (BridgeClient bridge = new BridgeClient(rootPath))
            {
                bridge.Start();
                System.Collections.Generic.Dictionary<string, object> handshake = bridge.SendAsync("handshake", null, 20000).Result;
                if (!handshake.ContainsKey("backendCount") || Convert.ToInt32(handshake["backendCount"], CultureInfo.InvariantCulture) != 230)
                    throw new InvalidDataException("Self-test: backendCount diferente de 230.");

                System.Collections.Generic.Dictionary<string, object> result = new System.Collections.Generic.Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                result["ok"] = true;
                result["xamlLoaded"] = window != null;
                result["dashboardControlsValidated"] = dashboardNames.Length;
                result["controllerInitialized"] = true;
                result["sidebarLabelsFit"] = true;
                result["presetControlsValidated"] = presetNames.Length;
                result["presetLayoutFits"] = true;
                result["presetTabsValidated"] = tabNames.Length;
                result["presetAdvancedPanelsFit"] = true;
                result["previewControlsValidated"] = 11;
                result["overlayTooltipsValidated"] = 16;
                result["resultControlsValidated"] = 12;
                result["resultDemoSafe"] = true;
                result["applyControlsValidated"] = 23;
                result["applyDemoCancellation"] = true;
                result["uniformWindowSize"] = true;
                System.Collections.Generic.Dictionary<string, object> customCatalog = bridge.SendAsync("catalog", null, 20000).Result;
                object customTweaksObject;
                object[] customTweaks = customCatalog.TryGetValue("tweaks", out customTweaksObject) ? customTweaksObject as object[] : null;
                if (customTweaks == null || customTweaks.Length != 230)
                    throw new InvalidDataException("Bridge de Personalizado não retornou os 230 ajustes.");
                using (MainWindowController integrationController = new MainWindowController(window, rootPath, Path.Combine(rootPath, "logs", "selftest-custom-r3.2.32.log"))) {
                    integrationController.SetCustomCatalog(customTweaks);
                    foreach (string detailId in new string[] { "PERF-001", "PERF-004" }) {
                        var detailData = bridge.SendAsync("tweakDetails", new System.Collections.Generic.Dictionary<string, object> { { "tweakId", detailId } }, 60000).Result;
                        integrationController.ValidateTweakDetail(detailData);
                    }
                    bool unknownDetailRejected = false;
                    try { bridge.SendAsync("tweakDetails", new System.Collections.Generic.Dictionary<string, object> { { "tweakId", "UNKNOWN-999" } }, 20000).GetAwaiter().GetResult(); } catch { unknownDetailRejected = true; }
                    if (!unknownDetailRejected) throw new InvalidDataException("Detalhes aceitaram ID desconhecido.");

                foreach (string preset in new string[] { "Balanceado", "Gamer", "Extremo" }) {
                    var request = new System.Collections.Generic.Dictionary<string, object> { { "presetName", preset }, { "conditionalProfiles", new string[0] }, { "allowHighRisk", false } };
                    var resolved = bridge.SendAsync("resolvePreset", request, 20000).Result;
                    integrationController.ValidateCustomPresetIntegration(resolved);
                }
                }
                var customRequest = new System.Collections.Generic.Dictionary<string, object> { { "selectedIds", new string[] { "PERF-001" } }, { "customName", "Teste personalizado" } };
                var customPreview = bridge.SendAsync("customPreview", customRequest, 60000).Result;
                if (!customPreview.ContainsKey("readOnly") || !Convert.ToBoolean(customPreview["readOnly"]) || !(customPreview["preview"] is System.Collections.Generic.Dictionary<string, object>))
                    throw new InvalidDataException("Prévia personalizada deve utilizar o Planner em modo consulta.");
                int customInvalidRejected = 0;
                foreach (object[] ids in new object[][] { new object[] { "UNKNOWN-999" }, new object[] { "PERF-001", "PERF-001" }, new object[0], new object[] { 123 } }) {
                    var invalid = new System.Collections.Generic.Dictionary<string, object> { { "selectedIds", ids }, { "customName", "Teste personalizado" } };
                    try { bridge.SendAsync("customPreview", invalid, 20000).GetAwaiter().GetResult(); } catch { customInvalidRejected++; }
                }
                if (customInvalidRejected != 4) throw new InvalidDataException("Bridge aceitou uma seleção personalizada inválida.");
                result["singleWindowNavigationValidated"] = true;
                result["tweakDetailValidated"] = true;
                result["customPresetIntegrationValidated"] = true;
                result["customPortableRoundtripValidated"] = true;
                result["customPreviewReadOnlyValidated"] = true;
                result["customWindowValidated"] = true;
                result["customCategoryBatchValidated"] = true;
                result["customTweakTooltipsValidated"] = 230;
                result["customCatalogCount"] = 230;
                result["backupLayoutValidated"] = true;
                result["backupReadOnly"] = true;
                result["backupInventoryReaderValidated"] = true;
                result["backendCount"] = handshake["backendCount"];
                result["plannerPromoted"] = handshake.ContainsKey("plannerPromoted") ? handshake["plannerPromoted"] : false;
                result["transactionPromoted"] = handshake.ContainsKey("transactionPromoted") ? handshake["transactionPromoted"] : false;
                result["bridgeVersion"] = handshake.ContainsKey("bridgeVersion") ? handshake["bridgeVersion"] : String.Empty;

                string fullPath = Path.GetFullPath(outputPath);
                string dir = Path.GetDirectoryName(fullPath);
                if (!String.IsNullOrWhiteSpace(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);
                JavaScriptSerializer serializer = new JavaScriptSerializer();
                File.WriteAllText(fullPath, serializer.Serialize(result), new UTF8Encoding(false));
            }
        }

        private static string ResolveRootPath(string[] args)
        {
            if (args != null)
            {
                for (int i = 0; i < args.Length - 1; i++)
                {
                    if (String.Equals(args[i], "--root", StringComparison.OrdinalIgnoreCase))
                    {
                        string candidate = args[i + 1].Trim('"');
                        if (Directory.Exists(candidate)) return Path.GetFullPath(candidate);
                    }
                }
            }

            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            DirectoryInfo dir = new DirectoryInfo(baseDir);
            if (String.Equals(dir.Name, "bin", StringComparison.OrdinalIgnoreCase) && dir.Parent != null)
                return dir.Parent.FullName;
            return baseDir;
        }

        internal static void SafeLog(string path, string area, string message)
        {
            try
            {
                string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture) + " [" + area + "] " + message + Environment.NewLine;
                File.AppendAllText(path, line, new UTF8Encoding(false));
            }
            catch { }
        }
    }
}
