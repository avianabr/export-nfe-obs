-- Run as SYS only after install.sql has completed as NFE_OWNER.
begin
 for r in (select grantee, privilege, table_name from dba_tab_privs where owner='NFE_OWNER' and table_name in ('NFE_CLASSIC_AQ_Q','NFE_CLASSIC_AQ_EX_Q') and grantee in ('NFE_MIGRATION_RUNTIME','NFE_AUDITOR','NFE_PURGE_ADMIN')) loop
   dbms_aqadm.revoke_queue_privilege(r.privilege,'NFE_OWNER.'||r.table_name,r.grantee);
 end loop;
end;
/
declare
  l_count number;
begin
  select count(*) into l_count from dba_role_privs
   where grantee='NFE_MIGRATION_RUNTIME' and granted_role='NFE_CLASSIC_AQ_RUNTIME_R';
  if l_count<>1 then raise_application_error(-20872,'NFE_MIGRATION_RUNTIME is not provisioned with NFE_CLASSIC_AQ_RUNTIME_R.'); end if;
  select count(*) into l_count from dba_role_privs
   where grantee='NFE_AUDITOR' and granted_role='NFE_CLASSIC_AQ_AUDITOR_R';
  if l_count<>1 then raise_application_error(-20873,'NFE_AUDITOR is not provisioned with NFE_CLASSIC_AQ_AUDITOR_R.'); end if;
end;
/
declare
  procedure revoke_if_direct(p_privilege varchar2,p_object varchar2,p_grantee varchar2) is
    l_count number;
  begin
    select count(*) into l_count from dba_tab_privs
     where owner='NFE_OWNER' and table_name=p_object
       and grantee=p_grantee and privilege=p_privilege;
    if l_count>0 then
      execute immediate 'revoke '||p_privilege||' on nfe_owner.'||p_object||' from '||p_grantee;
    end if;
  end;
begin
  revoke_if_direct('EXECUTE','PKG_NFE_CLASSIC_AQ_RUNTIME','NFE_MIGRATION_RUNTIME');
  revoke_if_direct('SELECT','V_NFE_CLASSIC_AQ_STATUS','NFE_AUDITOR');
  revoke_if_direct('EXECUTE','PKG_NFE_CLASSIC_AQ_MONITOR','NFE_AUDITOR');
end;
/
grant execute on nfe_owner.pkg_nfe_classic_aq_runtime to nfe_classic_aq_runtime_r;
grant select on nfe_owner.v_nfe_classic_aq_status to nfe_classic_aq_auditor_r;
grant execute on nfe_owner.pkg_nfe_classic_aq_monitor to nfe_classic_aq_auditor_r;
declare
  l_count number;
begin
  select count(*) into l_count from dba_tab_privs
   where owner='NFE_OWNER'
     and table_name in ('NFE_CLASSIC_AQ_Q','NFE_CLASSIC_AQ_EX_Q')
     and grantee in ('NFE_MIGRATION_RUNTIME','NFE_AUDITOR','NFE_PURGE_ADMIN');
  if l_count<>0 then raise_application_error(-20874,'Internal callers retain direct Classic AQ privilege.'); end if;
  dbms_output.put_line('PASS: internal callers use private API roles and have no direct Classic AQ queue grants.');
end;
/
