[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SptInstallRoot,
    [string]$Version = "0.1.0",
    [string]$VirusTotalProxy = "http://127.0.0.1:10808",
    [switch]$SkipVirusTotal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMilliseconds = 700
    )

    $Client = [System.Net.Sockets.TcpClient]::new()

    try {
        $Async = $Client.BeginConnect(
            $HostName,
            $Port,
            $null,
            $null
        )

        if (-not $Async.AsyncWaitHandle.WaitOne(
            $TimeoutMilliseconds,
            $false
        )) {
            return $false
        }

        $Client.EndConnect($Async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $Client.Dispose()
    }
}

function Get-EnvironmentSecret {
    param([Parameter(Mandatory)][string]$Name)

    foreach ($Scope in @("Process", "User", "Machine")) {
        $Value = [Environment]::GetEnvironmentVariable(
            $Name,
            $Scope
        )

        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            return $Value.Trim()
        }
    }

    return $null
}

function Get-PropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [object]$Default = 0
    )

    if ($null -eq $Object) {
        return $Default
    }

    $Property = $Object.PSObject.Properties[$Name]

    if (
        $null -eq $Property -or
        $null -eq $Property.Value
    ) {
        return $Default
    }

    return $Property.Value
}

function Invoke-VirusTotalScan {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$ApiKey,

        [AllowNull()]
        [string]$ProxyUri,

        [ValidateRange(15, 300)]
        [int]$InitialPollSeconds = 30,

        [ValidateRange(5, 120)]
        [int]$MaxWaitMinutes = 25
    )

    function Get-HttpStatusCode {
        param(
            [Parameter(Mandatory)]
            [object]$ErrorRecord
        )

        $Response = $ErrorRecord.Exception.Response

        if ($null -eq $Response) {
            return $null
        }

        try {
            return [int]$Response.StatusCode
        }
        catch {
            return $null
        }
    }

    function Get-StatsLine {
        param(
            [AllowNull()]
            [object]$Stats
        )

        return (
            "malicious={0}; suspicious={1}; harmless={2}; " +
            "undetected={3}; timeout={4}; failure={5}; " +
            "type-unsupported={6}"
        ) -f
            (
                Get-PropertyValue `
                    -Object $Stats `
                    -Name "malicious"
            ),
            (
                Get-PropertyValue `
                    -Object $Stats `
                    -Name "suspicious"
            ),
            (
                Get-PropertyValue `
                    -Object $Stats `
                    -Name "harmless"
            ),
            (
                Get-PropertyValue `
                    -Object $Stats `
                    -Name "undetected"
            ),
            (
                Get-PropertyValue `
                    -Object $Stats `
                    -Name "timeout"
            ),
            (
                Get-PropertyValue `
                    -Object $Stats `
                    -Name "failure"
            ),
            (
                Get-PropertyValue `
                    -Object $Stats `
                    -Name "type-unsupported"
            )
    }

    $File = Get-Item -LiteralPath $FilePath

    $Hash = (
        Get-FileHash `
            -LiteralPath $File.FullName `
            -Algorithm SHA256
    ).Hash

    $ReportUrl = (
        "https://www.virustotal.com/gui/file/" +
        $Hash +
        "/detection"
    )

    $WebCommon = @{
        Headers = @{
            "x-apikey" = $ApiKey
        }
        TimeoutSec = 120
        ErrorAction = "Stop"
    }

    if (-not [string]::IsNullOrWhiteSpace($ProxyUri)) {
        $WebCommon.Proxy = $ProxyUri
    }

    # 优先按 SHA-256 查询已有报告。
    # 相同构建产物重复发布时不再上传和轮询。
    try {
        $Existing = Invoke-RestMethod @WebCommon `
            -Method Get `
            -Uri (
                "https://www.virustotal.com/api/v3/files/" +
                $Hash
            )

        $ExistingStats = (
            $Existing.data.attributes.last_analysis_stats
        )

        if ($null -ne $ExistingStats) {
            Write-Host (
                "VirusTotal 已存在相同 SHA-256 的报告，" +
                "跳过重复上传和 analysis 轮询。"
            ) -ForegroundColor Green

            return [pscustomobject]@{
                FileName = $File.Name
                SHA256 = $Hash
                AnalysisId = "existing-report"
                Status = "completed"
                Statistics = (
                    Get-StatsLine -Stats $ExistingStats
                )
                Report = $ReportUrl
            }
        }
    }
    catch {
        $StatusCode = Get-HttpStatusCode `
            -ErrorRecord $_

        if ($StatusCode -eq 404) {
            Write-Host (
                "VirusTotal 尚无该 SHA-256 报告，" +
                "将提交新扫描。"
            )
        }
        elseif ($StatusCode -eq 429) {
            Write-Host (
                "VirusTotal 预查询触发限流，" +
                "等待 180 秒后再提交。"
            ) -ForegroundColor Yellow

            Start-Sleep -Seconds 180
        }
        else {
            throw
        }
    }

    $UploadUri = (
        "https://www.virustotal.com/api/v3/files"
    )

    if ($File.Length -gt 32MB) {
        $UploadUrlResponse = Invoke-RestMethod @WebCommon `
            -Method Get `
            -Uri (
                "https://www.virustotal.com/api/v3/" +
                "files/upload_url"
            )

        $UploadUri = [string]$UploadUrlResponse.data

        if ([string]::IsNullOrWhiteSpace($UploadUri)) {
            throw "VirusTotal 未返回大文件上传 URL。"
        }
    }

    $UploadResponse = Invoke-RestMethod @WebCommon `
        -Method Post `
        -Uri $UploadUri `
        -Form @{
            file = $File
        }

    $AnalysisId = [string]$UploadResponse.data.id

    if ([string]::IsNullOrWhiteSpace($AnalysisId)) {
        throw "VirusTotal 上传响应缺少 analysis id。"
    }

    Write-Host "VirusTotal analysis id：$AnalysisId"

    # 本次实际扫描约在 2～8 分钟完成。
    # 使用逐级退避，避免每 20 秒无效查询：
    # 30 → 60 → 90 → 120 → 180 → 300 秒，
    # 后续保持 300 秒。
    $QueuedDelays = @(
        30,
        60,
        90,
        120,
        180,
        300
    )

    $QueuedIndex = 0
    $NextDelay = [Math]::Max(
        $InitialPollSeconds,
        $QueuedDelays[0]
    )

    $Deadline = (Get-Date).AddMinutes(
        $MaxWaitMinutes
    )

    $Analysis = $null
    $Status = "queued"
    $PollCount = 0

    while ((Get-Date) -lt $Deadline) {
        Write-Host (
            "等待 $NextDelay 秒后查询 VirusTotal 状态..."
        ) -ForegroundColor DarkGray

        Start-Sleep -Seconds $NextDelay

        try {
            $Analysis = Invoke-RestMethod @WebCommon `
                -Method Get `
                -Uri (
                    "https://www.virustotal.com/api/v3/" +
                    "analyses/$AnalysisId"
                )
        }
        catch {
            $StatusCode = Get-HttpStatusCode `
                -ErrorRecord $_

            if ($StatusCode -eq 429) {
                $NextDelay = 300

                Write-Host (
                    "VirusTotal 返回 429，" +
                    "退避 300 秒后重试。"
                ) -ForegroundColor Yellow

                continue
            }

            throw
        }

        $PollCount++
        $Status = [string](
            $Analysis.data.attributes.status
        )

        Write-Host (
            "VirusTotal 状态：$Status " +
            "（第 $PollCount 次查询）"
        )

        if ($Status -eq "completed") {
            break
        }

        if ($Status -eq "in-progress") {
            # 已进入分析阶段后，用 45 秒平衡速度和配额。
            $NextDelay = 45
            continue
        }

        if ($Status -eq "queued") {
            if (
                $QueuedIndex -lt
                ($QueuedDelays.Count - 1)
            ) {
                $QueuedIndex++
            }

            $NextDelay = $QueuedDelays[$QueuedIndex]
            continue
        }

        # 未知状态保守退避。
        $NextDelay = 300
    }

    $StatsLine = ""

    if ($null -ne $Analysis) {
        $StatsLine = (
            Get-StatsLine `
                -Stats $Analysis.data.attributes.stats
        )
    }

    if ($Status -ne "completed") {
        Write-Host (
            "VirusTotal 在 $MaxWaitMinutes 分钟内未完成；" +
            "已保留 analysis id 和报告链接。"
        ) -ForegroundColor Yellow
    }

    return [pscustomobject]@{
        FileName = $File.Name
        SHA256 = $Hash
        AnalysisId = $AnalysisId
        Status = $Status
        Statistics = $StatsLine
        Report = $ReportUrl
    }
}
function Convert-VirusTotalResultToText {
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$TargetDescription
    )

    return @(
        "Target: $TargetDescription",
        "File: $($Result.FileName)",
        "SHA-256: $($Result.SHA256)",
        "Analysis ID: $($Result.AnalysisId)",
        "Status: $($Result.Status)",
        "Statistics: $($Result.Statistics)",
        "Report: $($Result.Report)"
    ) -join [Environment]::NewLine
}

