@echo ����֤��
%������֤��%
openssl rand -out ssl.rand 1000

%������֤��˽Կ%
openssl genrsa -aes256 -out ssl.server.pem 2048

%���ɸ�֤��ǩ������%
openssl req -new -key ssl.server.pem -config openssl.cfg -out ssl.server.csr -subj "/C=CN/ST=BJ/L=BJ/O=yangyxd/OU=yangyxd/CN=*.com"

%ǩ����֤������ǩ����֤��%
@echo ǩ��X.509��ʽ֤������
openssl x509 -req -days 10000 -sha1 -extensions v3_ca -signkey ssl.server.pem -in ssl.server.csr -out ssl.server.cer

pause
