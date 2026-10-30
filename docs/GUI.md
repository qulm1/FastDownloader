# WPF 图形界面

在 `D:\FastDownloader`（或完整发行目录）双击 **StartDownloadGui.cmd**。这是实际的 WPF 图形窗口，原命令行入口 StartDownload.cmd 保留。需要 Windows 自带的 Windows PowerShell 5.1、WPF/.NET Framework 及随包 aria2，不需要 Node.js、Python、PowerShell 7 或另装 GUI 框架。

## 操作

1. 每行输入一个链接，也可导入/拖入多个种子、Metalink 或 TXT/CSV/JSON/URL 清单。
2. 编辑保存目录，或点“保存位置”。Enter / “开始下载”提交全部输入，Shift+Enter 换行；整批参数先预检。
3. 任务按顺序下载。卡片显示实际已收到字节、速度、剩余时间，支持暂停、继续、停止和打开文件夹。暂停当前任务会让后面的队列等待；停止会保留断点并执行下一项。
4. 已完成链接不自动重下；需要独立副本时勾选“另建任务”。恢复旧任务沿用原目录和参数。
5. 关闭窗口时先保存并关闭自己的引擎，不会删除文件。重新打开后点“继续”恢复未完成任务；不会自动启动历史下载。

未知大小、旧任务没有精确遥测或正在取磁力元数据时，界面明确显示未知/待恢复，不根据文件逻辑长度假造百分比。文件预分配、最后一个分段提前写入会让文件长度看起来已满，因此不解析 `.aria2` 的假定固定偏移，也不把“磁盘上有这么长的文件”当成下载完成。只有引擎确认成功才显示 100%；有 SHA-256/Metalink/BT 校验时继续由 aria2 执行。

## 结构与边界

- FastDownloadGui.ps1：薄启动入口；正常启动和 LibraryOnly 测试模式明确区分。
- GuiApp.ps1 / GuiView.ps1：WPF 事件、卡片、布局与启动流程。
- GuiTasks.ps1：队列、锁、记录、暂停/恢复、保存退出。
- GuiEngine.cs：异步引擎控制，仅用系统 .NET 编译到进程内存，没有额外 EXE 或包管理依赖。
- FastDownload.ps1：共享输入校验、记录生成、参数生成及默认保存目录；保留 2.1 的限速、代理、认证、请求头等命令行参数。

CLI 仍关闭 RPC。GUI 为当前 aria2 子进程启用临时回环地址接口，每次随机生成认证令牌，仅监听本机，不开放局域网、不安装服务、令牌不写入 state 或日志。原任务的下载链接、HTTP 认证/自定义请求头等仍可能存在私有 state 中，不能把这个目录放进开源仓库或分享给别人。

GUI 用实时引擎遥测更新内存模型，每两秒保存检查点；不会每 500 毫秒递归扫描整个下载树。首次加载最多 500 项旧记录。其他 CLI 窗口启动的下载不提供这里的实时进度；同任务锁仍阻止重复下载。

## 自动化验收（不占用桌面）

```powershell
$env:TEST_WORK_ROOT='D:\临时验证'
New-Item -ItemType Directory -Force $env:TEST_WORK_ROOT | Out-Null
node tests/TestGui.mjs
powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File tests/TestGui.ps1 -WorkRoot D:\Wpf离屏
powershell.exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File tests/TestGuiPackage.ps1 -WorkRoot D:\Wpf便携包新目录
```

测试覆盖实际 WPF 控件事件、本机 HTTP、暂停/继续/停止/恢复、顺序队列、未知长度、错误响应和最终 SHA-256。离屏 PNG 来自实际 WPF 视图，使用虚构任务，不是桌面截图或真实网速证据。它不能替代真实显示器/DPI、鼠标/键盘焦点、系统文件选择器或拖拽手感的实机检查；当前默认不操作用户桌面。