$RepoRoot = Split-Path $PSScriptRoot -Parent
$SptInstallRoot = [System.IO.Path]::GetFullPath(
    $SptInstallRoot
)

$BuildScript = Join-Path $PSScriptRoot "Build.ps1"
$PackageStage = Join-Path $RepoRoot "artifacts\package"
$ModStage = Join-Path (
    $PackageStage
) "SPT_Runtime\user\mods\Astar.DatabaseBypass"

$ReleaseRoot = Join-Path $RepoRoot "release"
$PackageName = (
    "Astar.DatabaseBypass_v${Version}_SPT-4.1.x.zip"
)
$ZipPath = Join-Path $ReleaseRoot $PackageName

if (-not (Test-Path -LiteralPath $BuildScript -PathType Leaf)) {
    throw "未找到构建脚本：$BuildScript"
}

$ApiKey = $null
$ProxyUri = $null

if (-not $SkipVirusTotal) {
    $ApiKey = Get-EnvironmentSecret -Name "VIRUSTOTAL_API_KEY"

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw (
            "未从 Process、User 或 Machine 环境变量读取到 " +
            "VIRUSTOTAL_API_KEY。"
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($VirusTotalProxy)) {
        try {
            $ParsedProxy = [uri]$VirusTotalProxy

            if (
                Test-TcpPort `
                    -HostName $ParsedProxy.Host `
                    -Port $ParsedProxy.Port
            ) {
                $ProxyUri = $VirusTotalProxy
                Write-Host (
                    "VirusTotal 请求使用代理：$ProxyUri"
                )
            }
            else {
                Write-Host (
                    "本地代理端口不可用，将尝试直连 VirusTotal。"
                ) -ForegroundColor Yellow
            }
        }
        catch {
            throw (
                "VirusTotalProxy 不是有效 URI：" +
                $VirusTotalProxy
            )
        }
    }
}

