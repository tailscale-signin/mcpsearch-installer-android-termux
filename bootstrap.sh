#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# MCPSearch Termux Bootstrap — one-command setup (v1.3)
#
# Does everything in a single run:
#   1. Update package lists (pkg update) with auto-retry and timeout guards
#   2. Upgrade installed packages safely (pkg upgrade + openssl sync)
#   3. Install git (and curl, for safety) with mirror fallback & recovery
#   4. Clone this installer repo
#   5. Run install_mcpsearch.sh (passes through all CLI flags and options)
#
# Usage:
#   bash bootstrap.sh                         # full install
#   bash bootstrap.sh --help                  # show installer options
#   bash bootstrap.sh --version               # show installer version
#   bash bootstrap.sh --dry-run               # print install plan without changes
#   bash bootstrap.sh --check                 # run only Phase 4 self-tests
#   bash bootstrap.sh --no-rust               # skip Rust toolchain
#   bash bootstrap.sh --skip-upgrade          # skip pkg upgrade
#   bash bootstrap.sh --installer-branch DEV  # use custom branch for this installer
#
# You can run it directly from the internet without cloning first:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/tailscale-signin/mcpsearch-installer-android-termux/main/bootstrap.sh)"
# ============================================================================
set -uo pipefail

VERSION="1.3.0"
REPO_URL="https://github.com/tailscale-signin/mcpsearch-installer-android-termux.git"
INSTALLER_BRANCH="main"
INSTALLER_DIR="$HOME/mcpsearch-installer-android-termux"
LOG_DIR="$HOME/.mcpsearch_logs"

export DEBIAN_FRONTEND=noninteractive
APT_RETRY_FLAGS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
step(){ echo -e "\n${CYAN}▶ $*${NC}"; }
ok(){ echo -e "  ${GREEN}✔${NC} $*"; }
err(){ echo -e "  ${RED}✘${NC} $*"; }
warn(){ echo -e "  ${YELLOW}⚠${NC} $*"; }
fatal(){ err "$*"; echo -e "${RED}Aborted.${NC}"; exit 1; }

# Parse bootstrap-level flags before forwarding the rest to install_mcpsearch.sh
FORWARD_ARGS=()
SKIP_UPGRADE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --installer-branch)
      INSTALLER_BRANCH="$2"; shift 2 ;;
    --installer-branch=*)
      INSTALLER_BRANCH="${1#*=}"; shift ;;
    --skip-upgrade)
      SKIP_UPGRADE=1
      FORWARD_ARGS+=("$1"); shift ;;
    --bootstrap-version)
      echo "MCPSearch Termux Bootstrap v$VERSION"; exit 0 ;;
    *)
      FORWARD_ARGS+=("$1"); shift ;;
  esac
done

mkdir -p "$LOG_DIR"

echo -e "${BOLD}${CYAN}== MCPSearch Termux Bootstrap (v$VERSION) ==${NC}"

# Robust package manager helper with auto-clean and mirror switch on I/O failure
run_apt_with_retry() {
  local op="$1"
  shift
  local pkgs="$*"
  local max_retries=3
  local attempt=1

  while [ "$attempt" -le "$max_retries" ]; do
    case "$op" in
      update)
        if apt-get update $APT_RETRY_FLAGS >> "$LOG_DIR/bootstrap_pkg.log" 2>&1; then
          return 0
        fi
        ;;
      upgrade)
        if apt-get upgrade $APT_RETRY_FLAGS --fix-missing >> "$LOG_DIR/bootstrap_pkg.log" 2>&1; then
          return 0
        fi
        ;;
      install)
        if apt-get install $APT_RETRY_FLAGS --fix-missing $pkgs >> "$LOG_DIR/bootstrap_pkg.log" 2>&1; then
          return 0
        fi
        ;;
    esac

    warn "apt-get $op failed (attempt $attempt/$max_retries). Cleaning partial cache and retrying..."
    apt-get clean >> "$LOG_DIR/bootstrap_pkg.log" 2>&1 || true
    dpkg --configure -a >> "$LOG_DIR/bootstrap_pkg.log" 2>&1 || true
    apt-get --fix-broken install $APT_RETRY_FLAGS >> "$LOG_DIR/bootstrap_pkg.log" 2>&1 || true

    # If mirror is throwing repeated I/O errors, fall back to default official repo
    if grep -Eq "(I/O error|Failed to fetch|Error reading from server)" "$LOG_DIR/bootstrap_pkg.log" 2>/dev/null; then
      if [ -f "$PREFIX/etc/apt/sources.list" ] && grep -q "mirrors.hust.edu.cn" "$PREFIX/etc/apt/sources.list"; then
        warn "Detected failing mirror (mirrors.hust.edu.cn), switching to official termux.dev mirror..."
        sed -i 's|https://mirrors.hust.edu.cn/termux|https://packages.termux.dev/apt|g' "$PREFIX/etc/apt/sources.list" 2>/dev/null || true
      fi
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  return 1
}

