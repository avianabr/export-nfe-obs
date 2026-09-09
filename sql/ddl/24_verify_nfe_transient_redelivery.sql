-- Run as NFE_OWNER after rerunning 19_create_nfe_worker_package.sql.
-- Uses a dedicated message and confirms rollback preserves TEQ redelivery.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_marker varchar2(20) := substr(rawtohex(sys_guid()),1,20);
  l_batch number; l_nfe number; l_item number; l_key varchar2(1024); l_uri varchar2(2000); l_nfe_key varchar2(44);
  l_enq dbms_aq.enqueue_options_t; l_props dbms_aq.message_properties_t; l_msgid raw(16); l_payload raw(2000);
  l_count number; l_status varchar2(30); l_deq dbms_aq.dequeue_options_t;
  l_cleanup_props dbms_aq.message_properties_t; l_cleanup_payload raw(2000); l_cleanup_msgid raw(16);
begin
  l_nfe_key:='000020260904'||lpad(to_char(systimestamp,'YYYYMMDDHH24MISSFF3'),32,'0');
  insert into poc_nfe_document(chave_nfe,data_emissao,situacao,xml_clob)
  values(l_nfe_key,systimestamp-interval '2' day,'AUTORIZADA',to_clob('<NFe>transient retry test</NFe>')) returning nfe_id into l_nfe;
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,selection_chunk_size,criteria_json,created_by)
  values('RETRY-'||l_marker,'CREATED',systimestamp-interval '1' day,1,1,'{"purpose":"transient retry"}',user) returning batch_id into l_batch;
  update nfe_migration_batch set status='SELECTING' where batch_id=l_batch;
  select 'nfe/'||to_char(data_emissao at time zone 'UTC','YYYY/MM')||'/'||chave_nfe||'.xml' into l_key from poc_nfe_document where nfe_id=l_nfe;
  l_uri := 'https://idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com/POC_RT/'||l_key;
  insert into nfe_migration_item(batch_id,nfe_id,status,object_key,object_uri) values(l_batch,l_nfe,'QUEUED',l_key,l_uri) returning control_id into l_item;
  l_enq.visibility:=dbms_aq.on_commit; l_props.correlation:='RETRY-'||l_marker; l_props.exception_queue:='NFE_MIGRATION_EX_Q';
  l_payload:=utl_i18n.string_to_raw('{"eventType":"NFE_MIGRATION","version":1,"controlId":'||l_item||',"nfeId":'||l_nfe||',"batchId":'||l_batch||'}','AL32UTF8');
  dbms_aq.enqueue('NFE_MIGRATION_Q',l_enq,l_props,l_payload,l_msgid); commit;
  begin pkg_nfe_worker.process_one(true,'RETRY-'||l_marker); exception when others then if sqlcode <> -20066 then raise; end if; end;
  select status into l_status from nfe_migration_item where control_id=l_item;
  select count(*) into l_count from aq$nfe_migration_q where corr_id='RETRY-'||l_marker;
  dbms_output.put_line('Observed item status='||l_status||', correlated messages='||l_count||'.');
  if l_status <> 'QUEUED' or l_count <> 1 then raise_application_error(-20098,'Transient failure acknowledged or persisted success.'); end if;
  l_deq.visibility:=dbms_aq.on_commit; l_deq.dequeue_mode:=dbms_aq.remove;
  l_deq.wait:=dbms_aq.no_wait; l_deq.navigation:=dbms_aq.first_message; l_deq.msgid:=l_msgid;
  dbms_aq.dequeue('NFE_MIGRATION_Q',l_deq,l_cleanup_props,l_cleanup_payload,l_cleanup_msgid);
  commit;
  delete from nfe_migration_item where control_id=l_item;
  delete from nfe_migration_batch where batch_id=l_batch;
  delete from poc_nfe_document where nfe_id=l_nfe;
  commit;
  dbms_output.put_line('PASS: transient failure rolls back item state and preserves TEQ redelivery.');
exception when others then rollback; raise;
end;
/
