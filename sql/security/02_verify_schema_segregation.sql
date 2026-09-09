-- Run as SYS after 00_create_test_schemas.sql and 01_grant_deployed_object_privileges.sql.
-- Lists grants; direct mutation/execute denial is verified by the dedicated
-- integration test once the application objects are deployed.

whenever sqlerror exit failure rollback
set linesize 220
set pagesize 200

select username, account_status, default_tablespace, temporary_tablespace
  from dba_users
 where username in ('NFE_OWNER', 'NFE_MIGRATION_RUNTIME', 'NFE_PURGE_ADMIN', 'NFE_AUDITOR')
 order by username;

select grantee, privilege
  from dba_sys_privs
 where grantee in ('NFE_OWNER', 'NFE_MIGRATION_RUNTIME', 'NFE_PURGE_ADMIN', 'NFE_AUDITOR')
 order by grantee, privilege;

select grantee, granted_role
  from dba_role_privs
 where grantee in ('NFE_OWNER', 'NFE_MIGRATION_RUNTIME', 'NFE_PURGE_ADMIN', 'NFE_AUDITOR')
 order by grantee, granted_role;

select grantee, owner, table_name, privilege
  from dba_tab_privs
 where grantee in ('NFE_OWNER', 'NFE_MIGRATION_RUNTIME', 'NFE_PURGE_ADMIN', 'NFE_AUDITOR')
   and owner = 'NFE_OWNER'
 order by grantee, table_name, privilege;

select host, lower_port, upper_port, principal, privilege
  from dba_host_aces
 where principal = 'NFE_OWNER'
   and host = 'objectstorage.us-ashburn-1.oraclecloud.com'
 order by host, lower_port, privilege;

prompt Expected final criteria (run this check again after 01_grant_deployed_object_privileges.sql reports PASS):
prompt - NFE_MIGRATION_RUNTIME has no UPDATE privilege on NFE_OWNER.POC_NFE_DOCUMENT.
prompt - NFE_MIGRATION_RUNTIME has no EXECUTE privilege on PKG_NFE_PURGE_ADMIN.
prompt - NFE_PURGE_ADMIN has EXECUTE only on PKG_NFE_PURGE_ADMIN.
prompt - NFE_AUDITOR has SELECT only on control, audit, configuration and reconciliation tables.
