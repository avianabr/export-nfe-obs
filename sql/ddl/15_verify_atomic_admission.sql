-- Run as NFE_OWNER. Uses one untracked synthetic document and removes its
-- temporary batch, control item, and TEQ message after proving both paths.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_batch_id number; l_nfe_id number; l_key varchar2(44); l_before pls_integer; l_count pls_integer;
  l_admitted pls_integer; l_control_id number; l_target_msgid raw(16);
  l_deq dbms_aq.dequeue_options_t; l_props dbms_aq.message_properties_t;
  l_payload raw(2000); l_received_msgid raw(16);
begin
  l_key := '000020260904' || lpad(to_char(systimestamp,'YYYYMMDDHH24MISSFF3'),32,'0');
  insert into poc_nfe_document(chave_nfe,data_emissao,situacao,xml_clob)
  values(l_key,systimestamp-interval '2' day,'AUTORIZADA',to_clob('<NFe>atomic admission test</NFe>'))
  returning nfe_id into l_nfe_id;
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,selection_chunk_size,criteria_json,created_by)
  values('ATOMIC-'||substr(rawtohex(sys_guid()),1,20),'CREATED',systimestamp-interval '1' day,1,1,
    '{"eligibleSituations":["AUTORIZADA","CANCELADA","DENEGADA"],"benchmarkKeyPrefix":"000020260904","purpose":"atomic admission verification"}',user)
  returning batch_id into l_batch_id;
  commit;
  update nfe_migration_batch set status='SELECTING' where batch_id=l_batch_id;
  commit;
  select count(*) into l_before from nfe_migration_item;
  pkg_nfe_migration.admit_chunk(l_batch_id,1,l_admitted);
  if l_admitted<>1 then raise_application_error(-20062,'No synthetic document admitted for rollback test.'); end if;
  select count(*) into l_count from nfe_migration_item where batch_id=l_batch_id and status='QUEUED';
  if l_count<>1 then raise_application_error(-20063,'Control item missing before rollback.'); end if;
  rollback;
  select count(*) into l_count from nfe_migration_item;
  if l_count<>l_before then raise_application_error(-20064,'Rollback left a control item.'); end if;
  pkg_nfe_migration.admit_chunk(l_batch_id,1,l_admitted);
  commit;
  select control_id,aq_msgid into l_control_id,l_target_msgid from nfe_migration_item where batch_id=l_batch_id;
  select count(*) into l_count from aq$nfe_migration_q where corr_id='NFE-MIG-'||l_control_id and msg_state='READY';
  if l_admitted<>1 or l_count<>1 then raise_application_error(-20065,'Commit did not expose item and TEQ message together.'); end if;
  l_deq.visibility:=dbms_aq.on_commit; l_deq.dequeue_mode:=dbms_aq.remove;
  l_deq.wait:=dbms_aq.no_wait; l_deq.navigation:=dbms_aq.first_message;
  l_deq.msgid:=l_target_msgid;
  dbms_aq.dequeue('NFE_MIGRATION_Q',l_deq,l_props,l_payload,l_received_msgid);
  commit;
  delete from nfe_migration_item where control_id=l_control_id;
  delete from nfe_migration_batch where batch_id=l_batch_id;
  delete from poc_nfe_document where nfe_id=l_nfe_id;
  commit;
  dbms_output.put_line('PASS: rollback leaves no item; commit exposes item/message together; test artifacts removed.');
exception when others then rollback; raise;
end;
/
