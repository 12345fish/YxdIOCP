unit uMsgBase;

interface

uses
  Classes, SysUtils, Windows, ZLib;

type
  TMsgBase = class(TObject)
  private
    function GetData: string;
    procedure SetData(const Value: string);
  protected
    function ReadString(avIn: TStream): string; virtual;
    function ReadText(avIn: TStream; avLen: Integer): string; virtual;
    function ReadInt64(avIn: TStream): Int64; virtual;
    function ReadInteger(avIn: TStream): Integer; virtual;
    function ReadCardinal(avIn: TStream): Cardinal; virtual;
    function ReadWord(avIn: TStream): Word; virtual;
    function ReadByte(avIn: TStream): Byte; virtual;
    function ReadDateTime(avIn: TStream): TDateTime; virtual;
    function ReadBoolean(avIn: TStream): Boolean; virtual;
    procedure WriteWord(avOut: TStream; avData: Word); virtual;
    procedure WriteCardinal(avOut: TStream; avData: Cardinal); virtual;
    procedure WriteBoolean(avOut: TStream; avData: Boolean); virtual;
    procedure WriteText(avOut: TStream; const avData: string); virtual;
  public
    property Data: string read GetData write SetData;
    procedure SaveToStream(avOut: TStream); virtual; abstract;
    procedure LoadFromStream(avIn: TStream); virtual; abstract;
    procedure LoadFromFile(const avIn: string); virtual;
  end;

type
  /// <summary>
  /// ������Ϣ
  /// </summary>
  TMsgRequest = class(TMsgBase)
  private
    tvTime: Integer;
    tvUser: AnsiString;
    tvPass: AnsiString;
    tvRequestType: Integer;
    tvRequestParam: AnsiString;
    tvVerifyCode: Integer;
    tvZlib: Boolean;
    tvOK: Boolean;
  public
    property Time: Integer read tvTime write tvTime;      //ʱ��
    property User: AnsiString read tvUser write tvUser;   //�û�
    property Token: AnsiString read tvPass write tvPass;  //��¼ʱ��tonkenΪ����
    property RequestType: Integer read tvRequestType write tvRequestType; //��������
    property RequestParam: AnsiString read tvRequestParam write tvRequestParam; //�������
    property VerifyCode: Integer read tvVerifyCode write tvVerifyCode; //У���
    property Zlib: Boolean read tvZlib write tvZlib; // �Ƿ�ѹ������
    property OK: Boolean read tvOK; //�����Ƿ���ȷ
  public
    function IsEx: Boolean; virtual;
    procedure LoadFromStream(avIn: TStream); override;
    function Verify: Boolean;
    // �����ۼ�У���
    function CalVerifyCode: Longint; virtual;
  end;

type
  /// <summary>
  /// ������Ϣ
  /// </summary>
  TMsgRequestEx = class(TMsgRequest)
  public
    UID: Integer; // ���ֶβ����������д��ݣ�����Ϊ��¼֮��
    function IsEx: Boolean; override;
    procedure LoadFromStream(avIn: TStream); override;
  end;

type
  /// <summary>
  /// ���ش���
  /// </summary>
  TResponseCode = (
              rq_BadReq = -3,            //�Ƿ����� (���÷�������ַ)
              rq_SessionError = -2,      //�Ự���ڻ�ʧЧ��ԭ������ǳ�ʱ�����������
              rq_Error = -1,             //��������
              rq_Done = 0,               //�������(������ʾ����ɹ�)
              rq_OK = 1,                 //����ɹ�
              rq_UesrError,              //�û���Ϣ����
              rq_Null                    //δʹ��
    );
    
type
  /// <summary>
  /// �ظ���Ϣ
  /// </summary>
  TMsgResponse = class(TMsgBase)
  private
    tvZlib: Boolean;
    tvResultCode: TResponseCode;
    tvResultContent: AnsiString;
    tvOK: Boolean;
  public
    property ResultCode: TResponseCode read tvResultCode write tvResultCode; // ���ش���
    property ResultContent: AnsiString read tvResultContent write tvResultContent;
    property Zlib: Boolean read tvZlib write tvZlib;   // �Ƿ�ѹ������
    property OK: Boolean read tvOK write tvOK;
    procedure SaveToStream(avOut: TStream); override;
    procedure SaveResultContentToStream(avOut: TStream);
    procedure LoadFromStream(avIn: TStream); override;
  end;


implementation

const
  /// <summary>
  /// ���ݰ�ʶ��λ
  /// </summary>
  VERIFYWORD: WORD = $5688;
  /// <summary>
  /// ����ʱʱ��
  /// </summary>
  REQUESTTIMEOUT: Integer = 86400; //1��

