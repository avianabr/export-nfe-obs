whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
prompt Run through 00_run-installation.sql. The final SYS step applies least privilege and the endpoint-derived HTTP ACL.
@@sql/03_control_schema.sql
@@sql/04_source_mapping.sql
@@sql/05_storage_config.sql
@@sql/06_classic_aq.sql
@@sql/07_runtime_packages.sql
@@sql/08_scheduler_dashboard.sql
prompt Connect as SYS and run @@sql/09_least_privilege.sql to complete installation.
