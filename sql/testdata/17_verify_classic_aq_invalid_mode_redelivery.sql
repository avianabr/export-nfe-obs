-- Controlled redelivery test. Run as NFE_OWNER only with POC_NFE_OCI_10K
-- configured as the isolated source. It makes no Object Storage request.
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
  l_mode         nfe_migration_item.integrity_mode%type;
  l_ready_count  number;
  l_retry_count  number;
  l_state_summary varchar2(4000);
  l_deq          dbms_aq.dequeue_options_t;
  l_props        dbms_aq.message_properties_t;
  l_payload      raw(2000);
  l_dequeued     raw(16);
begin
  select source_table into l_source_table
    from nfe_deploy_source_config where config_id=1;
  if l_source_table <> 'POC_NFE_OCI_10K' then
    raise_application_error(-20970,
      'Test requires POC_NFE_OCI_10K as the configured isolated source.');
  end if;

  insert into poc_nfe_oci_10k(chave_nfe,data_emissao,situacao,xml_clob)
  values(l_key,systimestamp,'AUTORIZADA',
    '<NFe><infNFe Id="NFe'||l_key||'"><test>invalid mode</test></infNFe></NFe>')
  returning nfe_id into l_nfe_id;
  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,created_by)
  values('INVALID-MODE-REDELIVERY-'||to_char(systimestamp,'YYMMDDHH24MISSFF3'),
         'CREATED',systimestamp+interval '1' day,1,user)
  returning batch_id into l_batch_id;

  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  pkg_nfe_classic_aq_runtime.admit_one(l_batch_id,'AUTORIZADA',l_control_id);
  update nfe_migration_item
     set integrity_mode='INVALID_FOR_TEST'
   where control_id=l_control_id;
  commit;
  select integrity_mode into l_mode
    from nfe_migration_item where control_id=l_control_id;
  if l_mode <> 'INVALID_FOR_TEST' then
    raise_application_error(-20973,
      'Test setup did not persist INVALID_FOR_TEST; found ' || nvl(l_mode,'<NULL>'));
  end if;

  l_correlation := 'NFE-CLASSIC-'||l_control_id;
  begin
    pkg_nfe_classic_aq_runtime.process_one(l_correlation);
    raise_application_error(-20971,'Invalid integrity mode unexpectedly succeeded.');
  exception
    when others then
      if sqlcode=-20971 then raise; end if;
      if sqlcode<>-20842 then raise; end if;
  end;

  select status,aq_msgid into l_status,l_msgid
    from nfe_migration_item where control_id=l_control_id;
  select count(*),max(retry_count) into l_ready_count,l_retry_count
    from aq$nfe_classic_aq_qt
   where corr_id=l_correlation and msg_state in ('READY','WAIT');
  select nvl(listagg(msg_state,',') within group (order by msg_state),'<NONE>')
    into l_state_summary
    from aq$nfe_classic_aq_qt
   where corr_id=l_correlation;
  if l_status<>'QUEUED' or l_ready_count<>1 then
    raise_application_error(-20972,
      'Rollback state: item_status='||nvl(l_status,'<NULL>')||
      ', retry_pending_messages='||l_ready_count||
      ', retry_count='||nvl(to_char(l_retry_count),'<NULL>')||
      ', matching_message_states='||l_state_summary);
  end if;

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
  commit;
  dbms_output.put_line(
    'PASS: invalid mode rolled back; item stayed QUEUED and message is pending redelivery (states='||l_state_summary||', retry_count='||nvl(l_retry_count,0)||').');
exception
  when others then
    rollback;
    begin
      pkg_nfe_classic_aq_runtime.set_enabled('N');
      commit;
    exception when others then rollback; end;
    raise;
end;
/
