-- Run as NFE_OWNER. Does not enable jobs or purge XMLs.
-- Execute once for each worker count (1,2,4,8) and approved inflight limit.
set serveroutput on size unlimited
accept worker_count number prompt 'Worker count (1,2,4,8): '
accept inflight_limit number prompt 'Max inflight messages: '
declare
 l_pause char(1);l_old_inflight number;l_chunk number;l_old_workers number;l_idle number;l_run number;
 l_start timestamp with time zone:=systimestamp;l_items number;l_verified number;l_bytes number;
begin
 if &worker_count not in (1,2,4,8) or &inflight_limit<=0 then raise_application_error(-20150,'Use approved worker/inflight values.'); end if;
 pkg_nfe_pipeline_config.get_config(l_pause,l_old_inflight,l_chunk,l_old_workers,l_idle,l_run);
 pkg_nfe_pipeline_config.set_config('N',&inflight_limit,l_chunk,&worker_count,l_idle,l_run);
 select count(*),sum(case when status='VERIFIED' then 1 else 0 end),nvl(sum(object_size_bytes),0) into l_items,l_verified,l_bytes from nfe_migration_item;
 dbms_output.put_line('BENCHMARK_START='||to_char(l_start,'YYYY-MM-DD HH24:MI:SS TZH:TZM'));
 dbms_output.put_line('workers=&worker_count inflight=&inflight_limit items='||l_items||' verified='||l_verified||' bytes='||l_bytes);
 dbms_output.put_line('Run the approved batch/workers, then execute dashboard and capture AWR/ASH plus V$SYSSTAT deltas.');
 pkg_nfe_pipeline_config.set_config(l_pause,l_old_inflight,l_chunk,l_old_workers,l_idle,l_run);
 rollback;
end;
/
