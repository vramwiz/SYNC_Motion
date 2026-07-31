program SYNC_Motion_PluginLoadTests;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils;

type
  TObjectHandle = Pointer;
  TGetFilterPluginTable = function: Pointer; cdecl;
  PEditSection = ^TEditSection;
  TButtonCallback = procedure(Edit: PEditSection); cdecl;
  TSetObjectItemValue = function(Obj: TObjectHandle; Effect, Item: PWideChar;
    Value: PAnsiChar): Byte; cdecl;
  TGetFocusObject = function: TObjectHandle; cdecl;
  TItemHeader = record
    ItemType: PWideChar;
    Name: PWideChar;
  end;
  PItemHeader = ^TItemHeader;

  TTrackItem = record
    ItemType: PWideChar;
    Name: PWideChar;
    Value, S, E, Step: Double;
  end;
  PTrackItem = ^TTrackItem;

  TSelectItem = record
    Name: PWideChar;
    Value: Integer;
  end;
  PSelectItem = ^TSelectItem;

  TSelect = record
    ItemType: PWideChar;
    Name: PWideChar;
    Value: Integer;
    List: PSelectItem;
  end;
  PSelect = ^TSelect;

  TButton = record
    ItemType: PWideChar;
    Name: PWideChar;
    Callback: TButtonCallback;
  end;
  PButton = ^TButton;

  TEditSection = record
    Info, CreateObjectFromAlias, FindObject, CountObjectEffect: Pointer;
    GetObjectLayerFrame, GetObjectAlias, GetObjectItemValue: Pointer;
    SetObjectItemValue: TSetObjectItemValue;
    MoveObject, DeleteObject: Pointer;
    GetFocusObject: TGetFocusObject;
  end;

  TPluginTable = record
    Flag: Integer;
    Name, Label_, Information: PWideChar;
    Items: ^Pointer;
    FuncProcVideo, FuncProcAudio: Pointer;
  end;
  PPluginTable = ^TPluginTable;

  TItemArray = array[0..17] of Pointer;
  PItemArray = ^TItemArray;

var
  PresetUnderTest: Integer;
  PresetSetCount: Integer;

function MockSetObjectItemValue(Obj: TObjectHandle; Effect, Item: PWideChar;
  Value: PAnsiChar): Byte; cdecl;
var
  ItemName, ItemValue: string;
begin
  if (Obj <> Pointer(1)) or
    (string(Effect) <> 'SYNC_音楽同期アニメーション_Filter') then
    Exit(0);

  ItemName := string(Item);
  ItemValue := string(UTF8String(Value));
  if ((ItemName = 'リズムタイプ') and
    (((PresetUnderTest = 1) and (ItemValue <> '1')) or
    ((PresetUnderTest <> 1) and (ItemValue <> '0')))) or
    ((ItemName = '強さ') and
    (((PresetUnderTest = 1) and (ItemValue <> '50')) or
    ((PresetUnderTest <> 1) and (ItemValue <> '0')))) or
    ((ItemName = '速さ') and (ItemValue <> '2')) or
    ((ItemName = '基準音') and (ItemValue <> '60')) or
    ((ItemName <> 'リズムタイプ') and (ItemName <> '強さ') and
    (ItemName <> '速さ') and
    (ItemName <> '基準音') and
    (ItemValue <> '0')) then
    Exit(0);

  Inc(PresetSetCount);
  Result := 1;
end;

function MockGetFocusObject: TObjectHandle; cdecl;
begin
  Result := Pointer(1);
end;

var
  Edit: TEditSection;
  GetTable: TGetFilterPluginTable;
  Items: PItemArray;
  ModuleHandle: HMODULE;
  Table: Pointer;
