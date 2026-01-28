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

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ============================================================================
# CONFIGURATION
# ============================================================================

$Script:EverythingFolder = "$env:APPDATA\Everything"
$Script:EverythingIniPath = $null
$Script:BackupFolder = "$env:APPDATA\Everything\Backups"
$Script:Settings = @{}
$Script:OriginalSettings = @{}
$Script:ModifiedSettings = @{}
$Script:CurrentCsvType = $null
$Script:CsvData = @()
$Script:CsvModified = $false

# ============================================================================
# AUTO-DETECT INI FILE
# ============================================================================

function Find-EverythingIniFile {
    param([string]$Folder)
    
    if (-not (Test-Path $Folder)) {
        return $null
    }
    
    # Find all INI files that start with "Everything" but don't contain "backup"
    $iniFiles = Get-ChildItem -Path $Folder -Filter "Everything*.ini" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'backup' } |
        Sort-Object LastWriteTime -Descending
    
    if ($iniFiles.Count -gt 0) {
        return $iniFiles[0].FullName
    }
    
    return $null
}

function Find-EverythingCsvFile {
    param(
        [string]$Folder,
        [string]$BaseName  # e.g., "Filters", "Bookmarks", "Run_History", "Search_History"
    )
    
    if (-not (Test-Path $Folder)) {
        return $null
    }
    
    # Find CSV files matching the base name, excluding backups
    $csvFiles = Get-ChildItem -Path $Folder -Filter "$BaseName*.csv" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'backup' } |
        Sort-Object LastWriteTime -Descending
    
    if ($csvFiles.Count -gt 0) {
        return $csvFiles[0].FullName
    }
    
    return $null
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
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Read-IniFile {
    param([string]$Path)
    $ini = @{}
    if (-not (Test-Path $Path)) { return $ini }
    $content = Get-Content $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($content)) { return $ini }
    foreach ($line in $content -split "`r?`n") {
        $line = $line.Trim()
        if ($line -match '^([^=]+)=(.*)$') {
            $ini[$Matches[1].Trim()] = $Matches[2]
        }
    }
    return $ini
}

function Write-IniFile {
    param([string]$Path, [hashtable]$Settings)
    $lines = @()
    if (Test-Path $Path) { $lines = Get-Content $Path }
    $updated = @{}
    $newLines = @()
    foreach ($line in $lines) {
        if ($line -match '^([^=;]+)=') {
            $key = $Matches[1].Trim()
            if ($Settings.ContainsKey($key)) {
                $newLines += "$key=$($Settings[$key])"
                $updated[$key] = $true
            } else { $newLines += $line }
        } else { $newLines += $line }
    }
    foreach ($key in $Settings.Keys) {
        if (-not $updated.ContainsKey($key)) { $newLines += "$key=$($Settings[$key])" }
    }
    Set-Content -Path $Path -Value $newLines -Encoding UTF8
}

function Read-CsvFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    try { return @(Import-Csv -Path $Path -ErrorAction Stop) }
    catch { return @() }
}

function Write-CsvFile {
    param([string]$Path, [array]$Data)
    if ($Data.Count -eq 0) { return }
    $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path $Script:BackupFolder)) {
        New-Item -ItemType Directory -Path $Script:BackupFolder -Force | Out-Null
    }
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $Script:BackupFolder "${fileName}_${timestamp}${ext}"
    Copy-Item -Path $Path -Destination $backupPath -Force
    return $backupPath
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

