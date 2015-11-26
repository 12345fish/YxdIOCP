{*******************************************************}
{                                                       }
{       IOCP �������Ԫ                               }
{                                                       }
{       ��Ȩ���� (C) 2015 YangYxd                       }
{                                                       }
{*******************************************************}

{
  ����ԪΪIOCPר�ã���YxdWorkerΪ�����޸ĵ�������ģ��
  ע�� YxdWorker����QDAC��Ŀ��QWorker����Ȩ��ԭ��������
  QDAC�ٷ�Ⱥ��250530692
}

unit iocp.Task;

{$I 'iocp.inc'}
{$DEFINE SAVE_WORDER_TIME}    // ��¼�����߿�ʼ���������ʱ��

interface

uses
  iocp.Utils.Hash,
  iocp.Core.Engine, iocp.Res,
  {$IFDEF MSWINDOWS}Windows, Messages, TlHelp32, Activex, {$ENDIF}
  SyncObjs, Classes, Types, SysUtils;

const
  IT_WAITJOB_TIMEOUT = 15000;      // �����ߵȴ���ҵ��ʱʱ�� (����)
  IT_JOB_TERMINATED = $0020;       // ��ҵ����Ҫ�������У����Խ�����

  IT_WORKER_ISBUSY = $01;          // ������æµ
  IT_WORKER_COM_INITED = $04;      // �������ѳ�ʼ��Ϊ֧��COM��״̬(����Windows)
  IT_WORKER_LOOKUP = $08;          // ���������ڲ�����ҵ
  IT_WORKER_EXECUTING = $10;       // ����������ִ����ҵ
  IT_WORKER_EXECUTED = $20;        // �������Ѿ������ҵ
  IT_WORKER_FIRING = $40;          // ���������ڱ����
  IT_WORKER_RUNNING = $80;         // �������߳��Ѿ���ʼ����
  IT_WORKER_CLEANING = $0100;      // �������߳�����������ҵ 

