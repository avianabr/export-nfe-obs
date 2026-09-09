-- Run as SYS in PDB_POCRT_02 after ddl/37_create_nfe_classic_aq.sql.
-- The NFE_OWNER definer-rights packages are the only principals allowed to
-- enqueue/dequeue this transport. Runtime callers, auditors, and purge admins
-- must use a deliberately exposed API, never DBMS_AQ against this queue.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  c_owner     constant varchar2(30) := 'NFE_OWNER';
  c_queue     constant varchar2(30) := 'NFE_CLASSIC_AQ_Q';
  c_exception constant varchar2(30) := 'NFE_CLASSIC_AQ_EX_Q';
  l_count     pls_integer;
begin
  select count(*) into l_count
    from dba_queues
   where owner = c_owner
     and name in (c_queue, c_exception);
  if l_count <> 2 then
    raise_application_error(-20170,
      'Both classic AQ queues must exist before privilege policy is applied.');
  end if;

  -- Remove any accidental direct grant to non-owner PoC principals. OWNER has
  -- implicit access to its own queues; exception monitoring executes as that
  -- owner through a definer-rights package, so no separate dequeue identity is
  -- introduced.
  for r in (
    select grantee, table_name, privilege
      from dba_tab_privs
     where owner = c_owner
       and table_name in (c_queue, c_exception)
       and grantee in ('NFE_MIGRATION_RUNTIME', 'NFE_AUDITOR', 'NFE_PURGE_ADMIN')
       and privilege in ('ENQUEUE', 'DEQUEUE', 'READ', 'ALL')
  ) loop
    if r.privilege = 'READ' then
      execute immediate 'revoke read on ' || c_owner || '.' || r.table_name ||
                        ' from ' || r.grantee;
    else
      dbms_aqadm.revoke_queue_privilege(
        privilege  => r.privilege,
        queue_name => c_owner || '.' || r.table_name,
        grantee    => r.grantee);
    end if;
    dbms_output.put_line('Revoked ' || r.privilege || ' on ' || r.table_name ||
                         ' from ' || r.grantee || '.');
  end loop;

  select count(*) into l_count
    from dba_tab_privs
   where owner = c_owner
     and table_name in (c_queue, c_exception)
     and grantee <> c_owner
     and privilege in ('ENQUEUE', 'DEQUEUE', 'READ', 'ALL');
  if l_count <> 0 then
    raise_application_error(-20171,
      'Classic AQ direct privileges remain for a non-owner principal.');
  end if;

  dbms_output.put_line('PASS: classic AQ queue access is restricted to NFE_OWNER definer-rights code.');
  dbms_output.put_line('Runtime has no direct AQ access; monitor uses NFE_OWNER package rights; auditor has no AQ payload access.');
end;
/
