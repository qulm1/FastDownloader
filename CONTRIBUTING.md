# Contributing to FastDownloader

Thanks for taking the time to help. This project values **small, reviewable, honest**
changes: a bug fix that comes with a failing test is worth more than a large refactor.

## Ways to contribute

- Report a bug with a minimal reproduction (see `.github/ISSUE_TEMPLATE/bug_report.yml`).
- Improve the documentation, especially the Chinese and English READMEs drifting apart.
- Add a test for behaviour that is currently unverified.
- Fix a bug or implement something from the issue tracker.

Please open an issue before starting a large change (new CLI surface, new protocol,
restructuring `FastDownload.ps1`), so we do not both build the same thing.

## Development setup

Requirements: Windows 10/11 x64, Windows PowerShell 5.1 (built in), Node.js 20+ for
the tests, Git.

```powershell
git clone https://github.com/qulm1/FastDownloader.git
cd FastDownloader
git checkout -b fix/your-topic

# The aria2 engine is committed under bin/, so a plain clone is runnable.
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -DryRun
```

There is no build step, no package manager, and no compile of our own code. Node.js
is used only to drive the integration tests.

## Running the tests

```powershell
$env:TEST_WORK_ROOT = 'D:\tmp\fastdownloader-tests'   # optional, defaults to %TEMP%

node tests/TestDownload.mjs    # redirects, & in URLs, 16 MiB file, interrupt + R resume
node tests/TestFaults.mjs      # loops, 403, hangs, size change, checksum, locking, collisions
node tests/TestFeatures.mjs    # help text, network flags, task table, completion summary
node tests/TestScenarios.mjs   # batch manifests, realistic paths, torrent + magnet transfers
node tests/TestLauncher.mjs    # actual StartDownload.cmd entry point, missing-engine error
```

`tests/TestProtocols.mjs` needs two extra things and is therefore not part of the
default loop:

```powershell
# A throwaway certificate for the "must reject an untrusted TLS server" case
pwsh -File tests/NewTestCertificate.ps1 -OutputDir D:\tmp\certs
$env:TEST_CERT_ROOT = 'D:\tmp\certs'

# The public-HTTPS comparison against curl.exe needs internet access.
# Skip it (e.g. behind a proxy or on CI) with:
$env:SKIP_PUBLIC_HTTPS = '1'

node tests/TestProtocols.mjs
```

Tests create their own local servers, trackers, torrents, and temporary directories;
they never touch a real download folder, and each run writes `test-evidence.json`
next to its scratch directory. Two warnings:

- Do **not** point `TEST_WORK_ROOT` at a directory that holds data you care about;
  the suites create and delete files inside it.
- `TestLauncher.mjs` exercises the real default destination (`D:\Downloads\FastDownloads`).
  It is skipped nowhere and will use that path, so a `D:` drive is expected.

## Code conventions

- **Stay on Windows PowerShell 5.1.** No `??`, no ternary operator, no `-Parallel`,
  no `Get-Content -AsByteStream`. The script must load under 5.1 *and* 7.x.
- **Interface text goes through the presentation helpers.** Use `Write-Muted`,
  `Write-Accent`, `Write-Field`, `Format-Cell`, `Format-ByteSize` and `Format-Duration`
  instead of ad-hoc `Write-Host` with colours, and read [docs/UI.md](docs/UI.md) before
  adding a new colour, border or symbol. Downloads must not depend on the UI layer.
- **Keep the entry point auditable.** Logic that is not about the interactive loop
  belongs in a function; keep `Start-Downloader` readable top to bottom.
- **Never restore the BOM question by accident.** `FastDownload.ps1` and
  `BatchDownload.ps1` are UTF-8 **with BOM** because they contain Chinese output
  strings and must be read correctly by 5.1. Edit them with an editor that preserves it.
- **No new runtime dependencies.** The deliverable is the script plus the pinned
  aria2 1.37.0 binary. Do not add modules, installers, or helper executables.
- **Quote everything you pass to aria2** using the existing `@options` array pattern.
  Never interpolate user input into a command string; that is an injection risk
  (see `Get-AriaArguments`).
- **Validate file names once** and reuse the checks in `Get-AriaArguments`
  (reserved device names, trailing dots/spaces, traversal).
- Keep user-facing strings in Chinese for the interactive UI, and use English for
  identifiers, comments where practical, and developer documentation.

## Commit and PR conventions

- Commits: `type(scope): summary` — `fix`, `feat`, `docs`, `test`, `ci`, `build`, `chore`.
  Example: `fix(state): keep lock while aria2 is still writing`.
- Keep a PR focused on one concern. Separate "refactor" commits from "behaviour change"
  commits when both are needed.
- Describe **what changed, why, and how you verified it**. Paste the relevant test
  output or a short transcript instead of "tests pass".
- Add a `CHANGELOG.md` entry under `## [Unreleased]` for user-visible changes.
- Do not commit `state/`, download results, cookies, proxy configs, certificates,
  or any personal/company data. Our `.gitignore` covers the usual suspects — check
  `git status` before pushing.
- Do not add binaries. `bin/aria2c.exe` is the single, intentionally committed
  third-party artifact; new engine versions go through their own PR with updated
  license files and `THIRD_PARTY.md`.

## Review checklist

Reviewers look for:

1. Does it work on Windows PowerShell 5.1, not just 7.x?
2. Is there a test that fails before the change and passes after it?
3. Does any new code path write outside the task directory, or accept an unvalidated
   file name, URL, or manifest path?
4. Are secrets kept out of output, logs, and `task.json`?
5. Are docs (`README.md`, `README.zh-CN.md`, `TEST_REPORT.md`) still accurate?

## Release process

1. Update `CHANGELOG.md` (move `Unreleased` entries into the new version) and the
   version number in the portable package name if it is referenced anywhere.
2. Commit, then tag: `git tag v2.0.1 && git push origin v2.0.1`.
3. `.github/workflows/release.yml` builds `FastDownloader-<version>.zip` and
   `FastDownloader-<version>-source.zip`, writes `SHA256SUMS.txt`, and attaches all
   three to the GitHub Release using auto-generated notes.
4. Verify the release assets, then announce the change in the release notes if the
   auto-generated list misses something important.

## License

Contributions are accepted under the MIT license used by the project
(inbound = outbound). Do not paste code you cannot license this way.

Questions about a change are welcome in the issue or draft PR — asking early is
cheaper than rewriting later.
