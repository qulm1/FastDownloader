# Desktop layout. Backend task selection, validation and engine control live in DownloadWindow.ps1.
$script:FilterDirty=$true
$script:StateFilter='All'
$script:CategoryFilter='All'
$script:NavButtons=New-Object System.Collections.ArrayList
$script:Blue=[Drawing.Color]::FromArgb(52,120,246)
$script:Ink=[Drawing.Color]::FromArgb(34,43,61)
$script:Muted=[Drawing.Color]::FromArgb(126,135,152)
$script:Paper=[Drawing.Color]::FromArgb(247,249,252)

function Wrap-Input($TextBox) {
    $surface=New-Object FastDownloader.SurfacePanel
    $surface.Dock='Fill'; $surface.Padding=New-Object Windows.Forms.Padding(13,10,13,8)
    $surface.BackColor=[Drawing.Color]::White
    $TextBox.BorderStyle='None'; $TextBox.Dock='Fill'; $TextBox.BackColor=[Drawing.Color]::White
    $surface.Controls.Add($TextBox)
    return $surface
}

function New-Label([string]$Text,[int]$Size=10,[bool]$Bold=$false) {
    $label=New-Object Windows.Forms.Label
    $label.Text=$Text; $label.Dock='Fill'; $label.ForeColor=$script:Ink
    $weight=[Drawing.FontStyle]::Regular; if ($Bold) { $weight=[Drawing.FontStyle]::Bold }
    $label.Font=New-Object Drawing.Font('Microsoft YaHei UI',$Size,$weight)
    $label.TextAlign='MiddleLeft'
    return $label
}
function New-ModernButton([string]$Text,[int]$Width=90,[bool]$Primary=$false) {
    $button=New-Object FastDownloader.ModernButton
    $button.Text=$Text; $button.Width=$Width; $button.Height=40
    $button.Margin=New-Object Windows.Forms.Padding(0,0,8,0)
    $button.BackColor=$script:Paper; $button.ForeColor=$script:Ink
    if ($Primary) { $button.BackColor=$script:Blue; $button.ForeColor=[Drawing.Color]::White }
    return $button
}
function Get-ItemCategory($Item) {
    $extension=[IO.Path]::GetExtension([string]$Item.Row.Cells['Name'].Value).ToLowerInvariant()
    if ($extension -in @('.mp4','.mkv','.avi','.webm','.mov','.m4v')) { return 'Video' }
    if ($extension -in @('.mp3','.flac','.wav','.aac','.ogg','.m4a')) { return 'Audio' }
    if ($extension -in @('.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.epub','.csv')) { return 'Document' }
    if ($extension -in @('.png','.jpg','.jpeg','.webp','.gif','.bmp','.svg','.avif')) { return 'Image' }
    if ($extension -in @('.zip','.rar','.7z','.gz','.bz2','.tar','.xz')) { return 'Archive' }
    return 'Other'
}
function Test-StateFilter($Item,[string]$Filter) {
    switch ($Filter) {
        'Active' { return $Item.State -in @('Downloading','Starting','Waiting') }
        'Completed' { return $Item.State -eq 'Completed' }
        'Paused' { return $Item.State -eq 'Paused' }
        'Incomplete' { return $Item.State -in @('Incomplete','Failed') }
        default { return $true }
    }
}
function Refresh-TaskView {
    $query=$searchBox.Text.Trim()
    $selected=Get-SelectedItem
    $grid.CurrentCell=$null
    foreach ($item in $script:Items) {
        $visible=(Test-StateFilter $item $script:StateFilter)
        if ($script:CategoryFilter -ne 'All' -and (Get-ItemCategory $item) -ne $script:CategoryFilter) { $visible=$false }
        if ($query -and ([string]$item.Row.Cells['Name'].Value).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0 -and
            $item.Record.OutputDir.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0) { $visible=$false }
        $item.Row.Visible=$visible
    }
    if ($null -ne $selected -and $selected.Row.Visible) { $selected.Row.Selected=$true }
    elseif ($grid.Rows.Count -gt 0) { foreach ($row in $grid.Rows) { if ($row.Visible) { $row.Selected=$true; break } } }
    foreach ($nav in $script:NavButtons) {
        if ($nav.Group -eq 'State') { $count=@($script:Items | Where-Object { Test-StateFilter $_ $nav.Key }).Count; $isSelected=($script:StateFilter -eq $nav.Key) }
        else { $count=@($script:Items | Where-Object { $nav.Key -eq 'All' -or (Get-ItemCategory $_) -eq $nav.Key }).Count; $isSelected=($script:CategoryFilter -eq $nav.Key) }
        $nav.Button.Text=$nav.Label; $nav.Button.Badge=[string]$count
        $nav.Button.AccessibleName=$nav.Label+' '+$count
        $nav.Button.BackColor=$script:Paper; $nav.Button.ForeColor=$script:Muted
        if ($isSelected) { $nav.Button.BackColor=[Drawing.Color]::FromArgb(231,239,255); $nav.Button.ForeColor=$script:Blue }
    }
    $empty.Visible=(@($script:Items | Where-Object { $_.Row.Visible }).Count -eq 0)
    $empty.Text="还没有下载任务`n`n点击「新建下载」，开始保存你的第一个文件"
    if ($script:Items.Count -gt 0) { $empty.Text="没有匹配的任务`n`n试试其他分类，或清空搜索内容" }
    $script:FilterDirty=$false
    Update-TaskActions
}

