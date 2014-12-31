program PasteBin;

{$R 'resources.res' 'resources.rc'}

uses
  FMX.Forms,
  mainForm in 'mainForm.pas' {frmPaste},
  KeyConstants in 'KeyConstants.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmPaste, frmPaste);
  Application.Run;
end.
