#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# MCPSearch Termux Installer — Master Script (v1.8.1, all 4 phases + cleanup)
#
# Changelog:
#  - v1.0: Initial 4-phase installer (clone, patch, install, self-test)
#  - v1.1: Termux /tmp sandbox fix, line-aware regex patch (skip import
#          lines), full multi-line function signature capture fix.
#  - v1.2: hishel async-cache fixes, verified end-to-end.
#  - v1.3: visual feedback for Phase 1 (spinner + per-package progress bar).
#  - v1.4: CRITICAL here-doc terminator fix (unquoted closing delimiters).
#  - v1.5: self-integrity guard against truncated downloads.
#  - v1.6: auto-detect Python version for the Rust link flag.
#  - v1.7: storage & native-build hardening (package-aware tiers, memory-safe
#          Rust builds, Phase 0 storage check, --no-cache-dir, Phase 5
#          cleanup, --no-rust flag).
#  - v1.8: full CLI surface & runtime ergonomics (modes, skips, tuning).
#  - v1.8.1: fixes critical launcher expansion bug (unquoted heredocs for run.sh
#            and mcp_client_snippet.json), fixes CLI option shifting bug
#            (spurious unknown-option warnings), threads dynamic $APP_DIR through
#            all embedded patch/test scripts, restricts --check to self-tests,
#            makes --dry-run zero-side-effect, and cleans up dead code.
# ============================================================================
set -uo pipefail

VERSION="1.8.1"

# --- Configurable paths/env (env-overridable, then flags) ------------------
APP_DIR="${MCPSEARCH_APP_DIR:-$HOME/MCPSearch}"
LOG_DIR="${MCPSEARCH_LOG_DIR:-$HOME/.mcpsearch_logs}"
CFG_DIR="${MCPSEARCH_CONFIG_DIR:-$HOME/.mcpsearch}"
TMPDIR="${MCPSEARCH_TMP_DIR:-$HOME/.mcpsearch_tmp}"
REPO_URL="${MCPSEARCH_REPO_URL:-https://github.com/JonusNattapong/MCPSearch}"
BRANCH="${MCPSEARCH_BRANCH:-main}"
PY="${MCPSEARCH_PYTHON:-python3}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

# --- Behavior defaults -----------------------------------------------------
SKIP_UPGRADE=0
KEEP_TMP=0
NO_CACHE_TEST=0
FORCE_REINSTALL=0
VERBOSE=0
DRY_RUN=0
CHECK_ONLY=0
UNINSTALL=0
PURGE=0
NO_RUST=0
NO_COLOR=0
YES=0
NO_PROGRESS=0
NO_FAIL_FAST=0
LOG_LEVEL="info"

# Tuning defaults
TIMEOUT=60
JOBS="${CARGO_BUILD_JOBS:-1}"
OPT_LEVEL="${MCPSEARCH_RUST_OPT:-1}"

# Sub-step skip toggles
NO_PKG=0
NO_UPDATE=0
NO_CLONE=0
NO_PATCH=0
NO_STRIP_PLAYWRIGHT=0
NO_ANYSLITE=0
NO_EDITABLE=0
NO_ENSUREPIP=0
NO_PIP_UPGRADE=0
NO_SELFTEST=0
NO_CLEANUP=0
NO_VERIFY=0

# Cache-test overrides
CACHE_TEST_URL="https://httpbin.org/get"
CACHE_TEST_TIMEOUT=30
CACHE_TEST_RETRIES=2
CACHE_TEST_BACKOFF=1.0
CACHE_TEST_INTERVAL=0.0
NO_HTTPBIN=0

