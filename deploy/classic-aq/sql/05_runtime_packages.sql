-- The deployed runtime never embeds a source owner, table, or CLOB identifier.
create or replace package pkg_nfe_deploy_source authid definer as
  procedure get_document(p_source_id number, p_key out varchar2,
    p_emission_at out timestamp with time zone, p_status out varchar2,
    p_xml out nocopy clob);
  procedure find_candidate(p_cutoff timestamp with time zone, p_status varchar2,
    p_source_id out number, p_key out varchar2,
    p_emission_at out timestamp with time zone);
  procedure clear_document(p_source_id number);
end;
/

create or replace package pkg_nfe_classic_aq_monitor authid definer as
  procedure get_counts(p_queued out number, p_verified out number,
                       p_exception out number);
end;
/
create or replace package body pkg_nfe_classic_aq_monitor as
  procedure get_counts(p_queued out number, p_verified out number,
                       p_exception out number) is
  begin
    select nvl(sum(case when status='QUEUED' then 1 else 0 end),0),
           nvl(sum(case when status='VERIFIED' then 1 else 0 end),0)
      into p_queued,p_verified
      from nfe_migration_item;
    select count(*) into p_exception
      from aq$nfe_classic_aq_qt
     where msg_state='EXPIRED';
  end;
end;
/
create or replace package body pkg_nfe_deploy_source as
  procedure names(p_o out varchar2,p_t out varchar2,p_c out varchar2,p_i out varchar2,p_k out varchar2,p_d out varchar2,p_s out varchar2) is
  begin
    pkg_nfe_deploy_config.get_source(p_o,p_t,p_c,p_i,p_k,p_d,p_s);
    p_o:=dbms_assert.schema_name(p_o); p_t:=dbms_assert.simple_sql_name(p_t);
    p_c:=dbms_assert.simple_sql_name(p_c); p_i:=dbms_assert.simple_sql_name(p_i);
    p_k:=dbms_assert.simple_sql_name(p_k); p_d:=dbms_assert.simple_sql_name(p_d);
    p_s:=dbms_assert.simple_sql_name(p_s);
  end;
  procedure get_document(p_source_id number,p_key out varchar2,p_emission_at out timestamp with time zone,p_status out varchar2,p_xml out nocopy clob) is
    l_o varchar2(128);l_t varchar2(128);l_c varchar2(128);l_i varchar2(128);l_k varchar2(128);l_d varchar2(128);l_s varchar2(128);l_sql varchar2(32767);
  begin
    names(l_o,l_t,l_c,l_i,l_k,l_d,l_s);
    l_sql:='select '||l_k||',cast('||l_d||' as timestamp with time zone),'||l_s||','||l_c||' from '||l_o||'.'||l_t||' where '||l_i||'=:1';
    execute immediate l_sql into p_key,p_emission_at,p_status,p_xml using p_source_id;
  exception when no_data_found then raise_application_error(-20831,'Configured source document was not found.'); end;
  procedure find_candidate(p_cutoff timestamp with time zone,p_status varchar2,p_source_id out number,p_key out varchar2,p_emission_at out timestamp with time zone) is
    l_o varchar2(128);l_t varchar2(128);l_c varchar2(128);l_i varchar2(128);l_k varchar2(128);l_d varchar2(128);l_s varchar2(128);l_sql varchar2(32767);
  begin
    names(l_o,l_t,l_c,l_i,l_k,l_d,l_s);
    l_sql:='select d.'||l_i||',d.'||l_k||',cast(d.'||l_d||' as timestamp with time zone) from '||l_o||'.'||l_t||' d where d.'||l_c||' is not null and cast(d.'||l_d||' as timestamp with time zone)<:1 and d.'||l_s||'=:2 and not exists (select 1 from nfe_migration_item i where i.nfe_id=d.'||l_i||') order by d.'||l_d||',d.'||l_i||' fetch first 1 rows only';
    execute immediate l_sql into p_source_id,p_key,p_emission_at using p_cutoff,p_status;
  exception when no_data_found then raise_application_error(-20832,'No eligible configured source document is available.'); end;
  procedure clear_document(p_source_id number) is
    l_o varchar2(128);l_t varchar2(128);l_c varchar2(128);l_i varchar2(128);l_k varchar2(128);l_d varchar2(128);l_s varchar2(128);l_sql varchar2(32767);
  begin names(l_o,l_t,l_c,l_i,l_k,l_d,l_s);l_sql:='update '||l_o||'.'||l_t||' set '||l_c||'=null where '||l_i||'=:1';execute immediate l_sql using p_source_id;end;
end;
/

