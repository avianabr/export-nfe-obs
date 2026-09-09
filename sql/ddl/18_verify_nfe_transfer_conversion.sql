-- Run as NFE_OWNER after 17_create_nfe_transfer_package.sql.
-- Tests the synthetic small, medium and large XMLs without changing source data.

whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_xml          clob;
  l_blob         blob;
  l_unicode_xml  clob := to_clob('<?xml version="1.0" encoding="UTF-8"?><nfe>ação coração €</nfe>');
  l_char_size    number;
  l_byte_size_1  number;
  l_byte_size_2  number;
  l_sha256_1     varchar2(64);
  l_sha256_2     varchar2(64);
  l_unicode_size number;
  l_expected_utf8_size number := utl_raw.length(
    utl_i18n.string_to_raw('<?xml version="1.0" encoding="UTF-8"?><nfe>ação coração €</nfe>',
                           'AL32UTF8'));
  l_tested       pls_integer := 0;
begin
  for r in (
    select nfe_id from (
      select nfe_id, 1 as fixture_order
        from (
          select nfe_id
            from poc_nfe_document
           where xml_clob is not null
           order by dbms_lob.getlength(xml_clob), nfe_id
           fetch first 1 row only
        )
      union all
      select nfe_id, 2
        from (
          select nfe_id
            from poc_nfe_document
           where xml_clob is not null
             and dbms_lob.getlength(xml_clob) between 5000 and 50000
           order by nfe_id
           fetch first 1 row only
        )
      union all
      select nfe_id, 3
        from (
          select nfe_id
            from poc_nfe_document
           where xml_clob is not null
           order by dbms_lob.getlength(xml_clob) desc, nfe_id
           fetch first 1 row only
        )
    )
    order by fixture_order
  ) loop
    select xml_clob, dbms_lob.getlength(xml_clob)
      into l_xml, l_char_size
      from poc_nfe_document
     where nfe_id = r.nfe_id;

    pkg_nfe_transfer.clob_to_utf8_blob(l_xml, l_blob);
    if dbms_lob.istemporary(l_blob) <> 1 then
      raise_application_error(-20080, 'Conversion did not create a temporary BLOB.');
    end if;
    pkg_nfe_transfer.free_temporary_blob(l_blob);
    if l_blob is not null then
      raise_application_error(-20081, 'Temporary BLOB was not released.');
    end if;

    pkg_nfe_transfer.get_source_integrity(r.nfe_id, l_byte_size_1, l_sha256_1);
    pkg_nfe_transfer.get_source_integrity(r.nfe_id, l_byte_size_2, l_sha256_2);

    if l_byte_size_1 <= 0
       or l_byte_size_1 <> l_byte_size_2
       or l_sha256_1 <> l_sha256_2
       or not regexp_like(l_sha256_1, '^[0-9A-F]{64}$') then
      raise_application_error(-20082,
        'AL32UTF8 bytes or SHA-256 are not stable for NFE_ID ' || r.nfe_id || '.');
    end if;
    l_tested := l_tested + 1;
  end loop;

  pkg_nfe_transfer.clob_to_utf8_blob(l_unicode_xml, l_blob);
  l_unicode_size := dbms_lob.getlength(l_blob);
  pkg_nfe_transfer.free_temporary_blob(l_blob);
  if l_unicode_size <> l_expected_utf8_size then
    raise_application_error(-20084,
      'Explicit Unicode XML was not converted to the expected AL32UTF8 byte length.');
  end if;

  if l_tested <> 3 then
    raise_application_error(-20083,
      'Expected small, medium and large XML fixtures; found ' || l_tested || '.');
  end if;

  rollback;
  dbms_output.put_line(
    'PASS: AL32UTF8 BLOB byte size and SHA-256 are stable for small, medium and large XMLs; temporary LOBs are released.');
exception
  when others then
    pkg_nfe_transfer.free_temporary_blob(l_blob);
    rollback;
    raise;
end;
/
