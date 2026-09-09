-- Run as NFE_OWNER after 31_create_nfe_operations_dashboard.sql.
whenever sqlerror exit failure rollback
declare l_count number; begin
 select count(*) into l_count from user_views where view_name in ('V_NFE_MIGRATION_DASHBOARD','V_NFE_MIGRATION_THROUGHPUT');
 if l_count<>2 then raise_application_error(-20140,'Operational dashboard views missing.'); end if;
 select count(*) into l_count from v_nfe_migration_dashboard where backlog_items>0 or exception_items>0 or failed_items>0;
 dbms_output.put_line('PASS: dashboard exposes backlog/exceptions and throughput metrics; flagged batches='||l_count||'.');
end;
/
