-- Run as SYS (or a DBA account with SELECT_CATALOG_ROLE) in the affected PDB.
-- This collects support evidence without selecting TEQ payloads, XML source
-- content, Object Storage credentials, or authorization data.
-- SQL*Plus creates the spool file in the directory from which it is invoked.

whenever oserror exit failure rollback
set echo off feedback on heading on pagesize 200 linesize 240 long 20000 longchunksize 20000 trimspool on
set serveroutput on size unlimited

accept evidence_file char prompt 'Output file name (without extension): '
spool &&evidence_file..log

prompt === ORA-00600 / TEQ SUPPORT EVIDENCE ===
select systimestamp as collected_at_utc,
       sys_context('USERENV','DB_NAME') as db_name,
       sys_context('USERENV','CON_NAME') as container_name,
       sys_context('USERENV','INSTANCE_NAME') as instance_name,
       sys_context('USERENV','SESSION_USER') as collector
from dual;

prompt === DATABASE VERSION AND PATCH CONTEXT ===
select banner_full from v$version order by banner_full;
select instance_name, host_name, version, startup_time, status, parallel, thread#
from v$instance;
select name, open_mode, database_role, log_mode, force_logging from v$database;
select patch_id, patch_type, action, status, action_time, description
from dba_registry_sqlpatch
order by action_time desc fetch first 20 rows only;

prompt === ADR LOCATIONS ===
select name, value from v$diag_info
where name in ('Diag Trace','Diag Alert','Default Trace File','Alert Log');

prompt === RELEVANT ALERT LOG ENTRIES (LAST 24 HOURS) ===
select originating_timestamp, message_text
from v$diag_alert_ext
where originating_timestamp >= systimestamp - interval '24' hour
  and (message_text like '%ORA-00600%'
       or message_text like '%kwsdRmtDqIpc%'
       or message_text like '%24039%')
order by originating_timestamp;

prompt === INCIDENTS ===
select incident_id, create_time, problem_id, error_facility, error_number,
       error_arg1, error_arg2
from v$diag_incident
where create_time >= systimestamp - interval '24' hour
  and error_number = 600
order by create_time desc;

prompt === TEQ CONFIGURATION (NO PAYLOADS) ===
select owner, name, queue_table, queue_type, max_retries,
       enqueue_enabled, dequeue_enabled
from dba_queues
where owner = 'NFE_OWNER'
  and name in ('NFE_MIGRATION_Q','NFE_MIGRATION_EX_Q')
order by name;

select owner, queue_table, object_type, sort_order, recipients
from dba_queue_tables
where owner = 'NFE_OWNER'
  and queue_table in ('NFE_MIGRATION_Q','NFE_MIGRATION_EX_Q')
order by queue_table;

select msg_state, count(*) as message_count
from nfe_owner.aq$nfe_migration_q
group by msg_state
order by msg_state;

prompt === RETRY TEST CONTROL EVIDENCE (NO PAYLOADS OR XML) ===
select b.batch_id, b.batch_code, b.status as batch_status,
       i.control_id, i.status as item_status, rawtohex(i.aq_msgid) as aq_msgid,
       i.enqueued_at, i.last_error_code, i.last_error_at
from nfe_owner.nfe_migration_batch b
join nfe_owner.nfe_migration_item i on i.batch_id = b.batch_id
where b.batch_code like 'RETRY-%'
order by b.batch_id, i.control_id;

prompt === DEPLOYED PACKAGE STATE ===
select owner, object_name, object_type, status, last_ddl_time
from dba_objects
where owner = 'NFE_OWNER'
  and object_name in ('PKG_NFE_WORKER','PKG_NFE_MIGRATION','PKG_NFE_EXCEPTION_MONITOR')
order by object_name, object_type;

prompt === END OF EVIDENCE ===
spool off
prompt Evidence file created. Package the matching ADR incident with IPS/ADRCI before opening the Oracle Support request.
