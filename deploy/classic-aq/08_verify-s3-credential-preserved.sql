-- Run through 00_run-installation.sql to verify the configured credential.
-- This script intentionally does not load environment.sql or prompt for keys.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
declare
  l_name varchar2(128) := upper('&&DEPLOY_CREDENTIAL_NAME');
  l_provider varchar2(20) := upper('&&DEPLOY_STORAGE_PROVIDER');
  l_count number;
begin
  if l_name is null or instr(l_name,'<')>0 or not regexp_like(l_name, '^[A-Z][A-Z0-9_$#]{0,127}$') then
    raise_application_error(-20894,'Shared environment credential name is required.');
  end if;
  if l_provider not in ('S3_COMPATIBLE','OCI_NATIVE') then
    raise_application_error(-20894,'Storage provider must be S3_COMPATIBLE or OCI_NATIVE.');
  end if;
  select count(*) into l_count from user_credentials where credential_name=l_name;
  if l_count<>1 then
    raise_application_error(-20894,
      'Configured provider credential is absent or ambiguous; no creation was attempted.');
  end if;
  dbms_output.put_line('PASS: configured ' || l_provider || ' credential ' || l_name ||
                       ' is present and was not replaced.');
end;
/
