---
name: surgical-hermesdothealth
description: "Use when .hermes folder health, bloat, or stale caches."
version: 1.2.2
author: "TeacherEvan, Hermes Agent (revised by LittleDevil)"
license: MIT
platforms: [linux, macos, windows, termux]
metadata:
  hermes:
    category: devops
    tags: [hermes, doctor, diagnosis, folder-health, bloat, cache, cleanup]
    related_skills: [hermes-agent, surgical-audit]
---

# Hermes Folder Health Diagnostic (v1.2.2)

Measure `.hermes` size, find genuine bloat, stale files, and cache buildup — and
separate **user data** (safe to inspect, never auto-delete) from **app/vendor
trees** (git-managed, reinstall — do NOT hand-prune).

> Key correction over v1.0: `find -o` without parens misbinds `-type`, so the
> cache-dir and config-duplicate steps returned source *files*, not dirs. All
> `find` calls below use explicit `\( ... -o ... \)` grouping and `-print0 |
> xargs -0`. SQLite is checked via `python3` (the `sqlite3` CLI is often absent).

## Trigger

Use when:

- `.hermes` folder size seems excessive
- `hermes doctor` reports filesystem warnings
- You suspect cache buildup or orphaned files in `.hermes/`
- Periodic maintenance on a Termux/Android host (check both `~` and `/data/data/com.termux`)

**Don't use for:** deleting anything. This skill is diagnostic — cleanup steps require
explicit user approval and are never automated.

## Auxiliary Resources

- `scripts/hermes-doctor.sh` — the whole procedure as one read-only run
  (`bash scripts/hermes-doctor.sh`, `--live` for real network probes).
  Exits 3 on `--apply`: it never mutates.
- `scripts/conform.py` — family authoring gate (`python3 scripts/conform.py`).

## 0. Host pressure first — de-escalate if healthy

Do NOT recommend cleanup on a healthy disk. Measure first:

```bash
df -h ~
```

If `Use%` < 80% AND free space > 10 GB, state "No disk pressure" and stop unless
the user explicitly wants a tidy-up. Most `.hermes` size is git-managed
app/vendor (see Step 1) and is expected.

## 1. `hermes doctor` is the primary signal — run it first

It already checks skills, tools, memory provider, credentials, and offers auto-fix:

```bash
hermes doctor 2>&1
hermes doctor --fix 2>&1      # auto-fixes what it can (e.g. WAL checkpoint)
hermes doctor --live 2>&1     # opt-in real network probes per backend
```

Parse for: filesystem warnings, config validation, credential issues (see
the `hermes-agent` skill), model/provider connectivity. This skill ADDS
the per-directory sizing breakdown that `doctor` does not give.

## 2. Measure `.hermes` total size and top contributors

```bash
du -sh ~/.hermes
du -h --max-depth=1 ~/.hermes 2>/dev/null | sort -hr | head -25
```

On a typical dev host `.hermes` is ~13 GB: `hermes-agent/` alone is ~8 GB
(venv + bundled libs), `skills-vendor/` ~1.7 GB, `lsp/` ~140 MB. The rest is
user data + caches. Do NOT treat the whole folder as reclaimable — most of it
is git-managed app/vendor (see Step 1) and is expected.

Classify the top dirs:

- **USER DATA** (inspect only, never auto-delete): `sessions/`, `memories/`,
  `state.db*` (the single biggest file — ~1 GB, see Step 7), `kanban/`,
  `cron/`, `backups/` (keep latest 3), `pending/`.
- **APP/VENDOR** (git-managed — reinstall, do NOT hand-prune): `hermes-agent/`,
  `skills-vendor/`, `bin/`, `lsp/`. Deleting inside these breaks
  the install; reclaim space by `git` reinstall or version pin, not `rm`.
  (`coding-env/` is host-optional and may not exist — verify before guarding.)
- **CACHE/TRANSIENT** (safe to clean — see Cleanup): `cache/`, `image_cache/`,
  `audio_cache/`, `logs/`.

## 3. Large files (>100M) — exclude vendored trees (noise)

```bash
find ~/.hermes -type f -size +100M \
  -not -path "*/node_modules/*" -not -path "*/__pycache__/*" \
  -not -path "*/.venv/*" -not -path "*/venv/*" -not -path "*/.git/*" \
  -exec ls -lh {} \; 2>/dev/null
```

Report at the *directory* level (Step 2). Individual >100M files inside
`node_modules`/`venv` are vendor libs — never delete piecemeal.

## 4. Stale files (>90 days) — exclude git/vendor trees

