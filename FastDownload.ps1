<#
.SYNOPSIS
    Windows 上的 aria2 下载前端：粘贴链接即可下载，支持断点续传与校验。

.DESCRIPTION
    支持 HTTP/HTTPS/FTP 文件链接、magnet（BT v1）、本地 .torrent / .meta4 / .metalink
    文件，以及 TXT/URLS/LST/CSV/JSON/.url 批量清单。所有网络传输由随附的 aria2 1.37.0
    完成；本脚本只负责输入校验、任务记录和结果汇报。

    不常驻服务、不开 RPC 端口、不上报数据、不修改系统代理或证书信任。

.PARAMETER Source
    要下载的链接，或本地种子/Metalink 文件路径。省略则进入交互模式。

.PARAMETER BatchFile
    批量清单路径。清单格式见 docs/ARCHITECTURE.md。

.PARAMETER Connections
    单文件连接数，1-16，默认 8。连接数超过服务器能力时不会更快。

.PARAMETER Sha256
    期望的 64 位十六进制 SHA-256。不一致时任务不会标记为完成。

.PARAMETER MaxSpeed
    下载限速，例如 5M、800K。留空表示不限速（仍受 aria2 默认策略约束）。

.PARAMETER MaxUpload
    BT 上传限速，默认 1M。设为 0 表示不做上传限速。

.PARAMETER UseSystemProxy
    读取 Windows（Internet 选项）代理设置用于本次任务，只读不改。

.PARAMETER Header
    附加请求头，格式 'Name: Value'，可重复传入。

.PARAMETER HttpUser
    HTTP 基本认证用户名。与 -HttpPassword 一起记录在任务文件中，请勿分享 state 目录。

.PARAMETER HttpPassword
    HTTP 基本认证密码。

.PARAMETER ShowHash
    完成后计算并显示实际 SHA-256（大文件默认跳过以节省时间）。

.PARAMETER DryRun
    只校验输入与参数并输出脱敏摘要，不下载、不联网。

.EXAMPLE
    .\FastDownload.ps1 -Source 'https://example.com/file.zip' -Sha256 '<64位SHA256>'

.EXAMPLE
    .\FastDownload.ps1 -Source 'https://example.com/big.iso' -MaxSpeed 5M -Connections 16

.EXAMPLE
    .\FastDownload.ps1 -BatchFile 'D:\列表\batch.json' -FailFast

.EXAMPLE
    .\FastDownload.ps1 -Resume

.LINK
    https://github.com/qulm1/FastDownloader
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$BatchFile,
    [switch]$ListTasks,
    [switch]$FailFast,
    [string]$DownloadDir,
    [string]$StateDir,
    [ValidateRange(1, 16)][int]$Connections = 8,
    [string]$FileName,
    [ValidatePattern('^(|[a-fA-F0-9]{64})$')][string]$Sha256,
    [string]$Referer,
    [string]$CookieFile,
    [string]$Proxy,
    [switch]$UseSystemProxy,
    [ValidatePattern('^(|[0-9]+(\.[0-9]+)?[KMGkmg]?)$')][string]$MaxSpeed,
    [ValidatePattern('^(|[0-9]+(\.[0-9]+)?[KMGkmg]?)$')][string]$MaxUpload = '1M',
    [string]$UserAgent,
    [string[]]$Header,
    [string]$HttpUser,
    [string]$HttpPassword,
    [ValidatePattern('^(|[0-9,-]+)$')][string]$SelectFile,
    [switch]$Resume,
    [switch]$NewTask,
    [switch]$DryRun,
    [switch]$ShowHash,
    [switch]$NoColor,
    [switch]$Help,
    [ValidateRange(0, 86400)][int]$StopAfterSeconds = 0,
    [switch]$LibraryOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); $OutputEncoding = [Console]::OutputEncoding } catch { }
$script:ToolRoot = $PSScriptRoot
$script:Engine = Join-Path $PSScriptRoot 'bin\aria2c.exe'
if (-not $StateDir) { $StateDir = Join-Path $PSScriptRoot 'state' }
$script:JobsRoot = Join-Path ([IO.Path]::GetFullPath($StateDir)) 'jobs'
$script:Interactive = -not $PSBoundParameters.ContainsKey('Source') -and -not $Resume -and -not $BatchFile -and -not $ListTasks
. (Join-Path $PSScriptRoot 'BatchDownload.ps1')

