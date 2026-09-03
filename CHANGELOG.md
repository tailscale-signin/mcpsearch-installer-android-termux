# Changelog

All notable changes to this installer are documented here.

## v1.2

**Focus: hishel async HTTP cache fixes**

- Added missing `anysqlite>=0.0.5` dependency to `pyproject.toml`. `hishel[httpx]`'s `AsyncSqliteStorage` backend requires `anysqlite`, but it was never declared, causing an `ImportError` at cache-client construction time inside `search_and_summarize` and any other cache-enabled HTTP call.
- Removed the deprecated `refresh_ttl_on_access=config.refresh_on_hit` kwarg from the `AsyncSqliteStorage(...)` call in `utils/http_client.py`. This parameter is a no-op as of `hishel` 1.3.x and only emitted a `UserWarning` on every client construction. Patch is applied via an idempotent regex (safe to re-run, no-op if already patched), followed by a `py_compile` check to confirm the file is still syntactically valid.
- Added `hishel` and `anysqlite` explicitly to the pip install tier loop, rather than relying solely on the editable install to pull them in transitively (which could lag or silently fail on constrained Termux environments).
- Added a new **Phase 4b** self-test: constructs a real `AsyncCacheClient` with `always_cache=True`, makes two live GET requests, and asserts the second one returns `hishel_from_cache=True`. The whole test runs under `warnings.simplefilter("error", UserWarning)` so any regression of the deprecated-kwarg warning fails the install loudly instead of silently.
- Verified end-to-end: server imports cleanly, responds to a live `get_crawl_stats()` call, and the HTTP cache layer is confirmed functional with zero deprecation warnings.

## v1.1

**Focus: Termux sandbox & regex patch correctness**

- **Termux sandbox fix:** switched from `/tmp` to `$HOME/.mcpsearch_tmp` for all scratch files. Termux's scoped storage denies writes to the real `/tmp`, which silently broke the patch scripts.
- **Line-aware regex patch:** bare-name replacements (`crawler.` → `get_crawler().`, `aggregator.` → `get_aggregator().`, etc.) now skip any line starting with `from`/`import`. Previously this turned `from crawler.engine import ...` into `from get_crawler().engine import ...`, producing a `SyntaxError`.
- **Multi-line function signature fix:** the regex used to replace `investigate()`/`compare()`/`trending()` function bodies now matches the *full* multi-line signature through `-> str:`, not just the first line ending in `\n`. Previously, multi-line signatures were truncated mid-signature, producing unclosed `def`s and stray `try:` syntax errors.
- Verified: Phase 4 self-test passes — server imports cleanly and responds to a live `get_crawl_stats()` tool call.

## v1.0

**Initial release**

- 4-phase installer: clone MCPSearch, patch known bugs, install dependencies, self-test.
- Patches bare factory-object calls (`crawler.`, `aggregator.`, `summarizer.`, and various platform scrapers) to their `get_x()` accessor equivalents.
- Fixes an undefined `get_research_agent_instance()` reference to the correct `get_research_agent()`.
- Fixes zero-argument `lines.append()` calls to `lines.append("")`.
- Rebuilds the `investigate`, `compare`, and `trending` tool function bodies to match the actual data shape returned by the research agent and platform scrapers (previously assumed a dict-of-categories shape; actual data is a flat list of dicts).
- Strips Playwright from `pyproject.toml` for HTTP-only crawling (headless browser automation isn't practical on Android/Termux).
- Multi-tier pip install fallback (wheel → `--no-binary` → Rust-linked force-reinstall) to work around inconsistent native wheel availability on Termux.
- Generates a launcher script and MCP client config snippet.
- Phase 4 self-test: imports the server module and exercises a live tool call.