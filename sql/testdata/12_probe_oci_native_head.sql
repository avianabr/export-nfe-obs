-- OCI Object Storage HEAD capability probe using the DBMS_CLOUD API available
-- in this database. It creates one uniquely named disposable object below
-- nfe-head-probe/, verifies it with HTTP HEAD, and deletes that same object.
-- It never reads or alters NF-e data.
--
-- OCI signing is performed by DBMS_CLOUD using NFE_OCI_HEAD_PROBE_CRED.
-- Content-MD5 is supplied on PUT so OCI validates that upload checksum. The
-- SHA-256 in opc-meta-sha256 is application metadata, not OCI SHA validation.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set echo off verify off feedback on serveroutput on size unlimited

declare
  c_namespace       constant varchar2(128) := 'idzvuvikb5ym';
  c_bucket          constant varchar2(256) := 'nfe';
  c_region          constant varchar2(64)  := 'us-ashburn-1';
  c_credential_name constant varchar2(128) := 'NFE_OCI_HEAD_PROBE_CRED';

  l_object_name     varchar2(512) := 'nfe-head-probe/' || lower(rawtohex(sys_guid())) || '.txt';
  l_object_uri      varchar2(2048);
  l_payload         blob;
  l_payload_text    varchar2(32767) := 'NFE OCI HEAD probe ' || lower(rawtohex(sys_guid()));
  l_length          pls_integer;
  l_sha256          varchar2(64);
  l_md5_base64      varchar2(128);
  l_put_response    dbms_cloud_types.resp;
  l_head_response   dbms_cloud_types.resp;
  l_delete_response dbms_cloud_types.resp;
  l_headers         clob;
  l_created         boolean := false;

  procedure cleanup_probe is
  begin
    if l_created then
      l_delete_response := dbms_cloud.send_request(
        credential_name => c_credential_name,
        uri             => l_object_uri,
        method          => dbms_cloud.method_delete);
      dbms_output.put_line('CLEANUP_STATUS=' ||
        dbms_cloud.get_response_status_code(l_delete_response));
      l_created := false;
    end if;
  end cleanup_probe;
begin
  l_object_uri := 'https://objectstorage.' || c_region || '.oraclecloud.com/n/' ||
    c_namespace || '/b/' || c_bucket || '/o/' || l_object_name;

  dbms_lob.createtemporary(l_payload, true);
  dbms_lob.writeappend(l_payload, length(l_payload_text),
    utl_raw.cast_to_raw(l_payload_text));
  l_length := dbms_lob.getlength(l_payload);
  l_sha256 := lower(rawtohex(dbms_crypto.hash(l_payload, dbms_crypto.hash_sh256)));
  l_md5_base64 := utl_raw.cast_to_varchar2(
    utl_encode.base64_encode(dbms_crypto.hash(l_payload, dbms_crypto.hash_md5)));

  l_put_response := dbms_cloud.send_request(
    credential_name => c_credential_name,
    uri             => l_object_uri,
    method          => dbms_cloud.method_put,
    headers         => json_object(
      'content-type' value 'text/plain',
      'content-md5' value l_md5_base64,
      'if-none-match' value '*',
      'opc-meta-sha256' value l_sha256,
      'opc-meta-content-length' value to_char(l_length)),
    body            => l_payload);
  l_created := true;

  if dbms_cloud.get_response_status_code(l_put_response) not in (200, 201) then
    raise_application_error(-20930, 'OCI PUT probe did not succeed; status=' ||
      dbms_cloud.get_response_status_code(l_put_response));
  end if;

  l_head_response := dbms_cloud.send_request(
    credential_name => c_credential_name,
    uri             => l_object_uri,
    method          => dbms_cloud.method_head);
  l_headers := dbms_cloud.get_response_headers(l_head_response).to_clob;

  dbms_output.put_line('OBJECT_NAME=' || l_object_name);
  dbms_output.put_line('PUT_STATUS=' || dbms_cloud.get_response_status_code(l_put_response));
  dbms_output.put_line('HEAD_STATUS=' || dbms_cloud.get_response_status_code(l_head_response));
  dbms_output.put_line('EXPECTED_LENGTH=' || l_length);
  dbms_output.put_line('EXPECTED_SHA256=' || l_sha256);
  dbms_output.put_line('HAS_CONTENT_LENGTH=' ||
    case when dbms_lob.instr(lower(l_headers), 'content-length') > 0 then 'Y' else 'N' end);
  dbms_output.put_line('HEAD_LENGTH_MATCH=' ||
    case when dbms_lob.instr(lower(l_headers), 'content-length') > 0
               and dbms_lob.instr(l_headers, to_char(l_length)) > 0 then 'Y' else 'N' end);
  dbms_output.put_line('HAS_OPC_META_SHA256=' ||
    case when dbms_lob.instr(lower(l_headers), 'opc-meta-sha256') > 0 then 'Y' else 'N' end);
  dbms_output.put_line('HEAD_SHA256_METADATA_MATCH=' ||
    case when dbms_lob.instr(lower(l_headers), l_sha256) > 0 then 'Y' else 'N' end);
  dbms_output.put_line('RESPONSE_HEADERS_BEGIN');
  dbms_output.put_line(dbms_lob.substr(l_headers, 32767, 1));
  dbms_output.put_line('RESPONSE_HEADERS_END');

  if dbms_cloud.get_response_status_code(l_head_response) <> 200
     or dbms_lob.instr(lower(l_headers), 'content-length') = 0
     or dbms_lob.instr(lower(l_headers), 'opc-meta-sha256') = 0
     or dbms_lob.instr(lower(l_headers), l_sha256) = 0 then
    raise_application_error(-20931,
      'OCI HEAD lacks expected HTTP 200, Content-Length, or SHA-256 metadata.');
  end if;

  cleanup_probe;
  dbms_lob.freetemporary(l_payload);
  dbms_output.put_line('PASS: OCI HEAD returned size and SHA-256 metadata without GET.');
  dbms_output.put_line('NOTE: OCI server-side checksum validation here is Content-MD5, not SHA-256.');
exception
  when others then
    begin
      cleanup_probe;
    exception
      when others then
        dbms_output.put_line('WARNING: cleanup failed for ' || l_object_name || ': ' || sqlerrm);
    end;
    if dbms_lob.istemporary(l_payload) = 1 then
      dbms_lob.freetemporary(l_payload);
    end if;
    raise;
end;
/
