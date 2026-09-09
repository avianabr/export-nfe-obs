-- Run as NFE_OWNER after 29_create_nfe_reconciliation_package.sql.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
 l_n1 number;l_n2 number;l_bok number;l_bbad number;l_ok boolean;l_bad boolean;l_s varchar2(30);
 procedure batch_item(p_batch out number,p_nfe number,p_status varchar2) is l_k varchar2(1024); begin
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,selection_chunk_size,criteria_json,created_by) values('REC-'||substr(rawtohex(sys_guid()),1,20),'CREATED',systimestamp,1,1,'{"purpose":"reconciliation test"}',user) returning batch_id into p_batch;
  update nfe_migration_batch set status='SELECTING' where batch_id=p_batch; update nfe_migration_batch set status='PROCESSING' where batch_id=p_batch;
  select 'test/reconciliation/'||nfe_id||'.xml' into l_k from poc_nfe_document where nfe_id=p_nfe;
  insert into nfe_migration_item(batch_id,nfe_id,status,object_key,object_uri,source_size_bytes,object_size_bytes,source_sha256,object_sha256)
  values(p_batch,p_nfe,'QUEUED',l_k,'https://example.invalid/'||l_k,10,10,rpad('A',64,'A'),rpad('A',64,'A'));
  update nfe_migration_item set status='UPLOADING' where batch_id=p_batch; update nfe_migration_item set status='UPLOADED' where batch_id=p_batch; update nfe_migration_item set status='VERIFYING' where batch_id=p_batch;
  if p_status='VERIFIED' then update nfe_migration_item set status='VERIFIED' where batch_id=p_batch; else update nfe_migration_item set status='EXCEPTION' where batch_id=p_batch; end if;
 end;
begin
 select nfe_id into l_n1 from poc_nfe_document d where not exists(select 1 from nfe_migration_item i where i.nfe_id=d.nfe_id) and rownum=1;
 select nfe_id into l_n2 from poc_nfe_document d where d.nfe_id<>l_n1 and not exists(select 1 from nfe_migration_item i where i.nfe_id=d.nfe_id) and rownum=1;
 batch_item(l_bok,l_n1,'VERIFIED'); batch_item(l_bbad,l_n2,'EXCEPTION');
 pkg_nfe_reconciliation.reconcile_batch(l_bok,l_ok); pkg_nfe_reconciliation.reconcile_batch(l_bbad,l_bad);
 select status into l_s from nfe_migration_batch where batch_id=l_bok; if not l_ok or l_s<>'READY_FOR_APPROVAL' or l_bad then raise_application_error(-20130,'Reconciliation gate failed.'); end if;
 rollback; dbms_output.put_line('PASS: complete batch reaches READY_FOR_APPROVAL; incomplete batch is blocked.');
exception when others then rollback; raise; end;
/
