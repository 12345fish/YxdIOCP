unit MvcDemo;

interface

{$R+}

uses
  Iocp.Http, Iocp.Http.WebSocket, iocp.Http.MVC, DB,
  SysUtils, Classes;

type
  TUserData = record
    UID: Integer;
    Age: Integer;
    Name: string;
    Nick: string;
  end;

  TPerson = record
    UID: Integer;
    Name: string;
    Status: Integer;
  end;

  TRegState = record
    Status: Integer;
    Msg: string;
  end;

type
  [Service]
  [RequestMapping('/demo')]
  TMvcDemo = class(TObject)
  protected
    [Autowired]
    FServer: TIocpHttpServer;
  public
    class procedure Hello;

    // ֱ�Ӵ������󣬲�����ʹ�� Response ��������
    // ���� URL: /demo/view
    [RequestMapping('/view', http_GET)]
    procedure ViewTest(Request: TIocpHttpRequest; Response: TIocpHttpResponse);

    // ֱ�Ӵ������󣬲�����ʹ�� Response ��������
    [RequestMapping('/view/{uid}/{uname}', http_GET)]
    procedure ViewTest1(
      [PathVariable('uid')] UID: Integer;
      [PathVariable('uname')] const UName: string;
      Response: TIocpHttpWriter);

    // ����һ����ҳ����
    // ���� URL: /demo/view2
    [RequestMapping('/view2', http_GET)]
    function ViewTest2(Request: TIocpHttpRequest): string;

    // ����һ����ҳ����
    // ���� URL: /demo/view3/123456
    [RequestMapping('/view3/{uid}', http_GET)]
    function ViewTest3([PathVariable('uid')] UID: Integer): string;

    // ����һ����ҳ����, �����ط�ʽ
    // ���� URL: /demo/view4?uid=123456
    [Download]
    [RequestMapping('/view4', http_GET)]
    function ViewTest4([RequestParam('uid')] UID: Integer): string;

    // ����һ����¼�����Զ����л�
    // ���� URL: /demo/view5
    [RequestMapping('/view5', http_GET)]
    [ResponseBody]
    function ViewTest5(): TUserData;

    // ����һ�����󣬻��Զ����л������صĶ�����Զ��ͷ�
    // ���� URL: /demo/view6
    [RequestMapping('/view6', http_GET)]
    [ResponseBody]
    function ViewTest6(): TStrings;

    // ����UID��ѯ�û���Ϣ��
    // ���� URL: /demo/person/profile/123456
    [RequestMapping('/person/profile/{id}', http_GET)]
    [ResponseBody]
    function Porfile([PathVariable('id')] UID: Integer): TPerson;

    // �ύ�û�����
    // ���� URL: /demo/person/profile/reguser
    [RequestMapping('/person/profile/reguser')]
    [ResponseBody]
    function RegUser([RequestBody] Data: TUserData): TRegState;

    // WebSocket ������ֱ�ӷ����ַ�������
    [WebSocket]
    function HelloWebSocket(): string;

    // WebSocket ������, ֻ�н��յ��ı���Ϣ�������� 'hello' ʱ����Ӧ
    [WebSocket('hello')]
    procedure HelloWebSocket2(Response: TIocpWebSocketResponse);

  end;

implementation

{ TMvcDemo }

class procedure TMvcDemo.Hello;
begin
end;

function TMvcDemo.HelloWebSocket: string;
begin
  Result := '123456789';
end;

procedure TMvcDemo.HelloWebSocket2(Response: TIocpWebSocketResponse);
begin
  Response.Send('��á�');
end;

function TMvcDemo.Porfile(UID: Integer): TPerson;
begin
  Result.UID := UID;
  Result.Name := 'Admin';
  Result.Status := 100;
end;

function TMvcDemo.RegUser(Data: TUserData): TRegState;
begin
  Result.Status := 0;
  Result.Msg := 'ע��ɹ����û�����: ' + Data.Name;
end;

procedure TMvcDemo.ViewTest(Request: TIocpHttpRequest;
  Response: TIocpHttpResponse);
begin
  Response.Send(FServer.WebPath);
end;

procedure TMvcDemo.ViewTest1(UID: Integer; const UName: string;
  Response: TIocpHttpWriter);
begin
  Response.Charset := hct_UTF8;
  Response.Write(Format('{"uid":%d, "uname":"%s"}', [UID, UName]));
  Response.Flush;
end;

function TMvcDemo.ViewTest2(Request: TIocpHttpRequest): string;
begin
  Result := 'http_mvc_setting.xml';
end;

function TMvcDemo.ViewTest3(UID: Integer): string;
begin
  Result := 'httpPostTest.html';
end;

function TMvcDemo.ViewTest4(UID: Integer): string;
begin
  Result := 'http_mvc_setting.xml';
end;

function TMvcDemo.ViewTest5: TUserData;
begin
  Result.UID := 666;
  Result.Age := 30;
  Result.Name := 'yangyxd';
  Result.Nick := '����';
end;

function TMvcDemo.ViewTest6: TStrings;
begin
  Result := TStringList.Create;
  Result.Add('aaa');
  Result.Add('bbb');
  Result.Add('cccc');
end;

initialization
  // ��Ϊ TMvcDemo �������κεط���û���õ�������Ҫ
  // ��ֹ�����Ż���д��һ�����ô���
  // Ҳ����ֱ�ӵ��� RegMvcClass ����ע��
  TMvcDemo.Hello;

end.