# ============================================================================
# XAML UI
# ============================================================================

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Everything Settings Manager v2.0" Width="1200" Height="800" WindowStartupLocation="CenterScreen" Background="#1E1E1E">
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
<Border Grid.Row="0" Background="#252526" Padding="20,15"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0"><TextBlock Text="Everything Settings Manager" FontSize="22" FontWeight="SemiBold" Foreground="#E0E0E0"/><TextBlock x:Name="txtIniPath" Text="Auto-detecting..." FontSize="12" Foreground="#9D9D9D" Margin="0,4,0,0"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Border x:Name="statusIndicator" Width="12" Height="12" CornerRadius="6" Background="#4EC9B0" Margin="0,0,8,0"/><TextBlock x:Name="txtStatus" Text="Everything: Running" Foreground="#9D9D9D" VerticalAlignment="Center"/></StackPanel></Grid></Border>
<Border Grid.Row="1" Background="#252526" BorderBrush="#3F3F46" BorderThickness="0,0,0,1"><StackPanel x:Name="mainTabPanel" Orientation="Horizontal"/></Border>
<Grid Grid.Row="2" x:Name="contentGrid">
<Grid x:Name="settingsContent" Visibility="Visible"><Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Border Grid.Column="0" Background="#252526" BorderBrush="#3F3F46" BorderThickness="0,0,1,0"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="categoryPanel" Margin="0,10,0,10"/></ScrollViewer></Border><Border Grid.Column="1" Padding="20"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><StackPanel Grid.Row="0" Margin="0,0,0,15"><TextBlock x:Name="txtCategoryName" Text="Database" FontSize="18" FontWeight="SemiBold" Foreground="#E0E0E0"/><TextBlock x:Name="txtCategoryDesc" Text="" FontSize="12" Foreground="#9D9D9D" Margin="0,4,0,0" TextWrapping="Wrap"/></StackPanel><ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="settingsPanel"/></ScrollViewer></Grid></Border></Grid>
<Grid x:Name="csvContent" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Border Grid.Row="0" Background="#252526" Padding="15"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" Orientation="Horizontal"><TextBlock Text="Edit: " Foreground="#E0E0E0" VerticalAlignment="Center" Margin="0,0,10,0"/><ComboBox x:Name="cmbCsvType" Width="200" Style="{StaticResource DarkComboBox}"><ComboBoxItem Content="Filters" IsSelected="True"/><ComboBoxItem Content="Bookmarks"/><ComboBoxItem Content="Search_History"/><ComboBoxItem Content="Run_History"/></ComboBox></StackPanel><TextBlock x:Name="txtCsvPath" Grid.Column="1" Foreground="#9D9D9D" VerticalAlignment="Center" Margin="20,0,0,0"/><StackPanel Grid.Column="2" Orientation="Horizontal"><Button x:Name="btnCsvReload" Content="Reload" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><Button x:Name="btnCsvAddDefaults" Content="Add Defaults" Style="{StaticResource SecondaryButton}"/></StackPanel></Grid></Border><DataGrid x:Name="csvDataGrid" Grid.Row="1" AutoGenerateColumns="True" CanUserAddRows="True" CanUserDeleteRows="True" Margin="15"/><Border Grid.Row="2" Background="#252526" Padding="15"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" Orientation="Horizontal"><Button x:Name="btnCsvDelete" Content="Delete Selected" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><Button x:Name="btnCsvBackup" Content="Create Backup" Style="{StaticResource SecondaryButton}"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal"><TextBlock x:Name="txtCsvModified" Text="" Foreground="#CE9178" VerticalAlignment="Center" Margin="0,0,15,0"/><Button x:Name="btnCsvSave" Content="Save CSV" IsEnabled="False"/></StackPanel></Grid></Border></Grid>
</Grid>
<Border Grid.Row="3" Background="#252526" Padding="20,12" BorderBrush="#3F3F46" BorderThickness="0,1,0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" Orientation="Horizontal"><TextBlock x:Name="txtModified" Text="" Foreground="#CE9178" VerticalAlignment="Center" Margin="0,0,15,0"/><Button x:Name="btnBackup" Content="Create Backup" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><Button x:Name="btnRecommended" Content="Apply Recommended" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><Button x:Name="btnReload" Content="Reload" Style="{StaticResource SecondaryButton}"/></StackPanel><StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="btnRestartEverything" Content="Restart Everything" Style="{StaticResource SecondaryButton}" Margin="0,0,10,0"/><Button x:Name="btnSave" Content="Save Settings" IsEnabled="False"/></StackPanel></Grid></Border>
</Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get UI elements
$txtIniPath = $window.FindName("txtIniPath"); $txtStatus = $window.FindName("txtStatus"); $statusIndicator = $window.FindName("statusIndicator")
$mainTabPanel = $window.FindName("mainTabPanel"); $settingsContent = $window.FindName("settingsContent"); $csvContent = $window.FindName("csvContent")
$categoryPanel = $window.FindName("categoryPanel"); $settingsPanel = $window.FindName("settingsPanel")
$txtCategoryName = $window.FindName("txtCategoryName"); $txtCategoryDesc = $window.FindName("txtCategoryDesc")
$txtModified = $window.FindName("txtModified"); $btnBackup = $window.FindName("btnBackup"); $btnRecommended = $window.FindName("btnRecommended")
$btnReload = $window.FindName("btnReload"); $btnRestartEverything = $window.FindName("btnRestartEverything"); $btnSave = $window.FindName("btnSave")
$cmbCsvType = $window.FindName("cmbCsvType"); $txtCsvPath = $window.FindName("txtCsvPath"); $csvDataGrid = $window.FindName("csvDataGrid")
$btnCsvReload = $window.FindName("btnCsvReload"); $btnCsvAddDefaults = $window.FindName("btnCsvAddDefaults")
$btnCsvDelete = $window.FindName("btnCsvDelete"); $btnCsvBackup = $window.FindName("btnCsvBackup")
$btnCsvSave = $window.FindName("btnCsvSave"); $txtCsvModified = $window.FindName("txtCsvModified")

