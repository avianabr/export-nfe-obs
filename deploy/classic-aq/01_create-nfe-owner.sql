-- Run only through 00_run-installation.sql. This script never drops or
-- replaces an existing account.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
set verify off

declare
  l_count          number;
  l_authentication varchar2(30);
  l_dbms_cloud_owner varchar2(128);
  l_default_tablespace varchar2(128);
begin
  if sys_context('USERENV', 'CURRENT_USER') <> 'SYS' then
    raise_application_error(-20895,
      'Connect as SYS AS SYSDBA to the target PDB before running 01_create-nfe-owner.sql.');
  end if;

  select count(*), max(authentication_type)
    into l_count, l_authentication
    from dba_users
  where username = 'NFE_OWNER';

  if l_count = 0 then
    if not regexp_like('&&NFE_OWNER_PASSWORD', '^[A-Za-z0-9_$#]{12,128}$') then
      raise_application_error(-20892,
        'Set NFE_OWNER_PASSWORD to a protected 12-128 character password using only letters, digits, _, $, or #.');
    end if;
    execute immediate 'create user nfe_owner identified by "&&NFE_OWNER_PASSWORD" account unlock';
  elsif l_authentication <> 'PASSWORD' then
    raise_application_error(-20891,
      'NFE_OWNER exists with incompatible authentication; no change was made.');
  end if;

  select default_tablespace into l_default_tablespace
    from dba_users
   where username = 'NFE_OWNER';
  execute immediate 'alter user nfe_owner quota unlimited on ' ||
    dbms_assert.simple_sql_name(l_default_tablespace);
  execute immediate 'grant create session, create table, create procedure, create trigger, create view, create job, create credential to nfe_owner';
  execute immediate 'grant aq_administrator_role to nfe_owner';
  execute immediate 'grant execute on sys.dbms_aq to nfe_owner';
  execute immediate 'grant execute on sys.dbms_aqadm to nfe_owner';
  execute immediate 'grant execute on sys.dbms_crypto to nfe_owner';

  select owner into l_dbms_cloud_owner
    from (
      select owner
        from dba_objects
       where object_name = 'DBMS_CLOUD'
         and object_type = 'PACKAGE'
         and status = 'VALID'
       order by case when owner = 'C##CLOUD$SERVICE' then 0 else 1 end, owner)
   where rownum = 1;

  execute immediate 'grant execute on ' ||
    dbms_assert.schema_name(l_dbms_cloud_owner) || '.dbms_cloud to nfe_owner';

  dbms_output.put_line('PASS: NFE_OWNER is ready for the Classic AQ deployment.');
exception
  when no_data_found then
    raise_application_error(-20893,
      'No valid DBMS_CLOUD package was found in this PDB; no deployment should proceed.');
end;
/
