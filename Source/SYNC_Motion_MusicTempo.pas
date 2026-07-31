unit SYNC_Motion_MusicTempo;

// 楽譜ファイルを解析し、時刻からテンポと累積拍を引ける表をキャッシュする。

interface

function TryGetMusicSync(const FileName: string; TimeSeconds: Double;
  out BeatPosition, TempoBpm, SegmentStartSeconds: Double): Boolean;
function TryGetMusicSyncAtFrame(const FileName: string; Frame: Int64;
  Rate, Scale: Integer; out BeatPosition, TempoBpm,
  SegmentStartFrame: Double): Boolean;
function TryGetMusicVolume(const FileName: string; TimeSeconds: Double;
  out Level: Double): Boolean;
function TryGetMusicPitch(const FileName: string; TimeSeconds: Double;
  out NoteNumber, Envelope: Double): Boolean;
procedure InitializeMusicTempoCache;
procedure FinalizeMusicTempoCache;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Math,
  System.SyncObjs,
  System.SysUtils,
  SongData,
  SongDataNote;

type
  TRawTempo = record
    Tick: Integer;
    MicrosecondsPerBeat: Double;
    Order: Integer;
  end;

  TTempoSegment = record
    StartSeconds: Double;
    StartBeat: Double;
    TempoBpm: Double;
  end;

  TMusicNoteSegment = record
    StartSeconds: Double;
    EndSeconds  : Double;
    Key         : Integer;
    Velocity    : Integer;
  end;

  TMusicTempoTable = class
  private
    FSegments: TArray<TTempoSegment>;
    FNotes: TArray<TMusicNoteSegment>;
    FMaxNoteDuration: Double;
    procedure BuildNotesFromSong(Song: TSongData);
  public
    function BuildFromSong(Song: TSongData): Boolean;
    function Lookup(TimeSeconds: Double; out BeatPosition, TempoBpm,
      SegmentStartSeconds: Double): Boolean;
    function LookupVolume(TimeSeconds: Double; out Level: Double): Boolean;
    function LookupPitch(TimeSeconds: Double; out NoteNumber,
      Envelope: Double): Boolean;
  end;

  TMusicTempoCacheEntry = class
  public
    FileAge: Integer;
    FileSize: Int64;
    IsValid: Boolean;
    Table: TMusicTempoTable;
    destructor Destroy; override;
  end;

var
  MusicTempoCache: TObjectDictionary<string, TMusicTempoCacheEntry>;
  MusicTempoLock: TCriticalSection;

procedure SortRawTempos(var Values: TArray<TRawTempo>);
var
  I, J: Integer;
  Value: TRawTempo;
begin
  // 同一Tickは元の登録順を維持し、最後に登録された値で上書きできるようにする。
  for I := 1 to High(Values) do
  begin
    Value := Values[I];
    J := I - 1;
    while (J >= 0) and
      ((Values[J].Tick > Value.Tick) or
       ((Values[J].Tick = Value.Tick) and (Values[J].Order > Value.Order))) do
    begin
      Values[J + 1] := Values[J];
      Dec(J);
    end;
    Values[J + 1] := Value;
  end;
end;

procedure SortNoteSegments(var Values: TArray<TMusicNoteSegment>);
var
  I, J: Integer;
  Value: TMusicNoteSegment;
begin
  for I := 1 to High(Values) do
  begin
    Value := Values[I];
    J := I - 1;
    while (J >= 0) and (Values[J].StartSeconds > Value.StartSeconds) do
    begin
      Values[J + 1] := Values[J];
      Dec(J);
    end;
    Values[J + 1] := Value;
  end;
end;

procedure TMusicTempoTable.BuildNotesFromSong(Song: TSongData);
var
  Duration: Double;
  I, NoteCount: Integer;
  Note: TSongNoteItem;
