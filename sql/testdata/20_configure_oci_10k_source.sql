-- Switches only the source mapping and OCI test prefix. Run as NFE_OWNER.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
declare l_max number; begin
 select max_inflight into l_max from nfe_deploy_storage_config where config_id=1;
 pkg_nfe_deploy_config.set_environment('https://objectstorage.us-ashburn-1.oraclecloud.com','nfe','nfe-classic-aq-oci-10k','NFE_OCI_HEAD_PROBE_CRED','NFE_OWNER','POC_NFE_OCI_10K','XML_CLOB','NFE_ID','CHAVE_NFE','DATA_EMISSAO','SITUACAO',l_max,'OCI_NATIVE','idzvuvikb5ym','OCI_MD5_HEAD');commit;
 dbms_output.put_line('PASS: OCI 10K configuration persisted.');
end;
/
