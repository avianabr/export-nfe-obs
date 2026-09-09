-- Run as NFE_OWNER after transfer packages are deployed.
whenever sqlerror exit failure rollback
create or replace package pkg_nfe_reconciliation authid definer as
  procedure reconcile_batch(p_batch_id number, p_passed out boolean);
end;
/
create or replace package body pkg_nfe_reconciliation as
 procedure reconcile_batch(p_batch_id number,p_passed out boolean) is
  l_total number;l_verified number;l_bad number;l_src number;l_obj number;l_run number;
 begin
  select count(*),sum(case when status='VERIFIED' then 1 else 0 end),sum(case when status in ('FAILED','EXCEPTION') then 1 else 0 end),nvl(sum(source_size_bytes),0),nvl(sum(object_size_bytes),0)
   into l_total,l_verified,l_bad,l_src,l_obj from nfe_migration_item where batch_id=p_batch_id;
  p_passed := l_total>0 and l_total=l_verified and l_bad=0 and l_src=l_obj;
  insert into nfe_reconciliation_run(batch_id,status,total_count,verified_count,failed_count,exception_count,source_bytes,object_bytes,completed_at,executed_by)
  values(p_batch_id,case when p_passed then 'PASSED' else 'FAILED' end,l_total,l_verified,0,l_bad,l_src,l_obj,systimestamp,user) returning reconciliation_id into l_run;
  if p_passed then update nfe_migration_batch set status='RECONCILING' where batch_id=p_batch_id and status='PROCESSING'; update nfe_migration_batch set status='READY_FOR_APPROVAL',reconciliation_status='PASSED',reconciled_at=systimestamp where batch_id=p_batch_id; else update nfe_migration_batch set reconciliation_status='FAILED' where batch_id=p_batch_id; end if;
 end;
end;
/
prompt PASS: reconciliation package created.
