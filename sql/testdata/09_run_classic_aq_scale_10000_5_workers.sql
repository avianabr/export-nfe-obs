-- Explicit opt-in scale-test harness. Run only as NFE_OWNER in an isolated PDB
-- after 19_create_seed_oci_10k_source.sql. This is not a deployment script.
--
-- Prerequisites:
--   * deploy/classic-aq is installed and configured for POC_NFE_DOCUMENT;
--   * NFE_DEPLOY_STORAGE_CONFIG.MAX_INFLIGHT is at least 10000;
--   * the configured S3 credential and HTTP ACL are working;
--   * NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB remains disabled.
--
-- The script admits 10,000 documents in one transaction, launches ten
-- disposable Scheduler jobs with 1,000 messages each, waits for all items to
-- verify, reconciles the batch, and disables Classic AQ again. It never purges
-- source XMLs and never consumes or changes TEQ resources.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  c_document_count constant pls_integer := 10000;
  c_worker_count   constant pls_integer := 10;
  c_per_worker     constant pls_integer := c_document_count / c_worker_count;
  c_wait_seconds   constant pls_integer := 7200;
  c_poll_seconds   constant pls_integer := 5;

  l_source_count   pls_integer;
  l_controlled     pls_integer;
  l_max_inflight   number;
  l_enabled        char(1);
  l_deploy_job     varchar2(5);
  l_batch_id       number;
  l_control_id     number;
  l_verified       pls_integer;
  l_other_status   pls_integer;
  l_failed_jobs    pls_integer;
  l_passed         boolean;
  l_started_at     timestamp with time zone := systimestamp;
  l_job_name       varchar2(30);

  procedure disable_scale_jobs is
  begin
    for n in 1 .. c_worker_count loop
      l_job_name := 'NFE_SCALE_10000_10W_' || to_char(n, 'FM00');
      begin
        dbms_scheduler.disable(l_job_name, force => true);
      exception
        when others then
          if sqlcode not in (-27475, -27476) then raise; end if;
      end;
    end loop;
  end disable_scale_jobs;
begin
  select count(*)
    into l_source_count
    from poc_nfe_oci_10k
   where situacao = 'AUTORIZADA'
     and xml_clob is not null;
  if l_source_count <> c_document_count then
    raise_application_error(-20900,
      'Expected exactly 10000 authorized source documents in POC_NFE_DOCUMENT.');
  end if;

  select count(*)
    into l_controlled
    from nfe_migration_item i
    join poc_nfe_oci_10k d on d.nfe_id = i.nfe_id;
  if l_controlled <> 0 then
    raise_application_error(-20901,
      'POC source already has migration-control items; use a fresh isolated PDB.');
  end if;

  select max_inflight into l_max_inflight
    from nfe_deploy_storage_config
   where config_id = 1;
  if l_max_inflight < c_document_count then
    raise_application_error(-20902,
      'Configured MAX_INFLIGHT must be at least 10000 before this scale test.');
  end if;

  select classic_aq_enabled into l_enabled
    from nfe_classic_aq_config
   where config_id = 1;
  if l_enabled <> 'N' then
    raise_application_error(-20903,
      'Classic AQ must be disabled before starting the isolated scale test.');
  end if;

  select enabled into l_deploy_job
    from user_scheduler_jobs
   where job_name = 'NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB';
  if l_deploy_job <> 'FALSE' then
    raise_application_error(-20904,
      'The deployment Scheduler job must remain disabled during this scale test.');
  end if;

  insert into nfe_migration_batch (
    batch_code, status, cutoff_date, max_documents, created_by)
  values (
    'AQ-SCALE-10K-10W-' || to_char(systimestamp, 'YYYYMMDDHH24MISSFF3'),
    'CREATED', systimestamp + interval '1' minute, c_document_count, user)
  returning batch_id into l_batch_id;

  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  for n in 1 .. c_document_count loop
    pkg_nfe_classic_aq_runtime.admit_one(l_batch_id, 'AUTORIZADA', l_control_id);
  end loop;
  commit;

  for n in 1 .. c_worker_count loop
    l_job_name := 'NFE_SCALE_10000_10W_' || to_char(n, 'FM00');
    dbms_scheduler.create_job(
      job_name   => l_job_name,
      job_type   => 'PLSQL_BLOCK',
      job_action => 'begin pkg_nfe_classic_aq_runtime.run_workers(' ||
                    c_per_worker || '); end;',
      enabled    => false,
      auto_drop  => true,
      comments   => 'Isolated 10k/10-worker Classic AQ scale-test job.');
  end loop;
  for n in 1 .. c_worker_count loop
    dbms_scheduler.enable('NFE_SCALE_10000_10W_' || to_char(n, 'FM00'));
  end loop;

  loop
    select count(case when status = 'VERIFIED' then 1 end),
           count(case when status <> 'VERIFIED' then 1 end)
      into l_verified, l_other_status
      from nfe_migration_item
     where batch_id = l_batch_id;
    exit when l_verified = c_document_count;

    select count(*) into l_failed_jobs
      from user_scheduler_job_run_details
     where job_name like 'NFE_SCALE_10000_10W_%'
       and log_date >= l_started_at
       and status <> 'SUCCEEDED';
    if l_failed_jobs > 0 then
      raise_application_error(-20905,
        'At least one scale-test worker failed; inspect USER_SCHEDULER_JOB_RUN_DETAILS.');
    end if;
    if systimestamp >= l_started_at + numtodsinterval(c_wait_seconds, 'SECOND') then
      raise_application_error(-20906,
        'Timed out waiting for 10000 VERIFIED items; inspect batch and Scheduler evidence.');
    end if;
    dbms_session.sleep(c_poll_seconds);
  end loop;

  pkg_nfe_classic_aq_runtime.reconcile_batch(l_batch_id, l_passed);
  if not l_passed then
    raise_application_error(-20907, 'Batch reconciliation did not pass.');
  end if;
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  commit;

  dbms_output.put_line('PASS: batch_id=' || l_batch_id ||
    ', verified=' || l_verified || ', workers=' || c_worker_count ||
    ', elapsed_seconds=' || round((cast(systimestamp as date) - cast(l_started_at as date)) * 86400, 2));
exception
  when others then
    disable_scale_jobs;
    begin
      pkg_nfe_classic_aq_runtime.set_enabled('N');
      commit;
    exception when others then rollback; end;
    raise;
end;
/

select b.batch_id, b.batch_code, b.status as batch_status,
       count(i.control_id) as total_items,
       count(case when i.status = 'VERIFIED' then 1 end) as verified_items,
       count(case when i.status <> 'VERIFIED' then 1 end) as non_verified_items
  from nfe_migration_batch b
  join nfe_migration_item i on i.batch_id = b.batch_id
 where b.batch_code like 'AQ-SCALE-10K-10W-%'
 group by b.batch_id, b.batch_code, b.status
 order by b.batch_id desc;
