-- Mixed Scheduler-worker test for the configured isolated OCI POC source.
-- One item is invalid before upload; its peer must still verify normally.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited verify off

declare
  l_gate char(1);l_original_limit number;l_source_table varchar2(128);
  l_provider varchar2(20);l_mode varchar2(32);l_credential varchar2(128);
  l_batch_id number;l_invalid_control number;l_valid_control number;
  l_invalid_msgid raw(16);l_invalid_status varchar2(20);l_valid_status varchar2(20);
  l_retryable number;l_failed_jobs number;l_succeeded_jobs number;l_started_at timestamp with time zone;
  l_key varchar2(44);l_response dbms_cloud_types.resp;l_valid_uri varchar2(2000);
  l_deq dbms_aq.dequeue_options_t;l_props dbms_aq.message_properties_t;l_payload raw(2000);l_dequeued raw(16);
begin
  select classic_aq_enabled,worker_limit into l_gate,l_original_limit from nfe_classic_aq_config where config_id=1;
  if l_gate<>'N' then raise_application_error(-20991,'Mixed worker test requires Classic AQ disabled initially.'); end if;
  select source_table into l_source_table from nfe_deploy_source_config where config_id=1;
  select storage_provider,integrity_mode,credential_name into l_provider,l_mode,l_credential from nfe_deploy_storage_config where config_id=1;
  if l_source_table<>'POC_NFE_OCI_10K' or l_provider<>'OCI_NATIVE' or l_mode<>'OCI_MD5_HEAD' then
    raise_application_error(-20992,'Mixed worker test requires the isolated POC_NFE_OCI_10K OCI HEAD configuration.');
  end if;
  update nfe_classic_aq_config set worker_limit=2,updated_by=user,updated_at=systimestamp where config_id=1;
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,created_by)
  values('SCHEDULER-MIXED-'||to_char(systimestamp,'YYMMDDHH24MISSFF3'),'CREATED',systimestamp+interval '5' minute,2,user)
  returning batch_id into l_batch_id;
  for n in 1..2 loop
    l_key:=rpad('MIXED-'||to_char(n)||'-'||to_char(systimestamp,'YYYYMMDDHH24MISSFF3'),44,'X');
    insert into poc_nfe_oci_10k(chave_nfe,data_emissao,situacao,xml_clob)
    values(l_key,systimestamp,'AUTORIZADA','<NFe><infNFe Id="NFe'||l_key||'"><test>mixed scheduler failure</test></infNFe></NFe>');
  end loop;
  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  pkg_nfe_classic_aq_runtime.admit_one(l_batch_id,'AUTORIZADA',l_invalid_control);
  pkg_nfe_classic_aq_runtime.admit_one(l_batch_id,'AUTORIZADA',l_valid_control);
  update nfe_migration_item set integrity_mode='INVALID_FOR_TEST' where control_id=l_invalid_control;
  commit;
  l_started_at:=systimestamp;
  pkg_nfe_classic_aq_runtime.start_batch_workers(l_batch_id);
  for n in 1..60 loop
    select status,aq_msgid into l_invalid_status,l_invalid_msgid from nfe_migration_item where control_id=l_invalid_control;
    select status,object_uri into l_valid_status,l_valid_uri from nfe_migration_item where control_id=l_valid_control;
    select count(*) into l_retryable from aq$nfe_classic_aq_qt
     where corr_id='NFE-CLASSIC-'||to_char(l_invalid_control) and msg_state in ('READY','WAIT') and retry_count>=1;
    select count(case when status='FAILED' then 1 end),count(case when status='SUCCEEDED' then 1 end)
      into l_failed_jobs,l_succeeded_jobs from user_scheduler_job_run_details
     where job_name like 'NFE_AQ_B'||to_char(l_batch_id)||'_W%' and log_date>=l_started_at;
    exit when l_invalid_status='QUEUED' and l_retryable=1 and l_valid_status='VERIFIED'
              and l_failed_jobs>=1 and l_succeeded_jobs>=1;
    dbms_session.sleep(1);
  end loop;
  if l_invalid_status<>'QUEUED' or l_retryable<>1 or l_valid_status<>'VERIFIED' or l_failed_jobs<1 or l_succeeded_jobs<1 then
    raise_application_error(-20993,'Mixed worker failure did not preserve redelivery and peer completion.');
  end if;
  pkg_nfe_classic_aq_runtime.stop_batch_workers(l_batch_id);
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  l_response:=dbms_cloud.send_request(credential_name=>l_credential,uri=>l_valid_uri,method=>dbms_cloud.method_delete);
  if dbms_cloud.get_response_status_code(l_response) not in (200,204,404) then raise_application_error(-20994,'Could not remove the mixed-test OCI object.'); end if;
  l_deq.visibility:=dbms_aq.on_commit;l_deq.dequeue_mode:=dbms_aq.remove;l_deq.wait:=dbms_aq.no_wait;l_deq.msgid:=l_invalid_msgid;
  dbms_aq.dequeue('NFE_CLASSIC_AQ_Q',l_deq,l_props,l_payload,l_dequeued);
  delete from poc_nfe_oci_10k where nfe_id in (select nfe_id from nfe_migration_item where batch_id=l_batch_id);
  delete from nfe_migration_item where batch_id=l_batch_id;
  delete from nfe_migration_batch where batch_id=l_batch_id;
  update nfe_classic_aq_config set worker_limit=l_original_limit,updated_by=user,updated_at=systimestamp where config_id=1;
  commit;
  dbms_output.put_line('PASS: failed worker kept retryable item queued while its peer verified independently; test object and jobs were removed.');
exception when others then
  begin
    pkg_nfe_classic_aq_runtime.set_enabled('N');
    if l_batch_id is not null then pkg_nfe_classic_aq_runtime.stop_batch_workers(l_batch_id); end if;
    if l_original_limit is not null then update nfe_classic_aq_config set worker_limit=l_original_limit,updated_by=user,updated_at=systimestamp where config_id=1; end if;
    commit;
  exception when others then rollback; end;
  raise;
end;
/
