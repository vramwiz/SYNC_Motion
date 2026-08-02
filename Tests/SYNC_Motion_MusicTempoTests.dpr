program SYNC_Motion_MusicTempoTests;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  System.SysUtils,
  AviUtl2FilterTypes,
  SYNC_Motion_MusicTempo,
  SYNC_Motion_TempoMotion;

const
  TEST_IMAGE_SIZE = 5;
  TEST_PIXEL_COUNT = TEST_IMAGE_SIZE * TEST_IMAGE_SIZE;

var
  TestImageInput, TestImageOutput: array[0..TEST_PIXEL_COUNT - 1] of TPIXEL_RGBA;
  TestImageWasSet: Boolean;

procedure GetTestImageData(Buffer: PPIXEL_RGBA); cdecl;
begin
  Move(TestImageInput[0], Buffer^, SizeOf(TestImageInput));
end;

procedure SetTestImageData(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  if (Width <> TEST_IMAGE_SIZE) or (Height <> TEST_IMAGE_SIZE) then
    Exit;
  Move(Buffer^, TestImageOutput[0], SizeOf(TestImageOutput));
  TestImageWasSet := True;
end;

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

procedure ClearTestImage;
begin
  FillChar(TestImageInput, SizeOf(TestImageInput), 0);
  FillChar(TestImageOutput, SizeOf(TestImageOutput), 0);
  TestImageWasSet := False;
end;

procedure CheckRhythmImageTransforms;
var
  Index, TransparentCount: Integer;
  ObjectInfo: TOBJECT_INFO;
  Video: TFILTER_PROC_VIDEO;
begin
  FillChar(ObjectInfo, SizeOf(ObjectInfo), 0);
  ObjectInfo.Width := TEST_IMAGE_SIZE;
  ObjectInfo.Height := TEST_IMAGE_SIZE;
  FillChar(Video, SizeOf(Video), 0);
  Video.Object_ := @ObjectInfo;
  Video.GetImageData := GetTestImageData;
  Video.SetImageData := SetTestImageData;

  ClearTestImage;
  TestImageInput[2 * TEST_IMAGE_SIZE + 2].R := 255;
  TestImageInput[2 * TEST_IMAGE_SIZE + 2].A := 255;
  ApplyRhythmMotion(@Video, rmtVerticalJump, 0.25, 2.0, 1.0);
  Require(TestImageWasSet and
    (TestImageOutput[1 * TEST_IMAGE_SIZE + 2].R = 255),
    'vertical jump image mismatch');

  ClearTestImage;
  for Index := 0 to High(TestImageInput) do
    TestImageInput[Index].A := 255;
  ApplyRhythmMotion(@Video, rmtShrink, 0.25, 2.0, 100.0);
  TransparentCount := 0;
  for Index := 0 to High(TestImageOutput) do
    if TestImageOutput[Index].A = 0 then
      Inc(TransparentCount);
  Require(TestImageWasSet and (TransparentCount > 0),
    'shrink image mismatch');

  ClearTestImage;
  TestImageInput[0 * TEST_IMAGE_SIZE + 1].R := 255;
  TestImageInput[0 * TEST_IMAGE_SIZE + 1].A := 255;
  TestImageInput[4 * TEST_IMAGE_SIZE + 2].G := 255;
  TestImageInput[4 * TEST_IMAGE_SIZE + 2].A := 255;
  ApplyRhythmMotion(@Video, rmtPendulum, 0.25, 2.0, 2.4);
  Require(TestImageWasSet and
    (TestImageOutput[0 * TEST_IMAGE_SIZE + 3].R = 255),
    'pendulum top deformation mismatch');
  Require(TestImageOutput[4 * TEST_IMAGE_SIZE + 2].G = 255,
    'pendulum bottom anchor mismatch');

  ClearTestImage;
  TestImageInput[2 * TEST_IMAGE_SIZE + 2].R := 255;
  TestImageInput[2 * TEST_IMAGE_SIZE + 2].A := 255;
  ApplyMusicMotion(@Video, rmtNone, 0, 2.0, 0, 0, 0,
    72, 1.0, 60, 1.0, 1.0);
  Require(TestImageWasSet and
    (TestImageOutput[1 * TEST_IMAGE_SIZE + 2].R = 255),
    'high pitch image mismatch');
end;

var
  BadFile, ChangedFile, ConstantFile, TempDir, VelocityFile: string;
  Beat, Bpm, Envelope, Level, NoteNumber, StartFrame, StartSeconds: Double;
  OffsetX, OffsetY: Integer;
  Transform: TRhythmTransform;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'SYNC_Motion_TempoTests');
  ForceDirectories(TempDir);
  ConstantFile := TPath.Combine(TempDir, 'constant.mid');
  ChangedFile := TPath.Combine(TempDir, 'changed.mid');
  VelocityFile := TPath.Combine(TempDir, 'velocity.mid');
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

  // 120 BPM、velocity 64のノートを0.0秒から0.5秒まで発音する。
  SaveBytes(VelocityFile, [
    $4D,$54,$68,$64, $00,$00,$00,$06, $00,$00,$00,$01,$01,$E0,
    $4D,$54,$72,$6B, $00,$00,$00,$14,
    $00,$FF,$51,$03,$07,$A1,$20,
    $00,$90,$3C,$40,
    $83,$60,$80,$3C,$40,
    $00,$FF,$2F,$00]);

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
    CalculateRhythmTransform(rmtNone, 0.0, 2.0, 50.0, Transform);
    Require((Transform.OffsetX = 0) and (Transform.OffsetY = 0),
      'none rhythm offset mismatch');
    RequireNear(1.0, Transform.Scale, 'none rhythm scale');
    RequireNear(0.0, Transform.AngleDegrees, 'none rhythm angle');
    RequireNear(0.0, Transform.TopOffsetX, 'none rhythm deformation');
    CalculateRhythmTransform(rmtVerticalJump, 0.0, 2.0, 50.0,
      Transform);
    Require((Transform.OffsetX = 0) and (Transform.OffsetY = 0),
      'vertical rhythm must start at origin');
    CalculateRhythmTransform(rmtVerticalJump, 0.25, 2.0, 50.0,
      Transform);
    Require((Transform.OffsetX = 0) and (Transform.OffsetY = -50),
      'vertical rhythm peak mismatch');
    CalculateRhythmTransform(rmtVerticalJump, 0.5, 2.0, 50.0,
      Transform);
    Require((Transform.OffsetX = 0) and (Transform.OffsetY = 0),
      'vertical rhythm must return to origin');
    CalculateRhythmTransform(rmtShrink, 0.0, 2.0, 50.0, Transform);
    RequireNear(1.0, Transform.Scale, 'shrink rhythm start');
    CalculateRhythmTransform(rmtShrink, 0.25, 2.0, 50.0, Transform);
    RequireNear(0.875, Transform.Scale, 'shrink rhythm scale');
    CalculateRhythmTransform(rmtShrink, 0.5, 2.0, 50.0, Transform);
    RequireNear(1.0, Transform.Scale, 'shrink rhythm finish');
    CalculateRhythmTransform(rmtPendulum, 0.0, 2.0, 40.0, Transform);
    Require((Transform.OffsetX = 0) and (Transform.OffsetY = 0),
      'pendulum center start mismatch');
    RequireNear(0.0, Transform.TopOffsetX,
      'pendulum deformation start mismatch');
    CalculateRhythmTransform(rmtPendulum, 0.25, 2.0, 40.0, Transform);
    Require((Transform.OffsetX = 0) and (Transform.OffsetY = 0),
      'pendulum must not translate image');
    RequireNear(40.0 / Sqrt(2.0), Transform.TopOffsetX,
      'pendulum right deformation mismatch');
    RequireNear(0.475, Transform.WaistRatio,
      'pendulum default waist mismatch');
    RequireNear(0.5, Transform.JointFlexibility,
      'pendulum default flexibility mismatch');
    CalculateRhythmTransform(rmtPendulum, 0.25, 2.0, 40.0, Transform,
      0.0, 100.0);
    RequireNear(0.35, Transform.WaistRatio,
      'pendulum low waist mismatch');
    RequireNear(1.0, Transform.JointFlexibility,
      'pendulum full flexibility mismatch');
    CalculateRhythmTransform(rmtPendulum, 0.25, 2.0, 40.0, Transform,
      100.0, 0.0);
    RequireNear(0.6, Transform.WaistRatio,
      'pendulum high waist mismatch');
    RequireNear(0.0, Transform.JointFlexibility,
      'pendulum rigid flexibility mismatch');
    CalculateRhythmTransform(rmtPendulum, 0.5, 2.0, 40.0, Transform);
    RequireNear(40.0, Transform.TopOffsetX,
      'pendulum right maximum mismatch');
    CalculateRhythmTransform(rmtPendulum, 1.0, 2.0, 40.0, Transform);
    Require((Transform.OffsetX = 0) and (Transform.OffsetY = 0),
      'pendulum center return mismatch');
    RequireNear(0.0, Transform.TopOffsetX,
      'pendulum deformation return mismatch');
    CalculateRhythmTransform(rmtPendulum, 1.5, 2.0, 40.0, Transform);
    Require((Transform.OffsetX = 0) and (Transform.OffsetY = 0),
      'pendulum left must not translate image');
    RequireNear(-40.0, Transform.TopOffsetX,
      'pendulum left deformation mismatch');
    CalculateRhythmTransform(rmtPendulumFourBeat, 0.0, 2.0, 40.0,
      Transform);
    RequireNear(-40.0, Transform.TopOffsetX,
      'four beat pendulum left start mismatch');
    CalculateRhythmTransform(rmtPendulumFourBeat, 0.5, 2.0, 40.0,
      Transform);
    RequireNear(0.0, Transform.TopOffsetX,
      'four beat pendulum first crossing mismatch');
    CalculateRhythmTransform(rmtPendulumFourBeat, 1.0, 2.0, 40.0,
      Transform);
    RequireNear(40.0, Transform.TopOffsetX,
      'four beat pendulum right arrival mismatch');
    CalculateRhythmTransform(rmtPendulumFourBeat, 1.5, 2.0, 40.0,
      Transform);
    RequireNear(40.0, Transform.TopOffsetX,
      'four beat pendulum right hold mismatch');
    CalculateRhythmTransform(rmtPendulumFourBeat, 2.5, 2.0, 40.0,
      Transform);
    RequireNear(0.0, Transform.TopOffsetX,
      'four beat pendulum return crossing mismatch');
    CalculateRhythmTransform(rmtPendulumFourBeat, 3.0, 2.0, 40.0,
      Transform);
    RequireNear(-40.0, Transform.TopOffsetX,
      'four beat pendulum left arrival mismatch');
    CalculateRhythmTransform(rmtPendulumFourBeat, 3.5, 2.0, 40.0,
      Transform);
    RequireNear(-40.0, Transform.TopOffsetX,
      'four beat pendulum left hold mismatch');
    Require(TryGetMusicVolume(VelocityFile, 0.0, Level),
      'velocity lookup at note start failed');
    RequireNear(0.0, Level, 'velocity attack start');
    Require(TryGetMusicVolume(VelocityFile, 0.025, Level),
      'velocity lookup during attack failed');
    RequireNear(32.0 / 127.0, Level, 'velocity attack midpoint');
    Require(TryGetMusicVolume(VelocityFile, 0.25, Level),
      'velocity lookup during sustain failed');
    RequireNear(64.0 / 127.0, Level, 'velocity sustain');
    Require(TryGetMusicVolume(VelocityFile, 0.475, Level),
      'velocity lookup during release failed');
    RequireNear(32.0 / 127.0, Level, 'velocity release midpoint');
    Require(TryGetMusicVolume(VelocityFile, 0.5, Level),
      'velocity lookup after note failed');
    RequireNear(0.0, Level, 'velocity note end');
    RequireNear(1.5, CalculateVolumeScale(1.0, 100.0),
      'volume expansion scale');
    RequireNear(0.5, CalculateVolumeScale(1.0, -100.0),
      'volume contraction scale');
    Require(TryGetMusicPitch(VelocityFile, 0.025, NoteNumber, Envelope),
      'pitch lookup during attack failed');
    RequireNear(60.0, NoteNumber, 'pitch note number');
    RequireNear(0.5, Envelope, 'pitch attack midpoint');
    Require(TryGetMusicPitch(VelocityFile, 0.25, NoteNumber, Envelope),
      'pitch lookup during sustain failed');
    RequireNear(1.0, Envelope, 'pitch sustain envelope');
    Require(CalculatePitchOffset(72, 1.0, 60, 100, 100) = -100,
      'high pitch offset mismatch');
    Require(CalculatePitchOffset(48, 1.0, 60, 100, 100) = 100,
      'low pitch offset mismatch');
    Require(CalculatePitchOffset(66, 0.5, 60, 100, 100) = -25,
      'pitch normalization mismatch');
    CheckRhythmImageTransforms;
    Require(not TryGetMusicSync(BadFile, 1.0, Beat, Bpm, StartSeconds),
      'broken file must fail silently');
    Writeln('PASS');
  finally
    FinalizeMusicTempoCache;
  end;
end.
