unit SYNC_Motion_FrameShared;

// Input と Filter のDLL間で現在フレームを受け渡す共有領域。
// 画像サイズはFilterの処理対象から取得するため、この領域では共有しない。

interface

type
  PSyncMotionFrameState = ^TSyncMotionFrameState;
  TSyncMotionFrameState = record
    Magic: Cardinal;
    Version: Cardinal;
    Sequence: Integer;
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
  Winapi.Windows,
  System.SysUtils,
  SharedMemoryBase;

const
  MOTION_FRAME_MAP_NAME = 'Local\SYNC_Motion_Frame_V2';
  MOTION_FRAME_MAGIC = $534D4652; // SMFR
  MOTION_FRAME_VERSION = 2;

var
  SharedMemory: TSharedMemoryBase;

function GetMapView: PSyncMotionFrameState;
begin
  if SharedMemory = nil then
    Exit(nil);
  Result := SharedMemory.View;
end;

procedure InitializeMotionFrameShared;
begin
  if SharedMemory <> nil then
    Exit;

  try
    SharedMemory := TSharedMemoryBase.Create(MOTION_FRAME_MAP_NAME,
      SizeOf(TSyncMotionFrameState));
  except
    FreeAndNil(SharedMemory);
  end;
end;

procedure FinalizeMotionFrameShared;
begin
  FreeAndNil(SharedMemory);
end;

procedure PublishMotionFrame(Frame, Rate, Scale: Integer);
var
  MapView: PSyncMotionFrameState;
  SequenceBefore: Integer;
  WriteSequence: Integer;
  Retry: Integer;
begin
  InitializeMotionFrameShared;
  MapView := GetMapView;
  if MapView = nil then
    Exit;

  // 偶数から奇数へ変更できたInputだけが書き込む。
  WriteSequence := 0;
  for Retry := 0 to 15 do
  begin
    SequenceBefore := InterlockedCompareExchange(MapView^.Sequence, 0, 0);
    if Odd(SequenceBefore) then
      Continue;
    if InterlockedCompareExchange(MapView^.Sequence, SequenceBefore + 1,
      SequenceBefore) = SequenceBefore then
    begin
      WriteSequence := SequenceBefore + 1;
      Break;
    end;
  end;
  if WriteSequence = 0 then
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
  InterlockedExchange(MapView^.Sequence, WriteSequence + 1);
end;

function TryReadMotionFrame(out State: TSyncMotionFrameState): Boolean;
var
  MapView: PSyncMotionFrameState;
  SequenceBefore, SequenceAfter: Integer;
  Retry: Integer;
begin
  FillChar(State, SizeOf(State), 0);
  InitializeMotionFrameShared;
  MapView := GetMapView;
  Result := False;
  if MapView = nil then
    Exit;

  // Inputの更新と重なった場合は短く再試行し、一貫した組だけを返す。
  for Retry := 0 to 2 do
  begin
    SequenceBefore := InterlockedCompareExchange(MapView^.Sequence, 0, 0);
    if Odd(SequenceBefore) then
      Continue;

    State := MapView^;
    SequenceAfter := InterlockedCompareExchange(MapView^.Sequence, 0, 0);
    Result := (SequenceBefore = SequenceAfter) and
      not Odd(SequenceAfter) and
      (State.Magic = MOTION_FRAME_MAGIC) and
      (State.Version = MOTION_FRAME_VERSION);
    if Result then
      Exit;
  end;

  FillChar(State, SizeOf(State), 0);
end;

initialization
  SharedMemory := nil;

finalization
  FinalizeMotionFrameShared;

end.
