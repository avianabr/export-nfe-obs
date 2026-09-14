-- One-item OCI_HEAD smoke test. Run as NFE_OWNER only in the isolated PDB.
-- It inserts one synthetic authorized NF-e and writes its object exclusively
-- below the configured nfe-classic-aq-oci-test prefix.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited verify off
declare
  l_source_table varchar2(128);
  l_provider varchar2(20);
  l_mode varchar2(32);
  l_batch_id number;
  l_control_id number;
  l_key varchar2(44) := lpad(to_char(abs(dbms_random.random)),44,'0');
  l_passed boolean;
begin
  select source_table into l_source_table from nfe_deploy_source_config where config_id=1;
  select storage_provider,integrity_mode into l_provider,l_mode from nfe_deploy_storage_config where config_id=1;
  if l_source_table <> 'POC_NFE_DOCUMENT' then
    raise_application_error(-20940,'Smoke script requires configured isolated POC_NFE_DOCUMENT source table.');
  end if;
  if l_provider <> 'OCI_NATIVE' or l_mode <> 'OCI_MD5_HEAD' then
    raise_application_error(-20941,'Smoke script requires OCI_NATIVE / OCI_MD5_HEAD configuration.');
  end if;
  insert into poc_nfe_document(chave_nfe,data_emissao,situacao,xml_clob)
  values(l_key,systimestamp,'AUTORIZADA','<NFe><infNFe Id="NFe'||l_key||'"><smoke>OCI HEAD</smoke></infNFe></NFe>');
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,created_by)
  values('OCI-HEAD-SMOKE-'||to_char(systimestamp,'YYMMDDHH24MISSFF3'),'CREATED',systimestamp+interval '1' day,1,user)
  returning batch_id into l_batch_id;
  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  pkg_nfe_classic_aq_runtime.admit_one(l_batch_id,'AUTORIZADA',l_control_id);
  pkg_nfe_classic_aq_runtime.process_one('NFE-CLASSIC-'||l_control_id);
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  pkg_nfe_classic_aq_runtime.reconcile_batch(l_batch_id,l_passed);
  commit;
  if not l_passed then raise_application_error(-20942,'OCI HEAD smoke batch did not reconcile.'); end if;
  dbms_output.put_line('PASS: OCI HEAD smoke batch_id='||l_batch_id||', control_id='||l_control_id||'.');
exception when others then
  pkg_nfe_classic_aq_runtime.set_enabled('N'); commit; raise;
end;
/
column integrity_mode format a24
column object_uri format a110
select i.control_id,i.status,i.integrity_mode,i.source_bytes,i.destination_bytes,
       i.source_md5,i.destination_checksum,i.destination_algorithm,i.head_verified_at,
       i.object_uri
  from nfe_migration_item i
 where i.batch_id=(select max(batch_id) from nfe_migration_batch where batch_code like 'OCI-HEAD-SMOKE-%');
