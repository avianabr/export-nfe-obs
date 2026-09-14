-- Metadata only: this script intentionally contains no CREATE, ALTER, DROP,
-- DBMS_AQ, DBMS_SCHEDULER, DML, or network call. The local SQL*Plus defines
-- loaded by 04_preflight.sql are validated but never persisted here.
declare
  l_missing varchar2(32767);
  l_count number;
  l_endpoint varchar2(1000) := '&&DEPLOY_S3_ENDPOINT';
  l_provider varchar2(20) := upper('&&DEPLOY_STORAGE_PROVIDER');
  l_oci_namespace varchar2(128) := '&&DEPLOY_OCI_NAMESPACE';
  l_integrity_mode varchar2(32) := upper('&&DEPLOY_INTEGRITY_MODE');
  l_bucket varchar2(255) := '&&DEPLOY_BUCKET_NAME';
  l_prefix varchar2(512) := '&&DEPLOY_OBJECT_PREFIX';
  l_credential varchar2(128) := upper('&&DEPLOY_CREDENTIAL_NAME');
  l_source_owner varchar2(128) := upper('&&DEPLOY_SOURCE_OWNER');
  l_source_table varchar2(128) := upper('&&DEPLOY_SOURCE_TABLE');
  l_source_clob varchar2(128) := upper('&&DEPLOY_SOURCE_CLOB_COLUMN');
  l_source_id varchar2(128) := upper('&&DEPLOY_SOURCE_ID_COLUMN');
  l_source_key varchar2(128) := upper('&&DEPLOY_SOURCE_KEY_COLUMN');
  l_source_date varchar2(128) := upper('&&DEPLOY_SOURCE_DATE_COLUMN');
  l_source_status varchar2(128) := upper('&&DEPLOY_SOURCE_STATUS_COLUMN');
  l_max_inflight varchar2(128) := '&&DEPLOY_MAX_INFLIGHT';
  l_acl_host varchar2(255);
  procedure require_count(p_label varchar2, p_count number) is begin
    if p_count = 0 then l_missing := l_missing || chr(10) || ' - ' || p_label; end if;
  end;
  procedure require_name(p_label varchar2, p_value varchar2) is begin
    if p_value is null or instr(p_value,'<')>0 or not regexp_like(p_value, '^[A-Z][A-Z0-9_$#]{0,127}$') then
      l_missing := l_missing || chr(10) || ' - ' || p_label;
    end if;
  end;
