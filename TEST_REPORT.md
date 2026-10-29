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
