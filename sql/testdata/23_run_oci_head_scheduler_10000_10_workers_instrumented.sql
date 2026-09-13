-- Instrumented end-to-end benchmark. Run only as NFE_OWNER in the isolated PDB.
-- It creates a new 10k source, a unique OCI prefix and preserves the resulting
-- batch/objects as evidence. The previous configuration is restored on exit.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited verify off

declare
  c_document_count constant pls_integer:=10000;
  c_worker_count constant pls_integer:=10;
  c_source_table constant varchar2(128):='POC_NFE_OCI_10K_SCHED_2';
  c_wait_seconds constant pls_integer:=7200;
  l_original_gate char(1);l_original_worker_limit number;
  l_endpoint varchar2(1000);l_bucket varchar2(255);l_original_prefix varchar2(512);l_credential varchar2(128);
  l_source_owner varchar2(128);l_original_source_table varchar2(128);l_source_clob varchar2(128);l_source_id varchar2(128);l_source_key varchar2(128);l_source_date varchar2(128);l_source_status varchar2(128);
  l_max_inflight number;l_provider varchar2(20);l_namespace varchar2(128);l_mode varchar2(32);
  l_run_prefix varchar2(512);l_batch_id number;l_control_id number;l_verified number;l_other number;l_failed_jobs number;l_passed boolean;
  l_stage_started timestamp with time zone;l_total_started timestamp with time zone:=systimestamp;
  l_seed_seconds number;l_configure_seconds number;l_admit_seconds number;l_launch_seconds number;l_process_seconds number;l_reconcile_seconds number;l_restore_seconds number;
  l_last_reported number:=0;l_worker_first_start timestamp with time zone;l_worker_last_finish timestamp with time zone;

  function elapsed_seconds(p_started timestamp with time zone) return number is
  begin return round((cast(systimestamp as date)-cast(p_started as date))*86400,2); end;

  procedure restore_configuration is
  begin
    pkg_nfe_deploy_config.set_environment(
      p_s3_endpoint=>l_endpoint,p_bucket_name=>l_bucket,p_object_prefix=>l_original_prefix,p_credential_name=>l_credential,
      p_source_owner=>l_source_owner,p_source_table=>l_original_source_table,p_source_clob_column=>l_source_clob,
      p_source_id_column=>l_source_id,p_source_key_column=>l_source_key,p_source_date_column=>l_source_date,
      p_source_status_column=>l_source_status,p_max_inflight=>l_max_inflight,p_storage_provider=>l_provider,
      p_oci_namespace=>l_namespace,p_integrity_mode=>l_mode);
  end;
