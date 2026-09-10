-- Run as NFE_OWNER to verify that the configured credential remains present.
-- This script intentionally does not load s3-credential.sql or prompt for keys.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
declare
  l_name varchar2(128);
  l_count number;
begin
  select credential_name into l_name
    from nfe_deploy_storage_config where config_id=1;
  select count(*) into l_count from user_credentials where credential_name=l_name;
  if l_count<>1 then
    raise_application_error(-20894,
      'Configured S3 credential is absent or ambiguous; no creation was attempted.');
  end if;
  dbms_output.put_line('PASS: configured S3 credential ' || l_name ||
                       ' is present and was not replaced.');
end;
/