# ============================================================================
# UI FUNCTIONS
# ============================================================================

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
    $container.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(37, 37, 38))
    $container.CornerRadius = [System.Windows.CornerRadius]::new(4)
    $container.Padding = [System.Windows.Thickness]::new(15)
    $container.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
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
    $keyLabel = New-Object System.Windows.Controls.TextBlock; $keyLabel.Text = $Key; $keyLabel.FontSize = 11
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
        $currentValue = if ($Script:Settings.ContainsKey($settingKey)) { $Script:Settings[$settingKey] } else { "$($definition.Recommended)" }
        $control = Create-SettingControl -Key $settingKey -Definition $definition -CurrentValue $currentValue
        if ($control) { $settingsPanel.Children.Add($control) | Out-Null }
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

function Load-Settings {
    $Script:EverythingIniPath = Find-EverythingIniFile -Folder $Script:EverythingFolder
    if (-not $Script:EverythingIniPath) { $txtIniPath.Text = "No Everything INI file found in $Script:EverythingFolder"; return }
    $Script:Settings = Read-IniFile -Path $Script:EverythingIniPath
    $Script:OriginalSettings = @{}; foreach ($key in $Script:Settings.Keys) { $Script:OriginalSettings[$key] = $Script:Settings[$key] }
    $Script:ModifiedSettings = @{}
    $iniFileName = [System.IO.Path]::GetFileName($Script:EverythingIniPath)
    $txtIniPath.Text = "$Script:EverythingIniPath (auto-detected: $iniFileName)"
    Update-StatusIndicator; Update-ModifiedCount
}

