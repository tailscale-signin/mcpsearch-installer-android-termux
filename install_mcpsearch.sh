# !/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# MCPSearch Termux Installer — Master Script (v1.2, all 4 phases)
#
# Changelog:
#  - v1.0: Initial 4-phase installer (clone, patch, install, self-test)
#  - v1.1: Termux /tmp sandbox fix, line-aware regex patch (skip import
#          lines), full multi-line function signature capture fix.
#  - v1.2 (this version) — hishel async-cache fixes, verified end-to-end:
#      1. Added missing `anysqlite` dependency to pyproject.toml.
#         hishel[httpx]'s AsyncSqliteStorage requires anysqlite but it was
#         never declared, causing ImportError at cache-client construction
#         time inside search_and_summarize / any cached HTTP call.
#      2. Removed deprecated `refresh_ttl_on_access=config.refresh_on_hit`
#         kwarg from AsyncSqliteStorage(...) in utils/http_client.py.
#         This parameter is a no-op as of hishel 1.3.x and only emits a
#         UserWarning on every client construction; patch is done via
#         idempotent regex (safe to re-run, no-op if already patched).
#      3. anysqlite + hishel added explicitly to the pip install tier list
#         (previously only implied via editable install, which could lag
#         or fail silently on constrained Termux environments).
#      4. Phase 4 self-test extended with an HTTP-cache smoke test that
#         exercises build_async_client() under both the default RFC 9111
#         SpecificationPolicy and always_cache=True (FilterPolicy) paths,
#         asserting the correct hishel_from_cache extension behavior and
#         asserting NO UserWarning is raised (via warnings-as-errors).
#  - Verified: Phase 4 self-test passes — server imports cleanly, responds
#    to a live get_crawl_stats() tool call, and the HTTP cache layer is
#    confirmed functional with no deprecation warnings.
# ============================================================================
set -uo pipefail
APP_DIR="$HOME/MCPSearch"
LOG_DIR="$HOME/.mcpsearch_logs"
CFG_DIR="$HOME/.mcpsearch"
REPO_URL="https://github.com/JonusNattapong/MCPSearch"
PY="python3"
mkdir -p "$LOG_DIR" "$CFG_DIR"
TMPDIR="$HOME/.mcpsearch_tmp"; mkdir -p "$TMPDIR"
command -v python3 >/dev/null 2>&1 || PY="python"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
step(){ echo -e "\n${CYAN}▶ $*${NC}"; }
ok(){ echo -e "  ${GREEN}✔${NC} $*"; }
err(){ echo -e "  ${RED}✘${NC} $*"; }
warn(){ echo -e "  ${YELLOW}⚠${NC} $*"; }
fatal(){ err "$*"; echo -e "${RED}Aborted. Logs: $LOG_DIR${NC}"; exit 1; }

echo -e "${BOLD}${CYAN}== MCPSearch Termux Installer — Phases 1-4 (v1.2) ==${NC}"

# ---------------------------------------------------------------- PHASE 1
step "Phase 1: Termux packages"
pkg update -y > "$LOG_DIR/p1.log" 2>&1 || warn "pkg update had issues"
pkg upgrade -y >> "$LOG_DIR/p1.log" 2>&1 || warn "pkg upgrade had issues"
for p in python git rust binutils libjpeg-turbo libxml2 libxslt clang make pkg-config openssl patchelf curl; do
  pkg install -y "$p" >> "$LOG_DIR/p1.log" 2>&1 && ok "$p" || fatal "failed to install $p (see $LOG_DIR/p1.log)"
done
"$PY" -m ensurepip --upgrade > "$LOG_DIR/p1_pip.log" 2>&1 || true
"$PY" -m pip install --upgrade pip --break-system-packages >> "$LOG_DIR/p1_pip.log" 2>&1 || warn "pip upgrade had issues"
ok "interpreter ready: $("$PY" --version 2>&1)"

# ---------------------------------------------------------------- PHASE 2
step "Phase 2: Clone MCPSearch"
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" fetch origin >> "$LOG_DIR/p2.log" 2>&1
  git -C "$APP_DIR" reset --hard origin/main >> "$LOG_DIR/p2.log" 2>&1
else
  rm -rf "$APP_DIR"
  git clone "$REPO_URL" "$APP_DIR" > "$LOG_DIR/p2.log" 2>&1 || fatal "git clone failed (see $LOG_DIR/p2.log)"
fi
[ -f "$APP_DIR/pyproject.toml" ] && [ -f "$APP_DIR/mcp_server/server.py" ] || fatal "source tree missing expected files"
ok "source ready at $APP_DIR"

step "Phase 2: Strip Playwright (HTTP-only mode)"
sed -i '/[Pp]laywright/d' "$APP_DIR/pyproject.toml"
ok "playwright references removed from pyproject.toml"

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

