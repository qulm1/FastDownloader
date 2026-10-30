# Architecture

FastDownloader is deliberately small: one entry script, one helper script, one
pinned engine binary. This document explains how a pasted string becomes a
verified file, where the trust boundaries are, and which functions to touch for a
given kind of change.

## Components

| File | Responsibility |
|---|---|
| `FastDownload.ps1` | CLI parameter block, input classification, task records, aria2 argument construction, engine invocation, interactive loop |
| `BatchDownload.ps1` | Batch manifest readers (TXT/URLS/LST/CSV/JSON/.url), batch runner, task listing |
| `StartDownload.cmd` | Double-click entry point; `-ExecutionPolicy Bypass` applies to that one process and persists nothing |
| `bin/aria2c.exe` | aria2 1.37.0. All network I/O, segmentation, resume, BT, Metalink and checksum work happens here |
| `BuildRelease.ps1` | Whitelist packager producing the portable and source zips |

There is no daemon, no RPC listener, no database, and no module import. State is
file-based so it can be inspected, backed up, or deleted with a file manager.

## Lifecycle

```mermaid
flowchart TD
    A["-Source / pasted text / -BatchFile"] --> B{Batch manifest?}
    B -- yes --> C[Read-DownloadBatch<br/>limit 8 MiB, 1..1000 entries, field whitelist]
    C --> D[Get-SourceSpec per entry<br/>reject duplicate identities]
    D --> E[New-TaskRecord + Get-AriaArguments<br/>validate the whole batch before any network I/O]
    E --> F[[Invoke-Task per entry]]
    B -- no --> G[Get-SourceSpec<br/>URL / magnet / local seed]
    G --> H[Get-TaskKey = sha256(identity)[0..20]]
    H --> I{state/jobs/&lt;key&gt;/task.json exists?}
    I -- yes, same DownloadDir --> J[reuse record · prompt to re-download if Completed]
    I -- no --> K[New-TaskRecord<br/>OutputDir = DownloadDir/&lt;safeLabel&gt;-&lt;key&gt;]
    J --> F
    K --> F
    F --> L{--DryRun?}
    L -- yes --> M[print redacted JSON, no network]
    L -- no --> N[acquire task.lock exclusively]
    N --> O[Status = Downloading, Save-Record]
    O --> P["aria2c @options"]
    P --> Q{"exit 0 AND no session file left?"}
    Q -- yes --> R[Status = Completed · checksum already enforced by aria2]
    Q -- no --> S[Status = Incomplete · resumable with R / -Resume]
```

## Input classification

`Get-SourceSpec` is the only place that decides what a source *is*, and it also
produces the identity used for task de-duplication:

| Input | Detection | `Identity` |
|---|---|---|
| `http` / `https` / `ftp` URL | `[Uri]::TryCreate` with an absolute URI and an allowed scheme | the URL string |
| `magnet:` | regex for `xt=urn:btih:` with a 40-hex or 32-base32 info-hash | `btih:<lowercased hash>` |
| `.torrent` / `.meta4` / `.metalink` | an existing leaf path with one of those extensions | SHA-256 of the file's bytes |

Anything else throws before a task is created. Surrounding single or double quotes
are stripped (so a path from Explorer's "Copy as path" works), and control
characters — including newlines — are rejected so one paste cannot become two
sources.

The identity is hashed to a 20-character key: `sha256(identity)` in lowercase hex,
truncated. That keeps directory names short and hides long tokens from casual
browsing of `state\jobs\`. `-NewTask` appends an 8-character GUID so the same source
can own several tasks.

## Task records

```text
%ToolRoot%\state\jobs\<key>\
├─ task.json            # authoritative record, rewritten atomically
├─ unfinished.session   # aria2 session file; non-empty ⇒ work remains
├─ task.lock            # held for the duration of one Invoke-Task
└─ dht.dat             # per-task DHT table, avoids cross-task BT interference
```

`task.json` (written by `Save-Record` via a `.tmp` file plus `File.Replace`, so a
crash never leaves half a record):

```json
{
  "Id": "1f3c9a7b2e4d5c6f8a90",
  "Source": "https://example.com/file.zip",
  "Type": "URL",
  "Label": "example.com",
  "DownloadDir": "D:\\Downloads\\FastDownloads",
  "OutputDir": "D:\\Downloads\\FastDownloads\\example.com-1f3c9a7b2e4d5c6f8a90",
  "JobFolder": "<ToolRoot>\\state\\jobs\\1f3c9a7b2e4d5c6f8a90",
  "Status": "Downloading",
  "UpdatedAt": "2026-10-29T10:12:33",
  "Connections": 8,
  "FileName": null,
  "Sha256": null,
  "Referer": null,
  "CookieFile": null,
  "Proxy": null,
  "SelectFile": null,
  "MaxSpeed": null,
  "MaxUpload": "1M",
  "UserAgent": null,
  "Header": [],
  "HttpUser": null,
  "HttpPassword": null,
  "UseSystemProxy": false,
  "TotalBytes": 0,
  "ElapsedSeconds": 0,
  "FinishedAt": null
}
```

Status is a three-value machine: `Pending` → `Downloading` → `Completed` or
`Incomplete`. `Completed` requires both `aria2` exit code `0` *and* an empty or
missing session file; every other outcome stays `Incomplete` so it can be resumed.
A checksum mismatch surfaces as a non-zero aria2 exit code, which is why a bad hash
can never be recorded as a success.

The record is also the resume contract: `-Resume` and the interactive `R` command
reuse the stored `OutputDir`, `FileName`, `Sha256`, `Referer`, `CookieFile`,
`Proxy`, and `SelectFile`, so resuming never re-derives parameters from a URL that
may have changed meaning.

## aria2 invocation

`Get-AriaArguments` builds an `@options` array — never a command string — which is
splatted into `& $script:Engine @options`. User-controlled values therefore reach
the process as discrete argv elements, not as parsed script text.

| Group | Flags | Why |
|---|---|---|
| Isolation | `--no-conf=true`, `--no-netrc=true`, `--enable-rpc=false` | a user-level `aria2.conf` cannot change behaviour; nothing listens on a port |
| Resume | `--continue=true`, `--always-resume=true`, `--auto-file-renaming=false`, `--allow-overwrite=false`, `--save-session`, `--save-session-interval=5`, `--input-file=<session>` | resume the same bytes instead of silently starting a second file |
| Integrity | `--check-certificate=true`, `--check-integrity=true`, `--checksum=sha-256=…` | never trade validation for convenience |
| Performance | `--split`, `--max-connection-per-server`, `--min-split-size=4M`, `--disk-cache=32M`, `--max-concurrent-downloads=1`, `--max-overall-download-limit=<MaxSpeed>` | one task at a time, bounded connections, optional cap |
| BT | `--enable-dht=true`, `--enable-peer-exchange=true`, `--bt-enable-lpd=false`, `--bt-max-peers=80`, `--seed-time=0`, `--max-overall-upload-limit=<MaxUpload>`, `--dht-file-path=<job>\dht.dat` | finish-and-stop seeding, capped uploads, no local peer discovery |
| Request context | `--referer`, `--all-proxy`, `--user-agent`, `--header`, `--http-user`, `--http-passwd`, `--load-cookies` | per-task context, always validated before it reaches argv |
| Diagnostics | `--console-log-level=warn`, `--summary-interval=10`, `--download-result=full` | progress without flooding the console |

The wrapper adds no progress rendering of its own: aria2 owns the live progress output,
and the wrapper speaks only once the task settles (completion card or incomplete note).
That split is deliberate — two progress displays would fight over the same lines.

`-DryRun` prints only type, connection count, destination, and argument count — not
the source, cookies, or proxy credentials — so a bug report can be pasted safely.

## Batch pipeline

`Read-DownloadBatch` accepts `.txt`/`.urls`/`.lst` (one source per line, `#`
comments), `.csv` (`Source,FileName,Sha256`), `.json` (array or `{downloads:[…]}`),
and `.url` (exactly one `URL=` line). It enforces an 8 MiB manifest limit, 1–1000
entries, a `Source`-only field whitelist, and a 64-hex checksum format. Relative
local paths resolve against the manifest's directory; nothing from the manifest is
ever evaluated as code.

