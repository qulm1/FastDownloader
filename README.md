# 极速下载助手 2.0

## 日常使用

**窗口版预览：** 双击 `StartDownloadWindow.cmd`，使用侧栏分类、搜索、任务进度和暂停/继续界面；完整操作、依赖与恢复说明见 [WINDOW_GUIDE.md](WINDOW_GUIDE.md)。原命令行入口保留。

完整下载或克隆本仓库，保留 `bin` 目录，双击本目录 `StartDownload.cmd`。仓库本身不含桌面快捷方式；此前本机已创建的“极速下载助手”快捷方式也可以使用。
粘贴一个地址并按回车即可开始，不用手动给带 `&` 的网址加引号。

支持：HTTP/HTTPS/FTP 文件链接、GitHub Release 文件直链、magnet 磁力链接、本地 `.torrent` / `.meta4` / `.metalink` 文件。
HTTP 下载到种子文件后，aria2 会继续下载种子中的内容。种子默认下载全部文件。
纯 BT v2 磁力（只有 `btmh`、没有 `btih`）不支持；请用支持 BT v2 的客户端。

默认保存到 `D:\Downloads\FastDownloads`，每个任务单独一个子目录，防止不同链接的同名文件互相覆盖。
同一链接再次输入会续传；已完成任务会询问是否重新下载。
按一次 Ctrl+C 后稍等保存退出；重新启动输入 `R`，选择未完成任务恢复。强制关闭窗口可能丢失最后几秒进度。
请不要删除未完成文件旁的 `.aria2` 文件，或本工具的 `state` 文件夹。

## 速度与能力边界

- 默认单文件最多 8 个连接、4 MiB 最小分段；可改到 16，但连接越多不一定越快，也可能被限流。
- 支持服务器决定能否分段/续传；不支持续传时不会强行覆盖原文件重下。
- 服务器总限速、宽带上限、链路拥堵、BT 无做种无法靠脚本突破。
- 请输入“文件下载链接”，不是网盘分享页、需要验证码的页面、视频网页或登录页面。
- 不会绕过登录、付费、DRM、验证码、反爬，也不解析迅雷/电驴链接。
- 普通 HTTP 文件只有提供 `-Sha256` 或来源提供 Metalink 校验时，才能校验整体内容；BT 由种子分片哈希校验。不能把“下载完成”当作“文件绝对安全”。
- BT 下载期间会和其他节点交换数据，其他节点/Tracker 可能获知 IP 和资源哈希；默认限制上传总速度为 1 MiB/s，完成后停止做种。私有 PT 常有客户端白名单、分享率要求，本脚本不适合作为 PT 客户端。
- 命令行不启用 RPC；窗口版使用临时、本机回环地址的随机令牌认证接口，详见窗口说明。不安装常驻服务，不改浏览器默认关联、全局代理、防火墙或注册表。
- 首次 BT 使用如出现 Windows 防火墙询问，请你自行判断；脚本不会替你放行。网络封锁或无法连接节点也可能导致 BT 无速度。
- 任务记录和 aria2 续传文件可能保存原始下载链接（含临时签名/令牌）、代理地址、Cookie 文件路径。它们只保存在本机 `state` / 下载目录中，请不要分享整个 state 文件夹。不会自动读取浏览器 Cookie。

## 命令行进阶

在本目录打开 PowerShell，示例网址需要替换成你有权限的真实文件地址：

```powershell
# 16 连接；指定保存根目录
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -Connections 16 -DownloadDir 'D:\Downloads'

# 指定文件名与来源提供的 SHA-256（必须完整 64 位十六进制）
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -FileName 'file.zip' -Sha256 '<64位SHA256>'

# 手动提供来源页或你自行导出的 Cookie 文件；不要把 Cookie 发给别人
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -Referer 'https://example.com/' -CookieFile 'C:\private\cookies.txt'

# 仅对本次任务指定 HTTP 代理，不修改系统代理；不要把 BT 代理当作匿名保证
.\FastDownload.ps1 -Source 'https://example.com/file.zip' -Proxy 'http://127.0.0.1:7890'

# 多文件种子只选第 1、3、4、5 个文件；索引可用 bin\aria2c.exe -S file.torrent 查看
.\FastDownload.ps1 -Source 'D:\Downloads\file.torrent' -SelectFile '1,3-5'

# 同一 latest 链接已经完成，但远端内容更新后另建任务
.\FastDownload.ps1 -Source 'https://example.com/latest.zip' -NewTask

# 仅验证输入与参数，不下载；或选择未完成任务恢复
.\FastDownload.ps1 -Source 'magnet:?xt=urn:btih:<有效infohash>' -DryRun
.\FastDownload.ps1 -Resume
```

高级参数只用于新任务；恢复已有任务会沿用原来的目录、文件名、校验值、Cookie 路径等设置，避免错误拼接不同文件。
签名链接到期、Cookie 失效、远端内容更换后，需要重新获取有效链接；不能保证对旧任务无损续传。

## 文件组成