type
  TIocpTask = class;
  TIocpTaskWorker = class;
  TIocpJobBase = class;
  TIocpSimpleJobs = class;
  {$IFNDEF UNICODE}
  IntPtr = Integer;
  {$ENDIF}
  PIocpJob = ^TIocpJob;
  TIocpJobHandle = NativeInt;   

  // ��ҵ����ص�����
  TIocpJobProc = procedure(AJob: PIocpJob) of object;
  PIocpJobProc = ^TIocpJobProc;
  TIocpJobMethod = record
  function ToJobProc: TIocpJobProc; inline;
  case Integer of
    0:
      (Proc: {$IFNDEF NEXTGEN}TIocpJobProc{$ELSE}Pointer{$ENDIF});
    1:
      (ProcA: Pointer);
    2:
      (Code: Pointer; Data: Pointer);
  end;
  
  TIocpJob = record
  private
    function GetElapseTime: Int64; inline;
    function GetIsTerminated: Boolean; inline;
    procedure SetIsTerminated(const Value: Boolean); inline;
    function GetHandle: TIocpJobHandle;
  public
    procedure Create(AProc: TIocpJobProc);
    function GetValue(Index: Integer): Boolean; inline;
    procedure SetValue(Index: Integer; const Value: Boolean); inline;
    /// <summary>ֵ��������</summary>
    /// <remarks>Worker/Next/Source���Ḵ�Ʋ��ᱻ�ÿգ�Owner���ᱻ����</remarks>
    procedure Assign(const ASource: PIocpJob);
    /// <summary>�������ݣ��Ա�Ϊ�Ӷ����е�����׼��</summary>
    procedure Reset; inline;
    /// <summmary>����������ʱ�䣬��λΪ1ms</summary>
    property ElapseTime: Int64 read GetElapseTime;
    /// <summary>�Ƿ�Ҫ�������ǰ��ҵ</summary>
    property IsTerminated: Boolean read GetIsTerminated write SetIsTerminated;
    property Handle: TIocpJobHandle read GetHandle;
  public
    Next: PIocpJob;             // ��һ�����
    StartTime: Int64;       // ������ҵ��ʼʱ��,8B
    WorkerProc: TIocpJobMethod; // ��ҵ������+8/16B
    Owner: TIocpJobBase;        // ��ҵ�������Ķ���
    Worker: TIocpTaskWorker;// ��ǰ��ҵ������
    TotalUsedTime: Integer; // �����ܼƻ��ѵ�ʱ�䣬TotalUsedTime/Runs���Եó�ƽ��ִ��ʱ��+4B
    Flags: Integer;         // ��ҵ��־λ+4B
    Data: Pointer;          // ������������
  end;
    
  TIocpWorkProc = procedure(AJob: PIocpJob) of object;

  // ��ҵ���ж���Ļ��࣬�ṩ�����Ľӿڷ�װ
  TIocpJobBase = class(TObject)
  protected
    FOwner: TIocpTask;
    function InternalPush(AJob: PIocpJob): Boolean; virtual; abstract;
    function InternalPop: PIocpJob; virtual; abstract;
    function GetCount: Integer; virtual; abstract;
    function GetEmpty: Boolean; inline;
  public
    constructor Create(AOwner: TIocpTask); virtual;
    destructor Destroy; override;
    // Ͷ��һ����ҵ (�ⲿ��Ӧ����ֱ��Ͷ�����񵽶��У�����Workers����Ӧ�����ڲ����á�)
    function Push(AJob: PIocpJob): Boolean; 
    // ����һ����ҵ
    function Pop: PIocpJob; inline;
    // ��������ҵ
    procedure Clear; overload; virtual;
    function Clear(AObject: Pointer; AMaxTimes: Integer): Integer; overload; virtual; abstract;
    function Clear(AHandle: TIocpJobHandle): Boolean; overload; virtual; abstract;
    function Clear(AProc: TIocpJobProc; AData: Pointer; AMaxTimes: Integer): Integer; overload; virtual; abstract;
    property Empty: Boolean read GetEmpty; // ��ǰ�����Ƿ�Ϊ��
    property Count: Integer read GetCount; // ��ǰ����Ԫ������
  end;

  TIocpTaskWorker = class(TThread)
  private
    FOwner: TIocpTask;
    FEvent: TEvent;
    FFlags: Integer;
    FTimeout: Integer;
    FTerminatingJob: PIocpJob;
    FPending: Boolean; // �Ѿ��ƻ���ҵ
    FProcessed: Cardinal;
    {$IFDEF SAVE_WORDER_TIME}
    FStartTime: Int64;
    FLastExecTime: Int64;
    {$ENDIF}
    function GetValue(Index: Integer): Boolean; inline;
    procedure SetValue(Index: Integer; const Value: Boolean); inline;
    function GetIsIdle: Boolean; inline;
    function WaitSignal(ATimeout: Integer): TWaitResult; inline;
  protected
    FActiveJob: PIocpJob;
    // ֮���Բ�ֱ��ʹ��FActiveJob����ط���������Ϊ��֤�ⲿ�����̰߳�ȫ�ķ�����������Ա
    FActiveJobProc: TIocpJobProc;
    FActiveJobData: Pointer;
    FActiveJobFlags: Integer;
    FActiveJobSource: PIocpJob;
    procedure Execute; override;
    procedure DoJob(AJob: PIocpJob);
  public
    constructor Create(AOwner: TIocpTask); overload;
    destructor Destroy; override;
    procedure ComNeeded(AInitFlags: Cardinal = 0);
    // �ж�COM�Ƿ��Ѿ���ʼ��Ϊ֧��COM
    property ComInitialized: Boolean index IT_WORKER_COM_INITED read GetValue;
    // �жϵ�ǰ�Ƿ����
    property IsIdle: Boolean read GetIsIdle;
    // �жϵ�ǰ�Ƿ�æµ
    property IsBusy: Boolean index IT_WORKER_ISBUSY read GetValue;
    property IsLookuping: Boolean index IT_WORKER_LOOKUP read GetValue;
    property IsExecuting: Boolean index IT_WORKER_EXECUTING read GetValue;
    property IsExecuted: Boolean index IT_WORKER_EXECUTED read GetValue;
    property IsFiring: Boolean index IT_WORKER_FIRING read GetValue;
    property IsRunning: Boolean index IT_WORKER_RUNNING read GetValue;
    {$IFDEF SAVE_WORDER_TIME}
    // �����߳���ʱ��
    property StartTime: Int64 read FStartTime;
    // ���������һ�ι���ʱ��
    property LastExecTime: Int64 read FLastExecTime;
    {$ENDIF}
  end;
  
  TIocpJobErrorSource = (jesExecute, jesFreeData, jesWaitDone, jesAfterDone);
  // �����ߴ���֪ͨ�¼�
  TIocpWorkerErrorNotify = procedure(AJob: PIocpJob; E: Exception; ErrSource: TIocpJobErrorSource) of object;
  TIocpWorkerWaitParam = record
    WaitType: Byte;
    Data: Pointer;
    case Integer of
      0:
        (Bound: Pointer); // ���������
      1:
        (WorkerProc: TMethod);
      2:
        (SourceJob: PIocpJob);
  end;

  /// <summary>
  /// IOCP����ִ������
  /// </summary>
  TIocpTask = class(TObject)
  private
    FWorkers: array of TIocpTaskWorker;
    FWorkerCount: Integer;
    FDisableCount: Integer;
    FBusyCount: Integer;
    FFiringWorkerCount: Integer;
    FMinWorkers: Integer;
    FMaxWorkers: Integer;
    FFireTimeout: Integer;
    FTerminating: Boolean;
    FCPUNum: Integer;
    FLocker: TCriticalSection;
    FSimpleJobs: TIocpSimpleJobs;
    FIsDestroying: Boolean;

    FStaticThread: TThread;
    FOnError: TIocpWorkerErrorNotify;
    function GetEnabled: Boolean;
    procedure SetEnabled(const Value: Boolean);
    procedure EnableWorkers;
    procedure DisableWorkers;
    function GetIdleWorkerCount: Integer;
    procedure SetFireTimeout(const Value: Integer);
    procedure SetMaxWorkers(const Value: Integer);
    procedure SetMinWorkers(const Value: Integer);
  protected
    function Popup: PIocpJob;
    function Post(AJob: PIocpJob): TIocpJobHandle; overload;
    procedure FreeJob(AJob: PIocpJob);
    function LookupIdleWorker(AFromSimple: Boolean = True): Boolean;
    function CreateWorker(ASuspended: Boolean): TIocpTaskWorker;
    procedure NewWorkerNeeded;
    procedure WaitRunningDone(const AParam: TIocpWorkerWaitParam);
    procedure WorkerTimeout(AWorker: TIocpTaskWorker); inline;
    procedure WorkerTerminate(AWorker: TIocpTaskWorker);
    procedure ClearWorkers;
    function ClearJobs(AObject: Pointer; AProc: TIocpJobProc; AData: Pointer; AMaxTimes: Integer): Integer;
  public
    constructor Create(AMinWorkers: Integer = 2); overload;
    destructor Destroy; override;
    // ��ȡJob�ش�С
    class function JobPoolCount(): Integer;
    // ��ȡʵ��
    class function GetInstance: TIocpTask;
    // ��ȡCPUʹ����
    class function GetCPUUsage: Integer;

    
    
    // ���������ҵ
    procedure Clear; overload;
    /// <summary>���һ��������ص�������ҵ</summary>
    /// <param name="AObject">Ҫ�ͷŵ���ҵ������̹�������</param>
    /// <param name="AMaxTimes">�����������������<0����ȫ��</param>
    /// <returns>����ʵ���������ҵ����</returns>
    /// <remarks>һ����������ƻ�����ҵ�������Լ��ͷ�ǰӦ���ñ������������������ҵ��
    /// ����δ��ɵ���ҵ���ܻᴥ���쳣��</remarks>
    function Clear(AObject: Pointer; AMaxTimes: Integer = -1): Integer; overload;
    /// <summary>�������Ͷ�ĵ�ָ��������ҵ</summary>
    /// <param name="AProc">Ҫ�������ҵִ�й���</param>
    /// <param name="AData">Ҫ�������ҵ��������ָ���ַ�����ֵΪnil��
    /// ��������е���ع��̣�����ֻ����������ݵ�ַһ�µĹ���</param>
    /// <param name="AMaxTimes">�����������������<0����ȫ��</param>
    /// <returns>����ʵ���������ҵ����</returns>
    function Clear(AProc: TIocpJobProc; AData: Pointer; AMaxTimes: Integer = -1): Integer; overload;
    /// <summary>���ָ�������Ӧ����ҵ</summary>
    /// <param name="AHandle">Ҫ�������ҵ���</param>
    procedure Clear(AHandle: TIocpJobHandle); overload;

    /// <summary>Ͷ��һ����ҵ</summary>
    /// <param name="AJobProc">Ҫ��ʱִ�е���ҵ����</param>
    function Post(AJobProc: TIocpJobProc; AData: Pointer): TIocpJobHandle; overload;

    // ���������������������С��2
    property MaxWorkers: Integer read FMaxWorkers write SetMaxWorkers;
    // ��С����������������С��2
    property MinWorkers: Integer read FMinWorkers write SetMinWorkers;
    // �Ƿ�����ʼ��ҵ�����Ϊfalse����Ͷ�ĵ���ҵ�����ᱻִ�У�ֱ���ָ�ΪTrue
    // (EnabledΪFalseʱ�Ѿ����е���ҵ����Ȼ���У���ֻӰ����δִ�е�����)
    property Enabled: Boolean read GetEnabled write SetEnabled;
    // �Ƿ������ͷ�����
    property Terminating: Boolean read FTerminating;
    // ��ǰϵͳCPU����
    property CPUNum: Integer read FCPUNum;
    // ��æ�Ĺ���������
    property BusyWorkerCount: Integer read FBusyCount;
    // ��ǰ���й���������
    property IdleWorkerCount: Integer read GetIdleWorkerCount;
    // ��ǰ����������
    property WorkerCount: Integer read FWorkerCount;
    // Ĭ�Ͻ�͹����ߵĳ�ʱʱ��
    property FireTimeout: Integer read FFireTimeout write SetFireTimeout default IT_WAITJOB_TIMEOUT;
    // �����ߴ���ص�֪ͨ�¼�
    property OnError: TIocpWorkerErrorNotify read FOnError write FOnError;
  end;

  /// <summary>
  /// ���ڹ���򵥵��첽���ã�û�д���ʱ��Ҫ�����ҵ
  /// </summary>
  TIocpSimpleJobs = class(TIocpJobBase)
  private
    FFirst, FLast: PIocpJob;
    FCount: Integer;
    FLocker: TCriticalSection;
    function ClearJobs(AObject: Pointer; AProc: TIocpJobProc; AData: Pointer;
      AMaxTimes: Integer; AHandle: TIocpJobHandle = 0): Integer;
  protected
    function InternalPush(AJob: PIocpJob): Boolean; override;
    function InternalPop: PIocpJob; override;
    function GetCount: Integer; override;
  public
    constructor Create(AOwner: TIocpTask); override;
    destructor Destroy; override;
    procedure Clear; overload; override;
    function Clear(AObject: Pointer; AMaxTimes: Integer): Integer; overload; override;
    function Clear(AProc: TIocpJobProc; AData: Pointer; AMaxTimes: Integer): Integer; overload; override;
    function Clear(AHandle: TIocpJobHandle): Boolean; overload; override;
  end;

