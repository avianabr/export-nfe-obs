-- Run as NFE_OWNER after 01_create_nfe_migration_schema.sql.
-- Operational views deliberately omit POC_NFE_DOCUMENT.XML_CLOB and all
-- credential material. Audit changes are insert-only through the package.

whenever sqlerror exit failure rollback

create or replace package pkg_nfe_audit authid definer as
  procedure log_event(
    p_actor_type     in nfe_migration_audit.actor_type%type,
    p_event_type     in nfe_migration_audit.event_type%type,
    p_batch_id       in nfe_migration_audit.batch_id%type default null,
    p_control_id     in nfe_migration_audit.control_id%type default null,
    p_from_status    in nfe_migration_audit.from_status%type default null,
    p_to_status      in nfe_migration_audit.to_status%type default null,
    p_correlation_id in nfe_migration_audit.correlation_id%type default null,
    p_details_json   in clob default null);
end pkg_nfe_audit;
/

create or replace package body pkg_nfe_audit as
  procedure log_event(
    p_actor_type     in nfe_migration_audit.actor_type%type,
    p_event_type     in nfe_migration_audit.event_type%type,
    p_batch_id       in nfe_migration_audit.batch_id%type default null,
    p_control_id     in nfe_migration_audit.control_id%type default null,
    p_from_status    in nfe_migration_audit.from_status%type default null,
    p_to_status      in nfe_migration_audit.to_status%type default null,
    p_correlation_id in nfe_migration_audit.correlation_id%type default null,
    p_details_json   in clob default null) is
    l_details_prefix varchar2(4000);
  begin
    if p_actor_type is null or p_event_type is null then
      raise_application_error(-20030, 'Audit actor type and event type are required.');
    end if;

    if p_details_json is not null then
      if dbms_lob.getlength(p_details_json) > 4000 then
        raise_application_error(-20033, 'Audit details exceed the 4000-character safe diagnostic limit.');
      end if;
      l_details_prefix := lower(dbms_lob.substr(p_details_json, 4000, 1));
      if instr(l_details_prefix, 'xml') > 0
         or instr(l_details_prefix, 'credential') > 0
         or instr(l_details_prefix, 'secret') > 0
         or instr(l_details_prefix, 'token') > 0
         or instr(l_details_prefix, 'authorization') > 0 then
        raise_application_error(-20034, 'Audit details contain a prohibited sensitive-data marker.');
      end if;
    end if;

    insert into nfe_migration_audit (
      actor, actor_type, batch_id, control_id, event_type, from_status,
      to_status, correlation_id, details_json)
    values (
      sys_context('USERENV', 'SESSION_USER'), p_actor_type, p_batch_id,
      p_control_id, p_event_type, p_from_status, p_to_status,
      p_correlation_id, p_details_json);
  end log_event;
end pkg_nfe_audit;
/

create or replace view v_nfe_migration_batch_status as
select b.batch_id,
       b.batch_code,
       b.status as batch_status,
       b.cutoff_date,
       b.max_documents,
       b.selection_chunk_size,
       b.selected_count,
       b.queued_count,
       b.uploaded_count,
       b.verified_count,
       b.failed_count,
       b.exception_count,
       b.purged_count,
       b.source_bytes,
       b.object_bytes,
       b.reconciliation_status,
       b.reconciled_at,
       b.approved_by,
       b.approved_at,
       b.created_at,
       count(i.control_id) as item_count,
       count(case when i.status = 'QUEUED' then 1 end) as queued_items,
       count(case when i.status = 'UPLOADING' then 1 end) as uploading_items,
       count(case when i.status = 'UPLOADED' then 1 end) as uploaded_items,
       count(case when i.status = 'VERIFYING' then 1 end) as verifying_items,
       count(case when i.status = 'VERIFIED' then 1 end) as verified_items,
       count(case when i.status = 'FAILED' then 1 end) as failed_items,
       count(case when i.status = 'EXCEPTION' then 1 end) as exception_items,
       count(case when i.status = 'PURGED' then 1 end) as purged_items,
       min(case when i.status in ('QUEUED', 'UPLOADING', 'UPLOADED', 'VERIFYING')
                then i.enqueued_at end) as oldest_inflight_at
  from nfe_migration_batch b
  left join nfe_migration_item i on i.batch_id = b.batch_id
 group by b.batch_id, b.batch_code, b.status, b.cutoff_date, b.max_documents,
          b.selection_chunk_size, b.selected_count, b.queued_count,
          b.uploaded_count, b.verified_count, b.failed_count, b.exception_count,
          b.purged_count, b.source_bytes, b.object_bytes, b.reconciliation_status,
          b.reconciled_at, b.approved_by, b.approved_at, b.created_at;

create or replace view v_nfe_migration_item_status as
select i.control_id,
       i.batch_id,
       i.nfe_id,
       i.status,
       i.object_key,
       i.content_type,
       i.charset_name,
       i.source_size_bytes,
       i.object_size_bytes,
       i.source_sha256,
       i.object_sha256,
       i.etag,
       i.object_version_id,
       i.business_attempts,
       i.selected_at,
       i.enqueued_at,
       i.upload_started_at,
       i.uploaded_at,
       i.verified_at,
       i.purged_at,
       i.last_error_code,
       i.last_error_at,
       i.updated_at
  from nfe_migration_item i;

create or replace view v_nfe_migration_recent_audit as
select audit_id, event_at, actor, actor_type, batch_id, control_id,
       event_type, from_status, to_status, correlation_id, details_json
  from nfe_migration_audit;

prompt PASS: audit package and operational views created.
