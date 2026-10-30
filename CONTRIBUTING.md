# 参与维护

目前目标是 Windows x64、Windows PowerShell 5.1 和 aria2 1.37.0。Node.js 24 及 PowerShell 7 只用于开发测试，不是日常下载依赖。

## 问题反馈

先搜索已有 Issues。反馈时说明工具版本、系统、复现步骤和预期/实际结果。优先使用自建本机服务或无认证的小文件复现；删除日志中的签名参数、Cookie、代理密码和账号信息，不提交整个 `state` 目录。安全问题见 [SECURITY.md](SECURITY.md)。

## 修改和测试

窗口源码和原生启动器构建方法见 WINDOW_GUIDE.md。BuildWindow.ps1 必须使用 powershell.exe；生成的 bin/FastDownloader.exe 不提交 Git，发行时重新编译。引擎暂停、续传测试不能代替原生界面按钮、浮层和重启流程的桌面验收。

1. 从 `main` 新建分支；每个 PR 解决一个清晰的问题，保持 Windows PowerShell 5.1 兼容。
2. 增加能复现原问题的测试，使用独立临时目录和可控本机服务，不修改使用者已有任务、系统证书或下载结果。
3. 在有 D 盘的 Windows 环境执行：

```powershell
pwsh -NoProfile -File tests/RunChecks.ps1 -WorkRoot D:\FastDownloaderTests\my-run
# 可选公网 HTTPS 联调；公网不可达应如实报告，不能算作本机测试失败的替代证明。
pwsh -NoProfile -File tests/RunChecks.ps1 -WorkRoot D:\FastDownloaderTests\online-run -PublicHttps
```

每个目录必须是新的、位于源码目录之外的测试目录。测试含真实本机 HTTP、FTP、BT/磁力和 Metalink 传输、TLS 拒绝、恢复/错误分支、启动与发行包检查；磁盘不足使用故障注入。`checks-summary.json` 记录每项结果；公网 HTTPS 默认明确跳过。启动测试在临时发行副本中保存状态，不使用仓库内真实 `state`。

后续 GitHub Actions 可运行同一入口。目前工作流尚未接入，不能把本地检查结果当作远程 CI 结果。建议接入时不使用仓库密钥、不上传原始任务、证书或下载缓存，只保留测试摘要，不自动发布 Release、合并 PR 或推送代码；Actions 固定到完整提交 SHA。已提供的 Dependabot 配置用于后续 GitHub Actions 依赖更新。

## 发行维护

`BuildRelease.ps1` 在 D 盘指定目录构建源码包和便携包，分别核对内容及 SHA-256；新依赖或新测试文件需明确加入白名单。保留 aria2 及捆绑库的许可和来源，勿将第三方二进制改称为本项目 MIT。需要正式发版时，先在干净目录验证便携包，再人工确定版本、更新记录和发布内容。
