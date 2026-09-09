-- Run as SYS in PDB_POCRT_02 before creating the S3-compatible credential.
-- Grants NFE_OWNER only the outbound rights needed for the OCI S3-compatible
-- endpoint used with the OCI Customer Secret Key (access key / secret key).

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

grant create credential to nfe_owner;

begin
  dbms_network_acl_admin.append_host_ace(
    host => 'idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com',
    lower_port => 443,
    upper_port => 443,
    ace => xs$ace_type(
      privilege_list => xs$name_list('http'),
      principal_name => 'NFE_OWNER',
      principal_type => xs_acl.ptype_db));

  dbms_network_acl_admin.append_host_ace(
    host => 'idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com',
    ace => xs$ace_type(
      privilege_list => xs$name_list('resolve'),
      principal_name => 'NFE_OWNER',
      principal_type => xs_acl.ptype_db));
end;
/

prompt PASS: S3-compatible OCI Object Storage ACL granted to NFE_OWNER.