$script:AppVersion = '2.1.0'
$script:BannerShown = $false
$script:UseColor = $true
if ($NoColor -or $env:NO_COLOR) { $script:UseColor = $false }
try { if ([Console]::IsOutputRedirected) { $script:UseColor = $false } } catch { }

# ---------------------------------------------------------------------------
# Presentation layer
#
# House style: one accent colour, muted labels, aligned values, no decoration
# that a console font cannot draw. Everything here prints to the host; nothing
# affects download behaviour.
# ---------------------------------------------------------------------------

function Write-Muted {
    param([string]$Text)
    if ($script:UseColor) { Write-Host $Text -ForegroundColor DarkGray } else { Write-Host $Text }
}

function Write-Accent {
    param([string]$Text)
    if ($script:UseColor) { Write-Host $Text -ForegroundColor Cyan } else { Write-Host $Text }
}

function Write-Field {
    param([string]$Label, [string]$Value)
    Write-Host ('  ' + $Label + '  ') -NoNewline
    Write-Host $Value
}

function Get-DisplayWidth {
    param([string]$Text)
    $width = 0
    foreach ($character in $Text.ToCharArray()) {
        $code = [int]$character
        $wide = ($code -ge 0x1100 -and $code -le 0x115F) -or
                ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
                ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
                ($code -ge 0xF900 -and $code -le 0xFAFF) -or
                ($code -ge 0xFE30 -and $code -le 0xFE6F) -or
                ($code -ge 0xFF00 -and $code -le 0xFF60) -or
                ($code -ge 0xFFE0 -and $code -le 0xFFE6)
        if ($wide) { $width += 2 } else { $width += 1 }
    }
    return $width
}

function Format-Cell {
    param([string]$Text, [int]$Width, [switch]$Right)
    $value = [string]$Text
    $padding = $Width - (Get-DisplayWidth $value)
    if ($padding -lt 0) {
        $trimmed = ''
        foreach ($character in $value.ToCharArray()) {
            if ((Get-DisplayWidth ($trimmed + $character)) -gt ($Width - 1)) { break }
            $trimmed += $character
        }
        $value = $trimmed
        $padding = $Width - (Get-DisplayWidth $value)
    }
    if ($Right) { return (' ' * $padding) + $value + '  ' }
    return $value + (' ' * $padding) + '  '
}

function Format-ByteSize {
    param([double]$Bytes)
    if ($Bytes -le 0) { return '0 B' }
    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $index = 0
    $value = $Bytes
    while ($value -ge 1024 -and $index -lt ($units.Count - 1)) { $value = $value / 1024; $index++ }
    if ($index -eq 0) { return ('{0:N0} B' -f $value) }
    return ('{0:N1} {1}' -f $value, $units[$index])
}

function Format-Duration {
    param([double]$Seconds)
    if ($Seconds -lt 1) { return '不到 1 秒' }
    if ($Seconds -lt 60) { return ('{0:N0} 秒' -f $Seconds) }
    if ($Seconds -lt 3600) { return ('{0:N0} 分 {1:N0} 秒' -f [Math]::Floor($Seconds / 60), ($Seconds % 60)) }
    return ('{0:N0} 时 {1:N0} 分' -f [Math]::Floor($Seconds / 3600), [Math]::Floor(($Seconds % 3600) / 60))
}

function Get-RecordField {
    param($Record, [string]$Name)
    if ($null -eq $Record) { return $null }
    if ($null -ne $Record.PSObject.Properties[$Name]) { return $Record.$Name }
    return $null
}

