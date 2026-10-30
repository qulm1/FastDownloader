# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html) for release tags.

## [Unreleased]

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
