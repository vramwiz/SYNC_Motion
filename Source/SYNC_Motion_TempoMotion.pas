unit SYNC_Motion_TempoMotion;

// 共有時刻と手動BPMから拍を求め、処理対象画像を上下へ移動する初期PoC。

interface

uses
  AviUtl2FilterTypes,
  SYNC_Motion_FrameShared;

procedure ApplyTempoMotion(Video: PFILTER_PROC_VIDEO;
  const State: TSyncMotionFrameState; TempoBpm: Double);

implementation

uses
  System.Math,
  System.SysUtils;

type
  TPixelArray = array[0..0] of TPIXEL_RGBA;
  PPixelArray = ^TPixelArray;

function CalculateVerticalOffset(TimeSeconds, TempoBpm: Double;
  Height: Integer): Integer;
var
  Amplitude: Integer;
  BeatPhase, BeatPosition: Double;
begin
  Result := 0;
  if (TempoBpm <= 0) or (Height <= 0) then
    Exit;

  Amplitude := Height div 8;
  if Amplitude < 8 then
    Amplitude := 8;
  if Amplitude > 80 then
    Amplitude := 80;
  if Amplitude > Height then
    Amplitude := Height;

  BeatPosition := TimeSeconds * TempoBpm / 60.0;
  BeatPhase := BeatPosition - Floor(BeatPosition);

  // 拍の瞬間に上へ跳ね、拍の前半で元位置へ戻す。
  if BeatPhase < 0.5 then
    Result := -Round(Amplitude * (1.0 - BeatPhase * 2.0));
end;

procedure ShiftImageVertical(Source, Dest: PPixelArray;
  Width, Height, OffsetY: Integer);
var
  DestY, SourceY: Integer;
  RowBytes: NativeUInt;
begin
  RowBytes := NativeUInt(Width) * SizeOf(TPIXEL_RGBA);
  for DestY := 0 to Height - 1 do
  begin
    SourceY := DestY - OffsetY;
    if (SourceY >= 0) and (SourceY < Height) then
      Move(Source^[SourceY * Width], Dest^[DestY * Width], RowBytes);
  end;
end;

procedure ApplyTempoMotion(Video: PFILTER_PROC_VIDEO;
  const State: TSyncMotionFrameState; TempoBpm: Double);
var
  BufferSize: NativeUInt;
  Height, OffsetY, Width: Integer;
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

  OffsetY := CalculateVerticalOffset(State.TimeSeconds, TempoBpm, Height);
  if OffsetY = 0 then
    Exit;

  BufferSize := NativeUInt(Width) * NativeUInt(Height) * SizeOf(TPIXEL_RGBA);
  GetMem(Source, BufferSize);
  GetMem(Dest, BufferSize);
  try
    Video^.GetImageData(PPIXEL_RGBA(Source));
    FillChar(Dest^, BufferSize, 0);
    ShiftImageVertical(Source, Dest, Width, Height, OffsetY);
    Video^.SetImageData(PPIXEL_RGBA(Dest), Width, Height);
  finally
    FreeMem(Dest);
    FreeMem(Source);
  end;
end;

end.
