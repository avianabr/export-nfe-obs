-- Read-only baseline for the NF-e migration PoC.
-- Run as SYS in PDB_POCRT_02, before a representative migration batch.
-- It does not access XML content and performs no DDL, DML, queue action, or
-- Object Storage operation.

whenever oserror exit failure rollback
whenever sqlerror continue
set linesize 220
set pagesize 200
set long 20000
set serveroutput on size unlimited

prompt ================================================================
prompt 1. Database and collection timestamp
prompt ================================================================

select systimestamp as captured_at,
       sys_context('USERENV', 'CON_NAME') as container_name
  from dual;

select banner_full
  from v$version
 where banner_full is not null;

prompt ================================================================
prompt 2. PoC source volume and temporal distribution
prompt ================================================================

select count(*) as document_count,
       sum(case when xml_clob is null then 0 else 1 end) as xml_present_count,
       sum(case when xml_clob is null then 0 else dbms_lob.getlength(xml_clob) end)
         as xml_characters,
       round(avg(case when xml_clob is null then null else dbms_lob.getlength(xml_clob) end))
         as avg_xml_characters,
       max(case when xml_clob is null then null else dbms_lob.getlength(xml_clob) end)
         as max_xml_characters
  from nfe_owner.poc_nfe_document;

select trunc(cast(data_emissao as date), 'MM') as emission_month,
       count(*) as document_count,
       sum(case when xml_clob is null then 0 else 1 end) as xml_present_count,
       round(avg(case when xml_clob is null then null else dbms_lob.getlength(xml_clob) end))
         as avg_xml_characters,
       max(case when xml_clob is null then null else dbms_lob.getlength(xml_clob) end)
         as max_xml_characters
  from nfe_owner.poc_nfe_document
 group by trunc(cast(data_emissao as date), 'MM')
 order by emission_month;

select situacao,
       count(*) as document_count,
       sum(case when xml_clob is null then 0 else 1 end) as xml_present_count
  from nfe_owner.poc_nfe_document
 group by situacao
 order by document_count desc, situacao;

prompt Note: CLOB length is reported in characters. The worker test records
prompt the authoritative AL32UTF8 byte size and SHA-256 for each document.

prompt ================================================================
prompt 3. Instance pressure baseline
prompt ================================================================

select metric_name, value, metric_unit, begin_time, end_time
  from v$sysmetric
 where group_id = 2
   and metric_name in ('Host CPU Utilization (%)', 'CPU Usage Per Sec',
                       'Physical Read Total Bytes Per Sec',
                       'Physical Write Total Bytes Per Sec',
                       'Redo Generated Per Sec', 'Redo Writes Per Sec')
 order by metric_name;

select name, value
  from v$sysstat
 where name in ('redo size', 'redo writes', 'physical read total bytes',
                'physical write total bytes', 'CPU used by this session')
 order by name;

select begin_time, end_time, txncount, undoblks, maxquerylen,
       tuned_undoretention
  from v$undostat
 order by end_time desc
 fetch first 6 rows only;

select pool, name, bytes
  from v$sgastat
 where pool = 'streams pool'
 order by name;

select name, value
  from v$parameter
 where name in ('streams_pool_size', 'sga_target', 'memory_target',
                'pga_aggregate_target', 'processes', 'sessions')
 order by name;

prompt ================================================================
prompt 4. Current PoC queue and migration-control state
prompt ================================================================

select name, queue_type, max_retries, enqueue_enabled, dequeue_enabled
  from all_queues
 where owner = 'NFE_OWNER'
   and name in ('NFE_MIGRATION_Q', 'NFE_MIGRATION_EX_Q')
 order by name;

select status, count(*) as item_count
  from nfe_owner.nfe_migration_item
 group by status
 order by status;

prompt Preserve this output with the test run identifier. It is a pre-run
prompt baseline only and does not substitute for the benchmark matrix.

exit success
