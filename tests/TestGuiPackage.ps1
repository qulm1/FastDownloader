param([Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
if(Test-Path -LiteralPath $WorkRoot){throw 'Choose a fresh package evidence directory.'}
$null=New-Item -ItemType Directory -Path $WorkRoot
$fixture=Join-Path $WorkRoot 'source-fixture'
$null=New-Item -ItemType Directory -Path $fixture
foreach($file in Get-ChildItem -LiteralPath $project -File){Copy-Item -LiteralPath $file.FullName -Destination $fixture}
foreach($name in @('bin','tests','docs','examples')){Copy-Item -LiteralPath (Join-Path $project $name) -Destination $fixture -Recurse}
$null=New-Item -ItemType Directory -Path (Join-Path $fixture 'state')
foreach($name in @('state/private.json','cookies.txt','bin/private-cookie.txt','tests/private-test.key','docs/private-note.txt')){
    Set-Content -LiteralPath (Join-Path $fixture $name) -Value 'PRIVATE-TEST-CANARY' -Encoding UTF8
}
$dist=Join-Path $WorkRoot 'dist'
& (Join-Path $fixture 'BuildRelease.ps1') -Version '2.1.0-wpf.preview' -OutputDir $dist | Out-Host
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach($name in @('FastDownloader-2.1.0-wpf.preview.zip','FastDownloader-2.1.0-wpf.preview-source.zip')){
    $zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $dist $name))
    try{
        $entries=@($zip.Entries|ForEach-Object {$_.FullName.Replace('\','/')})
        foreach($required in @('FastDownloadGui.ps1','StartDownloadGui.cmd','GuiApp.ps1','GuiTasks.ps1','GuiView.ps1','GuiEngine.cs','docs/GUI.md','tests/TestWpf.ps1')){
            if($required -notin $entries){throw ('Package missing '+$required)}
        }
        if(@($entries|Where-Object {$_ -match '(^|/)state/|cookies\.txt|private-cookie|private-test|private-note|\.key$'}).Count){throw 'Private fixture data leaked into ZIP.'}
        if($name -like '*source*' -and @($entries|Where-Object {$_ -like 'bin/*'}).Count){throw 'Source ZIP contains binaries.'}
        if($name -notlike '*source*' -and 'bin/aria2c.exe' -notin $entries){throw 'Portable ZIP missing engine.'}
    }finally{$zip.Dispose()}
}
$portable=Join-Path $WorkRoot '中文 空格 便携包'
Expand-Archive -LiteralPath (Join-Path $dist 'FastDownloader-2.1.0-wpf.preview.zip') -DestinationPath $portable
foreach($name in @('FastDownload.ps1','FastDownloadGui.ps1','StartDownloadGui.cmd','GuiApp.ps1','GuiTasks.ps1','GuiView.ps1','GuiEngine.cs','bin/aria2c.exe')){
    if((Get-FileHash -LiteralPath (Join-Path $project $name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $portable $name)).Hash){throw ('Package bytes changed: '+$name)}
}
powershell.exe -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $portable 'tests/TestGui.ps1') -WorkRoot (Join-Path $WorkRoot 'packaged-runtime')
if($LASTEXITCODE -ne 0){throw 'Packaged WPF runtime failed.'}
@{passed=$true;portable_root=$portable;dist=$dist;runtime='Windows PowerShell 5.1 / WPF, no displayed window'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $WorkRoot 'test-evidence.json') -Encoding UTF8
Write-Output ('PASS: complete WPF package, private canaries, byte identity and packaged runtime; '+$WorkRoot)
