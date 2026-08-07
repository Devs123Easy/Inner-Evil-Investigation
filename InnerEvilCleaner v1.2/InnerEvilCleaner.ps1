[CmdletBinding()]
param(
    [ValidateSet("Quarantine","Delete")]
    [string]$Mode = "Quarantine",
    [switch]$NoPrompt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$SuspiciousIp = "40.76.119.174"
$SuspiciousPort = 3001
$SuspiciousDomain = "iloveanimals.life"
$Guid = "38d9ffe0-d9ea-5603-a8fc-8037ddd7cc83"

$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BaseDir = Join-Path $env:USERPROFILE "Desktop\InnerEvil_Remediation_$TimeStamp"
$QuarantineDir = Join-Path $BaseDir "Quarantine"
$BackupDir = Join-Path $BaseDir "Backups"
$LogPath = Join-Path $BaseDir "remediation.log"
$ReportPath = Join-Path $BaseDir "report.txt"

New-Item -ItemType Directory -Force -Path $BaseDir, $QuarantineDir, $BackupDir | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR","OK")][string]$Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "OK"    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SafeName {
    param([string]$Path)
    $name = $Path -replace '^[A-Za-z]:', ''
    $name = $name -replace '[\\/:*?"<>|]', '_'
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "item" }
    return $name
}

function Save-FileCopy {
    param([string]$Path, [string]$Label = "backup")
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $dest = Join-Path $BackupDir ("{0}_{1}" -f $Label, (Get-SafeName $Path))
        if ((Get-Item -LiteralPath $Path -Force).PSIsContainer) {
            Copy-Item -LiteralPath $Path -Destination $dest -Recurse -Force -ErrorAction Stop
        } else {
            Copy-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop
        }
        Write-Log "Backup created: $Path -> $dest" "OK"
    } catch {
        Write-Log "Backup failed for ${Path}: $($_.Exception.Message)" "WARN"
    }
}

function Remove-Or-Quarantine {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Reason = "Known InnerEvil/Exastealer artifact"
    )
    try {
        $exists = Test-Path -LiteralPath $Path -ErrorAction Stop
    } catch {
        Write-Log "Ignored invalid path value: $Path | $($_.Exception.Message)" "WARN"
        return
    }

    if (-not $exists) {
        Write-Log "Not present: $Path"
        return
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Log "Found: $Path ($Reason)" "WARN"

        if ($Mode -eq "Quarantine") {
            $destName = "{0}_{1}" -f (Get-Date -Format "HHmmssfff"), (Get-SafeName $Path)
            $dest = Join-Path $QuarantineDir $destName
            Move-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop
            Write-Log "Quarantined: $Path -> $dest" "OK"
        } else {
            if ($item.PSIsContainer) {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            }
            Write-Log "Deleted: $Path" "OK"
        }
    } catch {
        Write-Log "Failed to remediate ${Path}: $($_.Exception.Message)" "ERROR"
    }
}

function Stop-SuspiciousProcesses {
    Write-Log "Checking running processes..."
    $targets = Get-CimInstance Win32_Process | Where-Object {
        $p = $_
        $exe = [string]$p.ExecutablePath
        $cmd = [string]$p.CommandLine
        $name = [string]$p.Name

        ($name -ieq "InnerEvil.exe") -or
        ($name -ieq "elevate.exe" -and $exe -like "$env:LOCALAPPDATA\Programs\InnerEvil*") -or
        ($exe -like "$env:LOCALAPPDATA\emre*") -or
        ($cmd -match '(?i)\\emre\\emre\.jar') -or
        ($cmd -match '(?i)Exastealer') -or
        ($cmd -match [regex]::Escape($SuspiciousIp))
    }

    foreach ($p in $targets) {
        try {
            Write-Log "Stopping PID $($p.ProcessId): $($p.Name) | $($p.ExecutablePath) | $($p.CommandLine)" "WARN"
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
            Write-Log "Stopped PID $($p.ProcessId)" "OK"
        } catch {
            Write-Log "Could not stop PID $($p.ProcessId): $($_.Exception.Message)" "ERROR"
        }
    }
}

