@echo ����֤��
%������֤��%
openssl rand -out ssl.rand 1000

%������֤��˽Կ%
openssl genrsa -aes256 -out ssl.ca.key.pem 2048

%���ɸ�֤��ǩ������%
openssl req -new -key ssl.ca.key.pem -out ssl.ca.csr -subj "/C=CN/ST=BJ/L=BJ/O=lesaas/OU=lesaas/CN=*.lesaas.cn" -config openssl.cnf

%ǩ����֤������ǩ����֤��%
@echo ǩ��X.509��ʽ֤������
openssl x509 -req -days 10000 -sha1 -extensions v3_ca -signkey ssl.ca.key.pem -in ssl.ca.csr -out ssl.certs.ca.cer

pause
