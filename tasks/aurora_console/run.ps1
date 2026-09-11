#requires -Version 7.4
[CmdletBinding()]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$start = Get-Date
$stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
foreach ($folder in 'logs','reports','artifacts','artifacts/bin','backups') {
    New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot $folder) | Out-Null
}
$log = Join-Path $PSScriptRoot "logs/task_$stamp.log"
$report = @{TaskName='aurora_console'; StartTime=$start.ToString('o'); Hostname=$env:COMPUTERNAME; TriggeredBy=$env:USERNAME; Status='RUNNING'; DryRun=[bool]$DryRun; FilesChanged=0; Downloads=0}
$changed = $false
function Write-Log([string]$Message) {
    $line="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] $Message"
    Write-Host $line
    Add-Content $log $line
}
function Get-VerifiedAsset([string]$Url,[string]$Checksums,[string]$Destination) {
    $name = Split-Path $Url -Leaf
    $sumFile = Join-Path $PSScriptRoot "artifacts/$name.checksums.txt"
    Invoke-WebRequest $Checksums -OutFile $sumFile
    $line = Get-Content $sumFile | Where-Object { $_ -match [regex]::Escape($name) + '$' } | Select-Object -First 1
    if (-not $line -or $line -notmatch '([A-Fa-f0-9]{64})') { throw "Checksum missing: $name" }
    $expected = $Matches[1]
    if (-not (Test-Path $Destination) -or (Get-FileHash $Destination).Hash -ne $expected) {
        Invoke-WebRequest $Url -OutFile $Destination
        $report.Downloads++
    }
    if ((Get-FileHash $Destination).Hash -ne $expected) { throw "Checksum mismatch: $name" }
}
try {
    Write-Log '[Step 1/5] Validate configuration and existing Windows Terminal'
    $config = Get-Content (Join-Path $PSScriptRoot 'config/settings.json') -Raw | ConvertFrom-Json
    $target = Join-Path $env:LOCALAPPDATA 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
    $terminal = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json -AsHashtable
    $pwsh = Join-Path $PSScriptRoot 'artifacts/powershell/pwsh.exe'
    $posh = Join-Path $PSScriptRoot 'artifacts/bin/oh-my-posh.exe'
    if ($DryRun) {
        Write-Log '[Step 2/5] Would download and verify portable PowerShell and Oh My Posh'
        Write-Log '[Step 3/5] Would preserve original Terminal settings'
        Write-Log '[Step 4/5] Would add Aurora profile, theme and default profile'
        Write-Log '[Step 5/5] Simulation complete; no user configuration changed'
        $report.Status='DRY_RUN'
        return
    }
    Write-Log '[Step 2/5] Download and verify portable tools from official releases'
    $psBase="https://github.com/PowerShell/PowerShell/releases/download/v$($config.powershellVersion)"
    $zip=Join-Path $PSScriptRoot 'artifacts/powershell.zip'
    if (-not (Test-Path $pwsh)) {
        Get-VerifiedAsset "$psBase/PowerShell-$($config.powershellVersion)-win-x64.zip" "$psBase/hashes.sha256" $zip
        Expand-Archive -LiteralPath $zip -DestinationPath (Split-Path $pwsh) -Force
    }
    $ompBase="https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v$($config.poshVersion)"
    Get-VerifiedAsset "$ompBase/posh-windows-amd64.exe" "$ompBase/checksums.txt" $posh
    $report.PowerShell=(& $pwsh -NoProfile -Version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'PowerShell verification failed' }
    $report.OhMyPosh=(& $posh version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Oh My Posh verification failed' }
    Write-Log '[Step 3/5] Register readable Nerd Font and preserve Terminal settings'
    & (Join-Path $PSScriptRoot 'font.ps1')
    $manifestPath=Join-Path $PSScriptRoot 'backups/manifest.json'
    if (-not (Test-Path $manifestPath)) {
        Copy-Item -LiteralPath $target -Destination (Join-Path $PSScriptRoot 'backups/settings.original.json')
        @{Target=$target; Hash=(Get-FileHash $target).Hash} | ConvertTo-Json | Set-Content $manifestPath
    }
    # Every execution has its own immediate snapshot for failure recovery.
    $snapshot=Join-Path $PSScriptRoot "backups/settings_$stamp.json"
    Copy-Item -LiteralPath $target -Destination $snapshot
    Write-Log '[Step 4/5] Apply Aurora colors, spacing and dedicated PowerShell profile'
    $scheme=@{name='Aurora'; background='#000000'; foreground='#39FF14'; cursorColor='#00FFFF'; selectionBackground='#343434'; black='#000000'; red='#FF5050'; green='#39FF14'; yellow='#FFFF00'; blue='#00BFFF'; purple='#FF5FFF'; cyan='#00FFFF'; white='#EEEEEE'; brightBlack='#A0A0A0'; brightRed='#FF7070'; brightGreen='#69FF47'; brightYellow='#FFFF60'; brightBlue='#60DFFF'; brightPurple='#FF8FFF'; brightCyan='#80FFFF'; brightWhite='#FFFFFF'}
    $terminal.schemes=@($terminal.schemes | Where-Object name -ne 'Aurora') + @($scheme)
    $startup=Join-Path $PSScriptRoot 'config/startup.ps1'
    $profile=@{guid=$config.guid; name=$config.name; hidden=$false; commandline=('"{0}" -NoLogo -NoExit -File "{1}"' -f $pwsh,$startup); startingDirectory='%USERPROFILE%'; colorScheme='Aurora'; font=@{face=$config.font; size=$config.fontSize}; padding='12'; opacity=100; useAcrylic=$false; cursorShape='bar'; historySize=20000}
    $profile.font.weight='medium'
    $profile.antialiasingMode='cleartype'
    $terminal.profiles.list=@($terminal.profiles.list | Where-Object guid -ne $config.guid) + @($profile)
    $terminal.defaultProfile=$config.guid
    $terminal.theme='dark'
    $candidate=Join-Path $PSScriptRoot 'artifacts/settings.applied.json'
    $terminal | ConvertTo-Json -Depth 100 | Set-Content $candidate -Encoding utf8
    Get-Content $candidate -Raw | ConvertFrom-Json | Out-Null
    $changed=$true
    Copy-Item -LiteralPath $candidate -Destination $target -Force
    $report.FilesChanged=1
    Write-Log '[Step 5/5] Verify saved profile and prompt initialization'
    $saved=Get-Content $target -Raw | ConvertFrom-Json
    if ($saved.defaultProfile -ne $config.guid -or @($saved.profiles.list | Where-Object guid -eq $config.guid).Count -ne 1) { throw 'Terminal profile validation failed' }
    & $pwsh -NoProfile -File (Join-Path $PSScriptRoot 'verify.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Startup validation failed' }
    $report.Status='SUCCESS'
} catch {
    $report.Status='FAILED'; $report.Error=$_.Exception.Message
    Write-Log "Failure: $($_.Exception.Message)"
    if ($changed) {
        Copy-Item -LiteralPath $snapshot -Destination $target -Force
        $report.Status='ROLLED_BACK'
    }
    throw
} finally {
    $report.EndTime=(Get-Date).ToString('o')
    $report.DurationSeconds=[math]::Round(((Get-Date)-$start).TotalSeconds,2)
    $report | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $PSScriptRoot "reports/report_$stamp.json")
    "# Aurora Console`n`nEstado: $($report.Status)`nDuracion: $($report.DurationSeconds) segundos`nArchivos cambiados: $($report.FilesChanged)`nPowerShell: $($report.PowerShell)`nOh My Posh: $($report.OhMyPosh)" | Set-Content (Join-Path $PSScriptRoot "reports/report_$stamp.md")
    Write-Log "Finished: $($report.Status)"
}
