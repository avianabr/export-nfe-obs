-- Run as NFE_OWNER after ddl/37_create_nfe_classic_aq.sql.
-- Adds an auditable, disabled-by-default batch selection for classic AQ.
-- Existing batches have no selection row and therefore remain on the legacy
-- TEQ path; this script does not alter either TEQ queue or its messages.

whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited

declare
  l_count pls_integer;
begin
  select count(*) into l_count from user_tables where table_name = 'NFE_CLASSIC_AQ_CONFIG';
  if l_count = 0 then
    execute immediate q'[
      create table nfe_classic_aq_config (
        config_id         number not null,
        classic_aq_enabled char(1 char) default 'N' not null,
        updated_by        varchar2(128 char) not null,
        updated_at        timestamp(6) with time zone default systimestamp not null,
        constraint pk_nfe_classic_aq_config primary key (config_id),
        constraint ck_nfe_classic_aq_config_singleton check (config_id = 1),
        constraint ck_nfe_classic_aq_enabled check (classic_aq_enabled in ('Y', 'N'))
      )]';
    dbms_output.put_line('Created NFE_CLASSIC_AQ_CONFIG.');
  end if;

  -- The table may have been created above in this same anonymous block, so
  -- this must be dynamic SQL: static SQL is compiled before that DDL runs.
  execute immediate
    'select count(*) from nfe_classic_aq_config where config_id = 1'
    into l_count;
  if l_count = 0 then
    execute immediate q'[
      insert into nfe_classic_aq_config (config_id, classic_aq_enabled, updated_by)
      values (1, 'N', sys_context('USERENV', 'SESSION_USER'))]';
    dbms_output.put_line('Initialized classic AQ selection as disabled.');
  end if;

  select count(*) into l_count from user_tables where table_name = 'NFE_MIGRATION_BATCH_TRANSPORT';
  if l_count = 0 then
    execute immediate q'[
      create table nfe_migration_batch_transport (
        batch_id       number not null,
        transport_mode varchar2(30 char) not null,
        selected_by    varchar2(128 char) not null,
        selected_at    timestamp(6) with time zone default systimestamp not null,
        constraint pk_nfe_migration_batch_transport primary key (batch_id),
        constraint fk_nfe_batch_transport_batch foreign key (batch_id)
          references nfe_migration_batch (batch_id),
        constraint ck_nfe_batch_transport_mode check (transport_mode = 'CLASSIC_AQ')
      )]';
    dbms_output.put_line('Created NFE_MIGRATION_BATCH_TRANSPORT.');
  end if;
end;
/

create or replace package pkg_nfe_classic_aq_config authid definer as
  procedure get_classic_aq_enabled(p_enabled out char);

  procedure set_classic_aq_enabled(p_enabled in char);

  procedure select_classic_aq(p_batch_id in nfe_migration_batch.batch_id%type);

  procedure assert_classic_aq_selected(p_batch_id in nfe_migration_batch.batch_id%type);
end pkg_nfe_classic_aq_config;
/

create or replace package body pkg_nfe_classic_aq_config as
  procedure get_classic_aq_enabled(p_enabled out char) is
  begin
    select classic_aq_enabled
      into p_enabled
      from nfe_classic_aq_config
     where config_id = 1;
  end get_classic_aq_enabled;

  procedure set_classic_aq_enabled(p_enabled in char) is
    l_queue_count pls_integer;
  begin
    if p_enabled not in ('Y', 'N') then
      raise_application_error(-20180, 'Classic AQ enabled flag must be Y or N.');
    end if;

    if p_enabled = 'Y' then
      select count(*) into l_queue_count
        from user_queues
       where name in ('NFE_CLASSIC_AQ_Q', 'NFE_CLASSIC_AQ_EX_Q');
      if l_queue_count <> 2 then
        raise_application_error(-20181,
          'Classic AQ queues must exist before the transport can be enabled.');
      end if;
    end if;

    update nfe_classic_aq_config
       set classic_aq_enabled = p_enabled,
           updated_by = sys_context('USERENV', 'SESSION_USER'),
           updated_at = systimestamp
     where config_id = 1;

    pkg_nfe_audit.log_event(
      p_actor_type => 'USER',
      p_event_type => 'CLASSIC_AQ_MODE_CHANGED',
      p_details_json => '{"transportMode":"CLASSIC_AQ","enabled":"' || p_enabled || '"}');
  end set_classic_aq_enabled;

  procedure select_classic_aq(p_batch_id in nfe_migration_batch.batch_id%type) is
    l_enabled nfe_classic_aq_config.classic_aq_enabled%type;
    l_status  nfe_migration_batch.status%type;
    l_count   pls_integer;
  begin
    select classic_aq_enabled into l_enabled
      from nfe_classic_aq_config
     where config_id = 1
       for update;
    if l_enabled <> 'Y' then
      raise_application_error(-20182,
        'Classic AQ is disabled; explicit batch selection is not allowed.');
    end if;

    select status into l_status
      from nfe_migration_batch
     where batch_id = p_batch_id
       for update;
    if l_status <> 'CREATED' then
      raise_application_error(-20183,
        'Classic AQ may be selected only for a CREATED batch.');
    end if;

    select count(*) into l_count
      from nfe_migration_batch_transport
     where batch_id = p_batch_id;
    if l_count <> 0 then
      raise_application_error(-20184, 'Batch already has an explicit transport selection.');
    end if;

    insert into nfe_migration_batch_transport (batch_id, transport_mode, selected_by)
    values (p_batch_id, 'CLASSIC_AQ', sys_context('USERENV', 'SESSION_USER'));
    pkg_nfe_audit.log_event(
      p_actor_type => 'USER',
      p_event_type => 'CLASSIC_AQ_TRANSPORT_SELECTED',
      p_batch_id => p_batch_id,
      p_details_json => '{"transportMode":"CLASSIC_AQ"}');
  end select_classic_aq;

  procedure assert_classic_aq_selected(p_batch_id in nfe_migration_batch.batch_id%type) is
    l_enabled nfe_classic_aq_config.classic_aq_enabled%type;
    l_count   pls_integer;
  begin
    get_classic_aq_enabled(l_enabled);
    if l_enabled <> 'Y' then
      raise_application_error(-20185, 'Classic AQ is disabled.');
    end if;
    select count(*) into l_count
      from nfe_migration_batch_transport
     where batch_id = p_batch_id
       and transport_mode = 'CLASSIC_AQ';
    if l_count <> 1 then
      raise_application_error(-20186,
        'Batch does not have an explicit classic AQ transport selection.');
    end if;
  end assert_classic_aq_selected;
end pkg_nfe_classic_aq_config;
/

prompt PASS: classic AQ transport selection is auditable and disabled by default.
