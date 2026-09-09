-- Run as NFE_OWNER to replace incorrect OCI Customer Secret Key values.
-- This updates the existing credential in place. Secrets are prompted and are
-- not stored in the script or printed to the terminal.

whenever sqlerror exit failure rollback
set define on
set echo off
set verify off
set serveroutput on size unlimited

accept s3_access_key char prompt 'New OCI Customer Secret access key: '
accept s3_secret_key char prompt 'New OCI Customer Secret secret key: ' hide

declare
  l_count pls_integer;
begin
  if sys_context('USERENV', 'CURRENT_USER') <> 'NFE_OWNER' then
    raise_application_error(-20000, 'Connect as NFE_OWNER before rotating this credential.');
  end if;

  select count(*)
    into l_count
    from user_credentials
   where credential_name = 'NFE_OBJECT_STORAGE_S3_CRED';

  if l_count = 0 then
    raise_application_error(-20001,
      'Credential NFE_OBJECT_STORAGE_S3_CRED does not exist. Run 04_create_s3_compat_credential.sql instead.');
  end if;

  dbms_cloud.update_credential(
    credential_name => 'NFE_OBJECT_STORAGE_S3_CRED',
    attribute       => 'USERNAME',
    value           => '&s3_access_key');
  dbms_cloud.update_credential(
    credential_name => 'NFE_OBJECT_STORAGE_S3_CRED',
    attribute       => 'PASSWORD',
    value           => '&s3_secret_key');

  dbms_output.put_line('PASS: NFE_OBJECT_STORAGE_S3_CRED was updated.');
end;
/

select credential_name
  from user_credentials
 where credential_name = 'NFE_OBJECT_STORAGE_S3_CRED';
