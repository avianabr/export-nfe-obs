-- Run as NFE_OWNER after 03_grant_s3_compat_acl.sql and
-- 04_create_s3_compat_credential.sql have completed successfully.
-- This creates one unique, non-NF-e evidence object under nfe-poc/preflight/.
-- It does not overwrite or delete any object.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_source_blob    blob;
  l_received_blob  blob;
  l_contents_raw   raw(32767) := utl_raw.cast_to_raw('NFE Object Storage preflight: UTF-8 verification.');
  l_object_key     varchar2(200) := 'nfe-poc/preflight/dbms-cloud-' || lower(rawtohex(sys_guid())) || '.txt';
  l_object_uri     varchar2(1000);
  l_source_hash    raw(32);
  l_received_hash  raw(32);
begin
  if sys_context('USERENV', 'CURRENT_USER') <> 'NFE_OWNER' then
    raise_application_error(-20000, 'Connect as NFE_OWNER before running the smoke test.');
  end if;

  l_object_uri := 'https://idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com/POC_RT/' || l_object_key;

  dbms_lob.createtemporary(l_source_blob, true, dbms_lob.call);
  dbms_lob.writeappend(l_source_blob, utl_raw.length(l_contents_raw), l_contents_raw);
  l_source_hash := dbms_crypto.hash(l_source_blob, dbms_crypto.hash_sh256);

  dbms_cloud.put_object(
    credential_name => 'NFE_OBJECT_STORAGE_S3_CRED',
    object_uri      => l_object_uri,
    contents        => l_source_blob);

  l_received_blob := dbms_cloud.get_object(
    credential_name => 'NFE_OBJECT_STORAGE_S3_CRED',
    object_uri      => l_object_uri);
  l_received_hash := dbms_crypto.hash(l_received_blob, dbms_crypto.hash_sh256);

  if dbms_lob.getlength(l_source_blob) <> dbms_lob.getlength(l_received_blob)
     or l_source_hash <> l_received_hash then
    raise_application_error(-20001, 'Object Storage round-trip integrity check failed for ' || l_object_uri);
  end if;

  dbms_output.put_line('PASS: authenticated PUT_OBJECT/GET_OBJECT round trip succeeded.');
  dbms_output.put_line('Evidence object: ' || l_object_uri);
  dbms_output.put_line('SHA-256: ' || rawtohex(l_source_hash));

  dbms_lob.freetemporary(l_source_blob);
  if dbms_lob.istemporary(l_received_blob) = 1 then
    dbms_lob.freetemporary(l_received_blob);
  end if;
exception
  when others then
    if dbms_lob.istemporary(l_source_blob) = 1 then
      dbms_lob.freetemporary(l_source_blob);
    end if;
    if dbms_lob.istemporary(l_received_blob) = 1 then
      dbms_lob.freetemporary(l_received_blob);
    end if;
    raise;
end;
/