function Read-SavedExeName {
    $marker = Join-Path $env:TEMP ".exename"
    if (-not (Test-Path -LiteralPath $marker)) { return $null }

    try {
        $raw = Get-Content -LiteralPath $marker -Raw -ErrorAction Stop

        # The marker may contain multiple lines or malformed data. Accept only
        # a single safe Windows filename ending in .exe; never accept a path.
        $candidates = @(
            $raw -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_.Length -le 200 }
        )

        foreach ($candidate in $candidates) {
            if ($candidate -match '^[A-Za-z0-9 _!().+\-]{1,196}\.exe$' -and
                $candidate -notmatch '^\.+$' -and
                -not [IO.Path]::IsPathRooted($candidate) -and
                $candidate.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -lt 0) {
                Write-Log "Accepted safe launcher filename from .exename: $candidate"
                return $candidate
            }
        }

        $escaped = ($raw -replace "`r", "\r" -replace "`n", "\n")
        Write-Log "Ignored malformed .exename content: $escaped" "WARN"
    } catch {
        Write-Log "Could not read ${marker}: $($_.Exception.Message)" "WARN"
    }
    return $null
}

function Remove-StartupArtifacts {
    $startupDirs = @(
        [Environment]::GetFolderPath("Startup"),
        "$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $savedExe = Read-SavedExeName
    $candidateNames = @("InnerEvilSetup.vbs", "InnerEvil.vbs")
    if ($savedExe) {
        $candidateNames += ([IO.Path]::GetFileNameWithoutExtension($savedExe) + ".vbs")
    }

    foreach ($dir in $startupDirs) {
        foreach ($name in ($candidateNames | Select-Object -Unique)) {
            Remove-Or-Quarantine -Path (Join-Path $dir $name) -Reason "Known launcher Startup script"
        }

        Get-ChildItem -LiteralPath $dir -Filter "*.vbs" -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop
                if ($content -match '(?i)(\\emre\\|\.startup_mode|\.exename|InnerEvil|emre\.jar)') {
                    Remove-Or-Quarantine -Path $_.FullName -Reason "Startup VBS contains InnerEvil/Exastealer markers"
                }
            } catch {
                Write-Log "Could not inspect Startup script $($_.FullName)" "WARN"
            }
        }
    }
}

function Backup-And-RemoveRegistryKey {
    param([string]$PsPath, [string]$RegExePath)
    if (-not (Test-Path $PsPath)) {
        Write-Log "Registry key not present: $RegExePath"
        return
    }

    $backupName = (Get-SafeName $RegExePath) + ".reg"
    $backupPath = Join-Path $BackupDir $backupName
    & reg.exe export $RegExePath $backupPath /y | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Registry backup: $RegExePath -> $backupPath" "OK"
    } else {
        Write-Log "Registry export failed: $RegExePath" "WARN"
    }

    try {
        Remove-Item -Path $PsPath -Recurse -Force -ErrorAction Stop
        Write-Log "Registry key removed: $RegExePath" "OK"
    } catch {
        Write-Log "Registry key removal failed: $RegExePath | $($_.Exception.Message)" "ERROR"
    }
}

function Remove-SuspiciousRunValues {
    $runKeys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce"
    )

    foreach ($key in $runKeys) {
        if (-not (Test-Path $key)) { continue }
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        foreach ($prop in $props.PSObject.Properties) {
            if ($prop.Name -like "PS*") { continue }
            $value = [string]$prop.Value
            if ($value -match '(?i)(\\emre\\|emre\.jar|InnerEvil|Exastealer|\.startup_mode|\.exename)' -or
                $value -match [regex]::Escape($SuspiciousIp)) {
                try {
                    $backupLine = "$key :: $($prop.Name) = $value"
                    Add-Content -LiteralPath (Join-Path $BackupDir "removed_run_values.txt") -Value $backupLine
                    Remove-ItemProperty -Path $key -Name $prop.Name -Force -ErrorAction Stop
                    Write-Log "Removed suspicious Run value: $backupLine" "OK"
                } catch {
                    Write-Log "Failed removing Run value $key\$($prop.Name): $($_.Exception.Message)" "ERROR"
                }
            }
        }
    }
}

