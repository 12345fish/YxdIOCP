{*******************************************************}
{                                                       }
{       IOCP �ں�����                                   }
{                                                       }
{       ��Ȩ���� (C) 2015 YangYxd                       }
{                                                       }
{*******************************************************}

{
  IOCP �ں����棬ר���ڴ���IOCP����
}

unit iocp.Core.Engine;


{$I 'iocp.inc'}

{$if CompilerVersion >= 18}
  {$DEFINE INLINE}
{$IFEND}

interface

uses
  iocp.Utils.Hash, iocp.Sockets.Utils, iocp.Res,
  Windows, SysUtils, Classes, SyncObjs, ComObj, ActiveX;

const
  IOCP_LOG_DATEFORMAT = 'hh:mm:ss.zzz';

type
  TIocpLocker = class(TCriticalSection)
  private
    FName: string;
    FRemork: string;
  public
    procedure Enter(const ARemork: string); overload;
    procedure Leave;
    property Name: string read FName write FName;
    property Remork: string read FRemork write FRemork;
  end;
  TThreadStackFunc = function(AThread: TThread): string;

type
  TIocpCore = class(TObject)
  private
    FHandle: NativeUInt;
  protected
    function CreateIOCPHandle: Boolean;
  public
    destructor Destroy; override;
    procedure DoInitialize;
    procedure DoFinalize;
    function HandleAllocated: Boolean; {$IFDEF INLINE}inline; {$ENDIF}
    procedure HandleException(E: Exception);
    /// <summary>
    /// ��һ��Handle�����IOCP���
    /// </summary>
    function Bind(pvHandle: THandle; pvCompletionKey: ULONG_PTR): THandle;
    /// <summary>
    /// Postһ��Exit���󵽶�����
    /// </summary>
    function PostExitRequest: Boolean;
    /// <summary>
    /// Ͷ������IO
    /// </summary>
    function PostRequest(dwCompletionKey: DWORD; lpOverlapped: POverlapped): Boolean;
    property Handle: NativeUInt read FHandle;
  end;

const
  IOCP_WORKER_ISBUSY = $01;      // ������æµ
  IOCP_WORKER_ISWATING = $02;    // ���������ڵȴ�����
  IOCP_WORKER_RESERVED = $04;    // �����߿��б���
  IOCP_WORKER_OVER = $08;        // �����߱�����
  IOCP_WORKER_COM = $10;         // �������ѳ�ʼ��Ϊ֧��COM��״̬(����Windows)
  IOCP_WORKER_TIMEOUT = 30000;   // ��ʱ�����̳߳�ʱʱ��

