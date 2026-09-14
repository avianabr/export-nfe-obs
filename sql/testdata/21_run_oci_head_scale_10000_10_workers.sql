-- End-to-end OCI HEAD benchmark. Run as NFE_OWNER in the isolated PDB.
-- Creates 10,000 new synthetic documents, switches only the persisted source
-- mapping to POC_NFE_OCI_10K, and runs the ten-worker harness.
whenever oserror exit failure rollback
whenever sqlerror exit failure rollback
set serveroutput on size unlimited verify off
@@19_create_seed_oci_10k_source.sql
@@20_configure_oci_10k_source.sql
@@09_run_classic_aq_scale_10000_5_workers.sql
