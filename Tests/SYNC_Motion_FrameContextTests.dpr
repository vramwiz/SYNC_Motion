program SYNC_Motion_FrameContextTests;

// Input開始時間を含む共有フレームと、キャッシュ時のローカル補間を検証する。

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.Math,
  System.SysUtils,
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  SharedMemoryBase in 'Source\Lib\SharedMemoryBase.pas',
  SYNC_Motion_FrameShared in 'Source\Lib\SYNC_Motion_FrameShared.pas',
  SYNC_Motion_ContextManager in 'Source\SYNC_Motion_ContextManager.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure CheckResolved(var Video: TFILTER_PROC_VIDEO;
  const SharedState: TSyncMotionFrameState; ExpectedFrame: Integer;
  const MessageText: string);
var
  EffectiveState: TSyncMotionFrameState;
begin
  Check(ResolveMotionFrameState(@Video, SharedState, EffectiveState),
    MessageText + ': resolve failed');
  Check(EffectiveState.Frame = ExpectedFrame,
    Format('%s: expected frame %d, actual %d',
      [MessageText, ExpectedFrame, EffectiveState.Frame]));
  Check(SameValue(EffectiveState.TimeSeconds,
    ExpectedFrame * EffectiveState.Scale / EffectiveState.Rate),
    MessageText + ': time mismatch');
end;

procedure TestInputStartAndInterpolation;
var
  ObjectInfo: TOBJECT_INFO;
  SharedState: TSyncMotionFrameState;
  Video: TFILTER_PROC_VIDEO;
begin
  FillChar(ObjectInfo, SizeOf(ObjectInfo), 0);
  FillChar(SharedState, SizeOf(SharedState), 0);
  FillChar(Video, SizeOf(Video), 0);
  ObjectInfo.ID := 1;
  ObjectInfo.EffectID := 10;
  ObjectInfo.Frame := 0;
  Video.Object_ := @ObjectInfo;
  SharedState.Sequence := 2;
  SharedState.Frame := 81;
  SharedState.Rate := 30;
  SharedState.Scale := 1;
  SharedState.UpdateTick := GetTickCount64;

  CheckResolved(Video, SharedState, 81, 'input start frame');
  ObjectInfo.Frame := 1;
  CheckResolved(Video, SharedState, 82, 'cached next frame');
end;

procedure TestRejectsStaleInitialAnchor;
var
  EffectiveState: TSyncMotionFrameState;
  ObjectInfo: TOBJECT_INFO;
  SharedState: TSyncMotionFrameState;
  Video: TFILTER_PROC_VIDEO;
begin
  FillChar(ObjectInfo, SizeOf(ObjectInfo), 0);
  FillChar(SharedState, SizeOf(SharedState), 0);
  FillChar(Video, SizeOf(Video), 0);
  ObjectInfo.ID := 2;
  ObjectInfo.EffectID := 20;
  Video.Object_ := @ObjectInfo;
  SharedState.Sequence := 4;
  SharedState.Frame := 150;
  SharedState.Rate := 30;
  SharedState.Scale := 1;
  SharedState.UpdateTick := GetTickCount64 - 1001;

  Check(not ResolveMotionFrameState(@Video, SharedState, EffectiveState),
    'stale shared state was accepted as a new object anchor');
end;

begin
  InitializeMotionContexts;
  try
    TestInputStartAndInterpolation;
    TestRejectsStaleInitialAnchor;
    Writeln('PASS');
  finally
    FinalizeMotionContexts;
  end;
end.
