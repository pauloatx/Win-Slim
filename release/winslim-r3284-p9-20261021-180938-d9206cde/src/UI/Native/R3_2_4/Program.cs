using System;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Markup;
using System.Xml;
using System.Web.Script.Serialization;
using System.Runtime.InteropServices;

namespace WinSlim.NativeUI
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            string selfTestArgument;
            bool selfTestRequested = TryGetArgument(args, "--self-test", out selfTestArgument);
            string rootPath = ResolveRootPath(args);
            string logDir = Path.Combine(rootPath, "logs");
            string logPath = Path.Combine(logDir, "ui-native-r3.2.4.log");
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
                string xamlPath = Path.Combine(rootPath, "src", "UI", "Native", "R3_2_4", "WinSlimShell.xaml");
                if (!File.Exists(xamlPath))
                    throw new FileNotFoundException("XAML da Native UI não encontrado.", xamlPath);

                Application app = new Application();
                app.ShutdownMode = ShutdownMode.OnMainWindowClose;
                app.DispatcherUnhandledException += delegate(object sender, System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
                {
                    SafeLog(logPath, "Dispatcher", e.Exception.ToString());
                    MessageBox.Show(
                        "A Native UI encontrou um erro inesperado.\n\n" + e.Exception.Message + "\n\nConsulte logs\\ui-native-r3.2.4.log.",
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
                app.MainWindow = window;
                return app.Run(window);
            }
            catch (Exception ex)
            {
                SafeLog(logPath, "Startup", ex.ToString());
                if (!selfTestRequested)
                {
                    MessageBox.Show(
                        "Não foi possível iniciar a Native UI do Win-Slim.\n\n" + ex.Message + "\n\nConsulte logs\\ui-native-r3.2.4.log.",
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

        private static void DictionarySelfTest(Window window, string rootPath, string outputPath)
        {
            if (String.IsNullOrWhiteSpace(outputPath))
                throw new ArgumentException("--self-test exige um caminho de saída.");

            using (BridgeClient bridge = new BridgeClient(rootPath))
            {
                bridge.Start();
                System.Collections.Generic.Dictionary<string, object> handshake = bridge.SendAsync("handshake", null, 20000).Result;
                if (!handshake.ContainsKey("backendCount") || Convert.ToInt32(handshake["backendCount"], CultureInfo.InvariantCulture) != 230)
                    throw new InvalidDataException("Self-test: backendCount diferente de 230.");

                System.Collections.Generic.Dictionary<string, object> result = new System.Collections.Generic.Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
                result["ok"] = true;
                result["xamlLoaded"] = window != null;
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