begin
  FNotes := nil;
  FMaxNoteDuration := 0;
  if Song = nil then
    Exit;

  SetLength(FNotes, Song.Notes.Count);
  NoteCount := 0;
  for I := 0 to Song.Notes.Count - 1 do
  begin
    Note := Song.Notes[I];
    if (Note = nil) or (Note.StartSec < 0) or
      (Note.EndSec <= Note.StartSec) or (Note.Velocity <= 0) then
      Continue;
    FNotes[NoteCount].StartSeconds := Note.StartSec;
    FNotes[NoteCount].EndSeconds := Note.EndSec;
    FNotes[NoteCount].Key := EnsureRange(Note.Key, 0, 127);
    FNotes[NoteCount].Velocity := EnsureRange(Note.Velocity, 1, 127);
    Duration := Note.EndSec - Note.StartSec;
    if Duration > FMaxNoteDuration then
      FMaxNoteDuration := Duration;
    Inc(NoteCount);
  end;
  SetLength(FNotes, NoteCount);
  SortNoteSegments(FNotes);
end;

function TMusicTempoTable.BuildFromSong(Song: TSongData): Boolean;
var
  CurrentBeat, CurrentSeconds, DeltaBeats: Double;
  Division, I, RawCount, SegmentCount: Integer;
  Raw: TArray<TRawTempo>;
  Segment: TTempoSegment;
begin
  Result := False;
  FSegments := nil;
  if Song = nil then
    Exit;

  Division := Song.Info.Division;
  if Division <= 0 then
    Exit;

  // MIDI等では最初のテンポ指定まで120 BPMが標準値となる。
  SetLength(Raw, Song.Tempos.Count + 1);
  Raw[0].Tick := 0;
  Raw[0].MicrosecondsPerBeat := 500000.0;
  Raw[0].Order := -1;
  RawCount := 1;
  for I := 0 to Song.Tempos.Count - 1 do
    if (Song.Tempos[I].Delta >= 0) and
      (Song.Tempos[I].Tempo > 0) then
    begin
      Raw[RawCount].Tick := Song.Tempos[I].Delta;
      Raw[RawCount].MicrosecondsPerBeat := Song.Tempos[I].Tempo;
      Raw[RawCount].Order := I;
      Inc(RawCount);
    end;
  SetLength(Raw, RawCount);
  SortRawTempos(Raw);

  SetLength(FSegments, RawCount);
  SegmentCount := 0;
  CurrentSeconds := 0.0;
  CurrentBeat := 0.0;
  for I := 0 to RawCount - 1 do
  begin
    if (I > 0) and (Raw[I].Tick > Raw[I - 1].Tick) then
    begin
      DeltaBeats := (Raw[I].Tick - Raw[I - 1].Tick) / Division;
      CurrentSeconds := CurrentSeconds +
        DeltaBeats * Raw[I - 1].MicrosecondsPerBeat / 1000000.0;
      CurrentBeat := CurrentBeat + DeltaBeats;
    end;

    Segment.StartSeconds := CurrentSeconds;
    Segment.StartBeat := CurrentBeat;
    Segment.TempoBpm := 60000000.0 / Raw[I].MicrosecondsPerBeat;

    // 同一Tickのテンポイベントは後勝ちとする。
    if (SegmentCount > 0) and
      (Raw[I].Tick = Raw[I - 1].Tick) then
      FSegments[SegmentCount - 1] := Segment
    else
    begin
      FSegments[SegmentCount] := Segment;
      Inc(SegmentCount);
    end;
  end;
  SetLength(FSegments, SegmentCount);
  BuildNotesFromSong(Song);
  Result := SegmentCount > 0;
end;

function TMusicTempoTable.Lookup(TimeSeconds: Double; out BeatPosition,
  TempoBpm, SegmentStartSeconds: Double): Boolean;
var
  HighIndex, LowIndex, Middle, SegmentIndex: Integer;
