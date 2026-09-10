#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# MCPSearch Termux Bootstrap — one-command setup (v1.0)
#
# Does everything in a single run:
#   1. Update package lists (pkg update)
#   2. Upgrade installed packages (pkg upgrade)
#   3. Install git (and curl, for safety)
#   4. Clone this installer repo
#   5. Run install_mcpsearch.sh (passes through any extra args, e.g. --no-rust)
#
# Usage:
#   bash bootstrap.sh                 # full install
#   bash bootstrap.sh --no-rust       # skip Rust toolchain
#
# You can run it directly from the internet without cloning first:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/tailscale-signin/mcpsearch-installer-android-termux/main/bootstrap.sh)"
# ============================================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
step(){ echo -e "\n${CYAN}▶ $*${NC}"; }
ok(){ echo -e "  ${GREEN}✔${NC} $*"; }
err(){ echo -e "  ${RED}✘${NC} $*"; }
warn(){ echo -e "  ${YELLOW}⚠${NC} $*"; }
fatal(){ err "$*"; echo -e "${RED}Aborted.${NC}"; exit 1; }

REPO_URL="https://github.com/tailscale-signin/mcpsearch-installer-android-termux.git"
INSTALLER_DIR="$HOME/mcpsearch-installer-android-termux"
LOG_DIR="$HOME/.mcpsearch_logs"
mkdir -p "$LOG_DIR"

echo -e "${BOLD}${CYAN}== MCPSearch Termux Bootstrap (v1.0) ==${NC}"

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
step "Step 4: Clone the installer repo"
if [ -d "$INSTALLER_DIR/.git" ]; then
  git -C "$INSTALLER_DIR" fetch origin >> "$LOG_DIR/bootstrap_clone.log" 2>&1
  git -C "$INSTALLER_DIR" reset --hard origin/main >> "$LOG_DIR/bootstrap_clone.log" 2>&1 \
    && ok "installer repo updated at $INSTALLER_DIR" || fatal "could not update installer repo"
else
  rm -rf "$INSTALLER_DIR"
  git clone "$REPO_URL" "$INSTALLER_DIR" > "$LOG_DIR/bootstrap_clone.log" 2>&1 \
    && ok "installer repo cloned to $INSTALLER_DIR" || fatal "git clone failed (see $LOG_DIR/bootstrap_clone.log)"
fi

# ---------------------------------------------------------------- STEP 5
step "Step 5: Run the installer (passing through extra args: $*)"
cd "$INSTALLER_DIR" || fatal "could not enter $INSTALLER_DIR"
bash install_mcpsearch.sh "$@"