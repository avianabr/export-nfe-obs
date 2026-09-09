-- Run as NFE_OWNER after ddl/41_create_nfe_classic_aq_migration_package.sql.
-- This worker consumes only the separate classic AQ queue. PKG_NFE_WORKER and
-- NFE_MIGRATION_Q remain the unchanged TEQ implementation/evidence path.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

create or replace package pkg_nfe_classic_aq_worker authid definer as
  procedure dequeue_and_load(
    p_control_id  out nfe_migration_item.control_id%type,
    p_nfe_id      out poc_nfe_document.nfe_id%type,
    p_batch_id    out nfe_migration_batch.batch_id%type,
    p_xml_clob    out nocopy clob,
    p_msgid       out raw,
    p_correlation in varchar2 default null);

  procedure process_one(
    p_simulate_transient in boolean default false,
    p_correlation        in varchar2 default null);
end pkg_nfe_classic_aq_worker;
/

create or replace package body pkg_nfe_classic_aq_worker as
  c_queue constant varchar2(30) := 'NFE_CLASSIC_AQ_Q';

  procedure dequeue_and_load(
    p_control_id  out nfe_migration_item.control_id%type,
    p_nfe_id      out poc_nfe_document.nfe_id%type,
    p_batch_id    out nfe_migration_batch.batch_id%type,
    p_xml_clob    out nocopy clob,
    p_msgid       out raw,
    p_correlation in varchar2 default null) is
    l_deq              dbms_aq.dequeue_options_t;
    l_props            dbms_aq.message_properties_t;
    l_payload          raw(2000);
    l_json             varchar2(32767);
    l_version          number;
    l_payload_control  number;
    l_payload_nfe      number;
    l_payload_batch    number;
    l_item_status      nfe_migration_item.status%type;
    l_batch_status     nfe_migration_batch.status%type;
  begin
    l_deq.visibility := dbms_aq.on_commit;
    l_deq.dequeue_mode := dbms_aq.remove;
    l_deq.navigation := dbms_aq.first_message;
    l_deq.wait := dbms_aq.no_wait;
    l_deq.correlation := p_correlation;
    dbms_aq.dequeue(c_queue, l_deq, l_props, l_payload, p_msgid);

    begin
      l_json := utl_i18n.raw_to_char(l_payload, 'AL32UTF8');
      select json_value(l_json, '$.version' returning number error on error),
             json_value(l_json, '$.controlId' returning number error on error),
             json_value(l_json, '$.nfeId' returning number error on error),
             json_value(l_json, '$.batchId' returning number error on error)
        into l_version, l_payload_control, l_payload_nfe, l_payload_batch
        from dual;
    exception
      when others then
        raise_application_error(-20230,
          'Invalid classic AQ reference-envelope JSON contract.');
    end;

    if l_version <> 1 or l_payload_control is null or l_payload_nfe is null
       or l_payload_batch is null or l_payload_control <= 0
       or l_payload_nfe <= 0 or l_payload_batch <= 0 then
      raise_application_error(-20231,
        'Classic AQ envelope requires version and positive control references.');
    end if;

    begin
      select i.control_id, i.nfe_id, i.batch_id, i.status, b.status, d.xml_clob
        into p_control_id, p_nfe_id, p_batch_id, l_item_status, l_batch_status,
             p_xml_clob
        from nfe_migration_item i
        join nfe_migration_batch b on b.batch_id = i.batch_id
        join poc_nfe_document d on d.nfe_id = i.nfe_id
       where i.control_id = l_payload_control
       for update of i.status;
    exception
      when no_data_found then
        raise_application_error(-20232,
          'Classic AQ envelope control item or source content was not found.');
    end;

    if p_control_id <> l_payload_control or p_nfe_id <> l_payload_nfe
       or p_batch_id <> l_payload_batch then
      raise_application_error(-20233,
        'Classic AQ envelope references do not match its control item.');
    end if;
    if l_batch_status <> 'PROCESSING' or l_item_status <> 'QUEUED' then
      raise_application_error(-20234,
        'Classic AQ item is not eligible for processing.');
    end if;
    if p_xml_clob is null then
      raise_application_error(-20235, 'Classic AQ source content is absent.');
    end if;
    -- Protects both disabled transport and a batch without an explicit mode.
    pkg_nfe_classic_aq_config.assert_classic_aq_selected(p_batch_id);
  end dequeue_and_load;

  procedure process_one(
    p_simulate_transient in boolean default false,
    p_correlation        in varchar2 default null) is
    l_control_id number;
    l_nfe_id     number;
    l_batch_id   number;
    l_xml_clob   clob;
    l_msgid      raw(16);
  begin
    dequeue_and_load(l_control_id, l_nfe_id, l_batch_id, l_xml_clob, l_msgid,
                     p_correlation);
    if p_simulate_transient then
      -- Test hook only: fail before any Object Storage call. The enclosing
      -- rollback returns the AQ delivery without creating an external object.
      raise_application_error(-20236, 'Simulated classic AQ transient failure.');
    end if;
    pkg_nfe_worker.upload_item(l_control_id);
    -- An existing divergent object is a terminal, audited item exception. It
    -- is not a transient dequeue failure, so commit the EXCEPTION state with
    -- the REMOVE acknowledgement instead of redelivering indefinitely.
    declare
      l_status nfe_migration_item.status%type;
    begin
      select status into l_status from nfe_migration_item where control_id = l_control_id;
      if l_status = 'EXCEPTION' then
        commit;
        return;
      end if;
    end;
    pkg_nfe_worker.verify_uploaded_item(l_control_id);
    pkg_nfe_audit.log_event(
      p_actor_type => 'WORKER',
      p_event_type => 'CLASSIC_AQ_WORKER_VERIFIED',
      p_batch_id => l_batch_id,
      p_control_id => l_control_id,
      p_to_status => 'VERIFIED',
      p_correlation_id => p_correlation,
      p_details_json => '{"transportMode":"CLASSIC_AQ"}');
    -- The item success and REMOVE acknowledgement persist in this same commit.
    commit;
  exception
    when others then
      -- Roll back both item changes and the REMOVE delivery acknowledgement so
      -- AQ may redeliver according to the queue retry policy.
      rollback;
      raise;
  end process_one;
end pkg_nfe_classic_aq_worker;
/

prompt PASS: classic AQ transactional worker package created.
