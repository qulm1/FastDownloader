# 窗口版预览

双击 `StartDownloadWindow.cmd`；便携包也可直接运行 `bin/FastDownloader.exe`。必须完整保留目录，不能只发送 EXE。源码仓库首次启动使用系统 PowerShell 5.1 / .NET Framework 编译小型启动器，无需安装 Node.js、Python 或额外 GUI 框架。

界面参考用户提供的 FluxDown 截图，采用浅色侧栏、蓝色操作按钮、任务列表和居中新建下载浮层；保留自己的品牌及已实现的能力。

## 日常操作

1. 点击“新建下载”（Ctrl+N），每行粘贴一个链接；也可选择或拖入种子、Metalink 或批量清单。
2. 选择保存根目录、HTTP 连接上限；重命名只支持单个文件链接，批量重命名用 CSV/JSON 的 FileName。
3. 点击“开始下载”（Ctrl+Enter）。队列按顺序执行一个任务，每个任务仍可使用最多 16 个 HTTP 连接。
4. 选中任务后点击“暂停”（Ctrl+P）或“继续”（Ctrl+R）。“停止”保存断点，不删除文件。当前任务暂停时后续队列等待；停止当前任务则继续后续队列。
5. 关闭窗口会先保存断点再退出；重新启动显示已有任务，选中待恢复任务点继续。重启不会未经选择自动下载。双击任务打开目录，Ctrl+F 搜索文件名或保存路径。

左侧支持状态、文件类型筛选，任务行显示进度、速度、已下载大小和预计剩余时间。文件分类按任务文件名后缀判断，不分析内容；未知或无后缀归入“其他”。显示最近 500 个本地任务，更早的记录保留在原目录，可通过原命令行管理。

## 运行与恢复

窗口和命令行共用任务记录及互斥锁，同一任务不能在两个窗口同时运行。签名链接或 Cookie 过期时需取得有效链接；不会绕过认证。

窗口仅在 aria2 任务进程存活时启用回环地址 RPC，使用每次随机生成的令牌，不对局域网开放，不保存令牌，不安装服务。原命令行不启用 RPC。正常关闭会保存 session 和 .aria2 文件；强制结束或断电可能丢失最后一小段进度，请保留任务目录及 .aria2 文件。

启动器面向 Windows 自带 PowerShell 5.1 / .NET Framework，`pwsh` 不是窗口运行时。执行策略只在启动器进程内设置，不持久修改系统策略；公司组策略优先，不会尝试修改或绕过。

## 开发与分发

- WindowLauncher.cs：原生窗口启动器；用 powershell.exe 执行 BuildWindow.ps1，在新副本生成 bin/FastDownloader.exe。
- DownloadWindow.ps1：任务选择、校验、互斥、状态与引擎生命周期。
- WindowLayout.ps1 / DownloadDialog.ps1 / DesktopStyles.cs：布局、渐进展开的下载表单、筛选、浮层及自绘控件。
- WindowEngine.cs：异步引擎控制，网络等待不阻塞界面。

生成的启动器不提交 Git，发行打包从源码重新编译。测试结果及桌面验收范围见 TEST_REPORT.md。窗口为本分支预览功能，尚未发布 GitHub 正式 Release。

自动验收无需占用桌面：tests/TestWindowLayout.ps1 对实际控件进行离屏渲染、像素和布局检查；tests/TestWindowEngine.mjs 使用本机 HTTP 实测引擎及不显示窗口的窗口后端暂停、续传和 SHA-256。EXE 支持开发检查参数 `--check --check-report D:\新目录\runtime.txt`，加载实际随包模块后退出；此模式不显示窗口，失败写报告并返回非零状态。测试使用独立 state，不影响已有任务。
