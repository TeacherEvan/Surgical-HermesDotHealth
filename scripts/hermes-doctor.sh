#!/usr/bin/env bash
set -euo pipefail

# Hermes Folder Health Diagnostic v1.2.1
# Portable: linux, macos, windows-git-bash, termux
# Usage: bash scripts/hermes-doctor.sh [--help] [--apply] [--live]

APPLY=0
LIVE=0

for arg in "$@"; do
  case "$arg" in
    --help)
      echo "Usage: bash scripts/hermes-doctor.sh [--help] [--apply] [--live]"
      echo "  --help    Print this usage and exit"
      echo "  --apply   Reserved; exits 3. This script never mutates anything."
      echo "  --live    Enable real network probes per backend (hermes doctor --live)"
      exit 0
      ;;
    --apply) APPLY=1 ;;
    --live)  LIVE=1 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

HERMES_HOME="${HOME}/.hermes"
VENDOR_EXCLUDES=(-not -path "*/node_modules/*" -not -path "*/__pycache__/*"
  -not -path "*/.venv/*" -not -path "*/venv/*" -not -path "*/.git/*"
  -not -path "*/skills-vendor/*" -not -path "*/hermes-agent/*"
  -not -path "*/backups/*" -not -path "*/lsp/*")

echo "=== HERMES FOLDER HEALTH REPORT ==="
echo "Host: $(hostname) | User: $(whoami) | Date: $(date)"
echo ""

# Step 0: Host pressure de-escalation
echo "--- Step 0: Host disk pressure ---"
# -P = POSIX output, -k = 1K blocks: stable columns on Linux, macOS and BusyBox,
# and immune to the G/M/T suffix that `df -h` switches between by volume size.
DF_OUT=$(df -Pk ~ 2>/dev/null || echo "")
if [ -n "$DF_OUT" ]; then
  USE_PCT=$(echo "$DF_OUT" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  FREE_KB=$(echo "$DF_OUT" | awk 'NR==2 {print $4}')
  case "${USE_PCT:-}" in ''|*[!0-9]*) USE_PCT=100 ;; esac
  case "${FREE_KB:-}" in ''|*[!0-9]*) FREE_KB=0 ;; esac
  FREE_GB=$(( FREE_KB / 1048576 ))
  echo "  Disk use: ${USE_PCT}% | Free: ${FREE_GB} GB"
  if [ "$USE_PCT" -lt 80 ] && [ "$FREE_GB" -gt 10 ]; then
    echo "  No disk pressure (Use% < 80 AND free > 10 GB) - de-escalating"
    echo "  Skipping full scan per skill Step 0."
    exit 0
  fi
fi

# Step 1: hermes doctor
echo "--- Step 1: hermes doctor ---"
if command -v hermes &>/dev/null; then
  if [ "$LIVE" -eq 1 ]; then
    hermes doctor --live 2>&1 || echo "  (hermes doctor --live exited non-zero)"
  else
    hermes doctor 2>&1 || echo "  (hermes doctor exited non-zero)"
  fi
else
  echo "  hermes CLI not found on PATH"
fi
echo ""

# Step 2: .hermes size
echo "--- Step 2: .hermes size (top 25) ---"
if [ -d "$HERMES_HOME" ]; then
  # `-d 1` is understood by GNU coreutils and BSD du; `--max-depth` is GNU-only
  # and silently produced an empty report on macOS.
  du -h -d 1 "$HERMES_HOME" 2>/dev/null | sort -hr | head -25
else
  echo "  $HERMES_HOME not found"
fi
echo ""

# Step 3: Large files (>100M)
echo "--- Step 3: Large files (>100M, excl vendor) ---"
find "$HERMES_HOME" -type f -size +100M \
  "${VENDOR_EXCLUDES[@]}" -exec ls -lh {} \; 2>/dev/null || echo "  (none found)"
echo ""

# Step 4: Stale files (>90 days)
echo "--- Step 4: Stale files (>90 days, excl vendor) ---"
find "$HERMES_HOME" -type f -mtime +90 \
  "${VENDOR_EXCLUDES[@]}" -exec ls -lh {} \; 2>/dev/null || echo "  (none found)"
echo ""

# Step 5: Cache directories
echo "--- Step 5: Cache directories (excl vendor) ---"
find "$HERMES_HOME" \( -type d -name "*cache*" -o -type d -name "*Cache*" \) \
  -not -name "__pycache__" \
  -not -path "*/__pycache__/*" -not -path "*/.venv/*" -not -path "*/venv/*" \
  -not -path "*/node_modules/*" -not -path "*/.git/*" \
  -not -path "*/skills-vendor/*" -not -path "*/backups/*" \
  -print0 2>/dev/null | xargs -0 du -sh 2>/dev/null | sort -hr || echo "  (none found)"
