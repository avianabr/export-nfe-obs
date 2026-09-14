-- Removes only records created by 17_verify_classic_aq_invalid_mode_redelivery.sql.
-- Run as NFE_OWNER after an interrupted or failed invalid-mode redelivery test.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on verify off

declare
  l_removed number := 0;
  l_deq     dbms_aq.dequeue_options_t;
  l_props   dbms_aq.message_properties_t;
  l_payload raw(2000);
  l_msgid   raw(16);
begin
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  for r in (
    select i.control_id
      from nfe_migration_item i
      join nfe_migration_batch b on b.batch_id=i.batch_id
     where b.batch_code like 'INVALID-MODE-REDELIVERY-%'
       and i.aq_msgid is not null
  ) loop
    begin
      l_deq.visibility:=dbms_aq.on_commit;
      l_deq.dequeue_mode:=dbms_aq.remove;
      l_deq.wait:=10;
      l_deq.correlation:='NFE-CLASSIC-'||r.control_id;
      dbms_aq.dequeue('NFE_CLASSIC_AQ_Q',l_deq,l_props,l_payload,l_msgid);
    exception when others then
      if sqlcode not in (-25228,-25263) then raise; end if;
    end;
  end loop;
  delete from poc_nfe_oci_10k
   where nfe_id in (
     select i.nfe_id
       from nfe_migration_item i
       join nfe_migration_batch b on b.batch_id=i.batch_id
      where b.batch_code like 'INVALID-MODE-REDELIVERY-%');
  delete from nfe_migration_item
   where batch_id in (
     select batch_id from nfe_migration_batch
      where batch_code like 'INVALID-MODE-REDELIVERY-%');
  delete from nfe_migration_batch
   where batch_code like 'INVALID-MODE-REDELIVERY-%';
  l_removed:=sql%rowcount;
  commit;
  dbms_output.put_line('PASS: invalid-mode redelivery test records removed; batches='||l_removed||'.');
end;
/
