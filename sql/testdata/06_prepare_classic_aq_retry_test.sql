-- Explicit opt-in retry harness. Run only as NFE_OWNER in an isolated PDB.
-- It creates a non-secret invalid credential and leaves one message queued for
-- controlled failures. Restore the environment before running the cleanup file.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_count number;
  l_endpoint nfe_deploy_storage_config.s3_endpoint%type;
  l_bucket nfe_deploy_storage_config.bucket_name%type;
  l_prefix nfe_deploy_storage_config.object_prefix%type;
  l_acl_host nfe_deploy_storage_config.acl_host%type;
  l_max_inflight nfe_deploy_storage_config.max_inflight%type;
  l_source_owner nfe_deploy_source_config.source_owner%type;
  l_source_table nfe_deploy_source_config.source_table%type;
  l_source_clob nfe_deploy_source_config.source_clob_column%type;
  l_source_id nfe_deploy_source_config.source_id_column%type;
  l_source_key nfe_deploy_source_config.source_key_column%type;
  l_source_date nfe_deploy_source_config.source_date_column%type;
  l_source_status nfe_deploy_source_config.source_status_column%type;
  l_batch_id number;
  l_control_id number;
begin
  select count(*) into l_count from user_credentials
   where credential_name='NFE_CLASSIC_AQ_RETRY_TEST_CRED';
  if l_count<>0 then
    raise_application_error(-20885,
      'Retry-test credential already exists; restore and clean up the prior test first.');
  end if;
  dbms_cloud.create_credential(
    credential_name => 'NFE_CLASSIC_AQ_RETRY_TEST_CRED',
    username => 'INVALID_TEST_ACCESS_KEY', password => 'INVALID_TEST_SECRET');

  select s3_endpoint,bucket_name,object_prefix,acl_host,max_inflight
    into l_endpoint,l_bucket,l_prefix,l_acl_host,l_max_inflight
    from nfe_deploy_storage_config where config_id=1;
  select source_owner,source_table,source_clob_column,source_id_column,
         source_key_column,source_date_column,source_status_column
    into l_source_owner,l_source_table,l_source_clob,l_source_id,l_source_key,
         l_source_date,l_source_status
    from nfe_deploy_source_config where config_id=1;
  pkg_nfe_deploy_config.set_environment(
    l_endpoint,l_bucket,l_prefix,l_acl_host,'NFE_CLASSIC_AQ_RETRY_TEST_CRED',
    l_source_owner,l_source_table,l_source_clob,l_source_id,l_source_key,
    l_source_date,l_source_status,l_max_inflight);

  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,created_by)
  values ('RETRY-' || to_char(systimestamp,'YYYYMMDDHH24MISSFF3'),
          'CREATED',systimestamp + interval '1' day,1,user)
  returning batch_id into l_batch_id;
  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  pkg_nfe_classic_aq_runtime.admit_one(l_batch_id,'AUTORIZADA',l_control_id);
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  commit;
  dbms_output.put_line('PASS: retry batch_id=' || l_batch_id ||
                       ', control_id=' || l_control_id || ' queued.');
exception
  when others then
    rollback;
    raise;
end;
/
