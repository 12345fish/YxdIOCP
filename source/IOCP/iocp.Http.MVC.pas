{*******************************************************}
{                                                       }
{       Http ���� MVC ���ĵ�Ԫ                          }
{                                                       }
{       ��Ȩ���� (C) 2016 yangyxd                       }
{                                                       }
{*******************************************************}

unit iocp.Http.MVC;

interface

{$I 'iocp.inc'}

{$IF (RTLVersion>=26)}
{$DEFINE UseMvc}
{$ENDIF}

{$IFNDEF UseMvc}
{$MESSAGE WARN 'iocp.Http.MVC ��Ԫ��⵽��ǰIDE�汾���ͣ������޷�����ʹ�á�'}
{$ENDIF}

uses
  iocp.Http, iocp.Http.WebSocket, iocp.Sockets,
  iocp.Utils.Str,
  
  XML,
  
  {$IFDEF MSWINDOWS}Windows, {$ENDIF}
  Generics.Collections, Rtti, System.Generics.Defaults,
  SysUtils, Classes, Variants, TypInfo;

type
  TCustomAttributeClass = class of TCustomAttribute;
  TCompareAttributeItem = reference to function (const Item: TCustomAttribute; 
    const Data: Pointer): Boolean;  

  /// <summary>
  /// TObject Helper ���� RTTI ������
  /// </summary>
  TObjectHelper = class helper for TObject
  private
    function GetRealAttrName(const AttrName: string): string;
  public
    class procedure RegToMVC();
    function CheckAttribute(ARttiType: TRttiType; ACompare: TCompareAttributeItem;
      const Data: Pointer = nil): Boolean; overload;
    function CheckAttribute(const Attributes: TArray<TCustomAttribute>;
      ACompare: TCompareAttributeItem;
      const Data: Pointer = nil): Boolean; overload;
    /// <summary>
    /// ��⵱ǰ����ĸ������ԡ�
    /// </summary>
    function CheckAttribute(ACompare: TCompareAttributeItem; const Data: Pointer = nil): Boolean; overload;
    /// <summary>
    /// ����Ƿ����ָ�����͵�����
    /// </summary>
    function ExistAttribute(const AttrType: TCustomAttributeClass): Boolean; overload;
    function ExistAttribute(const Attributes: TArray<TCustomAttribute>;
      const AttrType: TCustomAttributeClass): Boolean; overload;
    /// <summary>
    /// ����Ƿ����ָ�����Ƶ����� (��Ҫ��������������"Attribute"����)
    /// </summary>
    function ExistAttribute(const AttrName: string): Boolean; overload;
    function ExistAttribute(const Attributes: TArray<TCustomAttribute>;
      const AttrName: string): Boolean; overload;
    /// <summary>
    /// ��ȡָ��������ָ���ֶ�����ֵ
    /// </summary>
    function GetAttribute<T>(const AttrName, FiledName: string): T; overload;
    function GetAttribute<T>(const AttrName, FiledName: string; const DefaultValue: T): T; overload; 

    function GetRttiValue<T>(const Name: string): T; 
    procedure SetRttiValue<T>(const Name: string; const Value: T);

    function CreateObject(const ARttiType: TRttiType; const Args: array of TValue): TObject; overload;
    function CreateObject(const AClassName: string; const Args: array of TValue): TObject; overload;

    procedure Log(const Msg: string);
  end;

type
  /// <summary>
  /// MVC ɨ���� - ����ע��ָ����ʶ�������Map��
  /// </summary>
  TIocpMvcScanner = class(TObject)
  private
    FScannerOK: Boolean;
    FClassMap: TDictionary<string, TObject>;
    FRttiContext: TRttiContext;
  protected
    procedure DoValueNotify(Sender: TObject; const Item: TObject; 
      Action: System.Generics.Collections.TCollectionNotification);
    function GetAllTypes: TArray<TRttiType>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>
    /// �Զ�ɨ��ϵͳ�е��࣬��ʼ����ע�� [Service, Controller] ����
    /// </summary>
    procedure StartScan;
    procedure Clear;

    procedure RegClass(AClass: TClass); overload;
    procedure RegClass(AClass: TRttiType); overload;
  end;

type
  /// <summary>
  /// URI ӳ����Ϣ
  /// </summary>
  TUriMapData = record
  private
    function GetParamName: string;
    function GetParamValue: string;
    function GetHeaderName: string;
    function GetHeaderValue: string;
  public
    URI: string;
    DownMode: Boolean;
    ResponseBody: Boolean;
    Method: TIocpHttpMethod;
    Consumes, Produces, Params, Headers: string;
    // ������ʵ������
    Controller: TObject;
    // ����������
    MethodIndex: Integer;
    procedure Clear;
    property ParamName: string read GetParamName;
    property ParamValue: string read GetParamValue;
    property HeaderName: string read GetHeaderName;
    property HeaderValue: string read GetHeaderValue;
  end;

type
  /// <summary>
  /// Web Socket ӳ����Ϣ
  /// </summary>
  TWebSocketMapData = record
    // �������ı���Ϣ������Data���ʱ�Ŵ�������. �Ƿ��Сд������ MvcServer ���ơ�
    Data: string;
    ResponseBody: Boolean;
    // ������ʵ������
    Controller: TObject;
    // ����������
    MethodIndex: Integer;  
    class function Create(AController: TObject; AMethodIndex: Integer): TWebSocketMapData; static; 
  end;

type
  /// <summary>
  /// ���л����� - �������¼������л�����
  /// </summary>
  TOnSerializeRequest = function (Sender: TObject; const Value: TValue): string of object;
  /// <summary>
  /// �����л����� - �������¼��з����л�����
  /// </summary>
  TOnDeSerializeRequest = function (Sender: TObject; const Value: string;
    const Dest: TValue; IsGet: Boolean): Boolean of object;

