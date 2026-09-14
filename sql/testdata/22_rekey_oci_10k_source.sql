-- Rekeys only the isolated OCI 10k source after a global OBJECT_KEY collision.
-- Run as NFE_OWNER before rerunning 09_run_classic_aq_scale_10000_5_workers.sql.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
declare l_count number; l_controlled number; begin
  select count(*) into l_count from poc_nfe_oci_10k;
  select count(*) into l_controlled from nfe_migration_item i join poc_nfe_oci_10k d on d.nfe_id=i.nfe_id;
  if l_count<>10000 or l_controlled<>0 then raise_application_error(-20971,'OCI 10k source must have 10000 uncontrolled rows.');end if;
  update poc_nfe_oci_10k set chave_nfe='9'||substr(chave_nfe,2);
  commit;dbms_output.put_line('PASS: OCI 10k source keys rekeyed with 9 prefix.');
end;
/
