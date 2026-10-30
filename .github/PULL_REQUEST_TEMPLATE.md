# Summary

<!-- What changes, and why. One or two sentences is enough for a small fix. -->

Fixes #

## Type of change

- [ ] Bug fix (behaviour change that corrects a defect)
- [ ] New feature (new capability, documented in README and CHANGELOG)
- [ ] Refactor (no behaviour change)
- [ ] Documentation or packaging only

## How it was verified

<!-- Paste the command(s) and the relevant output. "Tests pass" alone is not a verification. -->

```text

```

## Checklist

- [ ] Works on **Windows PowerShell 5.1** (not just PowerShell 7), and every `*.ps1`
      still parses cleanly there.
- [ ] Edited `*.ps1` files kept their UTF-8 BOM if they contain non-ASCII text.
- [ ] No new runtime dependency, module, installer, or committed binary.
- [ ] `state/`, downloads, cookies, proxies, certificates, and personal paths are not
      part of this diff.
- [ ] User-facing changes are reflected in `README.md`, `README.zh-CN.md`, and
      `CHANGELOG.md` (`## [Unreleased]`).
- [ ] New or changed behaviour has a test, or the PR explains why one is impractical.
- [ ] Inputs that reach aria2 or the filesystem are validated the same way as the
      existing paths (no command-string interpolation, no unvalidated file names).
