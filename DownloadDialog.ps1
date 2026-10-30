# Progressive disclosure: URL and destination first, advanced settings on demand.
$dialogLayout=New-Object Windows.Forms.TableLayoutPanel
$dialogLayout.Dock='Fill'; $dialogLayout.BackColor=[Drawing.Color]::White
$dialogLayout.Padding=New-Object Windows.Forms.Padding(30,22,30,22)
$dialogLayout.ColumnCount=1; $dialogLayout.RowCount=11
foreach ($height in @(44,32,28,150,42,28,44,36,0,28,52)) { [void]$dialogLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$height))) }
$dialogCard.Padding=New-Object Windows.Forms.Padding(1)
$dialogCard.Controls.Add($dialogLayout)
$dialogTitleLine=New-Object Windows.Forms.TableLayoutPanel
$dialogTitleLine.Dock='Fill'; $dialogTitleLine.ColumnCount=2
[void]$dialogTitleLine.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$dialogTitleLine.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,36)))
$dialogTitleLine.Controls.Add((New-Label '新建下载' 21 $true),0,0)
$closeDialog=New-ModernButton '' 32
$closeDialog.Glyph='Close'; $closeDialog.BackColor=[Drawing.Color]::White; $closeDialog.AccessibleName='关闭新建下载'
$dialogTitleLine.Controls.Add($closeDialog,1,0)
$dialogLayout.Controls.Add($dialogTitleLine,0,0)
$dialogHint=New-Label '粘贴链接，剩下的交给极速下载。多个链接请分行填写。' 10
$dialogHint.ForeColor=$script:Muted; $dialogLayout.Controls.Add($dialogHint,0,1)
$dialogLayout.Controls.Add((New-Label '下载链接' 10),0,2)
$inputBox=New-Object Windows.Forms.TextBox
$inputBox.Multiline=$true; $inputBox.AcceptsReturn=$true; $inputBox.ScrollBars='Vertical'
$inputBox.AllowDrop=$true; $inputBox.AccessibleName='下载链接'
$inputBox.Font=New-Object Drawing.Font('Microsoft YaHei UI',11)
$dialogLayout.Controls.Add((Wrap-Input $inputBox),0,3)
$fileActions=New-Object Windows.Forms.FlowLayoutPanel
$fileActions.Dock='Fill'; $fileActions.Padding=New-Object Windows.Forms.Padding(0,4,0,0)
$choose=New-ModernButton '导入种子或任务清单' 200
$choose.Glyph='Folder'; $choose.ForeColor=$script:Blue; $choose.BackColor=[Drawing.Color]::White
$fileActions.Controls.Add($choose); $dialogLayout.Controls.Add($fileActions,0,4)
$dialogLayout.Controls.Add((New-Label '保存到' 10),0,5)
$folderLine=New-Object Windows.Forms.TableLayoutPanel
$folderLine.Dock='Fill'; $folderLine.ColumnCount=2; $folderLine.RowCount=1
[void]$folderLine.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$folderLine.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$folderLine.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,98)))
$folder=New-Object Windows.Forms.TextBox
$folder.Text=$DownloadDir; $folder.AccessibleName='保存目录'
$browse=New-ModernButton '浏览' 88
$browse.Glyph='Folder'
$folderLine.Controls.Add((Wrap-Input $folder),0,0); $folderLine.Controls.Add($browse,1,0)
$dialogLayout.Controls.Add($folderLine,0,6)
$advancedToggle=New-ModernButton '更多选项' 108
$advancedToggle.BackColor=[Drawing.Color]::White; $advancedToggle.ForeColor=$script:Muted; $advancedToggle.TextAlign='MiddleLeft'
$dialogLayout.Controls.Add($advancedToggle,0,7)
$advancedPanel=New-Object Windows.Forms.TableLayoutPanel
$advancedPanel.Dock='Fill'; $advancedPanel.ColumnCount=2; $advancedPanel.RowCount=3; $advancedPanel.Visible=$false
[void]$advancedPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,75)))
[void]$advancedPanel.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,25)))
foreach ($height in @(28,44,34)) { [void]$advancedPanel.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,$height))) }
$advancedPanel.Controls.Add((New-Label '重命名（可选，单文件链接）' 9),0,0)
$advancedPanel.Controls.Add((New-Label '连接上限' 9),1,0)
$renameBox=New-Object FastDownloader.HintTextBox
$renameBox.Hint='自动识别文件名'; $renameBox.AccessibleName='重命名'
$advancedPanel.Controls.Add((Wrap-Input $renameBox),0,1)
$connectionBox=New-Object Windows.Forms.ComboBox
$connectionBox.DropDownStyle='DropDownList'; $connectionBox.Dock='Fill'; $connectionBox.AccessibleName='连接数'
[void]$connectionBox.Items.AddRange(@('1','4','8','16')); $connectionBox.SelectedItem='8'
$advancedPanel.Controls.Add($connectionBox,1,1)
$newTaskBox=New-Object Windows.Forms.CheckBox
$newTaskBox.Text='另建独立任务（保留原任务）'; $newTaskBox.Dock='Fill'; $newTaskBox.ForeColor=$script:Muted
$advancedPanel.Controls.Add($newTaskBox,0,2); $advancedPanel.SetColumnSpan($newTaskBox,2)
$dialogLayout.Controls.Add($advancedPanel,0,8)
$dialogError=New-Label '' 9
$dialogError.ForeColor=[Drawing.Color]::FromArgb(192,71,65); $dialogError.AutoEllipsis=$true
$dialogLayout.Controls.Add($dialogError,0,9)
$dialogButtons=New-Object Windows.Forms.FlowLayoutPanel
$dialogButtons.Dock='Fill'; $dialogButtons.FlowDirection='RightToLeft'; $dialogButtons.Padding=New-Object Windows.Forms.Padding(0,6,0,0)
$add=New-ModernButton '开始下载' 148 $true
$add.Glyph='Download'
$cancel=New-ModernButton '取消' 90
$cancel.BackColor=[Drawing.Color]::White
$dialogButtons.Controls.Add($add); $dialogButtons.Controls.Add($cancel)
$dialogLayout.Controls.Add($dialogButtons,0,10)
$script:AdvancedExpanded=$false
function Set-AdvancedOptions([bool]$Expanded) {
    $script:AdvancedExpanded=$Expanded
    $advancedPanel.Visible=$Expanded
    $dialogLayout.RowStyles[8].Height=$(if ($Expanded) {112} else {0})
    $dialogCard.Height=$(if ($Expanded) {680} else {560})
    $advancedToggle.Text=$(if ($Expanded) {'收起选项'} else {'更多选项'})
    $dialogCard.Top=[Math]::Max(12,($newDialog.ClientSize.Height-$dialogCard.Height)/2)
}
$advancedToggle.Add_Click({ Set-AdvancedOptions (-not $script:AdvancedExpanded) })
$closeDialog.Add_Click({$newDialog.Visible=$false})
