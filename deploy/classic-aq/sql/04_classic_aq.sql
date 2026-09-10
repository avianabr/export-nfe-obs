declare
 l_count number;
 l_retries number;
begin
 select count(*) into l_count from user_queue_tables where queue_table='NFE_CLASSIC_AQ_QT';
 if l_count=0 then dbms_aqadm.create_queue_table(queue_table=>'NFE_CLASSIC_AQ_QT',queue_payload_type=>'RAW',multiple_consumers=>false,compatible=>'10.0.0'); end if;
 select count(*) into l_count from user_queues where name='NFE_CLASSIC_AQ_Q';
 if l_count=0 then
   dbms_aqadm.create_queue(queue_name=>'NFE_CLASSIC_AQ_Q',queue_table=>'NFE_CLASSIC_AQ_QT',max_retries=>3,retry_delay=>60);
   dbms_aqadm.start_queue(queue_name=>'NFE_CLASSIC_AQ_Q');
 else
   select max_retries into l_retries from user_queues where name='NFE_CLASSIC_AQ_Q';
   if l_retries<>3 then raise_application_error(-20870,'Classic AQ queue exists with an incompatible retry policy; no change was made.'); end if;
 end if;
 select count(*) into l_count from user_queues where name='NFE_CLASSIC_AQ_EX_Q';
 if l_count=0 then dbms_aqadm.create_queue(queue_name=>'NFE_CLASSIC_AQ_EX_Q',queue_table=>'NFE_CLASSIC_AQ_QT'); dbms_aqadm.start_queue(queue_name=>'NFE_CLASSIC_AQ_EX_Q'); end if;
end;
/
