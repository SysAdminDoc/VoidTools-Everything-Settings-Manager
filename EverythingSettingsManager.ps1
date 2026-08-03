<#
.SYNOPSIS
    Everything Settings Manager - GUI tool to configure Voidtools Everything
.DESCRIPTION
    A comprehensive settings manager for Everything search utility.
    - Auto-detects INI file (supports beta versions like Everything-1.5a.ini)
    - Provides organized categories with explanations and recommended values
    - Includes CSV editor for Filters, Bookmarks, Search History, Run History
    - Ships with curated default filters and bookmarks
.AUTHOR
    Matt - Generated with Claude AI
.VERSION
    2.0.0
#>

[CmdletBinding()]
param(
    [string]$EverythingFolder,
    [string]$IniPath,
    [ValidateSet('Recommended', 'Safe', 'Privacy', 'Performance', 'PowerUser')]
    [string]$ApplyPreset,
    [switch]$Restart,
    [switch]$Silent,
    [switch]$NoGui,
    [switch]$UiSmoke,
    [string]$DiagnosticsPath,
    [switch]$SelfTest,
    [string]$ExportBundlePath,
    [string]$ImportBundlePath,
    [string]$ExportSettingsPath,
    [string]$ExportAdmxPath,
    [string]$HealthReportPath,
    [switch]$TestIpc,
    [int]$ScheduleIntervalMinutes
)

$Script:AppVersion = '2.0.0'
$Script:CliRequested = $false
if ($ApplyPreset -or $ExportBundlePath -or $ImportBundlePath -or $ExportSettingsPath -or $ExportAdmxPath -or $HealthReportPath -or $TestIpc -or $ScheduleIntervalMinutes -gt 0) {
    $Script:CliRequested = $true
    $NoGui = $true
}

if (-not $NoGui -and -not $SelfTest) {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
}

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:EverythingFolder = if ($EverythingFolder) { [System.IO.Path]::GetFullPath($EverythingFolder) } elseif ($env:APPDATA) { Join-Path $env:APPDATA 'Everything' } else { Join-Path $PSScriptRoot 'Everything' }
$Script:EverythingIniPath = $IniPath
$Script:BackupFolder = Join-Path $Script:EverythingFolder 'Backups'
$Script:BackupRetentionCount = 10
$Script:IniDocumentCache = @{}
$Script:IniCandidates = @()
$Script:IniProfilePath = $null
$Script:CurrentProfile = $null
$Script:CsvHistoryPath = Join-Path $Script:EverythingFolder 'EverythingSettingsManager.csv-history.jsonl'
$Script:UndoStack = New-Object System.Collections.Stack
$Script:RedoStack = New-Object System.Collections.Stack
$Script:CsvUndoStack = New-Object System.Collections.Stack
$Script:CsvRedoStack = New-Object System.Collections.Stack
$Script:ThemeName = 'Dark'
$Script:ThemePalette = @{}
$Script:SettingsSearchText = ''
$Script:ShowOnlyDifferences = $false
$Script:Settings = @{}
$Script:OriginalSettings = @{}
$Script:ModifiedSettings = @{}
$Script:CurrentCsvType = $null
$Script:CsvData = @()
$Script:CsvModified = $false

function Write-DiagnosticLog {
    param([string]$Message)
    if (-not $DiagnosticsPath) { return }
    try {
        $directory = Split-Path -Parent $DiagnosticsPath
        if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        Add-Content -LiteralPath $DiagnosticsPath -Value ("{0} {1}" -f (Get-Date -Format 'o'), $Message) -Encoding UTF8
    } catch { }
}
Write-DiagnosticLog -Message 'script started'

# ============================================================================
# AUTO-DETECT INI FILE
# ============================================================================

function Find-EverythingIniFile {
    param([string]$Folder)
    $candidates = @(Get-EverythingIniCandidates -Folder $Folder)
    if ($candidates.Count -gt 0) {
        $Script:IniCandidates = $candidates
        return $candidates[0].Path
    }
    return $null
}

function Find-EverythingCsvFile {
    param(
        [string]$Folder,
        [string]$BaseName  # e.g., "Filters", "Bookmarks", "Run_History", "Search_History"
    )
    
    $csvFiles = @(Get-EverythingCsvCandidates -Folder $Folder -BaseName $BaseName)
    if ($csvFiles.Count -gt 0) { return $csvFiles[0].Path }
    return $null
}

function Get-EverythingInstallationCandidates {
    $paths = @(
        (Join-Path ${env:ProgramFiles} 'Everything\Everything.exe'),
        (Join-Path ${env:ProgramFiles} 'Everything 1.5a\Everything.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Everything\Everything.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Everything 1.5a\Everything.exe')
    )
    $portableRoots = @(
        (Join-Path $env:USERPROFILE 'PortableApps'),
        (Join-Path $env:ProgramData 'PortableApps'),
        (Join-Path $PSScriptRoot 'PortableApps')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($root in $portableRoots) {
        try {
            foreach ($relativePath in @(
                    'Everything.exe',
                    'EverythingPortable\Everything.exe',
                    'EverythingPortable\Everything\Everything.exe',
                    'EverythingPortable\App\Everything\Everything.exe',
                    'Everything-Portable\Everything.exe',
                    'Everything-Portable\Everything\Everything.exe'
                )) {
                $candidate = Join-Path $root $relativePath
                if (Test-Path -LiteralPath $candidate) { $paths += $candidate }
            }
        } catch { }
    }
    $seen = @{}
    foreach ($path in $paths) {
        if (-not $path) { continue }
        try { $fullPath = [System.IO.Path]::GetFullPath($path) } catch { continue }
        if ($seen.ContainsKey($fullPath.ToLowerInvariant()) -or -not (Test-Path -LiteralPath $fullPath)) { continue }
        $seen[$fullPath.ToLowerInvariant()] = $true
        $item = Get-Item -LiteralPath $fullPath -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        [pscustomobject]@{
            Path = $item.FullName
            Folder = $item.DirectoryName
            Mode = if ($item.FullName -match '(?i)portableapps|\\portable\\') { 'Portable' } else { 'Installed' }
            Version = Get-FileVersionSafe -Path $item.FullName
        }
    }
}

function Get-FileVersionSafe {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Item -LiteralPath $Path).VersionInfo.ProductVersion } catch { return $null }
}

function Get-EverythingIniCandidates {
    param([string]$Folder)
    $locations = @()
    if ($Folder -and (Test-Path -LiteralPath $Folder)) { $locations += [pscustomobject]@{ Path = $Folder; Source = 'Selected folder'; IsService = $false; Mode = 'Installed' } }
    foreach ($installation in @(Get-EverythingInstallationCandidates)) {
        if ($installation.Folder -and (Test-Path -LiteralPath $installation.Folder)) {
            $locations += [pscustomobject]@{ Path = $installation.Folder; Source = $installation.Mode; IsService = $false; Mode = $installation.Mode }
        }
    }
    $serviceFolders = @(
        (Join-Path $env:ProgramData 'Everything'),
        (Join-Path $env:ProgramData 'Everything 1.5a')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($serviceFolder in $serviceFolders) {
        $locations += [pscustomobject]@{ Path = $serviceFolder; Source = 'Service'; IsService = $true; Mode = 'Service' }
    }
    $seen = @{}
    $files = foreach ($location in $locations) {
        try {
            Get-ChildItem -LiteralPath $location.Path -Filter 'Everything*.ini' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '(?i)backup' } |
                ForEach-Object {
                    $key = $_.FullName.ToLowerInvariant()
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        [pscustomobject]@{
                            Path = $_.FullName
                            Name = $_.Name
                            LastWriteTime = $_.LastWriteTime
                            Source = $location.Source
                            IsService = $location.IsService
                            Mode = $location.Mode
                            Version = if ($_.Name -match '(?i)1\.5|beta|alpha') { '1.5+' } else { '1.4' }
                        }
                    }
                }
        } catch { }
    }
    @($files | Sort-Object @{Expression = { $_.IsService }; Ascending = $true }, LastWriteTime -Descending)
}

function Get-EverythingCsvCandidates {
    param(
        [string]$Folder,
        [string]$BaseName
    )
    if (-not $Folder -or -not (Test-Path -LiteralPath $Folder)) { return @() }
    Get-ChildItem -LiteralPath $Folder -Filter "$BaseName*.csv" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '(?i)backup' } |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Name = $_.Name; LastWriteTime = $_.LastWriteTime } }
}

# ============================================================================
# DEFAULT FILTERS (from user's config)
# ============================================================================

$Script:DefaultFilters = @'
Name,Case,Whole Word,Path,Diacritics,Prefix,Suffix,Ignore Punctuation,Ignore Whitespace,Regex,Search,Columns,Sort,Descending,View,Macro,Key
"EVERYTHING",0,0,0,0,0,0,0,0,0,"","","",0,,,
"AUDIO",0,0,0,0,0,0,0,0,0,"ext:aac;ac3;adt;adts;aif;aifc;aiff;amr;ape;au;cda;dts;ec3;fla;flac;lpcm;m1a;m2a;m3u;m3u8;m4a;m4b;m4p;mid;midi;mka;mp2;mp3;mpa;mpc;oga;ogg;opus;ra;rmi;snd;wav;wax;weba;wma","","",0,,"audio",
"COMPRESSED",0,0,0,0,0,0,0,0,0,"ext:7z;ace;arj;bz2;cab;gz;gzip;jar;r00;r01;r02;r03;r04;r05;r06;r07;r08;r09;r10;r11;r12;r13;r14;r15;r16;r17;r18;r19;r20;r21;r22;r23;r24;r25;r26;r27;r28;r29;rar;tar;tgz;z;zip","","",0,,"zip",
"DOCUMENT",0,0,0,0,0,0,0,0,0,"ext:asm;c;cc;chm;cpp;cs;css;csv;cxx;doc;docm;docx;dot;dotm;dotx;efu;epub;h;hpp;htm;html;hxx;ini;java;js;json;lua;md;mht;mhtml;mobi;odp;ods;odt;ofd;pdf;php;pl;potm;potx;ppam;pps;ppsm;ppsx;ppt;pptm;pptx;ps1xml;pssc;pub;py;rtf;sldm;sldx;sql;tsv;txt;vb;vsd;wpd;wps;wri;xlam;xls;xlsb;xlsm;xlsx;xltm;xltx;xml;xsl","","",0,,"doc",
"EXECUTABLE",0,0,0,0,0,0,0,0,0,"ext:bat;cmd;exe;msi;msp;msu;ps1;scr;vbs","","",0,,"exe",
"FOLDER",0,0,0,0,0,0,0,0,0,"folder:","","",0,,"dir",
"IMAGE",0,0,0,0,0,0,0,0,0,"ext:ani;apng;avif;avifs;bmp;bpg;cur;dds;gif;heic;heics;heif;heifs;hif;ico;jfi;jfif;jif;jpe;jpeg;jpg;jxl;jxr;pcx;png;psb;psd;svg;tga;tif;tiff;wdp;webp;wmf","","",0,,"image",
"VIDEO",0,0,0,0,0,0,0,0,0,"ext:3g2;3gp;3gp2;3gpp;amv;asf;asx;avi;bdmv;bik;d2v;divx;drc;dsa;dsm;dss;dsv;evo;f4v;flc;fli;flic;flv;hdmov;ifo;ivf;m1v;m2p;m2t;m2ts;m2v;m4v;mkv;mod;mov;mp2v;mp4;mp4v;mpe;mpeg;mpg;mpls;mpv2;mpv4;mts;ogm;ogv;ogx;pss;pva;qt;ram;ratdvd;rm;rmm;rmvb;roq;rpm;smil;smk;swf;tod;tp;tpr;ts;tts;uvu;vob;vp6;webm;wm;wmp;wmv;wmx;wvx","","",0,,"video",
"LARGE_FILES",0,0,0,0,0,0,0,0,0,"size:>1GB","","Date Modified",1,,"large",
"USERSCRIPTS",0,0,0,0,0,0,0,0,0,"user.js","","Date Modified",1,,,
"PSD",0,0,0,0,0,0,0,0,0,"*.psd !""?:\program files\"" !""?:\program files (x86)\"" !?:\windows !?:\$recycle.bin\*","","Date Modified",1,96,,
"TEMP_FILES",0,0,0,0,0,0,0,0,0,"ext:tmp;temp;log;bak;old;$$$;~*","","Date Modified",1,,"temp",
"ADOBE",0,0,0,0,0,0,0,0,0,"Adobe .exe","","Date Modified",1,,,
"BOOKMARKS",0,0,0,0,0,0,0,0,0,"Bookmark","","Date Modified",1,,,
"CODE",0,0,0,0,0,0,0,0,0,"ext:c;cpp;h;hpp;cs;java;py;js;ts;go;rb;php;html;css;json;xml;sql;sh;bash;ps1;vb","","Date Modified",1,,"code",
"ISO_IMAGES",0,0,0,0,0,0,0,0,0,"ext:iso;img;nrg;bin;cue;mdf;mds;vhd;vhdx;vmdk","","Date Modified",1,,"iso",
"EXE_DLL",0,0,0,0,0,0,0,0,0,"ext:exe;dll;sys;ocx;msi;cpl","","Date Modified",1,,"exedll",
"FONTS",0,0,0,0,0,0,0,0,0,"ext:ttf;otf;ttc;fon;pfb;pfm;woff;woff2 !?:\$recycle.bin\*","","",0,,,
"SCRIPTS",0,0,0,0,0,0,0,0,0,"ext:bat;ps1;cmd;vbs;sh","","Date Modified",1,,,
"PYTHON",0,0,0,0,0,0,0,0,0,"ext:py","","Date Modified",1,,,
"RECENT_24H",0,0,0,0,0,0,0,0,0,"dm:today","","Date Modified",1,,,
"RECENT_7DAYS",0,0,0,0,0,0,0,0,0,"dm:last7days","","Date Modified",1,,,
"EMPTY_FILES",0,0,0,0,0,0,0,0,0,"size:0 file:","","Name",0,,,
"EMPTY_FOLDERS",0,0,0,0,0,0,0,0,0,"folder:empty:","","Path",1,,,
"HIDDEN_FILES",0,0,0,0,0,0,0,0,0,"attrib:H","","Name",0,,,
"DUPLICATES",0,0,0,0,0,0,0,0,0,"dupe:","","Size",1,,,
"LONG_PATHS",0,0,0,0,0,0,0,0,0,"len:>250","","Path",1,,,
'@

# ============================================================================
# DEFAULT BOOKMARKS (curated from user's config)
# ============================================================================

$Script:DefaultBookmarks = @'
Name,Type,Folder,Case,Whole Word,Path,Diacritic,Prefix,Suffix,Ignore Punctuation,Ignore Whitespace,Regex,Search,Filter,Columns,Sort,Descending,View,Index,File List,Host,Link Type,Macro,Key,Icon
"Default",0,"",0,0,0,0,,,,,0,"","EVERYTHING","","Name",0,,0,,,1,,,""
"Everything\By Name",0,"",0,0,0,0,,,,,0,"","EVERYTHING","","Name",0,,0,,,1,"everything",,""
"Everything\By Recents",0,"",0,0,0,0,,,,,0,"","EVERYTHING","","Date Recently Changed",0,,0,,,1,"everythingrc",,""
"Everything\By Size",0,"",0,0,0,0,,,,,0,"","EVERYTHING","","Size",1,,0,,,1,"everythingsize",,""
"Files\Only",0,"",0,0,0,0,,,,,0,"file:","EVERYTHING","","Name",0,,0,,,1,"filesonly",,""
"Files\W/O Extensions",0,"",0,0,0,0,,,,,0,"!. file:","EVERYTHING","","Name",0,,0,,,1,,,""
"Folders\Only",0,"",0,0,0,0,,,,,0,"folder:","EVERYTHING","","Name",0,,0,,,1,"foldersonly",,""
"Folders\Empty ones",0,"",0,0,0,0,,,,,0,"folder:empty:","FOLDER","","Path",1,,0,,,1,"emptyfolders",,""
"Date\Recent 24 Hours",0,"",0,0,0,0,,,,,0,"dm:today","EVERYTHING","","Date Recently Changed",1,,0,,,1,"recent24",,""
"Date\Recent 7 Days",0,"",0,0,0,0,,,,,0,"dm:last7days","EVERYTHING","","Date Recently Changed",1,,0,,,1,"recent7",,""
"Date\Recents\Files",0,"",0,0,0,0,,,,,0,"recentchange: file:","EVERYTHING","","Name",0,,0,,,1,,,""
"Date\Recents\Folders",0,"",0,0,0,0,,,,,0,"recentchange: folder:","EVERYTHING","","Name",0,,0,,,1,,,""
"Name\Duplicates\All",0,"",0,0,0,0,,,,,0,"dupe:","EVERYTHING","","Size",0,,0,,,1,,,""
"Name\Duplicates\Large ones",0,"",0,0,0,0,,,,,0,"file: dupe: size:>500mb","EVERYTHING","","Name",0,0,0,,,1,"largeduplicatefiles",,""
"Name\Length\Long File Names",0,"",0,0,0,0,,,,,0,"file: len:>85","EVERYTHING","","Name",0,,0,,,1,"longfilenames",,""
"Name\Length\Long Folder Names",0,"",0,0,0,0,,,,,0,"folder: len:>85","FOLDER","","Name",0,0,0,,,1,"longfoldernames",,""
"Size\Small Files",0,"",0,0,0,0,,,,,0,"file: size:<5MB","EVERYTHING","","Size",0,,0,,,1,"smallfiles",,""
"Size\Large Files",0,"",0,0,0,0,,,,,0,"file: size:>50MB","EVERYTHING","","Size",1,0,0,,,1,"largefilesall",,""
"Size\Big Files",0,"",0,0,0,0,,,,,0,"file: size:>2GB","EVERYTHING","","Size",1,,0,,,1,"bigfiles",,""
"Size\Massive Files",0,"",0,0,0,0,,,,,0,"file: size:>3GB","EVERYTHING","","Size",1,0,0,,,1,"massivefiles",,""
"Attributes\Empty Files & Folders",0,"",0,0,0,0,,,,,0,"size:0","EVERYTHING","","Name",0,,0,,,1,"empty",,""
"Attributes\Hidden Files & Folders",0,"",0,0,0,0,,,,,0,"attrib:H","EVERYTHING","","Name",0,,0,,,1,"hidden",,""
"Attributes\Read only\All",0,"",0,0,1,0,,,,,0,"attrib:R","EVERYTHING","","Name",0,,0,,,1,,,""
"Path\Long Paths (>250)",0,"",0,0,0,0,,,,,0,"len:>250","EVERYTHING","","Path",1,,0,,,1,"longpath",,""
"Filetypes\Batch and Commands",0,"",0,0,0,0,,,,,0,"*.bat | *.cmd","EVERYTHING","","Name",0,,0,,,1,"batchcommand",,""
"Filetypes\Powershell Scripts",0,"",0,0,0,0,,,,,0,"*.ps1","EVERYTHING","","Path",0,0,0,,,1,"powershellscripts",,""
"Filetypes\Links",0,"",0,0,0,0,,,,,0,"*.lnk | *.url","EVERYTHING","","Path",0,0,0,,,1,"links",,""
"File Types\Documents",0,"",0,0,0,0,,,,,0,"ext:doc;docx;pdf;odt;txt;rtf","EVERYTHING","","Name",0,,0,,,1,"docs",,""
'@

