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
    [ValidatePattern('^(|[0-9,-]+)$')][string]$SelectFile,
    [switch]$Resume,
    [switch]$NewTask,
    [switch]$DryRun,
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
        $existing = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        if ($existing.DownloadDir -ne $Destination) { throw '此任务已记录了另一个下载目录。要新建独立任务，请加 -NewTask。恢复任务请用 R 或 -Resume。' }
        return $existing
    }
    $safeLabel = [regex]::Replace($Spec.Label, '[^\p{L}\p{N}._-]', '_')
    if ($safeLabel.Length -gt 40) { $safeLabel = $safeLabel.Substring(0, 40) }
    $outputFolder = Join-Path $Destination ($safeLabel + '-' + $key)
    return [pscustomobject]@{
        Id = $key; Source = $Spec.Source; Type = $Spec.Type; Label = $Spec.Label
        DownloadDir = $Destination; OutputDir = $outputFolder; JobFolder = $jobFolder
        Status = 'Pending'; UpdatedAt = [DateTime]::Now.ToString('s')
        Connections = $Connections; FileName = $FileName; Sha256 = $Sha256
        Referer = $Referer; CookieFile = $CookieFile; Proxy = $Proxy; SelectFile = $SelectFile
    }
}

function Get-ResumeRecord {
    $records = @()
    if (Test-Path -LiteralPath $script:JobsRoot) {
        foreach ($file in Get-ChildItem -LiteralPath $script:JobsRoot -Filter task.json -Recurse -File) {
            try {
                $entry = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
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
        '--check-integrity=true', '--bt-max-peers=80', '--seed-time=0', '--max-overall-upload-limit=1M',
        '--user-agent=FastDownloader/2.0 aria2/1.37.0', ('--dir=' + $Record.OutputDir)
    )
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
        Write-Host ('保存位置：' + $Record.OutputDir) -ForegroundColor Cyan
        Write-Host ('HTTP 连接上限：' + $Record.Connections + '；每 5 秒保存进度。按一次 Ctrl+C 可停止，稍等它保存后退出。')
        Write-Host 'BT：可能上传数据，上传总上限 1 MiB/s；完成后停止做种。多文件种子默认下载全部文件。' -ForegroundColor Yellow
        Write-Host '请仅下载你有权获取的内容。不会自动打开或安装下载文件。'
        & $script:Engine @options | Out-Host
        $code = $LASTEXITCODE
        $session = Join-Path $Record.JobFolder 'unfinished.session'
        $unfinished = (Test-Path -LiteralPath $session) -and (Get-Item -LiteralPath $session).Length -gt 0
        $Record.Status = 'Incomplete'
        if ($code -eq 0 -and -not $unfinished) { $Record.Status = 'Completed' }
        $Record.UpdatedAt = [DateTime]::Now.ToString('s')
        Save-Record $Record $recordPath
        if ($Record.Status -eq 'Completed') {
            Write-Host ('下载完成：' + $Record.OutputDir) -ForegroundColor Green
            if ($Record.Sha256) { Write-Host 'SHA-256 校验通过。' -ForegroundColor Green }
        } else {
            Write-Host ('任务尚未完成（退出码 ' + $code + '），已保存记录。下次输入 R 续传。') -ForegroundColor Yellow
            Write-Host '若提示 401/403/验证码/过期链接，请获取有权限的有效文件链接；反复增加连接数不能解决。'
        }
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
    if ($BatchFile -and ($Source -or $Resume)) { Write-Host 'BatchFile 与 Source/Resume 不能同时使用。' -ForegroundColor Red; return 1 }
    if ($BatchFile) {
        try { return (Invoke-DownloadBatch $BatchFile $destination) }
        catch { Write-Host ('错误：' + $_.Exception.Message) -ForegroundColor Red; return 1 }
    }
    do {
        try {
            $record = $null
            if ($Resume) { $record = Get-ResumeRecord }
            else {
                $text = $Source
                if (-not $text) {
                    Write-Host ''
                    Write-Host '极速下载助手 | aria2 1.37.0' -ForegroundColor Cyan
                    Write-Host '粘贴网址、磁力链接，或拖入种子、TXT/CSV/JSON/URL 任务清单。'
                    Write-Host 'R = 续传；L = 查看任务；Q = 退出。默认保存到 D 盘。'
                    $text = Read-Host '下载地址'
                    if ($text -eq 'q') { return 0 }
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
                        Write-Host ('此链接之前已经完成，文件位置：' + $record.OutputDir)
                        if (-not $script:Interactive) { Write-Host '若链接指向了新版文件，请用 -NewTask 重新下载。'; return 0 }
                        if ((Read-Host '是否另建任务重新下载？输入 Y 确认，直接回车不重复下载') -eq 'y') { $record = New-TaskRecord $spec $destination -Separate }
                        else { $record = $null }
                    }
                }
            }
            if ($null -ne $record) {
                $result = Invoke-Task $record
                if (-not $script:Interactive) { return $result }
            }
        } catch {
            Write-Host ('错误：' + $_.Exception.Message) -ForegroundColor Red
            if (-not $script:Interactive) { return 1 }
        }
    } while ($script:Interactive)
    return 0
}

if (-not $LibraryOnly) { exit (Start-Downloader) }
