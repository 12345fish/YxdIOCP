{*******************************************************}
{                                                       }
{       IOCP HTTP ���������Ԫ                          }
{                                                       }
{       ��Ȩ���� (C) 2015 YangYxd                       }
{                                                       }
{*******************************************************}
{
  IOCP HTTP ����
  ��Ҫ���ܣ�
  1. ֧�ֱ�׼Http���ʷ���
  2. ֧�־ֲ�����
  3. ֧���ļ����أ��ϵ�����
  4. ֧�ֱ��ύ
  5. ֧��GZipѹ������
  6. ֧���ļ��ϴ������ܳ������ޣ�
  7. ֧��Pipe�ܵ���һ�ζ������
  8. ֧��Session
  9. ֧��Cookies
}

unit iocp.Http;

{$I 'iocp.inc'}
{$DEFINE UseMemPool_IocpLink}
{$DEFINE UseGZip}

{$IF (RTLVersion>=26) and (not Defined(NEXTGEN))}
{$DEFINE ANSISTRINGS}
{$IFEND}

interface

uses
  iocp.Utils.Hash, iocp.Utils.Str, {$IFDEF UseGZip}ZLibExGZ, {$ENDIF}
  iocp.Sockets, iocp.Task, iocp.core.Engine,
  iocp.Sockets.Utils, iocp.Res, iocp.Utils.Queues,
  {$IFDEF ANSISTRINGS}AnsiStrings, {$ENDIF}
  SyncObjs, Windows, Classes, SysUtils, DateUtils;

const
  HTTPLineBreak = #13#10;
  HTTPHeaderEnd = #13#10#13#10;
  HTTPCTTypeStream = 'application/octet-stream'; // �� ������������֪�������ļ����ͣ�
  HTTPMethodLen: array [0..8] of Word = (0, 3, 4, 3, 4, 7, 6, 5, 7);
  HTTPSESSIONID = 'diocp_sid';

type
  /// <summary>
  /// HTTP 1.1 ֧��8����������
  // ���󷽷������з���ȫΪ��д���ж��֣����������Ľ������£�
  // GET     �����ȡRequest-URI����ʶ����Դ
  // POST    ��Request-URI����ʶ����Դ�󸽼��µ����ݣ��������ύ����
  // HEAD    �����ȡ��Request-URI����ʶ����Դ����Ӧ��Ϣ��ͷ
  // PUT     ����������洢һ����Դ������Request-URI��Ϊ���ʶ
  // DELETE  ���������ɾ��Request-URI����ʶ����Դ
  // TRACE   ��������������յ���������Ϣ����Ҫ���ڲ��Ի����
  // CONNECT ��������ʹ��
  // OPTIONS �����ѯ�����������ܣ����߲�ѯ����Դ��ص�ѡ�������
  /// </summary>
  TIocpHttpMethod = (http_Unknown, http_GET, http_POST, http_PUT, http_HEAD,
    http_OPTIONS, http_DELETE, http_TRACE, http_CONNECT);

type
  /// <summary>
  /// Http ����汾, ��Ϊ HTTP 1.0, HTTP 1.1
  /// </summary>
  TIocpHttpReqVer = (hv_Unknown, hv_V1, hv_V2);

