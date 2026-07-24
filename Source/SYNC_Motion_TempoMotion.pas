unit SYNC_Motion_TempoMotion;

// 拍位置とジャンプ設定から2次元の移動量を求め、処理対象画像を移動する。

interface

uses
  AviUtl2FilterTypes;

procedure CalculateJumpVector(BeatPosition, Speed, WidthPixels,
  AngleDegrees: Double; out OffsetX, OffsetY: Integer);
procedure ApplyBeatMotion(Video: PFILTER_PROC_VIDEO; BeatPosition,
  Speed, WidthPixels, AngleDegrees: Double);

implementation

uses
  System.Math,
  System.SysUtils;

type
  TPixelArray = array[0..0] of TPIXEL_RGBA;
  PPixelArray = ^TPixelArray;

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

procedure ApplyBeatMotion(Video: PFILTER_PROC_VIDEO; BeatPosition,
  Speed, WidthPixels, AngleDegrees: Double);
var
  BufferSize: NativeUInt;
  Height, OffsetX, OffsetY, Width: Integer;
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

  CalculateJumpVector(BeatPosition, Speed, WidthPixels, AngleDegrees,
    OffsetX, OffsetY);
  if (OffsetX = 0) and (OffsetY = 0) then
    Exit;

  BufferSize := NativeUInt(Width) * NativeUInt(Height) * SizeOf(TPIXEL_RGBA);
  GetMem(Source, BufferSize);
  GetMem(Dest, BufferSize);
  try
    Video^.GetImageData(PPIXEL_RGBA(Source));
    FillChar(Dest^, BufferSize, 0);
    ShiftImage(Source, Dest, Width, Height, OffsetX, OffsetY);
    Video^.SetImageData(PPIXEL_RGBA(Dest), Width, Height);
  finally
    FreeMem(Dest);
    FreeMem(Source);
  end;
end;

end.
