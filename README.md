# FastDownloader · 极速下载助手

[![CI](https://github.com/qulm1/FastDownloader/actions/workflows/ci.yml/badge.svg)](https://github.com/qulm1/FastDownloader/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey.svg)](#requirements)
[![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE.svg)](#requirements)

*[中文说明](README.zh-CN.md)*

A small, auditable Windows download front-end for [aria2](https://github.com/aria2/aria2):
paste a link, press Enter, get a verified file. No service, telemetry or browser
integration. The CLI keeps RPC disabled; the optional WPF UI uses authenticated,
temporary loopback-only engine control. See [the desktop guide](docs/GUI.md).

```text
极速下载助手 | aria2 1.37.0
粘贴网址、磁力链接，或拖入种子、TXT/CSV/JSON/URL 任务清单。
下载地址: https://example.com/file.zip
保存位置：D:\Downloads\FastDownloads\example.com-1f3c9a7b2e4d5c6f
下载完成：D:\Downloads\FastDownloads\example.com-1f3c9a7b2e4d5c6f
```

## Why this exists

Most download helpers are either GUI applications you cannot audit or one-off
`aria2c` command lines you keep retyping. FastDownloader sits in between:

- **Auditable modules.** The CLI and WPF UI use small, readable source modules; all
  network I/O is delegated to the unmodified aria2 1.37.0 binary in `bin/`.
- **No persistence.** Nothing is installed: no Windows service, scheduled task,
  public RPC listener, registry edit, firewall rule, or default-browser change.
- **Predictable state.** Every task is a folder under `state\jobs\<id>\` holding a
  `task.json` record, the aria2 session file, and a lock. Delete it and the tool
  forgets the task.
- **Verification first.** `-Sha256`, Metalink hashes, and BT piece hashes are
  enforced; a checksum mismatch never becomes `Completed`.

## Requirements

| | |
|---|---|
| OS | Windows 10 / 11 (x64) |
| Runtime | Windows PowerShell 5.1 — already part of Windows |
| Engine | `bin\aria2c.exe` (bundled in the portable package) |
| Node.js | Only for the development test suite, never for daily use |

## Quick start

1. Download `FastDownloader-<version>.zip` from [Releases](https://github.com/qulm1/FastDownloader/releases).
2. Extract it anywhere — spaces and non-ASCII characters in the path are fine.
3. Double-click `StartDownload.cmd`.
4. Paste a download URL and press Enter.

For an actual graphical window, double-click **StartDownloadGui.cmd**. It supports
task cards, multi-input import, destination selection, progress, pause/resume and
recovery. Windows PowerShell 5.1 / WPF are built in; no Node.js is needed for daily
use. The full directory is required. [Desktop usage and tests](docs/GUI.md).

The default destination is `D:\Downloads\FastDownloads\<label>-<task-id>`, one
sub-directory per task so that different links with the same file name never
overwrite each other. On machines without a `D:` drive the default falls back to
`%USERPROFILE%\Downloads\FastDownloads`; pass `-DownloadDir` to choose your own.

## What you can paste

| Input | Notes |
|---|---|
| `http://`, `https://`, `ftp://` links | Direct file links only — not share pages, players, or login walls |
| `magnet:?xt=urn:btih:…` | BT v1 info-hash (hex or base32). BT v2-only magnets are not supported |
| Local `.torrent` | Any file name; UTF-8 paths are fine |
| Local `.meta4` / `.metalink` | Metalink v3 and v4, including embedded checksums |
| Batch manifest | `.txt`, `.urls`, `.lst`, `.csv`, `.json`, or a Windows `.url` shortcut |

In the interactive prompt, `L` lists known tasks, `R` resumes an unfinished one,
`Q` quits. Press `Ctrl+C` once and wait: the current position is saved before exit.

## Command line

```powershell
# 16 connections into a custom root directory
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -Connections 16 -DownloadDir 'D:\Downloads'

# File name plus an expected SHA-256 (exactly 64 hex characters)
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -FileName 'file.zip' -Sha256 '<sha256>'

# Referer or a Cookie file you exported yourself
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -Referer 'https://example.com/' -CookieFile 'C:\private\cookies.txt'

# Per-task HTTP proxy — it does not change the system proxy
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -Proxy 'http://127.0.0.1:7890'

# Only files 1, 3, 4 and 5 of a multi-file torrent (indices: bin\aria2c.exe -S file.torrent)
.\FastDownload.ps1 -Source 'D:\Downloads\file.torrent' -SelectFile '1,3-5'

# Same "latest" URL, but the remote content changed — start a new task
.\FastDownload.ps1 -Source 'https://example.com/latest.zip' -NewTask

# Cap the download rate at 5 MB/s, reuse the Windows proxy, send extra headers
.\FastDownload.ps1 -Source 'https://example.com/big.iso' -MaxSpeed 5M -UseSystemProxy -Header 'Accept-Language: zh-CN'

# HTTP basic auth (stored in the task record — treat state\ as private)
.\FastDownload.ps1 -Source 'https://example.com/private.zip' -HttpUser alice -HttpPassword '<password>'

# Print the computed SHA-256 when the source provides no checksum
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -ShowHash

# Validate input and arguments without downloading, list tasks, resume
.\FastDownload.ps1 -Source 'magnet:?xt=urn:btih:<info-hash>' -DryRun
.\FastDownload.ps1 -ListTasks
.\FastDownload.ps1 -Resume
```

| Parameter | Default | Purpose |
|---|---|---|
| `-Source` | — | URL, magnet link, or local `.torrent` / `.meta4` / `.metalink` |
| `-DownloadDir` | see above | Root directory for task sub-directories |
| `-StateDir` | `<tool>\state` | Where `jobs\` records live |
| `-Connections` | `8` (1–16) | aria2 `--split` / `--max-connection-per-server` |
| `-FileName` | engine decides | URL tasks only; must be a bare file name |
| `-Sha256` | — | Expected SHA-256 of the finished file |
| `-MaxSpeed` | unlimited | Download cap, e.g. `5M`, `800K` |
| `-MaxUpload` | `1M` | BT upload cap; `0` disables the cap |
| `-Referer`, `-CookieFile`, `-Proxy` | — | Per-task request context; never stored globally |
| `-UseSystemProxy` | off | Read the Windows (Internet Settings) proxy for this task only |
| `-UserAgent` | `FastDownloader/<version> aria2/1.37.0` | Override the User-Agent |
| `-Header` | — | Extra request header, `'Name: Value'`; repeatable |
| `-HttpUser`, `-HttpPassword` | — | HTTP basic auth; recorded in `task.json` |
| `-SelectFile` | all files | Torrent file indices, e.g. `1,3-5` |
| `-BatchFile` | — | Manifest path; see below |
| `-FailFast` | off | Stop the batch at the first failure |
| `-NewTask` | off | Force a separate task even if the URL completed before |
| `-Resume` | off | Pick an unfinished task interactively |
| `-ListTasks` | off | Print known tasks and exit |
| `-DryRun` | off | Validate only; prints a redacted JSON summary |
| `-ShowHash` | off | Compute and print the SHA-256 after a download |
| `-NoColor` | off | Disable colour (also honours `NO_COLOR`) |
| `-Help` | off | Print the short usage page |
| `-StopAfterSeconds` | `0` | Pass `--stop=<n>` to aria2 (used by tests) |
| `-LibraryOnly` | off | Dot-source the script without running it |

Advanced parameters apply to new tasks only. Resuming reuses the recorded
directory, file name, checksum, and Cookie path, so different files are never
mixed in one task.

Full parameter documentation is available offline:

```powershell
.\FastDownload.ps1 -Help
Get-Help .\FastDownload.ps1 -Full
```

## Interface

The console UI follows a small set of rules — one accent colour, whitespace instead
of borders, two-character labels, colour never the only signal — described in
[docs/UI.md](docs/UI.md). A finished task looks like this:

```text
  完成
  文件  payload.bin
  大小  5.0 MB · 不到 1 秒 · 25.0 MB/s
  校验  SHA-256 通过 · 16b632f11cf950dd…
  位置  D:\Downloads\FastDownloads\127.0.0.1-d213feaae89b91b8a68e
```

`-ListTasks` prints an aligned table (status, size, type, name, update time) and
never shows full URLs, because a task record can contain signed tokens:

```text
状态      大小        类型  名称                        更新
已完成    1.2 MB      URL   示例 文件                   10-30 15:02
未完成    2.0 MB      BT    老任务                      10-29 09:11
```

## Batch manifests

A TXT/URLS/LST manifest holds one link or local seed/metalink path per line;
blank lines and `#` comments are ignored, and relative paths resolve against the
manifest's own directory. CSV uses the header `Source,FileName,Sha256`; JSON is
an array of objects or `{"downloads":[…]}`. Only `Source` is required. See
`examples/`.

A batch is limited to 1000 entries and 8 MiB of manifest text, and every entry is
validated before the first byte is downloaded. File names are checked against
Windows reserved device names, trailing dots/spaces, and directory traversal.
By default a failing entry does not abort the batch, but the process exits
non-zero; add `-FailFast` to stop immediately.

## Task state

```text
state\jobs\<task-id>\
├─ task.json           # source, type, dirs, parameters, status, timestamps
├─ unfinished.session  # aria2 session file for the in-flight download
├─ task.lock           # single-writer guard for this task
└─ dht.dat             # per-task DHT routing table for BT
```

`Completed` is written only when aria2 exits `0`, no session file remains, and a
requested SHA-256 matched. Everything else is `Incomplete` and can be resumed
with `R`. Do not delete `.aria2` control files or `state\` while a download is
running — that is what makes resumption possible.

## Security and privacy notes

- **No telemetry.** The tool makes no network request of its own.
- **Secrets stay local.** `task.json` may record signed URLs (temporary tokens),
  proxy addresses, and Cookie file paths. Share `state\` with nobody.
- **No browser integration.** Cookies are read only from a file you pass in.
- **No bypassing.** Login walls, paywalls, DRM, captchas, and anti-bot systems are
  out of scope; there is no code that attempts them.
- **BT is public by nature.** While a torrent runs you exchange data with peers
  and trackers that see your IP and the infohash. Uploads are capped at 1 MiB/s
  and seeding stops when the download finishes.
- **HTTPS** uses the Windows certificate store (Schannel). Certificate validation
  is never disabled, and this build cannot pin a custom CA file.

A matching SHA-256 means the bytes are the bytes you asked for — not that the
content is safe to run. Files are never opened or installed automatically.

## Out of scope

BT v2-only magnets (`btmh` without `btih`), cloud-drive share pages, video
websites, Thunder/eD2K links, private-tracker client whitelisting, and any form
of access-control circumvention. Download speed is bounded by the server,
your link, and peer availability; raising `-Connections` cannot beat a rate limit.

## Build a release

```powershell
# Portable zip (script + engine) and source zip (script only), plus SHA-256 sums
./BuildRelease.ps1 -Version 2.0.0 -OutputDir .\dist
```

The packaging is whitelist-based: `state\`, cookies, proxies, download results,
test caches, and private keys are never included. The portable package runs
without Node.js or the developer checkout; the source package expects you to
obtain aria2 yourself, as described in [THIRD_PARTY.md](THIRD_PARTY.md).

Tagging `v*` runs `.github/workflows/release.yml`, which builds both packages and
attaches them (with checksums) to a GitHub Release.

## Tests

The suite drives the real script against local fixtures (HTTP, FTP, Metalink,
trackers, a local TLS server) with Node.js 20+:

```powershell
$env:TEST_WORK_ROOT = 'D:\tmp\fastdownloader-tests'   # optional scratch space
node tests/TestDownload.mjs
node tests/TestScenarios.mjs
node tests/TestFaults.mjs
node tests/TestLauncher.mjs
```

`tests/TestProtocols.mjs` additionally needs a throwaway TLS certificate
(`tests/NewTestCertificate.ps1`, PowerShell 7) and, unless `SKIP_PUBLIC_HTTPS=1`
is set, one public HTTPS comparison against `curl.exe`. Details and the recorded
evidence for 2.0 are in [TEST_REPORT.md](TEST_REPORT.md) (Chinese).

## Project layout

```text
FastDownload.ps1        Main entry point: input parsing, task records, aria2 invocation
BatchDownload.ps1       Manifest readers, batch runner, task listing
StartDownload.cmd       Double-click launcher (ExecutionPolicy Bypass for this process only)
BuildRelease.ps1        Whitelist packager for portable and source zips
bin/                    aria2 1.37.0 Windows x64 and its upstream license files
tests/                  Node.js integration and fault-injection tests
examples/               Sample CSV and JSON manifests
docs/ARCHITECTURE.md    How a paste becomes a verified file
docs/UI.md              Interface rules (one accent, whitespace, aligned labels)
```

## Contributing

Bug reports, reproductions, and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). Participation is covered by the
[Code of Conduct](CODE_OF_CONDUCT.md). Security issues: [SECURITY.md](SECURITY.md).
Release history: [CHANGELOG.md](CHANGELOG.md).

## License

The wrapper scripts are [MIT licensed](LICENSE). The bundled aria2 binary is
GPL-2.0-or-later and keeps its own license; see [THIRD_PARTY.md](THIRD_PARTY.md).

Not affiliated with the aria2 project. Download only what you have the right to
access.
