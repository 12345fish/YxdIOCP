{*******************************************************}
{                                                       }
{       HTTP WebSocket ����� ���Ŀ�                    }
{                                                       }
{       ��Ȩ���� (C) 2016 YangYxd                       }
{                                                       }
{*******************************************************}

{
  WebSocket ����˽�֧�� Version >= 13 �ı�׼Э��
}

unit iocp.Http.WebSocket;

{$IF (RTLVersion>=26) and (not Defined(NEXTGEN))}
{$DEFINE ANSISTRINGS}
{$IFEND}

interface

uses
  iocp.Http, SHA,
  {$IFDEF UNICODE}Soap.EncdDecd, System.NetEncoding{$ELSE}Base64{$ENDIF},
  iocp.Utils.Hash, iocp.Utils.Str, 
  iocp.Sockets, iocp.Task, iocp.core.Engine, 
  iocp.Utils.Queues,
  {$IFDEF ANSISTRINGS}AnsiStrings, {$ENDIF}
  SyncObjs, Windows, Classes, SysUtils;

type
  /// <summary>
  /// WebSocket ������
  /// </summary>
  TIocpWebSocketOpcode = (
    wso_Continuous, {������ϢƬ��}
    wso_Text {�ı���ϢƬ��},
    wso_Binary {��������ϢƬ��},
    wso_Rsv3, wso_Rsv4, wso_Rsv5, wso_Rsv6, wso_Rsv7 {�ǿ�����ϢƬ�ϱ����Ĳ�����},
    wso_Close {���ӹر�},
    wso_Ping {��������ping},
    wso_Pong {��������pong},
    wso_RsvB, wso_RsvC, wso_RsvD, wso_RsvE, wso_RsvF {Ϊ�����Ŀ�����ϢƬ�ϵı���������}
  );

  /// <summary>
  /// WebSocket ����֡
  /// </summary>
  TIocpWebSocketDataFrame = record
  private
    function GetFIN: Boolean;
    function GetRSV1: Byte;
    function GetRSV2: Byte;
    function GetRSV3: Byte;
    function GetOpcode: TIocpWebSocketOpcode;
    function GetHasMask: Boolean;
    function GetDataLength: Int64;
    function GetMask: TBytes;
    function GetData: PAnsiChar;
    procedure DecodeMask(const Offset: Integer);
    function GetDataLengthOffset: Integer;
  public
    // Դ����
    SrcData: PAnsiChar;

    // �������ݣ��ɹ����� True, ���ݲ��Ϸ����� False
    function TranslateFrame(const SrcDataLength: Integer): Integer;
    // ��ȡ�����ַ���
    function DataString(ACharSet: TIocpHttpCharset = hct_UTF8): string; 

    // �Ƿ�Ϊ������ϢƬ��
    property FIN: Boolean read GetFIN;
    // �Զ���Э�飬���û��Լ�����������0
    property RSV1: Byte read GetRSV1;
    property RSV2: Byte read GetRSV2;
    property RSV3: Byte read GetRSV3;
    // ������, 4λ
    property Opcode: TIocpWebSocketOpcode read GetOpcode;
    // �Ƿ�ʹ������
    property HasMask: Boolean read GetHasMask;
    // �������ݳ���
    property DataLength: Int64 read GetDataLength;
    // ���� (�����ĸ��ֽ�)
    property Mask: TBytes read GetMask;
    // ��������������
    property Data: PAnsiChar read GetData;
  end;
  PIocpWebSocketDataFrame = ^TIocpWebSocketDataFrame;
  
