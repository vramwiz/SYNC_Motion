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
  SYNC_Motion_FrameShared,
  SYNC_Motion_ContextManager,
  SYNC_Motion_MusicTempo,
  SYNC_Motion_TempoMotion;

const
  PRESET_NONE  = 0;
  PRESET_BASIC = 1;
  VOLUME_TYPE_NONE      = 0;
  VOLUME_TYPE_EXPANSION = 1;
  PITCH_TYPE_NONE       = 0;
  PITCH_TYPE_VERTICAL   = 1;

var
  MusicFileItem       : TFILTER_ITEM_FILE;
  TempoItem           : TFILTER_ITEM_TRACK;
  MotionShiftItem     : TFILTER_ITEM_TRACK;
  PresetItem          : TFILTER_ITEM_SELECT;
  PresetList          : array[0..2] of TFILTER_ITEM_SELECT_ITEM;
  PresetApplyButton   : TFILTER_ITEM_BUTTON;
  RhythmGroup         : TFILTER_ITEM_GROUP;
  RhythmTypeItem      : TFILTER_ITEM_SELECT;
  RhythmTypeList      : array[0..4] of TFILTER_ITEM_SELECT_ITEM;
  RhythmStrengthItem  : TFILTER_ITEM_TRACK;
  RhythmSpeedItem     : TFILTER_ITEM_TRACK;
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

procedure ApplyPresetToLocalItems(Preset: Integer);
begin
  RhythmSpeedItem.Value := 2.00;
  PitchBaseNoteItem.Value := 60.00;
  case Preset of
    PRESET_BASIC:
      begin
        RhythmTypeItem.Value := Ord(rmtVerticalJump);
        RhythmStrengthItem.Value := 50.00;
        VolumeTypeItem.Value := VOLUME_TYPE_NONE;
        VolumeStrengthItem.Value := 0.00;
        PitchTypeItem.Value := PITCH_TYPE_NONE;
        PitchHighPullItem.Value := 0.00;
        PitchLowSinkItem.Value := 0.00;
      end;
  else
    RhythmTypeItem.Value := Ord(rmtNone);
    RhythmStrengthItem.Value := 0.00;
    VolumeTypeItem.Value := VOLUME_TYPE_NONE;
    VolumeStrengthItem.Value := 0.00;
    PitchTypeItem.Value := PITCH_TYPE_NONE;
    PitchHighPullItem.Value := 0.00;
    PitchLowSinkItem.Value := 0.00;
  end;
end;

function SetPresetObjectItem(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE;
  Item: PWideChar; const Value: UTF8String): Boolean;
begin
  Result := False;
  if (Edit = nil) or (Obj = nil) or not Assigned(Edit^.SetObjectItemValue) then
    Exit;

  Result := Edit^.SetObjectItemValue(Obj,
    'SYNC_音楽同期アニメーション_Filter', Item, PAnsiChar(Value)) <> 0;
end;

procedure ApplyPresetToObject(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE;
  Preset: Integer);
begin
  if Preset = PRESET_BASIC then
  begin
    SetPresetObjectItem(Edit, Obj, 'リズムタイプ', UTF8String('1'));
    SetPresetObjectItem(Edit, Obj, '強さ', UTF8String('50'));
  end
  else
  begin
    SetPresetObjectItem(Edit, Obj, 'リズムタイプ', UTF8String('0'));
    SetPresetObjectItem(Edit, Obj, '強さ', UTF8String('0'));
  end;
  SetPresetObjectItem(Edit, Obj, '速さ', UTF8String('2'));
  SetPresetObjectItem(Edit, Obj, '音量タイプ', UTF8String('0'));
  SetPresetObjectItem(Edit, Obj, '音量強さ', UTF8String('0'));
  SetPresetObjectItem(Edit, Obj, '音程タイプ', UTF8String('0'));
  SetPresetObjectItem(Edit, Obj, '高音', UTF8String('0'));
  SetPresetObjectItem(Edit, Obj, '低音', UTF8String('0'));
  SetPresetObjectItem(Edit, Obj, '基準音', UTF8String('60'));
end;

procedure ApplyPresetButton(Edit: PEDIT_SECTION); cdecl;
var
  Obj: OBJECT_HANDLE;
  Preset: Integer;
