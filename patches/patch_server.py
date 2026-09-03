import re, sys, os

path = os.path.expanduser("~/MCPSearch/mcp_server/server.py")
with open(path, encoding="utf-8") as f:
    src = f.read()
orig = src
notes = []

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
        notes.append(f"replaced {count}x bare '{name}.' -> 'get_{name}().'.")
src = "\n".join(src_lines)

new_src, n = re.subn(r"lines\.append\(\)", 'lines.append("")', src)
if n:
    notes.append(f"fixed {n}x empty lines.append()")
src = new_src

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
