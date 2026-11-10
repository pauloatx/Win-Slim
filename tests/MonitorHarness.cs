using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
namespace WinSlim.NativeUI
{
    internal static class MonitorHarness
    {
        private static void Check(bool value,string label) { if (!value) throw new Exception(label); Console.WriteLine("[OK] " + label); }
        private static string Arg(string[] args,string name) { int i=Array.IndexOf(args,name); return i<0?"":args[i+1]; }
        private static int Collector(string[] args)
        {
            string session=Arg(args,"--session_name"), marker=Path.Combine(Path.GetTempPath(),session+".monitor-stop");
            if (args.Contains("--terminate_existing_session")) { File.WriteAllText(marker,session); return 0; }
            int pid=Int32.Parse(Arg(args,"--process_id"));
            if (pid==7303) { Console.Error.WriteLine("ETW unavailable fixture"); return 7; }
            if (pid==7304) { Console.WriteLine("broken,header"); Console.Out.Flush(); Thread.Sleep(500); return 2; }
            if (!args.Contains("--output_stdout") || args.Contains("--output_file") || args.Contains("--timed")) return 8;
            Console.WriteLine("Application,ProcessID,SwapChainAddress,MsBetweenPresents"); Console.Out.Flush();
            Stopwatch clock=Stopwatch.StartNew(); int n=0;
            while (!File.Exists(marker) && clock.Elapsed.TotalSeconds<30) {
                if (pid!=7302 || n<100) { Console.WriteLine("game.exe," + (pid==7305?9999:pid) + ",0x1," + (n%97==96?0:n%100==99?40:10)); Console.Out.Flush(); n++; }
                Thread.Sleep(5);
            }
            if (File.Exists(marker)) File.Delete(marker);
            return 0;
        }
        private static void Until(Func<bool> predicate,int ms,string label)
        {
            Stopwatch clock=Stopwatch.StartNew(); while (!predicate() && clock.ElapsedMilliseconds<ms) Thread.Sleep(25); Check(predicate(),label);
        }
        private static int Main(string[] args)
        {
            if (args.Length>0 && args[0].StartsWith("--")) return Collector(args);
            string temp=Path.Combine(Path.GetTempPath(),"winslim-monitor-"+Guid.NewGuid().ToString("N")), exe=System.Reflection.Assembly.GetExecutingAssembly().Location;
            Directory.CreateDirectory(temp);
            try {
                var reader=new BenchmarkLiveReader(7301,"game.exe",true); DateTime now=DateTime.UtcNow;
                reader.Accept("Application,ProcessID,SwapChainAddress,MsBetweenPresents",now);
                for (int i=0;i<150000;i++) reader.Accept("game.exe,7301,0x1,10",now);
                Check(reader.BufferedCount==4096 && Math.Abs(reader.Snapshot(now).Fps-100)<.001,"moving sample buffer bounded after 150000 frames; statistics preserved");
                Check(reader.Snapshot(now.AddSeconds(3))==null,"stale data never reused as current");
                Check(reader.Snapshot(now.AddSeconds(6))==null && reader.BufferedCount==0,"moving duration evicts all old samples");
                for(int i=0;i<40;i++) reader.Accept("game.exe,7301,0x1,10",now);
                for(int i=0;i<40;i++) reader.Accept("game.exe,7301,0x1,20",now.AddSeconds(2));
                var snap=reader.Snapshot(now.AddSeconds(2));
                Check(Math.Abs(snap.CurrentFps-50)<.001 && Math.Abs(snap.Fps-66.6666667)<.001,"current FPS uses one second while average uses five seconds");
                var monitor=PresentMonMonitor.StartCore(temp,exe,7301,"game.exe");
                try {
                    Until(()=>monitor.Snapshot!=null,3000,"monitoring works before any benchmark");
                    Check(!Directory.Exists(Path.Combine(temp,"Benchmarks")),"continuous monitor writes no permanent frame CSV");
                    string session=monitor.Session;
                    using(var cts=new CancellationTokenSource()) {
                        var recording=monitor.RecordAsync(10,cts.Token); Thread.Sleep(500);
                        Check(!recording.IsCompleted && monitor.Snapshot!=null,"metrics and orange-curve samples exist before benchmark ends");
                        cts.Cancel(); bool cancelled=false;
                        try { recording.GetAwaiter().GetResult(); } catch(OperationCanceledException) { cancelled=true; }
                        Check(cancelled && monitor.Running && monitor.Session==session && monitor.Snapshot!=null,"cancelling recording preserves monitor and session");
                    }
                    BenchmarkResult result=monitor.RecordAsync(10,CancellationToken.None).GetAwaiter().GetResult();
                    Check(result.Frames>300 && result.InvalidFrames>0 && result.RequestedSeconds==10 && result.Session==session && result.ProcessId==7301 && result.FrameTimesMs.Length>10,"record again succeeds using complete capture statistics, invalid-frame accounting and the same collector");
                    Check(monitor.Running && monitor.Snapshot!=null && monitor.BufferedCount<=4096,"recording completion leaves continuous monitor running and bounded");
                    using(var cts=new CancellationTokenSource()) { cts.Cancel(); try { monitor.RecordAsync(10,cts.Token).GetAwaiter().GetResult(); } catch(OperationCanceledException) {} Check(result.Frames>300 && File.Exists(result.CsvPath),"cancelled restart preserves previous complete result and file"); }
                    bool duplicate=false; using(var cts=new CancellationTokenSource()) { var pending=monitor.RecordAsync(10,cts.Token); try { monitor.RecordAsync(10,CancellationToken.None).GetAwaiter().GetResult(); } catch(InvalidOperationException) {duplicate=true;} cts.Cancel(); try {pending.GetAwaiter().GetResult();}catch(OperationCanceledException){} }
                    Check(duplicate,"second concurrent recording rejected without duplicate ETW session");
                } finally { monitor.StopAsync().GetAwaiter().GetResult(); }
                Check(!monitor.Running && monitor.Completion.IsCompleted && monitor.Snapshot==null,"game/session stop cleans resources and clears current data");
                Check(!File.Exists(Path.Combine(Path.GetTempPath(),monitor.Session+".monitor-stop")),"owned-session stop consumed by its collector");
                foreach(int pid in new int[]{7302,7303,7304,7305}) {
                    var other=PresentMonMonitor.StartCore(temp,exe,pid,"game.exe");
                    try {
                        if(pid==7302) { Until(()=>other.Snapshot!=null,3000,"data available before renderer pause"); Thread.Sleep(2800); Check(other.Snapshot==null && other.State.Contains("desatualizados"),"renderer pause has explicit stale state"); }
                        else if(pid==7305) { Thread.Sleep(450); Check(other.Snapshot==null && other.State=="Coletando amostras","foreign PID rejected without fake zeros or old session"); }
                        else { Until(()=>!other.Running,3000,"collector failure and malformed stream stop cleanly"); Check(other.Error!=null && other.Snapshot==null,"unavailability reports reason and clears data"); }
                    } finally {other.StopAsync().GetAwaiter().GetResult();}
                }
                bool missing=false; try { PresentMonMonitor.StartAsync(temp,7301,"game.exe").GetAwaiter().GetResult(); } catch(InvalidDataException) {missing=true;} Check(missing,"production monitor refuses missing or unverified binary");
                Console.WriteLine("[OK] REG-MONITOR-001 complete"); return 0;
            } catch(Exception ex) {Console.Error.WriteLine(ex);return 1;}
            finally {Directory.Delete(temp,true);}
        }
    }
}