function Save-Settings {
    if ($Script:ModifiedSettings.Count -eq 0 -or -not $Script:EverythingIniPath) { return }
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
    $result = [System.Windows.MessageBox]::Show("Apply all recommended settings?", "Apply Recommended", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    foreach ($category in $Script:SettingsDefinitions.Values) {
        foreach ($settingKey in $category.Settings.Keys) {
            $definition = $category.Settings[$settingKey]; $recommended = $definition.Recommended.ToString()
            $Script:Settings[$settingKey] = $recommended
            if ($Script:OriginalSettings[$settingKey] -ne $recommended) { $Script:ModifiedSettings[$settingKey] = $recommended }
        }
    }
    Update-ModifiedCount; Show-Category -CategoryName $txtCategoryName.Text
    [System.Windows.MessageBox]::Show("Recommended settings applied. Click 'Save Settings' to persist.", "Applied", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}

# ============================================================================
# CSV FUNCTIONS
# ============================================================================

function Load-CurrentCsv {
    $csvKey = $cmbCsvType.SelectedItem.Content
    $csvPath = Find-EverythingCsvFile -Folder $Script:EverythingFolder -BaseName $csvKey
    if (-not $csvPath) { $txtCsvPath.Text = "No $csvKey CSV file found"; $Script:CsvData = @(); $csvDataGrid.ItemsSource = $null; return }
    $txtCsvPath.Text = $csvPath; $Script:CurrentCsvType = $csvKey; $Script:CsvData = Read-CsvFile -Path $csvPath; $Script:CsvModified = $false
    $dataTable = New-Object System.Data.DataTable
    if ($Script:CsvData.Count -gt 0) {
        $columns = $Script:CsvData[0].PSObject.Properties.Name
        foreach ($col in $columns) { $dataTable.Columns.Add($col) | Out-Null }
        foreach ($row in $Script:CsvData) {
            $newRow = $dataTable.NewRow()
            foreach ($col in $columns) {
                $value = $row.$col
                if ($col -match "Date$" -and $value -match '^\d{17,}$') { $newRow[$col] = Convert-FileTimeToDateTime -FileTime ([long]$value) }
                else { $newRow[$col] = $value }
            }
            $dataTable.Rows.Add($newRow) | Out-Null
        }
    }
    $csvDataGrid.ItemsSource = $dataTable.DefaultView; Update-CsvModifiedStatus
}

function Update-CsvModifiedStatus {
    if ($Script:CsvModified) { $txtCsvModified.Text = "CSV modified"; $btnCsvSave.IsEnabled = $true }
    else { $txtCsvModified.Text = ""; $btnCsvSave.IsEnabled = $false }
}

function Save-CurrentCsv {
    if (-not $Script:CurrentCsvType) { return }
    $csvPath = Find-EverythingCsvFile -Folder $Script:EverythingFolder -BaseName $Script:CurrentCsvType
    if (-not $csvPath) { return }
    $wasRunning = Test-EverythingRunning
    if ($wasRunning) {
        $result = [System.Windows.MessageBox]::Show("Everything should be closed to save CSV files.`n`nClose and save?", "Everything Running", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
        Stop-Everything; Start-Sleep -Seconds 1
    }
    Backup-File -Path $csvPath
    $dataView = $csvDataGrid.ItemsSource
    if ($dataView -is [System.Data.DataView]) {
        $table = $dataView.Table; $data = @()
        foreach ($row in $table.Rows) {
            $obj = New-Object PSObject
            foreach ($col in $table.Columns) { $obj | Add-Member -NotePropertyName $col.ColumnName -NotePropertyValue $row[$col.ColumnName] }
            $data += $obj
        }
        Write-CsvFile -Path $csvPath -Data $data
    }
    $Script:CsvModified = $false; Update-CsvModifiedStatus
    [System.Windows.MessageBox]::Show("CSV saved!", "Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    if ($wasRunning) { Start-Everything }
}

function Add-DefaultsToCsv {
    $csvKey = $Script:CurrentCsvType
    $defaultData = switch ($csvKey) { "Filters" { $Script:DefaultFilters } "Bookmarks" { $Script:DefaultBookmarks } default { $null } }
    if (-not $defaultData) { [System.Windows.MessageBox]::Show("No defaults available for this CSV type.", "No Defaults", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information); return }
    $result = [System.Windows.MessageBox]::Show("Add default entries? Existing entries with same name will be skipped.", "Add Defaults", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
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
        $Script:CsvModified = $true; Update-CsvModifiedStatus
        [System.Windows.MessageBox]::Show("Added $addedCount default entries.`n`nClick 'Save CSV' to persist.", "Defaults Added", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
}

# ============================================================================
# EVENT HANDLERS
# ============================================================================

$btnBackup.Add_Click({ if ($Script:EverythingIniPath -and (Test-Path $Script:EverythingIniPath)) {
    $backupPath = Backup-File -Path $Script:EverythingIniPath
    [System.Windows.MessageBox]::Show("Backup created:`n$backupPath", "Backup", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) } })
$btnRecommended.Add_Click({ Apply-RecommendedSettings })
$btnReload.Add_Click({ Load-Settings; Show-Category -CategoryName $txtCategoryName.Text })
$btnSave.Add_Click({ Save-Settings })
$btnRestartEverything.Add_Click({ $wasRunning = Test-EverythingRunning; if ($wasRunning) { Stop-Everything; Start-Sleep -Seconds 1 }; Start-Everything; Start-Sleep -Seconds 1; Update-StatusIndicator })
$cmbCsvType.Add_SelectionChanged({ Load-CurrentCsv })
$btnCsvReload.Add_Click({ Load-CurrentCsv })
$btnCsvAddDefaults.Add_Click({ Add-DefaultsToCsv })
$btnCsvBackup.Add_Click({ $csvPath = Find-EverythingCsvFile -Folder $Script:EverythingFolder -BaseName $Script:CurrentCsvType
    if ($csvPath -and (Test-Path $csvPath)) { $backupPath = Backup-File -Path $csvPath; [System.Windows.MessageBox]::Show("Backup created:`n$backupPath", "Backup", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) } })
$btnCsvSave.Add_Click({ Save-CurrentCsv })
$btnCsvDelete.Add_Click({ $selectedItems = $csvDataGrid.SelectedItems; if ($selectedItems.Count -eq 0) { return }
    $result = [System.Windows.MessageBox]::Show("Delete $($selectedItems.Count) selected row(s)?", "Confirm Delete", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
        $dataView = $csvDataGrid.ItemsSource
        if ($dataView -is [System.Data.DataView]) { $rowsToDelete = @(); foreach ($item in $selectedItems) { if ($item -is [System.Data.DataRowView]) { $rowsToDelete += $item.Row } }
        foreach ($row in $rowsToDelete) { $row.Delete() }; $Script:CsvModified = $true; Update-CsvModifiedStatus } } })
$csvDataGrid.Add_CellEditEnding({ $Script:CsvModified = $true; Update-CsvModifiedStatus })

$timer = New-Object System.Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({ Update-StatusIndicator }); $timer.Start()

# ============================================================================
# INITIALIZATION
# ============================================================================

if (-not (Test-Path $Script:EverythingFolder)) {
    [System.Windows.MessageBox]::Show("Everything folder not found at:`n$Script:EverythingFolder", "Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
}

Initialize-MainTabs; Load-Settings; Initialize-Categories; Show-Category -CategoryName "Database"
$window.ShowDialog() | Out-Null
$timer.Stop()