# --- CLI argument parsing --------------------------------------------------
usage() {
  cat << 'HELPEOF'
MCPSearch Termux Installer (v1.8.1)

Usage:
  bash install_mcpsearch.sh [options]

Modes:
  --help               Show this help and exit.
  --version            Print version and exit.
  --dry-run            Print the plan (paths, flags, phases) without changing
                       anything, then exit.
  --check              Run only Phase 4 self-tests against an existing install
                       (skips clone/patch/install/cleanup).
  --uninstall          Remove the installed MCPSearch package and generated
                       artifacts (launcher, config snippet, source tree).
  --purge              Like --uninstall but also removes logs, config dir, and
                       the scratch tmp dir.

Install behavior:
  --skip-upgrade       Skip 'pkg upgrade' (the slowest step).
  --force-reinstall    Force a clean clone (rm -rf source tree) instead of
                       fetch+reset.
  --keep-tmp           Keep the scratch tmp dir for debugging.
  --no-rust            Skip the Rust toolchain and the Rust-link fallback tier.
  --no-cache-test      Skip Phase 4b (network-dependent HTTP cache smoke test).
  --no-progress        Disable animated spinner/progress bars.
  --no-fail-fast       Downgrade 'fatal' errors to warnings and continue.
  --verbose            Stream command logs to the console as well as files.
  --yes                Auto-confirm prompts (e.g. uninstall/purge).
  --no-color           Disable ANSI colors.
  --log-level LEVEL    debug|info|warn|error (default: info).

Sub-step skips:
  --no-update          Skip 'pkg update'.
  --no-pkg             Skip the Phase 1 package install loop.
  --no-ensurepip       Skip 'python -m ensurepip'.
  --no-pip-upgrade     Skip 'pip install --upgrade pip'.
  --no-clone           Assume the source tree already exists (skip clone).
  --no-strip-playwright  Skip removing Playwright from pyproject.toml.
  --no-anysqlite       Skip inserting the anysqlite dependency.
  --no-patch           Skip regex-patching server.py and http_client.py.
  --no-editable        Skip the editable install of MCPSearch.
  --no-selftest        Skip the Phase 4 self-tests.
  --no-cleanup         Skip Phase 5 cleanup.
  --no-verify          Skip grep-based verification of patch results.

Paths & source:
  --branch BRANCH      Upstream MCPSearch branch to clone (default: main).
  --repo-url URL       Upstream MCPSearch repo URL.
  --app-dir DIR        Where to clone MCPSearch (default: ~/MCPSearch).
  --log-dir DIR        Log directory (default: ~/.mcpsearch_logs).
  --config-dir DIR     Config/launcher directory (default: ~/.mcpsearch).
  --tmp-dir DIR        Scratch directory (default: ~/.mcpsearch_tmp).
  --prefix DIR         Termux prefix (default: $PREFIX).
  --python CMD         Python interpreter (default: python3).

Tuning:
  --timeout SEC        Base timeout for pip/git ops (default: 60).
  --jobs N             Rust/pip build parallelism (default: 1).
  --opt-level N        Rust optimization level, 0-3 (default: 1).

Cache test overrides (Phase 4b):
  --cache-test-url URL           URL to fetch (default: https://httpbin.org/get).
  --cache-test-timeout SEC       Request timeout (default: 30).
  --cache-test-retries N         Retries (default: 2).
  --cache-test-backoff F         Retry backoff seconds (default: 1.0).
  --cache-test-interval F        Interval between the two requests (default: 0.0).
  --no-httpbin                   Alias for --no-cache-test (skip the external call).

Environment variables (lower priority than flags):
  MCPSEARCH_APP_DIR, MCPSEARCH_LOG_DIR, MCPSEARCH_CONFIG_DIR,
  MCPSEARCH_TMP_DIR, MCPSEARCH_REPO_URL, MCPSEARCH_BRANCH, MCPSEARCH_PYTHON,
  MCPSEARCH_RUST_OPT, CARGO_BUILD_JOBS
HELPEOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --version) echo "MCPSearch Termux Installer v$VERSION"; exit 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --purge) PURGE=1; shift ;;
    --skip-upgrade) SKIP_UPGRADE=1; shift ;;
    --force-reinstall) FORCE_REINSTALL=1; shift ;;
    --keep-tmp) KEEP_TMP=1; shift ;;
    --no-rust) NO_RUST=1; shift ;;
    --no-cache-test|--no-http-cache-test|--no-httpbin) NO_CACHE_TEST=1; shift ;;
    --no-progress) NO_PROGRESS=1; shift ;;
    --no-fail-fast) NO_FAIL_FAST=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --no-color) NO_COLOR=1; shift ;;
    --no-update) NO_UPDATE=1; shift ;;
    --no-pkg) NO_PKG=1; shift ;;
    --no-ensurepip) NO_ENSUREPIP=1; shift ;;
    --no-pip-upgrade) NO_PIP_UPGRADE=1; shift ;;
    --no-clone) NO_CLONE=1; shift ;;
    --no-strip-playwright) NO_STRIP_PLAYWRIGHT=1; shift ;;
    --no-anysqlite) NO_ANYSLITE=1; shift ;;
    --no-patch) NO_PATCH=1; shift ;;
    --no-editable) NO_EDITABLE=1; shift ;;
    --no-selftest) NO_SELFTEST=1; shift ;;
    --no-cleanup) NO_CLEANUP=1; shift ;;
    --no-verify) NO_VERIFY=1; shift ;;
    --log-level) LOG_LEVEL="$2"; shift 2 ;;
    --log-level=*) LOG_LEVEL="${1#*=}"; shift ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --branch=*) BRANCH="${1#*=}"; shift ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --repo-url=*) REPO_URL="${1#*=}"; shift ;;
    --app-dir) APP_DIR="$2"; shift 2 ;;
    --app-dir=*) APP_DIR="${1#*=}"; shift ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    --log-dir=*) LOG_DIR="${1#*=}"; shift ;;
    --config-dir) CFG_DIR="$2"; shift 2 ;;
    --config-dir=*) CFG_DIR="${1#*=}"; shift ;;
    --tmp-dir) TMPDIR="$2"; shift 2 ;;
    --tmp-dir=*) TMPDIR="${1#*=}"; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    --python) PY="$2"; shift 2 ;;
    --python=*) PY="${1#*=}"; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --timeout=*) TIMEOUT="${1#*=}"; shift ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --jobs=*) JOBS="${1#*=}"; shift ;;
    --opt-level) OPT_LEVEL="$2"; shift 2 ;;
    --opt-level=*) OPT_LEVEL="${1#*=}"; shift ;;
    --cache-test-url) CACHE_TEST_URL="$2"; shift 2 ;;
    --cache-test-url=*) CACHE_TEST_URL="${1#*=}"; shift ;;
    --cache-test-timeout) CACHE_TEST_TIMEOUT="$2"; shift 2 ;;
    --cache-test-timeout=*) CACHE_TEST_TIMEOUT="${1#*=}"; shift ;;
    --cache-test-retries) CACHE_TEST_RETRIES="$2"; shift 2 ;;
    --cache-test-retries=*) CACHE_TEST_RETRIES="${1#*=}"; shift ;;
    --cache-test-backoff) CACHE_TEST_BACKOFF="$2"; shift 2 ;;
    --cache-test-backoff=*) CACHE_TEST_BACKOFF="${1#*=}"; shift ;;
    --cache-test-interval) CACHE_TEST_INTERVAL="$2"; shift 2 ;;
    --cache-test-interval=*) CACHE_TEST_INTERVAL="${1#*=}"; shift ;;
    *) echo "  \033[1;33m⚠\033[0m unknown option ignored: $1"; shift ;;
  esac
done

# --- Python interpreter & Rust tuning defaults ------------------------------
command -v "$PY" >/dev/null 2>&1 || { command -v python3 >/dev/null 2>&1 && PY="python3" || PY="python"; }
PYVER=$("$PY" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "3.11")

export CARGO_BUILD_JOBS="$JOBS"
RUST_OPT="$OPT_LEVEL"

# --- Colors & logging ------------------------------------------------------
if [ "$NO_COLOR" -eq 1 ]; then
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
else
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
fi

# Numeric log-level threshold: debug=0 info=1 warn=2 error=3
case "$LOG_LEVEL" in
  debug) _LEVEL=0 ;; warn) _LEVEL=2 ;; error) _LEVEL=3 ;; *) _LEVEL=1 ;;
esac

log() { # log LEVEL msg
  local lvl="$1" msg="$2" n=1
  case "$lvl" in debug) n=0 ;; info) n=1 ;; warn) n=2 ;; error) n=3 ;; esac
  [ "$n" -ge "$_LEVEL" ] && echo -e "$msg"
}

