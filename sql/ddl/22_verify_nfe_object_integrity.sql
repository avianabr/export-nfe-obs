-- Run as NFE_OWNER after rerunning 19_create_nfe_worker_package.sql.
-- Uses the uploaded synthetic item from batch 2. The mismatch injection rolls
-- back before the valid verification is committed.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_control_id number;
  l_status     varchar2(30);
  l_rejected   boolean := false;
begin
  select control_id into l_control_id
    from nfe_migration_item
   where batch_id = 2 and status = 'UPLOADED'
     and rownum = 1;

  update nfe_migration_item
     set source_sha256 = rpad('0', 64, '0')
   where control_id = l_control_id;
  begin
    pkg_nfe_worker.verify_uploaded_item(l_control_id);
    raise_application_error(-20094, 'Divergent integrity evidence was accepted.');
  exception
    when others then
      if sqlcode <> -20063 then
        raise;
      end if;
      l_rejected := true;
      rollback;
  end;

  pkg_nfe_worker.verify_uploaded_item(l_control_id);
  commit;
  select status into l_status from nfe_migration_item where control_id = l_control_id;
  if not l_rejected or l_status <> 'VERIFIED' then
    raise_application_error(-20095,
      'Verified state was not protected by the download integrity check.');
  end if;
  dbms_output.put_line(
    'PASS: downloaded object size/SHA-256 is required before VERIFIED; divergence is rejected.');
exception
  when others then
    rollback;
    raise;
end;
/
