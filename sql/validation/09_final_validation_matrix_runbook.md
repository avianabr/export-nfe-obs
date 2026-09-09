# Matriz final de validação da PoC

Execute somente no PDB da PoC, como os usuários indicados, e capture o texto
`PASS` de cada script. Os scripts de verificação criam dados de teste
controlados e fazem rollback quando aplicável; não os envolva em uma transação
externa.

## `NFE_OWNER`

```sql
@sql/ddl/15_verify_atomic_admission.sql
@sql/ddl/16_verify_nfe_admission_control.sql
@sql/ddl/23_verify_nfe_object_idempotency.sql
@sql/ddl/24_verify_nfe_transient_redelivery.sql
@sql/ddl/26_verify_nfe_exception_monitor.sql
```

This covers rollback of atomic admission, pause/resume and inflight limits,
failure after object upload with identical/divergent object handling, transient
redelivery, and exception-queue correlation.

## `NFE_MIGRATION_RUNTIME`

```sql
@sql/security/07_verify_runtime_denials.sql
```

This confirms the runtime identity cannot change source content or execute the
administrative purge package.

## Concurrency evidence

The benchmark already executed for task 5.5 is the concurrency evidence. Keep
the recorded four cohorts (1, 2, 4, and 8 workers) with their p50/p95/p99,
throughput, backlog, exception and divergence results. Do not rerun it until a
new synthetic cohort is provisioned, because the original benchmark documents
may already be controlled by migration items.

## Publication

After all six results pass, append the execution timestamp, executor, and the
captured `PASS` lines to `sql/validation/08_representative_poc_result.md` and
mark task 6.4 complete.
