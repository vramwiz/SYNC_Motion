unit SYNC_Motion_FilterPlugin;

// 音楽同期アニメーションフィルターの最小登録処理。
// 現段階では入力画像を変更せず、共有されたフレーム情報の受信だけを確認する。

interface

uses
  AviUtl2FilterTypes;

function GetMotionFilterTable: PFILTER_PLUGIN_TABLE;
procedure InitializeMotionFilter;
procedure FinalizeMotionFilter;

implementation

uses
  SYNC_Motion_FrameShared;

function MotionProcVideo(Video: Pointer): Byte; cdecl;
var
  FrameState: TSyncMotionFrameState;
begin
  // 揺れ計算は次段階で実装する。現在は入力画像をそのまま通す。
  TryReadMotionFrame(FrameState);
  Result := 1;
end;

var
  Plugin: TFILTER_PLUGIN_TABLE = (
    Flag: FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER;
    Name: '音楽同期アニメーション';
    Label_: 'アニメーション';
    Information: '音楽に同期して画像を動かすフィルター';
    Items: nil;
    Func_Proc_Video: MotionProcVideo;
    Func_Proc_Audio: nil
  );

function GetMotionFilterTable: PFILTER_PLUGIN_TABLE;
begin
  Result := @Plugin;
end;

procedure InitializeMotionFilter;
begin
  InitializeMotionFrameShared;
end;

procedure FinalizeMotionFilter;
begin
  FinalizeMotionFrameShared;
end;

end.