begin
  BeatPosition := 0.0;
  TempoBpm := 0.0;
  SegmentStartSeconds := 0.0;
  Result := Length(FSegments) > 0;
  if not Result then
    Exit;
  if TimeSeconds < 0 then
    TimeSeconds := 0;

  LowIndex := 0;
  HighIndex := High(FSegments);
  SegmentIndex := 0;
  while LowIndex <= HighIndex do
  begin
    Middle := LowIndex + (HighIndex - LowIndex) div 2;
    if FSegments[Middle].StartSeconds <= TimeSeconds then
    begin
      SegmentIndex := Middle;
      LowIndex := Middle + 1;
    end
    else
      HighIndex := Middle - 1;
  end;

  TempoBpm := FSegments[SegmentIndex].TempoBpm;
  SegmentStartSeconds := FSegments[SegmentIndex].StartSeconds;
  BeatPosition := FSegments[SegmentIndex].StartBeat +
    (TimeSeconds - SegmentStartSeconds) * TempoBpm / 60.0;
end;

function CalculateNoteEnvelope(const Note: TMusicNoteSegment;
  TimeSeconds: Double): Double;
const
  MAX_FADE_SECONDS = 0.05;
var
  Duration, FadeSeconds: Double;
begin
  Result := 0;
  if (TimeSeconds < Note.StartSeconds) or
    (TimeSeconds >= Note.EndSeconds) then
    Exit;

  Duration := Note.EndSeconds - Note.StartSeconds;
  FadeSeconds := Min(MAX_FADE_SECONDS, Duration / 2.0);
  Result := 1.0;
  if FadeSeconds <= 0 then
    Exit;

  if TimeSeconds < Note.StartSeconds + FadeSeconds then
    Result := (TimeSeconds - Note.StartSeconds) / FadeSeconds;
  if TimeSeconds > Note.EndSeconds - FadeSeconds then
    Result := Min(Result,
      (Note.EndSeconds - TimeSeconds) / FadeSeconds);
  Result := EnsureRange(Result, 0.0, 1.0);
end;

function TMusicTempoTable.LookupVolume(TimeSeconds: Double;
  out Level: Double): Boolean;
var
  Envelope, NoteLevel: Double;
  HighIndex, I, LowIndex, Middle, StartIndex: Integer;
begin
  Level := 0;
  Result := Length(FNotes) > 0;
  if not Result then
    Exit;
  if TimeSeconds < 0 then
    Exit;

  LowIndex := 0;
  HighIndex := High(FNotes);
  StartIndex := -1;
  while LowIndex <= HighIndex do
  begin
    Middle := LowIndex + (HighIndex - LowIndex) div 2;
    if FNotes[Middle].StartSeconds <= TimeSeconds then
    begin
      StartIndex := Middle;
      LowIndex := Middle + 1;
    end
    else
      HighIndex := Middle - 1;
  end;

  I := StartIndex;
  while (I >= 0) and
    (FNotes[I].StartSeconds >= TimeSeconds - FMaxNoteDuration) do
  begin
    if TimeSeconds < FNotes[I].EndSeconds then
    begin
      Envelope := CalculateNoteEnvelope(FNotes[I], TimeSeconds);
      NoteLevel := EnsureRange(FNotes[I].Velocity / 127.0 *
        Envelope, 0.0, 1.0);
      if NoteLevel > Level then
        Level := NoteLevel;
    end;
    Dec(I);
  end;
end;

function TMusicTempoTable.LookupPitch(TimeSeconds: Double;
  out NoteNumber, Envelope: Double): Boolean;
var
  ActiveStrength, BestStrength: Double;
  HighIndex, I, LowIndex, Middle, StartIndex: Integer;