type
  TIocpWebSocketServer = class;
  TIocpWebSocketConnection = class;
  TIocpWebSocketRequest = class;
  TIocpWebSocketResponse = class;
  TIocpWebSocketHttpRequest = class;

  TOnWebSocketConnection = procedure (Sender: TIocpWebSocketServer;
    Request: TIocpWebSocketHttpRequest; var IsAccept: Boolean) of object;
  TOnWebSocketDisconnect = procedure (Sender: TIocpWebSocketServer;
    Connection: TIocpWebSocketConnection) of object;
  TOnWebSocketRecvBuffer = procedure (Sender: TIocpWebSocketServer;
    Connection: TIocpWebSocketConnection; const Frame: TIocpWebSocketDataFrame) of object;
  TOnWebSocketRequest = procedure (Sender: TIocpWebSocketServer;
    Request: TIocpWebSocketRequest; Response: TIocpWebSocketResponse) of object;

  /// <summary>
  /// WebSocket ����
  /// </summary>
  TIocpWebSocketConnection = class(TIocpHttpConnection)
  private
    FSessionID: string;
    FProtocol: StringA;
  protected
    FSocketRequest: TIocpWebSocketRequest;
    FSocketResponse: TIocpWebSocketResponse;
    procedure DoCleanUp; override;
    procedure OnRecvBuffer(buf: Pointer; len: Cardinal; ErrorCode: Integer); override;
    procedure DoWebSocketrecvBuffer(buf: Pointer; len: Cardinal; ErrorCode: Integer); virtual;
    procedure ReleaseClientContext(); override;

    procedure DoSendPing;
    procedure DoSendPong;
  public
    constructor Create(AOwner: TIocpCustom); override;
    destructor Destroy; override;

    /// <summary>
    /// ��ȡ��ǰ����Session
    /// </summary>
    function GetSession: Pointer;
    /// <summary>
    /// ��ǰ���ӵ� SessionID
    /// </summary>
    property SessionID: string read FSessionID write FSessionID;
    /// <summary>
    /// WebSocket Э�飺�û�������ַ�������������ͬURL�£���ͬ�ķ�������Ҫ��Э��
    /// </summary>
    property Protocol: StringA read FProtocol write FProtocol;
    /// <summary>
    /// WebSocket ��������
    /// </summary>
    property Response: TIocpWebSocketResponse read FSocketResponse;
  end;

  TIocpWebSocketPingThd = class(TThread)
  private
    FOwner: TIocpWebSocketServer;
  protected
    procedure Execute; override;
  end;

  /// <summary>
  /// WebSocket ���� (���� Http ����)
  /// </summary>
  TIocpWebSocketServer = class(TIocpHttpServer)
  private
    FConnMap: TStringHash;
    FMaxConnection: Integer;
    FWebSocketRequestPool: TBaseQueue;
    FPingThread: TIocpWebSocketPingThd;

    FOnWebSocketRequest: TOnWebSocketRequest;
    FOnWebSocketRecvBuffer: TOnWebSocketRecvBuffer; 
    FOnWebSocketConnection: TOnWebSocketConnection;
    FOnWebSocketDisconnect: TOnWebSocketDisconnect;
    function GetConnectionItem(const SessionID: string): TIocpWebSocketConnection;
    function GetConnectionCount: Integer;
  protected
    procedure DoRequest(ARequest: TIocpHttpRequest); override;
    procedure DoWebSocketRequest(Request: TIocpWebSocketRequest; Response: TIocpWebSocketResponse); virtual;
    procedure DoWebSocketRecvBuffer(AConnection: TIocpWebSocketConnection; const Frame: TIocpWebSocketDataFrame); 
    procedure DoWebSocketConnection(Request: TIocpWebSocketHttpRequest; var IsAccept: Boolean); virtual;
    procedure DoWebSocketDisconnect(AConnection: TIocpWebSocketConnection); virtual;

    procedure DoOpen(); override;
    procedure DoClose(); override;

    // ��ʱ Ping ���ߵĿͻ���
    procedure DoPingClients();

    function GetWebSocketRequest: TIocpWebSocketRequest; virtual;
    procedure FreeWebSocketRequest(V: TIocpWebSocketRequest);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    /// <summary>
    /// ������ߵ�WebSocket�����Ƿ����һ��SesssionID
    /// </summary>
    function ExistSession(const SessionID: string): Boolean;

    /// <summary>
    /// ������WebSocket���е�Session����List�У�����ȡ��������
    /// </summary>
    function GetSessionList(List: TStrings): Integer;

    /// <summary>
    /// ��ǰ���ߵ�WebSocket����, ͨ�� SessionID ����ȡһ���Ѿ����������ӣ�Ȼ���շ���Ϣ
    /// </summary>
    property Connections[const SessionID: string]: TIocpWebSocketConnection read GetConnectionItem;
    /// <summary>
    /// ��ǰ���ߵ�WebSocket����
    /// </summary>
    property ConnectionCount: Integer read GetConnectionCount;
  published
    /// <summary>
    /// Ԥ������������������ڳ�ʼ���Ự������ (�����ڼ�������Ч)
    /// </summary>
    property MaxConnection: Integer read FMaxConnection write FMaxConnection default 99991;
    /// <summary>
    /// WebSocket ��������
    /// </summary>
    property OnWebSocketConnection: TOnWebSocketConnection read FOnWebSocketConnection write FOnWebSocketConnection;
    /// <summary>
    /// WebSocket ���ӶϿ�
    /// </summary>
    property OnWebSocketDisconnect: TOnWebSocketDisconnect read FOnWebSocketDisconnect write FOnWebSocketDisconnect;
    /// <summary>
    /// WebSocket ����
    /// </summary>
    property OnWebSocketRequest: TOnWebSocketRequest read FOnWebSocketRequest write FOnWebSocketRequest;
  end;

  /// <summary>
  /// WebSocket Http ��������
  /// </summary>
  TIocpWebSocketHttpRequest = class(TIocpHttpRequest)
  private
    function GetIsUpgrade: Boolean;
    function GetWebSocketKey: StringA;
    function GetWebSocketExtensions: StringA;
    function GetWebSocketProtocol: StringA;
    function GetWebSocketVersion: StringA;
    function GetWebSocketOrigin: StringA;
  protected
  public
    // �Ƿ�����Э�� (������Get��ʽ, Http1.1����߰汾)
    property IsUpgrade: Boolean read GetIsUpgrade;
    // ���ݴ�Key������ Sec-WebSocket-Accept ��Ӧͷ
    property WebSocketKey: StringA read GetWebSocketKey;
    // Э��汾����ǰֵ������ >= 13
    property WebSocketVersion: StringA read GetWebSocketVersion;
    // ��ʾclient��Ӧ�ó���֧�ֵ�Э���б�serverѡ��һ������û�пɽ��ܵ�Э����Ӧ֮��
    property WebSocketProtocol: StringA read GetWebSocketProtocol;
    // Э����չ�� ĳ��Э�����֧�ֶ����չ��ͨ��������ʵ��Э����ǿ
    property WebSocketExtensions: StringA read GetWebSocketExtensions;
    // ��Դ
    property WebSocketOrigin: StringA read GetWebSocketOrigin;
  end;

  /// <summary>
  /// WebSocket Http ��Ӧ
  /// </summary>
  TIocpWebSocketHttpResponse = class(TIocpHttpResponse)
  protected
    procedure MakeHeaderEx(const Data: TStringCatHelperA); override;
  public
    procedure ResponseWebSocket();
    function GetWebSocketAccept(): StringA;
  end;

  /// <summary>
  /// WebSocket ����
  /// </summary>
  TIocpWebSocketRequest = class(TObject)
  private
    FOwner: TIocpWebSocketServer;
    FData: TBytesCatHelper;
    FDataOpcode: TIocpWebSocketOpcode;
    function GetDataSize: Int64;
    function GetData: TBytesCatHelper;
  protected
  public
    constructor Create(AOwner: TIocpWebSocketServer);
    destructor Destroy; override;
    procedure Clear;

    // ��ȡ�����ַ���
    function DataString(ACharSet: TIocpHttpCharset = hct_UTF8): string;

    property Owner: TIocpWebSocketServer read FOwner write FOwner;
    property Data: TBytesCatHelper read GetData;
    property DataSize: Int64 read GetDataSize;
    property DataOpcode: TIocpWebSocketOpcode read FDataOpcode write FDataOpcode;
  end;

  /// <summary>
  /// WebSocket ��Ӧ
  /// </summary>
  TIocpWebSocketResponse = class(TObject)
  private
    FConnection: TIocpWebSocketConnection;
    FSendBuffer: TBytesCatHelper;
    function GetSendBuffer: TBytesCatHelper;
  protected
    procedure MakeData(buf: Pointer; Len: Cardinal;
      Opcode: TIocpWebSocketOpcode; FIN: Boolean = True);
    property SendBuffer: TBytesCatHelper read GetSendBuffer;
  public
    constructor Create();
    destructor Destroy; override;
    procedure Clear;

    /// <summary>
    /// ��������
    /// </summary>
    procedure Send(const buf: Pointer; const len: Cardinal); overload;
    procedure Send(buf: PChar; len: Cardinal; ACharSet: TIocpHttpCharset = hct_UTF8); overload;
    procedure Send(const Data: string; ACharSet: TIocpHttpCharset = hct_UTF8); overload;
    procedure Send(const Data: TBytes); overload;
    /// <summary>
    /// ��������ʹ�÷�Ƭ���ͷ�ʽ
    /// </summary>
    procedure Send(Stream: TStream; Opcode: TIocpWebSocketOpcode = wso_Binary); overload;

    property Connection: TIocpWebSocketConnection read FConnection write FConnection;
  end;

