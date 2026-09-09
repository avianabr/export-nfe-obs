-- Run as NFE_OWNER after 14_create_nfe_migration_package.sql.
-- This is rollback-only: the transient batch/item and configuration changes
-- are discarded, while the already committed item and TEQ backlog are checked.

whenever oserror exit failure rollback
set serveroutput on size unlimited

declare
  l_batch_id          nfe_migration_batch.batch_id%type;
  l_nfe_id            poc_nfe_document.nfe_id%type;
  l_batch_code        nfe_migration_batch.batch_code%type :=
    'ADMISSION-TEST-' || substr(rawtohex(sys_guid()), 1, 24);
  l_paused            nfe_migration_config.pipeline_paused%type;
  l_max_inflight      nfe_migration_config.max_inflight_messages%type;
  l_chunk_size        nfe_migration_config.enqueue_chunk_size%type;
  l_worker_count      nfe_migration_config.worker_count%type;
  l_idle_seconds      nfe_migration_config.worker_idle_seconds%type;
  l_run_minutes       nfe_migration_config.max_worker_run_minutes%type;
  l_backlog_before    pls_integer;
  l_backlog_after     pls_integer;
  l_ready_before      pls_integer;
  l_ready_after       pls_integer;
  l_inflight_for_test pls_integer;
  l_status_rejected   boolean := false;
  l_pause_rejected    boolean := false;
  l_max_rejected      boolean := false;
  l_inflight_rejected boolean := false;

  procedure expect_rejection(p_expected_code in pls_integer) is
  begin
    begin
      pkg_nfe_pipeline_config.assert_admission_allowed(l_batch_id, 1);
      raise_application_error(-20070,
        'Admission unexpectedly succeeded; expected ' || p_expected_code || '.');
    exception
      when others then
        if sqlcode <> p_expected_code then
          raise;
        end if;
    end;
  end expect_rejection;
begin
  pkg_nfe_pipeline_config.get_config(
    l_paused, l_max_inflight, l_chunk_size, l_worker_count,
    l_idle_seconds, l_run_minutes);

  select count(*) into l_backlog_before
    from nfe_migration_item;
  select count(*) into l_ready_before
    from aq$nfe_migration_q
   where msg_state = 'READY';

  insert into nfe_migration_batch (
    batch_code, status, cutoff_date, max_documents, selection_chunk_size,
    criteria_json, created_by)
  values (
    l_batch_code, 'CREATED', systimestamp - interval '1' day, 2, 1,
    '{"purpose":"admission control verification"}',
    sys_context('USERENV', 'SESSION_USER'))
  returning batch_id into l_batch_id;

  -- Normalize the test only; the original configuration is restored by rollback.
  pkg_nfe_pipeline_config.set_config(
    'N', greatest(l_max_inflight, 1), greatest(l_chunk_size, 1), l_worker_count,
    l_idle_seconds, l_run_minutes);

  expect_rejection(-20044);
  l_status_rejected := true;

  pkg_nfe_pipeline_config.set_config(
    'Y', greatest(l_max_inflight, 1), greatest(l_chunk_size, 1), l_worker_count,
    l_idle_seconds, l_run_minutes);
  expect_rejection(-20042);
  l_pause_rejected := true;

  -- Resume admission without changing any committed item or TEQ message.
  pkg_nfe_pipeline_config.set_config(
    'N', greatest(l_max_inflight, 1), greatest(l_chunk_size, 1), l_worker_count,
    l_idle_seconds, l_run_minutes);
  update nfe_migration_batch
     set status = 'SELECTING', selected_count = 2
   where batch_id = l_batch_id;
  expect_rejection(-20045);
  l_max_rejected := true;

  update nfe_migration_batch
     set selected_count = 0
   where batch_id = l_batch_id;

  select nfe_id into l_nfe_id
    from poc_nfe_document d
   where not exists (
           select 1 from nfe_migration_item i where i.nfe_id = d.nfe_id)
     and rownum = 1;

  -- A transient QUEUED item supplies a deterministic inflight backlog even if
  -- the script is rerun after real workers have drained their prior work.
  insert into nfe_migration_item (
    batch_id, nfe_id, status, object_key, object_uri)
  values (
    l_batch_id, l_nfe_id, 'QUEUED', 'test/admission/' || l_nfe_id || '.xml',
    'https://example.invalid/test/admission/' || l_nfe_id || '.xml');

  select count(*) into l_inflight_for_test
    from nfe_migration_item
   where status in ('QUEUED', 'UPLOADING', 'UPLOADED', 'VERIFYING');

  pkg_nfe_pipeline_config.set_config(
    'N', l_inflight_for_test, greatest(l_chunk_size, 1), l_worker_count,
    l_idle_seconds, l_run_minutes);
  expect_rejection(-20046);
  l_inflight_rejected := true;

  select count(*) into l_backlog_after
    from nfe_migration_item
   where batch_id <> l_batch_id;
  select count(*) into l_ready_after
    from aq$nfe_migration_q
   where msg_state = 'READY';

  if not l_status_rejected or not l_pause_rejected or not l_max_rejected
     or not l_inflight_rejected
     or l_backlog_after <> l_backlog_before
     or l_ready_after <> l_ready_before then
    raise_application_error(-20071,
      'Admission control did not preserve the committed backlog on resume.');
  end if;

  rollback;
  dbms_output.put_line(
    'PASS: status, pause, batch cap and inflight cap block admission; resume preserves committed backlog.');
exception
  when others then
    rollback;
    raise;
end;
/