procedure ThreadYield; inline;

implementation

var
  IocpWorkers: TIocpTask = nil;  // ��Ҫʱ��ʼ����Ҳ�����Լ����壬������
  FCPUUsage: Integer = 0;        // CPUʹ����
  
type
  PJob = PIocpJob;
  TJobPool = class
  protected
    FFirst: PIocpJob;
    FCount: Integer;
    FSize: Integer;
    FLocker: TCriticalSection;
  public
    constructor Create(AMaxSize: Integer);
    destructor Destroy; override;
    procedure Push(AJob: PIocpJob);
    function Pop: PIocpJob;
    property Count: Integer read FCount;
    property Size: Integer read FSize write FSize;
  end;

type
  {$IF RTLVersion<24}
  TSystemTimes = record
    IdleTime, UserTime, KernelTime, NiceTime: UInt64;
  end;
  {$IFEND <XE5}
  TStaticThread = class(TThread)
  protected
    FOwner: TIocpTask;
    FEvent: TEvent;
    FLastTimes: {$IF RTLVersion>=25}TThread.{$IFEND >=XE5}TSystemTimes;
    procedure Execute; override;
  public
    constructor Create(AOwner: TIocpTask; CreateSuspended: Boolean); overload;
    destructor Destroy; override;
    procedure CheckNeeded;
  end;

{$IFDEF MSWINDOWS}
type
  TGetSystemTimes = function(var lpIdleTime, lpKernelTime, lpUserTime: TFileTime): BOOL; stdcall;
{$ENDIF MSWINDOWS}
var
  JobPool: TJobPool;
  {$IFNDEF NEXTGEN}
  WinGetSystemTimes: TGetSystemTimes;
  {$ENDIF}

function SameWorkerProc(const P1: TIocpJobMethod; const P2: TIocpJobProc): Boolean; inline;
begin
  Result := (P1.Code = TMethod(P2).Code) and (P1.Data = TMethod(P2).Data);
end;

procedure ThreadYield; inline;
begin
  try
    {$IFDEF MSWINDOWS}
    SwitchToThread;
    {$ELSE}
    TThread.Yield;
    {$ENDIF}
  except end;
end;

procedure SetThreadCPU(AHandle: THandle; ACpuNo: Integer);
begin
  {$IFDEF MSWINDOWS}
  SetThreadIdealProcessor(AHandle, ACpuNo);
  {$ELSE}
  // Linux/Andriod/iOS��ʱ����,XE6δ����sched_setaffinity����
  {$ENDIF}
end;

procedure ProcessAppMessage;
{$IFDEF MSWINDOWS}
var
  AMsg: MSG;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  while PeekMessage(AMsg, 0, 0, 0, PM_REMOVE) do begin
    TranslateMessage(AMsg);
    DispatchMessage(AMsg);
  end;
  {$ELSE}
  Application.ProcessMessages;
  {$ENDIF}
end;

{ TJobPool }

constructor TJobPool.Create(AMaxSize: Integer);
begin
  FCount := 0;
  FSize := AMaxSize;
  FLocker := TCriticalSection.Create;
end;

destructor TJobPool.Destroy;
var
  AJob: PIocpJob;
begin
  FLocker.Enter;
  try
    while FFirst <> nil do begin
      AJob := FFirst.Next;
      Dispose(FFirst);
      FFirst := AJob;
    end;
  finally
    FLocker.Free;
  end;
  inherited;
end;

function TJobPool.Pop: PIocpJob;
begin
  FLocker.Enter;
  Result := FFirst;
  if Result <> nil then begin
    FFirst := Result.Next;
    Dec(FCount);
  end;
  FLocker.Leave;
  if Result = nil then
    GetMem(Result, SizeOf(TIocpJob));
  Result.Reset;
end;

