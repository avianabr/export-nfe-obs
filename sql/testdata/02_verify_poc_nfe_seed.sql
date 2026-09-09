-- Read-only verification. Run as NFE_OWNER or SYS after the synthetic seed.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set linesize 220
set pagesize 200

select count(*) as document_count,
       sum(case when xml_clob is null then 0 else 1 end) as xml_present_count,
       min(data_emissao) as earliest_emission,
       max(data_emissao) as latest_emission
  from nfe_owner.poc_nfe_document
 where chave_nfe like '000020260904%';

select case
         when dbms_lob.getlength(xml_clob) < 5000 then 'SMALL_LT_5K_CHARS'
         when dbms_lob.getlength(xml_clob) < 50000 then 'MEDIUM_5K_TO_50K_CHARS'
         else 'LARGE_GE_50K_CHARS'
       end as xml_size_bucket,
       count(*) as document_count,
       min(dbms_lob.getlength(xml_clob)) as min_xml_characters,
       max(dbms_lob.getlength(xml_clob)) as max_xml_characters
  from nfe_owner.poc_nfe_document
 where chave_nfe like '000020260904%'
 group by case
         when dbms_lob.getlength(xml_clob) < 5000 then 'SMALL_LT_5K_CHARS'
         when dbms_lob.getlength(xml_clob) < 50000 then 'MEDIUM_5K_TO_50K_CHARS'
         else 'LARGE_GE_50K_CHARS'
       end
 order by xml_size_bucket;

select situacao, count(*) as document_count
  from nfe_owner.poc_nfe_document
 where chave_nfe like '000020260904%'
 group by situacao
 order by situacao;

exit success
