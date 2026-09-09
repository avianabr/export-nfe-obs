-- Run as SYS while connected directly to PDB_POCRT_02.
-- Creates local test schemas only; do not run in CDB$ROOT.
-- Passwords are prompted and are never stored in this repository.
-- Adjust USERS and TEMP to the approved tablespaces before running.

whenever sqlerror exit failure rollback
set define on
set verify off
set serveroutput on

accept nfe_owner_password char prompt 'Password for NFE_OWNER: ' hide
accept nfe_runtime_password char prompt 'Password for NFE_MIGRATION_RUNTIME: ' hide
accept nfe_purge_password char prompt 'Password for NFE_PURGE_ADMIN: ' hide
accept nfe_auditor_password char prompt 'Password for NFE_AUDITOR: ' hide

declare
  procedure create_local_user(p_username varchar2, p_password varchar2) is
  begin
    execute immediate
      'create user ' || dbms_assert.simple_sql_name(p_username) ||
      ' identified by "' || replace(p_password, '"', '""') || '"' ||
      ' default tablespace users temporary tablespace temp quota unlimited on users';
  exception
    when others then
      if sqlcode = -1920 then
        dbms_output.put_line('User ' || p_username || ' already exists; creation skipped.');
      else
        raise;
      end if;
  end;
begin
  if sys_context('USERENV', 'CON_NAME') = 'CDB$ROOT' then
    raise_application_error(-20000, 'Connect to PDB_POCRT_02, not CDB$ROOT.');
  end if;

  create_local_user('NFE_OWNER', '&nfe_owner_password');
  create_local_user('NFE_MIGRATION_RUNTIME', '&nfe_runtime_password');
  create_local_user('NFE_PURGE_ADMIN', '&nfe_purge_password');
  create_local_user('NFE_AUDITOR', '&nfe_auditor_password');
end;
/

-- Owner: owns tables, views, packages, queues and disabled Scheduler jobs.
grant create session, create table, create view, create procedure, create trigger, create sequence, create job, create credential to nfe_owner;
grant aq_administrator_role, aq_user_role to nfe_owner;
grant execute on sys.dbms_aq to nfe_owner;
grant execute on sys.dbms_aqadm to nfe_owner;
grant execute on sys.dbms_scheduler to nfe_owner;
grant execute on sys.dbms_crypto to nfe_owner;
grant execute on sys.dbms_lob to nfe_owner;
grant execute on sys.utl_i18n to nfe_owner;
grant execute on c##cloud$service.dbms_cloud to nfe_owner;

-- Runtime: invokes only the migration API after that package is deployed.
grant create session to nfe_migration_runtime;
grant aq_user_role to nfe_migration_runtime;

-- Purge admin and auditor receive object grants only after deployment.
grant create session to nfe_purge_admin;
grant create session to nfe_auditor;

-- Network access is scoped to the PoC Object Storage endpoint. HTTP is needed
-- by the DBMS_CLOUD request path; RESOLVE permits DNS lookup.
begin
  dbms_network_acl_admin.append_host_ace(
    host => 'objectstorage.us-ashburn-1.oraclecloud.com',
    lower_port => 443,
    upper_port => 443,
    ace => xs$ace_type(
      privilege_list => xs$name_list('http'),
      principal_name => 'NFE_OWNER',
      principal_type => xs_acl.ptype_db));

  dbms_network_acl_admin.append_host_ace(
    host => 'objectstorage.us-ashburn-1.oraclecloud.com',
    ace => xs$ace_type(
      privilege_list => xs$name_list('resolve'),
      principal_name => 'NFE_OWNER',
      principal_type => xs_acl.ptype_db));
end;
/

prompt Test schemas and base privileges were created.
prompt Next run the DDL/package deployment as NFE_OWNER, then run 01_grant_deployed_object_privileges.sql as SYS.