function Read-JsonFile {
    # Always decode as UTF-8: task records may be written by 2.1 (UTF-8 with BOM),
    # 2.0 (UTF-8 with BOM), or a hand-edited file without a BOM. Get-Content in
    # Windows PowerShell 5.1 would fall back to the ANSI code page and mangle labels.
    param([string]$Path)
    return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Show-AppHelp {
    Write-Host ''
    Write-Accent ('FastDownloader ' + $script:AppVersion + '  ·  aria2 1.37.0')
    Write-Host ''
    Write-Host '  用法'
    Write-Host '    .\FastDownload.ps1                         交互模式'
    Write-Host '    .\FastDownload.ps1 -Source <链接或文件>     单个任务'
    Write-Host '    .\FastDownload.ps1 -BatchFile <清单>        批量任务'
    Write-Host '    .\FastDownload.ps1 -Resume                 续传未完成任务'
    Write-Host '    .\FastDownload.ps1 -ListTasks              查看任务'
    Write-Host ''
    Write-Host '  常用参数'
    Write-Host '    -DownloadDir <目录>      保存根目录，默认 D:\Downloads\FastDownloads'
    Write-Host '    -Connections <1-16>      单文件连接数，默认 8'
    Write-Host '    -Sha256 <64 位十六进制>   下载后校验，不一致不算完成'
    Write-Host '    -MaxSpeed <速率>         下载限速，例如 5M、800K'
    Write-Host '    -MaxUpload <速率>        BT 上传限速，默认 1M'
    Write-Host '    -UseSystemProxy          沿用系统（IE）代理，只读不改'
    Write-Host '    -Header ''Name: Value''    附加请求头，可重复'
    Write-Host '    -HttpUser / -HttpPassword  HTTP 基本认证（会记录在任务文件中）'
    Write-Host '    -ShowHash                完成后计算并显示 SHA-256'
    Write-Host '    -NewTask                 同一链接另建任务'
    Write-Host '    -DryRun                  只校验参数，不下载'
    Write-Host '    -NoColor                 关闭颜色，便于重定向到文件'
    Write-Host ''
    Write-Muted '  完整参数说明：Get-Help .\FastDownload.ps1 -Full'
    Write-Host ''
}

function Get-SystemProxy {
    # Reads the per-user Internet Settings. Never writes to the registry.
    try {
        $settings = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if (-not $settings.ProxyEnable) { return $null }
        $server = [string]$settings.ProxyServer
        if (-not $server) { return $null }
        $value = $server
        if ($server -match '(?i)(?:^|;)\s*http=([^;]+)') { $value = $Matches[1] }
        elseif ($server.Contains('=')) { $value = ($server -split ';')[0].Split('=', 2)[1] }
        $value = $value.Trim()
        if ($value -notmatch '^[^\s:]+:\d{1,5}$') { return $null }
        return 'http://' + $value
    } catch { return $null }
}


function Get-LocalSha256 {
    param([string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose(); $stream.Dispose() }
}

function Get-SourceSpec {
    param([Parameter(Mandatory = $true)][string]$Text)
    $value = $Text.Trim()
    if ($value.Length -gt 1 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x1f\x7f]') { throw '输入为空，或含有换行/控制字符。请一次只粘贴一个链接。' }
    $uri = $null
    if ([Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http', 'https', 'ftp')) {
        if ($value.Contains('"')) { throw '网址包含未编码的双引号，请先将双引号编码为 %22。' }
        return [pscustomobject]@{ Source = $value; Type = 'URL'; Label = $uri.Host; Identity = $value }
    }
    if ($value -match '^magnet:\?') {
        $decoded = [Uri]::UnescapeDataString($value)
        $hashMatch = [regex]::Match($decoded, '(?i)(?:[?&])xt=urn:btih:([a-f0-9]{40}|[a-z2-7]{32})(?:&|$)')
        if (-not $hashMatch.Success) { throw '磁力链接必须包含有效的 BT v1 info-hash（btih）。纯 BT v2/btmh 请使用支持该格式的客户端。' }
        if ($value.Contains('"')) { throw '磁力链接包含未编码的双引号。' }
        $infoHash = $hashMatch.Groups[1].Value.ToLowerInvariant()
        return [pscustomobject]@{ Source = $value; Type = 'BT'; Label = 'magnet'; Identity = 'btih:' + $infoHash }
    }
    if (Test-Path -LiteralPath $value -PathType Leaf) {
        $item = Get-Item -LiteralPath $value
        if ($item.Extension.ToLowerInvariant() -notin @('.torrent', '.meta4', '.metalink')) { throw '本地文件仅支持 .torrent、.meta4 或 .metalink；TXT 任务列表不能直接当种子使用。' }
        $type = 'BT'
        if ($item.Extension -ne '.torrent') { $type = 'Metalink' }
        return [pscustomobject]@{ Source = $item.FullName; Type = $type; Label = $item.BaseName; Identity = (Get-LocalSha256 $item.FullName) }
    }
    throw '不支持这个输入。请粘贴 HTTP/HTTPS/FTP 文件下载链接、magnet:? 磁力链接，或本地 .torrent 文件完整路径。'
}

function Get-TaskKey {
    param([string]$Identity)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Identity))).Replace('-', '').ToLowerInvariant()).Substring(0, 20) }
    finally { $hasher.Dispose() }
}

