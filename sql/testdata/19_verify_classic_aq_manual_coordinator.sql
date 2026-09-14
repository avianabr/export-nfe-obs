-- Run only as NFE_OWNER. This temporary control-plane test never enqueues AQ
-- payloads, reads source XML, calls Object Storage, or touches TEQ.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_batch_id number;
  l_control_id number;
  l_gate char(1);
  l_original_limit number;
  l_jobs number;
  l_snapshot number;
begin
  select classic_aq_enabled,worker_limit into l_gate,l_original_limit
    from nfe_classic_aq_config where config_id=1 for update;
  if l_gate<>'N' then
    raise_application_error(-20982,'Coordinator verification requires Classic AQ disabled initially.');
  end if;

  update nfe_classic_aq_config set worker_limit=2,updated_by=user,updated_at=systimestamp
   where config_id=1;
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,created_by)
  values('COORDINATOR-CONTROL-'||to_char(systimestamp,'YYMMDDHH24MISSFF3'),
         'PROCESSING',systimestamp+interval '1' day,1,user)
  returning batch_id into l_batch_id;
  insert into nfe_migration_item(batch_id,nfe_id,object_key,object_uri,status)
  values(l_batch_id,-l_batch_id,'coordinator-control/'||to_char(l_batch_id)||'.xml',
         'https://invalid.example/coordinator-control/'||to_char(l_batch_id)||'.xml','QUEUED')
  returning control_id into l_control_id;
  commit;

  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  commit;
  pkg_nfe_classic_aq_runtime.start_batch_workers(l_batch_id);
  select worker_limit into l_snapshot from nfe_migration_batch where batch_id=l_batch_id;
  select count(*) into l_jobs from user_scheduler_jobs
   where job_name like 'NFE_AQ_B'||to_char(l_batch_id)||'_W%';
  if l_snapshot<>2 or l_jobs<>2 then
    raise_application_error(-20983,'Coordinator did not create exactly the selected batch worker limit.');
  end if;

  pkg_nfe_classic_aq_runtime.stop_batch_workers(l_batch_id);
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  delete from nfe_migration_item where control_id=l_control_id;
  delete from nfe_migration_batch where batch_id=l_batch_id;
  update nfe_classic_aq_config set worker_limit=l_original_limit,updated_by=user,updated_at=systimestamp
   where config_id=1;
  commit;
  dbms_output.put_line('PASS: manual coordinator created only two named workers for its selected batch and cleanup removed them.');
exception
  when others then
    begin
      if l_batch_id is not null then pkg_nfe_classic_aq_runtime.stop_batch_workers(l_batch_id); end if;
      pkg_nfe_classic_aq_runtime.set_enabled('N');
      if l_control_id is not null then delete from nfe_migration_item where control_id=l_control_id; end if;
      if l_batch_id is not null then delete from nfe_migration_batch where batch_id=l_batch_id; end if;
      update nfe_classic_aq_config set worker_limit=l_original_limit,updated_by=user,updated_at=systimestamp where config_id=1;
      commit;
    exception when others then rollback; end;
    raise;
end;
/
