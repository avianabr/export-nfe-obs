create or replace package pkg_nfe_deploy_config authid definer as
 procedure set_environment(p_s3_endpoint varchar2,p_bucket_name varchar2,p_object_prefix varchar2,p_acl_host varchar2,p_credential_name varchar2,p_source_owner varchar2,p_source_table varchar2,p_source_clob_column varchar2,p_source_id_column varchar2,p_source_key_column varchar2,p_source_date_column varchar2,p_source_status_column varchar2,p_max_inflight number);
 procedure get_source(p_owner out varchar2,p_table out varchar2,p_clob_column out varchar2,p_id_column out varchar2,p_key_column out varchar2,p_date_column out varchar2,p_status_column out varchar2);
 procedure get_storage(p_endpoint out varchar2,p_bucket out varchar2,p_prefix out varchar2,p_credential out varchar2);
end;
/
create or replace package body pkg_nfe_deploy_config as
 procedure assert_name(p_name varchar2,p_label varchar2) is begin
   if p_name is null or dbms_assert.simple_sql_name(upper(p_name)) is null then raise_application_error(-20820,p_label||' must be a simple SQL identifier.'); end if;
 end;
 procedure set_environment(p_s3_endpoint varchar2,p_bucket_name varchar2,p_object_prefix varchar2,p_acl_host varchar2,p_credential_name varchar2,p_source_owner varchar2,p_source_table varchar2,p_source_clob_column varchar2,p_source_id_column varchar2,p_source_key_column varchar2,p_source_date_column varchar2,p_source_status_column varchar2,p_max_inflight number) is
   l_count number; l_type varchar2(30); l_sql varchar2(4000); l_dummy number;
 begin
   assert_name(p_source_owner,'Source owner'); assert_name(p_source_table,'Source table'); assert_name(p_source_clob_column,'Source CLOB column'); assert_name(p_source_id_column,'Source id column'); assert_name(p_source_key_column,'Source key column'); assert_name(p_source_date_column,'Source date column'); assert_name(p_source_status_column,'Source status column'); assert_name(p_credential_name,'Credential reference');
   if p_s3_endpoint not like 'https://%' or instr(p_s3_endpoint,'?')>0 or p_bucket_name is null or p_object_prefix is null or p_acl_host is null or p_max_inflight<=0 then raise_application_error(-20821,'Endpoint, bucket, prefix, ACL host and positive limit are required for S3-compatible storage.'); end if;
   select count(*) into l_count from all_tab_columns where owner=upper(p_source_owner) and table_name=upper(p_source_table) and column_name=upper(p_source_clob_column) and data_type='CLOB';
   if l_count<>1 then raise_application_error(-20822,'Configured source CLOB column does not exist or is not CLOB.'); end if;
   select count(*) into l_count from all_tab_columns where owner=upper(p_source_owner) and table_name=upper(p_source_table) and column_name=upper(p_source_id_column) and data_type='NUMBER';
   if l_count<>1 then raise_application_error(-20823,'Configured source id column must be NUMBER.'); end if;
   select count(*) into l_count from all_tab_columns where owner=upper(p_source_owner) and table_name=upper(p_source_table) and column_name in (upper(p_source_key_column),upper(p_source_date_column),upper(p_source_status_column));
   if l_count<>3 then raise_application_error(-20825,'Configured source key, date, or status column does not exist.'); end if;
   select count(*) into l_count from user_credentials where credential_name=upper(p_credential_name);
   if l_count<>1 then raise_application_error(-20824,'Referenced S3-compatible database credential does not exist for NFE_OWNER.'); end if;
   l_sql := 'select count(*) from '||dbms_assert.schema_name(upper(p_source_owner))||'.'||dbms_assert.simple_sql_name(upper(p_source_table))||' where '||dbms_assert.simple_sql_name(upper(p_source_clob_column))||' is not null';
   execute immediate l_sql into l_dummy; -- proves definer can read; no data is changed
   merge into nfe_deploy_source_config d using (select 1 id from dual) s on(d.config_id=s.id) when matched then update set source_owner=upper(p_source_owner),source_table=upper(p_source_table),source_clob_column=upper(p_source_clob_column),source_id_column=upper(p_source_id_column),source_key_column=upper(p_source_key_column),source_date_column=upper(p_source_date_column),source_status_column=upper(p_source_status_column),updated_by=user,updated_at=systimestamp when not matched then insert(config_id,source_owner,source_table,source_clob_column,source_id_column,source_key_column,source_date_column,source_status_column,updated_by) values(1,upper(p_source_owner),upper(p_source_table),upper(p_source_clob_column),upper(p_source_id_column),upper(p_source_key_column),upper(p_source_date_column),upper(p_source_status_column),user);
   merge into nfe_deploy_storage_config d using (select 1 id from dual) s on(d.config_id=s.id) when matched then update set s3_endpoint=p_s3_endpoint,bucket_name=p_bucket_name,object_prefix=p_object_prefix,acl_host=p_acl_host,credential_name=upper(p_credential_name),max_inflight=p_max_inflight,updated_by=user,updated_at=systimestamp when not matched then insert(config_id,s3_endpoint,bucket_name,object_prefix,acl_host,credential_name,max_inflight,updated_by) values(1,p_s3_endpoint,p_bucket_name,p_object_prefix,p_acl_host,upper(p_credential_name),p_max_inflight,user);
   insert into nfe_deploy_config_audit(actor,event_type,source_owner,source_table,source_clob_column,s3_endpoint,bucket_name,object_prefix,credential_name) values(user,'ENVIRONMENT_CONFIGURED',upper(p_source_owner),upper(p_source_table),upper(p_source_clob_column),p_s3_endpoint,p_bucket_name,p_object_prefix,upper(p_credential_name));
 end;
 procedure get_source(p_owner out varchar2,p_table out varchar2,p_clob_column out varchar2,p_id_column out varchar2,p_key_column out varchar2,p_date_column out varchar2,p_status_column out varchar2) is begin select source_owner,source_table,source_clob_column,source_id_column,source_key_column,source_date_column,source_status_column into p_owner,p_table,p_clob_column,p_id_column,p_key_column,p_date_column,p_status_column from nfe_deploy_source_config where config_id=1; end;
 procedure get_storage(p_endpoint out varchar2,p_bucket out varchar2,p_prefix out varchar2,p_credential out varchar2) is begin select s3_endpoint,bucket_name,object_prefix,credential_name into p_endpoint,p_bucket,p_prefix,p_credential from nfe_deploy_storage_config where config_id=1; end;
end;
/
