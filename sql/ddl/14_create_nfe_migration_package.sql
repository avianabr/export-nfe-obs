-- Run as NFE_OWNER after 11_create_nfe_selection_package.sql and TEQ setup.
whenever oserror exit failure rollback
create or replace package pkg_nfe_migration authid definer as
  procedure admit_chunk(p_batch_id in number, p_requested_count in pls_integer,
                        p_admitted_count out pls_integer);
end pkg_nfe_migration;
/
create or replace package body pkg_nfe_migration as
  c_object_root constant varchar2(300) :=
    'https://idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com/POC_RT/';
  procedure admit_chunk(p_batch_id in number, p_requested_count in pls_integer,
                        p_admitted_count out pls_integer) is
    l_status varchar2(30); l_control_id number; l_object_key varchar2(1024);
    l_msgid raw(16); l_payload raw(2000);
    l_enq dbms_aq.enqueue_options_t; l_props dbms_aq.message_properties_t;
  begin
    update nfe_migration_batch set status = 'SELECTING'
     where batch_id = p_batch_id and status = 'CREATED';
    pkg_nfe_pipeline_config.assert_admission_allowed(p_batch_id, p_requested_count);
    l_enq.visibility := dbms_aq.on_commit;
    p_admitted_count := 0;
    for r in (
      select d.nfe_id, d.chave_nfe, d.data_emissao
        from poc_nfe_document d join nfe_migration_batch b on b.batch_id=p_batch_id
       where d.xml_clob is not null and d.data_emissao < b.cutoff_date
         and (json_value(b.criteria_json, '$.benchmarkKeyPrefix' returning varchar2(20) null on empty) is null
              or d.chave_nfe like json_value(b.criteria_json, '$.benchmarkKeyPrefix' returning varchar2(20) null on empty) || '%')
         and not exists (select 1 from nfe_migration_item i where i.nfe_id=d.nfe_id)
         and exists (select 1 from json_table(b.criteria_json, '$.eligibleSituations[*]'
                      columns(situacao varchar2(30) path '$')) j where j.situacao=d.situacao)
       order by d.data_emissao, d.nfe_id fetch first p_requested_count rows only) loop
      l_object_key := 'nfe/' || to_char(r.data_emissao at time zone 'UTC','YYYY/MM') ||
                      '/' || r.chave_nfe || '.xml';
      insert into nfe_migration_item(batch_id,nfe_id,status,object_key,object_uri)
      values(p_batch_id,r.nfe_id,'QUEUED',l_object_key,c_object_root||l_object_key)
      returning control_id into l_control_id;
      l_props.correlation := 'NFE-MIG-' || l_control_id;
      l_props.exception_queue := 'NFE_MIGRATION_EX_Q';
      l_payload := utl_raw.cast_to_raw('{"eventType":"NFE_MIGRATION","version":1,"controlId":'||
                   l_control_id||',"nfeId":'||r.nfe_id||',"batchId":'||p_batch_id||'}');
      dbms_aq.enqueue('NFE_MIGRATION_Q',l_enq,l_props,l_payload,l_msgid);
      update nfe_migration_item set aq_msgid=l_msgid,enqueued_at=systimestamp
       where control_id=l_control_id;
      p_admitted_count := p_admitted_count + 1;
    end loop;
    if p_admitted_count > 0 then
      update nfe_migration_batch set selected_count=selected_count+p_admitted_count,
          queued_count=queued_count+p_admitted_count, status='PROCESSING' where batch_id=p_batch_id;
    end if;
  end;
end pkg_nfe_migration;
/
prompt PASS: migration admission package created.
