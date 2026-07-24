library SYNC_Motion_Input;

// 音楽同期アニメーション用の時刻ベースを提供する AviUtl2 入力プラグイン。

uses
  Winapi.Windows,
  AviUtl2InputTypes in 'Source\Lib\AviUtl2InputTypes.pas',
  SYNC_Motion_FrameShared in 'Source\Lib\SYNC_Motion_FrameShared.pas',
  SYNC_Motion_InputPlugin in 'Source\SYNC_Motion_InputPlugin.pas';

function func_open(FileName: LPCWSTR): INPUT_HANDLE; cdecl;
begin
  Result := MotionInputOpen(FileName);
end;

function func_close(Ih: INPUT_HANDLE): BOOL; cdecl;
begin
  Result := MotionInputClose(Ih);
end;

function func_info_get(Ih: INPUT_HANDLE; Info: PInputInfo): BOOL; cdecl;
begin
  Result := MotionInputGetInfo(Ih, Info);
end;

function func_read_video(Ih: INPUT_HANDLE; Frame: Integer; Buf: Pointer): Integer; cdecl;
begin
  Result := MotionInputReadVideo(Ih, Frame, Buf);
end;

function func_read_audio(Ih: INPUT_HANDLE; Start, Length: Integer; Buf: Pointer): Integer; cdecl;
begin
  Result := 0;
end;

function func_config(Hwnd: HWND; Hinst: HINST): BOOL; cdecl;
begin
  Result := MotionInputConfig(Hwnd, Hinst);
end;

var
  Plugin: TInputPluginTable = (
    flag: INPUT_PLUGIN_FLAG_VIDEO;
    name: '音楽同期ベース';
    filefilter: '音楽同期ベース (*.syncmotion)'#0'*.syncmotion'#0;
    information: '音楽同期アニメーション用フレーム位置入力';
    func_open: func_open;
    func_close: func_close;
    func_info_get: func_info_get;
    func_read_video: func_read_video;
    func_read_audio: func_read_audio;
    func_config: func_config;
    func_set_track: nil;
    func_time_to_frame: nil
  );

function GetInputPluginTable: PInputPluginTable; cdecl;
begin
  Result := @Plugin;
end;

exports
  GetInputPluginTable name 'GetInputPluginTable';

begin
end.
