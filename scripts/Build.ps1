[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SptInstallRoot,
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$DotnetCommand = "dotnet"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$RepoRoot = Split-Path $PSScriptRoot -Parent
$Project = Join-Path $RepoRoot "src\Astar.DatabaseBypass\Astar.DatabaseBypass.csproj"
$SptInstallRoot = [System.IO.Path]::GetFullPath($SptInstallRoot)
$TargetFramework = "net10.0"
$SptServerRoot = Join-Path $SptInstallRoot "SPT_Runtime"
$SptServerDll = Join-Path $SptServerRoot "SPT.Server.dll"

if (-not (Get-Command $DotnetCommand -ErrorAction SilentlyContinue)) {
    throw ".NET SDK 未安装或指定的 dotnet 不可用：$DotnetCommand"
}

$Sdks = @(& $DotnetCommand --list-sdks)
if (-not ($Sdks -match '^10\.')) {
    throw "指定的 dotnet 未检测到 .NET 10 SDK。SPT 4.1.x 服务端目标框架为 net10.0。"
}

if (-not (Test-Path -LiteralPath $SptServerDll -PathType Leaf)) {
    throw "未找到 SPT 4.1.x 服务端：$SptServerDll"
}

$ServerAssemblyVersion = [Reflection.AssemblyName]::GetAssemblyName($SptServerDll).Version
if ($ServerAssemblyVersion.Major -ne 4 -or $ServerAssemblyVersion.Minor -ne 1) {
    throw "只支持 SPT 4.1.x；当前引用的 SPT.Server.dll 是 $ServerAssemblyVersion。"
}

$BuildOutput = Join-Path $RepoRoot "artifacts\bin\$Configuration"
if (Test-Path -LiteralPath $BuildOutput -PathType Container) {
    Remove-Item -LiteralPath $BuildOutput -Recurse -Force
}

& $DotnetCommand build $Project `
    --configuration $Configuration `
    -p:SptInstallRoot="$SptInstallRoot" `
    --nologo

if ($LASTEXITCODE -ne 0) {
    throw "dotnet build 失败，退出码：$LASTEXITCODE"
}

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

$StageFiles = @(Get-ChildItem -LiteralPath $ModStage -File -Recurse)
if ($StageFiles.Count -ne 1 -or $StageFiles[0].Name -ne "Astar.DatabaseBypass.dll") {
    throw "构建暂存目录必须只包含 Astar.DatabaseBypass.dll。"
}

$DllHash = (Get-FileHash -LiteralPath (Join-Path $ModStage "Astar.DatabaseBypass.dll") -Algorithm SHA256).Hash

Write-Host "`n构建与最小安装目录暂存成功。" -ForegroundColor Green
Write-Host "SPT target    : $ServerAssemblyVersion"
Write-Host "Framework     : $TargetFramework"
Write-Host "dotnet        : $DotnetCommand"
Write-Host "Configuration : $Configuration"
Write-Host "Package stage : $PackageStage"
Write-Host "DLL SHA-256   : $DllHash"