type
  TIocpEngine = class;
  TIocpRequest = class;

  POVERLAPPEDEx = ^OVERLAPPEDEx;
  OVERLAPPEDEx = packed record
    Overlapped: OVERLAPPED;
    iocpRequest: TIocpRequest;
    refCount: Integer;
  end;

  TIocpWorker = class(TThread)
  private
    FFlags: Integer;
    FEngine: TIocpEngine;
    FIocpCore: TIocpCore;
    FData: Pointer;
    FLastRequest: TIocpRequest;
    FResponseRef: NativeUInt;
    function GetValue(Index: Integer): Boolean; inline;
    procedure SetValue(Index: Integer; const Value: Boolean); inline;
  protected
    procedure Execute; override;
    procedure RemoveFlags(Index: Integer); inline;
  public
    constructor Create(AIocpCore: TIocpCore);
    destructor Destroy; override;

    // д״̬��Ϣ
    procedure WriteStateInfo(const pvStrings: TStrings);

    procedure ComNeeded(AInitFlags: Cardinal = 0; pvReserved: Pointer = nil);
    // �ж�COM�Ƿ��Ѿ���ʼ��Ϊ֧��COM
    property ComInitialized: Boolean index IOCP_WORKER_COM read GetValue;
    // �жϵ�ǰ�Ƿ�æµ
    property IsBusy: Boolean index IOCP_WORKER_ISBUSY read GetValue;
    // �ж��Ƿ����ڵȴ�����ִ��
    property IsWating: Boolean index IOCP_WORKER_ISWATING read GetValue;
    // �ж��Ƿ�Ϊ�����߳�
    property IsReserved: Boolean index IOCP_WORKER_RESERVED read GetValue;
    // �ж��Ƿ����
    property IsOver: Boolean index IOCP_WORKER_OVER read GetValue;
    // ��������
    property Data: Pointer read FData write FData;
    // ���һ��IOCP����
    property LastRequest: TIocpRequest read FLastRequest;
  end;

  /// <summary>
  /// IOCP����, ����IOCP�����߳�
  /// </summary>
  TIocpEngine = class(TObject)
  private
    FActive: Boolean;
    FWorkerLocker: TIocpLocker;   
    FMaxWorkerCount: Integer;
    FWorkerNeedCoInitialize: Boolean;
    FWorkerCount: Integer;
    FActiveWorkerCount:Integer;
    FIocpCore: TIocpCore;
    FWorkerList: TYXDHashMapLinkTable;
    FSafeStopEvent: TEvent;
    FName: string;
    procedure SafeStop(pvTimeOut: Integer);
    function WorkersIsActive: Boolean; // ���̰߳�ȫ��ʹ��ǰ�����
    function HashItemToWorker(Item: PHashMapLinkItem): TIocpWorker; inline;
    procedure AddWorker(AWorker: TIocpWorker); inline;
    procedure SetActive(const Value: Boolean);
  protected
    procedure IncActiveWorker; 
    procedure DecActiveWorker(pvWorker: TIocpWorker);
  public
    constructor Create;
    destructor Destroy; override;

    function StopWorkers(pvTimeOut: Cardinal): Boolean;
    procedure WriteStateInfo(pvStrings: TStrings);
    /// <summary>
    /// ��ȡ״̬��Ϣ
    /// </summary>
    function GetStateInfo: string;
    /// <summary>
    /// ��ȡ�����߳�״̬��Ϣ
    /// </summary>
    function GetWorkerStateInfo(pvTimeOut: Cardinal = 3000): string;
    /// <summary>
    /// ��ȡ�����̶߳�ջ
    /// </summary>
    function GetWorkerStackInfos(pvThreadStackFunc: TThreadStackFunc; pvTimeOut: Integer = 3000): string;
    /// <summary>
    /// �������Ĺ����߳�
    /// </summary>
    procedure SetMaxWorkerCount(AWorkerCount: Integer);
    // ���ù���������������ֹͣ���й����ߣ��Ǳ�Ҫ��Ҫ����
    procedure SetWorkerCount(AWorkerCount: Integer);

    /// <summary>���Դ���һ�������߳�, ����Ѿ����ڿ��еĹ����̣߳��򲻴���</summary>
    /// <param name="pvIsTempWorker">��ʱ�����߳� </param>
    function CreateWorker(pvIsTempWorker: Boolean = True): Boolean;

    /// <summary>
    /// ����IOCP���棬���������߳�
    /// </summary>
    procedure Start;

    /// <summary>
    /// ֹͣ
    /// </summary>
    procedure Stop(ATimeOut: Integer = 120000);

    /// <summary>
    /// Post һ��Iocp���������У��ȴ�����
    /// </summary>
    procedure PostRequest(pvRequest: TIocpRequest);

    property Name: string read FName write FName;
    property Active: Boolean read FActive write SetActive;
    /// <summary>
    /// IOCP�ں�, ֻ��
    /// </summary>
    property IocpCore: TIocpCore read FIocpCore;
    /// <summary>
    /// ���Ĺ����߳���
    /// </summary>
    property MaxWorkerCount: Integer read FMaxWorkerCount write SetMaxWorkerCount;
    /// <summary>
    /// ��ȡ�����߳�����
    /// </summary>
    property WorkerCount: Integer read FWorkerCount;
    /// <summary>
    /// �����߳���Ҫ����Com��ʼ��
    /// </summary>
    property WorkerNeedCoInitialize: Boolean read FWorkerNeedCoInitialize write FWorkerNeedCoInitialize;
  end;

  /// <summary>
  /// Iocp����
  /// </summary>
  TIocpRequest = class(TObject)
  private
    FPrev: TIocpRequest;
    FNext: TIocpRequest;
    FResponding: Boolean;
    FErrorCode: Integer;
    FIocpWorker: TIocpWorker;
    FData: Pointer;
    FTag: Integer;
    FOnResponse: TNotifyEvent;
    FOnResponseDone: TNotifyEvent;
    FRemark: string;
  protected
    FRespondStartTime: Int64;
    FRespondEndTime: Int64;
    FOverlapped: OVERLAPPEDEx;
    FBytesTransferred: NativeUInt;
    FCompletionKey: NativeUInt;
    
    // IOCP������Ӧ, ������IOCP�����߳�
    procedure HandleResponse; virtual;
    /// <summary>
    /// ��Ӧ����������,��IOCP�߳�,ִ������ʱִ��,����������Ӧʱ��û�г����쳣����ִ��
    /// </summary>
    procedure ResponseDone; virtual;
    /// <summary>
    /// ����ȡ��, ��δͶ�ݵ�������, ���ò�ȡ������
    /// </summary>
    procedure CancelRequest; virtual;
  public
    constructor Create; virtual;
    function GetStateInfo: string; virtual;
    property IocpWorker: TIocpWorker read FIocpWorker;
    property ErrorCode: Integer read FErrorCode write FErrorCode;
    /// <summary>
    /// ������Ӧ����
    /// </summary>
    property Responding: Boolean read FResponding;
    property Remark: String read FRemark write FRemark;
    property Data: Pointer read FData write FData;
    property Tag: Integer read FTag write FTag;
    property Worker: TIocpWorker read FIocpWorker;
    property OnResponse: TNotifyEvent read FOnResponse write FOnResponse;
    property OnResponseDone: TNotifyEvent read FOnResponseDone write FOnResponseDone;
  end;

