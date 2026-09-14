create or replace package pkg_nfe_deploy_config authid definer as
 procedure set_environment(p_s3_endpoint varchar2,p_bucket_name varchar2,p_object_prefix varchar2,p_credential_name varchar2,p_source_owner varchar2,p_source_table varchar2,p_source_clob_column varchar2,p_source_id_column varchar2,p_source_key_column varchar2,p_source_date_column varchar2,p_source_status_column varchar2,p_max_inflight number,p_storage_provider varchar2,p_oci_namespace varchar2 default null,p_integrity_mode varchar2 default 'FULL_DOWNLOAD_SHA256');
 procedure get_source(p_owner out varchar2,p_table out varchar2,p_clob_column out varchar2,p_id_column out varchar2,p_key_column out varchar2,p_date_column out varchar2,p_status_column out varchar2);
 procedure get_storage(p_endpoint out varchar2,p_bucket out varchar2,p_prefix out varchar2,p_credential out varchar2);
 procedure get_storage(p_endpoint out varchar2,p_bucket out varchar2,p_prefix out varchar2,p_credential out varchar2,p_provider out varchar2,p_integrity_mode out varchar2,p_oci_namespace out varchar2);
end;
/
create or replace package body pkg_nfe_deploy_config as
 procedure probe_oci_head(p_endpoint varchar2,p_namespace varchar2,p_bucket varchar2,p_prefix varchar2,p_credential varchar2) is
   l_name varchar2(512):=trim(both '/' from p_prefix)||'/_integrity-probe/'||lower(rawtohex(sys_guid()))||'.txt';l_uri varchar2(2048):=rtrim(p_endpoint,'/')||'/n/'||p_namespace||'/b/'||p_bucket||'/o/'||l_name;
   l_blob blob;l_text varchar2(100):='NFE OCI integrity probe '||lower(rawtohex(sys_guid()));l_md5 varchar2(128);l_put dbms_cloud_types.resp;l_head dbms_cloud_types.resp;l_delete dbms_cloud_types.resp;l_headers clob;l_head_md5 varchar2(128);l_head_length number;l_created boolean:=false;
 begin
   dbms_lob.createtemporary(l_blob,true);dbms_lob.writeappend(l_blob,length(l_text),utl_raw.cast_to_raw(l_text));l_md5:=utl_raw.cast_to_varchar2(utl_encode.base64_encode(dbms_crypto.hash(l_blob,dbms_crypto.hash_md5)));
   l_put:=dbms_cloud.send_request(credential_name=>p_credential,uri=>l_uri,method=>dbms_cloud.method_put,headers=>json_object('content-type' value 'text/plain','content-md5' value l_md5,'if-none-match' value '*'),body=>l_blob);l_created:=true;
   if dbms_cloud.get_response_status_code(l_put) not in (200,201) then raise_application_error(-20829,'OCI integrity probe PUT failed.');end if;
   l_head:=dbms_cloud.send_request(credential_name=>p_credential,uri=>l_uri,method=>dbms_cloud.method_head);l_headers:=dbms_cloud.get_response_headers(l_head).to_clob;
   select json_value(l_headers,'$."content-md5"'),to_number(json_value(l_headers,'$."Content-Length"')) into l_head_md5,l_head_length from dual;
   if dbms_cloud.get_response_status_code(l_head)<>200 or l_head_md5 is null or l_head_length is null or l_head_md5<>l_md5 or l_head_length<>dbms_lob.getlength(l_blob) then raise_application_error(-20829,'OCI integrity probe HEAD evidence is missing or failed.');end if;
   l_delete:=dbms_cloud.send_request(credential_name=>p_credential,uri=>l_uri,method=>dbms_cloud.method_delete);if dbms_cloud.get_response_status_code(l_delete) not in (204,200) then raise_application_error(-20829,'OCI integrity probe cleanup failed.');end if;l_created:=false;dbms_lob.freetemporary(l_blob);
 exception when others then
   begin if l_created then l_delete:=dbms_cloud.send_request(credential_name=>p_credential,uri=>l_uri,method=>dbms_cloud.method_delete);end if;exception when others then null;end;
   if l_blob is not null and dbms_lob.istemporary(l_blob)=1 then dbms_lob.freetemporary(l_blob);end if;raise;
 end;
 procedure assert_name(p_name varchar2,p_label varchar2) is begin
   if p_name is null or instr(p_name,'<')>0 or dbms_assert.simple_sql_name(upper(p_name)) is null then
     raise_application_error(-20820,p_label||' must be a simple SQL identifier.');
   end if;
 end;
 function derive_acl_host(p_endpoint varchar2) return varchar2 is
   l_host varchar2(255);
 begin
   if p_endpoint is null or instr(p_endpoint,'<')>0 or
      not regexp_like(p_endpoint, '^https://[A-Za-z0-9.-]+$') then
     raise_application_error(-20821,
       'S3-compatible endpoint must be canonical HTTPS without path, port, query, fragment, or credentials.');
   end if;
   l_host := lower(regexp_substr(p_endpoint, '^https://([^/]+)$', 1, 1, null, 1));
   if l_host is null then
     raise_application_error(-20821,'S3-compatible endpoint host cannot be derived.');
   end if;
   return l_host;
 end;
 procedure set_environment(p_s3_endpoint varchar2,p_bucket_name varchar2,p_object_prefix varchar2,p_credential_name varchar2,p_source_owner varchar2,p_source_table varchar2,p_source_clob_column varchar2,p_source_id_column varchar2,p_source_key_column varchar2,p_source_date_column varchar2,p_source_status_column varchar2,p_max_inflight number,p_storage_provider varchar2,p_oci_namespace varchar2 default null,p_integrity_mode varchar2 default 'FULL_DOWNLOAD_SHA256') is
   l_count number; l_sql varchar2(4000); l_dummy number; l_acl_host varchar2(255);l_provider varchar2(20):=upper(p_storage_provider);l_mode varchar2(32):=upper(p_integrity_mode);
 begin
   assert_name(p_source_owner,'Source owner');
   assert_name(p_source_table,'Source table');
   assert_name(p_source_clob_column,'Source CLOB column');
   assert_name(p_source_id_column,'Source id column');
   assert_name(p_source_key_column,'Source key column');
   assert_name(p_source_date_column,'Source date column');
   assert_name(p_source_status_column,'Source status column');
   assert_name(p_credential_name,'Credential reference');
   if l_provider not in ('S3_COMPATIBLE','OCI_NATIVE') then raise_application_error(-20826,'Storage provider must be S3_COMPATIBLE or OCI_NATIVE.'); end if;
   if l_mode not in ('FULL_DOWNLOAD_SHA256','OCI_MD5_HEAD') or (l_mode='OCI_MD5_HEAD' and l_provider<>'OCI_NATIVE') then raise_application_error(-20827,'Integrity mode is incompatible with storage provider.'); end if;
   l_acl_host := derive_acl_host(p_s3_endpoint);
   if l_provider='OCI_NATIVE' and (p_oci_namespace is null or instr(p_oci_namespace,'<')>0 or not regexp_like(p_oci_namespace,'^[A-Za-z0-9]+$')) then raise_application_error(-20828,'OCI namespace is required for OCI_NATIVE.'); end if;
   if p_bucket_name is null or instr(p_bucket_name,'<')>0 or
      not regexp_like(p_bucket_name, '^[A-Za-z0-9][A-Za-z0-9._-]{0,253}[A-Za-z0-9]$') or
      p_object_prefix is null or instr(p_object_prefix,'<')>0 or
      substr(p_object_prefix,1,1)='/' or instr(p_object_prefix,'..')>0 or
      p_max_inflight is null or p_max_inflight<=0 then
     raise_application_error(-20821,'Valid endpoint, bucket, prefix and positive limit are required for S3-compatible storage.');
   end if;
   select count(*) into l_count from all_tab_columns
    where owner=upper(p_source_owner) and table_name=upper(p_source_table)
      and column_name=upper(p_source_clob_column) and data_type='CLOB';
   if l_count<>1 then raise_application_error(-20822,'Configured source CLOB column does not exist or is not CLOB.'); end if;
   select count(*) into l_count from all_tab_columns
    where owner=upper(p_source_owner) and table_name=upper(p_source_table)
      and column_name=upper(p_source_id_column) and data_type='NUMBER';
   if l_count<>1 then raise_application_error(-20823,'Configured source id column must be NUMBER.'); end if;
   select count(*) into l_count from all_tab_columns
    where owner=upper(p_source_owner) and table_name=upper(p_source_table)
      and column_name in (upper(p_source_key_column),upper(p_source_date_column),upper(p_source_status_column));
   if l_count<>3 then raise_application_error(-20825,'Configured source key, date, or status column does not exist.'); end if;
   select count(*) into l_count from user_credentials where credential_name=upper(p_credential_name);
   if l_count<>1 then raise_application_error(-20824,'Referenced S3-compatible database credential does not exist for NFE_OWNER.'); end if;
   if l_mode='OCI_MD5_HEAD' then
     probe_oci_head(p_s3_endpoint,p_oci_namespace,p_bucket_name,p_object_prefix,upper(p_credential_name));
     insert into nfe_deploy_config_audit(actor,event_type,s3_endpoint,bucket_name,object_prefix,credential_name)
       values(user,'OCI_HEAD_PROBE_PASSED',p_s3_endpoint,p_bucket_name,p_object_prefix,upper(p_credential_name));
   end if;
   l_sql := 'select count(*) from '||dbms_assert.schema_name(upper(p_source_owner))||'.'||
            dbms_assert.simple_sql_name(upper(p_source_table))||' where '||
            dbms_assert.simple_sql_name(upper(p_source_clob_column))||' is not null';
   execute immediate l_sql into l_dummy; -- proves definer can read; no data is changed
   merge into nfe_deploy_source_config d using (select 1 id from dual) s on(d.config_id=s.id)
    when matched then update set source_owner=upper(p_source_owner),source_table=upper(p_source_table),
      source_clob_column=upper(p_source_clob_column),source_id_column=upper(p_source_id_column),
      source_key_column=upper(p_source_key_column),source_date_column=upper(p_source_date_column),
      source_status_column=upper(p_source_status_column),updated_by=user,updated_at=systimestamp
    when not matched then insert(config_id,source_owner,source_table,source_clob_column,source_id_column,
      source_key_column,source_date_column,source_status_column,updated_by)
      values(1,upper(p_source_owner),upper(p_source_table),upper(p_source_clob_column),upper(p_source_id_column),
        upper(p_source_key_column),upper(p_source_date_column),upper(p_source_status_column),user);
   merge into nfe_deploy_storage_config d using (select 1 id from dual) s on(d.config_id=s.id)
    when matched then update set s3_endpoint=p_s3_endpoint,bucket_name=p_bucket_name,
      object_prefix=p_object_prefix,acl_host=l_acl_host,credential_name=upper(p_credential_name),
      max_inflight=p_max_inflight,storage_provider=l_provider,integrity_mode=l_mode,oci_namespace=case when l_provider='OCI_NATIVE' then p_oci_namespace else null end,updated_by=user,updated_at=systimestamp
    when not matched then insert(config_id,s3_endpoint,bucket_name,object_prefix,acl_host,credential_name,
      max_inflight,storage_provider,integrity_mode,oci_namespace,updated_by)
      values(1,p_s3_endpoint,p_bucket_name,p_object_prefix,l_acl_host,upper(p_credential_name),p_max_inflight,l_provider,l_mode,case when l_provider='OCI_NATIVE' then p_oci_namespace end,user);
   insert into nfe_deploy_config_audit(actor,event_type,source_owner,source_table,source_clob_column,
     s3_endpoint,bucket_name,object_prefix,credential_name)
    values(user,'ENVIRONMENT_CONFIGURED',upper(p_source_owner),upper(p_source_table),
      upper(p_source_clob_column),p_s3_endpoint,p_bucket_name,p_object_prefix,upper(p_credential_name));
 end;
 procedure get_source(p_owner out varchar2,p_table out varchar2,p_clob_column out varchar2,p_id_column out varchar2,p_key_column out varchar2,p_date_column out varchar2,p_status_column out varchar2) is begin
   select source_owner,source_table,source_clob_column,source_id_column,source_key_column,
     source_date_column,source_status_column into p_owner,p_table,p_clob_column,p_id_column,
     p_key_column,p_date_column,p_status_column from nfe_deploy_source_config where config_id=1;
 end;
 procedure get_storage(p_endpoint out varchar2,p_bucket out varchar2,p_prefix out varchar2,p_credential out varchar2) is begin
   select s3_endpoint,bucket_name,object_prefix,credential_name into p_endpoint,p_bucket,p_prefix,p_credential
     from nfe_deploy_storage_config where config_id=1;
 end;
 procedure get_storage(p_endpoint out varchar2,p_bucket out varchar2,p_prefix out varchar2,p_credential out varchar2,p_provider out varchar2,p_integrity_mode out varchar2,p_oci_namespace out varchar2) is begin
   select s3_endpoint,bucket_name,object_prefix,credential_name,storage_provider,integrity_mode,oci_namespace into p_endpoint,p_bucket,p_prefix,p_credential,p_provider,p_integrity_mode,p_oci_namespace from nfe_deploy_storage_config where config_id=1;
 end;
end;
/
