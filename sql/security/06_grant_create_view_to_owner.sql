-- One-time correction for an NFE_OWNER created before CREATE VIEW was added
-- to 00_create_test_schemas.sql. Run as SYS in PDB_POCRT_02.

whenever sqlerror exit failure rollback

grant create view to nfe_owner;

prompt PASS: CREATE VIEW granted to NFE_OWNER.
