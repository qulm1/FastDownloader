[CmdletBinding()]
param(
    [string]$StateDir,
    [string]$DownloadDir = 'D:\Downloads\FastDownloads',
    [switch]$LayoutOnly
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Net.Http,System.Web.Extensions
[Windows.Forms.Application]::EnableVisualStyles()
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'WindowEngine.cs') -ReferencedAssemblies System.dll,System.Core.dll,System.Net.Http.dll,System.Web.Extensions.dll
    Add-Type -Path (Join-Path $PSScriptRoot 'DesktopStyles.cs') -ReferencedAssemblies System.dll,System.Drawing.dll,System.Windows.Forms.dll
    . (Join-Path $PSScriptRoot 'FastDownload.ps1') -LibraryOnly -StateDir $StateDir -DownloadDir $DownloadDir
    $script:EnginePath = $script:Engine
} catch {
    [void][Windows.Forms.MessageBox]::Show(('启动失败：' + $_.Exception.Message),'极速下载助手')
    exit 1
}

$script:Items = New-Object System.Collections.ArrayList
$script:Active = $null
$script:Closing = $false
$script:ReadyToClose = $false
$script:LastPoll = [DateTime]::MinValue
$script:UiBusy = $false

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:0.00} GiB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:0.0} MiB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:0.0} KiB' -f ($Bytes / 1KB)) }
    return ('{0:0} B' -f $Bytes)
}

function Set-ItemState($Item, [string]$State) {
    if ($Item.State -ne $State) { $script:FilterDirty=$true }
    $Item.State = $State
    $labels = @{ Waiting='排队中'; Starting='正在连接'; Downloading='下载中'; Paused='已暂停';
        Completed='已完成'; Incomplete='待恢复'; Stopping='正在保存'; Failed='失败，可重试' }
    $Item.Row.Cells['Status'].Value = $labels[$State]
    $color = [Drawing.Color]::FromArgb(108,118,137)
    if ($State -eq 'Completed') { $color=[Drawing.Color]::FromArgb(34,151,113) }
    elseif ($State -in @('Starting','Downloading','Waiting')) { $color=[Drawing.Color]::FromArgb(52,120,246) }
    elseif ($State -eq 'Failed') { $color=[Drawing.Color]::FromArgb(204,74,74) }
    $Item.Row.Cells['Status'].Style.ForeColor=$color
    if ($State -eq 'Completed') { $Item.Row.Cells['Progress'].Value = '100%' }
}

function Add-RecordRow($Record) {
    $name = $Record.FileName
    if (-not $name) {
        try {
            if ($Record.Type -eq 'URL') { $name=[Uri]::UnescapeDataString(([Uri]$Record.Source).Segments[-1]) }
            else { $name=[IO.Path]::GetFileName($Record.Source) }
        } catch { }
    }
    if (-not $name -or $Record.Type -eq 'BT' -and $Record.Source -like 'magnet:*') { $name=$Record.Label }
    $index = $grid.Rows.Add($name, '', '', '', '', '', '', $Record.OutputDir)
    $item = [pscustomobject]@{ Record=$Record; Row=$grid.Rows[$index]; State='Incomplete' }
    $item.Row.Tag = $item
    $item.Row.Cells['Name'].ToolTipText=$Record.OutputDir
    $script:FilterDirty=$true
    [void]$script:Items.Add($item)
    $state = 'Incomplete'
    if ($Record.Status -eq 'Completed') { $state = 'Completed' }
    elseif ($Record.Status -eq 'Paused') { $state = 'Paused' }
    Set-ItemState $item $state
    if ($null -ne $Record.PSObject.Properties['TotalBytes'] -and [double]$Record.TotalBytes -gt 0) {
        $displayDone=[double]$Record.CompletedBytes
        if ($state -eq 'Completed') { $displayDone=[double]$Record.TotalBytes }
        $item.Row.Cells['Done'].Value=Format-Size $displayDone
        $item.Row.Cells['Total'].Value=Format-Size ([double]$Record.TotalBytes)
        $item.Row.Cells['Progress'].Value=([Math]::Min(100,[Math]::Floor($displayDone*100/[double]$Record.TotalBytes))).ToString()+'%'
    }
    return $item
}

