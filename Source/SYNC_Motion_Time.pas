unit SYNC_Motion_Time;

// Filter単体の配置先頭を基準に、音楽同期へ使うローカル時刻を取得する。

interface

uses
  AviUtl2FilterTypes;

function TryGetMotionTimeSeconds(Video: PFILTER_PROC_VIDEO;
  out TimeSeconds: Double): Boolean;
function CalculateAdjustedMotionTime(TimeSeconds, SongShiftSeconds,
  RhythmShiftSeconds: Double): Double;

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

function CalculateAdjustedMotionTime(TimeSeconds, SongShiftSeconds,
  RhythmShiftSeconds: Double): Double;
begin
  // 正のずらしは動きを遅延させ、負のずらしは先行させる。
  Result := TimeSeconds - SongShiftSeconds - RhythmShiftSeconds;
end;

end.
