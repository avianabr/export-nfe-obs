-- Run as NFE_OWNER after 17_create_nfe_transfer_package.sql and TEQ setup.
-- Dequeue remains part of the caller transaction (REMOVE + ON_COMMIT).

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

create or replace package pkg_nfe_worker authid definer as
  procedure dequeue_and_load(
    p_control_id  out nfe_migration_item.control_id%type,
    p_nfe_id      out poc_nfe_document.nfe_id%type,
    p_batch_id    out nfe_migration_batch.batch_id%type,
    p_xml_clob    out nocopy clob,
    p_msgid       out raw,
    p_correlation in varchar2 default null);

  procedure upload_item(
    p_control_id in nfe_migration_item.control_id%type);

  procedure verify_uploaded_item(
    p_control_id in nfe_migration_item.control_id%type);

  procedure process_one(
    p_simulate_transient in boolean default false,
    p_correlation        in varchar2 default null);
end pkg_nfe_worker;
/

create or replace package body pkg_nfe_worker as
  procedure dequeue_and_load(
    p_control_id  out nfe_migration_item.control_id%type,
    p_nfe_id      out poc_nfe_document.nfe_id%type,
    p_batch_id    out nfe_migration_batch.batch_id%type,
    p_xml_clob    out nocopy clob,
    p_msgid       out raw,
    p_correlation in varchar2 default null) is
    l_dequeue_options    dbms_aq.dequeue_options_t;
    l_message_properties dbms_aq.message_properties_t;
    l_payload            raw(2000);
    l_json               varchar2(32767);
    l_event_type         varchar2(30);
    l_version            number;
    l_payload_control_id number;
    l_payload_nfe_id     number;
    l_payload_batch_id   number;
    l_item_status        nfe_migration_item.status%type;
  begin
    l_dequeue_options.visibility := dbms_aq.on_commit;
    l_dequeue_options.dequeue_mode := dbms_aq.remove;
    l_dequeue_options.wait := dbms_aq.no_wait;
    l_dequeue_options.navigation := dbms_aq.first_message;
    l_dequeue_options.correlation := p_correlation;

    dbms_aq.dequeue(
      queue_name         => 'NFE_MIGRATION_Q',
      dequeue_options    => l_dequeue_options,
      message_properties => l_message_properties,
      payload            => l_payload,
      msgid              => p_msgid);

    begin
      l_json := utl_i18n.raw_to_char(l_payload, 'AL32UTF8');
      select json_value(l_json, '$.eventType' returning varchar2(30) error on error),
             json_value(l_json, '$.version' returning number error on error),
             json_value(l_json, '$.controlId' returning number error on error),
             json_value(l_json, '$.nfeId' returning number error on error),
             json_value(l_json, '$.batchId' returning number error on error)
        into l_event_type, l_version, l_payload_control_id,
             l_payload_nfe_id, l_payload_batch_id
        from dual;
    exception
      when others then
        raise_application_error(-20052,
          'Invalid NFE migration work-envelope JSON contract.');
    end;

    if l_event_type <> 'NFE_MIGRATION' then
      raise_application_error(-20053, 'Unsupported work-envelope event type.');
    end if;
    if l_version <> 1 then
      raise_application_error(-20054, 'Unsupported work-envelope version.');
    end if;
    if l_payload_control_id is null or l_payload_nfe_id is null
       or l_payload_batch_id is null or l_payload_control_id <= 0
       or l_payload_nfe_id <= 0 or l_payload_batch_id <= 0 then
      raise_application_error(-20055, 'Work-envelope references are required.');
    end if;

    begin
      select i.control_id, i.nfe_id, i.batch_id, i.status, d.xml_clob
        into p_control_id, p_nfe_id, p_batch_id, l_item_status, p_xml_clob
        from nfe_migration_item i
        join poc_nfe_document d on d.nfe_id = i.nfe_id
       where i.control_id = l_payload_control_id
       for update of i.status;
    exception
      when no_data_found then
        raise_application_error(-20056,
          'Work-envelope control item or source XML was not found.');
    end;

    if p_control_id <> l_payload_control_id or p_nfe_id <> l_payload_nfe_id
       or p_batch_id <> l_payload_batch_id then
      raise_application_error(-20057,
        'Work-envelope references do not match the control item.');
    end if;
    if l_item_status not in ('QUEUED','VERIFIED') then
      raise_application_error(-20058,
        'Control item is not eligible for worker processing.');
    end if;
    if p_xml_clob is null then
      raise_application_error(-20059, 'Source XML CLOB is absent.');
    end if;
  end dequeue_and_load;

  procedure upload_item(
    p_control_id in nfe_migration_item.control_id%type) is
    c_credential_name constant varchar2(128) := 'NFE_OBJECT_STORAGE_S3_CRED';
    l_nfe_id          nfe_migration_item.nfe_id%type;
    l_batch_id         nfe_migration_item.batch_id%type;
    l_status           nfe_migration_item.status%type;
    l_object_key       nfe_migration_item.object_key%type;
    l_object_uri       nfe_migration_item.object_uri%type;
    l_expected_key     nfe_migration_item.object_key%type;
    l_chave_nfe        poc_nfe_document.chave_nfe%type;
    l_emission_at      poc_nfe_document.data_emissao%type;
    l_xml_clob         clob;
    l_utf8_blob        blob;
    l_existing_blob    blob;
    l_source_size      number;
    l_source_sha256    varchar2(64);
    l_existing_size    number;
    l_existing_sha256  varchar2(64);
    l_object_exists    boolean := false;
  begin
    select i.nfe_id, i.batch_id, i.status, i.object_key, i.object_uri,
           d.chave_nfe, d.data_emissao, d.xml_clob
      into l_nfe_id, l_batch_id, l_status, l_object_key, l_object_uri,
           l_chave_nfe, l_emission_at, l_xml_clob
      from nfe_migration_item i
      join poc_nfe_document d on d.nfe_id = i.nfe_id
     where i.control_id = p_control_id
       for update of i.status;

    l_expected_key := 'nfe/' || to_char(l_emission_at at time zone 'UTC', 'YYYY/MM') ||
                      '/' || l_chave_nfe || '.xml';
    if l_status <> 'QUEUED' then
      raise_application_error(-20060, 'Only QUEUED items may be uploaded.');
    end if;
    if l_object_key <> l_expected_key
       or l_object_uri <>
          'https://idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com/POC_RT/' ||
          l_expected_key then
      raise_application_error(-20061, 'Control item has a non-deterministic Object Storage destination.');
    end if;

    update nfe_migration_item
       set status = 'UPLOADING', upload_started_at = systimestamp
     where control_id = p_control_id;
    pkg_nfe_transfer.clob_to_utf8_blob(l_xml_clob, l_utf8_blob);
    l_source_size := dbms_lob.getlength(l_utf8_blob);
    l_source_sha256 := rawtohex(dbms_crypto.hash(l_utf8_blob, dbms_crypto.hash_sh256));
    begin
      l_existing_blob := dbms_cloud.get_object(
        credential_name => c_credential_name, object_uri => l_object_uri);
      l_object_exists := true;
      l_existing_size := dbms_lob.getlength(l_existing_blob);
      l_existing_sha256 := rawtohex(dbms_crypto.hash(l_existing_blob, dbms_crypto.hash_sh256));
      pkg_nfe_transfer.free_temporary_blob(l_existing_blob);
    exception
      when others then
        pkg_nfe_transfer.free_temporary_blob(l_existing_blob);
        -- This 26ai DBMS_CLOUD deployment reports a missing S3-compatible
        -- object as ORA-20404; other releases can expose ORA-20025.
        if sqlcode in (-20404, -20025) then
          l_object_exists := false;
        else
          raise;
        end if;
    end;
    if l_object_exists and (l_existing_size <> l_source_size
       or l_existing_sha256 <> l_source_sha256) then
      update nfe_migration_item
         set status = 'EXCEPTION', last_error_code = 'OBJECT_CONFLICT',
             last_error = 'Preexisting object differs from source integrity evidence.',
             last_error_at = systimestamp
       where control_id = p_control_id;
      pkg_nfe_audit.log_event(
        p_actor_type => 'WORKER', p_event_type => 'OBJECT_CONFLICT',
        p_batch_id => l_batch_id, p_control_id => p_control_id,
        p_from_status => 'QUEUED', p_to_status => 'EXCEPTION',
        p_details_json => '{"existingObject":true}');
      pkg_nfe_transfer.free_temporary_blob(l_utf8_blob);
      return;
    end if;
    if not l_object_exists then
      dbms_cloud.put_object(
        credential_name => c_credential_name,
        object_uri      => l_object_uri,
        contents        => l_utf8_blob);
    end if;
    update nfe_migration_item
       set status = 'UPLOADED', source_size_bytes = l_source_size,
           source_sha256 = l_source_sha256, uploaded_at = systimestamp
     where control_id = p_control_id;
    update nfe_migration_batch
       set uploaded_count = uploaded_count + 1,
           source_bytes = source_bytes + l_source_size
     where batch_id = l_batch_id;
    pkg_nfe_audit.log_event(
      p_actor_type => 'WORKER', p_event_type => 'OBJECT_UPLOADED',
      p_batch_id => l_batch_id, p_control_id => p_control_id,
      p_from_status => 'QUEUED', p_to_status => 'UPLOADED',
      p_details_json => '{"sourceBytes":' || l_source_size ||
                        ',"sourceSha256":"' || l_source_sha256 || '"}');
    pkg_nfe_transfer.free_temporary_blob(l_utf8_blob);
  exception
    when others then
      pkg_nfe_transfer.free_temporary_blob(l_existing_blob);
      pkg_nfe_transfer.free_temporary_blob(l_utf8_blob);
      raise;
  end upload_item;

  procedure verify_uploaded_item(
    p_control_id in nfe_migration_item.control_id%type) is
    c_credential_name constant varchar2(128) := 'NFE_OBJECT_STORAGE_S3_CRED';
    l_batch_id      nfe_migration_item.batch_id%type;
    l_status        nfe_migration_item.status%type;
    l_object_uri    nfe_migration_item.object_uri%type;
    l_source_size   nfe_migration_item.source_size_bytes%type;
    l_source_hash   nfe_migration_item.source_sha256%type;
    l_object_blob   blob;
    l_object_size   number;
    l_object_hash   varchar2(64);
  begin
    select batch_id, status, object_uri, source_size_bytes, source_sha256
      into l_batch_id, l_status, l_object_uri, l_source_size, l_source_hash
      from nfe_migration_item
     where control_id = p_control_id
       for update;
    if l_status <> 'UPLOADED' then
      raise_application_error(-20062, 'Only UPLOADED items may be verified.');
    end if;
    update nfe_migration_item set status = 'VERIFYING' where control_id = p_control_id;
    l_object_blob := dbms_cloud.get_object(
      credential_name => c_credential_name, object_uri => l_object_uri);
    l_object_size := dbms_lob.getlength(l_object_blob);
    l_object_hash := rawtohex(dbms_crypto.hash(l_object_blob, dbms_crypto.hash_sh256));
    if l_object_size <> l_source_size or l_object_hash <> l_source_hash then
      raise_application_error(-20063,
        'Downloaded object size or SHA-256 differs from the source evidence.');
    end if;
    update nfe_migration_item
       set status = 'VERIFIED', object_size_bytes = l_object_size,
           object_sha256 = l_object_hash, verified_at = systimestamp
     where control_id = p_control_id;
    update nfe_migration_batch
       set verified_count = verified_count + 1,
           object_bytes = object_bytes + l_object_size
     where batch_id = l_batch_id;
    pkg_nfe_audit.log_event(
      p_actor_type => 'WORKER', p_event_type => 'OBJECT_VERIFIED',
      p_batch_id => l_batch_id, p_control_id => p_control_id,
      p_from_status => 'UPLOADED', p_to_status => 'VERIFIED',
      p_details_json => '{"objectBytes":' || l_object_size ||
                        ',"objectSha256":"' || l_object_hash || '"}');
    pkg_nfe_transfer.free_temporary_blob(l_object_blob);
  exception
    when others then
      pkg_nfe_transfer.free_temporary_blob(l_object_blob);
      raise;
  end verify_uploaded_item;

  procedure process_one(
    p_simulate_transient in boolean default false,
    p_correlation        in varchar2 default null) is
    l_control_id number; l_nfe_id number; l_batch_id number; l_xml clob; l_msgid raw(16); l_status varchar2(30);
  begin
    dequeue_and_load(l_control_id, l_nfe_id, l_batch_id, l_xml, l_msgid,
      p_correlation);
    select status into l_status from nfe_migration_item where control_id=l_control_id;
    if l_status='VERIFIED' then commit; return; end if;
    upload_item(l_control_id);
    if p_simulate_transient then
      raise_application_error(-20066, 'Simulated transient Object Storage timeout.');
    end if;
    verify_uploaded_item(l_control_id);
    commit;
  exception
    when others then
      -- Do not persist a success state or acknowledge the TEQ delivery.
      -- The caller receives only the Oracle code/message; no XML, URI, or
      -- credential material is written to diagnostics in this transaction.
      rollback;
      raise;
  end process_one;
end pkg_nfe_worker;
/

prompt PASS: transactional TEQ dequeue and work-envelope validation package created.
