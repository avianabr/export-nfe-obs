-- Run as NFE_OWNER after 03_create_audit_and_operational_views.sql.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_count pls_integer;
begin
  select count(*) into l_count
    from user_objects
   where object_name = 'PKG_NFE_AUDIT'
     and object_type = 'PACKAGE'
     and status = 'VALID';
  if l_count = 0 then
    raise_application_error(-20031, 'PKG_NFE_AUDIT is not valid.');
  end if;

  select count(*) into l_count
    from user_objects
   where object_name in ('V_NFE_MIGRATION_BATCH_STATUS', 'V_NFE_MIGRATION_ITEM_STATUS',
                         'V_NFE_MIGRATION_RECENT_AUDIT')
     and object_type = 'VIEW'
     and status = 'VALID';
  if l_count <> 3 then
    raise_application_error(-20032, 'One or more operational views are missing or invalid.');
  end if;

  dbms_output.put_line('PASS: audit package and all operational views are valid.');
end;
/

select count(*) as batch_rows from v_nfe_migration_batch_status;
select count(*) as item_rows from v_nfe_migration_item_status;
select count(*) as audit_rows from v_nfe_migration_recent_audit;