type
  /// <summary>
  /// ֧�� MVC ���ܵ� Http ����
  /// </summary>
  TIocpHttpMvcServer = class(TComponent)
  private
    FServer: TIocpHttpServer;
    FContext: TRttiContext;
    FPrefix, FSuffix: string;
    FUseWebSocket: Boolean;
    FNeedSaveConfig: Boolean;
    FUriCaseSensitive: Boolean;
    FUriMap: TDictionary<string, TUriMapData>;
    FWebSocketMap: TList<TWebSocketMapData>;

    FOnSerializeData: TOnSerializeRequest;
    FOnDeSerializeData: TOnDeSerializeRequest;
    
    procedure SetUseWebSocket(const Value: Boolean);
    function GetAccessControlAllow: TIocpHttpAccessControlAllow;
    function GetAutoDecodePostParams: Boolean;
    function GetCharset: StringA;
    function GetContentLanguage: StringA;
    function GetGzipFileTypes: string;
    function GetListenPort: Integer;
    function GetUploadMaxDataSize: NativeUInt;
    function GetWebBasePath: string;
    procedure SetAccessControlAllow(const Value: TIocpHttpAccessControlAllow);
    procedure SetActive(const Value: Boolean);
    procedure SetAutoDecodePostParams(const Value: Boolean);
    procedure SetCharset(const Value: StringA);
    procedure SetContentLanguage(const Value: StringA);
    procedure SetGzipFileTypes(const Value: string);
    procedure SetListenPort(const Value: Integer);
    procedure SetUploadMaxDataSize(const Value: NativeUInt);
    procedure SetWebBasePath(const Value: string);
    function GetActive: Boolean;
    function GetBindAddr: StringA;
    procedure SetBindAddr(const Value: StringA);
    function GetServer: TIocpWebSocketServer;
  protected
    procedure InitServer();
    function DefaultConfigName: string;
  protected
    procedure DoHttpRequest(Sender: TIocpHttpServer;
      Request: TIocpHttpRequest; Response: TIocpHttpResponse);
    procedure DoHttpWebSocketRequest(Sender: TIocpWebSocketServer;
      Request: TIocpWebSocketRequest; Response: TIocpWebSocketResponse);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    
    /// <summary>
    /// ���л�����
    /// </summary>
    function SerializeData(const Value: TValue): string;

    /// <summary>
    /// �����л�����
    /// </summary>
    function DeSerializeData(const SrcData: string; const DestValue: TValue; IsGet: Boolean): Boolean;
    
    /// <summary>
    /// ��������
    /// </summary>
    procedure LoadConfig(const AFileName: string = '');
    /// <summary>
    /// ��������
    /// </summary>
    procedure SaveConfig(const AFileName: string = '');
    /// <summary>
    /// �Ƿ����÷���
    /// </summary>
    property Active: Boolean read GetActive write SetActive;
    /// <summary>
    /// ���������
    /// </summary>
    property Server: TIocpHttpServer read FServer;
    /// <summary>
    /// WebSocket���������
    /// </summary>
    property WebSocketServer: TIocpWebSocketServer read GetServer;
  published

    /// <summary>
    /// ������ͼ��ǰ׺���ƣ�Ĭ��Ϊ��
    /// </summary>
    property Prefix: string read FPrefix write FPrefix;
    /// <summary>
    /// ������ͼ�ĺ�׺���ƣ�Ĭ��Ϊ��
    /// </summary>
    property Suffix: string read FSuffix write FSuffix;

    /// <summary>
    /// URI �Ƿ��Сд����
    /// </summary>
    property UriCaseSensitive: Boolean read FUriCaseSensitive write FUriCaseSensitive;

    /// <summary>
    /// �Ƿ����� WebSocket ����
    /// </summary>
    property UseWebSocket: Boolean read FUseWebSocket write SetUseWebSocket default False;
    
    
    property ListenPort: Integer read GetListenPort write SetListenPort default 8080;

    /// <summary>
    /// �������ѡ��, Ĭ�ϲ�����
    /// </summary>
    property AccessControlAllow: TIocpHttpAccessControlAllow read GetAccessControlAllow
      write SetAccessControlAllow;

    /// <summary>
    /// Ĭ���ַ���ѡ�������Ӧ�ͻ�������ʱ���� Content-Type �С�
    /// </summary>
    property Charset: StringA read GetCharset write SetCharset;

    /// <summary>
    /// �������˿ڰ󶨵�ַ
    /// </summary>
    property BindAddr: StringA read GetBindAddr write SetBindAddr;

    /// <summary>
    /// Ĭ����Ӧ�������ԡ�������Ӧ�ͻ�������ʱ���� Content-Language �С�
    /// </summary>
    property ContentLanguage: StringA read GetContentLanguage write SetContentLanguage;

    /// <summary>
    /// WEB�ļ��еĸ�Ŀ¼��Ĭ��Ϊ��������Ŀ¼��Web�ļ���
    /// </summary>
    property WebPath: string read GetWebBasePath write SetWebBasePath;

    /// <summary>
    /// �����ļ�ʱ���Զ�ʹ��GZip����ѹ�����ļ����� (��";"���зָ�)
    /// �磺'.htm;.html;.css;.js;'
    /// </summary>
    property GzipFileTypes: string read GetGzipFileTypes write SetGzipFileTypes;

    /// <summary>
    /// �Ƿ��Զ�����POST����
    /// </summary>
    property AutoDecodePostParams: Boolean read GetAutoDecodePostParams write SetAutoDecodePostParams;

    /// �ͻ����ϴ����ݴ�С�����ޣ�Ĭ��Ϊ2M��
    property UploadMaxDataSize: NativeUInt read GetUploadMaxDataSize write SetUploadMaxDataSize;

    /// <summary>
    /// ���л������¼�
    /// </summary>
    property OnSerializeData: TOnSerializeRequest read FOnSerializeData write FOnSerializeData;
    /// <summary>
    /// �����л������¼�
    /// </summary>
    property OnDeSerializeData: TOnDeSerializeRequest read FOnDeSerializeData write FOnDeSerializeData;
  end;

type
  /// <summary>
  /// ҵ����ע�����Ӵ˱�ע��ָ����ž߱�����ҵ�����������
  /// </summary>
  ServiceAttribute = class(TCustomAttribute);

  /// <summary>
  /// ���Ʋ��ע�����Ӵ˱�ע��ָ����ž߱�����ҵ�������������
  /// </summary>
  ControllerAttribute = class(TCustomAttribute);

  /// <summary>
  /// ���ݷ��������ע�����Ӵ˱�ע��ָ������Է������ݿ⡣
  /// </summary>
  RepositoryAttribute = class(TCustomAttribute); 

   
type
  /// <summary>
  /// ��Ҫ�Զ�װ��ı�ע
  /// </summary>
  AutowiredAttribute = class(TCustomAttribute);

type
  /// <summary>
  /// ��ʶ���󷵻�ҳ��������ط�ʽ�ı�ע
  /// </summary>
  DownloadAttribute = class(TCustomAttribute);

type
  /// <summary>
  /// WebSocket �������ע
  /// </summary>
  WebSocketAttribute = class(TCustomAttribute)
  private
    FData: string;
  public
    /// <summary>
    /// <param name="Data">ָ������DataΪָ�����ݵ��ı���Ϣʱ����Ӧ</param>
    /// </summary>
    constructor Create(const Data: string = '');
    
    property Data: string read FData;
  end;

type
  /// <summary>
  /// �����ַӳ���ע
  /// </summary>
  RequestMappingAttribute = class(TCustomAttribute)
  private
    FValue: string;
    FMethod: TIocpHttpMethod;
    FConsumes, FProduces, FParams, FHeaders: string;
  public
    /// <summary>
    /// <param name="Value">ָ�������ʵ�ʵ�ַ</param>
    /// </summary>
    constructor Create(const Value: string); overload;
    /// <summary>
    /// <param name="Method">ָ�������method���ͣ� GET��POST��PUT��DELETE��</param>
    /// </summary>
    constructor Create(Method: TIocpHttpMethod); overload;
    /// <summary>
    /// <param name="Value">ָ�������ʵ�ʵ�ַ</param>
    /// <param name="Method">ָ�������method���ͣ� GET��POST��PUT��DELETE��</param>
    /// <param name="Consumes">ָ������������ύ�������ͣ�Content-Type��������application/json, text/html</param>
    /// <param name="Produces">ָ�����ص��������ͣ�����request����ͷ�е�(Accept)�����а�����ָ�����Ͳŷ���</param>
    /// <param name="Params">ָ��request�б������ĳЩ����ֵ�ǣ����ø÷�������</param>
    /// <param name="Headers">ָ��request�б������ĳЩָ����headerֵ�������ø÷�����������</param>
    /// </summary>
    constructor Create(const Value: string; Method: TIocpHttpMethod; const Consumes, Produces, Params: string; const Headers: string = ''); overload;
    /// <summary>
    /// <param name="Value">ָ�������ʵ�ʵ�ַ</param>
    /// <param name="Method">ָ�������method���ͣ� GET��POST��PUT��DELETE��</param>
    /// <param name="Params">ָ��request�б������ĳЩ����ֵ�ǣ����ø÷�������</param>
    /// </summary>
    constructor Create(const Value: string; Method: TIocpHttpMethod; const Params: string = ''); overload;
    /// <summary>
    /// <param name="Value">ָ�������ʵ�ʵ�ַ</param>
    /// <param name="Params">ָ��request�б������ĳЩ����ֵ�ǣ����ø÷�������</param>
    /// <param name="Headers">ָ��request�б������ĳЩָ����headerֵ�������ø÷�����������</param>
    /// </summary>
    constructor Create(const Value: string; const Params: string; const Headers: string = ''); overload;

    property Value: string read FValue;
    property Method: TIocpHttpMethod read FMethod;
    property Consumes: string read FConsumes;
    property Produces: string read FProduces;
    property Params: string read FParams;
    property Headers: string read FHeaders;
  end;

