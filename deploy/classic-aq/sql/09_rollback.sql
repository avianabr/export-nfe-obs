begin
 update nfe_classic_aq_config set classic_aq_enabled='N',updated_by=user,updated_at=systimestamp where config_id=1;
 update nfe_migration_batch set status='BLOCKED' where status in ('SELECTING','PROCESSING');
 for r in (select job_name from user_scheduler_jobs where job_name='NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB') loop
   dbms_scheduler.disable(r.job_name, force=>false);
 end loop;
 commit;
 dbms_output.put_line('PASS: gate and deployment job disabled; active batches blocked. No source data, object, AQ message, TEQ object, or evidence was deleted.');
end;
/
