declare
  procedure ensure_role(p_role varchar2) is l_count number; begin
    select count(*) into l_count from dba_roles where role=p_role;
    if l_count=0 then execute immediate 'create role '||dbms_assert.simple_sql_name(p_role); end if;
  end;
  procedure ensure_user(p_user varchar2,p_password varchar2,p_role varchar2) is l_count number; l_auth varchar2(30); begin
    if p_password is null or instr(p_password,'<')>0 or instr(p_password,'"')>0 then raise_application_error(-20890,'Protected password required for '||p_user); end if;
    select count(*),max(authentication_type) into l_count,l_auth from dba_users where username=p_user;
    if l_count=0 then execute immediate 'create user '||p_user||' identified by "'||p_password||'" account unlock';
    elsif l_auth<>'PASSWORD' then raise_application_error(-20891,'Incompatible internal user '||p_user||'; no change made.'); end if;
    execute immediate 'grant create session, '||p_role||' to '||p_user;
  end;
begin
  ensure_role('NFE_CLASSIC_AQ_RUNTIME_R'); ensure_role('NFE_CLASSIC_AQ_AUDITOR_R'); ensure_role('NFE_CLASSIC_AQ_PURGE_R');
  ensure_user('NFE_MIGRATION_RUNTIME','&&NFE_MIGRATION_RUNTIME_PASSWORD','NFE_CLASSIC_AQ_RUNTIME_R');
  ensure_user('NFE_AUDITOR','&&NFE_AUDITOR_PASSWORD','NFE_CLASSIC_AQ_AUDITOR_R');
  ensure_user('NFE_PURGE_ADMIN','&&NFE_PURGE_ADMIN_PASSWORD','NFE_CLASSIC_AQ_PURGE_R');
  dbms_output.put_line('PASS: internal users and roles created or validated.');
end;
/
