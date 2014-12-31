unit mainForm;

interface

// tab order  requires custom FMX.TabControl:
// procedure TTabItem.DoAddObject(const AObject: TFmxObject); contains no  AddToTabList(AObject);  call

// Yes, I know about TClipboard, embarcadero.rs_xe4/rad/Cutting,_Copying,_and_Pasting_Text.html
uses
  System.SysUtils, System.Types, System.UITypes, System.Rtti, System.Classes,
  System.Variants, FMX.Types, FMX.Controls, FMX.Forms, FMX.Dialogs,
  FMX.StdCtrls, FMX.TabControl, FMX.Layouts, FMX.Memo, FMX.Edit, FMX.ListBox,
  FMX.ExtCtrls, IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient,
  IdHTTP, IdStack, IdHeaderList, IdException, Web.HTTPApp, IdIntercept,
  IdLogBase, IdLogDebug, IdGlobal, shellapi,
  FMX.Platform.Win, AnsiStrings,

  System.Win.ComObj, System.Win.Registry,
  Winapi.Windows, Winapi.Messages, Winapi.ShlObj,
  Character, FMX.Objects,
  System.IniFiles;

const
  WM_TRAYMSG = WM_USER + 250;
  APP_CAPTION = 'pastebin.org';
  DEV_KEY = '8013dbc557b58bad3ffbb2135cb8ac48';
  PASTEBIN_URL = 'http://pastebin.com/api/api_post.php';
  HK_VIEW = 0;
  HK_EDIT = 1;
  CFG_MAINSECTION = 'Settings';

  CFG_DEVKEY = 'DevKey';
  CFG_TRAY = 'Tray';
  CFG_DEBUG = 'Debug';
  CFG_HOTKEY = 'Hotkey';
  CFG_FORMAT = 'Format';
  CFG_KEEP = 'Keep';
  CFG_VISIBILITY = 'Visibility';

resourcestring
  STR_ENTER_HOTKEY = 'Нажмите сочетание клавиш или Esc для отмены';
  STR_COPIED_TO_CLIPBOARD = ' скопировано в буфер обмена';
  STR_PROTOCOL_ERROR = 'Ошибка протокола. HTTP статус: %s %s';
  STR_SOCKET_ERROR = 'Сокет вернул ошибку. Код: %s %s';
  STR_GENERAL_EXC = 'Общее исключение в классе: %s %s';
  STR_NOTHING_TO_SEND = 'Нечего посылать';
  STR_TITLE_IS_EMPTY = 'Не заполнено название';
  STR_SENDING = 'Отправляем...';

  STR_CONNECTION_CLOSED = 'Connection was closed gracefully.';
  STR_UNKNOWN_EXC = 'Неизвестное исключение ';
  STR_HTTP_HEADERS = '--------------------<HTTP header>---------------------';
  STR_HTTP_HEADERS_END =
    '--------------------</HTTP header>--------------------';