step(){ log info "\n${CYAN}▶ $*${NC}"; }
ok(){ log info "  ${GREEN}✔${NC} $*"; }
err(){ log error "  ${RED}✘${NC} $*"; }
warn(){ log warn "  ${YELLOW}⚠${NC} $*"; }
fatal(){
  if [ "$NO_FAIL_FAST" -eq 1 ]; then
    warn "$* (continuing due to --no-fail-fast)"
  else
    err "$*"; echo -e "${RED}Aborted. Logs: $LOG_DIR${NC}"; exit 1
  fi
}

# --- Self-integrity check --------------------------------------------------
_SELF="$0"
for _delim in HELPEOF PYEOF LAUNCHER_EOF JSONEOF TESTEOF CACHETESTEOF; do
  if ! grep -q "^${_delim}$" "$_SELF"; then
    echo -e "${RED}✘ This installer file appears truncated (missing here-doc terminator '${_delim}').${NC}"
    echo -e "${RED}  The download was incomplete. Please re-download it fully, e.g.:${NC}"
    echo -e "${YELLOW}  cd ~ && rm -rf mcpsearch-installer-android-termux && git clone https://github.com/tailscale-signin/mcpsearch-installer-android-termux.git && cd mcpsearch-installer-android-termux && bash install_mcpsearch.sh${NC}"
    exit 1
  fi
done
unset _SELF _delim

