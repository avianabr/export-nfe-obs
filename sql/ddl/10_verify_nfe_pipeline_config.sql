-- Run as NFE_OWNER after 09_create_nfe_pipeline_config.sql.
-- Uses a rollback-only test batch and restores the configuration before exit.

whenever oserror exit failure rollback
set serveroutput on size unlimited

declare
  l_batch_id        nfe_migration_batch.batch_id%type;
  l_batch_code      nfe_migration_batch.batch_code%type :=
    'CFG-TEST-' || substr(rawtohex(sys_guid()), 1, 32);
  l_paused          nfe_migration_config.pipeline_paused%type;
  l_max_inflight    nfe_migration_config.max_inflight_messages%type;
  l_chunk_size      nfe_migration_config.enqueue_chunk_size%type;
  l_worker_count    nfe_migration_config.worker_count%type;
  l_idle_seconds    nfe_migration_config.worker_idle_seconds%type;
  l_run_minutes     nfe_migration_config.max_worker_run_minutes%type;
  l_items_before    pls_integer;
  l_items_after     pls_integer;
  l_pause_rejected  boolean := false;
begin
  pkg_nfe_pipeline_config.get_config(
    l_paused, l_max_inflight, l_chunk_size, l_worker_count,
    l_idle_seconds, l_run_minutes);

  insert into nfe_migration_batch (
    batch_code, status, cutoff_date, max_documents, selection_chunk_size,
    criteria_json, created_by)
  values (
    l_batch_code, 'CREATED', systimestamp, 1, 1,
    '{"purpose":"configuration verification"}',
    sys_context('USERENV', 'SESSION_USER'))
  returning batch_id into l_batch_id;

  update nfe_migration_batch
     set status = 'SELECTING'
   where batch_id = l_batch_id;

  select count(*) into l_items_before from nfe_migration_item;

  pkg_nfe_pipeline_config.assert_admission_allowed(l_batch_id, 1);

  pkg_nfe_pipeline_config.set_config(
    'Y', l_max_inflight, l_chunk_size, l_worker_count,
    l_idle_seconds, l_run_minutes);

  begin
    pkg_nfe_pipeline_config.assert_admission_allowed(l_batch_id, 1);
  exception
    when others then
      if sqlcode = -20042 then
        l_pause_rejected := true;
      else
        raise;
      end if;
  end;

  select count(*) into l_items_after from nfe_migration_item;
  if not l_pause_rejected or l_items_before <> l_items_after then
    raise_application_error(-20047,
      'Pipeline pause did not safely restrict admission.');
  end if;

  rollback;
  dbms_output.put_line(
    'PASS: configuration reads restrict admission and leave confirmed backlog intact.');
exception
  when others then
    rollback;
    raise;
end;
/