procedure TJobPool.Push(AJob: PIocpJob);
var
  ADoFree: Boolean;
begin
  {$IFDEF NEXTGEN}
  PJobProc(@AJob.WorkerProc)^ := nil;
  {$ENDIF}
  FLocker.Enter;
  ADoFree := (FCount = FSize);
  if not ADoFree then begin
    AJob.Next := FFirst;
    FFirst := AJob;
    Inc(FCount);
  end;
  FLocker.Leave;
  if ADoFree then
    FreeMem(AJob);
end;

{ TStaticThread }

procedure TStaticThread.CheckNeeded;
begin
  if Assigned(Self) then FEvent.SetEvent;
end;

constructor TStaticThread.Create(AOwner: TIocpTask; CreateSuspended: Boolean);
begin
  FOwner := AOwner;
  FEvent := TEvent.Create(nil, False, False, '');
  inherited Create(CreateSuspended);
  {$IFDEF MSWINDOWS}
  Priority := tpIdle;
  {$ENDIF}
end;

destructor TStaticThread.Destroy;
begin
  FreeAndNil(FEvent);
  inherited;
end;

procedure TStaticThread.Execute;
var
  ATimeout: Cardinal;

  // ����ĩ1���CPUռ���ʣ��������60%����δ�������ҵ������������Ĺ������������ҵ
  function LastCpuUsage: Integer;
  {$IFDEF MSWINDOWS}
  var
    CurSystemTimes: TSystemTimes;
    Usage, Idle: UInt64;
  {$ENDIF}
  begin
    {$IFDEF MSWINDOWS}
    Result := 0;
    if WinGetSystemTimes(PFileTime(@CurSystemTimes.IdleTime)^,
      PFileTime(@CurSystemTimes.KernelTime)^, PFileTime(@CurSystemTimes.UserTime)^)
    then begin
      Usage := (CurSystemTimes.UserTime - FLastTimes.UserTime) +
        (CurSystemTimes.KernelTime - FLastTimes.KernelTime) +
        (CurSystemTimes.NiceTime - FLastTimes.NiceTime);
      Idle := CurSystemTimes.IdleTime - FLastTimes.IdleTime;
      if Usage > Idle then
        Result := (Usage - Idle) * 100 div Usage;
      FLastTimes := CurSystemTimes;
    end;
    {$ELSE}
    Result := TThread.GetCPUUsage(FLastTimes);
    {$ENDIF}
    FCPUUsage := Result;
  end;

begin
  {$IFDEF MSWINDOWS}
  {$IFDEF UNICODE}
  NameThreadForDebugging('StaticThread');
  {$ENDIF}
  if Assigned(WinGetSystemTimes) then // Win2000/XP<SP2�ú���δ���壬����ʹ��
    ATimeout := 1000
  else
    ATimeout := INFINITE;
  {$ELSE}
  ATimeout := 1000;
  {$ENDIF}
  while not Terminated do begin
    LastCpuUsage();
    case FEvent.WaitFor(ATimeout) of
      wrSignaled:
        if Assigned(FOwner) and (not FOwner.Terminating) and (FOwner.IdleWorkerCount = 0) then
          FOwner.LookupIdleWorker(False);
      wrTimeout:
        if Assigned(FOwner) and (not FOwner.Terminating) and (Assigned(FOwner.FSimpleJobs)) and 
          (FOwner.FSimpleJobs.Count > 0) and (FCpuUsage < 60) and
          (FOwner.IdleWorkerCount = 0) then
          FOwner.LookupIdleWorker;
    end;
  end;
  FOwner.FStaticThread := nil;
end;

{ TIocpJobMethod }

function TIocpJobMethod.ToJobProc: TIocpJobProc;
begin
  {$IFDEF NEXTGEN}
  Result := PIocpJobProc(@Self)^;
  {$ELSE} 
  Result := Proc; 
  {$ENDIF}
end;

{ TIocpJob }

procedure TIocpJob.Assign(const ASource: PIocpJob);
begin
  Self := ASource^;
  // ����������Ա������
  Worker := nil;
  Next := nil;
end;

procedure TIocpJob.Create(AProc: TIocpJobProc);
begin
  {$IFDEF NEXTGEN}
  PIocpJobProc(@WorkerProc)^ := AProc;
  {$ELSE}
  WorkerProc.Proc := AProc;
  {$ENDIF}
  Flags := 0;
end;

function TIocpJob.GetElapseTime: Int64;
begin
  Result := GetTimestamp - StartTime;
end;

function TIocpJob.GetHandle: TIocpJobHandle;
begin
  Result := TIocpJobHandle(@Self);
end;

function TIocpJob.GetIsTerminated: Boolean;
begin
  if Assigned(Worker) and Assigned(Worker.FOwner) then
    Result := Worker.FOwner.Terminating or Worker.Terminated or
      ((Flags and IT_JOB_TERMINATED) <> 0) or (Worker.FTerminatingJob = @Self)
  else
    Result := (Flags and IT_JOB_TERMINATED) <> 0;
end;

function TIocpJob.GetValue(Index: Integer): Boolean;
begin
  Result := (Flags and Index) <> 0;
end;

procedure TIocpJob.Reset;
begin
  FillChar(Self, SizeOf(TIocpJob), 0);
end;

procedure TIocpJob.SetIsTerminated(const Value: Boolean);
begin
  SetValue(IT_JOB_TERMINATED, Value);
end;

procedure TIocpJob.SetValue(Index: Integer; const Value: Boolean);
begin
  if Value then
    Flags := (Flags or Index)
  else
    Flags := (Flags and (not Index));
end;

{ TIocpJobBase }

procedure TIocpJobBase.Clear;
var
  AItem: PIocpJob;
begin
  while True do begin
    AItem := Pop;
    if AItem <> nil then
      FOwner.FreeJob(AItem)
    else
      Break;
  end;
end;

constructor TIocpJobBase.Create(AOwner: TIocpTask);
begin
  FOwner := AOwner;
end;

destructor TIocpJobBase.Destroy;
begin
  Clear;
  inherited;
end;

function TIocpJobBase.GetEmpty: Boolean;
begin
  Result := (Count = 0);
end;

function TIocpJobBase.Pop: PIocpJob;
begin
  Result := InternalPop;
end;

function TIocpJobBase.Push(AJob: PIocpJob): Boolean;
begin
  AJob.Owner := Self;
  Result := InternalPush(AJob);
  if not Result then begin
    AJob.Next := nil;
    FOwner.FreeJob(AJob);
  end;