type
  /// <summary>
  /// �����������url�еĶ�̬������
  /// </summary>
  PathVariableAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    /// <summary>
    /// <param name="Value">�������������ƺ���Ҫ�󶨵�uri template�б������Ʋ�һ��ʱ��
    /// ����ָ��uri template������</param>
    /// </summary>
    constructor Create(const Name: string); overload;

    property Name: string read FName;
  end;

type
  /// <summary>
  /// ���ڽ��������������ӳ�䵽���ܴ������Ĳ�����
  /// </summary>
  RequestParamAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const Name: string); overload;
    // ��������
    property Name: string read FName;
  end;

type
  /// <summary>
  /// 1. ��ȡRequest�����body�������ݣ�ʹ��ϵͳĬ�����õ�Converter���н�����
  ///    Ȼ�����Ӧ�����ݰ󶨵�Ҫ���صĶ����ϣ�
  /// 2. �ٰ�Converter���صĶ������ݰ󶨵�controller�з����Ĳ����ϡ�
  /// </summary>
  RequestBodyAttribute = class(TCustomAttribute);

type
  /// <summary>
  /// ��Controller�ķ������صĶ���ͨ���ʵ���Converter��Adapterת������,
  /// ������ת��Ϊָ����ʽ��д�뵽Response�����body��������
  /// </summary>
  ResponseBodyAttribute = class(TCustomAttribute);

var
  HttpMvc: TIocpHttpMvcServer = nil;

/// <summary>
/// ��ʼ�� MVC ������ - ����Ѿ��ڴ����Ϸ����� Mvc ���������Ҫ���ñ�����
/// ʹ�ñ��������Զ����������ļ���http_mvc_setting.xml
/// �������ļ�Ӧ���� AppPath Ŀ¼�С�
/// </summary>
procedure InitHttpMvcServer;

/// <summary>
/// ע��
/// </summary>
procedure RegMvcClass(AClass: TClass); overload;
procedure RegMvcClass(AClass: TRttiType); overload;


implementation

resourcestring
  S_BadRequestBody = 'Request Body Parse Failed.';

var
  MvcScanner: TIocpMvcScanner = nil;
  HttpMvcAllowFree: Boolean = False;

procedure InitHttpMvcServer;
begin
  if not Assigned(HttpMvc) then
    MvcScanner.StartScan;
end;

procedure RegMvcClass(AClass: TClass);
begin
  if Assigned(MvcScanner) then
    MvcScanner.RegClass(AClass);
end;

procedure RegMvcClass(AClass: TRttiType);
begin
  if Assigned(MvcScanner) then
    MvcScanner.RegClass(AClass);
end;

// ��ȡ Name=Value �ַ����е� Name �� Value
function GetNameOrValue(const Value: string; GetName: Boolean = True): string;
var
  I: Integer;
begin
  if Value = '' then
    Result := ''
  else begin
    I := Pos('=', Value);
    if I > 0 then begin
      if GetName then
        Result := Value.Substring(0, I - 1)
      else
        Result := Value.Substring(I);
    end else
      Result := '';
  end;
end;

{ TObjectHelper }

function TObjectHelper.ExistAttribute(
  const AttrType: TCustomAttributeClass): Boolean;
begin
  Result := CheckAttribute(
    function(const Item: TCustomAttribute; const Data: Pointer): Boolean 
    begin
      Result := Item.ClassType = AttrType;
    end, nil);
end;

function TObjectHelper.ExistAttribute(
  const Attributes: TArray<TCustomAttribute>;
  const AttrType: TCustomAttributeClass): Boolean;
begin
  Result := CheckAttribute(Attributes,
    function(const Item: TCustomAttribute; const Data: Pointer): Boolean
    begin
      Result := Item.ClassType = AttrType;
    end, nil);
end;

function TObjectHelper.ExistAttribute(
  const Attributes: TArray<TCustomAttribute>; const AttrName: string): Boolean;
var
  ARealAttrName: string;
begin
  ARealAttrName := GetRealAttrName(AttrName);
  Result := CheckAttribute(Attributes,
    function(const Item: TCustomAttribute; const Data: Pointer): Boolean
    begin
      Result := Item.ClassNameIs(ARealAttrName);
    end, nil);
end;

function TObjectHelper.CheckAttribute(ACompare: TCompareAttributeItem; 
  const Data: Pointer): Boolean;
var
  AContext: TRttiContext;
  ARttiType: TRttiType;
  AFieldAttrItem: TCustomAttribute;
begin
  Result := False;
  AContext := TRttiContext.Create;
  ARttiType := AContext.GetType(Self.ClassType);
  if ARttiType.GetAttributes <> nil then begin
    for AFieldAttrItem in ARttiType.GetAttributes do
      if ACompare(AFieldAttrItem, Data) then begin
        Result := True;
        Break;
      end;
  end;
end;

function TObjectHelper.CheckAttribute(
  const Attributes: TArray<TCustomAttribute>; ACompare: TCompareAttributeItem;
  const Data: Pointer): Boolean;
var
  AFieldAttrItem: TCustomAttribute;
begin
  Result := False;
  for AFieldAttrItem in Attributes do
    if ACompare(AFieldAttrItem, Data) then begin
      Result := True;
      Break;
    end;
end;

function TObjectHelper.CreateObject(const AClassName: string;
  const Args: array of TValue): TObject;
var
  Context: TRttiContext;
  RttiType: TRttiType;
begin
  RttiType := Context.FindType(AClassName);
  if Assigned(RttiType) then   
    Result := CreateObject(RttiType, Args)
  else
    Exit(nil);
end;

function TObjectHelper.CreateObject(const ARttiType: TRttiType;
  const Args: array of TValue): TObject;
var
  RttiMethod: TRttiMethod;
  AClass: TClass;
begin
  for RttiMethod in ARttiType.GetMethods do begin
    if RttiMethod.IsConstructor and (Length(RttiMethod.GetParameters) = Length(Args)) then begin
      AClass := ARttiType.AsInstance.MetaclassType;
      Exit(RttiMethod.Invoke(AClass, Args).AsObject);
    end;
  end;
  Exit(nil);
end;

function TObjectHelper.CheckAttribute(ARttiType: TRttiType;
  ACompare: TCompareAttributeItem; const Data: Pointer): Boolean;
var
  AFieldAttrItem: TCustomAttribute;
begin
  Result := False;
  if Assigned(ARttiType) and (ARttiType.GetAttributes <> nil) then begin
    for AFieldAttrItem in ARttiType.GetAttributes do
      if ACompare(AFieldAttrItem, Data) then begin
        Result := True;
        Break;
      end;
  end;    
end;

function TObjectHelper.ExistAttribute(const AttrName: string): Boolean;
var
  ARealAttrName: string;
begin
  ARealAttrName := GetRealAttrName(AttrName);
  Result := CheckAttribute(
    function(const Item: TCustomAttribute; const Data: Pointer): Boolean 
    begin
      Result := Item.ClassNameIs(ARealAttrName);
    end, nil);
end;

function TObjectHelper.GetAttribute<T>(const AttrName, FiledName: string): T;
begin
  Result := GetAttribute<T>(AttrName, FiledName, T(nil));  
end;

function TObjectHelper.GetAttribute<T>(const AttrName, FiledName: string;
  const DefaultValue: T): T;
var
  AContext: TRttiContext;
  ARttiType: TRttiType;
  AFieldAttrItem: TCustomAttribute;
  AFiled: TRttiField;
  ARealAttrName: string;
