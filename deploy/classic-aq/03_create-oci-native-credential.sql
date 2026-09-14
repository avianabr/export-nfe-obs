-- OCI signing-key credential. The private key is session-only and hidden.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on verify off
accept DEPLOY_OCI_USER_OCID char prompt 'OCI user OCID: '
accept DEPLOY_OCI_TENANCY_OCID char prompt 'OCI tenancy OCID: '
accept DEPLOY_OCI_FINGERPRINT char prompt 'OCI API-key fingerprint: '
accept DEPLOY_OCI_PRIVATE_KEY char prompt 'OCI API private key (one line; hidden): ' hide
declare
  l_name varchar2(128):=upper('&&DEPLOY_CREDENTIAL_NAME'); l_count number;
begin
  if l_name is null or instr(l_name,'<')>0 or not regexp_like(l_name,'^[A-Z][A-Z0-9_$#]{0,127}$') then raise_application_error(-20892,'Credential name is required.'); end if;
  select count(*) into l_count from user_credentials where credential_name=l_name;
  if l_count>0 then raise_application_error(-20893,'OCI credential already exists; no change was made.'); end if;
  dbms_cloud.create_credential(credential_name=>l_name,user_ocid=>'&&DEPLOY_OCI_USER_OCID',tenancy_ocid=>'&&DEPLOY_OCI_TENANCY_OCID',private_key=>'&&DEPLOY_OCI_PRIVATE_KEY',fingerprint=>'&&DEPLOY_OCI_FINGERPRINT');
  dbms_output.put_line('PASS: OCI native credential created for '||user||'.');
end;
/
undefine DEPLOY_OCI_USER_OCID
undefine DEPLOY_OCI_TENANCY_OCID
undefine DEPLOY_OCI_FINGERPRINT
undefine DEPLOY_OCI_PRIVATE_KEY