type
  TIocpASyncRequest = class;
  
  {$IFDEF UNICODE}
  TIocpASyncEvent = reference to procedure(pvRequest: TIocpASyncRequest);
  {$ELSE}
  TIocpASyncEvent = procedure(pvRequest: TIocpASyncRequest) of object;
  {$ENDIF}

  TIocpASyncRequest = class(TIocpRequest)
  private
    FOnASyncEvent: TIocpASyncEvent;
  protected
    procedure HandleResponse; override;
  public
    destructor Destroy; override;
    procedure DoCleanUp;
    function GetStateInfo: String; override;
    /// <summary>
    /// �첽ִ���¼���iocp�߳��д���
    /// </summary>
    property OnASyncEvent: TIocpASyncEvent read FOnASyncEvent write FOnASyncEvent;
  end;

type
  /// <summary>
  /// Iocp ����������
  /// </summary>
  TIocpRequestLinkList = class(TObject)
  private
    FCount: Integer;
    FHead: TIocpRequest;
    FTail: TIocpRequest;
    FMaxSize: Integer;
    procedure SetMaxSize(pvMaxSize:Integer);
  public
    constructor Create(pvMaxSize: Integer = 4096);
    destructor Destroy; override;
    function Push(pvRequest: TIocpRequest): Boolean;
    function Pop: TIocpRequest;
    property Count: Integer read FCount;
    property MaxSize: Integer read FMaxSize write SetMaxSize;
  end;

type
  /// <summary>
  /// Iocp ����˫������
  /// </summary>
  TIocpRequestDuLinkList = class(TObject)
  private
    FLocker: TIocpLocker;
    FHead: TIocpRequest;
    FTail: TIocpRequest;
    FCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(pvContext: TIocpRequest);
    /// <summary>
    /// �Ƴ������е�һ���ڵ㣬���������ͷ�pvContext
    /// </summary>
    function Remove(pvContext: TIocpRequest): Boolean;
    function Push(pvRequest: TIocpRequest): Boolean;
    function Pop: TIocpRequest;
    procedure ToList(pvList: TList);  
    property Count: Integer read FCount; 
  end;

function IsDebugMode: Boolean;

function GetTimestamp: Int64;
function TimestampToDatetime(const v: Int64): TDateTime;
function TimestampToStr(const v: Int64): string;
function GetCPUCount: Integer;

implementation

{$IFDEF MSWINDOWS}
type
  TGetTickCount64 = function: Int64;
  TGetSystemTimes = function(var lpIdleTime, lpKernelTime, lpUserTime: TFileTime): BOOL; stdcall;
{$ENDIF MSWINDOWS}

var
  _ProcessIDStr: string; 
  _CPUCount: Integer;
  {$IFDEF NEXTGEN}
  _Watch: TStopWatch;
  {$ELSE}
  GetTickCount64: TGetTickCount64;
  //WinGetSystemTimes: TGetSystemTimes;
  _StartCounter: Int64;
  _PerfFreq: Int64;
  {$ENDIF}
  _StartTime: TDateTime;
{$IFDEF DEBUG_ON}
var
  workerRef: Integer = 0;
{$ENDIF}

function BoolToStr(v: Boolean): string; inline;
const
  BoolStr: array [Boolean] of string = ('False', 'True');
begin
  Result := BoolStr[v];
end;

function IsDebugMode: Boolean;
begin
  {$IFDEF MSWINDOWS}
  {$warn symbol_platform off}
  Result := Boolean(DebugHook);
  {$warn symbol_platform on}
  {$ELSE}
  Result := false;
  {$ENDIF}
end;

function GetTimestamp: Int64;
begin
  {$IFDEF MSWINDOWS}
  if _PerfFreq > 0 then begin
    QueryPerformanceCounter(Result);
    Result := Trunc((Result - _StartCounter) / _PerfFreq * 1000);
  end else if Assigned(GetTickCount64) then
    Result := (GetTickCount64 - _StartCounter)
  else
    Result := (GetTickCount - _StartCounter)
  {$ELSE}
  Result := _Watch.Elapsed.Ticks div 10000;
  {$ENDIF}
end;

function TimestampToDatetime(const v: Int64): TDateTime;
const
  MSecsPerDay = 86400000;
begin
  Result := ((_StartTime * MSecsPerDay) + v) / MSecsPerDay;
end;

function TimestampToStr(const v: Int64): string;
begin
  Result := FormatDateTime(IOCP_LOG_DATEFORMAT, TimestampToDatetime(v));
end;

function GetCPUCount: Integer;
{$IFDEF MSWINDOWS}
var
  si: SYSTEM_INFO;
{$ENDIF}
begin
  if _CPUCount = 0 then begin
  {$IFDEF MSWINDOWS}
    GetSystemInfo(si);
    Result := si.dwNumberOfProcessors;
  {$ELSE}// Linux,MacOS,iOS,Andriod{POSIX}
  {$IFDEF POSIX}
    Result := sysconf(_SC_NPROCESSORS_ONLN);
  {$ELSE}// ����ʶ�Ĳ���ϵͳ��CPU��Ĭ��Ϊ1
    Result := 1;
  {$ENDIF !POSIX}
  {$ENDIF !MSWINDOWS}
  end else
    Result := _CPUCount;
