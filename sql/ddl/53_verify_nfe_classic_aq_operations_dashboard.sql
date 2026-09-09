-- Run as NFE_OWNER after ddl/52_create_nfe_classic_aq_operations_dashboard.sql.
-- Read-only validation of classic-AQ observability. No payload is selected.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_views        pls_integer;
  l_classic_rows pls_integer;
  l_audit_rows   pls_integer;
  l_bad_columns  pls_integer;
begin
  select count(*) into l_views
    from user_views
   where view_name in ('V_NFE_CLASSIC_AQ_BATCH_STATUS',
                       'V_NFE_CLASSIC_AQ_QUEUE_BACKLOG',
                       'V_NFE_CLASSIC_AQ_RECONCILIATION',
                       'V_NFE_CLASSIC_AQ_AUDIT');
  if l_views <> 4 then
    raise_application_error(-20290, 'Classic AQ operational views are incomplete.');
  end if;
  select count(*) into l_classic_rows from v_nfe_classic_aq_batch_status;
  if l_classic_rows = 0 then
    raise_application_error(-20291, 'No explicit classic AQ batch is visible in the dashboard.');
  end if;
  select count(*) into l_audit_rows from v_nfe_classic_aq_audit;
  if l_audit_rows = 0 then
    raise_application_error(-20292, 'Classic AQ audit trail is not visible.');
  end if;
  select count(*) into l_bad_columns
    from user_tab_columns
   where table_name in ('V_NFE_CLASSIC_AQ_BATCH_STATUS',
                        'V_NFE_CLASSIC_AQ_QUEUE_BACKLOG',
                        'V_NFE_CLASSIC_AQ_RECONCILIATION',
                        'V_NFE_CLASSIC_AQ_AUDIT')
     and column_name in ('XML_CLOB', 'PAYLOAD', 'USER_DATA', 'CREDENTIAL', 'SECRET', 'TOKEN');
  if l_bad_columns <> 0 then
    raise_application_error(-20293,
      'Classic AQ operational views expose a prohibited data-bearing column.');
  end if;
  dbms_output.put_line('PASS: classic AQ dashboard exposes transport, backlog, retries, exceptions, reconciliation, and audit safely.');
end;
/