# ---------------------------------------------------------------- STEP 1
step "Step 1: Update package lists (apt-get update)"
if run_apt_with_retry update; then
  ok "apt-get update"
else
  warn "apt-get update had issues (see $LOG_DIR/bootstrap_pkg.log)"
fi

# ---------------------------------------------------------------- STEP 2
if [ "$SKIP_UPGRADE" -eq 1 ]; then
  step "Step 2: Upgrade installed packages (skipped via --skip-upgrade)"
else
  step "Step 2: Upgrade installed packages (apt-get upgrade)"
  if run_apt_with_retry upgrade; then
    ok "apt-get upgrade"
  else
    warn "apt-get upgrade had issues (see $LOG_DIR/bootstrap_pkg.log)"
  fi
fi

# Ensure openssl is synchronized
run_apt_with_retry install openssl || true

# ---------------------------------------------------------------- STEP 3
step "Step 3: Install git and curl"
if run_apt_with_retry install git curl; then
  ok "git + curl installed"
else
  fatal "failed to install git/curl after multiple retries (see $LOG_DIR/bootstrap_pkg.log)"
fi

# Sanity check curl linkage after package install
if ! curl --version >/dev/null 2>&1; then
  warn "curl binary has library linkage mismatch; attempting repair"
  apt-get clean >> "$LOG_DIR/bootstrap_pkg.log" 2>&1 || true
  apt-get --fix-broken install $APT_RETRY_FLAGS >> "$LOG_DIR/bootstrap_pkg.log" 2>&1 || true
  apt-get install $APT_RETRY_FLAGS --reinstall openssl libcurl curl >> "$LOG_DIR/bootstrap_pkg.log" 2>&1 || true
  curl --version >/dev/null 2>&1 || fatal "curl remains broken after repair attempts (see $LOG_DIR/bootstrap_pkg.log)"
fi

# ---------------------------------------------------------------- STEP 4
step "Step 4: Clone the installer repo (branch: $INSTALLER_BRANCH)"
if [ -d "$INSTALLER_DIR/.git" ]; then
  git -C "$INSTALLER_DIR" fetch origin >> "$LOG_DIR/bootstrap_clone.log" 2>&1
  git -C "$INSTALLER_DIR" reset --hard "origin/$INSTALLER_BRANCH" >> "$LOG_DIR/bootstrap_clone.log" 2>&1 \
    && ok "installer repo updated at $INSTALLER_DIR" || fatal "could not update installer repo"
else
  rm -rf "$INSTALLER_DIR"
  git clone --branch "$INSTALLER_BRANCH" "$REPO_URL" "$INSTALLER_DIR" > "$LOG_DIR/bootstrap_clone.log" 2>&1 \
    && ok "installer repo cloned to $INSTALLER_DIR" || fatal "git clone failed (see $LOG_DIR/bootstrap_clone.log)"
fi

# ---------------------------------------------------------------- STEP 5
step "Step 5: Run the installer (passing through extra args: ${FORWARD_ARGS[*]:-none})"
cd "$INSTALLER_DIR" || fatal "could not enter $INSTALLER_DIR"
bash install_mcpsearch.sh "${FORWARD_ARGS[@]}"
