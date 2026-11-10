using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
namespace WinSlim.NativeUI {
 internal static class OverlaySettingsLegacyRepro {
  private static Button Find(DependencyObject root,string text) {
   var button=root as Button; if(button!=null && Convert.ToString(button.Content)==text)return button;
   foreach(object child in LogicalTreeHelper.GetChildren(root)){var node=child as DependencyObject;if(node!=null){var found=Find(node,text);if(found!=null)return found;}}return null;
  }
  [STAThread] private static int Main(){
   string temp=Path.Combine(Path.GetTempPath(),"winslim-settings-before-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(temp);
   try {
    new Application {ShutdownMode=ShutdownMode.OnExplicitShutdown};
    var game=new BenchmarkGame {Name="Cities.exe",Identity=@"C:\Games\Cities.exe"};
    var overlay=new BenchmarkOverlay(temp,game,delegate{});overlay.Preferences.PanelScale=1.5;overlay.ApplyPreferences();
    string path=BenchmarkOverlayPlacement.PathFor(temp,game.Identity);byte[] original=File.ReadAllBytes(path);
    overlay.ResetPreferences(); overlay.Close();
    if(!original.SequenceEqual(File.ReadAllBytes(path))){Console.WriteLine("FAIL REG-OVERLAYSETTINGS-001: restoring defaults then closing without Save overwrote the original profile.");return 1;}
    return 0;
   } catch(Exception ex){Console.Error.WriteLine(ex);return 2;}finally{Directory.Delete(temp,true);}
  }
 }
}
