# patches/

This directory contains standalone reference copies of the Python patch logic that `install_mcpsearch.sh` embeds and runs automatically during installation (Phase 2 of the installer).

## Why this exists

The main installer (`install_mcpsearch.sh`) generates and executes these patch scripts on-the-fly inside a Termux temp directory as part of its automated setup. The copies here are kept **for reference and manual troubleshooting only** — they let you:

- Inspect exactly what code transformations are applied to the cloned `MCPSearch` source tree without having to read through the installer's embedded heredocs.
- Re-run a specific patch step manually against a local checkout of `MCPSearch` if you need to debug a failed install without rerunning the entire installer.
- Review changes to the patch logic in isolation via git history/diffs.

## Files

- **`patch_server.py`** — Patches `mcp_server/server.py` in a cloned `MCPSearch` checkout:
  1. Fixes a stale `get_research_agent_instance()` call to the correct `get_research_agent()`, inserting the import if missing.
  2. Rewrites bare factory-object references (e.g. `aggregator.`, `crawler.`, `summarizer.`, `reddit_scraper.`, `twitter_scraper.`, `youtube_scraper.`, `github_scraper.`) to their corresponding `get_X()` calls, skipping `import`/`from` lines so real imports are never touched.
  3. Fixes zero-argument `lines.append()` calls to `lines.append("")`.

## Important note

These files are **not imported or executed by `install_mcpsearch.sh`** — the installer contains its own embedded, self-contained versions of this logic (written to a temp file at install time). If you edit the installer's patch behavior, update **both** the embedded heredoc in `install_mcpsearch.sh` and the corresponding reference copy here to keep them in sync.

To run this script manually against an existing `~/MCPSearch` checkout on Termux:

```bash
python3 patches/patch_server.py
```

It is idempotent — safe to re-run without side effects if the target file is already patched.