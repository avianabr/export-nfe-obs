-- Run as NFE_OWNER after all worker sessions for one benchmark batch finish.
whenever oserror exit failure rollback
set serveroutput on size unlimited
accept benchmark_batch_id number prompt 'Completed AQBENCH batch_id: '
select b.batch_id,b.batch_code,b.selected_count,b.verified_count,b.failed_count,b.exception_count,
       min(i.enqueued_at) first_enqueued_at,max(i.verified_at) last_verified_at,
       round(count(case when i.status='VERIFIED' then 1 end) /
         nullif((cast(max(i.verified_at) as date)-cast(min(i.enqueued_at) as date))*86400,0),2) verified_per_second
from nfe_migration_batch b join nfe_migration_item i on i.batch_id=b.batch_id
where b.batch_id=&benchmark_batch_id group by b.batch_id,b.batch_code,b.selected_count,b.verified_count,b.failed_count,b.exception_count;
select percentile_cont(.50) within group (order by latency_seconds) p50_seconds,
       percentile_cont(.95) within group (order by latency_seconds) p95_seconds,
       percentile_cont(.99) within group (order by latency_seconds) p99_seconds
from (select (cast(verified_at as date)-cast(enqueued_at as date))*86400 latency_seconds
      from nfe_migration_item where batch_id=&benchmark_batch_id and status='VERIFIED');
