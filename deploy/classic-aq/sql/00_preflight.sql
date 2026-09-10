-- Metadata only: this script intentionally contains no CREATE, ALTER, DROP,
-- DBMS_AQ, DBMS_SCHEDULER, DML, or network call. The local SQL*Plus defines
-- loaded by preflight.sql are validated but never persisted here.
declare
  l_missing varchar2(32767);
  l_count number;
  l_endpoint varchar2(1000) := '&&DEPLOY_S3_ENDPOINT';
  l_bucket varchar2(255) := '&&DEPLOY_BUCKET_NAME';
  l_prefix varchar2(512) := '&&DEPLOY_OBJECT_PREFIX';
  l_acl_host varchar2(255) := '&&DEPLOY_ACL_HOST';
  l_endpoint_host varchar2(255);
  l_credential varchar2(128) := upper('&&DEPLOY_CREDENTIAL_NAME');
  procedure require_count(p_label varchar2, p_count number) is begin
    if p_count = 0 then l_missing := l_missing || chr(10) || ' - ' || p_label; end if;
  end;
begin
  select count(*) into l_count from v$pdbs where name = sys_context('USERENV','CON_NAME') and open_mode = 'READ WRITE';
  require_count('open read-write PDB', l_count);
  for p in (select column_value name from table(sys.odcivarchar2list('NFE_OWNER','NFE_MIGRATION_RUNTIME','NFE_AUDITOR','NFE_PURGE_ADMIN'))) loop
    select count(*) into l_count from dba_users where username = p.name;
    require_count('database account ' || p.name, l_count);
  end loop;
  select count(*) into l_count from dba_objects
   where object_name='DBMS_CLOUD' and object_type='PACKAGE' and status='VALID';
  require_count('valid DBMS_CLOUD package in this PDB (normally C##CLOUD$SERVICE)', l_count);
  select count(*) into l_count from dba_tab_privs
   where grantee='NFE_OWNER' and table_name='DBMS_CLOUD' and privilege='EXECUTE';
  if l_count=0 then
    select count(*) into l_count from dba_role_privs
     where grantee='NFE_OWNER' and granted_role='DWROLE';
  end if;
  require_count('NFE_OWNER permission to execute DBMS_CLOUD', l_count);
  for p in (select column_value package_name
              from table(sys.odcivarchar2list('DBMS_AQ','DBMS_AQADM','DBMS_CRYPTO'))) loop
    select count(*) into l_count from dba_tab_privs
     where grantee='NFE_OWNER' and table_name=p.package_name and privilege='EXECUTE';
    require_count('direct EXECUTE on ' || p.package_name || ' for NFE_OWNER', l_count);
  end loop;
  select count(*) into l_count from dba_role_privs
   where grantee='NFE_OWNER' and granted_role='AQ_ADMINISTRATOR_ROLE';
  require_count('AQ_ADMINISTRATOR_ROLE granted to NFE_OWNER', l_count);
  select count(*) into l_count from dba_sys_privs
   where grantee='NFE_OWNER' and privilege='CREATE JOB';
  require_count('CREATE JOB granted directly to NFE_OWNER', l_count);
  if l_endpoint is null or not regexp_like(l_endpoint, '^https://[^/?#]+(/[^?#]*)?$') then
    l_missing := l_missing || chr(10) || ' - HTTPS S3-compatible endpoint without query or fragment';
  else
    l_endpoint_host := lower(regexp_substr(l_endpoint, '^https://([^/:]+)', 1, 1, null, 1));
  end if;
  -- OCI's S3-compatible endpoint accepts the underscore used by the existing
  -- PoC bucket name; retain the remaining conservative character checks.
  if l_bucket is null or instr(l_bucket,'<')>0 or not regexp_like(l_bucket, '^[A-Za-z0-9][A-Za-z0-9._-]{0,253}[A-Za-z0-9]$') then
    l_missing := l_missing || chr(10) || ' - S3-compatible bucket name';
  end if;
  if l_prefix is null or instr(l_prefix,'<')>0 or substr(l_prefix,1,1)='/' or instr(l_prefix,'..')>0 then
    l_missing := l_missing || chr(10) || ' - nonempty safe object prefix without a leading slash';
  end if;
  if l_acl_host is null or instr(l_acl_host,'<')>0 or not regexp_like(l_acl_host, '^[A-Za-z0-9.-]+$') then
    l_missing := l_missing || chr(10) || ' - ACL host matching the S3-compatible endpoint';
  elsif l_endpoint_host is not null and lower(l_acl_host)<>l_endpoint_host then
    l_missing := l_missing || chr(10) || ' - ACL host must exactly match the S3-compatible endpoint host ' || l_endpoint_host;
  end if;
  if l_credential is null or instr(l_credential,'<')>0 or not regexp_like(l_credential, '^[A-Z][A-Z0-9_$#]{0,127}$') then
    l_missing := l_missing || chr(10) || ' - database credential reference';
  else
    select count(*) into l_count from dba_credentials where owner='NFE_OWNER' and credential_name=l_credential;
    require_count('NFE_OWNER credential ' || l_credential, l_count);
  end if;
  select count(*) into l_count from dba_network_acls
   where host=lower(l_acl_host) or host='*';
  require_count('network ACL metadata for ' || l_acl_host, l_count);
  select count(*) into l_count from dba_host_aces
   where (host=lower(l_acl_host) or host='*')
     and principal='NFE_OWNER'
     and privilege='HTTP'
     and grant_type='GRANT';
  require_count('HTTP ACL grant for NFE_OWNER on ' || l_acl_host, l_count);
  for o in (select column_value name from table(sys.odcivarchar2list('NFE_DEPLOY_SOURCE_CONFIG','NFE_DEPLOY_STORAGE_CONFIG','NFE_DEPLOY_CONFIG_AUDIT','NFE_CLASSIC_AQ_CONFIG','NFE_CLASSIC_AQ_QT','NFE_CLASSIC_AQ_Q','NFE_CLASSIC_AQ_EX_Q','NFE_CLASSIC_AQ_WORKER_JOB'))) loop
    select count(*) into l_count from dba_objects where owner='NFE_OWNER' and object_name=o.name and object_type not in ('TABLE','QUEUE','QUEUE TABLE','JOB');
    if l_count > 0 then l_missing := l_missing || chr(10) || ' - incompatible existing object NFE_OWNER.' || o.name; end if;
  end loop;
  if l_missing is not null then raise_application_error(-20800, 'Preflight failed:' || l_missing); end if;
  dbms_output.put_line('PASS: PDB, accounts, DBMS_CLOUD/AQ privileges, S3-compatible metadata, credential, ACL and install targets are eligible; no DDL was executed.');
end;
/
