@echo ������֤��
%������֤��%
openssl rand -out ca.rand 1000

%������֤��˽Կ%
openssl genrsa -aes256 -out ca.key.pem 2048

%���ɸ�֤��ǩ������%
openssl req -new -key ca.key.pem -config openssl.cfg -out ca.csr -subj "/C=CN/ST=BJ/L=BJ/O=yangyxd/OU=yangyxd/CN=yangyxd"

%ǩ����֤������ǩ����֤��%
@echo ǩ��X.509��ʽ��֤��
openssl x509 -req -days 10000 -sha1 -extensions v3_ca -signkey ca.key.pem -in ca.csr -out ca.cer

@echo ����������֤��

%����������˽Կ%
openssl genrsa -aes256 -out ssl.server.pem 2048

%���ɷ�����֤��ǩ������%
openssl req -new -key ssl.server.pem -config openssl.cfg -out ssl.server.csr -subj "/C=CN/ST=BJ/L=BJ/O=lesaas/OU=lesaas/CN=yangyxd" 

%ǩ��������֤��%
openssl x509 -req -days 3650 -sha1 -extensions v3_req -CA ca.cer -CAkey ca.key.pem -CAserial ca.srl -CAcreateserial -in ssl.server.csr -out ssl.server.cer


@echo �����ͻ���֤��

%�����ͻ���˽Կ%
openssl genrsa -aes256 -out ssl.client.pem 2048

%���ɿͻ���֤��ǩ������%
openssl req -new -key ssl.client.pem -config openssl.cfg -out ssl.client.csr -subj "/C=CN/ST=BJ/L=BJ/O=lesaas/OU=lesaas/CN=yangyxd" 

%ǩ���ͻ���֤��%
openssl ca -days 3650 -in ssl.client.csr -out ssl.client.cer -cert ca.cer -keyfile ca.key.pem

pause
