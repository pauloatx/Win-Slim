"""Independent Windows ctypes layout oracle from pinned public NVAPI declarations, not adapter source."""
import ctypes as c
import hashlib
import json
import re
import sys
from pathlib import Path

def inspect(root):
    pin=json.loads((root/'specs/NVAPI-SDK-R3.2.84.json').read_text(encoding='utf-8-sig'))
    assert pin['commit']=='70d337db9186e968eab622f7e786de7e437faf3d'
    for item in pin['files']:
        assert hashlib.sha256((root/item['path']).read_bytes()).hexdigest()==item['sha256']
    sdk=root/'third_party/NvApiSdk'/pin['commit']
    api=(sdk/'nvapi.h').read_text(encoding='utf-8-sig')
    common=(sdk/'nvapi_lite_common.h').read_text(encoding='utf-8-sig')
    settings=(sdk/'NvApiDriverSettings.h').read_text(encoding='utf-8-sig')
    interfaces=(sdk/'nvapi_interface.h').read_text(encoding='utf-8-sig')
    def number(text,name):return int(re.search(r'\b'+name+r'\s*(?:=|\s)\s*(0x[0-9a-fA-F]+|\d+)',text).group(1),0)
    assert number(api,'NVAPI_UNICODE_STRING_MAX')==2048
    assert number(api,'NVAPI_BINARY_DATA_MAX')==4096
    assert number(api,'NVAPI_SETTING_MAX_VALUES')==100
    u32=c.c_uint32; unicode_string=c.c_uint16*2048
    class Binary(c.Structure):_fields_=[('length',u32),('bytes',c.c_uint8*4096)]
    class Value(c.Union):
        _pack_=4
        _fields_=[('dword',u32),('binary',Binary),('unicode',unicode_string),('qword',c.c_uint64)]
    class Setting(c.Structure):
        _pack_=4
        _fields_=[('Version',u32),('Name',unicode_string),('Id',u32),('Type',u32),('Location',u32),('CurrentPredefined',u32),('PredefinedValid',u32),('Predefined',Value),('Current',Value)]
    class SettingValues(c.Structure):
        _pack_=4
        _fields_=[('Version',u32),('Count',u32),('Type',u32),('Default',Value),('Values',Value*100)]
    class Application(c.Structure):
        _pack_=8
        _fields_=[('Version',u32),('Predefined',u32),('Name',unicode_string),('Friendly',unicode_string),('Launcher',unicode_string),('FileInFolder',unicode_string),('Flags',u32),('CommandLine',unicode_string)]
    class Profile(c.Structure):
        _pack_=8
        _fields_=[('Version',u32),('Name',unicode_string),('GpuSupport',u32),('Predefined',u32),('ApplicationCount',u32),('SettingCount',u32)]
    layouts={}
    for name,type_,revision in [('Setting',Setting,1),('SettingValues',SettingValues,1),('Application',Application,4),('Profile',Profile,1)]:
        layouts[name]={'size':c.sizeof(type_),'version':c.sizeof(type_)|(revision<<16),'offsets':{f[0]:getattr(type_,f[0]).offset for f in type_._fields_}}
    ids={name:int(value,16) for name,value in re.findall(r'\{\s*"([^"]+)",\s*(0x[0-9a-fA-F]+)',interfaces)}
    return {'sdkCommit':pin['commit'],'platform':sys.platform,'pointerBytes':c.sizeof(c.c_void_p),'layouts':layouts,
            'unicodeCodeUnitBytes':c.sizeof(c.c_uint16),'unionStride':c.sizeof(Value),
            'settingId':number(settings,'FRL_FPS_ID'),'headerRangeMin':number(settings,'FRL_FPS_MIN'),
            'headerRangeMax':number(settings,'FRL_FPS_MAX'),'headerRangeIsDriverCapability':False,
            'interfaceIds':ids,'physicalNvapiAbiCallTested':False}

if __name__=='__main__':
    print(json.dumps(inspect(Path(__file__).resolve().parents[2]),indent=2))