Write-Host (
    "`n=== 1. Release 构建与最小目录暂存 ==="
) -ForegroundColor Cyan

& $BuildScript `
    -SptInstallRoot $SptInstallRoot `
    -Configuration Release

$DllPath = Join-Path $ModStage "Astar.DatabaseBypass.dll"

if (-not (Test-Path -LiteralPath $DllPath -PathType Leaf)) {
    throw "构建暂存目录缺少 DLL：$DllPath"
}

Write-Host (
    "`n=== 2. Generate disclaimer and DLL scan information ==="
) -ForegroundColor Cyan

$DisclaimerPath = Join-Path $ModStage "DISCLAIMER.txt"
$DllVirusTotalPath = Join-Path $ModStage "VirusTotal_DLL.txt"
$DisclaimerSource = Join-Path $RepoRoot "DISCLAIMER.md"

if (-not (
    Test-Path `
        -LiteralPath $DisclaimerSource `
        -PathType Leaf
)) {
    throw "Missing repository disclaimer: $DisclaimerSource"
}

Copy-Item `
    -LiteralPath $DisclaimerSource `
    -Destination $DisclaimerPath `
    -Force
if (-not $SkipVirusTotal) {
    Write-Host "上传 Release DLL 到 VirusTotal。"

    $DllVt = Invoke-VirusTotalScan `
        -FilePath $DllPath `
        -ApiKey $ApiKey `
        -ProxyUri $ProxyUri

    $DllVtText = Convert-VirusTotalResultToText `
        -Result $DllVt `
        -TargetDescription (
            "Astar.DatabaseBypass Release DLL"
        )

    Write-Utf8NoBom `
        -Path $DllVirusTotalPath `
        -Content ($DllVtText + [Environment]::NewLine)
}
else {
    $DllHash = (
        Get-FileHash `
            -LiteralPath $DllPath `
            -Algorithm SHA256
    ).Hash

    $SkippedText = @(
        "Target: Astar.DatabaseBypass Release DLL",
        "File: Astar.DatabaseBypass.dll",
        "SHA-256: $DllHash",
        "Status: SKIPPED",
        (
            "Report after manual upload: " +
            "https://www.virustotal.com/gui/file/" +
            "$DllHash/detection"
        )
    ) -join [Environment]::NewLine

    Write-Utf8NoBom `
        -Path $DllVirusTotalPath `
        -Content ($SkippedText + [Environment]::NewLine)
}