- `FastDownload.ps1`：PowerShell 主脚本（UTF-8 BOM，兼容 Windows PowerShell 5.1）。
- `StartDownload.cmd`：双击启动入口；ExecutionPolicy Bypass 仅作用于此 PowerShell 进程，不持久修改执行策略。受公司组策略限制时不会尝试绕过。
- `bin`：aria2 1.37.0 原版 Windows x64 程序及其上游许可文件。
- `state\jobs`：本机任务记录、断点信息；不自动上传。

## 参考资料

- 官方项目：https://github.com/aria2/aria2
- 官方使用手册：https://aria2.github.io/manual/en/html/aria2c.html
- GitHub 配置思路：https://github.com/P3TERX/aria2.conf （仅参考分段/续传思路，没有照搬 RPC 公网监听或第三方脚本）
- Reddit 使用讨论：https://www.reddit.com/r/linuxquestions/comments/1dwpbwp/
- Linux.do 下载工具讨论：https://linux.do/t/topic/2934915 （用户经验，不把帖中的速度和全协议宣传视为保证，也未下载安装帖中软件）

本包装脚本可自行修改；aria2 及捆绑库的许可见 `bin\COPYING`、`bin\LICENSE.OpenSSL` 等。

## 本机验证

`tests\TestDownload.mjs` 为开发者测试（需要 Node.js），使用临时的本机 HTTP 服务验证跳转、含 `&` 的网址、下载、SHA-256、主动中断、R 菜单续传、磁力参数、中文种子路径与种子离线解析。
新增集成测试使用自己生成的种子、自建 Tracker 和独立 aria2 种子端，实测 torrent/magnet 元数据和完整内容传输；不代表任意公网磁力都有活跃做种节点。日常下载不依赖 Node.js，只需要 Windows 自带的 PowerShell 和本目录 bin 程序。


## 2.0 批量输入与管理

在交互窗口粘贴或拖入 TXT、URLS、LST、CSV、JSON 或 Windows URL 快捷方式文件的完整路径，即可执行整批任务；命令行也支持 `-BatchFile 'D:\列表\batch.json'`。TXT/URLS/LST 每行一个链接或本地种子/Metalink 路径，忽略空行和 # 注释；相对本地文件路径相对清单所在目录。

CSV 表头为 Source,FileName,Sha256；JSON 为对象数组，或 {"downloads":[...]}。每项只有 Source 必填，可指定 FileName、Sha256；示例见 examples。Windows .url 文件读取唯一的 URL= 项。只接受有效文件名，不允许目录穿越、保留设备名或尾随空格/点。整批最多 1000 项、输入文件最大 8 MiB，全部预检通过才开始下载；默认某项失败继续后续项，最终返回失败码，使用 -FailFast 可在第一项错误后结束。

交互输入 L 查看任务、R 恢复未完成任务；命令行 -ListTasks。任务列表不显示完整带令牌的网址。下载输出每个任务独立目录，同名不同地址不互相覆盖；同地址沿用原有任务参数，需更换目标或校验值时使用 -NewTask。仅记录失败不会变成完成，SHA-256 不一致不能标记成功。

支持的文件类型不限后缀：安装包、ZIP、PDF、图片、音视频均按原始二进制传输。更多后缀不意味着新增网络协议；2.0 新增的是批量输入和任务管理。HTTP/HTTPS/FTP、BT v1、Metalink 保留现有能力。HTTPS 使用 Windows 系统证书信任，不支持在此 Schannel 构建中指定单独 CA 文件，也不关闭证书验证。具体可复现验收见 TEST_REPORT.md。

## 构建和开源整理

执行 `./BuildRelease.ps1`，默认在 D:\softwere\Releases 产生 2.0 便携包和源码包。发行采用白名单，不打包本机 state、Cookie、代理配置、下载结果、测试缓存或证书私钥。便携包解压后双击 StartDownload.cmd，无需 Node.js 或开发源码位置；源码包需要按 THIRD_PARTY.md 取得 aria2。包装脚本许可为 MIT，第三方 aria2 的 GPL 和依赖许可独立保留。

开发测试：设置 TEST_WORK_ROOT 到 D 盘后，分别运行 node tests/TestDownload.mjs、node tests/TestScenarios.mjs；协议测试按 TEST_REPORT.md 生成本机拒绝测试证书后执行 node tests/TestProtocols.mjs。不要提交真实任务状态和个人/公司数据。

## GitHub 维护

问题反馈、开发验证和发行检查见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题见 [SECURITY.md](SECURITY.md)。目前提供统一的本地检查入口，GitHub Actions 工作流尚待单独接入；不能将本地通过视为 GitHub CI 已通过。公网 HTTPS 默认明确跳过，可用 -PublicHttps 单独选择执行。

本地完整检查入口：`pwsh -NoProfile -File tests/RunChecks.ps1 -WorkRoot D:\FastDownloaderTests\new-run`。测试不使用仓库内已有任务状态，不会上传证书、下载结果或原始任务目录，也不会自动发布版本。
