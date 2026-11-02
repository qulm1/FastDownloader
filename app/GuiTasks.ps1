# Task controller shared by the WPF UI and headless integration tests.
# Reuses CLI validation/options/records; it does not estimate progress from file length.
$script:GuiItems=New-Object System.Collections.ArrayList
$script:GuiActive=$null
$script:GuiClosing=$false
$script:GuiError=''

function Get-GuiValue($Object,[string]$Name,$Default=$null) {
    if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}
function Get-TaskSnapshot($Record) {
    [double]$bytes=0; [double]$total=0; $known=$false
    if($Record.Status -eq 'Completed') {
        $bytes=[double](Get-GuiValue $Record 'TotalBytes' 0)
        $total=$bytes; $known=$true
    } elseif((Get-GuiValue $Record 'GuiProgressVersion' 0) -eq 1) {
        $bytes=[double](Get-GuiValue $Record 'GuiCompletedBytes' 0)
        $total=[double](Get-GuiValue $Record 'GuiTargetBytes' 0)
        $known=($total -gt 0)
    }
    $percent=$null
    if($Record.Status -eq 'Completed') { $percent=100.0 }
    elseif($known) { $percent=[Math]::Min(99.9,[Math]::Round(100*$bytes/$total,1)) }
    return [pscustomobject]@{Bytes=$bytes;Total=$total;Known=$known;Percent=$percent;Speed=0.0}
}
function Get-GuiName($Record) {
    $name=[string](Get-GuiValue $Record 'FileName' '')
    if(-not $name) { $name=[string](Get-GuiValue $Record 'GuiDisplayName' '') }
    if(-not $name -and $Record.Type -eq 'URL') {
        try { $name=[Uri]::UnescapeDataString(([Uri]$Record.Source).Segments[-1]).TrimEnd('/') } catch { }
    }
    if(-not $name) { $name=[string]$Record.Label }
    return $name
}
function New-GuiItem($Record) {
    $state='Incomplete'
    if($Record.Status -eq 'Completed') { $state='Completed' }
    elseif($Record.Status -eq 'Paused') { $state='Paused' }
    return [pscustomobject]@{Record=$Record;State=$state;Snapshot=(Get-TaskSnapshot $Record);Name=(Get-GuiName $Record);Error=''}
}
function Read-GuiHistory {
    if(-not (Test-Path -LiteralPath $script:JobsRoot)) { return }
    foreach($file in Get-ChildItem -LiteralPath $script:JobsRoot -Filter task.json -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 500) {
        try {
            $record=Read-JsonFile $file.FullName
            if(@($script:GuiItems | Where-Object {$_.Record.Id -eq $record.Id}).Count -eq 0) {
                [void]$script:GuiItems.Add((New-GuiItem $record))
            }
        } catch { $script:GuiError='有一份旧任务记录无法读取，原文件已保留。' }
    }
}
function Save-GuiItem($Item,[string]$State) {
    $Item.Record.Status=$State
    $Item.Record.UpdatedAt=[DateTime]::Now.ToString('s')
    Save-Record $Item.Record (Join-Path $Item.Record.JobFolder 'task.json')
}
function Save-GuiPending($Item,[string]$State) {
    [void][IO.Directory]::CreateDirectory($Item.Record.JobFolder)
    $handle=$null
    try {
        $handle=[IO.File]::Open((Join-Path $Item.Record.JobFolder 'task.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        Save-GuiItem $Item $State
    } finally { if($null -ne $handle) { $handle.Dispose() } }
}
function Add-GuiInputs([string[]]$Texts,[string]$Destination,[bool]$Separate=$false) {
    if($script:GuiClosing) { throw '正在保存并退出，请稍候。' }
    $destination=[IO.Path]::GetFullPath($Destination)
    $prepared=New-Object System.Collections.ArrayList; $seen=@{}
    foreach($text in $Texts) {
        if([string]::IsNullOrWhiteSpace($text)) { continue }
        $entries=@([pscustomobject]@{Source=$text;FileName='';Sha256=''})
        if(Test-BatchSource $text) { $entries=@(Read-DownloadBatch $text) }
        foreach($entry in $entries) {
            if($prepared.Count -ge 1000) { throw '一次最多添加 1000 项任务。' }
            $spec=Get-SourceSpec $entry.Source
            if($seen.ContainsKey($spec.Identity)) { continue }
            $seen[$spec.Identity]=$true
            $record=New-TaskRecord $spec $destination -Separate:$Separate
            foreach($key in @('FileName','Sha256')) {
                if($entry.$key) {
                    if($record.Status -ne 'Pending' -and $record.$key -ne $entry.$key) { throw '已有任务的文件名或校验值不同，请勾选“另建任务”。' }
                    $record.$key=$entry.$key
                }
            }
            $null=@(Get-AriaArguments $record)
            [void]$prepared.Add($record)
        }
    }
    if($prepared.Count -eq 0) { throw '请粘贴下载链接，或选择种子/任务清单。' }
    foreach($record in $prepared) {
        $matches=@($script:GuiItems | Where-Object {$_.Record.Id -eq $record.Id})
        if($matches.Count) { $item=$matches[0] }
        else { $item=New-GuiItem $record; [void]$script:GuiItems.Add($item) }
        if($item.State -in @('Completed','Starting','Downloading','Waiting','Stopping')) { continue }
        if($null -ne $script:GuiActive -and $script:GuiActive.Item -eq $item) { continue }
        Save-GuiPending $item 'Pending'
        $item.State='Waiting'; $item.Error=''
    }
}
function Start-GuiNext {
    if($null -ne $script:GuiActive -or $script:GuiClosing) { return }
    $next=@($script:GuiItems | Where-Object State -eq 'Waiting' | Select-Object -First 1)
    if(-not $next.Count) { return }
    $item=$next[0]; $handle=$null; $worker=$null
    try {
        if(-not (Test-Path -LiteralPath $script:GuiEnginePath -PathType Leaf)) { throw '缺少 bin\aria2c.exe，请完整解压下载包。' }
        [void][IO.Directory]::CreateDirectory($item.Record.JobFolder)
        [void][IO.Directory]::CreateDirectory($item.Record.OutputDir)
        try { $handle=[IO.File]::Open((Join-Path $item.Record.JobFolder 'task.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
        catch { throw '同一个任务正在其他窗口运行，请先在那里停止。' }
        if(-not ('FastDownloader.WindowEngine' -as [type])) {
            Add-Type -Path (Join-Path $script:GuiRoot 'GuiEngine.cs') -ReferencedAssemblies System.dll,System.Core.dll,System.Net.Http.dll,System.Web.Extensions.dll
        }
        $port=[FastDownloader.WindowEngine]::FindPort()
        $secret=[Guid]::NewGuid().ToString('N')+[Guid]::NewGuid().ToString('N')
        $options=@('--enable-rpc=true','--rpc-listen-all=false','--rpc-allow-origin-all=false',('--rpc-listen-port='+$port),('--rpc-secret='+$secret),'--auto-save-interval=1','--save-session-interval=1','--max-download-result=1000')+
            @(Get-AriaArguments $item.Record | Where-Object {$_ -notmatch '^--(?:enable-rpc|auto-save-interval|save-session-interval)='})
        Save-GuiItem $item 'Downloading'
        $worker=New-Object FastDownloader.WindowEngine($script:GuiEnginePath,[string[]]$options,$port,$secret)
        $script:GuiActive=[pscustomobject]@{Item=$item;Engine=$worker;Lock=$handle;Poll=$null;Command=$null;
            Started=[DateTime]::Now;LastSuccess=[DateTime]::Now;LastPoll=[DateTime]::MinValue;LastSave=[DateTime]::MinValue;
            StopAt=$null;Final='Incomplete';SettledPolls=0}
        $item.State='Starting'
    } catch {
        if($null -ne $worker) { $worker.Dispose() }
        if($null -ne $handle) { $handle.Dispose() }
        $item.State='Failed';$item.Error=$_.Exception.Message;$script:GuiError=$item.Error
    }
}
function Stop-GuiActive([string]$State='Incomplete') {
    $active=$script:GuiActive
    if($null -eq $active -or $null -ne $active.StopAt) { return }
    $active.Final=$State;$active.StopAt=[DateTime]::Now;$active.Item.State='Stopping'
    if(-not $active.Engine.Process.HasExited) { $active.Command=$active.Engine.CommandAsync('aria2.shutdown') }
}
function Set-GuiAction([string]$Id,[string]$Action) {
    $matches=@($script:GuiItems | Where-Object {$_.Record.Id -eq $Id})
    if(-not $matches.Count -or $script:GuiClosing) { return }
    $item=$matches[0]
    if($null -ne $script:GuiActive -and $script:GuiActive.Item -eq $item) {
        if($null -ne $script:GuiActive.StopAt) { return }
        if($Action -eq 'Stop') { Stop-GuiActive;return }
        if($null -ne $script:GuiActive.Command) { return }
        if($Action -eq 'Pause' -and $item.State -eq 'Downloading') { $script:GuiActive.Command=$script:GuiActive.Engine.CommandAsync('aria2.pauseAll') }
        elseif($Action -eq 'Resume' -and $item.State -eq 'Paused') { $script:GuiActive.Command=$script:GuiActive.Engine.CommandAsync('aria2.unpauseAll') }
    } elseif($Action -eq 'Resume' -and $item.State -in @('Incomplete','Paused','Failed')) {
        Save-GuiPending $item 'Pending';$item.State='Waiting';$item.Error=''
    } elseif($item.State -in @('Paused','Waiting')) {
        $state='Incomplete';if($Action -eq 'Pause') { $state='Paused' }
        Save-GuiPending $item $state;$item.State=$state
    }
}
function Save-GuiProgress($Item) {
    $Item.Record | Add-Member -NotePropertyName GuiProgressVersion -NotePropertyValue 1 -Force
    $Item.Record | Add-Member -NotePropertyName GuiCompletedBytes -NotePropertyValue $Item.Snapshot.Bytes -Force
    $Item.Record | Add-Member -NotePropertyName GuiTargetBytes -NotePropertyValue $Item.Snapshot.Total -Force
    Save-GuiItem $Item $Item.Record.Status
}
function Finish-GuiActive {
    $active=$script:GuiActive;$item=$active.Item;$state=$active.Final
    if($null -eq $active.StopAt) { $state='Incomplete';$item.Error='下载引擎已退出，断点已保留，可点击继续。' }
    try {
        if($state -eq 'Completed') {
            $item.Snapshot.Bytes=[Math]::Max($item.Snapshot.Bytes,$item.Snapshot.Total)
            $item.Snapshot.Total=$item.Snapshot.Bytes;$item.Snapshot.Known=$true;$item.Snapshot.Percent=100.0
            $item.Record | Add-Member -NotePropertyName TotalBytes -NotePropertyValue $item.Snapshot.Bytes -Force
            $item.Record | Add-Member -NotePropertyName FinishedAt -NotePropertyValue ([DateTime]::Now.ToString('s')) -Force
            $item.Record | Add-Member -NotePropertyName ElapsedSeconds -NotePropertyValue ([Math]::Round(([DateTime]::Now-$active.Started).TotalSeconds,1)) -Force
        }
        $item.Snapshot.Speed=0
        Save-GuiProgress $item
        Save-GuiItem $item $state
        $item.State=$state
        if($item.Error -and $state -ne 'Completed') { $item.State='Failed';$script:GuiError=$item.Error }
    } finally {
        $active.Engine.Dispose();$active.Lock.Dispose();$script:GuiActive=$null
    }
}
function Update-GuiTasks {
    $active=$script:GuiActive
    if($null -ne $active) {
        try {
            if($active.Engine.Process.HasExited) { Finish-GuiActive }
            elseif($null -ne $active.StopAt) {
                if(([DateTime]::Now-$active.StopAt).TotalSeconds -gt 12) { $active.Final='Incomplete';$active.Engine.Process.Kill() }
            } else {
                if($null -ne $active.Command -and $active.Command.IsCompleted) {
                    $reply=$active.Command.Result;$active.Command=$null
                    if(-not $reply.Success) { $script:GuiError=$reply.Error }
                }
                if($null -ne $active.Poll -and $active.Poll.IsCompleted) {
                    $reply=$active.Poll.Result;$active.Poll=$null
                    if($reply.Success) {
                        $active.LastSuccess=[DateTime]::Now
                        $result=(ConvertFrom-Json -InputObject $reply.Json).result
                        $global=$result[0][0]
                        $tasks=@(@($result[1][0])+@($result[2][0])+@($result[3][0]) | Where-Object {$null -ne $_})
                        $errors=@($tasks | Where-Object {$_.status -in @('error','removed')})
                        $working=@($tasks | Where-Object {$_.status -in @('active','waiting','paused')})
                        $visible=@($tasks | Where-Object {@(Get-GuiValue $_ 'followedBy' @()).Count -eq 0})
                        [double]$bytes=0;[double]$total=0
                        foreach($task in $visible) {$bytes+=[double]$task.completedLength;$total+=[double]$task.totalLength}
                        $item=$active.Item
                        $item.Snapshot=[pscustomobject]@{Bytes=$bytes;Total=$total;Known=($total -gt 0);Percent=$null;Speed=[double]$global.downloadSpeed}
                        if($total -gt 0) {$item.Snapshot.Percent=[Math]::Min(99.9,[Math]::Round(100*$bytes/$total,1))}
                        $paths=@($visible | ForEach-Object {@($_.files)} | Where-Object {$_.path})
                        if($paths.Count -eq 1) {$item.Name=[IO.Path]::GetFileName($paths[0].path)}
                        if($errors.Count) {
                            $item.Error='下载失败（引擎代码 '+$errors[0].errorCode+'），请检查链接、网络或磁盘空间。'
                            Stop-GuiActive
                        } elseif($tasks.Count -gt 0 -and $working.Count -eq 0 -and [int]$global.numActive -eq 0 -and [int]$global.numWaiting -eq 0) {
                            # Two stable polls avoid mistaking a magnet metadata handoff for completion.
                            $active.SettledPolls++
                            if($active.SettledPolls -ge 2) { Stop-GuiActive 'Completed' }
                        } else {
                            $active.SettledPolls=0
                            $state='Downloading'
                            if(@($working | Where-Object status -eq 'paused').Count) {$state='Paused'}
                            $item.State=$state
                            if($item.Record.Status -ne $state) {Save-GuiItem $item $state}
                        }
                        if(([DateTime]::Now-$active.LastSave).TotalSeconds -ge 2) {Save-GuiProgress $item;$active.LastSave=[DateTime]::Now}
                    } elseif(([DateTime]::Now-$active.LastSuccess).TotalSeconds -gt 12) {
                        $active.Item.Error='本机引擎连接中断，断点已保留。';Stop-GuiActive
                    }
                }
                if($null -eq $active.Poll -and $null -eq $active.StopAt -and ([DateTime]::Now-$active.LastPoll).TotalMilliseconds -ge 600) {
                    $active.Poll=$active.Engine.PollAsync();$active.LastPoll=[DateTime]::Now
                }
            }
        } catch {
            $script:GuiError='任务状态处理失败，正在保存断点。'
            if($null -ne $script:GuiActive) {$script:GuiActive.Item.Error=$script:GuiError;Stop-GuiActive}
        }
    }
    if($null -eq $script:GuiActive -and -not $script:GuiClosing) {Start-GuiNext}
}
function Close-GuiController {
    if($null -eq $script:GuiActive) {return}
    try {
        Stop-GuiActive
        if(-not $script:GuiActive.Engine.Process.HasExited) {
            if(-not $script:GuiActive.Engine.Process.WaitForExit(5000)) {$script:GuiActive.Engine.Process.Kill()}
        }
        Finish-GuiActive
    } finally { $script:GuiClosing=$true }
}