# --- Progress helpers ------------------------------------------------------
SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spinner() {
  local pid="$1" msg="$2" i=0
  if [ "$NO_PROGRESS" -eq 1 ]; then wait "$pid"; return; fi
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}%s${NC} %s ..." "${SPIN[$((i % ${#SPIN[@]}))]}" "$msg"
    i=$((i + 1)); sleep 0.1
  done
  printf "\r\033[K"
}
pkg_progress() {
  local cur="$1" total="$2" name="$3" pid="$4" i=0 width=24
  if [ "$NO_PROGRESS" -eq 1 ]; then wait "$pid"; return; fi
  while kill -0 "$pid" 2>/dev/null; do
    local pct=$((cur * 100 / total)) filled=$((cur * width / total)) bar="" j
    for ((j = 0; j < width; j++)); do
      if [ "$j" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
    done
    printf "\r  ${CYAN}%s${NC} installing %-12s ${CYAN}[%s]${NC} %3d%% (%d/%d) ..." \
      "${SPIN[$((i % ${#SPIN[@]}))]}" "$name" "$bar" "$pct" "$cur" "$total"
    i=$((i + 1)); sleep 0.1
  done
  printf "\r\033[K"
}

# --- Dry-run report (strictly read-only) -----------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "${BOLD}${CYAN}== MCPSearch Termux Installer — DRY RUN (v$VERSION) ==${NC}"
  echo "  app-dir:      $APP_DIR"
  echo "  log-dir:      $LOG_DIR"
  echo "  config-dir:   $CFG_DIR"
  echo "  tmp-dir:      $TMPDIR"
  echo "  prefix:       $PREFIX"
  echo "  python:       $PY ($PYVER)"
  echo "  repo-url:     $REPO_URL"
  echo "  branch:       $BRANCH"
  echo "  timeout:      ${TIMEOUT}s   jobs: $JOBS   rust-opt: $OPT_LEVEL"
  echo "  skip-upgrade: $SKIP_UPGRADE   force-reinstall: $FORCE_REINSTALL"
  echo "  no-rust:      $NO_RUST   no-cache-test: $NO_CACHE_TEST"
  echo "  no-pkg:       $NO_PKG   no-clone: $NO_CLONE   no-patch: $NO_PATCH"
  echo "  no-selftest:  $NO_SELFTEST   no-cleanup: $NO_CLEANUP"
  echo -e "${CYAN}Would run: Phase 0 storage check → Phase 1 packages → Phase 2 clone/patch/install → Phase 3 launcher → Phase 4 self-tests → Phase 5 cleanup.${NC}"
  exit 0
fi

# --- Post-parse directories (created only after --dry-run check) -----------
mkdir -p "$LOG_DIR" "$CFG_DIR" "$TMPDIR"

# --- Uninstall / purge -----------------------------------------------------
if [ "$UNINSTALL" -eq 1 ] || [ "$PURGE" -eq 1 ]; then
  if [ "$YES" -eq 1 ]; then _confirm=1; else
    read -r -p "Remove MCPSearch installation? [y/N] " _ans
    case "$_ans" in y|Y|yes|YES) _confirm=1 ;; *) _confirm=0 ;; esac
  fi
  if [ "$_confirm" -eq 1 ]; then
    echo -e "${CYAN}▶ Uninstalling MCPSearch...${NC}"
    "$PY" -m pip uninstall -y mcpsearch >/dev/null 2>&1 || true
    rm -rf "$APP_DIR"
    rm -f "$CFG_DIR/run.sh" "$CFG_DIR/mcp_client_snippet.json"
    echo -e "  ${GREEN}✔${NC} removed package and source tree"
    if [ "$PURGE" -eq 1 ]; then
      rm -rf "$CFG_DIR" "$LOG_DIR" "$TMPDIR"
      "$PY" -m pip cache purge >/dev/null 2>&1 || true
      echo -e "  ${GREEN}✔${NC} purged config, logs, tmp, and pip cache"
    fi
  fi
  exit 0
fi

echo -e "${BOLD}${CYAN}== MCPSearch Termux Installer — Phases 1-5 (v$VERSION) ==${NC}"

# --- Check-only mode: run Phase 4 against existing install and exit -------
if [ "$CHECK_ONLY" -eq 1 ]; then
  step "Check mode: running Phase 4 self-tests against existing install at $APP_DIR"
  [ -d "$APP_DIR" ] || fatal "no existing install found at $APP_DIR"
  [ -f "$APP_DIR/mcp_server/server.py" ] || fatal "mcp_server/server.py missing in $APP_DIR"

  # Phase 4 self-test
  cat > "$TMPDIR/mcpsearch_selftest.py" << 'TESTEOF'
import sys, os, asyncio, traceback

sys.path.insert(0, "__APP_DIR__")

def fail(msg, exc=None):
    print(f"SELFTEST_FAIL: {msg}")
    if exc:
        traceback.print_exc()
    sys.exit(1)

try:
    from mcp_server import server as srv
except Exception as e:
    fail("could not import mcp_server.server", e)

try:
    tool_names = sorted(getattr(t, "name", str(t)) for t in srv.mcp._tool_manager._tools.values()) \
        if hasattr(srv, "mcp") else []
    print(f"SELFTEST_INFO: discovered {len(tool_names)} tools")
    for n in tool_names:
        print("   -", n)
except Exception as e:
    print(f"SELFTEST_WARN: could not enumerate tools cleanly ({e})")

async def run_smoke_call():
    if hasattr(srv, "get_crawl_stats"):
        try:
            result = await srv.get_crawl_stats.fn() if hasattr(srv.get_crawl_stats, "fn") else await srv.get_crawl_stats()
            print("SELFTEST_INFO: get_crawl_stats() returned:", str(result)[:200])
        except Exception as e:
            fail("get_crawl_stats() raised an exception", e)
    else:
        print("SELFTEST_WARN: get_crawl_stats not found, skipping smoke call")

try:
    asyncio.run(run_smoke_call())
except SystemExit:
    raise
except Exception as e:
    fail("smoke call crashed unexpectedly", e)

print("SELFTEST_PASS")
TESTEOF
  sed -i "s|__APP_DIR__|${APP_DIR}|g" "$TMPDIR/mcpsearch_selftest.py"
  if "$PY" "$TMPDIR/mcpsearch_selftest.py" 2>&1 | tee "$LOG_DIR/p4_selftest.log" | grep -q "SELFTEST_PASS"; then
    ok "self-test passed — server imports and responds to a tool call cleanly"
  else
    err "self-test FAILED — see $LOG_DIR/p4_selftest.log for the full traceback"
    exit 1
  fi

  if [ "$NO_CACHE_TEST" -eq 1 ]; then
    warn "skipping Phase 4b HTTP cache smoke test (--no-cache-test)"
  else
    step "Phase 4b: HTTP cache smoke test (hishel + anysqlite, no deprecation warnings)"
    cat > "$TMPDIR/mcpsearch_cache_selftest.py" << 'CACHETESTEOF'
import sys, os, asyncio, warnings, traceback

sys.path.insert(0, "__APP_DIR__")

def fail(msg, exc=None):
    print(f"CACHETEST_FAIL: {msg}")
    if exc:
        traceback.print_exc()
    sys.exit(1)

async def main():
    try:
        from utils.http_client import build_async_client, AsyncHttpClientConfig
    except Exception as e:
        fail("could not import build_async_client/AsyncHttpClientConfig", e)
        return

    with warnings.catch_warnings():
        warnings.simplefilter("error", UserWarning)
        try:
            config = AsyncHttpClientConfig(enable_cache=True, cache_ttl=60, always_cache=True)
            client = build_async_client(config)
        except UserWarning as e:
            fail(f"deprecated-kwarg UserWarning still present: {e}")
            return
        except Exception as e:
            fail("build_async_client() raised unexpectedly", e)
            return

    try:
        r1 = await client.get("__CACHE_TEST_URL__")
        r2 = await client.get("__CACHE_TEST_URL__")
        await client.aclose()
    except Exception as e:
        fail("cached client GET request failed (network or hishel wiring issue)", e)
        return

    hit1 = r1.extensions.get("hishel_from_cache")
    hit2 = r2.extensions.get("hishel_from_cache")
    print(f"CACHETEST_INFO: req1 hishel_from_cache={hit1}, req2 hishel_from_cache={hit2}")

    if hit2 is not True:
        fail(f"expected req2 hishel_from_cache=True under always_cache=True, got {hit2}")
        return

    print("CACHETEST_PASS")

asyncio.run(main())
CACHETESTEOF
    sed -i "s|__APP_DIR__|${APP_DIR}|g" "$TMPDIR/mcpsearch_cache_selftest.py"
    sed -i "s|__CACHE_TEST_URL__|${CACHE_TEST_URL}|g" "$TMPDIR/mcpsearch_cache_selftest.py"
    if "$PY" "$TMPDIR/mcpsearch_cache_selftest.py" 2>&1 | tee "$LOG_DIR/p4b_cache_selftest.log" | grep -q "CACHETEST_PASS"; then
      ok "HTTP cache self-test passed — hishel/anysqlite wired correctly, no deprecation warnings"
    else
      err "HTTP cache self-test FAILED — see $LOG_DIR/p4b_cache_selftest.log for the full traceback"
      exit 1
    fi
  fi
  ok "Check complete. Install at $APP_DIR verified."
  exit 0
fi

# ---------------------------------------------------------------- PHASE 0
step "Phase 0: Storage pre-flight check"
_FREE_KB=$(df -P "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$_FREE_KB" ] && [ "$_FREE_KB" -gt 0 ] 2>/dev/null; then
  _FREE_GB=$((_FREE_KB / 1024 / 1024))
  if [ "$_FREE_GB" -lt 2 ]; then
    warn "Only ~${_FREE_GB}GB free on $HOME. Native builds (pydantic-core, lxml) can need 2-4GB. Free space or run 'termux-setup-storage' before continuing."
  else
    ok "~${_FREE_GB}GB free on $HOME"
  fi
else
  warn "could not determine free space on $HOME"
fi
unset _FREE_KB _FREE_GB

# ---------------------------------------------------------------- PHASE 1
if [ "$NO_PKG" -eq 1 ]; then
  step "Phase 1: Termux packages (skipped via --no-pkg)"
else
  step "Phase 1: Termux packages"
  if [ "$NO_UPDATE" -eq 1 ]; then
    warn "skipping 'pkg update' (--no-update)"
  else
    pkg update -y > "$LOG_DIR/p1.log" 2>&1 &
    _PID=$!; spinner "$_PID" "pkg update"
    if wait "$_PID"; then ok "pkg update"; else warn "pkg update had issues"; fi
  fi

  if [ "$SKIP_UPGRADE" -eq 1 ]; then
    warn "skipping 'pkg upgrade' (--skip-upgrade)"
  else
    pkg upgrade -y >> "$LOG_DIR/p1.log" 2>&1 &
    _PID=$!; spinner "$_PID" "pkg upgrade (this can take a while)"
    if wait "$_PID"; then ok "pkg upgrade"; else warn "pkg upgrade had issues"; fi
  fi

  if [ "$NO_RUST" -eq 1 ]; then
    warn "Rust toolchain skipped (--no-rust). Rust-based packages (pydantic-core) will only install if a prebuilt wheel exists."
    PKGS="python git binutils libjpeg-turbo libxml2 libxslt clang make pkg-config openssl patchelf curl"
  else
    PKGS="python git rust binutils libjpeg-turbo libxml2 libxslt clang make pkg-config openssl patchelf curl"
  fi
  set -- $PKGS
  TOTAL=$#
  CUR=0
  for p in $PKGS; do
    CUR=$((CUR + 1))
    pkg install -y "$p" >> "$LOG_DIR/p1.log" 2>&1 &
    _PID=$!; pkg_progress "$CUR" "$TOTAL" "$p" "$_PID"
    if wait "$_PID"; then ok "$p"; else fatal "failed to install $p (see $LOG_DIR/p1.log)"; fi
  done

  if [ "$NO_ENSUREPIP" -eq 1 ]; then
    warn "skipping 'python -m ensurepip' (--no-ensurepip)"
  else
    "$PY" -m ensurepip --upgrade > "$LOG_DIR/p1_pip.log" 2>&1 || true
  fi
  if [ "$NO_PIP_UPGRADE" -eq 1 ]; then
    warn "skipping pip upgrade (--no-pip-upgrade)"
  else
    "$PY" -m pip install --upgrade pip --break-system-packages >> "$LOG_DIR/p1_pip.log" 2>&1 || warn "pip upgrade had issues"
  fi
  ok "interpreter ready: $("$PY" --version 2>&1)"
fi

# ---------------------------------------------------------------- PHASE 2
step "Phase 2: Clone MCPSearch"
if [ "$NO_CLONE" -eq 1 ]; then
  warn "skipping clone (--no-clone); assuming source already present at $APP_DIR"
else
  if [ "$FORCE_REINSTALL" -eq 1 ]; then
    rm -rf "$APP_DIR"
    git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR" > "$LOG_DIR/p2.log" 2>&1 || fatal "git clone failed (see $LOG_DIR/p2.log)"
    ok "fresh clone complete (--force-reinstall) at $APP_DIR"
  elif [ -d "$APP_DIR/.git" ]; then
    git -C "$APP_DIR" fetch origin >> "$LOG_DIR/p2.log" 2>&1
    git -C "$APP_DIR" reset --hard "origin/$BRANCH" >> "$LOG_DIR/p2.log" 2>&1
    ok "source updated at $APP_DIR"
  else
    rm -rf "$APP_DIR"
    git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR" > "$LOG_DIR/p2.log" 2>&1 || fatal "git clone failed (see $LOG_DIR/p2.log)"
  fi
fi
[ -f "$APP_DIR/pyproject.toml" ] && [ -f "$APP_DIR/mcp_server/server.py" ] || fatal "source tree missing expected files"
ok "source ready at $APP_DIR"

if [ "$NO_STRIP_PLAYWRIGHT" -eq 1 ]; then
  warn "skipping Playwright strip (--no-strip-playwright)"
else
  step "Phase 2: Strip Playwright (HTTP-only mode)"
  sed -i '/[Pp]laywright/d' "$APP_DIR/pyproject.toml"
  ok "playwright references removed from pyproject.toml"
fi

if [ "$NO_ANYSLITE" -eq 1 ]; then
  warn "skipping anysqlite insertion (--no-anysqlite)"
else
  step "Phase 2: Ensure anysqlite dependency for hishel async cache backend"
  if grep -q "anysqlite" "$APP_DIR/pyproject.toml"; then
    ok "anysqlite already declared in pyproject.toml"
  else
    if grep -q '"hishel[^"]*",' "$APP_DIR/pyproject.toml"; then
      sed -i '/"hishel[^"]*"/a\    "anysqlite>=0.0.5",' "$APP_DIR/pyproject.toml"
      ok "anysqlite>=0.0.5 inserted after hishel dependency"
    elif grep -q '"httpx[^"]*",' "$APP_DIR/pyproject.toml"; then
      sed -i '/"httpx[^"]*",/a\    "hishel>=1.0.0",\n    "anysqlite>=0.0.5",' "$APP_DIR/pyproject.toml"
      ok "hishel + anysqlite inserted after httpx dependency"
    else
      warn "could not find hishel/httpx anchor line in pyproject.toml; anysqlite NOT inserted — verify manually"
    fi
  fi
fi

if [ "$NO_PATCH" -eq 1 ]; then
  warn "skipping server.py / http_client.py patches (--no-patch)"
else
  step "Phase 2: Patch mcp_server/server.py (regex-based, idempotent)"
  cat > "$TMPDIR/mcpsearch_patch.py" << 'PYEOF'
import re, sys, os

path = os.path.join("__APP_DIR__", "mcp_server", "server.py")
with open(path, encoding="utf-8") as f:
    src = f.read()
orig = src
notes = []

# 1. Fix undefined get_research_agent_instance -> get_research_agent, ensure import exists
src2 = src.replace("get_research_agent_instance()", "get_research_agent()")
if src2 != src:
    notes.append("fixed get_research_agent_instance -> get_research_agent")
src = src2
if "get_research_agent()" in src and "import get_research_agent" not in src:
    src = re.sub(
        r"(^import .*$|^from .*$)",
        r"\1\nfrom agents.research_agent import get_research_agent",
        src, count=1, flags=re.MULTILINE,
    )
    notes.append("inserted missing get_research_agent import")

# 2. Replace bare factory-object names with their get_X() calls.
bare_names = ["aggregator", "crawler", "summarizer",
              "reddit_scraper", "twitter_scraper", "youtube_scraper", "github_scraper"]
src_lines = src.split("\n")
for name in bare_names:
    pattern = re.compile(r"\b" + name + r"\.")
    replacement = f"get_{name}()."
    count = 0
    for i, line in enumerate(src_lines):
        if re.match(r"^\s*(from|import)\s", line):
            continue
        new_line, n = pattern.subn(replacement, line)
        if n:
            src_lines[i] = new_line
            count += n
    if count:
        notes.append(f"replaced {count}x bare '{name}.' -> 'get_{name}().'")
src = "\n".join(src_lines)

# 3. Fix zero-arg lines.append() -> lines.append("")
new_src, n = re.subn(r"lines\.append\(\)", 'lines.append("")', src)
if n:
    notes.append(f"fixed {n}x empty lines.append()")
src = new_src

# 4. Rebuild investigate()/compare()/trending() bodies.
def replace_function(src, func_name, new_body_source, notes):
    pattern = re.compile(
        r"(async def " + func_name + r"\(.*?-> str:\n)(.*?)(?=\n@mcp\.tool\(|\Z)",
        re.DOTALL,
    )
    m = pattern.search(src)
    if not m:
        notes.append(f"WARNING: could not locate function '{func_name}' to patch")
        return src
    new_src = src[:m.start(2)] + new_body_source + src[m.end(2):]
    notes.append(f"rebuilt body of {func_name}()")
    return new_src

investigate_body = '''    agent = get_research_agent()
    try:
        report = await agent.investigate(
            topic,
            search_depth=depth,
            include_social=include_social,
            include_summary=include_summary,
            max_sources=max_sources,
        )
        findings = report.get("findings", [])
        by_type = {}
        for f in findings:
            by_type.setdefault(f["source"]["source_type"], []).append(f)

        lines = [f"# Research: {topic}\\n", f"**Depth:** {depth} | **Social:** {include_social}\\n"]

        web = by_type.get("web", []) + by_type.get("web_crawled", [])
        if web:
            lines.append("## Web Search Results\\n")
            for i, f in enumerate(web, 1):
                s = f["source"]
                lines.append(f"{i}. **{s.get('title', 'No title')}**")
                lines.append(f"   [{s.get('url', 'N/A')}]({s.get('url', 'N/A')})")
                if f.get("content"):
                    lines.append(f"   {f['content'][:200]}\\n")

        social = [t for t in by_type if t not in ("web", "web_crawled")]
        if social:
            lines.append("\\n## Social Media Insights\\n")
            for platform in social:
                lines.append(f"### {platform.title()}\\n")
                for f in by_type[platform][:3]:
                    lines.append(f"- {f['content'][:150]}")
                lines.append("")

        if report.get("summary"):
            lines.append("\\n## AI Summary\\n")
            lines.append(report["summary"])

        return "\\n".join(lines)
    except Exception as e:
        import logging, traceback
        logging.error(f"investigate error: {e}\\n{traceback.format_exc()}")
        return f"Error: {str(e)}"
'''

compare_body = '''    agent = get_research_agent()
    try:
        topic_list = [t.strip() for t in topics.split(",") if t.strip()]
        comparison = await agent.compare(topic_list, search_depth=depth)

        lines = [f"# Comparison: {' vs '.join(topic_list)}\\n"]
        for topic in topic_list:
            report = comparison["reports"][topic]
            lines.append(f"## {topic}\\n")
            web = [f for f in report.get("findings", [])
                   if f["source"]["source_type"] in ("web", "web_crawled")]
            if web:
                lines.append("### Key Results\\n")
                for f in web[:2]:
                    s = f["source"]
                    lines.append(f"- **{s.get('title', 'N/A')}**")
                    lines.append(f"  {f['content'][:100]}\\n")
            lines.append("")

        return "\\n".join(lines)
    except Exception as e:
        import logging, traceback
        logging.error(f"compare error: {e}\\n{traceback.format_exc()}")
        return f"Error: {str(e)}"
'''

trending_body = '''    try:
        result = {}
        if "github" in platforms:
            result["github"] = await get_github_scraper().get_trending()
        if "reddit" in platforms:
            result["reddit"] = await get_reddit_scraper().get_trending()

        lines = ["# Trending Topics\\n"]
        for platform, items in result.items():
            lines.append(f"## {platform.title()}\\n")
            item_list = items if isinstance(items, list) else (
                getattr(items, "posts", None) or getattr(items, "repos", None) or []
            )
            if item_list:
                for i, item in enumerate(item_list[:5], 1):
                    lines.append(f"{i}. {str(item)[:150]}")
            lines.append("")

        return "\\n".join(lines)
    except Exception as e:
        import logging, traceback
        logging.error(f"trending error: {e}\\n{traceback.format_exc()}")
        return f"Error: {str(e)}"
'''

if "async def investigate(" in src:
    src = replace_function(src, "investigate", investigate_body, notes)
else:
    notes.append("SKIP: no investigate() found")

if "async def compare(" in src:
    src = replace_function(src, "compare", compare_body, notes)
else:
    notes.append("SKIP: no compare() found")

if "async def trending(" in src:
    src = replace_function(src, "trending", trending_body, notes)
else:
    notes.append("SKIP: no trending() found")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print(f"--- patch summary ({len(orig)} -> {len(src)} bytes) ---")
for n in notes:
    print(" -", n)

remaining = re.findall(
    r"\b(?:aggregator|crawler|summarizer|reddit_scraper|twitter_scraper|youtube_scraper|github_scraper)\.\w+\(",
    src,
)
if remaining:
    print("REMAINING SUSPECT PATTERNS (manual review needed):")
    for r in sorted(set(remaining)):
        print("   ", r)
if "get_research_agent_instance" in src:
    print("VERIFY_FAIL: stale get_research_agent_instance still present")
    sys.exit(1)
print("VERIFY_OK: patch script completed without fatal issues")
PYEOF
  sed -i "s|__APP_DIR__|${APP_DIR}|g" "$TMPDIR/mcpsearch_patch.py"
  "$PY" "$TMPDIR/mcpsearch_patch.py" 2>&1 | tee "$LOG_DIR/p2_patch.log"
  if [ "$NO_VERIFY" -eq 1 ]; then
    ok "server.py patch script completed (verification skipped)"
  else
    grep -q "VERIFY_OK" "$LOG_DIR/p2_patch.log" || fatal "server.py patch verification failed, see $LOG_DIR/p2_patch.log"
    ok "server.py patched"
  fi

  step "Phase 2: Patch utils/http_client.py — remove deprecated hishel kwarg (idempotent)"
  cat > "$TMPDIR/mcpsearch_patch_httpclient.py" << 'PYEOF'
import re, os

path = os.path.join("__APP_DIR__", "utils", "http_client.py")
if not os.path.exists(path):
    print("SKIP: utils/http_client.py not found (nothing to patch)")
else:
    with open(path, encoding="utf-8") as f:
        src = f.read()
    orig = src

    src = re.sub(
        r"[ \t]*refresh_ttl_on_access\s*=\s*config\.refresh_on_hit\s*,?\n",
        "",
        src,
    )

    if src != orig:
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
        print("PATCHED: removed deprecated refresh_ttl_on_access kwarg from AsyncSqliteStorage(...)")
    else:
        print("NOOP: no deprecated refresh_ttl_on_access kwarg found (already clean or never present)")
print("VERIFY_OK: http_client.py patch script completed")
PYEOF
  sed -i "s|__APP_DIR__|${APP_DIR}|g" "$TMPDIR/mcpsearch_patch_httpclient.py"
  "$PY" "$TMPDIR/mcpsearch_patch_httpclient.py" 2>&1 | tee "$LOG_DIR/p2_patch_httpclient.log"
  if [ "$NO_VERIFY" -eq 1 ]; then
    ok "http_client.py patch script completed (verification skipped)"
  else
    grep -q "VERIFY_OK" "$LOG_DIR/p2_patch_httpclient.log" || fatal "http_client.py patch verification failed, see $LOG_DIR/p2_patch_httpclient.log"
  fi
  "$PY" -m py_compile "$APP_DIR/utils/http_client.py" 2>>"$LOG_DIR/p2_patch_httpclient.log" \
    && ok "http_client.py patched and compiles cleanly" \
    || fatal "http_client.py failed to compile after patch, see $LOG_DIR/p2_patch_httpclient.log"
fi

step "Phase 2: Install Python dependencies (with fallback tiers)"
install_pkg() {
  local pkg="$1"
  timeout "$TIMEOUT" "$PY" -m pip install --quiet --no-cache-dir --break-system-packages "$pkg" >> "$LOG_DIR/p2_pip.log" 2>&1 && return 0
  warn "$pkg: wheel install failed, retrying --no-binary"
  timeout $((TIMEOUT * 3)) "$PY" -m pip install --quiet --no-cache-dir --break-system-packages --no-binary :all: "$pkg" >> "$LOG_DIR/p2_pip.log" 2>&1 && return 0
  case "$pkg" in
    lxml|selectolax)
      warn "$pkg: retrying with C library link flags (libxml2/libxslt)"
      CFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib" \
      timeout $((TIMEOUT * 4)) "$PY" -m pip install --quiet --no-cache-dir --break-system-packages --force-reinstall --no-binary :all: "$pkg" >> "$LOG_DIR/p2_pip.log" 2>&1
      ;;
    *)
      if [ "$NO_RUST" -eq 1 ]; then
        err "$pkg: needs a Rust source build but --no-rust is set; no prebuilt wheel available"
        return 1
      fi
      warn "$pkg: retrying with rust link flags (python${PYVER})"
      RUSTFLAGS="-C opt-level=${RUST_OPT} -C link-arg=-lpython${PYVER}" CARGO_BUILD_JOBS="$JOBS" \
      timeout $((TIMEOUT * 5)) "$PY" -m pip install --quiet --no-cache-dir --break-system-packages --force-reinstall "$pkg" >> "$LOG_DIR/p2_pip.log" 2>&1
      ;;
  esac
}
DEP_FAIL=0
for pkg in pydantic pydantic-settings httpx beautifulsoup4 lxml selectolax mcp hishel anysqlite; do
  install_pkg "$pkg" && ok "$pkg" || { err "$pkg failed all install tiers"; DEP_FAIL=1; }
done
if [ "$NO_FAIL_FAST" -eq 1 ]; then
  [ "$DEP_FAIL" -eq 1 ] && warn "dependency install had failures (continuing via --no-fail-fast)"
else
  [ "$DEP_FAIL" -eq 1 ] && fatal "dependency install failed (see $LOG_DIR/p2_pip.log)"
fi

if [ "$NO_EDITABLE" -eq 1 ]; then
  warn "skipping editable install (--no-editable)"
else
  step "Phase 2: Editable install of MCPSearch"
  timeout 120 "$PY" -m pip install --quiet --no-cache-dir --break-system-packages -e "$APP_DIR" > "$LOG_DIR/p2_editable.log" 2>&1 \
    && ok "editable install complete" || fatal "editable install failed (see $LOG_DIR/p2_editable.log)"
fi

# ---------------------------------------------------------------- PHASE 3
step "Phase 3: Generate launcher and MCP client config"
# Heredoc must be UNQUOTED so $APP_DIR, $PY, $CFG_DIR expand at generation time.
cat > "$CFG_DIR/run.sh" << LAUNCHER_EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$APP_DIR" || exit 1
exec $PY -m mcp_server
LAUNCHER_EOF
chmod +x "$CFG_DIR/run.sh"
ok "launcher written to $CFG_DIR/run.sh"

cat > "$CFG_DIR/mcp_client_snippet.json" << JSONEOF
{
  "mcpServers": {
    "mcpsearch": {
      "command": "$CFG_DIR/run.sh",
      "args": []
    }
  }
}
JSONEOF
ok "MCP client config snippet written to $CFG_DIR/mcp_client_snippet.json"
warn "This is a stdio MCP server: it is meant to be launched by an MCP client (e.g. Claude Desktop, Cursor), not run standalone as a network daemon. Merge the snippet above into your client's config file."

# ---------------------------------------------------------------- PHASE 4
if [ "$NO_SELFTEST" -eq 1 ]; then
  warn "skipping Phase 4 self-tests (--no-selftest)"
else
  step "Phase 4: Self-test — import server and exercise a tool call"
  cat > "$TMPDIR/mcpsearch_selftest.py" << 'TESTEOF'
import sys, os, asyncio, traceback

sys.path.insert(0, "__APP_DIR__")

def fail(msg, exc=None):
    print(f"SELFTEST_FAIL: {msg}")
    if exc:
        traceback.print_exc()
    sys.exit(1)

try:
    from mcp_server import server as srv
except Exception as e:
    fail("could not import mcp_server.server", e)

try:
    tool_names = sorted(getattr(t, "name", str(t)) for t in srv.mcp._tool_manager._tools.values()) \
        if hasattr(srv, "mcp") else []
    print(f"SELFTEST_INFO: discovered {len(tool_names)} tools")
    for n in tool_names:
        print("   -", n)
except Exception as e:
    print(f"SELFTEST_WARN: could not enumerate tools cleanly ({e})")

async def run_smoke_call():
    if hasattr(srv, "get_crawl_stats"):
        try:
            result = await srv.get_crawl_stats.fn() if hasattr(srv.get_crawl_stats, "fn") else await srv.get_crawl_stats()
            print("SELFTEST_INFO: get_crawl_stats() returned:", str(result)[:200])
        except Exception as e:
            fail("get_crawl_stats() raised an exception", e)
    else:
        print("SELFTEST_WARN: get_crawl_stats not found, skipping smoke call")

try:
    asyncio.run(run_smoke_call())
except SystemExit:
    raise
except Exception as e:
    fail("smoke call crashed unexpectedly", e)

print("SELFTEST_PASS")
TESTEOF
  sed -i "s|__APP_DIR__|${APP_DIR}|g" "$TMPDIR/mcpsearch_selftest.py"
  if "$PY" "$TMPDIR/mcpsearch_selftest.py" 2>&1 | tee "$LOG_DIR/p4_selftest.log" | grep -q "SELFTEST_PASS"; then
    ok "self-test passed — server imports and responds to a tool call cleanly"
  else
    err "self-test FAILED — see $LOG_DIR/p4_selftest.log for the full traceback"
    echo -e "${YELLOW}The install finished but the server is not confirmed working. Review the log above.${NC}"
    exit 1
  fi

  if [ "$NO_CACHE_TEST" -eq 1 ]; then
    warn "skipping Phase 4b HTTP cache smoke test (--no-cache-test)"
  else
    step "Phase 4b: HTTP cache smoke test (hishel + anysqlite, no deprecation warnings)"
    cat > "$TMPDIR/mcpsearch_cache_selftest.py" << 'CACHETESTEOF'
import sys, os, asyncio, warnings, traceback

sys.path.insert(0, "__APP_DIR__")

def fail(msg, exc=None):
    print(f"CACHETEST_FAIL: {msg}")
    if exc:
        traceback.print_exc()
    sys.exit(1)

async def main():
    try:
        from utils.http_client import build_async_client, AsyncHttpClientConfig
    except Exception as e:
        fail("could not import build_async_client/AsyncHttpClientConfig", e)
        return

    with warnings.catch_warnings():
        warnings.simplefilter("error", UserWarning)
        try:
            config = AsyncHttpClientConfig(enable_cache=True, cache_ttl=60, always_cache=True)
            client = build_async_client(config)
        except UserWarning as e:
            fail(f"deprecated-kwarg UserWarning still present: {e}")
            return
        except Exception as e:
            fail("build_async_client() raised unexpectedly", e)
            return

    try:
        r1 = await client.get("__CACHE_TEST_URL__")
        r2 = await client.get("__CACHE_TEST_URL__")
        await client.aclose()
    except Exception as e:
        fail("cached client GET request failed (network or hishel wiring issue)", e)
        return

    hit1 = r1.extensions.get("hishel_from_cache")
    hit2 = r2.extensions.get("hishel_from_cache")
    print(f"CACHETEST_INFO: req1 hishel_from_cache={hit1}, req2 hishel_from_cache={hit2}")

    if hit2 is not True:
        fail(f"expected req2 hishel_from_cache=True under always_cache=True, got {hit2}")
        return

    print("CACHETEST_PASS")

asyncio.run(main())
CACHETESTEOF
    # Substitute dynamic app-dir and cache-test URL into the generated test.
    sed -i "s|__APP_DIR__|${APP_DIR}|g" "$TMPDIR/mcpsearch_cache_selftest.py"
    sed -i "s|__CACHE_TEST_URL__|${CACHE_TEST_URL}|g" "$TMPDIR/mcpsearch_cache_selftest.py"
    if "$PY" "$TMPDIR/mcpsearch_cache_selftest.py" 2>&1 | tee "$LOG_DIR/p4b_cache_selftest.log" | grep -q "CACHETEST_PASS"; then
      ok "HTTP cache self-test passed — hishel/anysqlite wired correctly, no deprecation warnings"
    else
      err "HTTP cache self-test FAILED — see $LOG_DIR/p4b_cache_selftest.log for the full traceback"
      echo -e "${YELLOW}Server imports fine but the HTTP cache layer used by search_and_summarize etc. is broken. Review the log above.${NC}"
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------- PHASE 5
if [ "$NO_CLEANUP" -eq 1 ]; then
  warn "skipping Phase 5 cleanup (--no-cleanup)"
else
  step "Phase 5: Post-install cleanup (reclaim build space)"
  "$PY" -m pip cache purge > "$LOG_DIR/p5_cleanup.log" 2>&1 || true
  rm -rf "$HOME/.cache/pip" 2>/dev/null
  if [ "$KEEP_TMP" -eq 1 ]; then
    warn "keeping scratch tmp dir (--keep-tmp): $TMPDIR"
  else
    rm -rf "$TMPDIR" 2>/dev/null
  fi
  rm -rf "$HOME/.cargo/registry" 2>/dev/null
  _FREE_KB=$(df -P "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -n "$_FREE_KB" ] && [ "$_FREE_KB" -gt 0 ] 2>/dev/null; then
    _FREE_GB=$((_FREE_KB / 1024 / 1024))
    ok "cleared pip/cargo build caches — ~${_FREE_GB}GB free on $HOME now"
  else
    ok "cleared pip/cargo build caches"
  fi
  unset _FREE_KB _FREE_GB
fi

echo -e "\n${GREEN}${BOLD}All 4 phases (+cache verification +cleanup) complete.${NC}"
echo -e "${CYAN}Launcher:${NC} $CFG_DIR/run.sh"
echo -e "${CYAN}Client config snippet:${NC} $CFG_DIR/mcp_client_snippet.json"
echo -e "${CYAN}Logs:${NC} $LOG_DIR"
