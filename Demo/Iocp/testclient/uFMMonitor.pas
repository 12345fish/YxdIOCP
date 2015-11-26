unit uFMMonitor;

interface

{$I 'iocp.inc'}

uses
  YxdCommon,
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms, 
  Dialogs, iocp.Sockets, StdCtrls, ExtCtrls, psApi;

type
  TFMMonitor = class(TFrame)
    lblServerStateCaption: TLabel;
    tmrReader: TTimer;
    lblsvrState: TLabel;
    lblRecvCaption: TLabel;
    lblPostRecvINfo: TLabel;
    lblSendCaption: TLabel;
    lblSend: TLabel;
    lblAcceptExCaption: TLabel;
    lblAcceptEx: TLabel;
    lblRunTimeINfo: TLabel;
    lblWorkersCaption: TLabel;
    lblWorkerCount: TLabel;
    lblRunTimeCaption: TLabel;
    lblRecvdSize: TLabel;
    lblSentSize: TLabel;
    lblSendQueue: TLabel;
    lblSendingQueueCaption: TLabel;
    lblSocketHandle: TLabel;
    lblSocketHandleCaption: TLabel;
    lblContextInfo: TLabel;
    lblContextInfoCaption: TLabel;
    lblSendRequest: TLabel;
    lblSendRequestCaption: TLabel;
    lblPCInfo: TLabel;
    lblDEBUG_ON: TLabel;
    procedure lblRecvCaptionDblClick(Sender: TObject);
    procedure lblWorkerCountClick(Sender: TObject);
    procedure tmrReaderTimer(Sender: TObject);
    procedure RefreshState;
  private
    FIocpTcpServer: TiocpCustom;
    procedure Translate();
  public
    class function CreateAsChild(pvParent: TWinControl; pvIOCPTcpServer:
        TiocpCustom): TFMMonitor;
    property IocpTcpManager: TiocpCustom read FIocpTcpServer write FIocpTcpServer;
  end;

implementation

{$R *.dfm}

resourcestring
  strState_Caption = '����״̬';
  strRecv_Caption  = '������Ϣ';
  strSend_Caption  = '������Ϣ';
  strSendQueue_Caption    = '���Ͷ���';
  strSendRequest_Caption  = '�����������';
  strSocketHandle_Caption = '�׽��־��';
  strAcceptEx_Caption     = 'AcceptEx��Ϣ';
  strContext_Caption      = '������Ϣ';
  strOnline_Caption       = '������Ϣ';
  strWorkers_Caption      = '�����߳�';
  strRunTime_Caption      = '������Ϣ';
  strDebugON_Caption      = '*����ģʽ';
  

  strState_Active      = '����';
  strState_MonitorNull = 'û�д��������';
  strState_ObjectNull  = 'û�м�ض���';    //'iocp server is null'
  strState_Off         = '�ر�';
  strRecv_PostInfo     = 'Ͷ��:%d, ��Ӧ:%d, ʣ��:%d';  //post:%d, response:%d, remain:%d
  strSend_Info         = 'Ͷ��:%d, ��Ӧ:%d, ʣ��:%d';  //post:%d, response:%d, remain:%d
  strSendQueue_Info    = 'ѹ��/����/���/��ֹ:%d, %d, %d, %d';//push/pop/complted/abort:%d, %d, %d, %d
  strSendRequest_Info  = '����:%d, ���:%d, ����:%d';  //'create:%d, out:%d, return:%d'
  strAcceptEx_Info     = '����:%d, Ͷ��:%d, ��Ӧ:%d';      //'post:%d, response:%d'
  strSocketHandle_Info = '����:%d, ����:%d';  //'create:%d, destroy:%d'
  strContext_Info      = '����:%d, ���:%d, ����:%d';  //'create:%d, out:%d, return:%d'
  strMemory_info       = '��������(�ڴ�): %s';

class function TFMMonitor.CreateAsChild(pvParent: TWinControl; pvIOCPTcpServer:
    TiocpCustom): TFMMonitor;
begin
  Result := TFMMonitor.Create(pvParent.Owner);
  Result.Translate;
  Result.Parent := pvParent;
  Result.Align := alClient;
  Result.IocpTcpManager := pvIOCPTcpServer;
  Result.tmrReader.Enabled := True;
  Result.RefreshState;
  {$IFDEF DEBUG_ON}
  Result.lblDEBUG_ON.Visible := true;
  {$ELSE}
  Result.lblDEBUG_ON.Visible := false;
  {$ENDIF}
   
end;

procedure TFMMonitor.lblRecvCaptionDblClick(Sender: TObject);
begin
  FIocpTcpServer.Moniter.Clear;
end;

procedure TFMMonitor.lblWorkerCountClick(Sender: TObject);
begin
  if IocpTcpManager <> nil then
  begin
    ShowMessage(IocpTcpManager.Engine.getStateInfo);
  end;
end;

procedure TFMMonitor.tmrReaderTimer(Sender: TObject);
begin
  RefreshState;
end;