type
  TIocpHttpServer = class;
  TIocpHttpRequest = class;
  TIocpHttpResponse = class;

  TOnHttpFilter = procedure (Request: TIocpHttpRequest; var CancelRequest: Boolean) of object;
  TOnHttpRequest = procedure (Sender: TIocpHttpServer;
    Request: TIocpHttpRequest; Response: TIocpHttpResponse) of object;
  /// <summary>
  /// ��ȡ�� Session �¼�������ֵ����Ϊ��ǰSessionID��ֵ
  /// </summary>
  TOnHttpGetSession = function (Sender: TIocpHttpServer; const SessionID: string): Pointer of object;
  /// <summary>
  /// �ͷ�(ɾ��) Session �¼���Data ��Ҫ�ⲿ�������ͷ�
  /// </summary>
  TOnHttpFreeSession = procedure (Sender: TIocpHttpServer;
    const SessionID: string; var Data: Pointer) of object;

  TIocpPointerStr = record
    P: PAnsiChar;
    Len: Word;
    function IsEmpty: Boolean;
    function ToString(): AnsiString;
  end;

  /// <summary>
  /// Http ��������
  /// </summary>
  TIocpHttpFromDataItem = packed record
  private
    P, FC: PAnsiChar;
    Len: Integer;
    function GetContentType: AnsiString;
    function GetDisposition: AnsiString;
    function GetFileName: AnsiString;
    function GetName: AnsiString;
    function GetContent: AnsiString;
    function GetHeaderSize: Integer;
    function GetIsFile: Boolean;
  public
    // ��������ݵ�ָ������
    procedure SaveContentToStream(const Stream: TStream);
    // ��ȡ�����ݵ������������ط�nilʱ����ʹ��������ֶ��ͷ�
    function GetContentStream: TStream;
    // �Ƿ�Ϊ�ļ�����
    property IsFile: Boolean read GetIsFile;

    property Data: PAnsiChar read P;
    property DataSize: Integer read Len;
    property Name: AnsiString read GetName;
    property ContentDisposition: AnsiString read GetDisposition;
    property ContentType: AnsiString read GetContentType;
    property FileName: AnsiString read GetFileName;
    property Content: AnsiString read GetContent;
    property HeaderSize: Integer read GetHeaderSize;
  end;

  TIocpHttpState = (hsCompleted, hsRequest { �������� } , hsRecvingPost { �������� } );

  TIocpHttpConnection = class(TIocpClientContext)
  private
    FRequest: TIocpHttpRequest;
    FHttpState: TIocpHttpState;
    FRequestQueue: TSimpleQueue;
    FProcessRequesting: Boolean;
  protected
    procedure ClearRequestTaskObject();
    procedure DoCleanUp; override;
    procedure DoJob(AJob: PIocpJob);
    procedure DoRequest(ARequest: TIocpHttpRequest);
    procedure OnRecvBuffer(buf: Pointer; len: Cardinal; ErrorCode: Integer); override;
  public
    constructor Create(AOwner: TIocpCustom); override;
    destructor Destroy; override;
  end;

  /// <summary>
  /// �ͻ���Cookie������
  /// </summary>
  TIocpHttpCookie = class(TObject)
  private
    FExpires: TDateTime;
    FMaxAge: Cardinal;
    FName: AnsiString;
    FPath: AnsiString;
    FValue: AnsiString;
    FDoMain: AnsiString;
  public
    constructor Create;
    /// <summary>
    /// �����һ��String
    /// </summary>
    function ToString: AnsiString;
    // ָ����coolie��������
    property Expires: TDateTime read FExpires write FExpires;
    property Name: AnsiString read FName write FName;
    property Value: AnsiString read FValue write FValue;
    // ָ����cookie������һ�����ҳ
    property Path: AnsiString read FPath write FPath;
    // ʹ���web����������cookie
    property DoMain: AnsiString read FDoMain write FDoMain;
    // ����������cookie��������
    property MaxAge: Cardinal read FMaxAge write FMaxAge;
  end;

  /// <summary>
  /// HTTP ����
  /// </summary>
  TIocpHttpServer = class(TIocpCustomTcpServer)
  private
    FSessionList: TStringHash;
    FHttpRequestPool: TBaseQueue;
    FUploadMaxDataSize: NativeUInt;
    FOnHttpRequest: TOnHttpRequest;
    FOnHttpFilter: TOnHttpFilter;
    FOnHttpGetSession: TOnHttpGetSession;
    FOnHttpFreeSession: TOnHttpFreeSession;
  protected
    procedure DoRequest(ARequest: TIocpHttpRequest);
    function GetHttpRequest: TIocpHttpRequest;
    procedure FreeHttpRequest(V: TIocpHttpRequest);
    procedure FreeSessionList;
    procedure DoFreeHashItem(Item: PHashItem);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>
    /// ��ȡָ��ID��Session���ݡ�Session�������ⲿ����ά����Http����ֻ����
    /// HashMap��¼SessionID��Data�Ĺ�����
    /// </summary>
    function GetSession(const SID: string): Pointer;
  published
    /// �ͻ����ϴ����ݴ�С�����ޣ�Ĭ��Ϊ2M��
    property UploadMaxDataSize: NativeUInt read FUploadMaxDataSize write FUploadMaxDataSize;
    /// <summary>
    /// Http��������¼�, ���ﷵ��False���жϵ�ǰ���󣬶Ͽ�����
    /// </summary>
    property OnHttpFilter: TOnHttpFilter read FOnHttpFilter write FOnHttpFilter;
    /// <summary>
    /// Http����������Ӧ����
    /// </summary>
    property OnHttpRequest: TOnHttpRequest read FOnHttpRequest write FOnHttpRequest;
    /// <summary>
    /// ��ȡ Session �����¼�
    /// </summary>
    property OnGetSession: TOnHttpGetSession read FOnHttpGetSession write FOnHttpGetSession;
    /// <summary>
    /// �ͷ� Session ��֪ͨ�¼�
    /// </summary>
    property OnFreeSession: TOnHttpFreeSession read FOnHttpFreeSession write FOnHttpFreeSession;
  end;

  /// <summary>
  /// Http ��������
  /// </summary>
  TIocpHttpRequest = class(TObject)
  private
    FOwner: TIocpHttpServer;
    FConnHandle: Cardinal;
    FConn: TIocpHttpConnection;
    FResponse: TIocpHttpResponse;
    FMethod: TIocpHttpMethod;
    FRequestVersion: TIocpHttpReqVer;
    FDataSize: NativeUInt;
    FHeaderSize: Integer;
    FRequestData: TMemoryStream;
    FKeepAlive: Boolean;
    FRange: Boolean;
    FIsFormData: Byte;
    FRangeStart, FRangeEnd: Int64;
    FParamHash: TStringHash;
    FParams: TStrings;
    FRawURL: TIocpPointerStr;
    FURI: TIocpPointerStr;
    FURL: AnsiString;
    FFormDataBoundary: TIocpPointerStr;
    FCookies: TIocpPointerStr;
    FSessionID : string;
    FTag: Integer;
    function GetAccept: AnsiString;
    function GetAcceptEncoding: AnsiString;
    function GetAcceptLanguage: AnsiString;
    function GetCookies: AnsiString;
    function GetHost: AnsiString;
    function GetParamItem(Index: Integer): AnsiString;
    function GetReferer: AnsiString;
    function GetParamsCount: Integer;
    function GetRequestVersionStr: AnsiString;
    function DecodeStr(const S: AnsiString): AnsiString;
    procedure DecodeParam(P: PAnsiChar; Len: Cardinal; DecodeURL: Boolean = False);
    procedure DecodeParams();
    function GetDataString: AnsiString;
    function GetHeaderStr: AnsiString;
    function GetRawURL: AnsiString;
    function GetParamIndex(Index: Integer): AnsiString;
    function GetURI: AnsiString;
    function GetIsPost: Boolean;
    function GetIsGet: Boolean;
    function GetIsPut: Boolean;
    function GetIsRange: Boolean;
    function GetIsFormData: Boolean;
    function GetFormDataItem(const Key: AnsiString): TIocpHttpFromDataItem;
    class function InnerGetHeader(const Key: AnsiString;
      const Data: Pointer; DataSize: Integer): TIocpPointerStr;
    procedure InnerGetCookie;
    procedure CheckCookieSession;
    function GetCookieItem(const Name: AnsiString): AnsiString;
    function GetSessionID: string;
    function GetAcceptGzip: Boolean;
  protected
    function DecodeHttpRequestMethod(): TIocpHttpMethod; 
    function DecodeHttpHeader(): Boolean;
    function DecodeHttpHeaderRange(): Boolean;
    function GetWaitRecvSize: Int64;
    procedure Clear;
    procedure WriteBuffer(P: Pointer; Len: Cardinal);        
  public
    constructor Create(AOwner: TIocpHttpServer);
    destructor Destroy; override;

    /// <summary>
    /// ��ȡ��ǰ����Session
    /// </summary>
    function GetSession: Pointer;

    /// <summary>
    /// �رյ�ǰ����
    /// </summary>
    procedure Close;

    /// <summary>
    /// �ر�����, �첽ģʽ����֤���ڷ��͵����ݿ��Է������
    /// </summary>
    procedure CloseConnection;

    /// <summary>
    /// ����Post���� , ���ñ������� �Ϳ���ʹ�� Params[Key] ����ȡPost�Ĳ�����
    /// </summary>
    procedure ParsePostParams();

    /// <summary>
    /// �жϲ����Ƿ����
    /// </summary>
    function ExistParam(const Key: AnsiString): Boolean;
    /// <summary>
    /// ��ȡ����
    /// </summary>
    function GetParam(const Key: AnsiString): string;
    /// <summary>
    /// ��ȡ����ͷ
    /// </summary>
    function GetHeader(const Key: AnsiString): AnsiString;

    property Owner: TIocpHttpServer read FOwner;
    property Connection: TIocpHttpConnection read FConn;
    
    // �Ƿ���Post����
    property IsPost: Boolean read GetIsPost;
    // �Ƿ���Put����
    property IsPut: Boolean read GetIsPut;
    // �Ƿ���Get����
    property IsGet: Boolean read GetIsGet;
    // �Ƿ��Ǳ��ύ���� (ͬʱ�϶���Post����)
    property IsFormData: Boolean read GetIsFormData;
    // �Ƿ�ʹ�÷�Χ���� (���ϵ�����)
    property IsRange: Boolean read GetIsRange;
    
    // ��������
    property Method: TIocpHttpMethod read FMethod;
    // ԭʼ�������ݳ��ȣ�һ��Ϊ0��Post����ʱһ�����0
    property ContextLength: NativeUInt read FDataSize;
    // ԭʼ�������ݣ�һ��Ϊnil��Post����һ���������
    property Data: TMemoryStream read FRequestData;
    // ��ͷ��Ϣ������������Url,��������
    property URL: AnsiString read FURL;
    // ����URL����
    property URI: AnsiString read GetURI;
    // ԭʼURL��������
    property RawURL: AnsiString read GetRawURL;
    // ԭʼ����ͷ��Ϣ
    property Header: AnsiString read GetHeaderStr;
    // HTTP ����Э��汾
    property RequestVersion: TIocpHttpReqVer read FRequestVersion;
    // HTTP ����Э��汾�ַ���
    property RequestVersionStr: AnsiString read GetRequestVersionStr;
    // �ַ�����ʽ���������
    property DataString: AnsiString read GetDataString;
    // ����ͷ������
    property HeaderLength: Integer read FHeaderSize;
    // �����Ϳ�ʼλ��
    property RangeStart: Int64 read FRangeStart;
    // �����ͽ���λ��
    property RangeEnd: Int64 read FRangeEnd;
    
    // ------- �����������ڶ���ʱ��Ŵ�Header�н��� ---------
    property Accept: AnsiString read GetAccept;
    property AcceptEncoding: AnsiString read GetAcceptEncoding;
    property AcceptLanguage: AnsiString read GetAcceptLanguage;
    property AcceptGzip: Boolean read GetAcceptGzip;
    property Host: AnsiString read GetHost;
    property Referer: AnsiString read GetReferer;
    property Session: Pointer read GetSession;
    property SessionID: string read GetSessionID;
    property Cookies: AnsiString read GetCookies;
    property Cookie[const Name: AnsiString]: AnsiString read GetCookieItem;
    property ParamsCount: Integer read GetParamsCount;
    property Params[Index: Integer]: AnsiString read GetParamIndex;
    // ע�⣬��������ʵʱ������ʹ��ʱע��Ч��
    property FormData[const Key: AnsiString]: TIocpHttpFromDataItem read GetFormDataItem;
    property Tag: Integer read FTag write FTag;
  end;

  TIocpPointerStream = class(TCustomMemoryStream)
  public
    constructor Create; overload;
    constructor Create(const Ptr: Pointer; ASize: Integer); overload;
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

  /// <summary>
  /// Http ����
  /// </summary>
  TIocpHttpResponse = class(TObject)
  private
    FRequest: TIocpHttpRequest;
    FCookies: TList;
    FCacheTime: Cardinal;
    FGZip: Boolean;
    FBlockSendBuffer: TMemoryStream;
    FContentType: AnsiString;
    function GetConnection: TIocpHttpConnection;
    function GetActive: Boolean;
    function GetContentType: AnsiString;
  protected
    function MakeHeader(ContextLength: Int64; const Status: AnsiString = '';
      FileDown: Boolean = False; const FileName: AnsiString = '';
      const LastModified: TDateTime = 0): AnsiString;
    function GetBlockHeader: AnsiString;
    procedure SendStream(Stream: TStream; IsDownloadFile: Boolean = False;
      const AFileName: AnsiString = ''; const AContentType: AnsiString = '';
      const LastModified: TDateTime = 0);
    function CheckFileUpdate(const Last: TDateTime): Boolean;
  public
    constructor Create();
    destructor Destroy; override;

    procedure Clear;

    /// <summary>
    /// ���Cookie
    /// </summary>
    function AddCookie: TIocpHttpCookie; overload;
    function AddCookie(const Name, Value: AnsiString): TIocpHttpCookie; overload;
    function AddCookie(const Name, Value: AnsiString; MaxAge: Cardinal): TIocpHttpCookie; overload;

    /// <summary>
    /// URL�ض���, ���þ�������ᷢ�ͻ��˷����ض����, �ض�������ͺ��ر�����
    /// </summary>
    procedure RedirectURL(const pvURL: AnsiString);
    /// <summary>
    /// ���ش�������������Ӧ�������Ͽ�����
    /// </summary>
    procedure ErrorRequest(ErrorCode: Word = 400);
    /// <summary>
    /// ����ָ����Ӧ����
    /// </summary>
    procedure ResponeCode(Code: Word; const Data: AnsiString = '');
    /// <summary>
    /// ���ط�����������Ϣ�����Ͽ�����
    /// </summary>
    procedure ServerError(const Msg: AnsiString);

    {$IFDEF UseGZip}
    // GZ ѹ������
    function GZCompress(const Data: AnsiString): AnsiString; overload;
    function GZCompress(const Data: WideString): AnsiString; overload;
    function GZCompress(Buf: Pointer; Len: Cardinal): AnsiString; overload;
    function GZCompress(inStream, outStream: TStream): Boolean; overload;
    {$ENDIF}

    /// <summary>
    /// ��ȡ�ļ��޸�ʱ��
    /// </summary>
    class function GetFileLastModified(const AFileName: string): TDateTime;

    /// <summary>
    /// �����ļ�, FileName ��Ҫ�����ļ�·��
    /// </summary>
    procedure SendFile(const FileName: string; const AContentType: string = '');
    /// <summary>
    /// �����ļ�, FileName����ָ���ļ����ƣ����Բ�������·��
    ///  * �ļ����������齫�ļ����ص��ڴ棬Ȼ��ʹ�ñ��������������ݣ�ֱ����
    ///  * SendFile����Ϊ����IO��������쳣
    /// </summary>
    procedure SendFileStream(AFileStream: TStream; const FileName: AnsiString = '';
      const AContentType: AnsiString = ''; const LastModified: TDateTime = 0;
      AGZip: Boolean = False);
    procedure SendFileData(const Data: AnsiString; const FileName: AnsiString = '';
      const AContentType: AnsiString = ''; const LastModified: TDateTime = 0;
      AGZip: Boolean = False); overload;
    procedure SendFileData(const Data: WideString; const FileName: AnsiString = '';
      const AContentType: AnsiString = ''; const LastModified: TDateTime = 0;
      AGZip: Boolean = False); overload;
    procedure SendFileData(const Data: Pointer; DataLen: Cardinal;
      const FileName: AnsiString = '';  const AContentType: AnsiString = '';
      const LastModified: TDateTime = 0; AGZip: Boolean = False); overload;

    /// <summary>
    /// �������ݣ�ȫ�Զ���� Http ��Ӧͷ (�첽)
    /// </summary>
    procedure Send(buf: Pointer; len: Cardinal; AGZip: Boolean = False); overload;
    procedure Send(const Data: AnsiString; AGZip: Boolean = False); overload;
    procedure Send(const Data: WideString; AGZip: Boolean = False); overload;
    procedure Send(Stream: TStream; AGZip: Boolean = False); overload;

    /// <summary>
    /// ����HTTP��Ӧ����ͷ�� (�첽)
    /// </summary>
    procedure SendHeader(DataSize: NativeUInt; AGZip: Boolean = False);
    /// <summary>
    /// ������������ (�첽)(*ע�⣬�������ڲ�������ʹ��GZipѹ������)
    /// * Ҫʹ��GZip��������������Ƚ�����ѹ������SendHeader���ٵ��ñ�����
    /// * Ҳ����ʹ�÷ֿ鷢�͵ķ�ʽ��
    /// </summary>
    procedure SendContent(const Data: AnsiString); overload;
    procedure SendContent(const Data: WideString); overload;

    /// <summary>
    /// �ֿ鷢��HTTP��Ӧ����ͷ�� (�첽)
    /// </summary>
    procedure SendChunkHeader(AGZip: Boolean = False); overload;
    /// <summary>
    /// �ֿ鷢���������� (�첽) (*ע�⣬�������ڲ�������ʹ��GZipѹ������)
    /// * ÿ�����ݲ��ܶ���Gzip���������������ʱ�������ȻҪ���Լ�����
    /// * ������������
    /// </summary>
    procedure SendChunk(const Data: AnsiString); overload;
    procedure SendChunk(const Data: WideString); overload;
    procedure SendChunk(buf: Pointer; len: Cardinal); overload;
    procedure SendChunk(Stream: TStream); overload;
    /// <summary>
    /// �ֿ鷢�����ݽ��� (�첽)
    /// </summary>
    procedure SendChunkEnd();

    property Request: TIocpHttpRequest read FRequest;
    property Connection: TIocpHttpConnection read GetConnection;
    property Active: Boolean read GetActive;

    // ������ƣ����������ʱ�䣺ms)
    property CacheTime: Cardinal read FCacheTime write FCacheTime;
    // ������������, Ĭ��text/html
    property ContentType: AnsiString read GetContentType write FContentType;
  end;

