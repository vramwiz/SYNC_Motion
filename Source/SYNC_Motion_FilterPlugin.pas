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
  System.Math,
  System.SysUtils,
  SYNC_Motion_MusicTempo,
  SYNC_Motion_Time,
  SYNC_Motion_TempoMotion;

const
  VOLUME_TYPE_NONE      = 0;
  VOLUME_TYPE_EXPANSION = 1;
  PITCH_TYPE_NONE       = 0;
  PITCH_TYPE_VERTICAL   = 1;

var
  MusicFileItem       : TFILTER_ITEM_FILE;
  TempoItem           : TFILTER_ITEM_TRACK;
  OffsetItem          : TFILTER_ITEM_TRACK;
  RhythmShiftItem     : TFILTER_ITEM_TRACK;
  RhythmGroup         : TFILTER_ITEM_GROUP;
  RhythmTypeItem      : TFILTER_ITEM_SELECT;
  RhythmTypeList      : array[0..7] of TFILTER_ITEM_SELECT_ITEM;
  RhythmStrengthItem  : TFILTER_ITEM_TRACK;
  RhythmSpeedItem     : TFILTER_ITEM_TRACK;
  RhythmParam1Item    : TFILTER_ITEM_TRACK;
  RhythmParam2Item    : TFILTER_ITEM_TRACK;
  VolumeGroup         : TFILTER_ITEM_GROUP;
  VolumeTypeItem      : TFILTER_ITEM_SELECT;
  VolumeTypeList      : array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  VolumeStrengthItem  : TFILTER_ITEM_TRACK;
  PitchGroup          : TFILTER_ITEM_GROUP;
  PitchTypeItem       : TFILTER_ITEM_SELECT;
  PitchTypeList       : array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  PitchHighPullItem   : TFILTER_ITEM_TRACK;
  PitchLowSinkItem    : TFILTER_ITEM_TRACK;
  PitchBaseNoteItem   : TFILTER_ITEM_TRACK;

procedure ApplySelectedRhythmMotion(Video: PFILTER_PROC_VIDEO;
  BeatPosition: Double);
begin
  if (RhythmTypeItem.Value < Ord(Low(TRhythmMotionType))) or
    (RhythmTypeItem.Value > Ord(High(TRhythmMotionType))) then
    Exit;
  ApplyRhythmMotion(Video, TRhythmMotionType(RhythmTypeItem.Value),
    BeatPosition, RhythmSpeedItem.Value, RhythmStrengthItem.Value,
    RhythmParam1Item.Value, RhythmParam2Item.Value);
end;

procedure ApplySelectedMusicMotion(Video: PFILTER_PROC_VIDEO;
  const MusicFileName: string; TimeSeconds, BeatPosition: Double);
var
  Level, NoteEnvelope, NoteNumber, VolumeStrength: Double;
begin
  if (RhythmTypeItem.Value < Ord(Low(TRhythmMotionType))) or
    (RhythmTypeItem.Value > Ord(High(TRhythmMotionType))) then
    Exit;

  Level := 0;
  VolumeStrength := 0;
  if (VolumeTypeItem.Value = VOLUME_TYPE_EXPANSION) and
    not SameValue(VolumeStrengthItem.Value, 0) and
    TryGetMusicVolume(MusicFileName, TimeSeconds, Level) then
    VolumeStrength := VolumeStrengthItem.Value;

  NoteNumber := PitchBaseNoteItem.Value;
  NoteEnvelope := 0;
  if (PitchTypeItem.Value = PITCH_TYPE_VERTICAL) and
    (not SameValue(PitchHighPullItem.Value, 0) or
      not SameValue(PitchLowSinkItem.Value, 0)) then
    TryGetMusicPitch(MusicFileName, TimeSeconds, NoteNumber, NoteEnvelope);

  ApplyMusicMotion(Video, TRhythmMotionType(RhythmTypeItem.Value),
    BeatPosition, RhythmSpeedItem.Value, RhythmStrengthItem.Value,
    Level, VolumeStrength, NoteNumber, NoteEnvelope,
    PitchBaseNoteItem.Value, PitchHighPullItem.Value,
    PitchLowSinkItem.Value, RhythmParam1Item.Value,
    RhythmParam2Item.Value);
end;

function MotionProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
var
  AlignedTime, BeatPosition, SegmentStartSeconds, TempoBpm: Double;
  LocalTime: Double;
  MusicFileName: string;