# ============================================================================
# SETTINGS DEFINITIONS
# ============================================================================

$Script:SettingsDefinitions = @{
    "Database" = @{
        "Order" = 1
        "Description" = "Controls how Everything stores and saves its index database"
        "Settings" = [ordered]@{
            "db_save_on_exit" = @{ "Type" = "Boolean"; "DisplayName" = "Save Database on Exit"; "Description" = "Save the index database when Everything closes. CRITICAL for preventing rescans."; "Recommended" = 1; "Impact" = "High" }
            "db_auto_save_on_close" = @{ "Type" = "Boolean"; "DisplayName" = "Auto-Save on Close"; "Description" = "Automatically save the database when closing."; "Recommended" = 1; "Impact" = "High" }
            "db_backup" = @{ "Type" = "Boolean"; "DisplayName" = "Enable Database Backup"; "Description" = "Create backup copies of the database file."; "Recommended" = 1; "Impact" = "Medium" }
            "db_auto_save_type" = @{ "Type" = "Combo"; "Options" = @("Disabled", "Interval", "Daily at specific time"); "DisplayName" = "Auto-Save Type"; "Description" = "How automatic saves are triggered."; "Recommended" = 2; "Impact" = "Medium" }
            "db_auto_save_at_hour" = @{ "Type" = "Number"; "DisplayName" = "Auto-Save Hour (0-23)"; "Description" = "Hour for scheduled auto-save."; "Recommended" = 4; "Min" = 0; "Max" = 23; "Impact" = "Low" }
            "db_location" = @{ "Type" = "FolderPath"; "DisplayName" = "Database Location"; "Description" = "Custom path for Everything.db."; "Recommended" = ""; "Impact" = "Medium" }
            "db_multi_user_filename" = @{ "Type" = "Boolean"; "DisplayName" = "Multi-User Database Filename"; "Description" = "Use unique database filenames per user/computer."; "Recommended" = 1; "Impact" = "Low" }
            "no_db" = @{ "Type" = "Boolean"; "DisplayName" = "Disable Database (RAM Only)"; "Description" = "CAUSES FULL RESCAN EVERY START. Only for testing."; "Recommended" = 0; "Impact" = "Critical" }
            "db_load_crc" = @{ "Type" = "Boolean"; "DisplayName" = "Verify Database CRC"; "Description" = "Check database integrity on load."; "Recommended" = 1; "Impact" = "Low" }
        }
    }
    "Indexing" = @{
        "Order" = 2
        "Description" = "Controls what file information is indexed"
        "Settings" = [ordered]@{
            "index_size" = @{ "Type" = "Boolean"; "DisplayName" = "Index File Size"; "Description" = "Store file sizes. Required for size searches."; "Recommended" = 1; "Impact" = "Medium" }
            "fast_size_sort" = @{ "Type" = "Boolean"; "DisplayName" = "Fast Size Sort"; "Description" = "Enable instant sorting by size."; "Recommended" = 1; "Impact" = "Medium" }
            "index_date_modified" = @{ "Type" = "Boolean"; "DisplayName" = "Index Date Modified"; "Description" = "Store file modification dates."; "Recommended" = 1; "Impact" = "Medium" }
            "fast_date_modified_sort" = @{ "Type" = "Boolean"; "DisplayName" = "Fast Date Modified Sort"; "Description" = "Enable instant sorting by date."; "Recommended" = 1; "Impact" = "Medium" }
            "index_date_created" = @{ "Type" = "Boolean"; "DisplayName" = "Index Date Created"; "Description" = "Store creation dates."; "Recommended" = 0; "Impact" = "Low" }
            "index_folder_size" = @{ "Type" = "Boolean"; "DisplayName" = "Index Folder Size"; "Description" = "HIGH OVERHEAD - can cause rescans."; "Recommended" = 0; "Impact" = "High" }
            "include_file_content" = @{ "Type" = "Boolean"; "DisplayName" = "Index File Content"; "Description" = "Full-text search. Very high CPU/disk usage."; "Recommended" = 0; "Impact" = "Critical" }
        }
    }
    "NTFS" = @{
        "Order" = 3
        "Description" = "NTFS-specific indexing and USN Journal settings"
        "Settings" = [ordered]@{
            "journal" = @{ "Type" = "Boolean"; "DisplayName" = "Enable USN Journal"; "Description" = "ESSENTIAL for instant updates without rescans."; "Recommended" = 1; "Impact" = "Critical" }
            "journal_max_size" = @{ "Type" = "Number"; "DisplayName" = "Journal Max Size (bytes)"; "Description" = "Default 1MB is usually sufficient."; "Recommended" = 1048576; "Min" = 65536; "Max" = 104857600; "Impact" = "Low" }
            "ntfs_open_file_by_id" = @{ "Type" = "Boolean"; "DisplayName" = "Open Files by ID"; "Description" = "Faster file access on NTFS."; "Recommended" = 1; "Impact" = "Medium" }
            "read_directory_changes" = @{ "Type" = "Boolean"; "DisplayName" = "Monitor Directory Changes"; "Description" = "Real-time monitoring."; "Recommended" = 1; "Impact" = "Medium" }
            "hardlink_monitor" = @{ "Type" = "Boolean"; "DisplayName" = "Monitor Hard Links"; "Description" = "Track hard linked files."; "Recommended" = 1; "Impact" = "Low" }
        }
    }
    "Volumes" = @{
        "Order" = 4
        "Description" = "Automatic volume detection and inclusion"
        "Settings" = [ordered]@{
            "auto_include_fixed_volumes" = @{ "Type" = "Boolean"; "DisplayName" = "Auto-Include Fixed NTFS"; "Description" = "Index new fixed NTFS drives."; "Recommended" = 1; "Impact" = "Medium" }
            "auto_include_removable_volumes" = @{ "Type" = "Boolean"; "DisplayName" = "Auto-Include Removable NTFS"; "Description" = "Index removable NTFS drives."; "Recommended" = 1; "Impact" = "Medium" }
            "auto_include_fixed_fat_volumes" = @{ "Type" = "Boolean"; "DisplayName" = "Auto-Include Fixed FAT"; "Description" = "Index FAT drives (requires rescans)."; "Recommended" = 1; "Impact" = "Low" }
            "auto_include_remote_volumes" = @{ "Type" = "Boolean"; "DisplayName" = "Auto-Include Network"; "Description" = "Index mapped network drives."; "Recommended" = 0; "Impact" = "Medium" }
        }
    }
    "Folders" = @{
        "Order" = 5
        "Description" = "Non-NTFS folder scanning settings"
        "Settings" = [ordered]@{
            "folder_update_rescan_asap" = @{ "Type" = "Boolean"; "DisplayName" = "Rescan Folders ASAP"; "Description" = "Rescan immediately on startup."; "Recommended" = 1; "Impact" = "High" }
            "folder_background_index" = @{ "Type" = "Boolean"; "DisplayName" = "Background Folder Indexing"; "Description" = "Scan in background thread."; "Recommended" = 0; "Impact" = "Medium" }
            "folder_rescan_timeout" = @{ "Type" = "Number"; "DisplayName" = "Folder Rescan Timeout (ms)"; "Description" = "Time between rescans."; "Recommended" = 10000; "Min" = 1000; "Max" = 3600000; "Impact" = "Low" }
        }
    }
    "Performance" = @{
        "Order" = 6
        "Description" = "Threading and performance tuning"
        "Settings" = [ordered]@{
            "max_threads" = @{ "Type" = "Number"; "DisplayName" = "Max Threads (0=Auto)"; "Description" = "Maximum worker threads."; "Recommended" = 0; "Min" = 0; "Max" = 64; "Impact" = "Medium" }
            "reuse_threads" = @{ "Type" = "Boolean"; "DisplayName" = "Reuse Threads"; "Description" = "Reduces overhead."; "Recommended" = 1; "Impact" = "Low" }
            "mem_trim" = @{ "Type" = "Boolean"; "DisplayName" = "Memory Trim"; "Description" = "Release unused memory."; "Recommended" = 1; "Impact" = "Low" }
            "no_incur_seek_penalty_multithreaded" = @{ "Type" = "Boolean"; "DisplayName" = "SSD Multi-Thread"; "Description" = "Multiple threads on SSDs."; "Recommended" = 1; "Impact" = "Medium" }
            "separate_device_thread" = @{ "Type" = "Boolean"; "DisplayName" = "Separate Thread Per Device"; "Description" = "Parallel scanning."; "Recommended" = 1; "Impact" = "Medium" }
        }
    }
    "Interface" = @{
        "Order" = 7
        "Description" = "Window, tray, and display settings"
        "Settings" = [ordered]@{
            "run_in_background" = @{ "Type" = "Boolean"; "DisplayName" = "Run in Background"; "Description" = "Keep running for instant searches."; "Recommended" = 1; "Impact" = "High" }
            "show_tray_icon" = @{ "Type" = "Boolean"; "DisplayName" = "Show Tray Icon"; "Description" = "System tray icon."; "Recommended" = 1; "Impact" = "Low" }
            "minimize_to_tray" = @{ "Type" = "Boolean"; "DisplayName" = "Minimize to Tray"; "Description" = "Minimize to tray instead of taskbar."; "Recommended" = 0; "Impact" = "Low" }
            "show_in_taskbar" = @{ "Type" = "Boolean"; "DisplayName" = "Show in Taskbar"; "Description" = "Show in Windows taskbar."; "Recommended" = 1; "Impact" = "Low" }
            "theme" = @{ "Type" = "Combo"; "Options" = @("System", "Light", "Dark"); "DisplayName" = "Theme"; "Description" = "Color theme."; "Recommended" = 0; "Impact" = "Low" }
            "zoom" = @{ "Type" = "Number"; "DisplayName" = "Zoom Level (%)"; "Description" = "Interface zoom."; "Recommended" = 100; "Min" = 50; "Max" = 400; "Impact" = "Low" }
        }
    }
    "History" = @{
        "Order" = 8
        "Description" = "Search and run history settings"
        "Settings" = [ordered]@{
            "search_history_enabled" = @{ "Type" = "Boolean"; "DisplayName" = "Enable Search History"; "Description" = "Remember previous searches."; "Recommended" = 1; "Impact" = "Low" }
            "run_history_enabled" = @{ "Type" = "Boolean"; "DisplayName" = "Enable Run History"; "Description" = "Track opened files."; "Recommended" = 1; "Impact" = "Low" }
            "search_history_days_to_keep" = @{ "Type" = "Number"; "DisplayName" = "Search History Days"; "Description" = "Days to keep history."; "Recommended" = 90; "Min" = 1; "Max" = 3650; "Impact" = "Low" }
            "undo_history" = @{ "Type" = "Boolean"; "DisplayName" = "Enable Undo History"; "Description" = "Track operations for undo."; "Recommended" = 1; "Impact" = "Low" }
        }
    }
    "Advanced" = @{
        "Order" = 9
        "Description" = "Backup and debugging options"
        "Settings" = [ordered]@{
            "ini_backup" = @{ "Type" = "Boolean"; "DisplayName" = "Backup INI File"; "Description" = "Backup settings file."; "Recommended" = 1; "Impact" = "Low" }
            "csv_backup" = @{ "Type" = "Boolean"; "DisplayName" = "Backup CSV Files"; "Description" = "Backup CSV data files."; "Recommended" = 1; "Impact" = "Low" }
            "debug" = @{ "Type" = "Boolean"; "DisplayName" = "Debug Mode"; "Description" = "Debug information."; "Recommended" = 0; "Impact" = "Low" }
            "debug_log" = @{ "Type" = "Boolean"; "DisplayName" = "Debug Logging"; "Description" = "Write debug log."; "Recommended" = 0; "Impact" = "Low" }
            "plugins" = @{ "Type" = "Boolean"; "DisplayName" = "Enable Plugins"; "Description" = "Allow plugins."; "Recommended" = 1; "Impact" = "Low" }
        }
    }
    "Exclusions" = @{
        "Order" = 10
        "Description" = "Paths and file patterns Everything should leave out of the index"
        "Settings" = [ordered]@{
            "exclude_folders" = @{ "Type" = "Text"; "DisplayName" = "Excluded Folders"; "Description" = "Semicolon-separated folders excluded from indexing. One path per line is also accepted."; "Recommended" = ""; "Impact" = "High" }
            "exclude_files" = @{ "Type" = "Text"; "DisplayName" = "Excluded File Patterns"; "Description" = "Semicolon-separated file patterns excluded from indexing."; "Recommended" = ""; "Impact" = "Medium" }
            "include_only_folders" = @{ "Type" = "Text"; "DisplayName" = "Include-Only Folders"; "Description" = "Optional folder allow-list. Leave empty to index all eligible locations."; "Recommended" = ""; "Impact" = "High" }
        }
    }
}

# Add schema metadata in one place so newly discovered Everything keys remain
# editable without being silently rewritten or lost on the next save.
$Script:OnePointFiveKeys = @(
    'include_file_content', 'content_max_size', 'content_max_file_size',
    'exclude_folders', 'exclude_files', 'include_only_folders',
    'folder_background_index', 'journal_max_size'
)
foreach ($category in $Script:SettingsDefinitions.Values) {
    foreach ($settingKey in $category.Settings.Keys) {
        $definition = $category.Settings[$settingKey]
        if (-not $definition.ContainsKey('FactoryDefault')) { $definition.FactoryDefault = $definition.Recommended }
        if (-not $definition.ContainsKey('Since')) { $definition.Since = if ($Script:OnePointFiveKeys -contains $settingKey) { '1.5+' } else { '1.4+' } }
        if (-not $definition.ContainsKey('ForumUrl')) { $definition.ForumUrl = 'https://www.voidtools.com/support/everything/ini/' }
    }
}

$Script:PresetDefinitions = [ordered]@{
    'Recommended' = @{ Description = 'Balanced defaults for a responsive, durable index'; Overrides = @{} }
    'Safe' = @{ Description = 'Conservative settings that minimize rescans and storage overhead'; Overrides = @{
            'no_db' = '0'; 'include_file_content' = '0'; 'index_folder_size' = '0'; 'auto_include_remote_volumes' = '0';
            'folder_background_index' = '1'; 'journal' = '1'; 'db_save_on_exit' = '1'; 'db_auto_save_on_close' = '1'
        } }
    'Privacy' = @{ Description = 'Minimize local history and content indexing while keeping core search available'; Overrides = @{
            'search_history_enabled' = '0'; 'run_history_enabled' = '0'; 'include_file_content' = '0'; 'debug' = '0'; 'debug_log' = '0'
        } }
    'Performance' = @{ Description = 'Favor fast sorting and parallel indexing on capable hardware'; Overrides = @{
            'index_size' = '1'; 'fast_size_sort' = '1'; 'index_date_modified' = '1'; 'fast_date_modified_sort' = '1';
            'reuse_threads' = '1'; 'separate_device_thread' = '1'; 'mem_trim' = '1'; 'include_file_content' = '0'
        } }
    'PowerUser' = @{ Description = 'Expose advanced indexing features for deliberate, higher-cost configurations'; Overrides = @{
            'include_file_content' = '1'; 'index_folder_size' = '1'; 'auto_include_remote_volumes' = '1'; 'debug' = '0'; 'plugins' = '1'
        } }
}

$Script:FilterPresetLibrary = [ordered]@{
    'Code files' = @{ Description = 'Common source, build, and configuration files'; Search = 'ext:c;cc;cpp;h;hpp;cs;java;py;js;ts;go;rs;rb;php;html;css;json;xml;yaml;yml;toml;sql;sh;ps1' }
    'Media files' = @{ Description = 'Audio, image, and video files'; Search = 'ext:3gp;avi;flac;gif;heic;jpeg;jpg;m4a;mkv;mov;mp3;mp4;ogg;png;wav;webm;webp;wmv' }
    'Installers' = @{ Description = 'Installers and package archives'; Search = 'ext:exe;msi;msix;appx;cab;iso;7z;rar;zip' }
    'Archives' = @{ Description = 'Compressed archive formats'; Search = 'ext:7z;ace;arj;bz2;cab;gz;gzip;jar;rar;tar;tgz;zip' }
    'Screenshots' = @{ Description = 'Common screenshot names and image formats'; Search = 'regex:.*(screenshot|screen.?shot|snip).* ext:png;jpg;jpeg;webp' }
    'Documents' = @{ Description = 'Office, text, and portable document formats'; Search = 'ext:doc;docx;epub;md;odt;pdf;ppt;pptx;rtf;txt;xls;xlsx' }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Read-IniFile {
    param([string]$Path)
    $ini = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $ini }
    try { $content = [System.IO.File]::ReadAllText($Path) } catch { return $ini }
    $newline = if ($content -match "`r`n") { "`r`n" } elseif ($content -match "`r") { "`r" } else { "`n" }
    $hadTrailingNewline = $content.EndsWith("`r`n") -or $content.EndsWith("`n") -or $content.EndsWith("`r")
    $lines = @($content -split "`r`n|`n|`r")
    foreach ($line in $lines) {
        if ($line -match '^\s*([^=;#]+?)\s*=\s*(.*)$') {
            $ini[$Matches[1].Trim()] = $Matches[2]
        }
    }
    $Script:IniDocumentCache[$Path] = [pscustomobject]@{
        Path = $Path
        Lines = $lines
        Newline = $newline
        HadTrailingNewline = $hadTrailingNewline
        HasBom = $content.Length -gt 0 -and [int]$content[0] -eq 0xFEFF
    }
    return $ini
}

