-- Run as NFE_OWNER after the reconciliation package is deployed.
-- This is the sole API allowed to clear source XML.  It intentionally has no
-- scheduler entry point; every purge invocation is an explicit admin action.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

create or replace package pkg_nfe_purge_admin authid definer as
  procedure approve_batch(
    p_batch_id     in nfe_migration_batch.batch_id%type,
    p_comment      in varchar2,
    p_evidence_ref in varchar2);

  procedure purge_batch_chunk(
    p_batch_id      in nfe_migration_batch.batch_id%type,
    p_chunk_size    in pls_integer,
    p_purged_count  out pls_integer);

  procedure reconcile_and_close_purge(
    p_batch_id in nfe_migration_batch.batch_id%type,
    p_closed   out boolean);
end pkg_nfe_purge_admin;
/

create or replace package body pkg_nfe_purge_admin as
  c_credential_name constant varchar2(128) := 'NFE_OBJECT_STORAGE_S3_CRED';

  procedure require_approved_batch(
    p_batch_id in nfe_migration_batch.batch_id%type,
    p_for_purge in boolean) is
    l_status nfe_migration_batch.status%type;
    l_reconciliation_status nfe_migration_batch.reconciliation_status%type;
    l_approved_by nfe_migration_batch.approved_by%type;
    l_approved_at nfe_migration_batch.approved_at%type;
    l_comment nfe_migration_batch.approval_comment%type;
    l_evidence nfe_migration_batch.approval_evidence_ref%type;
    l_last_run_status nfe_reconciliation_run.status%type;
  begin
    select status, reconciliation_status, approved_by, approved_at,
           approval_comment, approval_evidence_ref
      into l_status, l_reconciliation_status, l_approved_by, l_approved_at,
           l_comment, l_evidence
      from nfe_migration_batch
     where batch_id = p_batch_id
       for update;

    select status into l_last_run_status
      from (
        select status from nfe_reconciliation_run
         where batch_id = p_batch_id
         order by reconciliation_id desc)
     where rownum = 1;

    if l_reconciliation_status <> 'PASSED' or l_last_run_status <> 'PASSED'
       or l_approved_by is null or l_approved_at is null or l_comment is null
       or l_evidence is null then
      raise_application_error(-20140,
        'Batch has not retained a passed reconciliation and complete approval evidence.');
    end if;

    if (not p_for_purge and l_status <> 'READY_FOR_APPROVAL')
       or (p_for_purge and l_status not in ('APPROVED_FOR_PURGE', 'PURGING')) then
      raise_application_error(-20141, 'Batch is not in an eligible administrative state.');
    end if;
  exception
    when no_data_found then
      raise_application_error(-20142, 'Batch has no reconciliation evidence.');
  end require_approved_batch;

  procedure approve_batch(
    p_batch_id     in nfe_migration_batch.batch_id%type,
    p_comment      in varchar2,
    p_evidence_ref in varchar2) is
    l_actor varchar2(128) := sys_context('USERENV', 'SESSION_USER');
    l_reconciliation_status nfe_migration_batch.reconciliation_status%type;
    l_last_run_status nfe_reconciliation_run.status%type;
  begin
    if trim(p_comment) is null or trim(p_evidence_ref) is null then
      raise_application_error(-20143, 'Approval comment and evidence reference are required.');
    end if;

    -- Locks the batch before revalidating the latest reconciliation result.
    select reconciliation_status into l_reconciliation_status
      from nfe_migration_batch
     where batch_id = p_batch_id and status = 'READY_FOR_APPROVAL'
       for update;
    select status into l_last_run_status
      from (select status from nfe_reconciliation_run where batch_id = p_batch_id order by reconciliation_id desc)
     where rownum = 1;
    if l_reconciliation_status <> 'PASSED' or l_last_run_status <> 'PASSED' then
      raise_application_error(-20140, 'Batch is not reconciled for purge approval.');
    end if;

    update nfe_migration_batch
       set status = 'APPROVED_FOR_PURGE', approved_by = l_actor,
           approved_at = systimestamp, approval_comment = trim(p_comment),
           approval_evidence_ref = trim(p_evidence_ref)
     where batch_id = p_batch_id;
    pkg_nfe_audit.log_event(
      p_actor_type => 'USER', p_event_type => 'PURGE_APPROVED',
      p_batch_id => p_batch_id, p_from_status => 'READY_FOR_APPROVAL',
      p_to_status => 'APPROVED_FOR_PURGE',
      p_details_json => '{"evidenceRef":"' || replace(trim(p_evidence_ref), '"', '\\"') || '"}');
  exception
    when no_data_found then
      raise_application_error(-20141, 'Batch is not ready for purge approval.');
  end approve_batch;

  procedure purge_batch_chunk(
    p_batch_id     in nfe_migration_batch.batch_id%type,
    p_chunk_size   in pls_integer,
    p_purged_count out pls_integer) is
    l_from_status nfe_migration_batch.status%type;
  begin
    if p_chunk_size is null or p_chunk_size < 1 then
      raise_application_error(-20144, 'Purge chunk size must be positive.');
    end if;
    require_approved_batch(p_batch_id, true);
    select status into l_from_status from nfe_migration_batch where batch_id = p_batch_id for update;
    if l_from_status = 'APPROVED_FOR_PURGE' then
      update nfe_migration_batch set status = 'PURGING', purge_started_at = systimestamp
       where batch_id = p_batch_id;
    end if;

    p_purged_count := 0;
    for r in (
      select i.control_id, i.nfe_id
        from nfe_migration_item i
        join poc_nfe_document d on d.nfe_id = i.nfe_id
       where i.batch_id = p_batch_id and i.status = 'VERIFIED'
         and d.xml_clob is not null
       order by i.control_id
       for update of i.status, d.xml_clob) loop
      exit when p_purged_count = p_chunk_size;
      update poc_nfe_document set xml_clob = null where nfe_id = r.nfe_id;
      update nfe_migration_item set status = 'PURGED', purged_at = systimestamp
       where control_id = r.control_id;
      pkg_nfe_audit.log_event(
        p_actor_type => 'USER', p_event_type => 'SOURCE_XML_PURGED',
        p_batch_id => p_batch_id, p_control_id => r.control_id,
        p_from_status => 'VERIFIED', p_to_status => 'PURGED',
        p_details_json => '{"sourceContentCleared":true}');
      p_purged_count := p_purged_count + 1;
    end loop;
    update nfe_migration_batch set purged_count = purged_count + p_purged_count
     where batch_id = p_batch_id;
  end purge_batch_chunk;

  procedure reconcile_and_close_purge(
    p_batch_id in nfe_migration_batch.batch_id%type,
    p_closed out boolean) is
    l_total number; l_purged number; l_present_clob number; l_bad_object number := 0;
    l_approval_events number; l_purge_events number;
    l_blob blob; l_size number; l_hash varchar2(64);
  begin
    require_approved_batch(p_batch_id, true);
    select count(*),
           sum(case when i.status = 'PURGED' then 1 else 0 end),
           sum(case when d.xml_clob is not null then 1 else 0 end)
      into l_total, l_purged, l_present_clob
     from nfe_migration_item i join poc_nfe_document d on d.nfe_id = i.nfe_id
     where i.batch_id = p_batch_id;
    select count(case when event_type = 'PURGE_APPROVED' then 1 end),
           count(case when event_type = 'SOURCE_XML_PURGED' then 1 end)
      into l_approval_events, l_purge_events
      from nfe_migration_audit
     where batch_id = p_batch_id;

    for r in (select object_uri, object_size_bytes, object_sha256
                from nfe_migration_item where batch_id = p_batch_id and status = 'PURGED') loop
      begin
        l_blob := dbms_cloud.get_object(c_credential_name, r.object_uri);
        l_size := dbms_lob.getlength(l_blob);
        l_hash := rawtohex(dbms_crypto.hash(l_blob, dbms_crypto.hash_sh256));
        if l_size <> r.object_size_bytes or l_hash <> r.object_sha256 then l_bad_object := l_bad_object + 1; end if;
        pkg_nfe_transfer.free_temporary_blob(l_blob);
      exception when others then
        pkg_nfe_transfer.free_temporary_blob(l_blob); l_bad_object := l_bad_object + 1;
      end;
    end loop;

    p_closed := l_total > 0 and l_total = l_purged and l_present_clob = 0
      and l_bad_object = 0 and l_approval_events > 0 and l_purge_events = l_purged;
    if p_closed then
      update nfe_migration_batch set status = 'PURGED', purged_at = systimestamp
       where batch_id = p_batch_id;
      pkg_nfe_audit.log_event('USER', 'PURGE_RECONCILED', p_batch_id, null,
        'PURGING', 'PURGED', null, '{"postPurgePassed":true}');
    else
      update nfe_migration_batch set status = 'BLOCKED', reconciliation_status = 'FAILED',
        last_error = 'Post-purge reconciliation found source or object discrepancies.'
       where batch_id = p_batch_id;
      pkg_nfe_audit.log_event('USER', 'PURGE_RECONCILIATION_FAILED', p_batch_id, null,
        'PURGING', 'BLOCKED', null, '{"postPurgePassed":false}');
    end if;
  end reconcile_and_close_purge;
end pkg_nfe_purge_admin;
/

prompt PASS: segregated administrative approval and manual-purge package created.
