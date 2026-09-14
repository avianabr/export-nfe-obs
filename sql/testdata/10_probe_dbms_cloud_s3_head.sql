-- Read-only capability probe. Run as NFE_OWNER in the isolated PDB after at
-- least one Classic AQ item has reached VERIFIED. It sends HEAD only; it does
-- not upload, download, alter a batch, purge source content, or touch TEQ.
--
-- The response headers are printed because they are the evidence under test.
-- Request headers, credentials, XML, and payloads are never printed.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set echo off verify off serveroutput on size unlimited

declare
  l_credential_name  nfe_deploy_storage_config.credential_name%type;
  l_s3_object_uri    nfe_migration_item.object_uri%type;
  l_https_object_uri nfe_migration_item.object_uri%type;
  l_response         dbms_cloud_types.resp;
  l_status_code      pls_integer;
  l_response_headers clob;
begin
  select s.credential_name
    into l_credential_name
    from nfe_deploy_storage_config s
   where s.config_id = 1;

  select object_uri
    into l_s3_object_uri
    from (
      select object_uri
        from nfe_migration_item
       where status = 'VERIFIED'
         and object_uri is not null
       order by updated_at desc
    )
   where rownum = 1;

  l_https_object_uri := regexp_replace(l_s3_object_uri, '^s3://', 'https://', 1, 1, 'i');
  if l_https_object_uri = l_s3_object_uri then
    raise_application_error(-20922,
      'Verified object URI is not in s3:// form; refusing to infer an HTTPS URI.');
  end if;

  l_response := dbms_cloud.send_request(
    credential_name => l_credential_name,
    uri             => l_https_object_uri,
    method          => dbms_cloud.method_head);
  l_status_code := dbms_cloud.get_response_status_code(l_response);
  l_response_headers := dbms_cloud.get_response_headers(l_response).to_clob;

  dbms_output.put_line('HEAD_PROBE_STATUS=' || l_status_code);
  dbms_output.put_line('OBJECT_URI=' || l_https_object_uri);
  dbms_output.put_line('HAS_CONTENT_LENGTH=' ||
    case when dbms_lob.instr(lower(l_response_headers), 'content-length') > 0
         then 'Y' else 'N' end);
  dbms_output.put_line('HAS_AMZ_SHA256=' ||
    case when dbms_lob.instr(lower(l_response_headers), 'x-amz-checksum-sha256') > 0
         then 'Y' else 'N' end);
  dbms_output.put_line('HAS_OBS_SHA256_METADATA=' ||
    case when dbms_lob.instr(lower(l_response_headers), 'x-obs-meta-sha256') > 0
         then 'Y' else 'N' end);
  dbms_output.put_line('HAS_OBS_CRC64=' ||
    case when dbms_lob.instr(lower(l_response_headers), 'x-obs-checksum-crc64ecma') > 0
         then 'Y' else 'N' end);
  dbms_output.put_line('RESPONSE_HEADERS_BEGIN');
  dbms_output.put_line(dbms_lob.substr(l_response_headers, 32767, 1));
  dbms_output.put_line('RESPONSE_HEADERS_END');

  if l_status_code <> 200 then
    raise_application_error(-20920,
      'HEAD probe did not receive HTTP 200; inspect the response headers.');
  end if;
exception
  when no_data_found then
    raise_application_error(-20921,
      'No VERIFIED item with object URI exists for this read-only HEAD probe.');
end;
/
