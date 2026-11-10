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
            string selfTestArgument;
            bool selfTestRequested = TryGetArgument(args, "--self-test", out selfTestArgument);
            string rootPath = ResolveRootPath(args);
            string logDir = Path.Combine(rootPath, "logs");
            string logPath = Path.Combine(logDir, "ui-native-r3.2.16.log");
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
                string xamlPath = Path.Combine(rootPath, "src", "UI", "Native", "R3_2_16", "WinSlimShell.xaml");
                if (!File.Exists(xamlPath))
                    throw new FileNotFoundException("XAML da Native UI não encontrado.", xamlPath);

                Application app = new Application();
                app.ShutdownMode = ShutdownMode.OnMainWindowClose;
                app.DispatcherUnhandledException += delegate(object sender, System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
                {
                    SafeLog(logPath, "Dispatcher", e.Exception.ToString());
                    MessageBox.Show(
                        "A Native UI encontrou um erro inesperado.\n\n" + e.Exception.Message + "\n\nConsulte logs\\ui-native-r3.2.16.log.",
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
                            await Task.Delay(250);
                            window.UpdateLayout();
                            CaptureWindow(window, capturePath);
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
                        "Não foi possível iniciar a Native UI do Win-Slim.\n\n" + ex.Message + "\n\nConsulte logs\\ui-native-r3.2.16.log.",
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
            string[] tabNames = new string[] { "BtnPresetTabGeneral", "BtnPresetTabAdvanced", "BtnPresetTabLogs", "BtnPresetTabAbout", "PresetTabGeneral", "PresetTabAdvanced", "PresetTabLogs", "PresetTabAbout", "TxtPresetDiagnostics", "TxtPresetLogs", "BtnExportPresetOptions", "BtnExportPresetLogs" };
            foreach (string name in tabNames)
                if (window.FindName(name) == null) throw new InvalidDataException("Aba de Presets ausente: " + name);
            string[] presetNames = new string[] { "CardPresetBalanced", "CardPresetGamer", "CardPresetExtreme", "BtnPresetBalanced", "BtnPresetGamer", "BtnPresetExtreme", "TxtSummaryPreset", "TxtSummaryOverlays", "TxtSummaryTotal", "TxtSummaryRisk", "TxtSummaryFingerprint", "TxtResolveState", "HighRiskBanner", "BtnGrantHighRisk", "BtnResetOverlays", "BtnPreviewFromPreset" };
            foreach (string name in presetNames)
                if (window.FindName(name) == null) throw new InvalidDataException("Presets: controle ausente: " + name);
            using (MainWindowController controller = new MainWindowController(window, rootPath, Path.Combine(rootPath, "logs", "selftest-r3.2.16.log")))
            {
                controller.Initialize();
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
                foreach (string key in new string[] { "Advanced", "Logs", "About", "General" })
                {
                    System.Windows.Controls.Button tabButton = window.FindName("BtnPresetTab" + key) as System.Windows.Controls.Button;
                    tabButton.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Button.ClickEvent));
                    foreach (string other in new string[] { "Advanced", "Logs", "About", "General" })
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
                controller.SelectPresetTab("General");
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
