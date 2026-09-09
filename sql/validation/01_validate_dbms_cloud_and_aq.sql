-- Read-only prerequisite assessment for the NF-e historical migration PoC.
-- Run as the intended migration-runtime schema. It performs no DDL, DML,
-- queue operation, credential creation, or Object Storage request.
-- Target Object Storage endpoint: https://objectstorage.us-ashburn-1.oraclecloud.com/n/idzvuvikb5ym/b/POC_RT/o/
--
-- SQL*Plus / SQLcl example (do not put the password in shell history):
--   sqlplus 'NFE_MIGRATION_RUNTIME@//dev1-scan-zbnfc.clientsubnet.exadatavcn1.oraclevcn.com:1521/pocrt_pdb_pocrt_02.paas.oracle.com' @sql/validation/01_validate_dbms_cloud_and_aq.sql
--
-- Some sections require catalog privileges. ORA-00942/ORA-01031 in a section
-- means that a DBA must run that query or grant only the necessary read access.

whenever oserror exit failure rollback
whenever sqlerror continue

set echo off
set feedback on
set heading on
set linesize 220
set pagesize 200
set long 20000
set longchunksize 20000
set trimspool on
set serveroutput on size unlimited

prompt ================================================================
prompt 1. Connected database and container
prompt ================================================================

select sys_context('USERENV', 'DB_NAME') as db_name,
       sys_context('USERENV', 'DB_UNIQUE_NAME') as db_unique_name,
       sys_context('USERENV', 'CON_NAME') as container_name,
       sys_context('USERENV', 'CURRENT_USER') as current_user,
       sys_context('USERENV', 'CURRENT_SCHEMA') as current_schema
  from dual;

select banner_full
  from v$version
 where banner_full is not null;

select product, version, status
  from product_component_version
 where product like 'Oracle Database%';

select name, value
  from v$parameter
 where name in ('compatible', 'db_name', 'db_unique_name', 'db_domain',
                'streams_pool_size', 'sga_target', 'memory_target')
 order by name;

select con_id, name, open_mode, restricted
  from v$pdbs
 order by con_id;

prompt ================================================================
prompt 2. DBMS_CLOUD installation, visibility, and callable contract
prompt ================================================================

select object_name, object_type, owner, status
  from all_objects
 where object_name = 'DBMS_CLOUD'
 order by owner, object_type;

select synonym_name, table_owner, table_name
  from all_synonyms
 where synonym_name = 'DBMS_CLOUD'
 order by owner;

select owner, table_name, privilege, grantor
  from user_tab_privs_recd
 where table_name = 'DBMS_CLOUD'
 order by owner, privilege;

select owner, object_name, procedure_name, overload, subprogram_id
  from all_procedures
 where object_name = 'DBMS_CLOUD'
   and procedure_name in ('PUT_OBJECT', 'GET_OBJECT', 'LIST_OBJECTS', 'CREATE_CREDENTIAL')
 order by procedure_name, overload, subprogram_id;

select object_name, overload, position, argument_name, in_out, data_type
  from all_arguments
 where package_name = 'DBMS_CLOUD'
   and object_name in ('PUT_OBJECT', 'GET_OBJECT')
 order by object_name, overload, sequence;

prompt Credentials visible to the current schema (names only; no secrets)
select credential_name
  from user_credentials
 order by credential_name;

prompt ================================================================
prompt 3. Transactional Event Queue (TEQ) feature and API availability
prompt ================================================================

select parameter, value
  from v$option
 where upper(parameter) like '%QUEUE%'
    or upper(parameter) like '%ADVANCED%QUEUE%'
 order by parameter;

select object_name, object_type, owner, status
  from all_objects
 where object_name in ('DBMS_AQ', 'DBMS_AQADM')
 order by object_name, owner, object_type;

select synonym_name, table_owner, table_name
  from all_synonyms
 where synonym_name in ('DBMS_AQ', 'DBMS_AQADM')
 order by synonym_name, owner;

select owner, object_name, procedure_name, overload, subprogram_id
  from all_procedures
 where (object_name = 'DBMS_AQ'
        and procedure_name in ('ENQUEUE', 'DEQUEUE'))
    or (object_name = 'DBMS_AQADM'
        and procedure_name in ('CREATE_TRANSACTIONAL_EVENT_QUEUE',
                               'CREATE_EQ_EXCEPTION_QUEUE', 'START_QUEUE'))
 order by object_name, procedure_name, overload, subprogram_id;

prompt TEQ administrative API argument metadata
select object_name, overload, position, argument_name, in_out, data_type
  from all_arguments
 where package_name = 'DBMS_AQADM'
   and object_name in ('CREATE_TRANSACTIONAL_EVENT_QUEUE',
                       'CREATE_EQ_EXCEPTION_QUEUE')
 order by object_name, overload, sequence;

prompt Existing queues visible to the current schema
select name, queue_table, queue_type, enqueue_enabled, dequeue_enabled
  from user_queues
 order by name;

select queue_table, object_type
  from user_queue_tables
 order by queue_table;

prompt ================================================================
prompt 4. Runtime permissions and outbound-network visibility
prompt ================================================================

select privilege
  from session_privs
 where privilege in ('CREATE JOB', 'CREATE PROCEDURE', 'CREATE TABLE',
                     'EXECUTE ANY PROCEDURE', 'MANAGE SCHEDULER')
 order by privilege;

select granted_role
  from user_role_privs
 where granted_role in ('AQ_ADMINISTRATOR_ROLE', 'AQ_USER_ROLE', 'SCHEDULER_ADMIN')
 order by granted_role;

select host, lower_port, upper_port, privilege
  from user_host_aces
 order by host, lower_port, upper_port, privilege;

prompt ================================================================
prompt 5. Interpretation
prompt ================================================================
prompt Target bucket: POC_RT (namespace idzvuvikb5ym, region us-ashburn-1)
prompt PASS requires: target PDB is open read write; DBMS_CLOUD is VALID and
prompt visible to the runtime schema; PUT_OBJECT and GET_OBJECT signatures are
prompt listed; required TEQ APIs include CREATE_TRANSACTIONAL_EVENT_QUEUE and
prompt CREATE_EQ_EXCEPTION_QUEUE; and the schema has a valid credential and
prompt network access for the approved Object Storage endpoint.
prompt
prompt This script does not prove OCI connectivity. After credentials and IAM
prompt are approved, run a separate controlled PUT/GET smoke test against the
prompt dedicated PoC prefix, then preserve its output as change evidence.

exit success