function Write-IniFile {
    param(
        [string]$Path,
        [System.Collections.IDictionary]$Settings,
        [switch]$SkipValidation
    )
    if (-not $Path -or -not $Settings) { throw 'An INI path and settings dictionary are required.' }
    if (-not $SkipValidation) {
        $issues = @(Test-Settings -Settings $Settings)
        if ($issues.Count -gt 0) { throw (($issues | ForEach-Object { $_.Message }) -join [Environment]::NewLine) }
    }
    if (-not $Script:IniDocumentCache.ContainsKey($Path)) { Read-IniFile -Path $Path | Out-Null }
    $document = $Script:IniDocumentCache[$Path]
    if (-not $document) {
        $document = [pscustomobject]@{ Path = $Path; Lines = @(); Newline = "`r`n"; HadTrailingNewline = $true; HasBom = $false }
    }
    $lines = @($document.Lines)
    $updated = @{}
    $newLines = @()
    foreach ($line in $lines) {
        $match = [regex]::Match([string]$line, '^\s*([^=;#]+?)\s*=\s*(.*)$')
        if ($match.Success) {
            $key = $match.Groups[1].Value.Trim()
            if ($Settings.ContainsKey($key)) {
                $prefix = $line.Substring(0, $match.Groups[2].Index)
                $newLines += "$prefix$($Settings[$key])"
                $updated[$key] = $true
            } else { $newLines += $line }
        } else { $newLines += $line }
    }
    foreach ($key in $Settings.Keys) {
        if (-not $updated.ContainsKey($key)) { $newLines += "$key=$($Settings[$key])" }
    }
    $output = [string]::Join($document.Newline, [string[]]$newLines)
    if ($document.HadTrailingNewline -or $newLines.Count -eq 0) { $output += $document.Newline }
    $encoding = New-Object System.Text.UTF8Encoding($document.HasBom)
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $tempPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($tempPath, $output, $encoding)
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
    $Script:IniDocumentCache.Remove($Path)
    Read-IniFile -Path $Path | Out-Null
    return $Path
}

function Read-CsvFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    try { return @(Import-Csv -Path $Path -ErrorAction Stop) }
    catch { return @() }
}

function Write-CsvFile {
    param(
        [string]$Path,
        [array]$Data,
        [string[]]$Headers
    )
    if ($Data.Count -gt 0) {
        $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    } elseif ($Headers -and $Headers.Count -gt 0) {
        Set-Content -LiteralPath $Path -Value ($Headers -join ',') -Encoding UTF8
    } else {
        Set-Content -LiteralPath $Path -Value '' -Encoding UTF8
    }
}

function Backup-File {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { throw "Cannot back up missing file: $Path" }
    if (-not (Test-Path -LiteralPath $Script:BackupFolder)) {
        New-Item -ItemType Directory -Path $Script:BackupFolder -Force | Out-Null
    }
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $backupPath = Join-Path $Script:BackupFolder "${fileName}_${timestamp}${ext}"
    $suffix = 1
    while (Test-Path -LiteralPath $backupPath) {
        $backupPath = Join-Path $Script:BackupFolder "${fileName}_${timestamp}_$suffix${ext}"
        $suffix++
    }
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Prune-Backups -BaseName $fileName -Extension $ext -RetentionCount $Script:BackupRetentionCount
    return $backupPath
}

