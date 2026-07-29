unit SYNC_Motion_ContextManager;

// Object ID + Effect ID ごとに共有フレームとFilterローカルフレームの基準を保持する。

interface

uses
  AviUtl2FilterTypes,
  SYNC_Motion_FrameShared;

procedure InitializeMotionContexts;
procedure FinalizeMotionContexts;
function ResolveMotionFrameState(Video: PFILTER_PROC_VIDEO;
  const SharedState: TSyncMotionFrameState;
  out EffectiveState: TSyncMotionFrameState): Boolean;

implementation

uses
  Winapi.Windows,
  System.Generics.Collections,
  System.SyncObjs,
  System.SysUtils;

const
  // 別オブジェクトや過去のプロジェクトが残した共有値を新規基準に採用しない。
  MAX_SHARED_FRAME_AGE_MS = 1000;

type
  TMotionObjectContext = class
  public
    ObjectID: Int64;
    EffectID: Int64;
    HasAnchor: Boolean;
    LastSharedSequence: Integer;
    AnchorSharedFrame: Integer;
    AnchorObjectFrame: Integer;
    Rate: Integer;
    Scale: Integer;
    UpdateTick: UInt64;
  end;

  TMotionContextList = class
  private
    FItems: TObjectList<TMotionObjectContext>;
    FLock: TCriticalSection;
    function FindByKey(ObjectID, EffectID: Int64): TMotionObjectContext;
    function GetOrCreate(ObjectID, EffectID: Int64): TMotionObjectContext;
  public
    constructor Create;
    destructor Destroy; override;
    function Resolve(Video: PFILTER_PROC_VIDEO;
      const SharedState: TSyncMotionFrameState;
      out EffectiveState: TSyncMotionFrameState): Boolean;
  end;

var
  MotionContexts: TMotionContextList;

constructor TMotionContextList.Create;
begin
  inherited Create;
  FItems := TObjectList<TMotionObjectContext>.Create(True);
  FLock := TCriticalSection.Create;
end;

destructor TMotionContextList.Destroy;
begin
  FLock.Free;
  FItems.Free;
  inherited Destroy;
end;

function TMotionContextList.FindByKey(ObjectID,
  EffectID: Int64): TMotionObjectContext;
var
  Context: TMotionObjectContext;
begin
  Result := nil;
  for Context in FItems do
    if (Context.ObjectID = ObjectID) and (Context.EffectID = EffectID) then
      Exit(Context);
end;

function TMotionContextList.GetOrCreate(ObjectID,
  EffectID: Int64): TMotionObjectContext;
begin
  Result := FindByKey(ObjectID, EffectID);
  if Result <> nil then
    Exit;

  Result := TMotionObjectContext.Create;
  Result.ObjectID := ObjectID;
  Result.EffectID := EffectID;
  Result.HasAnchor := False;
  FItems.Add(Result);
end;

function TMotionContextList.Resolve(Video: PFILTER_PROC_VIDEO;
  const SharedState: TSyncMotionFrameState;
  out EffectiveState: TSyncMotionFrameState): Boolean;
var
  Context: TMotionObjectContext;
  ObjectInfo: POBJECT_INFO;
  SharedStateIsFresh: Boolean;
begin
  FillChar(EffectiveState, SizeOf(EffectiveState), 0);
  Result := False;
  if (Video = nil) or (Video^.Object_ = nil) then
    Exit;

  ObjectInfo := Video^.Object_;
  FLock.Acquire;
  try
    Context := GetOrCreate(ObjectInfo^.ID, ObjectInfo^.EffectID);
    SharedStateIsFresh := (SharedState.UpdateTick > 0) and
      (GetTickCount64 - SharedState.UpdateTick <= MAX_SHARED_FRAME_AGE_MS);

    // Inputが発火した時点の共有絶対フレームとローカルフレームを対応付ける。
    // Inputの再取得が省略された再描画では、既存基準からローカル差分を補間する。
    if (not Context.HasAnchor and SharedStateIsFresh) or
      (Context.HasAnchor and SharedStateIsFresh and
       (Context.LastSharedSequence <> SharedState.Sequence)) then
    begin
      Context.HasAnchor := True;
      Context.LastSharedSequence := SharedState.Sequence;
      Context.AnchorSharedFrame := SharedState.Frame;
      Context.AnchorObjectFrame := ObjectInfo^.Frame;
      Context.Rate := SharedState.Rate;
      Context.Scale := SharedState.Scale;
      Context.UpdateTick := SharedState.UpdateTick;
    end;

    if not Context.HasAnchor or (Context.Rate <= 0) or
      (Context.Scale <= 0) then
      Exit;

    EffectiveState := SharedState;
    EffectiveState.Sequence := Context.LastSharedSequence;
    EffectiveState.Frame := Context.AnchorSharedFrame +
      (ObjectInfo^.Frame - Context.AnchorObjectFrame);
    EffectiveState.Rate := Context.Rate;
    EffectiveState.Scale := Context.Scale;
    EffectiveState.TimeSeconds := EffectiveState.Frame *
      Context.Scale / Context.Rate;
    EffectiveState.UpdateTick := Context.UpdateTick;
    Result := True;
  finally
    FLock.Release;
  end;
end;

procedure InitializeMotionContexts;
begin
  if MotionContexts <> nil then
    Exit;
  try
    MotionContexts := TMotionContextList.Create;
  except
    FreeAndNil(MotionContexts);
  end;
end;

procedure FinalizeMotionContexts;
begin
  FreeAndNil(MotionContexts);
end;

function ResolveMotionFrameState(Video: PFILTER_PROC_VIDEO;
  const SharedState: TSyncMotionFrameState;
  out EffectiveState: TSyncMotionFrameState): Boolean;
begin
  InitializeMotionContexts;
  Result := (MotionContexts <> nil) and
    MotionContexts.Resolve(Video, SharedState, EffectiveState);
end;

initialization
  MotionContexts := nil;

finalization
  FinalizeMotionContexts;

end.
