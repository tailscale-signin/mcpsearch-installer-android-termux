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
        r"\\1\\nfrom agents.research_agent import get_research_agent",
        src, count=1, flags=re.MULTILINE,
    )
    notes.append("inserted missing get_research_agent import")

# 2. Replace bare factory-object names with their get_X() calls.
#    \\b already prevents matching inside get_crawler/get_summarizer/etc,
#    since \'_\\\' and the following letter are both word chars (no boundary).
#    Import/from lines are skipped so `from crawler.engine import ...`
#    is never touched.
bare_names = ["aggregator", "crawler", "summarizer",
              "reddit_scraper", "twitter_scraper", "youtube_scraper", "github_scraper"]
src_lines = src.split("\\n")
for name in bare_names:
    pattern = re.compile(r"\\b" + name + r"\\.")
    replacement = f"get_{name}()."
    count = 0
    for i, line in enumerate(src_lines):
        if re.match(r"^\\s*(from|import)\\s", line):
            continue
        new_line, n = pattern.subn(replacement, line)
        if n:
            src_lines[i] = new_line
            count += n
    if count:
        notes.append(f"replaced {count}x bare \'{name}.\' -> \'get_{name}().\'")
src = "\\n".join(src_lines)

# 3. Fix zero-arg lines.append() -> lines.append("")
new_src, n = re.subn(r\'lines\\.append\\(\)\', r\'lines.append("")\', src)
if n:
    notes.append(f"fixed {n}x empty lines.append()")
src = new_src

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print(f"--- patch summary ({len(orig)} -> {len(src)} bytes) ---")
for n in notes:
    print(" -", n)

remaining = re.findall(
    r"\\b(?:aggregator|crawler|summarizer|reddit_scraper|twitter_scraper|youtube_scraper|github_scraper)\\.\\w+\\(\\""",
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