procedure TFMMonitor.Translate;
begin
  lblServerStateCaption.Caption := strState_Caption;
  lblRecvCaption.Caption := strRecv_Caption;
  lblSendCaption.Caption := strSend_Caption;
  lblSendingQueueCaption.Caption := strSendQueue_Caption;
  lblSendRequestCaption.Caption := strSendRequest_Caption;
  lblRunTimeCaption.Caption := strRunTime_Caption;
  lblAcceptExCaption.Caption := strAcceptEx_Caption;
  lblSocketHandleCaption.Caption := strSocketHandle_Caption;
  lblContextInfoCaption.Caption := strContext_Caption;
  lblWorkersCaption.Caption := strWorkers_Caption;
  lblDEBUG_ON.Caption := strDebugON_Caption;
end;

// qsl
// δ����
function GetAddressSpaceUsed: Cardinal;
var
  LMemoryStatus: TMemoryStatus;
begin
  {Set the structure size}
  LMemoryStatus.dwLength := SizeOf(LMemoryStatus);
  {Get the memory status}
  GlobalMemoryStatus(LMemoryStatus);
  {The result is the total address space less the free address space}
  Result := (LMemoryStatus.dwTotalVirtual - LMemoryStatus.dwAvailVirtual) shr 10;
end;

function GetProcessMemUse(PID: Cardinal): Cardinal;
var
  pmc: _PROCESS_MEMORY_COUNTERS; //uses psApi
  ProcHandle: HWND;
  iSize: DWORD;
begin
  Result := 0;
  iSize := SizeOf(_PROCESS_MEMORY_COUNTERS);
  pmc.cb := iSize;
  ProcHandle := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_READ, False, PID); //��PIDȡ�ý��̶���ľ��
  if GetProcessMemoryInfo(ProcHandle, @pmc, iSize) then
    Result := pmc.WorkingSetSize;
  CloseHandle(ProcHandle);  
end;




procedure TFMMonitor.RefreshState;
begin
  if FIocpTcpServer = nil then
  begin
    lblsvrState.Caption := strState_ObjectNull;
    exit;
  end;

  if FIocpTcpServer.Moniter = nil then
  begin
    lblsvrState.Caption := strState_MonitorNull;
    exit;
  end;

  if FIocpTcpServer.Active then
  begin
    lblsvrState.Caption := strState_Active;
  end else
  begin
    lblsvrState.Caption := strState_Off;
  end;


  lblPostRecvINfo.Caption :=   Format(strRecv_PostInfo,
     [
       FIocpTcpServer.Moniter.PostWSARecvCounter,
       FIocpTcpServer.Moniter.ResponseWSARecvCounter,
       FIocpTcpServer.Moniter.PostWSARecvCounter -
       FIocpTcpServer.Moniter.ResponseWSARecvCounter
     ]
    );

  lblRecvdSize.Caption := TransByteSize(FIocpTcpServer.Moniter.RecvSize);


//  Format('post:%d, response:%d, recvd:%d',
//     [
//       FIocpTcpServer.DataMoniter.PostWSARecvCounter,
//       FIocpTcpServer.DataMoniter.ResponseWSARecvCounter,
//       FIocpTcpServer.DataMoniter.RecvSize
//     ]
//    );

  lblSend.Caption := Format(strSend_Info,
     [
       FIocpTcpServer.Moniter.PostWSASendCounter,
       FIocpTcpServer.Moniter.ResponseWSASendCounter,
       FIocpTcpServer.Moniter.PostWSASendCounter - FIocpTcpServer.Moniter.ResponseWSASendCounter
     ]
    );

  lblSendRequest.Caption := Format(strSendRequest_Info,
     [
       FIocpTcpServer.Moniter.SendRequestCreateCounter,
       FIocpTcpServer.Moniter.SendRequestOutCounter,
       FIocpTcpServer.Moniter.SendRequestReturnCounter
     ]
    );

  lblSendQueue.Caption := Format(strSendQueue_Info,
     [
       FIocpTcpServer.Moniter.PushSendQueueCounter,
       FIocpTcpServer.Moniter.PostSendObjectCounter,
       FIocpTcpServer.Moniter.ResponseSendObjectCounter,
       FIocpTcpServer.Moniter.SendRequestAbortCounter
     ]
    );
  lblSentSize.Caption := transByteSize(FIocpTcpServer.Moniter.SentSize);


  lblAcceptEx.Caption := Format(strAcceptEx_Info,
     [
       FIocpTcpServer.Moniter.AcceptExObjectCounter,
       FIocpTcpServer.Moniter.PostWSAAcceptExCounter,
       FIocpTcpServer.Moniter.ResponseWSAAcceptExCounter
     ]
    );

  lblSocketHandle.Caption := Format(strSocketHandle_Info,
     [
       FIocpTcpServer.Moniter.HandleCreateCounter,
       FIocpTcpServer.Moniter.HandleDestroyCounter
     ]
    );

  lblContextInfo.Caption := Format(strContext_Info,
     [
       FIocpTcpServer.Moniter.ContextCreateCounter,
       FIocpTcpServer.Moniter.ContextOutCounter,
       FIocpTcpServer.Moniter.ContextReturnCounter


     ]
    );
  
  lblWorkerCount.Caption := Format('%d', [FIocpTcpServer.WorkerCount]);


  lblRunTimeINfo.Caption := GetRunTimeINfo;

  lblPCInfo.Caption := Format(strMemory_info,
        [YxdCommon.RollupSize(GetProcessMemUse(GetCurrentProcessId))]
        //[GetAddressSpaceUsed / 1.0]
        );
end;

end.
