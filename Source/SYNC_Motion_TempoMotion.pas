unit SYNC_Motion_TempoMotion;

// 拍位置と共通設定からリズム変形を求め、処理対象画像へ適用する。

interface

uses
  AviUtl2FilterTypes;

type
  TRhythmMotionType = (
    rmtNone,
    rmtVerticalJump,
    rmtHorizontalJump,
    rmtShrink,
    rmtPendulum
  );

  TRhythmTransform = record
    OffsetX, OffsetY: Integer; // 元画像の中心位置からの移動量。
    Scale           : Double;  // 1.0を原寸とする中心基準の拡大率。
    AngleDegrees    : Double;  // 正方向を時計回りとする回転角度。
  end;

procedure CalculateJumpVector(BeatPosition, Speed, WidthPixels,
  AngleDegrees: Double; out OffsetX, OffsetY: Integer);
procedure ApplyBeatMotion(Video: PFILTER_PROC_VIDEO; BeatPosition,
  Speed, WidthPixels, AngleDegrees: Double);
procedure CalculateRhythmTransform(MotionType: TRhythmMotionType;
  BeatPosition, Speed, Strength: Double; out Transform: TRhythmTransform);
procedure ApplyRhythmMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, Strength: Double);
procedure ApplyRhythmVolumeMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, RhythmStrength,
  VolumeLevel, VolumeStrength: Double);
procedure ApplyMusicMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, RhythmStrength,
  VolumeLevel, VolumeStrength, NoteNumber, PitchEnvelope, BaseNote,
  HighPull, LowSink: Double);
function CalculateVolumeScale(Level, Strength: Double): Double;
function CalculatePitchOffset(NoteNumber, Envelope, BaseNote,
  HighPull, LowSink: Double): Integer;
procedure ApplyVolumeMotion(Video: PFILTER_PROC_VIDEO;
  Level, Strength: Double);

implementation

uses
  System.Math,
  System.SysUtils;

type
  TPixelArray = array[0..0] of TPIXEL_RGBA;
  PPixelArray = ^TPixelArray;

function TryCalculateActionProgress(BeatPosition, Speed: Double;
  out Progress: Double): Boolean;
var
  BeatPhase, DurationBeats: Double;
begin
  Result := False;
  Progress := 0;
  if Speed <= 0 then
    Exit;

  DurationBeats := 1.0 / Speed;
  BeatPhase := BeatPosition - Floor(BeatPosition);
  if BeatPhase >= DurationBeats then
    Exit;

  Progress := BeatPhase / DurationBeats;
  Result := True;
end;

procedure CalculateJumpVector(BeatPosition, Speed, WidthPixels,
  AngleDegrees: Double; out OffsetX, OffsetY: Integer);
var
  BeatPhase, Distance, DurationBeats, Radians: Double;
begin
  OffsetX := 0;
  OffsetY := 0;
  if (Speed <= 0) or (WidthPixels <= 0) then
    Exit;

  DurationBeats := 1.0 / Speed;
  BeatPhase := BeatPosition - Floor(BeatPosition);
  if BeatPhase >= DurationBeats then
    Exit;

  Distance := WidthPixels * (1.0 - BeatPhase / DurationBeats);
  Radians := DegToRad(AngleDegrees);
  // 角度0を上方向とし、正方向へ回すと右、下、左の順になる。
  OffsetX := Round(Distance * Sin(Radians));
  OffsetY := -Round(Distance * Cos(Radians));
end;

procedure CalculateRhythmTransform(MotionType: TRhythmMotionType;
  BeatPosition, Speed, Strength: Double; out Transform: TRhythmTransform);
var
  Curve, Progress, Swing: Double;