end;

{ TIocpSimpleJobs }

procedure TIocpSimpleJobs.Clear;
var
  AFirst: PJob;
begin
  FLocker.Enter;
  AFirst := FFirst;
  FFirst := nil;
  FLast := nil;
  FCount := 0;
  FLocker.Leave;
  FOwner.FreeJob(AFirst);
end;

function TIocpSimpleJobs.Clear(AObject: Pointer; AMaxTimes: Integer): Integer;
begin
  Result := ClearJobs(AObject, nil, nil, AMaxTimes);
end;

function TIocpSimpleJobs.Clear(AProc: TIocpJobProc; AData: Pointer;
  AMaxTimes: Integer): Integer;
begin
  Result := ClearJobs(nil, AProc, AData, AMaxTimes);
end;

function TIocpSimpleJobs.Clear(AHandle: TIocpJobHandle): Boolean;
begin
  if AHandle <> 0 then
    Result := ClearJobs(nil, nil, nil, -1, AHandle) > 0
  else
    Result := False;
end;

function TIocpSimpleJobs.ClearJobs(AObject: Pointer; AProc: TIocpJobProc;
  AData: Pointer; AMaxTimes: Integer; AHandle: TIocpJobHandle): Integer;
var
  AFirst, AJob, APrior, ANext: PJob;
  ACount: Integer;
  b: Boolean;
begin
  FLocker.Enter;     // �Ƚ����е��첽��ҵ��գ��Է�ֹ������ִ��
  AJob := FFirst;
  ACount := FCount;
  FFirst := nil;
  FLast := nil;
  FCount := 0;
  FLocker.Leave;

  Result := 0;
  APrior := nil;
  AFirst := nil;
  while (AJob <> nil) and (AMaxTimes <> 0) do begin
    ANext := AJob.Next;
    if AObject <> nil then
      b := AJob.WorkerProc.Data = AObject
    else if AHandle > 0 then
      b := TIocpJobHandle(AJob) = AHandle
    else
      b := SameWorkerProc(AJob.WorkerProc, AProc) and (AJob.Data = AData);
    if b then begin
      if APrior <> nil then
        APrior.Next := ANext
      else //�׸�
        AFirst := ANext;
      FOwner.FreeJob(AJob);
      Dec(AMaxTimes);
      Inc(Result);
      Dec(ACount);
      if TIocpJobHandle(AJob) = AHandle then
        Break;
    end else begin
      if AFirst = nil then
        AFirst := AJob;
      APrior := AJob;
    end;
    AJob := ANext;
  end;
  if ACount > 0 then begin
    FLocker.Enter;
    if AFirst <> nil then 
      AFirst.Next := FFirst;
    FFirst := AFirst;
    Inc(FCount, ACount);
    if FLast = nil then
      FLast := APrior;
    FLocker.Leave;
  end;
end;

constructor TIocpSimpleJobs.Create(AOwner: TIocpTask);
begin
  inherited Create(AOwner);
  FLocker := TCriticalSection.Create;
end;

destructor TIocpSimpleJobs.Destroy;
begin
  inherited;
  FLocker.Free;
end;

function TIocpSimpleJobs.GetCount: Integer;
begin
  Result := FCount;
end;

function TIocpSimpleJobs.InternalPop: PJob;
begin
  FLocker.Enter;
  Result := FFirst;
  if Result <> nil then begin
    FFirst := Result.Next;
    if FFirst = nil then
      FLast := nil;
    Dec(FCount);
  end;
  FLocker.Leave;
  if Result <> nil then
    Result.Next := nil;
end;

function TIocpSimpleJobs.InternalPush(AJob: PJob): Boolean;
begin
  FLocker.Enter;
  if FLast = nil then
    FFirst := AJob
  else
    FLast.Next := AJob;
  FLast := AJob;
  Inc(FCount);
  FLocker.Leave;
  Result := true;
end;

{ TIocpTask }

function TIocpTask.Clear(AProc: TIocpJobProc; AData: Pointer;
  AMaxTimes: Integer): Integer;
begin
  Result := ClearJobs(nil, AProc, AData, AMaxTimes);
end;

procedure TIocpTask.Clear(AHandle: TIocpJobHandle);
var
  AInstance: PJob;
  AWaitParam: TIocpWorkerWaitParam;
  Wait: Boolean;
begin
  if AHandle = 0 then Exit;
  AInstance := Pointer(AHandle and (not $03));
  Wait := FSimpleJobs.Clear(AHandle); // SimpleJobs
  if not Wait then Exit;
  FillChar(AWaitParam, SizeOf(TIocpWorkerWaitParam), 0);
  AWaitParam.SourceJob := AInstance;
  if (AHandle and $03) = 0 then
    AWaitParam.WaitType := 4
  else
    AWaitParam.WaitType := 2;
  WaitRunningDone(AWaitParam);
end;

function TIocpTask.ClearJobs(AObject: Pointer; AProc: TIocpJobProc; AData: Pointer;
  AMaxTimes: Integer): Integer;
var
  ACleared: Integer;
  AWaitParam: TIocpWorkerWaitParam;
begin
  Result := 0;
  if Self <> nil then begin
    ACleared := FSimpleJobs.ClearJobs(AObject, AProc, AData, AMaxTimes);
    Inc(Result, ACleared);
    Dec(AMaxTimes, ACleared);
    if AMaxTimes <> 0 then begin
      if AObject <> nil then begin
        AWaitParam.WaitType := 0;
        AWaitParam.Bound := AObject;
      end else begin
        AWaitParam.WaitType := 1;
        AWaitParam.Data := AData;
        AWaitParam.WorkerProc := TMethod(AProc);
      end;
      WaitRunningDone(AWaitParam);
    end;
  end;  
end;