create or replace package pkg_nfe_classic_aq_runtime authid definer as
  procedure set_enabled(p_enabled char);
  function object_uri(p_object_key varchar2) return varchar2;
  procedure read_source_clob(p_source_id number,p_xml out nocopy clob);
  procedure admit_one(p_batch_id number,p_required_status varchar2,p_control_id out number);
  procedure process_one(p_correlation varchar2 default null);
  procedure run_workers(p_max_messages pls_integer default 1);
  procedure reconcile_batch(p_batch_id number,p_passed out boolean);
  procedure purge_verified_source(p_control_id number);
end;
/
create or replace package body pkg_nfe_classic_aq_runtime as
  procedure set_enabled(p_enabled char) is begin if p_enabled not in ('Y','N') then raise_application_error(-20830,'Classic AQ enabled flag must be Y or N.');end if;update nfe_classic_aq_config set classic_aq_enabled=p_enabled,updated_by=user,updated_at=systimestamp where config_id=1;end;
  function object_uri(p_object_key varchar2) return varchar2 is l_e varchar2(1000);l_b varchar2(255);l_p varchar2(512);l_c varchar2(128);l_host varchar2(1000);begin pkg_nfe_deploy_config.get_storage(l_e,l_b,l_p,l_c);l_host:=regexp_replace(rtrim(l_e,'/'),'^https://','');if lower(l_host) like lower(l_b)||'.%' then return 's3://'||l_host||'/'||trim(both '/' from l_p)||'/'||p_object_key;end if;return 's3://'||l_host||'/'||l_b||'/'||trim(both '/' from l_p)||'/'||p_object_key;end;
  procedure read_source_clob(p_source_id number,p_xml out nocopy clob) is l_k varchar2(256);l_d timestamp with time zone;l_s varchar2(128);begin pkg_nfe_deploy_source.get_document(p_source_id,l_k,l_d,l_s,p_xml);end;
  procedure admit_one(p_batch_id number,p_required_status varchar2,p_control_id out number) is
    l_gate char(1);l_batch varchar2(20);l_cutoff timestamp with time zone;l_max_documents number;l_admitted number;l_source number;l_key varchar2(256);l_date timestamp with time zone;l_obj varchar2(1024);l_payload raw(2000);l_msg raw(16);l_enq dbms_aq.enqueue_options_t;l_props dbms_aq.message_properties_t;
  begin
    select classic_aq_enabled into l_gate from nfe_classic_aq_config where config_id=1 for update;if l_gate<>'Y' then raise_application_error(-20833,'Classic AQ is disabled.');end if;
    select status,cutoff_date,max_documents into l_batch,l_cutoff,l_max_documents from nfe_migration_batch where batch_id=p_batch_id for update;if l_batch not in ('CREATED','SELECTING','PROCESSING') then raise_application_error(-20834,'Batch is not eligible for admission.');end if;select count(*) into l_admitted from nfe_migration_item where batch_id=p_batch_id;if l_admitted>=l_max_documents then raise_application_error(-20839,'Batch admission limit has already been reached.');end if;if l_batch='CREATED' then update nfe_migration_batch set status='SELECTING' where batch_id=p_batch_id;end if;
    pkg_nfe_deploy_source.find_candidate(l_cutoff,p_required_status,l_source,l_key,l_date);l_obj:=to_char(l_date at time zone 'UTC','YYYY/MM')||'/'||l_key||'.xml';
    insert into nfe_migration_item(batch_id,nfe_id,object_key,object_uri,status) values(p_batch_id,l_source,l_obj,object_uri(l_obj),'QUEUED') returning control_id into p_control_id;
    l_enq.visibility:=dbms_aq.on_commit;l_props.correlation:='NFE-CLASSIC-'||p_control_id;l_props.exception_queue:='NFE_CLASSIC_AQ_EX_Q';l_payload:=utl_raw.cast_to_raw('{"version":1,"controlId":'||p_control_id||',"sourceId":'||l_source||',"batchId":'||p_batch_id||'}');dbms_aq.enqueue('NFE_CLASSIC_AQ_Q',l_enq,l_props,l_payload,l_msg);update nfe_migration_item set aq_msgid=l_msg where control_id=p_control_id;update nfe_migration_batch set status='PROCESSING' where batch_id=p_batch_id and status='SELECTING';
  end;
  procedure process_one(p_correlation varchar2 default null) is
    l_deq dbms_aq.dequeue_options_t;l_props dbms_aq.message_properties_t;l_payload raw(2000);l_msg raw(16);l_text varchar2(32767);l_control number;l_source number;l_batch number;l_item_source number;l_key varchar2(256);l_date timestamp with time zone;l_status varchar2(128);l_xml clob;l_blob blob;l_download blob;l_e varchar2(1000);l_b varchar2(255);l_p varchar2(512);l_credential varchar2(128);l_object_key varchar2(1024);l_hash varchar2(64);l_download_hash varchar2(64);l_dest_offset integer:=1;l_src_offset integer:=1;l_langctx integer:=0;l_warning integer;
  begin
    l_deq.visibility:=dbms_aq.on_commit;l_deq.dequeue_mode:=dbms_aq.remove;l_deq.navigation:=dbms_aq.first_message;l_deq.wait:=dbms_aq.no_wait;l_deq.correlation:=p_correlation;dbms_aq.dequeue('NFE_CLASSIC_AQ_Q',l_deq,l_props,l_payload,l_msg);l_text:=utl_i18n.raw_to_char(l_payload,'AL32UTF8');select json_value(l_text,'$.controlId' returning number error on error),json_value(l_text,'$.sourceId' returning number error on error),json_value(l_text,'$.batchId' returning number error on error) into l_control,l_source,l_batch from dual;
    select nfe_id,object_key into l_item_source,l_object_key from nfe_migration_item where control_id=l_control and batch_id=l_batch and status='QUEUED' for update;if l_item_source<>l_source then raise_application_error(-20835,'Classic AQ envelope source reference differs from its control item.');end if;
    update nfe_migration_item set status='UPLOADING',object_uri=object_uri(l_object_key) where control_id=l_control;pkg_nfe_deploy_source.get_document(l_source,l_key,l_date,l_status,l_xml);pkg_nfe_deploy_config.get_storage(l_e,l_b,l_p,l_credential);dbms_lob.createtemporary(l_blob,true);dbms_lob.converttoblob(dest_lob=>l_blob,src_clob=>l_xml,amount=>dbms_lob.lobmaxsize,dest_offset=>l_dest_offset,src_offset=>l_src_offset,blob_csid=>nls_charset_id('AL32UTF8'),lang_context=>l_langctx,warning=>l_warning);if l_warning<>dbms_lob.no_warning then raise_application_error(-20838,'Source CLOB cannot be converted to UTF-8.');end if;l_hash:=rawtohex(dbms_crypto.hash(l_blob,dbms_crypto.hash_sh256));dbms_cloud.put_object(credential_name=>l_credential,object_uri=>object_uri(l_object_key),contents=>l_blob);update nfe_migration_item set status='UPLOADED',source_sha256=l_hash where control_id=l_control;update nfe_migration_item set status='VERIFYING' where control_id=l_control;l_download:=dbms_cloud.get_object(credential_name=>l_credential,object_uri=>object_uri(l_object_key));l_download_hash:=rawtohex(dbms_crypto.hash(l_download,dbms_crypto.hash_sh256));if l_hash<>l_download_hash then raise_application_error(-20836,'S3-compatible object integrity verification failed.');end if;update nfe_migration_item set status='VERIFIED',object_sha256=l_download_hash where control_id=l_control;dbms_lob.freetemporary(l_blob);dbms_lob.freetemporary(l_download);commit;
  exception when others then if l_blob is not null and dbms_lob.istemporary(l_blob)=1 then dbms_lob.freetemporary(l_blob);end if;if l_download is not null and dbms_lob.istemporary(l_download)=1 then dbms_lob.freetemporary(l_download);end if;rollback;raise;end;
  procedure run_workers(p_max_messages pls_integer default 1) is l_enabled char(1);l_processed pls_integer:=0;begin
    if p_max_messages is null or p_max_messages<=0 then raise_application_error(-20841,'Worker message limit must be positive.');end if;
    select classic_aq_enabled into l_enabled from nfe_classic_aq_config where config_id=1;
    if l_enabled<>'Y' then return;end if;
    while l_processed<p_max_messages loop
      begin process_one; l_processed:=l_processed+1;
      exception when others then if sqlcode=-25228 then exit; else raise; end if; end;
    end loop;
  end;
  procedure reconcile_batch(p_batch_id number,p_passed out boolean) is l_total number;l_verified number;begin select count(*),sum(case when status='VERIFIED' then 1 else 0 end) into l_total,l_verified from nfe_migration_item where batch_id=p_batch_id;p_passed:=l_total>0 and l_total=l_verified;if p_passed then update nfe_migration_batch set status='VERIFIED' where batch_id=p_batch_id;end if;end;
  procedure purge_verified_source(p_control_id number) is l_source number;l_status varchar2(20);begin select nfe_id,status into l_source,l_status from nfe_migration_item where control_id=p_control_id for update;if l_status<>'VERIFIED' then raise_application_error(-20837,'Only a verified item may be purged.');end if;pkg_nfe_deploy_source.clear_document(l_source);update nfe_migration_item set status='PURGED' where control_id=p_control_id;end;
end;
/
