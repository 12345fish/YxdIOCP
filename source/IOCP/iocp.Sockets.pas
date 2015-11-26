{*******************************************************}
{                                                       }
{       IOCP Sockets ������Ԫ   (����DIOCP�޸İ汾)     }
{                                                       }
{       ��Ȩ���� (C) 2015 YangYxd                       }
{                                                       }
{*******************************************************}
{
  ����Ԫ����DIOCP�޸ģ��󲿷ִ��붼����ͬ�ġ��Ƴ�����־
  ϵͳ������ͳһ��StateMsg�¼����ϲ������Ϣ��

  ��лԭDIOCP���ߣ�����ң�����Դ����ԭ���߽��ƣ��������
  �⸴�ơ��޸ġ�ʹ�ã��緢��BUG�뱨������ǡ�
  Ϊ�˳�����Դ�����һ���޸İ汾������ϣ��Ҳ�ܿ�Դ��

  ʹ��ע�⣺ ����int64���ͱ�ʾ��ʱ��㣬����ͨ��
  TimestampToDatetime ��������ת��Ϊ TDateTime.
}

unit iocp.Sockets;

{$I 'iocp.inc'}
// �����־��¼���뿪��
{$DEFINE WRITE_LOG}

// �Ƿ��������ĵ�����Ϣ�������󽫽��Ͳ�������

{.$DEFINE DEBUGINFO}

// ��������ʱ��ʹ�� Iocp �����SendBuffer�ڴ��

{$DEFINE UseSendMemPool}

interface

uses
  iocp.Utils.Hash, iocp.Task, iocp.Utils.MemPool,
  iocp.Sockets.Utils, iocp.Core.Engine, iocp.Res, iocp.RawSockets,
  iocp.Utils.Queues, iocp.Utils.ObjectPool,
  WinSock, iocp.Winapi.WinSock,
  {$IFDEF UNICODE}Generics.Collections, {$ELSE}Contnrs, {$ENDIF}
  SyncObjs, Windows, Classes, SysUtils;

const
  LF = #10;
  CR = #13;
  EOL = #13#10;

type
  /// <summary>
  /// �����ͷŷ�ʽ
  /// </summary>
  TDataReleaseType = (
    dtNone {���Զ��ͷ�},
    dtFreeMem {����FreeMem�ͷ��ڴ�},
    dtDispose {����Dispose�ͷ����ݣ�������New���������},
    dtMemPool {ʹ���ڴ��});

