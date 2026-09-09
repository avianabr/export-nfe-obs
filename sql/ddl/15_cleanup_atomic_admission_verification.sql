-- Run as NFE_OWNER only to clean failed 15_verify_atomic_admission.sql runs.
-- Targets exclusively batches created by that verifier (ATOMIC-*).
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_deq dbms_aq.dequeue_options_t; l_props dbms_aq.message_properties_t;
  l_payload raw(2000); l_received_msgid raw(16);
begin
  for r in (
    select i.control_id, i.nfe_id, i.aq_msgid
      from nfe_migration_item i join nfe_migration_batch b on b.batch_id=i.batch_id
     where b.batch_code like 'ATOMIC-%') loop
    if r.aq_msgid is not null then
      begin
        l_deq.visibility:=dbms_aq.on_commit; l_deq.dequeue_mode:=dbms_aq.remove;
        l_deq.wait:=dbms_aq.no_wait; l_deq.navigation:=dbms_aq.first_message;
        l_deq.msgid:=r.aq_msgid;
        dbms_aq.dequeue('NFE_MIGRATION_Q',l_deq,l_props,l_payload,l_received_msgid);
        commit;
      exception when others then
        if sqlcode<>-25228 then raise; end if;
      end;
    end if;
    delete from nfe_migration_item where control_id=r.control_id;
    delete from poc_nfe_document where nfe_id=r.nfe_id;
  end loop;
  delete from nfe_migration_batch where batch_code like 'ATOMIC-%';
  commit;
  dbms_output.put_line('PASS: stale atomic-admission verification artifacts removed.');
exception when others then rollback; raise; end;
/