end;

procedure WriteFileMsgSafe(const pvMsg: string; const pvFilePre: string);
var
  lvFileName, lvBasePath:String;
  lvLogFile: TextFile;
begin
  try
    lvBasePath := ExtractFilePath(ParamStr(0)) + 'log';
    ForceDirectories(lvBasePath);
    lvFileName := lvBasePath + '\' + FormatDateTime('yyyymmddhhnnsszzz', Now()) +
      '_' + _ProcessIDStr + '_' + pvFilePre + '.log';
    AssignFile(lvLogFile, lvFileName);
    if (FileExists(lvFileName)) then
      Append(lvLogFile)
    else
      ReWrite(lvLogFile);
    Writeln(lvLogFile, pvMsg);
    flush(lvLogFile);
    CloseFile(lvLogFile);
  except end;
end;

{ TIocpCore }

function TIocpCore.Bind(pvHandle: THandle; pvCompletionKey: ULONG_PTR): THandle;
begin
  Result := CreateIoCompletionPort(pvHandle, FHandle, pvCompletionKey, 0);
end;

function TIocpCore.CreateIOCPHandle: Boolean;
begin
  FHandle := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  Result := HandleAllocated;
  if not Result then 
    RaiseLastOSError;
end;

destructor TIocpCore.Destroy;
begin
  DoFinalize();
  inherited;
end;

procedure TIocpCore.DoFinalize;
begin
  if HandleAllocated then begin
    CloseHandle(FHandle);
    FHandle := 0;
  end;
end;

procedure TIocpCore.DoInitialize;
begin
  if not HandleAllocated then CreateIOCPHandle();
end;

function TIocpCore.HandleAllocated: Boolean;
begin
  Result := (FHandle <> 0) and (FHandle <> INVALID_HANDLE_VALUE);
end;

procedure TIocpCore.HandleException(E: Exception);
begin 
end;

function TIocpCore.PostExitRequest: Boolean;
begin
  Result := PostQueuedCompletionStatus(FHandle, 0, 0, nil);
end;

function TIocpCore.PostRequest(dwCompletionKey: DWORD;
  lpOverlapped: POverlapped): Boolean;
begin
  Result := PostQueuedCompletionStatus(FHandle, 0, dwCompletionKey, lpOverlapped);
end;

{ TIocpWorker }

procedure TIocpWorker.ComNeeded(AInitFlags: Cardinal; pvReserved: Pointer);
begin
  {$IFDEF MSWINDOWS}
  if not ComInitialized then begin
    if AInitFlags = 0 then
      CoInitialize(pvReserved)
    else
      CoInitializeEx(pvReserved, AInitFlags);
    SetValue(IOCP_WORKER_COM, True);
  end;
  {$ENDIF}
end;

constructor TIocpWorker.Create(AIocpCore: TIocpCore);
begin
  FResponseRef := 0;
  inherited Create(True);
  FIocpCore := AIocpCore;
  FFlags := IOCP_WORKER_RESERVED;  // default is reserved
end;

destructor TIocpWorker.Destroy;
begin
  inherited;
end;

procedure TIocpWorker.WriteStateInfo(const pvStrings: TStrings);
var
  RequestStateInfo: string;
begin
  pvStrings.Add(Format(strWorker_Info, [ThreadID, FResponseRef]));
  if IsOver then
    pvStrings.Add(strWorker_Done)
  else begin
    pvStrings.Add(Format(strWorker_StateInfo,
       [BoolToStr(IsBusy),
        BoolToStr(IsWating),
        BoolToStr(IsReserved)]));

    if Assigned(FLastRequest) then begin
      RequestStateInfo := FLastRequest.GetStateInfo;
      if Length(RequestStateInfo) > 0 then begin
        pvStrings.Add(strRequest_Title);
        pvStrings.Add(RequestStateInfo);
      end;
    end;
  end;
end;

procedure TIocpWorker.Execute;
var
  lvBytesTransferred: DWORD;
  lvResultStatus: BOOL;
  lvErrCode: Integer;
  lpOverlapped: POVERLAPPEDEx;
  lpCompletionKey: ULONG_PTR;
  lvTempRequest: TIocpRequest;
