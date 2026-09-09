-- Run as NFE_OWNER after the base schema is deployed.
-- The package deliberately owns temporary-LOB cleanup for integrity inspection.
-- A worker that needs the BLOB for PUT_OBJECT must call free_temporary_blob
-- in both its success and exception paths.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

create or replace package pkg_nfe_transfer authid definer as
  procedure clob_to_utf8_blob(
    p_clob in clob,
    p_blob in out nocopy blob);

  procedure free_temporary_blob(
    p_blob in out nocopy blob);

  procedure get_source_integrity(
    p_nfe_id     in poc_nfe_document.nfe_id%type,
    p_byte_size  out number,
    p_sha256     out varchar2);
end pkg_nfe_transfer;
/

create or replace package body pkg_nfe_transfer as
  procedure free_temporary_blob(
    p_blob in out nocopy blob) is
  begin
    if p_blob is not null and dbms_lob.istemporary(p_blob) = 1 then
      dbms_lob.freetemporary(p_blob);
    end if;
    p_blob := null;
  end free_temporary_blob;

  procedure clob_to_utf8_blob(
    p_clob in clob,
    p_blob in out nocopy blob) is
    l_destination_offset integer := 1;
    l_source_offset      integer := 1;
    l_language_context   integer := dbms_lob.default_lang_ctx;
    l_warning            integer;
  begin
    if p_clob is null then
      raise_application_error(-20050, 'Source XML CLOB is required.');
    end if;

    free_temporary_blob(p_blob);
    dbms_lob.createtemporary(p_blob, cache => true, dur => dbms_lob.call);
    dbms_lob.converttoblob(
      dest_lob     => p_blob,
      src_clob     => p_clob,
      amount       => dbms_lob.lobmaxsize,
      dest_offset  => l_destination_offset,
      src_offset   => l_source_offset,
      blob_csid    => nls_charset_id('AL32UTF8'),
      lang_context => l_language_context,
      warning      => l_warning);

    if l_warning <> dbms_lob.no_warning then
      free_temporary_blob(p_blob);
      raise_application_error(-20051,
        'Warning converting source XML CLOB to AL32UTF8 BLOB: ' || l_warning);
    end if;
  exception
    when others then
      free_temporary_blob(p_blob);
      raise;
  end clob_to_utf8_blob;

  procedure get_source_integrity(
    p_nfe_id     in poc_nfe_document.nfe_id%type,
    p_byte_size  out number,
    p_sha256     out varchar2) is
    l_xml  clob;
    l_blob blob;
  begin
    select xml_clob into l_xml
      from poc_nfe_document
     where nfe_id = p_nfe_id;

    clob_to_utf8_blob(l_xml, l_blob);
    p_byte_size := dbms_lob.getlength(l_blob);
    p_sha256 := rawtohex(dbms_crypto.hash(l_blob, dbms_crypto.hash_sh256));
    free_temporary_blob(l_blob);
  exception
    when others then
      free_temporary_blob(l_blob);
      raise;
  end get_source_integrity;
end pkg_nfe_transfer;
/

prompt PASS: UTF-8 conversion and source-integrity package created.
