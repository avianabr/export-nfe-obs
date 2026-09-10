-- Run as NFE_OWNER once per retry attempt, with at least 65 seconds between
-- attempts because NFE_CLASSIC_AQ_Q has RETRY_DELAY=60.
set serveroutput on size unlimited
declare
  l_outcome varchar2(10) := 'NONE';
begin
  pkg_nfe_classic_aq_runtime.set_enabled('Y');
  commit;
  begin
    pkg_nfe_classic_aq_runtime.process_one;
    l_outcome := 'SUCCESS';
  exception
    when others then
      if sqlcode=-20403 then
        l_outcome := 'RETRY';
        dbms_output.put_line('EXPECTED S3 RETRY FAILURE: ' || sqlcode || ' ' || sqlerrm);
      elsif sqlcode=-25228 then
        dbms_output.put_line('NO MESSAGE AVAILABLE: wait at least 65 seconds after the last S3 retry failure.');
      else
        raise;
      end if;
  end;
  pkg_nfe_classic_aq_runtime.set_enabled('N');
  commit;
  if l_outcome='SUCCESS' then
    raise_application_error(-20886,'Retry test unexpectedly processed a message.');
  end if;
end;
/