implementation

const
  CSConnection: StringA             = 'Connection';
  CSUpgrade: StringA                = 'Upgrade';
  CSUpgradeI: StringA               = 'upgrade';
  CSWebScoket: StringA              = 'websocket';
  CSSecWebSocketVersion: StringA    = 'Sec-WebSocket-Version';
  CSSecWebSocketExtensions: StringA = 'Sec-WebSocket-Extensions';
  CSSecWebSocketProtocol: StringA   = 'Sec-WebSocket-Protocol';
  CSSecWebSocketKey: StringA        = 'Sec-WebSocket-Key';
  CSSecWebSocketOrigin: StringA     = 'Sec-WebSocket-Origin';

var
  Workers: TIocpTask;

{ TIocpWebSocketDataFrame }

function ReadBit(Value: Byte; const Index: Integer): Byte; inline;
begin
  Result := Value and (1 shl Index) shr Index;
end;

function ReadHi(Value: Byte): Byte; inline;
begin
  Result := Value shr 4;
end;

function ReadLo(Value: Byte): Byte; inline;
begin
  Result := Value and $F;
end;

procedure WriteBit(var Data: Byte; const Index: Integer; Value: Byte); inline;
begin
  if Value = 0 then
    Data := Data and ((1 shl Index) xor $FFFFFFFF)
  else
    Data := Data or (1 shl Index);
end;

procedure WriteLo(var Data: Byte; Value: Byte); inline;
begin
  Data := Data or Value;
end;

// ת���ֽ���
function SwapByteOrder(const Value: Int64): Int64; overload;
begin
  Result :=
    ((Value and $00000000000000ff) shl 56) or 
    ((Value and $000000000000ff00) shl 40) or
    ((Value and $0000000000ff0000) shl 24) or
    ((Value and $00000000ff000000) shl 8) or
    ((Value and $000000ff00000000) shr 8) or
    ((Value and $0000ff0000000000) shr 24) or
    ((Value and $00ff000000000000) shr 40) or
    ((Value and $ff00000000000000) shr 56);
end;

function SwapByteOrder(const Value: Word): Word; overload;
begin
  Result := ((Value and $00ff) shl 8) or ((Value and $ff00) shr 8);
end;

function GetDataString(ACharSet: TIocpHttpCharset; const Data: Pointer;
  const DataLength: Integer): string;