function Update-TaskActions {
    $item=Get-SelectedItem
    $pause.Enabled=($null -ne $item -and $item.State -in @('Downloading','Waiting'))
    $resumeButton.Enabled=($null -ne $item -and $item.State -in @('Paused','Incomplete','Failed'))
    $stop.Enabled=($null -ne $item -and $item.State -in @('Starting','Downloading','Waiting','Paused'))
    $open.Enabled=($null -ne $item)
}

$form=New-Object Windows.Forms.Form
$form.Text='极速下载助手'
$form.Size=New-Object Drawing.Size(1280,820)
$form.MinimumSize=New-Object Drawing.Size(1000,720)
$form.StartPosition='CenterScreen'
$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10)
$form.BackColor=[Drawing.Color]::White
$form.AutoScaleMode='Dpi'; $form.KeyPreview=$true
$shell=New-Object Windows.Forms.TableLayoutPanel
$shell.Dock='Fill'; $shell.ColumnCount=2; $shell.RowCount=1; $shell.Margin=0; $shell.Padding=0
[void]$shell.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,216)))
[void]$shell.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
$form.Controls.Add($shell)

$sidebar=New-Object Windows.Forms.FlowLayoutPanel
$sidebar.Dock='Fill'; $sidebar.BackColor=$script:Paper; $sidebar.FlowDirection='TopDown'; $sidebar.WrapContents=$false
$sidebar.Padding=New-Object Windows.Forms.Padding(16,18,16,8); $sidebar.AutoScroll=$true
$shell.Controls.Add($sidebar,0,0)
$brand=New-Label '极速下载' 17 $true
$brand.Dock='None'; $brand.Width=180; $brand.Height=52; $brand.ForeColor=$script:Ink
$sidebar.Controls.Add($brand)
function Add-NavHeading([string]$Text) {
    $label=New-Label $Text 9
    $label.Dock='None'; $label.Width=180; $label.Height=36; $label.ForeColor=$script:Muted
    $label.Margin=New-Object Windows.Forms.Padding(4,8,0,0)
    $sidebar.Controls.Add($label)
}
function Add-Nav([string]$Label,[string]$Key,[string]$Group) {
    $button=New-ModernButton $Label 178
    $button.Height=40; $button.Margin=New-Object Windows.Forms.Padding(0,2,0,2)
    $button.TextAlign='MiddleLeft'; $button.Glyph=$Key
    if ($Group -eq 'Category' -and $Key -eq 'All') { $button.Glyph='Folder' }
    $nav=[pscustomobject]@{Label=$Label;Key=$Key;Group=$Group;Button=$button}
    $button.Tag=$nav
    $button.Add_Click({
        $nav=$this.Tag
        if ($nav.Group -eq 'State') { $script:StateFilter=$nav.Key } else { $script:CategoryFilter=$nav.Key }
        Refresh-TaskView
    })
    $sidebar.Controls.Add($button); [void]$script:NavButtons.Add($nav)
}
Add-NavHeading '任务状态'
Add-Nav '全部任务' 'All' 'State'
Add-Nav '下载中' 'Active' 'State'
Add-Nav '已完成' 'Completed' 'State'
Add-Nav '已暂停' 'Paused' 'State'
Add-Nav '待恢复 / 失败' 'Incomplete' 'State'
Add-NavHeading '文件分类'
Add-Nav '全部文件' 'All' 'Category'
Add-Nav '视频' 'Video' 'Category'
Add-Nav '音频' 'Audio' 'Category'
Add-Nav '文档' 'Document' 'Category'
Add-Nav '图片' 'Image' 'Category'
Add-Nav '压缩包' 'Archive' 'Category'
Add-Nav '其他' 'Other' 'Category'

