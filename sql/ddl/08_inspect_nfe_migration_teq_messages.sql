-- Read-only message inspection for the isolated TEQ deployment test.
-- Run only before production workers exist: it emits the small test payloads
-- that prior validation runs enqueued. It performs no queue operation, DML,
-- DDL, or rollback.

whenever oserror exit failure rollback
whenever sqlerror continue
set linesize 240
set pagesize 200
set long 20000

prompt ================================================================
prompt 1. Transactional Event Queue table attributes
prompt ================================================================

select queue_table, object_type
  from user_queue_tables
 where queue_table = 'NFE_MIGRATION_Q';

prompt ================================================================
prompt 2. AQ view columns exposed by this database version
prompt ================================================================

select column_id, column_name, data_type, data_length
  from user_tab_columns
 where table_name = 'AQ$NFE_MIGRATION_Q'
 order by column_id;

prompt ================================================================
prompt 3. Current messages (test payloads only at this stage)
prompt ================================================================

select *
  from aq$nfe_migration_q;

exit success
