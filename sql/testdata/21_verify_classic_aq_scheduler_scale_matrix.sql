-- End-to-end Scheduler matrix for the configured isolated POC source. It runs
-- four ten-item batches (1, 2, 5 and 10 workers) and removes only its own
-- source rows, control rows, Scheduler jobs and OCI objects after each pass.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited verify off

declare
  c_items constant pls_integer:=10;
  l_gate char(1);l_original_limit number;l_source_table varchar2(128);
  l_provider varchar2(20);l_mode varchar2(32);l_credential varchar2(128);
  l_batch_id number;l_control_id number;l_verified number;l_other number;
  l_failed_jobs number;l_started_at timestamp with time zone;l_passed boolean;
  l_key varchar2(44);l_response dbms_cloud_types.resp;

  procedure cleanup_verified_batch(p_batch_id number) is
  begin
    pkg_nfe_classic_aq_runtime.stop_batch_workers(p_batch_id);
    for r in (select object_uri from nfe_migration_item where batch_id=p_batch_id and status='VERIFIED') loop
      l_response:=dbms_cloud.send_request(credential_name=>l_credential,uri=>r.object_uri,method=>dbms_cloud.method_delete);
      if dbms_cloud.get_response_status_code(l_response) not in (200,204,404) then
        raise_application_error(-20990,'Could not remove a Scheduler scale-test OCI object.');
      end if;
    end loop;
    delete from poc_nfe_oci_10k where nfe_id in (select nfe_id from nfe_migration_item where batch_id=p_batch_id);
    delete from nfe_migration_item where batch_id=p_batch_id;
    delete from nfe_migration_batch where batch_id=p_batch_id;
    commit;
  end;
begin
  select classic_aq_enabled,worker_limit into l_gate,l_original_limit from nfe_classic_aq_config where config_id=1;
  if l_gate<>'N' then raise_application_error(-20986,'Scheduler scale matrix requires Classic AQ disabled initially.'); end if;
  select source_table into l_source_table from nfe_deploy_source_config where config_id=1;
  select storage_provider,integrity_mode,credential_name into l_provider,l_mode,l_credential from nfe_deploy_storage_config where config_id=1;
  if l_source_table<>'POC_NFE_OCI_10K' or l_provider<>'OCI_NATIVE' or l_mode<>'OCI_MD5_HEAD' then
    raise_application_error(-20987,'Scheduler scale matrix requires the isolated POC_NFE_OCI_10K OCI HEAD configuration.');
  end if;

  for w in (select column_value as workers from table(sys.odcinumberlist(1,2,5,10))) loop
    update nfe_classic_aq_config set worker_limit=w.workers,updated_by=user,updated_at=systimestamp where config_id=1;
    insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,created_by)
    values('SCHEDULER-SCALE-'||to_char(systimestamp,'YYYYMMDDHH24MISSFF3')||'-'||to_char(w.workers),
           'CREATED',systimestamp+interval '5' minute,c_items,user)
    returning batch_id into l_batch_id;
    for n in 1..c_items loop
      l_key:=rpad('SCALE-'||to_char(w.workers)||'-'||to_char(n)||'-'||to_char(systimestamp,'YYYYMMDDHH24MISSFF3'),44,'X');
      insert into poc_nfe_oci_10k(chave_nfe,data_emissao,situacao,xml_clob)
      values(l_key,systimestamp,'AUTORIZADA','<NFe><infNFe Id="NFe'||l_key||'"><test>scheduler scale</test></infNFe></NFe>');
    end loop;
    pkg_nfe_classic_aq_runtime.set_enabled('Y');
    for n in 1..c_items loop pkg_nfe_classic_aq_runtime.admit_one(l_batch_id,'AUTORIZADA',l_control_id); end loop;
    commit;
    l_started_at:=systimestamp;
    pkg_nfe_classic_aq_runtime.start_batch_workers(l_batch_id);
    for n in 1..180 loop
      select count(case when status='VERIFIED' then 1 end),count(case when status<>'VERIFIED' then 1 end)
        into l_verified,l_other from nfe_migration_item where batch_id=l_batch_id;
      select count(*) into l_failed_jobs from user_scheduler_job_run_details
       where job_name like 'NFE_AQ_B'||to_char(l_batch_id)||'_W%'
         and log_date>=l_started_at and status='FAILED';
      exit when l_verified=c_items or l_failed_jobs>0;
      dbms_session.sleep(1);
    end loop;
    if l_verified<>c_items or l_other<>0 or l_failed_jobs<>0 then
      raise_application_error(-20988,'Scheduler scale batch failed for workers='||w.workers||'.');
    end if;
    pkg_nfe_classic_aq_runtime.reconcile_batch(l_batch_id,l_passed);
    if not l_passed then raise_application_error(-20989,'Scheduler scale batch integrity reconciliation failed.'); end if;
    dbms_output.put_line('PASS: workers='||w.workers||', verified='||l_verified||', elapsed_seconds='||
      round((cast(systimestamp as date)-cast(l_started_at as date))*86400,2));
    cleanup_verified_batch(l_batch_id);
    l_batch_id:=null;
    pkg_nfe_classic_aq_runtime.set_enabled('N');
    commit;
  end loop;
  update nfe_classic_aq_config set worker_limit=l_original_limit,updated_by=user,updated_at=systimestamp where config_id=1;
  commit;
  dbms_output.put_line('PASS: Scheduler scale matrix completed; all test objects and rows were removed.');
exception when others then
  begin
    pkg_nfe_classic_aq_runtime.set_enabled('N');
    if l_batch_id is not null then pkg_nfe_classic_aq_runtime.stop_batch_workers(l_batch_id); end if;
    update nfe_classic_aq_config set worker_limit=l_original_limit,updated_by=user,updated_at=systimestamp where config_id=1;
    commit;
  exception when others then rollback; end;
  raise;
end;
/