$content=New-Object Windows.Forms.TableLayoutPanel
$content.Dock='Fill'; $content.ColumnCount=1; $content.RowCount=5; $content.Padding=New-Object Windows.Forms.Padding(28,20,28,12)
foreach ($height in @(56,52)) { [void]$content.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$height))) }
[void]$content.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$content.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,6)))
[void]$content.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,46)))
$shell.Controls.Add($content,1,0)
$toolbar=New-Object Windows.Forms.TableLayoutPanel
$toolbar.Dock='Fill'; $toolbar.ColumnCount=3; $toolbar.RowCount=1
[void]$toolbar.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$toolbar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,158)))
[void]$toolbar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$toolbar.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,232)))
$newDownload=New-ModernButton '新建下载' 140 $true
$newDownload.Glyph='Plus'
$toolbar.Controls.Add($newDownload,0,0)
$searchPanel=New-Object FastDownloader.SurfacePanel
$searchPanel.BackColor=$script:Paper; $searchPanel.Height=40; $searchPanel.Dock='Top'; $searchPanel.Padding=New-Object Windows.Forms.Padding(14,9,12,7)
$searchBox=New-Object FastDownloader.HintTextBox
$searchBox.Hint='搜索任务'; $searchPanel.BorderColor=$script:Paper
$searchBox.BorderStyle='None'; $searchBox.BackColor=$script:Paper; $searchBox.Dock='Fill'; $searchBox.AccessibleName='搜索任务'
$searchPanel.Controls.Add($searchBox); $toolbar.Controls.Add($searchPanel,1,0)
$toolbarTools=New-Object Windows.Forms.FlowLayoutPanel
$toolbarTools.Dock='Fill'; $toolbarTools.FlowDirection='RightToLeft'; $toolbarTools.WrapContents=$false
$open=New-ModernButton '打开目录' 96
$chooseTop=New-ModernButton '导入文件' 96
$toolbarTools.Controls.Add($open); $toolbarTools.Controls.Add($chooseTop)
$toolbar.Controls.Add($toolbarTools,2,0)
$content.Controls.Add($toolbar,0,0)
$headingLine=New-Object Windows.Forms.TableLayoutPanel
$headingLine.Dock='Fill'; $headingLine.ColumnCount=2; $headingLine.RowCount=1
[void]$headingLine.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$headingLine.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$headingLine.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,300)))
$heading=New-Label '下载' 20 $true
$heading.Margin=New-Object Windows.Forms.Padding(0)
$headingLine.Controls.Add($heading,0,0)
$actions=New-Object Windows.Forms.FlowLayoutPanel
$actions.Dock='Fill'; $actions.FlowDirection='RightToLeft'; $actions.WrapContents=$false
$stop=New-ModernButton '停止' 90
$resumeButton=New-ModernButton '继续' 90
$pause=New-ModernButton '暂停' 90
$stop.Glyph='Stop'; $resumeButton.Glyph='Resume'; $pause.Glyph='Paused'
$actions.Controls.Add($stop); $actions.Controls.Add($resumeButton); $actions.Controls.Add($pause)
$headingLine.Controls.Add($actions,1,0); $content.Controls.Add($headingLine,0,1)
$listPanel=New-Object Windows.Forms.Panel
$listPanel.Dock='Fill'; $listPanel.BackColor=[Drawing.Color]::White
$grid=New-Object FastDownloader.TaskGrid
$grid.Dock='Fill'; $grid.AllowUserToAddRows=$false; $grid.AllowUserToDeleteRows=$false; $grid.AllowUserToResizeRows=$false
$grid.ReadOnly=$true; $grid.MultiSelect=$false; $grid.SelectionMode='FullRowSelect'; $grid.RowHeadersVisible=$false
$grid.AutoGenerateColumns=$false; $grid.BorderStyle='None'; $grid.BackgroundColor=[Drawing.Color]::White
$grid.GridColor=[Drawing.Color]::FromArgb(240,243,248); $grid.CellBorderStyle='SingleHorizontal'; $grid.ColumnHeadersBorderStyle='None'
$grid.EnableHeadersVisualStyles=$false; $grid.ColumnHeadersHeight=44; $grid.ColumnHeadersHeightSizeMode='DisableResizing'
$grid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::White; $grid.ColumnHeadersDefaultCellStyle.ForeColor=$script:Muted
$grid.ColumnHeadersDefaultCellStyle.Padding=New-Object Windows.Forms.Padding(10,0,0,0)
$grid.DefaultCellStyle.Padding=New-Object Windows.Forms.Padding(10,0,0,0)
$grid.DefaultCellStyle.ForeColor=$script:Ink; $grid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(240,245,255)
$grid.DefaultCellStyle.SelectionForeColor=$script:Ink; $grid.RowTemplate.Height=72; $grid.AccessibleName='下载任务'
foreach ($column in @(@('Name','文件名',240),@('Status','状态',100),@('Progress','进度',130),@('Speed','速度',105),@('Done','已下载',95),@('Total','总大小',95),@('Eta','剩余时间',100),@('Folder','保存位置',200))) {
    $c=New-Object Windows.Forms.DataGridViewTextBoxColumn
    $c.Name=$column[0]; $c.HeaderText=$column[1]; $c.Width=$column[2]; $c.SortMode='NotSortable'
    if ($column[0] -eq 'Name') { $c.AutoSizeMode='Fill'; $c.MinimumWidth=200 }
    if ($column[0] -eq 'Folder') { $c.Visible=$false }
    [void]$grid.Columns.Add($c)
}
$listPanel.Controls.Add($grid)
$empty=New-Label "还没有下载任务`n`n点击「新建下载」，开始保存你的第一个文件" 12
$empty.AutoSize=$false; $empty.Dock='None'; $empty.Size=New-Object Drawing.Size(500,110); $empty.TextAlign='MiddleCenter'; $empty.ForeColor=$script:Muted
$empty.Anchor='None'; $listPanel.Controls.Add($empty); $empty.BringToFront()
$listPanel.Add_Resize({ $empty.Left=[Math]::Max(0,($listPanel.ClientSize.Width-$empty.Width)/2); $empty.Top=[Math]::Max(70,($listPanel.ClientSize.Height-$empty.Height)/2) })
$content.Controls.Add($listPanel,0,2)
$progress=New-Object Windows.Forms.ProgressBar
$progress.Dock='Fill'; $progress.Style='Continuous'; $content.Controls.Add($progress,0,3)
$status=New-Label '就绪  ·  双击任务打开目录  ·  Ctrl+N 新建 / Ctrl+F 搜索' 9
$status.ForeColor=$script:Muted; $status.AutoEllipsis=$true; $content.Controls.Add($status,0,4)

