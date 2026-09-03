# MCPSearch Installer for Android Termux

A hardened, self-testing bash installer that gets [MCPSearch](https://github.com/JonusNattapong/MCPSearch) running correctly inside **Termux on Android** as a stdio MCP server — patching several upstream bugs and Termux-specific sandbox issues along the way, then verifying the result with live smoke tests before declaring success.

> This is an unofficial, community installer/patch script. It is not affiliated with the MCPSearch project maintainers.

## Why this exists

Running MCPSearch straight from `pip install` on Termux hits several walls:

- Termux's scoped storage denies writes to the real `/tmp`, breaking anything that assumes standard temp-dir access.
- A handful of bare-name factory calls in `mcp_server/server.py` (e.g. `crawler.fetch(...)` instead of `get_crawler().fetch(...)`) raise `NameError` at call time.
- The `investigate`, `compare`, and `trending` tool handlers assume a data shape from the research agent/scrapers that doesn't match what's actually returned, causing `KeyError`/`AttributeError` mid-request.
- `hishel`'s async SQLite cache backend requires the `anysqlite` package, which isn't declared as a dependency — so any cache-enabled HTTP call (including `search_and_summarize`) fails at client construction with an `ImportError`.
- `utils/http_client.py` passes a `refresh_ttl_on_access` kwarg to `AsyncSqliteStorage` that is deprecated/no-op as of `hishel` 1.3.x, and now only emits a `UserWarning` on every client construction.

This script clones the upstream repo fresh, applies idempotent patches for all of the above, installs dependencies with a multi-tier fallback strategy (since Termux's `pip` wheel availability for scientific/native packages is inconsistent), and then runs two rounds of live self-tests to confirm the server actually works — not just that it imports.

## What it does (high level)

1. **Phase 1 — Termux environment:** updates `pkg`, installs required native toolchain packages (`rust`, `clang`, `libxml2`, etc.), upgrades `pip`.
2. **Phase 2 — Clone, patch, install:**
   - Clones/updates the MCPSearch repo.
   - Strips Playwright (HTTP-only crawling mode — headless browsers aren't practical on Android).
   - Adds the missing `anysqlite` dependency to `pyproject.toml`.
   - Regex-patches `mcp_server/server.py`: fixes bare factory-object calls, a broken `get_research_agent_instance` reference, empty `lines.append()` calls, and rebuilds the `investigate`/`compare`/`trending` tool bodies to match the actual data shapes.
   - Regex-patches `utils/http_client.py` to remove the deprecated `refresh_ttl_on_access` kwarg.
   - Installs Python dependencies with a 3-tier fallback (wheel → `--no-binary` → Rust-linked force-reinstall).
   - Editable-installs the MCPSearch package.
3. **Phase 3 — Launcher & client config:** writes a `run.sh` launcher and an MCP client config JSON snippet you can merge into Claude Desktop / Cursor / etc.
4. **Phase 4 — Self-tests:**
   - Imports the server module, enumerates registered tools, and calls `get_crawl_stats()` live.
   - **Phase 4b:** constructs a real cached HTTP client, makes two requests, and asserts the second one is served from cache (`hishel_from_cache=True`) with zero deprecation warnings (enforced via `warnings-as-errors`).

All patches are idempotent — safe to re-run the script against an existing install without duplicating changes.

## Usage

```bash
curl -fsSL -o ~/install_mcpsearch.sh https://raw.githubusercontent.com/tailscale-signin/mcpsearch-installer-android-termux/main/install_mcpsearch.sh
chmod +x ~/install_mcpsearch.sh
bash ~/install_mcpsearch.sh
```

After a successful run, you'll have:

- `~/MCPSearch` — patched source tree
- `~/.mcpsearch/run.sh` — launcher script
- `~/.mcpsearch/mcp_client_snippet.json` — config to merge into your MCP client
- `~/.mcpsearch_logs/` — full logs for every phase, useful for debugging if something fails

Merge the contents of `mcp_client_snippet.json` into your MCP client's config (e.g. `claude_desktop_config.json`), then restart the client.

## Requirements

- Termux (F-Droid build recommended over the deprecated Play Store version)
- ~1–2 GB free storage (native builds for `lxml`, `selectolax`, etc. can be heavy)
- Internet access for `pkg`/`pip`/`git`

## Logs & troubleshooting

Every phase writes to `~/.mcpsearch_logs/`. If the script exits with `fatal`, check the referenced log file first — most failures are native-dependency build issues that resolve after `pkg upgrade` or a Termux storage permission fix (`termux-setup-storage`).

## License

MIT — see [LICENSE](LICENSE).
