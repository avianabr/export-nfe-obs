-- Run as NFE_OWNER after the base schema and PKG_NFE_AUDIT are deployed.
-- Runtime users receive no direct grant on NFE_MIGRATION_CONFIG; future
-- selection and worker packages call this definer-rights package instead.

whenever oserror exit failure rollback

create or replace package pkg_nfe_pipeline_config authid definer as
  procedure get_config(
    p_pipeline_paused         out nfe_migration_config.pipeline_paused%type,
    p_max_inflight_messages   out nfe_migration_config.max_inflight_messages%type,
    p_enqueue_chunk_size      out nfe_migration_config.enqueue_chunk_size%type,
    p_worker_count            out nfe_migration_config.worker_count%type,
    p_worker_idle_seconds     out nfe_migration_config.worker_idle_seconds%type,
    p_max_worker_run_minutes  out nfe_migration_config.max_worker_run_minutes%type);

  procedure set_config(
    p_pipeline_paused         in nfe_migration_config.pipeline_paused%type,
    p_max_inflight_messages   in nfe_migration_config.max_inflight_messages%type,
    p_enqueue_chunk_size      in nfe_migration_config.enqueue_chunk_size%type,
    p_worker_count            in nfe_migration_config.worker_count%type,
    p_worker_idle_seconds     in nfe_migration_config.worker_idle_seconds%type,
    p_max_worker_run_minutes  in nfe_migration_config.max_worker_run_minutes%type);

  procedure assert_admission_allowed(
    p_batch_id         in nfe_migration_batch.batch_id%type,
    p_requested_count  in pls_integer);
end pkg_nfe_pipeline_config;
/

create or replace package body pkg_nfe_pipeline_config as
  procedure get_config(
    p_pipeline_paused         out nfe_migration_config.pipeline_paused%type,
    p_max_inflight_messages   out nfe_migration_config.max_inflight_messages%type,
    p_enqueue_chunk_size      out nfe_migration_config.enqueue_chunk_size%type,
    p_worker_count            out nfe_migration_config.worker_count%type,
    p_worker_idle_seconds     out nfe_migration_config.worker_idle_seconds%type,
    p_max_worker_run_minutes  out nfe_migration_config.max_worker_run_minutes%type) is
  begin
    select pipeline_paused, max_inflight_messages, enqueue_chunk_size,
           worker_count, worker_idle_seconds, max_worker_run_minutes
      into p_pipeline_paused, p_max_inflight_messages, p_enqueue_chunk_size,
           p_worker_count, p_worker_idle_seconds, p_max_worker_run_minutes
      from nfe_migration_config
     where config_id = 1;
  end get_config;

  procedure set_config(
    p_pipeline_paused         in nfe_migration_config.pipeline_paused%type,
    p_max_inflight_messages   in nfe_migration_config.max_inflight_messages%type,
    p_enqueue_chunk_size      in nfe_migration_config.enqueue_chunk_size%type,
    p_worker_count            in nfe_migration_config.worker_count%type,
    p_worker_idle_seconds     in nfe_migration_config.worker_idle_seconds%type,
    p_max_worker_run_minutes  in nfe_migration_config.max_worker_run_minutes%type) is
  begin
    if p_pipeline_paused not in ('Y', 'N')
       or p_max_inflight_messages <= 0
       or p_enqueue_chunk_size <= 0
       or p_worker_count <= 0
       or p_worker_idle_seconds <= 0
       or p_max_worker_run_minutes <= 0 then
      raise_application_error(-20040, 'Invalid pipeline configuration.');
    end if;

    update nfe_migration_config
       set pipeline_paused = p_pipeline_paused,
           max_inflight_messages = p_max_inflight_messages,
           enqueue_chunk_size = p_enqueue_chunk_size,
           worker_count = p_worker_count,
           worker_idle_seconds = p_worker_idle_seconds,
           max_worker_run_minutes = p_max_worker_run_minutes,
           updated_by = sys_context('USERENV', 'SESSION_USER'),
           updated_at = systimestamp
     where config_id = 1;

    pkg_nfe_audit.log_event(
      p_actor_type => 'USER',
      p_event_type => 'PIPELINE_CONFIG_CHANGED',
      p_details_json => '{"pipelinePaused":"' || p_pipeline_paused ||
                        '","maxInflightMessages":' || p_max_inflight_messages ||
                        ',"enqueueChunkSize":' || p_enqueue_chunk_size ||
                        ',"workerCount":' || p_worker_count || '}');
  end set_config;

  procedure assert_admission_allowed(
    p_batch_id         in nfe_migration_batch.batch_id%type,
    p_requested_count  in pls_integer) is
    l_pipeline_paused nfe_migration_config.pipeline_paused%type;
    l_max_inflight    nfe_migration_config.max_inflight_messages%type;
    l_chunk_size      nfe_migration_config.enqueue_chunk_size%type;
    l_batch_status    nfe_migration_batch.status%type;
    l_batch_max       nfe_migration_batch.max_documents%type;
    l_selected_count  nfe_migration_batch.selected_count%type;
    l_inflight_count  pls_integer;
  begin
    if p_requested_count is null or p_requested_count <= 0 then
      raise_application_error(-20041, 'Admission request count must be positive.');
    end if;

    -- The config lock serializes an admission decision with a concurrent
    -- pause/limit update. The caller retains it until its enqueue commit.
    select pipeline_paused, max_inflight_messages, enqueue_chunk_size
      into l_pipeline_paused, l_max_inflight, l_chunk_size
      from nfe_migration_config
     where config_id = 1
       for update;

    if l_pipeline_paused = 'Y' then
      raise_application_error(-20042, 'Pipeline admission is paused.');
    end if;

    if p_requested_count > l_chunk_size then
      raise_application_error(-20043, 'Admission request exceeds configured chunk size.');
    end if;

    select status, max_documents, selected_count
      into l_batch_status, l_batch_max, l_selected_count
      from nfe_migration_batch
     where batch_id = p_batch_id
       for update;

    if l_batch_status <> 'SELECTING' then
      raise_application_error(-20044, 'Batch is not eligible for admission.');
    end if;

    if l_selected_count + p_requested_count > l_batch_max then
      raise_application_error(-20045, 'Admission request exceeds batch document limit.');
    end if;

    select count(*)
      into l_inflight_count
      from nfe_migration_item
     where status in ('QUEUED', 'UPLOADING', 'UPLOADED', 'VERIFYING');

    if l_inflight_count + p_requested_count > l_max_inflight then
      raise_application_error(-20046, 'Admission request exceeds configured inflight limit.');
    end if;
  end assert_admission_allowed;
end pkg_nfe_pipeline_config;
/

prompt PASS: pipeline configuration API created.
