---
name: surgical-HermesDotHealth
description: "Diagnose .hermes folder health, size, bloat, and stale files"
version: 1.0.0
author: Hermes curator
license: MIT
platforms: [linux, macos, windows, termux]
metadata:
  hermes:
    tags: [hermes, doctor, diagnosis, folder-health, bloat, cache, cleanup]
    related_skills: [hermes-agent, hermes-credential-diagnostics, hermes-gateway-ops, termux-system-health]
---

# Hermes Folder Health Diagnostic

Detect bloat, stale files, and cache issues in .hermes system directories and the broader local system.

## Trigger
Use when:
- `.hermes` folder size seems excessive
- Disk space is low on the host system
- `hermes doctor` reports unusual filesystem warnings
- You suspect cache buildup, duplicate configs, or orphaned files in `.hermes/`
- Running periodic maintenance on a Termux/Android host (pair with `termux-system-health`)

## Diagnostic Steps

### 1. Measure `.hermes` total size and top contributors
```bash
du -sh ~/.hermes
du -sh ~/.hermes/* | sort -hr | head -20
```

### 2. Find large files (>100MB) inside `.hermes`
```bash
find ~/.hermes -type f -size +100M -exec ls -lh {} \;
```

### 3. Find stale files (>90 days) inside `.hermes`
```bash
find ~/.hermes -type f -mtime +90 -exec ls -lh {} \;
```

### 4. Identify cache directories and their sizes
```bash
find ~/.hermes -type d -name "*cache*" -o -name "*Cache*" | xargs du -sh
```

### 5. Check for duplicate/contradicting config files
```bash
find ~/.hermes -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.toml" | xargs ls -la
```
Look for:
- Multiple `config.yaml` variants
- Old `config.yaml.bak` or `.bak` files
- Conflicting `profiles/` directories

### 6. Verify SQLite database integrity (sessions, memories, cron state)
```bash
find ~/.hermes -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" | while read db; do
  echo "=== $db ==="
  sqlite3 "$db" "PRAGMA integrity_check;" 2>/dev/null || echo "sqlite3 not available or corrupt"
done
```

### 7. Run `hermes doctor` and capture full output
```bash
hermes doctor 2>&1
```
Parse for:
- Filesystem warnings
- Config validation errors
- Credential issues (see `hermes-credential-diagnostics`)
- Model/provider connectivity failures

### 8. Broader system cache audit (Termux/Android focus)
```bash
# Termux package cache
du -sh ~/.cache 2>/dev/null
du -sh /data/data/com.termux/cache 2>/dev/null

# pip/uv cache
du -sh ~/.cache/pip 2>/dev/null
du -sh ~/.cache/uv 2>/dev/null

# npm/yarn/pnpm cache
du -sh ~/.npm 2>/dev/null
du -sh ~/.cache/yarn 2>/dev/null
du -sh ~/.local/share/pnpm 2>/dev/null

# Docker/podman if present
docker system df 2>/dev/null || podman system df 2>/dev/null

# Temporary files
du -sh /tmp 2>/dev/null
```

### 9. Check for orphaned Hermes processes/sockets
```bash
ls -la ~/.hermes/*.sock 2>/dev/null
ls -la ~/.hermes/*.pid 2>/dev/null
ps aux | grep -E "hermes|supervisord" | grep -v grep
```

## Cleanup Actions (require user approval)

| Finding | Safe to remove? | Command |
|---|---|---|
| `~/.hermes/cache/*` | Yes (regenerated) | `rm -rf ~/.hermes/cache/*` |
| `~/.hermes/logs/*.log` older than 30 days | Yes | `find ~/.hermes/logs -name "*.log" -mtime +30 -delete` |
| `~/.hermes/backups/` old snapshots | Keep latest 3 | Manual review |
| `~/.cache/pip`, `~/.cache/uv` | Yes | `pip cache purge`, `uv cache clean` |
| `~/.npm`, `~/.cache/yarn` | Yes | `npm cache clean --force` |
| Stale `*.bak`, `*.backup` files | Yes | `find ~/.hermes -name "*.bak" -delete` |
| Old session DBs (`.db-journal`, `.db-wal`) | If no active process | `find ~/.hermes -name "*.db-*" -delete` |

## Reporting Template

```
=== HERMES FOLDER HEALTH REPORT ===
Total .hermes size: X GB
Top 5 directories:
  1. path: X GB
  2. path: X GB
  ...

Large files (>100MB): [list]
Stale files (>90 days): [list]
Cache directories: [list with sizes]
SQLite integrity: [OK/CORRUPT per DB]
hermes doctor: [PASS/FAIL - details]
System cache total: X GB
Orphaned processes: [list]

RECOMMENDED CLEANUP:
- [ ] Remove ~/.hermes/cache/* (X MB)
- [ ] Prune logs >30 days (X MB)
- [ ] Clean pip/uv/npm caches (X MB)
- [ ] Remove stale .bak files (X MB)
- [ ] Vacuum SQLite DBs (X MB savings)

Awaiting approval for: [items]
```

## Pitfalls
- **Never delete `~/.hermes/.env`** — contains API keys (see `hermes-credential-diagnostics`).
- **Never delete `~/.hermes/config.yaml`** without a verified backup.
- **Never delete `~/.hermes/skills/`** unless you intend to reinstall them.
- **Never delete `~/.hermes/sessions/`** or `~/.hermes/memories/` — these are user data.
- **Termux/Android**: `/data/data/com.termux` is the real app storage; `~` may be a symlink. Check both.
- **Supervisord sockets/pids** in `.hermes/` are active if gateway is running — stop gateway first (`supervisorctl -c ~/.hermes/supervisord.conf stop hermes-gateway`) before cleaning.
- **SQLite vacuum** requires `sqlite3` binary; on Termux install via `pkg install sqlite`.

## Related Skills
- `hermes-credential-diagnostics` — for doctor credential failures
- `hermes-gateway-ops` — for gateway/supervisord issues
- `termux-system-health` — for broader Termux/Android disk/memory diagnosis