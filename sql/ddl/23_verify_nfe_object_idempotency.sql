-- Run as NFE_OWNER after rerunning 19_create_nfe_worker_package.sql.
-- Leaves one deliberately divergent test object under the deterministic PoC
-- prefix; its Oracle control rows and append-only audit evidence are retained.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_marker varchar2(20) := substr(rawtohex(sys_guid()),1,20);
  l_batch number; l_nfe number; l_nfe2 number; l_item number; l_item2 number; l_uri varchar2(2000); l_uri2 varchar2(2000); l_key varchar2(1024); l_key2 varchar2(1024);
  l_blob blob; l_raw raw(32767) := utl_i18n.string_to_raw('divergent-object-test','AL32UTF8');
  l_status varchar2(30);
begin
  select nfe_id into l_nfe from poc_nfe_document d
   where d.xml_clob is not null and not exists (select 1 from nfe_migration_item i where i.nfe_id=d.nfe_id)
     and rownum=1;
  select nfe_id into l_nfe2 from poc_nfe_document d
   where d.xml_clob is not null and d.nfe_id <> l_nfe and not exists (select 1 from nfe_migration_item i where i.nfe_id=d.nfe_id)
     and rownum=1;
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,selection_chunk_size,criteria_json,created_by)
  values('IDEMP-'||l_marker,'CREATED',systimestamp-interval '1' day,1,1,'{"purpose":"idempotency"}',user)
  returning batch_id into l_batch;
  update nfe_migration_batch set status='SELECTING' where batch_id=l_batch;
  select 'nfe/'||to_char(data_emissao at time zone 'UTC','YYYY/MM')||'/'||chave_nfe||'.xml' into l_key from poc_nfe_document where nfe_id=l_nfe;
  l_uri := 'https://idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com/POC_RT/'||l_key;
  insert into nfe_migration_item(batch_id,nfe_id,status,object_key,object_uri) values(l_batch,l_nfe,'QUEUED',l_key,l_uri) returning control_id into l_item;
  commit;
  pkg_nfe_worker.upload_item(l_item); rollback; -- PUT persists; Oracle state returns to QUEUED.
  pkg_nfe_worker.upload_item(l_item); commit; -- Existing identical object is reused.
  select status into l_status from nfe_migration_item where control_id=l_item;
  if l_status <> 'UPLOADED' then raise_application_error(-20096,'Identical retry was not recovered.'); end if;
  select 'nfe/'||to_char(data_emissao at time zone 'UTC','YYYY/MM')||'/'||chave_nfe||'.xml' into l_key2 from poc_nfe_document where nfe_id=l_nfe2;
  l_uri2 := 'https://idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com/POC_RT/'||l_key2;
  insert into nfe_migration_item(batch_id,nfe_id,status,object_key,object_uri) values(l_batch,l_nfe2,'QUEUED',l_key2,l_uri2) returning control_id into l_item2;
  dbms_lob.createtemporary(l_blob,true,dbms_lob.call); dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);
  dbms_cloud.put_object('NFE_OBJECT_STORAGE_S3_CRED',l_uri2,l_blob); dbms_lob.freetemporary(l_blob); commit;
  pkg_nfe_worker.upload_item(l_item2); commit;
  select status into l_status from nfe_migration_item where control_id=l_item2;
  if l_status <> 'EXCEPTION' then raise_application_error(-20097,'Divergent object was not blocked.'); end if;
  commit;
  dbms_output.put_line('PASS: identical retry reused its deterministic key; divergent object was blocked without overwrite.');
exception when others then if dbms_lob.istemporary(l_blob)=1 then dbms_lob.freetemporary(l_blob); end if; rollback; raise;
end;
/
