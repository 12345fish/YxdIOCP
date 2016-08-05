unit uServer;

interface

uses
  Windows, SysUtils, Classes, SyncObjs, Iocp, iocp.Utils.Hash;
  
type
  /// <summary>
  /// ��־��Ϣ����
  /// </summary>
  TXLogType = (log_Debug, {������Ϣ} log_Info {��Ϣ}, log_Warning {����},
    log_Error {����});

type
  /// <summary>
  /// ��־д�봦��
  /// </summary>
  TOnWriteLog = procedure (Sender: TObject; AType: TXLogType;
    const Log: string) of object;

  /// <summary>
  /// ����������
  /// </summary>
  TOnProcRequest = procedure (Request: TIocpHttpRequest; Response: TIocpHttpResponse) of object;

  /// <summary>
  /// HTTP����ϵͳ
  /// </summary>
  TPtService = class(TObject)
  private
    FPtWebService: TIocpHttpServer;
    FOnWriteLog: TOnWriteLog;
    HttpReqRef: Integer;
    FProcList: TStringHash;
  protected
    function IsDestroying: Boolean;
    procedure Log(Sender: TObject; AType: TXLogType; const Msg: string);
    procedure LogD(Sender: TObject; const Msg: string);
    procedure LogE(Sender: TObject; const Title: string; E: Exception);
    procedure DoWriteLog(Sender: TObject; AType: TXLogType; const Msg: string);
  protected
    procedure DoRequest(Sender: TIocpHttpServer; Request: TIocpHttpRequest; Response: TIocpHttpResponse);
    procedure DoRegProc(); virtual; abstract;
    procedure DoFreeProcItem(Item: PHashItem);
  public
    constructor Create(Port: Word); reintroduce;
    destructor Destroy; override;

    procedure RegProc(const URI: string; const Proc: TOnProcRequest);

    procedure Start;
    procedure Stop;
  end;

type
  TPtHttpService = class(TPtService)
  protected
    procedure DoRegProc(); override;
    procedure RequestDemo03(Request: TIocpHttpRequest; Response: TIocpHttpResponse);
  end;

implementation

type
  PMethod = ^TMethod;

var
  SoftPath: string;

{ TPtService }

constructor TPtService.Create(Port: Word);
begin
  FOnWriteLog := DoWriteLog;
  FPtWebService := TIocpHttpServer.Create(nil);
  FPtWebService.ListenPort := Port;
  FPtWebService.UploadMaxDataSize := 1024 * 1024;
  FPtWebService.MaxTaskWorker := 64;
  FPtWebService.OnHttpRequest := DoRequest;

  FProcList := TStringHash.Create();
  FProcList.OnFreeItem := DoFreeProcItem;

  DoRegProc(); 
end;

destructor TPtService.Destroy;
begin
  try
    Stop;
    FreeAndNil(FPtWebService);
    FreeAndNil(FProcList);
  except
    LogE(Self, 'DoDestroy', Exception(ExceptObject));  
  end;
  inherited Destroy;
end;

procedure TPtService.DoFreeProcItem(Item: PHashItem);
begin
  if Item <> nil then
    Dispose(Pointer(Item.Value));
end;

procedure TPtService.DoRequest(Sender: TIocpHttpServer;
  Request: TIocpHttpRequest; Response: TIocpHttpResponse);
var
  Path: string;
  V: Number;
begin
  InterlockedIncrement(HttpReqRef);
  Path := StringReplace(string(Request.URI), '/', '\', [rfReplaceAll]);
  if (Length(Path) > 0) and (Path[1] = '\') then
    Delete(Path, 1, 1);
  Path := SoftPath + Path;
  if FileExists(Path) then begin
    Response.SendFile(Path, '', False, True);
  end else begin
    V := FProcList.ValueOf(LowerCase(string(Request.URI)));
    if V <> -1 then begin
      TOnProcRequest(PMethod(Pointer(V))^)(Request, Response);
    end else
      Response.ErrorRequest(404);
  end;
end;

procedure TPtService.DoWriteLog(Sender: TObject; AType: TXLogType;
  const Msg: string);
begin
end;

function TPtService.IsDestroying: Boolean;
begin
  Result := (not Assigned(Self));
end;

procedure TPtService.Log(Sender: TObject; AType: TXLogType; const Msg: string);
begin
  if Assigned(FOnWriteLog) and (not IsDestroying) then
    FOnWriteLog(Sender, AType, Msg);  
end;

procedure TPtService.LogD(Sender: TObject; const Msg: string);
begin
  if Assigned(FOnWriteLog) and (not IsDestroying) then
    FOnWriteLog(Sender, log_Debug, Msg);
end;

procedure TPtService.LogE(Sender: TObject; const Title: string; E: Exception);
begin
  if Assigned(FOnWriteLog) and (not IsDestroying) then begin
    if E = nil then
      FOnWriteLog(Sender, log_Error, Format('[%s] %s', [Sender.ClassName, Title]))
    else
      FOnWriteLog(Sender, log_Error, Format('[%s] %s Error: %s',
        [Sender.ClassName, Title, E.Message]))
  end;
end;

procedure TPtService.RegProc(const URI: string; const Proc: TOnProcRequest);
var
  P: PMethod;
begin
  if Length(URI) = 0 then Exit;
  if Assigned(Proc) then begin
    New(P);
    P^ := TMethod(Proc);
    FProcList.Add(LowerCase(URI), Integer(P));
  end;
end;

procedure TPtService.Start;
begin
  FPtWebService.Open;
end;

procedure TPtService.Stop;
begin
  FPtWebService.Close;
end;  

{ TPtHttpService }

procedure TPtHttpService.DoRegProc;
begin
  RegProc('/RequestDemo03.o', RequestDemo03);
end;

procedure TPtHttpService.RequestDemo03(Request: TIocpHttpRequest;
  Response: TIocpHttpResponse);
var
  O: TIocpHttpWriter;
begin
  //Response.ContentType := 'text/html;charset=UTF-16';
  O := TIocpHttpWriter.Create();
  //Out.IsUTF8 := True;
  O.Write('���: ').Write(Request.GetParam('userid')).Write('<br>');
  O.Write('�û���: ').Write(Request.GetParam('username')).Write('<br>');
  O.Write('����: ').Write(Request.GetParam('userpass')).Write('<br>');
  O.Write('�Ա�: ').Write(Request.GetParam('sex')).Write('<br>');
  O.Write('����: ').Write(Request.GetParam('dept')).Write('<br>');
  O.Write('��Ȥ: ').Write(Request.GetParamValues('inst')).Write('<br>');
  O.Write('˵��: ').Write(Request.GetParam('note')).Write('<br>');
  O.Write('��������: ').Write(Request.GetParam('hiddenField')).Write('<br>');
  Response.Send(O, True);
end;

initialization
  SoftPath := ExtractFilePath(ParamStr(0));

finalization

end.