function Remove-SuspiciousScheduledTasks {
    Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $task = $_
        $actionTexts = @()

        foreach ($action in @($task.Actions)) {
            if ($null -eq $action) { continue }

            $parts = @()
            foreach ($propertyName in @("Execute", "Arguments", "WorkingDirectory", "ClassId", "Data")) {
                $property = $action.PSObject.Properties[$propertyName]
                if ($null -ne $property -and $null -ne $property.Value) {
                    $parts += [string]$property.Value
                }
            }

            if ($parts.Count -eq 0) {
                $parts += ($action | Out-String).Trim()
            }
            $actionTexts += ($parts -join " ")
        }

        $joined = ($actionTexts -join " ")
        if ([string]::IsNullOrWhiteSpace($joined)) { return }

        if ($joined -match '(?i)(\\emre\\|emre\.jar|InnerEvil|Exastealer|\.startup_mode|\.exename)' -or
            $joined -match [regex]::Escape($SuspiciousIp)) {
            try {
                $record = "$($task.TaskPath)$($task.TaskName) :: $joined"
                Add-Content -LiteralPath (Join-Path $BackupDir "removed_scheduled_tasks.txt") -Value $record
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                Write-Log "Removed suspicious scheduled task: $record" "OK"
            } catch {
                Write-Log "Failed removing task $($task.TaskPath)$($task.TaskName): $($_.Exception.Message)" "ERROR"
            }
        }
    }
}

function Remove-SuspiciousServices {
    Get-CimInstance Win32_Service | ForEach-Object {
        $svc = $_
        $path = [string]$svc.PathName
        if ($path -match '(?i)(\\emre\\|emre\.jar|InnerEvil|Exastealer)' -or
            $path -match [regex]::Escape($SuspiciousIp)) {
            try {
                Add-Content -LiteralPath (Join-Path $BackupDir "removed_services.txt") -Value "$($svc.Name) :: $path"
                if ($svc.State -eq "Running") {
                    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                }
                & sc.exe delete $svc.Name | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Deleted suspicious service: $($svc.Name) :: $path" "OK"
                } else {
                    Write-Log "sc.exe could not delete service $($svc.Name)" "ERROR"
                }
            } catch {
                Write-Log "Failed removing service $($svc.Name): $($_.Exception.Message)" "ERROR"
            }
        }
    }
}

function Remove-KnownFiles {
    # Read the marker before it is quarantined/deleted.
    $savedExe = Read-SavedExeName

    $knownPaths = @(
        "$env:LOCALAPPDATA\emre",
        "$env:LOCALAPPDATA\Programs\InnerEvil",
        "$env:LOCALAPPDATA\innerevil-updater",
        "$env:TEMP\.startup_mode",
        "$env:TEMP\launcher_debug.log",
        "$env:TEMP\injection_debug.log",
        "$env:TEMP\uac_output.log",
        "$env:TEMP\uac_bypass.exe",
        "$env:TEMP\Exastealer"
    )

    if ($savedExe) {
        $exactTempCopy = Join-Path -Path $env:TEMP -ChildPath $savedExe
        Remove-Or-Quarantine -Path $exactTempCopy -Reason "Exact launcher copy named by a validated .exename entry"
    }

    # Quarantine/delete the marker only after its contents were safely parsed.
    $knownPaths += "$env:TEMP\.exename"

    foreach ($path in $knownPaths) {
        Remove-Or-Quarantine -Path $path
    }

    Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter "ns*.tmp" -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $dir = $_.FullName
        $suspicious = @(
            (Join-Path $dir "emre.jar"),
            (Join-Path $dir "data.7z"),
            (Join-Path $dir "uac_bypass.exe"),
            (Join-Path $dir "InnerEvilSetup.exe")
        ) | Where-Object { Test-Path -LiteralPath $_ -ErrorAction SilentlyContinue }

        if (@($suspicious).Count -gt 0) {
            Remove-Or-Quarantine -Path $dir -Reason "NSIS temporary directory contains InnerEvil payload artifacts"
        }
    }
}

