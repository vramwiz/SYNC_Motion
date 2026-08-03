unit SYNC_Motion_Time;

// Filter単体の配置先頭を基準に、音楽同期へ使うローカル時刻を取得する。

interface

uses
  AviUtl2FilterTypes;

function TryGetMotionTimeSeconds(Video: PFILTER_PROC_VIDEO;
  out TimeSeconds: Double): Boolean;
function CalculateOffsetMotionTime(TimeSeconds, OffsetSeconds: Double): Double;
function CalculateRhythmBeatPosition(BeatPosition,
  RhythmShiftBeats: Double): Double;

implementation

uses
  System.Math;

function TryGetMotionTimeSeconds(Video: PFILTER_PROC_VIDEO;
  out TimeSeconds: Double): Boolean;
begin
  Result := False;
  TimeSeconds := 0.0;
  if (Video = nil) or (Video^.Object_ = nil) then
    Exit;

  TimeSeconds := Video^.Object_^.Time;
  Result := not IsNan(TimeSeconds) and not IsInfinite(TimeSeconds);
end;

function CalculateOffsetMotionTime(TimeSeconds, OffsetSeconds: Double): Double;
begin
  // 正のオフセットは動きを遅延させ、負のオフセットは先行させる。
  Result := TimeSeconds - OffsetSeconds;
end;

function CalculateRhythmBeatPosition(BeatPosition,
  RhythmShiftBeats: Double): Double;
begin
  // 秒位置から拍を求めた後に適用し、テンポ変更後も同じ拍数だけずらす。
  Result := BeatPosition - RhythmShiftBeats;
end;

end.