{$IFNDEF UNICODE}
type
  TThreadId = Cardinal;
{$ENDIF}
procedure TIocpTask.ClearWorkers;
var
  i: Integer;
  AInMainThread: Boolean;

  {$IFDEF MSWINDOWS}
  function ThreadExists(AId: TThreadId): Boolean;
  var
    ASnapshot: THandle;
    AEntry: TThreadEntry32;
  begin
    Result := False;
    ASnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if ASnapshot = INVALID_HANDLE_VALUE then
      Exit;
    try
      AEntry.dwSize := SizeOf(TThreadEntry32);
      if Thread32First(ASnapshot, AEntry) then begin
        repeat
          if AEntry.th32ThreadID = AId then begin
            Result := true;
            Break;
          end;
        until not Thread32Next(ASnapshot, AEntry);
      end;
    finally
      CloseHandle(ASnapshot);
    end;
  end;
  {$ENDIF}

  {$IFDEF MSWINDOWS}
  function WorkerExists: Boolean;
  var
    J: Integer;
  begin
    Result := False;
    FLocker.Enter;
    try
      J := FWorkerCount - 1;
      while J >= 0 do begin
        if ThreadExists(FWorkers[J].ThreadID) then begin
          Result := true;
          Break;
        end;
        Dec(J);
      end;
    finally
      FLocker.Leave;
    end;
  end;
  {$ENDIF}
var
  T: Int64;
begin
  FTerminating := True;
  FLocker.Enter;
  try
    for i := 0 to FWorkerCount - 1 do
      FWorkers[i].FEvent.SetEvent;
  finally
    FLocker.Leave;
  end;
  T := GetTimestamp;
  AInMainThread := GetCurrentThreadId = MainThreadId;
  while (FWorkerCount > 0) {$IFDEF MSWINDOWS} and WorkerExists {$ENDIF} do begin
    if AInMainThread and (not FIsDestroying) then
      ProcessAppMessage;
    if GetTimestamp - T > 15000 then
      Break;
    Sleep(10);
  end;
  for i := 0 to FWorkerCount - 1 do begin
    if FWorkers[i] <> nil then
      FreeAndNil(FWorkers[i]);
  end;
  FWorkerCount := 0;
end;

procedure TIocpTask.Clear;
var
  AParam: TIocpWorkerWaitParam;
begin
  DisableWorkers; // ���⹤����ȡ���µ���ҵ
  try
    FSimpleJobs.Clear;
    AParam.WaitType := $FF;
    WaitRunningDone(AParam);
  finally
    EnableWorkers;
  end;
end;

function TIocpTask.Clear(AObject: Pointer; AMaxTimes: Integer): Integer;
begin
  Result := ClearJobs(AObject, nil, nil, AMaxTimes);
end;

constructor TIocpTask.Create(AMinWorkers: Integer);
var
  i: Integer;
begin
  FBusyCount := 0;
  FFireTimeout := IT_WAITJOB_TIMEOUT;
  FSimpleJobs := TIocpSimpleJobs.Create(Self);
  FLocker := TCriticalSection.Create;

  FCPUNum := GetCPUCount;
  if AMinWorkers < 1 then
    FMinWorkers := 2
  else
    FMinWorkers := AMinWorkers; // ���ٹ�����Ϊ2��
  FMaxWorkers := (FCPUNum shl 2) + 1;
  if FMaxWorkers <= FMinWorkers then
    FMaxWorkers := (FMinWorkers shl 1) + 1;
  FTerminating := False;

  // ����Ĭ�Ϲ�����
  FDisableCount := 0;
  FWorkerCount := 0;
  SetLength(FWorkers, FMaxWorkers + 1);
  for i := 0 to FMinWorkers - 1 do 
    FWorkers[i] := CreateWorker(True);
  for i := 0 to FMinWorkers - 1 do begin
    FWorkers[i].FEvent.SetEvent;
    FWorkers[i].Suspended := False;
  end;
  FStaticThread := TStaticThread.Create(Self, True);
  FStaticThread.Suspended := False;
  //FStaticThread.Resume;
end;

function TIocpTask.CreateWorker(ASuspended: Boolean): TIocpTaskWorker;
begin
  if FWorkerCount < FMaxWorkers then begin
    Result := TIocpTaskWorker.Create(Self);
    FWorkers[FWorkerCount] := Result;
    {$IFDEF MSWINDOWS}
    SetThreadCPU(Result.Handle, FWorkerCount mod FCPUNum);
    {$ELSE}
    SetThreadCPU(Result.ThreadId, FWorkerCount mod FCPUNum);
    {$ENDIF}
    Inc(FWorkerCount);
    if not ASuspended then begin
      Result.FPending := true;
      Result.FEvent.SetEvent;
      Result.Suspended := False;
    end;
  end else
    Result := nil;
end;

destructor TIocpTask.Destroy;
var
  T: Int64;
begin
  FIsDestroying := True;
  ClearWorkers;
  FLocker.Enter;
  try
    FreeAndNil(FSimpleJobs);
  finally
    FLocker.Free;
  end;
  FStaticThread.FreeOnTerminate := True;
  FStaticThread.Terminate;
  TStaticThread(FStaticThread).FEvent.SetEvent;
  ThreadYield;
  T := GetTimestamp;
  while Assigned(FStaticThread) and (GetTimestamp - T < 6000) do
    Sleep(20);
  try
    if Assigned(FStaticThread) then
      FreeAndNil(FStaticThread);
  except
    {$IFNDEF NEXTGEN}OutputDebugString(PChar(Exception(ExceptObject).Message));{$ENDIF}
  end;
  inherited;
end;

procedure TIocpTask.DisableWorkers;
begin
  AtomicIncrement(FDisableCount);
end;

procedure TIocpTask.EnableWorkers;
var
  ANeedCount: Integer;
begin
  if AtomicDecrement(FDisableCount) = 0 then begin
    if (FSimpleJobs.Count > 0) then begin
      ANeedCount := FSimpleJobs.Count;
      while ANeedCount > 0 do begin
        if not LookupIdleWorker then
          Break;
        Dec(ANeedCount);
      end;
    end;
  end;
end;

procedure TIocpTask.FreeJob(AJob: PJob);
var
  ANext: PJob;
begin
  while AJob <> nil do begin
    ANext := AJob.Next;
    JobPool.Push(AJob);
    AJob := ANext;
  end;
end;

class function TIocpTask.GetCPUUsage: Integer;
begin
  Result := FCPUUsage;
end;

function TIocpTask.GetEnabled: Boolean;
begin
  Result := (FDisableCount = 0);
end;

function TIocpTask.GetIdleWorkerCount: Integer;
begin
  Result := FWorkerCount - FBusyCount;
end;

class function TIocpTask.GetInstance: TIocpTask;
begin
  if not Assigned(IocpWorkers) then
    IocpWorkers := TIocpTask.Create();
  Result := IocpWorkers;
end;

class function TIocpTask.JobPoolCount: Integer;
begin
  Result := JobPool.Count;
end;

function TIocpTask.LookupIdleWorker(AFromSimple: Boolean): Boolean;
var
  AWorker: TIocpTaskWorker;
  i: Integer;
