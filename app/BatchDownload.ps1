# Additional input formats. Only named data fields are accepted, never aria2 options or commands.
$script:BatchExtensions = @('.txt', '.urls', '.lst', '.csv', '.json', '.url')

function Test-BatchSource {
    param([string]$Text)
    $path = $Text.Trim().Trim('"').Trim("'")
    return (Test-Path -LiteralPath $path -PathType Leaf) -and ([IO.Path]::GetExtension($path).ToLowerInvariant() -in $script:BatchExtensions)
}

function Read-DownloadBatch {
    param([string]$Path)
    $file = Get-Item -LiteralPath ($Path.Trim().Trim('"').Trim("'"))
    if ($file.Length -gt 8MB) { throw 'Batch input exceeds 8 MiB.' }
    $extension = $file.Extension.ToLowerInvariant()
    $content = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    $rows = @()
    switch ($extension) {
        '.json' {
            $parsed = ConvertFrom-Json -InputObject $content
            if ($content.TrimStart().StartsWith('[')) { $rows = @($parsed) }
            elseif ($null -ne $parsed -and $null -ne $parsed.PSObject.Properties['downloads']) { $rows = @($parsed.downloads) }
            else { throw 'JSON must be an array or an object containing a downloads array.' }
        }
        '.csv' { $rows = @(ConvertFrom-Csv -InputObject $content) }
        '.url' {
            $urls = @($content -split '\r?\n' | Where-Object { $_ -match '^\s*URL\s*=' } | ForEach-Object { ($_ -split '=', 2)[1].Trim() })
            if ($urls.Count -ne 1) { throw '.url must contain exactly one URL= entry.' }
            $rows = @($urls[0])
        }
        default {
            if ($extension -notin $script:BatchExtensions) { throw 'Unsupported batch input format.' }
            $rows = @($content -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
        }
    }
    if ($rows.Count -eq 0 -or $rows.Count -gt 1000) { throw 'Batch must contain between 1 and 1000 tasks.' }
    $result = @()
    foreach ($row in $rows) {
        $sourceText = $null; $name = ''; $hash = ''
        if ($row -is [string]) { $sourceText = $row }
        elseif ($null -ne $row) {
            if ($null -eq $row.PSObject.Properties['Source']) { throw 'Every CSV/JSON task requires Source.' }
            foreach ($property in $row.PSObject.Properties) {
                if ($property.Name -notin @('Source', 'FileName', 'Sha256')) { throw ('Unsupported task field: ' + $property.Name) }
            }
            $sourceText = [string]$row.Source
            if ($null -ne $row.PSObject.Properties['FileName']) { $name = [string]$row.FileName }
            if ($null -ne $row.PSObject.Properties['Sha256']) { $hash = [string]$row.Sha256 }
        }
        if ([string]::IsNullOrWhiteSpace($sourceText)) { throw 'Batch contains an empty Source.' }
        if ($hash -and $hash -notmatch '^[a-fA-F0-9]{64}$') { throw 'Sha256 must contain 64 hexadecimal digits.' }
        # Relative local torrent/Metalink paths are resolved beside the batch, never evaluated.
        if (-not [Uri]::IsWellFormedUriString($sourceText, [UriKind]::Absolute)) {
            $candidate = Join-Path $file.DirectoryName $sourceText
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $sourceText = [IO.Path]::GetFullPath($candidate) }
        }
        $result += [pscustomobject]@{ Source = $sourceText; FileName = $name; Sha256 = $hash }
    }
    return $result
}

function Invoke-DownloadBatch {
    param([string]$Path, [string]$Destination)
    $entries = @(Read-DownloadBatch $Path)
    $records = @(); $identities = @{}
    foreach ($entry in $entries) {
        $spec = Get-SourceSpec $entry.Source
        if ($identities.ContainsKey($spec.Identity)) { throw 'Duplicate input in one batch; remove duplicates before starting.' }
        $identities[$spec.Identity] = $true
        $record = New-TaskRecord $spec $Destination -Separate:$NewTask
        foreach ($key in @('FileName', 'Sha256')) {
            if ($entry.$key) {
                if ($record.Status -ne 'Pending' -and $record.$key -ne $entry.$key) {
                    throw ('Saved task has different ' + $key + '; use -NewTask to keep previous content separate.')
                }
                $record.$key = $entry.$key
            }
        }
        # Validate the entire batch before creating directories or starting network work.
        $null = @(Get-AriaArguments $record $StopAfterSeconds)
        $records += $record
    }
    $failed = 0; $done = 0; $skipped = 0
    foreach ($record in $records) {
        if ($record.Status -eq 'Completed' -and -not $DryRun) { $skipped++; continue }
        try {
            $code = Invoke-Task $record
            if ($code -eq 0) { $done++ } else { $failed++ }
        } catch { $failed++; Write-Host ('Task failed: ' + $_.Exception.Message) -ForegroundColor Red }
        if ($failed -and $FailFast) { break }
    }
    Write-Host ('Batch result: passed={0}, skipped={1}, failed={2}, total={3}' -f $done, $skipped, $failed, $records.Count)
    if ($failed) { return 1 }
    return 0
}

function Show-DownloadTasks {
    if (-not (Test-Path -LiteralPath $script:JobsRoot)) { Write-Muted '  还没有任务记录。'; return }
    $rows = @()
    foreach ($path in Get-ChildItem -LiteralPath $script:JobsRoot -Filter task.json -Recurse -File) {
        try {
            $record = Read-JsonFile $path.FullName
            $bytes = [double](Get-RecordField $record 'TotalBytes')
            if ($bytes -le 0) { $bytes = [double](Get-TaskBytes $record.OutputDir) }
            $status = '待开始'
            if ($record.Status -eq 'Completed') { $status = '已完成' }
            elseif ($record.Status -eq 'Incomplete') { $status = '未完成' }
            elseif ($record.Status -eq 'Downloading') { $status = '下载中' }
            $updated = [string]$record.UpdatedAt
            try { $updated = ([datetime]$record.UpdatedAt).ToString('MM-dd HH:mm') } catch { }
            $rows += [pscustomobject]@{
                Status = $status; Size = (Format-ByteSize $bytes); Type = [string]$record.Type
                Label = [string]$record.Label; Updated = $updated; SortKey = [string]$record.UpdatedAt
            }
        } catch { Write-Warning ('跳过无法读取的任务记录：' + $path.Directory.Name) }
    }
    if ($rows.Count -eq 0) { Write-Muted '  还没有任务记录。'; return }
    Write-Host ''
    Write-Muted ((Format-Cell '状态' 8) + (Format-Cell '大小' 10) + (Format-Cell '类型' 4) + (Format-Cell '名称' 26) + '更新')
    foreach ($row in ($rows | Sort-Object -Property SortKey -Descending)) {
        Write-Host ((Format-Cell $row.Status 8) + (Format-Cell $row.Size 10) + (Format-Cell $row.Type 4) + (Format-Cell $row.Label 26) + $row.Updated)
    }
    Write-Host ''
}
