## Context

See [proposal.md](proposal.md) for the motivation and the four delta specs for the behavioral contract. The baseline is Oracle AI Database 26ai with NF-e XMLs retained in `CLOB`; OCI Object Storage is a separate durable store and cannot participate in the same ACID transaction as Oracle. The implementation must therefore make the Oracle control tables the source of truth for progress and use explicit verification and reconciliation to bridge the transaction boundary.

The first deployment is restricted to already-existing NF-es. Oracle Transactional Event Queue (TEQ) is used for small work references only; the design does not use Kafka-compatible interfaces or consumer-group semantics.

## Goals / Non-Goals

**Goals:**

- Preserve a durable, auditable Oracle catalog for every selected document and its Object Storage evidence.
- Make selection plus enqueue atomic, and make worker success plus TEQ dequeue completion coordinated on Oracle commit.
- Make the unavoidable post-upload/pre-commit retry safe through stable object identity and byte-level verification.
- Bound database and Object Storage pressure with chunking, inflight limits, worker counts and a pause control.
- Enforce the human gate as a database authorization boundary, not an operational convention.

**Non-Goals:**

- Distributed ACID commit across Oracle and Object Storage.
- Automatic deletion of source XMLs, migration of newly inserted NF-es, or a transparent legacy read path.
- Assumptions about queue parameters, Streams Pool sizing, DBMS_CLOUD availability, or Object Storage metadata that have not been proven in the exact target RU and OCI tenancy.

## Decisions

### Oracle control plane with one item per NF-e

`NFE_MIGRATION_BATCH` records criteria, phase, counters, reconciliation and approval; `NFE_MIGRATION_ITEM` records one stable migration identity per NF-e; audit and reconciliation runs retain append-only evidence. A unique constraint on `NFE_ID` prevents concurrent or accidental admission to multiple batches in this PoC.

The control tables, rather than TEQ depth or Object Storage listings, are the operational source of truth. TEQ is a delivery mechanism and Object Storage is the durable content destination.

Alternative considered: use only queue state or bucket listings for progress. Rejected because neither represents the full lifecycle, human approval, or a stable reconciliation record.

### Atomic outbox-like admission without a second dispatcher

For each selection chunk, insert the control item, enqueue a `RAW` UTF-8 JSON envelope containing `{eventType, version, controlId, nfeId, batchId}` in the TEQ, save the message identifier, and commit once. Message visibility is `ON_COMMIT`.

This removes the table/queue dual-write window without requiring an additional polling dispatcher. The payload excludes XML/CLOB/BLOB to limit Streams Pool pressure and to keep retry traffic small.

Alternative considered: enqueue XML content or commit table and enqueue independently. Rejected because the former couples large LOBs to queue capacity and the latter can create orphan work or unqueued items.

### Deterministic object identity plus verify-before-success

The object key is derived as `nfe/<yyyy>/<mm>/<chave-nfe>.xml`; it contains no worker ID, random identifier or attempt timestamp. The PoC uses the OCI S3-compatible dedicated endpoint `https://idzvuvikb5ym.compat.objectstorage.us-ashburn-1.oci.customer-oci.com/POC_RT/<object-key>` and an OCI Customer Secret Key credential owned by `NFE_OWNER`. Workers convert the source `CLOB` to a temporary `BLOB` in `AL32UTF8`, calculate size and SHA-256, upload or inspect the existing object, then retrieve the object and compare its bytes before setting `VERIFIED`.

If a worker fails after upload and before commit, the next delivery resolves to the same key. An identical object completes idempotently; a divergent object is a conflict and is never silently overwritten. Object version ID and ETag are recorded when exposed by the validated target API.

Alternative considered: random object names per retry or trust a successful PUT alone. Rejected because both fail to prove recovery safety at the Oracle/Object Storage transaction boundary.

### Transactional Event Queue dequeue with explicit error classes

Workers dequeue from TEQ with `REMOVE` and `ON_COMMIT`. Every work envelope is enqueued with the explicit `exception_queue` property set to the configured TEQ exception queue. A successful verification updates the item and commits, which completes message consumption. A transient fault rolls back, allowing TEQ retry; an integrity or configuration fault records safe diagnostics and blocks/pauses according to severity. A monitor drains the TEQ exception queue only after preserving correlation evidence and marks the item `EXCEPTION`.

