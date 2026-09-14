whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
set verify off
prompt Create the S3 credential from session-only keys.
accept DEPLOY_S3_ACCESS_KEY char prompt 'S3 access key: ' hide
accept DEPLOY_S3_SECRET_KEY char prompt 'S3 secret key: ' hide
declare
  l_name varchar2(128) := upper('&&DEPLOY_CREDENTIAL_NAME');
  l_count number;
begin
  if l_name is null or instr(l_name,'<')>0 or not regexp_like(l_name, '^[A-Z][A-Z0-9_$#]{0,127}$') then
    raise_application_error(-20892,'Shared environment credential name is required.');
  end if;
  select count(*) into l_count from user_credentials where credential_name=l_name;
  if l_count>0 then
    raise_application_error(-20893,
      'Configured S3 credential already exists; no protected key file was loaded and no change was made.');
  end if;
end;
/
declare
  l_name varchar2(128) := upper('&&DEPLOY_CREDENTIAL_NAME');
  l_access_key varchar2(4000) := '&&DEPLOY_S3_ACCESS_KEY';
  l_secret_key varchar2(4000) := '&&DEPLOY_S3_SECRET_KEY';
  l_count number;
begin
  if l_name is null or instr(l_name,'<')>0 or l_access_key is null or instr(l_access_key,'<')>0 or l_secret_key is null or instr(l_secret_key,'<')>0 then
    raise_application_error(-20892,'Environment credential name, access key, and secret key are required.');
  end if;
  select count(*) into l_count from user_credentials where credential_name=l_name;
  if l_count>0 then
    raise_application_error(-20893,'S3 credential already exists; no change was made. Rotate it through the approved DBMS_CLOUD procedure.');
  end if;
  dbms_cloud.create_credential(credential_name=>l_name,username=>l_access_key,password=>l_secret_key);
  dbms_output.put_line('PASS: local S3-compatible credential created for '||user||'.');
end;
/
undefine DEPLOY_S3_ACCESS_KEY
undefine DEPLOY_S3_SECRET_KEY
