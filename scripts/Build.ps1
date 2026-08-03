[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SptInstallRoot,
    [ValidateSet("Debug", "Release")][string]$Configuration = "Debug"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$RepoRoot = Split-Path $PSScriptRoot -Parent
$Project = Join-Path $RepoRoot "src\Astar.DatabaseBypass\Astar.DatabaseBypass.csproj"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw ".NET SDK 未安装或 dotnet 不在 PATH。"
}

$Sdks = @(& dotnet --list-sdks)
if (-not ($Sdks -match '^10\.')) {
    throw "未检测到 .NET 10 SDK。SPT 4.1.0 服务端目标框架为 net10.0。"
}

& dotnet build $Project `
    --configuration $Configuration `
    -p:SptInstallRoot="$SptInstallRoot" `
    --nologo

$BuiltDll = Join-Path $RepoRoot "artifacts\bin\$Configuration\Astar.DatabaseBypass.dll"
if (-not (Test-Path -LiteralPath $BuiltDll -PathType Leaf)) {
    throw "构建结束但未找到 DLL：$BuiltDll"
}

$PackageRoot = Join-Path $RepoRoot "artifacts\package\SPT_Runtime\user\mods\Astar.DatabaseBypass"
if (Test-Path -LiteralPath $PackageRoot) {
    Remove-Item -LiteralPath $PackageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null
Copy-Item -LiteralPath $BuiltDll -Destination $PackageRoot -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "README.md") -Destination $PackageRoot -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "LICENSE.md") -Destination $PackageRoot -Force

$Hash = Get-FileHash -LiteralPath (Join-Path $PackageRoot "Astar.DatabaseBypass.dll") -Algorithm SHA256
Write-Host "`n构建成功。" -ForegroundColor Green
Write-Host "DLL：$($Hash.Path)"
Write-Host "SHA-256：$($Hash.Hash)"
