-- Run while connected as NFE_OWNER, not SYS.
-- Stores an OCI Customer Secret Key pair for the S3-compatible endpoint in
-- DBMS_CLOUD. Values are prompted and are not written to this file.
-- Do not paste either value into a chat, terminal command line, or source file.

whenever sqlerror exit failure rollback
set define on
set echo off
set verify off
set serveroutput on size unlimited

accept s3_access_key char prompt 'OCI Customer Secret access key: '
accept s3_secret_key char prompt 'OCI Customer Secret secret key: ' hide

declare
  l_count pls_integer;
begin
  if sys_context('USERENV', 'CURRENT_USER') <> 'NFE_OWNER' then
    raise_application_error(-20000, 'Connect as NFE_OWNER before creating this credential.');
  end if;

  select count(*)
    into l_count
    from user_credentials
   where credential_name = 'NFE_OBJECT_STORAGE_S3_CRED';

  if l_count > 0 then
    raise_application_error(-20001,
      'Credential NFE_OBJECT_STORAGE_S3_CRED already exists. Use DBMS_CLOUD.UPDATE_CREDENTIAL for rotation.');
  end if;

  dbms_cloud.create_credential(
    credential_name => 'NFE_OBJECT_STORAGE_S3_CRED',
    username => '&s3_access_key',
    password => '&s3_secret_key');

  dbms_output.put_line('PASS: credential NFE_OBJECT_STORAGE_S3_CRED created for NFE_OWNER.');
end;
/

select credential_name
  from user_credentials
 where credential_name = 'NFE_OBJECT_STORAGE_S3_CRED';
