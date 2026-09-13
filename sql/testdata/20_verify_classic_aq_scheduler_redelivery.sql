-- Controlled Scheduler redelivery test. Run as NFE_OWNER only with
-- POC_NFE_OCI_10K as the isolated configured source. The invalid integrity
-- mode fails before any Object Storage request.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited verify off

declare
  l_source_table nfe_deploy_source_config.source_table%type;
  l_batch_id     nfe_migration_batch.batch_id%type;
  l_control_id   nfe_migration_item.control_id%type;
  l_nfe_id       poc_nfe_oci_10k.nfe_id%type;
  l_msgid        raw(16);
  l_key          varchar2(44) := lpad(to_char(abs(dbms_random.random)),44,'0');
  l_correlation  varchar2(100);
  l_status       nfe_migration_item.status%type;
  l_state_count  number;
  l_retry_count  number;
  l_failed_jobs  number;
  l_jobs         number;
  l_original_limit number;
  l_started_at   timestamp with time zone;
  l_deq          dbms_aq.dequeue_options_t;
  l_props        dbms_aq.message_properties_t;
  l_payload      raw(2000);
  l_dequeued     raw(16);
begin
  select source_table into l_source_table
    from nfe_deploy_source_config where config_id=1;
  if l_source_table <> 'POC_NFE_OCI_10K' then
    raise_application_error(-20984,'Test requires POC_NFE_OCI_10K as the configured isolated source.');
  end if;
  select worker_limit into l_original_limit
    from nfe_classic_aq_config where config_id=1;

  update nfe_classic_aq_config set worker_limit=2,updated_by=user,updated_at=systimestamp where config_id=1;
  insert into poc_nfe_oci_10k(chave_nfe,data_emissao,situacao,xml_clob)
  values(l_key,systimestamp,'AUTORIZADA',
    '<NFe><infNFe Id="NFe'||l_key||'"><test>scheduler invalid mode</test></infNFe></NFe>')
  returning nfe_id into l_nfe_id;
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,created_by)
  values('SCHEDULER-REDELIVERY-'||to_char(systimestamp,'YYMMDDHH24MISSFF3'),
         'CREATED',systimestamp+interval '1' day,1,user)
  returning batch_id into l_batch_id;

  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  pkg_nfe_classic_aq_runtime.admit_one(l_batch_id,'AUTORIZADA',l_control_id);
  update nfe_migration_item set integrity_mode='INVALID_FOR_TEST' where control_id=l_control_id;
  commit;

  l_correlation:='NFE-CLASSIC-'||l_control_id;
  l_started_at:=systimestamp;
  pkg_nfe_classic_aq_runtime.start_batch_workers(l_batch_id);
  for n in 1..30 loop
    select count(*),nvl(max(retry_count),0) into l_state_count,l_retry_count
      from aq$nfe_classic_aq_qt
     where corr_id=l_correlation and msg_state in ('READY','WAIT');
    select count(*) into l_failed_jobs
      from user_scheduler_job_run_details
     where job_name like 'NFE_AQ_B'||to_char(l_batch_id)||'_W%'
       and log_date>=l_started_at and status='FAILED';
    exit when l_state_count=1 and l_retry_count>=1 and l_failed_jobs>=1;
    dbms_session.sleep(1);
  end loop;
  select status,aq_msgid into l_status,l_msgid
    from nfe_migration_item where control_id=l_control_id;
  select count(*) into l_jobs from user_scheduler_jobs
   where job_name like 'NFE_AQ_B'||to_char(l_batch_id)||'_W%';
  if l_status<>'QUEUED' or l_state_count<>1 or l_retry_count<1 or l_failed_jobs<1 or l_jobs<>2 then
    raise_application_error(-20985,'Scheduler rollback did not preserve a queued retryable item and isolated worker failure.');
  end if;

  pkg_nfe_classic_aq_runtime.stop_batch_workers(l_batch_id);
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  commit;
  l_deq.visibility:=dbms_aq.on_commit;
  l_deq.dequeue_mode:=dbms_aq.remove;
  l_deq.wait:=dbms_aq.no_wait;
  l_deq.msgid:=l_msgid;
  dbms_aq.dequeue('NFE_CLASSIC_AQ_Q',l_deq,l_props,l_payload,l_dequeued);
  delete from nfe_migration_item where control_id=l_control_id;
  delete from nfe_migration_batch where batch_id=l_batch_id;
  delete from poc_nfe_oci_10k where nfe_id=l_nfe_id;
  update nfe_classic_aq_config set worker_limit=l_original_limit,updated_by=user,updated_at=systimestamp where config_id=1;
  commit;
  dbms_output.put_line('PASS: failed Scheduler worker preserved a queued redelivery message; peer worker remained isolated and cleanup removed both jobs.');
exception
  when others then
    begin
      if l_batch_id is not null then pkg_nfe_classic_aq_runtime.stop_batch_workers(l_batch_id); end if;
      pkg_nfe_classic_aq_runtime.set_enabled('N');
      if l_msgid is not null then
        l_deq.visibility:=dbms_aq.on_commit;l_deq.dequeue_mode:=dbms_aq.remove;l_deq.wait:=dbms_aq.no_wait;l_deq.msgid:=l_msgid;
        begin dbms_aq.dequeue('NFE_CLASSIC_AQ_Q',l_deq,l_props,l_payload,l_dequeued); exception when others then null; end;
      end if;
      if l_control_id is not null then delete from nfe_migration_item where control_id=l_control_id; end if;
      if l_batch_id is not null then delete from nfe_migration_batch where batch_id=l_batch_id; end if;
      if l_nfe_id is not null then delete from poc_nfe_oci_10k where nfe_id=l_nfe_id; end if;
      if l_original_limit is not null then update nfe_classic_aq_config set worker_limit=l_original_limit,updated_by=user,updated_at=systimestamp where config_id=1; end if;
      commit;
    exception when others then rollback; end;
    raise;
end;
/
