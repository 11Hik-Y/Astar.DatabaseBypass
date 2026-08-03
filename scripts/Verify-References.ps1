[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SptInstallRoot,
    [string]$AnalysisRoot = "D:\SPT_4_1_ModDev_TEMP"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ServerRoot = Join-Path $SptInstallRoot "SPT_Runtime"
$Required = @(
    "SPT.Server.dll",
    "SPTarkov.Server.Core.dll",
    "SPTarkov.Reflection.dll",
    "SPTarkov.Common.dll",
    "SPTarkov.DI.dll",
    "SemanticVersioning.dll",
    "0Harmony.dll"
)

$Rows = foreach ($Name in $Required) {
    $Path = Join-Path $ServerRoot $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "缺少服务端引用：$Path"
    }

    $Item = Get-Item -LiteralPath $Path
    [pscustomobject]@{
        Name = $Name
        Path = $Path
        Length = $Item.Length
        SHA256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        FileVersion = $Item.VersionInfo.FileVersion
        ProductVersion = $Item.VersionInfo.ProductVersion
    }
}

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutputRoot = Join-Path $AnalysisRoot "baseline-manifests\server-$Stamp"
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$Rows | Export-Csv -LiteralPath (Join-Path $OutputRoot "server-references.csv") -NoTypeInformation -Encoding utf8
$Rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot "server-references.json") -Encoding utf8NoBOM

$Rows | Format-Table Name, Length, FileVersion, SHA256 -AutoSize
Write-Host "`n服务端引用验证通过：$OutputRoot" -ForegroundColor Green