begin
  Result := False;
  if (FBusyCount >= FMaxWorkers) or ((FDisableCount <> 0) or FTerminating) then
    Exit;

  // ��������ڽ�͵Ĺ����ߣ���ô�ȴ����
  while FFiringWorkerCount > 0 do
    ThreadYield;
    
  AWorker := nil;
  FLocker.Enter;
  try
    for i := 0 to FWorkerCount - 1 do begin
      if (FWorkers[i].IsIdle) and (FWorkers[i].IsRunning) and
        (not(FWorkers[i].IsFiring or FWorkers[i].FPending)) then
      begin
        AWorker := FWorkers[i];
        AWorker.FPending := true;
        AWorker.FEvent.SetEvent;
        Break;
      end;
    end;
    if (AWorker = nil) then
      AWorker := CreateWorker(False);
  finally
    FLocker.Leave;
  end;
  Result := AWorker <> nil;
  if Result then
    ThreadYield;
end;

procedure TIocpTask.NewWorkerNeeded;
begin
  TStaticThread(FStaticThread).CheckNeeded;
end;

function TIocpTask.Popup: PJob;
begin
  Result := FSimpleJobs.Pop;
end;

function TIocpTask.Post(AJobProc: TIocpJobProc; AData: Pointer): TIocpJobHandle;
var
  AJob: PJob;
begin
  AJob := JobPool.Pop;
  {$IFDEF NEXTGEN}
  PIocpJobProc(@AJob.WorkerProc)^ := AJobProc;
  {$ELSE}
  AJob.WorkerProc.Proc := AJobProc;
  {$ENDIF}
  AJob.Data := AData;
  AJob.Flags := 0;
  Result := Post(AJob);
end;

function TIocpTask.Post(AJob: PJob): TIocpJobHandle;
begin
  Result := 0;
  if not Assigned(Self) then Exit;
  if (not FTerminating) and (Assigned(AJob.WorkerProc.Proc)
    {$IFDEF UNICODE} or Assigned(AJob.WorkerProc.ProcA){$ENDIF}) then
  begin
    if FSimpleJobs.Push(AJob) then begin
      Result := TIocpJobHandle(AJob);
      LookupIdleWorker(True);
    end;
  end else begin
    AJob.Next := nil;
    FreeJob(AJob);
  end;
end;

procedure TIocpTask.SetEnabled(const Value: Boolean);
begin
  if Value then
    EnableWorkers
  else
    DisableWorkers;
end;

procedure TIocpTask.SetFireTimeout(const Value: Integer);
begin
  if Value <= 0 then
    FFireTimeout := MaxInt
  else
    FFireTimeout := Value;
end;

procedure TIocpTask.SetMaxWorkers(const Value: Integer);
begin
  if (Value >= 2) and (FMaxWorkers <> Value) then begin
    FLocker.Enter;
    try
      if FMaxWorkers < Value then begin
        FMaxWorkers := Value;
        SetLength(FWorkers, Value + 1);
      end;
    finally
      FLocker.Leave;
    end;
  end;
end;

procedure TIocpTask.SetMinWorkers(const Value: Integer);
begin
  if FMinWorkers <> Value then begin
    if Value < 1 then
      raise Exception.Create(STooFewWorkers);
    FMinWorkers := Value;
  end;
end;

procedure TIocpTask.WaitRunningDone(const AParam: TIocpWorkerWaitParam);
var
  AInMainThread: Boolean;

  function HasJobRunning: Boolean;
  var
    i: Integer;
    AJob: PJob;
  begin
    Result := False;
    DisableWorkers;
    FLocker.Enter;
    try
      for i := 0 to FWorkerCount - 1 do begin
        if FWorkers[i].IsLookuping then begin// ��δ�������������´β�ѯ
          Continue;
        end else if FWorkers[i].IsExecuting then begin
          AJob := FWorkers[i].FActiveJob;
          case AParam.WaitType of
            0: // ByObject
              Result := TMethod(FWorkers[i].FActiveJobProc).Data = AParam.Bound;
            1: // ByData
              Result := (TMethod(FWorkers[i].FActiveJobProc).Code = TMethod(AParam.WorkerProc).Code) and
                (TMethod(FWorkers[i].FActiveJobProc).Data = TMethod(AParam.WorkerProc).Data) and
                ((AParam.Data = nil) or (AParam.Data = Pointer(-1)) or
                (FWorkers[i].FActiveJobData = AParam.Data));
            2: // BySignalSource
              Result := (FWorkers[i].FActiveJobSource = AParam.SourceJob);
            $FF: // ����
              Result := True;
          else 
            begin
              if Assigned(FOnError) then
                FOnError(AJob, Exception.CreateFmt(SBadWaitDoneParam, [AParam.WaitType]), jesWaitDone)
              else
                raise Exception.CreateFmt(SBadWaitDoneParam, [AParam.WaitType]);
            end;
          end;
          if Result then
            FWorkers[i].FTerminatingJob := AJob;
        end;
      end;
    finally
      FLocker.Leave;
      EnableWorkers;
    end;
  end;

begin
  AInMainThread := GetCurrentThreadId = MainThreadId;
  while True do begin
    if HasJobRunning then begin
      if AInMainThread then
        // ����������߳�������������ҵ���������߳�ִ�У������Ѿ�Ͷ����δִ�У����Ա��������ܹ�ִ��
        ProcessAppMessage;
      Sleep(10);
    end else // û�ҵ�
      Break;
  end;
end;

procedure TIocpTask.WorkerTerminate(AWorker: TIocpTaskWorker);
var
  i, J: Integer;
begin
  FLocker.Enter;
  try
    Dec(FWorkerCount);
    if AWorker.IsFiring then
      AtomicDecrement(FFiringWorkerCount);
    if FWorkerCount = 0 then
      FWorkers[0] := nil
    else begin
      for i := 0 to FWorkerCount do begin
        if AWorker = FWorkers[i] then begin
          for J := i to FWorkerCount do
            FWorkers[J] := FWorkers[J + 1];
          Break;
        end;
      end;
    end;
  finally
    FLocker.Leave;
  end;
end;

procedure TIocpTask.WorkerTimeout(AWorker: TIocpTaskWorker);
begin
  if FWorkerCount - AtomicIncrement(FFiringWorkerCount) < FMinWorkers then
    AtomicDecrement(FFiringWorkerCount)
  else begin
    AWorker.SetValue(IT_WORKER_FIRING, true);
    AWorker.Terminate;
  end;
