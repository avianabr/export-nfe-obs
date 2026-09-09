-- Run as NFE_OWNER after 33_create_nfe_purge_admin_package.sql.
-- Uses rollback so it leaves no test batch or source-XML mutation behind.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_batch number; l_nfe number; l_item number; l_purged pls_integer; l_status varchar2(30);
  l_rejected boolean := false;
begin
  select nfe_id into l_nfe from poc_nfe_document d
   where d.xml_clob is not null and not exists (select 1 from nfe_migration_item i where i.nfe_id=d.nfe_id) and rownum=1;
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,selection_chunk_size,criteria_json,created_by)
  values('PURGE-'||substr(rawtohex(sys_guid()),1,20),'CREATED',systimestamp,1,1,'{"purpose":"purge test"}',user)
  returning batch_id into l_batch;
  begin pkg_nfe_purge_admin.approve_batch(l_batch,'test','evidence://test');
  exception when others then if sqlcode=-20142 or sqlcode=-20141 then l_rejected:=true; else raise; end if; end;
  if not l_rejected then raise_application_error(-20150,'Unreconciled batch approval was not rejected.'); end if;
  update nfe_migration_batch set status='SELECTING' where batch_id=l_batch;
  update nfe_migration_batch set status='PROCESSING' where batch_id=l_batch;
  insert into nfe_migration_item(batch_id,nfe_id,status,object_key,object_uri,source_size_bytes,object_size_bytes,source_sha256,object_sha256)
  values(l_batch,l_nfe,'QUEUED','test/purge/'||l_nfe||'.xml','https://example.invalid/test/'||l_nfe,1,1,rpad('A',64,'A'),rpad('A',64,'A')) returning control_id into l_item;
  update nfe_migration_item set status='UPLOADING' where control_id=l_item; update nfe_migration_item set status='UPLOADED' where control_id=l_item;
  update nfe_migration_item set status='VERIFYING' where control_id=l_item; update nfe_migration_item set status='VERIFIED' where control_id=l_item;
  insert into nfe_reconciliation_run(batch_id,status,total_count,verified_count,source_bytes,object_bytes,completed_at,executed_by)
  values(l_batch,'PASSED',1,1,1,1,systimestamp,user);
  update nfe_migration_batch set status='RECONCILING' where batch_id=l_batch;
  update nfe_migration_batch set status='READY_FOR_APPROVAL',reconciliation_status='PASSED' where batch_id=l_batch;
  pkg_nfe_purge_admin.approve_batch(l_batch,'approved test purge','evidence://test');
  pkg_nfe_purge_admin.purge_batch_chunk(l_batch,1,l_purged);
  select status into l_status from nfe_migration_item where control_id=l_item;
  if l_purged<>1 or l_status<>'PURGED' then raise_application_error(-20151,'Approved purge did not change only the verified item.'); end if;
  rollback; dbms_output.put_line('PASS: approval gate and manual verified-item purge validated.');
exception when others then rollback; raise; end;
/
