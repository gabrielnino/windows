$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'config/startup.ps1')
if (-not [Console]::IsOutputRedirected -and (Get-PSReadLineOption).PredictionSource -ne 'History') { throw 'Prediction missing' }
if (-not (Get-Command aurora-help)) { throw 'Help missing' }
$posh=Join-Path $PSScriptRoot 'artifacts/bin/oh-my-posh.exe'
$render=& $posh print primary --config (Join-Path $PSScriptRoot 'config/aurora.omp.json') --shell pwsh
if ($LASTEXITCODE -ne 0 -or -not $render -or $render -match 'CONFIG ERROR|INVALID CONFIG') { throw 'Prompt rendering failed' }
Write-Output "Verified PowerShell $($PSVersionTable.PSVersion), PSReadLine $((Get-Module PSReadLine).Version), prompt rendering. Redirected=$([Console]::IsOutputRedirected); Prediction=$((Get-PSReadLineOption).PredictionSource)."
