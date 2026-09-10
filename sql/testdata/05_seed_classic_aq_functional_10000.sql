-- Explicit opt-in test harness. Run only as NFE_OWNER in an isolated PDB.
-- This script is not part of deploy/classic-aq and is never called by any
-- deployment entry point. It inserts 10,000 synthetic, authorized NF-es.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  c_document_count constant pls_integer := 10000;
  l_existing_count  pls_integer;
  l_inserted_count  pls_integer;
begin
  select count(*) into l_existing_count from poc_nfe_document;
  if l_existing_count <> 0 then
    raise_application_error(-20880,
      'POC_NFE_DOCUMENT is not empty; synthetic test data was not inserted.');
  end if;

  insert into poc_nfe_document (
    chave_nfe, emitente_cnpj, destinatario_cnpj, data_emissao, situacao, xml_clob)
  select lpad(to_char(level, 'FM9999999990'), 44, '0'),
         lpad(to_char(10000000000000 + level), 14, '0'),
         lpad(to_char(20000000000000 + level), 14, '0'),
         cast(trunc(sysdate) - mod(level, 365) as timestamp) at time zone 'UTC',
         'AUTORIZADA',
         to_clob('<?xml version="1.0" encoding="UTF-8"?><NFe><infNFe Id="NFe') ||
         lpad(to_char(level, 'FM9999999990'), 44, '0') ||
         to_clob('" versao="4.00"><ide><cNF>') ||
         lpad(to_char(level), 8, '0') ||
         to_clob('</cNF><natOp>TESTE FUNCIONAL CLASSIC AQ</natOp></ide>' ||
                 '<emit><xNome>EMITENTE SINTETICO</xNome></emit>' ||
                 '<dest><xNome>DESTINATARIO SINTETICO</xNome></dest>' ||
                 '<det nItem="1"><prod><xProd>NF-E SINTETICA</xProd></prod></det>' ||
                 '</infNFe></NFe>')
    from dual
  connect by level <= c_document_count;

  l_inserted_count := sql%rowcount;
  commit;
  dbms_output.put_line('PASS: ' || l_inserted_count ||
                       ' synthetic authorized NF-es inserted for isolated testing.');
exception
  when others then
    rollback;
    raise;
end;
/