begin
  {$IFDEF MSWINDOWS}{$IFDEF UNICODE}
  NameThreadForDebugging('TIocpWorker');
  {$ENDIF}{$ENDIF}
  if not Assigned(FEngine) then Exit;
  if FEngine.FWorkerNeedCoInitialize then
    ComNeeded();
  FEngine.IncActiveWorker;
  {$IFDEF DEBUG_ON}
  InterlockedIncrement(workerRef);
  {$ENDIF}
  while (not Terminated) do begin
    try
      FFlags := (FFlags or IOCP_WORKER_ISWATING) and (not IOCP_WORKER_ISBUSY);

      // ����ʱ�����̣߳���ȡ����ʱ�����ó�ʱֵ��������IOCP_WORKER_TIMEOUTΪ��ʱֵ
      if IsReserved then begin
        lvResultStatus := GetQueuedCompletionStatus(FIocpCore.FHandle,
            lvBytesTransferred, lpCompletionKey, POverlapped(lpOverlapped), INFINITE);
      end else begin 
        lvResultStatus := GetQueuedCompletionStatus(FIocpCore.FHandle,
          lvBytesTransferred, lpCompletionKey, POverlapped(lpOverlapped), IOCP_WORKER_TIMEOUT);
      end;

      FFlags := (FFlags or IOCP_WORKER_ISBUSY) and (not IOCP_WORKER_ISWATING);

      if Assigned(lpOverlapped) then begin
        if not lvResultStatus then
          lvErrCode := GetLastError
        else
          lvErrCode := 0;

        Inc(FResponseRef);  // ��Ӧ��������1
        lvTempRequest := lpOverlapped.iocpRequest;
        FLastRequest := lvTempRequest;
        try
          if FLastRequest = nil then
            Assert(FLastRequest <> nil);

          lvTempRequest.FResponding := true;
          lvTempRequest.FRespondStartTime := GetTimestamp;
          lvTempRequest.FRespondEndTime := 0;
          lvTempRequest.FIocpWorker := Self;
          lvTempRequest.FErrorCode := lvErrCode;
          lvTempRequest.FBytesTransferred := lvBytesTransferred;
          lvTempRequest.FCompletionKey := lpCompletionKey;

          if Assigned(lvTempRequest.FOnResponse) then
            lvTempRequest.FOnResponse(lvTempRequest)
          else
            lvTempRequest.HandleResponse();
            
        finally
          lvTempRequest.FRespondEndTime := GetTimestamp;
          lvTempRequest.FResponding := False;
          
          if Assigned(lvTempRequest.OnResponseDone) then
            lvTempRequest.FOnResponseDone(lvTempRequest)
          else
            lvTempRequest.ResponseDone();
        end;

      end else
        Break; // exit
        
    except
      on E: Exception do begin
        try
          FIocpCore.HandleException(E);
        except
        end;
      end;
    end;
  end;

  FFlags := IOCP_WORKER_OVER;
  if ComInitialized then
    CoUninitialize();

  {$IFDEF DEBUG_ON}
  InterlockedDecrement(workerRef);
  {$ENDIF}

  if Assigned(FEngine) then begin
    try
      FEngine.DecActiveWorker(Self);
    except end;
  end;
end;

function TIocpWorker.GetValue(Index: Integer): Boolean;
begin
  Result := (FFlags and Index) <> 0;
end;

procedure TIocpWorker.RemoveFlags(Index: Integer);
begin
  FFlags := (FFlags and (not Index));
end;

procedure TIocpWorker.SetValue(Index: Integer; const Value: Boolean);
begin
  if Value then
    FFlags := (FFlags or Index)
  else
    FFlags := (FFlags and (not Index));
end;

{ TIocpEngine }

procedure TIocpEngine.AddWorker(AWorker: TIocpWorker);
begin
  AWorker.FEngine := Self;
  AWorker.FreeOnTerminate := True;
  FWorkerList.Add(Cardinal(AWorker), nil);
end;

constructor TIocpEngine.Create;
begin
  inherited Create;
  FWorkerList := TYXDHashMapLinkTable.Create(10949);
  FWorkerLocker := TIocpLocker.Create;
  FWorkerCount := GetCPUCount shl 2 + 1;
  FMaxWorkerCount := FWorkerCount;
  FIocpCore := TIocpCore.Create;
  FIocpCore.DoInitialize;
end;

function TIocpEngine.CreateWorker(pvIsTempWorker: Boolean): Boolean;
var
  AWorker: TIocpWorker;
  Item: PHashMapLinkItem;
begin
  Result := False;
  FWorkerLocker.Enter;
  try
    if FWorkerList.Count >= FMaxWorkerCount then Exit;
    for Item in FWorkerList do begin
      AWorker := HashItemToWorker(Item);
      if Assigned(AWorker) and (AWorker.IsWating) then
        Exit;
    end; 
    AWorker := TIocpWorker.Create(FIocpCore);
    AWorker.SetValue(IOCP_WORKER_RESERVED, not pvIsTempWorker);
    AddWorker(AWorker);
    {$IFDEF UNICODE}
    AWorker.Start;
    {$ELSE}
    AWorker.Resume;
    {$ENDIF}
  finally
    FWorkerLocker.Leave;
  end;
end;

procedure TIocpEngine.DecActiveWorker(pvWorker: TIocpWorker);
var
  lvCount: Integer;
begin
  FWorkerLocker.Enter;
  try
    FWorkerList.Remove(Integer(pvWorker));
    lvCount := InterlockedDecrement(FActiveWorkerCount);
  finally
    FWorkerLocker.Leave;
  end;
  if lvCount = 0 then begin
    if Assigned(FSafeStopEvent) then
      FSafeStopEvent.SetEvent;
  end;
