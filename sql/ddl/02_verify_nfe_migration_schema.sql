-- Run as NFE_OWNER after 01_create_nfe_migration_schema.sql.
-- Read-only verification of the required tables, constraints and indexes.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_missing varchar2(4000);

  procedure require_object(p_name varchar2, p_type varchar2) is
    l_count pls_integer;
  begin
    select count(*) into l_count
      from user_objects
     where object_name = p_name
       and object_type = p_type
       and status = 'VALID';
    if l_count = 0 then
      l_missing := l_missing || chr(10) || ' - ' || p_name || ' (' || p_type || ')';
    end if;
  end;

  procedure require_constraint(p_name varchar2) is
    l_count pls_integer;
  begin
    select count(*) into l_count
      from user_constraints
     where constraint_name = p_name
       and status = 'ENABLED';
    if l_count = 0 then
      l_missing := l_missing || chr(10) || ' - constraint ' || p_name;
    end if;
  end;
begin
  require_object('POC_NFE_DOCUMENT', 'TABLE');
  require_object('NFE_MIGRATION_BATCH', 'TABLE');
  require_object('NFE_MIGRATION_ITEM', 'TABLE');
  require_object('NFE_MIGRATION_AUDIT', 'TABLE');
  require_object('NFE_RECONCILIATION_RUN', 'TABLE');
  require_object('NFE_MIGRATION_CONFIG', 'TABLE');
  require_object('TRG_NFE_ITEM_STATUS_TRANSITION', 'TRIGGER');
  require_object('TRG_NFE_BATCH_STATUS_TRANSITION', 'TRIGGER');
  require_object('TRG_NFE_AUDIT_APPEND_ONLY', 'TRIGGER');
  require_constraint('UK_NFE_MIGRATION_ITEM_NFE');
  require_constraint('FK_NFE_MIGRATION_ITEM_BATCH');
  require_constraint('FK_NFE_MIGRATION_ITEM_NFE');

  if l_missing is not null then
    raise_application_error(-20020, 'Schema verification failed:' || l_missing);
  end if;

  dbms_output.put_line('PASS: tables, state constraints, foreign keys and append-only audit trigger are present.');
end;
/

select config_id, pipeline_paused, max_inflight_messages, enqueue_chunk_size,
       worker_count, worker_idle_seconds, max_worker_run_minutes
  from nfe_migration_config;