type
  TPasteHotKey = record
    FMod: TShiftState;
    FKey: Word;
  end;

  TStatusLevel = (slInfo, slError, slOk);

  TfrmPaste = class(TForm)
    TabControl1: TTabControl;
    TabItem1: TTabItem;
    TabItem2: TTabItem;
    pOptionMain: TPanel;
    lName: TLabel;
    eTitle: TEdit;
    cbFormat: TComboBox;
    lFormat: TLabel;
    lExpiration: TLabel;
    lVisibility: TLabel;
    cbVisibility: TComboBox;
    btnPaste: TButton;
    cbKeep: TComboBox;
    mPaste: TMemo;
    IdLogDebug1: TIdLogDebug;
    Client: TIdHTTP;
    cbCloseType: TCheckBox;
    eDevkey: TEdit;
    cbDebug: TCheckBox;
    TabItem3: TTabItem;
    mLog: TMemo;
    lHotkeys: TLabel;
    StatusBar1: TStatusBar;
    Panel1: TPanel;
    Label1: TLabel;
    Label2: TLabel;
    StyleBook2: TStyleBook;
    lStatus: TText;
    procedure FormCreate(Sender: TObject);
    procedure btnPasteClick(Sender: TObject);
    procedure IdLogDebug1Send(ASender: TIdConnectionIntercept;
      var ABuffer: TIdBytes);
    procedure FormDestroy(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure cbDebugChange(Sender: TObject);
    procedure lHotkeysClick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char;
      Shift: TShiftState);
    procedure ClientHeadersAvailable(Sender: TObject; AHeaders: TIdHeaderList;
      var VContinue: Boolean);

  private
    { Private declarations }
    FNID: TNotifyIconData;
    Msg_Handler: HWND;
    StartUp: Boolean;
    FHotKey: TPasteHotKey;
    F_OldHotKey: TPasteHotKey;
    procedure ShowTray();
    procedure LoadFormats();
    procedure HideFromTaskbar();
    procedure MESSAGE_WND_PROC(var _message: TMessage);
    procedure CopyToClipboard(const str: String);
    function CopyFromClipboard(): String;
    procedure UpdateHKOnForm();
    procedure UpdateHKSequence(var KeyChar: Char; var Key: Word;
      Shift: TShiftState);
    procedure UpdateStatus(statusText: String; Level: TStatusLevel = slInfo);
    procedure Send();
    procedure RegisterHK();
    procedure HK_NewPaste();
    procedure ReadSettings();
    procedure WriteSettings();
    function PackHotkey(hk: TPasteHotKey): Integer;
    function UnPackHotkey(packedHK: Integer): TPasteHotKey;
  public
    { Public declarations }
  end;

  TString = class(TObject)
  public
    value: String;
    constructor Create(val: String);
  end;

var
  frmPaste: TfrmPaste;

implementation

{$R *.fmx}

procedure TfrmPaste.cbDebugChange(Sender: TObject);
begin
  TabItem3.Visible := cbDebug.IsChecked
end;

procedure TfrmPaste.ClientHeadersAvailable(Sender: TObject;
  AHeaders: TIdHeaderList; var VContinue: Boolean);
var
  headers: TStringsEnumerator;
begin
  headers := AHeaders.GetEnumerator;
  mLog.Lines.Add(STR_HTTP_HEADERS);
  while (headers.MoveNext) do
    mLog.Lines.Add(headers.GetCurrent);
  mLog.Lines.Add(STR_HTTP_HEADERS_END);
  VContinue := true;
end;

procedure TfrmPaste.CopyToClipboard(const str: String);
var
  buff: THandle;
  len: Integer;
begin
  len := (str.Length + 1) * SizeOf(Char);

  buff := GlobalAlloc(GMEM_MOVEABLE + GMEM_DDESHARE, len);
  Move(PChar(str)^, GlobalLock(buff)^, len);
  GlobalUnlock(buff);

  OpenClipboard(WindowHandleToPlatform(self.Handle).Wnd);
  EmptyClipboard();
  SetClipboardData(CF_UNICODETEXT, buff);
  CloseClipboard;
end;

function TfrmPaste.CopyFromClipboard: String;
var
  Handle: HWND;
begin
  OpenClipboard(WindowHandleToPlatform(self.Handle).Wnd);
  Handle := GetClipboardData(CF_UNICODETEXT);
  CloseClipboard;

  if (Handle = null) then
    result := EmptyStr
  else
  begin
    result := PChar(Handle)
  end;
end;

procedure TfrmPaste.FormActivate(Sender: TObject);
begin
  if StartUp then
  begin
    hide;
    StartUp := false;
  end;
end;

procedure TfrmPaste.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if cbCloseType.IsChecked then
  begin
    CanClose := false;
    hide;
  end;
end;

procedure TfrmPaste.FormCreate(Sender: TObject);
begin
  Msg_Handler := AllocateHWnd(MESSAGE_WND_PROC);
  UpdateStatus('');
  LoadFormats();

  ReadSettings();
  if (FHotKey.FKey = 0) then
  begin
    FHotKey.FMod := [ssAlt, ssShift, ssCtrl];
    FHotKey.FKey := vkC;
  end;
  lHotkeys.StyleLookup := '';
  UpdateHKOnForm;
  RegisterHK;

  //Prevents form from infinite loop (see onActivate handler)
  StartUp := true;
  ShowTray();

  HideFromTaskbar();
end;

procedure TfrmPaste.FormDestroy(Sender: TObject);
begin
  Shell_NotifyIcon(NIM_DELETE, @FNID);
  DeallocateHWnd(Msg_Handler);
  WriteSettings;
