[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SptInstallRoot,
    [ValidateSet("Debug", "Release")][string]$Configuration = "Debug",
    [string]$AnalysisRoot = "D:\SPT_4_1_ModDev_TEMP",
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot "Build.ps1") -SptInstallRoot $SptInstallRoot -Configuration $Configuration
}

$Source = Join-Path $RepoRoot "artifacts\package\SPT_Runtime\user\mods\Astar.DatabaseBypass"
$Destination = Join-Path $SptInstallRoot "SPT_Runtime\user\mods\Astar.DatabaseBypass"

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "缺少构建包：$Source"
}

if (Test-Path -LiteralPath $Destination) {
    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Backup = Join-Path $AnalysisRoot "evidence\server-mod-install-backup-$Stamp"
    New-Item -ItemType Directory -Path $Backup -Force | Out-Null
    Copy-Item -LiteralPath $Destination -Destination $Backup -Recurse -Force
    Remove-Item -LiteralPath $Destination -Recurse -Force
}

New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force

Write-Host "已安装开发版：$Destination" -ForegroundColor Green
