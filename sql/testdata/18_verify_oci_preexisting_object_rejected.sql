-- Read-safe overwrite-prevention probe. Run as NFE_OWNER with OCI_NATIVE active.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on verify off
declare
  l_uri nfe_migration_item.object_uri%type; l_credential nfe_deploy_storage_config.credential_name%type;
  l_status nfe_migration_item.status%type; l_blob blob; l_text varchar2(100):='must-not-overwrite';
  l_response dbms_cloud_types.resp; l_rejected boolean:=false;
begin
  select i.object_uri,i.status,s.credential_name into l_uri,l_status,l_credential
    from nfe_migration_item i join nfe_deploy_storage_config s on s.config_id=1
   where i.control_id=21821 and i.integrity_mode='OCI_MD5_HEAD';
  if l_status<>'VERIFIED' then raise_application_error(-20960,'Reference OCI item is not VERIFIED.');end if;
  dbms_lob.createtemporary(l_blob,true);dbms_lob.writeappend(l_blob,length(l_text),utl_raw.cast_to_raw(l_text));
  begin
    l_response:=dbms_cloud.send_request(credential_name=>l_credential,uri=>l_uri,method=>dbms_cloud.method_put,
      headers=>json_object('if-none-match' value '*','content-type' value 'text/plain'),body=>l_blob);
    raise_application_error(-20961,'Preexisting OCI object unexpectedly accepted overwrite.');
  exception when others then
    if sqlcode=-20961 then raise; end if;
    l_rejected:=true; dbms_output.put_line('PASS: preexisting OCI object rejected: '||sqlcode);
  end;
  dbms_lob.freetemporary(l_blob);
  select status into l_status from nfe_migration_item where control_id=21821;
  if not l_rejected or l_status<>'VERIFIED' then raise_application_error(-20962,'Overwrite probe changed control state.');end if;
  dbms_output.put_line('PASS: control 21821 remains VERIFIED.');
exception when others then if l_blob is not null and dbms_lob.istemporary(l_blob)=1 then dbms_lob.freetemporary(l_blob);end if;raise;end;
/
