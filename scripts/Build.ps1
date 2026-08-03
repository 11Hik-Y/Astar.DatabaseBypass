[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SptInstallRoot,
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$RepoRoot = Split-Path $PSScriptRoot -Parent
$Project = Join-Path $RepoRoot "src\Astar.DatabaseBypass\Astar.DatabaseBypass.csproj"
$SptInstallRoot = [System.IO.Path]::GetFullPath($SptInstallRoot)

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw ".NET SDK 未安装或 dotnet 不在 PATH。"
}

$Sdks = @(& dotnet --list-sdks)
if (-not ($Sdks -match '^10\.')) {
    throw "未检测到 .NET 10 SDK。SPT 4.1.x 服务端目标框架为 net10.0。"
}

$BuildOutput = Join-Path $RepoRoot "artifacts\bin\$Configuration"
if (Test-Path -LiteralPath $BuildOutput -PathType Container) {
    Remove-Item -LiteralPath $BuildOutput -Recurse -Force
}

& dotnet build $Project `
    --configuration $Configuration `
    -p:SptInstallRoot="$SptInstallRoot" `
    --nologo

$BuiltDll = Join-Path $BuildOutput "Astar.DatabaseBypass.dll"
if (-not (Test-Path -LiteralPath $BuiltDll -PathType Leaf)) {
    throw "构建结束但未找到 DLL：$BuiltDll"
}

$PackageStage = Join-Path $RepoRoot "artifacts\package"
$ModStage = Join-Path $PackageStage "SPT_Runtime\user\mods\Astar.DatabaseBypass"

if (Test-Path -LiteralPath $PackageStage -PathType Container) {
    Remove-Item -LiteralPath $PackageStage -Recurse -Force
}

New-Item -ItemType Directory -Path $ModStage -Force | Out-Null
Copy-Item -LiteralPath $BuiltDll -Destination $ModStage -Force

$StageFiles = @(
    Get-ChildItem -LiteralPath $ModStage -File -Recurse
)

if (
    $StageFiles.Count -ne 1 -or
    $StageFiles[0].Name -ne "Astar.DatabaseBypass.dll"
) {
    throw "构建暂存目录必须只包含 Astar.DatabaseBypass.dll。"
}

$DllHash = (
    Get-FileHash `
        -LiteralPath (Join-Path $ModStage "Astar.DatabaseBypass.dll") `
        -Algorithm SHA256
).Hash

Write-Host "`n构建与最小安装目录暂存成功。" -ForegroundColor Green
Write-Host "Configuration : $Configuration"
Write-Host "Package stage : $PackageStage"
Write-Host "DLL SHA-256   : $DllHash"