-- Safe control-plane verification. It does not admit items or start Scheduler jobs.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_active_before number;
  l_active_after  number;
  l_jobs_before   number;
  l_jobs_after    number;
  l_rejected      boolean;
begin
  select count(*) into l_active_before
    from nfe_migration_batch where status in ('SELECTING','PROCESSING');
  select count(*) into l_jobs_before
    from user_scheduler_jobs where job_name like 'NFE_AQ_B%_W%';

  for l_value in 0, 11 loop
    l_rejected:=false;
    savepoint invalid_parallel_limit;
    begin
      update nfe_classic_aq_config set worker_limit=l_value where config_id=1;
    exception
      when others then
        if sqlcode=-2290 then l_rejected:=true; else raise; end if;
    end;
    rollback to invalid_parallel_limit;
    if not l_rejected then
      raise_application_error(-20980,'Invalid worker limit '||l_value||' was accepted.');
    end if;
  end loop;

  select count(*) into l_active_after
    from nfe_migration_batch where status in ('SELECTING','PROCESSING');
  select count(*) into l_jobs_after
    from user_scheduler_jobs where job_name like 'NFE_AQ_B%_W%';
  if l_active_after<>l_active_before or l_jobs_after<>l_jobs_before then
    raise_application_error(-20981,'Invalid worker limit changed batch selection or Scheduler jobs.');
  end if;
  dbms_output.put_line('PASS: invalid worker limits were rejected without selecting a batch or enabling workers.');
end;
/
