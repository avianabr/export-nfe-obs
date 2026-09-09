## Context

See proposal.md for the AQ/TEQ incident motivation. The current PoC has an
Oracle control plane, reference-only RAW envelopes, idempotent Object Storage
verification, and a segregated purge flow. Only the queue transport is being
replaced; existing TEQ rows and ADR evidence must remain untouched.

Oracle AI Database 26ai documents AQ classic as a disk-based option for simpler
workflows and documents deprecation for AQ sharded queues, not AQ classic. This
design therefore targets classic AQ APIs compatible with 19c and does not use
sharded-queue/TxEventQ attributes.

## Goals / Non-Goals

**Goals:**

- Establish an independently named classic AQ transport that supports atomic
  admission, transactional dequeue, retry, exception routing, and bounded
  worker execution.
- Preserve the Oracle item table as source of truth and preserve the existing
  object-transfer, reconciliation, approval, and purge controls.
- Prove happy-path and fault-path behavior on the target RU before selecting AQ
  classic as the PoC transport.

**Non-Goals:**

- Altering, draining, repairing, or deleting the TEQ queues implicated in
  Oracle incident 836580.
- Migrating TEQ messages into the classic AQ queue automatically.
- Claiming an Oracle Support resolution for the TEQ incident or production
  suitability beyond the PoC evidence.

## Decisions

### Separate classic AQ queue namespace

Create a dedicated classic AQ queue table, normal queue, and exception queue
with names distinct from `NFE_MIGRATION_Q` and `NFE_MIGRATION_EX_Q`. Use a
single-consumer, persistent RAW queue and `DBMS_AQ`/`DBMS_AQADM` interfaces
available in 19c.

The deployed names are `NFE_CLASSIC_AQ_QT` (queue table),
`NFE_CLASSIC_AQ_Q` (normal queue), and `NFE_CLASSIC_AQ_EX_Q` (exception
queue). Their prefix is deliberately different from both TEQ queue names and
from the disposable `NFE_AQ19C_PROBE_*` compatibility-test objects.

Alternative considered: reuse the TEQ names or alter the existing queue.
Rejected because it would contaminate the Oracle Support evidence and make
rollback ambiguous.

### Explicit transport selection in the control plane

Add an explicitly auditable PoC transport selection, defaulting to disabled
until classic AQ validation passes. Admission, workers, exception monitoring,
jobs, dashboard, and tests select the classic-AQ implementation only when that
mode is enabled for the batch/run.

Alternative considered: replace TEQ calls in place. Rejected because a failed
deployment could accidentally consume the TEQ backlog or prevent comparison.

### Preserve the reference-only transactional contract

The existing UTF-8 JSON envelope remains reference-only. Classic AQ enqueue
uses `ON_COMMIT`; worker dequeue uses `REMOVE` and `ON_COMMIT`; only verified
success commits the item state and message removal together. The exception
queue receives explicit correlation evidence.

Alternative considered: table polling or an external dispatcher. Rejected
because it changes the atomic admission and transaction-boundary properties
being evaluated by this PoC.

### Validate operational semantics before scale

The first deployment runs isolated tests for enqueue/dequeue, rollback,
redelivery, max retries, exception routing, pause/resume, concurrent bounded
workers, and runtime privilege denial. No source CLOB purge is allowed in this
validation phase.

Alternative considered: start directly with a representative purge batch.
Rejected because queue delivery behavior is the unproven component.

## Risks / Trade-offs

- [Classic AQ behavior differs on the target RU] → run a scripted go/no-go
  suite before enabling any batch transport mode.
- [Two queue transports confuse operations] → expose transport mode, queue
  depth, exception count, and batch correlation in the dashboard and audit.
- [New deployment consumes TEQ evidence] → use separate names, grants, jobs,
  and tests; prohibit automatic TEQ drain/migration.
- [AQ classic has lower throughput than TxEventQ] → benchmark with conservative
  worker/inflight limits and retain the PoC scope until results are accepted.

## Migration Plan

1. Capture the current TEQ/ADR state and keep scheduler jobs disabled.
2. Provision classic AQ objects and least-privilege grants under separate names.
3. Deploy transport-selection, admission, worker, exception-monitor, job, and
   observability changes with classic AQ disabled by default.
4. Run the go/no-go suite on synthetic documents; enable classic AQ only for
   an isolated batch after all queue tests pass.
5. Roll back by disabling classic AQ jobs and selection; retain the classic AQ
   evidence and do not touch TEQ queues or source XML.

## Open Questions

- Which queue-table compatibility value and retry/exception settings are
  accepted by the exact 23.26.3.0.0 RU for the required 19c-compatible API set?
- Will the Oracle Support response for incident 836580 impose an operational
  restriction on coexisting AQ classic and TEQ objects in this PDB?
