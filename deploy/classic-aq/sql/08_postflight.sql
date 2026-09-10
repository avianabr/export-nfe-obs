-- Metadata-only safe-state check. It does not access AQ payloads or TEQ.
declare l_enabled char(1); l_job varchar2(5); l_active_batches number; begin
 select classic_aq_enabled into l_enabled from nfe_classic_aq_config where config_id=1;
 select enabled into l_job from user_scheduler_jobs where job_name='NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB';
 select count(*) into l_active_batches from nfe_migration_batch where status in ('SELECTING','PROCESSING');
 if l_enabled<>'N' or l_job<>'FALSE' or l_active_batches<>0 then
   raise_application_error(-20840,'Unsafe state: gate/job enabled or active Classic AQ batch selection remains.');
 end if;
 dbms_output.put_line('PASS: gate disabled, deployment job disabled, and no batch is actively selected. Preserved queue messages were not consumed; TEQ objects were not referenced.');
end;
/
