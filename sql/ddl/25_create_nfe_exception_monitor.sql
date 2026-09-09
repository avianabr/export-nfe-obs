-- Run as NFE_OWNER after TEQ and PKG_NFE_AUDIT are deployed.
whenever sqlerror exit failure rollback
create or replace package pkg_nfe_exception_monitor authid definer as
  procedure drain_one(p_processed out pls_integer, p_correlation in varchar2 default null);
end;
/
create or replace package body pkg_nfe_exception_monitor as
  procedure drain_one(p_processed out pls_integer, p_correlation in varchar2 default null) is
    l_opt dbms_aq.dequeue_options_t; l_prop dbms_aq.message_properties_t;
    l_payload raw(2000); l_msgid raw(16); l_control number; l_batch number;
  begin
    p_processed:=0; l_opt.visibility:=dbms_aq.on_commit; l_opt.dequeue_mode:=dbms_aq.remove;
    l_opt.wait:=dbms_aq.no_wait; l_opt.navigation:=dbms_aq.first_message; l_opt.correlation:=p_correlation;
    dbms_aq.dequeue('NFE_MIGRATION_EX_Q',l_opt,l_prop,l_payload,l_msgid);
    select json_value(utl_i18n.raw_to_char(l_payload,'AL32UTF8'),'$.controlId' returning number error on error),
           json_value(utl_i18n.raw_to_char(l_payload,'AL32UTF8'),'$.batchId' returning number error on error)
      into l_control,l_batch from dual;
    update nfe_migration_item set status='EXCEPTION',last_error_code='TEQ_MAX_RETRIES',last_error='TEQ retry limit exceeded.',last_error_at=systimestamp
     where control_id=l_control and status in ('QUEUED','UPLOADING','UPLOADED','VERIFYING');
    update nfe_migration_batch set exception_count=exception_count+1 where batch_id=l_batch;
    pkg_nfe_audit.log_event('SYSTEM','EXCEPTION_ALERT',l_batch,l_control,null,'EXCEPTION',l_prop.correlation,'{"reason":"TEQ_MAX_RETRIES"}');
    p_processed:=1; commit;
  exception when others then rollback; raise; end;
end;
/
prompt PASS: exception monitor created.
