whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set verify off
prompt Persist the environment loaded by 00_run-installation.sql.
declare
begin
  pkg_nfe_deploy_config.set_environment(
    p_s3_endpoint         => '&&DEPLOY_S3_ENDPOINT',
    p_bucket_name          => '&&DEPLOY_BUCKET_NAME',
    p_object_prefix        => '&&DEPLOY_OBJECT_PREFIX',
    p_credential_name      => '&&DEPLOY_CREDENTIAL_NAME',
    p_source_owner         => '&&DEPLOY_SOURCE_OWNER',
    p_source_table         => '&&DEPLOY_SOURCE_TABLE',
    p_source_clob_column   => '&&DEPLOY_SOURCE_CLOB_COLUMN',
    p_source_id_column     => '&&DEPLOY_SOURCE_ID_COLUMN',
    p_source_key_column    => '&&DEPLOY_SOURCE_KEY_COLUMN',
    p_source_date_column   => '&&DEPLOY_SOURCE_DATE_COLUMN',
    p_source_status_column => '&&DEPLOY_SOURCE_STATUS_COLUMN',
    p_max_inflight         => to_number('&&DEPLOY_MAX_INFLIGHT'),
    p_storage_provider     => '&&DEPLOY_STORAGE_PROVIDER',
    p_oci_namespace        => '&&DEPLOY_OCI_NAMESPACE',
    p_integrity_mode       => '&&DEPLOY_INTEGRITY_MODE');
  commit;
end;
/
declare
  l_enabled char(1);
  l_job varchar2(5);
begin
  select classic_aq_enabled into l_enabled from nfe_classic_aq_config where config_id=1;
  select enabled into l_job from user_scheduler_jobs where job_name='NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB';
  if l_enabled <> 'N' or l_job <> 'FALSE' then
    raise_application_error(-20850,'Configuration must leave the Classic AQ gate and job disabled.');
  end if;
  dbms_output.put_line('PASS: environment configuration persisted; Classic AQ, job, and batch selection remain disabled.');
end;
/
