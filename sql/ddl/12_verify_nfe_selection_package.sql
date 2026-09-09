-- Run as NFE_OWNER after 11_create_nfe_selection_package.sql.
-- Persists one valid, empty batch as evidence; it selects and queues nothing.

whenever oserror exit failure rollback
set serveroutput on size unlimited

declare
  l_invalid_rejected boolean := false;
  l_batch_id         nfe_migration_batch.batch_id%type;
  l_batch_code       nfe_migration_batch.batch_code%type :=
    'BATCH-VERIFY-' || substr(rawtohex(sys_guid()), 1, 24);
  l_criteria_count   pls_integer;
begin
  begin
    pkg_nfe_selection.create_batch(
      p_batch_code => 'INVALID-CUTOFF',
      p_cutoff_date => systimestamp + interval '1' day,
      p_max_documents => 1,
      p_selection_chunk_size => 1,
      p_eligible_situacoes => sys.odcivarchar2list('AUTORIZADA'),
      p_justification => 'invalid cutoff verification',
      p_batch_id => l_batch_id);
  exception
    when others then
      if sqlcode = -20051 then
        l_invalid_rejected := true;
      else
        raise;
      end if;
  end;

  pkg_nfe_selection.create_batch(
    p_batch_code => l_batch_code,
    p_cutoff_date => systimestamp - interval '30' day,
    p_max_documents => 10,
    p_selection_chunk_size => 5,
    p_eligible_situacoes => sys.odcivarchar2list('AUTORIZADA'),
    p_justification => 'Persist valid batch criteria for PoC verification.',
    p_batch_id => l_batch_id);
  commit;

  select count(*)
    into l_criteria_count
    from nfe_migration_batch
   where batch_id = l_batch_id
     and status = 'CREATED'
     and max_documents = 10
     and selection_chunk_size = 5
     and json_value(criteria_json, '$.eligibleSituations[0]') = 'AUTORIZADA'
     and json_value(criteria_json, '$.justification') =
         'Persist valid batch criteria for PoC verification.';

  if not l_invalid_rejected or l_criteria_count <> 1 then
    raise_application_error(-20057,
      'Batch validation or criteria persistence verification failed.');
  end if;

  dbms_output.put_line('PASS: invalid batch rejected; valid batch ' ||
                       l_batch_id || ' persisted with auditable criteria.');
end;
/
