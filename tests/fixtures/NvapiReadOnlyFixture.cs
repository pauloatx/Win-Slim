using System;
using System.Collections.Generic;
using System.Text;
using WinSlim.Development.NvapiReadOnly;
// Managed data fixture, compiled only as a DLL alongside the new independent adapter.
// Does not load NVAPI, create subprocesses, CSV or stop markers, or write driver settings.
namespace WinSlim.Development.NvapiReadOnlyTests {
 public sealed class FixtureApi : IReadApi {
  public string Failure="",LastPath=""; public int Calls,Unloads,Destroys;
  public uint Value=60,Location=0,SettingType=0,CurrentPredefined=0,PredefinedValid=1,Apps=1,Flags=0;
  public uint SettingVersion=Abi.Version(typeof(Setting),1),AppVersion=Abi.Version(typeof(Application),4),CapabilityCount=3;
  public bool Missing=false,Generic=false,GlobalProfile=false,ThrowSetting=false;
  public int Hit(string name){Calls++;return Failure==name?-9:0;}
  public int Initialize(){return Hit("Initialize");}public int Unload(){Unloads++;return Hit("Unload");}
  public int Driver(out uint version,StringBuilder branch){version=56000;branch.Append("fixture-not-a-driver");return Hit("DriverVersion");}
  public int Create(out IntPtr session){session=Failure=="CreateSession"?IntPtr.Zero:new IntPtr(10);return Hit("CreateSession");}
  public int Destroy(IntPtr session){Destroys++;return Hit("DestroySession");}public int Load(IntPtr session){return Hit("LoadSettings");}
  public int Find(IntPtr session,string path,out IntPtr profile,ref Application app){
   LastPath=path;profile=GlobalProfile?new IntPtr(1):new IntPtr(99);app.Name=Generic?"game.exe":path;app.Version=AppVersion;app.Flags=Flags;return Hit("FindFullPath");
  }
  public int Info(IntPtr session,IntPtr profile,ref Profile info){info.Name="Fixture isolated game";info.ApplicationCount=Apps;return Hit("ProfileInfo");}
  public int Base(IntPtr session,out IntPtr profile){profile=new IntPtr(1);return Hit("BaseProfile");}
  public int Global(IntPtr session,out IntPtr profile){profile=new IntPtr(2);return Hit("GlobalProfile");}
  public int ReadSetting(IntPtr session,IntPtr profile,uint id,ref Setting setting){
   if(ThrowSetting)throw new InvalidOperationException("fixture read exception");
   if(Missing)return -160;
   setting.Version=SettingVersion;setting.Id=id;setting.Type=SettingType;setting.Location=Location;setting.CurrentPredefined=CurrentPredefined;setting.PredefinedValid=PredefinedValid;
   Array.Copy(BitConverter.GetBytes(Value),setting.Current,4);Array.Copy(BitConverter.GetBytes((uint)0),setting.Predefined,4);return Hit("GetSetting");
  }
  public int Values(uint id,ref uint maximum,ref SettingValues values){
   values.Count=CapabilityCount;values.Type=0;uint[] raw={0,0,1023};
   for(int i=0;i<raw.Length;i++)Array.Copy(BitConverter.GetBytes(raw[i]),0,values.Payload,4100*(i+1),4);
   return Hit("EnumAvailableSettingValues");
  }
 }
}