function Check-DiscordInjection {
    Write-Log "Checking Discord installations for known injected JavaScript..."
    $roots = @(
        "$env:LOCALAPPDATA\Discord",
        "$env:LOCALAPPDATA\DiscordCanary",
        "$env:LOCALAPPDATA\DiscordPTB",
        "$env:LOCALAPPDATA\DiscordDevelopment"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter "index.js" -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '(?i)discord_desktop_core' } |
            ForEach-Object {
                try {
                    $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction Stop
                    $markers = @(
                        $SuspiciousIp,
                        "/api/discord-injection/",
                        "remote-auth-gateway.discord.gg",
                        "api.braintreegateway.com/merchants/49pp2rp4phym7387",
                        "injection_debug.log"
                    )
                    $matched = $markers | Where-Object { $text -match [regex]::Escape($_) }
                    if ($matched) {
                        Write-Log "Discord injection detected: $($_.FullName) | markers: $($matched -join ', ')" "ERROR"
                        Save-FileCopy -Path $_.FullName -Label "discord_injected"
                        Remove-Or-Quarantine -Path $_.FullName -Reason "Confirmed Discord injection markers"
                    }
                } catch {
                    Write-Log "Could not inspect Discord file $($_.FullName): $($_.Exception.Message)" "WARN"
                }
            }
    }
}

function Restore-WallpaperSettingIfSuspicious {
    $desktopKey = "HKCU:\Control Panel\Desktop"
    try {
        $current = (Get-ItemProperty -Path $desktopKey -Name Wallpaper -ErrorAction Stop).Wallpaper
        if ($current -match '(?i)(\\emre\\|Exastealer|wallpaper\.(jpg|png|bmp)$)' -and (Test-Path -LiteralPath $current)) {
            Write-Log "Suspicious wallpaper path detected: $current" "WARN"
            Save-FileCopy -Path $current -Label "wallpaper"
            Remove-Or-Quarantine -Path $current -Reason "Potential ransomware wallpaper"
            Set-ItemProperty -Path $desktopKey -Name Wallpaper -Value "" -ErrorAction Stop
            & rundll32.exe user32.dll,UpdatePerUserSystemParameters | Out-Null
            Write-Log "Suspicious wallpaper registry value cleared" "OK"
        }
    } catch {
        Write-Log "Wallpaper check skipped or failed: $($_.Exception.Message)" "WARN"
    }
}

function Configure-NetworkBlocks {
    Write-Log "Configuring network blocks..."

    $rules = @(
        @{
            Name = "Block InnerEvil C2 IP outbound"
            Params = @{
                DisplayName = "Block InnerEvil C2 IP outbound"
                Direction = "Outbound"
                Action = "Block"
                RemoteAddress = $SuspiciousIp
                Profile = "Any"
            }
        },
        @{
            Name = "Block InnerEvil C2 port outbound"
            Params = @{
                DisplayName = "Block InnerEvil C2 port outbound"
                Direction = "Outbound"
                Action = "Block"
                Protocol = "TCP"
                RemoteAddress = $SuspiciousIp
                RemotePort = $SuspiciousPort
                Profile = "Any"
            }
        }
    )

    foreach ($rule in $rules) {
        try {
            Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            $firewallParams = $rule.Params
            New-NetFirewallRule @firewallParams -ErrorAction Stop | Out-Null
            Write-Log "Firewall rule created: $($rule.Name)" "OK"
        } catch {
            Write-Log "Firewall rule failed: $($rule.Name) | $($_.Exception.Message)" "ERROR"
        }
    }

    $hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
    try {
        Copy-Item -LiteralPath $hosts -Destination (Join-Path $BackupDir "hosts.before") -Force
        $content = Get-Content -LiteralPath $hosts -ErrorAction Stop
        $line = "0.0.0.0`t$SuspiciousDomain"
        if (-not ($content | Where-Object { $_ -match "^\s*(127\.0\.0\.1|0\.0\.0\.0)\s+$([regex]::Escape($SuspiciousDomain))(\s|$)" })) {
            Add-Content -LiteralPath $hosts -Value "`r`n# InnerEvil remediation`r`n$line" -Encoding ASCII
            Write-Log "Hosts entry added for $SuspiciousDomain" "OK"
        } else {
            Write-Log "Hosts entry already exists for $SuspiciousDomain"
        }
    } catch {
        Write-Log "Could not update hosts file: $($_.Exception.Message)" "ERROR"
    }

    ipconfig /flushdns | Out-Null
    Write-Log "DNS cache flushed" "OK"
}