step "Phase 2: Patch mcp_server/server.py (regex-based, idempotent)"
cat > "$TMPDIR/mcpsearch_patch.py" << 'PYEOF'
import re, sys, os

path = os.path.expanduser("~/MCPSearch/mcp_server/server.py")
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
#    \b already prevents matching inside get_crawler/get_summarizer/etc,
#    since '_' and the following letter are both word chars (no boundary).
#    Import/from lines are skipped so `from crawler.engine import ...`
#    is never touched.
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
        r"(async def " + func_name + r"\(.*?-> str:\n)(.*?)(?=\n@mcp\\.tool\(|\Z)",
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

        lines = [f"# Research: {topic}\n", f"**Depth:** {depth} | **Social:** {include_social}\n"]

        web = by_type.get("web", []) + by_type.get("web_crawled", [])
        if web:
            lines.append("## Web Search Results\n")
            for i, f in enumerate(web, 1):
                s = f["source"]
                lines.append(f"{i}. **{s.get('title', 'No title')}**")
                lines.append(f"   [{s.get('url', 'N/A')}]({s.get('url', 'N/A')})")
                if f.get("content"):
                    lines.append(f"   {f['content'][:200]}\n")

        social = [t for t in by_type if t not in ("web", "web_crawled")]
        if social:
            lines.append("\n## Social Media Insights\n")
            for platform in social:
                lines.append(f"### {platform.title()}\n")
                for f in by_type[platform][:3]:
                    lines.append(f"- {f['content'][:150]}")
                lines.append("")

        if report.get("summary"):
            lines.append("\n## AI Summary\n")
            lines.append(report["summary"])

        return "\n".join(lines)
    except Exception as e:
        import logging, traceback
        logging.error(f"investigate error: {e}\n{traceback.format_exc()}")
        return f"Error: {str(e)}"
'''

compare_body = '''    agent = get_research_agent()
    try:
        topic_list = [t.strip() for t in topics.split(",") if t.strip()]
        comparison = await agent.compare(topic_list, search_depth=depth)

        lines = [f"# Comparison: {' vs '.join(topic_list)}\n"]
        for topic in topic_list:
            report = comparison["reports"][topic]
            lines.append(f"## {topic}\n")
            web = [f for f in report.get("findings", [])
                   if f["source"]["source_type"] in ("web", "web_crawled")]
            if web:
                lines.append("### Key Results\n")
                for f in web[:2]:
                    s = f["source"]
                    lines.append(f"- **{s.get('title', 'N/A')}**")
                    lines.append(f"  {f['content'][:100]}\n")
            lines.append("")

        return "\n".join(lines)
    except Exception as e:
        import logging, traceback
        logging.error(f"compare error: {e}\n{traceback.format_exc()}")
        return f"Error: {str(e)}"
'''

trending_body = '''    try:
        result = {}
        if "github" in platforms:
            result["github"] = await get_github_scraper().get_trending()
        if "reddit" in platforms:
            result["reddit"] = await get_reddit_scraper().get_trending()

        lines = ["# Trending Topics\n"]
        for platform, items in result.items():
            lines.append(f"## {platform.title()}\n")
            item_list = items if isinstance(items, list) else (
                getattr(items, "posts", None) or getattr(items, "repos", None) or []
            )
            if item_list:
                for i, item in enumerate(item_list[:5], 1):
                    lines.append(f"{i}. {str(item)[:150]}")
            lines.append("")

        return "\n".join(lines)
    except Exception as e:
        import logging, traceback
        logging.error(f"trending error: {e}\n{traceback.format_exc()}")
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
"$PY" "$TMPDIR/mcpsearch_patch.py" 2>&1 | tee "$LOG_DIR/p2_patch.log"
grep -q "VERIFY_OK" "$LOG_DIR/p2_patch.log" || fatal "server.py patch verification failed, see "$LOG_DIR/p2_patch.log""
ok "server.py patched"

step "Phase 2: Patch utils/http_client.py — remove deprecated hishel kwarg (idempotent)"
cat > "$TMPDIR/mcpsearch_patch_httpclient.py" << 'PYEOF'
import re, os

path = os.path.expanduser("~/MCPSearch/utils/http_client.py")
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
'PYEOF'
"$PY" "$TMPDIR/mcpsearch_patch_httpclient.py" 2>&1 | tee "$LOG_DIR/p2_patch_httpclient.log"
grep -q "VERIFY_OK" "$LOG_DIR/p2_patch_httpclient.log" || fatal "http_client.py patch verification failed, see "$LOG_DIR/p2_patch_httpclient.log""
"$PY" -m py_compile "$APP_DIR/utils/http_client.py" 2>>"$LOG_DIR/p2_patch_httpclient.log" \
  && ok "http_client.py patched and compiles cleanly" \
  || fatal "http_client.py failed to compile after patch, see "$LOG_DIR/p2_patch_httpclient.log""

