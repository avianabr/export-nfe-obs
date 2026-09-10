-- Run as NFE_OWNER only after environment.sql restored the normal credential.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_credential varchar2(128);
  l_count number;
begin
  select credential_name into l_credential
    from nfe_deploy_storage_config where config_id=1;
  if l_credential='NFE_CLASSIC_AQ_RETRY_TEST_CRED' then
    raise_application_error(-20887,
      'Restore the normal environment credential before removing the retry credential.');
  end if;
  select count(*) into l_count from user_credentials
   where credential_name='NFE_CLASSIC_AQ_RETRY_TEST_CRED';
  if l_count=1 then
    dbms_cloud.drop_credential('NFE_CLASSIC_AQ_RETRY_TEST_CRED');
  end if;
  dbms_output.put_line('PASS: retry-test credential removed; failed AQ message is preserved in the exception queue.');
end;
/
