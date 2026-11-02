# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html) for release tags.

## [Unreleased]

### Added

- WPF desktop UI: StartDownloadGui.cmd, multi-input import, task cards, destination,
  status filters, pause/resume/stop, sequential queue and graceful shutdown.
- Shared default-directory helper; the 2.1 CLI and its network options are retained.
- Real engine telemetry via per-process authenticated loopback RPC (GUI only),
  headless WPF event/transfer tests, offscreen previews and portable package checks.

### Fixed

- GUI startup no longer inherits the CLI's LibraryOnly flag and exits immediately.
- Preallocated files and missing telemetry never manufacture completed percentages.
- Release allowlists name files explicitly, including GUI modules, and exclude
  private files placed inside bin/tests/docs as well as the root state directory.

## [2.1.0] - 2026-10-30

### Added

- `-Help` and a comment-based help block, so `.\FastDownload.ps1 -Help` prints a short
  usage page and `Get-Help .\FastDownload.ps1 -Full` documents every parameter offline.
- Completion card after a download: file name, size, elapsed time, average speed,
  checksum result, and destination on five aligned lines.
- `-ShowHash` to compute and print the SHA-256 when the source provides no checksum;
  files up to 512 MiB are hashed automatically.
- Task list is now an aligned table (status, size, type, name, update time) that also
  accepts 2.0 records and still never prints full URLs.
- `-MaxSpeed` (download cap) and `-MaxUpload` (BT upload cap, `0` disables it).
- `-UseSystemProxy` reads the Windows Internet Settings proxy for one task; it never
  writes to the registry.
- `-UserAgent`, `-Header` (repeatable `'Name: Value'`), `-HttpUser` and `-HttpPassword`
  for per-request control. Invalid headers and an orphan password are rejected before
  any network work; `-DryRun` never echoes the password.
- `-NoColor` and `NO_COLOR` support; colour is also disabled when output is redirected.
- `tests/TestFeatures.mjs` covers the help page, the new flags, redaction, the task
  table and the completion card.
- `docs/UI.md` records the interface rules (one accent colour, whitespace over borders,
  two-character labels, colour never the only signal).

### Changed

- Interactive banner is now two lines plus a one-line command hint, printed once per
  session; the prompt is a caret instead of a `下载地址:` label.
- `H` in interactive mode prints the help page.
- Progress lines written by the wrapper are muted; aria2's own progress output is
  untouched.
- Task records gain `MaxSpeed`, `MaxUpload`, `UserAgent`, `Header`, `HttpUser`,
  `HttpPassword`, `TotalBytes`, `ElapsedSeconds` and `FinishedAt`; records are always
  read as UTF-8 so hand-edited or BOM-less records keep their Chinese labels.

### Fixed

- Task records written without a UTF-8 BOM were read with the ANSI code page, which
  mangled Chinese file labels in the task list.

## [2.0.1] - 2026-10-30

### Added

- GitHub Actions CI: PowerShell 5.1 parse check, integration suites on
  `windows-latest`, and a separate protocol job with a generated test certificate.
- GitHub Actions release workflow: pushing a `v*` tag builds the portable and source
  packages, writes `SHA256SUMS.txt`, and attaches them to a GitHub Release.
- English `README.md` with a maintained Chinese translation in `README.zh-CN.md`.
- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, and `docs/ARCHITECTURE.md`.
- Issue forms (bug report, feature request) and a pull request template.
- `.gitattributes` / `.editorconfig` so PowerShell files keep their CRLF endings and
  UTF-8 BOM while scripts, workflows, and docs use LF.
- `SKIP_PUBLIC_HTTPS=1` to skip the public-network leg of `tests/TestProtocols.mjs`
  on machines without internet access.

### Changed

- `BuildRelease.ps1` accepts `-Version` (default `2.0.0`) and writes to `dist\` by
  default instead of a hardcoded `D:` path; it also prints both SHA-256 sums.
- Default download root falls back to `%USERPROFILE%\Downloads\FastDownloads` when the
  machine has no `D:` drive.
- Release packaging whitelist now includes the new documentation files.

## [2.0.0] - 2026-10-29

### Added

- Batch input from TXT/URLS/LST, CSV (`Source,FileName,Sha256`), JSON, and Windows
  `.url` shortcuts, with validation of every entry before the first download.
- Task records under `state\jobs\<id>\` with `-ListTasks`, `-Resume`, and the
  interactive `L` / `R` menu; completed tasks are reused instead of silently redone.
- One output sub-directory per task, so equal file names from different URLs no
  longer overwrite each other; `-NewTask` forces a separate task.
- Metalink v3/v4 support, FTP transfers, torrent file selection (`-SelectFile`),
  `-FailFast`, `-DryRun`, `-StopAfterSeconds`, `-LibraryOnly`.
- Hash verification via `-Sha256`, Metalink embedded checksums, and BT piece hashes.

### Changed

- Download engine pinned to aria2 1.37.0 Windows x64 with upstream license files in
  `bin/`; no RPC listener and no persistent service.
- Per-task lock file prevents two windows from writing the same task.
- Release packaging is whitelist-based and excludes task state, cookies, proxies,
  downloads, and private keys.

### Fixed

- A failed or interrupted transfer can no longer be recorded as `Completed`; a
  checksum mismatch keeps the task `Incomplete`.
- Untrusted TLS certificates are rejected without changing Windows trust settings.
