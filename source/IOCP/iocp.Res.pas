unit iocp.Res;

interface

const
  BytePerKB = 1024;
  BytePerMB = BytePerKB * 1024;
  BytePerGB = BytePerMB * 1024;

const
  IOCP_CORE_LOG_FILE = 'Iocp_Core_Exception';
  IOCP_CORE_DEBUG_FILE = 'Iocp_Core_Debug'; 

resourcestring
  strEngine_DebugInfo   = 'State: %s, Workers: %d';
  strEngine_WorkerTitle = '------------------- Worker Thread (%d) -------------------';
  strWorker_Done        = 'Work done!!!';
  strWorker_Info        = 'ThreadID: %d, ResponeCount: %d';
  strWorker_StateInfo   = 'Working: %s, Waiting: %s, Reserved: %s';
  strRequest_Title      = 'Request State Info:';
  strRequest_State      = 'Finished: %s, Time(ms): %d';

  strSocket_ConnActived = 'On DoConnected event is already actived.';
  strSocket_ConnError   = 'On DoConnected error: %s.';
  strSocket_RSError     = 'Read-only data flow';
  strSocket_RSNotSup    = 'This operation is not supported';

  strConn_CounterInc    = 'ContextCounter: +(%d):0x%.8x, %s';
  strConn_CounterDec    = 'ContextCounter: -(%d):0x%.8x, %s';
  strConn_CounterView   = 'ContextCounter: *(%d):0x%.8x, %s';

  strSend_PushFail  = '[0x%.4x]Ͷ�ݷ����������ݰ����������������󳤶�[%d/%d]��';
  strSend_ReqKick   = '(0x%.4x)�Ͽ�������Ϣ: %s';
  strRecv_EngineOff = '[0x%.4x]��Ӧ��������ʱ����IOCP����ر�';
  strRecv_Error     = '[0x%.4x]��Ӧ��������ʱ�����˴��󡣴������:%d!';
  strRecv_Zero      = '[0x%.4x]���յ�0�ֽڵ�����,�����ӽ��Ͽ�!';
  strRecv_PostError = '[0x%.4x]Ͷ�ݽ�������ʱ�����˴��󡣴������:%d!';
  strSend_Zero      = '[0x%.4x]Ͷ�ݷ�����������ʱ����0�������ݡ����йرմ���';
  strSend_EngineOff = '[0x%.4x]��Ӧ������������ʱ����IOCP����ر�';
  strSend_Err       = '[0x%.4x]��Ӧ������������ʱ�����˴��󡣴������:%d!';
  strSend_PostError = '[0x%.4x]Ͷ�ݷ�����������ʱ�����˴��󡣴������:%d';
  strConn_Request   = '��������%s(%d)';
  strConn_TimeOut   = '�������ӳ�ʱ(%s:%d)';
  strBindingIocpError = '[%d]�󶨵�IOCP���ʱ�������쳣, �������:%d, (%s)';

  STooFewWorkers = 'ָ������С����������̫��(������ڵ���1)��';   
  SBadWaitDoneParam = 'δ֪�ĵȴ�����ִ����ҵ��ɷ�ʽ:%d';

  /// =========== iocpTcpServer ״̬��Ϣ============
  strState_Active      = '����״̬: ����';
  strState_MonitorNull = 'û�д��������';
  strState_ObjectNull  = 'û�м�ض���';    //'iocp server is null'
  strState_Off         = '����״̬: �ر�';
  strRecv_SizeInfo     = '��������: %s';
  strSend_SizeInfo     = '��������: %s';
  strRecv_PostInfo     = '������Ϣ: Ͷ��:%d, ��Ӧ:%d, ʣ��:%d';  //post:%d, response:%d, remain:%d
  strSend_Info         = '������Ϣ: Ͷ��:%d, ��Ӧ:%d, ʣ��:%d';  //post:%d, response:%d, remain:%d
  strSendQueue_Info    = '���Ͷ���: ѹ��/����/���/��ֹ:%d, %d, %d, %d';//push/pop/complted/abort:%d, %d, %d, %d
  strSendRequest_Info  = '���Ͷ���: ����:%d, ���:%d, ����:%d';  //'create:%d, out:%d, return:%d'
  strAcceptEx_Info     = 'AcceptEx: Ͷ��:%d, ��Ӧ:%d';      //'post:%d, response:%d'
  strSocketHandle_Info = '�׽��־��: ����:%d, ����:%d';  //'create:%d, destroy:%d'
  strContext_Info      = '���Ӷ���: ����:%d, ���:%d, ����:%d';  //'create:%d, out:%d, return:%d'
  strOnline_Info       = '������Ϣ: %d';
  strWorkers_Info      = '�����߳�: %d';
  strRunTime_Info      = '������Ϣ: %s';
  /// =========== �����״̬��Ϣ============

  strCannotConnect     = '��ǰ״̬�²��ܽ�������...';
  strConnectError      = '��������ʧ��, �������: %d';
  strConnectNonExist   = '���Ӳ�����';
  strStreamReadTimeOut = '����ȡ����';

  
implementation

end.
