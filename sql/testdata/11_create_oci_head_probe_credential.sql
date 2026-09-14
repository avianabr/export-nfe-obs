-- Creates an OCI API-signing credential for the isolated HEAD capability test.
-- Run as NFE_OWNER only after a least-privilege OCI API key and a dedicated
-- writable test bucket have been provisioned. No secret is written to disk.
--
-- Input values:
--   * OCI user OCID, tenancy OCID, and API-key fingerprint (non-secret);
--   * unencrypted API private key, Base64/PEM body on one line (secret).
-- The public half of that API key must already be uploaded to the OCI user.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set echo off verify off feedback on serveroutput on size unlimited

accept OCI_HEAD_PROBE_USER_OCID char prompt 'OCI user OCID: '
accept OCI_HEAD_PROBE_TENANCY_OCID char prompt 'OCI tenancy OCID: '
accept OCI_HEAD_PROBE_FINGERPRINT char prompt 'OCI API-key fingerprint: '
accept OCI_HEAD_PROBE_PRIVATE_KEY char hide prompt 'OCI API private key (one line; hidden): '

declare
  c_credential_name constant varchar2(128) := 'NFE_OCI_HEAD_PROBE_CRED';
  l_existing_count   pls_integer;
begin
  select count(*) into l_existing_count
    from user_credentials
   where credential_name = c_credential_name;

  if l_existing_count <> 0 then
    dbms_output.put_line('PASS: existing ' || c_credential_name ||
      ' was preserved; no credential was replaced.');
  else
    dbms_cloud.create_credential(
      credential_name => c_credential_name,
      user_ocid       => '&OCI_HEAD_PROBE_USER_OCID',
      tenancy_ocid    => '&OCI_HEAD_PROBE_TENANCY_OCID',
      private_key     => '&OCI_HEAD_PROBE_PRIVATE_KEY',
      fingerprint     => '&OCI_HEAD_PROBE_FINGERPRINT');
    dbms_output.put_line('PASS: OCI HEAD-probe credential created: ' ||
      c_credential_name || '.');
  end if;
end;
/

undefine OCI_HEAD_PROBE_USER_OCID
undefine OCI_HEAD_PROBE_TENANCY_OCID
undefine OCI_HEAD_PROBE_FINGERPRINT
undefine OCI_HEAD_PROBE_PRIVATE_KEY
