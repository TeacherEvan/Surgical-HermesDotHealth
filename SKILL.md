---
name: surgical-HermesDotHealth
description: "Diagnose .hermes folder health, size, bloat, and stale files — portable (linux/macos/windows-git-bash/termux), bug-free find, hermes doctor-first."
version: 1.1.0
author: Hermes curator (revised by LittleDevil)
license: MIT
platforms: [linux, macos, windows, termux]
metadata:
  hermes:
    tags: [hermes, doctor, diagnosis, folder-health, bloat, cache, cleanup]
    related_skills: [hermes-agent, hermes-credential-diagnostics, hermes-gateway-ops, termux-system-health]
---

# Hermes Folder Health Diagnostic (v1.1)

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
- Periodic maintenance on a Termux/Android host (pair with `termux-system-health`)

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
`hermes-credential-diagnostics`), model/provider connectivity. This skill ADDS
the per-directory sizing breakdown that `doctor` does not give.

## 2. Measure `.hermes` total size and top contributors
```bash
du -sh ~/.hermes
du -sh -d1 ~/.hermes 2>/dev/null | sort -hr | head -25
```
Classify the top dirs:
- **USER DATA** (inspect only, never auto-delete): `sessions/`, `memories/`,
  `state.db*`, `kanban/`, `cron/`, `backups/` (keep latest 3), `pending/`.
- **APP/VENDOR** (git-managed — reinstall, do NOT hand-prune): `hermes-agent/`,
  `coding-env/`, `skills-vendor/`, `bin/`, `lsp/`. Deleting inside these breaks
  the install; reclaim space by `git` reinstall or版本 pin, not `rm`.
- **CACHE/TRANSIENT** (safe to clean — see Cleanup): `cache/`, `image_cache/`,
  `audio_cache/`, `logs/`.

## 3. Large files (>100M) — exclude vendored trees (noise)
```bash
find ~/.hermes -type f -size +100M \
  -not -path "*/node_modules/*" -not -path "*/__pycache__/*" \
  -not -path "*/venv/*" -not -path "*/.git/*" \
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
  -not -path "*/venv/*" -not -path "*/.git/*" \
  -not -path "*/skills-vendor/*" -not -path "*/hermes-agent/*" \
  -exec ls -lh {} \; 2>/dev/null
```

## 5. Cache directories (CORRECTED — parenthesized find)
```bash
find ~/.hermes \( -type d -name "*cache*" -o -type d -name "*Cache*" \) \
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
Vacuum ONLY when no live hermes process (see Step 9) and after a backup:
```bash
cp ~/.hermes/state.db ~/.hermes/state.db.bak-$(date +%s)
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
|---|---|---|
| `~/.hermes/cache/*` | Yes (regenerated) | `rm -rf ~/.hermes/cache/*` |
| `~/.hermes/logs/*.log` >30d | Yes | `find ~/.hermes/logs -name "*.log" -mtime +30 -delete` |
| `~/.hermes/backups/` old | Keep latest 3 | Manual review |
| `~/.cache/pip`, `~/.cache/uv` | Yes | `pip cache purge`, `uv cache clean` |
| `~/.npm`, `~/.cache/yarn` | Yes | `npm cache clean --force` |
| Stale `*.bak`/`*.backup` | Yes | `find ~/.hermes -name "*.bak" -delete` |
| `state.db-wal`/`state.db-shm` | **ONLY if no live process** (Step 9) | stop hermes, then delete |
| `hermes-agent/` `coding-env/` `skills-vendor/` | **NO — reinstall, don't prune** | n/a |

## Reporting Template
```
=== HERMES FOLDER HEALTH REPORT ===
Host disk: X% used, Y free   [de-escalate if healthy]
Total .hermes: X GB
  APP/VENDOR (do not prune):  hermes-agent/venv X, skills-vendor/headroom X, coding-env/lib X
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
- **Never hand-prune `hermes-agent/`, `coding-env/`, `skills-vendor/`** — these
  are 21 GB+ of git-managed app/vendor; reclaim via reinstall, not `rm`.
- **WAL/SHM are live** while hermes runs — check Step 9 first.
- **`sqlite3` CLI is often absent** — use the python3 check (Step 7).
- **Termux/Android**: `/data/data/com.termux` is real app storage; `~` may be a
  symlink. Check both.
- **Supervisord sockets/pids** are active if gateway runs — stop it before cleanup.
- Stale-file scans MUST exclude `node_modules`/`venv`/`.git`/`__pycache__` or
  they flag thousands of legitimate vendored files.