end;

destructor TIocpEngine.Destroy;
begin
  Stop();
  Sleep(20);
  FreeAndNil(FIocpCore);
  FreeAndNil(FWorkerList);
  FreeAndNil(FWorkerLocker);
  FreeAndNil(FSafeStopEvent);
  inherited Destroy;
end;

function TIocpEngine.GetStateInfo: string;
var
  lvStrings :TStrings;
begin
  lvStrings := TStringList.Create;
  try
    WriteStateInfo(lvStrings);
    Result := lvStrings.Text;
  finally
    lvStrings.Free;
  end;
end;

function TIocpEngine.GetWorkerStackInfos(pvThreadStackFunc: TThreadStackFunc;
  pvTimeOut: Integer): string;
var
  lvStrings: TStrings;
  i, j: Integer;
  Item: PHashMapLinkItem;
  lvWorker: TIocpWorker;
begin
  Result := '';
  Assert(Assigned(pvThreadStackFunc));
  lvStrings := TStringList.Create;
  try
    j := 0;
    lvStrings.Add(Format(strEngine_DebugInfo, [BoolToStr(FActive), FWorkerCount]));
    FWorkerLocker.Enter;
    try
      i := 1;
      for Item in FWorkerList do begin
        lvWorker := HashItemToWorker(Item);
        if Assigned(lvWorker) and (lvWorker.IsBusy) then begin
          if GetTimestamp - lvWorker.FLastRequest.FRespondStartTime > pvTimeOut then begin
            lvStrings.Add(Format(strEngine_WorkerTitle, [i]));
            lvStrings.Add(pvThreadStackFunc(lvWorker));
            inc(j);
          end;
        end;
        inc(i);
      end;
    finally
      FWorkerLocker.Leave;
    end;
    if j > 0 then
      Result := lvStrings.Text;
  finally
    lvStrings.Free;
  end;
end;

function TIocpEngine.GetWorkerStateInfo(pvTimeOut: Cardinal): string;
var
  lvStrings: TStrings;
  i: Integer;
  Item: PHashMapLinkItem;
  lvWorker: TIocpWorker;
  lvNow: Int64;
begin
  lvStrings := TStringList.Create;
  try
    lvStrings.Add(Format(strEngine_DebugInfo, [BoolToStr(FActive), WorkerCount]));
    lvNow := GetTimestamp;
    FWorkerLocker.Enter;
    try
      i := 1;
      for Item in FWorkerList do begin
        lvWorker := HashItemToWorker(Item);
        if Assigned(lvWorker) and (lvWorker.IsBusy) then begin
          if lvNow - lvWorker.FLastRequest.FRespondStartTime > pvTimeOut then begin
            lvStrings.Add(Format(strEngine_WorkerTitle, [i]));
            lvWorker.WriteStateInfo(lvStrings);
          end;
          Inc(i);
        end;
      end;
    finally
      FWorkerLocker.Leave;
    end;
    Result := lvStrings.Text;
  finally
    lvStrings.Free;
  end;
end;

function TIocpEngine.HashItemToWorker(Item: PHashMapLinkItem): TIocpWorker;
begin
  if (Item <> nil) and (Item.Value <> nil) then
    Result := TIocpWorker(Pointer(Item.Value.GetNumKey))
  else
    Result := nil;  
end;

procedure TIocpEngine.IncActiveWorker;
begin
  InterlockedIncrement(FActiveWorkerCount);
end;

procedure TIocpEngine.PostRequest(pvRequest: TIocpRequest);
begin
  if not IocpCore.PostRequest(0, POverlapped(@pvRequest.FOverlapped)) then
    RaiseLastOSError;
end;

procedure TIocpEngine.SafeStop(pvTimeOut: Integer);
begin
  if FActiveWorkerCount > 0 then
    StopWorkers(pvTimeOut);
  FWorkerList.Clear;
  FActive := False; 
end;

procedure TIocpEngine.SetActive(const Value: Boolean);
begin
  if FActive = Value then Exit;
  if Value then
    Start()
  else
    Stop();
end;

procedure TIocpEngine.SetMaxWorkerCount(AWorkerCount: Integer);
begin
  FMaxWorkerCount := AWorkerCount;
end;

procedure TIocpEngine.SetWorkerCount(AWorkerCount: Integer);
begin
  if FActive then Stop;
  if AWorkerCount <= 0 then
    FWorkerCount := (GetCPUCount shl 1) + 1
  else
    FWorkerCount := AWorkerCount;
end;

procedure TIocpEngine.Start;
var
  i: Integer;
  AWorker: TIocpWorker;
  lvCpuCount: Integer;