end;

procedure TfrmPaste.lHotkeysClick(Sender: TObject);
  procedure ResetHotKey(var hk: TPasteHotKey);
  begin
    hk.FMod := [];
    hk.FKey := 0;
    lHotkeys.Text := STR_ENTER_HOTKEY;
  end;

begin
  if lHotkeys.Tag = HK_VIEW then
  begin
    lHotkeys.StyleLookup := 'lHotkeysStyle1';
    lHotkeys.Tag := HK_EDIT;
    F_OldHotKey := FHotKey;
    ResetHotKey(FHotKey);
  end;
end;


procedure TfrmPaste.UpdateHKOnForm();
var
  caption: String;
begin
  caption := '';
  with FHotKey do
  begin
    if ssCtrl in FMod then
      caption := caption + 'Ctrl+';
    if ssAlt in FMod then
      caption := caption + 'Alt+';
    if ssShift in FMod then
      caption := caption + 'Shift+';
    lHotkeys.Text := caption + Char(FKey);
  end;
end;

procedure TfrmPaste.UpdateHKSequence(var KeyChar: Char; var Key: Word;
  Shift: TShiftState);
begin
  if ((Shift = []) and (Key = vkEscape)) then
  begin
    lHotkeys.Tag := HK_VIEW;
    lHotkeys.StyleLookup := '';
    FHotKey := F_OldHotKey;
  end
  else
  begin
    case Key of
      vkShift:
        FHotKey.FMod := FHotKey.FMod + [ssShift];
      vkControl:
        FHotKey.FMod := FHotKey.FMod + [ssCtrl];
      vkMenu:
        FHotKey.FMod := FHotKey.FMod + [ssAlt];
    else
      // lStatus.Text := r.ToString(r) + ' : ' + KeyChar + ' : ' + Key.ToString(Key) + ' : ' + r.ToString(Lo(r));
      if (Key = 0) then
        FHotKey.FKey := Lo(VkKeyScanEx(KeyChar, GetKeyboardLayout(0)))
      else
        FHotKey.FKey := Key;

      lHotkeys.Tag := HK_VIEW;
      lHotkeys.StyleLookup := '';
      RegisterHK();
    end;
  end;
  UpdateHKOnForm;
end;

procedure TfrmPaste.UpdateStatus(statusText: String; Level: TStatusLevel);
begin
  if (Level = slOk) then
    lStatus.Color := TAlphaColorRec.Darkgreen
  else if (Level = slError) then
    lStatus.Color := TAlphaColorRec.Crimson
  else
    lStatus.Color := TAlphaColorRec.Blue;

  lStatus.Text := statusText;
end;

procedure TfrmPaste.WriteSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ChangeFileExt(ParamStr(0), '.ini'));
  try
    with Ini do
    begin
      WriteString(CFG_MAINSECTION, CFG_DEVKEY, eDevkey.Text);
      WriteBool(CFG_MAINSECTION, CFG_TRAY, cbCloseType.IsChecked);
      WriteBool(CFG_MAINSECTION, CFG_DEBUG, cbDebug.IsChecked);
      WriteInteger(CFG_MAINSECTION, CFG_HOTKEY, PackHotkey(FHotKey));
      WriteInteger(CFG_MAINSECTION, CFG_FORMAT, cbFormat.ItemIndex);
      WriteInteger(CFG_MAINSECTION, CFG_KEEP, cbKeep.ItemIndex);
      WriteInteger(CFG_MAINSECTION, CFG_VISIBILITY, cbVisibility.ItemIndex);
    end
  finally
    Ini.Free;
  end;

end;

procedure TfrmPaste.ReadSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ChangeFileExt(ParamStr(0), '.ini'));
  try
    with Ini do
    begin
      eDevkey.Text          := ReadString(CFG_MAINSECTION, CFG_DEVKEY, '');
      cbCloseType.IsChecked := ReadBool(CFG_MAINSECTION, CFG_TRAY, True);
      cbDebug.IsChecked     := ReadBool(CFG_MAINSECTION, CFG_DEBUG, False);
      cbDebug.OnChange(nil);

      FHotKey := UnPackHotkey( ReadInteger(CFG_MAINSECTION, CFG_HOTKEY, 0));

      cbFormat.ItemIndex := ReadInteger(CFG_MAINSECTION, CFG_FORMAT, 0);
      cbKeep.ItemIndex := ReadInteger(CFG_MAINSECTION, CFG_KEEP, 0);
      cbVisibility.ItemIndex := ReadInteger(CFG_MAINSECTION, CFG_VISIBILITY, 0);
    end;
  finally
    Ini.Free;
  end;
