-- Run as NFE_OWNER in PDB_POCRT_02.
-- Inserts an idempotent, synthetic non-fiscal dataset for the PoC only.
-- It never updates or deletes existing rows. The 44-digit keys begin with the
-- reserved test prefix 000020260904 and must never be used for real NF-es.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  c_document_count constant pls_integer := 100;
  c_key_prefix     constant varchar2(12) := '000020260904';
  l_xml            clob;
  l_key            varchar2(44);
  l_target_chars   pls_integer;
  l_exists         pls_integer;
  l_inserted       pls_integer := 0;
  l_skipped        pls_integer := 0;

  procedure append_text(p_text varchar2) is
  begin
    dbms_lob.writeappend(l_xml, length(p_text), p_text);
  end;

  procedure build_xml(p_key varchar2, p_document_number pls_integer,
                      p_target_chars pls_integer) is
    l_remaining pls_integer;
  begin
    dbms_lob.createtemporary(l_xml, cache => true, dur => dbms_lob.call);
    append_text('<?xml version="1.0" encoding="UTF-8"?>');
    append_text('<NFe><infNFe Id="NFe' || p_key || '" versao="4.00">');
    append_text('<ide><cNF>' || lpad(p_document_number, 8, '0') ||
                '</cNF><natOp>VENDA TESTE POC</natOp></ide>');
    append_text('<emit><xNome>EMITENTE SINTETICO ACAO</xNome></emit>');
    append_text('<dest><xNome>DESTINATARIO SINTETICO CORACAO</xNome></dest>');
    append_text('<obsCont xCampo="POC">conteudo sintetico com acentuacao: acao, coracao, nacao.</obsCont>');
    append_text('<det nItem="1"><prod><xProd>XML POC</xProd><infAdProd>');

    while dbms_lob.getlength(l_xml) < p_target_chars loop
      l_remaining := least(32000, p_target_chars - dbms_lob.getlength(l_xml));
      append_text(rpad('x', l_remaining, 'x'));
    end loop;

    append_text('</infAdProd></prod></det></infNFe></NFe>');
  end;
begin
  select count(*)
    into l_exists
    from user_tables
   where table_name = 'POC_NFE_DOCUMENT';

  if l_exists = 0 then
    raise_application_error(-20100,
      'POC_NFE_DOCUMENT does not exist. Deploy sql/ddl/01_create_nfe_migration_schema.sql first.');
  end if;

  for l_document_number in 1 .. c_document_count loop
    l_key := c_key_prefix || lpad(l_document_number, 32, '0');
    l_target_chars := case
      when l_document_number <= 60 then 2048
      when l_document_number <= 90 then 20000
      else 200000
    end;

    select count(*)
      into l_exists
      from poc_nfe_document
     where chave_nfe = l_key;

    if l_exists = 0 then
      build_xml(l_key, l_document_number, l_target_chars);

      insert into poc_nfe_document (
        chave_nfe, emitente_cnpj, destinatario_cnpj, data_emissao,
        situacao, xml_clob)
      values (
        l_key,
        lpad(to_char(10000000000000 + l_document_number), 14, '0'),
        lpad(to_char(20000000000000 + l_document_number), 14, '0'),
        cast(add_months(trunc(sysdate, 'MM'), -mod(l_document_number, 18) - 1)
             + mod(l_document_number, 27) as timestamp) at time zone 'UTC',
        case
          when mod(l_document_number, 10) = 0 then 'CANCELADA'
          when mod(l_document_number, 7) = 0 then 'DENEGADA'
          else 'AUTORIZADA'
        end,
        l_xml);

      dbms_lob.freetemporary(l_xml);
      l_inserted := l_inserted + 1;
    else
      l_skipped := l_skipped + 1;
    end if;
  end loop;

  commit;
  dbms_output.put_line('PASS: synthetic PoC dataset committed. Inserted=' ||
                       l_inserted || ', already present=' || l_skipped || '.');
exception
  when others then
    if dbms_lob.istemporary(l_xml) = 1 then
      dbms_lob.freetemporary(l_xml);
    end if;
    rollback;
    raise;
end;
/
