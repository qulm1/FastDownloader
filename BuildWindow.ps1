[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -eq 'Core') { throw '请用 Windows 自带 powershell.exe 运行 BuildWindow.ps1（不是 pwsh）。' }
$output = Join-Path $PSScriptRoot 'bin\FastDownloader.exe'
if (Test-Path -LiteralPath $output) { throw 'bin\FastDownloader.exe 已存在；构建到新的源代码副本，避免覆盖正在使用的程序。' }
Add-Type -Path (Join-Path $PSScriptRoot 'WindowLauncher.cs') -OutputAssembly $output -OutputType WindowsApplication -ReferencedAssemblies @(
    'System.dll','System.Core.dll','System.Windows.Forms.dll',([Management.Automation.PowerShell].Assembly.Location))
Get-FileHash -LiteralPath $output -Algorithm SHA256