end;

procedure TfrmPaste.FormKeyDown(Sender: TObject; var Key: Word;
  var KeyChar: Char; Shift: TShiftState);
begin
  if lHotkeys.Tag = HK_EDIT then
    UpdateHKSequence(KeyChar, Key, Shift)
  else if ((ssCtrl in Shift) and (Key = VK_RETURN)) then
    btnPasteClick(nil);
end;

procedure TfrmPaste.RegisterHK();
var
  mods: Integer;
begin
  if F_OldHotKey.FKey > 0 then
    UnregisterHotKey(Msg_Handler, F_OldHotKey.FKey);

  with FHotKey do
  begin
    mods := 0;
    // any way to iterate through set that buit on constant instead of itemtype?
    if (ssShift in FMod) then
      mods := mods or MOD_SHIFT;
    if (ssCtrl in FMod) then
      mods := mods or MOD_CONTROL;
    if (ssAlt in FMod) then
      mods := mods or MOD_ALT;
    RegisterHotKey(Msg_Handler, FKey, mods, FKey and $FF)
  end;
end;

procedure TfrmPaste.HideFromTaskbar;
begin
  // AllocateHWnd
  ShowWindow(GetWindow(WindowHandleToPlatform(self.Handle).Wnd,
    GW_OWNER), SW_HIDE);
  with CreateComObject(CLSID_TaskbarList) as ITaskbarList do
  begin
    HrInit;
    DeleteTab(WindowHandleToPlatform(frmPaste.Handle).Wnd);
  end;
end;

procedure TfrmPaste.HK_NewPaste;
var
  caption: String;
begin
  TabControl1.ActiveTab := TabItem1;
  mPaste.Text := CopyFromClipboard();

  for caption in mPaste.Lines do
    if (not caption.Trim.IsEmpty) then
    begin
      eTitle.Text := caption.Trim;
      eTitle.SelectAll;
      break;
    end;
end;

procedure TfrmPaste.LoadFormats();
var
  resource: TStringList;
  I: Integer;
  arr: TArray<String>;
  rs: TResourceStream;
begin
  cbFormat.Clear;
  resource := TStringList.Create;
  rs := TResourceStream.Create(hInstance, 'RC_formats', RT_RCDATA);
  resource.LoadFromStream(rs);

  for I := 0 to resource.Count - 1 do
  begin
    arr := resource.Strings[I].Split(['=']);
    cbFormat.Items.AddObject(arr[1], TString.Create(arr[0]));
  end;
  cbFormat.ItemIndex := 0;
  rs.Free;

  cbKeep.Clear;
  rs := TResourceStream.Create(hInstance, 'RC_expire', RT_RCDATA);
  resource.LoadFromStream(rs);
  for I := 0 to resource.Count - 1 do
  begin
    arr := resource.Strings[I].Split(['=']);
    cbKeep.Items.AddObject(arr[1], TString.Create(arr[0]));
  end;
  cbKeep.ItemIndex := 0;
  resource.Free;
  rs.Free;
end;

function TfrmPaste.PackHotkey(hk: TPasteHotKey): Integer;
begin
  Result := 0;
  if (ssShift in hk.FMod) then
    Result := Result or MOD_SHIFT;
  if (ssCtrl in hk.FMod) then
    Result := Result or MOD_CONTROL;
  if (ssAlt in hk.FMod) then
    Result := Result or MOD_ALT;

  Result := (Result shl 8) or (hk.FKey and $FF);
end;

function TfrmPaste.UnPackHotkey(packedHK: Integer): TPasteHotKey;
var
  tmp: Integer;
begin
  tmp := packedHK;
  Result.FKey := tmp and $FF;

  tmp := (tmp shr 8) and $FF;
  if (tmp and MOD_SHIFT > 0) then
    Result.FMod := Result.FMod + [ssShift];
  if (tmp and MOD_ALT > 0) then
    Result.FMod := Result.FMod + [ssAlt];
  if (tmp and MOD_CONTROL > 0) then
    Result.FMod := Result.FMod + [ssCtrl];