Old mtime inside `hermes-agent/` or `skills-vendor/` is EXPECTED (vendored);
listing them is noise.

```bash
find ~/.hermes -type f -mtime +90 \
  -not -path "*/node_modules/*" -not -path "*/__pycache__/*" \
  -not -path "*/.venv/*" -not -path "*/venv/*" -not -path "*/.git/*" \
  -not -path "*/skills-vendor/*" -not -path "*/hermes-agent/*" \
  -exec ls -lh {} \; 2>/dev/null
```

## 5. Cache directories (CORRECTED — parenthesized find + vendor exclusions)

The naive find still surfaces vendored `__pycache__`/`.venv`/`venv`/`node_modules`/
`skills-vendor`/`backups` dirs (noise — note `*cache*` matches `__pycache__`).
Exclude them with name + path guards:

```bash
find ~/.hermes \( -type d -name "*cache*" -o -type d -name "*Cache*" \) \
  -not -name "__pycache__" \
  -not -path "*/__pycache__/*" -not -path "*/.venv/*" -not -path "*/venv/*" \
  -not -path "*/node_modules/*" -not -path "*/.git/*" \
  -not -path "*/skills-vendor/*" -not -path "*/backups/*" \
  -print0 2>/dev/null | xargs -0 du -sh 2>/dev/null | sort -hr
```

## 6. Duplicate / conflicting config files (CORRECTED)

```bash
find ~/.hermes \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.toml" \) \
  -print0 2>/dev/null | xargs -0 ls -la 2>/dev/null
```

Look specifically for:

- Multiple `config.yaml` variants / `config.yaml.bak`
- `*.bak`, `*.backup`, `*.old` stale copies
- Conflicting `profiles/` directories

## 7. SQLite integrity — via python3 (sqlite3 CLI often absent)

On a busy host `state.db` is the dominant bloat (~1 GB on a 13 GB install,
holding 150k+ messages / 1300+ sessions). Run the integrity check on ALL dbs:

```bash
find ~/.hermes -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) \
  -print0 2>/dev/null | while IFS= read -r -d '' db; do
  echo "=== $db ==="
  python3 - "$db" <<'PY'
import sys, sqlite3
db = sys.argv[1]
try:
    c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    rows = c.execute("PRAGMA integrity_check;").fetchall()
    print("OK" if all(r[0] == "ok" for r in rows) else rows)
except Exception as e:
    print("UNREADABLE:", e)
PY
done
```

Vacuum ONLY when no live hermes process (see Step 9) AND after a backup.
`state.db` is typically held open by 5+ processes (gateway, cron, session
writers) — `hermes doctor` will report "N process(es) holding the DB open".
If any are live, VACUUM will fail or corrupt; stop the gateway first.

```bash
cp ~/.hermes/state.db ~/.hermes/state.db.bak-$(date +%s)
# confirm Step 9 shows NO live process before running:
python3 -c "import sqlite3; sqlite3.connect('$HOME/.hermes/state.db').execute('VACUUM')"
```

## 8. Broader system cache audit (real safe wins live OUTSIDE .hermes)

```bash
for p in ~/.cache/pip ~/.cache/uv ~/.npm ~/.cache/yarn ~/.cache; do
  printf "%-28s " "$p"; du -sh "$p" 2>/dev/null || echo absent
done
docker system df 2>/dev/null || podman system df 2>/dev/null
du -sh /tmp 2>/dev/null
```

On most dev hosts `~/.npm` + `~/.cache/pip` + `~/.cache/uv` are the biggest
reclaimable caches — far larger than anything inside `.hermes`.

## 9. Orphaned processes / live-state check (BEFORE any WAL/SHM delete)

```bash
ls -la ~/.hermes/*.sock ~/.hermes/*.pid 2>/dev/null
pgrep -fl "hermes" 2>/dev/null || echo "no hermes process running"
```

If `pgrep` finds a live process, `state.db-wal` / `state.db-shm` are ACTIVE —
never delete them. Stop the gateway first
(`supervisorctl -c ~/.hermes/supervisord.conf stop hermes-gateway`).

## Cleanup Actions (require explicit user approval)

