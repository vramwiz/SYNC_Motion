program SYNC_Motion_PluginLoadTests;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils;

type
  TGetFilterPluginTable = function: Pointer; cdecl;
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
  TSelectItemArray = array[0..7] of TSelectItem;
  PSelectItemArray = ^TSelectItemArray;

  TSelect = record
    ItemType: PWideChar;
    Name: PWideChar;
    Value: Integer;
    List: PSelectItem;
  end;
  PSelect = ^TSelect;

  TPluginTable = record
    Flag: Integer;
    Name, Label_, Information: PWideChar;
    Items: ^Pointer;
    FuncProcVideo, FuncProcAudio: Pointer;
  end;
  PPluginTable = ^TPluginTable;

  TItemArray = array[0..18] of Pointer;
  PItemArray = ^TItemArray;

var
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
    if (Items = nil) or (Items^[18] <> nil) then
      raise Exception.Create('plugin items are not terminated');
    if string(PItemHeader(Items^[2])^.Name) <> 'オフセット (秒)' then
      raise Exception.Create('offset name mismatch');
    if (PTrackItem(Items^[2])^.Value <> 0.0) or
      (PTrackItem(Items^[2])^.S <> -86400.0) or
      (PTrackItem(Items^[2])^.E <> 86400.0) or
      (PTrackItem(Items^[2])^.Step <> 0.01) then
      raise Exception.Create('offset range mismatch');
    if string(PItemHeader(Items^[3])^.Name) <> 'リズムずらし (拍)' then
      raise Exception.Create('rhythm shift name mismatch');
    if (PTrackItem(Items^[3])^.Value <> 0.0) or
      (PTrackItem(Items^[3])^.S <> -4.0) or
      (PTrackItem(Items^[3])^.E <> 4.0) or
      (PTrackItem(Items^[3])^.Step <> 0.01) then
      raise Exception.Create('rhythm shift range mismatch');
    if (string(PItemHeader(Items^[4])^.ItemType) <> 'group') or
      (string(PItemHeader(Items^[4])^.Name) <> 'リズム') then
      raise Exception.Create('rhythm group mismatch');
    if (string(PItemHeader(Items^[5])^.ItemType) <> 'select') or
      (string(PItemHeader(Items^[5])^.Name) <> 'リズムタイプ') or
      (PSelect(Items^[5])^.Value <> 1) or
      (string(PSelect(Items^[5])^.List^.Name) <> 'なし') or
      (string(PSelectItemArray(PSelect(Items^[5])^.List)^[3].Name) <>
        'バウンス') or
      (string(PSelectItemArray(PSelect(Items^[5])^.List)^[4].Name) <>
        'ステップ') or
      (string(PSelectItemArray(PSelect(Items^[5])^.List)^[5].Name) <>
        '振り子（1拍）') or
      (string(PSelectItemArray(PSelect(Items^[5])^.List)^[6].Name) <>
        '振り子（2拍）') then
      raise Exception.Create('rhythm type mismatch');
    if string(PItemHeader(Items^[6])^.Name) <> '強さ' then
      raise Exception.Create('rhythm strength name mismatch');
    if (PTrackItem(Items^[6])^.Value <> 50.0) or
      (PTrackItem(Items^[6])^.S <> -100.0) or
      (PTrackItem(Items^[6])^.E <> 100.0) or
      (PTrackItem(Items^[6])^.Step <> 1.0) then
      raise Exception.Create('rhythm strength range mismatch');
    if string(PItemHeader(Items^[7])^.Name) <> '速さ' then
      raise Exception.Create('rhythm speed name mismatch');
    if (PTrackItem(Items^[7])^.Value <> 2.0) or
      (PTrackItem(Items^[7])^.S <> 1.0) or
      (PTrackItem(Items^[7])^.E <> 100.0) or
      (PTrackItem(Items^[7])^.Step <> 0.1) then
      raise Exception.Create('rhythm speed range mismatch');
    if (string(PItemHeader(Items^[8])^.Name) <> 'Param1') or
      (PTrackItem(Items^[8])^.Value <> 50.0) or
      (PTrackItem(Items^[8])^.S <> 0.0) or
      (PTrackItem(Items^[8])^.E <> 100.0) or
      (PTrackItem(Items^[8])^.Step <> 1.0) or
      (string(PItemHeader(Items^[9])^.Name) <> 'Param2') or
      (PTrackItem(Items^[9])^.Value <> 50.0) or
      (PTrackItem(Items^[9])^.S <> 0.0) or
      (PTrackItem(Items^[9])^.E <> 100.0) or
      (PTrackItem(Items^[9])^.Step <> 1.0) then
      raise Exception.Create('rhythm parameter settings mismatch');
    if (string(PItemHeader(Items^[10])^.ItemType) <> 'group') or
      (string(PItemHeader(Items^[10])^.Name) <> '音量') then
      raise Exception.Create('volume group mismatch');
    if (string(PItemHeader(Items^[11])^.ItemType) <> 'select') or
      (string(PItemHeader(Items^[11])^.Name) <> '音量タイプ') or
      (PSelect(Items^[11])^.Value <> 0) or
      (string(PSelect(Items^[11])^.List^.Name) <> 'なし') or
      (string(PItemHeader(Items^[12])^.Name) <> '音量強さ') or
      (PTrackItem(Items^[12])^.Value <> 0.0) then
      raise Exception.Create('volume settings mismatch');
    if (string(PItemHeader(Items^[13])^.ItemType) <> 'group') or
      (string(PItemHeader(Items^[13])^.Name) <> '音程') then
      raise Exception.Create('pitch group mismatch');
    if (string(PItemHeader(Items^[14])^.ItemType) <> 'select') or
      (string(PItemHeader(Items^[14])^.Name) <> '音程タイプ') or
      (PSelect(Items^[14])^.Value <> 0) or
      (string(PSelect(Items^[14])^.List^.Name) <> 'なし') then
      raise Exception.Create('pitch type mismatch');
    if (string(PItemHeader(Items^[15])^.Name) <> '高音') or
      (PTrackItem(Items^[15])^.Value <> 0.0) or
      (string(PItemHeader(Items^[16])^.Name) <> '低音') or
      (PTrackItem(Items^[16])^.Value <> 0.0) then
      raise Exception.Create('pitch amount settings mismatch');
    if (string(PItemHeader(Items^[17])^.Name) <> '基準音') or
      (PTrackItem(Items^[17])^.Value <> 60.0) or
      (PTrackItem(Items^[17])^.S <> 0.0) or
      (PTrackItem(Items^[17])^.E <> 127.0) then
      raise Exception.Create('base note settings mismatch');
    Writeln('PASS');
  finally
    FreeLibrary(ModuleHandle);
  end;
end.
