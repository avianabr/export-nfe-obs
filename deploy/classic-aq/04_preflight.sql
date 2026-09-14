whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
set verify off
prompt Load the protected, local non-secret environment file before metadata checks.
@@sql/02_preflight.sql
