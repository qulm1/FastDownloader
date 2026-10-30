# Interface design notes

The interface is a console, so the usual tools — space, type, colour, motion — are
limited to text, whitespace, and a handful of colours. The design goal is borrowed
from Apple's product language: **nothing between the user and the task**, one clear
hierarchy, and a result that can be read at a glance.

## Principles

1. **One idea per line.** The banner says what this is and where files go. Nothing else.
2. **One accent colour.** Cyan marks the primary thing (the product name, "完成").
   Everything secondary is dark grey; values stay in the default foreground.
   Colour never carries meaning on its own — every value has a label next to it.
3. **Whitespace instead of rules.** No box borders, no ASCII art, no separators made
   of `=`, `-` or `*`. Blank lines group, indentation aligns.
4. **Two-character labels.** `文件`, `大小`, `校验`, `位置` — all the same visual width,
   so values line up without a table.
5. **Say the result, not the process.** The aria2 engine prints its own progress; the
   wrapper only speaks when something is ready to be read — a result, a decision, or
   an error.
6. **One prompt, one caret.** `> ` instead of `下载地址:`. The hint line above the
   prompt teaches the four commands once, then never again.
7. **Predictable shapes.** Every state prints the same way: heading, then labelled
   values. Errors are one sentence plus a hint, never a stack trace.
8. **Degrade cleanly.** `NO_COLOR=1`, `-NoColor`, or redirected output turns colour
   off without changing wording or layout. Wide characters (CJK) are measured as two
   columns, so the table stays aligned in any locale.

## Surfaces

**Banner** — printed once per interactive session, not on every task:

```text
FastDownloader 2.1.0  ·  aria2 1.37.0
保存到 D:\Downloads\FastDownloads

粘贴链接或清单路径   R 续传   L 任务   H 帮助   Q 退出

>
```

**Completion card** — the only place a successful download is celebrated, and it is
quiet about it:

```text
  完成
  文件  payload.bin
  大小  5.0 MB · 不到 1 秒 · 25.0 MB/s
  校验  SHA-256 通过 · 16b632f11cf950dd…
  位置  D:\Downloads\FastDownloads\127.0.0.1-d213feaae89b91b8a68e
```

Size, duration and speed share one line because they answer a single question:
*was this normal?* The checksum is on its own line because it is the only line that
proves integrity.

**Incomplete note** — same shape, no scolding, and always actionable:

```text
  未完成 · 退出码 16
  大小  1.2 GB
  位置  D:\Downloads\FastDownloads\example.com-1f3c9a7b
  进度已保存，重新运行后按 R 续传。
  401/403/验证码/过期链接需要重新获取有效链接，增加连接数不能解决。
```

**Task table** — column order follows the questions a user actually asks: *is it
done, how big, what kind, which one, when*:

```text
状态      大小        类型  名称                        更新
已完成    1.2 MB      URL   示例 文件                   10-30 15:02
未完成    2.0 MB      BT    老任务                      10-29 09:11
```

**Help page** — `-Help` for the short version, `Get-Help .\FastDownload.ps1 -Full`
for everything. Both come from one source: the comment block at the top of the script.

## What we deliberately avoid

- Spinners, progress bars of our own, or "请稍候" placeholders — aria2 already reports
  progress, and a second progress display would fight it.
- Emoji and decorative symbols. The console font may not have them, and they do not
  survive `chcp` changes.
- Colour-only status (red/green dots). The word is always there.
- Bilingual noise inside one screen: the interface is Chinese, the code identifiers and
  developer documents are English, and they do not mix in one output block.
- Walls of text on start-up. The old banner printed five lines of policy on every run;
  the current one prints two lines once, and the policy lives in the README.

## Changing the interface

Anything that prints belongs in the presentation layer at the top of
`FastDownload.ps1` (`Write-Muted`, `Write-Accent`, `Write-Field`, `Format-Cell`,
`Format-ByteSize`, `Format-Duration`). Keep download logic out of it, and keep the
principles above: if a change needs a new colour, a border, or a second sentence of
explanation, it probably needs a rethink instead.