begin
  AContext := TRttiContext.Create;
  ARttiType := AContext.GetType(Self.ClassType);
  if (ARttiType.GetAttributes <> nil) and (FiledName <> '') then begin
    ARealAttrName := GetRealAttrName(AttrName);
    for AFieldAttrItem in ARttiType.GetAttributes do
      if AFieldAttrItem.ClassNameIs(ARealAttrName) then begin
        if FiledName <> '' then begin        
          ARttiType := AContext.GetType(AFieldAttrItem.ClassType);
          if (LowerCase(FiledName[1]) <> 'f') then
            AFiled := ARttiType.GetField('f' + FiledName)
          else
            AFiled := nil;
          if not Assigned(AFiled) then
            AFiled := ARttiType.GetField(FiledName);
          if Assigned(AFiled) then begin   
            Result := AFiled.GetValue(AFieldAttrItem).AsType<T>();
            Exit;
          end else 
            Break;
        end else
          Break;
      end;
  end;    
  Result := DefaultValue;
end;  

function TObjectHelper.GetRealAttrName(const AttrName: string): string;
const
  S_Attribute = 'attribute';
  S_AttributeLen = Length(S_Attribute) - 1;
  SP_Attribute: PChar = S_Attribute;
  SP_AttributeLen = Length(S_Attribute);
var
  Len: Integer;
  P: PChar;
begin
  Len := Length(AttrName);
  if (Len > S_AttributeLen) then begin
    P := PChar(AttrName) + Len - SP_AttributeLen;
    if (StrLIComp(P, SP_Attribute, SP_AttributeLen) = 0) then begin
      Result := AttrName;
      Exit;
    end;
  end;
  Result := AttrName + S_Attribute;
end;

function TObjectHelper.GetRttiValue<T>(const Name: string): T;
var
  FType: TRttiType;
  FFiled: TRttiField;
  FContext: TRttiContext;
begin
  FContext := TRttiContext.Create;
  try
    FType := FContext.GetType(Self.ClassType);
    FFiled := FType.GetField(Name);
    if not Assigned(FFiled) then
      Result := T(nil)
    else
      Result := FFiled.GetValue(Self).AsType<T>();
  finally
    FContext.Free;
  end; 
end;

procedure TObjectHelper.Log(const Msg: string);
begin
  {$IFDEF MSWINDOWS}
  OutputDebugString(PChar(Msg));
  {$ENDIF}
end;

class procedure TObjectHelper.RegToMVC;
begin
end;

procedure TObjectHelper.SetRttiValue<T>(const Name: string; const Value: T);
var
  FType: TRttiType;
  FFiled: TRttiField;
  FContext: TRttiContext;
begin
  FContext := TRttiContext.Create;
  try
    FType := FContext.GetType(Self.ClassType);
    FFiled := FType.GetField(Name);
    if not Assigned(FFiled) then Exit;
    if FFiled.FieldType.TypeKind <> PTypeInfo(TypeInfo(T)).Kind then
      Exit;
    FFiled.SetValue(Self, TValue.From(Value));
  finally
    FContext.Free;
  end;
end;

{ TIocpMvcScanner }

procedure TIocpMvcScanner.Clear;
begin
  FClassMap.Clear;
end;

constructor TIocpMvcScanner.Create;
begin
  FScannerOK := False;
  FClassMap := TDictionary<string, TObject>.Create(63);
  FClassMap.OnValueNotify := DoValueNotify;
  FRttiContext := TRttiContext.Create;
end;

destructor TIocpMvcScanner.Destroy;
begin
  Clear;
  FreeAndNil(FClassMap);
  inherited;
end;

procedure TIocpMvcScanner.DoValueNotify(Sender: TObject; const Item: TObject; 
  Action: System.Generics.Collections.TCollectionNotification);
begin
  if Action = cnRemoved then
    Item.Free;
end;

function TIocpMvcScanner.GetAllTypes: TArray<TRttiType>;
begin
  Result := FRttiContext.GetTypes;
end;

procedure TIocpMvcScanner.RegClass(AClass: TRttiType);
var
  Obj: TObject;
begin
  if not FClassMap.ContainsKey(AClass.Name) then begin
    Obj := CreateObject(AClass, []);
    FClassMap.Add(AClass.Name, Obj);
    Log('Initial success: ' + AClass.QualifiedName);
  end;
end;

procedure TIocpMvcScanner.RegClass(AClass: TClass);
var
  AType: TRttiType;
begin
  AType := FRttiContext.GetType(AClass);
  RegClass(AType);
end;

procedure TIocpMvcScanner.StartScan;
var
  tl: TArray<TRttiType>;
  Item: TRttiType;
  J: Integer;
begin
  if FScannerOK then
    Exit;
  FClassMap.Clear;
  tl := GetAllTypes;
  for J := 0 to High(tl) do begin  
    Item := tl[J];    
    if CheckAttribute(Item,
      function(const Item: TCustomAttribute; const Data: Pointer): Boolean
      begin
        Result := (Item.ClassType = ServiceAttribute) or
           (Item.ClassType = ControllerAttribute);
      end, nil)
    then begin 
      Log('Scanner: ' + Item.QualifiedName);
      // ��ʼ��
      RegClass(Item);
    end;      
  end;
  
  // ��ʼ������
  if (HttpMvc = nil) then begin
    HttpMvcAllowFree := True;
    HttpMvc := TIocpHttpMvcServer.Create(nil);
    HttpMvc.LoadConfig;
  end;

  FScannerOK := True;
end;

{ WebSocketAttribute }

constructor WebSocketAttribute.Create(const Data: string);
begin
  FData := Data;
end;

{ RequestMappingAttribute }

constructor RequestMappingAttribute.Create(const Value: string);
begin
  FValue := Value;
end;

constructor RequestMappingAttribute.Create(Method: TIocpHttpMethod);
begin
  FMethod := Method;
end;

constructor RequestMappingAttribute.Create(const Value: string;
  Method: TIocpHttpMethod; const Consumes, Produces, Params, Headers: string);
begin
  FValue := Value;
  FMethod := Method;
  FConsumes := Consumes;
  FProduces := Produces;
  FParams := Params;
  FHeaders := Headers;
end;

constructor RequestMappingAttribute.Create(const Value: string;
  Method: TIocpHttpMethod; const Params: string);
begin
  FValue := Value;
  FMethod := Method;
  FParams := Params;
end;

constructor RequestMappingAttribute.Create(const Value, Params,
  Headers: string);
begin
  FValue := Value;
  FParams := Params;
  FHeaders := Headers;
end;

{ PathVariableAttribute }

constructor PathVariableAttribute.Create(const Name: string);
begin
  FName := Name;
end;

{ RequestParamAttribute }

constructor RequestParamAttribute.Create(const Name: string);
begin
  FName := Name;
end;

{ TIocpHttpMvcServer }

constructor TIocpHttpMvcServer.Create(AOwner: TComponent);
begin
  if Assigned(HttpMvc) then begin
    FreeAndNil(HttpMvc);
    HttpMvcAllowFree := False;
  end;
  HttpMvc := Self;
  FUseWebSocket := False;
  FNeedSaveConfig := False;
  FContext := TRttiContext.Create;
  FUriMap := TDictionary<string, TUriMapData>.Create(9973);
  FWebSocketMap := TList<TWebSocketMapData>.Create;

  if Assigned(MvcScanner) then
    MvcScanner.StartScan;

  InitServer();
  inherited;   
end;

function TIocpHttpMvcServer.DefaultConfigName: string;
begin
  Result := AppPath + 'http_mvc_setting.xml';
end;

function TIocpHttpMvcServer.DeSerializeData(const SrcData: string;
  const DestValue: TValue; IsGet: Boolean): Boolean;
begin
  if Assigned(FOnDeSerializeData) then begin
    Result := FOnDeSerializeData(Self, SrcData, DestValue, IsGet);
  end else
    Result := False;
end;

destructor TIocpHttpMvcServer.Destroy;
begin
  FreeAndNil(FServer);
  FreeAndNil(FUriMap);
  FreeAndNil(FWebSocketMap);
  FContext.Free;
  if HttpMvc = Self then
    HttpMvc := nil;
  inherited;