function Save-Record {
    param($Record, [string]$Path)
    $temporary = $Path + '.tmp'
    $Record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    if ([IO.File]::Exists($Path)) {
        [IO.File]::Replace($temporary, $Path, [NullString]::Value)
    } else {
        [IO.File]::Move($temporary, $Path)
    }
}

function New-TaskRecord {
    param($Spec, [string]$Destination, [switch]$Separate)
    $key = Get-TaskKey $Spec.Identity
    if ($Separate) { $key += '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) }
    $jobFolder = Join-Path $script:JobsRoot $key
    $recordPath = Join-Path $jobFolder 'task.json'
    if ((Test-Path -LiteralPath $recordPath) -and -not $Separate) {
        $existing = Read-JsonFile $recordPath
        if ($existing.DownloadDir -ne $Destination) { throw '此任务已记录了另一个下载目录。要新建独立任务，请加 -NewTask。恢复任务请用 R 或 -Resume。' }
        return $existing
    }
    $safeLabel = [regex]::Replace($Spec.Label, '[^\p{L}\p{N}._-]', '_')
    if ($safeLabel.Length -gt 40) { $safeLabel = $safeLabel.Substring(0, 40) }
    $outputFolder = Join-Path $Destination ($safeLabel + '-' + $key)
    $headerList = @()
    if ($Header) { $headerList = @($Header) }
    return [pscustomobject]@{
        Id = $key; Source = $Spec.Source; Type = $Spec.Type; Label = $Spec.Label
        DownloadDir = $Destination; OutputDir = $outputFolder; JobFolder = $jobFolder
        Status = 'Pending'; UpdatedAt = [DateTime]::Now.ToString('s')
        Connections = $Connections; FileName = $FileName; Sha256 = $Sha256
        Referer = $Referer; CookieFile = $CookieFile; Proxy = $Proxy; SelectFile = $SelectFile
        MaxSpeed = $MaxSpeed; MaxUpload = $MaxUpload; UserAgent = $UserAgent
        Header = $headerList; HttpUser = $HttpUser; HttpPassword = $HttpPassword
        UseSystemProxy = [bool]$UseSystemProxy
        TotalBytes = 0; ElapsedSeconds = 0; FinishedAt = $null
    }
}

function Get-ResumeRecord {
    $records = @()
    if (Test-Path -LiteralPath $script:JobsRoot) {
        foreach ($file in Get-ChildItem -LiteralPath $script:JobsRoot -Filter task.json -Recurse -File) {
            try {
                $entry = Read-JsonFile $file.FullName
                if ($entry.Status -ne 'Completed') { $records += $entry }
            } catch { Write-Warning ('跳过无法读取的任务记录：' + $file.Directory.Name) }
        }
    }
    if ($records.Count -eq 0) { Write-Host '没有未完成任务。' -ForegroundColor Yellow; return $null }
    $records = @($records | Sort-Object UpdatedAt -Descending)
    for ($i = 0; $i -lt $records.Count; $i++) {
        Write-Host ('{0}. [{1}] {2}  {3}' -f ($i + 1), $records[$i].Type, $records[$i].Label, $records[$i].UpdatedAt)
    }
    $choice = Read-Host '输入要续传的任务序号（直接回车取消）'
    if ([string]::IsNullOrWhiteSpace($choice)) { return $null }
    $number = 0
    if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $records.Count) { throw '任务序号无效。' }
    return $records[$number - 1]
}