begin
  if l_provider not in ('S3_COMPATIBLE','OCI_NATIVE') then
    l_missing := l_missing || chr(10) || ' - storage provider S3_COMPATIBLE or OCI_NATIVE';
  end if;
  if l_integrity_mode not in ('FULL_DOWNLOAD_SHA256','OCI_MD5_HEAD') or (l_integrity_mode='OCI_MD5_HEAD' and l_provider<>'OCI_NATIVE') then
    l_missing := l_missing || chr(10) || ' - integrity mode compatible with storage provider';
  end if;
  select count(*) into l_count from v$pdbs
   where name = sys_context('USERENV','CON_NAME') and open_mode = 'READ WRITE';
  require_count('open read-write PDB', l_count);
  for p in (select column_value name from table(sys.odcivarchar2list(
      'NFE_OWNER','NFE_MIGRATION_RUNTIME'))) loop
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

  if l_endpoint is null or instr(l_endpoint,'<')>0 or
     not regexp_like(l_endpoint, '^https://[A-Za-z0-9.-]+$') then
    l_missing := l_missing || chr(10) ||
      ' - canonical HTTPS S3-compatible endpoint without path, port, query, fragment, or credentials';
  else
    l_acl_host := lower(regexp_substr(l_endpoint, '^https://([^/]+)$', 1, 1, null, 1));
  end if;
  if l_bucket is null or instr(l_bucket,'<')>0 or
     not regexp_like(l_bucket, '^[A-Za-z0-9][A-Za-z0-9._-]{0,253}[A-Za-z0-9]$') then
    l_missing := l_missing || chr(10) || ' - S3-compatible bucket name';
  end if;
  if l_provider='OCI_NATIVE' and (l_oci_namespace is null or instr(l_oci_namespace,'<')>0 or not regexp_like(l_oci_namespace,'^[A-Za-z0-9]+$')) then
    l_missing := l_missing || chr(10) || ' - OCI namespace for OCI_NATIVE';
  end if;
  if l_prefix is null or instr(l_prefix,'<')>0 or substr(l_prefix,1,1)='/' or instr(l_prefix,'..')>0 then
    l_missing := l_missing || chr(10) || ' - nonempty safe object prefix without a leading slash';
  end if;
  require_name('database credential reference', l_credential);
  require_name('source owner', l_source_owner);
  require_name('source table', l_source_table);
  require_name('source CLOB column', l_source_clob);
  require_name('source id column', l_source_id);
  require_name('source key column', l_source_key);
  require_name('source date column', l_source_date);
  require_name('source status column', l_source_status);
  if l_max_inflight is null or instr(l_max_inflight,'<')>0 or
     not regexp_like(l_max_inflight, '^[1-9][0-9]*$') then
    l_missing := l_missing || chr(10) || ' - positive max inflight limit';
  end if;
  if l_credential is not null and instr(l_credential,'<')=0 and
     regexp_like(l_credential, '^[A-Z][A-Z0-9_$#]{0,127}$') then
    select count(*) into l_count from dba_credentials
     where owner='NFE_OWNER' and credential_name=l_credential;
    require_count('NFE_OWNER credential ' || l_credential, l_count);
  end if;
  if l_source_owner is not null and l_source_table is not null and
     instr(l_source_owner,'<')=0 and instr(l_source_table,'<')=0 then
    select count(*) into l_count from dba_tables
     where owner=l_source_owner and table_name=l_source_table;
    require_count('configured source table ' || l_source_owner || '.' || l_source_table, l_count);
  end if;
  if regexp_like(l_source_owner, '^[A-Z][A-Z0-9_$#]{0,127}$') and
     regexp_like(l_source_table, '^[A-Z][A-Z0-9_$#]{0,127}$') then
    select count(*) into l_count from dba_tab_columns
     where owner=l_source_owner and table_name=l_source_table
       and column_name=l_source_clob and data_type='CLOB';
    require_count('configured source CLOB column ' || l_source_clob, l_count);
    select count(*) into l_count from dba_tab_columns
     where owner=l_source_owner and table_name=l_source_table
       and column_name=l_source_id and data_type='NUMBER';
    require_count('configured source NUMBER id column ' || l_source_id, l_count);
    select count(*) into l_count from dba_tab_columns
     where owner=l_source_owner and table_name=l_source_table
       and column_name in (l_source_key,l_source_date,l_source_status);
    if l_count<>3 then
      l_missing := l_missing || chr(10) || ' - configured source key, date, and status columns';
    end if;
    if l_source_owner<>'NFE_OWNER' then
      select count(*) into l_count from dba_tab_privs
       where owner=l_source_owner and table_name=l_source_table
         and grantee='NFE_OWNER' and privilege='SELECT';
      require_count('direct SELECT for NFE_OWNER on configured source table', l_count);
    end if;
  end if;
  for o in (select column_value name from table(sys.odcivarchar2list(
      'NFE_DEPLOY_SOURCE_CONFIG','NFE_DEPLOY_STORAGE_CONFIG','NFE_DEPLOY_CONFIG_AUDIT',
      'NFE_CLASSIC_AQ_CONFIG','NFE_CLASSIC_AQ_QT','NFE_CLASSIC_AQ_Q',
      'NFE_CLASSIC_AQ_EX_Q','NFE_CLASSIC_AQ_WORKER_JOB'))) loop
    select count(*) into l_count from dba_objects
     where owner='NFE_OWNER' and object_name=o.name
       and object_type not in ('TABLE','QUEUE','QUEUE TABLE','JOB');
    if l_count > 0 then
      l_missing := l_missing || chr(10) || ' - incompatible existing object NFE_OWNER.' || o.name;
    end if;
  end loop;
  if l_missing is not null then raise_application_error(-20800, 'Preflight failed:' || l_missing); end if;
  dbms_output.put_line('PASS: PDB, accounts, DBMS_CLOUD/AQ privileges, shared environment, S3-compatible credential and install targets are eligible; no DDL was executed.');
end;
/
