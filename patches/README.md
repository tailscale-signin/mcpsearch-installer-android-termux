# patches/

This directory contains a **standalone, reference copy** of the `mcp_server/server.py`
patch logic that `install_mcpsearch.sh` applies inline during Phase 2.

## Files

- `patch_server.py` — regex-based patch for `~/MCPSearch/mcp_server/server.py`. Fixes:
  - an undefined `get_research_agent_instance()` reference (renamed to `get_research_agent()`)
  - bare factory-object calls (`crawler.`, `aggregator.`, `summarizer.`, and the
    per-platform scrapers) that should go through their `get_x()` accessors instead
  - zero-argument `lines.append()` calls (corrected to `lines.append("")`)
  - the `investigate`, `compare`, and `trending` tool bodies, rebuilt to match the
    actual data shape returned by the research agent / scrapers

## Do I need to run this manually?

**No, not normally.** `install_mcpsearch.sh` embeds and runs this exact patch logic
itself during Phase 2 — you don't need to touch this directory for a standard install.

This file exists for two reasons:

1. **Reference** — so you can review exactly what gets changed in `server.py` without
   digging it out of a bash heredoc inside `install_mcpsearch.sh`.
2. **Manual re-application** — if you've already run the installer once, then pulled a
   newer upstream `MCPSearch` commit into `~/MCPSearch` yourself (outside the
   installer), and want to re-apply just this patch without re-running the whole
   script:

   ```bash
   python3 patches/patch_server.py
   ```

The patch is idempotent — re-running it against an already-patched `server.py` is a
safe no-op, since it only rewrites the exact broken patterns it's looking for.