-- Creates exactly 10,000 isolated OCI benchmark documents. Run as NFE_OWNER.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
declare l_count number; begin
  select count(*) into l_count from user_tables where table_name='POC_NFE_OCI_10K';
  if l_count=0 then execute immediate q'[create table poc_nfe_oci_10k (nfe_id number generated always as identity primary key,chave_nfe varchar2(44) not null unique,data_emissao timestamp with time zone not null,situacao varchar2(30) not null,xml_clob clob not null)]'; end if;
end;
/
declare l_count number; begin
  select count(*) into l_count from poc_nfe_oci_10k; if l_count<>0 then raise_application_error(-20970,'POC_NFE_OCI_10K must be empty.');end if;
  insert into poc_nfe_oci_10k(chave_nfe,data_emissao,situacao,xml_clob)
  select lpad(to_char(level),44,'0'),systimestamp-interval '1' day,'AUTORIZADA',to_clob('<NFe><infNFe Id="NFe')||lpad(to_char(level),44,'0')||to_clob('"><x>OCI 10K benchmark</x></infNFe></NFe>') from dual connect by level<=10000;
  commit;dbms_output.put_line('PASS: OCI 10K source created and seeded.');
end;
/
