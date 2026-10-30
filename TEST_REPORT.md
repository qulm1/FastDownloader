# 2.0 测试说明

2026-10-24，Windows x64、Windows PowerShell 5.1、aria2 1.37.0；Node.js 23.9.0 执行集成测试。测试输入均为自建字节样本，不携带公司文件。

- TestDownload.mjs：真实 HTTP 跳转、含 & 链接、16 MiB 文件、进程中断后 R 菜单恢复，最终 SHA-256 一致；种子/非法输入回归。
- TestScenarios.mjs：六类批量清单实际下载、中文空格路径、二进制内容、无长度/空文件/无 Range/307、任务列表、完成任务复用、错误哈希、404 后继续任务、整批参数校验；自建私有 Tracker、自己生成的 torrent 和独立 aria2 种子端实际传输，magnet 元数据及文件完整 SHA-256 校验。
- TestProtocols.mjs：本机被动 FTP 完整传输；Metalink 3 与 4、多文件及内置哈希；不可信本机 HTTPS 证书必须失败；Microsoft 官方 HTTPS 文件和 Python 官网图片通过系统证书验证并与独立 curl 下载 SHA-256 一致。不更改证书信任，不关闭证书验证。Microsoft 地址曾在一次回归中超时，记录为网络失败，随后以同样验证方式完成 Python 官网的源码和便携包实测；不承诺任意站点始终可达。
- TestLauncher.mjs：从实际 StartDownload.cmd 交互入口输入本机链接、退出，保存到默认 D 盘并验证完整 SHA-256；在没有 aria2 的临时副本中验证依赖缺失提示。
- TestFaults.mjs：无后缀地址与 UTF-8 Content-Disposition、重定向循环、403、无响应、中断后远端同大小内容变更、旧校验拒绝、新任务正确恢复、同任务并发锁、输出目录冲突。内容变化时若没有来源校验值，不能保证旧任务无损续传；本测试提供 SHA-256。
- TestEngineFault.ps1：通过独立子进程注入磁盘不足退出码 9，验证保存为 Incomplete 并返回原始失败码；不实际填满磁盘，不修改真实引擎。该项属于故障注入，不冒充真实磁盘耗尽。

BT 与 FTP 是可控本机网络测试，不能证明所有公网节点、认证服务器或代理可用；磁力需要实际做种。公开 HTTPS 为真实公网验证。没有测试绕过登录或 DRM，不支持 BT v2-only、网盘页面解析和迅雷/电驴协议。

运行测试前设置 TEST_WORK_ROOT 指向 D 盘缓存。协议测试先以 PowerShell 7 执行 tests/NewTestCertificate.ps1 -OutputDir D:\测试缓存\tls，再设置 TEST_CERT_ROOT。测试会创建自己的服务并在结束时关闭；不会安装下载结果。所有原始记录只在本机证据目录，发行包不含任务状态、下载内容、令牌或测试私钥。

最终便携包在 D 盘“中文 空格”新目录解压验收，不依赖开发源码路径。源码与发行包内主脚本/批量模块/引擎字节一致；发行采用白名单排除了私有 state、缓存、Cookie 与下载结果。日常运行不需要 Node.js。源码包不带第三方引擎，按 THIRD_PARTY.md 获取。

测试脚本默认在系统临时目录创建临时工作区（可用 TEST_WORK_ROOT 覆盖）；协议测试中需要公网对比的那一段可用 SKIP_PUBLIC_HTTPS=1 跳过，其余 FTP、Metalink 与不可信证书断言仍在本机完成。

## 2026-10-30：接续 WPF 图形界面

在 D:\FastDownloader 继续已有 WPF 草稿，保留 2.1.0 的 CLI 参数与呈现层。原 TestDownload、TestFaults、TestFeatures、TestLauncher、TestScenarios、TestProtocols（公网 HTTPS 明确跳过）、TestEngineFault 七个套件在本机全部通过。GitHub 新增的 WPF 检查以实际 CI 结果为准，本地结果不当作远端通过。

- TestGui.mjs / TestWpf.ps1：加载实际 WPF 控件并触发自身按钮事件，全程不显示窗口、不移动鼠标或发送桌面按键。完成本机 HTTP、暂停后字节稳定、继续后进度增长、停止保存断点、顺序队列、重新恢复、未知长度和 404 失败测试，最终文件 SHA-256 与样本一致。
- 使用自建 Tracker、aria2 做种端和自己生成的私有 torrent，WPF 窗口后端实际完成 torrent 与 magnet 传输；确认下载的是全部样本内容，不能仅凭元数据下载完成就标为成功。
- XAML 和控件绑定、显式下载目录不被 CLI 导入覆盖、预分配文件不制造 100% 进度、任务筛选和三种布局尺寸均有自动检查。离屏 PNG 使用虚构任务并补画实际窗口背景，不是桌面截图或网速证据。
- TestGuiPackage.ps1：在独立副本向 state、bin、tests 和 docs 放入私有标记，检查它们均未进入 ZIP；核对 GUI 必需模块、许可、源码包无二进制、便携包源码/引擎哈希，并从中文空格路径的实际 ZIP 解压目录加载 WPF 与系统 .NET 控制模块。

这些测试不冒充实际显示器/DPI、鼠标焦点、系统文件选择器和拖拽手感的实机验收。默认遵守不占用用户桌面的要求。普通用户可双击 StartDownloadGui.cmd 手动验收。