$ExpectedStageNames = @(
    "Astar.DatabaseBypass.dll",
    "VirusTotal_DLL.txt",
    "DISCLAIMER.txt"
) | Sort-Object

$ActualStageNames = @(
    Get-ChildItem -LiteralPath $ModStage -File -Recurse |
        Select-Object -ExpandProperty Name
) | Sort-Object

$StageDifference = @(
    Compare-Object `
        -ReferenceObject $ExpectedStageNames `
        -DifferenceObject $ActualStageNames
)

if ($StageDifference.Count -gt 0) {
    $StageDifference |
        Format-Table -AutoSize |
        Out-Host

    throw (
        "The package stage must contain only the DLL, DISCLAIMER.txt, and " +
        "VirusTotal DLL 检测信息。"
    )
}

Write-Host (
    "`n=== 3. 重建最终 ZIP ==="
) -ForegroundColor Cyan

if (Test-Path -LiteralPath $ReleaseRoot -PathType Container) {
    Remove-Item -LiteralPath $ReleaseRoot -Recurse -Force
}

New-Item `
    -ItemType Directory `
    -Path $ReleaseRoot `
    -Force |
    Out-Null

Add-Type `
    -AssemblyName System.IO.Compression.FileSystem `
    -ErrorAction SilentlyContinue

[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $PackageStage,
    $ZipPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    throw "ZIP 创建失败：$ZipPath"
}

Write-Host "ZIP：$ZipPath" -ForegroundColor Green

Write-Host (
    "`n=== 4. ZIP 解压回环与严格白名单验证 ==="
) -ForegroundColor Cyan

$RoundTripRoot = Join-Path (
    [System.IO.Path]::GetTempPath()
) (
    "Astar.DatabaseBypass-minimal-release-" +
    [guid]::NewGuid().ToString("N")
)

