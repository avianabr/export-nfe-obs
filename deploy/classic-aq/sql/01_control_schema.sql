-- Idempotence is conservative: an existing object must have the expected type.
declare
  procedure require_absent_or_table(p_name varchar2) is l_count number; l_type varchar2(30); begin
    select count(*), max(object_type) into l_count,l_type from user_objects where object_name=p_name;
    if l_count > 0 and l_type <> 'TABLE' then raise_application_error(-20810, 'Conflicting object '||p_name||' is not a table.'); end if;
  end;
  procedure require_columns(p_table varchar2, p_columns sys.odcivarchar2list) is
    l_exists number;
    l_present number;
  begin
    select count(*) into l_exists from user_tables where table_name=p_table;
    if l_exists=1 then
      select count(*) into l_present from user_tab_columns
       where table_name=p_table and column_name in (select upper(column_value) from table(p_columns));
      if l_present<>p_columns.count then
        raise_application_error(-20811,'Conflicting table '||p_table||' does not have the required deployment columns; no change was made.');
      end if;
    end if;
  end;
begin
  require_absent_or_table('NFE_DEPLOY_SOURCE_CONFIG');
  require_absent_or_table('NFE_DEPLOY_STORAGE_CONFIG');
  require_absent_or_table('NFE_CLASSIC_AQ_CONFIG');
  require_absent_or_table('NFE_DEPLOY_CONFIG_AUDIT');
  require_absent_or_table('NFE_MIGRATION_BATCH');
  require_absent_or_table('NFE_MIGRATION_ITEM');
  require_columns('NFE_DEPLOY_SOURCE_CONFIG',sys.odcivarchar2list('CONFIG_ID','SOURCE_OWNER','SOURCE_TABLE','SOURCE_CLOB_COLUMN','SOURCE_ID_COLUMN','SOURCE_KEY_COLUMN','SOURCE_DATE_COLUMN','SOURCE_STATUS_COLUMN','UPDATED_BY','UPDATED_AT'));
  require_columns('NFE_DEPLOY_STORAGE_CONFIG',sys.odcivarchar2list('CONFIG_ID','S3_ENDPOINT','BUCKET_NAME','OBJECT_PREFIX','ACL_HOST','CREDENTIAL_NAME','MAX_INFLIGHT','UPDATED_BY','UPDATED_AT'));
  require_columns('NFE_CLASSIC_AQ_CONFIG',sys.odcivarchar2list('CONFIG_ID','CLASSIC_AQ_ENABLED','UPDATED_BY','UPDATED_AT'));
  require_columns('NFE_DEPLOY_CONFIG_AUDIT',sys.odcivarchar2list('AUDIT_ID','EVENT_AT','ACTOR','EVENT_TYPE'));
  require_columns('NFE_MIGRATION_BATCH',sys.odcivarchar2list('BATCH_ID','BATCH_CODE','STATUS','CUTOFF_DATE','MAX_DOCUMENTS','CREATED_BY','CREATED_AT'));
  require_columns('NFE_MIGRATION_ITEM',sys.odcivarchar2list('CONTROL_ID','BATCH_ID','NFE_ID','OBJECT_KEY','OBJECT_URI','STATUS','AQ_MSGID','SOURCE_SHA256','OBJECT_SHA256','CREATED_AT','UPDATED_AT'));
end;
/
begin
 execute immediate q'[create table nfe_deploy_source_config (config_id number constraint pk_nfe_deploy_source_config primary key check (config_id=1), source_owner varchar2(128) not null, source_table varchar2(128) not null, source_clob_column varchar2(128) not null, source_id_column varchar2(128) not null, source_key_column varchar2(128) not null, source_date_column varchar2(128) not null, source_status_column varchar2(128) not null, updated_by varchar2(128) not null, updated_at timestamp with time zone default systimestamp not null)]';
exception when others then if sqlcode <> -955 then raise; end if; end;
/
begin
 execute immediate q'[create table nfe_deploy_storage_config (config_id number constraint pk_nfe_deploy_storage_config primary key check (config_id=1), s3_endpoint varchar2(1000) not null, bucket_name varchar2(255) not null, object_prefix varchar2(512) not null, acl_host varchar2(255) not null, credential_name varchar2(128) not null, max_inflight number not null check(max_inflight>0), updated_by varchar2(128) not null, updated_at timestamp with time zone default systimestamp not null)]';
exception when others then if sqlcode <> -955 then raise; end if; end;
/
begin
 execute immediate q'[create table nfe_classic_aq_config (config_id number constraint pk_nfe_classic_aq_config primary key check(config_id=1), classic_aq_enabled char(1) default 'N' not null check(classic_aq_enabled in ('Y','N')), updated_by varchar2(128) not null, updated_at timestamp with time zone default systimestamp not null)]';
exception when others then if sqlcode <> -955 then raise; end if; end;
/
begin
 execute immediate q'[create table nfe_deploy_config_audit (audit_id number generated always as identity primary key, event_at timestamp with time zone default systimestamp not null, actor varchar2(128) not null, event_type varchar2(40) not null, source_owner varchar2(128), source_table varchar2(128), source_clob_column varchar2(128), s3_endpoint varchar2(1000), bucket_name varchar2(255), object_prefix varchar2(512), credential_name varchar2(128))]';
exception when others then if sqlcode <> -955 then raise; end if; end;
/
merge into nfe_classic_aq_config d using (select 1 id from dual) s on(d.config_id=s.id) when not matched then insert(config_id,updated_by) values(1,user);
begin
 execute immediate q'[create table nfe_migration_batch (batch_id number generated always as identity primary key, batch_code varchar2(50) not null unique, status varchar2(20) not null check(status in ('CREATED','SELECTING','PROCESSING','VERIFIED','BLOCKED','CANCELLED')), cutoff_date timestamp with time zone not null, max_documents number not null check(max_documents>0), created_by varchar2(128) not null, created_at timestamp with time zone default systimestamp not null)]';
exception when others then if sqlcode <> -955 then raise; end if; end;
/
begin
 execute immediate q'[create table nfe_migration_item (control_id number generated always as identity primary key, batch_id number not null references nfe_migration_batch(batch_id), nfe_id number not null, object_key varchar2(1024) not null unique, object_uri varchar2(2000) not null, status varchar2(20) not null check(status in ('QUEUED','UPLOADING','UPLOADED','VERIFYING','VERIFIED','PURGED','FAILED','EXCEPTION')), aq_msgid raw(16), source_sha256 varchar2(64), object_sha256 varchar2(64), last_error varchar2(4000), created_at timestamp with time zone default systimestamp not null, updated_at timestamp with time zone default systimestamp not null, constraint uk_nfe_migration_item_source unique(batch_id,nfe_id))]';
exception when others then if sqlcode <> -955 then raise; end if; end;
/
create or replace trigger trg_nfe_deploy_item_updated
before update on nfe_migration_item for each row
begin :new.updated_at := systimestamp; end;
/
