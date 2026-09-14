-- Main SQLcl/SQL*Plus installation orchestrator.
-- Start with: sql /nolog @00_run-installation.sql
-- It reads non-secret values from environment.sql and prompts for each
-- operator-supplied secret without echoing it or writing it to a local file.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set echo off
set verify off
set serveroutput on
@@sql/00_environment_defaults.sql
@@environment.sql
accept DEPLOY_SYS_PASSWORD char prompt 'Password for SYS: ' hide
accept DEPLOY_NFE_OWNER_PASSWORD char prompt 'Password for NFE_OWNER: ' hide
column deploy_credential_script new_value DEPLOY_CREDENTIAL_SCRIPT noprint
select case upper('&&DEPLOY_STORAGE_PROVIDER')
         when 'S3_COMPATIBLE' then '03_create-s3-credential.sql'
         when 'OCI_NATIVE' then '03_create-oci-native-credential.sql'
       end as deploy_credential_script
  from dual;
column deploy_credential_script clear
connect sys/"&&DEPLOY_SYS_PASSWORD"@&&DEPLOY_CONNECT_IDENTIFIER as sysdba
define NFE_OWNER_PASSWORD = '&&DEPLOY_NFE_OWNER_PASSWORD'
prompt [SYS] Create or validate NFE_OWNER.
@@01_create-nfe-owner.sql
column generated_runtime_password new_value NFE_MIGRATION_RUNTIME_PASSWORD noprint
set termout off
select 'R1#' || dbms_random.string('X', 29) as generated_runtime_password from dual;
set termout on
column generated_runtime_password clear
prompt [SYS] Create or validate the technical runtime identity and private roles.
@@02_provision.sql
connect nfe_owner/"&&DEPLOY_NFE_OWNER_PASSWORD"@&&DEPLOY_CONNECT_IDENTIFIER
prompt [NFE_OWNER] Create or validate the provider credential.
@@&&DEPLOY_CREDENTIAL_SCRIPT
connect sys/"&&DEPLOY_SYS_PASSWORD"@&&DEPLOY_CONNECT_IDENTIFIER as sysdba
prompt [SYS] Run read-only preflight checks.
@@04_preflight.sql
connect nfe_owner/"&&DEPLOY_NFE_OWNER_PASSWORD"@&&DEPLOY_CONNECT_IDENTIFIER
prompt [NFE_OWNER] Install runtime objects.
@@05_install.sql
connect sys/"&&DEPLOY_SYS_PASSWORD"@&&DEPLOY_CONNECT_IDENTIFIER as sysdba
prompt [SYS] Apply the endpoint-derived ACL and least-privilege grants.
@@sql/09_least_privilege.sql
connect nfe_owner/"&&DEPLOY_NFE_OWNER_PASSWORD"@&&DEPLOY_CONNECT_IDENTIFIER
prompt [NFE_OWNER] Persist and inspect configuration, then verify safe state.
@@06_configure.sql
@@07_show-effective-configuration.sql
@@08_verify-s3-credential-preserved.sql
@@09_postflight.sql
undefine NFE_OWNER_PASSWORD
undefine NFE_MIGRATION_RUNTIME_PASSWORD
undefine DEPLOY_CREDENTIAL_SCRIPT
undefine DEPLOY_SYS_PASSWORD
undefine DEPLOY_NFE_OWNER_PASSWORD
prompt PASS: orchestrated Classic AQ installation completed; session-only secrets were cleared.
exit success
