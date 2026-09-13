# MCPSearch Installer for Android Termux (v2.0.0 — Search & Crawl Suite)

A hardened, self-testing bash installer and curl bootstrap that gets [MCPSearch](https://github.com/JonusNattapong/MCPSearch) and companion search/crawler tools running reliably inside **Termux on Android** as stdio MCP servers — patching upstream bugs, resolving Termux-specific sandbox issues, and generating ready-to-merge multi-server MCP client configurations.

> This is an unofficial, community installer/patch script. It is not affiliated with the MCPSearch project maintainers.

## Why this exists

Running MCPSearch straight from `pip install` on Termux hits several walls:

- Termux's scoped storage denies writes to the real `/tmp`, breaking anything that assumes standard temp-dir access.
- A handful of bare-name factory calls in `mcp_server/server.py` (e.g. `crawler.fetch(...)` instead of `get_crawler().fetch(...)`) raise `NameError` at call time.
- The `investigate`, `compare`, and `trending` tool handlers assume a data shape from the research agent/scrapers that doesn't match what's actually returned, causing `KeyError`/`AttributeError` mid-request.
- `hishel`'s async SQLite cache backend requires the `anysqlite` package, which isn't declared as a dependency — so any cache-enabled HTTP call (including `search_and_summarize`) fails at client construction with an `ImportError`.
- `utils/http_client.py` passes a `refresh_ttl_on_access` kwarg to `AsyncSqliteStorage` that is deprecated/no-op as of `hishel` 1.3.x, and now only emits a `UserWarning` on every client construction.
- Native builds on a phone are storage- and memory-hungry: `pydantic-core` (Rust) and `lxml` (C) can need 2–4 GB and can be killed by Android's process killer on low-RAM devices.

This script clones the upstream repo fresh, applies idempotent patches for all of the above, installs dependencies with a multi-tier fallback strategy (including Termux User Repository / TUR precompiled PyPI wheels), supports companion search/crawl servers, and runs live self-tests to confirm the servers actually work.

## Search & Crawl Suite Tools (v2.0.0)

In addition to MCPSearch's multi-engine web search (DuckDuckGo, Google, Bing) and social scraping (Reddit, Twitter, YouTube), v2.0.0 introduces companion search and extraction tools:

| Server / Tool | Capability | Termux Footprint | Activation Flag |
| :--- | :--- | :--- | :--- |
| **MCPSearch** | Multi-engine web search & social trends | Python / FastMCP | *Default* |
| **grep-mcp** | Global code search across 500k+ GitHub repos (grep.app, AST & regex) | Pure Python / Async (lightweight) | `--with-grep` / `--bundle` |
| **trafilatura** | Clean HTML-to-text / Markdown article extractor (headless crawler) | Pure Python / C-lib (fast) | `--with-crawler` / `--bundle` |

## What it does (high level)

1. **Phase 0 — Storage pre-flight:** warns early if free space on `$HOME` is low, before native builds start.
2. **Phase 1 — Termux environment:** updates `pkg`, non-interactively installs native toolchain packages (`rust`, `clang`, `libxml2`, `libxslt`, `binutils`, etc.) in optimized batches, and upgrades `pip`.
3. **Phase 2 — Clone, patch, install:**
   - Performs a fast, shallow clone (`--depth 1 --single-branch`) of the MCPSearch repo.
   - Strips Playwright (HTTP-only crawling mode — headless browsers aren't practical on Android).
   - Adds the missing `anysqlite` dependency to `pyproject.toml`.
   - Regex-patches `mcp_server/server.py`: fixes bare factory-object calls, broken `get_research_agent_instance` references, empty `lines.append()` calls, and rebuilds the `investigate`/`compare`/`trending` tool bodies to match the actual data shapes.
   - Regex-patches `utils/http_client.py` to remove the deprecated `refresh_ttl_on_access` kwarg.
   - Installs Python dependencies using TUR prebuilt wheels and a package-aware multi-tier fallback strategy with hardened Rust/PyO3 flags and soft-fallback for `selectolax` to `BeautifulSoup4+lxml`.
   - Optionally installs `grep-mcp` and `trafilatura` if selected.
   - Editable-installs the MCPSearch package.
4. **Phase 3 — Launchers & unified client config:** writes `run.sh` and `run_grep.sh` (with automatic `termux-wake-lock` integration) and a unified MCP client config JSON snippet (`mcp_client_snippet.json`) with concrete paths to drop into Claude Desktop, Cursor, Roo Code, Cline, or LibreChat.
5. **Phase 4 — Self-tests:**
   - Imports the server module, enumerates registered tools, and calls `get_crawl_stats()` live.
   - Verifies companion servers (`grep-mcp` and `trafilatura`) if installed.
   - **Phase 4b:** constructs a real cached HTTP client, makes two requests, and asserts the second one is served from cache (`hishel_from_cache=True`) with zero deprecation warnings (enforced via `warnings-as-errors`).
6. **Phase 5 — Cleanup:** purges the pip cache, removes scratch files, and clears the cargo registry cache to reclaim build space.

All patches are idempotent — safe to re-run the script against an existing install without duplicating changes.

## Usage

### Quickest: one-line curl bootstrap

The curl bootstrap (`bootstrap.sh`) downloads the installer safely into a temporary file, verifies its integrity, and runs it with whichever flags you specify:

```bash
curl -fsSL https://raw.githubusercontent.com/tailscale-signin/mcpsearch-installer-android-termux/main/bootstrap.sh | bash
```

To install the complete search & crawl bundle (MCPSearch + grep code search + web extractor):

```bash
curl -fsSL https://raw.githubusercontent.com/tailscale-signin/mcpsearch-installer-android-termux/main/bootstrap.sh | bash -s -- --bundle
```

Pass other flags through directly:

```bash
curl -fsSL https://raw.githubusercontent.com/tailscale-signin/mcpsearch-installer-android-termux/main/bootstrap.sh | bash -s -- --dry-run
curl -fsSL https://raw.githubusercontent.com/tailscale-signin/mcpsearch-installer-android-termux/main/bootstrap.sh | bash -s -- --check
```

### Recommended: install via git clone

Cloning with `git` is the most reliable way to get the full script — it avoids any connection drops:

```bash
# 1. Make sure git is installed
pkg update -y && pkg install -y git

# 2. Clone the installer repo
cd ~
git clone https://github.com/tailscale-signin/mcpsearch-installer-android-termux.git
cd mcpsearch-installer-android-termux

# 3. Run the installer (standard or bundled suite)
bash install_mcpsearch.sh --bundle
```

### Installer CLI options

Run `bash install_mcpsearch.sh --help` for the complete list:

| Option | Description |
|---|---|
| `--help`, `-h` | Display help screen and exit |
| `--version`, `-V` | Show installer version and exit |
| `--bundle`, `--all` | Install MCPSearch + `grep-mcp` + `trafilatura` and build unified config |
| `--with-grep` | Install `grep-mcp` for global GitHub code search (grep.app) |
| `--with-crawler` | Install `trafilatura` for clean HTML-to-text/markdown web crawling |
| `--dry-run`, `-n` | Print detected environment and execution plan without making changes (zero-side-effect) |
| `--check` | Run Phase 4 self-tests only against existing installation without modifying anything |
| `--no-rust` | Skip installing the Rust toolchain; fail fast if any Rust wheel is missing |
| `--no-tur` | Do not use TUR (Termux User Repository) prebuilt PyPI index |
| `--no-wake-lock` | Do not add termux-wake-lock handling to `run.sh` launcher |
| `--no-color` | Disable ANSI colored terminal output |
| `--app-dir PATH` | Custom target directory for MCPSearch clone (default: `~/MCPSearch`) |
| `--config-dir PATH` | Custom directory for launchers and config snippet (default: `~/.mcpsearch`) |
| `--log-dir PATH` | Custom directory for phase logs (default: `~/.mcpsearch_logs`) |
| `--cache-test-url URL` | Custom URL for the Phase 4b HTTP cache smoke test (default: `https://httpbin.org/get`) |

### Environment variables

- `MCPSEARCH_WITH_GREP` — Set to `1` to enable `grep-mcp` code search.
- `MCPSEARCH_WITH_CRAWLER` — Set to `1` to enable `trafilatura` crawler.
- `MCPSEARCH_USE_TUR` — Set to `0` to disable the Termux User Repository PyPI wheel index (default `1`).
- `MCPSEARCH_WAKE_LOCK` — Set to `0` to disable wake lock acquisition in `run.sh` (default `1`).
- `MCPSEARCH_RUST_OPT` — Rust optimization level for source builds (default `1` for low memory; set to `3` for a faster but heavier release build).
- `CARGO_BUILD_JOBS` — Rust build parallelism (default `1` to avoid Android's process killer).

After a successful run, you'll have:

- `~/MCPSearch` — patched source tree
- `~/.mcpsearch/run.sh` — MCPSearch launcher script (with absolute interpreter, app paths, and wake-lock management)
- `~/.mcpsearch/run_grep.sh` — grep-mcp launcher script (if enabled)
- `~/.mcpsearch/mcp_client_snippet.json` — unified multi-server config snippet ready to merge into your MCP client
- `~/.mcpsearch_logs/` — full logs for every phase, useful for debugging if something fails

Merge the contents of `mcp_client_snippet.json` into your MCP client's config (e.g. `claude_desktop_config.json`), then restart the client.

## Requirements

- Termux (F-Droid build recommended over the deprecated Play Store version)
- ~2–4 GB free storage (native builds for `pydantic-core`, `lxml`, `selectolax`, etc. can be heavy when prebuilt wheels aren't matched)
- Internet access for `pkg`/`pip`/`git`

## Logs & troubleshooting

Every phase writes to `~/.mcpsearch_logs/`. If the script exits with `fatal`, check the referenced log file first — most failures are native-dependency build issues that resolve after `pkg upgrade` or a Termux storage permission fix (`termux-setup-storage`).

If a Rust build dies with a "signal 9" (or just vanishes), that's Android's process killer — the installer caps Rust parallelism and optimization to avoid it. On Android 14+ you can also disable child process restrictions in Settings → Developer Options.

## Repository structure

```
.
├── bootstrap.sh           # Safe curl-to-bash bootstrap entry point (run via curl | bash)
├── install_mcpsearch.sh   # The core installer — clone, patch, install, self-test (v2.0.0)
├── patches/                # Standalone reference copies of the patch logic embedded in the installer
│   ├── patch_server.py     # Reference copy of the mcp_server/server.py patch step
│   └── README.md            # Explains what patches/ is for and how it relates to the installer
├── CHANGELOG.md            # Version history of the installer script
├── LICENSE                 # MIT license
└── README.md                # You are here
```

See [`patches/README.md`](patches/README.md) for details on why those reference copies exist and how to use them for manual troubleshooting.

## License

MIT — see [LICENSE](LICENSE).
