-- Run as NFE_OWNER after 19_create_nfe_worker_package.sql.
-- Creates and removes dedicated test messages; it never marks an item VERIFIED.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_marker       varchar2(24) := substr(rawtohex(sys_guid()), 1, 24);
  l_batch_id     number;
  l_nfe_id       number;
  l_control_id   number;
  l_loaded_id    number;
  l_loaded_nfe   number;
  l_loaded_batch number;
  l_xml          clob;
  l_msgid        raw(16);
  l_payload      raw(2000);
  l_enq          dbms_aq.enqueue_options_t;
  l_deq          dbms_aq.dequeue_options_t;
  l_props        dbms_aq.message_properties_t;
  l_status       varchar2(30);
  l_invalid_rejected boolean := false;

  procedure remove_test_message(p_correlation in varchar2) is
    l_removed_payload raw(2000);
    l_removed_msgid   raw(16);
    l_removed_props   dbms_aq.message_properties_t;
    l_removed_deq     dbms_aq.dequeue_options_t;
  begin
    l_removed_deq.visibility := dbms_aq.on_commit;
    l_removed_deq.dequeue_mode := dbms_aq.remove;
    l_removed_deq.wait := dbms_aq.no_wait;
    l_removed_deq.navigation := dbms_aq.first_message;
    l_removed_deq.correlation := p_correlation;
    dbms_aq.dequeue('NFE_MIGRATION_Q', l_removed_deq, l_removed_props,
                    l_removed_payload, l_removed_msgid);
    commit;
  end remove_test_message;
begin
  select nfe_id into l_nfe_id
    from poc_nfe_document d
   where d.xml_clob is not null
     and not exists (select 1 from nfe_migration_item i where i.nfe_id = d.nfe_id)
     and rownum = 1;

  insert into nfe_migration_batch (
    batch_code, status, cutoff_date, max_documents, selection_chunk_size,
    criteria_json, created_by)
  values (
    'WORKER-TEST-' || l_marker, 'CREATED', systimestamp - interval '1' day,
    1, 1, '{"purpose":"worker dequeue verification"}',
    sys_context('USERENV', 'SESSION_USER'))
  returning batch_id into l_batch_id;
  update nfe_migration_batch set status = 'SELECTING' where batch_id = l_batch_id;
  insert into nfe_migration_item (
    batch_id, nfe_id, status, object_key, object_uri)
  values (
    l_batch_id, l_nfe_id, 'QUEUED', 'test/worker/' || l_marker || '.xml',
    'https://example.invalid/test/worker/' || l_marker || '.xml')
  returning control_id into l_control_id;
  commit;

  l_enq.visibility := dbms_aq.on_commit;
  l_props.correlation := 'WORKER-VALID-' || l_marker;
  l_props.exception_queue := 'NFE_MIGRATION_EX_Q';
  l_payload := utl_i18n.string_to_raw(
    '{"eventType":"NFE_MIGRATION","version":1,"controlId":' || l_control_id ||
    ',"nfeId":' || l_nfe_id || ',"batchId":' || l_batch_id || '}', 'AL32UTF8');
  dbms_aq.enqueue('NFE_MIGRATION_Q', l_enq, l_props, l_payload, l_msgid);
  commit;

  pkg_nfe_worker.dequeue_and_load(
    l_loaded_id, l_loaded_nfe, l_loaded_batch, l_xml, l_msgid,
    'WORKER-VALID-' || l_marker);
  if l_loaded_id <> l_control_id or l_loaded_nfe <> l_nfe_id
     or l_loaded_batch <> l_batch_id or dbms_lob.getlength(l_xml) = 0 then
    raise_application_error(-20090, 'Valid envelope did not load its control item and XML.');
  end if;
  rollback;
  remove_test_message('WORKER-VALID-' || l_marker);

  l_props.correlation := 'WORKER-INVALID-' || l_marker;
  l_props.exception_queue := 'NFE_MIGRATION_EX_Q';
  l_payload := utl_i18n.string_to_raw(
    '{"eventType":"NFE_MIGRATION","version":99,"controlId":' || l_control_id ||
    ',"nfeId":' || l_nfe_id || ',"batchId":' || l_batch_id || '}', 'AL32UTF8');
  dbms_aq.enqueue('NFE_MIGRATION_Q', l_enq, l_props, l_payload, l_msgid);
  commit;

  begin
    pkg_nfe_worker.dequeue_and_load(
      l_loaded_id, l_loaded_nfe, l_loaded_batch, l_xml, l_msgid,
      'WORKER-INVALID-' || l_marker);
    raise_application_error(-20091, 'Invalid envelope was accepted.');
  exception
    when others then
      if sqlcode <> -20054 then
        raise;
      end if;
      l_invalid_rejected := true;
      rollback;
  end;
  remove_test_message('WORKER-INVALID-' || l_marker);

  select status into l_status from nfe_migration_item where control_id = l_control_id;
  if not l_invalid_rejected or l_status <> 'QUEUED' then
    raise_application_error(-20092,
      'Invalid envelope changed the control item or was not rejected.');
  end if;

  delete from nfe_migration_item where control_id = l_control_id;
  delete from nfe_migration_batch where batch_id = l_batch_id;
  commit;
  dbms_output.put_line(
    'PASS: transactional dequeue validates the envelope and loads XML; invalid payload leaves no VERIFIED item.');
exception
  when others then
    rollback;
    raise;
end;
/
