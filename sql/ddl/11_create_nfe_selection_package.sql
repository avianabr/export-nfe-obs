-- Run as NFE_OWNER after 01_create_nfe_migration_schema.sql,
-- 03_create_audit_and_operational_views.sql and 09_create_nfe_pipeline_config.sql.

whenever oserror exit failure rollback

create or replace package pkg_nfe_selection authid definer as
  procedure create_batch(
    p_batch_code            in nfe_migration_batch.batch_code%type,
    p_cutoff_date           in nfe_migration_batch.cutoff_date%type,
    p_max_documents         in nfe_migration_batch.max_documents%type,
    p_selection_chunk_size  in nfe_migration_batch.selection_chunk_size%type,
    p_eligible_situacoes    in sys.odcivarchar2list,
    p_justification         in varchar2,
    p_batch_id              out nfe_migration_batch.batch_id%type);

  function derive_object_key(
    p_nfe_id in poc_nfe_document.nfe_id%type) return varchar2;

  procedure open_eligible_documents(
    p_batch_id        in nfe_migration_batch.batch_id%type,
    p_limit           in pls_integer,
    p_documents       out sys_refcursor);
end pkg_nfe_selection;
/

create or replace package body pkg_nfe_selection as
  procedure create_batch(
    p_batch_code            in nfe_migration_batch.batch_code%type,
    p_cutoff_date           in nfe_migration_batch.cutoff_date%type,
    p_max_documents         in nfe_migration_batch.max_documents%type,
    p_selection_chunk_size  in nfe_migration_batch.selection_chunk_size%type,
    p_eligible_situacoes    in sys.odcivarchar2list,
    p_justification         in varchar2,
    p_batch_id              out nfe_migration_batch.batch_id%type) is
    l_config_chunk_size nfe_migration_config.enqueue_chunk_size%type;
    l_criteria          json_object_t := json_object_t();
    l_situacoes         json_array_t := json_array_t();
    l_situacao          varchar2(30 char);
    l_criteria_json     clob;
  begin
    if p_batch_code is null or length(trim(p_batch_code)) = 0
       or length(p_batch_code) > 50 then
      raise_application_error(-20050, 'Batch code is required and limited to 50 characters.');
    end if;

    if p_cutoff_date is null or p_cutoff_date >= systimestamp then
      raise_application_error(-20051, 'Cutoff date must be in the past.');
    end if;

    if p_max_documents is null or p_max_documents <= 0
       or p_max_documents > 100000 then
      raise_application_error(-20052, 'Max documents must be between 1 and 100000.');
    end if;

    select enqueue_chunk_size
      into l_config_chunk_size
      from nfe_migration_config
     where config_id = 1;

    if p_selection_chunk_size is null or p_selection_chunk_size <= 0
       or p_selection_chunk_size > p_max_documents
       or p_selection_chunk_size > l_config_chunk_size then
      raise_application_error(-20053,
        'Selection chunk must be positive and not exceed batch/configured limits.');
    end if;

    if p_eligible_situacoes is null or p_eligible_situacoes.count = 0 then
      raise_application_error(-20054, 'At least one eligible fiscal situation is required.');
    end if;

    if p_justification is null or length(trim(p_justification)) < 10
       or length(p_justification) > 1000 then
      raise_application_error(-20055,
        'Justification must contain 10 to 1000 characters.');
    end if;

    for l_index in 1 .. p_eligible_situacoes.count loop
      l_situacao := upper(trim(p_eligible_situacoes(l_index)));
      if l_situacao not in ('AUTORIZADA', 'CANCELADA', 'DENEGADA') then
        raise_application_error(-20056, 'Unsupported eligible fiscal situation.');
      end if;
      l_situacoes.append(l_situacao);
    end loop;

    l_criteria.put('cutoffDateUtc',
      to_char(p_cutoff_date at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.FF3"Z"'));
    l_criteria.put('maxDocuments', p_max_documents);
    l_criteria.put('selectionChunkSize', p_selection_chunk_size);
    l_criteria.put('eligibleSituations', l_situacoes);
    l_criteria.put('justification', trim(p_justification));
    l_criteria_json := l_criteria.to_clob;

    insert into nfe_migration_batch (
      batch_code, status, cutoff_date, max_documents, selection_chunk_size,
      criteria_json, created_by)
    values (
      trim(p_batch_code), 'CREATED', p_cutoff_date, p_max_documents,
      p_selection_chunk_size, l_criteria_json,
      sys_context('USERENV', 'SESSION_USER'))
    returning batch_id into p_batch_id;

    pkg_nfe_audit.log_event(
      p_actor_type => 'USER',
      p_event_type => 'BATCH_CREATED',
      p_batch_id => p_batch_id,
      p_to_status => 'CREATED',
      p_details_json => '{"maxDocuments":' || p_max_documents ||
                        ',"selectionChunkSize":' || p_selection_chunk_size || '}');
  end create_batch;

  function derive_object_key(
    p_nfe_id in poc_nfe_document.nfe_id%type) return varchar2 is
    l_object_key varchar2(1024 char);
  begin
    select 'nfe/' || to_char(data_emissao at time zone 'UTC', 'YYYY/MM') ||
           '/' || chave_nfe || '.xml'
      into l_object_key
      from poc_nfe_document
     where nfe_id = p_nfe_id;
    return l_object_key;
  end derive_object_key;

  procedure open_eligible_documents(
    p_batch_id        in nfe_migration_batch.batch_id%type,
    p_limit           in pls_integer,
    p_documents       out sys_refcursor) is
    l_cutoff_date nfe_migration_batch.cutoff_date%type;
    l_chunk_size  nfe_migration_batch.selection_chunk_size%type;
    l_criteria    nfe_migration_batch.criteria_json%type;
    l_status      nfe_migration_batch.status%type;
  begin
    if p_limit is null or p_limit <= 0 then
      raise_application_error(-20058, 'Selection limit must be positive.');
    end if;
    select cutoff_date, selection_chunk_size, criteria_json, status
      into l_cutoff_date, l_chunk_size, l_criteria, l_status
      from nfe_migration_batch where batch_id = p_batch_id;
    if l_status not in ('CREATED', 'SELECTING') or p_limit > l_chunk_size then
      raise_application_error(-20059, 'Batch is not eligible or selection limit exceeds chunk size.');
    end if;
    open p_documents for
      select d.nfe_id, d.chave_nfe,
             'nfe/' || to_char(d.data_emissao at time zone 'UTC', 'YYYY/MM') ||
             '/' || d.chave_nfe || '.xml' as object_key
        from poc_nfe_document d
       where d.xml_clob is not null
         and d.data_emissao < l_cutoff_date
         and not exists (select 1 from nfe_migration_item i where i.nfe_id = d.nfe_id)
         and exists (
           select 1 from json_table(l_criteria, '$.eligibleSituations[*]'
                    columns (situacao varchar2(30) path '$')) j
            where j.situacao = d.situacao)
       order by d.data_emissao, d.nfe_id
       fetch first p_limit rows only;
  end open_eligible_documents;
end pkg_nfe_selection;
/

prompt PASS: selection package created.