begin
  case ACharSet of
    hct_GB2312:
      {$IFDEF UNICODE}
      Result := PCharAToStringW(Data, DataLength);
      {$ELSE}
      Result := PCharToString(Data, DataLength);
      {$ENDIF}
    hct_UTF8:
      {$IFDEF UNICODE}
      Result := Utf8Decode(Data, DataLength);
      {$ELSE}
      Result := Utf8Decode(Data, DataLength);
      {$ENDIF}
    hct_UTF16:
      {$IFDEF UNICODE}
      Result := PCharToString(Data, DataLength);
      {$ELSE}
      Result := PCharAToStringW(Data, DataLength)
      {$ENDIF}
  else
    Result := PCharToString(Data, DataLength);
  end;
end;

procedure TIocpWebSocketDataFrame.DecodeMask(const Offset: Integer);
var
  P: PAnsiChar;
  Mask: TBytes;
  I: Integer;
begin
  Mask := GetMask;
  P := SrcData + Offset;
  for I := 0 to DataLength - 1 do begin
    PByte(P)^ := Ord(P^) xor Mask[I mod 4];
    Inc(P);
  end;
end;

function TIocpWebSocketDataFrame.GetData: PAnsiChar;
begin
  Result := SrcData + GetDataLengthOffset + 2;
  if HasMask then Inc(Result, 4);   
end;

function TIocpWebSocketDataFrame.GetDataLength: Int64;
begin
  Result := Ord(SrcData[1]) and $7F;
  if Result = 126 then
    Result := Ord(SrcData[2]) shl 8 + Ord(SrcData[3])
  else if Result = 127 then
    Result := SwapByteOrder(PInt64(@SrcData[2])^);
end;

function TIocpWebSocketDataFrame.GetDataLengthOffset: Integer;
begin
  Result := Ord(SrcData[1]) and $7F;
  if Result < 126 then
    Result := 0
  else if Result = 126 then
    Result := 2
  else if Result = 127 then
    Result := 8;
end;

function TIocpWebSocketDataFrame.DataString(ACharSet: TIocpHttpCharset): string;
begin
  Result := GetDataString(ACharSet, Data, DataLength);
end;

function TIocpWebSocketDataFrame.GetFIN: Boolean;
begin
  Result := Boolean(ReadBit(PByte(SrcData)^, 7));
end;

function TIocpWebSocketDataFrame.GetHasMask: Boolean;
begin
  Result := Boolean(ReadBit(Ord(SrcData[1]), 7));
end;

function TIocpWebSocketDataFrame.GetMask: TBytes;
begin
  if HasMask then begin
    SetLength(Result, 4);
    Move(SrcData[2 + GetDataLengthOffset()], Result[0], 4)
  end else
    SetLength(Result, 0);
end;

function TIocpWebSocketDataFrame.GetOpcode: TIocpWebSocketOpcode;
begin
  Result := TIocpWebSocketOpcode(ReadLo(PByte(SrcData)^));
end;

function TIocpWebSocketDataFrame.GetRSV1: Byte;
begin
  Result := ReadBit(PByte(SrcData)^, 6);
end;

function TIocpWebSocketDataFrame.GetRSV2: Byte;
begin
  Result := ReadBit(PByte(SrcData)^, 5);
end;

function TIocpWebSocketDataFrame.GetRSV3: Byte;
begin
  Result := ReadBit(PByte(SrcData)^, 4);
end;

function TIocpWebSocketDataFrame.TranslateFrame(const SrcDataLength: Integer): Integer;
var
  LO: Integer;
begin
  LO := GetDataLengthOffset();
  if SrcDataLength < (2 + LO) then
    Result := 0
  else if HasMask then begin
    Result := (6 + LO + DataLength);
    if Result <= SrcDataLength then
      DecodeMask(6 + LO)
    else
      Result := 0;
  end else begin
    Result := (2 + LO + DataLength);
    if Result > SrcDataLength then
      Result := 0;
  end;
end;

{ TIocpWebSocketServer }

constructor TIocpWebSocketServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMaxConnection := 99991;
  FContextClass := TIocpWebSocketConnection;
  FHttpRequestClass := TIocpWebSocketHttpRequest;
  FHttpResponseClass := TIocpWebSocketHttpResponse;
  FWebSocketRequestPool := TBaseQueue.Create;
end;

destructor TIocpWebSocketServer.Destroy;
begin
  inherited Destroy;
  FreeAndNil(FPingThread);
  FreeAndNil(FConnMap);
  try
    FWebSocketRequestPool.FreeDataObject;
  finally
    FreeAndNil(FWebSocketRequestPool);
  end;
end;

procedure TIocpWebSocketServer.DoClose;
begin
  if Assigned(FPingThread) then begin
    FPingThread.Terminate;
    FreeAndNil(FPingThread);
  end;
  FreeAndNil(FConnMap);
  inherited;
end;

procedure TIocpWebSocketServer.DoOpen;
begin
  inherited;
  FConnMap := TStringHash.Create(FMaxConnection);
  FPingThread := TIocpWebSocketPingThd.Create(True);
  FPingThread.FOwner := Self;
  {$IFDEF UNICODE}
  FPingThread.Start;
  {$ELSE}
  FPingThread.Resume;
  {$ENDIF}
end;

procedure TIocpWebSocketServer.DoPingClients();

  procedure InitList(List: TList);
  var
    I: Integer;
    P: PHashItem;
  begin
    FConnMap.Lock;
    try
      for I := 0 to High(FConnMap.Buckets) do begin
        P := FConnMap.Buckets[I];
        while P <> nil do begin
          List.Add(Pointer(P.Value));
          P := P^.Next;
        end;
      end;
    finally
      FConnMap.UnLock;
    end;
  end;
  