function Run-MicrosoftDefenderScan {
    try {
        $service = Get-Service -Name WinDefend -ErrorAction Stop
        if ($service.Status -ne "Running") {
            Write-Log "Microsoft Defender service is not running (status: $($service.Status)). Scan skipped." "WARN"
            return
        }

        Get-Command Start-MpScan -ErrorAction Stop | Out-Null
        Write-Log "Starting Microsoft Defender quick scan..."
        Start-MpScan -ScanType QuickScan -ErrorAction Stop
        Write-Log "Microsoft Defender quick scan completed successfully" "OK"
    } catch {
        Write-Log "Microsoft Defender scan failed or is unavailable: $($_.Exception.Message)" "WARN"
    }
}

function Write-Report {
    $findings = @()
    $findings += "InnerEvil / Exastealer remediation report"
    $findings += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $findings += "Mode: $Mode"
    $findings += "Log: $LogPath"
    $findings += "Quarantine: $QuarantineDir"
    $findings += ""
    $findings += "IMPORTANT:"
    $findings += "- This tool cannot undo stolen passwords, cookies, Discord tokens, 2FA backup codes, wallet seeds, or payment data."
    $findings += "- Change credentials and revoke sessions from a different, trusted device."
    $findings += "- Reinstall Discord after deleting its remaining installation folders if injection was detected."
    $findings += "- For high assurance, reinstall Windows from trusted media."
    $findings += ""
    $findings += "Known C2 blocked: http://$SuspiciousIp`:$SuspiciousPort"
    $findings += "Legacy/domain IOC blocked: $SuspiciousDomain"
    Set-Content -LiteralPath $ReportPath -Value $findings -Encoding UTF8
    Write-Log "Report written: $ReportPath" "OK"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " InnerEvil / Exastealer Remediation Tool" -ForegroundColor Cyan
Write-Host " Mode: $Mode" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Administrator)) {
    Write-Host "Run this tool as Administrator." -ForegroundColor Red
    exit 1
}

if (-not $NoPrompt) {
    Write-Host "This tool will stop suspicious processes, modify persistence," -ForegroundColor Yellow
    Write-Host "quarantine/delete known artifacts, and add firewall/hosts blocks." -ForegroundColor Yellow
    $answer = Read-Host "Type CLEAN to continue"
    if ($answer -cne "CLEAN") {
        Write-Host "Cancelled."
        exit 0
    }
}

Write-Log "Remediation started. Mode=$Mode"
Stop-SuspiciousProcesses
Remove-StartupArtifacts
Remove-SuspiciousRunValues
Remove-SuspiciousScheduledTasks
Remove-SuspiciousServices

Backup-And-RemoveRegistryKey `
    -PsPath "HKCU:\SOFTWARE\$Guid" `
    -RegExePath "HKCU\SOFTWARE\$Guid"

Backup-And-RemoveRegistryKey `
    -PsPath "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$Guid" `
    -RegExePath "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$Guid"

Check-DiscordInjection
Restore-WallpaperSettingIfSuspicious
Remove-KnownFiles
Configure-NetworkBlocks
Run-MicrosoftDefenderScan
Write-Report

Write-Host ""
Write-Host "Remediation finished." -ForegroundColor Green
Write-Host "Review: $ReportPath" -ForegroundColor Cyan
Write-Host "Detailed log: $LogPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Do not treat cleanup as proof that stolen credentials are safe." -ForegroundColor Yellow
