---
name: documentation
description: Enforces canonical documentation maintenance, Architecture Decision Records (ADR), Phase reporting, and traceability updates for Market Management System (MMS). Use this skill whenever documenting architectural decisions, creating phase reports, updating project status, or updating business rule traceability.
---

# Documentation & ADR Governance Skill

This skill governs documentation integrity, Architectural Decision Records (ADR), and Phase lifecycle reporting for the **Market Management System (MMS)** project.

---

## 1. Documentation Hierarchy & Source of Truth

Never create conflicting documents. Every document in MMS serves a distinct purpose:

1. **`AGENTS.md` (Root):** Binding behavioral rules for AI models and human developers.
2. **`MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (Root):** Canonical baseline project charter.
3. **`docs/PROJECT_STATUS.md`:** Live operational status and next immediate tasks.
4. **`docs/requirements/BUSINESS_RULES_SPEC.md`:** 159 binding business rules with acceptance criteria.
5. **`docs/architecture/DATA_MODEL.md`:** Logical data schema (25 tables).
6. **`docs/decisions/`:** Formal Architecture Decision Records (ADR).
7. **`docs/phases/`:** Formal Phase kickoff and sign-off reports.

---

## 2. ADR Authoring Standards

Whenever a major architectural decision is proposed or confirmed, create or update a record in `docs/decisions/`:

- Follow the template in [`docs/decisions/ADR_TEMPLATE.md`](../../docs/decisions/ADR_TEMPLATE.md).
- Status must explicitly indicate:
  - `[CONFIRMED]`: Approved by user.
  - `[PROPOSED]`: Pending technical verification or spike.
  - `[DEPRECATED]`: Superseded by later architectural decisions.
- Record: Context, Decision, Alternatives Considered, Trade-offs, and Consequences.
- Register the new ADR in [`docs/decisions/README.md`](../../docs/decisions/README.md).

---

## 3. Phase Sign-off Protocol

Before transitioning from one phase to the next (e.g., Phase 0 to Phase 1):
1. Create a completion report in `docs/phases/` following [`docs/phases/PHASE-TEMPLATE.md`](../../docs/phases/PHASE-TEMPLATE.md).
2. Verify all Phase Acceptance Criteria against the Verification Matrix.
3. Update `docs/PROJECT_STATUS.md` to reflect completed items.
4. Obtain explicit user sign-off. Never advance a phase without user approval.