function Get-AriaArguments {
    param($Record, [int]$TimeLimit = 0)
    $session = Join-Path $Record.JobFolder 'unfinished.session'
    $options = @(
        '--no-conf=true', '--no-netrc=true', '--enable-rpc=false', '--check-certificate=true',
        '--continue=true', '--always-resume=true', '--auto-file-renaming=false', '--allow-overwrite=false',
        '--file-allocation=none', '--disk-cache=32M', '--max-concurrent-downloads=1',
        ('--max-connection-per-server=' + $Record.Connections), ('--split=' + $Record.Connections),
        '--min-split-size=4M', '--connect-timeout=15', '--timeout=60', '--max-tries=10', '--retry-wait=5',
        '--auto-save-interval=5', '--save-session-interval=5', ('--save-session=' + $session),
        '--summary-interval=10', '--console-log-level=warn', '--download-result=full',
        '--enable-dht=true', '--enable-peer-exchange=true', '--bt-enable-lpd=false',
        ('--dht-file-path=' + (Join-Path $Record.JobFolder 'dht.dat')),
        '--bt-save-metadata=true', '--follow-torrent=true', '--follow-metalink=true',
        '--check-integrity=true', '--bt-max-peers=80', '--seed-time=0',
        ('--dir=' + $Record.OutputDir)
    )
    $maxUpload = Get-RecordField $Record 'MaxUpload'
    if (-not $maxUpload) { $maxUpload = '1M' }
    if ($maxUpload -ne '0') { $options += '--max-overall-upload-limit=' + $maxUpload }
    $maxSpeed = Get-RecordField $Record 'MaxSpeed'
    if ($maxSpeed) { $options += '--max-overall-download-limit=' + $maxSpeed }
    $agent = Get-RecordField $Record 'UserAgent'
    if (-not $agent) { $agent = 'FastDownloader/' + $script:AppVersion + ' aria2/1.37.0' }
    if ($agent -match '[\x00-\x1f\x7f]') { throw 'UserAgent 含非法字符。' }
    $options += '--user-agent=' + $agent
    foreach ($line in @(Get-RecordField $Record 'Header')) {
        if (-not $line) { continue }
        if ($line -notmatch '^[A-Za-z0-9!#$%&''*+.^_`|~-]+:\s*[^\x00-\x1f\x7f]+$') { throw '请求头格式不正确，应形如 Name: Value。' }
        $options += '--header=' + $line
    }
    $httpUser = Get-RecordField $Record 'HttpUser'
    $httpPassword = Get-RecordField $Record 'HttpPassword'
    if ($httpPassword -and -not $httpUser) { throw 'HttpPassword 需要同时提供 HttpUser。' }
    if ($httpUser) {
        if ($httpUser -match '[\x00-\x1f\x7f]') { throw 'HttpUser 含非法字符。' }
        $options += '--http-user=' + $httpUser
    }
    if ($httpPassword) {
        if ($httpPassword -match '[\x00-\x1f\x7f]') { throw 'HttpPassword 含非法字符。' }
        $options += '--http-passwd=' + $httpPassword
    }
    if ($Record.FileName) {
        if ($Record.FileName -ne [IO.Path]::GetFileName($Record.FileName) -or $Record.FileName -in @('.', '..') -or $Record.FileName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { throw 'FileName 只能是文件名，不能包含目录或非法字符。' }
        if ($Record.FileName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or $Record.FileName -match '[. ]$') { throw 'FileName 不能是 Windows 保留名称，也不能以点或空格结尾。' }
        if ($Record.Type -ne 'URL') { throw '本地种子/磁力任务不能指定 FileName，BT 文件名由种子决定。' }
        $options += '--out=' + $Record.FileName
    }
    if ($Record.Sha256) { $options += '--checksum=sha-256=' + $Record.Sha256.ToLowerInvariant() }
    foreach ($pair in @(@('Referer', '--referer='), @('Proxy', '--all-proxy='))) {
        $value = $Record.($pair[0])
        if ($value) {
            if ($value -match '[\x00-\x1f\x7f"]') { throw ('参数含非法字符：' + $pair[0]) }
            $options += $pair[1] + $value
        }
    }
    if ($Record.CookieFile) {
        if (-not (Test-Path -LiteralPath $Record.CookieFile -PathType Leaf)) { throw '指定的 Cookie 文件不存在。不会自动读取浏览器 Cookie。' }
        $options += '--load-cookies=' + (Get-Item -LiteralPath $Record.CookieFile).FullName
    }
    if ($Record.SelectFile) { $options += '--select-file=' + $Record.SelectFile }
    if ($TimeLimit -gt 0) { $options += '--stop=' + $TimeLimit }
    if ((Test-Path -LiteralPath $session) -and (Get-Item -LiteralPath $session).Length -gt 0) {
        $options += '--input-file=' + $session
    } else {
        $options += '--'
        $options += $Record.Source
    }
    return $options
}

function Get-TaskFiles {
    param([string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory)) { return @() }
    return @(Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ne '.aria2' })
}

