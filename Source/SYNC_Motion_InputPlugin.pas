unit SYNC_Motion_InputPlugin;

// 透明映像を返し、読み出されたフレーム位置をフィルター側へ公開する。

interface

uses
  Winapi.Windows,
  AviUtl2InputTypes;

function MotionInputOpen(FileName: LPCWSTR): INPUT_HANDLE;
function MotionInputClose(Ih: INPUT_HANDLE): BOOL;
function MotionInputGetInfo(Ih: INPUT_HANDLE; Info: PInputInfo): BOOL;
function MotionInputReadVideo(Ih: INPUT_HANDLE; Frame: Integer; Buf: Pointer): Integer;
function MotionInputConfig(Hwnd: HWND; Hinst: HINST): BOOL;

implementation

uses
  System.Math,
  System.SysUtils,
  SYNC_Motion_FrameShared;

type
  PMotionInputContext = ^TMotionInputContext;
  TMotionInputContext = record
    Width : Integer;
    Height: Integer;
    MaxSec: Double;
    Rate  : Integer;
    Scale : Integer;
    Info  : BITMAPINFOHEADER;
  end;

procedure ParseBaseFileName(const FileName: string;
  out Width, Height: Integer; out MaxSec: Double;
  out Rate, Scale: Integer);
var
  Base: string;
  Parts: TArray<string>;
  Fps: Double;
begin
  // 形式: Width_Height_MaxSec_Fps_Scale.syncmotion
  Width := 1;
  Height := 1;
  MaxSec := 3600.0;
  Fps := 30.0;
  Scale := 1;

  Base := ChangeFileExt(ExtractFileName(FileName), '');
  Parts := Base.Split(['_']);
  if Length(Parts) >= 2 then
  begin
    Width := StrToIntDef(Parts[0], Width);
    Height := StrToIntDef(Parts[1], Height);
  end;
  if Length(Parts) >= 3 then
    MaxSec := StrToFloatDef(Parts[2], MaxSec);
  if Length(Parts) >= 4 then
    Fps := StrToFloatDef(Parts[3], Fps);
  if Length(Parts) >= 5 then
    Scale := StrToIntDef(Parts[4], Scale);

  Width := Max(1, Width);
  Height := Max(1, Height);
  MaxSec := Max(0.0, MaxSec);
  Scale := Max(1, Scale);
  Rate := Max(1, Round(Fps * Scale));
end;

function MotionInputOpen(FileName: LPCWSTR): INPUT_HANDLE;
var
  Ctx: PMotionInputContext;
begin
  Result := nil;
  New(Ctx);
  FillChar(Ctx^, SizeOf(Ctx^), 0);
  try
    ParseBaseFileName(string(FileName), Ctx^.Width, Ctx^.Height,
      Ctx^.MaxSec, Ctx^.Rate, Ctx^.Scale);

    Ctx^.Info.biSize := SizeOf(BITMAPINFOHEADER);
    Ctx^.Info.biWidth := Ctx^.Width;
    Ctx^.Info.biHeight := Ctx^.Height;
    Ctx^.Info.biPlanes := 1;
    Ctx^.Info.biBitCount := 32;
    Ctx^.Info.biCompression := BI_RGB;
    Ctx^.Info.biSizeImage := Ctx^.Width * Ctx^.Height * 4;
    Result := Ctx;
  except
    Dispose(Ctx);
  end;
end;

function MotionInputClose(Ih: INPUT_HANDLE): BOOL;
begin
  Result := False;
  if Ih = nil then
    Exit;
  Dispose(PMotionInputContext(Ih));
  Result := True;
end;

function MotionInputGetInfo(Ih: INPUT_HANDLE; Info: PInputInfo): BOOL;
var
  Ctx: PMotionInputContext;
begin
  Result := False;
  if (Ih = nil) or (Info = nil) then
    Exit;

  Ctx := PMotionInputContext(Ih);
  FillChar(Info^, SizeOf(TInputInfo), 0);
  Info^.flag := INPUT_INFO_FLAG_VIDEO;
  Info^.rate := Ctx^.Rate;
  Info^.scale := Ctx^.Scale;
  Info^.n := Ceil(Ctx^.MaxSec * Ctx^.Rate / Ctx^.Scale);
  Info^.format := @Ctx^.Info;
  Info^.format_size := SizeOf(BITMAPINFOHEADER);
  Result := True;
end;

function MotionInputReadVideo(Ih: INPUT_HANDLE; Frame: Integer; Buf: Pointer): Integer;
var
  Ctx: PMotionInputContext;
begin
  Result := 0;
  if (Ih = nil) or (Buf = nil) then
    Exit;

  Ctx := PMotionInputContext(Ih);
  FillChar(Buf^, Ctx^.Info.biSizeImage, 0);
  PublishMotionFrame(Frame, Ctx^.Rate, Ctx^.Scale);
  Result := Ctx^.Info.biSizeImage;
end;

function MotionInputConfig(Hwnd: HWND; Hinst: HINST): BOOL;
begin
  MessageBox(Hwnd,
    '音楽同期アニメーション用のフレーム位置入力プラグインです。',
    '音楽同期ベース', MB_OK or MB_ICONINFORMATION);
  Result := True;
end;

end.