`Invoke-DownloadBatch` then creates records for the whole batch, rejects duplicates
by identity, and calls `Get-AriaArguments` for every entry *before* the first
download starts. A batch therefore fails fast on bad input rather than after
downloading 900 of 1000 files. Execution is sequential; a failing entry is counted
and the batch continues unless `-FailFast` is set. The final line is a summary, and
the process exits `1` if anything failed.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success — including a fully skipped batch (nothing left to do) |
| `1` | Argument, input, manifest, or engine-missing error |
| aria2's code | The engine's failure code, propagated by `Invoke-Task` |

## Trust boundaries

1. **User input → argv.** Handled by the `@options` splatting pattern plus explicit
   rejection of control characters and quotes.
2. **User input → filesystem.** `FileName` must be a bare name (no separators, no
   reserved device names, no trailing dot/space); `OutputDir` is always
   `<DownloadDir>\<sanitized label>-<key>`; manifests cannot escape their directory
   via relative paths into *other* users' locations because the target is the task's
   own output folder.
3. **`task.json` → process.** Records can contain URLs with tokens. They are read
   with `ConvertFrom-Json` (data, not code) and only known properties are consumed.
4. **Network → disk.** aria2 performs all transfers; HTTPS trust comes from the
   Windows certificate store, and validation cannot be disabled by this wrapper.

Secrets that legitimately appear in `state\` are documented in the README: treat the
directory as private.

## Tests

| Suite | What it proves |
|---|---|
| `TestDownload.mjs` | redirects, `&` in URLs, 16 MiB body, interrupt + `R` resume, hash equality, torrent/illegal-input regressions |
| `TestScenarios.mjs` | all manifest formats, Chinese/space paths, no-length and empty files, no-Range servers, task listing, completed-task reuse, wrong hash, 404 continuation, full batch pre-validation, self-hosted tracker + torrent + magnet transfers |
| `TestProtocols.mjs` | passive FTP, Metalink 3/4 with embedded hashes, untrusted TLS rejection, one public HTTPS comparison against `curl.exe` |
| `TestLauncher.mjs` | the real `StartDownload.cmd` path, default output location, missing-engine message and exit code |
| `TestFaults.mjs` | redirect loops, 403, unresponsive hosts, content changed after interruption, stale-checksum refusal, concurrent task lock, output collision |
| `TestEngineFault.ps1` | injected exit code 9 (disk-full) via a stand-in engine process: status stays `Incomplete` and the code propagates |

Every suite starts its own local servers and writes `test-evidence.json` into a
fresh temporary directory; see [TEST_REPORT.md](../TEST_REPORT.md) for the recorded
2.0 evidence.

## Where to change what

| Change | Touch |
|---|---|
| New CLI parameter | `param()` block → `New-TaskRecord` (store it) → `Get-AriaArguments` (validate + map to a flag) |
| New input type (e.g. a new manifest dialect) | `Test-BatchSource` + `Read-DownloadBatch`, plus a scenario test |
| New source scheme (e.g. SFTP) | `Get-SourceSpec` (classification + identity) and the aria2 flag mapping |
| Different engine behaviour | `Get-AriaArguments` only — keep it declarative and splatted |
| Packaging changes | `BuildRelease.ps1` whitelist, then `CHANGELOG.md` |
