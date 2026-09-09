-- Run as NFE_OWNER after ddl/39_create_nfe_classic_transport_config.sql.
-- Verifies that a new batch cannot select or use classic AQ while its global
-- gate is disabled. It creates and removes one control-only test batch.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_enabled  char(1);
  l_batch_id number;
  l_count    pls_integer;
  l_denied   boolean := false;
  l_code     varchar2(50) := 'AQCFG-DISABLED-' || substr(rawtohex(sys_guid()), 1, 16);
begin
  pkg_nfe_classic_aq_config.get_classic_aq_enabled(l_enabled);
  if l_enabled <> 'N' then
    raise_application_error(-20190,
      'Classic AQ is already enabled; this disabled-by-default test cannot run safely.');
  end if;

  insert into nfe_migration_batch (
    batch_code, status, cutoff_date, max_documents, criteria_json, created_by)
  values (
    l_code, 'CREATED', systimestamp, 1,
    '{"eligibleSituations":["AUTORIZADA"]}', sys_context('USERENV', 'SESSION_USER'))
  returning batch_id into l_batch_id;

  begin
    pkg_nfe_classic_aq_config.select_classic_aq(l_batch_id);
    raise_application_error(-20191,
      'FAIL: disabled classic AQ was selected for a new batch.');
  exception
    when others then
      if sqlcode = -20191 then
        raise;
      elsif sqlcode = -20182 then
        l_denied := true;
      else
        raise;
      end if;
  end;

  select count(*) into l_count
    from nfe_migration_batch_transport
   where batch_id = l_batch_id;
  if l_count <> 0 then
    raise_application_error(-20192,
      'FAIL: a disabled classic AQ transport selection was persisted.');
  end if;

  delete from nfe_migration_batch where batch_id = l_batch_id;
  commit;

  if l_denied then
    dbms_output.put_line('PASS: classic AQ is disabled by default; new batch has no classic AQ selection.');
  end if;
exception
  when others then
    rollback;
    if l_batch_id is not null then
      delete from nfe_migration_batch where batch_id = l_batch_id;
      commit;
    end if;
    raise;
end;
/
