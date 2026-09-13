#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# MCPSearch Termux Installer — Master Script (v1.9.0, optimized & hardened)
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
#  - v1.9.0: Performance & reliability optimizations:
#            - Non-interactive Dpkg environment (--force-confdef, --force-confold)
#              preventing background subshell crashes on config prompts.
#            - Batch package detection & installation (cuts Phase 1 from 5m to seconds).
#            - Native python-lxml integration to bypass slow C compilation.
#            - Shallow git clones (--depth 1 --single-branch) saving bandwidth and I/O.
#            - Fast-path batch pip wheel installation with tier fallback.
# ============================================================================
set -uo pipefail

VERSION="1.9.0"

# Enforce non-interactive package operations to avoid background subshell hangs
export DEBIAN_FRONTEND=noninteractive
APT_DPKG_FLAGS='-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

# --- Configurable paths/env (env-overridable, then flags) ------------------
APP_DIR="${MCPSEARCH_APP_DIR:-$HOME/MCPSearch}"
LOG_DIR="${MCPSEARCH_LOG_DIR:-$HOME/.mcpsearch_logs}"
CFG_DIR="${MCPSEARCH_CONFIG_DIR:-$HOME/.mcpsearch}"
TMPDIR="${MCPSEARCH_TMP_DIR:-$HOME/.mcpsearch_tmp}"
REPO_URL="${MCPSEARCH_REPO_URL:-https://github.com/JonusNattapong/MCPSearch}"
BRANCH="${MCPSEARCH_BRANCH:-main}"
PY="${MCPSEARCH_PYTHON:-python3.11}"
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
TIMEOUT=60
TIMEOUT=60
TIMEOUT=60
TIMEOUT=60
TIMEOUT=60
TIMEOUT=60
TIMEOUT=60
TIMEOUT=60
TIMEOUT=60
JOBS="${CARGO_BUILD_JOBS:-1}"
OPT_LEVEL="${MCPSEARCH_RUST_OPT:-1}"

# Sub-step skip toggles
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
NO_PKG=0
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
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_ELFTEST=0
NO_ELFTEST=0
NO_ELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_ELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_SELFTEST=0
NO_CLEANUP=0
NO_VERIFY=0

# Cache-test overrides
CACHE_TEST_URL="https://httpbin.org/get"
ttt