function Prune-Backups {
    param(
        [string]$BaseName,
        [string]$Extension,
        [int]$RetentionCount = 10
    )
    if ($RetentionCount -lt 1 -or -not (Test-Path -LiteralPath $Script:BackupFolder)) { return }
    $pattern = if ($Extension) { "${BaseName}_*${Extension}" } else { "${BaseName}_*" }
    $backups = @(Get-ChildItem -LiteralPath $Script:BackupFolder -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($backup in ($backups | Select-Object -Skip $RetentionCount)) {
        Remove-Item -LiteralPath $backup.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Test-EverythingRunning {
    return $null -ne (Get-Process -Name "Everything*" -ErrorAction SilentlyContinue)
}

function Stop-Everything {
    $processes = Get-Process -Name "Everything*" -ErrorAction SilentlyContinue
    if ($processes) {
        foreach ($proc in $processes) {
            $proc.CloseMainWindow() | Out-Null
            Start-Sleep -Milliseconds 500
            if (-not $proc.HasExited) { $proc.Kill() }
        }
        return $true
    }
    return $false
}

function Start-Everything {
    $paths = @("${env:ProgramFiles}\Everything\Everything.exe", "${env:ProgramFiles}\Everything 1.5a\Everything.exe", "${env:ProgramFiles(x86)}\Everything\Everything.exe")
    $everythingPath = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($everythingPath) { Start-Process $everythingPath; return $true }
    return $false
}

function Convert-FileTimeToDateTime {
    param([long]$FileTime)
    if ($FileTime -le 0) { return "" }
    try { return [DateTime]::FromFileTime($FileTime).ToString("yyyy-MM-dd HH:mm:ss") }
    catch { return "" }
}

function Get-SettingDefinition {
    param([string]$Key)
    foreach ($category in $Script:SettingsDefinitions.Values) {
        if ($category.Settings.Contains($Key)) { return $category.Settings[$Key] }
    }
    return $null
}

function Add-DiscoveredSettings {
    param([System.Collections.IDictionary]$Settings)
    if (-not $Settings) { return }
    if (-not $Script:SettingsDefinitions.ContainsKey('Discovered')) {
        $Script:SettingsDefinitions['Discovered'] = @{
            Order = 90
            Description = 'Keys found in the selected Everything INI that are not yet in the built-in schema.'
            Settings = [ordered]@{}
        }
    }
    foreach ($key in $Settings.Keys) {
        if (-not (Get-SettingDefinition -Key $key)) {
            $Script:SettingsDefinitions['Discovered'].Settings[$key] = @{
                Type = 'Text'
                DisplayName = $key
                Description = 'Discovered from the selected Everything INI. The original value is preserved.'
                Recommended = [string]$Settings[$key]
                FactoryDefault = [string]$Settings[$key]
                Since = 'Detected'
                Impact = 'Unknown'
                ForumUrl = 'https://www.voidtools.com/support/everything/ini/'
            }
        }
    }
}

function Test-Settings {
    param([System.Collections.IDictionary]$Settings)
    $issues = @()
    if (-not $Settings) { return $issues }
    foreach ($key in $Settings.Keys) {
        $definition = Get-SettingDefinition -Key $key
        if (-not $definition) { continue }
        $value = [string]$Settings[$key]
        switch ($definition.Type) {
            'Boolean' {
                if ($value -notin @('0', '1')) {
                    $issues += [pscustomobject]@{ Key = $key; Value = $value; Message = "$key must be 0 or 1 (received '$value')." }
                }
            }
            'Number' {
                $number = 0L
                if (-not [long]::TryParse($value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
                    $issues += [pscustomobject]@{ Key = $key; Value = $value; Message = "$key must be an integer (received '$value')." }
                } else {
                    if ($definition.ContainsKey('Min') -and $number -lt [long]$definition.Min) { $issues += [pscustomobject]@{ Key = $key; Value = $value; Message = "$key must be at least $($definition.Min)." } }
                    if ($definition.ContainsKey('Max') -and $number -gt [long]$definition.Max) { $issues += [pscustomobject]@{ Key = $key; Value = $value; Message = "$key must be at most $($definition.Max)." } }
                }
            }
            'Combo' {
                $index = -1
                if (-not [int]::TryParse($value, [ref]$index) -or $index -lt 0 -or $index -ge $definition.Options.Count) {
                    $issues += [pscustomobject]@{ Key = $key; Value = $value; Message = "$key must be a valid option index." }
                }
            }
        }
    }
    return $issues
}

function Get-PresetSettings {
    param([ValidateSet('Recommended', 'Safe', 'Privacy', 'Performance', 'PowerUser')][string]$PresetName = 'Recommended')
    if (-not $Script:PresetDefinitions.Contains($PresetName)) { throw "Unknown preset: $PresetName" }
    $preset = @{}
    foreach ($category in $Script:SettingsDefinitions.Values) {
        foreach ($key in $category.Settings.Keys) {
            $definition = $category.Settings[$key]
            if ($definition.ContainsKey('Recommended')) { $preset[$key] = [string]$definition.Recommended }
        }
    }
    foreach ($key in $Script:PresetDefinitions[$PresetName].Overrides.Keys) {
        $preset[$key] = [string]$Script:PresetDefinitions[$PresetName].Overrides[$key]
    }
    return $preset
}

function Copy-SettingsDictionary {
    param([System.Collections.IDictionary]$Settings)
    $copy = @{}
    if ($Settings) { foreach ($key in $Settings.Keys) { $copy[$key] = [string]$Settings[$key] } }
    return $copy
}

function Push-SettingsUndoSnapshot {
    param([System.Collections.IDictionary]$Settings)
    if ($Settings) { $Script:UndoStack.Push((Copy-SettingsDictionary -Settings $Settings)) }
    $Script:RedoStack.Clear()
}

function Apply-PresetToSettings {
    param(
        [System.Collections.IDictionary]$Settings,
        [ValidateSet('Recommended', 'Safe', 'Privacy', 'Performance', 'PowerUser')][string]$PresetName = 'Recommended'
    )
    if (-not $Settings) { throw 'A settings dictionary is required.' }
    Push-SettingsUndoSnapshot -Settings $Settings
    $preset = Get-PresetSettings -PresetName $PresetName
    $changes = @{}
    foreach ($key in $preset.Keys) {
        $newValue = [string]$preset[$key]
        $oldValue = if ($Settings.ContainsKey($key)) { [string]$Settings[$key] } else { $null }
        $Settings[$key] = $newValue
        if ($oldValue -ne $newValue) { $changes[$key] = $newValue }
    }
    return $changes
}

function Undo-SettingsChange {
    param([System.Collections.IDictionary]$Settings)
    if (-not $Settings -or $Script:UndoStack.Count -eq 0) { return $false }
    $Script:RedoStack.Push((Copy-SettingsDictionary -Settings $Settings))
    $snapshot = $Script:UndoStack.Pop()
    $Settings.Clear()
    foreach ($key in $snapshot.Keys) { $Settings[$key] = $snapshot[$key] }
    return $true
}

function Redo-SettingsChange {
    param([System.Collections.IDictionary]$Settings)
    if (-not $Settings -or $Script:RedoStack.Count -eq 0) { return $false }
    $Script:UndoStack.Push((Copy-SettingsDictionary -Settings $Settings))
    $snapshot = $Script:RedoStack.Pop()
    $Settings.Clear()
    foreach ($key in $snapshot.Keys) { $Settings[$key] = $snapshot[$key] }
    return $true
}

function Get-SettingsDiff {
    param(
        [System.Collections.IDictionary]$Settings,
        [switch]$IncludeUnchanged
    )
    $rows = @()
    foreach ($categoryEntry in ($Script:SettingsDefinitions.GetEnumerator() | Sort-Object { $_.Value.Order })) {
        foreach ($key in $categoryEntry.Value.Settings.Keys) {
            $definition = $categoryEntry.Value.Settings[$key]
            $current = if ($Settings -and $Settings.ContainsKey($key)) { [string]$Settings[$key] } else { '<missing>' }
            $default = if ($definition.ContainsKey('FactoryDefault')) { [string]$definition.FactoryDefault } else { [string]$definition.Recommended }
            $different = $current -ne $default
            if ($IncludeUnchanged -or $different) {
                $rows += [pscustomobject]@{ Category = $categoryEntry.Key; Key = $key; Current = $current; FactoryDefault = $default; Different = $different; Impact = $definition.Impact }
            }
        }
    }
    return $rows
}

function Get-IndexImpactEstimate {
    param([System.Collections.IDictionary]$Settings)
    $warnings = @()
    if ($Settings['include_file_content'] -eq '1') { $warnings += 'Content indexing can substantially increase CPU, disk, and database usage.' }
    if ($Settings['index_folder_size'] -eq '1') { $warnings += 'Folder-size indexing adds rescans and directory traversal overhead.' }
    if ($Settings['auto_include_remote_volumes'] -eq '1') { $warnings += 'Network volume indexing depends on connection quality and can be slow.' }
    if ($Settings['auto_include_removable_volumes'] -eq '1') { $warnings += 'Removable-volume indexing may trigger work whenever a drive is connected.' }
    if ($Settings['journal'] -ne '1') { $warnings += 'Disabling the USN Journal removes the fastest change-tracking path and may cause rescans.' }
    if ($warnings.Count -eq 0) { $warnings += 'The selected configuration favors a low-overhead, journal-backed index.' }
    [pscustomobject]@{ Level = if ($warnings.Count -ge 3) { 'High' } elseif ($warnings.Count -eq 2) { 'Medium' } else { 'Low' }; Warnings = @($warnings) }
}

function Get-ExclusionSummary {
    param([System.Collections.IDictionary]$Settings)
    $rows = @()
    foreach ($key in @('exclude_folders', 'exclude_files', 'include_only_folders')) {
        $raw = if ($Settings -and $Settings.ContainsKey($key)) { [string]$Settings[$key] } else { '' }
        $items = @($raw -split '[;`r`n]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $rows += [pscustomobject]@{ Key = $key; Count = $items.Count; Entries = $items; ExistingPaths = @($items | Where-Object { Test-Path -LiteralPath $_ }).Count }
    }
    return $rows
}

function Resolve-EverythingIniPath {
    param([string]$RequestedPath)
    if ($RequestedPath -and (Test-Path -LiteralPath $RequestedPath)) { return [System.IO.Path]::GetFullPath($RequestedPath) }
    if ($Script:EverythingIniPath -and (Test-Path -LiteralPath $Script:EverythingIniPath)) { return [System.IO.Path]::GetFullPath($Script:EverythingIniPath) }
    return Find-EverythingIniFile -Folder $Script:EverythingFolder
}

function Get-EverythingServiceState {
    $service = Get-Service -Name 'Everything' -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Installed = $null -ne $service
        Status = if ($service) { [string]$service.Status } else { 'Not installed' }
        StartType = if ($service) { [string]$service.StartType } else { $null }
        DisplayName = if ($service) { $service.DisplayName } else { 'Everything service' }
    }
}

function Get-EverythingProfileCandidates {
    param([string]$Folder = $Script:EverythingFolder)
    $candidates = @(Get-EverythingIniCandidates -Folder $Folder)
    $profiles = @()
    foreach ($candidate in $candidates) {
        $profiles += [pscustomobject]@{
            DisplayName = "$($candidate.Name) [$($candidate.Source)]"
            Path = $candidate.Path
            Name = $candidate.Name
            Source = $candidate.Source
            Mode = $candidate.Mode
            IsService = $candidate.IsService
            LastWriteTime = $candidate.LastWriteTime
            Version = $candidate.Version
        }
    }
    return $profiles
}

function Get-BackupFiles {
    param([string]$SourcePath)
    if (-not (Test-Path -LiteralPath $Script:BackupFolder)) { return @() }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
    $extension = [System.IO.Path]::GetExtension($SourcePath)
    Get-ChildItem -LiteralPath $Script:BackupFolder -Filter "${baseName}_*${extension}" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
}

function Restore-BackupFile {
    param(
        [string]$SourcePath,
        [string]$BackupPath
    )
    if (-not (Test-Path -LiteralPath $BackupPath)) { throw "Backup not found: $BackupPath" }
    if (-not $SourcePath) { throw 'A destination path is required.' }
    if (Test-Path -LiteralPath $SourcePath) { Backup-File -Path $SourcePath | Out-Null }
    Copy-Item -LiteralPath $BackupPath -Destination $SourcePath -Force
    $Script:IniDocumentCache.Remove($SourcePath)
    return $SourcePath
}

function ConvertTo-SimpleYaml {
    param([System.Collections.IDictionary]$Values)
    $lines = @()
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value = [string]$Values[$key]
        $escaped = $value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '\n')
        $lines += "${key}: `"$escaped`""
    }
    return [string]::Join("`r`n", $lines) + "`r`n"
}

function ConvertTo-RegText {
    param([System.Collections.IDictionary]$Settings)
    $lines = @('Windows Registry Editor Version 5.00', '', '[HKEY_CURRENT_USER\Software\VoidTools\EverythingSettingsManager]')
    foreach ($key in ($Settings.Keys | Sort-Object)) {
        $value = ([string]$Settings[$key]).Replace('\', '\\').Replace('"', '\"')
        $lines += '"{0}"="{1}"' -f $key, $value
    }
    return [string]::Join("`r`n", $lines) + "`r`n"
}

function Export-SettingsSnapshot {
    param(
        [string]$Path,
        [System.Collections.IDictionary]$Settings,
        [string]$IniFilePath
    )
    if (-not $Path -or -not $Settings) { throw 'An export path and settings dictionary are required.' }
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $payload = [ordered]@{
        schemaVersion = 1
        applicationVersion = $Script:AppVersion
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        iniPath = $IniFilePath
        settings = [ordered]@{}
        impact = Get-IndexImpactEstimate -Settings $Settings
    }
    foreach ($key in ($Settings.Keys | Sort-Object)) { $payload.settings[$key] = [string]$Settings[$key] }
    $content = switch ($extension) {
        '.json' { $payload | ConvertTo-Json -Depth 8 }
        '.yaml' { ConvertTo-SimpleYaml -Values $payload.settings }
        '.yml' { ConvertTo-SimpleYaml -Values $payload.settings }
        '.reg' { ConvertTo-RegText -Settings $payload.settings }
        default { $payload | ConvertTo-Json -Depth 8 }
    }
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
    return $Path
}

function Export-SettingsBundle {
    param(
        [string]$OutputPath,
        [string]$Folder = $Script:EverythingFolder,
        [string]$SelectedIniPath
    )
    if (-not $OutputPath) { throw 'A bundle output path is required.' }
    if (-not (Test-Path -LiteralPath $Folder)) { throw "Everything folder not found: $Folder" }
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("EverythingSettingsBundle_" + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $files = @(Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.ini', '.csv') -and $_.Name -notmatch '(?i)backup' })
        if ($SelectedIniPath -and (Test-Path -LiteralPath $SelectedIniPath) -and -not ($files.FullName -contains $SelectedIniPath)) { $files += Get-Item -LiteralPath $SelectedIniPath }
        foreach ($file in $files) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $stage $file.Name) -Force }
        $iniForExport = if ($SelectedIniPath) { $SelectedIniPath } else { Resolve-EverythingIniPath }
        if ($iniForExport -and (Test-Path -LiteralPath $iniForExport)) {
            $settings = Read-IniFile -Path $iniForExport
            Export-SettingsSnapshot -Path (Join-Path $stage 'settings.json') -Settings $settings -IniFilePath $iniForExport | Out-Null
        }
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $OutputPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        } catch {
            Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutputPath -CompressionLevel Optimal
        }
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return $OutputPath
}

function Import-SettingsBundle {
    param(
        [string]$BundlePath,
        [string]$DestinationFolder = $Script:EverythingFolder
    )
    if (-not (Test-Path -LiteralPath $BundlePath)) { throw "Bundle not found: $BundlePath" }
    if (-not (Test-Path -LiteralPath $DestinationFolder)) { New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null }
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("EverythingSettingsImport_" + [guid]::NewGuid().ToString('N'))
    $copied = @()
    try {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            [System.IO.Compression.ZipFile]::ExtractToDirectory($BundlePath, $stage)
        } catch {
            Expand-Archive -LiteralPath $BundlePath -DestinationPath $stage -Force
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $stage -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.ini', '.csv') })) {
            $destination = Join-Path $DestinationFolder $file.Name
            if (Test-Path -LiteralPath $destination) { Backup-File -Path $destination | Out-Null }
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            $copied += $destination
        }
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return $copied
}

function Export-EverythingAdmx {
    param([string]$OutputPath)
    if (-not $OutputPath) { throw 'An ADMX output folder or file path is required.' }
    if ([System.IO.Path]::GetExtension($OutputPath).ToLowerInvariant() -eq '.admx') {
        $folder = Split-Path -Parent $OutputPath
        $admxPath = $OutputPath
    } else {
        $folder = $OutputPath
        $admxPath = Join-Path $folder 'EverythingSettingsManager.admx'
    }
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $admlFolder = Join-Path $folder 'en-US'
    if (-not (Test-Path -LiteralPath $admlFolder)) { New-Item -ItemType Directory -Path $admlFolder -Force | Out-Null }
    $admx = @'
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitions revision="1.0" schemaVersion="1.0" xmlns="http://schemas.microsoft.com/GroupPolicy/2006/07/PolicyDefinitions">
  <policyNamespaces><target prefix="esm" namespace="VoidTools.EverythingSettingsManager"/><using prefix="windows" namespace="Microsoft.Policies.Windows"/></policyNamespaces>
  <resources minRequiredRevision="1.0"/>
  <categories><category name="EverythingSettingsManager" displayName="$(string.Category)"/></categories>
  <policies>
    <policy name="ApplyPreset" class="Both" displayName="$(string.ApplyPreset)" explainText="$(string.ApplyPresetExplain)" key="Software\VoidTools\EverythingSettingsManager">
      <parentCategory ref="EverythingSettingsManager"/>
      <supportedOn ref="windows:SUPPORTED_Windows10"/>
      <elements><enum id="Preset" valueName="Preset" required="true"><item displayName="$(string.Recommended)"><value><string>Recommended</string></value></item><item displayName="$(string.Safe)"><value><string>Safe</string></value></item><item displayName="$(string.Privacy)"><value><string>Privacy</string></value></item><item displayName="$(string.Performance)"><value><string>Performance</string></value></item><item displayName="$(string.PowerUser)"><value><string>PowerUser</string></value></item></enum></elements>
    </policy>
  </policies>
</policyDefinitions>
'@
    $adml = @'
<?xml version="1.0" encoding="utf-8"?>
<policyDefinitionResources revision="1.0" schemaVersion="1.0" xmlns="http://schemas.microsoft.com/GroupPolicy/2006/07/PolicyDefinitionResources">
  <displayName/><description/><resources><stringTable><string id="Category">Everything Settings Manager</string><string id="ApplyPreset">Everything Settings Manager preset</string><string id="ApplyPresetExplain">Select the preset that the scheduled or managed deployment should apply.</string><string id="Recommended">Recommended</string><string id="Safe">Safe</string><string id="Privacy">Privacy</string><string id="Performance">Performance</string><string id="PowerUser">PowerUser</string></stringTable></resources>
</policyDefinitionResources>
'@
    Set-Content -LiteralPath $admxPath -Value $admx -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $admlFolder 'EverythingSettingsManager.adml') -Value $adml -Encoding UTF8
    return $admxPath
}

function Register-EverythingReapplyTask {
    param([int]$IntervalMinutes = 60)
    if ($IntervalMinutes -lt 1) { throw 'The schedule interval must be at least one minute.' }
    $taskName = 'Everything Settings Manager - Reapply Recommended'
    $scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ApplyPreset Recommended -Silent"
    $result = & schtasks.exe /Create /TN $taskName /SC MINUTE /MO $IntervalMinutes /TR "powershell.exe $arguments" /F 2>&1
    if ($LASTEXITCODE -ne 0) { throw (($result | Out-String).Trim()) }
    return $taskName
}

function Get-EverythingHealthReport {
    param([string]$SelectedIniPath)
    $path = Resolve-EverythingIniPath -RequestedPath $SelectedIniPath
    $settings = if ($path) { Read-IniFile -Path $path } else { @{} }
    Add-DiscoveredSettings -Settings $settings
    $backups = if ($path) { @(Get-BackupFiles -SourcePath $path) } else { @() }
    [pscustomobject]@{
        schemaVersion = 1
        applicationVersion = $Script:AppVersion
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        everythingFolder = $Script:EverythingFolder
        iniPath = $path
        profiles = @(Get-EverythingProfileCandidates)
        installation = @(Get-EverythingInstallationCandidates)
        service = Get-EverythingServiceState
        running = Test-EverythingRunning
        ipc = Test-EverythingIpc
        settingsIssues = @(Test-Settings -Settings $settings)
        differingSettings = @(Get-SettingsDiff -Settings $settings).Count
        backupCount = $backups.Count
        latestBackup = if ($backups.Count -gt 0) { $backups[0].FullName } else { $null }
        impact = Get-IndexImpactEstimate -Settings $settings
        exclusions = @(Get-ExclusionSummary -Settings $settings)
    }
}

function Invoke-ApplyPresetCli {
    param([string]$PresetName, [switch]$RestartEverything, [switch]$Quiet)
    $path = Resolve-EverythingIniPath -RequestedPath $IniPath
    if (-not $path) { throw "No Everything INI file was found in $Script:EverythingFolder." }
    if ((Test-EverythingRunning) -and -not $RestartEverything) { throw 'Everything is running. Re-run with -Restart so the INI can be changed safely.' }
    $wasRunning = Test-EverythingRunning
    if ($wasRunning -and $RestartEverything) { Stop-Everything | Out-Null; Start-Sleep -Milliseconds 500 }
    try {
        $settings = Read-IniFile -Path $path
        Add-DiscoveredSettings -Settings $settings
        $changes = Apply-PresetToSettings -Settings $settings -PresetName $PresetName
        if ($changes.Count -gt 0) {
            $backup = Backup-File -Path $path
            Write-IniFile -Path $path -Settings $settings
        } else { $backup = $null }
        $result = [pscustomobject]@{ preset = $PresetName; iniPath = $path; changed = $changes.Count; backup = $backup; restarted = $false }
    } finally {
        if ($wasRunning -and $RestartEverything) { Start-Everything | Out-Null; $result.restarted = $true }
    }
    if (-not $Quiet) { $result | ConvertTo-Json -Depth 8 | Write-Output }
    return $result
}

function Invoke-CliRequest {
    if ($ImportBundlePath) { Import-SettingsBundle -BundlePath $ImportBundlePath -DestinationFolder $Script:EverythingFolder | ConvertTo-Json | Write-Output }
    if ($ApplyPreset) { Invoke-ApplyPresetCli -PresetName $ApplyPreset -RestartEverything:$Restart -Quiet:$Silent | Out-Null }
    if ($ExportSettingsPath) {
        $path = Resolve-EverythingIniPath -RequestedPath $IniPath
        if (-not $path) { throw 'No Everything INI file was found for export.' }
        Export-SettingsSnapshot -Path $ExportSettingsPath -Settings (Read-IniFile -Path $path) -IniFilePath $path | Write-Output
    }
    if ($ExportBundlePath) { Export-SettingsBundle -OutputPath $ExportBundlePath -Folder $Script:EverythingFolder -SelectedIniPath (Resolve-EverythingIniPath -RequestedPath $IniPath) | Write-Output }
    if ($ExportAdmxPath) { Export-EverythingAdmx -OutputPath $ExportAdmxPath | Write-Output }
    if ($HealthReportPath) {
        $report = Get-EverythingHealthReport -SelectedIniPath $IniPath
        $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $HealthReportPath -Encoding UTF8
        if (-not $Silent) { $HealthReportPath | Write-Output }
    }
    if ($TestIpc) { Test-EverythingIpc | ConvertTo-Json -Depth 5 | Write-Output }
    if ($ScheduleIntervalMinutes -gt 0) { Register-EverythingReapplyTask -IntervalMinutes $ScheduleIntervalMinutes | Write-Output }
}

function Test-EverythingIpc {
    $processes = @(Get-Process -Name 'Everything*' -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return [pscustomobject]@{ Available = $false; Running = $false; Responsive = $false; WindowHandle = '0'; Message = 'Everything is not running.' }
    }
    if (-not ('EverythingSettingsManager_NativeMethods' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class EverythingSettingsManager_NativeMethods {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
}
"@ -ErrorAction SilentlyContinue
    }
    $handle = [IntPtr]::Zero
    $found = [EverythingSettingsManager_NativeMethods]::FindWindow('EVERYTHING', $null)
    if ($found -eq [IntPtr]::Zero) { $found = [EverythingSettingsManager_NativeMethods]::FindWindow('Everything', $null) }
    if ($found -eq [IntPtr]::Zero) {
        foreach ($process in $processes) {
            if ($process.MainWindowHandle -ne 0) { $found = $process.MainWindowHandle; break }
        }
    }
    $result = [IntPtr]::Zero
    $responsive = $false
    if ($found -ne [IntPtr]::Zero) {
        $handle = [EverythingSettingsManager_NativeMethods]::SendMessageTimeout($found, 0, [IntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$result)
        $responsive = $handle -ne [IntPtr]::Zero
    }
    [pscustomobject]@{
        Available = $responsive
        Running = $true
        Responsive = $responsive
        WindowHandle = ('0x{0:X}' -f $found.ToInt64())
        ProcessIds = @($processes | Select-Object -ExpandProperty Id)
        Message = if ($responsive) { 'Everything responded to the non-mutating IPC probe.' } else { 'Everything is running but no responsive IPC window was found.' }
    }
}

function Get-UsnJournalStatus {
    $rows = @()
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $root = $drive.Root
        if (-not $root -or $root -notmatch '^[A-Za-z]:\\$') { continue }
        $output = & fsutil.exe usn queryjournal $root 2>&1
        $joined = ($output | Out-String).Trim()
        $rows += [pscustomobject]@{
            Volume = $root
            Available = ($LASTEXITCODE -eq 0)
            Details = $joined
        }
    }
    return $rows
}

function ConvertTo-PlainCsvRows {
    param([array]$Rows)
    $plain = @()
    foreach ($row in @($Rows)) {
        $object = [ordered]@{}
        foreach ($property in @($row.PSObject.Properties)) { $object[$property.Name] = [string]$property.Value }
        $plain += [pscustomobject]$object
    }
    return $plain
}

function Get-CsvValidationIssues {
    param(
        [string]$CsvType,
        [array]$Rows
    )
    $issues = @()
    $seenNames = @{}
    $rowNumber = 1
    foreach ($row in @($Rows)) {
        $name = if ($row.PSObject.Properties['Name']) { [string]$row.Name } else { '' }
        if ($CsvType -in @('Filters', 'Bookmarks') -and [string]::IsNullOrWhiteSpace($name)) {
            $issues += [pscustomobject]@{ Row = $rowNumber; Column = 'Name'; Message = 'Name is required.' }
        } elseif ($name) {
            $nameKey = $name.ToLowerInvariant()
            if ($seenNames.ContainsKey($nameKey)) { $issues += [pscustomobject]@{ Row = $rowNumber; Column = 'Name'; Message = "Duplicate name (also used on row $($seenNames[$nameKey]))." } }
            else { $seenNames[$nameKey] = $rowNumber }
        }
        if ($CsvType -eq 'Filters') {
            $search = if ($row.PSObject.Properties['Search']) { [string]$row.Search } else { '' }
            $regex = if ($row.PSObject.Properties['Regex']) { [string]$row.Regex } else { '0' }
            if ($regex -eq '1' -and $search) {
                try { [regex]::new($search) | Out-Null } catch { $issues += [pscustomobject]@{ Row = $rowNumber; Column = 'Search'; Message = "Invalid regular expression: $($_.Exception.Message)" } }
            }
        }
        if ($CsvType -eq 'Bookmarks') {
            foreach ($column in @('URL', 'Url', 'Link', 'Host')) {
                if (-not $row.PSObject.Properties[$column]) { continue }
                $value = [string]$row.$column
                if ($value -and $value -match '^(?i)https?://') {
                    $uri = [System.Uri]::new($value)
                    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http', 'https')) { $issues += [pscustomobject]@{ Row = $rowNumber; Column = $column; Message = 'Bookmark URL must be an absolute HTTP or HTTPS URL.' } }
                }
            }
        }
        $rowNumber++
    }
    return $issues
}

function Get-FilterRegexPreview {
    param(
        [string]$Pattern,
        [string[]]$Samples = @()
    )
    try {
        $regex = [regex]::new($Pattern)
        $matches = @($Samples | Where-Object { $regex.IsMatch($_) })
        [pscustomobject]@{ Valid = $true; MatchCount = $matches.Count; Matches = $matches; Message = "Valid regex; $($matches.Count) sample match(es)." }
    } catch {
        [pscustomobject]@{ Valid = $false; MatchCount = 0; Matches = @(); Message = $_.Exception.Message }
    }
}

function Invoke-CsvBulkEdit {
    param(
        [array]$Rows,
        [string]$Column,
        [ValidateSet('Prefix', 'Suffix', 'RegexReplace')][string]$Operation,
        [string]$Value,
        [string]$Replacement = ''
    )
    if (-not $Column) { throw 'A column is required.' }
    $result = @()
    foreach ($row in @($Rows)) {
        $object = [ordered]@{}
        foreach ($property in @($row.PSObject.Properties)) { $object[$property.Name] = [string]$property.Value }
        if ($object.Contains($Column)) {
            switch ($Operation) {
                'Prefix' { $object[$Column] = "$Value$($object[$Column])" }
                'Suffix' { $object[$Column] = "$($object[$Column])$Value" }
                'RegexReplace' { $object[$Column] = [regex]::Replace([string]$object[$Column], $Value, $Replacement) }
            }
        }
        $result += [pscustomobject]$object
    }
    return $result
}

function Remove-HistoryMatches {
    param(
        [array]$Rows,
        [string]$Pattern,
        [switch]$Invert
    )
    if (-not $Pattern) { return @($Rows) }
    $regex = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $kept = @()
    foreach ($row in @($Rows)) {
        $text = (@($row.PSObject.Properties | ForEach-Object { [string]$_.Value }) -join ' ')
        $match = $regex.IsMatch($text)
        if (($match -and $Invert) -or (-not $match -and -not $Invert)) { $kept += $row }
    }
    return $kept
}

function Set-RunHistoryPinned {
    param([array]$Rows, [string[]]$Names)
    $nameSet = @{}
    foreach ($name in @($Names)) { if ($name) { $nameSet[$name] = $true } }
    $result = @()
    foreach ($row in @($Rows)) {
        $object = [ordered]@{}
        foreach ($property in @($row.PSObject.Properties)) { $object[$property.Name] = [string]$property.Value }
        if (-not $object.Contains('Pinned')) { $object['Pinned'] = '0' }
        $identity = if ($object.Contains('Name')) { $object['Name'] } elseif ($object.Contains('Path')) { $object['Path'] } else { '' }
        if ($nameSet.ContainsKey($identity)) { $object['Pinned'] = '1' }
        $result += [pscustomobject]$object
    }
    return $result
}

function Add-CsvHistoryEntry {
    param(
        [string]$Path,
        [string]$Operation,
        [array]$Before,
        [array]$After
    )
    $historyPath = if ($Path) { $Path } else { $Script:CsvHistoryPath }
    $directory = Split-Path -Parent $historyPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $entry = [ordered]@{ schemaVersion = 1; timestamp = (Get-Date).ToUniversalTime().ToString('o'); operation = $Operation; before = @(ConvertTo-PlainCsvRows -Rows $Before); after = @(ConvertTo-PlainCsvRows -Rows $After) }
    Add-Content -LiteralPath $historyPath -Value ($entry | ConvertTo-Json -Depth 10 -Compress) -Encoding UTF8
    return $historyPath
}

function Read-CsvHistoryEntries {
    param([string]$Path = $Script:CsvHistoryPath)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $entries = @()
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            try { $entries += $line | ConvertFrom-Json } catch { }
        }
    }
    return $entries
}

function Sync-BookmarksJson {
    param([string]$CsvPath, [array]$Rows)
    if (-not $CsvPath) { return $null }
    $jsonPath = [System.IO.Path]::ChangeExtension($CsvPath, '.json')
    (ConvertTo-PlainCsvRows -Rows $Rows) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    return $jsonPath
}

function Get-CommonBookmarkEntries {
    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    $entries = @()
    foreach ($item in @(
            [pscustomobject]@{ Name = 'Common\Desktop'; Search = "`"$desktop`""; Folder = $desktop; Key = 'common-desktop' },
            [pscustomobject]@{ Name = 'Common\Downloads'; Search = "`"$downloads`""; Folder = $downloads; Key = 'common-downloads' },
            [pscustomobject]@{ Name = 'Common\This Drive'; Search = "$($env:SystemDrive)\"; Folder = "$($env:SystemDrive)\"; Key = 'common-drive' }
        )) {
        if ($item.Folder -and (Test-Path -LiteralPath $item.Folder)) { $entries += $item }
    }
    return $entries
}

function Add-CommonBookmarksToRows {
    param([array]$Rows)
    $result = @(ConvertTo-PlainCsvRows -Rows $Rows)
    $existing = @{}
    foreach ($row in $result) { if ($row.PSObject.Properties['Name']) { $existing[$row.Name] = $true } }
    $columns = if ($result.Count -gt 0) { @($result[0].PSObject.Properties.Name) } else { @('Name', 'Search', 'Folder', 'Key') }
    foreach ($entry in @(Get-CommonBookmarkEntries)) {
        if ($existing.ContainsKey($entry.Name)) { continue }
        $object = [ordered]@{}
        foreach ($column in $columns) { $object[$column] = if ($entry.PSObject.Properties[$column]) { $entry.$column } else { '' } }
        if (-not $object.Contains('Name')) { $object['Name'] = $entry.Name }
        if (-not $object.Contains('Search')) { $object['Search'] = $entry.Search }
        $result += [pscustomobject]$object
    }
    return $result
}

function Add-FilterLibraryToRows {
    param([array]$Rows, [string]$PresetName)
    if (-not $Script:FilterPresetLibrary.Contains($PresetName)) { throw "Unknown filter library preset: $PresetName" }
    $result = @(ConvertTo-PlainCsvRows -Rows $Rows)
    $existing = @{}
    foreach ($row in $result) { if ($row.PSObject.Properties['Name']) { $existing[$row.Name] = $true } }
    $columns = if ($result.Count -gt 0) { @($result[0].PSObject.Properties.Name) } else { @('Name', 'Search', 'Regex') }
    $object = [ordered]@{}
    foreach ($column in $columns) {
        if ($column -eq 'Name') { $object[$column] = $PresetName }
        elseif ($column -eq 'Search') { $object[$column] = $Script:FilterPresetLibrary[$PresetName].Search }
        elseif ($column -eq 'Regex') { $object[$column] = if ($Script:FilterPresetLibrary[$PresetName].Search -match '^regex:') { '1' } else { '0' } }
        else { $object[$column] = '' }
    }
    if (-not $existing.ContainsKey($PresetName)) { $result += [pscustomobject]$object }
    return $result
}

function Find-EverythingSearchCli {
    $commands = @()
    try { $commands += (Get-Command 'es.exe' -ErrorAction SilentlyContinue).Source } catch { }
    foreach ($installation in @(Get-EverythingInstallationCandidates)) {
        if ($installation.Folder) { $commands += Join-Path $installation.Folder 'es.exe' }
    }
    foreach ($command in $commands) { if ($command -and (Test-Path -LiteralPath $command)) { return $command } }
    return $null
}

function Get-EverythingSearchPreview {
    param([string]$Query, [int]$Limit = 25)
    $cli = Find-EverythingSearchCli
    if (-not $cli) { return [pscustomobject]@{ Available = $false; Query = $Query; Results = @(); Message = 'es.exe was not found; install the Everything command-line client to enable live previews.' } }
    $output = & $cli -n $Limit $Query 2>&1
    [pscustomobject]@{ Available = ($LASTEXITCODE -eq 0); Query = $Query; Results = @($output | ForEach-Object { [string]$_ }); Message = if ($LASTEXITCODE -eq 0) { 'Preview loaded from Everything.' } else { ($output | Out-String).Trim() } }
}

function Get-EverythingUpdateFeed {
    param([int]$TimeoutSeconds = 10)
    $uri = 'https://www.voidtools.com/downloads/'
    try {
        $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        $links = @($response.Links | Where-Object { $_.href -match '(?i)everything.*(zip|exe)' } | Select-Object -First 20 | ForEach-Object { [pscustomobject]@{ Name = $_.innerText; Uri = $_.href } })
        return [pscustomobject]@{ Available = $true; Uri = $uri; Links = $links; RetrievedAt = (Get-Date).ToUniversalTime().ToString('o') }
    } catch {
        return [pscustomobject]@{ Available = $false; Uri = $uri; Links = @(); Error = $_.Exception.Message; RetrievedAt = (Get-Date).ToUniversalTime().ToString('o') }
    }
}

function Merge-CsvFromUrl {
    param(
        [string]$Url,
        [array]$ExistingRows,
        [string]$CsvType,
        [int]$TimeoutSeconds = 15
    )
    if ($Url -notmatch '^(?i)https?://') { throw 'Only HTTP and HTTPS CSV sources are supported.' }
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
    $incoming = @(ConvertFrom-Csv -InputObject $response.Content)
    $existing = @{}
    foreach ($row in @($ExistingRows)) { if ($row.PSObject.Properties['Name'] -and $row.Name) { $existing[[string]$row.Name] = $true } }
    $merged = @(ConvertTo-PlainCsvRows -Rows $ExistingRows); $added = 0; $skipped = 0
    foreach ($row in $incoming) {
        $name = if ($row.PSObject.Properties['Name']) { [string]$row.Name } else { '' }
        if (-not $name -or $existing.ContainsKey($name)) { $skipped++; continue }
        $merged += $row; $existing[$name] = $true; $added++
    }
    $issues = @(Get-CsvValidationIssues -CsvType $CsvType -Rows $merged)
    [pscustomobject]@{ Rows = $merged; Added = $added; Skipped = $skipped; ValidationIssues = $issues; Source = $Url }
}

function Prune-RunHistoryRows {
    param([array]$Rows, [int]$Maximum = 1000)
    if ($Maximum -lt 1) { throw 'Maximum history rows must be positive.' }
    $pinned = @($Rows | Where-Object { $_.PSObject.Properties['Pinned'] -and [string]$_.Pinned -eq '1' })
    $unpinned = @($Rows | Where-Object { -not ($_.PSObject.Properties['Pinned'] -and [string]$_.Pinned -eq '1') })
    $remaining = [Math]::Max(0, $Maximum - $pinned.Count)
    return @($pinned + @($unpinned | Select-Object -First $remaining))
}

function Set-EverythingServiceMode {
    param(
        [ValidateSet('Automatic', 'Manual', 'Disabled')][string]$StartupType,
        [switch]$Start,
        [switch]$Stop
    )
    $service = Get-Service -Name 'Everything' -ErrorAction Stop
    Set-Service -Name $service.Name -StartupType $StartupType
    if ($Stop) { Stop-Service -Name $service.Name -Force -ErrorAction Stop }
    if ($Start) { Start-Service -Name $service.Name -ErrorAction Stop }
    return Get-EverythingServiceState
}

if (-not $NoGui -and -not $SelfTest) {

# ============================================================================
# XAML UI
# ============================================================================

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Everything Settings Manager" Width="1400" Height="900" WindowStartupLocation="CenterScreen" Background="#1E1E1E">
<Window.Resources>
<Style TargetType="Button"><Setter Property="Background" Value="#0078D4"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="16,8"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#1084D8"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Background" Value="#3F3F46"/><Setter Property="Foreground" Value="#6D6D6D"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style x:Key="SecondaryButton" TargetType="Button"><Setter Property="Background" Value="#3F3F46"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="16,8"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#4F4F56"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style x:Key="TabButton" TargetType="Button"><Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#9D9D9D"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="20,12"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="13"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="#3F3F46" BorderThickness="0,0,0,2" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#2D2D30"/></Trigger><Trigger Property="Tag" Value="Selected"><Setter TargetName="border" Property="BorderBrush" Value="#0078D4"/><Setter Property="Foreground" Value="#E0E0E0"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style x:Key="CategoryButton" TargetType="Button"><Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#9D9D9D"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="12,10"/><Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="border" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="border" Property="Background" Value="#2D2D30"/></Trigger><Trigger Property="Tag" Value="Selected"><Setter Property="Background" Value="#0078D4"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType="CheckBox"><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
<Style TargetType="TextBox"><Setter Property="Background" Value="#3C3C3C"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="BorderBrush" Value="#3F3F46"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="8,6"/><Setter Property="CaretBrush" Value="#E0E0E0"/><Setter Property="SelectionBrush" Value="#0078D4"/></Style>
<ControlTemplate x:Key="ComboBoxToggleButton" TargetType="ToggleButton">
<Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="20"/></Grid.ColumnDefinitions>
<Border x:Name="Border" Grid.ColumnSpan="2" Background="#3C3C3C" BorderBrush="#3F3F46" BorderThickness="1" CornerRadius="2"/>
<Border Grid.Column="0" Background="#3C3C3C" BorderBrush="#3F3F46" BorderThickness="0,0,1,0" Margin="1"/>
<Path x:Name="Arrow" Grid.Column="1" Fill="#E0E0E0" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M0,0 L0,2 L4,6 L8,2 L8,0 L4,4 z"/>
</Grid>
<ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Border" Property="Background" Value="#4E4E52"/></Trigger></ControlTemplate.Triggers>
</ControlTemplate>
<ControlTemplate x:Key="ComboBoxTextBox" TargetType="TextBox">
<Border x:Name="PART_ContentHost" Focusable="False" Background="{TemplateBinding Background}"/>
</ControlTemplate>
<Style x:Key="DarkComboBoxItem" TargetType="ComboBoxItem">
<Setter Property="SnapsToDevicePixels" Value="True"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="OverridesDefaultStyle" Value="True"/>
<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem">
<Border Name="Border" Padding="8,4" SnapsToDevicePixels="True" Background="Transparent">
<ContentPresenter/></Border>
<ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Border" Property="Background" Value="#3E3E42"/></Trigger>
<Trigger Property="IsSelected" Value="True"><Setter TargetName="Border" Property="Background" Value="#0078D4"/></Trigger>
</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style x:Key="DarkComboBox" TargetType="ComboBox">
<Setter Property="SnapsToDevicePixels" Value="True"/><Setter Property="OverridesDefaultStyle" Value="True"/><Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Auto"/><Setter Property="ScrollViewer.VerticalScrollBarVisibility" Value="Auto"/><Setter Property="ScrollViewer.CanContentScroll" Value="True"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
<Setter Property="ItemContainerStyle" Value="{StaticResource DarkComboBoxItem}"/>
<Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">
<Grid><ToggleButton Name="ToggleButton" Template="{StaticResource ComboBoxToggleButton}" Grid.Column="2" Focusable="False" IsChecked="{Binding Path=IsDropDownOpen,Mode=TwoWay,RelativeSource={RelativeSource TemplatedParent}}" ClickMode="Press"/>
<ContentPresenter Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}" Margin="6,3,23,3" VerticalAlignment="Center" HorizontalAlignment="Left"/>
<TextBox x:Name="PART_EditableTextBox" Style="{x:Null}" Template="{StaticResource ComboBoxTextBox}" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="3,3,23,3" Focusable="True" Background="Transparent" Foreground="#E0E0E0" Visibility="Hidden" IsReadOnly="{TemplateBinding IsReadOnly}"/>
<Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
<Grid Name="DropDown" SnapsToDevicePixels="True" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
<Border x:Name="DropDownBorder" Background="#2D2D30" BorderThickness="1" BorderBrush="#3F3F46"/>
<ScrollViewer Margin="4,6,4,6" SnapsToDevicePixels="True"><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>
</Grid></Popup></Grid>
<ControlTemplate.Triggers><Trigger Property="HasItems" Value="False"><Setter TargetName="DropDownBorder" Property="MinHeight" Value="95"/></Trigger>
<Trigger Property="IsGrouping" Value="True"><Setter Property="ScrollViewer.CanContentScroll" Value="False"/></Trigger>
<Trigger Property="IsEditable" Value="True"><Setter Property="IsTabStop" Value="False"/><Setter TargetName="PART_EditableTextBox" Property="Visibility" Value="Visible"/><Setter TargetName="ContentSite" Property="Visibility" Value="Hidden"/></Trigger>
</ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
<Style TargetType="ComboBox" BasedOn="{StaticResource DarkComboBox}"/>
<Style TargetType="ComboBoxItem" BasedOn="{StaticResource DarkComboBoxItem}"/>
<Style TargetType="DataGrid"><Setter Property="Background" Value="#252526"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="BorderBrush" Value="#3F3F46"/><Setter Property="RowBackground" Value="#252526"/><Setter Property="AlternatingRowBackground" Value="#2D2D30"/><Setter Property="GridLinesVisibility" Value="Horizontal"/><Setter Property="HorizontalGridLinesBrush" Value="#3F3F46"/></Style>
<Style TargetType="DataGridColumnHeader"><Setter Property="Background" Value="#1E1E1E"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="Padding" Value="10,8"/><Setter Property="BorderBrush" Value="#3F3F46"/><Setter Property="BorderThickness" Value="0,0,1,1"/></Style>
<Style TargetType="DataGridCell"><Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="Padding" Value="8,4"/><Setter Property="BorderThickness" Value="0"/><Style.Triggers><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#0078D4"/><Setter Property="Foreground" Value="White"/></Trigger><Trigger Property="IsEditing" Value="True"><Setter Property="Background" Value="#3C3C3C"/></Trigger></Style.Triggers></Style>
<Style TargetType="DataGridRow"><Setter Property="Background" Value="#252526"/><Setter Property="Foreground" Value="#E0E0E0"/><Style.Triggers><Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#0078D4"/></Trigger><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#2D2D30"/></Trigger></Style.Triggers></Style>
<Style TargetType="DataGridRowHeader"><Setter Property="Background" Value="#1E1E1E"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="BorderBrush" Value="#3F3F46"/></Style>
<Style TargetType="ScrollBar"><Setter Property="Background" Value="#1E1E1E"/></Style>
<Style TargetType="ToolTip"><Setter Property="Background" Value="#2D2D30"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="BorderBrush" Value="#3F3F46"/></Style>
<Style TargetType="ContextMenu"><Setter Property="Background" Value="#2D2D30"/><Setter Property="Foreground" Value="#E0E0E0"/><Setter Property="BorderBrush" Value="#3F3F46"/></Style>
<Style TargetType="MenuItem"><Setter Property="Background" Value="#2D2D30"/><Setter Property="Foreground" Value="#E0E0E0"/><Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#3E3E42"/></Trigger></Style.Triggers></Style>
</Window.Resources>
<Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
<Border Grid.Row="0" Background="#252526" Padding="20,15"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0"><TextBlock Text="Everything Settings Manager" FontSize="22" FontWeight="SemiBold" Foreground="#E0E0E0"/><TextBlock x:Name="txtIniPath" Text="Auto-detecting..." FontSize="12" Foreground="#9D9D9D" Margin="0,4,0,0"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><ComboBox x:Name="cmbIniProfile" Width="300" Margin="0,0,15,0" ToolTip="Select an installed, portable, service, or multi-instance INI profile"/><Border x:Name="statusIndicator" Width="12" Height="12" CornerRadius="6" Background="#4EC9B0" Margin="0,0,8,0"/><TextBlock x:Name="txtStatus" Text="Everything: Running" Foreground="#9D9D9D" VerticalAlignment="Center"/></StackPanel></Grid></Border>
<Border Grid.Row="1" Background="#252526" BorderBrush="#3F3F46" BorderThickness="0,0,0,1"><StackPanel x:Name="mainTabPanel" Orientation="Horizontal"/></Border>
<Grid Grid.Row="2" x:Name="contentGrid">
<Grid x:Name="settingsContent" Visibility="Visible"><Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Grid.Column="0" Background="#252526" BorderBrush="#3F3F46" BorderThickness="0,0,1,0"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="categoryPanel" Margin="0,10,0,10"/></ScrollViewer></Border><Border Grid.Column="1" Padding="20"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><StackPanel Grid.Row="0" Margin="0,0,0,15"><Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox x:Name="txtSettingSearch" Grid.Column="0" Height="32" ToolTip="Search setting names, keys, descriptions, defaults, or impact"/><CheckBox x:Name="chkDifferences" Grid.Column="1" Content="Only differences" Foreground="#E0E0E0" VerticalAlignment="Center" Margin="12,0,12,0"/><Button x:Name="btnShowDiff" Grid.Column="2" Content="Diff view" Style="{StaticResource SecondaryButton}" Padding="12,6"/></Grid><TextBlock x:Name="txtCategoryName" Text="Database" FontSize="18" FontWeight="SemiBold" Foreground="#E0E0E0"/><TextBlock x:Name="txtCategoryDesc" Text="" FontSize="12" Foreground="#9D9D9D" Margin="0,4,0,0" TextWrapping="Wrap"/><TextBlock x:Name="txtImpactEstimate" Text="" FontSize="11" Foreground="#CE9178" Margin="0,6,0,0" TextWrapping="Wrap"/></StackPanel><ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="settingsPanel"/></ScrollViewer></Grid></Border></Grid>
<Grid x:Name="csvContent" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Border Grid.Row="0" Background="#252526" Padding="15"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" Orientation="Horizontal"><TextBlock Text="Edit: " Foreground="#E0E0E0" VerticalAlignment="Center" Margin="0,0,10,0"/><ComboBox x:Name="cmbCsvType" Width="200" Style="{StaticResource DarkComboBox}"><ComboBoxItem Content="Filters" IsSelected="True"/><ComboBoxItem Content="Bookmarks"/><ComboBoxItem Content="Search_History"/><ComboBoxItem Content="Run_History"/></ComboBox></StackPanel><TextBlock x:Name="txtCsvPath" Grid.Column="1" Foreground="#9D9D9D" VerticalAlignment="Center" Margin="20,0,0,0"/><StackPanel Grid.Column="2" Orientation="Horizontal"><Button x:Name="btnCsvReload" Content="Reload" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnCsvAddDefaults" Content="Add Defaults" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnCsvLibrary" Content="Library" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnCsvPreview" Content="Live preview" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnCsvMerge" Content="Merge URL" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnCsvBulkEdit" Content="Bulk edit" Style="{StaticResource SecondaryButton}"/></StackPanel></Grid></Border><DataGrid x:Name="csvDataGrid" Grid.Row="1" AutoGenerateColumns="True" CanUserAddRows="True" CanUserDeleteRows="True" Margin="15"/><Border Grid.Row="2" Background="#252526" Padding="15"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" Orientation="Horizontal"><Button x:Name="btnCsvDelete" Content="Delete Selected" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><Button x:Name="btnCsvBackup" Content="Create Backup" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><Button x:Name="btnCsvPin" Content="Pin Selected" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><Button x:Name="btnCsvScrub" Content="Scrub history" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><TextBlock x:Name="txtCsvValidation" Text="" Foreground="#CE9178" VerticalAlignment="Center" TextWrapping="Wrap"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal"><TextBlock x:Name="txtCsvModified" Text="" Foreground="#CE9178" VerticalAlignment="Center" Margin="0,0,15,0"/><Button x:Name="btnCsvUndo" Content="Undo" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnCsvSave" Content="Save CSV" IsEnabled="False"/></StackPanel></Grid></Border></Grid>
</Grid>
<Border Grid.Row="3" Background="#252526" Padding="20,12" BorderBrush="#3F3F46" BorderThickness="0,1,0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" Orientation="Horizontal"><TextBlock x:Name="txtModified" Text="" Foreground="#CE9178" VerticalAlignment="Center" Margin="0,0,15,0"/><Button x:Name="btnBackup" Content="Create Backup" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><ComboBox x:Name="cmbPreset" Width="125" Margin="0,0,8,0"/><Button x:Name="btnRecommended" Content="Apply Preset" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnUndo" Content="Undo" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnRedo" Content="Redo" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnHealth" Content="Health" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/><Button x:Name="btnReload" Content="Reload" Style="{StaticResource SecondaryButton}"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal"><ComboBox x:Name="cmbTheme" Width="110" Margin="0,0,10,0"/><Button x:Name="btnRestartEverything" Content="Restart Everything" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><Button x:Name="btnSave" Content="Save Settings" IsEnabled="False"/></StackPanel></Grid></Border>
</Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)
Write-DiagnosticLog -Message 'XAML loaded'

# codex-branding:start
                try {
                    $brandingIconPath = Join-Path $PSScriptRoot 'icon.ico'
                    if (Test-Path $brandingIconPath) {
                        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($brandingIconPath)))
                    }
                } catch {
                }
                # codex-branding:end
# Get UI elements
$window.Title = "Everything Settings Manager v$($Script:AppVersion)"
$txtIniPath = $window.FindName("txtIniPath"); $txtStatus = $window.FindName("txtStatus"); $statusIndicator = $window.FindName("statusIndicator"); $cmbIniProfile = $window.FindName("cmbIniProfile")
$mainTabPanel = $window.FindName("mainTabPanel"); $settingsContent = $window.FindName("settingsContent"); $csvContent = $window.FindName("csvContent")
$categoryPanel = $window.FindName("categoryPanel"); $settingsPanel = $window.FindName("settingsPanel")
$txtCategoryName = $window.FindName("txtCategoryName"); $txtCategoryDesc = $window.FindName("txtCategoryDesc"); $txtSettingSearch = $window.FindName("txtSettingSearch"); $chkDifferences = $window.FindName("chkDifferences"); $btnShowDiff = $window.FindName("btnShowDiff"); $txtImpactEstimate = $window.FindName("txtImpactEstimate")
$txtModified = $window.FindName("txtModified"); $btnBackup = $window.FindName("btnBackup"); $btnRecommended = $window.FindName("btnRecommended")
$btnReload = $window.FindName("btnReload"); $btnRestartEverything = $window.FindName("btnRestartEverything"); $btnSave = $window.FindName("btnSave"); $cmbPreset = $window.FindName("cmbPreset"); $btnUndo = $window.FindName("btnUndo"); $btnRedo = $window.FindName("btnRedo"); $btnHealth = $window.FindName("btnHealth"); $cmbTheme = $window.FindName("cmbTheme")
$cmbCsvType = $window.FindName("cmbCsvType"); $txtCsvPath = $window.FindName("txtCsvPath"); $csvDataGrid = $window.FindName("csvDataGrid")
$btnCsvReload = $window.FindName("btnCsvReload"); $btnCsvAddDefaults = $window.FindName("btnCsvAddDefaults")
$btnCsvDelete = $window.FindName("btnCsvDelete"); $btnCsvBackup = $window.FindName("btnCsvBackup")
$btnCsvSave = $window.FindName("btnCsvSave"); $txtCsvModified = $window.FindName("txtCsvModified"); $txtCsvValidation = $window.FindName("txtCsvValidation"); $btnCsvLibrary = $window.FindName("btnCsvLibrary"); $btnCsvPreview = $window.FindName("btnCsvPreview"); $btnCsvMerge = $window.FindName("btnCsvMerge"); $btnCsvBulkEdit = $window.FindName("btnCsvBulkEdit"); $btnCsvPin = $window.FindName("btnCsvPin"); $btnCsvScrub = $window.FindName("btnCsvScrub"); $btnCsvUndo = $window.FindName("btnCsvUndo")
Write-DiagnosticLog -Message 'UI controls resolved'

# ============================================================================
# UI FUNCTIONS
# ============================================================================

function Set-Theme {
    param([ValidateSet('Dark', 'Light', 'High Contrast')][string]$Name = 'Dark')
    $palettes = @{
        'Dark' = @{ Window = '#1E1E1E'; Surface = '#252526'; Input = '#3C3C3C'; Text = '#E0E0E0'; Muted = '#9D9D9D'; Border = '#3F3F46'; Accent = '#0078D4' }
        'Light' = @{ Window = '#F4F4F4'; Surface = '#FFFFFF'; Input = '#FFFFFF'; Text = '#1F1F1F'; Muted = '#5F5F5F'; Border = '#C8C8C8'; Accent = '#0067C0' }
        'High Contrast' = @{ Window = '#000000'; Surface = '#000000'; Input = '#000000'; Text = '#FFFFFF'; Muted = '#FFFFFF'; Border = '#FFFFFF'; Accent = '#FFFF00' }
    }
    $Script:ThemeName = $Name
    $Script:ThemePalette = $palettes[$Name]
    if (-not $window) { return }
    $window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Window)
    foreach ($elementName in @('txtIniPath', 'txtStatus', 'txtCategoryName', 'txtCategoryDesc', 'txtImpactEstimate', 'txtModified', 'txtCsvPath', 'txtCsvModified', 'txtCsvValidation')) {
        $element = $window.FindName($elementName)
        if ($element -and $element.PSObject.Properties['Foreground']) { $element.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Muted) }
    }
    foreach ($elementName in @('settingsContent', 'csvContent', 'categoryPanel', 'mainTabPanel')) {
        $element = $window.FindName($elementName)
        if ($element -and $element.PSObject.Properties['Background']) { $element.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Surface) }
    }
    if ($cmbTheme -and $cmbTheme.SelectedItem -ne $Name) { $cmbTheme.SelectedItem = $Name }
    if ($txtCategoryName) { Show-Category -CategoryName $txtCategoryName.Text }
}

function Sync-ModifiedSettings {
    $Script:ModifiedSettings = @{}
    $keys = @($Script:Settings.Keys) + @($Script:OriginalSettings.Keys) | Select-Object -Unique
    foreach ($key in $keys) {
        $current = if ($Script:Settings.ContainsKey($key)) { [string]$Script:Settings[$key] } else { $null }
        $original = if ($Script:OriginalSettings.ContainsKey($key)) { [string]$Script:OriginalSettings[$key] } else { $null }
        if ($current -ne $original) { $Script:ModifiedSettings[$key] = $current }
    }
}

function Test-SettingMatchesSearch {
    param([string]$Key, [System.Collections.IDictionary]$Definition)
    if ([string]::IsNullOrWhiteSpace($Script:SettingsSearchText)) { return $true }
    $needle = $Script:SettingsSearchText.Trim()
    $haystack = "$Key $($Definition.DisplayName) $($Definition.Description) $($Definition.Recommended) $($Definition.Impact)"
    return $haystack.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Show-SettingsDiffWindow {
    $diffWindow = New-Object System.Windows.Window
    $diffWindow.Title = "Settings diff - $($Script:AppVersion)"
    $diffWindow.Width = 900; $diffWindow.Height = 600; $diffWindow.WindowStartupLocation = 'CenterOwner'; $diffWindow.Owner = $window; $diffWindow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Window)
    $grid = New-Object System.Windows.Controls.DataGrid
    $grid.AutoGenerateColumns = $true; $grid.IsReadOnly = $true; $grid.Margin = [System.Windows.Thickness]::new(12)
    $grid.ItemsSource = @(Get-SettingsDiff -Settings $Script:Settings)
    $diffWindow.Content = $grid
    $diffWindow.ShowDialog() | Out-Null
}

function Show-CommandPalette {
    $commands = @(
        [pscustomobject]@{ Name = 'Save settings'; Action = { Save-Settings } },
        [pscustomobject]@{ Name = 'Apply selected preset'; Action = { Apply-RecommendedSettings } },
        [pscustomobject]@{ Name = 'Show settings diff'; Action = { Show-SettingsDiffWindow } },
        [pscustomobject]@{ Name = 'Undo settings change'; Action = { if (Undo-SettingsChange -Settings $Script:Settings) { Sync-ModifiedSettings; Show-Category -CategoryName $txtCategoryName.Text } } },
        [pscustomobject]@{ Name = 'Reload selected INI'; Action = { Load-Settings } },
        [pscustomobject]@{ Name = 'Open CSV editor'; Action = { $csvContent.Visibility = 'Visible'; $settingsContent.Visibility = 'Collapsed'; Load-CurrentCsv } }
    )
    $paletteWindow = New-Object System.Windows.Window; $paletteWindow.Title = 'Command palette'; $paletteWindow.Width = 520; $paletteWindow.Height = 360; $paletteWindow.WindowStartupLocation = 'CenterOwner'; $paletteWindow.Owner = $window; $paletteWindow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Window)
    $panel = New-Object System.Windows.Controls.DockPanel; $panel.Margin = [System.Windows.Thickness]::new(12)
    $search = New-Object System.Windows.Controls.TextBox; $search.Height = 32; [System.Windows.Controls.DockPanel]::SetDock($search, 'Top')
    $list = New-Object System.Windows.Controls.ListBox; $list.ItemsSource = $commands; $list.DisplayMemberPath = 'Name'
    $panel.Children.Add($search) | Out-Null; $panel.Children.Add($list) | Out-Null; $paletteWindow.Content = $panel
    $search.Add_TextChanged({ $text = $search.Text; $list.ItemsSource = @($commands | Where-Object { $_.Name.IndexOf($text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }) })
    $search.Add_KeyDown({ param($sender, $event); if ($event.Key -eq 'Enter' -and $list.SelectedItem) { $action = $list.SelectedItem.Action; $paletteWindow.Close(); & $action } elseif ($event.Key -eq 'Escape') { $paletteWindow.Close() } })
    $list.SelectedIndex = 0; $paletteWindow.ShowDialog() | Out-Null
}

function Update-StatusIndicator {
    if (Test-EverythingRunning) {
        $statusIndicator.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(78, 201, 176))
        $txtStatus.Text = "Everything: Running"
    } else {
        $statusIndicator.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(241, 76, 76))
        $txtStatus.Text = "Everything: Stopped"
    }
}

function Update-ModifiedCount {
    $count = $Script:ModifiedSettings.Count
    if ($count -gt 0) { $txtModified.Text = "$count setting(s) modified"; $btnSave.IsEnabled = $true }
    else { $txtModified.Text = ""; $btnSave.IsEnabled = $false }
}

function Initialize-MainTabs {
    $mainTabPanel.Children.Clear()
    foreach ($tabName in @("Settings", "CSV Editor")) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $tabName
        $btn.Style = $window.FindResource("TabButton")
        if ($tabName -eq "Settings") { $btn.Tag = "Selected" }
        $btn.Add_Click({
            param($sender, $e)
            foreach ($child in $mainTabPanel.Children) { $child.Tag = $null }
            $sender.Tag = "Selected"
            if ($sender.Content -eq "Settings") { $settingsContent.Visibility = "Visible"; $csvContent.Visibility = "Collapsed" }
            else { $settingsContent.Visibility = "Collapsed"; $csvContent.Visibility = "Visible"; Load-CurrentCsv }
        }.GetNewClosure())
        $mainTabPanel.Children.Add($btn) | Out-Null
    }
}

function Create-SettingControl {
    param([string]$Key, [hashtable]$Definition, [string]$CurrentValue)
    if (-not $Definition -or -not $Definition.Type) { return $null }
    $container = New-Object System.Windows.Controls.Border
    $surface = if ($Script:ThemePalette.Surface) { $Script:ThemePalette.Surface } else { '#252526' }
    $container.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($surface)
    $container.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $container.Padding = [System.Windows.Thickness]::new(15)
    $container.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
    if ($Definition.ForumUrl) {
        $tooltipText = New-Object System.Windows.Controls.TextBlock
        $tooltipText.Text = "$($Definition.Description)`n"
        $link = New-Object System.Windows.Documents.Hyperlink
        $link.NavigateUri = New-Object System.Uri($Definition.ForumUrl)
        $link.Inlines.Add('Open Everything documentation') | Out-Null
        $link.Add_RequestNavigate({ param($sender, $event); Start-Process -FilePath $event.Uri.AbsoluteUri; $event.Handled = $true })
        $tooltipText.Inlines.Add($link) | Out-Null
        $container.ToolTip = $tooltipText
    }
    $grid = New-Object System.Windows.Controls.Grid
    $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::new(200)
    $grid.ColumnDefinitions.Add($col1) | Out-Null; $grid.ColumnDefinitions.Add($col2) | Out-Null
    $leftPanel = New-Object System.Windows.Controls.StackPanel; [System.Windows.Controls.Grid]::SetColumn($leftPanel, 0)
    $titlePanel = New-Object System.Windows.Controls.StackPanel; $titlePanel.Orientation = "Horizontal"
    $titleLabel = New-Object System.Windows.Controls.TextBlock; $titleLabel.Text = $Definition.DisplayName; $titleLabel.FontWeight = "SemiBold"; $titleLabel.FontSize = 13
    $titleLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(224, 224, 224))
    $titlePanel.Children.Add($titleLabel) | Out-Null
    if ($Definition.Impact) {
        $impactBadge = New-Object System.Windows.Controls.Border; $impactBadge.CornerRadius = [System.Windows.CornerRadius]::new(3)
        $impactBadge.Padding = [System.Windows.Thickness]::new(6, 2, 6, 2); $impactBadge.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
        $impactText = New-Object System.Windows.Controls.TextBlock; $impactText.FontSize = 10; $impactText.Text = $Definition.Impact
        switch ($Definition.Impact) {
            "Critical" { $impactBadge.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(40, 241, 76, 76)); $impactText.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(241, 76, 76)) }
            "High" { $impactBadge.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(40, 206, 145, 120)); $impactText.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(206, 145, 120)) }
            "Medium" { $impactBadge.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(40, 220, 220, 170)); $impactText.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(220, 220, 170)) }
            default { $impactBadge.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromArgb(40, 157, 157, 157)); $impactText.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(157, 157, 157)) }
        }
        $impactBadge.Child = $impactText; $titlePanel.Children.Add($impactBadge) | Out-Null
    }
    $leftPanel.Children.Add($titlePanel) | Out-Null
    $keyLabel = New-Object System.Windows.Controls.TextBlock; $keyLabel.Text = "$Key  [$($Definition.Since)]"; $keyLabel.FontSize = 11
    $keyLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(78, 201, 176))
    $keyLabel.Margin = [System.Windows.Thickness]::new(0, 2, 0, 4); $leftPanel.Children.Add($keyLabel) | Out-Null
    $descLabel = New-Object System.Windows.Controls.TextBlock; $descLabel.Text = $Definition.Description; $descLabel.FontSize = 12
    $descLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(157, 157, 157)); $descLabel.TextWrapping = "Wrap"
    $leftPanel.Children.Add($descLabel) | Out-Null
    $recLabel = New-Object System.Windows.Controls.TextBlock; $recLabel.FontSize = 11; $recLabel.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
    $recValue = $Definition.Recommended
    if ($Definition.Type -eq "Boolean") { $recValue = if ($Definition.Recommended -eq 1) { "Enabled" } else { "Disabled" } }
    elseif ($Definition.Type -eq "Combo" -and $Definition.Options) { $recValue = $Definition.Options[$Definition.Recommended] }
    $recLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(78, 201, 176))
    $recLabel.Text = "Recommended: $recValue"; $leftPanel.Children.Add($recLabel) | Out-Null
    $grid.Children.Add($leftPanel) | Out-Null
    $rightPanel = New-Object System.Windows.Controls.StackPanel; $rightPanel.VerticalAlignment = "Center"; $rightPanel.HorizontalAlignment = "Right"
    [System.Windows.Controls.Grid]::SetColumn($rightPanel, 1)
    $control = $null
    switch ($Definition.Type) {
        "Boolean" {
            $control = New-Object System.Windows.Controls.CheckBox; $control.IsChecked = ($CurrentValue -eq "1"); $control.Tag = $Key
            $control.Add_Checked({ param($sender, $e); $k = $sender.Tag; $Script:Settings[$k] = "1"
                if ($Script:OriginalSettings[$k] -ne "1") { $Script:ModifiedSettings[$k] = "1" } else { $Script:ModifiedSettings.Remove($k) }; Update-ModifiedCount })
            $control.Add_Unchecked({ param($sender, $e); $k = $sender.Tag; $Script:Settings[$k] = "0"
                if ($Script:OriginalSettings[$k] -ne "0") { $Script:ModifiedSettings[$k] = "0" } else { $Script:ModifiedSettings.Remove($k) }; Update-ModifiedCount })
        }
        "Number" {
            $control = New-Object System.Windows.Controls.TextBox; $control.Text = $CurrentValue; $control.Width = 150; $control.Tag = $Key
            $control.Add_TextChanged({ param($sender, $e); $k = $sender.Tag; $Script:Settings[$k] = $sender.Text
                if ($Script:OriginalSettings[$k] -ne $sender.Text) { $Script:ModifiedSettings[$k] = $sender.Text } else { $Script:ModifiedSettings.Remove($k) }; Update-ModifiedCount })
        }
        "Combo" {
            $control = New-Object System.Windows.Controls.ComboBox; $control.Width = 150; $control.Tag = $Key
            # Apply the dark ComboBox style with explicit key
            try { $control.Style = $window.FindResource("DarkComboBox") } catch { }
            foreach ($opt in $Definition.Options) { $control.Items.Add($opt) | Out-Null }
            $index = [int]$CurrentValue; if ($index -ge 0 -and $index -lt $Definition.Options.Count) { $control.SelectedIndex = $index }
            $control.Add_SelectionChanged({ param($sender, $e); $k = $sender.Tag; $Script:Settings[$k] = $sender.SelectedIndex.ToString()
                if ($Script:OriginalSettings[$k] -ne $sender.SelectedIndex.ToString()) { $Script:ModifiedSettings[$k] = $sender.SelectedIndex.ToString() } else { $Script:ModifiedSettings.Remove($k) }; Update-ModifiedCount })
        }
        "FolderPath" {
            $pathPanel = New-Object System.Windows.Controls.StackPanel; $pathPanel.Orientation = "Horizontal"
            $textBox = New-Object System.Windows.Controls.TextBox; $textBox.Text = $CurrentValue; $textBox.Width = 120; $textBox.Tag = $Key
            $textBox.Add_TextChanged({ param($sender, $e); $k = $sender.Tag; $Script:Settings[$k] = $sender.Text
                if ($Script:OriginalSettings[$k] -ne $sender.Text) { $Script:ModifiedSettings[$k] = $sender.Text } else { $Script:ModifiedSettings.Remove($k) }; Update-ModifiedCount })
            $browseBtn = New-Object System.Windows.Controls.Button; $browseBtn.Content = "..."; $browseBtn.Width = 30
            $browseBtn.Margin = [System.Windows.Thickness]::new(5, 0, 0, 0); $browseBtn.Tag = $textBox
            $browseBtn.Add_Click({ param($sender, $e); $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $sender.Tag.Text = $dialog.SelectedPath } })
            $pathPanel.Children.Add($textBox) | Out-Null; $pathPanel.Children.Add($browseBtn) | Out-Null; $control = $pathPanel
        }
        default {
            $control = New-Object System.Windows.Controls.TextBox; $control.Text = $CurrentValue; $control.Width = 150; $control.Tag = $Key
            $control.Add_TextChanged({ param($sender, $e); $k = $sender.Tag; $Script:Settings[$k] = $sender.Text
                if ($Script:OriginalSettings[$k] -ne $sender.Text) { $Script:ModifiedSettings[$k] = $sender.Text } else { $Script:ModifiedSettings.Remove($k) }; Update-ModifiedCount })
        }
    }
    if ($control) { $rightPanel.Children.Add($control) | Out-Null }
    $grid.Children.Add($rightPanel) | Out-Null; $container.Child = $grid
    return $container
}

