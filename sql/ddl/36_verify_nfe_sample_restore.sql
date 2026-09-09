-- Run as NFE_OWNER after a batch has been closed as PURGED.
-- This proves a sample can be reconstructed from Object Storage without
-- repopulating the source fiscal row.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

accept restore_control_id number prompt 'PURGED control ID to restore into a temporary CLOB: '

declare
  c_credential_name constant varchar2(128) := 'NFE_OBJECT_STORAGE_S3_CRED';
  l_uri nfe_migration_item.object_uri%type;
  l_status nfe_migration_item.status%type;
  l_expected_size nfe_migration_item.object_size_bytes%type;
  l_expected_hash nfe_migration_item.object_sha256%type;
  l_source_present pls_integer;
  l_blob blob;
  l_clob clob;
  l_destination_offset integer := 1;
  l_source_offset integer := 1;
  l_language_context integer := dbms_lob.default_lang_ctx;
  l_warning integer;
  l_size number;
  l_hash varchar2(64);
begin
  select i.object_uri, i.status, i.object_size_bytes, i.object_sha256,
         case when d.xml_clob is null then 0 else 1 end
    into l_uri, l_status, l_expected_size, l_expected_hash, l_source_present
    from nfe_migration_item i join poc_nfe_document d on d.nfe_id = i.nfe_id
   where i.control_id = &restore_control_id;
  if l_status <> 'PURGED' or l_source_present <> 0 then
    raise_application_error(-20180, 'Control item is not a closed purge with absent source content.');
  end if;

  l_blob := dbms_cloud.get_object(c_credential_name, l_uri);
  l_size := dbms_lob.getlength(l_blob);
  l_hash := rawtohex(dbms_crypto.hash(l_blob, dbms_crypto.hash_sh256));
  if l_size <> l_expected_size or l_hash <> l_expected_hash then
    raise_application_error(-20181, 'Object Storage bytes do not match persisted evidence.');
  end if;

  dbms_lob.createtemporary(l_clob, cache => false, dur => dbms_lob.call);
  dbms_lob.converttoclob(l_clob, l_blob, dbms_lob.lobmaxsize,
    l_destination_offset, l_source_offset, nls_charset_id('AL32UTF8'),
    l_language_context, l_warning);
  if l_warning <> dbms_lob.no_warning or dbms_lob.getlength(l_clob) = 0 then
    raise_application_error(-20182, 'Temporary restoration conversion did not complete cleanly.');
  end if;
  pkg_nfe_audit.log_event('USER', 'RESTORE_SAMPLE_VERIFIED', null, &restore_control_id,
    null, null, null, '{"restoredBytes":' || l_size || '}');
  commit;
  dbms_output.put_line('PASS: Object Storage sample restored to a temporary CLOB and matched integrity evidence.');
  dbms_lob.freetemporary(l_clob);
  pkg_nfe_transfer.free_temporary_blob(l_blob);
exception
  when others then
    if l_clob is not null and dbms_lob.istemporary(l_clob) = 1 then dbms_lob.freetemporary(l_clob); end if;
    pkg_nfe_transfer.free_temporary_blob(l_blob);
    rollback;
    raise;
end;
/