var
  I: Integer;
  List: TList;
  Conn: TIocpWebSocketConnection;
begin
  List := TList.Create;
  try
    InitList(List);
    for I := 0 to List.Count - 1 do begin
      Conn := TIocpWebSocketConnection(List[I]);
      try
        if Assigned(Conn) and (not Conn.IsDisconnecting) and (Conn.Active) then
          Conn.DoSendPing;
      except
        DoStateMsgE(Self, 'DoPingClients. ' + Exception(ExceptObject).Message);
      end;
    end;
  finally
    List.Free;
  end;
end;

procedure TIocpWebSocketServer.DoRequest(ARequest: TIocpHttpRequest);
var
  IsUpgrade: Boolean;
begin
  if Assigned(ARequest) then begin
    if TIocpWebSocketHttpRequest(ARequest).IsUpgrade then begin
      IsUpgrade := True; 
      // ����һ�������¼�
      DoWebSocketConnection(TIocpWebSocketHttpRequest(ARequest), IsUpgrade);
      // ���������������
      if IsUpgrade then begin
        // ��¼ SessionID 
        TIocpWebSocketConnection(ARequest.Connection).FSessionID := string(ARequest.SessionID);
        // ����һ�����������Http��Ӧ
        TIocpWebSocketHttpResponse(ARequest.Response).ResponseWebSocket();
        // ����Ự��������
        FConnMap.Add(TIocpWebSocketConnection(ARequest.Connection).FSessionID,
          iocp.Utils.Hash.Number(ARequest.Connection));
      end else
        inherited DoRequest(ARequest);
    end else
      inherited DoRequest(ARequest);
  end;
end;

procedure TIocpWebSocketServer.DoWebSocketConnection(
  Request: TIocpWebSocketHttpRequest; var IsAccept: Boolean);
begin
  if Assigned(FOnWebSocketConnection) then
    FOnWebSocketConnection(Self, TIocpWebSocketHttpRequest(Request), IsAccept);
end;

procedure TIocpWebSocketServer.DoWebSocketDisconnect(
  AConnection: TIocpWebSocketConnection);
begin
  if Assigned(FConnMap) and (AConnection.FSessionID <> '') then  
    FConnMap.Remove(AConnection.FSessionID);
  if Assigned(FOnWebSocketDisconnect) then
    FOnWebSocketDisconnect(Self, AConnection);
end;

procedure TIocpWebSocketServer.DoWebSocketRecvBuffer(
  AConnection: TIocpWebSocketConnection; const Frame: TIocpWebSocketDataFrame);
begin
  if Assigned(FOnWebSocketRecvBuffer) then
    FOnWebSocketRecvBuffer(Self, AConnection, Frame);
end;

procedure TIocpWebSocketServer.DoWebSocketRequest(Request: TIocpWebSocketRequest;
  Response: TIocpWebSocketResponse);
begin
  if Assigned(FOnWebSocketRequest) and Assigned(Request) then
    FOnWebSocketRequest(Self, Request, Response)
end;

function TIocpWebSocketServer.ExistSession(const SessionID: string): Boolean;
begin
  Result := FConnMap.Exists(SessionID);
end;

procedure TIocpWebSocketServer.FreeWebSocketRequest(V: TIocpWebSocketRequest);
begin
  if Assigned(V) then begin
    V.Clear;
    FWebSocketRequestPool.EnQueue(V);
  end;
end;

function TIocpWebSocketServer.GetConnectionCount: Integer;
begin
  Result := FConnMap.Count;
end;

function TIocpWebSocketServer.GetConnectionItem(
  const SessionID: string): TIocpWebSocketConnection;
var
  V: iocp.Utils.Hash.Number;
begin
  Result := nil;
  if Assigned(FConnMap) then begin
    V := FConnMap.ValueOf(SessionID);
    if V <> -1 then
      Result := TIocpWebSocketConnection(Pointer(V));
  end;
end;

function TIocpWebSocketServer.GetSessionList(List: TStrings): Integer;
var
  I: Integer;
  P: PHashItem;
begin
  Result := 0;
  if not Assigned(List) then Exit;  
  FConnMap.Lock;
  try
    for I := 0 to High(FConnMap.Buckets) do begin
      P := FConnMap.Buckets[I];
      while P <> nil do begin
        List.Add(P.Key);
        Inc(Result);
        P := P^.Next;
      end;
    end;
  finally
    FConnMap.UnLock;
  end;
end;

function TIocpWebSocketServer.GetWebSocketRequest: TIocpWebSocketRequest;
begin
  Result := TIocpWebSocketRequest(FWebSocketRequestPool.DeQueue);
  if Result = nil then
    Result := TIocpWebSocketRequest.Create(Self);
  Result.FOwner := Self;
end;

{ TIocpWebSocketConnection }

constructor TIocpWebSocketConnection.Create(AOwner: TIocpCustom);
begin
  inherited Create(AOwner);
  FSessionID := '';
  FSocketResponse := TIocpWebSocketResponse.Create;
  FSocketResponse.FConnection := Self;
end;

destructor TIocpWebSocketConnection.Destroy;
begin
  if Assigned(FSocketRequest) then begin
    TIocpWebSocketServer(Owner).FreeWebSocketRequest(FSocketRequest);
    FSocketRequest := nil;
  end;
  FreeAndNil(FSocketResponse);
  inherited Destroy;