function Show-Category {
    param([string]$CategoryName)
    $category = $Script:SettingsDefinitions[$CategoryName]; if (-not $category) { return }
    $txtCategoryName.Text = $CategoryName; $txtCategoryDesc.Text = $category.Description
    $settingsPanel.Children.Clear()
    foreach ($settingKey in $category.Settings.Keys) {
        $definition = $category.Settings[$settingKey]
        if (-not $definition -or -not $definition.Type) { continue }
        if (-not (Test-SettingMatchesSearch -Key $settingKey -Definition $definition)) { continue }
        $currentValue = if ($Script:Settings.ContainsKey($settingKey)) { $Script:Settings[$settingKey] } else { "$($definition.Recommended)" }
        $factoryDefault = if ($definition.ContainsKey('FactoryDefault')) { [string]$definition.FactoryDefault } else { [string]$definition.Recommended }
        if ($Script:ShowOnlyDifferences -and [string]$currentValue -eq $factoryDefault) { continue }
        $control = Create-SettingControl -Key $settingKey -Definition $definition -CurrentValue $currentValue
        if ($control) { $settingsPanel.Children.Add($control) | Out-Null }
    }
    if ($txtImpactEstimate) {
        $impact = Get-IndexImpactEstimate -Settings $Script:Settings
        $warningText = $impact.Warnings -join ' '
        $txtImpactEstimate.Text = "Index impact: $($impact.Level) - $warningText"
    }
    foreach ($child in $categoryPanel.Children) {
        if ($child -is [System.Windows.Controls.Button]) {
            if ($child.Content -eq $CategoryName) {
                $child.Tag = "Selected"; $child.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0, 120, 212))
                $child.Foreground = [System.Windows.Media.Brushes]::White
            } else {
                $child.Tag = $null; $child.Background = [System.Windows.Media.Brushes]::Transparent
                $child.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(157, 157, 157))
            }
        }
    }
}