begin
  Transform.OffsetX := 0;
  Transform.OffsetY := 0;
  Transform.Scale := 1.0;
  Transform.AngleDegrees := 0;
  if (MotionType = rmtNone) or SameValue(Strength, 0) then
    Exit;

  if MotionType = rmtPendulum then
  begin
    // 確認用に最初の実装の4倍速とし、既定の速さ2では1/4拍ごとに左右の最大点を通る。
    Swing := Sin(BeatPosition * Speed * Pi);
    Transform.OffsetX := Round(Strength * Swing);
    Transform.OffsetY := Round(Abs(Strength) * 0.25 * Sqr(Swing));
    Exit;
  end;

  if not TryCalculateActionProgress(BeatPosition, Speed, Progress) then
    Exit;
  // 原位置から滑らかに最大点へ達し、同じ時間で原位置へ戻る放物線。
  Curve := 4.0 * Progress * (1.0 - Progress);
  case MotionType of
    rmtVerticalJump:
      Transform.OffsetY := -Round(Strength * Curve);
    rmtShrink:
      Transform.Scale := 1.0 - Strength * Curve / 400.0;
  end;
end;

function IsIdentityTransform(const Transform: TRhythmTransform): Boolean;
begin
  Result := (Transform.OffsetX = 0) and (Transform.OffsetY = 0) and
    SameValue(Transform.Scale, 1.0) and
    SameValue(Transform.AngleDegrees, 0);
end;

procedure ShiftImage(Source, Dest: PPixelArray;
  Width, Height, OffsetX, OffsetY: Integer);
var
  CopyWidth, DestX, DestY, SourceX, SourceY: Integer;
  CopyBytes: NativeUInt;
begin
  if OffsetX >= 0 then
  begin
    SourceX := 0;
    DestX := OffsetX;
    CopyWidth := Width - OffsetX;
  end
  else
  begin
    SourceX := -OffsetX;
    DestX := 0;
    CopyWidth := Width + OffsetX;
  end;
  if CopyWidth <= 0 then
    Exit;

  CopyBytes := NativeUInt(CopyWidth) * SizeOf(TPIXEL_RGBA);
  for DestY := 0 to Height - 1 do
  begin
    SourceY := DestY - OffsetY;
    if (SourceY >= 0) and (SourceY < Height) then
      Move(Source^[SourceY * Width + SourceX],
        Dest^[DestY * Width + DestX], CopyBytes);
  end;
end;

procedure TransformImage(Source, Dest: PPixelArray; Width, Height: Integer;
  const Transform: TRhythmTransform);
var
  CenterX, CenterY, CosAngle, DestCenterX, DestCenterY: Double;
  InverseScale, Radians, SinAngle, SourceCenterX, SourceCenterY: Double;
  DestX, DestY, SourceX, SourceY: Integer;
begin
  CenterX := (Width - 1) / 2.0;
  CenterY := (Height - 1) / 2.0;
  Radians := DegToRad(Transform.AngleDegrees);
  CosAngle := Cos(Radians);
  SinAngle := Sin(Radians);
  InverseScale := 1.0 / Transform.Scale;

  for DestY := 0 to Height - 1 do
  begin
    for DestX := 0 to Width - 1 do
    begin
      DestCenterX := DestX - CenterX - Transform.OffsetX;
      DestCenterY := DestY - CenterY - Transform.OffsetY;
      SourceCenterX := (CosAngle * DestCenterX +
        SinAngle * DestCenterY) * InverseScale;
      SourceCenterY := (-SinAngle * DestCenterX +
        CosAngle * DestCenterY) * InverseScale;
      SourceX := Round(CenterX + SourceCenterX);
      SourceY := Round(CenterY + SourceCenterY);
      if (SourceX >= 0) and (SourceX < Width) and
        (SourceY >= 0) and (SourceY < Height) then
        Dest^[DestY * Width + DestX] := Source^[SourceY * Width + SourceX];
    end;
  end;
end;

procedure ApplyTransform(Video: PFILTER_PROC_VIDEO;
  const Transform: TRhythmTransform);
var
  BufferSize: NativeUInt;
  Height, Width: Integer;
  Dest, Source: PPixelArray;