echo ""

# Step 6: Duplicate / conflicting config files
echo "--- Step 6: Config files (yaml/json/toml) ---"
find "$HERMES_HOME" \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.toml" \) \
  -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/venv/*" \
  -not -path "*/.git/*" -not -path "*/skills-vendor/*" -not -path "*/hermes-agent/*" \
  -print0 2>/dev/null | xargs -0 ls -la 2>/dev/null || echo "  (none found)"
echo ""

# Step 7: SQLite integrity (via python3)
echo "--- Step 7: SQLite integrity check ---"
find "$HERMES_HOME" -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) \
  "${VENDOR_EXCLUDES[@]}" -print0 2>/dev/null | while IFS= read -r -d '' db; do
  echo "=== $db ==="
  python3 - "$db" << 'PY'
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
echo ""

# Step 8: Broader system cache audit
echo "--- Step 8: System caches (outside .hermes) ---"
for p in ~/.cache/pip ~/.cache/uv ~/.npm ~/.cache/yarn ~/.cache; do
  printf "  %-28s " "$p"
  du -sh "$p" 2>/dev/null || echo "absent"
done
docker system df 2>/dev/null || podman system df 2>/dev/null || true
du -sh /tmp 2>/dev/null || echo "  /tmp absent"
echo ""

# Step 9: Orphaned processes
echo "--- Step 9: Live hermes processes ---"
ls -la "$HERMES_HOME"/*.sock "$HERMES_HOME"/*.pid 2>/dev/null || echo "  (no sockets/pids found)"
pgrep -fl hermes 2>/dev/null || echo "  no hermes process running"
echo ""

# Report template
echo "=== HERMES FOLDER HEALTH REPORT ==="
echo "Host disk: $(df -h ~ 2>/dev/null | awk 'NR==2 {print $5" used, "$4" free}')"
echo "Total .hermes: $(du -sh "$HERMES_HOME" 2>/dev/null | awk '{print $1}')"
echo "  APP/VENDOR (do not prune): hermes-agent $(du -sh "$HERMES_HOME/hermes-agent" 2>/dev/null | awk '{print $1}'), skills-vendor $(du -sh "$HERMES_HOME/skills-vendor" 2>/dev/null | awk '{print $1}'), lsp $(du -sh "$HERMES_HOME/lsp" 2>/dev/null | awk '{print $1}')"
echo "  USER DATA: state.db $(du -sh "$HERMES_HOME/state.db" 2>/dev/null | awk '{print $1}'), sessions $(du -sh "$HERMES_HOME/sessions" 2>/dev/null | awk '{print $1}')"
echo "  CACHE/TRANSIENT: cache $(du -sh "$HERMES_HOME/cache" 2>/dev/null | awk '{print $1}'), logs $(du -sh "$HERMES_HOME/logs" 2>/dev/null | awk '{print $1}')"
echo "Large files (>100M, excl vendor): $(find "$HERMES_HOME" -type f -size +100M "${VENDOR_EXCLUDES[@]}" 2>/dev/null | wc -l) found"
echo "Stale files (>90 days, excl vendor): $(find "$HERMES_HOME" -type f -mtime +90 "${VENDOR_EXCLUDES[@]}" 2>/dev/null | wc -l) found"
echo "Cache dirs: $(find "$HERMES_HOME" \( -type d -name '*cache*' -o -type d -name '*Cache*' \) -not -name '__pycache__' -not -path '*/__pycache__/*' -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/skills-vendor/*' -not -path '*/backups/*' 2>/dev/null | wc -l) found"
echo "SQLite integrity: $(find "$HERMES_HOME" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) "${VENDOR_EXCLUDES[@]}" 2>/dev/null | wc -l) DBs checked"
echo "hermes doctor: $(command -v hermes &>/dev/null && echo 'ran' || echo 'skipped')"
echo "System caches outside .hermes: ~/.npm $(du -sh ~/.npm 2>/dev/null | awk '{print $1}'), ~/.cache/pip $(du -sh ~/.cache/pip 2>/dev/null | awk '{print $1}')"
echo "Live hermes process: $(pgrep -fl hermes 2>/dev/null | wc -l) running"
echo ""
echo "RECOMMENDED CLEANUP (awaiting approval):"
echo "- [ ] pip/uv/npm caches"
echo "- [ ] ~/.hermes/cache/*"
echo "- [ ] logs >30d"
echo "- [ ] stale .bak"
echo "- [ ] vacuum state.db (only if no live process)"
if [ "$APPLY" -eq 1 ]; then
  echo ""
  echo "*** --apply is not implemented. This script is read-only by design." >&2
  echo "*** Work through RECOMMENDED CLEANUP manually, one path at a time." >&2
  exit 3
fi