begin
  if ParamCount <> 1 then
    raise Exception.Create('plugin path is required');

  ModuleHandle := LoadLibrary(PChar(ParamStr(1)));
  if ModuleHandle = 0 then
    RaiseLastOSError;
  try
    GetTable := TGetFilterPluginTable(
      GetProcAddress(ModuleHandle, 'GetFilterPluginTable'));
    if not Assigned(GetTable) then
      raise Exception.Create('GetFilterPluginTable export is missing');
    Table := GetTable;
    if Table = nil then
      raise Exception.Create('plugin table is nil');

    Items := PItemArray(PPluginTable(Table)^.Items);
    if (Items = nil) or (Items^[17] <> nil) then
      raise Exception.Create('plugin items are not terminated');
    if string(PItemHeader(Items^[2])^.Name) <> 'ずらし' then
      raise Exception.Create('sync offset name mismatch');
    if (PTrackItem(Items^[2])^.Value <> 0.0) or
      (PTrackItem(Items^[2])^.S <> -60.0) or
      (PTrackItem(Items^[2])^.E <> 60.0) or
      (PTrackItem(Items^[2])^.Step <> 0.01) then
      raise Exception.Create('sync offset range mismatch');
    if (string(PItemHeader(Items^[3])^.ItemType) <> 'select') or
      (string(PItemHeader(Items^[3])^.Name) <> 'プリセット') or
      (PSelect(Items^[3])^.Value <> 1) or
      (string(PSelect(Items^[3])^.List^.Name) <> 'なし') then
      raise Exception.Create('preset item mismatch');
    if (string(PItemHeader(Items^[4])^.ItemType) <> 'button') or
      (string(PItemHeader(Items^[4])^.Name) <> '反映') then
      raise Exception.Create('preset button mismatch');
    if (string(PItemHeader(Items^[5])^.ItemType) <> 'group') or
      (string(PItemHeader(Items^[5])^.Name) <> 'リズム') then
      raise Exception.Create('rhythm group mismatch');
    if (string(PItemHeader(Items^[6])^.ItemType) <> 'select') or
      (string(PItemHeader(Items^[6])^.Name) <> 'リズムタイプ') or
      (PSelect(Items^[6])^.Value <> 1) or
      (string(PSelect(Items^[6])^.List^.Name) <> 'なし') then
      raise Exception.Create('rhythm type mismatch');
    if string(PItemHeader(Items^[7])^.Name) <> '強さ' then
      raise Exception.Create('rhythm strength name mismatch');
    if (PTrackItem(Items^[7])^.Value <> 50.0) or
      (PTrackItem(Items^[7])^.S <> -100.0) or
      (PTrackItem(Items^[7])^.E <> 100.0) or
      (PTrackItem(Items^[7])^.Step <> 1.0) then
      raise Exception.Create('rhythm strength range mismatch');
    if string(PItemHeader(Items^[8])^.Name) <> '速さ' then
      raise Exception.Create('rhythm speed name mismatch');
    if (PTrackItem(Items^[8])^.Value <> 2.0) or
      (PTrackItem(Items^[8])^.S <> 1.0) or
      (PTrackItem(Items^[8])^.E <> 100.0) or
      (PTrackItem(Items^[8])^.Step <> 0.1) then
      raise Exception.Create('rhythm speed range mismatch');
    if (string(PItemHeader(Items^[9])^.ItemType) <> 'group') or
      (string(PItemHeader(Items^[9])^.Name) <> '音量') then
      raise Exception.Create('volume group mismatch');
    if (string(PItemHeader(Items^[10])^.ItemType) <> 'select') or
      (string(PItemHeader(Items^[10])^.Name) <> '音量タイプ') or
      (PSelect(Items^[10])^.Value <> 0) or
      (string(PSelect(Items^[10])^.List^.Name) <> 'なし') or
      (string(PItemHeader(Items^[11])^.Name) <> '音量強さ') or
      (PTrackItem(Items^[11])^.Value <> 0.0) then
      raise Exception.Create('volume settings mismatch');
    if (string(PItemHeader(Items^[12])^.ItemType) <> 'group') or
      (string(PItemHeader(Items^[12])^.Name) <> '音程') then
      raise Exception.Create('pitch group mismatch');
    if (string(PItemHeader(Items^[13])^.ItemType) <> 'select') or
      (string(PItemHeader(Items^[13])^.Name) <> '音程タイプ') or
      (PSelect(Items^[13])^.Value <> 0) or
      (string(PSelect(Items^[13])^.List^.Name) <> 'なし') then
      raise Exception.Create('pitch type mismatch');
    if (string(PItemHeader(Items^[14])^.Name) <> '高音') or
      (PTrackItem(Items^[14])^.Value <> 0.0) or
      (string(PItemHeader(Items^[15])^.Name) <> '低音') or
      (PTrackItem(Items^[15])^.Value <> 0.0) then
      raise Exception.Create('pitch amount settings mismatch');
    if (string(PItemHeader(Items^[16])^.Name) <> '基準音') or
      (PTrackItem(Items^[16])^.Value <> 60.0) or
      (PTrackItem(Items^[16])^.S <> 0.0) or
      (PTrackItem(Items^[16])^.E <> 127.0) then
      raise Exception.Create('base note settings mismatch');

    FillChar(Edit, SizeOf(Edit), 0);
    Edit.SetObjectItemValue := MockSetObjectItemValue;
    Edit.GetFocusObject := MockGetFocusObject;
    PresetUnderTest := 0;
    PresetSetCount := 0;
    PSelect(Items^[3])^.Value := 0;
    PButton(Items^[4])^.Callback(@Edit);
    if PresetSetCount <> 9 then
      raise Exception.Create('preset apply callback mismatch');
    if (PSelect(Items^[6])^.Value <> 0) or
      (PTrackItem(Items^[7])^.Value <> 0.0) or
      (PSelect(Items^[10])^.Value <> 0) or
      (PTrackItem(Items^[11])^.Value <> 0.0) or
      (PSelect(Items^[13])^.Value <> 0) or
      (PTrackItem(Items^[14])^.Value <> 0.0) or
      (PTrackItem(Items^[15])^.Value <> 0.0) then
      raise Exception.Create('none preset local values mismatch');

    PresetUnderTest := 1;
    PresetSetCount := 0;
    PSelect(Items^[3])^.Value := 1;
    PButton(Items^[4])^.Callback(@Edit);
    if (PresetSetCount <> 9) or
      (PSelect(Items^[6])^.Value <> 1) or
      (PTrackItem(Items^[7])^.Value <> 50.0) then
      raise Exception.Create('basic preset values mismatch');
    Writeln('PASS');
  finally
    FreeLibrary(ModuleHandle);
  end;
end.