end;

procedure TfrmPaste.IdLogDebug1Send(ASender: TIdConnectionIntercept;
  var ABuffer: TIdBytes);
begin
  mLog.Lines.Append(TEncoding.UTF8.GetString(TBytes(ABuffer)))
end;

procedure TfrmPaste.Send;
var
  expiration, highlight, visibility: String;
  params: TStringList;
  status: TStatusLevel;
  str: string;
  function getCBValue(cb: TComboBox): String;
  begin
    result := TString(cb.Items.Objects[cb.ItemIndex]).value;
  end;

begin
  UpdateStatus(STR_SENDING);
  expiration := getCBValue(cbKeep);
  highlight := getCBValue(cbFormat);
  visibility := cbVisibility.ItemIndex.ToString;

  params := TStringList.Create;
  with params do
  begin
    Add('api_option=paste');
    Add('api_paste_private=' + visibility);
    if eTitle.Text.Length > 0 then
      Add('api_paste_name=' + String(HTTPEncode(AnsiString(eTitle.Text))));


    Add('api_dev_key=' + eDevkey.Text);
    Add('api_paste_expire_date=' + expiration);
    Add('api_paste_format=' + highlight);
    Add('api_paste_code=' + mPaste.Text);
  end;

  status := slError;
  try
    str := Client.Post(PASTEBIN_URL, params);
    CopyToClipboard(str);
    str := str + STR_COPIED_TO_CLIPBOARD;
    status := slOk;
  except
    on E: EIdHTTPProtocolException do
      str := String.Format(STR_PROTOCOL_ERROR, [IntToStr(E.ErrorCode),
        E.Message]);
    on E: EIdConnClosedGracefully do
      str := STR_CONNECTION_CLOSED;
    on E: EIdSocketError do
      str := String.Format(STR_SOCKET_ERROR, [IntToStr(E.LastError),
        E.Message]);
    on E: EIdException do
      str := String.Format(STR_GENERAL_EXC, [E.ClassName, E.Message]);
    on E: Exception do
      str := STR_UNKNOWN_EXC + E.Message;
  end;
  UpdateStatus(str, status);
  params.Free;
end;

procedure TfrmPaste.ShowTray;
begin
  // http://stackoverflow.com/questions/20109686/fmx-trayicon-message-handling
  // http://www.cyberforum.ru/delphi-firemonkey/thread626503.html
  with FNID do
  begin
    cbSize := SizeOf;
    Wnd := Msg_Handler;
    uID := 1;
    uFlags := NIF_ICON or NIF_MESSAGE or NIF_TIP;
    uCallbackMessage := WM_TRAYMSG;
    hIcon := LoadImage(hInstance, PWideChar('RC_TRAY_ICON'), IMAGE_ICON,
      32, 32, 0);
    StrPCopy(szTip, APP_CAPTION);

  end;
  Shell_NotifyIcon(NIM_ADD, @FNID);
end;

procedure TfrmPaste.MESSAGE_WND_PROC(var _message: TMessage);
  procedure PopupMainForm();
  begin
    frmPaste.Show;
    frmPaste.TopMost := true;
    frmPaste.TopMost := false;
    frmPaste.SetActive(true);
    eTitle.SetFocus;
  end;

begin
  if _message.Msg = WM_HOTKEY then
  begin
    HK_NewPaste();
    PopupMainForm();
  end
  else
    case _message.lParam of
      WM_LBUTTONDOWN:
        PopupMainForm();
      WM_RBUTTONDOWN:
        begin
          UnregisterHotKey(Msg_Handler, FHotKey.FKey);
          Application.Terminate;
        end;
    end;
end;

procedure TfrmPaste.btnPasteClick(Sender: TObject);
begin
  if (mPaste.Text.Trim.IsEmpty) then
    UpdateStatus(STR_NOTHING_TO_SEND, slError)
  else if (eTitle.Text.Trim.IsEmpty) then
    UpdateStatus(STR_TITLE_IS_EMPTY, slError)
  else
    Send();
end;

{ TString }
constructor TString.Create(val: String);
begin
  value := val
end;

end.