end;

procedure TIocpWebSocketConnection.DoCleanUp;
begin
  inherited DoCleanUp;
  if (FSessionID <> '') and Assigned(Owner) then begin
    TIocpWebSocketServer(Owner).DoWebSocketDisconnect(Self);
    FSessionID := '';
  end;
  if Assigned(FSocketRequest) then begin
    TIocpWebSocketServer(Owner).FreeWebSocketRequest(FSocketRequest);
    FSocketRequest := nil;
    FSocketResponse.Clear;
  end;
end;

procedure TIocpWebSocketConnection.DoSendPing;
const
  PingMsg: Word = $0089;
begin
  Send(@PingMsg, 2, False);
end;

procedure TIocpWebSocketConnection.DoSendPong;
const
  PongMsg: Word = $008A;
begin
  Send(@PongMsg, 2, False);
end;

procedure TIocpWebSocketConnection.DoWebSocketrecvBuffer(buf: Pointer;
  len: Cardinal; ErrorCode: Integer);
var
  Frame: TIocpWebSocketDataFrame;
  I: Integer;
  P, PMax: PAnsiChar;
begin
  P := buf;
  PMax := P + len;

  while P < PMax do begin  
    Frame.SrcData := P;
    I := Frame.TranslateFrame(len);
    if I > 0 then begin
      case Frame.Opcode of
        wso_Continuous:
          begin
            // ������֡
            if FSocketRequest = nil then
              FSocketRequest := TIocpWebSocketServer(Owner).GetWebSocketRequest;
            FSocketRequest.Data.Cat(Frame.Data, Frame.DataLength);
            TIocpWebSocketServer(Owner).DoWebSocketRecvBuffer(Self, Frame);
            if Frame.FIN then begin
              FSocketRequest.DataOpcode := Frame.Opcode;
              TIocpWebSocketServer(Owner).DoWebSocketRequest(FSocketRequest, FSocketResponse);
              FSocketRequest.Data.Reset;
            end;
          end;
        wso_Close:
          begin
            // �ر�����
            CloseConnection;
            Break;
          end;
        wso_Ping:
          DoSendPong;
        wso_Pong:
          begin
            // �����һ�� Ping Pong ʱ��������10�����Ӧ������������
            if GetTimestamp - LastActivity > 10000 then
              DoSendPing;
          end
      else
        begin
          // ��������
          TIocpWebSocketServer(Owner).DoWebSocketRecvBuffer(Self, Frame);

          if FSocketRequest = nil then
            FSocketRequest := TIocpWebSocketServer(Owner).GetWebSocketRequest;
          FSocketRequest.Data.Cat(Frame.Data, Frame.DataLength);

          if Frame.FIN then begin
            FSocketRequest.DataOpcode := Frame.Opcode;
            TIocpWebSocketServer(Owner).DoWebSocketRequest(FSocketRequest, FSocketResponse);
            FSocketRequest.Data.Reset;
          end;
        end;
      end;
      Inc(P, I);
    end else begin
      CloseConnection;  // ��Ч������
      Break;
    end;
  end;
  
end;

function TIocpWebSocketConnection.GetSession: Pointer;
begin
  Result := TIocpWebSocketServer(Owner).GetSession(FSessionID);
end;

procedure TIocpWebSocketConnection.OnRecvBuffer(buf: Pointer; len: Cardinal;
  ErrorCode: Integer);
begin
  if FSessionID = '' then   
    inherited OnRecvBuffer(buf, len, ErrorCode)
  else
    DoWebSocketrecvBuffer(buf, len, ErrorCode);
end;

procedure TIocpWebSocketConnection.ReleaseClientContext;
begin
  if Assigned(Owner) then
    TIocpWebSocketServer(Owner).DoWebSocketDisconnect(Self);
  inherited ReleaseClientContext;
end;

{ TIocpWebSocketHttpRequest }

function TIocpWebSocketHttpRequest.GetIsUpgrade: Boolean;
begin
  Result := IsGet and
    (RequestVersion > hv_V1) and
    (Pos(CSUpgradeI, LowerCase(GetHeader(CSConnection))) > 0) and
    (LowerCase(GetHeader(CSUpgrade)) = CSWebScoket) and
    // ���WebSocket�汾����13��˵�����ڱ�׼��֮ǰ��Э�飬��֧��
    (StrToIntDef(string(GetHeader(CSSecWebSocketVersion)), 0) >= 13);
end;

function TIocpWebSocketHttpRequest.GetWebSocketExtensions: StringA;
begin
  Result := GetHeader(CSSecWebSocketExtensions);
end;

function TIocpWebSocketHttpRequest.GetWebSocketKey: StringA;
begin
  Result := GetHeader(CSSecWebSocketKey);
end;

function TIocpWebSocketHttpRequest.GetWebSocketOrigin: StringA;
begin
  Result := GetHeader(CSSecWebSocketOrigin);
end;

function TIocpWebSocketHttpRequest.GetWebSocketProtocol: StringA;
begin
  Result := GetHeader(CSSecWebSocketProtocol);
end;

function TIocpWebSocketHttpRequest.GetWebSocketVersion: StringA;
begin
  Result := GetHeader(CSSecWebSocketVersion);