end;

function GetArgsValue(AParam: TRttiParameter; const Value: string): TValue;
begin
  Result := TValue.Empty;
  if Value = '' then Exit;  
  case AParam.ParamType.TypeKind of
    tkInteger, tkInt64:
      Result := StrToInt(Value);
    tkFloat:
      Result := StrToFloat(Value);
    tkChar, tkWChar:
      begin
        if Value <> '' then
          Result := Value[1];
      end;
    tkString, tkLString, tkWString, tkUString:
      Result := Value;
    tkEnumeration:
      begin
        if StrToIntDef(Value, 0) <> 0 then
          Result := StrToInt(Value)
        else
          Result := GetEnumValue(AParam.ParamType.Handle, Value);
      end;
  end;
end;

procedure TIocpHttpMvcServer.DoHttpRequest(Sender: TIocpHttpServer;
  Request: TIocpHttpRequest; Response: TIocpHttpResponse);

  // ��� Path ����
  procedure CheckPathVariable(const URI: string; var Item: TUriMapData;
    var APathVariable: TDictionary<string, string>);
  var
    P, P1: PChar;
    Key: string;
  begin
    P := PChar(URI);
    P1 := P + Length(URI);
    while P1 > P do begin
      if P1^ = '/' then begin
        Key := PCharToString(P, P1 - P + 1);
        if FUriMap.ContainsKey(Key) then begin
          Item := FUriMap[Key];
          APathVariable := TDictionary<string, string>.Create(7);
          Break;
        end;
      end;
      Dec(P1);
    end;
  end;

  // ��ʼ�� Path ����
  procedure InitPathVariable(const URI: string; const Item: TUriMapData;
    APathVariable: TDictionary<string, string>);
  var
    P1, P2, P3, P4, P5: PChar;
    Key: string;
  begin
    P1 := PChar(URI);
    P3 := PChar(Item.Uri);
    P4 := P3 + Length(Item.URI);
    P2 := P1 + Length(URI);
    while P3 < P4 do begin
      if P3^ = '{' then begin
        Inc(P3);
        P5 := P3;
        while (P3 < P4) and (P3^ <> '}') do
          Inc(P3);
        Key := PCharToString(P5, P3 - P5);
        P5 := P1;
        while (P1 < P2) and (P1^ <> '/') do
          Inc(P1);
        APathVariable.Add(Key, PCharToString(P5, P1 - P5));
      end;
      Inc(P1);
      Inc(P3);
    end;
  end;

const
  CS_Mltipart_FormData: StringA = 'multipart/form-data';
var
  Key, URI: string;
  Item: TUriMapData;
  AClass: TClass;
  AMethod: TRttiMethod;
  ARttiType: TRttiType;
  AParams: TArray<TRttiParameter>;
  APathVariable: TDictionary<string, string>;
  AParamObjs: TObject;
  Args: array of TValue;
  ResultValue: TValue;
  IsOK: Boolean;
  I: Integer;
begin
  try
    if FUriCaseSensitive then
      URI := string(Request.URI)
    else
      URI := LowerCase(string(Request.URI));
    FillChar(Item, SizeOf(Item), 0);
    APathVariable := nil;
    AParamObjs := nil;
    try
      // ��� URI ӳ��
      if not FUriMap.ContainsKey(URI) then begin
        // ������ʱ�������һ�ڿ�ʼ�����Ͻضϣ��ж��Ƿ���� Path ������ URI
        CheckPathVariable(URI, Item, APathVariable);
      end else
        Item := FUriMap[URI];

      // û���ҵ�ҳ��
      if (not Assigned(Item.Controller)) then begin
        Response.SendFileByURI(URI, '', False, True);
        //Response.ErrorRequest(404);
        Exit;
      end;

      // ���������
      if // ������ƥ��
        ((Item.Method <> http_Unknown) and (Item.Method <> Request.Method)) or
        // ������ָ���Ĳ���
        ((Item.Params <> '') and (Request.GetParam(StringA(Item.ParamName)) <> Item.ParamValue)) or
        // ������ָ������������ύ��������
        ((Item.Consumes <> '') and (not Request.ExistContentType(StringA(Item.Consumes)))) or
        // ������ָ�����ص���������
        ((Item.Produces <> '') and (not Request.AllowAccept(StringA(Item.Produces)))) or
        // δ������ָ����headerֵ
        ((Item.Headers <> '') and (Request.GetHeader(StringA(Item.HeaderName)) <> StringA(Item.HeaderValue)))
      then begin
        Response.ErrorRequest(405);
        Exit;
      end;

      // ��ʼ�� PathVariable �б�
      if Assigned(APathVariable) then
        InitPathVariable(URI, Item, APathVariable);

      // ����ע��
      ARttiType := FContext.GetType(Item.Controller.ClassType);
      AMethod := ARttiType.GetMethods[Item.MethodIndex];
      AParams := AMethod.GetParameters;
      SetLength(Args, Length(AParams));
      for I := 0 to High(AParams) do begin
        // ������԰�
        if CheckAttribute(AParams[I].GetAttributes,
          function(const Item: TCustomAttribute; const Data: Pointer): Boolean
          begin
            if Assigned(APathVariable) and (Item.ClassType = PathVariableAttribute) then begin
              // PathVariable ��ע���ֶ�
              Result := True;
              Key := PathVariableAttribute(Item).Name;
              if not APathVariable.ContainsKey(Key) then
                Exit;
              Args[I] := GetArgsValue(AParams[I], APathVariable[Key]);
            end else if Item.ClassType = RequestParamAttribute then begin
              // RequestParam ��ע���ֶ�
              Result := True;
              Args[I] := GetArgsValue(AParams[I], Request.GetParam(StringA(PathVariableAttribute(Item).FName)));
            end else if (Item.ClassType = RequestBodyAttribute) and (AParamObjs = nil) then begin
              // RequestBody �����������������
              Result := True;
              case AParams[I].ParamType.TypeKind of
                tkString, tkLString, tkWString, tkUString:
                  begin
                    // �ַ�����ֱ�Ӹ�ֵ
                    if Request.Method <> http_GET then
                      Args[I] := Request.GetDataString()
                    else
                      Args[I] := string(Request.ParamData);
                  end;
                tkClass:
                  begin
                    // �࣬ʵ������ͨ�����л��¼���ֵ
                    Args[I] := nil;
                    AClass := AParams[I].ParamType.AsInstance.MetaclassType;
                    try
                      if AClass.InheritsFrom(TComponent) then
                        Args[I] := CreateObject(AClass.ClassName, [Owner])
                      else
                        Args[I] := CreateObject(AClass.ClassName, []);
                      // ������Ƕ���������
                      if not Request.ExistContentType(CS_Mltipart_FormData) then begin
                        if Request.Method <> http_GET then
                          IsOK := DeSerializeData(Request.GetDataString(), Args[I], False)
                        else
                          IsOK := DeSerializeData(string(Request.ParamData), Args[I], True);
                        if not IsOK then
                          raise Exception.Create(S_BadRequestBody);
                      end;
                    finally
                      if (not Args[I].IsEmpty) and (Args[I].IsObject) then
                        AParamObjs := Args[I].AsObject; // ����������뵽�б���ʹ������ͷ�
                    end;
                  end;
                tkRecord:
                  begin
                    // ��¼��ʵ������ͨ�����л��¼���ֵ
                    TValue.Make(nil, AParams[I].ParamType.Handle, Args[I]);
                    // ������Ƕ���������
                    if not Request.ExistContentType(CS_Mltipart_FormData) then begin
                      if Request.Method <> http_GET then
                        IsOK := DeSerializeData(Request.GetDataString(), Args[I], False)
                      else
                        IsOK := DeSerializeData(string(Request.ParamData), Args[I], True);
                      if not IsOK then
                        raise Exception.Create(S_BadRequestBody);
                    end;
                  end;
              end;
            end else
              Result := False;
          end
        ) then
          Continue;

        // ����ֶΰ󶨣��Զ�ע�����
        case AParams[I].ParamType.TypeKind of
          tkClass:
            begin
              AClass := AParams[I].ParamType.AsInstance.MetaclassType;
              if AClass = TIocpHttpRequest then
                Args[I] := Request
              else if AClass = TIocpHttpResponse then
                Args[I] := Response
              else if (AClass = TIocpHttpServer) or (AClass = FServer.ClassType) then
                Args[I] := FServer
              else if AClass = TIocpHttpWriter then
                Args[I] := Response.GetOutWriter()
              else if (AClass = TIocpHttpConnection) or (AClass = TIocpClientContext) or (AClass = TIocpCustomContext) then
                Args[I] := Request.Connection
              else if AClass.InheritsFrom(TStream) then
                Args[I] := Request.Data
              else
                Args[I] := nil;
            end;
          tkString, tkLString, tkWString, tkUString:
            begin
              // ���������һ���ַ�����������Ϊ RequestData ����ֱ��ע��Ϊ�ַ����� Data
              if LowerCase(AParams[I].Name) = 'requestdata' then
                Args[I] := string(Request.DataString);
            end;
        end;
      end;

      // ִ��
      if Assigned(AMethod.ReturnType) then begin
        ResultValue := AMethod.Invoke(Item.Controller, Args);
        if not ResultValue.IsEmpty then begin 
          case ResultValue.TypeInfo.Kind of
            // ��������Ϊ�ַ���ʱ����Ϊ����ͼ�ļ���
            tkString, tkLString, tkWString, tkUString:
              begin
                Key := Prefix + ResultValue.AsString + Suffix;
                Response.SendFile(GetAbsolutePathEx(WebPath, Key), Item.Produces, Item.DownMode, True);
              end;
            // ��������Ϊ����ʱ����Ϊ�Ǵ������
            tkInteger, tkInt64:
              begin
                Response.ErrorRequest(ResultValue.AsInt64);
              end;
            tkClass:
              begin
                try
                  if Item.ResponseBody then
                    Response.Send(SerializeData(ResultValue))
                  else
                    Response.ResponeCode(200);
                finally
                  ResultValue.AsObject.Free;
                end;
              end;
            tkRecord:
              begin
                if Item.ResponseBody then
                  Response.Send(SerializeData(ResultValue))
                else
                  Response.ResponeCode(200);
              end;
          else
            Response.ResponeCode(200);
          end;
        end else
          // ��������Ϊ��ʱ��ֱ�ӷ���һ��Http 200״̬
          Response.ResponeCode(200);
      end else begin
        // �޷���ֵ����
        AMethod.Invoke(Item.Controller, Args);
        Response.ResponeCode(200);
      end;
    finally
      FreeAndNil(APathVariable);
      FreeAndNil(AParamObjs);
    end;
  except
    Log(Exception(ExceptObject).Message);
    if Assigned(Response) and (Response.Active) then
      Response.ServerError(StringA(Exception(ExceptObject).Message));
  end;
