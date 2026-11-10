// Development-only NVAPI reader. No setting/profile/application mutation or persistence API.
// SDK ABI: NVIDIA/nvapi 70d337db9186e968eab622f7e786de7e437faf3d (MIT; see pinned headers).
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace WinSlim.Development.NvapiReadOnly {
    [StructLayout(LayoutKind.Sequential, Pack=4, CharSet=CharSet.Unicode)]
    public struct Setting {
        public uint Version;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=2048)] public string Name;
        public uint Id, Type, Location, CurrentPredefined, PredefinedValid;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=4100)] public byte[] Predefined;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=4100)] public byte[] Current;
        public static Setting New() { return new Setting { Version=Abi.Version(typeof(Setting),1), Name="", Predefined=new byte[4100], Current=new byte[4100] }; }
    }
    [StructLayout(LayoutKind.Sequential, Pack=4)]
    public struct SettingValues {
        public uint Version, Count, Type;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=414100)] public byte[] Payload;
        public static SettingValues New() { return new SettingValues { Version=Abi.Version(typeof(SettingValues),1), Payload=new byte[414100] }; }
    }
    [StructLayout(LayoutKind.Sequential, Pack=8, CharSet=CharSet.Unicode)]
    public struct Application {
        public uint Version, Predefined;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=2048)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=2048)] public string Friendly;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=2048)] public string Launcher;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=2048)] public string FileInFolder;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=2048)] public string CommandLine;
        public static Application New() { return new Application { Version=Abi.Version(typeof(Application),4), Name="", Friendly="", Launcher="", FileInFolder="", CommandLine="" }; }
    }
    [StructLayout(LayoutKind.Sequential, Pack=8, CharSet=CharSet.Unicode)]
    public struct Profile {
        public uint Version;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=2048)] public string Name;
        public uint GpuSupport, Predefined, ApplicationCount, SettingCount;
        public static Profile New() { return new Profile { Version=Abi.Version(typeof(Profile),1), Name="" }; }
    }
    public static class Abi {
        public const uint SettingId=0x10835002;
        public static uint Version(Type type, uint revision) { return (uint)Marshal.SizeOf(type) | (revision << 16); }
        public static void Validate() {
            if (Marshal.SizeOf(typeof(Setting))!=12320 || Marshal.SizeOf(typeof(SettingValues))!=414112 ||
                Marshal.SizeOf(typeof(Application))!=20492 || Marshal.SizeOf(typeof(Profile))!=4116 ||
                Marshal.OffsetOf(typeof(Setting),"Current").ToInt32()!=8220 ||
                Marshal.OffsetOf(typeof(Application),"CommandLine").ToInt32()!=16396)
                throw new InvalidOperationException("SDK structure layout mismatch; do not bind driver.");
        }
        public static string GameKey(string path) {
            if (String.IsNullOrWhiteSpace(path) || path.Length>=2048 || path.Length<4 || !Char.IsLetter(path[0]) ||
                path[1]!=':' || (path[2]!='\\' && path[2]!='/') || path.Substring(2).IndexOf(':')>=0 ||
                path.IndexOfAny(new char[]{'\0','\r','\n','\t','"','<','>','|','*','?'})>=0)
                throw new ArgumentException("Full local game executable path required.");
            string full=Path.GetFullPath(path);
            if (!String.Equals(Path.GetExtension(full),".exe",StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("Executable path required.");
            return full.ToLowerInvariant();
        }
    }
    // This is the complete transport surface, deliberately without save/set/delete/create-profile.
    public interface IReadApi {
        int Initialize(); int Unload(); int Driver(out uint version, StringBuilder branch);
        int Create(out IntPtr session); int Destroy(IntPtr session); int Load(IntPtr session);
        int Find(IntPtr session, string fullPath, out IntPtr profile, ref Application application);
        int Info(IntPtr session, IntPtr profile, ref Profile info);
        int Base(IntPtr session, out IntPtr profile); int Global(IntPtr session, out IntPtr profile);
        int ReadSetting(IntPtr session, IntPtr profile, uint id, ref Setting setting);
        int Values(uint id, ref uint maximum, ref SettingValues values);
    }
    public sealed class Snapshot {
        public string Source="nvapi-readonly", Status="Unavailable", Stage, GamePath, DriverBranch, ProfileName, StoredApplication;
        public string Origin, Mapping, EligibilityReason;
        public int? NativeStatus;
        public uint? DriverVersion, Value, PredefinedValue;
        public uint? SettingLocation, ApplicationCount;
        public bool CurrentPredefined, PredefinedValid, GlobalProfile, SharedProfile, HasValue, ReadComplete;
        public bool ReadOnly=true, CanApplyToDriver=false, PhysicalFrameLimitTested=false;
        public bool CapabilitiesAvailable, EnumeratedValuesAreCompleteRange=false;
        public uint[] RawEnumeratedValues=new uint[0];
        public List<string> CleanupErrors=new List<string>();
    }
    public static class Reader {
        static void Ok(int status, string stage) { if(status!=0) throw new ProbeException(stage,status); }
        public static Snapshot Read(IReadApi api, string path) {
            string key=Abi.GameKey(path); Abi.Validate();
            Snapshot result=new Snapshot { GamePath=key }; IntPtr session=IntPtr.Zero; bool initialized=false;
            try {
                Ok(api.Initialize(),"Initialize"); initialized=true;
                uint driver; StringBuilder branch=new StringBuilder(64); Ok(api.Driver(out driver,branch),"DriverVersion");
                if(driver==0) throw new ProbeException("InvalidDriverVersion",null);
                result.DriverVersion=driver; result.DriverBranch=branch.ToString();
                Ok(api.Create(out session),"CreateSession"); if(session==IntPtr.Zero) throw new ProbeException("NullSession",null);
                Ok(api.Load(session),"LoadSettings");
                IntPtr profile; Application app=Application.New();
                Ok(api.Find(session,key,out profile,ref app),"FindFullPath");
                if(profile==IntPtr.Zero) throw new ProbeException("NullProfile",null);
                if(app.Version!=Abi.Version(typeof(Application),4)) throw new ProbeException("ApplicationVersion",null);
                Profile info=Profile.New(); Ok(api.Info(session,profile,ref info),"ProfileInfo");
                if(info.Version!=Abi.Version(typeof(Profile),1) || info.ApplicationCount>4096) throw new ProbeException("ProfileVersionOrCount",null);
                IntPtr baseProfile,globalProfile; Ok(api.Base(session,out baseProfile),"BaseProfile"); Ok(api.Global(session,out globalProfile),"GlobalProfile");
                result.ProfileName=info.Name; result.ApplicationCount=info.ApplicationCount; result.StoredApplication=app.Name;
                result.GlobalProfile=(profile==baseProfile || profile==globalProfile || profile==new IntPtr(-1));
                result.SharedProfile=info.ApplicationCount!=1;
                bool exact=false; try {exact=String.Equals(Abi.GameKey(app.Name),key,StringComparison.Ordinal);} catch(ArgumentException) {}
                result.Mapping=exact?"ExactStoredPath":"DriverResolvedGenericAssociation";
                result.EligibilityReason=result.GlobalProfile?"Global profile":result.SharedProfile?"Shared or empty profile":!exact?"Stored association is not an exact full path":
                    app.Flags!=0 || !String.IsNullOrEmpty(app.Launcher) || !String.IsNullOrEmpty(app.FileInFolder) || !String.IsNullOrEmpty(app.CommandLine)?"Qualified or command-line association":"Read-only prototype; physical write eligibility not approved";
                Setting setting=Setting.New(); int settingStatus=api.ReadSetting(session,profile,Abi.SettingId,ref setting);
                if(settingStatus==-160) {result.Origin="Absent"; result.HasValue=false;}
                else {
                    Ok(settingStatus,"GetSetting");
                    if(setting.Version!=Abi.Version(typeof(Setting),1) || setting.Id!=Abi.SettingId || setting.Type!=0 || setting.Location>3 ||
                        setting.Current==null || setting.Current.Length!=4100 || setting.Predefined==null || setting.Predefined.Length!=4100 ||
                        setting.CurrentPredefined>1 || setting.PredefinedValid>1) throw new ProbeException("SettingContract",null);
                    result.HasValue=true; result.Value=BitConverter.ToUInt32(setting.Current,0); result.SettingLocation=setting.Location;
                    result.CurrentPredefined=setting.CurrentPredefined!=0; result.PredefinedValid=setting.PredefinedValid!=0;
                    if(result.PredefinedValid) result.PredefinedValue=BitConverter.ToUInt32(setting.Predefined,0);
                    result.Origin=setting.Location==0?(result.CurrentPredefined?"CurrentPredefined":"CurrentExplicit"):
                        setting.Location==1?"GlobalInherited":setting.Location==2?"BaseInherited":"DefaultInherited";
                }
                SettingValues values=SettingValues.New(); uint maximum=100; int capabilities=api.Values(Abi.SettingId,ref maximum,ref values);
                if(capabilities==0) {
                    if(values.Version!=Abi.Version(typeof(SettingValues),1) || values.Type!=0 || maximum>100 || values.Count>maximum ||
                        values.Payload==null || values.Payload.Length!=414100) throw new ProbeException("CapabilityContract",null);
                    result.RawEnumeratedValues=new uint[values.Count];
                    for(int i=0;i<values.Count;i++) result.RawEnumeratedValues[i]=BitConverter.ToUInt32(values.Payload,4100*(i+1));
                    result.CapabilitiesAvailable=true;
                }
                result.ReadComplete=capabilities==0; result.Status=capabilities==0?"ReadOnlySnapshot":"PartialCapabilitiesUnavailable";
                result.Stage=capabilities==0?"Completed":"EnumAvailableSettingValues"; if(capabilities!=0) result.NativeStatus=capabilities;
            } catch(ProbeException ex) {result.Status="Unavailable";result.Stage=ex.Stage;result.NativeStatus=ex.Status;result.ReadComplete=false;}
            catch(Exception ex) {result.Status="Unavailable";result.Stage="ReadFailure:"+ex.GetType().Name;result.ReadComplete=false;}
            finally {
                if(session!=IntPtr.Zero) try {int code=api.Destroy(session);if(code!=0) result.CleanupErrors.Add("DestroySession:"+code);}catch(Exception ex){result.CleanupErrors.Add("DestroySession:"+ex.GetType().Name);}
                if(initialized) try {int code=api.Unload();if(code!=0) result.CleanupErrors.Add("Unload:"+code);}catch(Exception ex){result.CleanupErrors.Add("Unload:"+ex.GetType().Name);}
                if(result.CleanupErrors.Count>0) {result.ReadComplete=false;result.Status="CleanupFailed";}
            }
            return result;
        }
        sealed class ProbeException : Exception { public string Stage;public int? Status;public ProbeException(string stage,int? status){Stage=stage;Status=status;} }
    }
    // Private binding implementation can resolve only these reviewed read/lifecycle interfaces.
    public sealed class InstalledReader {
        public static uint[] InterfaceIds() { return new uint[]{0x0150e828,0xd22bdd7e,0x2926aaad,0x0694d52e,0xdad9cff8,0x375dbd6b,0xeee566b2,0x61cd6fd6,0xda8466a0,0x617bff9f,0x73bf8338,0x2ec39f90}; }
        static readonly object Gate=new object();
        public static Snapshot ReadValidatedSystemLibrary(string gamePath,string expectedSha256) {
            Abi.GameKey(gamePath); Abi.Validate();
            if(IntPtr.Size!=8) return new Snapshot {Stage="UnsupportedProcessArchitecture"};
            string library=Path.Combine(Environment.SystemDirectory,"nvapi64.dll");
            if(!File.Exists(library)) return new Snapshot {Stage="DriverLibraryMissing",GamePath=Abi.GameKey(gamePath)};
            if(String.IsNullOrEmpty(expectedSha256) || expectedSha256.Length!=64) throw new ArgumentException("Wrapper must verify Authenticode/publisher and supply exact installed DLL hash.");
            lock(Gate) {
                if(!String.Equals(Hash(library),expectedSha256,StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Driver library changed after signature review.");
                using(Binding binding=new Binding(library)) {
                    if(!String.Equals(Hash(library),expectedSha256,StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Driver library changed while loading.");
                    return Reader.Read(binding,gamePath);
                }
            }
        }
        static string Hash(string path) {using(SHA256 sha=SHA256.Create())using(FileStream stream=File.OpenRead(path)){return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","");}}
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryExW(string file,IntPtr reserved,uint flags);
        [DllImport("kernel32.dll",CharSet=CharSet.Ansi,ExactSpelling=true,SetLastError=true)] static extern IntPtr GetProcAddress(IntPtr module,string name);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool FreeLibrary(IntPtr module);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr Query(uint id);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Simple();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl,CharSet=CharSet.Ansi)] delegate int DriverFn(out uint version,StringBuilder branch);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int CreateFn(out IntPtr session);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SessionFn(IntPtr session);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl,CharSet=CharSet.Unicode)] delegate int FindFn(IntPtr session,[MarshalAs(UnmanagedType.LPWStr)]string path,out IntPtr profile,[In,Out]ref Application application);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int InfoFn(IntPtr session,IntPtr profile,[In,Out]ref Profile info);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int ProfileFn(IntPtr session,out IntPtr profile);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SettingFn(IntPtr session,IntPtr profile,uint id,[In,Out]ref Setting setting);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int ValuesFn(uint id,ref uint maximum,[In,Out]ref SettingValues values);
        sealed class Binding : IReadApi, IDisposable {
            IntPtr module; Query query; Dictionary<uint,IntPtr> pointers=new Dictionary<uint,IntPtr>();
            T Get<T>(uint id) where T:class {
                if(Array.IndexOf(InterfaceIds(),id)<0) throw new InvalidOperationException("Non-readonly interface denied.");
                IntPtr pointer=pointers[id];
                return (T)(object)Marshal.GetDelegateForFunctionPointer(pointer,typeof(T));
            }
            public Binding(string path) {
                module=LoadLibraryExW(path,IntPtr.Zero,0x00000800); // LOAD_LIBRARY_SEARCH_SYSTEM32; no current-directory fallback
                if(module==IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                IntPtr address=GetProcAddress(module,"nvapi_QueryInterface");
                if(address==IntPtr.Zero){Dispose();throw new EntryPointNotFoundException("nvapi_QueryInterface");}
                query=(Query)Marshal.GetDelegateForFunctionPointer(address,typeof(Query));
                try {foreach(uint id in InterfaceIds()){IntPtr pointer=query(id);if(pointer==IntPtr.Zero)throw new EntryPointNotFoundException("NVAPI interface unavailable: "+id.ToString("X8"));pointers.Add(id,pointer);}}
                catch {Dispose();throw;}
            }
            public int Initialize(){return Get<Simple>(0x0150e828)();} public int Unload(){return Get<Simple>(0xd22bdd7e)();}
            public int Driver(out uint version,StringBuilder branch){return Get<DriverFn>(0x2926aaad)(out version,branch);}
            public int Create(out IntPtr session){return Get<CreateFn>(0x0694d52e)(out session);}
            public int Destroy(IntPtr session){return Get<SessionFn>(0xdad9cff8)(session);} public int Load(IntPtr session){return Get<SessionFn>(0x375dbd6b)(session);}
            public int Find(IntPtr session,string path,out IntPtr profile,ref Application application){return Get<FindFn>(0xeee566b2)(session,path,out profile,ref application);}
            public int Info(IntPtr session,IntPtr profile,ref Profile info){return Get<InfoFn>(0x61cd6fd6)(session,profile,ref info);}
            public int Base(IntPtr session,out IntPtr profile){return Get<ProfileFn>(0xda8466a0)(session,out profile);}
            public int Global(IntPtr session,out IntPtr profile){return Get<ProfileFn>(0x617bff9f)(session,out profile);}
            public int ReadSetting(IntPtr session,IntPtr profile,uint id,ref Setting setting){return Get<SettingFn>(0x73bf8338)(session,profile,id,ref setting);}
            public int Values(uint id,ref uint maximum,ref SettingValues values){return Get<ValuesFn>(0x2ec39f90)(id,ref maximum,ref values);}
            public void Dispose(){if(module!=IntPtr.Zero){FreeLibrary(module);module=IntPtr.Zero;}query=null;}
        }
    }
}
