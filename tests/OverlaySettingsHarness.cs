using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace WinSlim.NativeUI {
 internal static class OverlaySettingsHarness {
  private static void Check(bool value,string message){if(!value)throw new Exception(message);Console.WriteLine("[OK] "+message);}
  private static T Find<T>(DependencyObject root,string name) where T:FrameworkElement{var value=root as T;if(value!=null&&value.Name==name)return value;foreach(object child in LogicalTreeHelper.GetChildren(root)){var item=child as DependencyObject;if(item!=null){var found=Find<T>(item,name);if(found!=null)return found;}}return null;}
  private static void Click(ButtonBase button){button.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));}
  private static void Layout(BenchmarkOverlay overlay){var content=(FrameworkElement)overlay.Content;content.Measure(new Size(overlay.Width,Double.PositiveInfinity));content.Arrange(new Rect(0,0,overlay.Width,content.DesiredSize.Height));content.UpdateLayout();var handle=new WindowInteropHelper(overlay).Handle;var rect=BenchmarkOverlayDesktop.Rect(handle);BenchmarkOverlayDesktop.Move(handle,rect.Left,rect.Top,(int)Math.Ceiling(overlay.Width),(int)Math.Ceiling(content.DesiredSize.Height),true);overlay.Place();}
  private static void Image(FrameworkElement root,int width,int height,string path){if(path==null)return;Directory.CreateDirectory(Path.GetDirectoryName(path));var bitmap=new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32);bitmap.Render(root);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var file=File.Create(path))encoder.Save(file);}
  [STAThread] private static int Main(string[] args){
   string temp=Path.Combine(Path.GetTempPath(),"winslim-settings-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(temp);
   try{
    new Application {ShutdownMode=ShutdownMode.OnExplicitShutdown};
    if(args.Length>0)UiLanguage.Initialize(args[0],true);
    var game=new BenchmarkGame {Name="Cities.exe",Identity=@"C:\Games\Cities.exe"};
    var screen=new BenchmarkOverlayMonitor {Id="fixture",Primary=true,Bounds=new BenchmarkGameWindow.Bounds {Left=0,Top=0,Right=1920,Bottom=1080}};
    var overlay=new BenchmarkOverlay(temp,game,Console.WriteLine,new double[]{16,24,20},delegate{return new[]{screen};});new WindowInteropHelper(overlay).EnsureHandle();Layout(overlay);
    overlay.Preferences.PanelScale=1.1;overlay.Preferences.Medium=true;overlay.Preferences.X=.4;overlay.Preferences.Y=.2;overlay.ApplyPreferences();Layout(overlay);
    var live=new BenchmarkLiveSnapshot {Fps=60,CurrentFps=64,Low=40,Mean=16.67,P99=25,Times=new double[]{16,18,25},UpdatedUtc=DateTime.UtcNow};overlay.Update(live);
    string path=BenchmarkOverlayPlacement.PathFor(temp,game.Identity);byte[] original=File.ReadAllBytes(path);var opening=overlay.Preferences.Clone();
    string otherPath=BenchmarkOverlayPlacement.PathFor(temp,@"D:\Other\Cities.exe");new BenchmarkOverlayPlacement {Schema=1,X=.1,Y=.2,Locked=true}.Save(otherPath);byte[] other=File.ReadAllBytes(otherPath);
    var registrations=new Dictionary<int,uint>();using(var hotkeys=new BenchmarkHotkeys(delegate(int id,uint mod,uint key){if(key==0x79)return false;registrations[id]=key;return true;},delegate(int id){registrations.Remove(id);})){
     hotkeys.Apply(new[]{"Ctrl+Alt+F8","",""},false);
     var window=new BenchmarkSettingsWindow(overlay,hotkeys);
     Check(window.Title=="Configurar overlay"&&hotkeys.Suspended,"settings opens explicitly with a themed title and suspends command dispatch");
     var anchor=BenchmarkOverlayDesktop.Rect(new WindowInteropHelper(overlay).Handle);window.ScaleControl.Value=1.5;window.OpacityControl.Value=.6;Layout(overlay);
     var resized=BenchmarkOverlayDesktop.Rect(new WindowInteropHelper(overlay).Handle);
     Check(overlay.Preferences.PanelScale==1.5&&overlay.Preferences.BackgroundOpacity==.6&&window.ScaleText=="150%"&&window.OpacityText=="60%","sliders immediately update live overlay, preview and percentage values");
     Check(resized.Left==anchor.Left&&resized.Top==anchor.Top&&overlay.Medium,"appearance changes preserve size mode and physical position when space permits; before="+anchor.Left+","+anchor.Top+" after="+resized.Left+","+resized.Top+" medium="+overlay.Medium);
     Check(original.SequenceEqual(File.ReadAllBytes(path)),"live geometry and appearance changes never write an unsaved draft");
     window.RestoreDefaults();Check(original.SequenceEqual(File.ReadAllBytes(path)),"restore defaults remains a draft until Save");
     window.CancelButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
     Check(overlay.Preferences.PanelScale==opening.PanelScale&&overlay.Preferences.Medium==opening.Medium&&overlay.Preferences.BackgroundOpacity==opening.BackgroundOpacity&&original.SequenceEqual(File.ReadAllBytes(path)),"Cancel restores opening appearance and preserves original profile bytes");
     Check(!hotkeys.Suspended&&hotkeys.Bindings[0]=="Ctrl+Alt+F8"&&overlay.MetricText(0)==60.0.ToString("F1")&&overlay.ReferenceCount==3,"cancel preserves active keys, live numbers and reference");
     window=new BenchmarkSettingsWindow(overlay,hotkeys);window.ScaleControl.Value=1.25;window.Close();Check(overlay.Preferences.PanelScale==opening.PanelScale&&original.SequenceEqual(File.ReadAllBytes(path)),"titlebar close behaves like Cancel");
     window=new BenchmarkSettingsWindow(overlay,hotkeys);overlay.Update(new BenchmarkLiveSnapshot {Fps=81,CurrentFps=90,Low=65,Mean=12.34,P99=18,Times=new double[]{12,18,12},UpdatedUtc=DateTime.UtcNow});window.ScaleControl.Value=1.25;
     Check(overlay.MetricText(0)==81.0.ToString("F1")&&window.PreviewMetricText(0)==60.0.ToString("F1")&&overlay.ReferenceCount==3,"illustrative preview stays separate from newly arriving live data and reference");
     Click(Find<ToggleButton>(window,"SettingsSmall"));Check(!overlay.Medium&&overlay.MetricCount==4,"settings Small selector applies immediately without adding or clearing game metrics");Click(Find<ToggleButton>(window,"SettingsMedium"));Check(overlay.Medium&&overlay.ChartCurve(false)!=null&&overlay.ChartCurve(true)!=null,"settings Medium selector preserves both graph curves");window.Close();overlay.Update(live);
     window=new BenchmarkSettingsWindow(overlay,hotkeys);window.BeginCapture(0);Check(Convert.ToString(window.KeyControl(0).Content)=="Pressione a combinação","click starts keyboard capture with an explicit prompt");
     window.CaptureKey(0,Key.F9,ModifierKeys.Control|ModifierKeys.Alt);Check(window.Binding(0)=="Ctrl+Alt+F9","captured combination is displayed without a text field");
     window.BeginCapture(2);window.CaptureKey(2,Key.F12,ModifierKeys.Control);Check(window.ErrorText(2)!=""&&!window.SaveChanges(),"reserved combination reports an inline error and an unfinished capture cannot Save");window.SetBinding(2,"");
     window.SetBinding(1,"Alt+Ctrl+F9");Check(window.ErrorText(0)!=""&&window.ErrorText(1)!=""&&!window.SaveChanges(),"duplicate combinations report errors alongside both fields and block Save");
     window.SetBinding(1,"");Check(window.ErrorText(0)==""&&Convert.ToString(window.KeyControl(1).Content)=="Não definido","clearing a shortcut removes its duplicate error and disables it");
     window.BeginCapture(2);hotkeys.Dispatch(0);Check(window.Binding(2)=="Ctrl+Alt+F8","already registered hotkey can be captured without executing its monitoring action");window.SetBinding(2,"");
     window.SetBinding(1,"Ctrl+Alt+F10");Check(!window.SaveChanges()&&window.ErrorText(1).Contains("indisponível")&&hotkeys.Bindings[0]=="Ctrl+Alt+F8","registration conflict appears at the affected field and restores previous keys");
     window.SetBinding(1,"");window.ScaleControl.Value=1.25;var computer=Find<ToggleButton>(window,"SettingsComputer");computer.IsChecked=true;Click(computer);
     foreach(string name in new[]{"CPU","GPU","VRAM"}){var item=Find<CheckBox>(window,"SettingsSensor"+name);item.IsChecked=false;Click(item);}
     overlay.SetSensors("CPU: 25%\nGPU: 60%\nVRAM: 2000 MiB\nRAM: Indisponível");
     Check(overlay.Preferences.Sensors&&!overlay.Preferences.ShowCpu&&!overlay.Preferences.ShowGpu&&!overlay.Preferences.ShowVram&&overlay.Preferences.ShowRam&&overlay.MetricCount==4,"computer information can be selected individually without changing the four game metrics");
     Check(window.SaveChanges()&&window.Saved&&!hotkeys.Suspended,"Save persists and closes the draft session cleanly");var persisted=BenchmarkOverlayPlacement.Load(path);
     Check(persisted.PanelScale==1.25&&persisted.Hotkeys[0]=="Ctrl+Alt+F9"&&!persisted.ShowCpu&&persisted.ShowRam,"appearance, selected sensors and shortcuts persist per executable");
     byte[] saved=File.ReadAllBytes(path);window=new BenchmarkSettingsWindow(overlay,hotkeys);window.ScaleControl.Value=1.4;
     using(var locked=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.None)){Check(!window.SaveChanges(),"unavailable profile storage fails Save without claiming success");}
     window.Close();Check(saved.SequenceEqual(File.ReadAllBytes(path))&&overlay.Preferences.PanelScale==1.25&&hotkeys.Bindings[0]=="Ctrl+Alt+F9","failed Save followed by close restores the prior saved state and shortcuts");
     Check(other.SequenceEqual(File.ReadAllBytes(otherPath)),"all settings operations preserve another game's profile");
     var readings=BenchmarkSensorText.Format(new Dictionary<string,object>{{"CPU",15},{"VramMiB",4096},{"GPU",Double.NaN}});
     Check(readings.Contains("CPU: 15% · Temperatura indisponível")&&readings.Contains((4096.0*1048576/1000000000).ToString("F2")+" GB")&&readings.Contains("VRAM do adaptador:")&&readings.Contains("GPU: Uso indisponível")&&!BenchmarkSensorText.Format(null).Contains("0%"),"sensor presentation distinguishes missing readings and converts MiB to decimal GB for the adapter");
     var general=new BenchmarkOverlay(temp,new BenchmarkGame {Name="Padrão para novos jogos",Identity=BenchmarkOverlayPlacement.GeneralIdentity},Console.WriteLine);
     window=new BenchmarkSettingsWindow(general,hotkeys);Check(window.ScopeText=="Padrão para novos jogos","general settings identifies defaults for new games");window.ScaleControl.Value=1.5;window.Close();
     Check(!File.Exists(BenchmarkOverlayPlacement.PathFor(temp,BenchmarkOverlayPlacement.GeneralIdentity)),"cancelled general draft creates no default profile");
     window=new BenchmarkSettingsWindow(general,hotkeys);window.ScaleControl.Value=1.35;window.SetBinding(0,"Ctrl+Alt+F8");Check(window.SaveChanges()&&hotkeys.Bindings[0]=="Ctrl+Alt+F9","general Save persists defaults without replacing current game hotkeys");
     var inherited=BenchmarkOverlayPlacement.LoadFor(temp,"new-game");Check(inherited.PanelScale==1.35&&!inherited.Medium&&!inherited.Sensors&&inherited.Locked&&inherited.Hotkeys[0]=="Ctrl+Alt+F8","new profiles inherit defaults, initially Small with sensors off and a fresh position");
     Check(BenchmarkOverlayPlacement.LoadFor(temp,game.Identity).PanelScale==1.25&&saved.SequenceEqual(File.ReadAllBytes(path)),"general preferences preserve existing per-game choices and bytes");general.Close();
     var shadow=new BenchmarkOverlay(temp,new BenchmarkGame {Name="New.exe",Identity="new-game"},Console.WriteLine);
     window=new BenchmarkSettingsWindow(shadow,hotkeys);window.ScaleControl.Value=1.5;
     var started=new BenchmarkOverlay(temp,new BenchmarkGame {Name="New.exe",Identity="new-game"},Console.WriteLine,new[]{16.0,80});new WindowInteropHelper(started).EnsureHandle();Layout(started);var startedOpening=started.Preferences.Clone();started.Update(live);window.AttachLiveOverlay(started);
     Check(started.Preferences.PanelScale==1.5&&started.MetricText(0)==60.0.ToString("F1")&&started.ReferenceCount==2,"starting monitor with settings already open attaches its draft without clearing data or reference");window.OpacityControl.Value=.55;window.Close();
     Check(started.Preferences.PanelScale==startedOpening.PanelScale&&started.Preferences.BackgroundOpacity==startedOpening.BackgroundOpacity,"Cancel restores newly attached live overlay's prior preferences");started.Close();shadow.Close();
     foreach(double dpi in new[]{1.0,1.25,1.5}){
      window=new BenchmarkSettingsWindow(overlay,hotkeys);new WindowInteropHelper(window).EnsureHandle();var root=(FrameworkElement)window.Content;root.LayoutTransform=new ScaleTransform(dpi,dpi);int width=(int)(660*dpi),height=720;
      window.ScaleControl.Value=1.2;window.SetBinding(2,"Ctrl+Shift+M");
      for(int tab=0;tab<3;tab++){
      window.SelectTab(tab);root.Measure(new Size(width,height));root.Arrange(new Rect(0,0,width,height));root.UpdateLayout();
      Check(window.Body.ViewportHeight>80&&window.Body.HorizontalScrollBarVisibility==ScrollBarVisibility.Disabled,"DPI "+dpi+", tab "+tab+": internal viewport remains usable with no horizontal scrolling");
      if(tab==0){
       window.ScaleControl.Value=.75;root.UpdateLayout();double small=window.PreviewPanel.TransformToAncestor(root).TransformBounds(new Rect(0,0,window.PreviewPanel.ActualWidth,window.PreviewPanel.ActualHeight)).Width;
       window.ScaleControl.Value=1.5;root.UpdateLayout();double large=window.PreviewPanel.TransformToAncestor(root).TransformBounds(new Rect(0,0,window.PreviewPanel.ActualWidth,window.PreviewPanel.ActualHeight)).Width;
       Check(Math.Abs(large/small-2)<.03,"DPI "+dpi+": rendered preview visibly reflects scale rather than normalising it away");window.ScaleControl.Value=1.2;root.UpdateLayout();
      }
      foreach(Button button in new[]{window.SaveButton,window.CancelButton,window.ResetButton}){Point at=button.TranslatePoint(new Point(),root);Check(button.ActualHeight>=34&&at.Y>=0&&at.Y+button.ActualHeight<=root.ActualHeight+.5,"DPI "+dpi+": footer action remains visible: "+button.Name);}
      var first=window.SaveButton.TranslatePoint(new Point(),root);var second=window.CancelButton.TranslatePoint(new Point(),root);Check(first.X+window.SaveButton.ActualWidth<=second.X+.5,"DPI "+dpi+": footer buttons do not overlap");
      string directory=args.Length>1?args[1]:null;Image(root,width,height,directory==null?null:Path.Combine(directory,"settings-"+(int)(dpi*100)+"-tab"+tab+".png"));
      if(tab==2){for(int key=0;key<3;key++){window.KeyControl(key).BringIntoView();root.UpdateLayout();var field=window.KeyControl(key);Point at=field.TranslatePoint(new Point(),window.Body);Check(at.Y>=0&&at.Y+field.ActualHeight<=window.Body.ActualHeight+.5&&field.ActualWidth>=150,"DPI "+dpi+": shortcut "+key+" is fully reachable");}}
      }
      window.SelectTab(0);Check(window.ScaleControl.Value==1.2&&window.Binding(2)=="Ctrl+Shift+M","switching tabs retains appearance and shortcut drafts");window.Close();
      var restore=overlay.BeginPreferencesEdit();overlay.Preferences.PanelScale=dpi;overlay.Preferences.Sensors=true;overlay.Preferences.ShowCpu=overlay.Preferences.ShowGpu=overlay.Preferences.ShowVram=overlay.Preferences.ShowRam=true;overlay.SetSensors(readings);overlay.Update(live);
      foreach(bool medium in new[]{false,true}){
       overlay.Preferences.Medium=medium;overlay.ApplyEditedPreferences();Layout(overlay);var frame=(FrameworkElement)overlay.Content;
       foreach(string control in new[]{"OverlaySmall","OverlayMedium","OverlayMove","OverlayFpsMode"}){var button=Find<Button>(frame,control);Point at=button.TranslatePoint(new Point(),frame);Check(button.ActualHeight>=28&&at.X>=0&&at.X+button.ActualWidth<=frame.ActualWidth+.5,"DPI "+dpi+": "+control+" fits "+(medium?"Medium":"Small"));}
       Image(frame,(int)Math.Ceiling(frame.ActualWidth*dpi),(int)Math.Ceiling(frame.ActualHeight*dpi),args.Length>1?Path.Combine(args[1],"overlay-"+(int)(dpi*100)+(medium?"-medium.png":"-small.png")):null);
      }
      overlay.CancelPreferencesEdit(restore);
     }
    }
    overlay.Close();Check(other.SequenceEqual(File.ReadAllBytes(otherPath)),"other game remains unchanged after DPI layout tests");Console.WriteLine("[OK] REG-OVERLAYSETTINGS-001 complete; DPI simulated in WPF, physical monitor acceptance pending.");return 0;
   }catch(Exception ex){Console.Error.WriteLine(ex);return 1;}finally{Directory.Delete(temp,true);}
  }
 }
}
