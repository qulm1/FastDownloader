<#
.SYNOPSIS
    极速下载助手 WPF 图形窗口；双击 StartDownloadGui.cmd 启动。
.PARAMETER LibraryOnly
    只加载函数，不显示窗口，用于自动化测试。
#>
[CmdletBinding()]
param([string]$DownloadDir,[string]$StateDir,[switch]$LibraryOnly)
. (Join-Path $PSScriptRoot 'GuiApp.ps1')