begin
  if (Video = nil) or (Video^.Object_ = nil) or
    not Assigned(Video^.GetImageData) or
    not Assigned(Video^.SetImageData) then
    Exit;

  Width := Video^.Object_^.Width;
  Height := Video^.Object_^.Height;
  if (Width <= 0) or (Height <= 0) then
    Exit;
  if NativeUInt(Width) > High(NativeUInt) div NativeUInt(Height) div
    SizeOf(TPIXEL_RGBA) then
    Exit;
  if (Transform.Scale <= 0) or IsIdentityTransform(Transform) then
    Exit;

  BufferSize := NativeUInt(Width) * NativeUInt(Height) * SizeOf(TPIXEL_RGBA);
  GetMem(Source, BufferSize);
  GetMem(Dest, BufferSize);
  try
    Video^.GetImageData(PPIXEL_RGBA(Source));
    FillChar(Dest^, BufferSize, 0);
    if SameValue(Transform.Scale, 1.0) and
      SameValue(Transform.AngleDegrees, 0) then
      ShiftImage(Source, Dest, Width, Height, Transform.OffsetX,
        Transform.OffsetY)
    else
      TransformImage(Source, Dest, Width, Height, Transform);
    Video^.SetImageData(PPIXEL_RGBA(Dest), Width, Height);
  finally
    FreeMem(Dest);
    FreeMem(Source);
  end;
end;

procedure ApplyBeatMotion(Video: PFILTER_PROC_VIDEO; BeatPosition,
  Speed, WidthPixels, AngleDegrees: Double);
var
  Transform: TRhythmTransform;
begin
  Transform.Scale := 1.0;
  Transform.AngleDegrees := 0;
  CalculateJumpVector(BeatPosition, Speed, WidthPixels, AngleDegrees,
    Transform.OffsetX, Transform.OffsetY);
  ApplyTransform(Video, Transform);
end;

procedure ApplyRhythmMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, Strength: Double);
begin
  ApplyRhythmVolumeMotion(Video, MotionType, BeatPosition, Speed, Strength,
    0, 0);
end;

procedure ApplyRhythmVolumeMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, RhythmStrength,
  VolumeLevel, VolumeStrength: Double);
begin
  ApplyMusicMotion(Video, MotionType, BeatPosition, Speed, RhythmStrength,
    VolumeLevel, VolumeStrength, 0, 0, 60, 0, 0);
end;

procedure ApplyMusicMotion(Video: PFILTER_PROC_VIDEO;
  MotionType: TRhythmMotionType; BeatPosition, Speed, RhythmStrength,
  VolumeLevel, VolumeStrength, NoteNumber, PitchEnvelope, BaseNote,
  HighPull, LowSink: Double);
var
  Transform: TRhythmTransform;
begin
  CalculateRhythmTransform(MotionType, BeatPosition, Speed, RhythmStrength,
    Transform);
  Transform.Scale := Transform.Scale *
    CalculateVolumeScale(VolumeLevel, VolumeStrength);
  Inc(Transform.OffsetY, CalculatePitchOffset(NoteNumber, PitchEnvelope,
    BaseNote, HighPull, LowSink));
  ApplyTransform(Video, Transform);
end;

function CalculateVolumeScale(Level, Strength: Double): Double;
begin
  Result := 1.0 + EnsureRange(Level, 0.0, 1.0) * Strength / 200.0;
  Result := EnsureRange(Result, 0.01, 2.0);
end;

function CalculatePitchOffset(NoteNumber, Envelope, BaseNote,
  HighPull, LowSink: Double): Integer;
var
  Distance: Double;
begin
  Distance := EnsureRange((NoteNumber - BaseNote) / 12.0, -1.0, 1.0);
  Envelope := EnsureRange(Envelope, 0.0, 1.0);
  if Distance > 0 then
    Result := -Round(HighPull * Distance * Envelope)
  else if Distance < 0 then
    Result := Round(LowSink * -Distance * Envelope)
  else
    Result := 0;
end;

procedure ApplyVolumeMotion(Video: PFILTER_PROC_VIDEO;
  Level, Strength: Double);
var
  Transform: TRhythmTransform;
begin
  Transform.OffsetX := 0;
  Transform.OffsetY := 0;
  Transform.Scale := CalculateVolumeScale(Level, Strength);
  Transform.AngleDegrees := 0;
  ApplyTransform(Video, Transform);
end;

end.