function Get-TaskBytes {
    param([string]$Directory)
    $total = 0
    foreach ($file in (Get-TaskFiles $Directory)) { $total += $file.Length }
    return $total
}

function Get-ShortHash {
    param([string]$Hash)
    if ($Hash.Length -le 16) { return $Hash }
    return $Hash.Substring(0, 16) + '…'
}

function Show-CompletionCard {
    param($Record)
    $files = @(Get-TaskFiles $Record.OutputDir)
    $bytes = [double](Get-RecordField $Record 'TotalBytes')
    if ($bytes -le 0) { $bytes = [double](Get-TaskBytes $Record.OutputDir) }
    $elapsed = [double](Get-RecordField $Record 'ElapsedSeconds')
    $name = $Record.Label
    if ($files.Count -eq 1) { $name = $files[0].Name }
    elseif ($files.Count -gt 1) { $name = ([string]$files.Count) + ' 个文件' }

    Write-Host ''
    Write-Accent '  完成'
    Write-Field '文件' $name
    $summary = Format-ByteSize $bytes
    if ($elapsed -gt 0) {
        $summary = $summary + ' · ' + (Format-Duration $elapsed)
        if ($bytes -gt 0) { $summary = $summary + ' · ' + (Format-ByteSize ($bytes / $elapsed)) + '/s' }
    }
    Write-Field '大小' $summary

    $expected = [string](Get-RecordField $Record 'Sha256')
    if ($expected) {
        Write-Field '校验' ('SHA-256 通过 · ' + (Get-ShortHash $expected))
    } elseif ($files.Count -eq 1 -and ($ShowHash -or $bytes -le 512MB)) {
        if ($bytes -gt 64MB) { Write-Muted '  正在计算 SHA-256…' }
        Write-Field '校验' (Get-LocalSha256 $files[0].FullName)
    }
    Write-Field '位置' $Record.OutputDir
    Write-Host ''
}

function Show-IncompleteNote {
    param($Record, [int]$Code)
    $bytes = [double](Get-RecordField $Record 'TotalBytes')
    Write-Host ''
    Write-Muted ('  未完成 · 退出码 ' + $Code)
    if ($bytes -gt 0) { Write-Field '大小' (Format-ByteSize $bytes) }
    Write-Field '位置' $Record.OutputDir
    Write-Muted '  进度已保存，重新运行后按 R 续传。'
    Write-Muted '  401/403/验证码/过期链接需要重新获取有效链接，增加连接数不能解决。'
    Write-Host ''
}