begin
  try
    if TryGetMotionTimeSeconds(Video, LocalTime) then
    begin
      MusicFileName := Trim(string(MusicFileItem.Value));
      AlignedTime := CalculateOffsetMotionTime(LocalTime, OffsetItem.Value);
      if MusicFileName = '' then
      begin
        if AlignedTime >= 0 then
        begin
          BeatPosition := CalculateRhythmBeatPosition(
            AlignedTime * TempoItem.Value / 60.0, RhythmShiftItem.Value);
          ApplySelectedRhythmMotion(Video, BeatPosition);
        end;
      end
      else
      begin
        if (AlignedTime >= 0) and
          TryGetMusicSync(MusicFileName, AlignedTime, BeatPosition,
            TempoBpm, SegmentStartSeconds) then
        begin
          BeatPosition := CalculateRhythmBeatPosition(BeatPosition,
            RhythmShiftItem.Value);
          ApplySelectedMusicMotion(Video, MusicFileName, AlignedTime, BeatPosition);
        end;
      end;
    end;
  except
    // Delphi例外をAviUtl2のコールバック境界より外へ漏らさない。
  end;
  Result := 1;
end;

var
  PluginItems: array[0..18] of Pointer;
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

    // 映像と音楽の開始位置を実時間で合わせる保険用の調整値。
    OffsetItem.ItemType := 'track';
    OffsetItem.Name := 'オフセット (秒)';
    OffsetItem.Value := 0.00;
    OffsetItem.S := -86400.00;
    OffsetItem.E := 86400.00;
    OffsetItem.Step := 0.01;

    // テンポへ追従したまま、リズム変形を拍単位で先行・遅延させる。
    RhythmShiftItem.ItemType := 'track';
    RhythmShiftItem.Name := 'リズムずらし (拍)';
    RhythmShiftItem.Value := 0.00;
    RhythmShiftItem.S := -4.00;
    RhythmShiftItem.E := 4.00;
    RhythmShiftItem.Step := 0.01;

    RhythmGroup.ItemType := 'group';
    RhythmGroup.Name := 'リズム';
    RhythmGroup.DefaultVisible := 1;

    RhythmTypeList[0].Name := 'なし';
    RhythmTypeList[0].Value := Ord(rmtNone);
    RhythmTypeList[1].Name := '縦ジャンプ';
    RhythmTypeList[1].Value := Ord(rmtVerticalJump);
    RhythmTypeList[2].Name := '縮小';
    RhythmTypeList[2].Value := Ord(rmtShrink);
    RhythmTypeList[3].Name := 'バウンス';
    RhythmTypeList[3].Value := Ord(rmtBounce);
    RhythmTypeList[4].Name := 'ステップ';
    RhythmTypeList[4].Value := Ord(rmtStep);
    RhythmTypeList[5].Name := '振り子（1拍）';
    RhythmTypeList[5].Value := Ord(rmtPendulum);
    RhythmTypeList[6].Name := '振り子（2拍）';
    RhythmTypeList[6].Value := Ord(rmtPendulumTwoBeat);
    RhythmTypeList[7].Name := nil;
    RhythmTypeList[7].Value := 0;
    RhythmTypeItem.ItemType := 'select';
    RhythmTypeItem.Name := 'リズムタイプ';
    RhythmTypeItem.Value := Ord(rmtVerticalJump);
    RhythmTypeItem.List := @RhythmTypeList[0];

    RhythmStrengthItem.ItemType := 'track';
    RhythmStrengthItem.Name := '強さ';
    RhythmStrengthItem.Value := 50.00;
    RhythmStrengthItem.S := -100.00;
    RhythmStrengthItem.E := 100.00;
    RhythmStrengthItem.Step := 1.00;

    RhythmSpeedItem.ItemType := 'track';
    RhythmSpeedItem.Name := '速さ';
    RhythmSpeedItem.Value := 2.00;
    RhythmSpeedItem.S := 1.00;
    RhythmSpeedItem.E := 100.00;
    RhythmSpeedItem.Step := 0.10;

    RhythmParam1Item.ItemType := 'track';
    RhythmParam1Item.Name := 'Param1';
    RhythmParam1Item.Value := 50.00;
    RhythmParam1Item.S := 0.00;
    RhythmParam1Item.E := 100.00;
    RhythmParam1Item.Step := 1.00;

    RhythmParam2Item.ItemType := 'track';
    RhythmParam2Item.Name := 'Param2';
    RhythmParam2Item.Value := 50.00;
    RhythmParam2Item.S := 0.00;
    RhythmParam2Item.E := 100.00;
    RhythmParam2Item.Step := 1.00;

    VolumeGroup.ItemType := 'group';
    VolumeGroup.Name := '音量';
    VolumeGroup.DefaultVisible := 1;

    VolumeTypeList[0].Name := 'なし';
    VolumeTypeList[0].Value := VOLUME_TYPE_NONE;
    VolumeTypeList[1].Name := '膨張';
    VolumeTypeList[1].Value := VOLUME_TYPE_EXPANSION;
    VolumeTypeList[2].Name := nil;
    VolumeTypeList[2].Value := 0;
    VolumeTypeItem.ItemType := 'select';
    VolumeTypeItem.Name := '音量タイプ';
    VolumeTypeItem.Value := VOLUME_TYPE_NONE;
    VolumeTypeItem.List := @VolumeTypeList[0];

    VolumeStrengthItem.ItemType := 'track';
    VolumeStrengthItem.Name := '音量強さ';
    VolumeStrengthItem.Value := 0.00;
    VolumeStrengthItem.S := -100.00;
    VolumeStrengthItem.E := 100.00;
    VolumeStrengthItem.Step := 1.00;

    PitchGroup.ItemType := 'group';
    PitchGroup.Name := '音程';
    PitchGroup.DefaultVisible := 1;

    PitchTypeList[0].Name := 'なし';
    PitchTypeList[0].Value := PITCH_TYPE_NONE;
    PitchTypeList[1].Name := '上下移動';
    PitchTypeList[1].Value := PITCH_TYPE_VERTICAL;
    PitchTypeList[2].Name := nil;
    PitchTypeList[2].Value := 0;
    PitchTypeItem.ItemType := 'select';
    PitchTypeItem.Name := '音程タイプ';
    PitchTypeItem.Value := PITCH_TYPE_NONE;
    PitchTypeItem.List := @PitchTypeList[0];

    PitchHighPullItem.ItemType := 'track';
    PitchHighPullItem.Name := '高音';
    PitchHighPullItem.Value := 0.00;
    PitchHighPullItem.S := 0.00;
    PitchHighPullItem.E := 1000.00;
    PitchHighPullItem.Step := 1.00;

    PitchLowSinkItem.ItemType := 'track';
    PitchLowSinkItem.Name := '低音';
    PitchLowSinkItem.Value := 0.00;
    PitchLowSinkItem.S := 0.00;
    PitchLowSinkItem.E := 1000.00;
    PitchLowSinkItem.Step := 1.00;

    PitchBaseNoteItem.ItemType := 'track';
    PitchBaseNoteItem.Name := '基準音';
    PitchBaseNoteItem.Value := 60.00;
    PitchBaseNoteItem.S := 0.00;
    PitchBaseNoteItem.E := 127.00;
    PitchBaseNoteItem.Step := 1.00;

    // AviUtl2はnil終端された項目ポインター配列を参照する。
    PluginItems[0] := @MusicFileItem;
    PluginItems[1] := @TempoItem;
    PluginItems[2] := @OffsetItem;
    PluginItems[3] := @RhythmShiftItem;
    PluginItems[4] := @RhythmGroup;
    PluginItems[5] := @RhythmTypeItem;
    PluginItems[6] := @RhythmStrengthItem;
    PluginItems[7] := @RhythmSpeedItem;
    PluginItems[8] := @RhythmParam1Item;
    PluginItems[9] := @RhythmParam2Item;
    PluginItems[10] := @VolumeGroup;
    PluginItems[11] := @VolumeTypeItem;
    PluginItems[12] := @VolumeStrengthItem;
    PluginItems[13] := @PitchGroup;
    PluginItems[14] := @PitchTypeItem;
    PluginItems[15] := @PitchHighPullItem;
    PluginItems[16] := @PitchLowSinkItem;
    PluginItems[17] := @PitchBaseNoteItem;
    PluginItems[18] := nil;
    Plugin.Items := @PluginItems[0];
  end;
  Result := @Plugin;
end;

procedure InitializeMotionFilter;
begin
  InitializeMusicTempoCache;
end;

procedure FinalizeMotionFilter;
begin
  FinalizeMusicTempoCache;
end;

end.
