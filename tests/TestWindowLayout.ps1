param([Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'
if ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($WorkRoot)) -notmatch '^(?i)D:\\$') { throw 'Use an isolated D: test directory.' }
if (Test-Path -LiteralPath $WorkRoot) { throw 'Choose a new evidence directory.' }
[void][IO.Directory]::CreateDirectory($WorkRoot)
$testRoot=[IO.Path]::GetFullPath($WorkRoot)
$project=Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'DownloadWindow.ps1') -LayoutOnly -StateDir (Join-Path $testRoot 'state') -DownloadDir (Join-Path $testRoot 'downloads')
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;
public static class OffscreenProbe {
    private static bool LocallyVisible(Control control) {
        // Visible returns false for every child of an unshown form. Inspect the
        // control's own visibility flag without showing or changing any window.
        var flags=BindingFlags.Static|BindingFlags.NonPublic;
        var field=typeof(Control).GetField("STATE_VISIBLE",flags);
        int visible=(int)field.GetRawConstantValue();
        return (bool)typeof(Control).GetMethod("GetState",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(control,new object[]{visible});
    }
    private static Bitmap Render(Control control) {
        var bitmap=new Bitmap(Math.Max(1,control.Width),Math.Max(1,control.Height));
        control.DrawToBitmap(bitmap,new Rectangle(0,0,bitmap.Width,bitmap.Height));
        using(var graphics=Graphics.FromImage(bitmap)) {
            graphics.SetClip(new Rectangle(0,0,control.ClientSize.Width,control.ClientSize.Height));
            // DrawToBitmap omits children of hidden parents. Render the actual
            // controls individually and composite them at their real layout bounds.
            for(int i=control.Controls.Count-1;i>=0;i--) {
                var child=control.Controls[i];
                if(!LocallyVisible(child)||child.Width<=0||child.Height<=0)continue;
                using(var image=Render(child))graphics.DrawImageUnscaled(image,child.Left,child.Top);
            }
        }
        return bitmap;
    }
    public static Bitmap PaintButton(Button button) {
        var image=new Bitmap(button.Width,button.Height);
        using(var graphics=Graphics.FromImage(image)) {
            graphics.Clear(Color.Black); // Simulate stale native pixels, not a blank canvas.
            var method=button.GetType().GetMethod("OnPaint",BindingFlags.Instance|BindingFlags.NonPublic);
            method.Invoke(button,new object[]{new PaintEventArgs(graphics,new Rectangle(0,0,image.Width,image.Height))});
        }
        return image;
    }
    public static void Layout(Control control) {
        var handle=control.Handle; // Create an unshown handle; never call Show/Activate.
        control.PerformLayout();
        foreach(Control child in control.Controls) Layout(child);
        control.PerformLayout();
    }
    public static void Save(Control control,string path) {
        Layout(control);
        using(var bitmap=Render(control)) {
            int blue=0,ink=0;
            for(int y=0;y<bitmap.Height;y+=2)for(int x=0;x<bitmap.Width;x+=2){var p=bitmap.GetPixel(x,y);if(p.B>210&&p.R<100&&p.G>80&&p.G<180)blue++;if(p.R<100&&p.G<110&&p.B<140)ink++;}
            bitmap.Save(path,System.Drawing.Imaging.ImageFormat.Png);
            if(blue<100||ink<30)throw new InvalidOperationException("Offscreen render is missing real controls or text: "+path+" blue="+blue+" ink="+ink);
        }
    }
}
'@ -ReferencedAssemblies System.dll,System.Drawing.dll,System.Windows.Forms.dll
$evidence=New-Object System.Collections.ArrayList
function Assert-Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw $Name }
    [void]$evidence.Add(@{name=$Name;passed=$true})
}
function Assert-InParent($Control,[string]$Name) {
    Assert-Check ($Control.Left -ge 0 -and $Control.Top -ge 0 -and $Control.Right -le $Control.Parent.ClientSize.Width -and $Control.Bottom -le $Control.Parent.ClientSize.Height) $Name
}
try {
    # Compile a deliberate negative control in memory. No product files are changed.
    $negative=[IO.File]::ReadAllText((Join-Path $project 'DesktopStyles.cs')).Replace('namespace FastDownloader {','namespace FastDownloaderNegative {').Replace('e.Graphics.Clear(Parent == null ? SystemColors.Control : Parent.BackColor);','/* negative control: old pixels are deliberately left in place */')
    Add-Type -TypeDefinition $negative -ReferencedAssemblies System.dll,System.Drawing.dll,System.Windows.Forms.dll
    $negativeButton=New-Object FastDownloaderNegative.ModernButton
    $negativeButton.Size=New-Object Drawing.Size(140,40)
    $negativeParent=New-Object Windows.Forms.Panel
    $negativeParent.BackColor=[Drawing.Color]::White
    $negativeButton.Parent=$negativeParent
    $negativeImage=[OffscreenProbe]::PaintButton($negativeButton)
    try { Assert-Check ($negativeImage.GetPixel(0,0).ToArgb() -eq [Drawing.Color]::Black.ToArgb()) 'Negative control reproduces stale black button corners' }
    finally { $negativeImage.Dispose(); $negativeButton.Dispose(); $negativeParent.Dispose() }
    foreach ($button in @($newDownload,$open,$chooseTop,$pause,$resumeButton,$stop,$script:NavButtons[0].Button,$add,$cancel)) {
        foreach ($enabled in @($true,$false,$true)) {
            $button.Enabled=$enabled
            $image=[OffscreenProbe]::PaintButton($button)
            try {
                foreach ($point in @(@(0,0),@(($image.Width-1),0),@(0,($image.Height-1)),@(($image.Width-1),($image.Height-1)))) {
                    Assert-Check ($image.GetPixel($point[0],$point[1]).ToArgb() -eq $button.Parent.BackColor.ToArgb()) ('Clean corner: '+$button.Text+' enabled='+$enabled+' at '+$point[0]+','+$point[1])
                }
            } finally { $image.Dispose() }
        }
    }
    foreach ($size in @(@(1280,820),@(1000,720),@(1600,1000))) {
        $form.Size=New-Object Drawing.Size($size[0],$size[1])
        [OffscreenProbe]::Layout($form)
        Assert-InParent $open ('Toolbar open button stays in its row '+$size[0])
        Assert-InParent $chooseTop ('Toolbar import button stays in its row '+$size[0])
        foreach ($button in @($pause,$resumeButton,$stop)) { Assert-InParent $button ('Task action stays in its row '+$button.Text+' '+$size[0]) }
        Assert-Check ($heading.Height -ge $heading.PreferredSize.Height) ('Heading text has full line height '+$size[0])
    }
    $form.Size=New-Object Drawing.Size(1280,820)
    foreach ($entry in @(@('安装包.exe','Downloading','42%'),@('设计说明.pdf','Completed','100%'),@('演示视频.mp4','Paused','68%'))) {
        $record=New-TaskRecord (Get-SourceSpec ('https://example.invalid/'+[Uri]::EscapeDataString($entry[0]))) (Join-Path $testRoot 'downloads')
        $record.FileName=$entry[0]
        if ($entry[1] -eq 'Completed') {
            $record.Status='Completed'
            $record | Add-Member -NotePropertyName CompletedBytes -NotePropertyValue 512
            $record | Add-Member -NotePropertyName TotalBytes -NotePropertyValue 1024
        }
        $item=Add-RecordRow $record
        if ($entry[1] -eq 'Completed') { Assert-Check ($item.Row.Cells['Progress'].Value -eq '100%') 'Completed history ignores a stale partial progress checkpoint' }
        Set-ItemState $item $entry[1]
        $item.Row.Cells['Progress'].Value=$entry[2]
        $item.Row.Cells['Speed'].Value='2.4 MiB/s'
        $item.Row.Cells['Total'].Value='128 MiB'
    }
    Refresh-TaskView
    [OffscreenProbe]::Save($shell,(Join-Path $testRoot 'main.png'))
    $script:StateFilter='Completed'; Refresh-TaskView
    Assert-Check (@($script:Items | Where-Object {$_.Row.Visible}).Count -eq 1) 'Completed filter selects one task'
    $script:StateFilter='All'; $script:CategoryFilter='Video'; Refresh-TaskView
    Assert-Check (@($script:Items | Where-Object {$_.Row.Visible}).Count -eq 1) 'Video category selects one task'
    $script:CategoryFilter='All'; $searchBox.Text='设计说明'; Refresh-TaskView
    Assert-Check (@($script:Items | Where-Object {$_.Row.Visible}).Count -eq 1) 'Unicode search selects matching filename'
    $searchBox.Text=''; Refresh-TaskView
    $dialogCard.PerformLayout()
    [OffscreenProbe]::Save($dialogCard,(Join-Path $testRoot 'new-download.png'))
    Assert-InParent $folder.Parent 'Destination input has full rounded frame height'
    Assert-InParent $add 'Download action stays inside footer'
    Assert-InParent $cancel 'Cancel action stays inside footer'
    Set-AdvancedOptions $true
    [OffscreenProbe]::Layout($dialogCard)
    Assert-InParent $renameBox.Parent 'Expanded rename input stays inside advanced area'
    Assert-InParent $connectionBox 'Expanded connection selector stays inside advanced area'
    [OffscreenProbe]::Save($dialogCard,(Join-Path $testRoot 'advanced-options.png'))
    Set-AdvancedOptions $false
    Assert-Check (-not $script:AdvancedExpanded) 'Advanced options collapse without changing default inputs'
    Assert-Check ($null -eq $script:Active) 'Offscreen checks never start a download engine'
    Assert-Check (-not $form.Visible) 'Offscreen checks never show a desktop window'
    @{passed=$true;kind='Offscreen rendering and own-control layout checks; no desktop input or screenshot';checks=@($evidence);images=@('main.png','new-download.png','advanced-options.png')} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $testRoot 'layout-evidence.json') -Encoding UTF8
    Write-Output ('PASS: offscreen button pixels, layout and filters; '+$testRoot)
} finally {
    $timer.Dispose(); $tips.Dispose(); $form.Dispose()
}