function Invoke-Task {
    param($Record)
    $options = @(Get-AriaArguments $Record $StopAfterSeconds)
    if ($DryRun) {
        # 不打印带签名的下载网址、Cookie 或代理凭据。
        Write-Host ([pscustomobject]@{ Type = $Record.Type; Connections = $Record.Connections; Destination = $Record.OutputDir; ArgumentCount = $options.Count; Valid = $true } | ConvertTo-Json)
        return 0
    }
    if (-not (Test-Path -LiteralPath $script:Engine -PathType Leaf)) { throw '缺少 bin\aria2c.exe，请完整保留工具目录。' }
    foreach ($folder in @($Record.JobFolder, $Record.OutputDir)) { [void][IO.Directory]::CreateDirectory($folder) }
    $lock = $null
    try {
        try { $lock = [IO.File]::Open((Join-Path $Record.JobFolder 'task.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch { throw '同一个任务可能已在另一个窗口下载。请不要重复运行；不同任务可以分别打开窗口。' }
        $recordPath = Join-Path $Record.JobFolder 'task.json'
        $Record.Status = 'Downloading'; $Record.UpdatedAt = [DateTime]::Now.ToString('s')
        Save-Record $Record $recordPath
        $started = Get-Date
        Write-Host ''
        Write-Muted ('保存到 ' + $Record.OutputDir)
        if ($Record.Type -eq 'BT') { Write-Muted '  BT 任务会上传数据（默认限速 1M），完成后停止做种。' }
        & $script:Engine @options | Out-Host
        $code = $LASTEXITCODE
        $elapsed = ((Get-Date) - $started).TotalSeconds
        $session = Join-Path $Record.JobFolder 'unfinished.session'
        $unfinished = (Test-Path -LiteralPath $session) -and (Get-Item -LiteralPath $session).Length -gt 0
        $Record.Status = 'Incomplete'
        if ($code -eq 0 -and -not $unfinished) { $Record.Status = 'Completed' }
        $Record.UpdatedAt = [DateTime]::Now.ToString('s')
        $Record.FinishedAt = [DateTime]::Now.ToString('s')
        $Record.ElapsedSeconds = [Math]::Round($elapsed, 1)
        $Record.TotalBytes = Get-TaskBytes $Record.OutputDir
        Save-Record $Record $recordPath
        if ($Record.Status -eq 'Completed') { Show-CompletionCard $Record }
        else { Show-IncompleteNote $Record $code }
        return $code
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
}

function Start-Downloader {
    if (-not $DownloadDir) {
        # Prefer the D: data drive when the machine has one, otherwise use the profile so
        # the default works on any Windows installation.
        if (Test-Path -LiteralPath 'D:\') { $DownloadDir = 'D:\Downloads\FastDownloads' }
        else { $DownloadDir = Join-Path $env:USERPROFILE 'Downloads\FastDownloads' }
    }
    $destination = [IO.Path]::GetFullPath($DownloadDir)
    if ($ListTasks) { Show-DownloadTasks; return 0 }
    if ($BatchFile -and ($Source -or $Resume)) { Write-Muted '  BatchFile 与 Source/Resume 不能同时使用。'; return 1 }
    if ($BatchFile) {
        try { return (Invoke-DownloadBatch $BatchFile $destination) }
        catch { Write-Muted ('  错误：' + $_.Exception.Message); return 1 }
    }
    if (-not $Proxy -and $UseSystemProxy) {
        $systemProxy = Get-SystemProxy
        if ($systemProxy) { $Proxy = $systemProxy; Write-Muted ('  使用系统代理 ' + $systemProxy) }
        else { Write-Muted '  没有检测到可用的系统代理，按直连处理。' }
    }
    do {
        try {
            $record = $null
            if ($Resume) { $record = Get-ResumeRecord }
            else {
                $text = $Source
                if (-not $text) {
                    if (-not $script:BannerShown) {
                        Write-Host ''
                        Write-Accent ('FastDownloader ' + $script:AppVersion + '  ·  aria2 1.37.0')
                        Write-Muted ('保存到 ' + $destination)
                        Write-Host ''
                        Write-Muted '粘贴链接或清单路径   R 续传   L 任务   H 帮助   Q 退出'
                        Write-Host ''
                        $script:BannerShown = $true
                    }
                    Write-Host '> ' -NoNewline
                    $text = Read-Host
                    if ($text -eq 'q') { return 0 }
                    if ($text -eq 'h') { Show-AppHelp; continue }
                    if ($text -eq 'l') { Show-DownloadTasks; continue }
                    if ($text -eq 'r') { $record = Get-ResumeRecord }
                }
                if ($text -and $text -ne 'r') {
                    if (Test-BatchSource $text) {
                        $batchCode = Invoke-DownloadBatch $text $destination
                        if (-not $script:Interactive) { return $batchCode }
                        continue
                    }
                    $spec = Get-SourceSpec $text
                    $record = New-TaskRecord $spec $destination -Separate:$NewTask
                    if ($record.Status -eq 'Completed' -and -not $DryRun) {
                        Write-Host ''
                        Write-Muted ('  这个链接之前已经下载完成')
                        Write-Field '位置' $record.OutputDir
                        if (-not $script:Interactive) {
                            Write-Muted '  若要当作新文件重新下载，请加 -NewTask。'
                            return 0
                        }
                        Write-Host ''
                        Write-Host '  重新下载？' -NoNewline
                        Write-Muted '[y/N] '
                        Write-Host '> ' -NoNewline
                        if ((Read-Host) -eq 'y') { $record = New-TaskRecord $spec $destination -Separate }
                        else { $record = $null }
                    }
                }
            }
            if ($null -ne $record) {
                $result = Invoke-Task $record
                if (-not $script:Interactive) { return $result }
            }
        } catch {
            Write-Host ''
            Write-Muted ('  未能开始：' + $_.Exception.Message)
            Write-Host ''
            if (-not $script:Interactive) { return 1 }
        }
    } while ($script:Interactive)
    return 0
}

if ($Help) { Show-AppHelp; exit 0 }
if (-not $LibraryOnly) { exit (Start-Downloader) }
