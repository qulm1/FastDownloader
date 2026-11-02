# 第三方组件

`bin/aria2c.exe` 为 aria2 1.37.0 Windows x64，项目与对应源码见 https://github.com/aria2/aria2/tree/release-1.37.0 ，官方发行包见 https://github.com/aria2/aria2/releases/tag/release-1.37.0 。它采用 GNU GPL v2 或更新版本；完整许可保留在 `bin/COPYING`。随上游发行包附带的 AUTHORS、ChangeLog、README、LICENSE.OpenSSL 同时保留，不将第三方二进制声明为 MIT。

本包装脚本的 MIT 许可见 LICENSE。源码包不携带第三方二进制；从上述上游发行包取得 Windows x64 版本，将 aria2c.exe 和许可资料放入 bin 即可。便携包同时包含二进制和原版许可资料。再次分发 aria2 时应遵循其 GPL 对许可和对应源码提供的要求；此处保留项目来源，不代表以脚本许可替代 GPL。

日常使用只依赖 Windows PowerShell 5.1 和 aria2。测试需要 Node.js，生成仅用于拒绝不可信证书测试的本机证书另需 PowerShell 7。未捆绑 Node.js、PowerShell、测试证书或任何用户任务记录。
