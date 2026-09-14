-- Configure the already installed Classic AQ runtime for the isolated OCI
-- HEAD test. Run as NFE_OWNER. It reuses the existing source mapping and the
-- existing NFE_OCI_HEAD_PROBE_CRED; it neither creates nor prints secrets.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on verify off
declare
  l_owner nfe_deploy_source_config.source_owner%type;
  l_table nfe_deploy_source_config.source_table%type;
  l_clob nfe_deploy_source_config.source_clob_column%type;
  l_id nfe_deploy_source_config.source_id_column%type;
  l_key nfe_deploy_source_config.source_key_column%type;
  l_date nfe_deploy_source_config.source_date_column%type;
  l_status nfe_deploy_source_config.source_status_column%type;
  l_max number;
begin
  select source_owner,source_table,source_clob_column,source_id_column,
         source_key_column,source_date_column,source_status_column
    into l_owner,l_table,l_clob,l_id,l_key,l_date,l_status
    from nfe_deploy_source_config where config_id=1;
  select max_inflight into l_max from nfe_deploy_storage_config where config_id=1;
  pkg_nfe_deploy_config.set_environment(
    p_s3_endpoint=>'https://objectstorage.us-ashburn-1.oraclecloud.com',
    p_bucket_name=>'nfe',p_object_prefix=>'nfe-classic-aq-oci-test',
    p_credential_name=>'NFE_OCI_HEAD_PROBE_CRED',p_source_owner=>l_owner,
    p_source_table=>l_table,p_source_clob_column=>l_clob,p_source_id_column=>l_id,
    p_source_key_column=>l_key,p_source_date_column=>l_date,
    p_source_status_column=>l_status,p_max_inflight=>l_max,
    p_storage_provider=>'OCI_NATIVE',p_oci_namespace=>'idzvuvikb5ym',
    p_integrity_mode=>'OCI_MD5_HEAD');
  commit;
  dbms_output.put_line('PASS: OCI_NATIVE / OCI_MD5_HEAD test configuration persisted.');
end;
/
select storage_provider,integrity_mode,s3_endpoint,bucket_name,object_prefix,
       oci_namespace,credential_name,max_inflight
  from nfe_deploy_storage_config where config_id=1;