end;

{ TIocpTaskWorker }

procedure TIocpTaskWorker.ComNeeded(AInitFlags: Cardinal);
begin
  {$IFDEF MSWINDOWS}
  if not ComInitialized then begin
    if AInitFlags = 0 then
      CoInitialize(nil)
    else
      CoInitializeEx(nil, AInitFlags);
    SetValue(IT_WORKER_COM_INITED, True);
  end;
  {$ENDIF MSWINDOWS}
end;

constructor TIocpTaskWorker.Create(AOwner: TIocpTask);
begin
  inherited Create(True);
  FOwner := AOwner;
  FTimeout := 1000;
  {$IFDEF SAVE_WORDER_TIME}
  FStartTime := GetTimestamp;
  FLastExecTime := 0;
  {$ENDIF}
  FEvent := TEvent.Create(nil, False, False, '');
  FreeOnTerminate := True;
end;

destructor TIocpTaskWorker.Destroy;
begin
  FreeAndNil(FEvent);
  inherited;
end;

procedure TIocpTaskWorker.DoJob(AJob: PJob);
begin
  {$IFDEF SAVE_WORDER_TIME}
  FLastExecTime := 0;
  {$ENDIF}
  {$IFDEF NEXTGEN}
  PJobProc(@AJob.WorkerProc)^(AJob)
  {$ELSE}
  AJob.WorkerProc.Proc(AJob);
  {$ENDIF}
  {$IFDEF SAVE_WORDER_TIME}
  FLastExecTime := GetTimestamp;
  {$ENDIF}
end;

procedure TIocpTaskWorker.Execute;
var
  wr: TWaitResult;
  {$IFDEF MSWINDOWS}
  SyncEvent: TEvent;
  {$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  SyncEvent := TEvent.Create(nil, False, False, '');
  {$IFDEF UNICODE}
  NameThreadForDebugging('YXDWorker');
  {$ENDIF}
  {$ENDIF}
  try
    SetValue(IT_WORKER_RUNNING, true);
    while not(Terminated or FOwner.FTerminating) do begin

      if FOwner.Enabled then begin
        if (FOwner.FSimpleJobs.FFirst <> nil) then begin
          wr := WaitSignal(0)
        end else
          wr := WaitSignal(FOwner.FFireTimeout);
      end else
        wr := WaitSignal(FOwner.FFireTimeout);

      if Terminated or FOwner.FTerminating then
        Break;

      if wr = wrSignaled then begin          
        if FOwner.FTerminating then
          Break;
          
        SetValue(IT_WORKER_LOOKUP or IT_WORKER_ISBUSY, true);
        FPending := False;

        if (FOwner.WorkerCount - AtomicIncrement(FOwner.FBusyCount) = 0) and
          (FOwner.WorkerCount < FOwner.MaxWorkers) then
          FOwner.NewWorkerNeeded;

        repeat
          FActiveJob := FOwner.Popup;
          if FActiveJob <> nil then begin
            FTimeout := 0;
            FActiveJob.Worker := Self;
            FActiveJobProc := FActiveJob^.WorkerProc.ToJobProc();

            // ΪClear(AObject)׼���жϣ��Ա���FActiveJob�̲߳���ȫ
            FActiveJobData := FActiveJob.Data;
            FActiveJobFlags := FActiveJob.Flags;
            FActiveJobSource := nil;
            FActiveJob.StartTime := GetTimestamp;

            try
              FFlags := (FFlags or IT_WORKER_EXECUTING) and (not IT_WORKER_LOOKUP);
              DoJob(FActiveJob);
            except
              on E: Exception do
                if Assigned(FOwner.FOnError) then
                  FOwner.FOnError(FActiveJob, E, jesExecute);
            end;
            
            Inc(FProcessed);
            FActiveJob.Worker := nil;
            
            FOwner.FreeJob(FActiveJob);
            FActiveJobProc := nil;
            FActiveJobFlags := 0;
            FTerminatingJob := nil;
            FFlags := FFlags and (not IT_WORKER_EXECUTING);

          end else
            FFlags := FFlags and (not IT_WORKER_LOOKUP);
            
        until (FActiveJob = nil) or Terminated or FOwner.FTerminating or
          (not FOwner.Enabled);

        SetValue(IT_WORKER_ISBUSY, False);
        AtomicDecrement(FOwner.FBusyCount);
        ThreadYield;
      end else begin
        if (FTimeout >= FOwner.FireTimeout) then
          FOwner.WorkerTimeout(Self);
      end;
    end;
  finally
    SetValue(IT_WORKER_RUNNING, False);
    {$IFDEF MSWINDOWS}
    FreeAndNil(SyncEvent);
    if ComInitialized then
      CoUninitialize;
    {$ENDIF}
    //OutputDebugString(PChar('Worker '+IntToStr(ThreadID)+' Done'));
    FOwner.WorkerTerminate(Self);
  end;
end;

function TIocpTaskWorker.GetIsIdle: Boolean;
begin
  Result := not IsBusy;
end;

function TIocpTaskWorker.GetValue(Index: Integer): Boolean;
begin
  Result := (FFlags and Index) <> 0;
end;

procedure TIocpTaskWorker.SetValue(Index: Integer; const Value: Boolean);
begin
  if Value then
    FFlags := (FFlags or Index)
  else
    FFlags := (FFlags and (not Index));
end;

function TIocpTaskWorker.WaitSignal(ATimeout: Integer): TWaitResult;
var
  T: Int64;
begin
  if ATimeout > 1 then begin
    T := GetTimestamp;
    Result := FEvent.WaitFor(ATimeout);
    Inc(FTimeout, GetTimestamp - T);
  end else
    Result := wrSignaled;
end;

initialization
  {$IFNDEF NEXTGEN}
  WinGetSystemTimes := GetProcAddress(GetModuleHandle(kernel32), 'GetSystemTimes');
  {$ENDIF}
  JobPool := TJobPool.Create(1024);
  IocpWorkers := TIocpTask.Create(4);
  IocpWorkers.MaxWorkers := 1024;

finalization
  try
    if Assigned(IocpWorkers) then
      FreeAndNil(IocpWorkers);
  except
    {$IFNDEF NEXTGEN}OutputDebugString(PChar(Exception(ExceptObject).Message));{$ENDIF}
  end;
  if Assigned(JobPool) then FreeAndNil(JobPool);

end.