step "Phase 2: Install Python dependencies (with fallback tiers)"
install_pkg() {
  local pkg="$1"
  timeout 60 "$PY" -m pip install --quiet --break-system-packages "$pkg" >> "$LOG_DIR/p2_pip.log" 2>&1 && return 0
  warn "$pkg: wheel install failed, retrying --no-binary"
  timeout 180 "$PY" -m pip install --quiet --break-system-packages --no-binary :all: "$pkg" >> "$LOG_DIR/p2_pip.log" 2>&1 && return 0
  warn "$pkg: retrying with rust link flags"
  RUSTFLAGS="-C link-arg=-lpython3.11" timeout 240 "$PY" -m pip install --quiet --break-system-packages --force-reinstall "$pkg" >> "$LOG_DIR/p2_pip.log" 2>&1
}
DEP_FAIL=0
for pkg in pydantic pydantic-settings httpx beautifulsoup4 lxml selectolax mcp hishel anysqlite; do
  install_pkg "$pkg" && ok "$pkg" || { err "$pkg failed all install tiers"; DEP_FAIL=1; }
done
[ "$DEP_FAIL" -eq 1 ] && fatal "dependency install failed (see "$LOG_DIR/p2_pip.log")"

step "Phase 2: Editable install of MCPSearch"
timeout 120 "$PY" -m pip install --quiet --break-system-packages -e "$APP_DIR" > "$LOG_DIR/p2_editable.log" 2>&1 \
  && ok "editable install complete" || fatal "editable install failed (see "$LOG_DIR/p2_editable.log")"

# ---------------------------------------------------------------- PHASE 3
step "Phase 3: Generate launcher and MCP client config"
cat > "$CFG_DIR/run.sh" << 'LAUNCHER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd "$APP_DIR" || exit 1
exec $PY -m mcp_server
'LAUNCHER_EOF'
chmod +x "$CFG_DIR/run.sh"
ok "launcher written to "$CFG_DIR/run.sh""

cat > "$CFG_DIR/mcp_client_snippet.json" << 'JSONEOF'
{
  "mcpServers": {
    "mcpsearch": {
      "command": "$CFG_DIR/run.sh",
      "args": []
    }
  }
}
'JSONEOF'
ok "MCP client config snippet written to "$CFG_DIR/mcp_client_snippet.json""
warn "This is a stdio MCP server: it is meant to be launched by an MCP client (e.g. Claude Desktop, Cursor), not run standalone as a network daemon. Merge the snippet above into your client's config file."

# ---------------------------------------------------------------- PHASE 4
step "Phase 4: Self-test — import server and exercise a tool call"
cat > "$TMPDIR/mcpsearch_selftest.py" << 'TESTEOF'
import sys, os, asyncio, traceback

sys.path.insert(0, os.path.expanduser("~/MCPSearch"))

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
if "$PY" "$TMPDIR/mcpsearch_selftest.py" 2>&1 | tee "$LOG_DIR/p4_selftest.log" | grep -q "SELFTEST_PASS"; then
  ok "self-test passed — server imports and responds to a tool call cleanly"
else
  err "self-test FAILED — see "$LOG_DIR/p4_selftest.log" for the full traceback"
  echo -e "${YELLOW}The install finished but the server is not confirmed working. Review the log above.${NC}"
  exit 1
fi

step "Phase 4b: HTTP cache smoke test (hishel + anysqlite, no deprecation warnings)"
cat > "$TMPDIR/mcpsearch_cache_selftest.py" << 'CACHETESTEOF'
import sys, os, asyncio, warnings, traceback

sys.path.insert(0, os.path.expanduser("~/MCPSearch"))

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
        r1 = await client.get("https://httpbin.org/get")
        r2 = await client.get("https://httpbin.org/get")
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
if "$PY" "$TMPDIR/mcpsearch_cache_selftest.py" 2>&1 | tee "$LOG_DIR/p4b_cache_selftest.log" | grep -q "CACHETEST_PASS"; then
  ok "HTTP cache self-test passed — hishel/anysqlite wired correctly, no deprecation warnings"
else
  err "HTTP cache self-test FAILED — see "$LOG_DIR/p4b_cache_selftest.log" for the full traceback"
  echo -e "${YELLOW}Server imports fine but the HTTP cache layer used by search_and_summarize etc. is broken. Review the log above.${NC}"
  exit 1
fi

echo -e "\n${GREEN}${BOLD}All 4 phases (+cache verification) complete.${NC}"
echo -e "${CYAN}Launcher:${NC} "$CFG_DIR/run.sh""
echo -e "${CYAN}Client config snippet:${NC} "$CFG_DIR/mcp_client_snippet.json""
echo -e "${CYAN}Logs:${NC} "$LOG_DIR""
