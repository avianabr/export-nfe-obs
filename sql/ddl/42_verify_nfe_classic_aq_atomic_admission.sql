-- Run as NFE_OWNER after ddl/41_create_nfe_classic_aq_migration_package.sql.
-- Creates isolated synthetic source/batch evidence. It commits one classic AQ
-- admission and rolls another back. No source content is purged or uploaded.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_marker          varchar2(32) := rawtohex(sys_guid());
  l_commit_nfe_id   number;
  l_rollback_nfe_id number;
  l_commit_batch    number;
  l_rollback_batch  number;
  l_admitted        pls_integer;
  l_count           pls_integer;
  l_ready_before    pls_integer;
  l_enabled         char(1);
  l_commit_corr     varchar2(100);

  procedure create_source_and_batch(
    p_suffix in varchar2,
    p_nfe_id out number,
    p_batch_id out number) is
    l_key varchar2(44) := lpad('AQCLASSIC' || p_suffix || substr(l_marker, 1, 16), 44, '0');
  begin
    insert into poc_nfe_document (
      chave_nfe, emitente_cnpj, destinatario_cnpj, data_emissao, situacao, xml_clob)
    values (
      l_key, '00000000000000', '00000000000000', systimestamp,
      'AUTORIZADA', '<nfe><transport>classic-aq-test</transport></nfe>')
    returning nfe_id into p_nfe_id;

    insert into nfe_migration_batch (
      batch_code, status, cutoff_date, max_documents, criteria_json, created_by)
    values (
      'AQCL-' || p_suffix || '-' || substr(l_marker, 1, 16), 'CREATED',
      systimestamp + interval '1' day, 1,
      -- Restrict selection to this synthetic key. Without this criterion the
      -- admission query could correctly choose an older eligible NF-e and the
      -- test would inspect the wrong control item.
      '{"eligibleSituations":["AUTORIZADA"],"benchmarkKeyPrefix":"' ||
        substr(l_key, 1, 20) || '"}',
      sys_context('USERENV', 'SESSION_USER'))
    returning batch_id into p_batch_id;
    pkg_nfe_classic_aq_config.select_classic_aq(p_batch_id);
  end create_source_and_batch;
begin
  pkg_nfe_classic_aq_config.get_classic_aq_enabled(l_enabled);
  if l_enabled <> 'N' then
    raise_application_error(-20200,
      'Classic AQ must be disabled before this isolated atomic-admission test.');
  end if;

  pkg_nfe_classic_aq_config.set_classic_aq_enabled('Y');
  commit;

  create_source_and_batch('COMMIT', l_commit_nfe_id, l_commit_batch);
  commit;
  pkg_nfe_classic_aq_migration.admit_chunk(l_commit_batch, 1, l_admitted);
  if l_admitted <> 1 then
    raise_application_error(-20201, 'Expected one committed classic AQ admission.');
  end if;
  commit;

  select 'NFE-CLASSIC-' || control_id into l_commit_corr
    from nfe_migration_item
   where batch_id = l_commit_batch
     and nfe_id = l_commit_nfe_id
     and status = 'QUEUED';
  select count(*) into l_count
    from aq$nfe_classic_aq_qt
   where corr_id = l_commit_corr
     and msg_state = 'READY';
  if l_count <> 1 then
    raise_application_error(-20202,
      'Committed item does not have exactly one visible classic AQ message.');
  end if;
  select count(*) into l_ready_before
    from aq$nfe_classic_aq_qt
   where msg_state = 'READY';

  create_source_and_batch('ROLLBACK', l_rollback_nfe_id, l_rollback_batch);
  commit;
  pkg_nfe_classic_aq_migration.admit_chunk(l_rollback_batch, 1, l_admitted);
  if l_admitted <> 1 then
    raise_application_error(-20203, 'Expected one rollback-path classic AQ admission.');
  end if;
  rollback;

  select count(*) into l_count
    from nfe_migration_item
   where batch_id = l_rollback_batch
     and nfe_id = l_rollback_nfe_id;
  if l_count <> 0 then
    raise_application_error(-20204, 'Rollback left a classic AQ control item.');
  end if;
  select count(*) into l_count
    from aq$nfe_classic_aq_qt
   where msg_state = 'READY';
  if l_count <> l_ready_before then
    raise_application_error(-20205,
      'Rollback changed the count of visible classic AQ messages.');
  end if;

  pkg_nfe_classic_aq_config.set_classic_aq_enabled('N');
  commit;
  dbms_output.put_line('PASS: classic AQ admission commits item/message together and rollback exposes neither.');
  dbms_output.put_line('Committed evidence batch=' || l_commit_batch ||
                       ', rollback evidence batch=' || l_rollback_batch ||
                       ', classic AQ disabled again.');
exception
  when others then
    rollback;
    begin
      pkg_nfe_classic_aq_config.set_classic_aq_enabled('N');
      commit;
    exception when others then rollback; end;
    raise;
end;
/
