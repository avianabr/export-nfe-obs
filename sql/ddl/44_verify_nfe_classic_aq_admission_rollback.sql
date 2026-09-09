-- Run as NFE_OWNER after ddl/41_create_nfe_classic_aq_migration_package.sql.
-- Complements the committed evidence batch created by validation 42. This
-- script proves only the rollback side with a uniquely scoped synthetic batch
-- and leaves that empty batch CANCELLED as auditable evidence.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_marker       varchar2(32) := rawtohex(sys_guid());
  l_key          varchar2(44) := lpad('AQCLASSICROLLBACK' || substr(rawtohex(sys_guid()), 1, 16), 44, '0');
  l_nfe_id       number;
  l_batch_id     number;
  l_admitted     pls_integer;
  l_enabled      char(1);
  l_ready_before pls_integer;
  l_ready_after  pls_integer;
  l_item_count   pls_integer;
begin
  pkg_nfe_classic_aq_config.get_classic_aq_enabled(l_enabled);
  if l_enabled <> 'N' then
    raise_application_error(-20220,
      'Classic AQ must be disabled before the isolated rollback test.');
  end if;

  pkg_nfe_classic_aq_config.set_classic_aq_enabled('Y');
  commit;

  insert into poc_nfe_document (
    chave_nfe, emitente_cnpj, destinatario_cnpj, data_emissao, situacao, xml_clob)
  values (
    l_key, '00000000000000', '00000000000000', systimestamp,
    'AUTORIZADA', '<nfe><transport>classic-aq-rollback-test</transport></nfe>')
  returning nfe_id into l_nfe_id;
  insert into nfe_migration_batch (
    batch_code, status, cutoff_date, max_documents, criteria_json, created_by)
  values (
    'AQCL-ROLLBACK-' || substr(l_marker, 1, 16), 'CREATED',
    systimestamp + interval '1' day, 1,
    '{"eligibleSituations":["AUTORIZADA"],"benchmarkKeyPrefix":"' ||
      substr(l_key, 1, 20) || '"}',
    sys_context('USERENV', 'SESSION_USER'))
  returning batch_id into l_batch_id;
  pkg_nfe_classic_aq_config.select_classic_aq(l_batch_id);
  commit;

  select count(*) into l_ready_before
    from aq$nfe_classic_aq_qt
   where msg_state = 'READY';

  pkg_nfe_classic_aq_migration.admit_chunk(l_batch_id, 1, l_admitted);
  if l_admitted <> 1 then
    raise_application_error(-20221, 'Expected exactly one rollback-path admission.');
  end if;
  rollback;

  select count(*) into l_item_count
    from nfe_migration_item
   where batch_id = l_batch_id
     and nfe_id = l_nfe_id;
  if l_item_count <> 0 then
    raise_application_error(-20222, 'Rollback left a classic AQ control item.');
  end if;
  select count(*) into l_ready_after
    from aq$nfe_classic_aq_qt
   where msg_state = 'READY';
  if l_ready_after <> l_ready_before then
    raise_application_error(-20223, 'Rollback changed the visible classic AQ message count.');
  end if;

  update nfe_migration_batch
     set status = 'CANCELLED'
   where batch_id = l_batch_id
     and status = 'CREATED';
  pkg_nfe_audit.log_event(
    p_actor_type => 'SYSTEM',
    p_event_type => 'CLASSIC_AQ_ROLLBACK_TEST',
    p_batch_id => l_batch_id,
    p_details_json => '{"result":"ROLLED_BACK"}');
  pkg_nfe_classic_aq_config.set_classic_aq_enabled('N');
  commit;

  dbms_output.put_line('PASS: classic AQ rollback exposes neither item nor message.');
  dbms_output.put_line('Cancelled rollback evidence batch=' || l_batch_id ||
                       '; classic AQ disabled again.');
exception
  when others then
    dbms_output.put_line('ERROR STACK: ' || dbms_utility.format_error_stack);
    dbms_output.put_line('ERROR BACKTRACE: ' || dbms_utility.format_error_backtrace);
    rollback;
    begin
      pkg_nfe_classic_aq_config.set_classic_aq_enabled('N');
      commit;
    exception when others then rollback; end;
    raise;
end;
/
