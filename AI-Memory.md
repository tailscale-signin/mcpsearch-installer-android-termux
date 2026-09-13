# AI Memory

## Repository Overview

This repository provides an unofficial, community-maintained Bash installer for running [MCPSearch](https://github.com/JonusNattapong/MCPSearch) and companion search & crawl tools as stdio MCP servers in Android Termux. The installer prepares native and Python dependencies, clones upstream MCPSearch, applies Termux-specific and upstream compatibility patches, generates multi-server client-launch configurations, and runs import/tool/cache smoke tests.

**Primary stack:** Bash, Python patch scripts, Termux `pkg`, `pip`, Git, MCP, `httpx`, `hishel`, `anysqlite`, `grep-mcp`, and `trafilatura`.

**Execution model:** `install_mcpsearch.sh` is the product entry point. It installs the patched upstream project under `~/MCPSearch` (configurable via `--app-dir`), writes runtime artifacts under `~/.mcpsearch` (configurable via `--config-dir`), and stores logs under `~/.mcpsearch_logs` (configurable via `--log-dir`). `bootstrap.sh` provides a safe curl-to-bash bootstrap entry point.

## Repository Index

### Root

#### `AI-Memory.md`
- **Responsibility:** Persistent architecture and engineering context for this repository.
- **Key contents:** Repository overview, file index, engineering guidelines, and known traps.
- **Dependencies:** Must be kept synchronized with repository changes.

#### `README.md`
- **Responsibility:** User-facing overview, motivation, requirements, installation instructions, troubleshooting guidance, and repository map.
- **Key contents:** Documents the installer phases (0-5), Search & Crawl Suite tools (`grep-mcp`, `trafilatura`), generated paths, patched upstream failures, CLI flags (`--help`, `--version`, `--bundle`, `--with-grep`, `--with-crawler`, `--dry-run`, `--check`, `--no-rust`, `--no-tur`, `--no-wake-lock`, path overrides), env vars (`MCPSEARCH_USE_TUR`, `MCPSEARCH_WAKE_LOCK`, `MCPSEARCH_WITH_GREP`, `MCPSEARCH_WITH_CRAWLER`), bootstrap curl piping, and git clone installation flow.
- **Dependencies:** Describes `install_mcpsearch.sh`, `bootstrap.sh`, `patches/`, `CHANGELOG.md`, and `LICENSE`; links to upstream MCPSearch.

#### `bootstrap.sh`
- **Responsibility:** Safe curl-to-bash entry point (v1.2).
- **Key functions:**
  - Streams or downloads `install_mcpsearch.sh` into a temporary file in `$TMPDIR` / `$HOME/.mcpsearch_tmp` (never the real `/tmp`).
  - Verifies minimum size (>5KB) and shebang before execution.
  - Supports `--installer-branch <branch>`, `--bootstrap-version`, and passes through all remaining arguments cleanly to `install_mcpsearch.sh`.
  - Cleans up downloaded files via `trap ... EXIT`.
- **Dependencies:** `curl` or `wget`, Termux bash environment.

#### `install_mcpsearch.sh`
- **Responsibility:** Main Termux installer and test runner (v2.0.0 — Search & Crawl Suite).
- **Key functions:**
  - `step`, `ok`, `err`, `warn`, `fatal`: formatted status and failure reporting.
  - `spinner`: animated single-line progress feedback for long-running operations running under `env -u LD_PRELOAD` to prevent linker warnings.
  - `install_pkg`: package-aware, multi-tier Python dependency installation fallback supporting TUR PyPI prebuilt wheels and soft-fallback for `selectolax`.
  - CLI argument parser supporting `--bundle`, `--with-grep`, `--with-crawler`, `--no-tur`, `--no-wake-lock`, `--dry-run`, `--check`, etc.
- **Major phases:**
  - **Phase 0:** Storage pre-flight check — warns early if free space on `$HOME` is low (native builds can need 2-4GB).
  - **Phase 1:** Updates Termux in non-interactive batch mode and installs native build/runtime packages (Rust toolchain is optional via `--no-rust`).
  - **Phase 2:** Shallow clone (`--depth 1`); strips Playwright; adds `anysqlite`; patches `mcp_server/server.py` and `utils/http_client.py`; installs Python dependencies via TUR PyPI index and package-aware tiers; installs companion packages (`grep-mcp`, `trafilatura`) if enabled.
  - **Phase 3:** Generates `~/.mcpsearch/run.sh` launcher (with `termux-wake-lock`), companion launchers (`run_grep.sh`), and unified multi-server `mcp_client_snippet.json`.
  - **Phase 4:** Imports the MCP server, exercises `get_crawl_stats()`, validates companion server imports, and verifies live `hishel` caching without deprecation warnings (Phase 4b).
  - **Phase 5:** Post-install cleanup — purges pip cache, removes scratch tmp dir, and clears cargo registry cache to reclaim build space.
- **Modes:**
  - Standard install: runs Phases 0 through 5.
  - `--dry-run`: strictly read-only inspection of paths, tools, free space, and execution plan without making any disk modifications.
  - `--check`: runs Phase 4 and 4b self-tests only against existing `$APP_DIR` without touching `pkg`, `pyproject.toml`, or running `pip install`.
- **Dependencies:** Termux `pkg`; Bash utilities; `git`; Python/pip; Rust/Clang/native libraries; network access; upstream MCPSearch file layout and symbols; `httpbin.org` (or `--cache-test-url`) for the cache smoke test.

#### `CHANGELOG.md`
- **Responsibility:** Human-readable release history.
- **Key contents:** Documents all releases through v2.0.0 (Search & Crawl Suite, `grep-mcp`, `trafilatura`, unified multi-server config).
- **Dependencies:** Must track behavior and version changes in `install_mcpsearch.sh` and related reference patches.

#### `LICENSE`
- **Responsibility:** MIT license terms and copyright notice.

### `patches/`

Reference-only copies of patch logic embedded in the installer.

#### `patches/README.md`
- **Responsibility:** Explains the purpose, manual usage, idempotency expectations, and synchronization requirement for reference patches.

#### `patches/patch_server.py`
- **Responsibility:** Standalone reference/manual patcher for `~/MCPSearch/mcp_server/server.py`.

## Engineering Guidelines (Do's)

- Inspect the current upstream MCPSearch layout and affected symbols before changing regex patches.
- Keep changes minimal, idempotent, and safe when the installer is rerun against an existing installation.
- Preserve import-line exclusions when replacing bare names; transformations must never rewrite module paths.
- Match complete multi-line Python function signatures when replacing function bodies.
- Keep embedded patch heredocs and their files under `patches/` synchronized.
- Quote shell path variables and account for spaces and Termux-specific paths.
- Use `$HOME/.mcpsearch_tmp` rather than `/tmp`, which may be inaccessible under Android scoped storage.
- Log each installation phase and include actionable log paths in failures.
- Fail fast for required packages, malformed patches, compile errors, and failed smoke tests; reserve warnings for genuinely recoverable operations.
- Run `python -m py_compile` on modified Python files before installation proceeds.
- Test both server import/tool behavior and the real async HTTP-cache path.
- Treat expected deprecation warnings as errors in targeted tests so dependency API drift is caught.
- Update `README.md`, `CHANGELOG.md`, and `AI-Memory.md` whenever user-visible behavior, dependencies, phases, or generated files change.
- Keep native-build memory in check on constrained Android devices: cap `CARGO_BUILD_JOBS` and lower `-C opt-level` (via `MCPSEARCH_RUST_OPT`) to avoid Android's process killer (signal 9).
- Use `--no-cache-dir` on pip installs and purge caches after install to avoid storage bloat on phones.
- Remember that C-extension packages (e.g. `lxml`, `selectolax`) link against Termux's `libxml2`/`libxslt` and must NOT be sent through the Rust link-flag tier.
- **Heredoc variable expansion rule:** Launchers (`run.sh`) and config snippets (`mcp_client_snippet.json`) that must contain concrete values at install time **must use unquoted heredocs** (`<< LAUNCHER_EOF` / `<< JSONEOF`). Python scripts and help text containing `$` variables that should not be expanded by bash **must use quoted heredocs** (`<< 'PYEOF'` / `<< 'HELPEOF'`).

## Anti-Patterns & Traps (Don'ts)

- Do not use real `/tmp` for installer scratch files on Termux.
- Do not add Playwright/browser automation to the Android flow without a proven supported runtime strategy.
- Do not globally replace names such as `crawler.` or `aggregator.` without skipping `import` and `from` lines.
- Do not use a regex that captures only the first line of a multi-line Python function signature.
- Do not reintroduce `get_research_agent_instance()` when the upstream accessor is `get_research_agent()`.
- Do not call `lines.append()` without an argument.
- Do not assume research findings are grouped dictionaries; current compatibility logic expects a flat list of finding dictionaries and groups it by `source.source_type`.
- Do not omit `anysqlite` when using `hishel`'s async SQLite storage backend.
- Do not pass deprecated `refresh_ttl_on_access` to `AsyncSqliteStorage`.
- Do not assume scientific/native Python wheels are available in Termux; preserve tested fallback installation paths.
- Do not send C-extension packages (`lxml`, `selectolax`) through the Rust link-flag tier.
- Do not install the Rust toolchain when `--no-rust` is requested.
- Do not quote heredoc terminators when writing launcher scripts (`run.sh`) or config snippets (`mcp_client_snippet.json`) that need shell variables expanded into concrete paths.
- Do not run `pkg update`, `pip install`, or mutate upstream `pyproject.toml` when `--check` mode is invoked.
- Do not create directories during `--dry-run`; dry-run must be strictly read-only.
