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
  System.SysUtils,
  SYNC_Motion_FrameShared,
  SYNC_Motion_ContextManager,
  SYNC_Motion_MusicTempo,
  SYNC_Motion_TempoMotion;

var
  TempoItem: TFILTER_ITEM_TRACK;
  MusicFileItem: TFILTER_ITEM_FILE;
  MotionTypeItem: TFILTER_ITEM_SELECT;
  MotionTypeList: array[0..1] of TFILTER_ITEM_SELECT_ITEM;
  MotionSpeedItem: TFILTER_ITEM_TRACK;
  MotionWidthItem: TFILTER_ITEM_TRACK;
  MotionAngleItem: TFILTER_ITEM_TRACK;
  MotionShiftItem: TFILTER_ITEM_TRACK;

function MotionProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  AdjustedTime, BeatPosition, SegmentStartSeconds, TempoBpm: Double;
  EffectiveState: TSyncMotionFrameState;
  FrameState: TSyncMotionFrameState;
  MusicFileName: string;
begin
  try
    if TryReadMotionFrame(FrameState) and
      ResolveMotionFrameState(Video, FrameState, EffectiveState) then
    begin
      // 未知の種類は将来値として安全に無加工とする。
      if MotionTypeItem.Value <> 0 then
        Exit(1);

      MusicFileName := Trim(string(MusicFileItem.Value));
      if MusicFileName = '' then
      begin
        AdjustedTime := EffectiveState.TimeSeconds - MotionShiftItem.Value;
        if AdjustedTime >= 0 then
          ApplyBeatMotion(Video, AdjustedTime * TempoItem.Value / 60.0,
            MotionSpeedItem.Value, MotionWidthItem.Value,
            MotionAngleItem.Value);
      end
      else
      begin
        // 正のオフセットは動きを遅延させ、負の値は先行させる。
        if (Video <> nil) and (Video^.Object_ <> nil) and
          (EffectiveState.Rate > 0) and (EffectiveState.Scale > 0) then
        begin
          AdjustedTime := Video^.Object_^.Frame *
            EffectiveState.Scale / EffectiveState.Rate -
            MotionShiftItem.Value;
          if (AdjustedTime >= 0) and
            TryGetMusicSync(MusicFileName, AdjustedTime, BeatPosition,
              TempoBpm, SegmentStartSeconds) then
            ApplyBeatMotion(Video, BeatPosition, MotionSpeedItem.Value,
              MotionWidthItem.Value, MotionAngleItem.Value);
        end;
      end;
    end;
  except
    // Delphi例外をAviUtl2のコールバック境界より外へ漏らさない。
  end;
  Result := 1;
end;

var
  PluginItems: array[0..7] of Pointer;
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

    MotionTypeList[0].Name := 'ジャンプ';
    MotionTypeList[0].Value := 0;
    MotionTypeList[1].Name := nil;
    MotionTypeList[1].Value := 0;

    MotionTypeItem.ItemType := 'select';
    MotionTypeItem.Name := '動きタイプ';
    MotionTypeItem.Value := 0;
    MotionTypeItem.List := @MotionTypeList[0];

    MotionSpeedItem.ItemType := 'track';
    MotionSpeedItem.Name := '速さ';
    MotionSpeedItem.Value := 2.00;
    MotionSpeedItem.S := 1.00;
    MotionSpeedItem.E := 100.00;
    MotionSpeedItem.Step := 0.10;

    MotionWidthItem.ItemType := 'track';
    MotionWidthItem.Name := '幅';
    MotionWidthItem.Value := 50.00;
    MotionWidthItem.S := 0.00;
    MotionWidthItem.E := 1000.00;
    MotionWidthItem.Step := 1.00;

    MotionAngleItem.ItemType := 'track';
    MotionAngleItem.Name := '角度';
    MotionAngleItem.Value := 0.00;
    MotionAngleItem.S := -360.00;
    MotionAngleItem.E := 360.00;
    MotionAngleItem.Step := 0.10;

    MotionShiftItem.ItemType := 'track';
    MotionShiftItem.Name := 'ずらし';
    MotionShiftItem.Value := 0.00;
    MotionShiftItem.S := -60.00;
    MotionShiftItem.E := 60.00;
    MotionShiftItem.Step := 0.01;

    // AviUtl2はnil終端された項目ポインター配列を参照する。
    PluginItems[0] := @MusicFileItem;
    PluginItems[1] := @TempoItem;
    PluginItems[2] := @MotionTypeItem;
    PluginItems[3] := @MotionSpeedItem;
    PluginItems[4] := @MotionWidthItem;
    PluginItems[5] := @MotionAngleItem;
    PluginItems[6] := @MotionShiftItem;
    PluginItems[7] := nil;
    Plugin.Items := @PluginItems[0];
  end;
  Result := @Plugin;
end;

procedure InitializeMotionFilter;
begin
  InitializeMotionFrameShared;
  InitializeMotionContexts;
  InitializeMusicTempoCache;
end;

procedure FinalizeMotionFilter;
begin
  FinalizeMusicTempoCache;
  FinalizeMotionContexts;
  FinalizeMotionFrameShared;
end;

end.
