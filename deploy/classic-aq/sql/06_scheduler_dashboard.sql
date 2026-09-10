declare l_count number; l_action varchar2(4000); l_enabled varchar2(5); begin
 select count(*) into l_count from user_scheduler_jobs where job_name='NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB';
 if l_count=0 then
   dbms_scheduler.create_job(job_name=>'NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB',job_type=>'PLSQL_BLOCK',job_action=>'begin pkg_nfe_classic_aq_runtime.run_workers; end;',enabled=>false,auto_drop=>false);
 else
   select job_action,enabled into l_action,l_enabled from user_scheduler_jobs where job_name='NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB';
   if l_enabled<>'FALSE' then raise_application_error(-20860,'Existing Classic AQ worker job is enabled; no change was made.'); end if;
   if regexp_replace(lower(trim(l_action)),'[[:space:]]','')='beginnull;end;' then
     dbms_scheduler.set_attribute('NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB','job_action','begin pkg_nfe_classic_aq_runtime.run_workers; end;');
   elsif regexp_replace(lower(trim(l_action)),'[[:space:]]','')<>'beginpkg_nfe_classic_aq_runtime.run_workers;end;' then
     raise_application_error(-20861,'Existing Classic AQ worker job has an incompatible action; no change was made.');
   end if;
 end if;
end;
/
create or replace view v_nfe_classic_aq_status as
select classic_aq_enabled
  from nfe_classic_aq_config
 where config_id=1;