begin
  select q.classic_aq_enabled,q.worker_limit into l_original_gate,l_original_worker_limit from nfe_classic_aq_config q where q.config_id=1;
  if l_original_gate<>'N' then raise_application_error(-20995,'Benchmark requires Classic AQ disabled initially.'); end if;
  select s.s3_endpoint,s.bucket_name,s.object_prefix,s.credential_name,s.max_inflight,s.storage_provider,s.oci_namespace,s.integrity_mode,
         m.source_owner,m.source_table,m.source_clob_column,m.source_id_column,m.source_key_column,m.source_date_column,m.source_status_column
    into l_endpoint,l_bucket,l_original_prefix,l_credential,l_max_inflight,l_provider,l_namespace,l_mode,
         l_source_owner,l_original_source_table,l_source_clob,l_source_id,l_source_key,l_source_date,l_source_status
    from nfe_deploy_storage_config s join nfe_deploy_source_config m on m.config_id=s.config_id where s.config_id=1;
  if l_provider<>'OCI_NATIVE' or l_mode<>'OCI_MD5_HEAD' or l_max_inflight<c_document_count then
    raise_application_error(-20996,'Benchmark requires OCI_NATIVE / OCI_MD5_HEAD and MAX_INFLIGHT >= 10000.');
  end if;

  l_stage_started:=systimestamp;
  declare l_exists number;l_rows number; begin
    select count(*) into l_exists from user_tables where table_name=c_source_table;
    if l_exists=0 then
      execute immediate 'create table '||c_source_table||' (nfe_id number generated always as identity (start with 1000000) primary key,chave_nfe varchar2(44) not null unique,data_emissao timestamp with time zone not null,situacao varchar2(30) not null,xml_clob clob not null)';
    end if;
    execute immediate 'select count(*) from '||c_source_table into l_rows;
    if l_rows<>0 then raise_application_error(-20997,c_source_table||' must be empty before the benchmark.'); end if;
    execute immediate 'insert into '||c_source_table||'(chave_nfe,data_emissao,situacao,xml_clob) select ''8''||lpad(to_char(level),43,''0''),systimestamp-interval ''1'' day,''AUTORIZADA'',to_clob(''<NFe><infNFe Id="NFe'')||''8''||lpad(to_char(level),43,''0'')||to_clob(''"><x>instrumented scheduler benchmark</x></infNFe></NFe>'') from dual connect by level<='||c_document_count;
    commit;
  end;
  l_seed_seconds:=elapsed_seconds(l_stage_started);

  l_stage_started:=systimestamp;
  l_run_prefix:=trim(both '/' from l_original_prefix)||'/scheduler-10w-'||to_char(systimestamp,'YYYYMMDDHH24MISSFF3');
  pkg_nfe_deploy_config.set_environment(
    p_s3_endpoint=>l_endpoint,p_bucket_name=>l_bucket,p_object_prefix=>l_run_prefix,p_credential_name=>l_credential,
    p_source_owner=>user,p_source_table=>c_source_table,p_source_clob_column=>'XML_CLOB',p_source_id_column=>'NFE_ID',
    p_source_key_column=>'CHAVE_NFE',p_source_date_column=>'DATA_EMISSAO',p_source_status_column=>'SITUACAO',
    p_max_inflight=>l_max_inflight,p_storage_provider=>l_provider,p_oci_namespace=>l_namespace,p_integrity_mode=>l_mode);
  update nfe_classic_aq_config set worker_limit=c_worker_count,updated_by=user,updated_at=systimestamp where config_id=1;
  commit;
  l_configure_seconds:=elapsed_seconds(l_stage_started);

  insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,created_by)
  values('AQ-SCHED-INST-10K-10W-'||to_char(systimestamp,'YYYYMMDDHH24MISSFF3'),'CREATED',systimestamp+interval '5' minute,c_document_count,user)
  returning batch_id into l_batch_id;
  l_stage_started:=systimestamp;
  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  for n in 1..c_document_count loop
    pkg_nfe_classic_aq_runtime.admit_one(l_batch_id,'AUTORIZADA',l_control_id);
    if mod(n,1000)=0 then dbms_output.put_line('ADMISSION: items='||n||', elapsed_seconds='||elapsed_seconds(l_stage_started)); end if;
  end loop;
  commit;
  l_admit_seconds:=elapsed_seconds(l_stage_started);

  l_stage_started:=systimestamp;
  pkg_nfe_classic_aq_runtime.start_batch_workers(l_batch_id);
  l_launch_seconds:=elapsed_seconds(l_stage_started);

  l_stage_started:=systimestamp;
  loop
    select count(case when status='VERIFIED' then 1 end),count(case when status<>'VERIFIED' then 1 end)
      into l_verified,l_other from nfe_migration_item where batch_id=l_batch_id;
    if l_verified-l_last_reported>=1000 then
      l_last_reported:=l_verified;
      dbms_output.put_line('PROCESSING: verified='||l_verified||', pending='||l_other||', elapsed_seconds='||elapsed_seconds(l_stage_started));
    end if;
    exit when l_verified=c_document_count;
    select count(*) into l_failed_jobs from user_scheduler_job_run_details
     where job_name like 'NFE_AQ_B'||to_char(l_batch_id)||'_W%' and log_date>=l_stage_started and status<>'SUCCEEDED';
    if l_failed_jobs>0 then raise_application_error(-20998,'A Scheduler worker failed; inspect USER_SCHEDULER_JOB_RUN_DETAILS.'); end if;
    if elapsed_seconds(l_stage_started)>=c_wait_seconds then raise_application_error(-20999,'Timed out waiting for 10000 VERIFIED items.'); end if;
    dbms_session.sleep(2);
  end loop;
  l_process_seconds:=elapsed_seconds(l_stage_started);

  l_stage_started:=systimestamp;
  pkg_nfe_classic_aq_runtime.reconcile_batch(l_batch_id,l_passed);
  if not l_passed then raise_application_error(-21000,'Instrumented batch reconciliation failed.'); end if;
  pkg_nfe_classic_aq_runtime.stop_batch_workers(l_batch_id);
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  commit;
  l_reconcile_seconds:=elapsed_seconds(l_stage_started);

  select min(actual_start_date),max(log_date) into l_worker_first_start,l_worker_last_finish
    from user_scheduler_job_run_details
   where job_name like 'NFE_AQ_B'||to_char(l_batch_id)||'_W%' and log_date>=l_total_started;
  l_stage_started:=systimestamp;
  restore_configuration;
  update nfe_classic_aq_config set worker_limit=l_original_worker_limit,updated_by=user,updated_at=systimestamp where config_id=1;
  commit;
  l_restore_seconds:=elapsed_seconds(l_stage_started);

  dbms_output.put_line('BENCHMARK PASS: batch_id='||l_batch_id||', prefix='||l_run_prefix);
  dbms_output.put_line('TIMING seed_seconds='||l_seed_seconds||', configure_seconds='||l_configure_seconds||', admit_seconds='||l_admit_seconds||', launch_seconds='||l_launch_seconds||', processing_seconds='||l_process_seconds||', reconcile_and_stop_seconds='||l_reconcile_seconds||', restore_seconds='||l_restore_seconds||', total_seconds='||elapsed_seconds(l_total_started));
  dbms_output.put_line('WORKERS first_start='||to_char(l_worker_first_start,'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM')||', last_finish='||to_char(l_worker_last_finish,'YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM'));
exception when others then
  begin
    pkg_nfe_classic_aq_runtime.set_enabled('N');
    if l_batch_id is not null then pkg_nfe_classic_aq_runtime.stop_batch_workers(l_batch_id); end if;
    if l_original_worker_limit is not null then update nfe_classic_aq_config set worker_limit=l_original_worker_limit,updated_by=user,updated_at=systimestamp where config_id=1; end if;
    if l_endpoint is not null then restore_configuration; end if;
    commit;
  exception when others then rollback; end;
  raise;
end;
/

select b.batch_id,b.batch_code,b.status,count(i.control_id) total_items,
       count(case when i.status='VERIFIED' then 1 end) verified_items,
       count(case when i.status<>'VERIFIED' then 1 end) non_verified_items
  from nfe_migration_batch b join nfe_migration_item i on i.batch_id=b.batch_id
 where b.batch_code like 'AQ-SCHED-INST-10K-10W-%'
 group by b.batch_id,b.batch_code,b.status order by b.batch_id desc fetch first 1 row only;
