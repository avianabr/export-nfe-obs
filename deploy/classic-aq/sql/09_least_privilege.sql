-- Run as SYS only after 05_install.sql has completed as NFE_OWNER.
-- This prescribed installation step derives and applies the HTTP ACL from the
-- persisted storage configuration. This keeps ACL derivation aligned with the
-- selected provider endpoint even when the script is run independently.
set verify off
declare
  l_endpoint varchar2(1000);
  l_acl_host varchar2(255);
begin
  select s3_endpoint into l_endpoint from nfe_owner.nfe_deploy_storage_config where config_id=1;
  if l_endpoint is null or instr(l_endpoint, '<') > 0 or
     not regexp_like(l_endpoint, '^https://[A-Za-z0-9.-]+$') then
    raise_application_error(-20875,
      'A canonical HTTPS S3-compatible endpoint is required to apply the installation ACL.');
  end if;
  l_acl_host := lower(regexp_substr(l_endpoint, '^https://([^/]+)$', 1, 1, null, 1));
  begin
    dbms_network_acl_admin.append_host_ace(
      host => l_acl_host,
      ace  => xs$ace_type(
        privilege_list => xs$name_list('http'),
        principal_name => 'NFE_OWNER',
        principal_type => xs_acl.ptype_db,
        granted => true));
  exception
    when others then
      if sqlcode <> -24243 then raise; end if; -- matching ACE already exists
  end;
  dbms_output.put_line('PASS: HTTP ACL for NFE_OWNER applied or already present for ' || l_acl_host || '.');
end;
/
begin
 for r in (select grantee, privilege, table_name from dba_tab_privs where owner='NFE_OWNER' and table_name in ('NFE_CLASSIC_AQ_Q','NFE_CLASSIC_AQ_EX_Q') and grantee='NFE_MIGRATION_RUNTIME') loop
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
     and grantee = 'NFE_MIGRATION_RUNTIME';
  if l_count<>0 then raise_application_error(-20874,'Internal callers retain direct Classic AQ privilege.'); end if;
  dbms_output.put_line('PASS: runtime identity uses its private API role and has no direct Classic AQ queue grants.');
end;
/
