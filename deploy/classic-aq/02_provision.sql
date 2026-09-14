whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
set verify off
prompt Provision technical runtime identity and private roles.
@@sql/01_provision_principals.sql