type
  TIocpCustom = class;
  TIocpRecvRequest = class;
  TIocpSendRequest = class;
  TIocpCustomContext = class;
  TIocpDataMonitor = class;
  TIocpAcceptorMgr = class;
  TIocpAcceptExRequest = class;
  TIocpBlockSocketStream = class;

  TIocpSendRequestClass = class of TIocpSendRequest;
  TIocpContextClass = class of TIocpCustomContext;

  TIocpStateMsgType = (
    iocp_mt_Info {��Ϣ},
    iocp_mt_Debug {������Ϣ},
    iocp_mt_Warning {����},
    iocp_mt_Error {����});

  TNotifyContextEvent = procedure(const Context: TIocpCustomContext) of object;
  TOnStateMsgEvent = procedure(Sender: TObject; MsgType: TIocpStateMsgType;
    const Msg: string) of object;
  TOnContextError = procedure(const Context: TIocpCustomContext; ErrorCode: Integer) of object;
  TOnBufferReceived = procedure(const Context: TIocpCustomContext; buf: Pointer;
    len: Cardinal; ErrorCode: Integer) of object;
  TOnDataRequestCompleted = procedure(const ClientContext: TIocpCustomContext;
    Request: TIocpRequest) of object;
  TOnSendRequestResponse = procedure(Context: TIocpCustomContext;
    Request: TIocpSendRequest) of object;

  /// <summary>
  /// �ͻ�(Client)����
  /// </summary>
  TIocpCustomContext = class(TObject)
  private
    FPrev: TIocpCustomContext;
    FNext: TIocpCustomContext;
    FOwner: TIocpCustom;
    FActive: Boolean;
    FSending: Boolean;
    FAlive: Boolean;  // �Ƿ�����ʹ��
    FRequestDisconnect: Boolean;

    FRawSocket: TRawSocket;
    FSocketHandle: TSocket;
    FRecvRequest: TIocpRecvRequest;
    FSendRequest: TIocpSendRequest;
    FSendRequestList: TIocpRequestLinkList;

    FData: Pointer;
    FOnConnectedEvent: TNotifyContextEvent;
    FOnSocketStateChanged: TNotifyEvent;

    FLastActive: Int64;
    FHandle: Cardinal;
    FSocketState: TSocketState;
    FContextLocker: TIocpLocker;
    FLastErrorCode: Integer;

    FRefCount: Integer;
    // ��󽻻���ʱ��
    FLastActivity: Int64;

    function GetSocketHandle: TSocket;

    // �ڲ���������
    function InnerSendData(buf: Pointer; len: Cardinal;
      pvBufReleaseType: TDataReleaseType; pvTag: Integer = 0;
      pvTagData: Pointer = nil): Boolean;
  private
    function IncReferenceCounter(pvObj: TObject; const pvDebugInfo: string = ''): Boolean;
    function DecReferenceCounter(pvObj: TObject; const pvDebugInfo: string = ''): Integer;
    // �ͷſͻ�����
    procedure ReleaseClientContext(); virtual;
    /// <summary>
    /// ���������FRefCount��1��������RequestDisconnect�Ͽ�����, Ȼ����Disconnect��־
    /// </summary>
    procedure DecReferenceCounterAndRequestDisconnect(pvObj: TObject;
      const pvDebugInfo: string = '');
    /// <example>
    /// �ͷŴ����Ͷ����еķ�������(TSendRequest)
    /// </example>
    procedure CheckReleaseRes;
    /// <summary>
    /// ��Ӧ RecvRequest
    /// </summary>
    procedure DoReceiveData;
    /// <summary>
    /// ��Ӧ SendRequest
    /// </summary>
    procedure DoSendRequestCompleted(pvRequest: TIocpSendRequest);
    /// <summary>
    /// ��鲢Ͷ����һ����������
    /// </summary>
    function CheckNextSendRequest: Boolean;
    /// <summary>
    /// �Ͽ���������
    /// </summary>
    procedure RequestDisconnect(pvObj: TObject = nil; const pvDebugInfo: string = '');
    function GetIsDisconnect: Boolean;
  protected
    procedure OnRecvBuffer(buf: Pointer; len: Cardinal; ErrorCode: Integer); virtual;
    procedure OnDisconnected; virtual;
    procedure OnConnected; virtual;
    procedure DoCleanUp; virtual;
    procedure DoConnected;
    procedure DoDisconnect;
    procedure DoError(ErrorCode: Integer);
    procedure CreateSocket(IsOverlapped: Boolean); virtual;
    function GetSendRequest: TIocpSendRequest; virtual;

    /// <summary>
    /// Ͷ�ݵķ���������Ӧʱִ�У�һ��Ӧ������ִ�У�Errcode <> 0Ҳ����Ӧ
    /// </summary>
    procedure DoSendRequestRespnonse(pvRequest: TIocpSendRequest); virtual;

    /// <summary>
    /// �����������
    /// </summary>
    procedure PostWSARecvRequest(); virtual;
    procedure PostNextSendRequest; virtual;
    procedure PostWSACloseRequest(); virtual;
    procedure InnerCloseContext;

    /// <summary>
    /// 1. Ͷ�ݷ������󵽶�����, ������Ͷ����������� False
    /// 2. ��� sending ��־, ��� sending �� False �ſ�ʼ
    /// </summary>
    function InnerPostSendRequestAndCheckStart(pvSendRequest:TIocpSendRequest): Boolean;

    procedure SetSocketState(pvState: TSocketState); virtual;
    function LockContext(pvObj: TObject; const pvDebugInfo: string): Boolean;
    procedure UnLockContext(pvObj: TObject; const pvDebugInfo: string);
  public
    constructor Create(AOwner: TIocpCustom); virtual;
    destructor Destroy; override;

    procedure Lock;
    procedure UnLock;

    /// <summary>
    /// �Ͽ�����
    /// </summary>
    procedure Disconnect; virtual;
    procedure Close; virtual;

    /// <summary>
    /// �������� (�첽) , �ɹ����� True.
    /// </summary>
    function Send(buf: Pointer; len: Cardinal; CopyBuf: Boolean = True): Boolean; overload; inline;
    function Send(buf: Pointer; len: Cardinal; BufReleaseType: TDataReleaseType): Boolean; overload; inline;
    function Send(const Data: AnsiString): Boolean; overload;
    function Send(const Data: WideString): Boolean; overload;
    {$IFDEF UNICODE}
    function Send(const Data: UnicodeString): Boolean; overload;
    {$ENDIF}
    function Send(Stream: TStream): Boolean; overload;
    function Send(Stream: TStream; ASize: Int64): Boolean; overload;

    /// <summary>
    /// Ͷ��һ����������Iocp������, �ɹ����� True.
    /// ����������, ������ DoSendRequestCompleted ����
    /// </summary>
    function PostWSASendRequest(buf: Pointer; len: Cardinal;
      pvCopyBuf: Boolean = True): Boolean; overload;
    /// <summary>
    /// Ͷ��һ����������Iocp������, �ɹ����� True.
    /// ����������, ������ DoSendRequestCompleted ����
    /// </summary>
    function PostWSASendRequest(buf: Pointer; len: Cardinal;
      pvBufReleaseType: TDataReleaseType; pvTag: Integer = 0;
      pvTagData: Pointer = nil): Boolean; overload;

    /// <summary>
    /// ���÷��Ͷ������޴�С
    /// </summary>
    procedure SetMaxSendingQueueSize(pvSize: Integer);

    property Active: Boolean read FActive;
    property Owner: TIocpCustom read FOwner;
    property Socket: TRawSocket read FRawSocket;
    property SocketHandle: TSocket read GetSocketHandle;
    property SocketState: TSocketState read FSocketState;
    property IsDisconnecting: Boolean read GetIsDisconnect;

    /// <summary>
    /// ��󽻻����ݵ�ʱ��
    /// </summary>
    property LastActive: Int64 read FLastActive;
    // ��������
    property Data: Pointer read FData write FData;

    property Prev: TIocpCustomContext read FPrev;
    property Next: TIocpCustomContext read FNext;
    // ��󽻻�ʱ��
    property LastActivity: Int64 read FLastActivity write FLastActivity;
    // ���Ӿ���������첽����ʱʶ������
    property Handle: Cardinal read FHandle;
    /// <summary>
    /// ������ɴ������¼�
    /// </summary>
    property OnConnectedEvent: TNotifyContextEvent read FOnConnectedEvent write FOnConnectedEvent;
    /// <summary>
    /// Socket״̬�ı䴥�����¼�
    /// </summary>
    property OnSocketStateChanged: TNotifyEvent read FOnSocketStateChanged write FOnSocketStateChanged;
  end;

  TIocpBase = class(TComponent)
  private
    FActive: Boolean;
    FIocpEngine: TIocpEngine;
    FDataMoniter: TIocpDataMonitor;
    FLocker: TIocpLocker;
    FMemPool: TIocpMemPool;
    FIsDestroying: Boolean;
    FWSARecvBufferSize: Cardinal;
    FWSASendBufferSize: Cardinal;
    FBindAddr: string;

    FOnSendRequestResponse: TOnSendRequestResponse;
    FOnStateMsg: TOnStateMsgEvent;

    function GetWorkerCount: Integer;
    function GetMaxWorkerCount: Integer;
    procedure SetBindAddr(const Value: string);
    procedure SetMaxWorkerCount(const Value: Integer);
    procedure SetWorkerCount(const Value: Integer);
    procedure SetWSARecvBufferSize(const Value: Cardinal);
    procedure SetWSASendBufferSize(const Value: Cardinal);
  protected
    FContextClass: TIocpContextClass;
    FSendRequestClass: TIocpSendRequestClass;
    procedure SetName(const NewName: TComponentName); override;
    procedure SetActive(const Value: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function PopMem: Pointer;
    procedure PushMem(const V: Pointer);

    /// <summary>
    /// �������ݼ������ʵ��
    /// </summary>
    procedure CreateDataMonitor;

    /// <summary>
    /// ֹͣIOCP�̣߳��ȴ������߳��ͷ�
    /// </summary>
    procedure Close; virtual; abstract;

    /// <summary>
    /// ��ʼ����
    /// </summary>
    procedure Open; virtual; abstract;

    /// <summary>
    /// �Ƿ������ͷ�
    /// </summary>
    function IsDestroying: Boolean;

    // ״̬��Ϣ
    procedure DoStateMsg(Sender: TObject; MsgType: TIocpStateMsgType;
      const Msg: string);
    // ״̬��Ϣ
    procedure DoStateMsgD(Sender: TObject; const Msg: string); overload;
    // ״̬��Ϣ
    procedure DoStateMsgD(Sender: TObject; const MsgFormat: string; const Params: array of const); overload;
    // ״̬��Ϣ
    procedure DoStateMsgE(Sender: TObject; const Msg: string); overload;
    // ״̬��Ϣ
    procedure DoStateMsgE(Sender: TObject; E: Exception); overload;
    // ״̬��Ϣ
    procedure DoStateMsgE(Sender: TObject; const MsgFormat: string; E: Exception); overload;
    // ״̬��Ϣ
    procedure DoStateMsgE(Sender: TObject; const MsgFormat: string; const Params: array of const); overload;

    property Active: Boolean read FActive write SetActive;
    /// <summary>
    /// ��������������С(Ĭ��4k)
    /// </summary>
    property RecvBufferSize: Cardinal read FWSARecvBufferSize write SetWSARecvBufferSize;
    /// <summary>
    /// ���η�����������ֽ��� (Ĭ��8k)
    /// </summary>
    property SendBufferSize: Cardinal read FWSASendBufferSize write SetWSASendBufferSize;
    /// <summary>
    /// �����߳�����
    /// </summary>
    property WorkerCount: Integer read GetWorkerCount write SetWorkerCount;
    /// <summary>
    /// ������߳�����
    /// </summary>
    property MaxWorkerCount: Integer read GetMaxWorkerCount write SetMaxWorkerCount;

    property Locker: TIocpLocker read FLocker;
    /// <summary>
    /// ״̬������
    /// </summary>
    property Moniter: TIocpDataMonitor read FDataMoniter;
    /// <summary>
    /// IOCP����
    /// </summary>
    property Engine: TIocpEngine read FIocpEngine;
    /// <summary>
    /// �󶨵�ַ
    /// </summary>
    property BindAddr: string read FBindAddr write SetBindAddr;
    /// <summary>
    /// ��һ���첽����������Ӧʱ����
    /// </summary>
    property OnSendRequestResponse: TOnSendRequestResponse read FOnSendRequestResponse write FOnSendRequestResponse;
    /// <summary>
    /// ״̬��Ϣ����ӿ�
    /// </summary>
    property OnStateInfo: TOnStateMsgEvent read FOnStateMsg write FOnStateMsg;
  end;

  TIocpCustom = class(TIocpBase)
  private
    FOnlineContextList: TYXDHashMapLinkTable;
    FSendRequestPool: TBaseQueue;

    FContextCounter: Integer;

    FOnReceivedBuffer: TOnBufferReceived;
    FOnContextConnected: TNotifyContextEvent;
    FOnContextDisconnected: TNotifyContextEvent;
    FOnContextError: TOnContextError;

    function GetOnlineContextCount: Integer;
    function HashItemToContext(Item: PHashMapLinkItem): TIocpCustomContext; inline;
  protected
    function RequestContextHandle: Integer;
    /// <summary>
    /// ��������
    /// </summary>
    procedure DoReceiveData(const pvContext: TIocpCustomContext; pvRequest: TIocpRecvRequest);

    procedure DoClientContextError(const pvClientContext: TIocpCustomContext; pvErrorCode: Integer);
    /// <summary>
    ///  ��ӵ������б���
    /// </summary>
    procedure AddToOnlineList(const pvObject: TIocpCustomContext);
    /// <summary>
    /// �������б����Ƴ�
    /// </summary>
    procedure RemoveFromOnlineList(const pvObject: TIocpCustomContext); virtual;

    procedure DoAcceptExResponse(pvRequest: TIocpAcceptExRequest); virtual;

    /// <summary>
    /// ��ȡһ��SendRequest����ʵ�����Ǵӳ��е���
    /// </summary>
    function GetSendRequest: TIocpSendRequest;
    /// <summary>
    /// �ͷ�SendRequest�����س���
    /// </summary>
    function ReleaseSendRequest(pvObject: TIocpSendRequest): Boolean;
    /// <summary>
    /// �ȴ��������ӹر�
    /// </summary>
    function WaitForContext(pvTimeOut: Cardinal = 30000): Boolean;

    /// <summary>
    /// ����һ������ʵ��
    /// ͨ��ע���ContextClass���д���ʵ��
    /// </summary>
    function CreateContext: TIocpCustomContext; virtual;
    procedure OnCreateContext(const Context: TIocpCustomContext); virtual;
    /// <summary>
    /// �ͷ����Ӷ��󣬹黹�������
    /// </summary>
    function ReleaseClientContext(const pvObject: TIocpCustomContext): Boolean; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    /// <summary>
    /// ֹͣIOCP�̣߳��ȴ������߳��ͷ�
    /// </summary>
    procedure Close; override;

    /// <summary>
    /// ����Ͽ��������ӣ������̷��ء�
    /// </summary>
    procedure DisconnectAll;

    /// <summary>
    /// ��ʼ����
    /// </summary>
    procedure Open; override;

    /// <summary>
    /// ��ȡһ�����Ӷ�������������û�У���ᴴ��һ���µ�ʵ��
    /// </summary>
    function GetClientContext: TIocpCustomContext; virtual;

    /// <summary>
    /// ��ȡ���߿ͻ��б�
    /// </summary>
    procedure GetOnlineContextList(pvList: TList);

    /// <summary>
    /// ���ͻ����Ӷ����Ƿ���Ч
    /// </summary>
    function CheckClientContextValid(const ClientContext: TIocpCustomContext): Boolean;

    /// <summary>
    /// ��ǰ������
    /// </summary>
    property OnlineContextCount: Integer read GetOnlineContextCount;
    /// <summary>
    /// ������Ͷ�������Iocp�����߳��еĴ����¼�
    /// </summary>
    property OnContextError: TOnContextError read FOnContextError write FOnContextError;
    /// <summary>
    /// �ͻ����Ӻ���յ�����ʱ�������¼�����Iocp�����̴߳���
    /// </summary>
    property OnDataReceived: TOnBufferReceived read FOnReceivedBuffer write FOnReceivedBuffer;
    /// <summary>
    /// �����ӽ����ɹ�ʱ�����¼�
    /// </summary>
    property OnContextConnected: TNotifyContextEvent read FOnContextConnected write FOnContextConnected;
    /// <summary>
    /// �����ӶϿ�ʱ�����¼�
    /// </summary>
    property OnContextDisconnected: TNotifyContextEvent read FOnContextDisconnected write FOnContextDisconnected;
  end;

  /// <summary>
  /// ���ݽ�������
  /// </summary>
  TIocpRecvRequest = class(TIocpRequest)
  private
    FOwner: TIocpCustom;
    FContext: TIocpCustomContext;
    FRecvBuffer: TWsaBuf;
    FInnerBuffer: TWsaBuf;
    FRecvdFlag: Cardinal;
  protected
    function PostRequest: Boolean; overload;
    function PostRequest(pvBuffer: PAnsiChar; len: Cardinal): Boolean; overload;
    procedure HandleResponse; override;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Clear;
    property Owner: TIocpCustom read FOwner;
    property Context: TIocpCustomContext read FContext;
  end;

  /// <summary>
  /// ������������
  /// </summary>
  TIocpSendRequest = class(TIocpRequest)
  private
    FOwner: TIocpCustom;
    FContext: TIocpCustomContext;
    //FNext: TIocpSendRequest;
    FIsBusying: Boolean;
    FAlive: Boolean;
    FBuf: Pointer;
    FLen: Cardinal;
    FSendBufferReleaseType: TDataReleaseType;
    FSendBuf: TWsaBuf;
    FBytesSize: Cardinal;
    FOnDataRequestCompleted: TOnDataRequestCompleted;
    procedure CheckClearSendBuffer;
  protected
    // post send a block
    function ExecuteSend: Boolean; virtual;
    procedure UnBindingSendBuffer;
    function InnerPostRequest(buf: Pointer; len: Cardinal): Boolean;

    procedure HandleResponse; override;
    procedure ResponseDone; override;

    procedure DoCleanUp; virtual;
    procedure SetBuffer(buf: Pointer; len: Cardinal; pvCopyBuf: Boolean = True);overload;
    procedure SetBuffer(buf: Pointer; len: Cardinal; pvBufReleaseType: TDataReleaseType); overload;
  public
    constructor Create; override;
    destructor Destroy; override;
    function GetStateInfo: string; override;

    property IsBusying: Boolean read FIsBusying;
    property Context: TIocpCustomContext read FContext;
    property Owner: TIocpCustom read FOwner;
    property OnDataRequestCompleted: TOnDataRequestCompleted read FOnDataRequestCompleted write FOnDataRequestCompleted;
  end;

  /// <summary>
  /// IO��������
  /// </summary>
  TIocpConnectExRequest = class(TIocpRequest)
  private
    FContext: TIocpCustomContext;
    FBytesSent: Cardinal;
  public
    constructor Create(const AContext: TIocpCustomContext); reintroduce;
    destructor Destroy; override;
    function PostRequest(const Host: string; Port: Word): Boolean;
    property Context: TIocpCustomContext read FContext;
  end;

  /// <summary>
  /// ������������
  /// </summary>
  TIocpAcceptExRequest = class(TIocpRequest)
  private
    FOwner: TIocpCustom;
    FContext: TIocpCustomContext;
    FAcceptorMgr: TIocpAcceptorMgr;
    /// <summary>
    ///   acceptEx lpOutBuffer[in]
    ///     A pointer to a buffer that receives the first block of data sent on a new connection,
    ///       the local address of the server, and the remote address of the client.
    ///       The receive data is written to the first part of the buffer starting at offset zero,
    ///       while the addresses are written to the latter part of the buffer.
    ///       This parameter must be specified.
    /// </summary>
    FAcceptBuffer: array [0.. (SizeOf(TSockAddrIn) + 16) * 2 - 1] of byte;
    FOnAcceptedEx: TNotifyEvent;
    // get socket peer info on acceptEx reponse
    procedure getPeerInfo;
  protected
    procedure HandleResponse; override;
    procedure ResponseDone; override;
    function PostRequest: Boolean;
  public
    constructor Create(AOwner: TIocpCustom); reintroduce;
    property OnAcceptedEx: TNotifyEvent read FOnAcceptedEx write FOnAcceptedEx;
  end;

  /// <summary>
  /// ����������ܹ�����
  /// </summary>
  TIocpAcceptorMgr = class(TObject)
  private
    FOwner: TIocpCustom;
    FListenSocket: TRawSocket;
    FList: TList;
    FLocker: TIocpLocker;
    FMaxRequest: Integer;
    FMinRequest: Integer;
    FAcceptExRequestPool: TBaseQueue;
  public
    constructor Create(AOwner: TIocpCustom; AListenSocket: TRawSocket);
    destructor Destroy; override;
    procedure Release(Request: TIocpAcceptExRequest);
    procedure Remove(Request: TIocpAcceptExRequest);
    procedure Check(const Context: TIocpCustomContext);
    /// <summary>
    /// ����Ƿ���ҪͶ��AcceptEx
    /// </summary>
    procedure CheckPostRequest;
    procedure ReleaseRequestObject(pvRequest: TIocpAcceptExRequest);
    function GetRequestObject: TIocpAcceptExRequest;
    /// <summary>
    /// �ȴ��������ӹر�
    /// </summary>
    function WaitForCancel(pvTimeOut: Cardinal): Boolean;
    property MaxRequest: Integer read FMaxRequest write FMaxRequest;
    property MinRequest: Integer read FMinRequest write FMinRequest;
  end;

  /// <summary>
  /// ����ʽTCP�ͻ���
  /// </summary>
  TIocpCustomBlockTcpSocket = class(TComponent)
  private
    FActive: Boolean;
    FRawSocket: TRawSocket;
    FReadTimeOut: Integer;
    FConnectTimeOut: Integer;
    FErrorCode: Integer;
    FHost: string;
    FPort: Word;
    FStream: TIocpBlockSocketStream;
    FBuffer: TMemoryStream;
    FRecvBufferSize: Integer;
    procedure SetActive(const Value: Boolean);
    procedure CheckSocketResult(pvSocketResult:Integer);
    function IsConnected: Boolean;
    function GetErrorCode: Integer;
    function GetRecvStream: TStream;
    procedure SetReadTimeOut(const Value: Integer);
    function GetRecvBufferIsEmpty: Boolean;
    function GetRecvBufferSize: Cardinal;
  protected
    procedure CreateSocket; virtual;
    procedure RaiseLastOSError(RaiseErr: Boolean = True);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Connect(RaiseError: Boolean = True): Boolean; overload; inline;
    function Connect(ATimeOut: Integer; RaiseError: Boolean = True): Boolean; overload;
    function Connect(const RemoteHost: string; RemotePort: Word; ATimeOut: Integer = 0): Boolean; overload;
    procedure Disconnect;
    procedure Open;
    procedure Close;
    function SetKeepAlive(pvKeepAliveTime: Integer = 5000): Boolean;
    class function IsIP(v: PAnsiChar): Longint;
    function DomainNameToAddr(const host: string): string;
    function Recv(Len: Integer = -1): AnsiString; overload;
    function Recv(buf: Pointer; len: Cardinal): Cardinal; overload;
    function Seek(Len: Integer = -1): Boolean;
    function Send(buf: Pointer; len: Cardinal): Cardinal; overload; inline;
    function Send(const Data: WideString): Cardinal; overload;
    function Send(const Data: AnsiString): Cardinal; overload;
    {$IFDEF UNICODE}
    function Send(const Data: UnicodeString): Cardinal; overload;
    {$ENDIF}
    procedure Send(Stream: TStream; SendSize: Integer = -1); overload;
    function ReadChar: Char;
    function ReadInteger: Integer;
    function ReadWord: Word;
    function ReadDouble: Double;
    function ReadInt64: Int64;
    function ReadSmallInt: SmallInt;
    function ReadString(const ABytes: Integer = -1): string;
    /// <summary>
    /// �������ݵ�����
    /// <param name="WaitRecvLen">�ȴ�����ָ�����ȵ�����ֱ�����ӶϿ�(Len����1ʱ��Ч��</param>
    /// </summary>
    function ReadStream(OutStream: TStream; Len: Integer; WaitRecvLen: Boolean = False): Integer;
    function ReadBytes(var Buffer: TBytes; AByteCount: Integer; AAppend: Boolean = True): Integer;
    function RecvBuffer(buf: Pointer; len: cardinal): Integer;
    function SendBuffer(buf: Pointer; len: cardinal): Integer;
    property Active: Boolean read FActive write SetActive;
    property Socket: TRawSocket read FRawSocket;
    property Connected: Boolean read IsConnected;
    property ErrorCode: Integer read GetErrorCode;
    property RecvStream: TStream read GetRecvStream;
    property RecvBufferSize: Cardinal read GetRecvBufferSize;
    property RecvBufferIsEmpty: Boolean read GetRecvBufferIsEmpty;
  published
    property RemoteHost: string read FHost write FHost;
    property RemotePort: Word read FPort write FPort;
    property ReadTimeOut: Integer read FReadTimeOut write SetReadTimeOut;
    property ConnectTimeOut: Integer read FConnectTimeOut write FConnectTimeOut default -1;
  end;

  /// <summary>
  /// ����ʽTCP�ͻ���
  /// </summary>
  TIocpCustomBlockUdpSocket = class(TIocpCustomBlockTcpSocket)
  protected
    procedure CreateSocket; override;
  public
    function Send(buf: Pointer; len: Cardinal; const Addr: string; Port: Word): Cardinal; overload;
    {$IFDEF UNICODE}
    function Send(const Data: UnicodeString; const Addr: string; Port: Word): Cardinal; overload;
    {$ENDIF}
    function Send(const Data: WideString; const Addr: string; Port: Word): Cardinal; overload;
    function Send(const Data: AnsiString; const Addr: string; Port: Word): Cardinal; overload;
  end;
  
  /// <summary>
  /// ����ʽ�ͻ���Socket��
  /// </summary>
  TIocpBlockSocketStream = class(TStream)
  protected
    FSocket: TIocpCustomBlockTcpSocket;
    FReadTimeOut: Integer;
    procedure SetSize(NewSize: Longint); override;
    procedure SetSize(const NewSize: Int64); override;
  public
    constructor Create(ASocket: TIocpCustomBlockTcpSocket);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  /// <summary>
  /// IOCP ���ݼ�����
  /// </summary>
  TIocpDataMonitor = class(TObject)
  private
    FLocker: TCriticalSection;
    FSentSize:Int64;
    FRecvSize:Int64;
    FPostWSASendSize: Int64;

    FHandleCreateCounter:Integer;
    FHandleDestroyCounter:Integer;

    FContextCreateCounter: Integer;
    FContextOutCounter:Integer;
    FContextReturnCounter:Integer;
    FAcceptExObjectCounter: Integer;

    FPushSendQueueCounter: Integer;
    FResponseSendObjectCounter:Integer;

    FPostWSASendCounter:Integer;
    FResponseWSASendCounter:Integer;

    FPostWSARecvCounter:Integer;
    FResponseWSARecvCounter:Integer;

    FPostWSAAcceptExCounter:Integer;
    FResponseWSAAcceptExCounter:Integer;

    FPostSendObjectCounter: Integer;
    FSendRequestAbortCounter: Integer;
    FSendRequestCreateCounter: Integer;
    FSendRequestOutCounter: Integer;
    FSendRequestReturnCounter: Integer;
  protected
    procedure incSentSize(pvSize:Cardinal);
    procedure incPostWSASendSize(pvSize:Cardinal);

    procedure incPostWSASendCounter();
    procedure incResponseWSASendCounter;

    procedure incPostWSARecvCounter();
    procedure incResponseWSARecvCounter;

    procedure IncAcceptExObjectCounter;
    procedure incPushSendQueueCounter;
    procedure incPostSendObjectCounter();
    procedure incResponseSendObjectCounter();
    procedure incHandleCreateCounter;
    procedure incHandleDestroyCounter;
  public
    constructor Create;
    destructor Destroy; override;
    procedure incRecvdSize(pvSize:Cardinal);

    procedure Clear;

    property ContextCreateCounter: Integer read FContextCreateCounter;
    property ContextOutCounter: Integer read FContextOutCounter;
    property ContextReturnCounter: Integer read FContextReturnCounter;

    property PushSendQueueCounter: Integer read FPushSendQueueCounter;
    property PostSendObjectCounter: Integer read FPostSendObjectCounter;
    property ResponseSendObjectCounter: Integer read FResponseSendObjectCounter;

    property PostWSAAcceptExCounter: Integer read FPostWSAAcceptExCounter;
    property PostWSARecvCounter: Integer read FPostWSARecvCounter;
    property PostWSASendCounter: Integer read FPostWSASendCounter;


    property PostWSASendSize: Int64 read FPostWSASendSize;
    property RecvSize: Int64 read FRecvSize;

    property AcceptExObjectCounter: Integer read FAcceptExObjectCounter;
    property HandleCreateCounter: Integer read FHandleCreateCounter;
    property HandleDestroyCounter: Integer read FHandleDestroyCounter;
    property ResponseWSAAcceptExCounter: Integer read FResponseWSAAcceptExCounter;
    property ResponseWSARecvCounter: Integer read FResponseWSARecvCounter;
    property ResponseWSASendCounter: Integer read FResponseWSASendCounter;
    property SendRequestAbortCounter: Integer read FSendRequestAbortCounter;
    property SendRequestCreateCounter: Integer read FSendRequestCreateCounter;
    property SendRequestOutCounter: Integer read FSendRequestOutCounter;
    property SendRequestReturnCounter: Integer read FSendRequestReturnCounter;
    property SentSize: Int64 read FSentSize;
  end;

type
  TIocpClientContext = class;

  TOnContextAcceptEvent = procedure(Socket: THandle; const Addr: string; Port: Word;
      var AllowAccept: Boolean) of object;

  /// <summary>
  /// Զ��������, ��Ӧ�ͻ��˵�һ������
  /// </summary>
  TIocpClientContext = class(TIocpCustomContext)
  private
    FRemotePort: Word;
    FRemoteAddr: string;
    function GetPeerAddr: Cardinal;
    function GetBindIP: string;
    function GetBindPort: Word;
    {$IFDEF SOCKET_REUSE}
    /// <summary>
    /// �׽�������ʱʹ�ã�������ӦDisconnectEx�����¼�
    /// </summary>
    procedure OnDisconnectExResponse(pvObject:TObject);
    {$ENDIF}
  protected
    procedure ReleaseClientContext(); override;
  public
    constructor Create(AOwner: TIocpCustom); override;
    destructor Destroy; override;

    procedure Disconnect; override;

    /// <summary>
    /// �ر�����, �첽ģʽ����֤���ڷ��͵����ݿ��Է������
    /// </summary>
    procedure CloseConnection;

    property RemoteAddr: string read FRemoteAddr;
    property RemotePort: Word read FRemotePort;
    property PeerPort: Word read FRemotePort;
    property PeerAddr: Cardinal read GetPeerAddr;
    property BindIP: string read GetBindIP;
    property BindPort: Word read GetBindPort;
  end;

  /// <summary>
  /// IOCP �����
  /// </summary>
  TIocpCustomTcpServer = class(TIocpCustom)
  private
    FListenSocket: TRawSocket;
    FKeepAlive: Boolean;
    FPort: Word;
    FMaxSendingQueueSize: Integer;
    FKickOutInterval: Integer;
    FIocpAcceptorMgr: TIocpAcceptorMgr;
    FContextPool: TBaseQueue;
    FTimeOutClearThd: TThread;

    FOnContextAccept: TOnContextAcceptEvent;
    function GetClientCount: Integer;
  protected
    procedure CreateSocket; virtual;
    procedure DoCleaerTimeOutConnection();
    /// <summary>
    /// ��Ͷ�ݵ�AcceptEx������Ӧʱ�е���
    /// </summary>
    procedure DoAcceptExResponse(pvRequest: TIocpAcceptExRequest); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Open; override;
    procedure Close; override;
    function GetStateInfo: string;

    function CreateContext: TIocpCustomContext; override;

    function GetClientContext: TIocpCustomContext; override;
    function ReleaseClientContext(const pvObject: TIocpCustomContext): Boolean; override;

    /// <summary>
    /// ��������ÿ��������������Ͷ��У������������ٽ���Ͷ��
    /// </summary>
    procedure SetMaxSendingQueueSize(pvSize: Integer);

    /// <summary>
    /// ����SocketHandle�������б��в��Ҷ�Ӧ��Contextʵ��
    /// </summary>
    function FindContext(SocketHandle: TSocket): TIocpClientContext;

    /// <summary>
    /// ��ʱ���, �������Timeoutָ����ʱ�仹û���κ����ݽ������ݼ�¼��
    /// �ͽ��йر�����, ʹ��ѭ�����
    /// </summary>
    procedure KickOut(pvTimeOut:Cardinal = 60000);

    procedure RegisterContextClass(pvContextClass: TIocpContextClass);
    procedure RegisterSendRequestClass(pvClass: TIocpSendRequestClass);

    procedure Start;
    procedure Stop;

    property ClientCount: Integer read GetClientCount;
    property IocpAcceptorMgr: TIocpAcceptorMgr read FIocpAcceptorMgr;
    property MaxSendingQueueSize: Integer read FMaxSendingQueueSize;
  published
    property KeepAlive: Boolean read FKeepAlive write FKeepAlive;
    property BindAddr;
    /// <summary>
    /// Ĭ�������Ķ˿�
    /// </summary>
    property ListenPort: Word read FPort write FPort default 9000;
    property MaxWorkerCount;
    /// <summary>
    /// �����Զ���ʱ�߳����ʱ�� (ע�⣬Ϊ�˲�Ӱ�����ܣ�ÿ10��ִ��һ���Զ��߳��������������ֵֻ�Ǹ��ο�)
    /// </summary>
    property KickOutInterval: Integer read FKickOutInterval write FKickOutInterval default 60000;
    /// <summary>
    /// ����������ʱ�����¼� (����ִ��)
    /// </summary>
    property OnContextAccept: TOnContextAcceptEvent read FOnContextAccept write FOnContextAccept;
    /// <summary>
    /// ���ӽ������ʱ�����¼� (����ִ��)
    /// </summary>
    property OnContextConnected;
    /// <summary>
    /// ���ӶϿ��󴥷��¼�  (����ִ��)
    /// </summary>
    property OnContextDisconnected;
    /// <summary>
    /// ��������ʱ�����¼� (����ִ��)
    /// </summary>
    property OnContextError;
    /// <summary>
    /// ���������¼� (����ִ��)
    /// </summary>
    property OnDataReceived;
    /// <summary>
    /// �ڲ�״̬��Ϣ����ӿ� (����ִ��)
    /// </summary>
    property OnStateInfo;
  end;

type
  TIocpUdpServer = class;
  TIocpUdpRecvRequest = class;
  TIocpUdpRequest = TIocpUdpRecvRequest;
  TIocpUdpSendRequest = class;
  TIocpUdpSendRequestClass = class of TIocpUdpSendRequest;

  TOnUdpBufferReceived = procedure(Request: TIocpUdpRequest; buf: Pointer; len: Cardinal) of object;

  /// <summary>
  /// UDP ���ݽ�������
  /// </summary>
  TIocpUdpRecvRequest = class(TIocpRequest)
  private
    FOwner: TIocpUdpServer;
    FRecvBuffer: TWsaBuf;
    FRecvdFlag: Cardinal;
    FFrom: TSockAddrIn;
    FFromLen: Integer;
    function GetPeerAddr: Cardinal;
    function GetRemoteAddr: string;
    function GetRemotePort: Word;
  protected
    procedure HandleResponse; override;
    function PostRequest: Boolean;
    procedure DoRecvData; virtual;
  public
    constructor Create(AOwner: TIocpUdpServer); reintroduce;
    destructor Destroy; override;
    procedure Clear;

    procedure Send(buf: Pointer; len: Cardinal); overload;
    {$IFDEF UNICODE}
    procedure Send(const Data: UnicodeString); overload;
    {$ENDIF}
    procedure Send(const Data: WideString); overload;
    procedure Send(const Data: AnsiString); overload;

    property Owner: TIocpUdpServer read FOwner;
    property RemoteAddr: string read GetRemoteAddr;
    property RemotePort: Word read GetRemotePort;
    property PeerPort: Word read GetRemotePort;
    property PeerAddr: Cardinal read GetPeerAddr;
  end;

  /// <summary>
  /// UDP Send ����
  /// </summary>
  TIocpUdpSendRequest = class(TIocpRequest)
  private
    FOwner: TIocpUdpServer;
    FBuf: Pointer;
    FLen: Cardinal;
    FSendBuf: TWsaBuf;
    FAddr: TSockAddrIn;
    FSendBufferReleaseType: TDataReleaseType;
    FIsBusying: Boolean;
    FAlive: Boolean;
    procedure CheckClearSendBuffer;
  protected
    function ExecuteSend: Boolean; virtual;
    procedure UnBindingSendBuffer;
    function InnerPostRequest(buf: Pointer; len: Cardinal): Boolean;

    procedure HandleResponse; override;
    procedure ResponseDone; override;

    procedure DoCleanUp; virtual;
    procedure SetBuffer(buf: Pointer; len: Cardinal; pvCopyBuf: Boolean = True); overload;
    procedure SetBuffer(buf: Pointer; len: Cardinal; pvBufReleaseType: TDataReleaseType); overload;
  public
    constructor Create; override;
    destructor Destroy; override;
    property Owner: TIocpUdpServer read FOwner;
    property IsBusying: Boolean read FIsBusying;
  end;

  /// <summary>
  /// IOCP UDP �����
  /// </summary>
  TIocpUdpServer = class(TIocpBase)
  private
    FListenSocket: TRawSocket;
    FPort: Word;
    FOnReceivedBuffer: TOnUdpBufferReceived;
    FSendRef: Integer;
    FRecvItems: array of TObject;
    FSendRequestPool: TBaseQueue;
    FSendRequestClass: TIocpUdpSendRequestClass;
    FSendRequestList: TIocpRequestLinkList;
    function GetSocketHandle: TSocket;
    function GetMaxSendingQueueSize: Integer;
  protected
    procedure CreateSocket;
    procedure ClearRecvObjs;
    procedure DoReceiveData(Sender: TIocpUdpRequest); virtual;
    function WaitFor(pvTimeOut: Cardinal = 30000): Boolean;
    /// <summary>
    /// ��鲢Ͷ����һ����������
    /// </summary>
    function CheckNextSendRequest: Boolean;
    /// <summary>
    /// ��ȡһ��SendRequest����ʵ�����Ǵӳ��е���
    /// </summary>
    function GetSendRequest: TIocpUdpSendRequest;
    /// <summary>
    /// �ͷ�SendRequest�����س���
    /// </summary>
    function ReleaseSendRequest(pvObject: TIocpUdpSendRequest): Boolean;
    /// <summary>
    /// 1. Ͷ�ݷ������󵽶�����, ������Ͷ����������� False
    /// 2. ��� sending ��־, ��� sending �� False �ſ�ʼ
    /// </summary>
    function InnerPostSendRequestAndCheckStart(pvSendRequest: TIocpUdpSendRequest): Boolean;
    function InnerSendData(const Dest: TSockAddrin; buf: Pointer; len: Cardinal;
      pvBufReleaseType: TDataReleaseType; pvTag: Integer = 0; pvTagData: Pointer = nil): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Open; override;
    procedure Close; override;

    procedure RegisterSendRequestClass(pvClass: TIocpUdpSendRequestClass);
    /// <summary>
    /// ���÷��Ͷ������޴�С
    /// </summary>
    procedure SetMaxSendingQueueSize(pvSize: Integer);

    procedure PostNextSendRequest; virtual;

    function Send(const Dest: TSockAddrin; buf: Pointer; len: Cardinal; CopyBuf: Boolean = True): Boolean; overload;
    function Send(const Dest: TSockAddrin; buf: Pointer; len: Cardinal; BufReleaseType: TDataReleaseType): Boolean; overload;

    property SocketHandle: TSocket read GetSocketHandle;
    property MaxSendingQueueSize: Integer read GetMaxSendingQueueSize;
  published
    /// <summary>
    /// Ĭ�������Ķ˿�
    /// </summary>
    property ListenPort: Word read FPort write FPort default 9000;
    /// <summary>
    /// ���ݽ����¼�
    /// </summary>
    property OnDataReceived: TOnUdpBufferReceived read FOnReceivedBuffer write FOnReceivedBuffer;
  end;

type
  /// <summary>
  /// Զ�������࣬��Ӧ���������ÿ������
  /// </summary>
  TIocpRemoteContext = class(TIocpCustomContext)
  private
    FIsConnecting: Boolean;
    FAutoReConnect: Boolean;
    FConnectExRequest: TIocpConnectExRequest;
    FLastDisconnectTime: Int64;
    FHost: string;
    FPort: Word;
    function CanAutoReConnect: Boolean;
    procedure ReCreateSocket;
    procedure PostConnectRequest;
  protected
    procedure OnConnecteExResponse(pvObject: TObject);
    procedure OnDisconnected; override;
    procedure OnConnected; override;
    procedure SetSocketState(pvState:TSocketState); override;
    procedure ReleaseClientContext(); override;
  public
    constructor Create(AOwner: TIocpCustom); override;
    destructor Destroy; override;
    /// <summary>
    /// �������ӣ�Async �Ƿ�ʹ���첽��
    /// </summary>
    procedure Connect(ASync: Boolean = False); overload;
    /// <summary>
    /// �������ӣ�Async �Ƿ�ʹ���첽��
    /// </summary>
    procedure Connect(const AHost: string; APort: Word; ASync: Boolean = False); overload;
    /// <summary>
    /// ���ø����Ӷ�����Զ���������
    /// </summary>
    property AutoReConnect: Boolean read FAutoReConnect write FAutoReConnect;
    property Host: String read FHost write FHost;
    property Port: Word read FPort write FPort;
  end;

  /// <summary>
  /// IOCP TCP �ͻ���
  /// </summary>
  TIocpCustomTcpClient = class(TIocpCustom)
  private
    FDisableAutoConnect: Boolean;
    FReconnectRequestPool: TObjectPool;
    {$IFDEF UNICODE}
    FList: TObjectList<TIocpRemoteContext>;
    {$ELSE}
    FList: TObjectList;
    {$ENDIF}
    function GetCount: Integer;
    function GetItems(Index: Integer): TIocpRemoteContext;
    function CreateReconnectRequest: TObject;
  protected
    /// <summary>
    /// ��Ӧ��ɣ��黹������󵽳�
    /// </summary>
    procedure OnReconnectRequestResponseDone(pvObject: TObject);
    /// <summary>
    /// ��Ӧ��������Request
    /// </summary>
    procedure OnReconnectRequestResponse(pvObject: TObject);
    /// <summary>
    /// Ͷ�����������¼�
    /// </summary>
    procedure PostReconnectRequestEvent(const pvContext: TIocpRemoteContext);

    function ReleaseClientContext(const pvObject: TIocpCustomContext): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function CreateContext: TIocpCustomContext; override;


    /// <summary>
    /// ���һ�����Ӷ���
    /// </summary>
    function Add: TIocpRemoteContext;
    /// <summary>
    /// ����һ��������
    /// </summary>
    function Connect(const Host: string; Port: Word;
      AutoReConnect: Boolean = False; ASync: Boolean = True): TIocpRemoteContext;

    /// <summary>
    /// ɾ��һ������
    /// </summary>
    procedure Remove(const Value: TIocpRemoteContext);
    /// <summary>
    /// ɾ��ָ����������
    /// </summary>
    procedure Delete(Index: Integer);

    /// <summary>
    /// ɾ��ȫ������
    /// </summary>
    procedure RemoveAll();


    /// <summary>
    /// �ܵ����Ӷ�������
    /// </summary>
    property Count: Integer read GetCount;
    /// <summary>
    /// ��ֹ�������Ӷ����Զ�����
    /// </summary>
    property DisableAutoConnect: Boolean read FDisableAutoConnect write FDisableAutoConnect;
    /// <summary>
    /// ͨ��λ��������ȡ���е�һ������
    /// </summary>
    property Items[Index: Integer]: TIocpRemoteContext read GetItems; default;
  end;

function TransByteSize(const pvByte: Int64): string;
function BytesToString(const ABytes: TBytes; const AStartIndex: Integer = 0;
  AMaxCount: Integer = MaxInt): string;
function GetRunTimeInfo: string;

implementation

var
  Workers: TIocpTask;

const
  RECONNECT_INTERVAL = 1000; // ����������������ӹ��죬����OnDisconnected��û�д������, 1��

function TransByteSize(const pvByte: Int64): string;
var
  lvTB, lvGB, lvMB, lvKB: Word;
  lvRemain: Int64;
begin
  lvRemain := pvByte;
  lvTB := Trunc(lvRemain / BytePerGB / 1024);
  lvGB := Trunc(lvRemain / BytePerGB);
  lvGB := lvGB mod 1024;      // trunc TB
  lvRemain := lvRemain mod BytePerGB;
  lvMB := Trunc(lvRemain/BytePerMB);
  lvRemain := lvRemain mod BytePerMB;
  lvKB := Trunc(lvRemain/BytePerKB);
  lvRemain := lvRemain mod BytePerKB;
  Result := Format('%d TB, %d GB, %d MB, %d KB, %d B', [lvTB, lvGB, lvMB, lvKB, lvRemain]);
end;

function GetRunTimeInfo: string;
var
  lvMSec, lvRemain:Int64;
  lvDay, lvHour, lvMin, lvSec:Integer;
begin
  lvMSec := GetTimestamp;
  lvDay := Trunc(lvMSec / MSecsPerDay);
  lvRemain := lvMSec mod MSecsPerDay;

  lvHour := Trunc(lvRemain / (MSecsPerSec * 60 * 60));
  lvRemain := lvRemain mod (MSecsPerSec * 60 * 60);

  lvMin := Trunc(lvRemain / (MSecsPerSec * 60));
  lvRemain := lvRemain mod (MSecsPerSec * 60);

  lvSec := Trunc(lvRemain / (MSecsPerSec));

  if lvDay > 0 then
    Result := Result + IntToStr(lvDay) + ' d ';
  if lvHour > 0 then
    Result := Result + IntToStr(lvHour) + ' h ';
  if lvMin > 0 then
    Result := Result + IntToStr(lvMin) + ' m ';
  if lvSec > 0 then
    Result := Result + IntToStr(lvSec) + ' s ';
end;

{ TIocpCustomContext }

function TIocpCustomContext.CheckNextSendRequest: Boolean;
var
  lvRequest: TIocpSendRequest;
begin
  Result := False;
  Assert(FOwner <> nil);
  FContextLocker.Enter();
  try
    lvRequest := TIocpSendRequest(FSendRequestList.Pop);
    if lvRequest = nil then begin
      FSending := False;
      exit;
    end;
  finally
    FContextLocker.Leave;
  end;

  if lvRequest <> nil then begin
    FSendRequest := lvRequest;
    if lvRequest.ExecuteSend then begin
      Result := True;
      if (FOwner.FDataMoniter <> nil) then
        FOwner.FDataMoniter.IncPostSendObjectCounter;
    end else begin
      FSendRequest := nil;

      /// cancel request
      lvRequest.CancelRequest;

      {$IFDEF DEBUG_ON}
      FOwner.DoStateMsgD(Self, '[0x%.4x] CheckNextSendRequest.ExecuteSend Return False',
         [SocketHandle]);
      {$ENDIF}
      // ����Ͽ����� kick out the clientContext
      RequestDisconnect(lvRequest);
      FOwner.ReleaseSendRequest(lvRequest);
    end;
  end;
end;

procedure TIocpCustomContext.CheckReleaseRes;
var
  lvRequest: TIocpSendRequest;
begin
  if not Assigned(FOwner) then Exit;
  while True do begin
    lvRequest := TIocpSendRequest(FSendRequestList.Pop);
    if lvRequest <> nil then begin
      if (FOwner.FDataMoniter <> nil) then
        InterlockedIncrement(FOwner.FDataMoniter.FSendRequestAbortCounter);
      lvRequest.CancelRequest;
      FOwner.ReleaseSendRequest(lvRequest)
    end else
      Break;
  end;
end;

procedure TIocpCustomContext.Close;
begin
  RequestDisconnect();
end;

constructor TIocpCustomContext.Create(AOwner: TIocpCustom);
begin
  FOwner := AOwner;
  FRefCount := 0;
  FActive := False;
  FAlive := False;
  FContextLocker := TIocpLocker.Create();
  FContextLocker.Name := 'ContextLocker';
  FRawSocket := TRawSocket.Create();
  FSocketHandle := FRawSocket.SocketHandle;
  FSendRequestList := TIocpRequestLinkList.Create(64);
  FRecvRequest := TIocpRecvRequest.Create;
  FRecvRequest.FOwner := AOwner;
  FRecvRequest.FContext := Self;
end;

procedure TIocpCustomContext.CreateSocket(IsOverlapped: Boolean);
begin
  FRawSocket.CreateTcpSocket(IsOverlapped);
  FSocketHandle := FRawSocket.SocketHandle;
end;

function TIocpCustomContext.DecReferenceCounter(pvObj: TObject; const pvDebugInfo: string): Integer;
var
  lvCloseContext: Boolean;
begin
  lvCloseContext := false;
  FContextLocker.Enter('DecRefCount');
  try
    Dec(FRefCount);
    Result := FRefCount;
    if FRefCount <= 0 then begin
      FRefCount := 0;
      if FRequestDisconnect then lvCloseContext := True;
    end;
    if IsDebugMode and Assigned(FOwner) then
      FOwner.DoStateMsgD(Self, strConn_CounterDec, [FRefCount, IntPtr(pvObj), pvDebugInfo]);
  finally
    FContextLocker.Leave;
  end;
  if lvCloseContext then
    InnerCloseContext;
end;

procedure TIocpCustomContext.DecReferenceCounterAndRequestDisconnect(
  pvObj: TObject; const pvDebugInfo: string);
var
  lvCloseContext:Boolean;
begin
  lvCloseContext := false;
  {$IFDEF DEBUG_ON}
  if Assigned(FOwner) then
    FOwner.DoStateMsgD(Self, strSend_ReqKick, [SocketHandle, pvDebugInfo]);
  {$ENDIF}
  FContextLocker.Enter('DecReferenceCounter');
  try
    FRequestDisconnect := True;
    Dec(FRefCount);
    if FRefCount < 0 then
      Assert(FRefCount >=0 );
    if FRefCount = 0 then
      lvCloseContext := True;
  finally
    FContextLocker.Leave;
  end;
  if lvCloseContext then
    InnerCloseContext;
end;

destructor TIocpCustomContext.Destroy;
begin
  if IsDebugMode then begin
    if FRefCount <> 0 then
      Assert(FRefCount = 0);
  end;

  FreeAndNil(FRawSocket);
  FreeAndNil(FRecvRequest);
  Assert(FSendRequestList.Count = 0);
  FreeAndNil(FSendRequestList);
  FreeAndNil(FContextLocker);
  inherited;
end;

procedure TIocpCustomContext.Disconnect;
begin
  RequestDisconnect();
end;

procedure TIocpCustomContext.DoCleanUp;
begin
  FLastActive := 0;
  //FLastActivity := GetTimestamp;
  FRequestDisconnect := False;
  FSending := False;
  if IsDebugMode then begin
    if Assigned(FOwner) then
      FOwner.DoStateMsgD(Self, '-(%d):0x%.4x, %s', [FRefCount, IntPtr(Self), 'DoCleanUp']);
    if FRefCount <> 0 then
      Assert(FRefCount = 0);
    Assert(not FActive);
  end;
  FRecvRequest.Clear;
end;

procedure TIocpCustomContext.DoConnected;
begin
  FRequestDisconnect := False;
  FLastActive := GetTimestamp;
  FLastActivity := FLastActive;

  FContextLocker.Enter('DoConnected');
  try
    if not Assigned(FOwner) then Exit;
    if FActive then begin
      // �Ѿ���������ӣ������κδ���
      if IsDebugMode then
        Assert(not FActive);
      {$IFDEF DEBUG_ON}
      FOwner.DoStateMsgD(Self, strSocket_ConnActived);
      {$ENDIF}
    end else begin
      FHandle := FOwner.RequestContextHandle; //����OwnerΪ�Լ�����һ��Handle
      FActive := True;
      FOwner.AddToOnlineList(Self);
      if LockContext(Self, 'OnConnected') then
      try
        if Assigned(FOwner.FOnContextConnected) then
          FOwner.FOnContextConnected(Self);
        try
          OnConnected();
        except
          {$IFDEF DEBUG_ON}
          FOwner.DoStateMsgE(Self, strSocket_ConnError, Exception(ExceptObject));
          {$ENDIF}
        end;
        if Assigned(FOnConnectedEvent) then
          FOnConnectedEvent(Self);
        // ����Ϊ���ӳɹ�״̬���������������
        SetSocketState(ssConnected);
        PostWSARecvRequest;
      finally
        UnLockContext(Self, 'OnConnected');
      end;
    end;
  finally
    FContextLocker.Leave;
  end;
end;

procedure TIocpCustomContext.DoDisconnect;
begin
  InnerCloseContext;
end;

procedure TIocpCustomContext.DoError(ErrorCode: Integer);
begin
  FLastErrorCode := ErrorCode;
  FOwner.DoClientContextError(Self, ErrorCode);
end;

procedure TIocpCustomContext.DoReceiveData;
begin
  OnRecvBuffer(FRecvRequest.FRecvBuffer.buf,
    FRecvRequest.FBytesTransferred,
    FRecvRequest.ErrorCode);
  if Assigned(FOwner) and (not GetIsDisconnect) then
    FOwner.DoReceiveData(Self, FRecvRequest);
end;

procedure TIocpCustomContext.DoSendRequestCompleted(pvRequest: TIocpSendRequest);
begin
end;

procedure TIocpCustomContext.DoSendRequestRespnonse(
  pvRequest: TIocpSendRequest);
begin
  FLastActive := GetTimestamp;
  if Assigned(FOwner.FOnSendRequestResponse) then
    FOwner.FOnSendRequestResponse(Self, pvRequest);
end;

function TIocpCustomContext.GetIsDisconnect: Boolean;
begin
  if (not Assigned(Self)) or (FRequestDisconnect) then
    Result := True
  else
    Result := False;
end;

function TIocpCustomContext.GetSendRequest: TIocpSendRequest;
begin
  Result := FOwner.GetSendRequest;
  Assert(Result <> nil);
  Result.FContext := Self;
end;

function TIocpCustomContext.GetSocketHandle: TSocket;
begin
  Result := FSocketHandle;
end;

function TIocpCustomContext.IncReferenceCounter(pvObj: TObject; const pvDebugInfo: string): Boolean;
begin
  FContextLocker.Enter('IncRefCount');
  if (not FActive) or FRequestDisconnect then
    Result := False
  else begin
    Inc(FRefCount);
    Result := True;
    if Assigned(FOwner) and IsDebugMode then
      FOwner.DoStateMsgD(Self, strConn_CounterInc, [FRefCount, IntPtr(pvObj), pvDebugInfo]);
  end;
  FContextLocker.Leave;
end;

procedure TIocpCustomContext.InnerCloseContext;
begin
  Assert(FOwner <> nil);
  {$IFDEF DEBUG_ON}
  if FRefCount <> 0 then
    FOwner.DoStateMsgD(Self, 'InnerCloseContext ContextCounter: %d', [FRefCount]);
  if not FActive then begin
    FOwner.DoStateMsgD(Self, 'InnerCloseContext Active is False');
    Exit;
  end;
  {$ELSE}
  if not FActive then Exit;
  {$ENDIF}
  try
    FActive := False;
    {$IFDEF SOCKET_REUSE}
    {$ELSE}
    FRawSocket.Close;
    {$ENDIF}
    CheckReleaseRes;
    try
      if Assigned(FOwner.FOnContextDisconnected) then
        FOwner.FOnContextDisconnected(Self);
      OnDisconnected;
      // ����Socket״̬
      SetSocketState(ssDisconnected);
      DoCleanUp;
    except
      {$IFDEF DEBUG_ON}
      FOwner.DoStateMsgE(Self, Exception(ExceptObject));
      {$ENDIF}
    end;
  finally
    FOwner.RemoveFromOnlineList(Self);
    ReleaseClientContext;
  end;
end;

function TIocpCustomContext.InnerPostSendRequestAndCheckStart(
  pvSendRequest: TIocpSendRequest): Boolean;
var
  lvStart: Boolean;
begin
  lvStart := False;
  FContextLocker.Enter();
  try
    Result := FSendRequestList.Push(pvSendRequest);
    if Result then begin
      if not FSending then begin
        FSending := true;
        lvStart := true;  // start send work
      end;
    end;
  finally
    FContextLocker.Leave;
  end;

  {$IFDEF DEBUG_ON}
  if (not Result) and Assigned(FOwner) then
    FOwner.DoStateMsgE(Self, strSend_PushFail, [SocketHandle, FSendRequestList.Count, FSendRequestList.MaxSize]);
  {$ENDIF}

  if lvStart then begin  // start send work
    if (Assigned(FOwner)) and (FOwner.FDataMoniter <> nil) then
      FOwner.FDataMoniter.incPushSendQueueCounter;
    CheckNextSendRequest;
  end;
end;

function TIocpCustomContext.InnerSendData(buf: Pointer; len: Cardinal;
  pvBufReleaseType: TDataReleaseType; pvTag: Integer;
  pvTagData: Pointer): Boolean;
var
  lvRequest: TIocpSendRequest;
begin
  Result := False;
  if Active then begin
    if IncReferenceCounter(Self, 'InnerSendData') then begin
      try
        lvRequest := GetSendRequest;
        lvRequest.SetBuffer(buf, len, pvBufReleaseType);
        lvRequest.Tag := pvTag;
        lvRequest.Data := pvTagData;
        Result := InnerPostSendRequestAndCheckStart(lvRequest);
        if not Result then begin
          /// Push Fail unbinding buf
          lvRequest.UnBindingSendBuffer;

          {$IFDEF DEBUG_ON}
          Self.RequestDisconnect(lvRequest, Format(strSend_PushFail, [SocketHandle,
            FSendRequestList.Count, FSendRequestList.MaxSize]));
          {$ELSE}
          Self.RequestDisconnect(lvRequest);
          {$ENDIF}

          lvRequest.CancelRequest;
          FOwner.ReleaseSendRequest(lvRequest);
        end;
      finally
        decReferenceCounter(self, 'InnerSendData');
      end;
    end;
  end;
end;

procedure TIocpCustomContext.Lock;
begin
  FContextLocker.Enter();
end;

function TIocpCustomContext.LockContext(pvObj: TObject; const pvDebugInfo: string): Boolean;
begin
  Result := IncReferenceCounter(pvObj, pvDebugInfo);
end;

procedure TIocpCustomContext.OnConnected;
begin
end;

procedure TIocpCustomContext.OnDisconnected;
begin
end;

procedure TIocpCustomContext.OnRecvBuffer(buf: Pointer; len: Cardinal;
  ErrorCode: Integer);
begin
end;

procedure TIocpCustomContext.PostNextSendRequest;
begin
  FContextLocker.Enter();
  try
    if not CheckNextSendRequest then FSending := false;
  finally
    FContextLocker.Leave;
  end;
end;

procedure TIocpCustomContext.PostWSACloseRequest;
begin
  PostWSASendRequest(nil, 0, dtNone, -1);
end;

procedure TIocpCustomContext.PostWSARecvRequest;
begin
  FRecvRequest.PostRequest;
end;

function TIocpCustomContext.PostWSASendRequest(buf: Pointer; len: Cardinal;
  pvCopyBuf: Boolean): Boolean;
var
  lvBuf: PAnsiChar;
begin
  if (not Assigned(Self)) or (buf = nil) then begin
    Result := False;
    Exit;
  end;
  if pvCopyBuf and (len <= Owner.SendBufferSize) then begin
    if len = 0 then begin
      Result := False;
      Exit;
    end;

    {$IFDEF UseSendMemPool}
    lvBuf := FOwner.PopMem;
    Move(buf^, lvBuf^, len);
    Result := PostWSASendRequest(lvBuf, len, dtMemPool);
    if not Result then //post fail
      FOwner.PushMem(lvBuf);
    {$ELSE}
    GetMem(lvBuf, len);
    Move(buf^, lvBuf^, len);
    Result := PostWSASendRequest(lvBuf, len, dtFreeMem);
    if not Result then //post fail
      FreeMem(lvBuf);
    {$ENDIF}
  end else
    Result := PostWSASendRequest(buf, len, dtNone);
end;

function TIocpCustomContext.PostWSASendRequest(buf: Pointer; len: Cardinal;
  pvBufReleaseType: TDataReleaseType; pvTag: Integer; pvTagData: Pointer): Boolean;

  // �ֿ�Ͷ��
  function BlockSend(lvSrc: PAnsiChar; lvSrcLen: Cardinal; pvTag: Integer; pvTagData: Pointer): Boolean;
  var
    lvBuf: PAnsiChar;
    lvLen, lvBuffSize: Cardinal;
    lvFreeType: TDataReleaseType;
    lvRequest: TIocpSendRequest;
  begin
    lvBuffSize := Owner.SendBufferSize;
    Result := False;

    while lvSrcLen > 0 do begin
      if lvSrcLen > lvBuffSize then
        lvLen := lvBuffSize
      else
        lvLen := lvSrcLen;
      {$IFDEF UseSendMemPool}
      lvBuf := FOwner.PopMem;
      Move(lvSrc^, lvBuf^, lvLen);
      lvFreeType := dtMemPool;
      {$ELSE}
      GetMem(lvBuf, lvLen);
      Move(lvSrc^, lvBuf^, lvLen);
      lvFreeType := dtFreeMem;
      {$ENDIF}

      Result := False;

      lvRequest := GetSendRequest;
      lvRequest.SetBuffer(lvBuf, lvLen, lvFreeType);
      lvRequest.Tag := pvTag;
      lvRequest.Data := pvTagData;
      repeat
        if IncReferenceCounter(Self, 'BlockSend') then begin
          try
            Result := InnerPostSendRequestAndCheckStart(lvRequest);
            if not Result then begin
              {$IFDEF MSWINDOWS}
              SwitchToThread;
              {$ELSE}
              TThread.Yield;
              {$ENDIF}
              Sleep(50);
            end;
          finally
            decReferenceCounter(self, 'BlockSend');
          end;
        end else
          Break;
      until (Result);

      if not Result then begin
        lvRequest.UnBindingSendBuffer;
        lvRequest.CancelRequest;
        FOwner.ReleaseSendRequest(lvRequest);

        {$IFDEF UseSendMemPool}
        FOwner.PushMem(lvBuf);
        {$ELSE}
        FreeMem(lvBuf);
        {$ENDIF}
        Break;
      end;

      Inc(lvSrc, lvLen);
      Dec(lvSrcLen, lvLen);
    end;
  end;

begin
  Result := False;
  if (not Assigned(Self)) then Exit;
  if Active then begin
    if len <= Owner.SendBufferSize then
      Result := InnerSendData(buf, len, pvBufReleaseType, pvTag, pvTagData)
    else begin
      // ���ڷ��ͻ�����ʱ���ֿ鷢��
      try
        Result := BlockSend(buf, len, pvTag, pvTagData);
      finally
        case pvBufReleaseType of
          dtDispose: Dispose(buf);
          dtFreeMem: FreeMem(buf);
          dtMemPool: FOwner.PushMem(buf);
        end;
      end;
    end;
  end;
end;

procedure TIocpCustomContext.ReleaseClientContext;
begin
end;

procedure TIocpCustomContext.RequestDisconnect(pvObj: TObject; const pvDebugInfo: string);
var
  lvCloseContext: Boolean;
begin
  if (not Assigned(Self)) or (not FActive) then Exit;
  {$IFDEF DEBUG_ON}
  if Assigned(FOwner) then
    FOwner.DoStateMsgD(Self, strSend_ReqKick, [SocketHandle, pvDebugInfo]);
  {$ENDIF}
  lvCloseContext := False;
  FContextLocker.Enter('RequestDisconnect');
  if Assigned(FOwner) and (Length(pvDebugInfo) > 0) then
     FOwner.DoStateMsgD(Self, strConn_CounterView, [FRefCount, IntPtr(pvObj), pvDebugInfo]);
  {$IFDEF SOCKET_REUSE}
  if not FRequestDisconnect then begin
    // cancel
    FRawSocket.ShutDown();
    FRawSocket.CancelIO;
    // post succ, in handleReponse Event do
    if not FDisconnectExRequest.PostRequest then begin
      // post fail,
      FRawSocket.Close;
      if FRefCount = 0 then
        lvCloseContext := true; // lvCloseContext := true;   //directly close
    end;
    FRequestDisconnect := true;
  end;
  {$ELSE}
  FRequestDisconnect := true;
  if FRefCount = 0 then
    lvCloseContext := true;
  {$ENDIF}
  FContextLocker.Leave;

  {$IFDEF SOCKET_REUSE}
  if lvCloseContext then
    InnerCloseContext;
  {$ELSE}
  if lvCloseContext then
    InnerCloseContext
  else
    FRawSocket.Close;
  {$ENDIF}
end;

function TIocpCustomContext.Send(buf: Pointer; len: Cardinal;
  CopyBuf: Boolean): Boolean;
begin
  Result := PostWSASendRequest(buf, len, CopyBuf);
end;

function TIocpCustomContext.Send(buf: Pointer; len: Cardinal;
  BufReleaseType: TDataReleaseType): Boolean;
begin
  Result := PostWSASendRequest(buf, len, BufReleaseType);
end;

function TIocpCustomContext.Send(const Data: AnsiString): Boolean;
begin
  Result := PostWSASendRequest(Pointer(Data), Length(Data), True);
end;

function TIocpCustomContext.Send(const Data: WideString): Boolean;
begin
  Result := PostWSASendRequest(Pointer(Data), Length(Data) shl 1, True);
end;

{$IFDEF UNICODE}
function TIocpCustomContext.Send(const Data: UnicodeString): Boolean;
begin
  Result := PostWSASendRequest(Pointer(Data), Length(Data) shl 1, True);
end;
{$ENDIF}

function TIocpCustomContext.Send(Stream: TStream; ASize: Int64): Boolean;
var
  P: PAnsiChar;
  lvFreeType: TDataReleaseType;
  lvRequest: TIocpSendRequest;
  lvBuffSize, lvL: Cardinal;
  lvLen: Int64;
  lvBuf: PAnsiChar;
begin
  Result := False;
  if Assigned(Stream) then begin
    lvLen := Stream.Size - Stream.Position;
    if lvLen < ASize then
      Exit
    else
      lvLen := ASize;
    if (Stream is TMemoryStream) then begin
      P := PAnsiChar(TMemoryStream(Stream).Memory) + Stream.Position;
      Result := PostWSASendRequest(P, lvLen);
      Stream.Position := Stream.Position + lvLen;
    end else begin
      Result := False;
      lvBuffSize := Owner.SendBufferSize;
      while lvLen > 0 do begin
        if lvLen > lvBuffSize then
          lvL := lvBuffSize
        else
          lvL := lvLen;
        {$IFDEF UseSendMemPool}
        lvBuf := FOwner.PopMem;
        lvFreeType := dtMemPool;
        {$ELSE}
        GetMem(lvBuf, lvL);
        lvFreeType := dtFreeMem;
        {$ENDIF}

        lvL := Stream.Read(lvBuf^, lvL);
        if (lvL = 0) then
          Break;
        Result := False;
        lvRequest := GetSendRequest;
        lvRequest.SetBuffer(lvBuf, lvL, lvFreeType);
        lvRequest.Tag := 0;
        lvRequest.Data := nil;
        repeat
          if IncReferenceCounter(Self, 'SendStream') then begin
            try
              Result := InnerPostSendRequestAndCheckStart(lvRequest);
              if not Result then begin
                {$IFDEF MSWINDOWS}
                SwitchToThread;
                {$ELSE}
                TThread.Yield;
                {$ENDIF}
                Sleep(50);
              end;
            finally
              decReferenceCounter(self, 'SendStream');
            end;
          end else
            Break;
        until (Result);

        if not Result then begin
          lvRequest.UnBindingSendBuffer;
          lvRequest.CancelRequest;
          FOwner.ReleaseSendRequest(lvRequest);

          {$IFDEF UseSendMemPool}
          FOwner.PushMem(lvBuf);
          {$ELSE}
          FreeMem(lvBuf);
          {$ENDIF}
          Break;
        end;

        Dec(lvLen, lvL);
      end;
    end;
  end;
end;

function TIocpCustomContext.Send(Stream: TStream): Boolean;
begin
  if Assigned(Stream) then begin
    Result := Send(Stream, Stream.Size - Stream.Position);
  end else
    Result := False;
end;

procedure TIocpCustomContext.SetMaxSendingQueueSize(pvSize: Integer);
begin
  FSendRequestList.MaxSize := pvSize;
end;

procedure TIocpCustomContext.SetSocketState(pvState: TSocketState);
begin
  FSocketState := pvState;
  if Assigned(FOnSocketStateChanged) then
    FOnSocketStateChanged(Self);
end;

procedure TIocpCustomContext.UnLock;
begin
  FContextLocker.Leave;
end;

procedure TIocpCustomContext.UnLockContext(pvObj: TObject; const pvDebugInfo: string);
begin
  if Assigned(Self) and (Assigned(FContextLocker)) then
    DecReferenceCounter(pvObj, pvDebugInfo);
end;

{ TIocpBase }

constructor TIocpBase.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBindAddr := '0.0.0.0';
  FLocker := TIocpLocker.Create();
  FLocker.Name := Self.ClassName;
  FIocpEngine := TIocpEngine.Create();
  // post wsaRecv block size
  FWSARecvBufferSize := 1024 shl 2;
  FWSASendBufferSize := 1024 shl 3;
  FMemPool := TIocpMemPool.Create(FWSASendBufferSize, 4096);
end;

procedure TIocpBase.CreateDataMonitor;
begin
  if not Assigned(FDataMoniter) then
    FDataMoniter := TIocpDataMonitor.Create;
end;

destructor TIocpBase.Destroy;
begin
  FIsDestroying := True;
  Close;
  FreeAndNil(FDataMoniter);
  FreeAndNil(FIocpEngine);
  inherited Destroy;
  FreeAndNil(FMemPool);
  FreeAndNil(FLocker);
end;

procedure TIocpBase.DoStateMsg(Sender: TObject;
  MsgType: TIocpStateMsgType; const Msg: string);
begin
  if Assigned(FOnStateMsg) then
    FOnStateMsg(Sender, MsgType, Msg);
end;

procedure TIocpBase.DoStateMsgD(Sender: TObject;
  const MsgFormat: string; const Params: array of const);
begin
  if Assigned(FOnStateMsg) then
    FOnStateMsg(Sender, iocp_mt_Debug, Format(MsgFormat, Params));
end;

procedure TIocpBase.DoStateMsgE(Sender: TObject; E: Exception);
begin
  if Assigned(FOnStateMsg) then
    FOnStateMsg(Sender, iocp_mt_Error, E.Message);
end;

procedure TIocpBase.DoStateMsgE(Sender: TObject;
  const MsgFormat: string; E: Exception);
begin
  if Assigned(FOnStateMsg) then
    FOnStateMsg(Sender, iocp_mt_Error, Format(MsgFormat, [E.Message]));
end;

procedure TIocpBase.DoStateMsgE(Sender: TObject;
  const MsgFormat: string; const Params: array of const);
begin
  if Assigned(FOnStateMsg) then
    FOnStateMsg(Sender, iocp_mt_Error, Format(MsgFormat, Params));
end;

procedure TIocpBase.DoStateMsgD(Sender: TObject; const Msg: string);
begin
  if Assigned(FOnStateMsg) then
    FOnStateMsg(Sender, iocp_mt_Debug, Msg);
end;

procedure TIocpBase.DoStateMsgE(Sender: TObject; const Msg: string);
begin
  if Assigned(FOnStateMsg) then
    FOnStateMsg(Sender, iocp_mt_Error, Msg);
end;

function TIocpBase.GetMaxWorkerCount: Integer;
begin
  if Assigned(FIocpEngine) then
    Result := FIocpEngine.MaxWorkerCount
  else
    Result := 0;
end;

function TIocpBase.GetWorkerCount: Integer;
begin
  if Assigned(FIocpEngine) then
    Result := FIocpEngine.WorkerCount
  else
    Result := 0;
end;

function TIocpBase.IsDestroying: Boolean;
begin
  Result := (not Assigned(Self)) or FIsDestroying or (csDestroying in Self.ComponentState);
end;

function TIocpBase.PopMem: Pointer;
begin
  Result := FMemPool.Pop;
end;

procedure TIocpBase.PushMem(const V: Pointer);
begin
  FMemPool.Push(V);
end;

procedure TIocpBase.SetActive(const Value: Boolean);
begin
  if FActive = Value then Exit;
  if Value then
    Open
  else
    Close;
end;

procedure TIocpBase.SetBindAddr(const Value: string);
begin
  if FBindAddr <> Value then
    FBindAddr := Value;
end;

procedure TIocpBase.SetMaxWorkerCount(const Value: Integer);
begin
  FIocpEngine.SetMaxWorkerCount(Value);
end;

procedure TIocpBase.SetName(const NewName: TComponentName);
begin
  inherited;
end;

procedure TIocpBase.SetWorkerCount(const Value: Integer);
begin
  FIocpEngine.SetWorkerCount(Value);
end;

procedure TIocpBase.SetWSARecvBufferSize(const Value: Cardinal);
begin
  FWSARecvBufferSize := Value;
  if FWSARecvBufferSize = 0 then
    FWSARecvBufferSize := 1024 shl 2;
end;

procedure TIocpBase.SetWSASendBufferSize(const Value: Cardinal);
begin
  if FWSASendBufferSize <> Value then begin
    FWSASendBufferSize := Value;
    if FWSASendBufferSize = 0 then
      FWSASendBufferSize := 1024 shl 3;
    FreeAndNil(FMemPool);
    FMemPool := TIocpMemPool.Create(FWSASendBufferSize, 4096);
  end;
end;

{ TIocpCustom }

procedure TIocpCustom.AddToOnlineList(const pvObject: TIocpCustomContext);
begin
  FLocker.Enter('AddToOnlineList');
  try
    FOnlineContextList.Add(Cardinal(pvObject.SocketHandle), Integer(pvObject));
  finally
    FLocker.Leave;
  end;
end;

function TIocpCustom.GetClientContext: TIocpCustomContext;
begin
  Result := CreateContext;
end;

function TIocpCustom.GetOnlineContextCount: Integer;
begin
  Result := FOnlineContextList.Count;
end;

procedure TIocpCustom.GetOnlineContextList(pvList: TList);
var
  Item: PHashMapLinkItem;
  lvClientContext: TIocpCustomContext;
begin
  FLocker.Enter('GetOnlineContextList');
  try
    for Item in FOnlineContextList do begin
      lvClientContext := HashItemToContext(Item);
      if Assigned(lvClientContext) then
        pvList.Add(lvClientContext);
    end;
  finally
    FLocker.Leave;
  end;
end;

function TIocpCustom.GetSendRequest: TIocpSendRequest;
begin
  Result := TIocpSendRequest(FSendRequestPool.DeQueue);
  if Result = nil then begin
    if FSendRequestClass <> nil then
      Result := FSendRequestClass.Create
    else
      Result := TIocpSendRequest.Create;
  end;
  Result.FAlive := True;
  Result.DoCleanup;
  Result.FOwner := Self;
end;

function TIocpCustom.HashItemToContext(Item: PHashMapLinkItem): TIocpCustomContext;
begin
  if (Item <> nil) and (Item.Value <> nil) then
    Result := TIocpCustomContext(Item.Value.Value.Data)
  else
    Result := nil;
end;

function TIocpCustom.CheckClientContextValid(const ClientContext: TIocpCustomContext): Boolean;
begin
  Result := (ClientContext.FOwner = Self);
end;

procedure TIocpCustom.Close;
begin
  if not FActive then Exit;
  FActive := False;
  DisconnectAll;
  WaitForContext(30000);
  // engine Stop
  FIocpEngine.Stop;
end;

constructor TIocpCustom.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOnlineContextList := TYXDHashMapLinkTable.Create(99991);
  // send requestPool
  FSendRequestPool := TBaseQueue.Create;
end;

function TIocpCustom.CreateContext: TIocpCustomContext;
begin
  if FContextClass <> nil then
    Result := FContextClass.Create(Self)
  else
    Result := TIocpCustomContext.Create(Self);
  OnCreateContext(Result);
end;

destructor TIocpCustom.Destroy;
begin
  inherited Destroy;
  FSendRequestPool.FreeDataObject;
  FreeAndNil(FOnlineContextList);
  FreeAndNil(FSendRequestPool);
end;

procedure TIocpCustom.DisconnectAll;
var
  Item: PHashMapLinkItem;
  lvClientContext: TIocpCustomContext;
const
  DEBUGINFO = 'DisconnectAll';
begin
  FLocker.Enter(DEBUGINFO);
  try
    for Item in FOnlineContextList do begin
      lvClientContext := HashItemToContext(Item);
      if Assigned(lvClientContext) then
        lvClientContext.RequestDisconnect(Self, DEBUGINFO);
    end;
  finally
    FLocker.Leave;
  end;
end;

procedure TIocpCustom.DoAcceptExResponse(pvRequest: TIocpAcceptExRequest);
begin
  pvRequest.FAcceptorMgr.ReleaseRequestObject(pvRequest);
end;

procedure TIocpCustom.DoClientContextError(
  const pvClientContext: TIocpCustomContext; pvErrorCode: Integer);
begin
  if Assigned(FOnContextError) then
    FOnContextError(pvClientContext, pvErrorCode);
end;

procedure TIocpCustom.DoReceiveData(const pvContext: TIocpCustomContext;
  pvRequest: TIocpRecvRequest);
begin
  pvContext.FLastActivity := GetTimestamp;
  if Assigned(FOnReceivedBuffer) then
    FOnReceivedBuffer(pvContext, pvRequest.FRecvBuffer.buf,
      pvRequest.FBytesTransferred, pvRequest.ErrorCode);
end;

procedure TIocpCustom.OnCreateContext(const Context: TIocpCustomContext);
begin
end;

procedure TIocpCustom.Open;
begin
  if FActive then Exit;
  FActive := True;
  try
    if Assigned(FDataMoniter) then
      FDataMoniter.Clear;
    FIocpEngine.Start;
  except
    FActive := False;
  end;
end;

function TIocpCustom.ReleaseClientContext(const pvObject: TIocpCustomContext): Boolean;
begin
  if Assigned(pvObject) then
    pvObject.Free;
  Result := False;
end;

function TIocpCustom.ReleaseSendRequest(pvObject: TIocpSendRequest): Boolean;
begin
  Result := False;
  if (not Assigned(Self)) or (not Assigned(FSendRequestPool)) then
    Assert(False);
  if IsDebugMode then
    Assert(pvObject.FAlive);
  if lock_cmp_exchange(True, False, pvObject.FAlive) = True then begin
    if Assigned(FDataMoniter) then
      InterlockedIncrement(FDataMoniter.FSendRequestReturnCounter);
    pvObject.DoCleanUp;
    pvObject.FOwner := nil;
    FSendRequestPool.EnQueue(pvObject);
    Result := True;
  end else begin
    if IsDebugMode then
      Assert(False);
  end;
end;

procedure TIocpCustom.RemoveFromOnlineList(const pvObject: TIocpCustomContext);
{$IFDEF DEBUG_ON}
var
  lvSucc:Boolean;
{$ENDIF}
begin
  FLocker.Enter('RemoveFromOnlineList');
  try
    {$IFDEF DEBUG_ON}
    lvSucc := FOnlineContextList.Remove(Cardinal(pvObject.SocketHandle));
    Assert(lvSucc);
    {$ELSE}
    FOnlineContextList.Remove(Cardinal(pvObject.SocketHandle));
    {$ENDIF}
  finally
    FLocker.Leave;
  end;
end;

function TIocpCustom.RequestContextHandle: Integer;
begin
  Result := InterlockedIncrement(FContextCounter);
end;

function TIocpCustom.WaitForContext(pvTimeOut: Cardinal): Boolean;
var
  l, t: Int64;
  c: Integer;
begin
  l := GetTimestamp;
  c := FOnlineContextList.Count;
  while (c > 0) do begin
    {$IFDEF MSWINDOWS}
    SwitchToThread;
    {$ELSE}
    TThread.Yield;
    {$ENDIF}
    t := GetTimestamp - l;
    if t > pvTimeOut then begin
      {$IFDEF DEBUG_ON}
      DoStateMsgD(Self, 'WaitForContext End Current num: %d', [c]);
      {$ENDIF}
      Break;
    end else if (t > 10000) and (c < 100) then begin
      {$IFDEF DEBUG_ON}
      DoStateMsgD(Self, 'WaitForContext End Current num: %d', [c]);
      {$ENDIF}
      Break;
    end;
    c := FOnlineContextList.Count;
  end;
  Result := FOnlineContextList.Count = 0;
end;

{ TIocpRecvRequest }

procedure TIocpRecvRequest.Clear;
begin
  if FInnerBuffer.len > 0 then begin
    FreeMem(FInnerBuffer.buf, FInnerBuffer.len);
    FInnerBuffer.len := 0;
  end;
end;

constructor TIocpRecvRequest.Create;
begin
  inherited Create;
end;

destructor TIocpRecvRequest.Destroy;
begin
  if FInnerBuffer.len > 0 then
    FreeMem(FInnerBuffer.buf, FInnerBuffer.len);
  inherited Destroy;
end;

procedure TIocpRecvRequest.HandleResponse;
begin
  {$IFDEF DEBUG_ON}
  InterlockedDecrement(FOverlapped.refCount);
  if FOverlapped.refCount <> 0 then
    Assert(FOverlapped.refCount <> 0);
  if FOwner = nil then
    Assert(FOwner <> nil);
  {$ENDIF}

  try
    if (Assigned(FOwner.FDataMoniter)) then begin
      FOwner.FDataMoniter.incResponseWSARecvCounter;
      FOwner.FDataMoniter.incRecvdSize(FBytesTransferred);
    end;

    if not FOwner.Active then begin
      {$IFDEF DEBUG_ON}
      FOwner.DoStateMsgD(Self, strRecv_EngineOff, [FContext.SocketHandle]);
      {$ENDIF}
      // avoid postWSARecv
      FContext.RequestDisconnect(Self{$IFDEF DEBUGINFO}, Format(strRecv_EngineOff, [FContext.SocketHandle]){$ENDIF});
    end else if ErrorCode <> 0 then begin
      FContext.DoError(ErrorCode);
      if ErrorCode <> 995 then begin  // �첽����ȴ�ʱ�����˹ر��׽���
        FOwner.DoStateMsgE(Self, strRecv_Error, [FContext.SocketHandle, ErrorCode]);
      end;
      FContext.RequestDisconnect(Self{$IFDEF DEBUGINFO}, Format(strRecv_Error, [FContext.SocketHandle, ErrorCode]){$ENDIF});
    end else if (FBytesTransferred = 0) then begin
      // no data recvd, socket is break
      {$IFDEF DEBUG_ON}
      //FOwner.DoStateMsgE(Self, strRecv_Zero, [FContext.SocketHandle]);
      {$ENDIF}
      FContext.RequestDisconnect(Self{$IFDEF DEBUGINFO}, Format(strRecv_Zero, [FContext.SocketHandle]){$ENDIF});
    end else
      FContext.DoReceiveData;
  finally
    if not FContext.FRequestDisconnect then
      FContext.PostWSARecvRequest;
    FContext.DecReferenceCounter(Self{$IFDEF DEBUGINFO},
      Format('Refcount: %d, TIocpRecvRequest.WSARecvRequest.HandleResponse',
        [FOverlapped.refCount]){$ENDIF});
  end;
end;

function TIocpRecvRequest.PostRequest: Boolean;
begin
  if FInnerBuffer.len <> FOwner.FWSARecvBufferSize then begin
    if FInnerBuffer.len > 0 then
      FreeMem(FInnerBuffer.buf);
    FInnerBuffer.len := FOwner.FWSARecvBufferSize;
    GetMem(FInnerBuffer.buf, FInnerBuffer.len);
  end;
  Result := PostRequest(FInnerBuffer.buf, FInnerBuffer.len);
end;

function TIocpRecvRequest.PostRequest(pvBuffer: PAnsiChar;
  len: Cardinal): Boolean;
var
  lvRet: Integer;
  lpNumberOfBytesRecvd: Cardinal;
begin
  Result := False;
  if not Assigned(Self) then Exit;
  lpNumberOfBytesRecvd := 0;
  FRecvdFlag := 0;
  FRecvBuffer.buf := pvBuffer;
  FRecvBuffer.len := len;

  if FContext.IncReferenceCounter(Self, 'TIocpRecvRequest.PostRequest') then begin
    {$IFDEF DEBUG_ON}
    InterlockedIncrement(FOverlapped.refCount);
    {$ENDIF}
    lvRet := iocp.winapi.winsock.WSARecv(FContext.FRawSocket.SocketHandle,
         @FRecvBuffer, 1, lpNumberOfBytesRecvd, FRecvdFlag,
         LPWSAOVERLAPPED(@FOverlapped),   // d7 need to cast
         nil
       );
    if lvRet = SOCKET_ERROR then begin
      lvRet := WSAGetLastError;
      Result := lvRet = WSA_IO_PENDING;
      if not Result then begin
        {$IFDEF DEBUG_ON}
        FOwner.DoStateMsgE(Self, strRecv_PostError, [FContext.SocketHandle, lvRet]);
        InterlockedDecrement(FOverlapped.refCount);
        {$ENDIF}
        // trigger error event
        FOwner.DoClientContextError(FContext, lvRet);
        // decReferenceCounter
        FContext.DecReferenceCounterAndRequestDisconnect(Self,
          'TIocpRecvRequest.PostRequest.Error');
      end else begin
        if (FOwner <> nil) and (Assigned(FOwner.FDataMoniter)) then
          FOwner.FDataMoniter.incPostWSARecvCounter;
      end;
    end else begin
      Result := True;
      if (FOwner <> nil) and (Assigned(FOwner.FDataMoniter)) then
        FOwner.FDataMoniter.incPostWSARecvCounter;
    end;
  end;
end;

{ TIocpSendRequest }

procedure TIocpSendRequest.CheckClearSendBuffer;
begin
  if FLen > 0 then begin
    case FSendBufferReleaseType of
      dtDispose: Dispose(FBuf);
      dtFreeMem: FreeMem(FBuf);
      dtMemPool: FOwner.PushMem(FBuf);
    end;
  end;
  FSendBufferReleaseType := dtNone;
  FLen := 0;
end;

constructor TIocpSendRequest.Create;
begin
  inherited Create;
end;

destructor TIocpSendRequest.Destroy;
begin
  CheckClearSendBuffer;
  inherited;
end;

procedure TIocpSendRequest.DoCleanUp;
begin
  CheckClearSendBuffer;
  FBytesSize := 0;
  //FNext := nil;
  FOwner := nil;
  FContext := nil;
  FBuf := nil;
  FLen := 0;
end;

function TIocpSendRequest.ExecuteSend: Boolean;
begin
  if (FBuf = nil) or (FLen = 0) then begin
    {$IFDEF DEBUG_ON}
    FOwner.DoStateMsgD(Self, strSend_Zero, [FContext.SocketHandle]);
    {$ENDIF}
    Result := False;
  end else
    Result := InnerPostRequest(FBuf, FLen);
end;

function TIocpSendRequest.GetStateInfo: string;
begin
  Result := Format('%s %s', [Self.ClassName, Remark]);
  if Responding then
    Result := Result + sLineBreak + Format('start: %s, datalen: %d',
      [TimestampToStr(FRespondStartTime), FSendBuf.len])
  else
    Result := Result + sLineBreak + Format('start: %s, end: %s, datalen: %d',
      [TimestampToStr(FRespondStartTime), TimestampToStr(FRespondEndTime), FSendBuf.len]);
end;

procedure TIocpSendRequest.HandleResponse;
var
  lvContext: TIocpCustomContext;
begin
  lvContext := FContext;
  FIsBusying := False;
  if FOwner = nil then Exit;
  try
    if Assigned(FOwner.FDataMoniter) then begin
      FOwner.FDataMoniter.incSentSize(FBytesTransferred);
      FOwner.FDataMoniter.incResponseWSASendCounter;
    end;

    lvContext.DoSendRequestRespnonse(Self);

    if not FOwner.Active then begin
      {$IFDEF DEBUG_ON}
      FOwner.DoStateMsgD(Self, strSend_EngineOff, [lvContext.SocketHandle]);
      {$ENDIF}
      // avoid postWSARecv
      lvContext.RequestDisconnect(Self,
        Format(strSend_EngineOff, [lvContext.SocketHandle]));
    end else if ErrorCode <> 0 then begin
      if not FContext.FRequestDisconnect then begin // �������رգ����������־,�ʹ�������
        FOwner.DoClientContextError(lvContext, ErrorCode);
        FOwner.DoStateMsgD(Self, strSend_Err, [lvContext.SocketHandle, ErrorCode]);
        lvContext.RequestDisconnect(Self,
           Format(strSend_Err, [lvContext.SocketHandle, ErrorCode]));
      end;
    end else begin
      // �ɹ�
      if Assigned(FOwner.FDataMoniter) then
        FOwner.FDataMoniter.incResponseSendObjectCounter;
      if Assigned(FOnDataRequestCompleted) then
        FOnDataRequestCompleted(lvContext, Self);
      lvContext.DoSendRequestCompleted(Self);
      lvContext.PostNextSendRequest;
    end;
  finally
    lvContext.decReferenceCounter(Self, 'TIocpSendRequest.HandleResponse');
  end;
end;

function TIocpSendRequest.InnerPostRequest(buf: Pointer;
  len: Cardinal): Boolean;
var
  lvErrorCode, lvRet: Integer;
  dwFlag, lpNumberOfBytesSent: Cardinal;
  lvContext: TIocpCustomContext;
  lvOwner: TIocpCustom;
begin
  Result := False;
  FIsBusying := True;
  FBytesSize := len;
  FSendBuf.buf := buf;
  FSendBuf.len := len;
  dwFlag := 0;
  lvErrorCode := 0;
  lpNumberOfBytesSent := 0;

  // maybe on HandleResonse and release self
  lvOwner := FOwner;
  lvContext := FContext;
  if lvContext.IncReferenceCounter(Self, 'InnerPostRequest::WSASend_Start') then
  try
    lvRet := WSASend(lvContext.FRawSocket.SocketHandle,
                  @FSendBuf, 1, lpNumberOfBytesSent, dwFlag,
                  LPWSAOVERLAPPED(@FOverlapped),   // d7 need to cast
                  nil);
    if lvRet = SOCKET_ERROR then begin
      // Ͷ��ʧ��
      lvErrorCode := WSAGetLastError;
      Result := lvErrorCode = WSA_IO_PENDING;
      if not Result then begin
        //���ʹ����ͷŸ�SOCKET��Ӧ��������Դ
        FIsBusying := False;
        lvOwner.DoStateMsgE(Self, strSend_PostError, [lvContext.SocketHandle, lvErrorCode]);
        lvContext.RequestDisconnect(Self);
      end else begin
        // ���ͳɹ�����TCP/IP�㻺������������TCP/IP�㻺�����п���ĵط�������
        // �������ǵĳ��򻺳�������ʱ�Ż���ɿ�����Ȼ�󽫸�IOCPһ�������Ϣ
        if (lvOwner <> nil) and (lvOwner.FDataMoniter <> nil) then begin
          lvOwner.FDataMoniter.incPostWSASendSize(len);
          lvOwner.FDataMoniter.incPostWSASendCounter;
        end;
      end;
    end else begin
      // ���ͳɹ����Ѿ������ݷ���TCP/IP�㻺����
      Result := True;
      if (lvOwner <> nil) and (lvOwner.FDataMoniter <> nil) then begin
        lvOwner.FDataMoniter.incPostWSASendSize(len);
        lvOwner.FDataMoniter.incPostWSASendCounter;
      end;
    end;
  finally
    if not Result then begin
      // Ͷ��ʧ��ֱ�ӽ���������1�����������Ϊ0ʱ����û���κ����󣬽��ر�socket
      if IsDebugMode then
        Assert(lvContext = FContext);
      lvContext.DecReferenceCounter(Self,
        Format('InnerPostRequest::WSASend_Fail, ErrorCode:%d', [lvErrorCode]));
    end;
    // �������True�����ܻ��� HandleResponse �� dispose �򷵻ص����С�
  end;
end;

procedure TIocpSendRequest.ResponseDone;
begin
  inherited;
  if FOwner = nil then begin
    if IsDebugMode then begin
      Assert(FOwner <> nil);
      Assert(Self.FAlive);
    end;
  end else
    FOwner.ReleaseSendRequest(Self);
end;

procedure TIocpSendRequest.SetBuffer(buf: Pointer; len: Cardinal;
  pvCopyBuf: Boolean);
var
  lvBuf: PAnsiChar;
begin
  if pvCopyBuf then begin
    GetMem(lvBuf, len);
    Move(buf^, lvBuf^, len);
    SetBuffer(lvBuf, len, dtFreeMem);
  end else
    SetBuffer(buf, len, dtNone);
end;

procedure TIocpSendRequest.SetBuffer(buf: Pointer; len: Cardinal;
  pvBufReleaseType: TDataReleaseType);
begin
  CheckClearSendBuffer;
  FBuf := buf;
  FLen := len;
  FSendBufferReleaseType := pvBufReleaseType;
end;

procedure TIocpSendRequest.UnBindingSendBuffer;
begin
  FBuf := nil;
  FLen := 0;
  FSendBufferReleaseType := dtNone;
end;

{ TIocpDataMonitor }

procedure TIocpDataMonitor.Clear;
var
  L: TCriticalSection;
begin
  L := FLocker;
  FLocker.Enter;
  try
    FillChar(Pointer(IntPtr(Pointer(@Self)^)+4)^, Self.InstanceSize, 0);
    FLocker := L;
  finally
    FLocker.Leave;
  end;
end;

constructor TIocpDataMonitor.Create;
begin
  FLocker := TCriticalSection.Create;
end;

destructor TIocpDataMonitor.Destroy;
begin
  FreeAndNil(FLocker);
  inherited;
end;

procedure TIocpDataMonitor.IncAcceptExObjectCounter;
begin
  InterlockedIncrement(FAcceptExObjectCounter);
end;

procedure TIocpDataMonitor.incHandleCreateCounter;
begin
  InterlockedIncrement(FHandleCreateCounter);
end;

procedure TIocpDataMonitor.incHandleDestroyCounter;
begin
  InterlockedIncrement(FHandleDestroyCounter);
end;

procedure TIocpDataMonitor.incPostSendObjectCounter;
begin
  InterlockedIncrement(FPostSendObjectCounter);
end;

procedure TIocpDataMonitor.incPostWSARecvCounter;
begin
  InterlockedIncrement(FPostWSARecvCounter);
end;

procedure TIocpDataMonitor.incPostWSASendCounter;
begin
  InterlockedIncrement(FPostWSASendCounter);
end;

procedure TIocpDataMonitor.incPostWSASendSize(pvSize: Cardinal);
begin
  FLocker.Enter;
  FPostWSASendSize := FPostWSASendSize + pvSize;
  FLocker.Leave;
end;

procedure TIocpDataMonitor.incPushSendQueueCounter;
begin
  InterlockedIncrement(FPushSendQueueCounter);
end;

procedure TIocpDataMonitor.incRecvdSize(pvSize: Cardinal);
begin
  FLocker.Enter;
  FRecvSize := FRecvSize + pvSize;
  FLocker.Leave;
end;

procedure TIocpDataMonitor.incResponseSendObjectCounter;
begin
  InterlockedIncrement(FResponseSendObjectCounter);
end;

procedure TIocpDataMonitor.incResponseWSARecvCounter;
begin
  InterlockedIncrement(FResponseWSARecvCounter);
end;

procedure TIocpDataMonitor.incResponseWSASendCounter;
begin
  InterlockedIncrement(FResponseWSASendCounter);
end;

procedure TIocpDataMonitor.incSentSize(pvSize: Cardinal);
begin
  FLocker.Enter;
  FSentSize := FSentSize + pvSize;
  FLocker.Leave;
end;

{ TIocpConnectExRequest }

constructor TIocpConnectExRequest.Create(const AContext: TIocpCustomContext);
begin
  inherited Create;
  FContext := AContext;
end;

destructor TIocpConnectExRequest.Destroy;
begin
  inherited Destroy;
end;

function TIocpConnectExRequest.PostRequest(const Host: string; Port: Word): Boolean;
var
  lvSockAddrIn: TSockAddrIn;
  lvRet: BOOL;
  lvErrCode: Integer;
  lp: Pointer;
  lvRemoteIP: AnsiString;
begin
  {$IFDEF DEBUG_ON}
  Remark := Format(strConn_Request, [Host, Port]);
  {$ENDIF}
  try
    lvRemoteIP := FContext.Socket.DomainNameToAddr(Host);
  except
    lvRemoteIP := Host;
  end;
  FContext.SetSocketState(ssConnecting);
  lvSockAddrIn := GetSocketAddr(lvRemoteIP, Port);
  FContext.Socket.bind('0.0.0.0', 0);

  lp := @FOverlapped;
  lvRet := IocpConnectEx(FContext.Socket.SocketHandle, @lvSockAddrIn,
    sizeOf(lvSockAddrIn), nil, 0, FBytesSent, lp);
  if not lvRet then begin
    lvErrCode := WSAGetLastError;
    Result := lvErrCode = WSA_IO_PENDING;
    if not Result then begin
      FContext.DoError(lvErrCode);
      FContext.RequestDisconnect(Self, 'TIocpConnectExRequest.PostRequest');
    end;
  end else
    Result := True;
end;

{ TIocpAcceptExRequest }

constructor TIocpAcceptExRequest.Create(AOwner: TIocpCustom);
begin
  FOwner := AOwner;
  inherited Create();
end;

procedure TIocpAcceptExRequest.getPeerInfo;
const
  ADDRSIZE = SizeOf(TSockAddr) + 16;
var
  localAddr: PSockAddr;
  remoteAddr: PSockAddr;
  localAddrSize: Integer;
  remoteAddrSize: Integer;
begin
  localAddrSize := ADDRSIZE;
  remoteAddrSize := ADDRSIZE;
  IocpGetAcceptExSockaddrs(@FAcceptBuffer[0], 0,
    SizeOf(localAddr^) + 16, SizeOf(remoteAddr^) + 16,
    localAddr, localAddrSize,
    remoteAddr, remoteAddrSize);
  TIocpClientContext(FContext).FRemoteAddr := string(inet_ntoa(TSockAddrIn(remoteAddr^).sin_addr));
  TIocpClientContext(FContext).FRemotePort := ntohs(TSockAddrIn(remoteAddr^).sin_port);
end;

procedure TIocpAcceptExRequest.HandleResponse;
begin
  if (FOwner<> nil) and (FOwner.FDataMoniter <> nil) then
    InterlockedIncrement(FOwner.FDataMoniter.FResponseWSAAcceptExCounter);
  try
    if ErrorCode = 0 then begin
      // msdn
      // The socket sAcceptSocket does not inherit the properties of the socket
      //  associated with sListenSocket parameter until SO_UPDATE_ACCEPT_CONTEXT
      //  is set on the socket.
      FAcceptorMgr.FListenSocket.UpdateAcceptContext(FContext.SocketHandle);
      getPeerInfo();
    end;
    if Assigned(FOnAcceptedEx) then FOnAcceptedEx(Self);
  finally
    FOwner.DoAcceptExResponse(Self);
  end;
end;

function TIocpAcceptExRequest.PostRequest: Boolean;
var
  dwBytes: Cardinal;
  lvRet: BOOL;
  lvErrCode: Integer;
begin
  dwBytes := 0;
  FContext.CreateSocket(True);
  lvRet := IocpAcceptEx(FAcceptorMgr.FListenSocket.SocketHandle
                , FContext.FRawSocket.SocketHandle
                , @FAcceptBuffer[0]
                , 0
                , SizeOf(TSockAddrIn) + 16
                , SizeOf(TSockAddrIn) + 16
                , dwBytes
                , @FOverlapped);
  if not lvRet then begin
    lvErrCode := WSAGetLastError;
    Result := lvErrCode = WSA_IO_PENDING;
    if not Result then
      FOwner.DoClientContextError(FContext, lvErrCode);
  end else
    Result := True;
end;

procedure TIocpAcceptExRequest.ResponseDone;
begin
  inherited;
  FAcceptorMgr.ReleaseRequestObject(Self);
end;

{ TIocpAcceptorMgr }

procedure TIocpAcceptorMgr.Check(const Context: TIocpCustomContext);
var
  lvRequest: TIocpAcceptExRequest;
begin
  FLocker.Enter;
  try
    if FList.Count > FMinRequest then Exit;
    while FList.Count < FMaxRequest do begin
      lvRequest := TIocpAcceptExRequest.Create(FOwner);
      lvRequest.FContext := Context;
      lvRequest.FAcceptorMgr := Self;
      FList.Add(lvRequest);
      lvRequest.PostRequest;
      if (FOwner<> nil) and (FOwner.FDataMoniter <> nil) then
        InterlockedIncrement(FOwner.FDataMoniter.FPostWSAAcceptExCounter);
    end;
  finally
    FLocker.Leave;
  end;
end;

procedure TIocpAcceptorMgr.CheckPostRequest;
var
  lvRequest: TIocpAcceptExRequest;
  i:Integer;
begin
  Assert(FOwner <> nil);
  FLocker.Enter;
  try
    if FList.Count > FMinRequest then Exit;
    i := 0;
    // post request
    while FList.Count < FMaxRequest do  begin
      lvRequest := GetRequestObject;
      lvRequest.FContext := FOwner.GetClientContext;
      lvRequest.FAcceptorMgr := self;
      if lvRequest.PostRequest then begin
        FList.Add(lvRequest);
        if (FOwner.FDataMoniter <> nil) then
          InterlockedIncrement(FOwner.FDataMoniter.FPostWSAAcceptExCounter);
      end else begin
        // post fail
        Inc(i);
        try
          // �����쳣��ֱ���ͷ�Context
          lvRequest.FContext.Socket.Close;
          lvRequest.FContext.FAlive := false;
          lvRequest.FContext.Free;
          lvRequest.FContext := nil;
        except
        end;

        // �黹�������
        ReleaseRequestObject(lvRequest);

        if i > 100 then begin
          // Ͷ��ʧ�ܴ�������100 ��¼��־,������Ͷ��
          FOwner.DoStateMsgE(Self, 'IocpAcceptorMgr.CheckPostRequest ErrCounter: %d', [i]);
          Break;
        end;

      end;
    end;
  finally
    FLocker.Leave;
  end;
end;

constructor TIocpAcceptorMgr.Create(AOwner: TIocpCustom; AListenSocket: TRawSocket);
begin
  inherited Create;
  FOwner := AOwner;
  FListenSocket := AListenSocket;
  FLocker := TIocpLocker.Create();
  FLocker.Name := 'AcceptorLocker';
  FMaxRequest := 256;
  FMinRequest := 16;
  FList := TList.Create;
  FAcceptExRequestPool := TBaseQueue.Create;
end;

destructor TIocpAcceptorMgr.Destroy;
begin
  FAcceptExRequestPool.FreeDataObject;
  FList.Free;
  FLocker.Free;
  FreeAndNil(FAcceptExRequestPool);
  inherited Destroy;
end;

function TIocpAcceptorMgr.GetRequestObject: TIocpAcceptExRequest;
begin
  Result := TIocpAcceptExRequest(FAcceptExRequestPool.DeQueue);
  if Result = nil then begin
    Result := TIocpAcceptExRequest.Create(FOwner);
    if (FOwner.FDataMoniter <> nil) then
      FOwner.Moniter.IncAcceptExObjectCounter;
  end;
end;

procedure TIocpAcceptorMgr.Release(Request: TIocpAcceptExRequest);
begin
  Request.Free;
end;

procedure TIocpAcceptorMgr.ReleaseRequestObject(
  pvRequest: TIocpAcceptExRequest);
begin
  FAcceptExRequestPool.EnQueue(pvRequest);
end;

procedure TIocpAcceptorMgr.Remove(Request: TIocpAcceptExRequest);
begin
  FLocker.Enter;
  try
    FList.Remove(Request);
  finally
    FLocker.Leave;
  end;
end;

function TIocpAcceptorMgr.WaitForCancel(pvTimeOut: Cardinal): Boolean;
var
  l: Int64;
  c: Integer;
begin
  l := GetTimestamp;
  c := FList.Count;
  while (c > 0) do begin
    {$IFDEF MSWINDOWS}
    SwitchToThread;
    {$ELSE}
    TThread.Yield;
    {$ENDIF}
    if GetTimestamp - l > pvTimeOut then begin
      {$IFDEF WRITE_LOG}
      FOwner.DoStateMsgD(Self, 'WaitForCancel End Current AccepEx num:%d', [c]);
      {$ENDIF}
      Break;
    end;
    c := FList.Count;
  end;
  Result := FList.Count = 0;
end;

{ TIocpCustomBlockTcpSocket }

const
  RECVBUFSize = 1024 * 16;

function Min(const AValueOne, AValueTwo: Int64): Int64;
begin
  If AValueOne > AValueTwo then
    Result := AValueTwo
  else
    Result := AValueOne;
end;

function BytesToString(const ABytes: TBytes; const AStartIndex: Integer;
  AMaxCount: Integer): string;
begin
  if (AStartIndex > High(ABytes)) or (AStartIndex < 0) then
    raise Exception.Create(Format('Index (%d) out of bounds. (%d)', [AStartIndex, Length(ABytes) - 1]));
  AMaxCount := Min(Length(ABytes) - AStartIndex, AMaxCount);
  {$IFDEF DotNet}
  Result := System.Text.Encoding.ASCII.GetString(ABytes, AStartIndex, AMaxCount);
  {$ELSE}
  SetLength(Result, AMaxCount);
  if AMaxCount > 0 then
    Move(ABytes[AStartIndex], Result[1], AMaxCount);
  {$ENDIF}
end;

procedure TIocpCustomBlockTcpSocket.CheckSocketResult(pvSocketResult: Integer);
begin
  {$IFDEF POSIX}
  if (pvSocketResult = -1) or (pvSocketResult = 0) then
    RaiseLastOSError;
  {$ELSE}
  if (pvSocketResult = -1) then
    RaiseLastOSError;
  {$ENDIF}
end;

function TIocpCustomBlockTcpSocket.Connect(ATimeOut: Integer; RaiseError: Boolean): Boolean;
var
  lvIpAddr: string;
begin
  Result := FActive;
  if Result then Exit;

  if Length(FHost) = 0 then Exit;

  CreateSocket;

  lvIpAddr := FRawSocket.DomainNameToAddr(FHost);
  FActive := FRawSocket.Connect(lvIpAddr, FPort, ATimeOut);
  Result := FActive;
  if not Result then begin
    if ATimeOut > 0 then begin
      if RaiseError then       
        raise Exception.CreateFmt(strConn_TimeOut, [FHost, FPort])
    end else
      RaiseLastOSError(RaiseError);
  end
end;

function TIocpCustomBlockTcpSocket.Connect(RaiseError: Boolean): Boolean;
begin
  Result := Connect(FConnectTimeOut, RaiseError);
end;

procedure TIocpCustomBlockTcpSocket.Close;
begin
  Disconnect;
end;

function TIocpCustomBlockTcpSocket.Connect(const RemoteHost: string;
  RemotePort: Word; ATimeOut: Integer): Boolean;
var
  lvIpAddr: string;
begin
  Result := FActive;
  if Result then begin
    if (FHost = RemoteHost) and (FPort = RemotePort) then
      Exit;
    Active := False;
    Result := False;
  end;

  if Length(RemoteHost) = 0 then Exit;

  CreateSocket;

  lvIpAddr := FRawSocket.DomainNameToAddr(RemoteHost);
  FActive := FRawSocket.Connect(lvIpAddr, RemotePort, ATimeOut);
  Result := FActive;
  if not Result then begin
    if ATimeOut > 0 then
      raise Exception.CreateFmt(strConn_TimeOut, [RemoteHost, RemotePort])
    else
      RaiseLastOSError;
  end else begin
    FHost := RemoteHost;
    FPort := RemotePort;
  end;
end;

constructor TIocpCustomBlockTcpSocket.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRawSocket := TRawSocket.Create;
  FReadTimeOut := 30000;
  FConnectTimeOut := -1;
  FRecvBufferSize := -1;
end;

procedure TIocpCustomBlockTcpSocket.CreateSocket;
begin
  FRecvBufferSize := -1;
  FRawSocket.CreateTcpSocket;
  FRawSocket.SetReadTimeOut(FReadTimeOut);
end;

destructor TIocpCustomBlockTcpSocket.Destroy;
begin
  FreeAndNil(FRawSocket);
  FreeAndNil(FStream);
  FreeAndNil(FBuffer);
  inherited;
end;

procedure TIocpCustomBlockTcpSocket.Disconnect;
begin
  if not FActive then Exit;
  FRecvBufferSize := -1;
  FRawSocket.Close;
  FActive := False;
end;

function TIocpCustomBlockTcpSocket.DomainNameToAddr(const host: string): string;
begin
  Result := FRawSocket.DomainNameToAddr(host);
end;

function TIocpCustomBlockTcpSocket.GetErrorCode: Integer;
begin
  Result := FErrorCode;
  FErrorCode := 0;
end;

function TIocpCustomBlockTcpSocket.GetRecvBufferIsEmpty: Boolean;
begin
  if FRecvBufferSize < 0 then begin
    FRecvBufferSize := GetRecvBufferSize();
    if FRecvBufferSize = 0 then
      FRecvBufferSize := -1;
  end;
  Result := FRecvBufferSize < 1;
end;

function TIocpCustomBlockTcpSocket.GetRecvBufferSize: Cardinal;
begin
  if Assigned(FRawSocket) and (FRawSocket.SocketHandle <> INVALID_SOCKET) then
    ioctlsocket(FRawSocket.SocketHandle, FIONREAD, Result)
  else
    Result := 0;
end;

function TIocpCustomBlockTcpSocket.GetRecvStream: TStream;
begin
  if not Assigned(FStream) then
    FStream := TIocpBlockSocketStream.Create(Self)
  else if FStream.FSocket <> Self then
    FStream.FSocket := Self;
  Result := FStream;
  TIocpBlockSocketStream(Result).FReadTimeOut := ReadTimeOut;
end;

function TIocpCustomBlockTcpSocket.IsConnected: Boolean;
begin
  Result := FActive and Assigned(FRawSocket) and (FRawSocket.Connected);
  if not Result then
    FActive := False;
end;

class function TIocpCustomBlockTcpSocket.IsIP(v: PAnsiChar): Longint;
begin
  Result := inet_addr(v);
end;

procedure TIocpCustomBlockTcpSocket.Open;
begin
  SetActive(True);
end;

procedure TIocpCustomBlockTcpSocket.RaiseLastOSError(RaiseErr: Boolean);
begin
  FRecvBufferSize := -1;
  FErrorCode := GetLastError;
  if (FErrorCode = WSAENOTSOCK)         // �����ֲ���һ���׽ӿڡ�
    or (FErrorCode = WSAECONNABORTED)   // ���ڳ�ʱ������ԭ�����·ʧЧ��
    or (FErrorCode = WSAECONNRESET)     // Զ��ǿ����ֹ�����·��
    or (FErrorCode = WSAESHUTDOWN)      // �׽ӿ��ѱ��ر�
    or (FErrorCode = WSAEINVAL)         // �׽ӿ�δ��bind()��������
    or (FErrorCode = WSAENOTCONN)       // �׽ӿ�δ���ӡ�
  then begin
    Disconnect; // ���ӶϿ�
    if RaiseErr then
      SysUtils.RaiseLastOSError(FErrorCode);
  end else
    SysUtils.RaiseLastOSError(FErrorCode);
end;

function TIocpCustomBlockTcpSocket.ReadBytes(var Buffer: TBytes;
  AByteCount: Integer; AAppend: Boolean): Integer;
var
  J: Integer;
  P: Pointer;
begin
  if not Assigned(FBuffer) then
    FBuffer := TMemoryStream.Create;
  P := Pointer(Cardinal(FBuffer.Memory) + FBuffer.Position);
  Result := ReadStream(FBuffer, AByteCount);
  if Result > 0 then begin
    if AAppend then begin
      J := Length(Buffer);
      SetLength(Buffer, J + Result);
      Move(P^, Buffer[J], Result);
    end else begin
      SetLength(Buffer, Result);
      Move(P^, Buffer[0], Result);
    end;
    FBuffer.Clear;
  end;
end;

function TIocpCustomBlockTcpSocket.ReadChar: Char;
begin
  Recv(@Result, SizeOf(Result));
end;

function TIocpCustomBlockTcpSocket.ReadDouble: Double;
begin
  Result := 0;
  Recv(@Result, SizeOf(Result));
end;

function TIocpCustomBlockTcpSocket.ReadInt64: Int64;
begin
  Result := 0;
  Recv(@Result, SizeOf(Result));
end;

function TIocpCustomBlockTcpSocket.ReadInteger: Integer;
begin
  Result := 0;
  Recv(@Result, SizeOf(Result));
end;

function TIocpCustomBlockTcpSocket.ReadSmallInt: SmallInt;
begin
  Result := 0;
  Recv(@Result, SizeOf(Result));
end;

function TIocpCustomBlockTcpSocket.ReadStream(OutStream: TStream;
  Len: Integer; WaitRecvLen: Boolean): Integer;
const
  BUFSize = 4096;
var
  lvTempL: Integer;
  Buf: array [0..BUFSize - 1] of Byte;
begin
  Result := 0;
  FRecvBufferSize := -1;
  if Len > 0 then begin
    while True do begin
      if Len > BUFSize then
        lvTempL := FRawSocket.RecvBuf(Buf, BUFSize)
      else
        lvTempL := FRawSocket.RecvBuf(Buf, Len);
      if lvTempL > 0 then begin
        OutStream.WriteBuffer(Buf, lvTempL);
        Dec(Len, lvTempL);
        Inc(Result, lvTempL);
        if (Len = 0) or ((lvTempL < BUFSize) and (not WaitRecvLen)) then Break;
      end else begin
        if (lvTempL < 0){$IFDEF POSIX} or (lvTempL = 0){$ENDIF} then
          RaiseLastOSError(False);
        Break;
      end;
    end;
  end else begin
    while True do begin
      lvTempL := FRawSocket.RecvBuf(Buf, BUFSize);
      if lvTempL > 0 then begin
        OutStream.WriteBuffer(Buf, lvTempL);
        Inc(Result, lvTempL);
        if lvTempL < BUFSize then Break;        
      end else begin
        if (lvTempL < 0){$IFDEF POSIX} or (lvTempL = 0){$ENDIF} then
          RaiseLastOSError(False);
        Break;
      end;
    end;
  end;
end;

function TIocpCustomBlockTcpSocket.ReadString(const ABytes: Integer): string;
const
  MaxRecvSize = 1024 * 1024 * 8;
var
  I: Integer;
  Last: Int64;
begin
  if not Assigned(FBuffer) then begin
    FBuffer := TMemoryStream.Create;
    Last := 0;
  end else
    Last := FBuffer.Position;
  if ABytes < 1 then
    I := ReadStream(FBuffer, MaxRecvSize)
  else
    I := ReadStream(FBuffer, ABytes);
  if I > 0 then begin
    SetString(Result, PAnsiChar(Cardinal(FBuffer.Memory) + Last), I);
    FBuffer.Clear;
  end else
    Result := '';
end;

function TIocpCustomBlockTcpSocket.ReadWord: Word;
begin
  Result := 0;
  Recv(@Result, SizeOf(Result));
end;

function TIocpCustomBlockTcpSocket.Recv(buf: Pointer; len: Cardinal): Cardinal;
var
  lvTempL :Integer;
  lvPBuf: Pointer;
begin
  Result := 0;
  FRecvBufferSize := -1;
  lvPBuf := buf;
  while Result < len do begin
    if len - Result > RECVBUFSize then
      lvTempL := RECVBUFSize
    else
      lvTempL := len - Result;
    lvTempL := FRawSocket.RecvBuf(lvPBuf^, lvTempL);
    CheckSocketResult(lvTempL);
    lvPBuf := Pointer(Cardinal(lvPBuf) + Cardinal(lvTempL));
    Result := Result + Cardinal(lvTempL);
    if lvTempL < RECVBUFSize then
      Break;
  end;
end;

function TIocpCustomBlockTcpSocket.Recv(Len: Integer): AnsiString;
begin
  Result := ReadString(Len);
end;

function TIocpCustomBlockTcpSocket.RecvBuffer(buf: Pointer;
  len: cardinal): Integer;
begin
  FRecvBufferSize := -1;
  Result := FRawSocket.RecvBuf(buf^, len);
  CheckSocketResult(Result);
end;

function TIocpCustomBlockTcpSocket.Send(buf: Pointer; len: Cardinal): Cardinal;
begin
  Result := SendBuffer(buf, len);
end;

function TIocpCustomBlockTcpSocket.Send(const Data: WideString): Cardinal;
begin
  if Length(Data) = 0 then
    Result := 0
  else
    Result := SendBuffer(@Data[1], Length(Data) shl 1);
end;

function TIocpCustomBlockTcpSocket.Send(const Data: AnsiString): Cardinal;
begin
  if Length(Data) = 0 then
    Result := 0
  else
    Result := SendBuffer(@Data[1], Length(Data));
end;

procedure TIocpCustomBlockTcpSocket.Send(Stream: TStream; SendSize: Integer);
var
  buf: array [0..4095] of Byte;
  BytesRead, SendRef: Integer;
begin
  if (SendSize < 0) or (SendSize > stream.Size - stream.Position) then
    SendSize := stream.Size - stream.Position;
  if SendSize = 0 then Exit;
  SendRef := 0;
  while SendRef < SendSize do begin
    if SendSize - SendRef < SizeOf(buf) then
      BytesRead := SendSize - SendRef
    else
      BytesRead := SizeOf(buf);
    BytesRead := stream.Read(buf, bytesRead);
    SendBuffer(@buf[0], BytesRead);
    Inc(SendRef, BytesRead);
  end;
end;

{$IFDEF UNICODE}
function TIocpCustomBlockTcpSocket.Send(const Data: UnicodeString): Cardinal;
begin
  if Length(Data) = 0 then
    Result := 0
  else
    Result := SendBuffer(@Data[1], Length(Data) shl 1);
end;
{$ENDIF}

function TIocpCustomBlockTcpSocket.SendBuffer(buf: Pointer;
  len: cardinal): Integer;
begin
  Result := FRawSocket.SendBuf(buf^, len);
  CheckSocketResult(Result);
end;

procedure TIocpCustomBlockTcpSocket.SetActive(const Value: Boolean);
begin
  if (FActive = Value) then Exit;
  if Value then
    Connect
  else
    Disconnect;
end;

function TIocpCustomBlockTcpSocket.SetKeepAlive(
  pvKeepAliveTime: Integer): Boolean;
begin
  Result := Assigned(FRawSocket) and (FRawSocket.SetKeepAliveOption(pvKeepAliveTime));
end;

procedure TIocpCustomBlockTcpSocket.SetReadTimeOut(const Value: Integer);
begin
  if FReadTimeOut <> Value then begin
    FReadTimeOut := Value;
    if Assigned(FRawSocket) then
      FRawSocket.SetReadTimeOut(Value);
  end;
end;

function TIocpCustomBlockTcpSocket.Seek(Len: Integer): Boolean;
const
  BUFSize = 4096;
var
  lvTempL: Integer;
  Buf: array [0..BUFSize - 1] of Byte;
begin
  if Active then begin
    lvTempL := BUFSize;
    if Len > 0 then begin
      while lvTempL = BUFSize do begin
        if Len > BUFSize then
          lvTempL := FRawSocket.RecvBuf(Buf, BUFSize)
        else
          lvTempL := FRawSocket.RecvBuf(Buf, Len);
        CheckSocketResult(lvTempL);
        Dec(Len, lvTempL);
      end;
    end else begin
      while lvTempL = BUFSize do begin
        lvTempL := FRawSocket.RecvBuf(Buf, BUFSize);
        CheckSocketResult(lvTempL);
      end;
    end;
    Result := True;
  end else
    Result := False;
end;

{ TIocpCustomBlockUdpSocket }

procedure TIocpCustomBlockUdpSocket.CreateSocket;
begin
  FRawSocket.CreateUdpSocket;
  FRawSocket.SetReadTimeOut(FReadTimeOut);
end;

function TIocpCustomBlockUdpSocket.Send(buf: Pointer; len: Cardinal;
  const Addr: string; Port: Word): Cardinal;
begin
  if Connect(Addr, Port) then begin
    Result := SendBuffer(buf, len);
  end else
    Result := 0;
end;

function TIocpCustomBlockUdpSocket.Send(const Data: WideString;
  const Addr: string; Port: Word): Cardinal;
begin
  if Connect(Addr, Port) then
    Result := Send(Data)
  else
    Result := 0;
end;

function TIocpCustomBlockUdpSocket.Send(const Data: AnsiString;
  const Addr: string; Port: Word): Cardinal;
begin
  if Connect(Addr, Port) then
    Result := Send(Data)
  else
    Result := 0;
end;

{$IFDEF UNICODE}
function TIocpCustomBlockUdpSocket.Send(const Data: UnicodeString;
  const Addr: string; Port: Word): Cardinal;
begin
  if Connect(Addr, Port) then
    Result := Send(Data)
  else
    Result := 0;
end;
{$ENDIF}

type
  TTimeOutClearThread = class(TThread)
  protected
    FOwner: TIocpCustomTcpServer;
    procedure Execute; override;
  end;

procedure TTimeOutClearThread.Execute();
var
  T: Int64;
begin
  if not Assigned(FOwner) then Exit;
  T := GetTimestamp;
  while not Self.Terminated do begin
    if Assigned(FOwner) and (GetTimestamp - T > 10000) then begin
      T := GetTimestamp;
      try
        FOwner.DoCleaerTimeOutConnection();
      except
        if Assigned(FOwner) then
          FOwner.DoStateMsgE(Self, Exception(ExceptObject));
      end;
    end;
    Sleep(1000);
  end;
end;

{ TIocpCustomTcpServer }

procedure TIocpCustomTcpServer.Close;

  procedure DoCloseTimeOut();
  begin
    DoStateMsg(Self, iocp_mt_Warning, Self.Name +
        'CloseTimeOut. '#13#10'EngineWorkerInfo: ' + sLineBreak +
        FIocpEngine.GetStateInfo + sLineBreak +
        '================================================'#1310 +
        'TcpServerInfo:'#1310 + GetStateInfo);
  end;

begin
  if not FActive then Exit;
  DoStateMsgD(Self, 'Server Closeing...');
  FActive := False;
  if Assigned(FListenSocket) then
    FListenSocket.Close;
  FreeAndNil(FTimeOutClearThd);
  DisconnectAll;
  // �ȴ����е�Ͷ�ݵ�AcceptEx����ع�
  FIocpAcceptorMgr.WaitForCancel(12000);
  if not WaitForContext(120000) then begin
    Sleep(10);
    if not FIocpEngine.StopWorkers(10000) then begin
      // record info
      DoCloseTimeOut();
    end else begin
      if not FIocpEngine.StopWorkers(120000) then begin
        // record info
        DoCloseTimeOut();
      end;
    end;
  end;
  FIocpAcceptorMgr.FAcceptExRequestPool.FreeDataObject;
  FIocpAcceptorMgr.FAcceptExRequestPool.Clear;

  FContextPool.FreeDataObject;
  FContextPool.Clear;

  FSendRequestPool.FreeDataObject;
  FSendRequestPool.Clear;
  // engine Stop
  FIocpEngine.Stop;
  DoStateMsgD(Self, 'Server Closed.');
end;

constructor TIocpCustomTcpServer.Create(AOwner: TComponent);
begin
  DoStateMsgD(Self, 'Server Create...');
  inherited Create(AOwner);
  // Ĭ�ϲ���������ѡ��
  FKeepAlive := False;
  FPort := 9000;
  FMaxSendingQueueSize := 256;
  FKickOutInterval := 60000;
  FListenSocket := TRawSocket.Create;
  FIocpAcceptorMgr := TIocpAcceptorMgr.Create(Self, FListenSocket);
  FIocpAcceptorMgr.FMaxRequest := 256;
  FIocpAcceptorMgr.FMinRequest := 32;
  FContextPool := TBaseQueue.Create;
  DoStateMsgD(Self, 'Server Created.');
end;

function TIocpCustomTcpServer.CreateContext: TIocpCustomContext;
begin
  if FContextClass <> nil then
    Result := FContextClass.Create(Self)
  else
    Result := TIocpClientContext.Create(Self);
  OnCreateContext(Result);
end;

procedure TIocpCustomTcpServer.CreateSocket;
begin
  FListenSocket.CreateTcpSocket(True);
  // �������˿�
  if not FListenSocket.Bind(FBindAddr, FPort) then
    RaiseLastOSError;
  // ��������
  if not FListenSocket.listen() then
    RaiseLastOSError;
  // �������׽��ְ󶨵�IOCP���
  FIocpEngine.IocpCore.Bind(FListenSocket.SocketHandle, 0);
  // post AcceptEx request
  FIocpAcceptorMgr.CheckPostRequest;
end;

destructor TIocpCustomTcpServer.Destroy;
begin
  inherited Destroy;
  FreeAndNil(FListenSocket);
  FreeAndNil(FIocpAcceptorMgr);
  FreeAndNil(FContextPool);
end;

procedure TIocpCustomTcpServer.DoAcceptExResponse(pvRequest: TIocpAcceptExRequest);
{$IFDEF SOCKET_REUSE}
var
  lvErrCode:Integer;
{$ELSE}
var
  lvRet:Integer;
  lvErrCode:Integer;
{$ENDIF}
  function DoAfterAcceptEx():Boolean;
  begin
    Result := true;
    if Assigned(FOnContextAccept) then begin
      FOnContextAccept(pvRequest.FContext.SocketHandle,
         TIocpClientContext(pvRequest.FContext).RemoteAddr,
         TIocpClientContext(pvRequest.FContext).RemotePort, Result);

      {$IFDEF WRITE_LOG}
      if not Result then
        DoStateMsgD(Self, 'OnAcceptEvent AllowAccept is False.');
      {$ENDIF}
    end;
    if Result then begin
      if FKeepAlive then begin
        Result := SetKeepAlive(pvRequest.FContext.SocketHandle, 10000);
        if not Result then begin
          lvErrCode := GetLastError;
          {$IFDEF WRITE_LOG}
          DoStateMsgE(Self, 'AcceptEx Response AfterAccept. Socket.SetKeepAlive Error: %d', [lvErrCode]);
          {$ENDIF}
        end;
      end;
    end;

  end;
begin
  if pvRequest.ErrorCode = 0 then begin
    if DoAfterAcceptEx then begin
      {$IFDEF SOCKET_REUSE}
      pvRequest.FClientContext.DoConnected;
      {$ELSE}
      lvRet := FIocpEngine.IocpCore.Bind(pvRequest.FContext.SocketHandle, 0);
      if lvRet = 0 then begin
        // binding error
        lvErrCode := GetLastError;
        {$IFDEF WRITE_LOG}
        DoStateMsgE(Self, 'Bind IOCPHandle(%d) in Context DoAcceptExResponse occur Error: %d',
            [pvRequest.FContext.SocketHandle, lvErrCode]);
        {$ENDIF}

        DoClientContextError(pvRequest.FContext, lvErrCode);
        pvRequest.FContext.FRawSocket.Close;

        // relase client context object
        ReleaseClientContext(pvRequest.FContext);
        pvRequest.FContext := nil;
      end else
        pvRequest.FContext.DoConnected;
      {$ENDIF}

    end else begin
     {$IFDEF SOCKET_REUSE}
      pvRequest.FContext.FRawSocket.ShutDown;
      // post disconnectEx
      pvRequest.FContext.FDisconnectExRequest.DirectlyPost;
      pvRequest.FContext := nil;
     {$ELSE}
      pvRequest.FContext.FRawSocket.Close;

      // return to pool
      ReleaseClientContext(pvRequest.FContext);
      pvRequest.FContext := nil;
      {$ENDIF}
    end;

  end else begin
   {$IFDEF SOCKET_REUSE}

   {$ELSE}
    pvRequest.FContext.FRawSocket.Close;
   {$ENDIF}
    // �黹�����������ĳ�
    ReleaseClientContext(pvRequest.FContext);
    pvRequest.FContext := nil;
  end;

  // ������������б����Ƴ�
  FIocpAcceptorMgr.Remove(pvRequest);
  if FActive then
    FIocpAcceptorMgr.CheckPostRequest;
end;

procedure TIocpCustomTcpServer.DoCleaerTimeOutConnection();
begin
  if not Assigned(Self) or IsDestroying then Exit;
  try
    if FKickOutInterval < 1000 then
      KickOut(1000)
    else
      KickOut(FKickOutInterval);
  except
    DoStateMsgE(Self, Exception(ExceptObject));
  end;
end;

function TIocpCustomTcpServer.FindContext(SocketHandle: TSocket): TIocpClientContext;
var
  Item: PHashValue;
begin
  Item := FOnlineContextList.ValueOf(Cardinal(SocketHandle));
  if Item <> nil then
    Result := TIocpClientContext(Item.Data)
  else
    Result := nil;
end;

function TIocpCustomTcpServer.GetClientContext: TIocpCustomContext;
begin
  Result := TIocpClientContext(FContextPool.DeQueue);
  if Result = nil then begin
    Result := CreateContext;
    if (FDataMoniter <> nil) then
      InterlockedIncrement(FDataMoniter.FContextCreateCounter);
    Result.FSendRequestList.MaxSize := FMaxSendingQueueSize;
  end;
  Result.FAlive := True;
  Result.DoCleanUp;
  Result.FOwner := Self;
  if (FDataMoniter <> nil) then
    InterlockedIncrement(FDataMoniter.FContextOutCounter);
end;

function TIocpCustomTcpServer.GetClientCount: Integer;
begin
  Result := FOnlineContextList.Count;
end;

function TIocpCustomTcpServer.GetStateInfo: string;
var
  lvStrings:TStrings;
begin
  Result := '';
  if not Assigned(FDataMoniter) then exit;
  lvStrings := TStringList.Create;
  try
    if Active then
      lvStrings.Add(strState_Active)
    else
      lvStrings.Add(strState_Off);

    lvStrings.Add(Format(strRecv_PostInfo,
         [
           Moniter.PostWSARecvCounter,
           Moniter.ResponseWSARecvCounter,
           Moniter.PostWSARecvCounter -
           Moniter.ResponseWSARecvCounter
         ]
        ));


    lvStrings.Add(Format(strRecv_SizeInfo, [TransByteSize(Moniter.RecvSize)]));

    //  Format('post:%d, response:%d, recvd:%d',
    //     [
    //       FIocpTcpServer.DataMoniter.PostWSARecvCounter,
    //       FIocpTcpServer.DataMoniter.ResponseWSARecvCounter,
    //       FIocpTcpServer.DataMoniter.RecvSize
    //     ]
    //    );

    lvStrings.Add(Format(strSend_Info,
       [
         Moniter.PostWSASendCounter,
         Moniter.ResponseWSASendCounter,
         Moniter.PostWSASendCounter -
         Moniter.ResponseWSASendCounter
       ]
      ));

    lvStrings.Add(Format(strSendRequest_Info,
       [
         Moniter.SendRequestCreateCounter,
         Moniter.SendRequestOutCounter,
         Moniter.SendRequestReturnCounter
       ]
      ));

    lvStrings.Add(Format(strSendQueue_Info,
       [
         Moniter.PushSendQueueCounter,
         Moniter.PostSendObjectCounter,
         Moniter.ResponseSendObjectCounter,
         Moniter.SendRequestAbortCounter
       ]
      ));

    lvStrings.Add(Format(strSend_SizeInfo, [TransByteSize(Moniter.SentSize)]));

    lvStrings.Add(Format(strAcceptEx_Info,
       [
         Moniter.PostWSAAcceptExCounter,
         Moniter.ResponseWSAAcceptExCounter
       ]
      ));

    lvStrings.Add(Format(strSocketHandle_Info,
       [
         Moniter.HandleCreateCounter,
         Moniter.HandleDestroyCounter
       ]
      ));

    lvStrings.Add(Format(strContext_Info,
       [
         Moniter.ContextCreateCounter,
         Moniter.ContextOutCounter,
         Moniter.ContextReturnCounter
       ]
      ));

    lvStrings.Add(Format(strOnline_Info, [ClientCount]));
    lvStrings.Add(Format(strWorkers_Info, [WorkerCount]));
    lvStrings.Add(Format(strRunTime_Info, [GetRunTimeInfo]));

    Result := lvStrings.Text;
  finally
    lvStrings.Free;

  end;
end;

procedure TIocpCustomTcpServer.KickOut(pvTimeOut: Cardinal);
var
  lvNowTickCount: Int64;
  Item, Next: PHashMapLinkItem;
  lvContext: TIocpCustomContext;
begin
  lvNowTickCount := GetTimestamp;
  Item := nil;
  Next := nil;
  while True do begin
    FLocker.Enter('KickOut');
    try
      if Item = nil then
        Item := FOnlineContextList.First
      else
        Item := Next;
      if Item <> nil then
        Next := Item.Next
      else
        Exit;
      lvContext := HashItemToContext(Item);
      if Assigned(lvContext) and (lvContext.FLastActivity <> 0) then begin
        if lvNowTickCount - lvContext.FLastActivity > pvTimeOut then
          // ����ر�
          lvContext.PostWSACloseRequest();
      end;
    finally
      FLocker.Leave;
    end;
  end;
end;

procedure TIocpCustomTcpServer.Open;
begin
  if FActive then Exit;
  FActive := True;
  try
    if Assigned(FDataMoniter) then
      FDataMoniter.Clear;
    // ����IOCP����
    FIocpEngine.Start;
    // �����������׽���
    CreateSocket;
    // ��ʼ��һ����ʱ�����߳�
    FreeAndNil(FTimeOutClearThd);
    FTimeOutClearThd := TTimeOutClearThread.Create(True);
    TTimeOutClearThread(FTimeOutClearThd).FOwner := Self;
    FTimeOutClearThd.Resume;
    FTimeOutClearThd.Suspended := False;
  except
    FActive := False;
    FListenSocket.Close;
  end;
end;

procedure TIocpCustomTcpServer.RegisterContextClass(
  pvContextClass: TIocpContextClass);
begin
  FContextClass := pvContextClass;
end;

procedure TIocpCustomTcpServer.RegisterSendRequestClass(
  pvClass: TIocpSendRequestClass);
begin
  FSendRequestClass := pvClass;
end;

function TIocpCustomTcpServer.ReleaseClientContext(
  const pvObject: TIocpCustomContext): Boolean;
begin
  Result := false;
  if not Assigned(pvObject) then Exit;
  if lock_cmp_exchange(True, False, pvObject.FAlive) = true then begin
    pvObject.DoCleanUp;
    FContextPool.EnQueue(pvObject);
    if (FDataMoniter <> nil) then
      InterlockedIncrement(FDataMoniter.FContextReturnCounter);
    Result := true;
  end;
end;

procedure TIocpCustomTcpServer.SetMaxSendingQueueSize(pvSize: Integer);
begin
  if pvSize <= 0 then
    FMaxSendingQueueSize := 10
  else
    FMaxSendingQueueSize := pvSize;
end;

procedure TIocpCustomTcpServer.Start;
begin
  Open;
end;

procedure TIocpCustomTcpServer.Stop;
begin
  Close;
end;

{ TIocpClientContext }

procedure TIocpClientContext.CloseConnection;
begin
  PostWSACloseRequest;
end;

constructor TIocpClientContext.Create(AOwner: TIocpCustom);
begin
  inherited Create(AOwner);
  {$IFDEF SOCKET_REUSE}
  FDisconnectExRequest := TIocpDisconnectExRequest.Create;
  FDisconnectExRequest.FOwner := AOwner;
  FDisconnectExRequest.FContext := Self;
  FDisconnectExRequest.OnResponse := OnDisconnectExResponse;
  {$ENDIF}
end;

destructor TIocpClientContext.Destroy;
begin
  {$IFDEF SOCKET_REUSE}
  FDisconnectExRequest.Free;
  {$ENDIF}
  inherited Destroy;
end;

procedure TIocpClientContext.Disconnect;
begin
  PostWSACloseRequest;
end;

function TIocpClientContext.GetBindIP: string;
var
  name: sockaddr;
  l: Integer;
begin
  if FSocketHandle <> INVALID_SOCKET then begin
    l := SizeOf(name);
    if getsockname(FSocketHandle, name, l) = S_OK then
      Result := string(inet_ntoa(TSockAddrIn(name).sin_addr))
    else
      Result := '';
  end else
    Result := '';
end;

function TIocpClientContext.GetBindPort: Word;
begin
  if Assigned(FOwner) then
    Result := TIocpCustomTcpServer(FOwner).ListenPort
  else
    Result := 0;
end;

function TIocpClientContext.GetPeerAddr: Cardinal;
begin
  if (Length(FRemoteAddr) > 0) then
    Result := ipToInt(FRemoteAddr)
  else
    Result := 0;
end;

procedure TIocpClientContext.ReleaseClientContext;
begin
  FOwner.ReleaseClientContext(Self);
end;

{$IFDEF SOCKET_REUSE}
procedure TIocpClientContext.OnDisconnectExResponse(pvObject: TObject);
var
  lvRequest:TIocpDisconnectExRequest;
begin
  if FActive then begin   // already connected
    lvRequest :=TIocpDisconnectExRequest(pvObject);
    if lvRequest.FErrorCode <> 0 then begin
      CloseSocket;
      if (FOwner.FDataMoniter <> nil) then
        FOwner.FDataMoniter.incHandleDestroyCounter;
      DecReferenceCounter(lvRequest,
          Format('TIocpDisconnectExRequest.HandleResponse.Error, %d', [lvRequest.FErrorCode]));
    end else
      DecReferenceCounter(lvRequest, 'TIocpDisconnectExRequest.HandleResponse');
  end else
    // not connected, onaccept allow is false
    FOwner.releaseClientContext(Self);
end;
{$ENDIF}

{ TIocpRemoteContext }

function TIocpRemoteContext.CanAutoReConnect: Boolean;
begin
  Result := FAutoReConnect and (Owner.Active) and
    (not TIocpCustomTcpClient(Owner).DisableAutoConnect);
end;

procedure TIocpRemoteContext.Connect(ASync: Boolean);
var
  lvRemoteIP: string;
begin
  if Length(FHost) = 0 then
    Exit;
  if SocketState <> ssDisconnected then
    raise Exception.Create(strCannotConnect);

  ReCreateSocket;
  if ASync then
    PostConnectRequest
  else begin
    try
      lvRemoteIP := Socket.DomainNameToAddr(FHost);
    except
      lvRemoteIP := FHost;
    end;
    if not Socket.Connect(lvRemoteIP, FPort) then
      RaiseLastOSError;
    DoConnected;
  end;
end;

procedure TIocpRemoteContext.Connect(const AHost: string; APort: Word;
  ASync: Boolean);
begin
  FHost := AHost;
  FPort := APort;
  Connect(ASync);
end;

constructor TIocpRemoteContext.Create(AOwner: TIocpCustom);
begin
  inherited Create(AOwner);
  FAutoReConnect := False;
  FIsConnecting := False;
  FConnectExRequest := TIocpConnectExRequest.Create(Self);
  FConnectExRequest.OnResponse := OnConnecteExResponse;
end;

destructor TIocpRemoteContext.Destroy;
begin
  FreeAndNil(FConnectExRequest);
  inherited Destroy;
end;

procedure TIocpRemoteContext.OnConnected;
begin
  inherited OnConnected;
  FLastDisconnectTime := 0;  // ���öϿ�ʱ��
end;

procedure TIocpRemoteContext.OnConnecteExResponse(pvObject: TObject);
begin
  FIsConnecting := False;
  if TIocpConnectExRequest(pvObject).ErrorCode = 0 then
    DoConnected
  else begin
    {$IFDEF DEBUG_ON}
    if Assigned(Owner) then
      Owner.DoStateMsgE(Self, strConnectError, [TIocpConnectExRequest(pvObject).ErrorCode]);
    {$ENDIF}

    DoError(TIocpConnectExRequest(pvObject).ErrorCode);

    if (CanAutoReConnect) then begin
      Sleep(100);
      PostConnectRequest;
    end else
      SetSocketState(ssDisconnected);
  end;
end;

procedure TIocpRemoteContext.OnDisconnected;
begin
  inherited OnDisconnected;
end;

procedure TIocpRemoteContext.PostConnectRequest;
begin
  if lock_cmp_exchange(False, True, FIsConnecting) = False then begin
    if (Socket.SocketHandle = INVALID_SOCKET) then
      ReCreateSocket;

    if not FConnectExRequest.PostRequest(FHost, FPort) then begin
      FIsConnecting := False;
      Sleep(RECONNECT_INTERVAL);
      if CanAutoReConnect then
        PostConnectRequest;
    end;
  end;
end;

procedure TIocpRemoteContext.ReCreateSocket;
begin
  Socket.CreateTcpSocket(True);
  FSocketHandle := Socket.SocketHandle;
  if not Socket.bind('0.0.0.0', 0) then
    RaiseLastOSError;
  Owner.Engine.IocpCore.Bind(FSocketHandle, 0);
end;

procedure TIocpRemoteContext.ReleaseClientContext;
begin
  if not FAutoReConnect then
    FOwner.ReleaseClientContext(Self)
  else
    inherited;
end;

procedure TIocpRemoteContext.SetSocketState(pvState: TSocketState);
begin
  inherited SetSocketState(pvState);
  if pvState = ssDisconnected then begin
    // ��¼���Ͽ�ʱ��
    FLastDisconnectTime := GetTimestamp;
    if CanAutoReConnect then
      TIocpCustomTcpClient(Owner).PostReconnectRequestEvent(Self);
  end;
end;

{ TIocpCustomTcpClient }

function TIocpCustomTcpClient.Add: TIocpRemoteContext;
begin
  Result := TIocpRemoteContext(CreateContext());
  FList.Add(Result);
end;

function TIocpCustomTcpClient.Connect(const Host: string; Port: Word;
  AutoReConnect, ASync: Boolean): TIocpRemoteContext;
begin
  Result := nil;
  if Length(Host) = 0 then Exit;
  Open;
  Result := Add();
  if not Assigned(Result) then Exit;
  Result.Host := Host;
  Result.Port := Port;
  Result.AutoReConnect := AutoReConnect;
  Result.Connect(ASync);
end;

constructor TIocpCustomTcpClient.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  {$IFDEF UNICODE}
  FList := TObjectList<TIocpRemoteContext>.Create();
  {$ELSE}
  FList := TObjectList.Create();
  {$ENDIF}
  FDisableAutoConnect := False;
  FReconnectRequestPool := TObjectPool.Create(CreateReconnectRequest);
end;

function TIocpCustomTcpClient.CreateContext: TIocpCustomContext;
begin
  if FContextClass = nil then
    Result := TIocpRemoteContext.Create(Self)
  else
    Result := TIocpRemoteContext(FContextClass.Create(Self));
  OnCreateContext(Result);
end;

function TIocpCustomTcpClient.CreateReconnectRequest: TObject;
begin
  Result := TIocpASyncRequest.Create;
end;

procedure TIocpCustomTcpClient.Delete(Index: Integer);
var
  Context: TIocpRemoteContext;
begin
  Context := Items[index];
  Context.FAutoReConnect := False;
  Context.Disconnect;
end;

destructor TIocpCustomTcpClient.Destroy;
begin
  Close;
  FReconnectRequestPool.WaitFor(5000);
  FList.Clear;
  FList.Free;
  FReconnectRequestPool.Free;
  inherited Destroy;
end;

function TIocpCustomTcpClient.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TIocpCustomTcpClient.GetItems(Index: Integer): TIocpRemoteContext;
begin
  {$IFDEF UNICODE}
  Result := FList[Index];
  {$ELSE}
  Result := TIocpRemoteContext(FList[Index]);
  {$ENDIF}
end;

procedure TIocpCustomTcpClient.OnReconnectRequestResponse(pvObject: TObject);
var
  lvContext: TIocpRemoteContext;
  lvRequest: TIocpASyncRequest;
begin
  // �˳�
  if (not Self.Active) then Exit;

  lvRequest := TIocpASyncRequest(pvObject);
  lvContext := TIocpRemoteContext(lvRequest.Data);

  if GetTimestamp - lvContext.FLastDisconnectTime >= RECONNECT_INTERVAL then begin
    // Ͷ����������������
    lvContext.PostConnectRequest();
  end else begin
    Sleep(100);
    // �ٴ�Ͷ����������
    PostReconnectRequestEvent(lvContext);
  end;
end;

procedure TIocpCustomTcpClient.OnReconnectRequestResponseDone(
  pvObject: TObject);
begin
  FReconnectRequestPool.ReleaseObject(pvObject);
end;

procedure TIocpCustomTcpClient.PostReconnectRequestEvent(
  const pvContext: TIocpRemoteContext);
var
  lvRequest: TIocpASyncRequest;
begin
  if not Active then Exit;
  lvRequest := TIocpASyncRequest(FReconnectRequestPool.GetObject);
  lvRequest.DoCleanUp;
  lvRequest.OnResponseDone := OnReconnectRequestResponseDone;
  lvRequest.OnResponse := OnReconnectRequestResponse;
  lvRequest.Data := pvContext;
  Engine.PostRequest(lvRequest);
end;

function TIocpCustomTcpClient.ReleaseClientContext(
  const pvObject: TIocpCustomContext): Boolean;
begin
  if Assigned(pvObject) then
    FList.Remove(TIocpRemoteContext(pvObject));
  Result := False;
end;

procedure TIocpCustomTcpClient.Remove(const Value: TIocpRemoteContext);
begin
  if not Assigned(Value) then Exit;
  Value.FAutoReConnect := False;
  Value.Disconnect;
end;

procedure TIocpCustomTcpClient.RemoveAll;
var
  B: Boolean;
begin
  B := Active;
  Close;
  FReconnectRequestPool.WaitFor(5000);
  FList.Clear;
  Active := B;
end;

{ TIocpUdpServer }

function TIocpUdpServer.CheckNextSendRequest: Boolean;
var
  lvRequest: TIocpUdpSendRequest;
begin
  Result := False;
  FLocker.Enter();
  try
    lvRequest := TIocpUdpSendRequest(FSendRequestList.Pop);
  finally
    FLocker.Leave;
  end;
  if lvRequest <> nil then begin
    if lvRequest.ExecuteSend then begin
      Result := True;
      if (FDataMoniter <> nil) then
        FDataMoniter.IncPostSendObjectCounter;
    end else begin
      /// cancel request
      lvRequest.CancelRequest;
      {$IFDEF DEBUG_ON}
      DoStateMsgD(Self, '[0x%.4x] CheckNextSendRequest.ExecuteSend Return False',
         [SocketHandle]);
      {$ENDIF}
      ReleaseSendRequest(lvRequest);
    end;
    AtomicDecrement(FSendRef);
  end;
end;

procedure TIocpUdpServer.ClearRecvObjs;
var
  I: Integer;
begin
  for I := 0 to High(FRecvItems) do
    FreeAndNil(FRecvItems[i]);
  SetLength(FRecvItems, 0);
end;

procedure TIocpUdpServer.Close;
begin
  if not FActive then Exit;
  DoStateMsgD(Self, 'Server Closeing...');
  FActive := False;
  if Assigned(FListenSocket) then
    FListenSocket.Close;
  // engine Stop
  FIocpEngine.Stop;
  WaitFor(30000);
  if Assigned(FSendRequestPool) then begin
    FSendRequestPool.FreeDataObject;
    FSendRequestPool.Clear;
  end;
  ClearRecvObjs;
  DoStateMsgD(Self, 'Server Closed.');
end;

constructor TIocpUdpServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FListenSocket := TRawSocket.Create;
  FSendRequestPool := TBaseQueue.Create;
  FSendRequestList := TIocpRequestLinkList.Create(256);
end;

procedure TIocpUdpServer.CreateSocket();
var
  ARequest: TIocpUdpRecvRequest;
  AAddr: sockaddr_in;
  I: Integer;
begin
  FListenSocket.CreateUdpSocket(True);
  // �������˿�
  AAddr := GetSocketAddr(FBindAddr, FPort);
  if not FListenSocket.Bind(TSockAddr(AAddr)) then
    RaiseLastOSError;
  // �������׽��ְ󶨵�IOCP���
  FIocpEngine.IocpCore.Bind(FListenSocket.SocketHandle, DWORD(FListenSocket.SocketHandle));
  // ��ʼ��������
  SetLength(FRecvItems, FIocpEngine.MaxWorkerCount);
  //SetLength(FRecvItems, GetCPUCount shl 1);
  for I := 0 to High(FRecvItems) do begin
    ARequest := TIocpUdpRecvRequest.Create(Self);
    if not ARequest.PostRequest then begin
      FreeAndNil(ARequest);
      Break;
    end else
      FRecvItems[i] := ARequest;
  end;
end;

destructor TIocpUdpServer.Destroy;
begin
  inherited Destroy;
  FreeAndNil(FListenSocket);
  ClearRecvObjs;
  FSendRequestPool.FreeDataObject;
  FreeAndNil(FSendRequestPool);
  Assert(FSendRequestList.Count = 0);
  FreeAndNil(FSendRequestList);
end;

procedure TIocpUdpServer.DoReceiveData(Sender: TIocpUdpRequest);
begin
  if Assigned(FOnReceivedBuffer) then
    FOnReceivedBuffer(Sender, Sender.FRecvBuffer.buf, Sender.FBytesTransferred);
end;

function TIocpUdpServer.GetMaxSendingQueueSize: Integer;
begin
  if Assigned(FSendRequestList) then
    Result := FSendRequestList.MaxSize
  else
    Result := 0;
end;

function TIocpUdpServer.GetSendRequest: TIocpUdpSendRequest;
begin
  Result := TIocpUdpSendRequest(FSendRequestPool.DeQueue);
  if Result = nil then begin
    if FSendRequestClass <> nil then
      Result := FSendRequestClass.Create
    else
      Result := TIocpUdpSendRequest.Create;
  end;
  Result.DoCleanup;
  Result.FAlive := True;
  Result.FOwner := Self;
end;

function TIocpUdpServer.GetSocketHandle: TSocket;
begin
  Result := FListenSocket.SocketHandle;
end;

function TIocpUdpServer.InnerPostSendRequestAndCheckStart(
  pvSendRequest: TIocpUdpSendRequest): Boolean;
var
  lvStart: Boolean;
begin
  lvStart := False;
  FLocker.Enter();
  try
    Result := FSendRequestList.Push(pvSendRequest);
  finally
    FLocker.Leave;
  end;
  if Result and (AtomicIncrement(FSendRef) <= 1) then
    lvStart := true;  // start send work
  {$IFDEF DEBUG_ON}
  if (not Result) then
    DoStateMsgE(Self, strSend_PushFail, [SocketHandle, FSendRequestList.Count, FSendRequestList.MaxSize]);
  {$ENDIF}
  if lvStart then begin  // start send work
    if (FDataMoniter <> nil) then
      FDataMoniter.incPushSendQueueCounter;
    CheckNextSendRequest;
  end;
end;

function TIocpUdpServer.InnerSendData(const Dest: TSockAddrin; buf: Pointer; len: Cardinal;
  pvBufReleaseType: TDataReleaseType; pvTag: Integer;
  pvTagData: Pointer): Boolean;
var
  lvRequest: TIocpUdpSendRequest;
begin
  if Active then begin
    lvRequest := GetSendRequest;
    lvRequest.FAddr := Dest;
    lvRequest.SetBuffer(buf, len, pvBufReleaseType);
    lvRequest.Tag := pvTag;
    lvRequest.Data := pvTagData;
    Result := InnerPostSendRequestAndCheckStart(lvRequest);
    if not Result then begin
      /// Push Fail unbinding buf
      lvRequest.UnBindingSendBuffer;
      lvRequest.CancelRequest;
      ReleaseSendRequest(lvRequest);
    end;
  end else
    Result := False;
end;

procedure TIocpUdpServer.Open;
begin
  if FActive then Exit;
  FActive := True;
  try
    if Assigned(FDataMoniter) then
      FDataMoniter.Clear;
    // ����IOCP����
    FIocpEngine.Start;
    // �����������׽���
    CreateSocket;
  except
    FActive := False;
    FListenSocket.Close;
  end;
end;

procedure TIocpUdpServer.PostNextSendRequest;
begin
  CheckNextSendRequest;
end;

procedure TIocpUdpServer.RegisterSendRequestClass(
  pvClass: TIocpUdpSendRequestClass);
begin
  FSendRequestClass := pvClass;
end;

function TIocpUdpServer.ReleaseSendRequest(pvObject: TIocpUdpSendRequest): Boolean;
begin
  AtomicDecrement(FSendRef);
  Result := False;
  if (not Assigned(Self)) or (not Assigned(FSendRequestPool)) then
    Assert(False);
  if lock_cmp_exchange(True, False, pvObject.FAlive) = True then begin
    if Assigned(FDataMoniter) then
      InterlockedIncrement(FDataMoniter.FSendRequestReturnCounter);
    pvObject.DoCleanUp;
    pvObject.FOwner := nil;
    FSendRequestPool.EnQueue(pvObject);
    Result := True;
  end else begin
    if IsDebugMode then
      Assert(False);
  end;
end;

function TIocpUdpServer.Send(const Dest: TSockAddrin; buf: Pointer; len: Cardinal;
  CopyBuf: Boolean): Boolean;
var
  Data: Pointer;
begin
  Result := False;
  if (buf = nil) or (Len = 0) then Exit;
  if CopyBuf and (Len <= FWSASendBufferSize) then begin
    {$IFDEF UseSendMemPool}
    Data := PopMem;
    Move(buf^, Data^, len);
    Result := InnerSendData(Dest, Data, len, dtMemPool);
    {$ELSE}
    GetMem(Data, len);
    Move(buf^, Data^, len);
    Result := InnerSendData(Dest, Data, len, dtFreeMem);
    {$ENDIF}
  end else
    Result := InnerSendData(Dest, buf, len, dtNone);
end;

function TIocpUdpServer.Send(const Dest: TSockAddrin; buf: Pointer; len: Cardinal;
  BufReleaseType: TDataReleaseType): Boolean;
begin
  if (buf = nil) or (Len = 0) then
    Result := True
  else
    Result := InnerSendData(Dest, buf, len, BufReleaseType);
end;

procedure TIocpUdpServer.SetMaxSendingQueueSize(pvSize: Integer);
begin
  FSendRequestList.MaxSize := pvSize;
end;

function TIocpUdpServer.WaitFor(pvTimeOut: Cardinal): Boolean;
var
  T: Int64;
begin
  T := GetTimestamp;
  while True do begin
    if InterlockedIncrement(FSendRef) > 1 then begin
      InterlockedDecrement(FSendRef);
      Sleep(50);
      if (pvTimeOut > 0) and (GetTimestamp - T > pvTimeOut) then
        Break;
    end else begin
      InterlockedDecrement(FSendRef);
      Break;
    end;
  end;
  Result := FSendRef < 1;
end;

{ TIocpUdpRecvRequest }

procedure TIocpUdpRecvRequest.Clear;
begin
  if FRecvBuffer.len > 0 then begin
    FreeMem(FRecvBuffer.buf, FRecvBuffer.len);
    FRecvBuffer.len := 0;
  end;
end;

constructor TIocpUdpRecvRequest.Create(AOwner: TIocpUdpServer);
begin
  FOwner := AOwner;
  inherited Create();
end;

destructor TIocpUdpRecvRequest.Destroy;
begin
  if FRecvBuffer.len > 0 then
    FreeMem(FRecvBuffer.buf, FRecvBuffer.len);
  inherited Destroy;
end;

procedure TIocpUdpRecvRequest.DoRecvData;
begin
  FOwner.DoReceiveData(Self);
end;

function TIocpUdpRecvRequest.GetPeerAddr: Cardinal;
begin
  Result := inet_addr(inet_ntoa(FFrom.sin_addr));
end;

function TIocpUdpRecvRequest.GetRemoteAddr: string;
begin
  Result := inet_ntoa(FFrom.sin_addr);
end;

function TIocpUdpRecvRequest.GetRemotePort: Word;
begin
  Result := ntohs(FFrom.sin_port);
end;

procedure TIocpUdpRecvRequest.HandleResponse;
var
  IsDisconnect: Boolean;
begin
  {$IFDEF DEBUG_ON}
  if FOwner = nil then
    Assert(FOwner <> nil);
  {$ENDIF}
  if not FOwner.Active then begin
    {$IFDEF DEBUG_ON}
    FOwner.DoStateMsgD(Self, strRecv_EngineOff, [FOwner.SocketHandle]);
    {$ENDIF}
    Exit;
  end;
  IsDisconnect := True;
  try
    if (Assigned(FOwner.FDataMoniter)) then begin
      FOwner.FDataMoniter.incResponseWSARecvCounter;
      FOwner.FDataMoniter.incRecvdSize(FBytesTransferred);
    end;
    if ErrorCode <> 0 then begin
      if ErrorCode <> 995 then  // �첽����ȴ�ʱ�����˹ر��׽���
        FOwner.DoStateMsgE(Self, strRecv_Error, [FOwner.SocketHandle, ErrorCode]);
      IsDisconnect := False;
    end else begin
      IsDisconnect := False;
      DoRecvData;
    end;
  finally
    if not IsDisconnect then
      PostRequest;
  end;
end;

function TIocpUdpRecvRequest.PostRequest: Boolean;
var
  lvRet: Integer;
begin
  if (FOwner = nil) or (not FOwner.Active) then begin
    Result := False;
    Exit;
  end;
  lvRet := FOwner.FWSARecvBufferSize;
  if Integer(FRecvBuffer.len) <> lvRet then begin
    if FRecvBuffer.len > 0 then
      FreeMem(FRecvBuffer.buf);
    FRecvBuffer.len := lvRet;
    GetMem(FRecvBuffer.buf, lvRet);
  end;
  FRecvdFlag := 0;
  FBytesTransferred := 0;
  FFromLen := SizeOf(FFrom);
  if (Assigned(FOwner.FDataMoniter)) then
    FOwner.FDataMoniter.incPostWSARecvCounter;
  lvRet := WSARecvFrom(FOwner.FListenSocket.SocketHandle,
    @FRecvBuffer,
    1,
    @FBytesTransferred,
    FRecvdFlag,
    @FFrom,
    @FFromLen,
    LPWSAOVERLAPPED(@FOverlapped),
    nil);
  if lvRet = SOCKET_ERROR then begin
    lvRet := WSAGetLastError;
    Result := lvRet = WSA_IO_PENDING;
    if not Result then begin
      {$IFDEF DEBUG_ON}
      FOwner.DoStateMsgE(Self, strRecv_PostError, [FOwner.FListenSocket.SocketHandle, lvRet]);
      {$ENDIF}
      if lvRet = 10054 then begin
        Sleep(100);
        PostRequest;
      end;
    end;
  end else
    Result := True;
end;

procedure TIocpUdpRecvRequest.Send(const Data: WideString);
begin
  if Length(Data) = 0 then Exit;
  FOwner.Send(FFrom, @Data[1], Length(Data) shl 1, True);
end;

procedure TIocpUdpRecvRequest.Send(const Data: AnsiString);
begin
  if Length(Data) = 0 then Exit;
  FOwner.Send(FFrom, @Data[1], Length(Data), True);
end;

{$IFDEF UNICODE}
procedure TIocpUdpRecvRequest.Send(const Data: UnicodeString);
begin
  if Length(Data) = 0 then Exit;
  FOwner.Send(FFrom, @Data[1], Length(Data) shl 1, True);
end;
{$ENDIF}

procedure TIocpUdpRecvRequest.Send(buf: Pointer; len: Cardinal);
begin
  if len > 0 then
    FOwner.Send(FFrom, buf, len);
end;

{ TIocpUdpSendRequest }

procedure TIocpUdpSendRequest.CheckClearSendBuffer;
begin
  if FLen > 0 then begin
    case FSendBufferReleaseType of
      dtDispose: Dispose(FBuf);
      dtFreeMem: FreeMem(FBuf);
      dtMemPool: FOwner.PushMem(FBuf);
    end;
  end;
  FSendBufferReleaseType := dtNone;
  FLen := 0;
end;

constructor TIocpUdpSendRequest.Create;
begin
  inherited Create;
end;

destructor TIocpUdpSendRequest.Destroy;
begin
  CheckClearSendBuffer;
  inherited Destroy;
end;

procedure TIocpUdpSendRequest.DoCleanUp;
begin
  CheckClearSendBuffer;
  FOwner := nil;
  FBuf := nil;
  FLen := 0;
end;

function TIocpUdpSendRequest.ExecuteSend: Boolean;
begin
  if (FBuf = nil) or (FLen = 0) then begin
    {$IFDEF DEBUG_ON}
    FOwner.DoStateMsgD(Self, strSend_Zero, [FOwner.SocketHandle]);
    {$ENDIF}
    Result := False;
  end else
    Result := InnerPostRequest(FBuf, FLen);
end;

procedure TIocpUdpSendRequest.HandleResponse;
begin
  FIsBusying := False;
  if FOwner = nil then Exit;
  if Assigned(FOwner.FDataMoniter) then begin
    FOwner.FDataMoniter.incSentSize(FBytesTransferred);
    FOwner.FDataMoniter.incResponseWSASendCounter;
  end;
  if not FOwner.Active then begin
    {$IFDEF DEBUG_ON}
    FOwner.DoStateMsgD(Self, strSend_EngineOff, [FOwner.SocketHandle]);
    {$ENDIF}
  end else if ErrorCode <> 0 then begin
    FOwner.DoStateMsgE(Self, strSend_Err, [FOwner.SocketHandle, ErrorCode]);
    FOwner.CheckNextSendRequest;
  end else begin
    if Assigned(FOwner.FDataMoniter) then
      FOwner.FDataMoniter.incResponseSendObjectCounter;
    FOwner.CheckNextSendRequest;
  end;
end;

function TIocpUdpSendRequest.InnerPostRequest(buf: Pointer;
  len: Cardinal): Boolean;
var
  lvErrorCode, lvRet: Integer;
  dwFlag, lpNumberOfBytesSent: Cardinal;
  lvOwner: TIocpUdpServer;
begin
  Result := False;
  if not Assigned(FOwner) then Exit;
  FIsBusying := True;
  FSendBuf.buf := buf;
  FSendBuf.len := len;
  dwFlag := 0;
  lpNumberOfBytesSent := 0;

  // maybe on HandleResonse and release self
  lvOwner := FOwner;
  lvOwner.Locker.Enter();
  Result := lvOwner.Active;
  lvOwner.Locker.Leave;
  if not Result then Exit;
  lvRet := WSASendTo(lvOwner.SocketHandle,
                @FSendBuf, 1, @lpNumberOfBytesSent, dwFlag,
                TSockAddr(FAddr), SizeOf(FAddr),
                LPWSAOVERLAPPED(@FOverlapped),   // d7 need to cast
                nil);
  if lvRet = SOCKET_ERROR then begin
    // Ͷ��ʧ��
    lvErrorCode := WSAGetLastError;
    Result := lvErrorCode = WSA_IO_PENDING;
    if not Result then begin
      //���ʹ����ͷŸ�SOCKET��Ӧ��������Դ
      FIsBusying := False;
      lvOwner.DoStateMsgE(Self, strSend_PostError, [lvOwner.SocketHandle, lvErrorCode]);
    end else begin
      // ���ͳɹ�
      if (lvOwner <> nil) and (lvOwner.FDataMoniter <> nil) then begin
        lvOwner.FDataMoniter.incPostWSASendSize(len);
        lvOwner.FDataMoniter.incPostWSASendCounter;
      end;
    end;
  end else begin
    // ���ͳɹ�
    Result := True;
    if (lvOwner <> nil) and (lvOwner.FDataMoniter <> nil) then begin
      lvOwner.FDataMoniter.incPostWSASendSize(len);
      lvOwner.FDataMoniter.incPostWSASendCounter;
    end;
  end;
end;

procedure TIocpUdpSendRequest.ResponseDone;
begin
  if FOwner = nil then begin
    if IsDebugMode then
      Assert(FOwner <> nil);
  end else
    FOwner.ReleaseSendRequest(Self);
end;

procedure TIocpUdpSendRequest.SetBuffer(buf: Pointer; len: Cardinal;
  pvCopyBuf: Boolean);
var
  lvBuf: PAnsiChar;
begin
  if pvCopyBuf then begin
    GetMem(lvBuf, len);
    Move(buf^, lvBuf^, len);
    SetBuffer(lvBuf, len, dtFreeMem);
  end else
    SetBuffer(buf, len, dtNone);
end;

procedure TIocpUdpSendRequest.SetBuffer(buf: Pointer; len: Cardinal;
  pvBufReleaseType: TDataReleaseType);
begin
  CheckClearSendBuffer;
  FBuf := buf;
  FLen := len;
  FSendBufferReleaseType := pvBufReleaseType;
end;

procedure TIocpUdpSendRequest.UnBindingSendBuffer;
begin
  FBuf := nil;
  FLen := 0;
  FSendBufferReleaseType := dtNone;
end;

{ TIocpBlockSocketStream }

constructor TIocpBlockSocketStream.Create(ASocket: TIocpCustomBlockTcpSocket);
begin
  FSocket := ASocket;
  FReadTimeOut := 30000;
end;

function TIocpBlockSocketStream.Read(var Buffer; Count: Integer): Longint;
var
  P: PAnsiChar;
  ALen, I: Integer;
  T: Cardinal;
begin
  ALen := Count;
  P := @Buffer;
  Result := 0;
  T := GetTickCount;
  while ALen > 0 do begin
    if ALen > 4096 then
      I := FSocket.FRawSocket.RecvBuf(P^, 4096)
    else
      I := FSocket.FRawSocket.RecvBuf(P^, ALen);
    if I > 0 then begin
      Inc(P, I);
      Inc(Result, I);
      Dec(ALen, I);
    end else begin
      if (I = -1){$IFDEF POSIX} or (I = 0){$ENDIF} then
        FSocket.RaiseLastOSError(False);
      if (not FSocket.Active) or (FReadTimeOut < 1) or
        ((FReadTimeOut > 0) and (GetTickCount - T > Cardinal(FReadTimeOut))) then
      begin
        if FSocket.Active then          
          FSocket.Disconnect;
        Break;
      end;
      Sleep(50);
      {$IFDEF MSWINDOWS}
      SwitchToThread;  
      {$ELSE}
      TThread.Yield;
      {$ENDIF}
    end;
  end;
end;

procedure TIocpBlockSocketStream.SetSize(NewSize: Integer);
begin
  raise Exception.Create(strSocket_RSNotSup);
end;

function TIocpBlockSocketStream.Seek(const Offset: Int64;
  Origin: TSeekOrigin): Int64;
begin
  raise Exception.Create(strSocket_RSNotSup);
end;

procedure TIocpBlockSocketStream.SetSize(const NewSize: Int64);
begin
  raise Exception.Create(strSocket_RSNotSup);
end;

function TIocpBlockSocketStream.Write(const Buffer; Count: Integer): Longint;
begin
  Result := FSocket.FRawSocket.SendBuf(Buffer, Count);
end;

initialization
  Workers := TIocpTask.GetInstance;

finalization
  Workers := nil;

end.


