# Changelog

All notable changes to this installer are documented here.

## v1.9.0

**Focus: performance & non-interactive execution reliability**

- **Non-interactive Dpkg environment:** Enforces `DEBIAN_FRONTEND=noninteractive` and `-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold` across all package operations. Prevents background installer subshells from freezing or crashing when apt encounters config file prompts on Android Termux.
- **Batch package detection & installation:** Replaced the slow sequential loop (12 separate `pkg install` runs) with a fast `dpkg -s` check that only installs missing packages in a single batch. Saves 3–5 minutes of package manager overhead.
- **Native `python-lxml` package integration:** Pre-installs Termux's native `python-lxml` binary if available, avoiding 5–10 minutes of compiling `lxml` from source on low-power mobile ARM processors.
- **Bandwidth and I/O optimization:** Converted git operations to use shallow clones (`git clone --depth 1 --single-branch`) and shallow fetches (`git fetch --depth 1`), dramatically speeding up source tree synchronization on mobile storage.
- **Fast-path pip wheel resolution:** Attempts a single batch wheel install for standard Python dependencies first, and falls back to custom C-lib and Rust link flags only if needed.

## v1.8.1

- Fixed critical launcher expansion bug (unquoted heredocs for run.sh and mcp_client_snippet.json).
- Fixed CLI option shifting bug (spurious unknown-option warnings).
- Restricts `--check` to self-tests and makes `--dry-run` zero-side-effect.

## v1.7

**Focus: storage & native-build hardening**

- **Package-aware install tiers.** The last-resort pip fallback tier previously sent *every* package through the Rust link flag (`-lpython3.14`). That was meaningless for C-extension packages like `lxml`/`selectolax`, which link against Termux's `libxml2`/`libxslt` — not Rust. Those packages now retry with `CFLAGS`/`LDFLAGS` pointed at the Termux prefix instead, fixing the "lxml: retrying with rust link flags" dead-end.
- **Memory-safe Rust builds.** `CARGO_BUILD_JOBS=1` and `-C opt-level=1` (configurable via `MCPSEARCH_RUST_OPT`) are now set for Rust source builds. This prevents Android's process killer (signal 9) from terminating `cargo`/`rustc` on low-RAM phones, which previously killed pydantic-core builds mid-compile.
- **Storage pre-flight check (Phase 0).** Warns early if free space on `$HOME` is below ~2 GB, before the heavy native builds start.
- **`--no-cache-dir` on every pip install.** Stops pip's download cache from silently eating GBs of storage on constrained devices.
- **New Phase 5 cleanup.** Purges the pip cache, removes the scratch tmp dir, and clears the cargo registry cache to reclaim build space after a successful install.
- **Optional `--no-rust` flag.** Skips installing the Rust toolchain and the Rust-link fallback tier entirely. Useful for users who want prebuilt wheels only and a fast, clear failure if a Rust-built package has no wheel.

## v1.2

**Focus: hishel async HTTP cache fixes**

- Added missing `anysqlite>=0.0.5` dependency to `pyproject.toml`. `hishel[httpx]`'s `AsyncSqliteStorage` backend requires `anysqlite`, but it was never declared, causing an an `ImportError` at cache-client construction time inside `search_and_summarize` and any other cache-enabled HTTP call.
- Removed the deprecated `refresh_ttl_on_access=config.refresh_on_hit` kwarg from the `AsyncSqliteStorage(...)` call in `utils/http_client.py`. This parameter is a no-op as of `hishel` 1.3.x and only emitted a `UserWarning` on every client construction. Patch is applied via an idempotent regex (safe to re-run, no-op if already patched), followed by a a `py_compile` check to confirm the file is still syntactically valid.
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