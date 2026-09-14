# Implementation TODO

## Objective
Run the surgical-implementation V2 pipeline end-to-end on the shipped `Surgical-HermesDotHealth` skill v1.2.1: author a fresh plan from the current code state, consistency-gate it, verify the shipped script against its spec, security-audit, debrief, and commit+push the scoped artifacts.

## Constraints
- Must not break `bash -n scripts/hermes-doctor.sh` (green baseline).
- Must not touch `TeacherEvan/TeacherEvan`.
- No issues/PRs/merge.
- `docs/.scratch-audit/` stays gitignored; only `docs/plans/` + `.gitignore` may be committed.

## Objectives
- [x] OBJ-001. Confirm affected modules and baseline assumptions from CODEBASE-STATE.md.
- [x] OBJ-002. Confirm interfaces/contracts: script flags, Step ordering, vendor exclusion list.
- [x] OBJ-003. Author V2 planning artifacts (REQUIREMENTS, CODEBASE-STATE, ARCHITECTURE, TODO).
- [x] OBJ-004. Run CONSISTENCY_GATE: reviewer PASS on REQUIREMENTS ↔ CODEBASE-STATE ↔ ARCHITECTURE ↔ TODO.
- [x] OBJ-005. Syntax-gate the shipped script: `bash -n scripts/hermes-doctor.sh` exit 0.
- [x] OBJ-006. Live-run the script; confirm Step 0 de-escalation + well-formed report.
- [x] OBJ-007. Scan script for spec drift vs SKILL.md (Step 1–9 coverage, find parens, vendor excludes).
- [x] OBJ-008. SECURITY_AUDIT: secret scan + scope review; no CRITICAL findings.
- [x] OBJ-009. Author TRACEABILITY.md mapping OBJ → REQ → evidence.
- [x] OBJ-010. Author debrief.md (17 sections) + copy plan/debrief to `docs/plans/`.
- [x] OBJ-011. Commit scoped artifacts; push (push=1); confirm `0 0` remote state.

## Objective evidence
### OBJ-001
- Requirement: REQ-001 / AC-003
- Files/modules: `docs/.scratch-audit/CODEBASE-STATE.md`, `SKILL.md`, `scripts/hermes-doctor.sh`
- Acceptance: baseline inventory matches live `ls`/`git status`
- Validation: `ls -la`, `git status -s`, `bash -n`
- Evidence: CODEBASE-STATE.md written; `git status -s` clean before artifacts

### OBJ-002
- Requirement: REQ-002
- Acceptance: script flags (`--help/--apply/--live`), Step 0–9 ordering, VENDOR_EXCLUDES list match SKILL.md
- Validation: `bash scripts/hermes-doctor.sh --help`, grep script for Step markers
- Evidence: `--help` output; Step 0 de-escalates on 52% disk

### OBJ-003
- Requirement: REQ-001
- Acceptance: four planning artifacts exist
- Validation: `ls docs/.scratch-audit/`
- Evidence: REQUIREMENTS.md, CODEBASE-STATE.md, ARCHITECTURE.md, TODO.md present

### OBJ-004
- Requirement: REQ-004 / AC-004
- Acceptance: artifacts agree; no contradictions
- Validation: manual cross-check + gate log entry
- Evidence: `audit/logs/retry-CONSISTENCY_GATE.jsonl` with PASS

### OBJ-005
- Requirement: AC-001
- Acceptance: `bash -n` exit 0
- Validation: terminal
- Evidence: `SYNTAX OK` output

### OBJ-006
- Requirement: AC-002
- Acceptance: live run prints report + Step 0 de-escalates
- Validation: terminal
- Evidence: report output captured

### OBJ-007
- Requirement: REQ-002
- Acceptance: script covers SKILL.md Steps 1–9; find parens present; vendor excludes present
- Validation: `rg` scans on script
- Evidence: grep hits for Step markers + VENDOR_EXCLUDES

### OBJ-008
- Requirement: REQ-006 / AC-005
- Acceptance: no secrets, no scope violations
- Validation: `rg` secret scan + diff review
- Evidence: SECURITY.md

### OBJ-009
- Requirement: REQ-001
- Acceptance: every OBJ traces to a REQ + evidence
- Validation: manual matrix
- Evidence: TRACEABILITY.md

### OBJ-010
- Requirement: REQ-007
- Acceptance: debrief.md 17 sections; docs/plans/ has plan + debrief
- Validation: `ls docs/plans/`, section count
- Evidence: debrief.md written

### OBJ-011
- Requirement: AC-006
- Acceptance: commit + push; remote `0 0`
- Validation: `git commit`, `git push`, `git status -sb`
- Evidence: commit SHA + push output

## Definition of done
- [] Every required objective is complete or explicitly blocked.
- [] Acceptance criteria have evidence in TRACEABILITY.md.
- [] Security review complete in SECURITY.md.
- [] Final audit + debrief.md complete.
