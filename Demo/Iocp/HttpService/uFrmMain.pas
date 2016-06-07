unit uFrmMain;

interface

uses
  uServer,
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, XPMan, Buttons, ExtCtrls;

type
  THttpService = class(TForm)
    Edit1: TEdit;
    XPManifest1: TXPManifest;
    BitBtn1: TBitBtn;
    Label1: TLabel;
    Label2: TLabel;
    procedure BitBtn1Click(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
    FSvr: TPtService;
  public
    { Public declarations }
  end;

var
  HttpService: THttpService;

implementation

{$R *.dfm}

procedure THttpService.BitBtn1Click(Sender: TObject);
begin
  if Assigned(FSvr) then begin
    FreeAndNil(FSvr);
    BitBtn1.Caption := '��������';
  end else begin
    BitBtn1.Enabled := False;
    FSvr := TPtService.Create(StrToIntDef(Edit1.Text, 8080));
    FSvr.Start;
    BitBtn1.Caption := 'ֹͣ����';
    BitBtn1.Enabled := True;
  end
end;

procedure THttpService.FormCreate(Sender: TObject);
begin
  DoubleBuffered := True;
  Edit1.DoubleBuffered := True;
  BitBtn1.DoubleBuffered := True;
end;

procedure THttpService.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FSvr);
end;

end.