| Finding | Safe? | Command |
| --- | --- | --- |
| `~/.hermes/cache/*` | Yes (regenerated) | `rm -rf ~/.hermes/cache/*` |
| `~/.hermes/logs/*.log` >30d | Yes | `find ~/.hermes/logs -name "*.log" -mtime +30 -delete` |
| `~/.hermes/backups/` old | Keep latest 3 | Manual review |
| `~/.cache/pip`, `~/.cache/uv` | Yes | `pip cache purge`, `uv cache clean` |
| `~/.npm`, `~/.cache/yarn` | Yes | `npm cache clean --force` |
| Stale `*.bak`/`*.backup` | Yes | `find ~/.hermes -name "*.bak" -delete` |
| `state.db-wal`/`state.db-shm` | **ONLY if no live process** (Step 9) | stop hermes, then delete |
| `hermes-agent/` `skills-vendor/` `lsp/` | **NO — reinstall, don't prune** | n/a |

## Reporting Template

```text
=== HERMES FOLDER HEALTH REPORT ===
Host disk: X% used, Y free   [de-escalate if healthy]
Total .hermes: X GB
  APP/VENDOR (do not prune):  hermes-agent/venv X, skills-vendor/headroom X, lsp X
  USER DATA:                  state.db X, sessions X, kanban X, backups X
  CACHE/TRANSIENT:            cache X, logs X
Large files (>100M, excl vendor): [list]
Stale files (>90 days, excl vendor): [list]
Cache dirs: [list with sizes]
SQLite integrity: [OK/CORRUPT per DB]
hermes doctor: [PASS/FAIL — details]
System caches outside .hermes: ~/.npm X, ~/.cache/pip X, ~/.cache/uv X
Live hermes process: [yes/no]  (gates WAL/SHM cleanup)
RECOMMENDED CLEANUP (awaiting approval):
- [ ] pip/uv/npm caches (X)
- [ ] ~/.hermes/cache/* (X)
- [ ] logs >30d (X)
- [ ] stale .bak (X)
- [ ] vacuum state.db (X) — only if no live process
```

## Pitfalls

- **Never delete `~/.hermes/.env`** — API keys.
- **Never delete `~/.hermes/config.yaml`** without a verified backup.
- **Never delete `sessions/` or `memories/`** — user data.
- **Never hand-prune `hermes-agent/`, `skills-vendor/`, `lsp/`** — these
  are ~10 GB of git-managed app/vendor; reclaim via reinstall, not `rm`.
- **WAL/SHM are live** while hermes runs — check Step 9 first.
- **`sqlite3` CLI is often absent** — use the python3 check (Step 7).
- **Termux/Android**: `/data/data/com.termux` is real app storage; `~` may be a
  symlink. Check both.
- **Supervisord sockets/pids** are active if gateway runs — stop it before cleanup.
- Stale-file scans MUST exclude `node_modules`/`venv`/`.git`/`__pycache__` or
  they flag thousands of legitimate vendored files.
- **"Corrected" find still leaks vendored cache (2026-08-20).** The v1.1 fix
  parenthesized the `-o` so it returned dirs — but did NOT exclude
  `node_modules`/`venv`/`__pycache__`/`skills-vendor`/`backups`. Live run still
  surfaced googleapiclient/discovery_cache (inside venv), lsp/node_modules
  type caches, and dozens of `skills-vendor/__pycache__` dirs. Any "fixed" find
  in this skill must carry the full `-not -path` vendor exclusion list or it is
  not actually fixed.
- **State.db is the real bloat, not caches (2026-08-20).** On a 13 GB `.hermes`,
  `state.db` alone is ~1 GB (150k+ messages). A vacuum is unsafe while the
  gateway/cron hold it open — Step 7 must defer to Step 9's live-process check.

- **`-s` and a depth flag are mutually exclusive (corrected 2026-10-24).** GNU
  coreutils treats `du -sh -d1` as a conflict and warns; `2>/dev/null` hides the
  warning and the section renders empty. The earlier fix (`--max-depth=1`) is
  **GNU-only** — BSD/macOS `du` rejects it, so the same silent-empty bug came back
  on macOS. Step 2 now uses `du -h -d 1`, which both GNU and BSD accept. Never
  combine `-s` with a depth flag.
- **`df -h` suffixes follow the volume, not the host (corrected 2026-10-24).**
  Free space can be reported as `G`, `T`, or `M`; `sed 's/G.*//'` left `1.2T`
  behind and the integer compare in Step 0 failed, so a healthy TB volume never
  de-escalated. Use `df -Pk` (1K blocks) and integer maths.

## Verification

```bash
bash -n scripts/hermes-doctor.sh      # syntax
bash scripts/hermes-doctor.sh --help  # flags documented
bash scripts/hermes-doctor.sh         # read-only run; must print a report
bash scripts/hermes-doctor.sh --apply; echo "exit=$?"   # must be 3
```

A run that prints a report but exits non-zero, or that prints an empty Step 2, is a failure —
not a clean host.
