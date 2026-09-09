-- Run as NFE_MIGRATION_RUNTIME after 33_create_nfe_purge_admin_package.sql
-- and 01_grant_deployed_object_privileges.sql have been deployed.
-- The UPDATE statement intentionally matches no rows; it is used only to
-- verify that Oracle denies the column/table mutation privilege.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_purge_package_exists pls_integer;
  l_purge_execute_grants pls_integer;
  l_update_was_denied boolean := false;
begin
  begin
    execute immediate
      'update nfe_owner.poc_nfe_document set xml_clob = xml_clob where 1 = 0';
    raise_application_error(-20070,
      'FAIL: runtime identity unexpectedly has UPDATE on POC_NFE_DOCUMENT.');
  exception
    when others then
      -- Oracle returns ORA-01031 when the object is visible but UPDATE is
      -- denied, and ORA-00942 when the runtime account has no object
      -- privilege at all. Both are the intended least-privilege outcome.
      if sqlcode in (-1031, -942) then
        l_update_was_denied := true;
      else
        raise;
      end if;
  end;

  select count(*)
    into l_purge_package_exists
    from all_objects
   where owner = 'NFE_OWNER'
     and object_name = 'PKG_NFE_PURGE_ADMIN'
     and object_type = 'PACKAGE'
     and status = 'VALID';

  if l_purge_package_exists = 0 then
    -- Purge administration is optional in this transport-only deployment.
    -- Its absence is already a safe denial for the runtime identity and must
    -- not make the AQ/XML least-privilege validation fail.
    dbms_output.put_line(
      'SKIPPED: PKG_NFE_PURGE_ADMIN is not deployed; runtime has no purge API to execute.');
  else
    select count(*)
      into l_purge_execute_grants
      from user_tab_privs_recd
     where owner = 'NFE_OWNER'
       and table_name = 'PKG_NFE_PURGE_ADMIN'
       and privilege = 'EXECUTE';

    if l_purge_execute_grants <> 0 then
      raise_application_error(-20072,
        'FAIL: runtime identity has EXECUTE on PKG_NFE_PURGE_ADMIN.');
    end if;
  end if;

  if l_update_was_denied then
    dbms_output.put_line(
      'PASS: runtime cannot update XML_CLOB and cannot execute purge administration.');
  end if;
end;
/