type
  /// <summary>
  /// ֻ���ļ��� 
  /// </summary>
  TFileOnlyStream = class(THandleStream)
  private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    property FileName: string read FFileName;
  end;

function DateTimeToGMTRFC822(Const DateTime: TDateTime): string;
function GMTRFC822ToDateTime(const pSour: AnsiString): TDateTime;
function NewSessionID(): string;

implementation

var
  Workers: TIocpTask;

{$IFDEF ANSISTRINGS}
function StrLIComp(const Str1, Str2: PAnsiChar; MaxLen: Cardinal): Integer; inline;
begin
  Result := AnsiStrings.StrLIComp(Str1, Str2, MaxLen);
end;
function StrScan(const Str: PAnsiChar; Chr: AnsiChar): PAnsiChar; inline;
begin
  Result := AnsiStrings.StrScan(Str, Chr);
end;
{$ENDIF}

function LocalTimeZoneBias: Integer;
{$IFDEF LINUX}
var
  TV: TTimeval;
  TZ: TTimezone;
begin
  gettimeofday(TV, TZ);
  Result := TZ.tz_minuteswest;
end;
{$ELSE}
var
  TimeZoneInformation: TTimeZoneInformation;
  Bias: Longint;
begin
  case GetTimeZoneInformation(TimeZoneInformation) of
    TIME_ZONE_ID_STANDARD: Bias := TimeZoneInformation.Bias + TimeZoneInformation.StandardBias;
    TIME_ZONE_ID_DAYLIGHT: Bias := TimeZoneInformation.Bias + ((TimeZoneInformation.DaylightBias div 60) * -100);
  else
    Bias := TimeZoneInformation.Bias;
  end;
  Result := Bias;
end;
{$ENDIF}

var
  DLocalTimeZoneBias: Double = 0;

function DateTimeToGMT(const DT: TDateTime): TDateTime; inline;
begin
  Result := DT + DLocalTimeZoneBias;
end;

function GMTToDateTime(const DT: TDateTime): TDateTime; inline;
begin
  Result := DT - DLocalTimeZoneBias;
end;