end;

procedure TIocpHttpMvcServer.DoHttpWebSocketRequest(
  Sender: TIocpWebSocketServer; Request: TIocpWebSocketRequest;
  Response: TIocpWebSocketResponse);
var
  I, J: Integer;
  AClass: TClass;
  AMethod: TRttiMethod;
  ARttiType: TRttiType;
  AParams: TArray<TRttiParameter>;
  Args: array of TValue;
  ResultValue: TValue;
  Data: string;
begin
  try
    if Request.DataOpcode = wso_Text then begin
      if FUriCaseSensitive then
        Data := LowerCase(Request.DataString())
      else
        Data := Request.DataString();
    end else
      Data := '';

    // һ�� WebSocket �������������������д���
    for J := 0 to FWebSocketMap.Count - 1 do begin
      // ����Ƿ���Ҫ����
      if (FWebSocketMap[J].Data <> '') then begin
        if (FUriCaseSensitive and (LowerCase(FWebSocketMap[J].Data) <> Data)) or 
          (FWebSocketMap[J].Data <> Data) 
        then begin
          Continue;
        end;
      end;
      // ����ע��
      ARttiType := FContext.GetType(FWebSocketMap[J].Controller.ClassType);
      AMethod := ARttiType.GetMethods[FWebSocketMap[J].MethodIndex];
      AParams := AMethod.GetParameters;
      SetLength(Args, Length(AParams));
      for I := 0 to High(AParams) do begin
        // ����ֶΰ󶨣��Զ�ע�����
        case AParams[I].ParamType.TypeKind of
          tkClass:
            begin
              AClass := AParams[I].ParamType.AsInstance.MetaclassType;
              if AClass = TIocpWebSocketRequest then
                Args[I] := Request
              else if AClass = TIocpWebSocketResponse then
                Args[I] := Response
              else if (AClass = TIocpWebSocketServer) or (AClass = Sender.ClassType) then
                Args[I] := Sender
              else if (AClass = TIocpWebSocketConnection) or
                (AClass = TIocpHttpConnection) or
                (AClass = TIocpClientContext) or 
                (AClass = TIocpCustomContext) then
                Args[I] := Response.Connection
              else if (AClass = TBytesCatHelper) then
                Args[I] := Request.Data 
              else
                Args[I] := nil;
            end;
          tkString, tkLString, tkWString, tkUString:
            begin
              // ���������һ���ַ�����������Ϊ RequestData ����ֱ��ע��Ϊ�ַ����� Data
              if LowerCase(AParams[I].Name) = 'requestdata' then
                Args[I] := Data;
            end;
        end;
      end;   

      // ִ��
      if Assigned(AMethod.ReturnType) then begin
        ResultValue := AMethod.Invoke(FWebSocketMap[J].Controller, Args);
        if not ResultValue.IsEmpty then begin        
          case ResultValue.TypeInfo.Kind of
            // ��������Ϊ�ַ���ʱ����Ϊ����ͼ�ļ���
            tkString, tkLString, tkWString, tkUString:
              begin
                Response.Send(ResultValue.AsString);
              end;
            // ��������Ϊ����ʱ��תΪ�ַ���
            tkInteger, tkInt64:
              begin
                Response.Send(IntToStr(ResultValue.AsInt64));
              end;
            tkClass:
              begin
                try
                  if FWebSocketMap[J].ResponseBody then
                    Response.Send(SerializeData(ResultValue))
                finally
                  ResultValue.AsObject.Free;
                end;
              end;
            tkRecord:
              begin
                if FWebSocketMap[J].ResponseBody then
                  Response.Send(SerializeData(ResultValue))
              end;
          end;
        end;
      end else
        // �޷���ֵ����
        AMethod.Invoke(FWebSocketMap[J].Controller, Args);     
    end;
  except
    Log(Exception(ExceptObject).Message);
  end;
end;

function TIocpHttpMvcServer.GetAccessControlAllow: TIocpHttpAccessControlAllow;
begin
  Result := FServer.AccessControlAllow;
end;

function TIocpHttpMvcServer.GetActive: Boolean;
begin
  Result := FServer.Active;
end;

function TIocpHttpMvcServer.GetAutoDecodePostParams: Boolean;
begin
  Result := FServer.AutoDecodePostParams;
end;

function TIocpHttpMvcServer.GetBindAddr: StringA;
begin
  Result := FServer.BindAddr;
end;

function TIocpHttpMvcServer.GetCharset: StringA;
begin
  Result := FServer.Charset;
end;

function TIocpHttpMvcServer.GetContentLanguage: StringA;
begin
  Result := FServer.ContentLanguage;
end;

function TIocpHttpMvcServer.GetGzipFileTypes: string;
begin
  Result := FServer.GzipFileTypes;
end;

function TIocpHttpMvcServer.GetListenPort: Integer;
begin
  Result := FServer.ListenPort;
end;

