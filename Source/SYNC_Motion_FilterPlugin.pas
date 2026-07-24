unit SYNC_Motion_FilterPlugin;

// 音楽同期アニメーションフィルターの登録と映像処理の入口。

interface

uses
  AviUtl2FilterTypes;

function GetMotionFilterTable: PFILTER_PLUGIN_TABLE;
procedure InitializeMotionFilter;
procedure FinalizeMotionFilter;

implementation

uses
  SYNC_Motion_FrameShared,
  SYNC_Motion_ContextManager,
  SYNC_Motion_TempoMotion;

var
  TempoItem: TFILTER_ITEM_TRACK;

function MotionProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  EffectiveState: TSyncMotionFrameState;
  FrameState: TSyncMotionFrameState;
begin
  try
    // 手動BPMと共有時刻がFilterへ届くことを、対象画像の上下移動で確認する。
    if TryReadMotionFrame(FrameState) and
      ResolveMotionFrameState(Video, FrameState, EffectiveState) then
      ApplyTempoMotion(Video, EffectiveState, TempoItem.Value);
  except
    // Delphi例外をAviUtl2のコールバック境界より外へ漏らさない。
  end;
  Result := 1;
end;

var
  MusicFileItem: TFILTER_ITEM_FILE;
  PluginItems: array[0..2] of Pointer;
  Plugin: TFILTER_PLUGIN_TABLE = (
    Flag: FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER;
    Name: 'SYNC_音楽同期アニメーション_Filter';
    Label_: 'SYNC';
    Information: '音楽に同期して画像を動かすフィルター';
    Items: nil;
    Func_Proc_Video: MotionProcVideo;
    Func_Proc_Audio: nil
  );

function GetMotionFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if Plugin.Items = nil then
  begin
    // ファイル選択値はAviUtl2に保持させ、解析処理はまだ行わない。
    MusicFileItem.ItemType := 'file';
    MusicFileItem.Name := '音楽ファイル';
    MusicFileItem.Value := '';
    MusicFileItem.FileFilter :=
      '音楽ファイル (*.mid;*.midi;*.ust;*.vsq;*.vsqx;*.musicxml;*.mxl;*.xml;*.mscx;*.mscz)'#0 +
      '*.mid;*.midi;*.ust;*.vsq;*.vsqx;*.musicxml;*.mxl;*.xml;*.mscx;*.mscz'#0#0;

    // 解析前でも一定テンポで同期できるよう、0を除く広いBPM範囲を持たせる。
    TempoItem.ItemType := 'track';
    TempoItem.Name := 'テンポ (BPM)';
    TempoItem.Value := 120.00;
    TempoItem.S := 1.00;
    TempoItem.E := 999.99;
    TempoItem.Step := 0.01;

    // AviUtl2はnil終端された項目ポインター配列を参照する。
    PluginItems[0] := @MusicFileItem;
    PluginItems[1] := @TempoItem;
    PluginItems[2] := nil;
    Plugin.Items := @PluginItems[0];
  end;
  Result := @Plugin;
end;

procedure InitializeMotionFilter;
begin
  InitializeMotionFrameShared;
  InitializeMotionContexts;
end;

procedure FinalizeMotionFilter;
begin
  FinalizeMotionContexts;
  FinalizeMotionFrameShared;
end;

end.
