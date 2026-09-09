-- Run as NFE_OWNER. Substitute &&cohort with 01, 02, 03 or 04.
accept cohort char prompt 'Cohort (01-04): '
declare l_batch number;l_admitted number; begin
 insert into nfe_migration_batch(batch_code,status,cutoff_date,max_documents,selection_chunk_size,criteria_json,created_by)
 values('BENCH-&&cohort','CREATED',systimestamp,20,20,'{"eligibleSituations":["AUTORIZADA"],"benchmarkKeyPrefix":"000020260908&&cohort","justification":"Comparable benchmark cohort"}',user)
 returning batch_id into l_batch;
 pkg_nfe_migration.admit_chunk(l_batch,20,l_admitted); commit;
 dbms_output.put_line('Batch='||l_batch||', admitted='||l_admitted||'.');
end;
/
