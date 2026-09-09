-- Run as NFE_OWNER after 25_create_nfe_exception_monitor.sql.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_marker varchar2(16):=substr(rawtohex(sys_guid()),1,16); l_batch number; l_nfe number; l_item number;
  l_key varchar2(1024); l_uri varchar2(2000); l_enq dbms_aq.enqueue_options_t; l_deq dbms_aq.dequeue_options_t;
  l_prop dbms_aq.message_properties_t; l_payload raw(2000); l_msgid raw(16); l_recv raw(2000); l_done pls_integer; l_status varchar2(30); l_audit number;
begin
 select nfe_id into l_nfe from poc_nfe_document d where not exists(select 1 from nfe_migration_item i where i.nfe_id=d.nfe_id) and rownum=1;
 insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,selection_chunk_size,criteria_json,created_by) values('EX-'||l_marker,'CREATED',systimestamp,1,1,'{"purpose":"exception"}',user) returning batch_id into l_batch;
 update nfe_migration_batch set status='SELECTING' where batch_id=l_batch;
 select 'nfe/'||to_char(data_emissao at time zone 'UTC','YYYY/MM')||'/'||chave_nfe||'.xml' into l_key from poc_nfe_document where nfe_id=l_nfe;
 l_uri:='https://idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com/POC_RT/'||l_key;
 insert into nfe_migration_item(batch_id,nfe_id,status,object_key,object_uri) values(l_batch,l_nfe,'QUEUED',l_key,l_uri) returning control_id into l_item;
 l_enq.visibility:=dbms_aq.on_commit; l_prop.correlation:='EX-'||l_marker; l_prop.exception_queue:='NFE_MIGRATION_EX_Q'; l_payload:=utl_i18n.string_to_raw('{"eventType":"NFE_MIGRATION","version":1,"controlId":'||l_item||',"nfeId":'||l_nfe||',"batchId":'||l_batch||'}','AL32UTF8'); dbms_aq.enqueue('NFE_MIGRATION_Q',l_enq,l_prop,l_payload,l_msgid); commit;
 l_deq.visibility:=dbms_aq.on_commit;l_deq.dequeue_mode:=dbms_aq.remove;l_deq.wait:=dbms_aq.no_wait;l_deq.navigation:=dbms_aq.first_message;l_deq.correlation:='EX-'||l_marker;
 for x in 1..3 loop dbms_aq.dequeue('NFE_MIGRATION_Q',l_deq,l_prop,l_recv,l_msgid); rollback; end loop;
 pkg_nfe_exception_monitor.drain_one(l_done,'EX-'||l_marker);
 select status into l_status from nfe_migration_item where control_id=l_item; select count(*) into l_audit from nfe_migration_audit where control_id=l_item and event_type='EXCEPTION_ALERT' and correlation_id='EX-'||l_marker;
 if l_done<>1 or l_status<>'EXCEPTION' or l_audit<>1 then raise_application_error(-20110,'Exception monitor did not preserve evidence.'); end if;
 dbms_output.put_line('PASS: exception queue monitor preserved correlation and marked the item EXCEPTION.');
exception when others then rollback; raise; end;
/