New-Item `
    -ItemType Directory `
    -Path $RoundTripRoot `
    -Force |
    Out-Null

try {
    Expand-Archive `
        -LiteralPath $ZipPath `
        -DestinationPath $RoundTripRoot `
        -Force

    $ExpectedRelativeFiles = @(
        (
            "SPT_Runtime/user/mods/Astar.DatabaseBypass/" +
            "Astar.DatabaseBypass.dll"
        ),
        (
            "SPT_Runtime/user/mods/Astar.DatabaseBypass/" +
            "VirusTotal_DLL.txt"
        ),
        (
            "SPT_Runtime/user/mods/Astar.DatabaseBypass/" +
            "DISCLAIMER.txt"
        )
    ) | Sort-Object

    $ActualRelativeFiles = @(
        Get-ChildItem `
            -LiteralPath $RoundTripRoot `
            -File `
            -Recurse |
            ForEach-Object {
                [System.IO.Path]::GetRelativePath(
                    $RoundTripRoot,
                    $_.FullName
                ).Replace("\", "/")
            }
    ) | Sort-Object

    $Difference = @(
        Compare-Object `
            -ReferenceObject $ExpectedRelativeFiles `
            -DifferenceObject $ActualRelativeFiles
    )

    if ($Difference.Count -gt 0) {
        $Difference |
            Format-Table -AutoSize |
            Out-Host

        throw "ZIP 内容严格白名单验证失败。"
    }

    $ExtractedDll = Join-Path (
        $RoundTripRoot
    ) (
        "SPT_Runtime\user\mods\Astar.DatabaseBypass\" +
        "Astar.DatabaseBypass.dll"
    )

    $StageDllHash = (
        Get-FileHash `
            -LiteralPath $DllPath `
            -Algorithm SHA256
    ).Hash

    $ExtractedDllHash = (
        Get-FileHash `
            -LiteralPath $ExtractedDll `
            -Algorithm SHA256
    ).Hash

    if ($StageDllHash -ne $ExtractedDllHash) {
        throw "ZIP 回环后的 DLL Hash 不一致。"
    }
}
finally {
    if (
        Test-Path `
            -LiteralPath $RoundTripRoot `
            -PathType Container
    ) {
        Remove-Item `
            -LiteralPath $RoundTripRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

Write-Host (
    "The ZIP contains only the DLL, DISCLAIMER.txt, and the DLL scan record. Round-trip validation passed."
) -ForegroundColor Green

Write-Host (
    "`n=== 5. 生成最终 SHA-256 ==="
) -ForegroundColor Cyan

$ZipHash = (
    Get-FileHash `
        -LiteralPath $ZipPath `
        -Algorithm SHA256
).Hash

$DllHash = (
    Get-FileHash `
        -LiteralPath $DllPath `
        -Algorithm SHA256
).Hash

$ShaPath = Join-Path $ReleaseRoot "SHA256.txt"

$ShaContent = @(
    "$ZipHash  $PackageName",
    "$DllHash  Astar.DatabaseBypass.dll"
) -join [Environment]::NewLine

Write-Utf8NoBom `
    -Path $ShaPath `
    -Content ($ShaContent + [Environment]::NewLine)

Write-Host "ZIP SHA-256：$ZipHash"
Write-Host "DLL SHA-256：$DllHash"

$ZipVirusTotalPath = Join-Path (
    $ReleaseRoot
) "VirusTotal_ZIP.txt"

Write-Host (
    "`n=== 6. 检测最终 ZIP（结果只放在包外） ==="
) -ForegroundColor Cyan

if (-not $SkipVirusTotal) {
    $ZipVt = Invoke-VirusTotalScan `
        -FilePath $ZipPath `
        -ApiKey $ApiKey `
        -ProxyUri $ProxyUri

    $ZipVtText = Convert-VirusTotalResultToText `
        -Result $ZipVt `
        -TargetDescription (
            "Final distributable ZIP"
        )

    Write-Utf8NoBom `
        -Path $ZipVirusTotalPath `
        -Content ($ZipVtText + [Environment]::NewLine)
}
else {
    $SkippedZipText = @(
        "Target: Final distributable ZIP",
        "File: $PackageName",
        "SHA-256: $ZipHash",
        "Status: SKIPPED",
        (
            "Report after manual upload: " +
            "https://www.virustotal.com/gui/file/" +
            "$ZipHash/detection"
        )
    ) -join [Environment]::NewLine

    Write-Utf8NoBom `
        -Path $ZipVirusTotalPath `
        -Content ($SkippedZipText + [Environment]::NewLine)
}

$ExpectedReleaseFiles = @(
    $PackageName,
    "SHA256.txt",
    "VirusTotal_ZIP.txt"
) | Sort-Object

$ActualReleaseFiles = @(
    Get-ChildItem -LiteralPath $ReleaseRoot -File |
        Select-Object -ExpandProperty Name
) | Sort-Object

$ReleaseDifference = @(
    Compare-Object `
        -ReferenceObject $ExpectedReleaseFiles `
        -DifferenceObject $ActualReleaseFiles
)

if ($ReleaseDifference.Count -gt 0) {
    $ReleaseDifference |
        Format-Table -AutoSize |
        Out-Host

    throw "release 目录存在非预期文件。"
}

Write-Host (
    "`n=== 最小正式发布产物 ==="
) -ForegroundColor Green

Get-ChildItem -LiteralPath $ReleaseRoot -File |
    Sort-Object Name |
    Select-Object Name, Length, LastWriteTime |
    Format-Table -AutoSize |
    Out-Host

Write-Host "最终 ZIP：$ZipPath" -ForegroundColor Green
Write-Host "ZIP SHA-256：$ZipHash" -ForegroundColor Green
Write-Host (
    "ZIP VirusTotal 记录：$ZipVirusTotalPath"
) -ForegroundColor Green