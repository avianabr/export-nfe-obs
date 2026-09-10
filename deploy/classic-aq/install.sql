whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on
prompt Run this file as NFE_OWNER. The final privilege script must be run as SYS.
@@sql/01_control_schema.sql
@@sql/02_source_mapping.sql
@@sql/03_storage_config.sql
@@sql/04_classic_aq.sql
@@sql/05_runtime_packages.sql
@@sql/06_scheduler_dashboard.sql
prompt Connect as SYS and run @@sql/07_least_privilege.sql