# A dedicated new-download dialog keeps the main task list uncluttered.
$newDialog=New-Object Windows.Forms.Panel
$newDialog.AutoScroll=$true; $newDialog.Dock='Fill'; $newDialog.BackColor=[Drawing.Color]::FromArgb(234,238,245); $newDialog.Visible=$false
$form.Controls.Add($newDialog)
$dialogCard=New-Object FastDownloader.SurfacePanel
$dialogCard.Radius=16
$dialogCard.BackColor=[Drawing.Color]::White; $dialogCard.Size=New-Object Drawing.Size(760,560)
$dialogCard.Anchor='None'; $newDialog.Controls.Add($dialogCard)
$newDialog.Add_Resize({ $dialogCard.Left=($newDialog.ClientSize.Width-$dialogCard.Width)/2; $dialogCard.Top=[Math]::Max(12,($newDialog.ClientSize.Height-$dialogCard.Height)/2) })
. (Join-Path $PSScriptRoot 'DownloadDialog.ps1')
function Show-DownloadDialog {
    $dialogError.Text=''; $newDialog.Visible=$true; $newDialog.BringToFront()
    $dialogCard.Left=($newDialog.ClientSize.Width-$dialogCard.Width)/2
    $dialogCard.Top=[Math]::Max(12,($newDialog.ClientSize.Height-$dialogCard.Height)/2)
    $inputBox.Focus()
}
$newDownload.Add_Click({ Show-DownloadDialog })
$cancel.Add_Click({ $newDialog.Visible=$false })
$add.Add_Click({ try { Add-Inputs @($inputBox.Text -split '\r?\n'); Refresh-TaskView } catch { Show-UiError $_.Exception.Message } })
$browse.Add_Click({
    $dialog=New-Object Windows.Forms.FolderBrowserDialog
    try { $dialog.SelectedPath=$folder.Text; if ($dialog.ShowDialog($newDialog) -eq 'OK') { $folder.Text=$dialog.SelectedPath } } finally { $dialog.Dispose() }
})
$choose.Add_Click({
    $dialog=New-Object Windows.Forms.OpenFileDialog
    $dialog.Multiselect=$true; $dialog.Filter='任务文件|*.torrent;*.meta4;*.metalink;*.txt;*.csv;*.json;*.url;*.urls;*.lst|所有文件|*.*'
    try { if ($dialog.ShowDialog($newDialog) -eq 'OK') { $inputBox.AppendText(($dialog.FileNames -join [Environment]::NewLine)+[Environment]::NewLine) } } finally { $dialog.Dispose() }
})
$chooseTop.Add_Click({ Show-DownloadDialog; $choose.Focus() })
$inputBox.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect=[Windows.Forms.DragDropEffects]::Copy } })
$inputBox.Add_DragDrop({ $inputBox.AppendText(($_.Data.GetData([Windows.Forms.DataFormats]::FileDrop) -join [Environment]::NewLine)+[Environment]::NewLine) })
$pause.Add_Click({
    $item=Get-SelectedItem; if ($null -eq $item) { return }
    if ($null -ne $script:Active -and $script:Active.Item -eq $item) {
        if ($null -eq $script:Active.StopAt -and $null -eq $script:Active.Command) { $script:Active.Command=$script:Active.Engine.CommandAsync('aria2.pauseAll') }
    } elseif ($item.State -eq 'Waiting') { try { Save-WaitingRecord $item 'Paused'; Set-ItemState $item 'Paused' } catch { Show-UiError '任务记录暂时无法保存，请检查权限或其他窗口。' } }
})
$resumeButton.Add_Click({
    $item=Get-SelectedItem; if ($null -eq $item) { return }
    if ($null -ne $script:Active -and $script:Active.Item -eq $item) {
        if ($null -eq $script:Active.StopAt -and $null -eq $script:Active.Command) { $script:Active.Command=$script:Active.Engine.CommandAsync('aria2.unpauseAll') }
    } elseif ($item.State -in @('Paused','Incomplete','Failed')) { Set-ItemState $item 'Waiting' }
})
$stop.Add_Click({
    $item=Get-SelectedItem; if ($null -eq $item) { return }
    if ($null -ne $script:Active -and $script:Active.Item -eq $item) { Stop-Active 'Incomplete' }
    elseif ($item.State -in @('Waiting','Paused')) { try { Save-WaitingRecord $item 'Incomplete'; Set-ItemState $item 'Incomplete' } catch { Show-UiError '任务记录暂时无法保存。' } }
})
$open.Add_Click({
    $item=Get-SelectedItem
    if ($null -ne $item -and (Test-Path -LiteralPath $item.Record.OutputDir -PathType Container)) { [void][Diagnostics.Process]::Start('explorer.exe',[FastDownloader.WindowEngine]::Quote($item.Record.OutputDir)) }
})
$grid.Add_CellDoubleClick({ if ($_.RowIndex -ge 0) { $open.PerformClick() } })
$grid.Add_SelectionChanged({ Update-TaskActions })
$searchBox.Add_TextChanged({ Refresh-TaskView })
$form.Add_KeyDown({
    if ($newDialog.Visible) {
        if ($_.KeyCode -eq 'Escape') { $_.Handled=$true; $_.SuppressKeyPress=$true; $newDialog.Visible=$false }
        elseif ($_.Control -and $_.KeyCode -eq 'Return') { $_.Handled=$true; $_.SuppressKeyPress=$true; $add.PerformClick() }
        return
    }
    if ($_.Control -and $_.KeyCode -in @('N','F','P','R')) {
        $_.Handled=$true; $_.SuppressKeyPress=$true
        switch ([string]$_.KeyCode) { 'N' {$newDownload.PerformClick()} 'F' {$searchBox.Focus()} 'P' {$pause.PerformClick()} 'R' {$resumeButton.PerformClick()} }
    }
})
$tips=New-Object Windows.Forms.ToolTip
$tips.SetToolTip($searchBox,'搜索文件名或保存路径（Ctrl+F）')
$tips.SetToolTip($pause,'暂停选中任务（Ctrl+P）')
$tips.SetToolTip($resumeButton,'继续选中任务（Ctrl+R）')
$tips.SetToolTip($stop,'停止并保存断点，不删除文件')
$tips.SetToolTip($connectionBox,'HTTP 连接上限；8 为默认值，连接更多不保证更快')
$form.Add_FormClosing({
    if ($script:ReadyToClose) { return }
    if ($null -ne $script:Active) {
        $_.Cancel=$true; $script:Closing=$true; $actions.Enabled=$false; $newDownload.Enabled=$false; $chooseTop.Enabled=$false
        $status.Text='正在保存下载断点，请稍候…'; Stop-Active 'Incomplete'
    }
})
$timer=New-Object Windows.Forms.Timer
$timer.Interval=200
$timer.Add_Tick({ Update-Window; if ($script:FilterDirty -and -not $script:Closing) { Refresh-TaskView; Update-TaskActions } })
$form.Add_Shown({ Refresh-TaskView; $timer.Start() })
if ($LayoutOnly) { return } # Developer tests create controls without showing any window.
try {
    if (Test-Path -LiteralPath $script:JobsRoot) {
        foreach ($file in Get-ChildItem -LiteralPath $script:JobsRoot -Filter task.json -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 500) {
            try { $null=Add-RecordRow (Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json) }
            catch { $status.Text='已跳过损坏记录，原文件已保留。' }
        }
    }
    [Windows.Forms.Application]::Run($form)
} finally {
    $timer.Stop(); $timer.Dispose(); $tips.Dispose(); $newDialog.Dispose()
    if ($null -ne $script:Active) {
        try { if (-not $script:Active.Engine.Process.HasExited) { $script:Active.Engine.Process.Kill() } } catch { }
        $script:Active.Engine.Dispose(); $script:Active.Lock.Dispose()
    }
    $form.Dispose()
}
