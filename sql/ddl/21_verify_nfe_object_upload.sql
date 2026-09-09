-- Run as NFE_OWNER after rerunning 19_create_nfe_worker_package.sql.
-- Uploads the one already admitted synthetic item from batch 2 and commits it;
-- this is the durable test input for the subsequent download/hash verification.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_control_id   number;
  l_status       varchar2(30);
  l_object_key   varchar2(1024);
  l_object_uri   varchar2(2000);
  l_source_bytes number;
  l_source_hash  varchar2(64);
  l_object_blob  blob;
begin
  select control_id into l_control_id
    from (
      select control_id
        from nfe_migration_item
       where batch_id = 2 and status = 'QUEUED'
       order by control_id
    )
   where rownum = 1;

  pkg_nfe_worker.upload_item(l_control_id);
  commit;

  select status, object_key, object_uri, source_size_bytes, source_sha256
    into l_status, l_object_key, l_object_uri, l_source_bytes, l_source_hash
    from nfe_migration_item
   where control_id = l_control_id;
  l_object_blob := dbms_cloud.get_object(
    credential_name => 'NFE_OBJECT_STORAGE_S3_CRED', object_uri => l_object_uri);

  if l_status <> 'UPLOADED' or l_source_bytes <= 0
     or not regexp_like(l_source_hash, '^[0-9A-F]{64}$')
     or dbms_lob.getlength(l_object_blob) <> l_source_bytes
     or not regexp_like(l_object_key, '^nfe/[0-9]{4}/[0-9]{2}/[0-9]{44}\.xml$') then
    raise_application_error(-20093,
      'Upload did not persist the expected deterministic object evidence.');
  end if;
  if dbms_lob.istemporary(l_object_blob) = 1 then
    dbms_lob.freetemporary(l_object_blob);
  end if;
  dbms_output.put_line(
    'PASS: uploaded item ' || l_control_id || ' to its deterministic Object Storage key.');
exception
  when others then
    if dbms_lob.istemporary(l_object_blob) = 1 then
      dbms_lob.freetemporary(l_object_blob);
    end if;
    rollback;
    raise;
end;
/
