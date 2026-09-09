# AI Memory

## Repository Overview

This repository provides an unofficial, community-maintained Bash installer for running [MCPSearch](https://github.com/JonusNattapong/MCPSearch) as a stdio MCP server in Android Termux. The installer prepares native and Python dependencies, clones upstream MCPSearch, applies Termux-specific and upstream compatibility patches, generates client-launch configuration, and runs import/tool/cache smoke tests.

**Primary stack:** Bash, Python patch scripts, Termux `pkg`, `pip`, Git, MCP, `httpx`, `hishel`, and `anysqlite`.

**Execution model:** `install_mcpsearch.sh` is the product entry point. It installs the patched upstream project under `~/MCPSearch`, writes runtime artifacts under `~/.mcpsearch`, and stores logs under `~/.mcpsearch_logs`.

## Repository Index

### Root

#### `AI-Memory.md`
- **Responsibility:** Persistent architecture and engineering context for this repository.
- **Key contents:** Repository overview, file index, engineering guidelines, and known traps.
- **Dependencies:** Must be kept synchronized with repository changes.

#### `README.md`
- **Responsibility:** User-facing overview, motivation, requirements, installation instructions, troubleshooting guidance, and repository map.
- **Key contents:** Documents the four installer phases, generated paths, patched upstream failures, and one-command installation flow.
- **Dependencies:** Describes `install_mcpsearch.sh`, `patches/`, `CHANGELOG.md`, and `LICENSE`; links to upstream MCPSearch.

#### `install_mcpsearch.sh`
- **Responsibility:** Main v1.2 Termux installer and test runner.
- **Key functions:**
  - `step`, `ok`, `err`, `warn`, `fatal`: formatted status and failure reporting.
  - `install_pkg`: three-tier Python dependency installation fallback.
- **Major phases:**
  1. Updates Termux and installs native build/runtime packages.
  2. Clones or resets upstream MCPSearch; removes Playwright; adds `anysqlite`; patches `mcp_server/server.py` and `utils/http_client.py`; installs Python dependencies and the package.
  3. Generates `~/.mcpsearch/run.sh` and `mcp_client_snippet.json`.
  4. Imports the MCP server, exercises `get_crawl_stats()`, and verifies live `hishel` caching without deprecation warnings.
- **Dependencies:** Termux `pkg`; Bash utilities; `git`; Python/pip; Rust/Clang/native libraries; network access; upstream MCPSearch file layout and symbols; `httpbin.org` for the cache smoke test.

#### `CHANGELOG.md`
- **Responsibility:** Human-readable release history.
- **Key contents:** v1.0 initial installer, v1.1 Termux/regex corrections, and v1.2 `hishel`/`anysqlite` cache fixes and tests.
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
- Do not edit only a reference patch or only its embedded installer copy when both represent the same transformation.
- Do not assume reference scripts are valid merely because embedded versions pass; compile/test standalone files independently after edits.
- Do not hardcode credentials, tokens, API keys, or private endpoints in scripts, generated configuration, tests, or documentation.
- Do not print secrets or sensitive MCP client configuration into logs.
- Do not silently continue after a required patch fails verification or produces invalid Python.
- Do not treat a successful import as sufficient verification; exercise at least one tool and the cache behavior.
- Do not forget that the live cache test depends on external network availability; distinguish network failures from code regressions when diagnosing it.
- Do not generate launchers with unresolved shell variables. Verify generated `run.sh` and JSON contain usable absolute paths or deliberately preserved runtime variables.
- Do not rely on an invalid shebang format; executable scripts should begin exactly with `#!` followed by the interpreter path.
- Do not assume upstream `main` remains compatible forever; the installer currently hard-resets to `origin/main`, so upstream changes can break path- and regex-based patches.
