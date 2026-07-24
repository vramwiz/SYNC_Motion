program SYNC_Motion_MusicTempoTests;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  System.SysUtils,
  SYNC_Motion_MusicTempo,
  SYNC_Motion_TempoMotion;

procedure SaveBytes(const FileName: string; const Bytes: array of Byte);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
end;

procedure Require(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure RequireNear(Expected, Actual: Double; const MessageText: string);
begin
  Require(Abs(Expected - Actual) < 0.000001,
    Format('%s: expected %.6f, actual %.6f',
      [MessageText, Expected, Actual]));
end;

procedure CheckSync(const FileName: string; TimeSeconds, ExpectedBeat,
  ExpectedBpm, ExpectedStart: Double);
var
  Beat, Bpm, StartSeconds: Double;
begin
  Require(TryGetMusicSync(FileName, TimeSeconds, Beat, Bpm, StartSeconds),
    'sync lookup failed');
  RequireNear(ExpectedBeat, Beat, 'beat');
  RequireNear(ExpectedBpm, Bpm, 'bpm');
  RequireNear(ExpectedStart, StartSeconds, 'segment start');
end;

var
  BadFile, ChangedFile, ConstantFile, TempDir: string;
  Beat, Bpm, StartFrame, StartSeconds: Double;
  OffsetX, OffsetY: Integer;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'SYNC_Motion_TempoTests');
  ForceDirectories(TempDir);
  ConstantFile := TPath.Combine(TempDir, 'constant.mid');
  ChangedFile := TPath.Combine(TempDir, 'changed.mid');
  BadFile := TPath.Combine(TempDir, 'bad.mid');

  // 120 BPM。960 tick後に終端するが、表は最後のテンポで継続する。
  SaveBytes(ConstantFile, [
    $4D,$54,$68,$64, $00,$00,$00,$06, $00,$00,$00,$01,$01,$E0,
    $4D,$54,$72,$6B, $00,$00,$00,$0C,
    $00,$FF,$51,$03,$07,$A1,$20,
    $87,$40,$FF,$2F,$00]);

  // 0.5秒（480 tick）で120 BPMから60 BPMへ変更。
  SaveBytes(ChangedFile, [
    $4D,$54,$68,$64, $00,$00,$00,$06, $00,$00,$00,$01,$01,$E0,
    $4D,$54,$72,$6B, $00,$00,$00,$14,
    $00,$FF,$51,$03,$07,$A1,$20,
    $83,$60,$FF,$51,$03,$0F,$42,$40,
    $83,$60,$FF,$2F,$00]);

  SaveBytes(BadFile, [$00,$01,$02,$03]);

  InitializeMusicTempoCache;
  try
    CheckSync(ConstantFile, 1.0, 2.0, 120.0, 0.0);
    CheckSync(ConstantFile, 100.0, 200.0, 120.0, 0.0);
    CheckSync(ChangedFile, 0.5, 1.0, 60.0, 0.5);
    CheckSync(ChangedFile, 1.5, 2.0, 60.0, 0.5);
    Require(TryGetMusicSyncAtFrame(ChangedFile, 30, 60, 1, Beat, Bpm,
      StartFrame), 'frame sync lookup failed');
    RequireNear(1.0, Beat, 'frame beat');
    RequireNear(60.0, Bpm, 'frame bpm');
    RequireNear(30.0, StartFrame, 'segment start frame');
    CalculateJumpVector(0.0, 2.0, 50.0, 0.0, OffsetX, OffsetY);
    Require((OffsetX = 0) and (OffsetY = -50),
      'default jump vector mismatch');
    CalculateJumpVector(0.25, 2.0, 50.0, 0.0, OffsetX, OffsetY);
    Require((OffsetX = 0) and (OffsetY = -25),
      'jump speed mismatch');
    CalculateJumpVector(0.5, 2.0, 50.0, 0.0, OffsetX, OffsetY);
    Require((OffsetX = 0) and (OffsetY = 0),
      'jump must finish at speed duration');
    CalculateJumpVector(0.0, 2.0, 50.0, 90.0, OffsetX, OffsetY);
    Require((OffsetX = 50) and (OffsetY = 0),
      'right angle mismatch');
    CalculateJumpVector(0.0, 2.0, 50.0, 180.0, OffsetX, OffsetY);
    Require((OffsetX = 0) and (OffsetY = 50),
      'down angle mismatch');
    Require(not TryGetMusicSync(BadFile, 1.0, Beat, Bpm, StartSeconds),
      'broken file must fail silently');
    Writeln('PASS');
  finally
    FinalizeMusicTempoCache;
  end;
end.
