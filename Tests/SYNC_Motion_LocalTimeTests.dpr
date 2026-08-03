program SYNC_Motion_LocalTimeTests;

// Filter単体のローカル時刻、秒オフセット、拍ずらしを検証する。

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  AviUtl2FilterTypes,
  SYNC_Motion_Time;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure CheckNear(Expected, Actual: Double; const MessageText: string);
begin
  Check(SameValue(Expected, Actual, 0.000001), MessageText);
end;

var
  ObjectInfo: TOBJECT_INFO;
  TimeSeconds: Double;
  Video: TFILTER_PROC_VIDEO;
begin
  FillChar(ObjectInfo, SizeOf(ObjectInfo), 0);
  FillChar(Video, SizeOf(Video), 0);

  Check(not TryGetMotionTimeSeconds(nil, TimeSeconds),
    'nil video must fail');
  Check(not TryGetMotionTimeSeconds(@Video, TimeSeconds),
    'nil object must fail');

  ObjectInfo.Time := 123.456;
  Video.Object_ := @ObjectInfo;
  Check(TryGetMotionTimeSeconds(@Video, TimeSeconds),
    'local time lookup failed');
  CheckNear(123.456, TimeSeconds, 'local time mismatch');

  CheckNear(113.25, CalculateOffsetMotionTime(123.25, 10.0),
    'positive offset must delay motion');
  CheckNear(133.25, CalculateOffsetMotionTime(123.25, -10.0),
    'negative offset must advance motion');
  CheckNear(12.0, CalculateRhythmBeatPosition(12.5, 0.5),
    'positive rhythm shift must delay motion');
  CheckNear(13.0, CalculateRhythmBeatPosition(12.5, -0.5),
    'negative rhythm shift must advance motion');
  CheckNear(123.25, CalculateOffsetMotionTime(123.25, 0.0),
    'zero offset must preserve time');

  Writeln('PASS');
end.
