whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
@@principals.sql
@@sql/00_provision_principals.sql
