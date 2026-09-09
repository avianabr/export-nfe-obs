-- Read-only TEQ diagnostic. Run as NFE_OWNER and share the output.
-- It performs no enqueue, dequeue, DDL, DML, or rollback.

whenever oserror exit failure rollback
whenever sqlerror continue
set linesize 220
set pagesize 200
set serveroutput on size unlimited

prompt ================================================================
prompt 1. Queue and backing-table metadata
prompt ================================================================

select name, queue_table, queue_type, max_retries,
       enqueue_enabled, dequeue_enabled
  from user_queues
 where name in ('NFE_MIGRATION_Q', 'NFE_MIGRATION_EX_Q')
 order by name;

select queue_table, object_type
  from user_queue_tables
 where queue_table in (
   select queue_table
     from user_queues
    where name in ('NFE_MIGRATION_Q', 'NFE_MIGRATION_EX_Q'))
 order by queue_table;

prompt ================================================================
prompt 2. Subscriber metadata
prompt ================================================================

select queue_name, consumer_name, address, protocol, rule
  from user_queue_subscribers
 where queue_name in ('NFE_MIGRATION_Q', 'NFE_MIGRATION_EX_Q')
 order by queue_name, consumer_name;

prompt ================================================================
prompt 3. Relevant DBMS_AQ API argument metadata
prompt ================================================================

select object_name, overload, position, argument_name, in_out, data_type
  from user_arguments
 where package_name = 'DBMS_AQ'
   and object_name in ('ENQUEUE', 'DEQUEUE')
 order by object_name, overload, sequence;

prompt ================================================================
prompt 4. TEQ runtime views accessible to this schema
prompt ================================================================

select owner, object_name, object_type, status
  from all_objects
 where object_name like 'AQ$%NFE%'
 order by owner, object_name, object_type;

exit success
