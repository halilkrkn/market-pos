---
name: systematic-debugging
description: Guides structured root-cause analysis (RCA), SQLite WAL diagnostics, transaction isolation verification, and failure analysis for Market Management System (MMS). Use this skill whenever investigating crashes, sync errors, SQLite busy locks, or calculation inconsistencies.
---

# Systematic Debugging & Root Cause Analysis Skill

This skill enforces disciplined, hypothesis-driven debugging for the **Market Management System (MMS)** project, adapted from the `obra/superpowers` systematic debugging methodology.

---

## 1. Core Principle: Never Guess or Blindly Edit Code

When an unexpected error or test failure occurs, **do NOT jump straight into editing source files based on assumptions**. Randomly tweaking code creates new bugs and hides the actual failure mode.

Follow the 4-phase Root Cause Analysis (RCA) procedure:

```text
[PHASE 1: REPRODUCE & ISOLATE]
  - Replicate the failure deterministically with minimal inputs.
  - Isolate whether it is a UI state, Domain business rule, SQLite storage, or Network API issue.

[PHASE 2: GATHER FACTS & LOGS]
  - Inspect SQLite WAL status, database integrity (PRAGMA integrity_check).
  - Inspect sync_operations queue status ('PENDING', 'PROCESSING', 'FAILED', 'CONFLICT').
  - Read exact stack traces and error types (e.g. SqliteException, FormatException).

[PHASE 3: FORMULATE & TEST HYPOTHESIS]
  - State clearly: "I hypothesize that error X is caused by Y because Z."
  - Devise a minimal check or failing unit test to prove or disprove the hypothesis.

[PHASE 4: SURGICAL FIX & VERIFICATION]
  - Apply the minimal, targeted correction.
  - Verify that the original failure is resolved AND no regressions were introduced.
```

---

## 2. Common MMS Failure Modes & Diagnostic Protocols

### 2.1. SQLite Busy / Lock Issues (`SQLITE_BUSY` or `database is locked`)
- **Diagnosis:** Occurs when multiple threads or processes attempt to write simultaneously outside of WAL mode or without a busy handler.
- **Verification:**
  1. Verify `PRAGMA journal_mode;` returns `wal`.
  2. Verify `PRAGMA busy_timeout;` is configured to at least `5000` (5 seconds).
  3. Verify that all central writes flow exclusively through the Windows Service single-writer queue.

### 2.2. Outbox Synchronization Stalls
- **Diagnosis:** Operation remains stuck in `PROCESSING` status.
- **Verification:**
  1. Inspect `sync_operations.lease_expires_at`.
  2. Check if worker crashed mid-network-call.
  3. Ensure exponential backoff worker unlocks expired leases (`lease_expires_at < CURRENT_TIMESTAMP`).

### 2.3. Monetary Mismatch / Rounding Drift
- **Diagnosis:** Cart sum does not match line item totals.
- **Verification:**
  1. Inspect `sale_items.total_amount`.
  2. Ensure calculation uses integer cents: $\text{total} = \text{round}\left(\frac{\text{quantity} \times \text{unit\_price}}{1000}\right)$ or rational integer arithmetic.
  3. Confirm that no intermediate conversion to `double` occurred.

