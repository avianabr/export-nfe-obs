-- Run as NFE_OWNER after redeploying ddl/45. Uses two new synthetic NF-es and
-- two dedicated Object Storage keys: one preloaded with identical content and
-- one with divergent content. No existing object, source XML, TEQ artifact,
-- or purge state is changed.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  c_credential constant varchar2(128) := 'NFE_OBJECT_STORAGE_S3_CRED';
  l_marker varchar2(16) := substr(rawtohex(sys_guid()),1,16);
  l_enabled char(1);
  l_identical_batch number; l_divergent_batch number;
  l_identical_control number; l_divergent_control number;
  l_identical_uri varchar2(2000); l_divergent_uri varchar2(2000);
  l_admitted pls_integer; l_status varchar2(30); l_count pls_integer;

  procedure create_batch(p_kind varchar2, p_batch out number, p_control out number,
                         p_uri out varchar2) is
    l_nfe number; l_key varchar2(44);
  begin
    l_key := rpad('AQOBJ' || p_kind || l_marker,44,'0');
    insert into poc_nfe_document(chave_nfe,emitente_cnpj,destinatario_cnpj,data_emissao,situacao,xml_clob)
    values(l_key,'00000000000000','00000000000000',systimestamp,'AUTORIZADA',
           '<nfe><classic-aq-object-test>'||p_kind||'</classic-aq-object-test></nfe>')
    returning nfe_id into l_nfe;
    insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,criteria_json,created_by)
    values('AQOBJ-'||p_kind||'-'||l_marker,'CREATED',systimestamp+interval '1' day,1,
           '{"eligibleSituations":["AUTORIZADA"],"benchmarkKeyPrefix":"'||substr(l_key,1,20)||'"}',
           sys_context('USERENV','SESSION_USER')) returning batch_id into p_batch;
    pkg_nfe_classic_aq_config.select_classic_aq(p_batch);
    commit;
    pkg_nfe_classic_aq_migration.admit_chunk(p_batch,1,l_admitted);
    if l_admitted <> 1 then raise_application_error(-20330,'Expected one classic AQ item.'); end if;
    commit;
    select control_id,object_uri into p_control,p_uri from nfe_migration_item where batch_id=p_batch;
  end;

  procedure preload(p_uri varchar2,p_text clob) is
    l_blob blob;
  begin
    pkg_nfe_transfer.clob_to_utf8_blob(p_text,l_blob);
    dbms_cloud.put_object(c_credential,p_uri,l_blob);
    pkg_nfe_transfer.free_temporary_blob(l_blob);
  exception when others then pkg_nfe_transfer.free_temporary_blob(l_blob); raise; end;
begin
  pkg_nfe_classic_aq_config.get_classic_aq_enabled(l_enabled);
  if l_enabled <> 'N' then raise_application_error(-20331,'Classic AQ must be disabled before this test.'); end if;
  pkg_nfe_classic_aq_config.set_classic_aq_enabled('Y'); commit;

  create_batch('SAME',l_identical_batch,l_identical_control,l_identical_uri);
  preload(l_identical_uri,'<nfe><classic-aq-object-test>SAME</classic-aq-object-test></nfe>');
  pkg_nfe_classic_aq_worker.process_one(false,'NFE-CLASSIC-'||l_identical_control);
  select status into l_status from nfe_migration_item where control_id=l_identical_control;
  if l_status <> 'VERIFIED' then raise_application_error(-20332,'Identical object did not verify.'); end if;

  create_batch('DIFF',l_divergent_batch,l_divergent_control,l_divergent_uri);
  preload(l_divergent_uri,'<nfe><classic-aq-object-test>DIFFERENT</classic-aq-object-test></nfe>');
  pkg_nfe_classic_aq_worker.process_one(false,'NFE-CLASSIC-'||l_divergent_control);
  select status into l_status from nfe_migration_item where control_id=l_divergent_control;
  if l_status <> 'EXCEPTION' then raise_application_error(-20333,'Divergent object did not become EXCEPTION.'); end if;
  select count(*) into l_count from aq$nfe_classic_aq_qt
   where corr_id in ('NFE-CLASSIC-'||l_identical_control,'NFE-CLASSIC-'||l_divergent_control)
     and msg_state='READY';
  if l_count <> 0 then raise_application_error(-20334,'Object tests left READY messages.'); end if;
  pkg_nfe_classic_aq_config.set_classic_aq_enabled('N'); commit;
  dbms_output.put_line('PASS: classic AQ accepts identical object and exposes divergent object as EXCEPTION.');
exception when others then rollback; begin pkg_nfe_classic_aq_config.set_classic_aq_enabled('N'); commit; exception when others then rollback; end; raise; end;
/
