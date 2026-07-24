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

  TItemArray = array[0..7] of Pointer;
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
    if (Items = nil) or (Items^[7] <> nil) then
      raise Exception.Create('plugin items are not terminated');
    if string(PItemHeader(Items^[2])^.ItemType) <> 'select' then
      raise Exception.Create('motion type is not a select item');
    if string(PItemHeader(Items^[2])^.Name) <> '動きタイプ' then
      raise Exception.Create('motion type name mismatch');
    if PSelect(Items^[2])^.Value <> 0 then
      raise Exception.Create('motion type default mismatch');
    if string(PSelect(Items^[2])^.List^.Name) <> 'ジャンプ' then
      raise Exception.Create('motion type choice mismatch');
    if string(PItemHeader(Items^[3])^.Name) <> '速さ' then
      raise Exception.Create('motion speed name mismatch');
    if (PTrackItem(Items^[3])^.Value <> 2.0) or
      (PTrackItem(Items^[3])^.S <> 1.0) or
      (PTrackItem(Items^[3])^.E <> 100.0) or
      (PTrackItem(Items^[3])^.Step <> 0.1) then
      raise Exception.Create('motion speed range mismatch');
    if string(PItemHeader(Items^[4])^.Name) <> '幅' then
      raise Exception.Create('motion width name mismatch');
    if (PTrackItem(Items^[4])^.Value <> 50.0) or
      (PTrackItem(Items^[4])^.S <> 0.0) or
      (PTrackItem(Items^[4])^.E <> 1000.0) or
      (PTrackItem(Items^[4])^.Step <> 1.0) then
      raise Exception.Create('motion width range mismatch');
    if string(PItemHeader(Items^[5])^.Name) <> '角度' then
      raise Exception.Create('motion angle name mismatch');
    if (PTrackItem(Items^[5])^.Value <> 0.0) or
      (PTrackItem(Items^[5])^.S <> -360.0) or
      (PTrackItem(Items^[5])^.E <> 360.0) or
      (PTrackItem(Items^[5])^.Step <> 0.1) then
      raise Exception.Create('motion angle range mismatch');
    if string(PItemHeader(Items^[6])^.Name) <> 'ずらし' then
      raise Exception.Create('sync offset name mismatch');
    if (PTrackItem(Items^[6])^.Value <> 0.0) or
      (PTrackItem(Items^[6])^.S <> -60.0) or
      (PTrackItem(Items^[6])^.E <> 60.0) or
      (PTrackItem(Items^[6])^.Step <> 0.01) then
      raise Exception.Create('sync offset range mismatch');
    Writeln('PASS');
  finally
    FreeLibrary(ModuleHandle);
  end;
end.
