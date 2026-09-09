-- Run as NFE_OWNER. Creates four idempotent, equivalent 20-document cohorts.
whenever sqlerror exit failure rollback
set serveroutput on size unlimited
declare
  l_inserted number := 0;
begin
  for c in 1..4 loop
    for r in (select nfe_id,xml_clob,data_emissao from poc_nfe_document
               where chave_nfe like '000020260904%' order by nfe_id fetch first 20 rows only) loop
      declare l_key varchar2(44):='000020260908'||lpad(c,2,'0')||lpad(r.nfe_id,30,'0'); l_exists number; begin
        select count(*) into l_exists from poc_nfe_document where chave_nfe=l_key;
        if l_exists=0 then
          insert into poc_nfe_document(chave_nfe,emitente_cnpj,destinatario_cnpj,data_emissao,situacao,xml_clob)
          values(l_key,'00000000000000','00000000000000',r.data_emissao,'AUTORIZADA',r.xml_clob);
          l_inserted:=l_inserted+1;
        end if;
      end;
    end loop;
  end loop;
  commit; dbms_output.put_line('PASS: benchmark cohorts inserted='||l_inserted||'.');
end;
/
