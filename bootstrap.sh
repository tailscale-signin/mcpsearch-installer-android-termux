#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# MCPSearch Termux Bootstrap — one-command setup (v1.1)
#
# Does everything in a single run:
#   1. Update package lists (pkg update)
#   2. Upgrade installed packages (pkg upgrade)
#   3. Install git (and curl, for safety)
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

VERSION="1.1.0"
REPO_URL="https://github.com/tailscale-signin/mcpsearch-installer-android-termux.git"
INSTALLER_BRANCH="main"
INSTALLER_DIR="$HOME/mcpsearch-installer-android-termux"
LOG_DIR="$HOME/.mcpsearch_logs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
step(){ echo -e "\n${CYAN}▶ $*${NC}"; }
ok(){ echo -e "  ${GREEN}✔${NC} $*"; }
err(){ echo -e "  ${RED}✘${NC} $*"; }
warn(){ echo -e "  ${YELLOW}⚠${NC} $*"; }
fatal(){ err "$*"; echo -e "${RED}Aborted.${NC}"; exit 1; }

# Parse bootstrap-level flags before forwarding the rest to install_mcpsearch.sh
FORWARD_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --installer-branch)
      INSTALLER_BRANCH="$2"; shift 2 ;;
    --installer-branch=*)
      INSTALLER_BRANCH="${1#*=}"; shift ;;
    --bootstrap-version)
      echo "MCPSearch Termux Bootstrap v$VERSION"; exit 0 ;;
    *)
      FORWARD_ARGS+=("$1"); shift ;;
  esac
done

mkdir -p "$LOG_DIR"

echo -e "${BOLD}${CYAN}== MCPSearch Termux Bootstrap (v$VERSION) ==${NC}"

# ---------------------------------------------------------------- STEP 1
step "Step 1: Update package lists (pkg update)"
pkg update -y > "$LOG_DIR/bootstrap_pkg.log" 2>&1 \
  && ok "pkg update" || warn "pkg update had issues (see $LOG_DIR/bootstrap_pkg.log)"

# ---------------------------------------------------------------- STEP 2
step "Step 2: Upgrade installed packages (pkg upgrade)"
pkg upgrade -y >> "$LOG_DIR/bootstrap_pkg.log" 2>&1 \
  && ok "pkg upgrade" || warn "pkg upgrade had issues (see $LOG_DIR/bootstrap_pkg.log)"

# ---------------------------------------------------------------- STEP 3
step "Step 3: Install git (and curl)"
pkg install -y git curl >> "$LOG_DIR/bootstrap_pkg.log" 2>&1 \
  && ok "git + curl installed" || fatal "failed to install git/curl (see $LOG_DIR/bootstrap_pkg.log)"

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
