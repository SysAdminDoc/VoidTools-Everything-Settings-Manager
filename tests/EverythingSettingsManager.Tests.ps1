$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('EverythingSettingsManagerTests_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $scriptPath = Join-Path $PSScriptRoot '..\EverythingSettingsManager.ps1'
    . $scriptPath -NoGui -EverythingFolder $root
    $Script:EverythingFolder = $root
    $Script:BackupFolder = Join-Path $root 'Backups'
    $Script:CsvHistoryPath = Join-Path $root 'history.jsonl'

    $iniPath = Join-Path $root 'Everything-1.5a.ini'
    @(
        '; keep this comment'
        'alpha=one'
        ''
        'journal = 0'
        'index_folder_size=0'
        'custom_key=keep-me'
    ) | Set-Content -LiteralPath $iniPath -Encoding UTF8

    $settings = Read-IniFile -Path $iniPath
    Assert-True ($settings['alpha'] -eq 'one') 'INI reader should parse values.'
    Assert-True ($settings['custom_key'] -eq 'keep-me') 'INI reader should retain unknown keys.'
    $settings['journal'] = '1'
    Write-IniFile -Path $iniPath -Settings $settings
    $iniText = Get-Content -LiteralPath $iniPath -Raw
    Assert-True ($iniText -match '; keep this comment') 'INI writer should preserve comments.'
    Assert-True ($iniText -match 'journal = 1') 'INI writer should preserve key spacing while updating values.'
    Assert-True ($iniText -match 'custom_key=keep-me') 'INI writer should preserve unknown keys.'

    $invalid = @{ journal = '2'; journal_max_size = '1' }
    Assert-True (@(Test-Settings -Settings $invalid).Count -eq 2) 'INI validation should report invalid boolean and range values.'

    $presetSettings = @{ journal = '0'; search_history_enabled = '1' }
    $changes = Apply-PresetToSettings -Settings $presetSettings -PresetName Privacy
    Assert-True ($changes['search_history_enabled'] -eq '0') 'Privacy preset should disable search history.'
    Assert-True ((Get-SettingsDiff -Settings $presetSettings).Count -gt 0) 'Settings diff should expose non-default values.'

    $backup = Backup-File -Path $iniPath
    Assert-True (Test-Path -LiteralPath $backup) 'Backup should be created.'
    Assert-True ((@(Get-BackupFiles -SourcePath $iniPath)).Count -ge 1) 'Backup inventory should find created backups.'

    $csvPath = Join-Path $root 'Filters.csv'
    @(
        [pscustomobject]@{ Name = 'One'; Search = '[bad'; Regex = '1' }
        [pscustomobject]@{ Name = 'One'; Search = 'two'; Regex = '0' }
    ) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $rows = Read-CsvFile -Path $csvPath
    $csvIssues = @(Get-CsvValidationIssues -CsvType Filters -Rows $rows)
    Assert-True ($csvIssues.Count -ge 2) 'CSV validation should report duplicate names and invalid regex.'
    $bulk = Invoke-CsvBulkEdit -Rows $rows -Column Name -Operation Prefix -Value 'X-'
    Assert-True ($bulk[0].Name -eq 'X-One') 'CSV bulk prefix should update selected column.'
    $scrubbed = @(Remove-HistoryMatches -Rows @([pscustomobject]@{ Search = 'secret' }, [pscustomobject]@{ Search = 'keep' }) -Pattern 'secret')
    Assert-True ($scrubbed.Count -eq 1 -and $scrubbed[0].Search -eq 'keep') 'History scrubber should remove regex matches.'
    $pinned = Set-RunHistoryPinned -Rows @([pscustomobject]@{ Name = 'keep' }) -Names @('keep')
    Assert-True ($pinned[0].Pinned -eq '1') 'Run history pinning should add the Pinned field.'
    $jsonPath = Sync-BookmarksJson -CsvPath (Join-Path $root 'Bookmarks.csv') -Rows @([pscustomobject]@{ Name = 'Example'; Search = 'ext:txt' })
    Assert-True (Test-Path -LiteralPath $jsonPath) 'Bookmark JSON synchronization should create a sidecar.'

    $bundlePath = Join-Path $root 'settings.bundle.zip'
    Export-SettingsBundle -OutputPath $bundlePath -Folder $root -SelectedIniPath $iniPath | Out-Null
    Assert-True (Test-Path -LiteralPath $bundlePath) 'Bundle export should create a ZIP archive.'
    $importRoot = Join-Path $root 'Imported'
    $imported = @(Import-SettingsBundle -BundlePath $bundlePath -DestinationFolder $importRoot)
    Assert-True ($imported.Count -ge 1) 'Bundle import should restore INI/CSV files.'

    $admxRoot = Join-Path $root 'Policy'
    $admxPath = Export-EverythingAdmx -OutputPath $admxRoot
    Assert-True ((Test-Path -LiteralPath $admxPath) -and (Test-Path -LiteralPath (Join-Path $admxRoot 'en-US\EverythingSettingsManager.adml'))) 'ADMX export should create both language-neutral and en-US files.'

    $report = Get-EverythingHealthReport -SelectedIniPath $iniPath
    Assert-True ($report.iniPath -eq $iniPath) 'Health report should identify the selected INI.'
    Assert-True ($null -ne $report.service) 'Health report should include service state.'
    Write-Output 'EverythingSettingsManager tests: PASS'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