function TIocpHttpMvcServer.GetServer: TIocpWebSocketServer;
begin
  if FServer is TIocpWebSocketServer then
    Result := FServer as TIocpWebSocketServer
  else
    Result := nil;
end;

function TIocpHttpMvcServer.GetUploadMaxDataSize: NativeUInt;
begin
  Result := FServer.UploadMaxDataSize;
end;

function TIocpHttpMvcServer.GetWebBasePath: string;
begin
  Result := FServer.WebPath;
end;

procedure TIocpHttpMvcServer.InitServer;
var
  Svr: TIocpHttpServer;
  WebSocketDataItem: TWebSocketMapData;
  DataItem: TUriMapData;
  BaseDataItem: TUriMapData;
  BaseUri, ChildUri: string;
  ClassItem: TPair<string, TObject>;
  AMethods: TArray<TRttiMethod>;
  AFileds: TArray<TRttiField>;
  AParams: TArray<TRttiParameter>;
  AContext: TRttiContext;
  ARttiType: TRttiType;
  AClass: TClass;
  I, J, L: Integer;
begin
  // ��ʼ������
  if FUseWebSocket then        
    Svr := TIocpWebSocketServer.Create(Owner)
  else
    Svr := TIocpHttpServer.Create(Owner);

  if Assigned(FServer) then begin      
    Svr.ListenPort := ListenPort;
    Svr.AccessControlAllow := AccessControlAllow;
    Svr.Charset := Charset;
    Svr.ContentLanguage := ContentLanguage;
    Svr.WebPath := WebPath;
    Svr.GzipFileTypes := GzipFileTypes;
    Svr.AutoDecodePostParams := AutoDecodePostParams;
    Svr.UploadMaxDataSize := UploadMaxDataSize;
    FreeAndNil(FServer);
    
  end;

  FServer := Svr;
  FServer.OnHttpRequest := DoHttpRequest;
  if Svr is TIocpWebSocketServer then
    (TIocpWebSocketServer(Svr)).OnWebSocketRequest := DoHttpWebSocketRequest;

  // ���״̬������
  if (csDesigning in ComponentState) then
    Exit;

  // ��ʼ��ӳ���
  if not Assigned(MvcScanner) then
    Exit;
  FUriMap.Clear;
  FWebSocketMap.Clear;
  AContext := TRttiContext.Create;
  for ClassItem in MvcScanner.FClassMap do begin
    if not Assigned(ClassItem.Value) then
      Continue;

    // ע�����б�עΪ Autowired ���ֶ�
    ARttiType := AContext.GetType(ClassItem.Value.ClassType);
    AFileds := ARttiType.GetFields;
    for I := 0 to High(AFileds) do begin
      if ExistAttribute(AFileds[i].GetAttributes, AutowiredAttribute) then begin
        case AFileds[i].FieldType.TypeKind of
          tkClass:
            begin
              AClass := AFileds[i].FieldType.AsInstance.MetaclassType;
              if AClass = Self.ClassType then // �Լ�
                AFileds[i].SetValue(ClassItem.Value, TValue.From(Self))
              else if (AClass = FServer.ClassType) then  // FServer
                AFileds[i].SetValue(ClassItem.Value, TValue.From(FServer))
              else if AClass = TIocpHttpServer then  // FServer
                AFileds[i].SetValue(ClassItem.Value, TValue.From(FServer))
            end;
        end;        
      end;
    end;

    // �����л�ȡ Value ����Ϊ����Ļ��� URI
    // �������õ� RequestMapping ��ע���� Value ��Ч
    BaseDataItem.Clear;
    if not ClassItem.Value.CheckAttribute(
      function(const Item: TCustomAttribute; const Data: Pointer): Boolean
      begin
        Result := Item.ClassType = RequestMappingAttribute;
        if Result then begin
          BaseUri := RequestMappingAttribute(Item).FValue;
          BaseDataItem.Method := RequestMappingAttribute(Item).FMethod;
          BaseDataItem.Consumes := RequestMappingAttribute(Item).FConsumes;
          BaseDataItem.Produces := RequestMappingAttribute(Item).FProduces;
          BaseDataItem.Headers := RequestMappingAttribute(Item).FHeaders;
        end;
      end)
    then 
      BaseUri := '';
    BaseDataItem.DownMode := ClassItem.Value.ExistAttribute(DownloadAttribute);

    // �������з������ҳ���Ҫӳ���Uri
    ARttiType := AContext.GetType(ClassItem.Value.ClassType);
    AMethods := ARttiType.GetMethods;
    for I := 0 to High(AMethods) do begin
      if AMethods[I].IsConstructor or AMethods[I].IsDestructor or
        AMethods[I].IsClassMethod
      then
        Continue;

      // RequestMapping
      if CheckAttribute(AMethods[I].GetAttributes,
        function(const Item: TCustomAttribute; const Data: Pointer): Boolean
        begin
          Result := Item.ClassType = RequestMappingAttribute;
          if Result then begin
            ChildUri := RequestMappingAttribute(Item).FValue;
            DataItem.Method := RequestMappingAttribute(Item).FMethod;
            DataItem.Consumes := RequestMappingAttribute(Item).FConsumes;
            DataItem.Produces := RequestMappingAttribute(Item).FProduces;
            DataItem.Params := RequestMappingAttribute(Item).FParams;
            DataItem.Headers := RequestMappingAttribute(Item).FHeaders;
          end;
        end)
      then begin
        // �̳����е�����
        if DataItem.Method = http_Unknown then
          DataItem.Method := BaseDataItem.Method;
        if DataItem.Consumes = '' then
          DataItem.Consumes := BaseDataItem.Consumes;
        if DataItem.Produces = '' then
          DataItem.Produces := BaseDataItem.Produces;
        if DataItem.Headers = '' then
          DataItem.Headers := BaseDataItem.Headers;

        Log(Format('ӳ��URI: %s, ������: %s', [BaseUri + ChildUri, AMethods[I].Name]));
        DataItem.Controller := ClassItem.Value;
        DataItem.MethodIndex := I;
        DataItem.URI := BaseUri + ChildUri;
        DataItem.DownMode := BaseDataItem.DownMode or
          ExistAttribute(AMethods[I].GetAttributes, DownloadAttribute);
        DataItem.ResponseBody := ExistAttribute(AMethods[I].GetAttributes, ResponseBodyAttribute);

        // �ж� Uri ���Ƿ��� PathVariable �ֶ�
        L := Pos('{', ChildUri);
        if L > 0 then begin
          // ���������Ƿ��� PathVariable
          AParams := AMethods[I].GetParameters;
          for J := 0 to High(AParams) do begin
            if ExistAttribute(AParams[J].GetAttributes, PathVariableAttribute) then begin
              ChildUri := ChildUri.Substring(0, L - 1);
              Break;
            end;
          end;
        end;
        // ����ӳ�����
        if FUriCaseSensitive then
          FUriMap.Add(BaseUri + ChildUri, DataItem)
        else
          FUriMap.Add(LowerCase(BaseUri + ChildUri), DataItem);
        Continue;
      end;

      // WebSocketAttribute
      if CheckAttribute(AMethods[I].GetAttributes,
        function(const Item: TCustomAttribute; const Data: Pointer): Boolean
        begin
          Result := Item.ClassType = WebSocketAttribute;
          if Result then
            WebSocketDataItem.Data := (WebSocketAttribute(Item)).Data; 
        end)
      then begin 
        WebSocketDataItem.Controller := ClassItem.Value;
        WebSocketDataItem.MethodIndex := I;
        WebSocketDataItem.ResponseBody := ExistAttribute(AMethods[I].GetAttributes, ResponseBodyAttribute);
        FWebSocketMap.Add(WebSocketDataItem);
      end;
    end;
  end;
end;

