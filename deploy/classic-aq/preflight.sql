whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
prompt Load the protected, local preflight environment file before metadata checks.
@@preflight-environment.sql
@@sql/00_preflight.sql
