-- Run as NFE_OWNER after reconciliation deployment.
whenever sqlerror exit failure rollback
create or replace view v_nfe_migration_dashboard as
select b.batch_id,b.batch_code,b.status,count(i.control_id) total_items,
 sum(case when i.status in ('QUEUED','UPLOADING','UPLOADED','VERIFYING') then 1 else 0 end) backlog_items,
 sum(case when i.status='EXCEPTION' then 1 else 0 end) exception_items,
 sum(case when i.status='FAILED' then 1 else 0 end) failed_items,
 min(case when i.status in ('QUEUED','UPLOADING','UPLOADED','VERIFYING') then i.enqueued_at end) oldest_backlog_at,
 max(i.business_attempts) max_business_attempts,b.reconciliation_status,b.last_error
from nfe_migration_batch b left join nfe_migration_item i on i.batch_id=b.batch_id
group by b.batch_id,b.batch_code,b.status,b.reconciliation_status,b.last_error;
/
create or replace view v_nfe_migration_throughput as
select trunc(cast(created_at as date),'HH24') metric_hour,count(*) selected_items,
 sum(case when verified_at is not null then 1 else 0 end) verified_items,
 sum(nvl(source_size_bytes,0)) source_bytes,sum(nvl(object_size_bytes,0)) object_bytes,
 round(avg(case when verified_at is not null then (cast(verified_at as date)-cast(enqueued_at as date))*86400 end),2) avg_latency_seconds
from nfe_migration_item group by trunc(cast(created_at as date),'HH24');
/
prompt PASS: operational dashboard views created.