function Initialize-Categories {
    $categoryPanel.Children.Clear()
    $sortedCategories = $Script:SettingsDefinitions.GetEnumerator() | Sort-Object { $_.Value.Order }
    foreach ($cat in $sortedCategories) {
        $btn = New-Object System.Windows.Controls.Button; $btn.Content = $cat.Key
        $btn.Style = $window.FindResource("CategoryButton"); $btn.HorizontalAlignment = "Stretch"
        $btn.Add_Click({ param($sender, $e); Show-Category -CategoryName $sender.Content }.GetNewClosure())
        $categoryPanel.Children.Add($btn) | Out-Null
    }
}

function Initialize-Profiles {
    if (-not $cmbIniProfile) { return }
    $cmbIniProfile.Items.Clear()
    $profiles = @(Get-EverythingProfileCandidates -Folder $Script:EverythingFolder)
    foreach ($profile in $profiles) { $cmbIniProfile.Items.Add($profile) | Out-Null }
    $cmbIniProfile.DisplayMemberPath = 'DisplayName'
    if ($profiles.Count -gt 0) {
        $selected = if ($Script:EverythingIniPath) { $profiles | Where-Object { $_.Path -eq $Script:EverythingIniPath } | Select-Object -First 1 } else { $profiles[0] }
        if ($selected) { $cmbIniProfile.SelectedItem = $selected }
    }
}

