using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Interop;
using System.Windows.Automation;
using System.Windows.Automation.Peers;

namespace WinSlim.NativeUI
{
    public static class OverlayThemeFixture
    {
        [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr window,int message,IntPtr wp,IntPtr lp);
        [DllImport("user32.dll",EntryPoint="GetWindowLongW")] private static extern int WindowStyle(IntPtr window,int index);
        private static void Check(List<string> output, string name, Action body)
        {
            try { body(); output.Add("[OK] " + name); }
            catch (Exception error) { output.Add("[FAIL] " + name + ": " + error.GetType().Name + " - " + error.Message); }
        }
        private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
        private static T Find<T>(DependencyObject parent, string name) where T : FrameworkElement
        {
            T element = parent as T;
            if (element != null && element.Name == name) return element;
            foreach (object child in LogicalTreeHelper.GetChildren(parent)) {
                var dependency = child as DependencyObject;
                if (dependency != null) { T found = Find<T>(dependency, name); if (found != null) return found; }
            }
            return null;
        }
        private static void Click(DependencyObject root, string name)
        {
            ButtonBase button = Find<ButtonBase>(root, name);
            Require(button != null, "User control missing: " + name);
            button.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
        }
        private static bool Accessible(AutomationPeer peer,string id)
        {
            if(peer==null)return false;if(peer.GetAutomationId()==id)return true;
            var children=peer.GetChildren();return children!=null&&children.Any(child=>Accessible(child,id));
        }
        private static void AccessibleSelect(FrameworkElement element)
        {
            var peer=UIElementAutomationPeer.CreatePeerForElement(element);object provider=peer.GetPattern(PatternInterface.SelectionItem);string contract="ISelectionItemProvider",method="Select";
            if(provider==null){provider=peer.GetPattern(PatternInterface.Toggle);contract="IToggleProvider";method="Toggle";}
            Require(provider!=null,"Accessible selection provider missing");
            provider.GetType().GetInterfaces().First(type=>type.Name==contract).GetMethod(method).Invoke(provider,null);
        }
        private static double Brightness(Brush brush)
        {
            var solid = brush as SolidColorBrush;
            Require(solid != null, "Expected actual rendered solid brush");
            return (solid.Color.R + solid.Color.G + solid.Color.B) / 765.0;
        }
        public static string[] RunAll(string root)
        {
            List<string> output = new List<string>(); Exception failure = null;
            Thread thread = new Thread(delegate() {
                try { RunSta(root, output); } catch (Exception error) { failure = error; }
                finally { System.Windows.Threading.Dispatcher.CurrentDispatcher.InvokeShutdown(); }
            });
            thread.SetApartmentState(ApartmentState.STA); thread.IsBackground = true; thread.Start();
            if (!thread.Join(45000)) throw new TimeoutException("Theme STA fixture did not complete");
            if (failure != null) output.Add("[FAIL] STA fixture: " + failure);
            return output.ToArray();
        }
        private static void RunSta(string root, List<string> output)
        {
            Directory.CreateDirectory(Path.Combine(root, "config"));
            File.WriteAllText(Path.Combine(root, "config", "WinSlim-theme.json"), "{\"schemaVersion\":1,\"theme\":\"light\"}");
            var game = new BenchmarkGame { Name = "Theme fixture", Identity = "theme-fixture" };
            var overlay = new BenchmarkOverlay(root, game, delegate(string message) { });
            var window = new BenchmarkSettingsWindow(overlay, null);
            try {
                Check(output, "saved manual light preference reaches floating overlay on startup", delegate {
                    Require(Brightness(((Border)overlay.Content).Background) > .7, "Floating overlay ignores saved light preference");
                });
                Check(output, "saved manual light preference reaches settings on startup", delegate {
                    Require(Brightness(window.Background) > .7, "Settings stays dark despite saved light preference");
                });
                Check(output, "light selection previews both settings and existing overlay", delegate {
                    Click(window, "SettingsThemeLight");
                    Require(Brightness(window.Background) > .7 && Brightness(((Border)overlay.Content).Background) > .7, "Light preview not synchronized");
                });
                Check(output, "dark selection previews both settings and existing overlay", delegate {
                    Click(window, "SettingsThemeDark");
                    Require(Brightness(window.Background) < .2 && Brightness(((Border)overlay.Content).Background) < .2, "Dark preview not synchronized");
                });
                Check(output, "compact theme action exists while locked and changes immediately", delegate {
                    Click(overlay.ControlsWindow, "OverlayTheme");
                    Require(overlay.Locked && Brightness(((Border)overlay.Content).Background) > .7 && Brightness(window.Background) > .7, "Locked theme button not synchronized");
                });
                Check(output, "automatic selection is available as an explicit choice", delegate { Click(window, "SettingsThemeAuto"); });
            } finally { window.Close(); overlay.Close(); }
            Additional(Path.Combine(root,"automatic"),output);
        }
        private static void Layout(BenchmarkOverlay overlay)
        {
            var frame=(FrameworkElement)overlay.Content;frame.Measure(new Size(overlay.Width,Double.PositiveInfinity));frame.Arrange(new Rect(0,0,overlay.Width,frame.DesiredSize.Height));frame.UpdateLayout();
            IntPtr handle=new WindowInteropHelper(overlay).Handle;
            if(handle!=IntPtr.Zero){var rect=BenchmarkOverlayDesktop.Rect(handle);BenchmarkOverlayDesktop.Move(handle,rect.Left,rect.Top,(int)overlay.Width,(int)frame.DesiredSize.Height,true);overlay.Place();}
        }
        private static double Luminance(Color c)
        {
            Func<byte,double> channel=delegate(byte n){double v=n/255.0;return v<=.04045?v/12.92:Math.Pow((v+.055)/1.055,2.4);};return .2126*channel(c.R)+.7152*channel(c.G)+.0722*channel(c.B);
        }
        private static double Contrast(Brush foreground,Brush background)
        {
            double a=Luminance(((SolidColorBrush)foreground).Color),b=Luminance(((SolidColorBrush)background).Color);return (Math.Max(a,b)+.05)/(Math.Min(a,b)+.05);
        }
        private static void Additional(string root,List<string> output)
        {
            bool systemLight=false,unavailable=false;int reads=0;
            Func<bool> source=delegate{reads++;if(unavailable)throw new IOException("injected system preference unavailable");return systemLight;};
            var game=new BenchmarkGame {Name="Recording.exe",Identity="recording-theme-game",Pid=7301};
            Check(output,"legacy profile without theme inherits saved app manual preference without rewriting",delegate{
                string legacyRoot=Path.Combine(root,"legacy"),legacyPath=BenchmarkOverlayPlacement.PathFor(legacyRoot,"legacy");Directory.CreateDirectory(Path.GetDirectoryName(legacyPath));
                File.WriteAllText(legacyPath,"{\"Schema\":1,\"X\":0.2,\"Y\":0.3,\"Locked\":true}");byte[] bytes=File.ReadAllBytes(legacyPath);
                Directory.CreateDirectory(Path.Combine(legacyRoot,"config"));File.WriteAllText(Path.Combine(legacyRoot,"config","WinSlim-theme.json"),"{\"theme\":\"dark\"}");
                using(var legacy=new ClosingOverlay(new BenchmarkOverlay(legacyRoot,new BenchmarkGame {Name="Legacy",Identity="legacy"},delegate(string message){},null,null,source))){Require(legacy.Value.ThemeMode=="dark"&&!legacy.Value.ThemeIsLight&&bytes.SequenceEqual(File.ReadAllBytes(legacyPath)),"Legacy preference migration overwrote data");}
            });
            Check(output,"invalid saved theme is rejected without rewriting invalid bytes",delegate{
                string invalid=Path.Combine(root,"invalid-profile.json");Directory.CreateDirectory(root);File.WriteAllText(invalid,"{\"Schema\":1,\"ThemeMode\":\"sepia\"}");byte[] bytes=File.ReadAllBytes(invalid);bool rejected=false;try{BenchmarkOverlayPlacement.Load(invalid);}catch(InvalidDataException){rejected=true;}Require(rejected&&bytes.SequenceEqual(File.ReadAllBytes(invalid)),"Invalid persisted input accepted or modified");
            });
            Check(output,"corrupt app preference falls back to actual automatic source",delegate{
                string corruptRoot=Path.Combine(root,"corrupt-app");Directory.CreateDirectory(Path.Combine(corruptRoot,"config"));File.WriteAllText(Path.Combine(corruptRoot,"config","WinSlim-theme.json"),"broken JSON");
                using(var corrupt=new ClosingOverlay(new BenchmarkOverlay(corruptRoot,new BenchmarkGame{Name="Corrupt",Identity="corrupt"},delegate(string message){},null,null,source))){Require(corrupt.Value.ThemeMode=="auto"&&!corrupt.Value.ThemeIsLight,"Corrupt global preference did not fall back to automatic");}
            });
            string path=BenchmarkOverlayPlacement.PathFor(root,game.Identity);
            string otherPath=BenchmarkOverlayPlacement.PathFor(root,"another-game");
            new BenchmarkOverlayPlacement {Schema=1,X=.2,Y=.3,ThemeMode="light"}.Save(otherPath);byte[] other=File.ReadAllBytes(otherPath);
            var overlay=new BenchmarkOverlay(root,game,delegate(string message){},new[]{16.0,32,80},null,source);
            try {
                Check(output,"fresh automatic follows injected dark Windows without saving",delegate{Require(overlay.ThemeMode=="auto"&&!overlay.ThemeIsLight&&!File.Exists(path),"Wrong fresh automatic state");});
                IntPtr hwnd=new WindowInteropHelper(overlay).EnsureHandle();Layout(overlay);
                var snapshot=new BenchmarkLiveSnapshot {Fps=60,CurrentFps=64,Low=45,Mean=16.67,P99=25,Times=new[]{16.0,18,24},UpdatedUtc=DateTime.UtcNow};overlay.Update(snapshot);overlay.SetState("Gravando benchmark");
                // Creating/placing the native HWND legitimately persists monitor geometry.
                // A system theme event must preserve those bytes rather than forbid that contract.
                byte[] positionedBytes=File.ReadAllBytes(path);
                Check(output,"native Windows preference notification updates automatic overlay",delegate{
                    systemLight=true;SendMessage(hwnd,0x1A,new IntPtr(Int64.MaxValue),IntPtr.Zero);
                    Require(overlay.ThemeIsLight&&overlay.ThemeMode=="auto"&&Brightness(((Border)overlay.Content).Background)>.7&&positionedBytes.SequenceEqual(File.ReadAllBytes(path)),"Automatic notification failed or persisted");
                });
                Check(output,"manual dark overrides subsequent Windows notification",delegate{
                    overlay.SetThemeMode("dark");byte[] saved=File.ReadAllBytes(path);systemLight=true;SendMessage(hwnd,0x31A,IntPtr.Zero,IntPtr.Zero);
                    Require(!overlay.ThemeIsLight&&saved.SequenceEqual(File.ReadAllBytes(path)),"Manual dark overwritten or system event wrote profile");
                });
                Check(output,"manual light overrides dark Windows",delegate{overlay.SetThemeMode("light");systemLight=false;overlay.RefreshSystemTheme();Require(overlay.ThemeIsLight,"Manual light ignored");});
                var editor=new BenchmarkSettingsWindow(overlay,null);byte[] openingBytes=File.ReadAllBytes(path);
                try {
                    Check(output,"accessible theme selection performs the actual preference change",delegate{AccessibleSelect(Find<ToggleButton>(editor,"SettingsThemeDark"));Require(overlay.ThemeMode=="dark"&&!overlay.ThemeIsLight,"Accessible choice changed only the checkmark");AccessibleSelect(Find<ToggleButton>(editor,"SettingsThemeLight"));Require(overlay.ThemeMode=="light"&&overlay.ThemeIsLight,"Accessible light choice did not apply");});
                    Check(output,"selection changes draft only, without early profile writes",delegate{Click(editor,"SettingsThemeDark");Require(!overlay.ThemeIsLight&&openingBytes.SequenceEqual(File.ReadAllBytes(path)),"Draft persisted early");});
                    Check(output,"selecting the active mode again keeps one checked choice",delegate{Click(editor,"SettingsThemeDark");Require(Find<ToggleButton>(editor,"SettingsThemeDark").IsChecked==true&&Find<ToggleButton>(editor,"SettingsThemeLight").IsChecked==false,"Selection became empty or ambiguous");});
                    Check(output,"compact button synchronizes open settings and keeps a draft",delegate{
                        Click(overlay.ControlsWindow,"OverlayTheme");Require(overlay.ThemeIsLight&&Find<ToggleButton>(editor,"SettingsThemeLight").IsChecked==true&&openingBytes.SequenceEqual(File.ReadAllBytes(path)),"Button/settings draft out of sync");
                    });
                    Check(output,"automatic editor and preview follow Windows while open",delegate{
                        Click(editor,"SettingsThemeAuto");Require(!overlay.ThemeIsLight,"Wrong automatic dark");systemLight=true;SendMessage(hwnd,0x1A,IntPtr.Zero,IntPtr.Zero);
                        Require(overlay.ThemeIsLight&&Brightness(editor.Background)>.7&&Find<ToggleButton>(editor,"SettingsThemeAuto").IsChecked==true,"Open editor did not follow Windows");
                    });
                    Click(editor,"SettingsThemeDark");
                } finally {editor.Close();}
                Check(output,"Cancel restores previous theme and exact profile bytes",delegate{Require(overlay.ThemeMode=="light"&&overlay.ThemeIsLight&&openingBytes.SequenceEqual(File.ReadAllBytes(path)),"Cancel lost opening theme or wrote file");});
                editor=new BenchmarkSettingsWindow(overlay,null);Click(editor,"SettingsThemeDark");
                Check(output,"Save persists theme with existing profile contract",delegate{Require(editor.SaveChanges()&&editor.Saved&&BenchmarkOverlayPlacement.Load(path).ThemeMode=="dark","Theme Save failed");});editor.Close();
                using(var reopened=new ClosingOverlay(new BenchmarkOverlay(root,game,delegate(string message){},null,null,source))){Check(output,"saved per-game manual preference wins on restart",delegate{Require(reopened.Value.ThemeMode=="dark"&&!reopened.Value.ThemeIsLight,"Per-game theme did not survive restart");});}
                byte[] savedBytes=File.ReadAllBytes(path);editor=new BenchmarkSettingsWindow(overlay,null);Click(editor,"SettingsThemeLight");
                using(var locked=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.None)){
                    Check(output,"unavailable profile storage rejects Save and retains preview",delegate{Require(!editor.SaveChanges()&&overlay.ThemeIsLight&&!editor.Saved,"Failed storage claimed Save");});
                }
                editor.Close();Check(output,"failed Save plus Cancel restores saved theme and bytes",delegate{Require(overlay.ThemeMode=="dark"&&savedBytes.SequenceEqual(File.ReadAllBytes(path)),"Failure/Cancel changed profile");});
                using(var locked=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.None)){
                    Check(output,"compact toggle storage failure preserves visual mode and preferences",delegate{Require(!overlay.SetThemeMode("light")&&overlay.ThemeMode=="dark"&&!overlay.ThemeIsLight,"Failed quick save changed theme");});
                }
                Check(output,"invalid mode rejected without writing or clearing metrics",delegate{bool failed=false;try{overlay.SetThemeMode("sepia");}catch(ArgumentException){failed=true;}Require(failed&&savedBytes.SequenceEqual(File.ReadAllBytes(path))&&overlay.MetricText(0)==60.0.ToString("F1"),"Invalid mode mutated state");});
                overlay.SetThemeMode("auto");systemLight=true;overlay.RefreshSystemTheme();
                Check(output,"unavailable Windows preference preserves last valid theme and data",delegate{unavailable=true;overlay.RefreshSystemTheme();Require(overlay.ThemeIsLight&&overlay.ThemeMode=="auto"&&overlay.ReferenceCount==3&&overlay.MetricText(0)==60.0.ToString("F1"),"Unavailable system state cleared preference/data");unavailable=false;});
                foreach(bool medium in new[]{false,true}) {
                    overlay.SetMedium(medium);Layout(overlay);double left=overlay.Left,top=overlay.Top,width=overlay.Width;string metric=overlay.MetricText(0);
                    foreach(string mode in new[]{"light","dark"}) {
                        string currentMode=mode;
                        Check(output,"theme during recording preserves data/geometry "+mode+" "+medium,delegate{
                            overlay.SetThemeMode(currentMode);Require(overlay.Left==left&&overlay.Top==top&&overlay.Width==width&&overlay.MetricText(0)==metric&&overlay.ReferenceCount==3&&overlay.Medium==medium&&overlay.StatusText.Contains("Gravando"),"Theme interrupted overlay state");
                            if(medium){var current=overlay.ChartCurve(false);var reference=overlay.ChartCurve(true);Require(current!=null&&reference!=null&&current.Points.Count==3&&reference.StrokeDashArray.Count>0&&((SolidColorBrush)current.Stroke).Color==Color.FromRgb(255,128,0)&&((SolidColorBrush)reference.Stroke).Color==Color.FromRgb(83,174,255),"Approved curves lost");}
                        });
                        foreach(string control in new[]{"OverlaySmall","OverlayMedium","OverlayMove","OverlayFpsMode","OverlayTheme","OverlayReferenceToggle"}) {
                            string name=control;
                            Check(output,"control fits "+mode+" "+medium+" "+name,delegate{var b=Find<Button>((DependencyObject)overlay.Content,name);if(b.Visibility!=Visibility.Visible)return;var frame=(FrameworkElement)overlay.Content;Point at=b.TranslatePoint(new Point(),frame);Require(b.ActualHeight>=28&&at.X>=0&&at.X+b.ActualWidth<=frame.ActualWidth+.5,"Control clipped");});
                        }
                        Check(output,"native passthrough and accessible proxy "+mode+" "+medium,delegate{overlay.SetLocked(true);var button=Find<Button>(overlay.ControlsWindow,"OverlayTheme");Require((WindowStyle(hwnd,-20)&BenchmarkOverlayDesktop.Transparent)!=0&&(WindowStyle(new WindowInteropHelper(overlay.ControlsWindow).Handle,-20)&BenchmarkOverlayDesktop.Transparent)==0&&AutomationProperties.GetName(button).Contains(mode=="light"?"claro":"escuro"),"Native input or accessible theme label lost");});
                        editor=new BenchmarkSettingsWindow(overlay,null);
                        try {
                            foreach(double dpi in new[]{1.0,1.25,1.5}) {
                                double scale=dpi;
                                Check(output,"rendered settings contrast/footer "+mode+" DPI "+dpi,delegate{
                                    var content=(FrameworkElement)editor.Content;content.LayoutTransform=new ScaleTransform(scale,scale);content.Measure(new Size(660*scale,720));content.Arrange(new Rect(0,0,660*scale,720));content.UpdateLayout();
                                    Require(Accessible(UIElementAutomationPeer.CreatePeerForElement(editor.Tabs),"SettingsThemeAuto")&&Accessible(UIElementAutomationPeer.CreatePeerForElement(editor.Tabs),"SettingsThemeDark"),"Selected tab controls absent from accessibility tree");
                                    Require(Contrast(editor.Foreground,editor.Background)>=4.5&&Contrast(editor.SaveButton.Foreground,editor.SaveButton.Background)>=4.5&&Contrast(editor.CancelButton.Foreground,editor.CancelButton.Background)>=4.5,"Text contrast below 4.5");
                                    foreach(var b in new[]{editor.SaveButton,editor.CancelButton,editor.ResetButton}){Point at=b.TranslatePoint(new Point(),content);Require(at.Y>=0&&at.Y+b.ActualHeight<=content.ActualHeight+.5,"Footer clipped");}
                                });
                            }
                        } finally {editor.Close();}
                    }
                }
                var shadow=new BenchmarkOverlay(root,game,delegate(string message){},null,null,source);overlay.SetThemeMode("light");editor=new BenchmarkSettingsWindow(shadow,null);editor.AttachLiveOverlay(overlay);
                try {
                    Check(output,"late live overlay attachment synchronizes theme both directions",delegate{Click(editor,"SettingsThemeLight");Require(overlay.ThemeIsLight&&shadow.ThemeIsLight,"Attach did not preview theme");Click(overlay.ControlsWindow,"OverlayTheme");Require(!overlay.ThemeIsLight&&!shadow.ThemeIsLight&&Find<ToggleButton>(editor,"SettingsThemeDark").IsChecked==true,"Live button failed to synchronize shadow editor");});
                } finally {editor.Close();shadow.Close();}
                Check(output,"Cancel restores independently attached live opening preference",delegate{Require(overlay.ThemeMode=="light"&&overlay.ThemeIsLight,"Attached live opening mode lost");});
                Check(output,"all theme operations preserve another game's exact bytes",delegate{Require(other.SequenceEqual(File.ReadAllBytes(otherPath)),"Another game profile changed");});
                Check(output,"general theme defaults affect new games and preserve existing game bytes",delegate{
                    var general=new BenchmarkOverlay(root,new BenchmarkGame{Name="Defaults",Identity=BenchmarkOverlayPlacement.GeneralIdentity},delegate(string message){},null,null,source);
                    var settings=new BenchmarkSettingsWindow(general,null);
                    try{Click(settings,"SettingsThemeDark");Require(settings.SaveChanges(),"General theme save failed");using(var next=new ClosingOverlay(new BenchmarkOverlay(root,new BenchmarkGame{Name="New game",Identity="brand-new"},delegate(string message){},null,null,source))){Require(next.Value.ThemeMode=="dark"&&!next.Value.ThemeIsLight&&other.SequenceEqual(File.ReadAllBytes(otherPath)),"Defaults overwrote existing game");}}
                    finally{settings.Close();general.Close();}
                });
                int previousReads=reads;overlay.Close();overlay.RefreshSystemTheme();Check(output,"closed overlay stops reacting to Windows theme",delegate{Require(reads==previousReads,"Closed theme source still observed");});
            } finally {overlay.Close();}
        }
        private sealed class ClosingOverlay : IDisposable
        {
            internal readonly BenchmarkOverlay Value;internal ClosingOverlay(BenchmarkOverlay value){Value=value;}public void Dispose(){Value.Close();}
        }
    }
}