begin
  Preset := PresetItem.Value;
  ApplyPresetToLocalItems(Preset);
  if (Edit = nil) or not Assigned(Edit^.GetFocusObject) then
    Exit;

  Obj := Edit^.GetFocusObject;
  if Obj <> nil then
    ApplyPresetToObject(Edit, Obj, Preset);
end;

procedure ApplySelectedRhythmMotion(Video: PFILTER_PROC_VIDEO;
  BeatPosition: Double);
begin
  if (RhythmTypeItem.Value < Ord(Low(TRhythmMotionType))) or
    (RhythmTypeItem.Value > Ord(High(TRhythmMotionType))) then
    Exit;

  ApplyRhythmMotion(Video, TRhythmMotionType(RhythmTypeItem.Value),
    BeatPosition, RhythmSpeedItem.Value, RhythmStrengthItem.Value);
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
    PitchLowSinkItem.Value);
end;

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
      MusicFileName := Trim(string(MusicFileItem.Value));
      if MusicFileName = '' then
      begin
        AdjustedTime := EffectiveState.TimeSeconds - MotionShiftItem.Value;
        if AdjustedTime >= 0 then
          ApplySelectedRhythmMotion(Video,
            AdjustedTime * TempoItem.Value / 60.0);
      end
      else
      begin
        // 音楽ファイル指定時もInput開始時間を含む共有時刻を使う。
        // 正のオフセットは動きを遅延させ、負の値は先行させる。
        AdjustedTime := EffectiveState.TimeSeconds - MotionShiftItem.Value;
        if (AdjustedTime >= 0) and
          TryGetMusicSync(MusicFileName, AdjustedTime, BeatPosition,
            TempoBpm, SegmentStartSeconds) then
        begin
          ApplySelectedMusicMotion(Video, MusicFileName, AdjustedTime,
            BeatPosition);
        end;
      end;
    end;
  except
    // Delphi例外をAviUtl2のコールバック境界より外へ漏らさない。
  end;
  Result := 1;
end;

var
  PluginItems: array[0..17] of Pointer;
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

    MotionShiftItem.ItemType := 'track';
    MotionShiftItem.Name := 'ずらし';
    MotionShiftItem.Value := 0.00;
    MotionShiftItem.S := -60.00;
    MotionShiftItem.E := 60.00;
    MotionShiftItem.Step := 0.01;

    PresetList[0].Name := 'なし';
    PresetList[0].Value := PRESET_NONE;
    PresetList[1].Name := '基本';
    PresetList[1].Value := PRESET_BASIC;
    PresetList[2].Name := nil;
    PresetList[2].Value := 0;
    PresetItem.ItemType := 'select';
    PresetItem.Name := 'プリセット';
    PresetItem.Value := PRESET_BASIC;
    PresetItem.List := @PresetList[0];
    PresetApplyButton.ItemType := 'button';
    PresetApplyButton.Name := '反映';
    PresetApplyButton.Callback := ApplyPresetButton;

    RhythmGroup.ItemType := 'group';
    RhythmGroup.Name := 'リズム';
    RhythmGroup.DefaultVisible := 1;

    RhythmTypeList[0].Name := 'なし';
    RhythmTypeList[0].Value := Ord(rmtNone);
    RhythmTypeList[1].Name := '縦ジャンプ';
    RhythmTypeList[1].Value := Ord(rmtVerticalJump);
    RhythmTypeList[2].Name := '縮小';
    RhythmTypeList[2].Value := Ord(rmtShrink);
    RhythmTypeList[3].Name := '振り子';
    RhythmTypeList[3].Value := Ord(rmtPendulum);
    RhythmTypeList[4].Name := nil;
    RhythmTypeList[4].Value := 0;
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
    PluginItems[2] := @MotionShiftItem;
    PluginItems[3] := @PresetItem;
    PluginItems[4] := @PresetApplyButton;
    PluginItems[5] := @RhythmGroup;
    PluginItems[6] := @RhythmTypeItem;
    PluginItems[7] := @RhythmStrengthItem;
    PluginItems[8] := @RhythmSpeedItem;
    PluginItems[9] := @VolumeGroup;
    PluginItems[10] := @VolumeTypeItem;
    PluginItems[11] := @VolumeStrengthItem;
    PluginItems[12] := @PitchGroup;
    PluginItems[13] := @PitchTypeItem;
    PluginItems[14] := @PitchHighPullItem;
    PluginItems[15] := @PitchLowSinkItem;
    PluginItems[16] := @PitchBaseNoteItem;
    PluginItems[17] := nil;
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
