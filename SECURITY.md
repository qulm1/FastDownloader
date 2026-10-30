# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 2.0.x | ✅ |
| < 2.0 | ❌ |

Only the latest release receives fixes. The tool is a local Windows script that
ships no server component and opens no listening port, so most findings are about
how user input reaches aria2, the filesystem, or the persisted task records.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Use GitHub's private reporting: *Security* tab → *Report a vulnerability*
(`https://github.com/qulm1/FastDownloader/security/advisories/new`).

Include, as far as you can:

- affected version / commit,
- a minimal reproduction (the exact command line or pasted input),
- what an attacker gains (code execution, file write outside the task folder,
  credential disclosure, TLS bypass, …),
- whether the issue is in this repository or in the bundled aria2 binary.

You can expect an acknowledgement within about 7 days. Fixes are released as a new
patch version with credit in the advisory and `CHANGELOG.md`, unless you ask to stay
anonymous. Please give us a reasonable window before public disclosure.

## In scope

- Argument or command injection through `-Source`, `-FileName`, `-Referer`,
  `-Proxy`, `-CookieFile`, `-SelectFile`, a batch manifest entry, or a task record.
- Path traversal or overwriting files outside the task's output directory — via
  `FileName`, manifest paths, torrent file names, or `state\` handling.
- TLS certificate validation being bypassed, or trust being silently modified.
- Disclosure of secrets (signed URLs, Cookie contents, proxy credentials) in console
  output, `task.json`, or the task list.
- Privilege escalation, persistence, or firewall/registry modification caused by
  running the script.

## Out of scope

- Vulnerabilities in **aria2** itself — report those to
  [aria2/aria2](https://github.com/aria2/aria2). We pin 1.37.0 and will follow
  upstream advisories with a version bump.
- Behaviour that is inherent to the feature and documented: torrent peers learning
  your IP and infohash, a signed URL being stored in `task.json`, or a downloaded
  file being malicious *content*. A matching SHA-256 proves integrity, not safety.
- Requests for features that bypass DRM, paywalls, captchas, logins, or anti-bot
  systems. Those are design non-goals, not vulnerabilities.
- Missing hardening that requires an attacker who already has write access to the
  user's profile, `state\`, or the tool directory.
- Reports produced only by a scanner without a demonstrable impact path.

## Security-relevant design constraints

- Certificate validation is always on (`--check-certificate=true`); this Schannel-based
  build cannot pin a custom CA and deliberately does not try.
- No RPC listener (`--enable-rpc=false`), no service, no scheduled task.
- Cookie files are read only from a path you pass explicitly; browsers are never read.
- HTTP basic-auth credentials (`-HttpUser` / `-HttpPassword`) and custom `-Header` values
  are recorded in `state\jobs\<id>\task.json` so a resume can reuse them. They are stored
  in clear text, exactly like the signed URLs and Cookie file paths 2.0 already kept:
  treat `state\` as private, and prefer a short-lived token over a long-lived password.
- `-UseSystemProxy` only reads `HKCU\...\Internet Settings`; the wrapper never writes to
  the registry and never changes the system proxy.
- Downloads are never opened, extracted, or executed automatically.

## Handling of your report data

Reproductions may involve a URL or token from your own account. Redact it before
sending, or note that the value is a throwaway; we do not need a live credential to
confirm a parsing or injection bug.