begin
  FreeAndNil(FSafeStopEvent);
  FSafeStopEvent := TEvent.Create(nil, True, False, '');

  lvCpuCount := GetCPUCount;
  for i := 0 to FWorkerCount - 1 do begin
    AWorker := TIocpWorker.Create(FIocpCore);
    AddWorker(AWorker);
    {$IFDEF UNICODE}
    AWorker.Start;
    {$ELSE}
    AWorker.Resume;
    {$ENDIF}
    SetThreadIdealProcessor(AWorker.Handle, i mod lvCpuCount);
  end;
  FActive := True;
end;

procedure TIocpEngine.Stop(ATimeOut: Integer);
begin
  SafeStop(ATimeOut);
end;

function TIocpEngine.StopWorkers(pvTimeOut: Cardinal): Boolean;
var
  t: Int64;
  i: Integer;
  lvEvent: TEvent;
  lvWrited: Boolean;
begin
  Result := not FActive;
  if Result then
    Exit;

  if WorkersIsActive then begin
    for i := 0 to FWorkerList.Count - 1 do begin      
      if not FIocpCore.PostExitRequest then
        RaiseLastOSError;
    end;
  end else begin
    FWorkerList.Clear;
    if Assigned(FSafeStopEvent) then
      FSafeStopEvent.SetEvent;
  end;

  lvWrited := False;
  if Assigned(FSafeStopEvent) then begin
    lvEvent := FSafeStopEvent;

    t := GetTimestamp;
    while True do begin
      {$IFDEF MSWINDOWS}
      SwitchToThread;
      {$ELSE}
      TThread.Yield;
      {$ENDIF}
      Sleep(10);

      // ����Ͷ�ݣ�������Ӧʧ�ܵĹ����߳�
      FIocpCore.PostExitRequest;

      // �ȴ����й������
      if lvEvent.WaitFor(1000) = wrSignaled then begin
        Result := True;
        Break;
      end;

      if not lvWrited then begin
        lvWrited := True;
        WriteFileMsgSafe(GetStateInfo, Trim(Name) + '_STOP');
      end;

      if GetTimestamp - t > pvTimeOut then begin
        Result := False;
        Break;
      end;
    end;
  end;  
end;

function TIocpEngine.WorkersIsActive: Boolean;
var
  lvCode: Cardinal;
  Item: PHashMapLinkItem;
begin
  Result := False;
  for Item in FWorkerList do begin
    if Item.Value <> nil then begin
      if GetExitCodeThread(TThread(Pointer(Item.Value.GetNumKey)).Handle, lvCode) then begin
        if lvCode = STILL_ACTIVE then begin
          Result := true;
          Break;
        end;
      end;
    end;
  end;
end;

procedure TIocpEngine.WriteStateInfo(pvStrings: TStrings);
var
  i: Integer;
  Item: PHashMapLinkItem;
begin
  pvStrings.Add(Format(strEngine_DebugInfo, [BoolToStr(FActive), FWorkerCount]));
  i := 1;
  FWorkerLocker.Enter;
  try
    for Item in FWorkerList do begin
      if Item.Value <> nil then begin
        pvStrings.Add(Format(strEngine_WorkerTitle, [i + 1]));
        TIocpWorker(Pointer(Item.Value.GetNumKey)).WriteStateInfo(pvStrings);
      end;
      Inc(i);
    end;
  finally
    FWorkerLocker.Leave;
  end;
end;

{ TIocpRequest }

procedure TIocpRequest.CancelRequest;
begin
end;

constructor TIocpRequest.Create;
begin
  FOverlapped.iocpRequest := Self;
  FOverlapped.refCount := 0;
end;

function TIocpRequest.GetStateInfo: string;
begin
  Result := Format('%s %s', [Self.ClassName, FRemark]);
  if FResponding then
    Result := Result + sLineBreak + Format('start: %s', [TimestampToStr(FRespondStartTime)])
  else
    Result := Result + sLineBreak + Format('start: %s, end: %s',
      [TimestampToStr(FRespondStartTime), TimestampToStr(FRespondEndTime)]);
end;

procedure TIocpRequest.HandleResponse;
begin
end;

procedure TIocpRequest.ResponseDone;
begin
end;

{ TIocpASyncRequest }

destructor TIocpASyncRequest.Destroy;
begin
  inherited;
end;

procedure TIocpASyncRequest.DoCleanUp;
begin
  Remark := '';
  FOnASyncEvent := nil;
end;

function TIocpASyncRequest.GetStateInfo: String;
var
  lvEndTime: Int64;
begin
  if FRespondStartTime = 0 then begin
    Result := '';
    Exit;
  end;
  if FRespondEndTime <> 0 then
    lvEndTime := FRespondEndTime
  else
    lvEndTime := GetTimestamp;
  if Remark <> '' then
    Result := Remark + sLineBreak
  else
    Result := '';
  Result := Result + Format(strRequest_State,
    [BoolToStr(FRespondEndTime <> 0), lvEndTime - FRespondStartTime]);
end;

procedure TIocpASyncRequest.HandleResponse;
begin
  if Assigned(FOnASyncEvent) then FOnASyncEvent(Self);
end;

{ TIocpRequestLinkList }