function DateTimeToGMTRFC822(const DateTime: TDateTime): string;
const
  WEEK: array[1..7] of string = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
  STR_ENGLISH_M: array[1..12] of string = ('Jan', 'Feb', 'Mar', 'Apr', 'May',
    'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  wWeek, wYear, wMonth, wDay, wHour, wMin, wSec, wMilliSec: Word;
begin
  DecodeDateTime(DateTimeToGMT(DateTime), wYear, wMonth, wDay, wHour, wMin, wSec, wMilliSec);
  wWeek := DayOfWeek(DateTimeToGMT(DateTime));
  Result := Format('%s, %.2d %s %.4d %.2d:%.2d:%.2d GMT',
    [WEEK[wWeek], wDay, STR_ENGLISH_M[wMonth], wYear, wHour, wMin, wSec]);
end;

function GMTRFC822ToDateTime(const pSour: AnsiString): TDateTime;
  function GetMonthDig(const Value: PAnsiChar): Integer;
  const
    STR_ENGLISH_M: array[1..12] of PAnsiChar = ('Jan', 'Feb', 'Mar', 'Apr', 'May',
      'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
  begin
    for Result := Low(STR_ENGLISH_M) to High(STR_ENGLISH_M) do begin
      if StrLIComp(Value, STR_ENGLISH_M[Result], 3) = 0 then
        Exit;
    end;
    Result := 0;
  end;
var
  P1, P2, PMax: PAnsiChar;
  wDay, wMonth, wYear, wHour, wMinute, wSec: SmallInt;
begin
  Result := 0;
  if Length(pSour) < 25 then Exit;
  P1 := Pointer(pSour);
  P2 := P1;
  PMax := P1 + Length(pSour);
  while (P1 < PMax) and (P1^ <> ',') do Inc(P1); Inc(P1);
  if (P1^ <> #32) and (P1 - P2 < 4) then Exit;
  Inc(P1); P2 := P1;
  while (P1 < PMax) and (P1^ <> #32) do Inc(P1);
  if (P1^ <> #32) then Exit;
  wDay := PCharToIntDef(P2, P1 - P2);
  if wDay = 0 then Exit;  
  Inc(P1); P2 := P1;

  while (P1 < PMax) and (P1^ <> #32) do Inc(P1);
  if (P1^ <> #32) and (P1 - P2 < 3) then Exit;
  wMonth := GetMonthDig(P2);
  Inc(P1); P2 := P1;

  while (P1 < PMax) and (P1^ <> #32) do Inc(P1);
  if (P1^ <> #32) then Exit;
  wYear := PCharToIntDef(P2, P1 - P2);
  if wYear = 0 then Exit;
  Inc(P1); P2 := P1;

  while (P1 < PMax) and (P1^ <> ':') do Inc(P1);
  if (P1^ <> ':') then Exit;
  wHour := PCharToIntDef(P2, P1 - P2);
  if wHour = 0 then Exit;
  Inc(P1); P2 := P1;

  while (P1 < PMax) and (P1^ <> ':') do Inc(P1);
  if (P1^ <> ':') then Exit;
  wMinute := PCharToIntDef(P2, P1 - P2);
  if wMinute = 0 then Exit;
  Inc(P1); P2 := P1;

  while (P1 < PMax) and (P1^ <> #32) do Inc(P1);
  if (P1^ <> #32) then Exit;
  wSec := PCharToIntDef(P2, P1 - P2);
  if wSec = 0 then Exit;

  Result := GMTToDateTime(EnCodeDateTime(wYear, wMonth, wDay, wHour, wMinute, wSec, 0));
end;

var
  LastUpdate: Cardinal = 0;
  LastGMTTime: string = '';
  FGMTLocker: TCriticalSection;

function GetNowGMTRFC822: string;
begin
  if GetTickCount - LastUpdate > 250 then begin
    FGMTLocker.Enter;
    LastGMTTime := DateTimeToGMTRFC822(Now);
    FGMTLocker.Leave;
  end;
  Result := LastGMTTime;
end;

function FixHeader(const Header: AnsiString): AnsiString;
begin
  if (iocp.Utils.Str.RightStr(Header, 4) <> HTTPHeaderEnd) then begin
    if (iocp.Utils.Str.RightStr(Header, 2) = HTTPLineBreak) then
      Result := Header + HTTPLineBreak
    else
      Result := Header + HTTPHeaderEnd;
  end else
    Result := Header;
end;

{ TIocpHttpRequest }

function NewSessionID(): string;
var
  V: TGUID;
begin
  CreateGUID(V);
  SetLength(Result, 32);
  StrLFmt(PChar(Result), 32,'%.8x%.4x%.4x%.2x%.2x%.2x%.2x%.2x%.2x%.2x%.2x',
    [V.D1, V.D2, V.D3, V.D4[0], V.D4[1], V.D4[2], V.D4[3],
    V.D4[4], V.D4[5], V.D4[6], V.D4[7]]);
end;

procedure TIocpHttpRequest.CheckCookieSession;
begin
  FSessionID := GetCookieItem(HTTPSESSIONID);
  if (FSessionID = '') and (Assigned(FResponse)) then begin
    FSessionID := HTTPSESSIONID + '_' + NewSessionID();
    FResponse.AddCookie(HTTPSESSIONID, FSessionID);
  end;
end;

procedure TIocpHttpRequest.Clear;
begin
  FreeAndNil(FParams);
  FreeAndNil(FParamHash);
  FRequestData.Clear;
  FMethod := http_Unknown;
  FDataSize := 0;
  FIsFormData := 0;
  FConn := nil;
  if Assigned(FResponse) then begin
    FResponse.Clear;
    FResponse.FRequest := Self;
  end;
  FURL := '';
  FURI.Len := 0;
  FURI.P := nil;
  FFormDataBoundary.Len := 0;
  FFormDataBoundary.P := nil;
  FCookies.P := nil;
  FCookies.Len := 0;
  FSessionID := '';
end;

procedure TIocpHttpRequest.Close;
begin
  if Assigned(Self) and Assigned(FOwner) then
    FOwner.FreeHttpRequest(Self);
end;

procedure TIocpHttpRequest.CloseConnection;
begin
  if Assigned(FConn) then
    FConn.PostWSACloseRequest;
end;

constructor TIocpHttpRequest.Create(AOwner: TIocpHttpServer);
begin
  FOwner := AOwner;
  FResponse := TIocpHttpResponse.Create;
  FResponse.FRequest := Self;
  FRequestData := TMemoryStream.Create;
end;

procedure TIocpHttpRequest.DecodeParam(P: PAnsiChar; Len: Cardinal; DecodeURL: Boolean);
var
  P1: PAnsiChar;
  Key, Value: string;
begin
  if Len = 0 then Exit;
  while (Len > 0) and ((P^ = #13) or (P^ = #10) or (P^ = #32)) do begin
    Inc(P);
    Dec(Len);
  end;
  P1 := P;
  while (P <> nil) do begin
    if P^ = '=' then begin
      SetString(Key, P1, P - P1);
      P1 := P + 1;
    end else if (P^ = '&') or (P^ = #0) or (Len = 0) then begin
      if Length(Key) > 0 then begin
        SetString(Value, P1, P - P1);
        if Length(Value) > 0 then begin
          if not Assigned(FParams) then
            FParams := TStringList.Create;
          FParamHash.Add(LowerCase(Key), FParams.Count);
          if DecodeURL then 
            Value := DecodeStr(Value);
          FParams.Add(Value);
        end;
        if (P^ = #0) or (Len = 0) then
          Break;
        Key := '';
        P1 := P + 1;
      end else if P^ = #0 then
        Break;
    end;
    Dec(Len);
    Inc(P);
  end;
end;

procedure TIocpHttpRequest.DecodeParams;
var
  P: PAnsiChar;
begin
  FParamHash := TStringHash.Create();
  // GET ��ͨ��URL���ݵĲ���
  if FURI.Len < Length(FURL) then begin
    P := Pointer(FURL);
    Inc(P, FURI.Len);
    Inc(P);
    DecodeParam(P, Length(FURL) - FURI.Len);
  end;
end;

procedure TIocpHttpRequest.ParsePostParams;
begin
  // POST ����
  if (FMethod = http_POST) and (FDataSize > 0) then begin
    if not Assigned(FParamHash) then
      DecodeParams;
    DecodeParam(PAnsiChar(FRequestData.Memory) + FHeaderSize, FDataSize, True);
  end;
end;

procedure TIocpHttpRequest.WriteBuffer(P: Pointer; Len: Cardinal);
begin
  FRequestData.Write(P^, Len);
end;

function TIocpHttpRequest.DecodeStr(const S: AnsiString): AnsiString;
var
  tmp: AnsiString;
begin
  if Pos('%', S) > 0 then begin
    try
      Result := URLDecode(S, False);
      tmp := Utf8ToAnsi(Result);
      if Length(tmp) > 0 then
        Result := tmp;
    except
      Result := '';
    end;
  end else
    Result := S;
end;

destructor TIocpHttpRequest.Destroy;
begin
  FreeAndNil(FParams);
  FreeAndNil(FParamHash);
  FreeAndNil(FResponse);
  FreeAndNil(FRequestData);
  inherited Destroy;
end;

function TIocpHttpRequest.ExistParam(const Key: AnsiString): Boolean;
begin
  if not Assigned(FParamHash) then
    DecodeParams;
  Result := FParamHash.Exists(Key);
end;

function TIocpHttpRequest.GetAccept: AnsiString;
begin
  Result := GetHeader('Accept');
end;

function TIocpHttpRequest.GetAcceptEncoding: AnsiString;
begin
  Result := GetHeader('Accept-Encoding');
end;

function TIocpHttpRequest.GetAcceptGzip: Boolean;
begin
  Result := Pos('gzip', GetAcceptEncoding()) > 0;
end;

function TIocpHttpRequest.GetAcceptLanguage: AnsiString;
begin
  Result := GetHeader('Accept-Language');
end;

function TIocpHttpRequest.GetCookieItem(const Name: AnsiString): AnsiString;
var
  P, PMax: PAnsiChar;
  Sub: PAnsiChar;
  SubLen: Integer;
  I: Integer;
begin
  InnerGetCookie();
  Result := '';
  SubLen := Length(Name);
  if (SubLen = 0) or FCookies.IsEmpty then
    Exit;
  P := FCookies.P;
  PMax := P + FCookies.Len;
  Sub := Pointer(Name);
  while P < PMax do begin
    I := PosStr(Sub, SubLen, P, PMax - P, 0);
    if I < 0 then
      Break;
    Inc(P, I + SubLen);
    if P^ = '=' then begin
      Inc(P);
      I := PosStr(';', 1, P, PMax - P, 0);
      if I < 0 then
        SetString(Result, P, PMax - P)
      else
        SetString(Result, P, I);
      Break;
    end;
  end;
end;

function TIocpHttpRequest.GetCookies: AnsiString;
begin
  InnerGetCookie();
  Result := FCookies.ToString;
end;

function TIocpHttpRequest.GetDataString: AnsiString;
begin
  if (FDataSize = 0) or (not Assigned(FRequestData)) then
    Result := ''
  else
    SetString(Result, PAnsiChar(FRequestData.Memory) + FHeaderSize, 
      FRequestData.Size - FHeaderSize);
end;

// ��һ�鹦��Ϊʵʱ��ѯ����Ҫ������ҪҲ����Ū�ɽ�������������������Լӿ��ȡ�ٶ�
function TIocpHttpRequest.GetFormDataItem(
  const Key: AnsiString): TIocpHttpFromDataItem;
var
  P, P1, P2, P3: PAnsiChar;
  B: Boolean;
begin
  Result.P := nil;
  Result.FC := nil;
  Result.Len := 0;
  if (not IsFormData) or (FRequestData.Size < FFormDataBoundary.Len) then
    Exit;
  P1 := FFormDataBoundary.P;
  P := FRequestData.Memory;
  P2 := P + FRequestData.Size;
  Inc(P, FHeaderSize);
  if PWORD(P)^ = PWORD(PAnsiChar(#13#10))^ then
    Inc(P, 2)
  else if (P^ = #13) or (P^ = #10) then
    Inc(P);
  while (P < P2 - 1) and (PWORD(P)^ = PWORD(PAnsiChar('--'))^) do begin
    Inc(P, 2);
    if StrLIComp(P, P1, FFormDataBoundary.Len) = 0 then begin
      Inc(P, FFormDataBoundary.Len + 2);
      Result.P := P;
      P3 := P2 - 3;
      B := False;
      while (P < P3) do begin
        if PDWORD(P)^ = PDWORD(PAnsiChar(#13#10#13#10))^ then begin
          B := True;
          Break;
        end;
        Inc(P);
      end;
      if not B then Break;

      Inc(P, 4);
      Result.FC := P;
      B := False; 
      while (P < P3) do begin
        if (PDWORD(P)^ = PDWORD(PAnsiChar(#13#10'--'))^) then begin
          Inc(P, 4);
          if StrLIComp(P, P1, FFormDataBoundary.Len) = 0 then begin
            B := True;
            Dec(P, 2);
          end;
          Break;
        end;
        Inc(P);
      end;

      if B then begin
        // �ɹ�ȡ��һ������
        Result.Len := P - Result.P - 2;
        if Result.Name = Key then
          Exit;     
      end;
    end else
      Break;
  end;
  Result.P := nil;
  Result.FC := nil;
  Result.Len := 0;
end;

function TIocpHttpRequest.GetHeaderStr: AnsiString;
begin
  SetString(Result, PAnsiChar(FRequestData.Memory), FHeaderSize);
end;

function TIocpHttpRequest.GetHeader(const Key: AnsiString): AnsiString;
begin
  Result := InnerGetHeader(Key, FRequestData.Memory, FHeaderSize).ToString;
end;

function TIocpHttpRequest.GetHost: AnsiString;
begin
  Result := GetHeader('Host');
end;

function TIocpHttpRequest.GetIsFormData: Boolean;
var
  S: AnsiString;
  I: Integer;
begin
  if FIsFormData = 0 then begin
    if FMethod <> http_POST then begin
      FIsFormData := 1;
      Result := False;
    end else begin
      FIsFormData := 1;
      FFormDataBoundary := InnerGetHeader('Content-Type', FRequestData.Memory, FHeaderSize);
      S := FFormDataBoundary.ToString;      
      I := Pos('multipart/form-data;', LowerCase(S));
      Result := I > 0;
      if Result then begin
        I := Pos('boundary=', LowerCase(S));
        if I > 0 then begin
          FFormDataBoundary.P := FFormDataBoundary.P + I + 8;
          FFormDataBoundary.Len := FFormDataBoundary.Len - (I + 8);
          Result := FFormDataBoundary.Len > 0;
          if Result then
            FIsFormData := 2;
        end else
          Result := False;
      end;
    end;
  end else
    Result := FIsFormData = 2;
end;

function TIocpHttpRequest.GetIsGet: Boolean;
begin
  Result := FMethod = http_GET;
end;

function TIocpHttpRequest.GetIsPost: Boolean;
begin
  Result := FMethod = http_POST
end;

function TIocpHttpRequest.GetIsPut: Boolean;
begin
  Result := FMethod = http_PUT;
end;

function TIocpHttpRequest.GetIsRange: Boolean;
begin
  Result := (FRequestVersion = hv_V2) and (FRange);
end;

function TIocpHttpRequest.GetParam(const Key: AnsiString): string;
begin
  if not Assigned(FParamHash) then
    DecodeParams;
  Result := GetParamItem(FParamHash.ValueOf(LowerCase(Key)));
end;

function TIocpHttpRequest.GetParamIndex(Index: Integer): AnsiString;
begin
  if not Assigned(FParamHash) then
    DecodeParams;
  Result := GetParamItem(Index);
end;

function TIocpHttpRequest.GetParamItem(Index: Integer): AnsiString;
begin
  if (not Assigned(FParams)) or (Index < 0) or (Index >= FParams.Count) then
    Result := ''
  else
    Result := FParams[index];  
end;

function TIocpHttpRequest.GetParamsCount: Integer;
begin
  if Assigned(FParams) then
    Result := FParams.Count
  else
    Result := 0;
end;

function TIocpHttpRequest.GetRawURL: AnsiString;
begin
  Result := FRawURL.ToString;
end;

function TIocpHttpRequest.GetReferer: AnsiString;
begin
  Result := GetHeader('Referer');
end;

const
  CSHTTP1: AnsiString = 'HTTP/1.0';
  CSHTTP2: AnsiString = 'HTTP/1.1';

function TIocpHttpRequest.GetRequestVersionStr: AnsiString;
begin
  case FRequestVersion of
    hv_V1: Result := CSHTTP1;
    hv_V2: Result := CSHTTP2;
  else
    Result := CSHTTP2; // Ĭ��1.1
  end;
end;

function TIocpHttpRequest.GetSession: Pointer;
begin
  if Length(FSessionID) = 0 then
    CheckCookieSession;
  Result := FOwner.GetSession(FSessionID);
end;

function TIocpHttpRequest.GetSessionID: string;
begin
  if Length(FSessionID) = 0 then
    CheckCookieSession;
  Result := FSessionID;
end;

function TIocpHttpRequest.GetURI: AnsiString;
begin
  Result := FURI.ToString;
end;

function TIocpHttpRequest.GetWaitRecvSize: Int64;
begin
  Result := FDataSize - (FRequestData.Size - FHeaderSize);
end;

procedure TIocpHttpRequest.InnerGetCookie;
begin
  if FCookies.IsEmpty and Assigned(FRequestData) then
    FCookies := InnerGetHeader('Cookie', FRequestData.Memory, FHeaderSize);
end;

class function TIocpHttpRequest.InnerGetHeader(const Key: AnsiString;
  const Data: Pointer; DataSize: Integer): TIocpPointerStr;
var
  I: Integer;
  P, P1, P2: PAnsiChar;
begin
  if DataSize > 0 then
    I := PosStr(PAnsiChar(Key), Length(Key), Data, DataSize, 0)
  else
    I := -1;
  if I > -1 then begin
    Inc(I, Length(Key));
    P := Data;
    P1 := P;
    Inc(P1, DataSize);
    Inc(P, I);
    while (P < P1) and (P^ <> ':') and (P^ <> #13) do
      Inc(P);
    if P^ = ':' then begin
      Inc(P);
      P2 := P;
      while (P2 < P1) and (P2^ = ' ') do Inc(P2);
      while (P < P1) and (P^ <> #13) do Inc(P);
      P1 := P - 1;
      while (P1 > P2) and (P1^ = ' ') do begin
        Dec(P);
        Dec(P1);
      end;
      Result.P := P2;
      Result.Len := P - P2;
    end else begin
      Result.Len := 0;
    end;
  end else begin
    Result.Len := 0;
  end;
end;

function TIocpHttpRequest.DecodeHttpHeader(): Boolean;
var
  P, P1, PMax: PAnsiChar;
  J: Integer;
begin
  Result := False;
  
  FHeaderSize := FRequestData.Size;
  P := FRequestData.Memory;
  PMax := P + FHeaderSize - 4;

  // ���������·��
  Inc(P, HTTPMethodLen[Integer(FMethod)]);
  if P^ <> ' ' then Exit;
  Inc(P);
  while (P < PMax) and (P^ = ' ') do Inc(P);
  P1 := P;
  while (P1 < PMax) and ((P1^ <> ' ') and (P1^ <> #13)) do Inc(P1);
  if P1^ <> ' ' then Exit;
  FRawURL.P := P;
  FRawURL.Len := P1 - P;
  FURL := DecodeStr(FRawURL.ToString);
  if Length(FURL) = 0 then Exit;  
  J := Integer(Pointer(FURL));
  P := StrScan(PAnsiChar(J), '?');
  if (P = nil) or (P^ = #0) then begin
    FURI.P := Pointer(J); //�޲�����urlһ��
    FURI.Len := Length(FURL);
  end else begin
    FURI.P := Pointer(J);
    FURI.Len := P - PAnsiChar(J);
  end;

  // ����汾��
  Inc(P1);
  if PInt64(P1)^ = PInt64(PAnsiChar(CSHTTP2))^ then begin
    FRequestVersion := hv_V2;
    FKeepAlive := True;
  end else if PInt64(P1)^ = PInt64(PAnsiChar(CSHTTP1))^ then begin
    FRequestVersion := hv_V1;
    FKeepAlive := False;
  end else
    Exit;
    
  // ��ȡ���ݳ���
  if (FMethod = http_POST) or (FMethod = http_PUT) then begin   
    FDataSize := StrToIntDef(GetHeader('Content-Length'), 0);
    if FDataSize > FOwner.FUploadMaxDataSize then
      Exit;
  end else
    FDataSize := 0;    

  // Keep-Alive
  if LowerCase(GetHeader('Connection')) = 'keep-alive' then
    FKeepAlive := True
  else
    FKeepAlive := False;
    
  Result := True;
end;

function TIocpHttpRequest.DecodeHttpHeaderRange: Boolean;
var
  S: AnsiString;
  P, P1: PAnsiChar;
begin
  Result := False;
  FRangeStart := 0;
  FRangeEnd := 0;
  FRange := False;
  if FRequestVersion = hv_V2 then begin
    S := GetHeader('Range');
    if Length(S) > 6 then begin
      P := Pointer(S);
      if (PDWORD(P)^ = PDWORD(PAnsiChar('byte'))^) and (S[5] = 's') and (S[6] = '=') then begin
        Inc(P, 6);
        P1 := StrScan(P, '-');
        if P1 = nil then begin
          FRangeStart := PCharToInt64Def(P, Length(S) - 6);
        end else begin
          FRangeStart := PCharToInt64Def(P, P1 - P);
          Inc(P1);
          P := P1;
          if P^ <> #0 then
            FRangeEnd := PCharToInt64Def(P, Length(P), 0);
        end;
        if (FRangeEnd > 0) and (FRangeEnd < FRangeStart) then
          Exit;
        FRange := (FRangeEnd > 0) or (FRangeStart > 0);
      end else
        Exit;
    end else if Length(S) > 0 then
      Exit;
  end;
  Result := True;
end;

function TIocpHttpRequest.DecodeHttpRequestMethod: TIocpHttpMethod;
var
  P: PAnsiChar;
begin
  Result := FMethod;
  if (Result <> http_Unknown) or (FRequestData.Size < 8) then
    Exit;

  P := FRequestData.Memory;
  
  if StrLIComp(P, 'GET', 3) = 0 then begin
    Result := http_GET;
  end else if StrLIComp(P, 'POST', 4) = 0 then begin
    Result := http_POST;
  end else if StrLIComp(P, 'PUT', 3) = 0 then begin
    Result := http_PUT;
  end else if StrLIComp(P, 'HEAD', 4) = 0 then begin
    Result := http_HEAD;
  end else if StrLIComp(P, 'OPTIONS', 7) = 0 then begin
    Result := http_OPTIONS;
  end else if StrLIComp(P, 'DELETE', 6) = 0 then begin
    Result := http_DELETE;
  end else if StrLIComp(P, 'TRACE', 5) = 0 then begin
    Result := http_TRACE;
  end else if StrLIComp(P, 'CONNECT', 7) = 0 then begin
    Result := http_CONNECT;
  end else
    Result := http_Unknown; 
    
  FMethod := Result;
end;

{ TIocpPointerStr }

function TIocpPointerStr.IsEmpty: Boolean;
begin
  Result := (Len = 0) or (P = nil);
end;

function TIocpPointerStr.ToString: AnsiString;
begin
  if (Len = 0) then
    Result := ''
  else
    SetString(Result, P, Len);
end;

{ TIocpHttpConnection }

procedure TIocpHttpConnection.DoJob(AJob: PIocpJob);
const
  DEBUGINFO = 'HTTP�߼�����...';
var
  Obj: TIocpHttpRequest;
begin
  while Assigned(Self) and Assigned(Owner) and (Self.Active) do begin
    Lock;
    try
      Obj := FRequestQueue.DeQueue;
      if Obj = nil then begin
        FProcessRequesting := False;
        Exit;
      end;
    finally
      UnLock;
    end;
    if Obj.FConnHandle <> Self.Handle then
      Continue;
    try
      Self.LockContext(Self, DEBUGINFO);
      try
        //OutputDebugString(PChar(Obj.FURL));
        TIocpHttpServer(Owner).DoRequest(Obj);
      except
        Obj.FResponse.ServerError(Exception(ExceptObject).Message);
      end;
      LastActivity := GetTimestamp;
    finally
      Self.UnLockContext(Self, DEBUGINFO);
      Obj.Close;
    end;
  end;
end;

procedure TIocpHttpConnection.DoRequest(ARequest: TIocpHttpRequest);
begin
  if Assigned(ARequest) then begin
    Lock;
    try
      FRequestQueue.EnQueue(ARequest);
      if not FProcessRequesting then begin
        FProcessRequesting := True;
        Workers.Post(DoJob, ARequest);
      end;
    finally
      UnLock;
    end;
  end;
end;

procedure TIocpHttpConnection.OnRecvBuffer(buf: Pointer; len: Cardinal;
  ErrorCode: Integer);
var
  L, R, I: Cardinal;
  P, P1: PAnsiChar;
  lvTempRequest: TIocpHttpRequest;
  B: Boolean;
begin
  P := Buf;
  P1 := P;
  L := Len;
  R := 0;
  
  while L > 0 do begin

    if FHttpState = hsCompleted then begin
      FRequest := TIocpHttpServer(Owner).GetHttpRequest;
      FRequest.FConn := Self;
      FRequest.FConnHandle := Self.Handle;
      FHttpState := hsRequest;
    end;

    if (FHttpState = hsRequest) then begin

      case P^ of
        #13: Inc(R);
        #10:
          if (R = 1) or (R = 3) then
            Inc(R)
          else
            R := 0;
      else
        R := 0;
      end;

      Dec(L);

      if (R > 1) or (L = 0) then begin
        FRequest.WriteBuffer(P1, P - P1 + 1);         
        P1 := P + 1;
      end else begin
        Inc(P);
        Continue;
      end;      

      if FRequest.DecodeHttpRequestMethod = http_Unknown then begin
        CloseConnection;  // ��Ч��Http����
        Exit;       
      end;

      if R = 4 then begin
        Inc(P);  // Inc(P), ��Ϊ�����Inc(P)���ᱻִ�е��ˣ����������ȼ��ϡ�
      
        if not FRequest.DecodeHttpHeader then begin
          FRequest.FResponse.ErrorRequest(400);
          Exit;
        end else begin
          if not FRequest.DecodeHttpHeaderRange() then begin
            FRequest.FResponse.ErrorRequest(416);
            Exit;
          end;
          if Assigned(TIocpHttpServer(Owner).FOnHttpFilter) then begin
            B := False;
            TIocpHttpServer(Owner).FOnHttpFilter(FRequest, B);
            if B then begin
              FRequest.FResponse.ErrorRequest(403);
              Exit;
            end;
          end;
        end;

        if (FRequest.FMethod = http_POST) or (FRequest.FMethod = http_PUT) then begin
          // �ı�Http״̬, �����������״̬
          FHttpState := hsRecvingPost;
        end else begin
          FHttpState := hsCompleted;
          lvTempRequest := FRequest;
          // ����Ͽ��󻹻ض���أ�����ظ�����
          FRequest := nil;
          // �����¼�
          DoRequest(lvTempRequest);  
          // ���ʣ�������С��һ��ֵ���Ͳ�������
          if L < 12 then
            Break
          else
            Continue;

        end;
        
      end;
            
    end;

    if FHttpState = hsRecvingPost then begin
      // ����Post������
      I := FRequest.GetWaitRecvSize;
      if I <= L then begin
        FRequest.WriteBuffer(P1, I);
        Dec(L, I);

        FHttpState := hsCompleted;
        lvTempRequest := FRequest;
        // ����Ͽ��󻹻ض���أ�����ظ�����
        FRequest := nil;
        // �����¼�
        DoRequest(lvTempRequest);
        // ���ʣ�������С��һ��ֵ���Ͳ�������
        if L < 12 then
          Break
        else begin
          //Inc(P, I);
          Owner.DoStateMsgD(Self, 'Next Request. Ignore.');
          Break;
        end;
      end else begin
        if L > 0 then
          FRequest.WriteBuffer(P, L);
        Break;
      end;                                  
    end; 
      
    Inc(P);
  end;
end;

procedure TIocpHttpConnection.ClearRequestTaskObject;
var
  Obj: TObject;
begin
  Lock;
  try
    if not FProcessRequesting then Exit; 
    while True do begin
      Obj := FRequestQueue.DeQueue;
      if Obj = nil then
        Break;
      if Assigned(Obj) then begin
        try
          FreeAndNil(Obj);
        except
          if Assigned(Owner) then
            Owner.DoStateMsgE(Self, Exception(ExceptObject));
        end;
      end;
    end;
  finally
    FProcessRequesting := False;
    UnLock;
  end;
end;

constructor TIocpHttpConnection.Create(AOwner: TIocpCustom);
begin
  inherited Create(AOwner);
  FRequestQueue := TSimpleQueue.Create();
end;

destructor TIocpHttpConnection.Destroy;
begin
  ClearRequestTaskObject;
  FreeAndNil(FRequestQueue);
  inherited Destroy;
end;

procedure TIocpHttpConnection.DoCleanUp;
begin
  inherited DoCleanUp;
  ClearRequestTaskObject;
  FProcessRequesting := False;
  FHttpState := hsCompleted;
  if FRequest <> nil then begin
    FRequest.Close;
    FRequest := nil;
  end;
end;

{ TIocpHttpServer }

constructor TIocpHttpServer.Create(AOwner: TComponent);
begin
  inherited;
  FHttpRequestPool := TBaseQueue.Create;
  FUploadMaxDataSize := 1024 * 1024 * 2;  // 2M
  FContextClass := TIocpHttpConnection;
  FSessionList := TStringHash.Create(99991);
  FSessionList.OnFreeItem := DoFreeHashItem;
end;

destructor TIocpHttpServer.Destroy;
begin
  inherited Destroy;
  try
    FHttpRequestPool.FreeDataObject;
  finally
    FreeAndNil(FHttpRequestPool);
    FreeSessionList; 
  end;
end;

procedure TIocpHttpServer.DoFreeHashItem(Item: PHashItem);
var
  P: Pointer;
begin
  if Assigned(FOnHttpFreeSession) then begin
    P := Pointer(Item.Value);
    FOnHttpFreeSession(Self, Item.Key, P);
    Item.Value := Integer(P);
  end;
end;

procedure TIocpHttpServer.DoRequest(ARequest: TIocpHttpRequest);
begin
  if not Assigned(ARequest) then Exit;
  if Assigned(FOnHttpRequest) then
    FOnHttpRequest(Self, ARequest, ARequest.FResponse);
  if not ARequest.FKeepAlive then
    ARequest.CloseConnection;
end;

procedure TIocpHttpServer.FreeHttpRequest(V: TIocpHttpRequest);
begin
  if not Assigned(V) then Exit;
  V.Clear;
  FHttpRequestPool.EnQueue(V);
end;

procedure TIocpHttpServer.FreeSessionList;
begin
  FreeAndNil(FSessionList);
end;

function TIocpHttpServer.GetHttpRequest: TIocpHttpRequest;
begin
  Result := TIocpHttpRequest(FHttpRequestPool.DeQueue);
  if not Assigned(Result) then
    Result := TIocpHttpRequest.Create(Self)
  else
    Result.FOwner := Self;
end;

function TIocpHttpServer.GetSession(const SID: string): Pointer;
begin
  Result := Pointer(FSessionList.ValueOf(SID));
  if (Result = nil) and Assigned(FOnHttpGetSession) then begin
    Result := FOnHttpGetSession(Self, SID);
    FSessionList.AddOrUpdate(SID, Integer(Result));
  end;
end;

{ TIocpHttpResponse }

const
  ContextLength0 = 'Content-Length: 0'#13#10;

function TIocpHttpResponse.AddCookie: TIocpHttpCookie;
begin
  Result := TIocpHttpCookie.Create;
  if not Assigned(FCookies) then
    FCookies := TList.Create;
  FCookies.Add(Result);
end;

function TIocpHttpResponse.AddCookie(const Name, Value: AnsiString): TIocpHttpCookie;
begin
  Result := AddCookie;
  Result.Name := Name;
  Result.Value := Value;
end;

function TIocpHttpResponse.AddCookie(const Name, Value: AnsiString;
  MaxAge: Cardinal): TIocpHttpCookie;
begin
  Result := AddCookie;
  Result.Name := Name;
  Result.Value := Value;
  Result.MaxAge := MaxAge;
end;

function TIocpHttpResponse.CheckFileUpdate(const Last: TDateTime): Boolean;
var
  T: TDateTime;
begin
  if (Last > 0) and (not Request.IsRange) then begin
    // �����ļ�ʱ���жϿͻ������������޸�ʱ�䣬���û�б仯�ͷ��� 304
    T := GMTRFC822ToDateTime(Request.GetHeader('If-Modified-Since'));
    if (T > 0) and (SecondsBetween(T, Last) = 0) then begin
      Result := False;
      ResponeCode(304);
      Exit;
    end;
  end;
  Result := True;
end;

procedure TIocpHttpResponse.Clear;
var
  I: Integer;
begin
  FContentType := '';
  FCacheTime := 0;
  {$IFDEF UseGZip}
  FGZip := True;
  {$ENDIF}
  if Assigned(FBlockSendBuffer) then
    FBlockSendBuffer.Clear;
  if Assigned(FCookies) then begin
    for I := 0 to FCookies.Count - 1 do
      TObject(FCookies[I]).Free;
    FCookies.Clear;
  end;
end;

constructor TIocpHttpResponse.Create;
begin
  FGZip := True;
end;

destructor TIocpHttpResponse.Destroy;
begin
  FreeAndNil(FBlockSendBuffer);
  FreeAndNil(FCookies);
  inherited;
end;

function GetResponseCodeNote(V: Word): AnsiString;
begin
  case V of
    100: Result := 'Continue';
    101: Result := 'Switching Protocols';
    102: Result := 'Processing';
    200: Result := 'OK';
    201: Result := 'Created';
    202: Result := 'Accepted';
    203: Result := 'Non-Authoriative Information';
    204: Result := 'No Content';
    205: Result := 'Reset Content';
    206: Result := 'Partial Content';
    207: Result := 'Multi-Status';
    300: Result := 'Multiple Choices';
    301: Result := 'Moved Permanently';
    302: Result := 'Found';
    303: Result := 'See Other';
    304: Result := 'Not Modified';
    305: Result := 'Use Proxy';
    306: Result := '(Unused)';
    307: Result := 'Temporary Redirect';
    400: Result := 'Bad Request';
    401: Result := 'Unauthorized';
    403: Result := 'Forbidden';
    404: Result := 'Not Found';
    405: Result := 'Method Not Allowed';
    406: Result := 'Not Acceptable';
    407: Result := 'Proxy Authentication Required';
    408: Result := 'Request Timeout';
    409: Result := 'Conflict';
    410: Result := 'Gone';
    411: Result := 'Length Required';
    412: Result := 'Precondition Failed';
    413: Result := 'Request Entity Too Large';
    414: Result := 'Request URI Too Long';
    415: Result := 'An Unsupported Media Type';
    416: Result := 'Requested Range Not Satisfiable';
    417: Result := 'On Failure';
    422: Result := 'Unprocessable Entity';
    423: Result := 'Locked';
    424: Result := 'Failed Dependency';
    500: Result := 'Internal Server Error';
    501: Result := 'Not Implemented';
    502: Result := 'Bad Gateway';
    503: Result := 'Service Unavailable';
    504: Result := 'Gateway Timeout';
    505: Result := 'Version Not Supported';
    507: Result := 'Insufficient Storage';
  else
    Result := 'Unknown Error';
  end;
end;

procedure TIocpHttpResponse.ServerError(const Msg: AnsiString);
begin
  if (not Active) then Exit;
  Send(Format('<html><head><meta http-equiv="Content-Type" content="text/html; '+
      'charset=gb2312"></head>'#13'<body><font color="red"><b>%s</b></font><br>'+
      '<br>%s<br>'#13'</body></html>', [GetResponseCodeNote(500), Msg]));
  FRequest.FConn.CloseConnection;
end;

procedure TIocpHttpResponse.ErrorRequest(ErrorCode: Word);
begin
  if (not Active) or (ErrorCode < 400) then Exit;
  FRequest.FConn.Send(
    FixHeader(MakeHeader(0, IntToStr(ErrorCode) + ' ' +
    GetResponseCodeNote(ErrorCode))));
  FRequest.FConn.CloseConnection;
end;

function TIocpHttpResponse.GetActive: Boolean;
begin
  if Assigned(FRequest) and Assigned(FRequest.FConn) then
    Result := FRequest.FConn.Active
  else
    Result := False;
end;

function TIocpHttpResponse.GetBlockHeader: AnsiString;
begin
  Result := FixHeader(MakeHeader(0) + 'Transfer-Encoding: chunked'#13#10);
end;

function TIocpHttpResponse.GetConnection: TIocpHttpConnection;
begin
  if Assigned(FRequest) then
    Result := FRequest.FConn
  else
    Result := nil;
end;

function TIocpHttpResponse.GetContentType: AnsiString;
begin
  if Length(FContentType) > 0 then   
    Result := FContentType
  else
    Result := 'text/html';
end;

class function TIocpHttpResponse.GetFileLastModified(
  const AFileName: string): TDateTime;
begin
  Result := GetFileLastWriteTime(AFileName);
end;

{$IFDEF UseGZip}
function TIocpHttpResponse.GZCompress(inStream, outStream: TStream): Boolean;
begin
  GZCompressStream(inStream, outStream);
  Result := True;
end;

function TIocpHttpResponse.GZCompress(Buf: Pointer; Len: Cardinal): AnsiString;
var
  S: AnsiString;
begin
  if Len = 0 then
    Result := ''
  else begin
    SetLength(S, Len);
    Move(Buf^, S[1], Len);
    Result := GZCompressStr(S);
  end;
end;

function TIocpHttpResponse.GZCompress(const Data: WideString): AnsiString;
var
  S: AnsiString;
begin
  if Length(Data) = 0 then
    Result := ''
  else begin
    SetLength(S, Length(Data) shl 1);
    Move(Data[1], S[1], Length(S));
    Result := GZCompressStr(S);
  end;
end;
{$ENDIF}

{$IFDEF UseGZip}
function TIocpHttpResponse.GZCompress(const Data: AnsiString): AnsiString;
begin
  Result := GZCompressStr(Data);
end;
{$ENDIF}

function TIocpHttpResponse.MakeHeader(ContextLength: Int64; const Status: AnsiString;
  FileDown: Boolean; const FileName: AnsiString; const LastModified: TDateTime): AnsiString;
const
  CSVRNAME: AnsiString = #13#10'Server: DIOCP-YXD/1.0'#13#10;
  CSDFILE: AnsiString = 'Accept-Ranges: bytes'#13#10 +
    'Content-Disposition: attachment;filename="%s"'#13#10'Last-Modified: %s'#13#10;
var
  Data: TStringCatHelperA;
  I: Integer;
begin
  Data := TStringCatHelperA.Create;
  Data.Cat(FRequest.RequestVersionStr);
  if (Length(Status) = 0) then begin
    // ���������� (���ڶϵ㴫��)
    if FileDown and FRequest.IsRange then begin
      Data.Cat(' 206 Partial Content');
    end else
      Data.Cat(' 200 OK');
  end else
    Data.Cat(' ').Cat(Status);
  Data.Cat(CSVRNAME);

  Data.Cat('Date: ').Cat(GetNowGMTRFC822()).Cat(HTTPLineBreak);
  Data.Cat('Content-Type: ').Cat(GetContentType).Cat(HTTPLineBreak);

  //if ContextLength > 0 then
  Data.Cat('Content-Length: ').Cat(ContextLength).Cat(HTTPLineBreak);

  {$IFDEF UseGZip}
  if FGZip then
    Data.Cat('Content-Encoding: gzip'#13#10);
  {$ENDIF}

  if FCacheTime > 0 then
    Data.Cat('Cache-Control: max-age=').Cat(FCacheTime).Cat(HTTPLineBreak);
    
  if FileDown then begin
    if LastModified > 0 then
      Data.Cat(Format(CSDFILE, [FileName, DateTimeToGMTRFC822(LastModified)]))
    else
      Data.Cat('Accept-Ranges: bytes'#13#10'Content-Disposition: attachment;filename="')
        .Cat(FileName).Cat('"'#13#10);
  end;

  if Assigned(FCookies) then begin  
    for I := 0 to FCookies.Count - 1 do
      Data.Cat('Set-Cookie:').Cat(TIocpHttpCookie(FCookies[i]).ToString()).Cat(HTTPLineBreak);
  end;
  
  if Request.FKeepAlive then
    Data.Cat('Connection: Keep-Alive'#13#10)
  else
    Data.Cat('Connection: close'#13#10);

  Result := Data.Value;
  Data.Free;
end;

procedure TIocpHttpResponse.RedirectURL(const pvURL: AnsiString);
begin
  if (not Active) or (Length(pvURL) = 0) then Exit;
  FRequest.FConn.Send(
    FixHeader(MakeHeader(0, '302 Temporarily Moved') + 'Location: ' + pvURL));
  FRequest.FConn.CloseConnection;
end;

procedure TIocpHttpResponse.ResponeCode(Code: Word; const Data: AnsiString);
begin
  if (not Active) or (Code < 100) then Exit;
  FRequest.FConn.Send(
    FixHeader(MakeHeader(Length(Data), IntToStr(Code) + ' ' +
    GetResponseCodeNote(Code))) + Data);
end;

const
  MaxHttpOSS = $40000;  // Http���ݳ�����ֵʱ���ȷ���Э��ͷ�ٷ�������

procedure TIocpHttpResponse.Send(buf: Pointer; len: Cardinal; AGZip: Boolean);
var
  s: AnsiString;
begin
  if (not Active) then Exit;
  if (len = 0) or (buf = nil) then begin
    Send('');
    Exit;
  end;
  {$IFDEF UseGZip}
  FGZip := AGZip;
  if AGZip then begin
    s := GZCompress(buf, len);
    if Length(s) > MaxHttpOSS then begin
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(s))));
      FRequest.FConn.Send(s);
    end else
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(s))) + s);
  end else
  {$ENDIF}
  begin  
    if len > MaxHttpOSS then begin
      FRequest.FConn.Send(FixHeader(MakeHeader(len)));
      FRequest.FConn.Send(buf, len);
    end else begin
      SetString(s, PAnsiChar(buf), len);
      CopyMemory(@s[1], buf, len);
      FRequest.FConn.Send(FixHeader(MakeHeader(len)) + s);
    end;
  end;
end;

procedure WriteStringToStream(Stream: TStream; const V: AnsiString); overload;
begin
  Stream.Write(V[1], Length(V));
end;

procedure WriteStringToStream(Stream: TStream; const V: WideString); overload;
begin
  Stream.Write(Pointer(V)^, Length(V) shl 1);
end;

procedure TIocpHttpResponse.Send(Stream: TStream; AGZip: Boolean);
{$IFDEF UseGZip}
var
  S: TMemoryStream;
  L: NativeUInt;
{$ENDIF}
begin
  if not Active then Exit;
  if not Assigned(Stream) then begin
    Send('');
    Exit;
  end;
  {$IFDEF UseGZip}
  FGZip := AGZip;
  L := Stream.Size - Stream.Position;
  if L < 1024 then
    FGZip := False;
  if FGZip and (L > 0) then begin
    S := TMemoryStream.Create;
    try
      GZCompressStream(Stream, S);
      S.Position := 0;
      SendStream(S);
    finally
      S.Free;
    end;
  end else
  {$ENDIF}
    SendStream(Stream);
end;

procedure TIocpHttpResponse.SendChunk(const Data: AnsiString);
begin
  if (not Active) or (not Assigned(FBlockSendBuffer)) then Exit;
  if Length(Data) = 0 then Exit;
  WriteStringToStream(FBlockSendBuffer, AnsiString(IntToHex(Length(Data), 2) + HTTPLineBreak));
  WriteStringToStream(FBlockSendBuffer, Data);
  WriteStringToStream(FBlockSendBuffer, AnsiString(HTTPLineBreak));
end;

procedure TIocpHttpResponse.SendChunk(const Data: WideString);
begin
  if (not Active) or (not Assigned(FBlockSendBuffer)) then Exit;
  if Length(Data) = 0 then Exit;
  WriteStringToStream(FBlockSendBuffer, AnsiString(IntToHex(Length(Data) shl 1, 2) + HTTPLineBreak));
  WriteStringToStream(FBlockSendBuffer, Data);
  WriteStringToStream(FBlockSendBuffer, AnsiString(HTTPLineBreak));
end;

procedure TIocpHttpResponse.SendChunk(buf: Pointer; len: Cardinal);
begin
  if (not Active) or (not Assigned(FBlockSendBuffer)) then Exit;
  if len = 0 then Exit;
  WriteStringToStream(FBlockSendBuffer, AnsiString(IntToHex(len, 2) + HTTPLineBreak));
  FBlockSendBuffer.Write(buf^, len);
  WriteStringToStream(FBlockSendBuffer, AnsiString(HTTPLineBreak));
end;

procedure TIocpHttpResponse.SendChunk(Stream: TStream);
var
  I, J: Integer;
  Buf: array [0..4095] of Byte;
  P: Pointer;
begin
  if (not Active) or (not Assigned(FBlockSendBuffer)) then Exit;
  I := Stream.Size - Stream.Position;
  if I = 0 then Exit;
  WriteStringToStream(FBlockSendBuffer, AnsiString(IntToHex(I, 2) + HTTPLineBreak));
  if (Stream is TMemoryStream) then begin
    P := Pointer(IntPtr(TMemoryStream(Stream).Memory) + Stream.Position);
    FBlockSendBuffer.Write(P^, I);
  end else begin
    while I > 0 do begin
      if I > SizeOf(Buf) then
        J := Stream.Read(Buf, SizeOf(Buf))
      else
        J := Stream.Read(Buf, I);
      if J > 0 then begin
        FBlockSendBuffer.Write(Buf, J);
        Dec(I, J);
      end;
    end;
  end;
  WriteStringToStream(FBlockSendBuffer, AnsiString(HTTPLineBreak));
end;

procedure TIocpHttpResponse.SendChunkEnd;
begin
  if not Assigned(FBlockSendBuffer) then Exit;
  WriteStringToStream(FBlockSendBuffer, AnsiString('0' + HTTPHeaderEnd));
  FBlockSendBuffer.Position := 0;
  FRequest.FConn.Send(FBlockSendBuffer);
  FBlockSendBuffer.Clear;
end;

procedure TIocpHttpResponse.SendChunkHeader(AGZip: Boolean);
begin
  {$IFDEF UseGZip}
  FGZip := AGZip;
  {$ENDIF}
  if not Assigned(FBlockSendBuffer) then
    FBlockSendBuffer := TMemoryStream.Create;
  WriteStringToStream(FBlockSendBuffer, GetBlockHeader);
end;

procedure TIocpHttpResponse.SendContent(const Data: WideString);
begin
  if (not Active) then Exit;
  FRequest.FConn.Send(Data);
end;

procedure TIocpHttpResponse.SendFile(const FileName, AContentType: string);
var
  S: TFileOnlyStream;
  Last: TDateTime;
begin
  if (not Active) then Exit;
  if not FileExists(FileName) then begin
    ErrorRequest(404);
    Exit;
  end;
  Last := GetFileLastWriteTime(FileName);
  // �����ļ�ʱ���жϿͻ������������޸�ʱ�䣬���û�б仯�ͷ��� 304
  if not CheckFileUpdate(Last) then
    Exit;
  S := TFileOnlyStream.Create(FileName);
  try
    FGZip := False;
    S.Position := 0;
    if Length(AContentType) = 0 then
      SendStream(S, True, FileName, HTTPCTTypeStream, Last)
    else
      SendStream(S, True, FileName, AContentType, Last);
  finally
    S.Free;
  end;
end;

procedure TIocpHttpResponse.SendFileData(const Data: AnsiString; const FileName,
  AContentType: AnsiString; const LastModified: TDateTime; AGZip: Boolean);
var
  S: TIocpPointerStream;
begin
  if (not Active) then Exit;
  S := TIocpPointerStream.Create;
  try
    S.SetPointer(Pointer(Data), Length(Data));
    SendFileStream(S, FileName, AContentType, LastModified, AGZip);
  finally
    S.Free;
  end;
end;

procedure TIocpHttpResponse.SendFileData(const Data: WideString; const FileName,
  AContentType: AnsiString; const LastModified: TDateTime; AGZip: Boolean);
var
  S: TIocpPointerStream;
begin
  if (not Active) then Exit;
  S := TIocpPointerStream.Create;
  try
    S.SetPointer(Pointer(Data), Length(Data) shl 1);
    SendFileStream(S, FileName, AContentType, LastModified, AGZip);
  finally
    S.Free;
  end;
end;

procedure TIocpHttpResponse.SendFileData(const Data: Pointer; DataLen: Cardinal;
  const FileName, AContentType: AnsiString; const LastModified: TDateTime;
  AGZip: Boolean);
var
  S: TIocpPointerStream;
begin
  if (not Active) or (DataLen = 0) or (Data = nil) then Exit;
  S := TIocpPointerStream.Create;
  try
    S.SetPointer(Data, DataLen);
    SendFileStream(S, FileName, AContentType, LastModified, AGZip);
  finally
    S.Free;
  end;
end;

procedure TIocpHttpResponse.SendFileStream(AFileStream: TStream;
  const FileName, AContentType: AnsiString; const LastModified: TDateTime;
  AGZip: Boolean);
var
  S: TMemoryStream;
begin
  if (not Active) then Exit;
  {$IFDEF UseGZip}
  FGZip := AGZip;
  if AGZip then begin
    FGZip := True;
    S := TMemoryStream.Create;
    try
      GZCompress(AFileStream, S);
      S.Position := 0;
      if Length(AContentType) = 0 then begin
        SendStream(S, True, FileName, HTTPCTTypeStream, LastModified)
      end else
        SendStream(S, True, FileName, AContentType, LastModified);
    finally
      S.Free;
    end;
  end else {$ENDIF} begin
    if Length(AContentType) = 0 then begin
      SendStream(AFileStream, True, FileName, HTTPCTTypeStream, LastModified)
    end else
      SendStream(AFileStream, True, FileName, AContentType, LastModified);
  end;
end;

procedure TIocpHttpResponse.SendContent(const Data: AnsiString);
begin
  if (not Active) then Exit;
  FRequest.FConn.Send(Data);
end;

procedure TIocpHttpResponse.SendHeader(DataSize: NativeUInt; AGZip: Boolean);
begin
  if (not Active) then Exit;
  if DataSize < 1 then
    Send('')
  else begin
    {$IFDEF UseGZip}
    FGZip := AGZip;
    {$ENDIF}
    FRequest.FConn.Send(FixHeader(MakeHeader(DataSize)));
  end;
end;

function SpanOfNowAndThen(const ANow, AThen: TDateTime): TDateTime; inline;
begin
  if ANow < AThen then
    Result := AThen - ANow
  else
    Result := ANow - AThen;
end;

function SecondsBetween(const ANow, AThen: TDateTime): Int64; 
begin
  Result := Round(SecsPerDay * SpanOfNowAndThen(ANow, AThen));
end;

procedure TIocpHttpResponse.SendStream(Stream: TStream; IsDownloadFile: Boolean;
  const AFileName, AContentType: AnsiString; const LastModified: TDateTime);
var
  L: Int64;
  I: Integer;
  Buf: array [0..4095] of Byte;
  Header: AnsiString;
  IsRange: Boolean;
  T: TDateTime;
begin
  L := Stream.Size - Stream.Position;
  if IsDownloadFile then begin
    // �ļ�����ģʽ��֧����������/�ϵ�����
    FContentType := AContentType;
    IsRange := FRequest.IsRange;

    if (LastModified > 0) and (not IsRange) then begin
      // �����ļ�ʱ���жϿͻ������������޸�ʱ�䣬���û�б仯�ͷ��� 304
      T := GMTRFC822ToDateTime(Request.GetHeader('If-Modified-Since'));
      if (T > 0) and (SecondsBetween(T, LastModified) = 0) then begin
        ResponeCode(304);
        Exit;
      end;
    end else if (IsRange) and (LastModified > 0) then begin
      // �ж��ļ��Ƿ��Ѿ��޸ģ�����Ѿ��޸ģ�������ֿ�����
      T := GMTRFC822ToDateTime(Request.GetHeader('If-Range'));
      if (T > 0) and (SecondsBetween(T, LastModified) > 0) then
        // �Ѿ��޸ģ�����ȫ������
        IsRange := False
      else begin
        T := GMTRFC822ToDateTime(Request.GetHeader('If-Unmodified-Since'));
        if (T > 0) and (SecondsBetween(T, LastModified) > 0) then begin
          // �Ѿ��޸ģ�����������
          IsRange := False;
          L := 0;
        end;
      end;
    end;

    if (IsRange) then begin
      if FRequest.FRangeStart >= L then
        Exit;
      if FRequest.FRangeEnd = 0 then
        FRequest.FRangeEnd := L - 1;
      Header := Format('Content-Range: bytes %d-%d/%d', [
          FRequest.FRangeStart, FRequest.FRangeEnd, L]);
      L := FRequest.FRangeEnd - FRequest.FRangeStart + 1;
      Header := FixHeader(MakeHeader(L, '', IsDownloadFile, ExtractFileName(AFileName), LastModified) + Header);
      if FRequest.FRangeStart > 0 then
        Stream.Position := Stream.Position + FRequest.FRangeStart;
    end else begin
      Header := FixHeader(MakeHeader(L, '', IsDownloadFile,
        ExtractFileName(AFileName), LastModified));
    end;

  end else
    Header := FixHeader(MakeHeader(L));
  if L > MaxHttpOSS then begin
    FRequest.FConn.Send(Header);
    FRequest.FConn.Send(Stream, L);
  end else begin
    if not Assigned(FBlockSendBuffer) then
      FBlockSendBuffer := TMemoryStream.Create
    else
      FBlockSendBuffer.Clear;
    try
      WriteStringToStream(FBlockSendBuffer, Header);
      while L > 0 do begin
        I := Stream.Read(Buf, SizeOf(Buf));
        if I > 0 then begin
          FBlockSendBuffer.Write(Buf, I);
          Dec(L, I);
        end else
          Break;
      end;
      FBlockSendBuffer.Position := 0;
      FRequest.FConn.Send(FBlockSendBuffer, FBlockSendBuffer.Size);
    finally
      FBlockSendBuffer.Clear;
    end;
  end;
end;

procedure TIocpHttpResponse.Send(const Data: AnsiString; AGZip: Boolean);
{$IFDEF UseGZip}
var s: AnsiString;
{$ENDIF}
begin
  if (not Active) then Exit;
  if Length(Data) = 0 then begin
    // 0���ȵķ������ݣ�д��һ��#0��������Щ�������ȴ�
    FRequest.FConn.Send(FixHeader(MakeHeader(0)) + #0);
    Exit;
  end;
  {$IFDEF UseGZip}
  FGZip := AGZip;
  if FGZip then begin
    s := GZCompressStr(Data);
    if (Length(s)) > MaxHttpOSS then begin
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(s))));
      FRequest.FConn.Send(s);
    end else
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(s))) + s);
  end else
  {$ENDIF}
  begin
    if (Length(Data)) > MaxHttpOSS then begin
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(Data))));
      FRequest.FConn.Send(Data);
    end else
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(Data))) + Data);
  end;
end;

procedure TIocpHttpResponse.Send(const Data: WideString; AGZip: Boolean);
{$IFDEF UseGZip}
var s: AnsiString;
{$ENDIF}
begin
  if (not Active) then Exit;
  if Length(Data) = 0 then begin
    // 0���ȵķ������ݣ�д��һ��#0��������Щ�������ȴ�
    FRequest.FConn.Send(FixHeader(MakeHeader(0)) + #0);
    Exit;
  end;
  {$IFDEF UseGZip}
  FGZip := AGZip;
  if FGZip then begin
    s := GZCompress(Data);
    if (Length(s)) > MaxHttpOSS then begin
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(s))));
      FRequest.FConn.Send(s);
    end else
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(s))) + s);
  end else
  {$ENDIF}
  begin
    if (Length(Data)) > MaxHttpOSS then begin
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(Data) shl 1)));
      FRequest.FConn.Send(Data);
    end else begin
      {$IFDEF UNICODE}
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(Data) shl 1)));
      FRequest.FConn.Send(Data);
      {$ELSE}
      FRequest.FConn.Send(FixHeader(MakeHeader(Length(Data) shl 1)) + Data);
      {$ENDIF}
    end;
  end;
end;

{ TIocpPointerStream }

constructor TIocpPointerStream.Create;
begin
  inherited Create;
end;

constructor TIocpPointerStream.Create(const Ptr: Pointer; ASize: Integer);
begin
  inherited Create;
  SetPointer(Ptr, ASize);
end;

function TIocpPointerStream.Write(const Buffer; Count: Integer): Longint;
begin
  raise Exception.Create('PointerStream Ban Written.');
end;

{ TIocpHttpFromDataItem }

function TIocpHttpFromDataItem.GetContentStream: TStream;
begin
  if (Len = 0) or (P = nil) or (FC < P) then
    Result := nil
  else begin
    Result := TIocpPointerStream.Create;
    TIocpPointerStream(Result).SetPointer(FC, Len - HeaderSize);
  end;
end;

function TIocpHttpFromDataItem.GetContentType: AnsiString;
begin
  if Len = 0 then
    Result := ''
  else
    Result := TIocpHttpRequest.InnerGetHeader('Content-Type', P, FC - P).ToString;
end;

function TIocpHttpFromDataItem.GetDisposition: AnsiString;
begin
  if Len = 0 then
    Result := ''
  else
    Result := TIocpHttpRequest.InnerGetHeader('Content-Disposition', P, FC - P).ToString;
end;

function TIocpHttpFromDataItem.GetFileName: AnsiString;
var
  I: Integer;
  P, P1: PAnsiChar;
begin
  Result := GetDisposition;
  if Length(Result) > 0 then begin
    I := Pos(AnsiString('filename="'), Result);
    if I > 0 then begin
      P := PAnsiChar(Result) + I + 9;
      P1 := StrScan(P, '"');
      if P1 <> nil then
        SetString(Result, P, P1 - P);
    end;
  end;
end;

function TIocpHttpFromDataItem.GetHeaderSize: Integer;
begin
  if (Len = 0) or (P = nil) or (FC = nil) then
    Result := 0
  else
    Result := FC - P;
end;

function TIocpHttpFromDataItem.GetIsFile: Boolean;
begin
  Result := Pos(AnsiString('filename="'), GetDisposition) > 0;
end;

function TIocpHttpFromDataItem.GetName: AnsiString;
var
  I: Integer;
  P, P1: PAnsiChar;
begin
  Result := GetDisposition;
  if Length(Result) > 0 then begin
    I := Pos(AnsiString('name="'), Result);
    if I > 0 then begin
      P := PAnsiChar(Result) + I + 5;
      P1 := StrScan(P, '"');
      if P1 <> nil then
        SetString(Result, P, P1 - P);
    end;
  end;
end;

procedure TIocpHttpFromDataItem.SaveContentToStream(const Stream: TStream);
begin
  if Assigned(Stream) and (Len > 0) and (P <> nil) or (FC > P) then
    Stream.Write(FC^, Len - HeaderSize);
end;

function TIocpHttpFromDataItem.GetContent: AnsiString;
begin
  if (Len > 0) and (P <> nil) or (FC > P) then
    SetString(Result, FC, Len - HeaderSize)
  else
    Result := '';
end;

{ TFileOnlyStream }

constructor TFileOnlyStream.Create(const AFileName: string);
begin
  inherited Create(_lopen(PAnsiChar(AnsiString(AFileName)), OF_READ));
end;

destructor TFileOnlyStream.Destroy;
begin
  if FHandle >= 0 then _lclose(FHandle);
  inherited Destroy;
end;

{ TIocpHttpCookie }

constructor TIocpHttpCookie.Create;
begin
  FMaxAge := 604800; // 7 ��
  FPath := '/';
end;

function TIocpHttpCookie.ToString: AnsiString;
begin
  Result := Format('%s=%s; path=%s', [FName, FValue, FPath]);   
  if FExpires > 0 then   
    Result := Result + '; expires=' + DateTimeToGMTRFC822(FExpires);
  if FMaxAge > 0 then
    Result := Result + '; max-age=' + IntToStr(FMaxAge);
  if Length(FDoMain) > 0 then
    Result := Result + '; domain=' + FDoMain;
end;

initialization
  DLocalTimeZoneBias := LocalTimeZoneBias / 1440;
  FGMTLocker := TCriticalSection.Create;
  Workers := TIocpTask.GetInstance;

finalization
  Workers := nil;
  FreeAndNil(FGMTLocker);

end.


