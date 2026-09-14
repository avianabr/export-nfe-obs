-- Temporary S3-compatible fallback configuration. Run as NFE_OWNER.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on verify off
declare
  l_owner nfe_deploy_source_config.source_owner%type; l_table nfe_deploy_source_config.source_table%type;
  l_clob nfe_deploy_source_config.source_clob_column%type; l_id nfe_deploy_source_config.source_id_column%type;
  l_key nfe_deploy_source_config.source_key_column%type; l_date nfe_deploy_source_config.source_date_column%type;
  l_status nfe_deploy_source_config.source_status_column%type; l_max number;
begin
  select source_owner,source_table,source_clob_column,source_id_column,source_key_column,source_date_column,source_status_column into l_owner,l_table,l_clob,l_id,l_key,l_date,l_status from nfe_deploy_source_config where config_id=1;
  select max_inflight into l_max from nfe_deploy_storage_config where config_id=1;
  pkg_nfe_deploy_config.set_environment(
    p_s3_endpoint=>'https://nfe.obs.sa-brazil-1.myhuaweicloud.com',p_bucket_name=>'rtc',p_object_prefix=>'nfe-classic-aq-s3-fallback-test',p_credential_name=>'HUAWEI_OBS_CRED',
    p_source_owner=>l_owner,p_source_table=>l_table,p_source_clob_column=>l_clob,p_source_id_column=>l_id,p_source_key_column=>l_key,p_source_date_column=>l_date,p_source_status_column=>l_status,p_max_inflight=>l_max,
    p_storage_provider=>'S3_COMPATIBLE',p_integrity_mode=>'FULL_DOWNLOAD_SHA256');
  commit; dbms_output.put_line('PASS: S3_COMPATIBLE / FULL_DOWNLOAD_SHA256 fallback configuration persisted.');
end;
/
