-- Run as NFE_OWNER. Creates four isolated 1,000-document cohorts for classic
-- AQ benchmark rounds. It copies one existing non-null PoC XML into synthetic
-- rows only; it never changes source rows or purge state.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_xml clob;
  l_emission timestamp(6) with time zone;
  l_inserted pls_integer := 0;
  l_key varchar2(44);
begin
  select xml_clob, data_emissao into l_xml, l_emission
    from poc_nfe_document
   where xml_clob is not null
   fetch first 1 row only;

  for l_cohort in 1 .. 4 loop
    for l_row in 1 .. 1000 loop
      l_key := rpad('AQBENCH' || lpad(l_cohort, 2, '0') || lpad(l_row, 6, '0'), 44, '0');
      begin
        insert into poc_nfe_document (
          chave_nfe, emitente_cnpj, destinatario_cnpj, data_emissao, situacao, xml_clob)
        values (l_key, '00000000000000', '00000000000000', l_emission,
                'AUTORIZADA', l_xml);
        l_inserted := l_inserted + 1;
      exception
        when dup_val_on_index then null;
      end;
    end loop;
  end loop;
  commit;
  dbms_output.put_line('PASS: classic AQ benchmark synthetic rows inserted=' || l_inserted || '.');
end;
/