/// <summary>
/// ��ѹ���ַ���
/// </summary>
function DecompressDataToStr(const Data: string): string;
var
  I: Integer;
  s: Pointer;
begin
  if Length(Data) = 0 then
    Result := ''
  else begin
    DecompressBuf(@Data[1], Length(Data), 0, s, i);
    if i <= 0 then
      Result := ''
    else begin
      SetLength(Result, i);
      CopyMemory(@Result[1], s, i);
      FreeMem(s, i);
    end;
  end;
end;

function SetCompressRespData(Response: TMsgResponse): Boolean;
var
  i: Integer;
  ZlibData: Pointer;
  str: string;
begin
  CompressBuf(@Response.ResultContent[1], Length(Response.ResultContent), ZlibData, i);
  SetLength(str, i);
  CopyMemory(@str[1], ZlibData, i);
  FreeMem(ZlibData, i);
  Response.ResultContent := str;
  Result := True;
end;
  
{ TMsgBase }

function TMsgBase.GetData: string;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create();
  Self.SaveToStream(ms);
  SetString(Result, PChar(ms.Memory), ms.Size);
  ms.Free;
end;

procedure TMsgBase.LoadFromFile(const avIn: string);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(avIn, fmOpenRead or fmShareDenyWrite);
  try
    Self.LoadFromStream(fs);
  finally
    fs.Free;
  end;
end;

function TMsgBase.ReadBoolean(avIn: TStream): Boolean;
begin
  avIn.ReadBuffer(Result, SizeOf(Result));
end;

function TMsgBase.ReadByte(avIn: TStream): Byte;
begin
  avIn.ReadBuffer(Result, SizeOf(Result));
end;

function TMsgBase.ReadCardinal(avIn: TStream): Cardinal;
begin
  avIn.ReadBuffer(Result, SizeOf(Result));
end;

function TMsgBase.ReadDateTime(avIn: TStream): TDateTime;
begin
  avIn.ReadBuffer(Result, SizeOf(Result));
end;

function TMsgBase.ReadInt64(avIn: TStream): Int64;
begin
  avIn.ReadBuffer(Result, SizeOf(Result));
end;

function TMsgBase.ReadInteger(avIn: TStream): Integer;
begin
  avIn.ReadBuffer(Result, SizeOf(Result));
end;

function TMsgBase.ReadString(avIn: TStream): string;
var
  l: Integer;
begin
  l := Self.ReadWord(avIn);
  SetLength(Result, l);
  if l > 0 then
    avIn.ReadBuffer(Result[1], l);
end;

function TMsgBase.ReadText(avIn: TStream; avLen: Integer): string;
begin
  SetLength(Result, avLen);
  if avLen > 0 then
    avIn.ReadBuffer(Result[1], avLen);
end;

function TMsgBase.ReadWord(avIn: TStream): Word;
begin
  avIn.ReadBuffer(Result, SizeOf(Result));
end;

procedure TMsgBase.SetData(const Value: string);
var
  ss: TStringStream;
begin
  ss := TStringStream.Create(Value);
  try
    Self.LoadFromStream(ss);
  finally
    ss.Free;
  end;
end;

procedure TMsgBase.WriteBoolean(avOut: TStream; avData: Boolean);
begin
  avOut.WriteBuffer(avData, SizeOf(avData));
end;

procedure TMsgBase.WriteCardinal(avOut: TStream; avData: Cardinal);
begin
  avOut.WriteBuffer(avData, SizeOf(avData));
end;

procedure TMsgBase.WriteText(avOut: TStream; const avData: string);
var
  l: Integer;
begin
  l := Length(avData);
  if l > 0 then
    avOut.WriteBuffer(avData[1], l);
end;

procedure TMsgBase.WriteWord(avOut: TStream; avData: Word);
begin
  avOut.WriteBuffer(avData, SizeOf(avData));
end;

{ TMsgRequest }

function TMsgRequest.CalVerifyCode: Longint;
var
  p: PAnsiChar;
  i: integer;
begin
  Result := tvTime + tvRequestType;
  p := PAnsiChar(tvUser);
  for I := 1 to length(tvUser) do begin
    Inc(Result, Ord(p^));
    Inc(p);
  end;
  p := PAnsiChar(tvPass);
  for I := 1 to length(tvPass) do begin
    Inc(Result, Ord(p^));
    Inc(p);
  end;
  p := PAnsiChar(tvRequestParam);
  for I := 1 to length(tvRequestParam) do begin
    Inc(Result, Ord(p^));
    Inc(p);
  end;
