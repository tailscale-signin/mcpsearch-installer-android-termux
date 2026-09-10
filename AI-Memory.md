# AI Memory

## Repository Overview

This repository provides an unofficial, community-maintained Bash installer for running [MCPSearch](https://github.com/JonusNattapong/MCPSearch) as a stdio MCP server in Android Termux. The installer prepares native and Python dependencies, clones upstream MCPSearch, applies Termux-specific and upstream compatibility patches, generates client-launch configuration, and runs import/tool/cache smoke tests.

**Primary stack:** Bash, Python patch scripts, Termux `pkg`, `pip`, Git, MCP, `httpx`, `hishel`, and `anysqlite`.

**Execution model:** `install_mcpsearch.sh` is the product entry point. It installs the patched upstream project under `~/MCPSearch` (configurable via `--app-dir`), writes runtime artifacts under `~/.mcpsearch` (configurable via `--config-dir`), and stores logs under `~/.mcpsearch_logs` (configurable via `--log-dir`). `bootstrap.sh` provides a safe curl-to-bash bootstrap entry point.

## Repository Index

### Root

#### `AI-Memory.md`
- **Responsibility:** Persistent architecture and engineering context for this repository.
- **Key contents:** Repository overview, file index, engineering guidelines, and known traps.
- **Dependencies:** Must be kept synchronized with repository changes.

#### `README.md`
- **Responsibility:** User-facing overview, motivation, requirements, installation instructions, troubleshooting guidance, and repository map.
- **Key contents:** Documents the installer phases (0-5), generated paths, patched upstream failures, CLI flags (`--help`, `--version`, `--dry-run`, `--check`, `--no-rust`, `--no-color`, path overrides, `--cache-test-url`), env vars (`MCPSEARCH_RUST_OPT`, `CARGO_BUILD_JOBS`), bootstrap curl piping, and git clone installation flow.
- **Dependencies:** Describes `install_mcpsearch.sh`, `bootstrap.sh`, `patches/`, `CHANGELOG.md`, and `LICENSE`; links to upstream MCPSearch.

#### `bootstrap.sh`
- **Responsibility:** Safe curl-to-bash entry point (v1.1).
- **Key functions:**
  - Streams or downloads `install_mcpsearch.sh` into a temporary file in `$TMPDIR` / `$HOME/.mcpsearch_tmp` (never the real `/tmp`).
  - Verifies minimum size (>5KB) and shebang before execution.
  - Supports `--installer-branch <branch>`, `--bootstrap-version`, and passes through all remaining arguments cleanly to `install_mcpsearch.sh`.
  - Cleans up downloaded files via `trap ... EXIT`.
- **Dependencies:** `curl` or `wget`, Termux bash environment.

#### `install_mcpsearch.sh`
- **Responsibility:** Main Termux installer and test runner (v1.8.1).
- **Key functions:**
  - `step`, `ok`, `err`, `warn`, `fatal`: formatted status and failure reporting.
  - `spinner`, `pkg_progress`: animated single-line progress feedback for long-running `pkg` operations.
  - `install_pkg`: package-aware, multi-tier Python dependency installation fallback.
  - `parse_args`: robust CLI flag parsing supporting both `--flag VALUE` and `--flag=VALUE` syntax.
- **Major phases:**
  - **Phase 0:** Storage pre-flight check — warns early if free space on `$HOME` is low (native builds can need 2-4GB).
  - **Phase 1:** Updates Termux and installs native build/runtime packages (Rust toolchain is optional via `--no-rust`).
  - **Phase 2:** Clones or resets upstream MCPSearch; removes Playwright; adds `anysqlite`; patches `mcp_server/server.py` and `utils/http_client.py`; installs Python dependencies (package-aware tiers) and the package.
  - **Phase 3:** Generates `~/.mcpsearch/run.sh` launcher and `mcp_client_snippet.json` using unquoted heredocs so concrete paths expand into the files.
  - **Phase 4:** Imports the MCP server, exercises `get_crawl_stats()`, and verifies live `hishel` caching without deprecation warnings (Phase 4b).
  - **Phase 5:** Post-install cleanup — purges pip cache, removes scratch tmp dir, and clears cargo registry cache to reclaim build space.
- **Modes:**
  - Standard install: runs Phases 0 through 5.
  - `--dry-run`: strictly read-only inspection of paths, tools, free space, and execution plan without making any disk modifications.
  - `--check`: runs Phase 4 and 4b self-tests only against existing `$APP_DIR` without touching `pkg`, `pyproject.toml`, or running `pip install`.
- **Install tiers (`install_pkg`):**
  1. Prebuilt wheel (`--no-cache-dir`).
  2. Source build (`--no-binary :all:`).
  3. Package-aware last resort: C-extension packages (`lxml`, `selectolax`) retry with `CFLAGS`/`LDFLAGS` pointing at Termux's `libxml2`/`libxslt`; everything else retries with Rust link flags derived from the live interpreter (`-lpython${PYVER}`), unless `--no-rust` is set.
- **Dependencies:** Termux `pkg`; Bash utilities; `git`; Python/pip; Rust/Clang/native libraries; network access; upstream MCPSearch file layout and symbols; `httpbin.org` (or `--cache-test-url`) for the cache smoke test.

#### `CHANGELOG.md`
- **Responsibility:** Human-readable release history.
- **Key contents:** v1.0 initial installer through v1.8 (CLI flags, custom paths, check mode, bootstrap script) and v1.8.1 (fix launcher heredoc expansion, fix arg parsing, fix APP_DIR propagation in self-tests and patches, make check mode strictly run self-tests only).
- **Dependencies:** Must track behavior and version changes in `install_mcpsearch.sh` and related reference patches.

#### `LICENSE`
- **Responsibility:** MIT license terms and copyright notice.
- **Dependencies:** License notices should remain intact in distributed copies.

### `patches/`

Reference-only copies of patch logic embedded in the installer. These files are not imported or invoked automatically by `install_mcpsearch.sh`.

#### `patches/README.md`
- **Responsibility:** Explains the purpose, manual usage, idempotency expectations, and synchronization requirement for reference patches.
- **Key contents:** Warns that edits to patch behavior must be made both in the installer heredoc and in the corresponding reference file.
- **Dependencies:** `install_mcpsearch.sh` and `patches/patch_server.py`.

#### `patches/patch_server.py`
- **Responsibility:** Standalone reference/manual patcher for `~/MCPSearch/mcp_server/server.py`.
- **Key operations:**
  - Replaces stale `get_research_agent_instance()` calls with `get_research_agent()` and inserts its import when needed.
  - Rewrites bare service/scraper object references to `get_X()` accessor calls while skipping import lines.
  - Replaces invalid zero-argument `lines.append()` calls with `lines.append("")`.
  - Writes the target file and reports verification results.
- **Dependencies:** Python standard library (`os`, `re`, `sys`) and the expected upstream checkout path/layout.
- **Important limitation:** It is a partial reference copy; the installer also embeds function-body patches and an HTTP-client patch that are not represented by this file.

## Engineering Guidelines (Do's)

- Inspect the current upstream MCPSearch layout and affected symbols before changing regex patches.
- Keep changes minimal, idempotent, and safe when the installer is rerun against an existing installation.
- Preserve import-line exclusions when replacing bare names; transformations must never rewrite module paths.
- Match complete multi-line Python function signatures when replacing function bodies.
- Keep embedded patch heredocs and their files under `patches/` synchronized. If a reference copy is intentionally partial, document that clearly.
- Quote shell path variables and account for spaces and Termux-specific paths.
- Use `$HOME/.mcpsearch_tmp` rather than `/tmp`, which may be inaccessible under Android scoped storage.
- Log each installation phase and include actionable log paths in failures.
- Fail fast for required packages, malformed patches, compile errors, and failed smoke tests; reserve warnings for genuinely recoverable operations.
- Run `python -m py_compile` on modified Python files before installation proceeds.
- Test both server import/tool behavior and the real async HTTP-cache path.
- Treat expected deprecation warnings as errors in targeted tests so dependency API drift is caught.
- Update `README.md` and `CHANGELOG.md` whenever user-visible behavior, dependencies, phases, or generated files change.
- Update this `AI-Memory.md` whenever repository files or established practices change.
- Keep the installer version, header changelog, documentation, and release changelog aligned.
- Preserve the MIT license and the unofficial/non-affiliation notice.
- Keep native-build memory in check on constrained Android devices: cap `CARGO_BUILD_JOBS` and lower `-C opt-level` (via `MCPSEARCH_RUST_OPT`) to avoid Android's process killer (signal 9).
- Use `--no-cache-dir` on pip installs and purge caches after install to avoid storage bloat on phones.
- Remember that C-extension packages (e.g. `lxml`, `selectolax`) link against Termux's `libxml2`/`libxslt` and must NOT be sent through the Rust link-flag tier.
- **Heredoc variable expansion rule:** Launchers (`run.sh`) and config snippets (`mcp_client_snippet.json`) that must contain concrete values at install time **must use unquoted heredocs** (`<< LAUNCHER_EOF` / `<< JSONEOF`). Python scripts and help text containing `$` variables that should not be expanded by bash **must use quoted heredocs** (`<< 'PYEOF'` / `<< 'HELPEOF'`), or dynamic values should be injected via explicit string substitution.

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
- Do not send C-extension packages (`lxml`, `selectolax`) through the Rust link-flag tier — they need `libxml2`/`libxslt` CFLAGS/LDFLAGS instead.
- Do not install the Rust toolchain when `--no-rust` is requested; Rust-based packages (e.g. `pydantic-core`) should then fail fast if no prebuilt wheel exists.
- Do not edit only a reference patch or only its embedded installer copy when both represent the same transformation.
- Do not assume reference scripts are valid merely because embedded versions pass; compile/test standalone files independently after edits.
- Do not hardcode credentials, tokens, API keys, or private endpoints in scripts, generated configuration, tests, or documentation.
- Do not print secrets or sensitive MCP client configuration into logs.
- Do not silently continue after a required patch fails verification or produces invalid Python.
- Do not treat a successful import as sufficient verification; exercise at least one tool and the cache behavior.
- Do not forget that the live cache test depends on external network availability; distinguish network failures from code regressions when diagnosing it.
- Do not quote heredoc terminators when writing launcher scripts (`run.sh`) or config snippets (`mcp_client_snippet.json`) that need shell variables like `$APP_DIR`, `$PY`, or `$CFG_DIR` expanded into concrete paths.
- Do not use `[ "$1" = "$2" ] && shift 2 || shift` for argument parsing; implement separate case arms for `--flag VALUE` (shift 2) and `--flag=VALUE` (shift 1).
- Do not run `pkg update`, `pip install`, or mutate upstream `pyproject.toml` when `--check` mode is invoked; `--check` must only execute Phase 4 tests against an existing installation.
- Do not create directories (`mkdir`) during `--dry-run`; dry-run must be strictly read-only.
- Do not rely on an invalid shebang format; executable scripts should begin exactly with `#!` followed by the interpreter path.
- Do not assume upstream `main` remains compatible forever; the installer currently hard-resets to `origin/main`, so upstream changes can break path- and regex-based patches.
