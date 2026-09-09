-- Run as NFE_OWNER after rerunning 11_create_nfe_selection_package.sql.
-- Uses a rollback-only control item to prove a previously controlled NF-e is
-- excluded; it neither enqueues messages nor persists test items.
whenever oserror exit failure rollback
set serveroutput on size unlimited
declare
  l_cursor sys_refcursor; l_nfe_id number; l_key varchar2(44); l_object_key varchar2(1024);
  l_first_nfe_id number; l_first_key varchar2(1024); l_count pls_integer := 0;
begin
  update nfe_migration_batch set status = 'SELECTING' where batch_id = 2;
  pkg_nfe_selection.open_eligible_documents(2, 5, l_cursor);
  loop
    fetch l_cursor into l_nfe_id, l_key, l_object_key; exit when l_cursor%notfound;
    l_count := l_count + 1;
    if l_count = 1 then l_first_nfe_id := l_nfe_id; l_first_key := l_object_key; end if;
  end loop;
  close l_cursor;
  if l_count = 0 or l_first_key <> pkg_nfe_selection.derive_object_key(l_first_nfe_id) then
    raise_application_error(-20060, 'Eligible selection or deterministic key verification failed.');
  end if;
  insert into nfe_migration_item(batch_id,nfe_id,status,object_key,object_uri)
  values(2,l_first_nfe_id,'QUEUED',l_first_key,'pending://selection-test');
  pkg_nfe_selection.open_eligible_documents(2, 5, l_cursor);
  loop
    fetch l_cursor into l_nfe_id, l_key, l_object_key; exit when l_cursor%notfound;
    if l_nfe_id = l_first_nfe_id then raise_application_error(-20061, 'Controlled NF-e was selected again.'); end if;
  end loop;
  close l_cursor;
  rollback;
  dbms_output.put_line('PASS: eligible documents have deterministic keys and controlled NF-e is excluded.');
exception when others then rollback; raise; end;
/
