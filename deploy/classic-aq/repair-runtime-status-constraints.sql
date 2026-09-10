-- Explicit one-time repair for a deployment created before the SELECTING and
-- VERIFYING intermediate runtime states were included in its CHECK clauses.
-- Run as NFE_OWNER. Only the identified status CHECK constraints are changed.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_count number;
  procedure replace_status_constraint(
    p_table_name varchar2,
    p_missing_status varchar2,
    p_constraint_name varchar2,
    p_condition varchar2
  ) is
    l_constraint_name user_constraints.constraint_name%type;
    l_count number;
  begin
    select count(*) into l_count
     from user_constraints
     where table_name=p_table_name
       and constraint_type='C'
       and upper(search_condition_vc) like '%STATUS%'
       and upper(search_condition_vc) not like '%' || p_missing_status || '%';
    if l_count=0 then
      return;
    elsif l_count<>1 then
      raise_application_error(-20881,
        'Unable to identify the legacy status constraint on ' || p_table_name || '.');
    end if;

    select constraint_name into l_constraint_name
     from user_constraints
     where table_name=p_table_name
       and constraint_type='C'
       and upper(search_condition_vc) like '%STATUS%'
       and upper(search_condition_vc) not like '%' || p_missing_status || '%';
    execute immediate 'alter table ' || p_table_name ||
                      ' drop constraint ' || l_constraint_name;
    select count(*) into l_count
      from user_constraints
     where table_name=p_table_name and constraint_name=p_constraint_name;
    if l_count=0 then
      execute immediate 'alter table ' || p_table_name ||
                        ' add constraint ' || p_constraint_name || ' check (' || p_condition || ')';
    elsif l_count<>1 then
      raise_application_error(-20884,
        'Expected one named status constraint on ' || p_table_name || '.');
    end if;
  end;
begin
  replace_status_constraint(
    'NFE_MIGRATION_BATCH', 'SELECTING', 'CK_NFE_MIGRATION_BATCH_STATUS',
    q'[status in ('CREATED','SELECTING','PROCESSING','VERIFIED','BLOCKED','CANCELLED')]');
  replace_status_constraint(
    'NFE_MIGRATION_ITEM', 'VERIFYING', 'CK_NFE_MIGRATION_ITEM_STATUS',
    q'[status in ('QUEUED','UPLOADING','UPLOADED','VERIFYING','VERIFIED','PURGED','FAILED','EXCEPTION')]');
  select count(*) into l_count
    from user_constraints
   where table_name='NFE_MIGRATION_BATCH'
     and constraint_name='CK_NFE_MIGRATION_BATCH_STATUS'
     and upper(search_condition_vc) like '%SELECTING%';
  if l_count<>1 then
    raise_application_error(-20882,'Batch status constraint was not repaired.');
  end if;
  select count(*) into l_count
    from user_constraints
   where table_name='NFE_MIGRATION_ITEM'
     and constraint_name='CK_NFE_MIGRATION_ITEM_STATUS'
     and upper(search_condition_vc) like '%VERIFYING%';
  if l_count<>1 then
    raise_application_error(-20883,'Item status constraint was not repaired.');
  end if;
  dbms_output.put_line('PASS: runtime status constraints include all intermediate states.');
end;
/
