-- Isolated-test harness only; it is not part of the deployment package.
-- Run as NFE_OWNER only in an isolated PDB with an empty test schema.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on

declare
  l_count number;
  l_columns number;
begin
  select count(*) into l_count
    from user_objects
   where object_name = 'POC_NFE_DOCUMENT';

  if l_count > 0 then
    select count(*) into l_columns
      from user_tab_columns
     where table_name = 'POC_NFE_DOCUMENT'
       and column_name in ('NFE_ID', 'CHAVE_NFE', 'DATA_EMISSAO', 'SITUACAO', 'XML_CLOB');

    if l_columns <> 5 then
      raise_application_error(-20894,
        'POC_NFE_DOCUMENT already exists but does not match the required source contract; no change was made.');
    end if;

    dbms_output.put_line('PASS: existing POC_NFE_DOCUMENT satisfies the source-column contract.');
  else
    execute immediate q'[
      create table poc_nfe_document (
        nfe_id           number generated always as identity primary key,
        chave_nfe        varchar2(44) not null,
        emitente_cnpj    varchar2(14),
        destinatario_cnpj varchar2(14),
        data_emissao     timestamp with time zone not null,
        situacao         varchar2(30) not null,
        xml_clob         clob not null,
        constraint uk_poc_nfe_document_chave unique (chave_nfe)
      )]';
    dbms_output.put_line('PASS: empty POC_NFE_DOCUMENT created for the isolated PoC.');
  end if;
end;
/
