declare l_count number; l_action varchar2(4000); l_enabled varchar2(5); begin
 select count(*) into l_count from user_scheduler_jobs where job_name='NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB';
 if l_count=0 then
   dbms_scheduler.create_job(job_name=>'NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB',job_type=>'PLSQL_BLOCK',job_action=>'begin null; end;',enabled=>false,auto_drop=>false);
 else
   select job_action,enabled into l_action,l_enabled from user_scheduler_jobs where job_name='NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB';
   if l_enabled<>'FALSE' then raise_application_error(-20860,'Existing Classic AQ worker job is enabled; no change was made.'); end if;
   if regexp_replace(lower(trim(l_action)),'[[:space:]]','')='beginpkg_nfe_classic_aq_runtime.run_workers;end;' then
     dbms_scheduler.set_attribute('NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB','job_action','begin null; end;');
   elsif regexp_replace(lower(trim(l_action)),'[[:space:]]','')<>'beginnull;end;' then
     raise_application_error(-20861,'Existing Classic AQ worker job has an incompatible action; no change was made.');
   end if;
 end if;
end;
/
create or replace view v_nfe_classic_aq_status as
select q.classic_aq_enabled,q.worker_limit,
       (select count(*) from user_scheduler_running_jobs r
         where r.job_name like 'NFE_AQ_B%_W%') as active_workers
  from nfe_classic_aq_config q
 where q.config_id=1;
/
create or replace view v_nfe_classic_aq_integrity as
select i.control_id,i.batch_id,i.status,i.integrity_mode,i.object_uri,
       i.source_bytes,i.destination_bytes,i.source_sha256,i.object_sha256,
       i.source_md5,i.destination_checksum,i.destination_algorithm,
       i.object_version,i.head_verified_at,i.last_error,i.updated_at
  from nfe_migration_item i;
/
create or replace view v_nfe_classic_aq_batch_progress as
select b.batch_id,b.batch_code,b.status as batch_status,b.worker_limit,
       b.worker_started_at,
       count(i.control_id) as total_items,
       count(case when i.status='QUEUED' then 1 end) as queued_items,
       count(case when i.status in ('UPLOADING','UPLOADED','VERIFYING') then 1 end) as active_items,
       count(case when i.status='VERIFIED' then 1 end) as verified_items,
       count(case when i.status in ('FAILED','EXCEPTION') then 1 end) as failed_items,
       (select count(*) from user_scheduler_running_jobs r
         where r.job_name like 'NFE_AQ_B'||to_char(b.batch_id)||'_W%') as active_workers
  from nfe_migration_batch b
  left join nfe_migration_item i on i.batch_id=b.batch_id
 group by b.batch_id,b.batch_code,b.status,b.worker_limit,b.worker_started_at;
