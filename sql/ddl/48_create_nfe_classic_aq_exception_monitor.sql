-- Run as NFE_OWNER after ddl/45_create_nfe_classic_aq_worker_package.sql.
-- Separate from PKG_NFE_EXCEPTION_MONITOR, which remains dedicated to TEQ.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

create or replace package pkg_nfe_classic_aq_exception_monitor authid definer as
  procedure drain_one(
    p_processed out pls_integer,
    p_correlation in varchar2 default null);
end pkg_nfe_classic_aq_exception_monitor;
/

create or replace package body pkg_nfe_classic_aq_exception_monitor as
  c_exception_queue constant varchar2(30) := 'NFE_CLASSIC_AQ_EX_Q';

  procedure drain_one(
    p_processed out pls_integer,
    p_correlation in varchar2 default null) is
    l_deq             dbms_aq.dequeue_options_t;
    l_props           dbms_aq.message_properties_t;
    l_payload         raw(2000);
    l_msgid           raw(16);
    l_json            varchar2(32767);
    l_version         number;
    l_control_id      number;
    l_nfe_id          number;
    l_batch_id        number;
    l_item_nfe_id     number;
    l_item_batch_id   number;
  begin
    p_processed := 0;
    l_deq.visibility := dbms_aq.on_commit;
    l_deq.dequeue_mode := dbms_aq.remove;
    l_deq.navigation := dbms_aq.first_message;
    l_deq.wait := dbms_aq.no_wait;
    l_deq.correlation := p_correlation;
    dbms_aq.dequeue(c_exception_queue, l_deq, l_props, l_payload, l_msgid);

    begin
      l_json := utl_i18n.raw_to_char(l_payload, 'AL32UTF8');
      select json_value(l_json, '$.version' returning number error on error),
             json_value(l_json, '$.controlId' returning number error on error),
             json_value(l_json, '$.nfeId' returning number error on error),
             json_value(l_json, '$.batchId' returning number error on error)
        into l_version, l_control_id, l_nfe_id, l_batch_id
        from dual;
    exception
      when others then
        raise_application_error(-20260,
          'Invalid classic AQ exception-envelope JSON contract.');
    end;
    if l_version <> 1 or l_control_id is null or l_nfe_id is null
       or l_batch_id is null then
      raise_application_error(-20261,
        'Classic AQ exception envelope has incomplete references.');
    end if;

    select nfe_id, batch_id into l_item_nfe_id, l_item_batch_id
      from nfe_migration_item
     where control_id = l_control_id
       for update;
    if l_item_nfe_id <> l_nfe_id or l_item_batch_id <> l_batch_id then
      raise_application_error(-20262,
        'Classic AQ exception envelope does not match its control item.');
    end if;

    update nfe_migration_item
       set status = 'EXCEPTION',
           last_error_code = 'CLASSIC_AQ_MAX_RETRIES',
           last_error = 'Classic AQ retry limit exceeded.',
           last_error_at = systimestamp
     where control_id = l_control_id
       and status in ('QUEUED', 'UPLOADING', 'UPLOADED', 'VERIFYING');
    if sql%rowcount <> 1 then
      raise_application_error(-20263,
        'Classic AQ exception item is not in a retry-eligible state.');
    end if;
    update nfe_migration_batch
       set exception_count = exception_count + 1
     where batch_id = l_batch_id;
    pkg_nfe_audit.log_event(
      p_actor_type => 'SYSTEM',
      p_event_type => 'CLASSIC_AQ_EXCEPTION_ALERT',
      p_batch_id => l_batch_id,
      p_control_id => l_control_id,
      p_from_status => 'QUEUED',
      p_to_status => 'EXCEPTION',
      p_correlation_id => l_props.correlation,
      p_details_json => '{"reason":"CLASSIC_AQ_MAX_RETRIES"}');
    p_processed := 1;
    commit;
  exception
    when others then
      rollback;
      raise;
  end drain_one;
end pkg_nfe_classic_aq_exception_monitor;
/

prompt PASS: classic AQ exception monitor created.
