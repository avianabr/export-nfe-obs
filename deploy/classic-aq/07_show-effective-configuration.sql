-- Run as NFE_OWNER after installation. This read-only command deliberately
-- loads no local secret file and never displays credential contents.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
set pagesize 100
column s3_endpoint format a70
column acl_host format a50
column credential_name format a30
column source_owner format a20
column source_table format a30
select s.s3_endpoint,
       s.storage_provider,
       s.integrity_mode,
       s.oci_namespace,
       regexp_substr(s.s3_endpoint, '^https://([^/]+)$', 1, 1, null, 1) as acl_host,
       s.bucket_name,
       s.object_prefix,
       s.credential_name,
       m.source_owner,
       m.source_table,
       m.source_clob_column,
       m.source_id_column,
       m.source_key_column,
       m.source_date_column,
       m.source_status_column,
       s.max_inflight,
       q.classic_aq_enabled,
       q.worker_limit,
       (select enabled from user_scheduler_jobs
         where job_name='NFE_CLASSIC_AQ_DEPLOY_WORKER_JOB') as job_enabled
  from nfe_deploy_storage_config s
  join nfe_deploy_source_config m on m.config_id=s.config_id
  join nfe_classic_aq_config q on q.config_id=s.config_id
 where s.config_id=1;

prompt Latest item-integrity evidence:
select control_id,batch_id,status,integrity_mode,source_bytes,destination_bytes,
       destination_algorithm,head_verified_at,object_uri,last_error
  from v_nfe_classic_aq_integrity
 order by control_id desc fetch first 20 rows only;

prompt Batch progress and Scheduler workers (metadata only):
select batch_id,batch_code,batch_status,worker_limit,active_workers,total_items,
       queued_items,active_items,verified_items,failed_items,worker_started_at
  from v_nfe_classic_aq_batch_progress
 order by batch_id desc fetch first 20 rows only;
