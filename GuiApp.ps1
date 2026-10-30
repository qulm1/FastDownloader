Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
# Dot-sourcing the CLI assigns its LibraryOnly parameter in this scope, too.
$script:GuiLoadOnly=[bool]$LibraryOnly
$requestedDestination=$DownloadDir
$requestedState=$StateDir
$script:GuiRoot=$PSScriptRoot
. (Join-Path $PSScriptRoot 'FastDownload.ps1') -LibraryOnly -StateDir $requestedState -DownloadDir $requestedDestination
$script:GuiEnginePath=$script:Engine
$script:GuiDestination=$(if($requestedDestination){[IO.Path]::GetFullPath($requestedDestination)}else{Get-DefaultDownloadDir})
. (Join-Path $PSScriptRoot 'GuiTasks.ps1')
. (Join-Path $PSScriptRoot 'GuiView.ps1')
$script:GuiCards=@{}
$script:GuiBrushes=@{}
$script:GuiAllowClose=$false
$script:GuiTickBusy=$false

function Get-GuiStatusText($Item) {
    switch($Item.State) {
        'Completed' {return '已完成'}
        'Paused' {return '已暂停'}
        'Incomplete' {return '待恢复'}
        'Failed' {return '失败，可重试'}
        'Waiting' {return '排队中'}
        'Starting' {return '正在连接'}
        'Stopping' {return '正在保存'}
        default {
            if($Item.Snapshot.Known -and $null -ne $Item.Snapshot.Percent){return ('下载中 {0:0.#}%' -f $Item.Snapshot.Percent)}
            return '下载中，大小未知'
        }
    }
}
function Get-GuiMetaText($Item) {
    if($Item.Error){return $Item.Error}
    $snapshot=$Item.Snapshot
    $text=Format-ByteSize ([double]$snapshot.Bytes)
    if($snapshot.Known){$text+=' / '+(Format-ByteSize ([double]$snapshot.Total))}
    elseif($Item.State -ne 'Completed'){$text+=' · 总大小未知'}
    if($snapshot.Speed -gt 0 -and $Item.State -eq 'Downloading') {
        $text+=' · '+(Format-ByteSize ([double]$snapshot.Speed))+'/s'
        if($snapshot.Known -and $snapshot.Total -gt $snapshot.Bytes) {$text+=' · 剩余 '+(Format-Duration (($snapshot.Total-$snapshot.Bytes)/$snapshot.Speed))}
    }
    if($Item.State -eq 'Completed' -and $Item.Record.Sha256){$text+=' · SHA-256 已校验'}
    return $text
}
function Get-GuiBrush([string]$Color) {
    if(-not $script:GuiBrushes.ContainsKey($Color)) {
        $brush=(New-Object Windows.Media.BrushConverter).ConvertFromString($Color)
        $brush.Freeze();$script:GuiBrushes[$Color]=$brush
    }
    return $script:GuiBrushes[$Color]
}
function Test-GuiFilter($Item,[int]$Filter) {
    switch($Filter) {
        1 {return $Item.State -in @('Downloading','Starting','Waiting','Stopping')}
        2 {return $Item.State -eq 'Paused'}
        3 {return $Item.State -eq 'Completed'}
        4 {return $Item.State -in @('Incomplete','Failed')}
        default {return $true}
    }
}
function New-GuiCard($Item) {
    $card=[Windows.Markup.XamlReader]::Parse((Get-TaskCardXaml))
    $parts=@{Root=$card}
    foreach($name in @('Title','Chip','ChipText','Meta','Bar','PauseButton','ResumeButton','StopButton','OpenButton')) {$parts[$name]=$card.FindName($name)}
    $parts.Bar.Style=$script:GuiWindow.Resources['SlimProgress']
    foreach($pair in @(@('PauseButton','Pause'),@('ResumeButton','Resume'),@('StopButton','Stop'),@('OpenButton','Open'))) {
        $button=$parts[$pair[0]]
        $button.Style=$script:GuiWindow.Resources['QuietButton']
        $button.Tag=[pscustomobject]@{Id=$Item.Record.Id;Action=$pair[1]}
        $button.Add_Click({
            param($sender,$eventArgs)
            try {
                if($sender.Tag.Action -eq 'Open') {
                    $items=@($script:GuiItems | Where-Object {$_.Record.Id -eq $sender.Tag.Id})
                    if($items.Count -gt 0 -and (Test-Path -LiteralPath $items[0].Record.OutputDir -PathType Container)) {
                        $info=New-Object Diagnostics.ProcessStartInfo
                        $info.FileName='explorer.exe';$info.Arguments='"'+$items[0].Record.OutputDir+'"';$info.UseShellExecute=$true
                        [void][Diagnostics.Process]::Start($info)
                    }
                } else {Set-GuiAction $sender.Tag.Id $sender.Tag.Action}
                Render-GuiTasks
            } catch {$script:GuiError=$_.Exception.Message;Render-GuiTasks}
        })
    }
    $script:GuiControls.TaskPanel.Children.Add($card)|Out-Null
    return $parts
}
function Render-GuiTasks {
    $filter=$script:GuiControls.FilterBox.SelectedIndex
    $visible=0
    foreach($item in $script:GuiItems) {
        $id=[string]$item.Record.Id
        if(-not $script:GuiCards.ContainsKey($id)) {$script:GuiCards[$id]=New-GuiCard $item}
        $card=$script:GuiCards[$id]
        $show=Test-GuiFilter $item $filter
        $card.Root.Visibility=$(if($show){'Visible'}else{'Collapsed'})
        if($show){$visible++}
        $card.Title.Text=$item.Name
        $card.ChipText.Text=Get-GuiStatusText $item
        $card.Meta.Text=Get-GuiMetaText $item
        $card.Root.ToolTip=$item.Record.OutputDir
        $card.Chip.Background=Get-GuiBrush '#EAF3FE';$card.ChipText.Foreground=Get-GuiBrush '#0071E3'
        if($item.State -eq 'Completed') {$card.Chip.Background=Get-GuiBrush '#E8F6EE';$card.ChipText.Foreground=Get-GuiBrush '#218457'}
        elseif($item.State -in @('Incomplete','Failed','Paused')) {$card.Chip.Background=Get-GuiBrush '#F0F0F4';$card.ChipText.Foreground=Get-GuiBrush '#66666C'}
        $card.Bar.IsIndeterminate=(-not $item.Snapshot.Known -and $item.State -in @('Starting','Downloading'))
        $card.Bar.Value=$(if($null -ne $item.Snapshot.Percent){[double]$item.Snapshot.Percent}else{0})
        $card.Bar.Visibility=$(if($item.State -eq 'Completed'){'Collapsed'}else{'Visible'})
        $card.PauseButton.IsEnabled=($item.State -in @('Downloading','Waiting') -and -not $script:GuiClosing)
        $card.ResumeButton.IsEnabled=($item.State -in @('Paused','Incomplete','Failed') -and -not $script:GuiClosing)
        $card.StopButton.IsEnabled=($item.State -in @('Starting','Downloading','Waiting','Paused') -and -not $script:GuiClosing)
        $card.PauseButton.Visibility=$(if($item.State -in @('Downloading','Waiting')){'Visible'}else{'Collapsed'})
        $card.ResumeButton.Visibility=$(if($item.State -in @('Paused','Incomplete','Failed')){'Visible'}else{'Collapsed'})
        $card.StopButton.Visibility=$(if($item.State -in @('Starting','Downloading','Waiting','Paused')){'Visible'}else{'Collapsed'})
    }
    $script:GuiControls.EmptyHint.Text=$(if($script:GuiItems.Count){'这个分类还没有任务'}else{'还没有任务。粘贴链接或拖入任务文件开始。'})
    $script:GuiControls.EmptyHint.Visibility=$(if($visible -eq 0){'Visible'}else{'Collapsed'})
    $script:GuiControls.FooterInfo.Text=('共 {0} 个任务 · {1} 项显示' -f $script:GuiItems.Count,$visible)
    $script:GuiControls.Message.Text=$script:GuiError
    $script:GuiControls.Placeholder.Visibility=$(if([string]::IsNullOrWhiteSpace($script:GuiControls.UrlBox.Text)){'Visible'}else{'Collapsed'})
    $script:GuiControls.StartButton.IsEnabled=(-not $script:GuiClosing -and -not [string]::IsNullOrWhiteSpace($script:GuiControls.UrlBox.Text))
}
function Start-GuiInput {
    try {
        $script:GuiError=''
        Add-GuiInputs @($script:GuiControls.UrlBox.Text -split '\r?\n') $script:GuiControls.DestinationBox.Text ([bool]$script:GuiControls.NewTaskCheck.IsChecked)
        $script:GuiControls.UrlBox.Text=''
        Update-GuiTasks;Render-GuiTasks
    } catch {$script:GuiError=$_.Exception.Message;Render-GuiTasks}
}
function Initialize-GuiWindow {
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
    $script:GuiWindow=[Windows.Markup.XamlReader]::Parse((Get-GuiXaml))
    $script:GuiControls=@{}
    foreach($name in @('UrlBox','StartButton','TaskPanel','EmptyHint','FooterInfo','Message','Placeholder','Subtitle','DestinationBox','ChooseFolderButton','ImportButton','FilterBox','NewTaskCheck')) {
        $script:GuiControls[$name]=$script:GuiWindow.FindName($name)
    }
    $script:GuiControls.Subtitle.Text='每行一个链接 · Enter 开始 · Shift+Enter 换行 · 按顺序下载'
    $script:GuiControls.DestinationBox.Text=$script:GuiDestination
    $script:GuiControls.FilterBox.SelectedIndex=0
    $script:GuiControls.UrlBox.Add_TextChanged({Render-GuiTasks})
    $script:GuiControls.UrlBox.Add_PreviewKeyDown({
        param($sender,$eventArgs)
        if($eventArgs.Key -eq 'Return' -and -not ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift)) {
            $eventArgs.Handled=$true;Start-GuiInput
        }
    })
    $script:GuiControls.StartButton.Add_Click({Start-GuiInput})
    $script:GuiControls.FilterBox.Add_SelectionChanged({Render-GuiTasks})
    $script:GuiControls.ChooseFolderButton.Add_Click({
        $dialog=New-Object Windows.Forms.FolderBrowserDialog
        try {$dialog.SelectedPath=$script:GuiControls.DestinationBox.Text;if($dialog.ShowDialog() -eq 'OK'){$script:GuiControls.DestinationBox.Text=$dialog.SelectedPath}} finally {$dialog.Dispose()}
    })
    $script:GuiControls.ImportButton.Add_Click({
        $dialog=New-Object Windows.Forms.OpenFileDialog
        $dialog.Multiselect=$true;$dialog.Filter='种子及任务清单|*.torrent;*.meta4;*.metalink;*.txt;*.csv;*.json;*.url;*.urls;*.lst|所有文件|*.*'
        try {if($dialog.ShowDialog() -eq 'OK'){$script:GuiControls.UrlBox.Text=($dialog.FileNames -join [Environment]::NewLine)}}finally{$dialog.Dispose()}
    })
    $script:GuiWindow.Add_PreviewDragOver({param($sender,$eventArgs);$eventArgs.Effects=[Windows.DragDropEffects]::Copy;$eventArgs.Handled=$true})
    $script:GuiWindow.Add_Drop({
        param($sender,$eventArgs)
        if($eventArgs.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) {$script:GuiControls.UrlBox.Text=(@($eventArgs.Data.GetData([Windows.DataFormats]::FileDrop)) -join [Environment]::NewLine)}
        elseif($eventArgs.Data.GetDataPresent([Windows.DataFormats]::UnicodeText)) {$script:GuiControls.UrlBox.Text=[string]$eventArgs.Data.GetData([Windows.DataFormats]::UnicodeText)}
        $eventArgs.Handled=$true
    })
    $script:GuiTimer=New-Object Windows.Threading.DispatcherTimer
    $script:GuiTimer.Interval=[TimeSpan]::FromMilliseconds(300)
    $script:GuiTimer.Add_Tick({
        if($script:GuiTickBusy){return}
        $script:GuiTickBusy=$true
        try {
            Update-GuiTasks;Render-GuiTasks
            if($script:GuiClosing -and $null -eq $script:GuiActive) {$script:GuiAllowClose=$true;$script:GuiTimer.Stop();$script:GuiWindow.Close()}
        } finally {$script:GuiTickBusy=$false}
    })
    $script:GuiWindow.Add_Closing({
        param($sender,$eventArgs)
        if($script:GuiAllowClose){return}
        if($null -ne $script:GuiActive){$eventArgs.Cancel=$true;$script:GuiClosing=$true;Stop-GuiActive;$script:GuiError='正在保存断点，完成后自动退出。';Render-GuiTasks}
    })
    $script:GuiWindow.Add_Loaded({$script:GuiTimer.Start()})
    Render-GuiTasks
    return $script:GuiWindow
}

if(-not $script:GuiLoadOnly) {
    try {
        Read-GuiHistory
        $null=Initialize-GuiWindow
        $null=$script:GuiWindow.ShowDialog()
    } catch {
        Add-Type -AssemblyName PresentationFramework
        [void][Windows.MessageBox]::Show(('启动失败：'+$_.Exception.Message),'极速下载助手')
    } finally {
        if($null -ne (Get-Variable GuiTimer -Scope Script -ErrorAction SilentlyContinue)) {$script:GuiTimer.Stop()}
        Close-GuiController
    }
}