begin
  NoteNumber := 0;
  Envelope := 0;
  Result := Length(FNotes) > 0;
  if not Result or (TimeSeconds < 0) then
    Exit;

  LowIndex := 0;
  HighIndex := High(FNotes);
  StartIndex := -1;
  while LowIndex <= HighIndex do
  begin
    Middle := LowIndex + (HighIndex - LowIndex) div 2;
    if FNotes[Middle].StartSeconds <= TimeSeconds then
    begin
      StartIndex := Middle;
      LowIndex := Middle + 1;
    end
    else
      HighIndex := Middle - 1;
  end;

  BestStrength := 0;
  I := StartIndex;
  while (I >= 0) and
    (FNotes[I].StartSeconds >= TimeSeconds - FMaxNoteDuration) do
  begin
    if TimeSeconds < FNotes[I].EndSeconds then
    begin
      ActiveStrength := FNotes[I].Velocity / 127.0 *
        CalculateNoteEnvelope(FNotes[I], TimeSeconds);
      if ActiveStrength > BestStrength then
      begin
        BestStrength := ActiveStrength;
        NoteNumber := FNotes[I].Key;
        Envelope := CalculateNoteEnvelope(FNotes[I], TimeSeconds);
      end;
    end;
    Dec(I);
  end;
  Result := BestStrength > 0;
end;

destructor TMusicTempoCacheEntry.Destroy;
begin
  Table.Free;
  inherited Destroy;
end;

function ReadFileIdentity(const FileName: string; out Age: Integer;
  out Size: Int64): Boolean;
var
  Search: TSearchRec;
begin
  Age := -1;
  Size := -1;
  Result := FindFirst(FileName, faAnyFile, Search) = 0;
  if not Result then
    Exit;
  try
    if (Search.Attr and faDirectory) <> 0 then
    begin
      Result := False;
      Exit;
    end;
    Age := DateTimeToFileDate(Search.TimeStamp);
    Size := Search.Size;
  finally
    FindClose(Search);
  end;
end;

function LoadCacheEntry(const FileName: string; Age: Integer;
  Size: Int64): TMusicTempoCacheEntry;
var
  Song: TSongData;
begin
  Result := TMusicTempoCacheEntry.Create;
  Result.FileAge := Age;
  Result.FileSize := Size;
  Result.IsValid := False;
  Song := TSongData.Create;
  try
    try
      if not Song.LoadFromMusicFile(FileName) then
        Exit;
      Result.Table := TMusicTempoTable.Create;
      Result.IsValid := Result.Table.BuildFromSong(Song);
      if not Result.IsValid then
        FreeAndNil(Result.Table);
    except
      // 壊れたファイルや未対応形式は無効なキャッシュとして静かに保持する。
      FreeAndNil(Result.Table);
      Result.IsValid := False;
    end;
  finally
    Song.Free;
  end;
end;

procedure InitializeMusicTempoCache;
begin
  if MusicTempoLock = nil then
    MusicTempoLock := TCriticalSection.Create;
  if MusicTempoCache = nil then
    MusicTempoCache :=
      TObjectDictionary<string, TMusicTempoCacheEntry>.Create([doOwnsValues]);
end;

procedure FinalizeMusicTempoCache;
begin
  FreeAndNil(MusicTempoCache);
  FreeAndNil(MusicTempoLock);
end;

function TryGetMusicSync(const FileName: string; TimeSeconds: Double;
  out BeatPosition, TempoBpm, SegmentStartSeconds: Double): Boolean;
var
  Age: Integer;
  Entry: TMusicTempoCacheEntry;
  FullName, Key: string;
  Size: Int64;
begin
  BeatPosition := 0.0;
  TempoBpm := 0.0;
  SegmentStartSeconds := 0.0;
  Result := False;
  if Trim(FileName) = '' then
    Exit;

  try
    FullName := ExpandFileName(FileName);
    if not ReadFileIdentity(FullName, Age, Size) then
      Exit;
    Key := LowerCase(FullName);

    InitializeMusicTempoCache;
    if (MusicTempoLock = nil) or (MusicTempoCache = nil) then
      Exit;
    MusicTempoLock.Acquire;
    try
      if not MusicTempoCache.TryGetValue(Key, Entry) or
        (Entry.FileAge <> Age) or (Entry.FileSize <> Size) then
      begin
        Entry := LoadCacheEntry(FullName, Age, Size);
        MusicTempoCache.AddOrSetValue(Key, Entry);
      end;
      Result := Entry.IsValid and
        Entry.Table.Lookup(TimeSeconds, BeatPosition, TempoBpm,
          SegmentStartSeconds);
    finally
      MusicTempoLock.Release;
    end;
  except
    // ファイルI/O、解析、キャッシュの例外をプラグイン境界へ出さない。
    Result := False;
  end;
