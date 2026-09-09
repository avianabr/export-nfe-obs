-- Run as NFE_OWNER only to clean failed 24_verify_nfe_transient_redelivery.sql runs.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_deq dbms_aq.dequeue_options_t; l_props dbms_aq.message_properties_t;
  l_payload raw(2000); l_received_msgid raw(16);
begin
  for r in (select i.control_id,i.aq_msgid from nfe_migration_item i
              join nfe_migration_batch b on b.batch_id=i.batch_id
             where b.batch_code like 'RETRY-%') loop
    if r.aq_msgid is not null then
      begin
        l_deq.visibility:=dbms_aq.on_commit; l_deq.dequeue_mode:=dbms_aq.remove;
        l_deq.wait:=dbms_aq.no_wait; l_deq.navigation:=dbms_aq.first_message; l_deq.msgid:=r.aq_msgid;
        dbms_aq.dequeue('NFE_MIGRATION_Q',l_deq,l_props,l_payload,l_received_msgid);
        commit;
      exception when others then if sqlcode<>-25228 then raise; end if; end;
    end if;
  end loop;
  commit;
  dbms_output.put_line('PASS: stale transient test messages removed; audited control evidence retained.');
exception when others then rollback; raise; end;
/
