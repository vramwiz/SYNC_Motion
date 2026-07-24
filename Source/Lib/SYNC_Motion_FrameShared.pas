unit SYNC_Motion_FrameShared;

// Input と Filter のDLL間で現在フレームを受け渡す最小共有領域。

interface

type
  TSyncMotionFrameState = record
    Magic: Cardinal;
    Version: Cardinal;
    Frame: Integer;
    Rate: Integer;
    Scale: Integer;
    TimeSeconds: Double;
    UpdateTick: UInt64;
  end;

procedure InitializeMotionFrameShared;
procedure FinalizeMotionFrameShared;
procedure PublishMotionFrame(Frame, Rate, Scale: Integer);
function TryReadMotionFrame(out State: TSyncMotionFrameState): Boolean;

implementation

uses
  Winapi.Windows;

const
  MOTION_FRAME_MAP_NAME = 'Local\SYNC_Motion_Frame_V1';
  MOTION_FRAME_MAGIC = $534D4652; // SMFR
  MOTION_FRAME_VERSION = 1;

var
  MapHandle: THandle;
  MapView: ^TSyncMotionFrameState;

procedure InitializeMotionFrameShared;
begin
  if MapView <> nil then
    Exit;

  MapHandle := CreateFileMapping(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE,
    0, SizeOf(TSyncMotionFrameState), MOTION_FRAME_MAP_NAME);
  if MapHandle = 0 then
    Exit;

  MapView := MapViewOfFile(MapHandle, FILE_MAP_ALL_ACCESS, 0, 0,
    SizeOf(TSyncMotionFrameState));
  if MapView = nil then
  begin
    CloseHandle(MapHandle);
    MapHandle := 0;
  end;
end;

procedure FinalizeMotionFrameShared;
begin
  if MapView <> nil then
  begin
    UnmapViewOfFile(MapView);
    MapView := nil;
  end;
  if MapHandle <> 0 then
  begin
    CloseHandle(MapHandle);
    MapHandle := 0;
  end;
end;

procedure PublishMotionFrame(Frame, Rate, Scale: Integer);
begin
  InitializeMotionFrameShared;
  if MapView = nil then
    Exit;

  MapView^.Magic := MOTION_FRAME_MAGIC;
  MapView^.Version := MOTION_FRAME_VERSION;
  MapView^.Frame := Frame;
  MapView^.Rate := Rate;
  MapView^.Scale := Scale;
  if (Rate > 0) and (Scale > 0) then
    MapView^.TimeSeconds := Frame * Scale / Rate
  else
    MapView^.TimeSeconds := 0;
  MapView^.UpdateTick := GetTickCount64;
end;

function TryReadMotionFrame(out State: TSyncMotionFrameState): Boolean;
begin
  FillChar(State, SizeOf(State), 0);
  InitializeMotionFrameShared;
  Result := (MapView <> nil) and
    (MapView^.Magic = MOTION_FRAME_MAGIC) and
    (MapView^.Version = MOTION_FRAME_VERSION);
  if Result then
    State := MapView^;
end;

initialization
  MapHandle := 0;
  MapView := nil;

finalization
  FinalizeMotionFrameShared;

end.