end;

function TryGetMusicSyncAtFrame(const FileName: string; Frame: Int64;
  Rate, Scale: Integer; out BeatPosition, TempoBpm,
  SegmentStartFrame: Double): Boolean;
var
  SegmentStartSeconds, TimeSeconds: Double;
begin
  BeatPosition := 0.0;
  TempoBpm := 0.0;
  SegmentStartFrame := 0.0;
  Result := (Rate > 0) and (Scale > 0);
  if not Result then
    Exit;

  TimeSeconds := Frame * Scale / Rate;
  Result := TryGetMusicSync(FileName, TimeSeconds, BeatPosition, TempoBpm,
    SegmentStartSeconds);
  if Result then
    SegmentStartFrame := SegmentStartSeconds * Rate / Scale;
end;

function TryGetMusicVolume(const FileName: string; TimeSeconds: Double;
  out Level: Double): Boolean;
var
  Age: Integer;
  Entry: TMusicTempoCacheEntry;
  FullName, Key: string;
  Size: Int64;
begin
  Level := 0;
  Result := False;
  if Trim(FileName) = '' then
    Exit;

  try
    FullName := ExpandFileName(FileName);
    if not ReadFileIdentity(FullName, Age, Size) then
      Exit;
    Key := LowerCase(FullName);

    InitializeMusicTempoCache;
    if (MusicTempoLock = nil) or (MusicTempoCache = nil) then
      Exit;
    MusicTempoLock.Acquire;
    try
      if not MusicTempoCache.TryGetValue(Key, Entry) or
        (Entry.FileAge <> Age) or (Entry.FileSize <> Size) then
      begin
        Entry := LoadCacheEntry(FullName, Age, Size);
        MusicTempoCache.AddOrSetValue(Key, Entry);
      end;
      Result := Entry.IsValid and Entry.Table.LookupVolume(
        TimeSeconds, Level);
    finally
      MusicTempoLock.Release;
    end;
  except
    Level := 0;
    Result := False;
  end;
end;

function TryGetMusicPitch(const FileName: string; TimeSeconds: Double;
  out NoteNumber, Envelope: Double): Boolean;
var
  Age: Integer;
  Entry: TMusicTempoCacheEntry;
  FullName, Key: string;
  Size: Int64;
begin
  NoteNumber := 0;
  Envelope := 0;
  Result := False;
  if Trim(FileName) = '' then
    Exit;

  try
    FullName := ExpandFileName(FileName);
    if not ReadFileIdentity(FullName, Age, Size) then
      Exit;
    Key := LowerCase(FullName);

    InitializeMusicTempoCache;
    if (MusicTempoLock = nil) or (MusicTempoCache = nil) then
      Exit;
    MusicTempoLock.Acquire;
    try
      if not MusicTempoCache.TryGetValue(Key, Entry) or
        (Entry.FileAge <> Age) or (Entry.FileSize <> Size) then
      begin
        Entry := LoadCacheEntry(FullName, Age, Size);
        MusicTempoCache.AddOrSetValue(Key, Entry);
      end;
      Result := Entry.IsValid and Entry.Table.LookupPitch(
        TimeSeconds, NoteNumber, Envelope);
    finally
      MusicTempoLock.Release;
    end;
  except
    NoteNumber := 0;
    Envelope := 0;
    Result := False;
  end;
end;

initialization
  MusicTempoCache := nil;
  MusicTempoLock := nil;

finalization
  FinalizeMusicTempoCache;

end.