function Load-Settings {
    param([string]$Path)
    $requested = if ($Path) { $Path } elseif ($cmbIniProfile -and $cmbIniProfile.SelectedItem) { $cmbIniProfile.SelectedItem.Path } else { $IniPath }
    $Script:EverythingIniPath = Resolve-EverythingIniPath -RequestedPath $requested
    if (-not $Script:EverythingIniPath) { $txtIniPath.Text = "No Everything INI file found in $Script:EverythingFolder"; return }
    $Script:Settings = Read-IniFile -Path $Script:EverythingIniPath
    Add-DiscoveredSettings -Settings $Script:Settings
    $Script:OriginalSettings = @{}; foreach ($key in $Script:Settings.Keys) { $Script:OriginalSettings[$key] = $Script:Settings[$key] }
    $Script:ModifiedSettings = @{}
    $iniFileName = [System.IO.Path]::GetFileName($Script:EverythingIniPath)
    $txtIniPath.Text = "$Script:EverythingIniPath (auto-detected: $iniFileName)"
    Update-StatusIndicator; Update-ModifiedCount
}

function Save-Settings {
    if ($Script:ModifiedSettings.Count -eq 0 -or -not $Script:EverythingIniPath) { return }
    $issues = @(Test-Settings -Settings $Script:Settings)
    if ($issues.Count -gt 0) {
        [System.Windows.MessageBox]::Show(($issues | ForEach-Object { $_.Message } -join "`n"), "Validation failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    $wasRunning = Test-EverythingRunning
    if ($wasRunning) {
        $result = [System.Windows.MessageBox]::Show("Everything must be closed to save settings.`n`nClose Everything and save?", "Everything Running", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
        Stop-Everything; Start-Sleep -Seconds 1
    }
    $backupPath = Backup-File -Path $Script:EverythingIniPath
    Write-IniFile -Path $Script:EverythingIniPath -Settings $Script:Settings
    foreach ($key in $Script:Settings.Keys) { $Script:OriginalSettings[$key] = $Script:Settings[$key] }
    $Script:ModifiedSettings = @{}; Update-ModifiedCount
    [System.Windows.MessageBox]::Show("Settings saved!`n`nBackup: $backupPath", "Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    if ($wasRunning) {
        $restart = [System.Windows.MessageBox]::Show("Restart Everything now?", "Restart", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($restart -eq [System.Windows.MessageBoxResult]::Yes) { Start-Everything }
    }
    Update-StatusIndicator
}

function Apply-RecommendedSettings {
    $presetName = if ($cmbPreset -and $cmbPreset.SelectedItem) { [string]$cmbPreset.SelectedItem } else { 'Recommended' }
    $description = $Script:PresetDefinitions[$presetName].Description
    $result = [System.Windows.MessageBox]::Show("Apply '$presetName'?`n`n$description", "Apply Preset", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Apply-PresetToSettings -Settings $Script:Settings -PresetName $presetName | Out-Null
    Sync-ModifiedSettings
    Update-ModifiedCount; Show-Category -CategoryName $txtCategoryName.Text
    [System.Windows.MessageBox]::Show("$presetName settings applied. Click 'Save Settings' to persist.", "Applied", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}

# ============================================================================
# CSV FUNCTIONS
# ============================================================================

function Get-CsvGridRows {
    $rows = @()
    $dataView = if ($csvDataGrid) { $csvDataGrid.ItemsSource } else { $null }
    if ($dataView -is [System.Data.DataView]) {
        foreach ($row in $dataView.Table.Rows) {
            $object = [ordered]@{}
            foreach ($column in $dataView.Table.Columns) { $object[$column.ColumnName] = [string]$row[$column.ColumnName] }
            $rows += [pscustomobject]$object
        }
    }
    return $rows
}

function Update-CsvValidationStatus {
    $rows = @(Get-CsvGridRows)
    $issues = @(Get-CsvValidationIssues -CsvType $Script:CurrentCsvType -Rows $rows)
    if ($issues.Count -gt 0) {
        $txtCsvValidation.Text = "$($issues.Count) validation issue(s)"
        $txtCsvValidation.ToolTip = ($issues | ForEach-Object { "Row $($_.Row), $($_.Column): $($_.Message)" } -join "`n")
    } else {
        $previewText = ''
        if ($Script:CurrentCsvType -eq 'Filters') {
            $regexRows = @($rows | Where-Object { $_.PSObject.Properties['Regex'] -and $_.Regex -eq '1' -and $_.PSObject.Properties['Search'] -and $_.Search })
            if ($regexRows.Count -gt 0) { $previewText = "; regex preview: $((Get-FilterRegexPreview -Pattern $regexRows[0].Search -Samples @($rows.Search)).Message)" }
        }
        $txtCsvValidation.Text = "CSV valid$previewText"
        $txtCsvValidation.ToolTip = $null
    }
    return $issues
}

function Push-CsvGridUndoSnapshot {
    $snapshot = @(Get-CsvGridRows)
    if ($snapshot.Count -gt 0) { $Script:CsvUndoStack.Push($snapshot) }
    $Script:CsvRedoStack.Clear()
}

function Set-CsvGridRows {
    param([array]$Rows)
    $table = New-Object System.Data.DataTable
    $columns = if (@($Rows).Count -gt 0) { @($Rows[0].PSObject.Properties.Name) } else { @() }
    foreach ($column in $columns) { $table.Columns.Add($column) | Out-Null }
    foreach ($row in @($Rows)) {
        $newRow = $table.NewRow()
        foreach ($column in $columns) { $newRow[$column] = [string]$row.$column }
        $table.Rows.Add($newRow) | Out-Null
    }
    $csvDataGrid.ItemsSource = $table.DefaultView
    $Script:CsvData = @(ConvertTo-PlainCsvRows -Rows $Rows)
    $Script:CsvModified = $true
    Update-CsvValidationStatus
    Update-CsvModifiedStatus
}

function Show-TextInputDialog {
    param([string]$Title, [string]$Prompt, [string]$DefaultValue = '')
    $dialog = New-Object System.Windows.Window; $dialog.Title = $Title; $dialog.Width = 520; $dialog.Height = 170; $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.Owner = $window; $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Window)
    $panel = New-Object System.Windows.Controls.StackPanel; $panel.Margin = [System.Windows.Thickness]::new(15)
    $label = New-Object System.Windows.Controls.TextBlock; $label.Text = $Prompt; $label.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Text); $label.Margin = [System.Windows.Thickness]::new(0,0,0,8)
    $input = New-Object System.Windows.Controls.TextBox; $input.Text = $DefaultValue; $input.Margin = [System.Windows.Thickness]::new(0,0,0,12)
    $ok = New-Object System.Windows.Controls.Button; $ok.Content = 'OK'; $ok.Width = 90; $ok.HorizontalAlignment = 'Right'; $ok.IsDefault = $true
    $ok.Add_Click({ $dialog.DialogResult = $true; $dialog.Close() })
    $panel.Children.Add($label) | Out-Null; $panel.Children.Add($input) | Out-Null; $panel.Children.Add($ok) | Out-Null; $dialog.Content = $panel
    $input.Focus() | Out-Null
    if ($dialog.ShowDialog()) { return $input.Text }
    return $null
}

function Show-CsvBulkEditDialog {
    $rows = @(Get-CsvGridRows)
    if ($rows.Count -eq 0) { return }
    $dialog = New-Object System.Windows.Window; $dialog.Title = 'Bulk edit CSV'; $dialog.Width = 600; $dialog.Height = 260; $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.Owner = $window; $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Window)
    $panel = New-Object System.Windows.Controls.StackPanel; $panel.Margin = [System.Windows.Thickness]::new(15)
    $column = New-Object System.Windows.Controls.ComboBox; foreach ($name in @($rows[0].PSObject.Properties.Name)) { $column.Items.Add($name) | Out-Null }; $column.SelectedIndex = 0
    $operation = New-Object System.Windows.Controls.ComboBox; foreach ($name in @('Prefix', 'Suffix', 'RegexReplace')) { $operation.Items.Add($name) | Out-Null }; $operation.SelectedIndex = 0
    $value = New-Object System.Windows.Controls.TextBox; $value.Margin = [System.Windows.Thickness]::new(0,8,0,12)
    $ok = New-Object System.Windows.Controls.Button; $ok.Content = 'Apply'; $ok.Width = 90; $ok.HorizontalAlignment = 'Right'; $ok.IsDefault = $true
    $ok.Add_Click({
        try {
            Push-CsvGridUndoSnapshot
            $updated = Invoke-CsvBulkEdit -Rows $rows -Column ([string]$column.SelectedItem) -Operation ([string]$operation.SelectedItem) -Value $value.Text -Replacement $value.Text
            Set-CsvGridRows -Rows $updated; Add-CsvHistoryEntry -Path $Script:CsvHistoryPath -Operation 'bulk-edit' -Before $rows -After $updated | Out-Null; $dialog.DialogResult = $true; $dialog.Close()
        } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Bulk edit failed') }
    })
    foreach ($control in @($column, $operation)) { $panel.Children.Add($control) | Out-Null }; $panel.Children.Add($value) | Out-Null; $panel.Children.Add($ok) | Out-Null; $dialog.Content = $panel; $dialog.ShowDialog() | Out-Null
}

function Show-CsvLibraryDialog {
    if ($Script:CurrentCsvType -ne 'Filters') { [System.Windows.MessageBox]::Show('The filter library is available for Filters.csv.', 'Library'); return }
    $dialog = New-Object System.Windows.Window; $dialog.Title = 'Filter preset library'; $dialog.Width = 560; $dialog.Height = 220; $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.Owner = $window; $dialog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Window)
    $panel = New-Object System.Windows.Controls.StackPanel; $panel.Margin = [System.Windows.Thickness]::new(15)
    $choice = New-Object System.Windows.Controls.ComboBox; foreach ($name in $Script:FilterPresetLibrary.Keys) { $choice.Items.Add($name) | Out-Null }; $choice.SelectedIndex = 0
    $ok = New-Object System.Windows.Controls.Button; $ok.Content = 'Add preset'; $ok.Width = 100; $ok.HorizontalAlignment = 'Right'; $ok.Margin = [System.Windows.Thickness]::new(0,12,0,0)
    $ok.Add_Click({ $rows = @(Get-CsvGridRows); Push-CsvGridUndoSnapshot; $updated = Add-FilterLibraryToRows -Rows $rows -PresetName ([string]$choice.SelectedItem); Set-CsvGridRows -Rows $updated; Add-CsvHistoryEntry -Path $Script:CsvHistoryPath -Operation 'filter-library' -Before $rows -After $updated | Out-Null; $dialog.Close() })
    $panel.Children.Add($choice) | Out-Null; $panel.Children.Add($ok) | Out-Null; $dialog.Content = $panel; $dialog.ShowDialog() | Out-Null
}

function Show-CsvMergeDialog {
    if ($Script:CurrentCsvType -notin @('Filters', 'Bookmarks')) { [System.Windows.MessageBox]::Show('URL merging is available for Filters.csv and Bookmarks.csv.', 'Merge URL'); return }
    $url = Show-TextInputDialog -Title 'Merge CSV from URL' -Prompt 'HTTP(S) URL containing a compatible CSV:'
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    $before = @(Get-CsvGridRows)
    try {
        $merged = Merge-CsvFromUrl -Url $url -ExistingRows $before -CsvType $Script:CurrentCsvType
        if (@($merged.ValidationIssues).Count -gt 0) { [System.Windows.MessageBox]::Show(($merged.ValidationIssues | ForEach-Object { $_.Message } -join "`n"), 'Merge validation failed'); return }
        Push-CsvGridUndoSnapshot; Set-CsvGridRows -Rows $merged.Rows; Add-CsvHistoryEntry -Path $Script:CsvHistoryPath -Operation 'merge-url' -Before $before -After $merged.Rows | Out-Null
        [System.Windows.MessageBox]::Show("Added $($merged.Added) row(s); skipped $($merged.Skipped).", 'Merge complete')
    } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Merge failed') }
}

function Show-CsvPreview {
    if ($Script:CurrentCsvType -ne 'Filters') { [System.Windows.MessageBox]::Show('Live preview is available for Filters.csv.', 'Live preview'); return }
    $query = Show-TextInputDialog -Title 'Everything live preview' -Prompt 'Everything query to preview:'
    if ([string]::IsNullOrWhiteSpace($query)) { return }
    $preview = Get-EverythingSearchPreview -Query $query
    $message = if ($preview.Available) { "$($preview.Message)`n`n$($preview.Results -join "`n")" } else { $preview.Message }
    [System.Windows.MessageBox]::Show($message, 'Live preview')
}

function Show-HealthWindow {
    $report = Get-EverythingHealthReport -SelectedIniPath $Script:EverythingIniPath
    $usn = @(Get-UsnJournalStatus)
    $payload = [ordered]@{ Report = $report; UsnJournal = $usn }
    $healthWindow = New-Object System.Windows.Window; $healthWindow.Title = 'Everything health and journal status'; $healthWindow.Width = 900; $healthWindow.Height = 650; $healthWindow.WindowStartupLocation = 'CenterOwner'; $healthWindow.Owner = $window; $healthWindow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Script:ThemePalette.Window)
    $text = New-Object System.Windows.Controls.TextBox; $text.Margin = [System.Windows.Thickness]::new(12); $text.IsReadOnly = $true; $text.AcceptsReturn = $true; $text.VerticalScrollBarVisibility = 'Auto'; $text.HorizontalScrollBarVisibility = 'Auto'; $text.Text = ($payload | ConvertTo-Json -Depth 12)
    $healthWindow.Content = $text; $healthWindow.ShowDialog() | Out-Null
}

function Load-CurrentCsv {
    $csvKey = if ($cmbCsvType.SelectedItem.Content) { $cmbCsvType.SelectedItem.Content } else { [string]$cmbCsvType.SelectedItem }
    $csvPath = Find-EverythingCsvFile -Folder $Script:EverythingFolder -BaseName $csvKey
    if (-not $csvPath) { $txtCsvPath.Text = "No $csvKey CSV file found"; $Script:CurrentCsvType = $csvKey; $Script:CsvData = @(); $csvDataGrid.ItemsSource = $null; $txtCsvValidation.Text = ''; return }
    $txtCsvPath.Text = $csvPath; $Script:CurrentCsvType = $csvKey; $Script:CsvData = Read-CsvFile -Path $csvPath; $Script:CsvModified = $false; $Script:CsvUndoStack.Clear(); $Script:CsvRedoStack.Clear(); $Script:CsvOriginalRows = @(ConvertTo-PlainCsvRows -Rows $Script:CsvData)
    $dataTable = New-Object System.Data.DataTable
    if ($Script:CsvData.Count -gt 0) {
        $columns = $Script:CsvData[0].PSObject.Properties.Name
        if ($csvKey -eq 'Run_History' -and 'Pinned' -notin $columns) { $columns = @($columns) + 'Pinned' }
        foreach ($col in $columns) { $dataTable.Columns.Add($col) | Out-Null }
        foreach ($row in $Script:CsvData) {
            $newRow = $dataTable.NewRow()
            foreach ($col in $columns) {
                $value = if ($col -eq 'Pinned' -and -not $row.PSObject.Properties['Pinned']) { '0' } else { $row.$col }
                if ($col -match "Date$" -and $value -match '^\d{17,}$') { $newRow[$col] = Convert-FileTimeToDateTime -FileTime ([long]$value) }
                else { $newRow[$col] = $value }
            }
            $dataTable.Rows.Add($newRow) | Out-Null
        }
    }
    $csvDataGrid.ItemsSource = $dataTable.DefaultView; Update-CsvModifiedStatus; Update-CsvValidationStatus
}

function Update-CsvModifiedStatus {
    if ($Script:CsvModified) { $txtCsvModified.Text = "CSV modified"; $btnCsvSave.IsEnabled = $true }
    else { $txtCsvModified.Text = ""; $btnCsvSave.IsEnabled = $false }
}

function Save-CurrentCsv {
    if (-not $Script:CurrentCsvType) { return }
    $csvPath = Find-EverythingCsvFile -Folder $Script:EverythingFolder -BaseName $Script:CurrentCsvType
    if (-not $csvPath) { return }
    $dataView = $csvDataGrid.ItemsSource
    $data = @(Get-CsvGridRows)
    $issues = @(Get-CsvValidationIssues -CsvType $Script:CurrentCsvType -Rows $data)
    if ($issues.Count -gt 0) { [System.Windows.MessageBox]::Show(($issues | ForEach-Object { $_.Message } -join "`n"), 'CSV validation failed', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning); return }
    $before = @(if ($Script:CsvOriginalRows) { $Script:CsvOriginalRows } else { @() })
    $wasRunning = Test-EverythingRunning
    if ($wasRunning) {
        $result = [System.Windows.MessageBox]::Show("Everything should be closed to save CSV files.`n`nClose and save?", "Everything Running", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
        Stop-Everything; Start-Sleep -Seconds 1
    }
    Backup-File -Path $csvPath | Out-Null
    if ($dataView -is [System.Data.DataView]) {
        $headers = @($dataView.Table.Columns | ForEach-Object { $_.ColumnName })
        Write-CsvFile -Path $csvPath -Data $data -Headers $headers
    }
    if ($Script:CurrentCsvType -eq 'Bookmarks') { Sync-BookmarksJson -CsvPath $csvPath -Rows $data | Out-Null }
    Add-CsvHistoryEntry -Path $Script:CsvHistoryPath -Operation 'save' -Before $before -After $data | Out-Null
    $Script:CsvOriginalRows = @(ConvertTo-PlainCsvRows -Rows $data)
    $Script:CsvModified = $false; Update-CsvModifiedStatus
    Update-CsvValidationStatus
    [System.Windows.MessageBox]::Show("CSV saved!", "Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    if ($wasRunning) { Start-Everything }
}

function Add-DefaultsToCsv {
    $csvKey = $Script:CurrentCsvType
    $defaultData = switch ($csvKey) { "Filters" { $Script:DefaultFilters } "Bookmarks" { $Script:DefaultBookmarks } default { $null } }
    if (-not $defaultData) { [System.Windows.MessageBox]::Show("No defaults available for this CSV type.", "No Defaults", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information); return }
    $result = [System.Windows.MessageBox]::Show("Add default entries? Existing entries with same name will be skipped.", "Add Defaults", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $before = @(Get-CsvGridRows); Push-CsvGridUndoSnapshot
    $defaults = $defaultData | ConvertFrom-Csv
    $dataView = $csvDataGrid.ItemsSource
    if ($dataView -is [System.Data.DataView]) {
        $table = $dataView.Table; $existingNames = @{}
        foreach ($row in $table.Rows) { $name = $row["Name"]; if ($name) { $existingNames[$name] = $true } }
        $addedCount = 0
        foreach ($default in $defaults) {
            if (-not $existingNames.ContainsKey($default.Name)) {
                $newRow = $table.NewRow()
                foreach ($col in $table.Columns) {
                    $colName = $col.ColumnName
                    if ($default.PSObject.Properties[$colName]) { $newRow[$colName] = $default.$colName }
                }
                $table.Rows.Add($newRow) | Out-Null; $addedCount++
            }
        }
        if ($csvKey -eq 'Bookmarks') {
            foreach ($entry in @(Get-CommonBookmarkEntries)) {
                if ($existingNames.ContainsKey($entry.Name)) { continue }
                $newRow = $table.NewRow()
                foreach ($col in $table.Columns) {
                    if ($col.ColumnName -eq 'Name') { $newRow[$col.ColumnName] = $entry.Name }
                    elseif ($col.ColumnName -eq 'Search') { $newRow[$col.ColumnName] = $entry.Search }
                    elseif ($col.ColumnName -eq 'Folder') { $newRow[$col.ColumnName] = $entry.Folder }
                }
                $table.Rows.Add($newRow) | Out-Null; $addedCount++
            }
        }
        $Script:CsvModified = $true; Update-CsvModifiedStatus
        $after = @(Get-CsvGridRows); Add-CsvHistoryEntry -Path $Script:CsvHistoryPath -Operation 'add-defaults' -Before $before -After $after | Out-Null; Update-CsvValidationStatus
        [System.Windows.MessageBox]::Show("Added $addedCount default entries.`n`nClick 'Save CSV' to persist.", "Defaults Added", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
}

function Pin-SelectedCsvRows {
    if ($Script:CurrentCsvType -ne 'Run_History') { [System.Windows.MessageBox]::Show('Pinning is available for Run_History.csv.', 'Pin history'); return }
    $dataView = $csvDataGrid.ItemsSource
    if (-not ($dataView -is [System.Data.DataView])) { return }
    if (-not $dataView.Table.Columns.Contains('Pinned')) { $dataView.Table.Columns.Add('Pinned') | Out-Null }
    $selected = @($csvDataGrid.SelectedItems)
    foreach ($item in $selected) { if ($item -is [System.Data.DataRowView]) { $item.Row['Pinned'] = '1' } }
    $Script:CsvModified = $true; Update-CsvModifiedStatus; Update-CsvValidationStatus
}

function Scrub-CurrentHistory {
    if ($Script:CurrentCsvType -notin @('Search_History', 'Run_History')) { [System.Windows.MessageBox]::Show('Scrubbing is available for history CSV files.', 'Scrub history'); return }
    $pattern = Show-TextInputDialog -Title 'Scrub history' -Prompt 'Remove rows matching this regular expression:'
    if ([string]::IsNullOrWhiteSpace($pattern)) { return }
    $before = @(Get-CsvGridRows); Push-CsvGridUndoSnapshot
    try { $after = @(Remove-HistoryMatches -Rows $before -Pattern $pattern); Set-CsvGridRows -Rows $after; Add-CsvHistoryEntry -Path $Script:CsvHistoryPath -Operation 'history-scrub' -Before $before -After $after | Out-Null }
    catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Scrub failed') }
}

function Undo-CsvGridChange {
    if ($Script:CsvUndoStack.Count -eq 0) { return }
    $current = @(Get-CsvGridRows); $Script:CsvRedoStack.Push($current); $previous = $Script:CsvUndoStack.Pop(); Set-CsvGridRows -Rows $previous
}

# ============================================================================
# EVENT HANDLERS
# ============================================================================

function Initialize-UiOptions {
    if ($cmbPreset) {
        $cmbPreset.Items.Clear()
        foreach ($presetName in $Script:PresetDefinitions.Keys) { $cmbPreset.Items.Add($presetName) | Out-Null }
        $cmbPreset.SelectedItem = 'Recommended'
    }
    if ($cmbTheme) {
        $cmbTheme.Items.Clear(); foreach ($themeName in @('Dark', 'Light', 'High Contrast')) { $cmbTheme.Items.Add($themeName) | Out-Null }; $cmbTheme.SelectedItem = 'Dark'
    }
    Set-Theme -Name 'Dark'
    $window.Add_KeyDown({ param($sender, $event); if ($event.KeyboardDevice.Modifiers -eq 'Control' -and $event.Key -eq 'K') { Show-CommandPalette; $event.Handled = $true } })
}

$cmbIniProfile.Add_SelectionChanged({ if ($cmbIniProfile.SelectedItem -and $cmbIniProfile.SelectedItem.Path -ne $Script:EverythingIniPath) { Load-Settings -Path $cmbIniProfile.SelectedItem.Path; Show-Category -CategoryName $txtCategoryName.Text } })
$txtSettingSearch.Add_TextChanged({ $Script:SettingsSearchText = $txtSettingSearch.Text; Show-Category -CategoryName $txtCategoryName.Text })
$chkDifferences.Add_Checked({ $Script:ShowOnlyDifferences = $true; Show-Category -CategoryName $txtCategoryName.Text })
$chkDifferences.Add_Unchecked({ $Script:ShowOnlyDifferences = $false; Show-Category -CategoryName $txtCategoryName.Text })
$btnShowDiff.Add_Click({ Show-SettingsDiffWindow })
$cmbTheme.Add_SelectionChanged({ if ($cmbTheme.SelectedItem) { Set-Theme -Name ([string]$cmbTheme.SelectedItem) } })

$btnBackup.Add_Click({ if ($Script:EverythingIniPath -and (Test-Path $Script:EverythingIniPath)) {
    $backupPath = Backup-File -Path $Script:EverythingIniPath
    [System.Windows.MessageBox]::Show("Backup created:`n$backupPath", "Backup", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) } })
$btnRecommended.Add_Click({ Apply-RecommendedSettings })
$btnUndo.Add_Click({ if (Undo-SettingsChange -Settings $Script:Settings) { Sync-ModifiedSettings; Update-ModifiedCount; Show-Category -CategoryName $txtCategoryName.Text } })
$btnRedo.Add_Click({ if (Redo-SettingsChange -Settings $Script:Settings) { Sync-ModifiedSettings; Update-ModifiedCount; Show-Category -CategoryName $txtCategoryName.Text } })
$btnHealth.Add_Click({ Show-HealthWindow })
$btnReload.Add_Click({ Load-Settings; Show-Category -CategoryName $txtCategoryName.Text })
$btnSave.Add_Click({ Save-Settings })
$btnRestartEverything.Add_Click({ $wasRunning = Test-EverythingRunning; if ($wasRunning) { Stop-Everything; Start-Sleep -Seconds 1 }; Start-Everything; Start-Sleep -Seconds 1; Update-StatusIndicator })
$cmbCsvType.Add_SelectionChanged({ Load-CurrentCsv })
$btnCsvReload.Add_Click({ Load-CurrentCsv })
$btnCsvAddDefaults.Add_Click({ Add-DefaultsToCsv })
$btnCsvLibrary.Add_Click({ Show-CsvLibraryDialog })
$btnCsvPreview.Add_Click({ Show-CsvPreview })
$btnCsvMerge.Add_Click({ Show-CsvMergeDialog })
$btnCsvBulkEdit.Add_Click({ Show-CsvBulkEditDialog })
$btnCsvPin.Add_Click({ Pin-SelectedCsvRows })
$btnCsvScrub.Add_Click({ Scrub-CurrentHistory })
$btnCsvUndo.Add_Click({ Undo-CsvGridChange })
$btnCsvBackup.Add_Click({ $csvPath = Find-EverythingCsvFile -Folder $Script:EverythingFolder -BaseName $Script:CurrentCsvType
    if ($csvPath -and (Test-Path $csvPath)) { $backupPath = Backup-File -Path $csvPath; [System.Windows.MessageBox]::Show("Backup created:`n$backupPath", "Backup", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) } })
$btnCsvSave.Add_Click({ Save-CurrentCsv })
$btnCsvDelete.Add_Click({ $selectedItems = $csvDataGrid.SelectedItems; if ($selectedItems.Count -eq 0) { return }
    $result = [System.Windows.MessageBox]::Show("Delete $($selectedItems.Count) selected row(s)?", "Confirm Delete", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        $dataView = $csvDataGrid.ItemsSource
        if ($dataView -is [System.Data.DataView]) { Push-CsvGridUndoSnapshot; $rowsToDelete = @(); foreach ($item in $selectedItems) { if ($item -is [System.Data.DataRowView]) { $rowsToDelete += $item.Row } }
        foreach ($row in $rowsToDelete) { $row.Delete() }; $Script:CsvModified = $true; Update-CsvModifiedStatus; Update-CsvValidationStatus } } })
$csvDataGrid.Add_BeginningEdit({ Push-CsvGridUndoSnapshot })
$csvDataGrid.Add_CellEditEnding({ $Script:CsvModified = $true; Update-CsvModifiedStatus; Update-CsvValidationStatus })

$timer = New-Object System.Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({ Update-StatusIndicator }); $timer.Start()

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $Script:EverythingFolder)) {
    [System.Windows.MessageBox]::Show("Everything folder not found at:`n$Script:EverythingFolder", "Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
}

Write-DiagnosticLog -Message 'starting UI initialization'
Initialize-UiOptions; Initialize-Profiles; Initialize-MainTabs; Load-Settings; Initialize-Profiles; Initialize-Categories; Show-Category -CategoryName "Database"
Write-DiagnosticLog -Message 'UI initialization complete'
if ($UiSmoke) {
    $smokeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $smokeTimer.Interval = [TimeSpan]::FromSeconds(10)
    $smokeTimer.Add_Tick({ $smokeTimer.Stop(); $window.Close() })
    $smokeTimer.Start()
}
$window.ShowDialog() | Out-Null
Write-DiagnosticLog -Message 'UI dialog closed'
$timer.Stop()
}

if ($SelfTest) {
    # The test harness is kept in tests/ so the production script can remain a
    # single-file distribution while still supporting a fully headless suite.
    Write-Output 'Self-test mode requires tests/EverythingSettingsManager.Tests.ps1.'
} elseif ($Script:CliRequested) {
    Invoke-CliRequest
}