constructor TIocpRequestLinkList.Create(pvMaxSize: Integer);
begin
  FMaxSize := pvMaxSize;
end;

destructor TIocpRequestLinkList.Destroy;
begin 
  inherited;
end;

function TIocpRequestLinkList.Pop: TIocpRequest;
begin
  if FHead <> nil then begin
    Result := FHead;
    FHead := FHead.FNext;
    if FHead = nil then
      FTail := nil;
    Dec(FCount);
  end else
    Result := nil;
end;

function TIocpRequestLinkList.Push(pvRequest: TIocpRequest): Boolean;
begin
  if FCount < FMaxSize then begin
    pvRequest.FNext := nil;
    if FHead = nil then
      FHead := pvRequest
    else
      FTail.FNext := pvRequest;
    FTail := pvRequest;
    Inc(FCount);
    Result := True;
  end else
    Result := False;
end;

procedure TIocpRequestLinkList.SetMaxSize(pvMaxSize: Integer);
begin
  FMaxSize := pvMaxSize;
  if FMaxSize <= 0 then FMaxSize := 512;
end;

{ TIocpRequestDuLinkList }

procedure TIocpRequestDuLinkList.Add(pvContext: TIocpRequest);
begin
  FLocker.Enter;
  try
    if FHead = nil then begin
      FHead := pvContext;
    end else begin
      FTail.FNext := pvContext;
      pvContext.FPrev := FTail;
    end;
    FTail := pvContext;
    FTail.FNext := nil;
    Inc(FCount);
  finally
    FLocker.Leave;
  end;
end;

constructor TIocpRequestDuLinkList.Create;
begin
  FHead := nil;
  FTail := nil;
  FLocker := TIocpLocker.Create();
  FLocker.Name := 'OnlineContext';
end;

destructor TIocpRequestDuLinkList.Destroy;
begin
  FreeAndNil(FLocker);
  inherited;
end;

function TIocpRequestDuLinkList.Pop: TIocpRequest;
begin
  FLocker.Enter;
  try
    Result := FHead;
    if FHead <> nil then begin
      FHead := FHead.FNext;
      if FHead = nil then FTail := nil;
      Dec(FCount);
      Result.FPrev := nil;
      Result.FNext := nil;  
    end;  
  finally
    FLocker.Leave;
  end;
end;

function TIocpRequestDuLinkList.Push(pvRequest: TIocpRequest): Boolean;
begin
  Add(pvRequest);
  Result := True;
end;

function TIocpRequestDuLinkList.Remove(pvContext: TIocpRequest): Boolean;
begin
  Result := False;
  FLocker.Enter;
  try
    if pvContext.FPrev <> nil then begin
      pvContext.FPrev.FNext := pvContext.FNext;
      if pvContext.FNext <> nil then
        pvContext.FNext.FPrev := pvContext.FPrev;
    end else if pvContext.FNext <> nil then begin  // prev is nil, pvContext is FHead
      pvContext.FNext.FPrev := nil;
      FHead := pvContext.FNext;
    end else begin   // prev and next is nil
      if pvContext = FHead then
        FHead := nil
      else
        exit;
    end;
    Dec(FCount);
    if FTail = pvContext then
      FTail := pvContext.FPrev;
    pvContext.FPrev := nil;
    pvContext.FNext := nil;
    Result := True;
  finally
    FLocker.Leave;
  end;
end;

procedure TIocpRequestDuLinkList.ToList(pvList: TList);
var
  lvItem: TIocpRequest;
begin
  FLocker.Enter;
  try
    lvItem := FHead;
    while lvItem <> nil do begin
      pvList.Add(lvItem);
      lvItem := lvItem.FNext;
    end;
  finally
    FLocker.Leave;
  end;
end;

{ TIocpLocker }

procedure TIocpLocker.Enter(const ARemork: string);
begin
  Acquire;
  FRemork := ARemork;
end;

procedure TIocpLocker.Leave;
begin
  FRemork := '';
  Release;
end;

initialization
  _StartTime := Now();
  _ProcessIDStr := IntToStr(GetCurrentProcessId);
  _CPUCount := GetCPUCount;
  {$IFNDEF NEXTGEN}
  GetTickCount64 := GetProcAddress(GetModuleHandle(kernel32), 'GetTickCount64');
  //WinGetSystemTimes := GetProcAddress(GetModuleHandle(kernel32), 'GetSystemTimes');
  if not QueryPerformanceFrequency(_PerfFreq) then begin
    _PerfFreq := -1;
    if Assigned(GetTickCount64) then
      _StartCounter := GetTickCount64
    else
      _StartCounter := GetTickCount;
  end else
    QueryPerformanceCounter(_StartCounter);
  {$ELSE}
    _Watch := TStopWatch.Create;
    _Watch.Start;
  {$ENDIF}

finalization
  {$IFDEF DEBUG_ON}
  if IsDebugMode then
      Assert(workerRef <= 0, ('iocp.core.Engine WorkerCounter, has dead thread? current worker Counter:' + IntToStr(workerRef)));
  {$ENDIF}

end.


