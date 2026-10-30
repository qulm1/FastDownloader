param([string]$WorkRoot,[string]$NetworkSource,[string]$SecondSource,[string]$UnknownSource,[string]$MissingSource,[string]$ExpectedHash,[string]$TorrentSource,[string]$MagnetSource)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
[void][IO.Directory]::CreateDirectory($WorkRoot)
. (Join-Path $project 'FastDownloadGui.ps1') -LibraryOnly -StateDir (Join-Path $WorkRoot 'state') -DownloadDir (Join-Path $WorkRoot '中文 下载')
$evidence=New-Object System.Collections.ArrayList
function Assert-Gui([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};[void]$evidence.Add(@{name=$Name;passed=$true})}
function Wait-Gui($Condition,[int]$Seconds=45){
    $end=[DateTime]::Now.AddSeconds($Seconds)
    do{Update-GuiTasks;Render-GuiTasks;if(& $Condition){return};Start-Sleep -Milliseconds 100}while([DateTime]::Now -lt $end)
    throw ('GUI wait timed out: '+$script:GuiError)
}
function Click-OwnButton($Button){$Button.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}
function Save-WpfPreview([string]$Name,[int]$Width,[int]$Height){
    $root=$script:GuiWindow.Content
    $root.Measure((New-Object Windows.Size($Width,$Height)))
    $root.Arrange((New-Object Windows.Rect(0,0,$Width,$Height)))
    $root.UpdateLayout()
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap($Width,$Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    # Window background is outside Content's visual tree; paint that real parent
    # background first so an offscreen transparent margin does not look black.
    $background=New-Object Windows.Media.DrawingVisual
    $context=$background.RenderOpen()
    $context.DrawRectangle($script:GuiWindow.Background,$null,(New-Object Windows.Rect(0,0,$Width,$Height)))
    $context.Close();$bitmap.Render($background)
    $bitmap.Render($root)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create((Join-Path $WorkRoot $Name))
    try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
try{
    if(-not ('FastDownloader.WindowEngine' -as [type])){Add-Type -Path (Join-Path $project 'GuiEngine.cs') -ReferencedAssemblies System.dll,System.Core.dll,System.Net.Http.dll,System.Web.Extensions.dll}
    $window=Initialize-GuiWindow
    Assert-Gui (-not $window.IsVisible) 'WPF initializes without showing any desktop window'
    Assert-Gui ($script:GuiDestination.EndsWith('中文 下载')) 'Explicit destination survives CLI dot-source import'
    foreach($name in @('UrlBox','StartButton','TaskPanel','DestinationBox','ImportButton','ChooseFolderButton','FilterBox','NewTaskCheck')){Assert-Gui ($null -ne $script:GuiControls[$name]) ('Actual WPF view exposes '+$name)}
    # A preallocated file has a long logical length, not necessarily received data.
    $allocated=Join-Path $WorkRoot 'preallocated';[void][IO.Directory]::CreateDirectory($allocated)
    $stream=[IO.File]::Create((Join-Path $allocated 'file.bin'));$stream.SetLength(32MB);$stream.Dispose()
    $legacy=New-TaskRecord (Get-SourceSpec 'https://example.invalid/preallocated.bin') $allocated
    $legacy.OutputDir=$allocated;$legacy.Status='Incomplete'
    $snapshot=Get-TaskSnapshot $legacy
    Assert-Gui (-not $snapshot.Known -and $null -eq $snapshot.Percent) 'Preallocation and missing telemetry never manufacture 100 percent'
    $legacy.Status='Completed';$legacy.TotalBytes=32MB
    Assert-Gui ((Get-TaskSnapshot $legacy).Percent -eq 100) 'Only completed legacy records report 100 percent'
    $sample=@(@('设计说明.pdf','Completed',100),@('演示视频.mp4','Paused',45),@('应用安装包.exe','Downloading',28))
    foreach($entry in $sample){
        $record=New-TaskRecord (Get-SourceSpec ('https://example.invalid/'+[Uri]::EscapeDataString($entry[0]))) (Join-Path $WorkRoot 'sample')
        $record.FileName=$entry[0];$record.TotalBytes=128MB
        $item=New-GuiItem $record;$item.State=$entry[1]
        $item.Snapshot=[pscustomobject]@{Bytes=([double]$entry[2]*128MB/100);Total=128MB;Known=$true;Percent=[double]$entry[2];Speed=2MB}
        [void]$script:GuiItems.Add($item)
    }
    Render-GuiTasks
    foreach($size in @(@(760,600),@(960,740),@(1280,900))){
        Save-WpfPreview ('preview-'+$size[0]+'.png') $size[0] $size[1]
        foreach($control in @($script:GuiControls.UrlBox,$script:GuiControls.StartButton,$script:GuiControls.DestinationBox)){
            Assert-Gui ($control.ActualWidth -gt 40 -and $control.ActualHeight -gt 10) ('Usable WPF input/action geometry at '+$size[0])
        }
    }
    $script:GuiControls.FilterBox.SelectedIndex=3;Render-GuiTasks
    Assert-Gui (@($script:GuiCards.Values|Where-Object {$_.Root.Visibility -eq 'Visible'}).Count -eq 1) 'Completed filter drives the actual card collection'
    $script:GuiControls.FilterBox.SelectedIndex=0
    $script:GuiControls.TaskPanel.Children.Clear();$script:GuiCards.Clear();$script:GuiItems.Clear()
    if($NetworkSource){
        $script:Sha256=$ExpectedHash
        $script:GuiControls.UrlBox.Text=$NetworkSource+[Environment]::NewLine+$SecondSource
        Click-OwnButton $script:GuiControls.StartButton
        Wait-Gui {$null -ne $script:GuiActive -and $script:GuiActive.Item.Snapshot.Bytes -gt 100000}
        $first=$script:GuiActive.Item;$id=[string]$first.Record.Id
        $firstCard=$script:GuiCards[$id]
        Assert-Gui ($firstCard.PauseButton.Tag.Id -eq $id) 'Task action tags target their own model'
        Click-OwnButton $firstCard.PauseButton
        Wait-Gui {$first.State -eq 'Paused'}
        $bytes=$first.Snapshot.Bytes
        for($i=0;$i -lt 12;$i++){Update-GuiTasks;Render-GuiTasks;Start-Sleep -Milliseconds 100}
        Assert-Gui ($first.Snapshot.Bytes -eq $bytes) 'WPF pause event reaches engine and stabilizes real bytes'
        Assert-Gui (@($script:GuiItems|Where-Object State -eq 'Waiting').Count -eq 1) 'Paused current task keeps the next task queued'
        Click-OwnButton $firstCard.ResumeButton
        Wait-Gui {$first.State -eq 'Downloading' -and $first.Snapshot.Bytes -gt $bytes}
        Click-OwnButton $firstCard.StopButton
        Wait-Gui {$first.State -eq 'Incomplete'}
        Assert-Gui (Test-Path -LiteralPath (Join-Path $first.Record.JobFolder 'unfinished.session')) 'Stop preserves actual aria2 session'
        Wait-Gui {@($script:GuiItems|Where-Object State -eq 'Completed').Count -eq 1}
        Click-OwnButton $firstCard.ResumeButton
        Wait-Gui {$first.State -eq 'Completed' -and $null -eq $script:GuiActive}
        foreach($item in $script:GuiItems){
            $files=@(Get-TaskFiles $item.Record.OutputDir)
            Assert-Gui ($files.Count -eq 1 -and (Get-LocalSha256 $files[0].FullName) -eq $ExpectedHash) 'Final resumed/queued content matches source SHA256'
            Assert-Gui ((Get-TaskSnapshot $item.Record).Percent -eq 100) 'Completed persisted GUI progress reloads as 100 percent'
        }
        $script:Sha256=''
        $script:GuiControls.UrlBox.Text=$UnknownSource;Click-OwnButton $script:GuiControls.StartButton
        Wait-Gui {$null -ne $script:GuiActive -and $script:GuiActive.Item.Snapshot.Bytes -gt 50000}
        $unknown=$script:GuiActive.Item
        Assert-Gui (-not $unknown.Snapshot.Known -and $null -eq $unknown.Snapshot.Percent) 'Real chunked transfer shows unknown length rather than fabricated percentage'
        Wait-Gui {$unknown.State -eq 'Completed' -and $null -eq $script:GuiActive}
        Assert-Gui ((Get-LocalSha256 (@(Get-TaskFiles $unknown.Record.OutputDir)[0].FullName)) -eq $ExpectedHash) 'Unknown-length transfer completes with full hash identity'
        $script:GuiControls.UrlBox.Text=$MissingSource;Click-OwnButton $script:GuiControls.StartButton
        Wait-Gui {@($script:GuiItems|Where-Object State -eq 'Failed').Count -gt 0 -and $null -eq $script:GuiActive}
        Assert-Gui (@($script:GuiItems|Where-Object {$_.Record.Source -eq $MissingSource -and $_.Record.Status -eq 'Completed'}).Count -eq 0) 'HTTP errors never create a completed task'
        foreach($btSource in @($TorrentSource,$MagnetSource)) {
            if(-not $btSource){continue}
            $script:GuiControls.UrlBox.Text=$btSource;Click-OwnButton $script:GuiControls.StartButton
            Wait-Gui {@($script:GuiItems|Where-Object {$_.Record.Source -eq $btSource -and $_.State -eq 'Completed'}).Count -eq 1 -and $null -eq $script:GuiActive} 45
            $btItem=@($script:GuiItems|Where-Object {$_.Record.Source -eq $btSource})[0]
            $payload=Join-Path $btItem.Record.OutputDir 'fixture-seed.bin'
            Assert-Gui ((Test-Path -LiteralPath $payload) -and (Get-LocalSha256 $payload) -eq $ExpectedHash) 'WPF torrent/magnet completes actual private payload, not only metadata'
        }
    }
    Assert-Gui (-not $window.IsVisible) 'All own-control events and transfer tests ran without desktop input'
    @{passed=$true;kind='Headless WPF own-control events, offscreen rendering and optional real local transfer';checks=@($evidence);network_requested=[bool]$NetworkSource} |
        ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $WorkRoot 'test-evidence.json') -Encoding UTF8
    Write-Output ('PASS: WPF checks; '+$WorkRoot)
}finally{
    $script:GuiTimer.Stop();Close-GuiController;$script:GuiAllowClose=$true;$window.Close()
}