function Save-UiRecord($Item, [string]$State) {
    $Item.Record.Status = $State
    $Item.Record.UpdatedAt = [DateTime]::Now.ToString('s')
    Save-Record $Item.Record (Join-Path $Item.Record.JobFolder 'task.json')
}

function Save-WaitingRecord($Item, [string]$State) {
    [void][IO.Directory]::CreateDirectory($Item.Record.JobFolder)
    $lock = $null
    try {
        $lock = [IO.File]::Open((Join-Path $Item.Record.JobFolder 'task.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        Save-UiRecord $Item $State
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
}

function Get-SelectedItem {
    if ($grid.SelectedRows.Count -eq 0) { return $null }
    return $grid.SelectedRows[0].Tag
}

function Show-UiError([string]$Message) {
    $status.Text = $Message
    if ($newDialog.Visible) { $dialogError.Text=$Message; return }
    [void][Windows.Forms.MessageBox]::Show($form,$Message,'极速下载助手',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)
}

function Add-Inputs([string[]]$Texts) {
    # Fully validate all input before starting this batch or writing its records.
    $destination = [IO.Path]::GetFullPath($folder.Text.Trim())
    $prepared = New-Object System.Collections.ArrayList
    $script:Connections=[int]$connectionBox.SelectedItem
    $script:FileName=$renameBox.Text.Trim()
    $seen = @{}
    foreach ($text in $Texts) {
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $entries = @([pscustomobject]@{ Source=$text; FileName=''; Sha256='' })
        if (Test-BatchSource $text) { $entries = @(Read-DownloadBatch $text) }
        foreach ($entry in $entries) {
            if ($prepared.Count -ge 1000) { throw '一次最多添加 1000 项任务。' }
            $spec = Get-SourceSpec $entry.Source
            if ($seen.ContainsKey($spec.Identity)) { continue }
            $seen[$spec.Identity] = $true
            $record = New-TaskRecord $spec $destination -Separate:$newTaskBox.Checked
            foreach ($key in @('FileName','Sha256')) {
                if ($entry.$key) {
                    if ($record.Status -ne 'Pending' -and $record.$key -ne $entry.$key) { throw '此链接的已有任务参数不同，请勾选“另建任务”。' }
                    $record.$key = $entry.$key
                }
            }
            $null = @(Get-AriaArguments $record)
            [void]$prepared.Add($record)
        }
    }
    if ($prepared.Count -eq 0) { throw '请粘贴下载链接，或拖入任务清单/种子文件。' }
    if ($script:FileName -and $prepared.Count -gt 1) { throw '批量下载请留空重命名，或在 CSV / JSON 清单中分别指定 FileName。' }
    foreach ($record in $prepared) {
        $matches = @($script:Items | Where-Object { $_.Record.Id -eq $record.Id })
        if ($matches.Count -gt 0) { $item = $matches[0] }
        else { $item = Add-RecordRow $record }
        if ($item.State -notin @('Completed','Downloading','Starting','Paused','Stopping')) {
            Save-WaitingRecord $item 'Pending'
            Set-ItemState $item 'Waiting'
        }
    }
    $inputBox.Clear()
    $newDialog.Visible=$false
    $status.Text = '任务已添加。按列表顺序下载；已有任务不会重复下载，待恢复任务可继续。'
}

function Start-NextItem {
    if ($null -ne $script:Active -or $script:Closing) { return }
    $next = @($script:Items | Where-Object { $_.State -eq 'Waiting' } | Select-Object -First 1)
    if ($next.Count -eq 0) { return }
    $item = $next[0]; $lock = $null; $engine = $null
    try {
        if (-not (Test-Path -LiteralPath $script:EnginePath -PathType Leaf)) { throw '缺少 bin\aria2c.exe，请完整解压便携包。' }
        [void][IO.Directory]::CreateDirectory($item.Record.JobFolder)
        [void][IO.Directory]::CreateDirectory($item.Record.OutputDir)
        try { $lock = [IO.File]::Open((Join-Path $item.Record.JobFolder 'task.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
        catch { throw '这个任务正在另一个窗口中运行，请先在那里暂停并关闭。' }
        # The secret is generated for this process only and never saved in state.
        $port = [FastDownloader.WindowEngine]::FindPort()
        $secret = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
        $arguments = @(Get-AriaArguments $item.Record | Where-Object { $_ -notmatch '^--(?:enable-rpc|auto-save-interval|save-session-interval)=' })
        $rpc = @('--enable-rpc=true','--rpc-listen-all=false','--rpc-allow-origin-all=false',
            ('--rpc-listen-port=' + $port),('--rpc-secret=' + $secret),
            '--auto-save-interval=1','--save-session-interval=1','--max-download-result=1000')
        # Engine options must precede the final -- URL/source delimiter.
        $arguments = $rpc + $arguments
        Save-UiRecord $item 'Downloading'
        $engine = New-Object FastDownloader.WindowEngine($script:EnginePath,[string[]]$arguments,$port,$secret)
        $script:Active = [pscustomobject]@{ Item=$item; Engine=$engine; Lock=$lock; Poll=$null; Command=$null;
            Started=[DateTime]::Now; LastSuccess=[DateTime]::Now; StopAt=$null; FinalState='Incomplete'; LastSaved='Downloading'; Intent=''; UserMessage=''; ProgressSavedAt=[DateTime]::MinValue }
        Set-ItemState $item 'Starting'
        if ($item.Row.Visible) { $grid.ClearSelection(); $item.Row.Selected=$true }
        $status.Text = '正在连接下载引擎…'
    } catch {
        if ($null -ne $engine) { $engine.Dispose() }
        if ($null -ne $lock) { $lock.Dispose() }
        Set-ItemState $item 'Failed'
        $status.Text = '启动失败：' + $_.Exception.Message
    }
}

function Stop-Active([string]$FinalState = 'Incomplete') {
    $active = $script:Active
    if ($null -eq $active -or $null -ne $active.StopAt) { return }
    $active.FinalState = $FinalState
    $active.StopAt = [DateTime]::Now
    if (-not $active.Engine.Process.HasExited) { $active.Command = $active.Engine.CommandAsync('aria2.shutdown') }
    Set-ItemState $active.Item 'Stopping'
}

function Finish-Active {
    $active = $script:Active
    $state = $active.FinalState
    if ($null -eq $active.StopAt) { $state = 'Incomplete' }
    try {
        if ($state -eq 'Completed' -and $null -ne $active.Item.Record.PSObject.Properties['TotalBytes']) {
            $active.Item.Record | Add-Member -NotePropertyName CompletedBytes -NotePropertyValue $active.Item.Record.TotalBytes -Force
            $active.Item.Row.Cells['Done'].Value=Format-Size ([double]$active.Item.Record.TotalBytes)
        }
        Save-UiRecord $active.Item $state
        Set-ItemState $active.Item $state
        $active.Item.Row.Cells['Speed'].Value = ''
        $active.Item.Row.Cells['Eta'].Value = ''
        if ($state -eq 'Completed') { $status.Text = '下载完成。可选择任务并打开所在文件夹。' }
        elseif (-not $script:Closing) {
            $status.Text = '任务已停止并保留断点，点击“继续”可恢复。'
            if ($active.UserMessage) { Set-ItemState $active.Item 'Failed'; $status.Text=$active.UserMessage }
        }
    } finally {
        $active.Engine.Dispose()
        $active.Lock.Dispose()
        $script:Active = $null
    }
}

function Update-Window {
    if ($script:UiBusy) { return }
    $script:UiBusy = $true
    try {
        $active = $script:Active
        if ($null -ne $active) {
            if ($active.Engine.Process.HasExited) { Finish-Active }
            elseif ($null -ne $active.StopAt) {
                # Normal shutdown saves session and .aria2 state. Bound an unresponsive engine.
                if (([DateTime]::Now - $active.StopAt).TotalSeconds -gt 12) {
                    $active.FinalState = 'Incomplete'
                    $active.Engine.Process.Kill()
                }
            } else {
                if ($null -ne $active.Command -and $active.Command.IsCompleted) {
                    $reply = $active.Command.Result; $active.Command = $null
                    if (-not $reply.Success) { $status.Text = $reply.Error }
                    $active.Intent = ''
                }
                if ($null -ne $active.Poll -and $active.Poll.IsCompleted) {
                    $reply = $active.Poll.Result; $active.Poll = $null
                    if ($reply.Success) {
                        $active.LastSuccess = [DateTime]::Now
                        $result = (ConvertFrom-Json -InputObject $reply.Json).result
                        $global = $result[0][0]
                        $tasks = @($result[1][0]) + @($result[2][0]) + @($result[3][0])
                        $tasks = @($tasks | Where-Object { $null -ne $_ })
                        $failedTasks = @($tasks | Where-Object { $_.status -in @('error','removed') })
                        $working = @($tasks | Where-Object { $_.status -in @('active','waiting','paused') })
                        if ($failedTasks.Count -gt 0) {
                            $active.UserMessage = '下载失败（引擎代码 ' + $failedTasks[0].errorCode + '）。请检查链接、网络和剩余磁盘空间，再点击继续。'
                            $status.Text=$active.UserMessage
                            Stop-Active 'Incomplete'
                        } elseif ($tasks.Count -gt 0 -and $working.Count -eq 0 -and [int]$global.numActive -eq 0 -and [int]$global.numWaiting -eq 0) {
                            Stop-Active 'Completed'
                        } else {
                            # A magnet metadata task is followed by a different content task.
                            $visible = @($tasks | Where-Object { $_.status -ne 'complete' -or -not $_.followedBy })
                            [double]$total = 0; [double]$done = 0
                            foreach ($task in $visible) { $total += [double]$task.totalLength; $done += [double]$task.completedLength }
                            if (([DateTime]::Now-$active.ProgressSavedAt).TotalSeconds -ge 2) {
                                $active.Item.Record | Add-Member -NotePropertyName CompletedBytes -NotePropertyValue $done -Force
                                $active.Item.Record | Add-Member -NotePropertyName TotalBytes -NotePropertyValue $total -Force
                                Save-UiRecord $active.Item $active.Item.Record.Status
                                $active.ProgressSavedAt=[DateTime]::Now
                            }
                            [double]$speed = $global.downloadSpeed
                            $paused = @($working | Where-Object { $_.status -eq 'paused' }).Count -gt 0
                            $state = 'Downloading'; if ($paused) { $state = 'Paused' }
                            Set-ItemState $active.Item $state
                            if ($active.LastSaved -ne $state) { Save-UiRecord $active.Item $state; $active.LastSaved = $state }
                            $percent = 0
                            if ($total -gt 0) { $percent = [Math]::Min(100,[Math]::Floor($done * 100 / $total)) }
                            $active.Item.Row.Cells['Progress'].Value = $(if ($total -gt 0) { "$percent%" } else { '等待长度/元数据' })
                            $active.Item.Row.Cells['Speed'].Value = (Format-Size $speed) + '/s'
                            $active.Item.Row.Cells['Done'].Value = Format-Size $done
                            $active.Item.Row.Cells['Total'].Value = $(if ($total -gt 0) { Format-Size $total } else { '未知' })
                            $eta = '—'
                            if ($speed -gt 0 -and $total -gt $done) { $eta = [TimeSpan]::FromSeconds([Math]::Min(31536000,($total-$done)/$speed)).ToString('g') }
                            $active.Item.Row.Cells['Eta'].Value = $eta
                            $progress.Value = [int]$percent
                            $status.Text = $(if ($paused) { '当前任务已暂停。点击“继续”后继续下载和后续队列。' } else { '下载中。暂停保留当前任务；关闭窗口会保存断点。' })
                        }
                    } elseif (([DateTime]::Now - $active.LastSuccess).TotalSeconds -gt 12) {
                        $status.Text = '下载引擎连接中断，正在保存断点。'
                        Stop-Active 'Incomplete'
                    }
                }
                if ($null -eq $active.Poll -and $null -eq $active.StopAt -and ([DateTime]::Now - $script:LastPoll).TotalMilliseconds -ge 600) {
                    $active.Poll = $active.Engine.PollAsync(); $script:LastPoll = [DateTime]::Now
                }
            }
        }
        if ($null -eq $script:Active) {
            if ($script:Closing) { $script:ReadyToClose = $true; $form.Close() }
            else { Start-NextItem }
        }
    } catch {
        $status.Text = '状态更新失败：' + $_.Exception.Message
        if ($null -ne $script:Active) { Stop-Active 'Incomplete' }
    } finally { $script:UiBusy = $false }
}

. (Join-Path $PSScriptRoot 'WindowLayout.ps1')
