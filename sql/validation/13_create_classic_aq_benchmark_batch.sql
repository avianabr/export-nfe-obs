-- Run as NFE_OWNER after testdata/04. Create exactly one 1,000-item batch for
-- the requested worker round. It enables classic AQ only for that round.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

accept worker_count number prompt 'Worker count (1,2,4,8): '
declare
  l_workers number := &worker_count;
  l_paused char(1); l_inflight number; l_chunk number; l_old_workers number; l_idle number; l_run number;
  l_batch_id number; l_admitted pls_integer; l_exists pls_integer; l_existing_active pls_integer;
  l_batch_status nfe_migration_batch.status%type; l_item_count pls_integer;
  l_cohort varchar2(2); l_batch_suffix varchar2(2);
begin
  if l_workers not in (1,2,4,8) then
    raise_application_error(-20320, 'Worker count must be 1, 2, 4, or 8.');
  end if;
  l_cohort := case l_workers when 1 then '01' when 2 then '02'
                when 4 then '04' when 8 then '03' end;
  l_batch_suffix := lpad(l_workers, 2, '0');
  select count(*) into l_exists from nfe_migration_batch where batch_code = 'AQBENCH-' || l_batch_suffix;
  pkg_nfe_pipeline_config.get_config(l_paused,l_inflight,l_chunk,l_old_workers,l_idle,l_run);
  -- The control-plane limit is global and includes preserved TEQ/in-flight
  -- work. Retain that backlog and reserve exactly 1,000 additional slots for
  -- this isolated classic-AQ cohort.
  select count(*) into l_existing_active
    from nfe_migration_item
   where status in ('QUEUED','UPLOADING','UPLOADED','VERIFYING');
  pkg_nfe_pipeline_config.set_config('N',l_existing_active + 1000,1000,l_workers,l_idle,l_run);
  pkg_nfe_classic_aq_config.set_classic_aq_enabled('Y');
  if l_exists = 0 then
    insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,selection_chunk_size,criteria_json,created_by)
    values ('AQBENCH-' || l_batch_suffix,'CREATED',systimestamp + interval '1' day,1000,1000,
            '{"eligibleSituations":["AUTORIZADA"],"benchmarkKeyPrefix":"AQBENCH' || l_cohort || '"}',
            sys_context('USERENV','SESSION_USER')) returning batch_id into l_batch_id;
    pkg_nfe_classic_aq_config.select_classic_aq(l_batch_id);
    commit;
  else
    select batch_id, status into l_batch_id, l_batch_status
      from nfe_migration_batch where batch_code = 'AQBENCH-' || l_batch_suffix;
    select count(*) into l_item_count from nfe_migration_item where batch_id = l_batch_id;
    if l_batch_status not in ('CREATED', 'SELECTING') or l_item_count <> 0 then
      raise_application_error(-20321,
        'AQBENCH-' || l_batch_suffix || ' is not an empty resumable CREATED/SELECTING batch.');
    end if;
    -- AQBENCH-08 from the pre-fix script can be an empty batch with a prefix
    -- that was never seeded. Correct only that empty batch to use cohort 03.
    update nfe_migration_batch
       set criteria_json = '{"eligibleSituations":["AUTORIZADA"],"benchmarkKeyPrefix":"AQBENCH' || l_cohort || '"}'
     where batch_id = l_batch_id
       and status = 'CREATED'
       and batch_code = 'AQBENCH-08';
    commit;
    dbms_output.put_line('Resuming empty AQBENCH batch=' || l_batch_id || '.');
  end if;
  pkg_nfe_classic_aq_migration.admit_chunk(l_batch_id,1000,l_admitted);
  if l_admitted <> 1000 then raise_application_error(-20322,'Expected exactly 1000 admitted items.'); end if;
  commit;
  dbms_output.put_line('PASS: AQBENCH batch='||l_batch_id||', workers='||l_workers||', admitted='||l_admitted||', prior_active='||l_existing_active||'.');
end;
/
