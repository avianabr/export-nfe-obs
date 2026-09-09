-- Run as NFE_OWNER after classic AQ config, worker, exception monitor, and
-- reconciliation objects are deployed. These views expose control-plane and
-- queue metadata only: they never select AQ payloads, XML, or credentials.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback

create or replace view v_nfe_classic_aq_batch_status as
select b.batch_id,
       b.batch_code,
       b.status as batch_status,
       t.transport_mode,
       t.selected_by as transport_selected_by,
       t.selected_at as transport_selected_at,
       b.selected_count,
       b.queued_count,
       b.uploaded_count,
       b.verified_count,
       b.exception_count,
       count(i.control_id) as item_count,
       count(case when i.status = 'QUEUED' then 1 end) as queued_items,
       count(case when i.status = 'VERIFIED' then 1 end) as verified_items,
       count(case when i.status = 'EXCEPTION' then 1 end) as exception_items,
       max(q.retry_count) as max_aq_retry_count,
       count(case when q.msg_state = 'READY' then 1 end) as ready_message_count,
       min(case when q.msg_state = 'READY' then q.enq_time end) as oldest_ready_at
  from nfe_migration_batch b
  join nfe_migration_batch_transport t on t.batch_id = b.batch_id
  left join nfe_migration_item i on i.batch_id = b.batch_id
  left join aq$nfe_classic_aq_qt q on q.corr_id = 'NFE-CLASSIC-' || i.control_id
 group by b.batch_id, b.batch_code, b.status, t.transport_mode,
          t.selected_by, t.selected_at, b.selected_count, b.queued_count,
          b.uploaded_count, b.verified_count, b.exception_count;
/

create or replace view v_nfe_classic_aq_queue_backlog as
select msg_state,
       count(*) as message_count,
       min(enq_time) as oldest_enqueued_at,
       max(retry_count) as max_retry_count
  from aq$nfe_classic_aq_qt
 group by msg_state;
/

create or replace view v_nfe_classic_aq_reconciliation as
select b.batch_id,
       b.batch_code,
       b.status as batch_status,
       t.transport_mode,
       r.reconciliation_id,
       r.status as reconciliation_status,
       r.total_count,
       r.verified_count,
       r.missing_object_count,
       r.size_mismatch_count,
       r.hash_mismatch_count,
       r.failed_count,
       r.exception_count,
       r.started_at,
       r.completed_at
  from nfe_migration_batch b
  join nfe_migration_batch_transport t on t.batch_id = b.batch_id
  left join nfe_reconciliation_run r on r.batch_id = b.batch_id;
/

create or replace view v_nfe_classic_aq_audit as
select audit_id,
       event_at,
       actor,
       actor_type,
       batch_id,
       control_id,
       event_type,
       from_status,
       to_status,
       correlation_id,
       details_json
  from nfe_migration_audit
 where event_type like 'CLASSIC_AQ%';
/

prompt PASS: classic AQ operational, queue, reconciliation, and audit views created.