procedure TIocpHttpMvcServer.LoadConfig(const AFileName: string);
var
  LFileName: string;  
  XML: TXMLDocument;
  LNode: PXMLNode;

  function GetInt(const Name: string; DefaultValue: Integer = 0): Integer;
  var
    ANode: PXMLNode;
  begin
    ANode := LNode.NodeByName(Name);
    if Assigned(ANode) then      
      Result := StrToIntDef(ANode.Text, DefaultValue)
    else
      Result := DefaultValue;
  end;
  
  function GetString(const Name: string): string;
  var
    ANode: PXMLNode;
  begin
    ANode := LNode.NodeByName(Name);
    if Assigned(ANode) then      
      Result := Trim(ANode.Text)
    else Result := '';
  end;
  
  function GetBoolean(const Name: string): Boolean;
  var
    ANode: PXMLNode;
  begin
    ANode := LNode.NodeByName(Name);
    if Assigned(ANode) then
      Result := ANode.AsBoolean
    else
      Result := False;
  end;
  
var
  LActive: Boolean;
begin
  FNeedSaveConfig := True;
  if (AFileName = '') or (not FileExists(AFileName)) then begin
    LFileName := DefaultConfigName;
    if not FileExists(LFileName) then 
      Exit;
  end else
    LFileName := AFileName;
  LActive := Active;
  XML := TXMLDocument.Create();
  try
    XML.LoadFromFile(LFileName);
    LNode := @XML.Root;
    LActive := GetBoolean('Active');
    ListenPort := GetInt('ListenPort', 8080);
    Charset := StringA(GetString('Charset'));
    UseWebSocket := GetBoolean('UseWebSocket');
    BindAddr := StringA(GetString('BindAddr'));
    Prefix := GetString('Prefix');
    Suffix := GetString('Suffix');
    UriCaseSensitive := GetBoolean('UriCaseSensitive');
    ContentLanguage := StringA(GetString('ContentLanguage')); 
    WebPath := GetAbsolutePathEx(AppPath, GetString('WebPath'));
    GzipFileTypes := GetString('GzipFileTypes');
    AutoDecodePostParams := GetBoolean('AutoDecodePostParams');
    UploadMaxDataSize := GetInt('UploadMaxDataSize');
    
    LNode := XML.Root.NodeByName('AccessControlAllow');
    if Assigned(LNode) then begin
      AccessControlAllow.Enabled := GetBoolean('Enabled');
      AccessControlAllow.Origin := GetString('Origin');
      AccessControlAllow.Methods := GetString('Methods');
      AccessControlAllow.Headers := GetString('Headers');
    end;

    FNeedSaveConfig := False;
  finally
    Active := LActive;
    FreeAndNil(XML);
  end;
end;

procedure TIocpHttpMvcServer.SaveConfig(const AFileName: string);
var
  LFileName: string;  
  XML: TXMLDocument;
  LNode: PXMLNode;

  procedure SetInt(const Name: string; const Value: Integer);
  begin
    LNode.AddOrUpdate(Name, Value);
  end;

  procedure SetString(const Name, Value: string);
  begin
    LNode.AddOrUpdate(Name, Value);
  end;
  
  procedure SetBoolean(const Name: string; Value: Boolean);
  begin
    LNode.AddOrUpdate(Name, Value);
  end;
  
begin
  if (AFileName = '') then
    LFileName := DefaultConfigName
  else
    LFileName := AFileName;
  XML := TXMLDocument.Create();
  try
    if FileExists(LFileName) then
      XML.LoadFromFile(LFileName);
    LNode := @XML.Root;
    SetInt('ListenPort', ListenPort);
    SetBoolean('Active', Active);
    SetString('Charset', string(Charset));
    SetString('BindAddr', string(BindAddr));
    SetBoolean('UseWebSocket', UseWebSocket);
    SetString('Prefix', Prefix);
    SetString('Suffix', Suffix);
    SetBoolean('UriCaseSensitive', FUriCaseSensitive);
    SetString('ContentLanguage', string(ContentLanguage));
    SetString('WebPath', GetRelativePath(AppPath, WebPath));
    SetString('GzipFileTypes', GzipFileTypes);
    SetBoolean('AutoDecodePostParams', AutoDecodePostParams);
    SetInt('UploadMaxDataSize', UploadMaxDataSize);
    
    LNode := XML.Node^['AccessControlAllow'];
    if not Assigned(LNode) then
      LNode := XML.AddChild('AccessControlAllow');
    SetBoolean('Enabled', AccessControlAllow.Enabled);
    SetString('Origin', AccessControlAllow.Origin);
    SetString('Methods', AccessControlAllow.Methods);
    SetString('Headers', AccessControlAllow.Headers);
  finally
    XML.SaveToFile(LFileName);
    FreeAndNil(XML);
  end;  
end;

function TIocpHttpMvcServer.SerializeData(const Value: TValue): string;
begin
  if Assigned(FOnSerializeData) then
    Result := FOnSerializeData(Self, Value)
  else
    Result := Value.ToString;
end;

procedure TIocpHttpMvcServer.SetAccessControlAllow(
  const Value: TIocpHttpAccessControlAllow);
begin
  FServer.AccessControlAllow := Value;
end;

procedure TIocpHttpMvcServer.SetActive(const Value: Boolean);
begin
  FServer.Active := Value;
end;

procedure TIocpHttpMvcServer.SetAutoDecodePostParams(const Value: Boolean);
begin
  FServer.AutoDecodePostParams := Value;
end;

procedure TIocpHttpMvcServer.SetBindAddr(const Value: StringA);
begin
  FServer.BindAddr := Value;
end;

procedure TIocpHttpMvcServer.SetCharset(const Value: StringA);
begin
  FServer.Charset := Value;
end;

procedure TIocpHttpMvcServer.SetContentLanguage(const Value: StringA);
begin
  FServer.ContentLanguage := Value;
end;

procedure TIocpHttpMvcServer.SetGzipFileTypes(const Value: string);
begin
  FServer.GzipFileTypes := Value;
end;

procedure TIocpHttpMvcServer.SetListenPort(const Value: Integer);
begin
  FServer.ListenPort := Value;
end;

procedure TIocpHttpMvcServer.SetUploadMaxDataSize(const Value: NativeUInt);
begin
  FServer.UploadMaxDataSize := Value;
end;

procedure TIocpHttpMvcServer.SetUseWebSocket(const Value: Boolean);
begin
  if FUseWebSocket <> Value then begin  
    FUseWebSocket := Value;
    if not (csLoading in ComponentState) then
      InitServer;
  end;
end;

procedure TIocpHttpMvcServer.SetWebBasePath(const Value: string);
begin
  FServer.WebPath := Value;
end;

{ TUriMapData }

procedure TUriMapData.Clear;
begin
  Method := http_Unknown;
  Consumes := '';
  Produces := '';
  Params := '';
  Headers := '';
  Controller := nil;
  MethodIndex := -1;
  DownMode := False;
end;

function TUriMapData.GetHeaderName: string;
begin
  Result := GetNameOrValue(Headers, True);
end;

function TUriMapData.GetHeaderValue: string;
begin
  Result := GetNameOrValue(Headers, False);
end;

function TUriMapData.GetParamName: string;
begin
  Result := GetNameOrValue(Params, True);
end;

function TUriMapData.GetParamValue: string;
begin
  Result := GetNameOrValue(Params, False);
end;

{ TWebSocketMapData }

class function TWebSocketMapData.Create(AController: TObject;
  AMethodIndex: Integer): TWebSocketMapData;
begin
  Result.Controller := AController;
  Result.MethodIndex := AMethodIndex;
end;

initialization
  MvcScanner := TIocpMvcScanner.Create();

finalization
  FreeAndNil(MvcScanner);
  if HttpMvcAllowFree and Assigned(HttpMvc) then begin
    if HttpMvc.FNeedSaveConfig then
      HttpMvc.SaveConfig();
    FreeAndNil(HttpMvc);
  end;

end.
