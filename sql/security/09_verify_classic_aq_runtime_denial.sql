-- Run as NFE_MIGRATION_RUNTIME after security/08_grant_classic_aq_privileges.sql.
-- This script never commits an AQ message. It verifies both catalog policy and
-- a denied direct enqueue, while retaining the prior XML/purge isolation check.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_count   pls_integer;
  l_denied  boolean := false;
  l_msgid   raw(16);
  l_payload raw(2000) := utl_raw.cast_to_raw('UNAUTHORIZED-AQ-PROBE');
  l_enq     dbms_aq.enqueue_options_t;
  l_props   dbms_aq.message_properties_t;
begin
  select count(*) into l_count
    from user_tab_privs_recd
   where owner = 'NFE_OWNER'
     and table_name in ('NFE_CLASSIC_AQ_Q', 'NFE_CLASSIC_AQ_EX_Q')
     and privilege in ('ENQUEUE', 'DEQUEUE', 'READ', 'ALL');
  if l_count <> 0 then
    raise_application_error(-20172,
      'FAIL: runtime identity received a direct classic AQ queue privilege.');
  end if;

  begin
    l_enq.visibility := dbms_aq.on_commit;
    l_props.correlation := 'UNAUTHORIZED-AQ-PROBE';
    dbms_aq.enqueue('NFE_OWNER.NFE_CLASSIC_AQ_Q', l_enq, l_props, l_payload, l_msgid);
    rollback;
    raise_application_error(-20173,
      'FAIL: runtime identity unexpectedly enqueued directly to classic AQ.');
  exception
    when others then
      if sqlcode = -20173 then
        raise;
      end if;
      rollback;
      l_denied := true;
      dbms_output.put_line('Direct classic AQ enqueue denied with ORA-' || to_char(abs(sqlcode)) || '.');
  end;

  if l_denied then
    dbms_output.put_line('PASS: runtime cannot access classic AQ directly.');
  end if;
end;
/

@@07_verify_runtime_denials.sql