Business attempt counts are application telemetry; TEQ remains authoritative for delivery retry policy. Autonomous logging, if used, is confined to diagnostics and must never mutate business state or acknowledge a message.

Alternative considered: acknowledge before Object Storage verification. Rejected because it would lose the retry path when verification fails.

### Admission control and scheduler topology are configurable

Selection runs in chunks only while the global pause is off, the batch remains eligible, its document cap is not reached and inflight work is below the configured threshold. Recurrent scheduler jobs invoke bounded worker runs; workers inspect pause state between messages and exit cleanly after an idle or duration limit.

Initial throughput settings are intentionally conservative and must be benchmarked: small selection chunks, low worker count and one message per dequeue. TEQ partitioning, dequeue affinity, flow control and Streams Pool sizing are environment tuning inputs rather than fixed architectural constants.

Alternative considered: enqueue the full historical archive at once. Rejected because it defeats backpressure and increases redo, undo, memory and operational recovery risk.

### Purge is a separate administrative capability

Workers receive only the minimum privileges needed to read source content through a controlled interface and to operate the queue/transfer path. A distinct administrative package, identity and role perform approval and purge. Approval locks and revalidates the batch, records the authenticated actor, timestamp, comment and evidence reference. Purge is manually initiated in small chunks, revalidates approval before each chunk, sets only `XML_CLOB` to `NULL`, and follows with reconciliation.

Alternative considered: a worker automatically clears `XML_CLOB` after verification. Rejected because verification of an item is insufficient approval for a destructive, fiscal-data operation and would defeat segregation of duties.

## Risks / Trade-offs

- [Target release lacks a required TEQ or `DBMS_CLOUD` capability] → Run the discovery/go-no-go checks before any schema deployment and adapt only within the documented Oracle AI Database 26ai feature set.
- [Object Storage write succeeds before Oracle commit] → Reuse deterministic keys, inspect existing objects and require size/hash verification on every successful completion.
- [Full download verification increases PoC cost and latency] → Keep it mandatory for the PoC; assess an evidence-equivalent optimization only after measured results.
- [Queue/database saturation under high concurrency] → Enforce admission limits, begin with low worker counts, benchmark incrementally, and pause admission on systemic errors.
- [Duplicate, malformed or stale messages] → Validate contract version and references, enforce unique item identity, and retain diagnostic/audit evidence.
- [Premature or unauthorized source-data removal] → Require passed reconciliation and explicit approval, separate package privileges, chunk purge work, and reconcile after purge.
- [Sensitive data appears in operations data] → Never log XML, credential material or authentication headers; protect URI and bucket metadata per internal classification.
- [OCI Customer Secret Key expires or is rotated] → Store it only in `DBMS_CLOUD`, rotate it with `UPDATE_CREDENTIAL`, and repeat the controlled smoke test after rotation.

## Migration Plan

1. Validate the target database RU, TEQ features, `DBMS_CLOUD`, credential mechanism, ACL/TLS connectivity, IAM and bucket configuration using a controlled non-production dataset.
2. Deploy owner, runtime, purge-admin and auditor schemas/roles; then deploy control tables, constraints, audit/reconciliation structures, queue and exception queue.
3. Deploy packages and disabled scheduler jobs. Validate that runtime identity cannot update source XML or execute purge administration.
4. Execute functional and fault-injection tests with 10–100 NF-es, then benchmark batches with progressively larger worker counts and controlled inflight limits.
5. Run a representative historical batch through verification, reconciliation, human approval, a small manual purge, and post-purge reconciliation before deciding whether to expand the PoC.

Rollback before purge consists of disabling scheduler jobs, pausing admission and preserving Oracle controls, queue evidence and Object Storage objects for investigation. After purge, source XML restoration is a separate, explicitly authorized recovery operation using the verified Object Storage copy; purge must therefore not begin until retention, backup and restoration evidence have been accepted.

## Open Questions

- Which exact Oracle AI Database 26ai release update, deployment topology (including RAC, if any), and `DBMS_CLOUD` package version will be used for the PoC?
- Which OCI bucket settings (versioning, retention and immutability) and corporate fiscal-retention rules apply before a batch can be approved for purge?
- Which authenticated database identities and approval workflow satisfy the organization’s segregation-of-duties policy?
