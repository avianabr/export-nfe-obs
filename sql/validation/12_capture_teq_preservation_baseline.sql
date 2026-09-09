-- Run as SYS (or a DBA account with SELECT_CATALOG_ROLE) in PDB_POCRT_02
-- BEFORE deploying any classic-AQ compatibility objects.
--
-- Read-only preservation baseline for the affected TEQ path.  It deliberately
-- does not dequeue, browse, select, or spool AQ payloads; it records only
-- metadata, state counts, and grant metadata needed to prove coexistence.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set echo off feedback on heading on pagesize 200 linesize 240 trimspool on

accept evidence_file char prompt 'Baseline output file name (without extension): '
spool &&evidence_file..log

prompt === TEQ PRESERVATION BASELINE ===
select systimestamp as collected_at_utc,
       sys_context('USERENV', 'DB_NAME') as db_name,
       sys_context('USERENV', 'CON_NAME') as container_name,
       sys_context('USERENV', 'INSTANCE_NAME') as instance_name,
       sys_context('USERENV', 'SESSION_USER') as collector
from dual;

prompt === ADR INCIDENT 836580 (LOCAL INSTANCE VISIBILITY) ===
-- V$DIAG_INCIDENT is instance-local. The original incident evidence was
-- collected with ADRCI on pocrt1; a connection served by pocrt2 can correctly
-- return no rows here. Do not use GV$DIAG_INCIDENT: it is not exposed by
-- every managed-database service.
select incident_id, create_time, problem_id, error_number, error_arg1, error_arg2
from v$diag_incident
where incident_id = 836580;

prompt === EXISTING TEQ QUEUES (NO PAYLOADS) ===
select owner, name, queue_table, queue_type, max_retries,
       retry_delay, enqueue_enabled, dequeue_enabled
from dba_queues
where owner = 'NFE_OWNER'
  and name in ('NFE_MIGRATION_Q', 'NFE_MIGRATION_EX_Q')
order by name;

select owner, queue_table, object_type, sort_order, recipients,
       compatible, secure
from dba_queue_tables
where owner = 'NFE_OWNER'
  and queue_table in ('NFE_MIGRATION_Q', 'NFE_MIGRATION_EX_Q')
order by queue_table;

prompt === EXISTING TEQ MESSAGE COUNTS BY STATE (NO PAYLOADS) ===
select msg_state, count(*) as message_count
from nfe_owner.aq$nfe_migration_q
group by msg_state
order by msg_state;

prompt === EXISTING TEQ QUEUE PRIVILEGES ===
select grantee, privilege, grantable
from dba_tab_privs
where owner = 'NFE_OWNER'
  and table_name in ('NFE_MIGRATION_Q', 'NFE_MIGRATION_EX_Q')
order by table_name, grantee, privilege;

prompt === DEPLOYED TEQ-DEPENDENT PACKAGE STATE ===
select owner, object_name, object_type, status, last_ddl_time
from dba_objects
where owner = 'NFE_OWNER'
  and object_name in ('PKG_NFE_MIGRATION', 'PKG_NFE_WORKER',
                      'PKG_NFE_EXCEPTION_MONITOR')
order by object_name, object_type;

prompt === END TEQ PRESERVATION BASELINE ===
spool off
prompt PASS: read-only TEQ preservation baseline captured.