end;

{ TIocpWebSocketHttpResponse }

function TIocpWebSocketHttpResponse.GetWebSocketAccept: StringA;
const
  MHSTR: StringA = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
var
  Key: StringA;
  Bin: TBytes;
begin
  Key := TIocpWebSocketHttpRequest(Request).WebSocketKey + MHSTR;
  Bin := SHA1Bin(Key);
  {$IFDEF UNICODE}
  Result := Soap.EncdDecd.EncodeBase64(@Bin[0], Length(Bin));
  {$ELSE}
  Result := Base64Encode(Bin[0], Length(Bin));
  {$ENDIF}
end;

procedure TIocpWebSocketHttpResponse.MakeHeaderEx(
  const Data: TStringCatHelperA);
const
  CSConnectionUpgrade: StringA    = 'Connection: Upgrade'#13#10;
  CSUpgradeWebSocket: StringA     = 'Upgrade: websocket'#13#10;
  CSSecWebSocketProtocol: StringA = 'Sec-WebSocket-Protocol: ';
  CSSecWebSocketAccept: StringA   = 'Sec-WebSocket-Accept: ';
var
  Conn: TIocpWebSocketConnection;
begin
  Conn := TIocpWebSocketConnection(Request.Connection);
  if Conn.FSessionID = '' then
    inherited MakeHeaderEx(Data)
  else begin
    Data.Cat(CSUpgradeWebSocket);
    Data.Cat(CSConnectionUpgrade);
    if Conn.FProtocol <> '' then
      Data.Cat(CSSecWebSocketProtocol).Cat(Conn.FProtocol).Cat(HTTPLineBreak);
    Data.Cat(CSSecWebSocketAccept).Cat(GetWebSocketAccept()).Cat(HTTPLineBreak);
  end;
end;

procedure TIocpWebSocketHttpResponse.ResponseWebSocket;
begin
  if (not Active) then Exit;
  ResponeCode(101);
end;

{ TIocpWebSocketRequest }

procedure TIocpWebSocketRequest.Clear;
begin
  if Assigned(FData) then begin
    if FData.Position > 1024 then  // ������ 1k �Ļ�������С�������������ֱ���ͷ�
      FreeAndNil(FData)
    else
      FData.Reset;
  end;
end;

constructor TIocpWebSocketRequest.Create(AOwner: TIocpWebSocketServer);
begin
  FOwner := AOwner;  
end;

function TIocpWebSocketRequest.DataString(ACharSet: TIocpHttpCharset): string;
begin
  if FData = nil then
    Result := ''
  else
    Result := GetDataString(ACharSet, FData.Memory, FData.Position);  
end;

destructor TIocpWebSocketRequest.Destroy;
begin
  FreeAndNil(FData);
  inherited;
end;

function TIocpWebSocketRequest.GetData: TBytesCatHelper;
begin
  if FData = nil then
    FData := TBytesCatHelper.Create(1024);
  Result := FData;
end;

function TIocpWebSocketRequest.GetDataSize: Int64;
begin
  Result := FData.Position;
end;

{ TIocpWebSocketPingThd }

procedure TIocpWebSocketPingThd.Execute;
var
  Last: Int64;
begin
  Last := GetTimestamp;
  while (not Terminated) and (not FOwner.IsDestroying) do begin
    if GetTimestamp - Last > 30000 then begin
      try
        Last := GetTimestamp;
        FOwner.DoPingClients();
      except
        FOwner.DoStateMsgE(Self, Exception(ExceptObject));
      end;
    end;
    Sleep(200);
  end;
end;

//procedure Test();
//var
//  F: TIocpWebSocketDataFrame;
//  Bytes: TBytes;
//begin
//  SetLength(Bytes, 15);
//  Bytes[0] := $89;

//  F.SrcData := @Bytes[0];
//  if F.TranslateFrame(Length(Bytes)) > 0 then begin
//    OutputDebugString(PChar(BoolToStr(F.FIN)));
//    OutputDebugString(PChar(BoolToStr(F.HasMask)));
//    OutputDebugString(PChar(IntToStr(F.RSV1)));
//    OutputDebugString(PChar(IntToStr(F.RSV2)));
//    OutputDebugString(PChar(IntToStr(F.RSV3)));
//    OutputDebugString(PChar(IntToStr(Ord(F.Opcode))));
//    OutputDebugString(PChar(IntToStr(F.DataLength)));
//    OutputDebugString(PChar(iocp.Utils.Str.BinToHex(F.Mask)));
//    OutputDebugString(PChar(F.Data));
//  end else
//    OutputDebugString('Error');
//end;

{ TIocpWebSocketResponse } 

procedure TIocpWebSocketResponse.Clear;
begin
  if Assigned(FSendBuffer) then begin
    if FSendBuffer.Position > 1024 then
      FreeAndNil(FSendBuffer)
    else
      FSendBuffer.Reset;
  end;
end;

constructor TIocpWebSocketResponse.Create;
begin
end;

destructor TIocpWebSocketResponse.Destroy;
begin
  FreeAndNil(FSendBuffer);
  inherited;
end;

function TIocpWebSocketResponse.GetSendBuffer: TBytesCatHelper;
begin
  if FSendBuffer = nil then
    FSendBuffer := TBytesCatHelper.Create(1024);
  Result := FSendBuffer;
