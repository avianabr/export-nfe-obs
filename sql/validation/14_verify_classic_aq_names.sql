-- Run as NFE_OWNER in PDB_POCRT_02 before creating the permanent classic AQ
-- objects. This is read-only and does not access AQ payloads.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_count pls_integer;

  procedure require_absent(p_name varchar2) is
  begin
    select count(*)
      into l_count
      from user_objects
     where object_name = p_name;

    if l_count <> 0 then
      raise_application_error(-20140,
        'Name collision: ' || p_name || ' already exists; no deployment was performed.');
    end if;

    select count(*)
      into l_count
      from user_queues
     where name = p_name;

    if l_count <> 0 then
      raise_application_error(-20141,
        'Queue collision: ' || p_name || ' already exists; no deployment was performed.');
    end if;
  end;

  procedure require_teq(p_name varchar2) is
  begin
    select count(*) into l_count from user_queues where name = p_name;
    if l_count <> 1 then
      raise_application_error(-20142,
        'Expected pre-existing TEQ queue ' || p_name || ' was not found.');
    end if;
  end;
begin
  require_teq('NFE_MIGRATION_Q');
  require_teq('NFE_MIGRATION_EX_Q');

  require_absent('NFE_CLASSIC_AQ_QT');
  require_absent('NFE_CLASSIC_AQ_Q');
  require_absent('NFE_CLASSIC_AQ_EX_Q');

  dbms_output.put_line('PASS: permanent classic AQ names are available and isolated.');
  dbms_output.put_line('Queue table=NFE_CLASSIC_AQ_QT');
  dbms_output.put_line('Normal queue=NFE_CLASSIC_AQ_Q');
  dbms_output.put_line('Exception queue=NFE_CLASSIC_AQ_EX_Q');
end;
/
