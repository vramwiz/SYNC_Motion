library SYNC_Motion_Filter;

// 音楽同期アニメーションフィルターの AviUtl2 DLL 境界。

{$ALIGN 8}

uses
  Winapi.Windows,
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  SharedMemoryBase in 'Source\Lib\SharedMemoryBase.pas',
  SYNC_Motion_FrameShared in 'Source\Lib\SYNC_Motion_FrameShared.pas',
  SYNC_Motion_ContextManager in 'Source\SYNC_Motion_ContextManager.pas',
  SYNC_Motion_TempoMotion in 'Source\SYNC_Motion_TempoMotion.pas',
  SYNC_Motion_FilterPlugin in 'Source\SYNC_Motion_FilterPlugin.pas';

function InitializePlugin(Version: DWORD): Byte; cdecl;
begin
  InitializeMotionFilter;
  Result := 1;
end;

procedure UninitializePlugin; cdecl;
begin
  FinalizeMotionFilter;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := GetMotionFilterTable;
end;

exports
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