end;

procedure TIocpWebSocketResponse.MakeData(buf: Pointer; Len: Cardinal;
  Opcode: TIocpWebSocketOpcode; FIN: Boolean);
begin
  SendBuffer.Reset;
  FSendBuffer.Cat(Byte($00));
  if FIN then
    WriteBit(FSendBuffer.Start^, 7, 1);
  if Opcode <> wso_Continuous then   
    WriteLo(FSendBuffer.Start^, Ord(Opcode));

  // д�볤��
  if Len < 126 then
    FSendBuffer.Cat(Byte(Len))
  else if Len <= $FFFF then begin
    FSendBuffer.Cat(Byte(126));
    FSendBuffer.Cat(SwapByteOrder(Word(Len)));
  end else begin
    FSendBuffer.Cat(Byte(127));
    FSendBuffer.Cat(SwapByteOrder(Int64(Len)));
  end;
  // д��Data
  if Len > 0 then
    FSendBuffer.Cat(buf, Len);
  // ����
  FConnection.Send(FSendBuffer.Memory, FSendBuffer.Position);
end;

procedure TIocpWebSocketResponse.Send(const Data: string; ACharSet: TIocpHttpCharset);
var
  SA: StringA;
  {$IFDEF UNICODE}
  {$ELSE}
  SW: StringW;
  {$ENDIF}
begin
  if Length(Data) = 0 then begin
    MakeData(nil, 0, wso_Text, True);
    Exit;  
  end;
  case ACharSet of
    hct_UTF8:
      begin
        {$IFDEF UNICODE}
        SA := iocp.Utils.Str.Utf8Encode(StringW(Data));
        MakeData(PAnsiChar(SA), Length(SA), wso_Text, True);
        {$ELSE}
        SA := AnsiToUtf8(Data);
        MakeData(PAnsiChar(SA), Length(SA), wso_Text, True);
        {$ENDIF}
      end;
    hct_UTF16:
      begin
        {$IFDEF UNICODE}
        MakeData(Pointer(Data), Length(Data) shl 1, wso_Text, True);
        {$ELSE}
        SW := StringW(Data);
        MakeData(Pointer(SW), Length(SW) shl 1, wso_Text, True);
        {$ENDIF}
      end;
  else
    begin
      {$IFDEF UNICODE}
      SA := StringA(Data);
      MakeData(PAnsiChar(SA), Length(SA), wso_Text, True);
      {$ELSE}
      MakeData(PAnsiChar(Data), Length(Data), wso_Text, True);
      {$ENDIF}
    end;
  end;
end;

procedure TIocpWebSocketResponse.Send(const buf: Pointer; const len: Cardinal);
begin
  MakeData(buf, Len, wso_Binary, True);
end;

procedure TIocpWebSocketResponse.Send(const Data: TBytes);
begin
  if Length(Data) > 0 then  
    MakeData(@Data[0], Length(Data), wso_Binary, True)
  else
    MakeData(nil, 0, wso_Binary, True);
end;

procedure TIocpWebSocketResponse.Send(buf: PChar; len: Cardinal;
  ACharSet: TIocpHttpCharset);
var
  SA: StringA;
  {$IFDEF UNICODE}
  {$ELSE}
  SW: StringW;
  {$ENDIF}
begin
  if (len = 0) or (buf = nil) then begin
    MakeData(nil, 0, wso_Text, True);
    Exit;
  end;
  case ACharSet of
    hct_UTF8:
      begin
        {$IFDEF UNICODE}
        SA := iocp.Utils.Str.Utf8Encode(buf, len);
        MakeData(PAnsiChar(SA), Length(SA), wso_Text, True);
        {$ELSE}
        SA := AnsiToUtf8(PCharAToStringW(buf, len));
        MakeData(PAnsiChar(SA), Length(SA), wso_Text, True);
        {$ENDIF}
      end;
    hct_UTF16:
      begin
        {$IFDEF UNICODE}
        MakeData(buf, len shl 1, wso_Text, True);
        {$ELSE}
        SW := PCharAToStringW(buf, len);
        MakeData(Pointer(SW), Length(SW) shl 1, wso_Text, True);
        {$ENDIF}
      end;
  else
    begin
      {$IFDEF UNICODE}
      SA := PCharWToString(buf, len);
      MakeData(PAnsiChar(SA), Length(SA), wso_Text, True);
      {$ELSE}
      MakeData(buf, len, wso_Text, True);
      {$ENDIF}
    end;
  end;
end;

procedure TIocpWebSocketResponse.Send(Stream: TStream; Opcode: TIocpWebSocketOpcode);
var
  L: Int64;
  Buf: array [0..4095] of Byte;
  I, J: Integer;
begin
  L := Stream.Size - Stream.Position;
  J := 0;
  while L > 0 do begin
    I := Stream.Read(Buf, SizeOf(Buf));
    if I > 0 then begin
      if J = 0 then
        MakeData(@Buf[0], I, Opcode, False)  // ��һ֡������������
      else
        MakeData(@Buf[0], I, wso_Continuous, False);
      Inc(J);
      Dec(L, I);
    end else
      Break;
  end;
  // ���ͽ���֡
  MakeData(nil, 0, wso_Continuous, True);
end; 

initialization
  Workers := TIocpTask.GetInstance;
  //Test();

finalization
  Workers := nil;
  
end.
