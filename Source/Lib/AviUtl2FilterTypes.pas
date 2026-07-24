unit AviUtl2FilterTypes;

// AviUtl2 フィルタープラグイン登録に必要な最小ABI定義。

{$ALIGN 8}

interface

type
  LPCWSTR = PWideChar;
  TFuncProcVideo = function(Video: Pointer): Byte; cdecl;
  TFuncProcAudio = function(Audio: Pointer): Byte; cdecl;

  PFILTER_PLUGIN_TABLE = ^TFILTER_PLUGIN_TABLE;
  TFILTER_PLUGIN_TABLE = record
    Flag: Integer;
    Name: LPCWSTR;
    Label_: LPCWSTR;
    Information: LPCWSTR;
    Items: ^Pointer;
    Func_Proc_Video: TFuncProcVideo;
    Func_Proc_Audio: TFuncProcAudio;
  end;

const
  FILTER_FLAG_VIDEO = 1;
  FILTER_FLAG_FILTER = 8;

implementation

end.
