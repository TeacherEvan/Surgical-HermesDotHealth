# Health Report Script and Desktop Output

## Script location

`~/hermes-dothealth-report` (Python executable, NOT inside `.hermes/`).
Produces:
- `~/Desktop/hermes-health-report.html` (replaces previous)
- `~/.hermes/health-snapshot.json` (metrics for delta comparison)
- Log at `~/.hermes/logs/health-report.log`

## Known bug — `UnboundLocalError` in `collect_size()`

The `rows` list is referenced by a `for p in HERMES_HOME.iterdir()` loop before `rows = []` is assigned. Fix: move `rows = []` before that loop.

Generalizable rule: always initialize collection variables (`rows`, `sub`, `files`) before any loop that appends to them, even when a second loop also assigns them — Python treats any assignment in the function as a local, so references before the assignment raise `UnboundLocalError`.

## Desktop HTML gap — missing findings/recommendations/safe-to-delete

The `~/hermes-dothealth-report` script produces a desktop HTML but initially omitted structured `Findings` (grouped by severity), `Recommendations` (with verification status), and `Safe-to-delete` sections. Fix: insert these sections before the `<footer>` in the generated HTML, or patch the Python script's `build_html()` to include them by default.

Verification after fix: `grep -c '<h2>🔍 Findings' ~/Desktop/hermes-health-report.html` returns 1, same for Recommendations and Safe-to-delete.

## Best practices for cleanup recommendations

When the user approves recommendations (e.g., `proceed with recommendations following best practices`):
- Back up `state.db`: `cp ~/.hermes/state.db backups/state.db.backup-<timestamp>.bak`
- Archive (not delete) emergency backups: `mv ... archive/state-backups-<date>/`
- Only delete verified safe items: 0-byte stale locks, completed migration artifacts, partial `.partial` files, leftover session/interrupted turn data
- Regenerate desktop HTML after cleanup and verify timestamp is fresh
- Confirm health snapshot updated (`~/.hermes/health-snapshot.json`)
- Confirm partial files removed (`ls .../*.partial` returns none)

## Verification sequence (run after any script change)

1. `sqlite3 ~/.hermes/state.db 'PRAGMA integrity_check;'`
2. `python3 ~/hermes-dothealth-report` (or via venv)
3. Confirm `~/Desktop/hermes-health-report.html` exists and timestamp is fresh.
4. Confirm `~/.hermes/health-snapshot.json` updated.
5. Confirm `crontab -l | grep hermes-dothealth` shows `0 5 * * *`.

## Verified Cleanup Commands (2026-10-24)

The following targeted `rm -f` / `rm -rf` commands were executed and verified to reduce `.hermes` from 8.0 GB → 7.2 GB with `lock_stale: 0`:

**Stale locks (zero-byte, safe):**
```bash
rm -f ~/.hermes/kanban.db.init.lock ~/.hermes/.hermes-update-in-progress.lock \
  ~/.hermes/kanban.db.dispatch.lock ~/.hermes/.env.lock ~/.hermes/processes.json.lock \
  ~/.hermes/skills/.usage.json.lock ~/.hermes/bot-desktop/install.lock \
  ~/.hermes/cron/.fire-*.lock ~/.hermes/cron/.jobs.lock \
  ~/.hermes/runtime/active_sessions.lock ~/.hermes/shared/nous_auth.lock \
  ~/.hermes/mcp-tokens/vercel.json.refresh.lock ~/.hermes/mcp-tokens/hugging_face.json.refresh.lock \
  ~/.hermes/hermes-agent/uv.lock ~/.hermes/hermes-agent/flake.lock \
  ~/.hermes/memories/MEMORY.md.lock ~/.hermes/plugins/.install-metadata.json.lock \
  ~/.hermes/plugins/hindsight/uv.lock ~/.hermes/platforms/pairing/.lock \
  ~/.hermes/hermes-agent/.git/hermes-update.lock ~/.hermes/hermes-agent/.git/hermes-pack-tidy.lock \
  ~/.hermes/hermes-agent/data/.openviking.lock ~/.hermes/hermes-agent/pm/uv.lock \
  ~/.hermes/logs/update_receipts/.pm-write.lock ~/.hermes/runtime/bot_live_delivery/.lock \
  ~/.hermes/lsp/node_modules/fuzzy-search/yarn.lock \
  ~/.hermes/cache/scratch/uv-*.lock ~/.hermes/cache/scratch/uv-setuptools-*.lock \
  ~/.hermes/installs/*/.install.lock ~/.hermes/installs/*/pm-runtime/.prepare.lock \
  ~/.hermes/installs/*/pm-runtime/generations/*/.lock \
  ~/.hermes/installs/*/environments/*/venv/.lock \
  ~/.hermes/installs/*/environments/*/workspace/uv.lock \
  ~/.hermes/installs/*/environments/*/workspace/pm/uv.lock \
  ~/.hermes/installs/*/environments/*/workspace/plugin-sources/hindsight-*/uv.lock \
  ~/.hermes/skills/.locks/*.lock
```

**OpenViking run locks:**
```bash
rm -f ~/.hermes/openviking/runs/*.lock
```

**Worker outbox locks:**
```bash
rm -f ~/.hermes/worker-outboxes/*/owner.lock
```

**Node/yarn locks in hermes-agent:**
```bash
rm -f ~/.hermes/hermes-agent/node_modules/*/yarn.lock
```

**uv wheel/sdist cache (NOT cleared by `uv cache prune --ci`):**
```bash
rm -rf ~/.hermes/cache/uv/wheels-v7 ~/.hermes/cache/uv/sdists-v9 \
  ~/.hermes/cache/uv/sdists-v10 ~/.hermes/cache/uv/archive-v0
```

**Old backup zips (keep last 2):**
```bash
ls -t ~/.hermes/backups/hermes-backup-*.zip | tail -n +3 | xargs rm -f
```

**Logs > 7 days:**
```bash
find ~/.hermes/logs -name "*.log" -mtime +7 -delete
```

**Verification after cleanup:** Re-run `~/hermes-dothealth-report` and confirm:
- Total size reduced (target: cache < 500 MB, stale locks = 0)
- `lock_stale: 0` in health-snapshot.json
- SQLite health: good, freelist_pct: 0.0
- Config YAML: valid

## Cron

Installed in user's crontab (`crontab -l`) as:
```
0 5 * * * <venv_python> ~/hermes-dothealth-report >> ~/.hermes/logs/health-report.log 2>&1
TZ=Africa/Johannesburg
```
This runs every morning and replaces the desktop HTML.