end;

function TMsgRequest.IsEx: Boolean;
begin
  Result := False;
end;

procedure TMsgRequest.LoadFromStream(avIn: TStream);
begin
  tvOK := False;
  if self.ReadWord(avIn) <> VERIFYWORD then
    Exit;
  avIn.ReadBuffer(tvTime, SizeOf(tvTime));
  tvUser := Self.ReadString(avIn);
  tvPass := Self.ReadString(avIn);
  avIn.ReadBuffer(tvRequestType, SizeOf(tvRequestType));
  avIn.ReadBuffer(tvZlib, SizeOf(tvZlib));
  if Self.tvZlib then
    tvRequestParam := DecompressDataToStr(Self.ReadString(avIn))
  else
    tvRequestParam := Self.ReadString(avIn);
  avIn.ReadBuffer(tvVerifyCode, SizeOf(tvVerifyCode));
  tvOK := True;
end;

function TMsgRequest.Verify: Boolean;
begin
  if Abs(Now() - tvTime) > REQUESTTIMEOUT then
    Result := False
  else
    Result := CalVerifyCode = tvVerifyCode;
end;

{ TMsgRequestEx }

function TMsgRequestEx.IsEx: Boolean;
begin
  Result := True;
end;

procedure TMsgRequestEx.LoadFromStream(avIn: TStream);
var
  i: Cardinal;
  b: Byte;
  w: Word;
begin
  tvOK := False;
  avIn.ReadBuffer(w, SizeOf(w));
  if w <> VERIFYWORD then Exit;
  avIn.ReadBuffer(tvTime, SizeOf(tvTime));

  avIn.ReadBuffer(w, SizeOf(w));
  SetLength(tvUser, w);
  if w > 0 then
    avIn.ReadBuffer(tvUser[1], w);

  avIn.ReadBuffer(w, SizeOf(w));
  SetLength(tvPass, w);
  if w > 0 then
    avIn.ReadBuffer(tvPass[1], w);

  avIn.ReadBuffer(tvRequestType, SizeOf(tvRequestType));
  avIn.ReadBuffer(b, SizeOf(b));
  avIn.ReadBuffer(tvZlib, SizeOf(tvZlib));
  //Self.tvDevType := TPtLoginType(b);
  avIn.ReadBuffer(b, SizeOf(b));
  if b = 1 then
    avIn.ReadBuffer(i, SizeOf(i))
  else begin  // �����ϰ汾
    i := StrToIntDef('$' + IntToHex(ReadByte(avIn), 2) + IntToHex(b, 2), 0);
  end;
  if i > 0 then begin
    if Self.tvZlib then
      Self.tvRequestParam := DecompressDataToStr(Self.ReadText(avIn, i))
    else begin
      SetLength(tvRequestParam, i);
      avIn.ReadBuffer(tvRequestParam[1], i);
    end;
  end;
  avIn.ReadBuffer(tvVerifyCode, SizeOf(tvVerifyCode));
  tvOK := True;
end;

{ TMsgResponse }

procedure TMsgResponse.LoadFromStream(avIn: TStream);
var
  len: DWORD;
begin
  tvOK := False;
  if self.ReadWord(avIn) <> VERIFYWORD then
    Exit;
  Self.tvResultCode := TResponseCode(Self.ReadCardinal(avIn));
  Self.tvZlib := Self.ReadBoolean(avIn); 
  len := Self.ReadCardinal(avIn);
  if Self.tvZlib then
    Self.tvResultContent := DecompressDataToStr(Self.ReadText(avIn, len))
  else
    Self.tvResultContent := Self.ReadText(avIn, len);
  tvOK := True;
end;

procedure TMsgResponse.SaveResultContentToStream(avOut: TStream);
begin
  if Length(tvResultContent) > 0 then
    avOut.WriteBuffer(tvResultContent[1], Length(tvResultContent));
end;

procedure TMsgResponse.SaveToStream(avOut: TStream);
begin
  if Self.tvZlib then begin
    if Length(tvResultContent) > 0 then
      Self.tvZlib := SetCompressRespData(Self)
    else
      Self.tvZlib := False;
  end;
  Self.WriteWord(avOut, VERIFYWORD);
  Self.WriteCardinal(avOut, Integer(Self.tvResultCode));
  Self.WriteBoolean(avOut, Self.tvZlib);
  Self.WriteCardinal(avOut, Length(Self.tvResultContent));
  Self.WriteText(avOut, Self.tvResultContent);
end;

end.
