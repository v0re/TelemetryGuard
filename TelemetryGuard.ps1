#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Gui', 'Status', 'Preview', 'Disable', 'Restore')]
    [string]$Mode = 'Gui',

    [switch]$NoElevation,

    [string[]]$OptionalProfiles = @(),

    [string]$ExpectedSourceHash = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AppName = 'TelemetryGuard'
$script:AppVersion = '1.2.0'
$script:CommonDataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
$script:StateRoot = Join-Path $script:CommonDataRoot $script:AppName
$script:BackupPath = Join-Path $script:StateRoot 'backup-v1.json'
$script:OptionalBackupPath = Join-Path $script:StateRoot 'resource-backup-v1.json'
$script:LogPath = Join-Path $script:StateRoot 'activity.log'
$script:DataCollectionPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
$script:CeipPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'
$script:AllowedRegistryIdentities = @(
    ('{0}|AllowTelemetry' -f $script:DataCollectionPolicyPath).ToLowerInvariant(),
    ('{0}|LimitDiagnosticLogCollection' -f $script:DataCollectionPolicyPath).ToLowerInvariant(),
    ('{0}|LimitDumpCollection' -f $script:DataCollectionPolicyPath).ToLowerInvariant(),
    ('{0}|CEIPEnable' -f $script:CeipPolicyPath).ToLowerInvariant()
)
$script:AllowedTaskIdentities = @(
    '\Microsoft\Windows\Application Experience\|Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\|Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\Customer Experience Improvement Program\|Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\|KernelCeipTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\|UsbCeip'
) | ForEach-Object { $_.ToLowerInvariant() }
$script:AllowedOptionalProfileIds = @(
    'search-indexing',
    'mixed-reality-link',
    'printing',
    'connected-devices',
    'location-maps',
    'xbox',
    'error-feedback',
    'compatibility-assistant',
    'store-install',
    'media-sharing',
    'mobile-hotspot',
    'webdav-client'
)
$script:AllowedOptionalServiceNames = @(
    'WSearch',
    'MixedRealityLinkSvc',
    'Spooler',
    'CDPSvc',
    'PhoneSvc',
    'lfsvc',
    'MapsBroker',
    'XblAuthManager',
    'XblGameSave',
    'XboxGipSvc',
    'XboxNetApiSvc',
    'WerSvc',
    'PcaSvc',
    'InstallService',
    'WMPNetworkSvc',
    'icssvc',
    'WebClient'
)
$script:AllowedOptionalTaskIdentities = @(
    '\Microsoft\Windows\Shell\|IndexerAutomaticMaintenance',
    '\Microsoft\Windows\Application Experience\|MareBackup',
    '\Microsoft\Windows\Maps\|MapsToastTask',
    '\Microsoft\Windows\Maps\|MapsUpdateTask',
    '\Microsoft\XblGameSave\|XblGameSaveTask',
    '\Microsoft\Windows\Feedback\Siuf\|DmClient',
    '\Microsoft\Windows\Feedback\Siuf\|DmClientOnScenarioDownload',
    '\Microsoft\Windows\Sustainability\|SustainabilityTelemetry',
    '\Microsoft\Windows\Windows Error Reporting\|QueueReporting'
) | ForEach-Object { $_.ToLowerInvariant() }

# Keep the exact source file read-only for this process lifetime. This prevents
# another same-user process from replacing it while the UAC prompt is open and
# before the elevated Windows PowerShell process reads it again.
if ([string]::IsNullOrWhiteSpace([string]$PSCommandPath)) {
    throw 'TelemetryGuard 必須從已儲存的 .ps1 檔案啟動。'
}
$script:LaunchSourceStream = $null
try {
    $script:LaunchSourceStream = [IO.File]::Open(
        $PSCommandPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    $launchHasher = [Security.Cryptography.SHA256]::Create()
    try {
        $script:LaunchSourceHash = (($launchHasher.ComputeHash($script:LaunchSourceStream) |
                    ForEach-Object { $_.ToString('X2') }) -join '')
        $script:LaunchSourceStream.Position = 0
    }
    finally {
        $launchHasher.Dispose()
    }
}
catch {
    if ($null -ne $script:LaunchSourceStream) {
        $script:LaunchSourceStream.Dispose()
    }
    throw ('無法鎖定並驗證程式來源；沒有執行任何系統變更：{0}' -f $_.Exception.Message)
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedSourceHash)) {
    if ($ExpectedSourceHash -notmatch '^[A-Fa-f0-9]{64}$') {
        if ($Mode -eq 'Gui') {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                [System.Windows.Forms.MessageBox]::Show(
                    '啟動器提供的完整性資料無效。請重新下載正式版本。沒有執行任何系統變更。',
                    'TelemetryGuard 完整性檢查失敗',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
            catch { }
        }
        throw '啟動器提供的程式雜湊格式無效；沒有執行任何系統變更。'
    }
    if ($script:LaunchSourceHash -ne $ExpectedSourceHash.ToUpperInvariant()) {
        if ($Mode -eq 'Gui') {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                [System.Windows.Forms.MessageBox]::Show(
                    'TelemetryGuard.ps1 與啟動器的完整性資料不符。請重新下載正式版本。沒有執行任何系統變更。',
                    'TelemetryGuard 完整性檢查失敗',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
            catch { }
        }
        throw 'TelemetryGuard.ps1 與啟動器的完整性雜湊不符；請重新下載正式版本。沒有執行任何系統變更。'
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedCopy {
    $windowsDirectory = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        'Sysnative'
    }
    else {
        'System32'
    }
    $windowsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    if ([string]::IsNullOrWhiteSpace($windowsRoot)) {
        throw '無法從 Windows Known Folder 取得系統目錄；沒有執行任何系統變更。'
    }
    $powerShellExe = Join-Path $windowsRoot ($windowsDirectory + '\WindowsPowerShell\v1.0\powershell.exe')
    if (-not (Test-Path -LiteralPath $powerShellExe -PathType Leaf)) {
        throw '找不到 Windows 系統 PowerShell；沒有執行任何系統變更。'
    }
    $sourcePathBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
            [IO.Path]::GetFullPath($PSCommandPath)))
    $bootstrap = @'
$ErrorActionPreference = 'Stop'
$expectedHash = '__EXPECTED_HASH__'
$sourcePath = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__SOURCE_PATH_BASE64__'))
$sourceStream = $null
$stageStream = $null
$stagingRoot = $null
$commonDataRoot = $null
$failed = $false

try {
    if ($expectedHash -notmatch '^[A-F0-9]{64}$') {
        throw 'Invalid expected hash.'
    }
    $sourcePath = [IO.Path]::GetFullPath($sourcePath)
    $sourceStream = [IO.File]::Open(
        $sourcePath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    if ($sourceStream.Length -le 0 -or $sourceStream.Length -gt 5242880) {
        throw 'Unexpected source length.'
    }

    $sourceBytes = New-Object byte[] ([int]$sourceStream.Length)
    $offset = 0
    while ($offset -lt $sourceBytes.Length) {
        $read = $sourceStream.Read($sourceBytes, $offset, $sourceBytes.Length - $offset)
        if ($read -le 0) {
            throw 'Could not read the complete source file.'
        }
        $offset += $read
    }

    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $actualHash = (($hasher.ComputeHash($sourceBytes) |
                    ForEach-Object { $_.ToString('X2') }) -join '')
    }
    finally {
        $hasher.Dispose()
    }
    if ($actualHash -cne $expectedHash) {
        throw 'Source hash mismatch.'
    }

    $commonDataRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if ([string]::IsNullOrWhiteSpace($commonDataRoot) -or -not [IO.Path]::IsPathRooted($commonDataRoot)) {
        throw 'Common application data folder is unavailable.'
    }

    $administrators = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $system = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $directorySecurity = New-Object Security.AccessControl.DirectorySecurity
    $directorySecurity.SetAccessRuleProtection($true, $false)
    $directorySecurity.SetOwner($administrators)
    foreach ($sid in @($administrators, $system)) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        $directorySecurity.AddAccessRule($rule)
    }

    $stagingRoot = Join-Path $commonDataRoot ('TelemetryGuard-Launch-' + [Guid]::NewGuid().ToString('N'))
    $stagingDirectory = New-Object IO.DirectoryInfo($stagingRoot)
    $stagingDirectory.Create($directorySecurity)
    if (([IO.File]::GetAttributes($stagingRoot) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Protected staging folder cannot be a reparse point.'
    }

    $stagedScript = Join-Path $stagingRoot 'TelemetryGuard.ps1'
    $stageStream = [IO.File]::Open(
        $stagedScript,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    $stageStream.Write($sourceBytes, 0, $sourceBytes.Length)
    $stageStream.Flush($true)
    $stageStream.Dispose()
    $stageStream = $null

    $fileSecurity = New-Object Security.AccessControl.FileSecurity
    $fileSecurity.SetAccessRuleProtection($true, $false)
    $fileSecurity.SetOwner($administrators)
    foreach ($sid in @($administrators, $system)) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow
        )
        $fileSecurity.AddAccessRule($rule)
    }
    [IO.File]::SetAccessControl($stagedScript, $fileSecurity)

    $stageReadStream = [IO.File]::Open(
        $stagedScript,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    try {
        $stageHasher = [Security.Cryptography.SHA256]::Create()
        try {
            $stagedHash = (($stageHasher.ComputeHash($stageReadStream) |
                        ForEach-Object { $_.ToString('X2') }) -join '')
        }
        finally {
            $stageHasher.Dispose()
        }
    }
    finally {
        $stageReadStream.Dispose()
    }
    if ($stagedHash -cne $expectedHash) {
        throw 'Protected staging hash mismatch.'
    }

    & $stagedScript -Mode Gui -NoElevation -ExpectedSourceHash $expectedHash
}
catch {
    $failed = $true
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            '無法驗證或安全啟動 TelemetryGuard。請重新下載正式版本。沒有執行任何系統變更。',
            'TelemetryGuard 完整性檢查失敗',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch { }
}
finally {
    if ($null -ne $stageStream) {
        $stageStream.Dispose()
    }
    if ($null -ne $sourceStream) {
        $sourceStream.Dispose()
    }
    if (-not [string]::IsNullOrWhiteSpace($stagingRoot) -and
        -not [string]::IsNullOrWhiteSpace($commonDataRoot)) {
        $expectedPrefix = [IO.Path]::GetFullPath($commonDataRoot).TrimEnd('\') + '\TelemetryGuard-Launch-'
        $resolvedStage = [IO.Path]::GetFullPath($stagingRoot)
        if ($resolvedStage.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedStage) -match '^TelemetryGuard-Launch-[a-f0-9]{32}$') {
            Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($failed) {
    exit 23
}
exit 0
'@
    $bootstrap = $bootstrap.Replace('__EXPECTED_HASH__', $script:LaunchSourceHash).
        Replace('__SOURCE_PATH_BASE64__', $sourcePathBase64)
    $encodedBootstrap = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
    if ($encodedBootstrap.Length -gt 24000) {
        throw '安全提升啟動程式超過允許長度；沒有執行任何系統變更。'
    }
    $argumentList = @(
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-EncodedCommand', $encodedBootstrap
    )

    try {
        $process = Start-Process -FilePath $powerShellExe -Verb RunAs `
            -ArgumentList $argumentList -Wait -PassThru
        return [bool]($process.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

function Assert-WriteAccess {
    if (Test-IsAdministrator) {
        return
    }

    if ($Mode -eq 'Gui' -and -not $NoElevation) {
        if (-not (Start-ElevatedCopy)) {
            throw '未取得系統管理員權限，沒有變更任何設定。'
        }
        exit 0
    }

    throw '此動作需要系統管理員權限。請從系統管理員 PowerShell 執行，或使用圖形介面。'
}

function New-SecureDirectorySecurity {
    $administrators = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    $security.SetOwner($administrators)
    foreach ($sid in @($administrators, $system)) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        [void]$security.AddAccessRule($rule)
    }
    return $security
}

function New-SecureFileSecurity {
    $administrators = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $security = [Security.AccessControl.FileSecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    $security.SetOwner($administrators)
    foreach ($sid in @($administrators, $system)) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow
        )
        [void]$security.AddAccessRule($rule)
    }
    return $security
}

function Convert-IdentityToSidValue {
    param([Parameter(Mandatory = $true)][string]$Identity)

    if ($Identity.StartsWith('S-1-', [StringComparison]::OrdinalIgnoreCase)) {
        return ([Security.Principal.SecurityIdentifier]::new($Identity)).Value
    }
    return ([Security.Principal.NTAccount]::new($Identity)).Translate(
        [Security.Principal.SecurityIdentifier]
    ).Value
}

function Assert-SecureAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][bool]$Directory
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ('安全檢查失敗：{0} 不可為連結或重新解析點。' -f $Path)
    }
    if ($Directory -and -not $item.PSIsContainer) {
        throw ('安全檢查失敗：{0} 不是資料夾。' -f $Path)
    }

    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    if (-not $acl.AreAccessRulesProtected) {
        throw ('安全檢查失敗：{0} 的權限未受保護。' -f $Path)
    }

    $allowedSids = @('S-1-5-32-544', 'S-1-5-18')
    foreach ($rule in @($acl.Access)) {
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) {
            continue
        }
        $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($allowedSids -notcontains $sid) {
            throw ('安全檢查失敗：{0} 允許非系統管理員寫入。' -f $Path)
        }
    }

    $ownerSid = Convert-IdentityToSidValue -Identity ([string]$acl.Owner)
    if ($allowedSids -notcontains $ownerSid) {
        throw ('安全檢查失敗：{0} 的擁有者不受信任。' -f $Path)
    }
}

function Ensure-StateRoot {
    if ([string]::IsNullOrWhiteSpace($script:CommonDataRoot) -or
        -not [IO.Path]::IsPathRooted($script:StateRoot)) {
        throw '無法取得受信任的 ProgramData 路徑。'
    }

    if (-not (Test-Path -LiteralPath $script:StateRoot)) {
        $security = New-SecureDirectorySecurity
        [void][IO.Directory]::CreateDirectory($script:StateRoot, $security)
    }
    Assert-SecureAcl -Path $script:StateRoot -Directory $true
}

function Set-SecureFileAcl {
    param([Parameter(Mandatory = $true)][string]$Path)
    Set-Acl -LiteralPath $Path -AclObject (New-SecureFileSecurity) -ErrorAction Stop
    Assert-SecureAcl -Path $Path -Directory $false
}

function Write-GuardLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    try {
        Ensure-StateRoot
        $line = '{0}  {1}' -f ([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')), $Message
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Logging is best-effort and must never interrupt a system change.
    }
}

function Invoke-WithOperationLock {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)

    $mutex = [Threading.Mutex]::new($false, 'Global\TelemetryGuard.Operation')
    $ownsMutex = $false
    try {
        try {
            $ownsMutex = $mutex.WaitOne(0)
        }
        catch [Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
        if (-not $ownsMutex) {
            throw '另一個 TelemetryGuard 操作正在執行，請稍後再試。'
        }
        & $Action
    }
    finally {
        if ($ownsMutex) {
            try { $mutex.ReleaseMutex() } catch { }
        }
        $mutex.Dispose()
    }
}

function Get-MachineFingerprint {
    $machineGuid = [string](Get-ItemPropertyValue `
        -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' `
        -Name 'MachineGuid' `
        -ErrorAction Stop)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($machineGuid)
        return (($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-WindowsInfo {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $operatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $productName = if ($null -ne $operatingSystem -and -not [string]::IsNullOrWhiteSpace([string]$operatingSystem.Caption)) {
        [string]$operatingSystem.Caption
    }
    else {
        [string]$currentVersion.ProductName
    }
    $editionId = [string]$currentVersion.EditionID
    $displayVersion = if ($currentVersion.PSObject.Properties.Name -contains 'DisplayVersion') {
        [string]$currentVersion.DisplayVersion
    }
    elseif ($currentVersion.PSObject.Properties.Name -contains 'ReleaseId') {
        [string]$currentVersion.ReleaseId
    }
    else {
        ''
    }
    $buildNumber = [int]$currentVersion.CurrentBuild
    if ($buildNumber -lt 10240) {
        throw 'TelemetryGuard 只支援 Windows 10、Windows 11 與 Windows Server 2016 或更新版本。'
    }
    $build = [string]$buildNumber
    if ($currentVersion.PSObject.Properties.Name -contains 'UBR' -and $currentVersion.UBR -ne $null) {
        $build = '{0}.{1}' -f $build, $currentVersion.UBR
    }

    $diagnosticOffEditions = @(
        'Enterprise', 'EnterpriseN', 'EnterpriseS', 'EnterpriseSN', 'EnterpriseG', 'EnterpriseGN',
        'Education', 'EducationN'
    )
    $proEditions = @(
        'Professional', 'ProfessionalN', 'ProfessionalEducation', 'ProfessionalEducationN',
        'ProfessionalWorkstation', 'ProfessionalWorkstationN'
    )
    $iotEditions = @('IoTEnterprise', 'IoTEnterpriseS')
    $isServerEdition = $editionId.StartsWith('Server', [StringComparison]::OrdinalIgnoreCase)
    $supportsDiagnosticDataOff = ($diagnosticOffEditions -contains $editionId) -or $isServerEdition
    $supportsManagementPolicies = $supportsDiagnosticDataOff -or
        ($proEditions -contains $editionId) -or
        ($iotEditions -contains $editionId)

    return [pscustomobject][ordered]@{
        ProductName = $productName
        EditionId = $editionId
        DisplayVersion = $displayVersion
        BuildNumber = $buildNumber
        Build = $build
        IsServerEdition = [bool]$isServerEdition
        SupportsDiagnosticDataOff = [bool]$supportsDiagnosticDataOff
        SupportsManagementPolicies = [bool]$supportsManagementPolicies
    }
}

function Get-OptionalOptimizationProfiles {
    return @(
        [pscustomobject][ordered]@{
            Id = 'search-indexing'
            Title = 'Windows 搜尋索引'
            Impact = '會降低檔案總管、開始功能表與 Outlook 的搜尋速度；需要時可還原。'
            Services = @('WSearch')
            Tasks = @(
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Shell\'; TaskName = 'IndexerAutomaticMaintenance' }
            )
        },
        [pscustomobject][ordered]@{
            Id = 'mixed-reality-link'
            Title = 'Mixed Reality Link'
            Impact = '會停用 Meta Quest 3／3S 的 Mixed Reality Link 串流功能。'
            Services = @('MixedRealityLinkSvc')
            Tasks = @()
        },
        [pscustomobject][ordered]@{
            Id = 'printing'
            Title = '列印服務'
            Impact = '會停用實體印表機、Microsoft Print to PDF 與其他列印功能。'
            Services = @('Spooler')
            Tasks = @()
        },
        [pscustomobject][ordered]@{
            Id = 'connected-devices'
            Title = '跨裝置與手機連結'
            Impact = '可能停用 Phone Link、附近分享及部分跨裝置體驗。'
            Services = @('CDPSvc', 'PhoneSvc')
            Tasks = @()
        },
        [pscustomobject][ordered]@{
            Id = 'location-maps'
            Title = '定位與離線地圖'
            Impact = '會影響定位、離線地圖更新、天氣與依位置運作的功能。'
            Services = @('lfsvc', 'MapsBroker')
            Tasks = @(
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Maps\'; TaskName = 'MapsToastTask' },
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Maps\'; TaskName = 'MapsUpdateTask' }
            )
        },
        [pscustomobject][ordered]@{
            Id = 'xbox'
            Title = 'Xbox 與 Game Pass 背景功能'
            Impact = '會影響 Xbox 登入、Game Pass、雲端存檔、多人連線及部分控制器配件。'
            Services = @('XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc')
            Tasks = @(
                [pscustomobject]@{ TaskPath = '\Microsoft\XblGameSave\'; TaskName = 'XblGameSaveTask' }
            )
        },
        [pscustomobject][ordered]@{
            Id = 'error-feedback'
            Title = '額外遙測、錯誤回報與意見回饋'
            Impact = '會減少永續性遙測、當機回報與意見收集，但也降低 Microsoft 或 IT 人員診斷故障的資訊。'
            Services = @('WerSvc')
            Tasks = @(
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Feedback\Siuf\'; TaskName = 'DmClient' },
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Feedback\Siuf\'; TaskName = 'DmClientOnScenarioDownload' },
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Sustainability\'; TaskName = 'SustainabilityTelemetry' },
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Windows Error Reporting\'; TaskName = 'QueueReporting' }
            )
        },
        [pscustomobject][ordered]@{
            Id = 'compatibility-assistant'
            Title = '程式相容性小幫手'
            Impact = '舊版程式發生相容性問題時，Windows 將不再自動偵測並建議修正。'
            Services = @('PcaSvc')
            Tasks = @(
                [pscustomobject]@{ TaskPath = '\Microsoft\Windows\Application Experience\'; TaskName = 'MareBackup' }
            )
        },
        [pscustomobject][ordered]@{
            Id = 'store-install'
            Title = 'Microsoft Store 應用程式安裝'
            Impact = '會阻止 Microsoft Store 安裝或更新應用程式；不會停用 Windows Update。'
            Services = @('InstallService')
            Tasks = @()
        },
        [pscustomobject][ordered]@{
            Id = 'media-sharing'
            Title = 'Windows Media Player 媒體庫分享'
            Impact = '會停止透過 UPnP 將媒體庫分享給電視、播放器或其他網路裝置。'
            Services = @('WMPNetworkSvc')
            Tasks = @()
        },
        [pscustomobject][ordered]@{
            Id = 'mobile-hotspot'
            Title = 'Windows 行動熱點'
            Impact = '會關閉行動熱點；目前透過這台電腦上網的裝置會中斷連線。'
            Services = @('icssvc')
            Tasks = @()
        },
        [pscustomobject][ordered]@{
            Id = 'webdav-client'
            Title = 'WebDAV 網路檔案用戶端'
            Impact = '檔案總管與程式將無法使用 WebDAV／部分 SharePoint 對應資料夾。'
            Services = @('WebClient')
            Tasks = @()
        }
    )
}

function Resolve-OptionalProfileIds {
    param([AllowEmptyCollection()][string[]]$ProfileIds = @())

    $requested = @{}
    foreach ($profileArgument in @($ProfileIds)) {
        foreach ($profileId in @(([string]$profileArgument).Split(','))) {
            if ([string]::IsNullOrWhiteSpace([string]$profileId)) {
                throw '資源最佳化選項不可為空白。'
            }
            $normalized = ([string]$profileId).Trim().ToLowerInvariant()
            if ($script:AllowedOptionalProfileIds -notcontains $normalized) {
                throw ('未知的資源最佳化選項：{0}。' -f $profileId)
            }
            if ($requested.ContainsKey($normalized)) {
                throw ('資源最佳化選項重複：{0}。' -f $profileId)
            }
            $requested[$normalized] = $true
        }
    }

    return @(
        Get-OptionalOptimizationProfiles |
            Where-Object { $requested.ContainsKey([string]$_.Id) } |
            ForEach-Object { [string]$_.Id }
    )
}

function Get-SelectedOptionalProfiles {
    param([AllowEmptyCollection()][string[]]$ProfileIds = @())

    $resolved = @(Resolve-OptionalProfileIds -ProfileIds $ProfileIds)
    return @(
        Get-OptionalOptimizationProfiles |
            Where-Object { $resolved -contains [string]$_.Id }
    )
}

function Get-OptionalServiceNames {
    param([AllowEmptyCollection()][string[]]$ProfileIds = @())

    return @(
        Get-SelectedOptionalProfiles -ProfileIds $ProfileIds |
            ForEach-Object { @($_.Services) } |
            Sort-Object -Unique
    )
}

function Get-OptionalTaskDefinitions {
    param([AllowEmptyCollection()][string[]]$ProfileIds = @())

    return @(
        foreach ($profile in @(Get-SelectedOptionalProfiles -ProfileIds $ProfileIds)) {
            foreach ($task in @($profile.Tasks)) {
                [pscustomobject][ordered]@{
                    ProfileId = [string]$profile.Id
                    TaskPath = [string]$task.TaskPath
                    TaskName = [string]$task.TaskName
                }
            }
        }
    )
}

function Get-DesiredPolicySettings {
    $windows = Get-WindowsInfo
    $settings = @()
    if ($windows.SupportsManagementPolicies) {
        $allowTelemetry = if ($windows.SupportsDiagnosticDataOff) { 0 } else { 1 }
        $settings += [pscustomobject][ordered]@{
            Path = $script:DataCollectionPolicyPath
            Name = 'AllowTelemetry'
            Value = $allowTelemetry
        }
        $settings += [pscustomobject][ordered]@{
            Path = $script:CeipPolicyPath
            Name = 'CEIPEnable'
            Value = 0
        }
    }

    $supportsLimitPolicies = $windows.SupportsManagementPolicies -and
        (($windows.BuildNumber -ge 22000) -or
            ($windows.IsServerEdition -and $windows.BuildNumber -ge 20348))
    if ($supportsLimitPolicies) {
        $settings += [pscustomobject][ordered]@{
            Path = $script:DataCollectionPolicyPath
            Name = 'LimitDiagnosticLogCollection'
            Value = 1
        }
        $settings += [pscustomobject][ordered]@{
            Path = $script:DataCollectionPolicyPath
            Name = 'LimitDumpCollection'
            Value = 1
        }
    }

    return @($settings)
}

function Get-RegistryValueSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $snapshot = [ordered]@{
        Path = $Path
        Name = $Name
        Existed = $false
        Kind = 'DWord'
        Value = $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$snapshot
    }

    $key = Get-Item -LiteralPath $Path
    if (@($key.GetValueNames()) -notcontains $Name) {
        return [pscustomobject]$snapshot
    }

    $snapshot.Existed = $true
    $snapshot.Kind = $key.GetValueKind($Name).ToString()
    $snapshot.Value = $key.GetValue(
        $Name,
        $null,
        [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    )
    return [pscustomobject]$snapshot
}

function Set-RegistryValueFromSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    if (-not [bool]$Snapshot.Existed) {
        if (Test-Path -LiteralPath ([string]$Snapshot.Path)) {
            $current = Get-RegistryValueSnapshot -Path ([string]$Snapshot.Path) -Name ([string]$Snapshot.Name)
            if ($current.Existed) {
                Remove-ItemProperty `
                    -LiteralPath ([string]$Snapshot.Path) `
                    -Name ([string]$Snapshot.Name) `
                    -ErrorAction Stop
            }
        }
        return
    }

    if (-not (Test-Path -LiteralPath ([string]$Snapshot.Path))) {
        New-Item -Path ([string]$Snapshot.Path) -Force -ErrorAction Stop | Out-Null
    }

    $value = $Snapshot.Value
    switch ([string]$Snapshot.Kind) {
        'Binary' { $value = [byte[]]@($Snapshot.Value) }
        'MultiString' { $value = [string[]]@($Snapshot.Value) }
    }

    New-ItemProperty `
        -LiteralPath ([string]$Snapshot.Path) `
        -Name ([string]$Snapshot.Name) `
        -PropertyType ([string]$Snapshot.Kind) `
        -Value $value `
        -Force `
        -ErrorAction Stop | Out-Null
}

function Get-TargetScheduledTasks {
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        throw '此系統缺少 ScheduledTasks 管理模組，無法安全判定排程狀態。'
    }

    $appraiserNames = @(
        'Microsoft Compatibility Appraiser',
        'Microsoft Compatibility Appraiser Exp'
    )
    $ceipNames = @(
        'Consolidator',
        'KernelCeipTask',
        'UsbCeip'
    )

    return @(
        Get-ScheduledTask -ErrorAction Stop |
            Where-Object {
                ($_.TaskPath -eq '\Microsoft\Windows\Application Experience\' -and
                    $appraiserNames -contains $_.TaskName) -or
                ($_.TaskPath -eq '\Microsoft\Windows\Customer Experience Improvement Program\' -and
                    $ceipNames -contains $_.TaskName)
            } |
            Sort-Object TaskPath, TaskName
    )
}

function Find-ScheduledTaskExact {
    param(
        [Parameter(Mandatory = $true)][string]$TaskPath,
        [Parameter(Mandatory = $true)][string]$TaskName
    )

    return @(
        Get-ScheduledTask -ErrorAction Stop |
            Where-Object {
                [string]$_.TaskPath -eq $TaskPath -and
                [string]$_.TaskName -eq $TaskName
            }
    ) | Select-Object -First 1
}

function Get-OptionalTargetScheduledTasks {
    param([AllowEmptyCollection()][string[]]$ProfileIds = @())

    $definitions = @(Get-OptionalTaskDefinitions -ProfileIds $ProfileIds)
    if ($definitions.Count -eq 0) {
        return @()
    }
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        throw '此系統缺少 ScheduledTasks 管理模組，無法安全判定選用排程狀態。'
    }

    $definitionMap = @{}
    foreach ($definition in $definitions) {
        $identity = ('{0}|{1}' -f $definition.TaskPath, $definition.TaskName).ToLowerInvariant()
        $definitionMap[$identity] = $definition
    }

    return @(
        Get-ScheduledTask -ErrorAction Stop |
            Where-Object {
                $identity = ('{0}|{1}' -f $_.TaskPath, $_.TaskName).ToLowerInvariant()
                $definitionMap.ContainsKey($identity)
            } |
            Sort-Object TaskPath, TaskName
    )
}

function Get-ServiceSnapshot {
    $service = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction Stop
    if ($null -eq $service) {
        return [pscustomobject][ordered]@{ Existed = $false }
    }

    return [pscustomobject][ordered]@{
        Existed = $true
        Name = 'DiagTrack'
        State = [string]$service.State
        StartMode = [string]$service.StartMode
        DelayedAutoStart = Get-RegistryValueSnapshot `
            -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack' `
            -Name 'DelayedAutoStart'
    }
}

function Get-OptionalServiceSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ProfileId
    )

    if ($script:AllowedOptionalServiceNames -notcontains $Name -or
        $script:AllowedOptionalProfileIds -notcontains $ProfileId) {
        throw '拒絕讀取不在資源最佳化白名單內的服務。'
    }

    $snapshot = [ordered]@{
        ProfileId = $ProfileId
        Name = $Name
        Existed = $false
        State = $null
        StartMode = $null
        DelayedAutoStart = $null
    }
    $service = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $Name) -ErrorAction Stop
    if ($null -eq $service) {
        return [pscustomobject]$snapshot
    }

    $snapshot.Existed = $true
    $snapshot.State = [string]$service.State
    $snapshot.StartMode = [string]$service.StartMode
    $snapshot.DelayedAutoStart = Get-RegistryValueSnapshot `
        -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $Name) `
        -Name 'DelayedAutoStart'
    return [pscustomobject]$snapshot
}

function New-BackupObject {
    $taskSnapshots = @(
        Get-TargetScheduledTasks | ForEach-Object {
            [pscustomobject][ordered]@{
                TaskPath = [string]$_.TaskPath
                TaskName = [string]$_.TaskName
                Enabled = [bool]$_.Settings.Enabled
            }
        }
    )

    $registrySnapshots = @(
        foreach ($setting in @(Get-DesiredPolicySettings)) {
            Get-RegistryValueSnapshot -Path ([string]$setting.Path) -Name ([string]$setting.Name)
        }
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        AppVersion = $script:AppVersion
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        MachineFingerprint = Get-MachineFingerprint
        Windows = Get-WindowsInfo
        Service = Get-ServiceSnapshot
        RegistryValues = $registrySnapshots
        Tasks = $taskSnapshots
    }
}

function Save-BackupObject {
    param([Parameter(Mandatory = $true)]$Backup)

    Ensure-StateRoot
    Assert-BackupObject -Backup $Backup
    if (Test-Path -LiteralPath $script:BackupPath) {
        throw '原始備份已存在；為避免覆寫，已停止建立新備份。'
    }

    $json = $Backup | ConvertTo-Json -Depth 10
    $tempPath = Join-Path $script:StateRoot ('backup-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    try {
        [IO.File]::WriteAllText($tempPath, $json, $utf8Bom)
        Set-SecureFileAcl -Path $tempPath
        [IO.File]::Move($tempPath, $script:BackupPath)
        Assert-SecureAcl -Path $script:BackupPath -Directory $false
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Assert-BackupObject {
    param([Parameter(Mandatory = $true)]$Backup)

    foreach ($propertyName in @('SchemaVersion', 'MachineFingerprint', 'Service', 'RegistryValues', 'Tasks')) {
        if ($Backup.PSObject.Properties.Name -notcontains $propertyName) {
            throw ('備份缺少必要欄位 {0}。' -f $propertyName)
        }
    }
    if ($Backup.SchemaVersion -isnot [int] -or [int]$Backup.SchemaVersion -ne 1) {
        throw '備份格式不相容，已停止還原。'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Backup.MachineFingerprint) -or
        [string]$Backup.MachineFingerprint -ne (Get-MachineFingerprint)) {
        throw '這份備份不是由目前這台電腦建立，已停止還原。'
    }

    $service = $Backup.Service
    if ($service.PSObject.Properties.Name -notcontains 'Existed' -or $service.Existed -isnot [bool]) {
        throw '備份中的服務狀態無效。'
    }
    if ([bool]$service.Existed) {
        if ([string]$service.Name -cne 'DiagTrack' -or
            @('Running', 'Stopped') -notcontains [string]$service.State -or
            @('Auto', 'Manual', 'Disabled') -notcontains [string]$service.StartMode) {
            throw '備份中的 DiagTrack 服務資料不在允許範圍內。'
        }
        if ($service.PSObject.Properties.Name -notcontains 'DelayedAutoStart') {
            throw '備份缺少 DiagTrack 的 DelayedAutoStart 狀態。'
        }
        $delayed = $service.DelayedAutoStart
        if ([string]$delayed.Path -ine 'HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack' -or
            [string]$delayed.Name -ine 'DelayedAutoStart' -or
            [string]$delayed.Kind -ine 'DWord' -or
            $delayed.Existed -isnot [bool]) {
            throw '備份中的 DelayedAutoStart 資料無效。'
        }
        if ([bool]$delayed.Existed -and
            ($delayed.Value -isnot [int] -and $delayed.Value -isnot [long])) {
            throw '備份中的 DelayedAutoStart 值無效。'
        }
        if ([bool]$delayed.Existed -and
            ([int64]$delayed.Value -lt [int64][int]::MinValue -or
                [int64]$delayed.Value -gt [int64][uint32]::MaxValue)) {
            throw '備份中的 DelayedAutoStart DWORD 超出有效範圍。'
        }
    }

    $seenRegistry = @{}
    foreach ($snapshot in @($Backup.RegistryValues)) {
        foreach ($propertyName in @('Path', 'Name', 'Existed', 'Kind')) {
            if ($snapshot.PSObject.Properties.Name -notcontains $propertyName) {
                throw ('備份中的登錄資料缺少 {0}。' -f $propertyName)
            }
        }
        $identity = ('{0}|{1}' -f $snapshot.Path, $snapshot.Name).ToLowerInvariant()
        if ($script:AllowedRegistryIdentities -notcontains $identity -or $seenRegistry.ContainsKey($identity)) {
            throw '備份含有未知或重複的登錄目標。'
        }
        if ($snapshot.Existed -isnot [bool] -or [string]$snapshot.Kind -ine 'DWord') {
            throw '備份中的登錄型別無效。'
        }
        if ([bool]$snapshot.Existed -and
            $snapshot.Value -isnot [int] -and $snapshot.Value -isnot [long]) {
            throw '備份中的登錄值不是有效的 DWORD。'
        }
        if ([bool]$snapshot.Existed -and
            ([int64]$snapshot.Value -lt [int64][int]::MinValue -or
                [int64]$snapshot.Value -gt [int64][uint32]::MaxValue)) {
            throw '備份中的 DWORD 超出有效範圍。'
        }
        $seenRegistry[$identity] = $true
    }

    $seenTasks = @{}
    foreach ($task in @($Backup.Tasks)) {
        foreach ($propertyName in @('TaskPath', 'TaskName', 'Enabled')) {
            if ($task.PSObject.Properties.Name -notcontains $propertyName) {
                throw ('備份中的排程資料缺少 {0}。' -f $propertyName)
            }
        }
        $identity = ('{0}|{1}' -f $task.TaskPath, $task.TaskName).ToLowerInvariant()
        if ($script:AllowedTaskIdentities -notcontains $identity -or $seenTasks.ContainsKey($identity)) {
            throw '備份含有未知或重複的排程目標。'
        }
        if ($task.Enabled -isnot [bool]) {
            throw '備份中的排程 Enabled 狀態無效。'
        }
        $seenTasks[$identity] = $true
    }
}

function Read-BackupObject {
    Ensure-StateRoot
    if (-not (Test-Path -LiteralPath $script:BackupPath)) {
        throw '找不到還原備份。請先套用關閉設定。'
    }
    Assert-SecureAcl -Path $script:BackupPath -Directory $false

    try {
        $backup = Get-Content -LiteralPath $script:BackupPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        throw ('無法讀取安全備份：{0}' -f $_.Exception.Message)
    }
    Assert-BackupObject -Backup $backup
    return $backup
}

function Get-OrCreateBackup {
    Ensure-StateRoot
    if (Test-Path -LiteralPath $script:BackupPath) {
        return (Read-BackupObject)
    }

    $backup = New-BackupObject
    Save-BackupObject -Backup $backup
    Write-GuardLog '已建立不可覆寫的原始設定備份。'
    return $backup
}

function New-OptionalBackupObject {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ProfileIds)

    $resolved = @(Resolve-OptionalProfileIds -ProfileIds $ProfileIds)
    if ($resolved.Count -eq 0) {
        throw '沒有勾選任何可選資源最佳化項目。'
    }

    $serviceSnapshots = @(
        foreach ($profile in @(Get-SelectedOptionalProfiles -ProfileIds $resolved)) {
            foreach ($serviceName in @($profile.Services)) {
                Get-OptionalServiceSnapshot -Name ([string]$serviceName) -ProfileId ([string]$profile.Id)
            }
        }
    )

    $existingTaskMap = @{}
    foreach ($task in @(Get-OptionalTargetScheduledTasks -ProfileIds $resolved)) {
        $identity = ('{0}|{1}' -f $task.TaskPath, $task.TaskName).ToLowerInvariant()
        $existingTaskMap[$identity] = $task
    }
    $taskSnapshots = @(
        foreach ($definition in @(Get-OptionalTaskDefinitions -ProfileIds $resolved)) {
            $identity = ('{0}|{1}' -f $definition.TaskPath, $definition.TaskName).ToLowerInvariant()
            $task = if ($existingTaskMap.ContainsKey($identity)) { $existingTaskMap[$identity] } else { $null }
            [pscustomobject][ordered]@{
                ProfileId = [string]$definition.ProfileId
                TaskPath = [string]$definition.TaskPath
                TaskName = [string]$definition.TaskName
                Existed = [bool]($null -ne $task)
                Enabled = if ($null -ne $task) { [bool]$task.Settings.Enabled } else { $null }
            }
        }
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        AppVersion = $script:AppVersion
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        MachineFingerprint = Get-MachineFingerprint
        Windows = Get-WindowsInfo
        SelectedProfiles = @($resolved)
        Services = $serviceSnapshots
        Tasks = $taskSnapshots
    }
}

function Assert-OptionalBackupObject {
    param([Parameter(Mandatory = $true)]$Backup)

    foreach ($propertyName in @('SchemaVersion', 'MachineFingerprint', 'SelectedProfiles', 'Services', 'Tasks')) {
        if ($Backup.PSObject.Properties.Name -notcontains $propertyName) {
            throw ('資源備份缺少必要欄位 {0}。' -f $propertyName)
        }
    }
    if ($Backup.SchemaVersion -isnot [int] -or [int]$Backup.SchemaVersion -ne 1) {
        throw '資源備份格式不相容，已停止還原。'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Backup.MachineFingerprint) -or
        [string]$Backup.MachineFingerprint -ne (Get-MachineFingerprint)) {
        throw '這份資源備份不是由目前這台電腦建立，已停止還原。'
    }

    $profileIds = @($Backup.SelectedProfiles | ForEach-Object { [string]$_ })
    $resolved = @(Resolve-OptionalProfileIds -ProfileIds $profileIds)
    if ($resolved.Count -eq 0 -or ($resolved -join "`n") -cne ($profileIds -join "`n")) {
        throw '資源備份中的選項順序或內容無效。'
    }

    $expectedServices = @{}
    $expectedServiceNames = @{}
    $expectedServiceOrder = New-Object System.Collections.Generic.List[string]
    foreach ($profile in @(Get-SelectedOptionalProfiles -ProfileIds $resolved)) {
        foreach ($serviceName in @($profile.Services)) {
            $identity = ('{0}|{1}' -f $profile.Id, $serviceName).ToLowerInvariant()
            $serviceIdentity = ([string]$serviceName).ToLowerInvariant()
            if ($expectedServiceNames.ContainsKey($serviceIdentity)) {
                throw '內建資源最佳化目錄將同一服務對應到多個選項，已停止處理。'
            }
            $expectedServices[$identity] = $true
            $expectedServiceNames[$serviceIdentity] = $true
            $expectedServiceOrder.Add($identity)
        }
    }
    $seenServices = @{}
    $seenServiceOrder = New-Object System.Collections.Generic.List[string]
    foreach ($snapshot in @($Backup.Services)) {
        foreach ($propertyName in @('ProfileId', 'Name', 'Existed')) {
            if ($snapshot.PSObject.Properties.Name -notcontains $propertyName) {
                throw ('資源備份中的服務資料缺少 {0}。' -f $propertyName)
            }
        }
        $identity = ('{0}|{1}' -f $snapshot.ProfileId, $snapshot.Name).ToLowerInvariant()
        if (-not $expectedServices.ContainsKey($identity) -or $seenServices.ContainsKey($identity) -or
            $script:AllowedOptionalServiceNames -notcontains [string]$snapshot.Name) {
            throw '資源備份含有未知、錯誤對應或重複的服務目標。'
        }
        if ($snapshot.Existed -isnot [bool]) {
            throw '資源備份中的服務 Existed 狀態無效。'
        }
        if ([bool]$snapshot.Existed) {
            if (@('Running', 'Stopped') -notcontains [string]$snapshot.State -or
                @('Auto', 'Manual', 'Disabled') -notcontains [string]$snapshot.StartMode -or
                $snapshot.PSObject.Properties.Name -notcontains 'DelayedAutoStart') {
                throw '資源備份中的服務狀態或啟動方式無效。'
            }
            $delayed = $snapshot.DelayedAutoStart
            $expectedPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $snapshot.Name
            if ([string]$delayed.Path -ine $expectedPath -or
                [string]$delayed.Name -ine 'DelayedAutoStart' -or
                [string]$delayed.Kind -ine 'DWord' -or
                $delayed.Existed -isnot [bool]) {
                throw '資源備份中的 DelayedAutoStart 資料無效。'
            }
            if ([bool]$delayed.Existed -and
                ($delayed.Value -isnot [int] -and $delayed.Value -isnot [long])) {
                throw '資源備份中的 DelayedAutoStart 值無效。'
            }
            if ([bool]$delayed.Existed -and
                ([int64]$delayed.Value -lt [int64][int]::MinValue -or
                    [int64]$delayed.Value -gt [int64][uint32]::MaxValue)) {
                throw '資源備份中的 DelayedAutoStart DWORD 超出有效範圍。'
            }
        }
        $seenServices[$identity] = $true
        $seenServiceOrder.Add($identity)
    }
    if ((@($seenServiceOrder) -join "`n") -cne (@($expectedServiceOrder) -join "`n")) {
        throw '資源備份未依固定目錄順序完整涵蓋選取的服務。'
    }

    $expectedTasks = @{}
    foreach ($definition in @(Get-OptionalTaskDefinitions -ProfileIds $resolved)) {
        $identity = ('{0}|{1}|{2}' -f $definition.ProfileId, $definition.TaskPath, $definition.TaskName).ToLowerInvariant()
        $expectedTasks[$identity] = $true
    }
    $seenTasks = @{}
    foreach ($snapshot in @($Backup.Tasks)) {
        foreach ($propertyName in @('ProfileId', 'TaskPath', 'TaskName', 'Existed', 'Enabled')) {
            if ($snapshot.PSObject.Properties.Name -notcontains $propertyName) {
                throw ('資源備份中的排程資料缺少 {0}。' -f $propertyName)
            }
        }
        $identity = ('{0}|{1}|{2}' -f $snapshot.ProfileId, $snapshot.TaskPath, $snapshot.TaskName).ToLowerInvariant()
        $taskIdentity = ('{0}|{1}' -f $snapshot.TaskPath, $snapshot.TaskName).ToLowerInvariant()
        if (-not $expectedTasks.ContainsKey($identity) -or $seenTasks.ContainsKey($identity) -or
            $script:AllowedOptionalTaskIdentities -notcontains $taskIdentity) {
            throw '資源備份含有未知、錯誤對應或重複的排程目標。'
        }
        if ($snapshot.Existed -isnot [bool] -or
            ([bool]$snapshot.Existed -and $snapshot.Enabled -isnot [bool])) {
            throw '資源備份中的排程狀態無效。'
        }
        $seenTasks[$identity] = $true
    }
    $seenTaskIds = @(($seenTasks.Keys | Sort-Object))
    $expectedTaskIds = @(($expectedTasks.Keys | Sort-Object))
    if (($seenTaskIds -join "`n") -cne ($expectedTaskIds -join "`n")) {
        throw '資源備份未完整涵蓋選取的排程。'
    }
}

function Save-OptionalBackupObject {
    param([Parameter(Mandatory = $true)]$Backup)

    Ensure-StateRoot
    Assert-OptionalBackupObject -Backup $Backup
    if (Test-Path -LiteralPath $script:OptionalBackupPath) {
        throw '資源最佳化備份已存在；為避免覆寫，已停止建立新備份。'
    }

    $json = $Backup | ConvertTo-Json -Depth 10
    $tempPath = Join-Path $script:StateRoot ('resource-backup-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    try {
        [IO.File]::WriteAllText($tempPath, $json, $utf8Bom)
        Set-SecureFileAcl -Path $tempPath
        [IO.File]::Move($tempPath, $script:OptionalBackupPath)
        Assert-SecureAcl -Path $script:OptionalBackupPath -Directory $false
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-OptionalBackupObject {
    Ensure-StateRoot
    if (-not (Test-Path -LiteralPath $script:OptionalBackupPath)) {
        throw '找不到資源最佳化還原備份。'
    }
    Assert-SecureAcl -Path $script:OptionalBackupPath -Directory $false
    try {
        $backup = Get-Content -LiteralPath $script:OptionalBackupPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        throw ('無法讀取安全的資源備份：{0}' -f $_.Exception.Message)
    }
    Assert-OptionalBackupObject -Backup $backup
    return $backup
}

function Get-OrCreateOptionalBackup {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ProfileIds)

    if (Test-Path -LiteralPath $script:OptionalBackupPath) {
        return (Read-OptionalBackupObject)
    }
    $backup = New-OptionalBackupObject -ProfileIds $ProfileIds
    Assert-OptionalServicesCanStop -Snapshots $backup.Services
    Save-OptionalBackupObject -Backup $backup
    Write-GuardLog '已建立不可覆寫的資源最佳化原始設定備份。'
    return $backup
}

function Assert-OptionalBackupCoversSelection {
    param(
        [Parameter(Mandatory = $true)]$Backup,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ProfileIds
    )

    $resolved = @(Resolve-OptionalProfileIds -ProfileIds $ProfileIds)
    $backupProfiles = @($Backup.SelectedProfiles | ForEach-Object { [string]$_ })
    if (($resolved -join "`n") -cne ($backupProfiles -join "`n")) {
        throw '勾選項目與現有資源備份不同。請先還原原始設定，再重新選取。'
    }

    foreach ($snapshot in @($Backup.Services)) {
        $current = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $snapshot.Name) -ErrorAction Stop
        if ([bool]$snapshot.Existed -ne ($null -ne $current)) {
            throw ('服務 {0} 的存在狀態已改變；請先還原並輪替資源備份。' -f $snapshot.Name)
        }
    }
    foreach ($snapshot in @($Backup.Tasks)) {
        $current = Find-ScheduledTaskExact -TaskPath ([string]$snapshot.TaskPath) -TaskName ([string]$snapshot.TaskName)
        if ([bool]$snapshot.Existed -ne ($null -ne $current)) {
            throw ('排程 {0}{1} 的存在狀態已改變；請先還原並輪替資源備份。' -f
                $snapshot.TaskPath, $snapshot.TaskName)
        }
    }
}

function Assert-BackupCoversCurrentTargets {
    param([Parameter(Mandatory = $true)]$Backup)

    $backupRegistry = @(
        @($Backup.RegistryValues) | ForEach-Object {
            ('{0}|{1}' -f $_.Path, $_.Name).ToLowerInvariant()
        } | Sort-Object
    )
    $currentRegistry = @(
        @(Get-DesiredPolicySettings) | ForEach-Object {
            ('{0}|{1}' -f $_.Path, $_.Name).ToLowerInvariant()
        } | Sort-Object
    )
    if (($backupRegistry -join "`n") -cne ($currentRegistry -join "`n")) {
        throw 'Windows 版本或適用政策已改變；目前備份無法涵蓋這次變更。請先還原後再建立新備份。'
    }

    $backupTasks = @(
        @($Backup.Tasks) | ForEach-Object {
            ('{0}|{1}' -f $_.TaskPath, $_.TaskName).ToLowerInvariant()
        } | Sort-Object
    )
    $currentTasks = @(
        @(Get-TargetScheduledTasks) | ForEach-Object {
            ('{0}|{1}' -f $_.TaskPath, $_.TaskName).ToLowerInvariant()
        } | Sort-Object
    )
    if (($backupTasks -join "`n") -cne ($currentTasks -join "`n")) {
        throw 'Windows 已新增或移除目標排程；目前備份無法安全涵蓋這次變更。請先還原後再重新套用。'
    }

    $serviceNow = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction Stop
    if ([bool]$Backup.Service.Existed -ne ($null -ne $serviceNow)) {
        throw 'DiagTrack 的存在狀態與備份不同；為避免無法還原，已停止套用。'
    }
}

function Set-DiagnosticDataPolicies {
    foreach ($setting in @(Get-DesiredPolicySettings)) {
        if (-not (Test-Path -LiteralPath ([string]$setting.Path))) {
            New-Item -Path ([string]$setting.Path) -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty `
            -LiteralPath ([string]$setting.Path) `
            -Name ([string]$setting.Name) `
            -PropertyType DWord `
            -Value ([int]$setting.Value) `
            -Force `
            -ErrorAction Stop | Out-Null
        Write-GuardLog ('政策 {0} 設為 {1}。' -f $setting.Name, $setting.Value)
    }
}

function Disable-DiagTrackService {
    param([Parameter(Mandatory = $true)]$Snapshot)

    if (-not [bool]$Snapshot.Existed) {
        Write-GuardLog '建立備份時沒有 DiagTrack；為避免修改備份後才新增的服務，已略過。'
        return
    }

    $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction Stop
    if ($null -eq $serviceInfo) {
        Write-GuardLog 'DiagTrack 在備份後已不存在，略過且不自行重建。'
        return
    }

    $service = Get-Service -Name 'DiagTrack' -ErrorAction Stop
    Set-Service -Name 'DiagTrack' -StartupType Disabled -ErrorAction Stop
    $service.Refresh()
    if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        Stop-Service -Name 'DiagTrack' -ErrorAction Stop
    }
    Write-GuardLog 'DiagTrack 服務已停止並設為停用。'
}

function Disable-TelemetryTasks {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        $Snapshots
    )

    $snapshotsToApply = @($Snapshots)
    foreach ($snapshot in $snapshotsToApply) {
        $task = Find-ScheduledTaskExact `
            -TaskPath ([string]$snapshot.TaskPath) `
            -TaskName ([string]$snapshot.TaskName)
        if ($null -eq $task) {
            Write-GuardLog ('排程在備份後已不存在，略過且不自行重建：{0}{1}。' -f
                $snapshot.TaskPath, $snapshot.TaskName)
            continue
        }
        Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
        $current = Get-ScheduledTask `
            -TaskPath ([string]$task.TaskPath) `
            -TaskName ([string]$task.TaskName) `
            -ErrorAction Stop
        if ([string]$current.State -eq 'Running') {
            Stop-ScheduledTask -InputObject $current -ErrorAction Stop | Out-Null
        }

        $stopped = $false
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            $current = Get-ScheduledTask `
                -TaskPath ([string]$task.TaskPath) `
                -TaskName ([string]$task.TaskName) `
                -ErrorAction Stop
            if (-not [bool]$current.Settings.Enabled -and [string]$current.State -ne 'Running') {
                $stopped = $true
                break
            }
            Start-Sleep -Milliseconds 250
        }
        if (-not $stopped) {
            throw ('排程未在時限內停止：{0}{1}' -f $task.TaskPath, $task.TaskName)
        }
        Write-GuardLog ('已停用排程 {0}{1}。' -f $task.TaskPath, $task.TaskName)
    }

    if ($snapshotsToApply.Count -eq 0) {
        Write-GuardLog '沒有找到適用的相容性或 CEIP 遙測排程。'
    }
}

function Invoke-DisableTelemetry {
    Assert-WriteAccess
    Invoke-WithOperationLock {
        $backup = Get-OrCreateBackup
        Assert-BackupCoversCurrentTargets -Backup $backup

        Write-GuardLog '開始套用關閉設定。'
        Set-DiagnosticDataPolicies
        Disable-DiagTrackService -Snapshot $backup.Service
        Disable-TelemetryTasks -Snapshots $backup.Tasks
        $status = Get-GuardStatus
        if (-not $status.Protected -or -not $status.BackupAvailable) {
            throw '寫入後驗證或受保護備份檢查未通過；請使用「還原原始設定」復原。'
        }
        Write-GuardLog '關閉設定已完成並通過驗證。'
    }
}

function Disable-OptionalServices {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Snapshots)

    # Stop dependents before their dependencies. The profile catalog keeps
    # dependency-first order so restore can run in the natural reverse direction.
    $snapshotsToApply = @($Snapshots)
    [Array]::Reverse($snapshotsToApply)
    foreach ($snapshot in $snapshotsToApply) {
        if (-not [bool]$snapshot.Existed) {
            Write-GuardLog ('建立資源備份時沒有服務 {0}；略過且不修改後來新增的服務。' -f $snapshot.Name)
            continue
        }
        $serviceInfo = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $snapshot.Name) -ErrorAction Stop
        if ($null -eq $serviceInfo) {
            Write-GuardLog ('服務 {0} 在備份後已不存在，略過且不自行重建。' -f $snapshot.Name)
            continue
        }

        $service = Get-Service -Name ([string]$snapshot.Name) -ErrorAction Stop
        Set-Service -Name ([string]$snapshot.Name) -StartupType Disabled -ErrorAction Stop
        $service.Refresh()
        if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            Stop-Service -Name ([string]$snapshot.Name) -ErrorAction Stop
        }
        Write-GuardLog ('可選服務 {0} 已停止並設為停用。' -f $snapshot.Name)
    }
}

function Assert-OptionalServicesCanStop {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Snapshots)

    $snapshotsToCheck = @($Snapshots)
    $selectedNames = @($snapshotsToCheck | ForEach-Object { [string]$_.Name })
    $selectedOrder = @{}
    for ($index = 0; $index -lt $selectedNames.Count; $index++) {
        $identity = ([string]$selectedNames[$index]).ToLowerInvariant()
        if ($selectedOrder.ContainsKey($identity)) {
            throw '可選服務快照含有重複目標，已停止處理。'
        }
        $selectedOrder[$identity] = $index
    }

    for ($index = 0; $index -lt $snapshotsToCheck.Count; $index++) {
        $snapshot = $snapshotsToCheck[$index]
        if (-not [bool]$snapshot.Existed) {
            continue
        }
        $service = Get-Service -Name ([string]$snapshot.Name) -ErrorAction Stop
        foreach ($dependent in @($service.DependentServices)) {
            $dependentIdentity = ([string]$dependent.Name).ToLowerInvariant()
            if ($selectedOrder.ContainsKey($dependentIdentity) -and
                [int]$selectedOrder[$dependentIdentity] -le $index) {
                throw ('內建服務順序無法安全處理 {0} 對 {1} 的相依關係，已停止處理。' -f
                    $snapshot.Name, $dependent.Name)
            }
        }
        $blockingDependents = @(
            $service.DependentServices |
                Where-Object {
                    $_.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped -and
                    $selectedNames -notcontains [string]$_.Name
                } |
                ForEach-Object { [string]$_.Name }
        )
        if ($blockingDependents.Count -gt 0) {
            throw ('服務 {0} 仍有未勾選且正在使用中的相依服務：{1}。為避免連帶中斷，沒有套用任何可選項目。' -f
                $snapshot.Name, ($blockingDependents -join ', '))
        }
    }
}

function Assert-OptionalDisableMatchesBackup {
    param([Parameter(Mandatory = $true)]$Backup)

    foreach ($snapshot in @($Backup.Services)) {
        $current = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $snapshot.Name) -ErrorAction Stop
        if (-not [bool]$snapshot.Existed) {
            if ($null -ne $current) {
                throw ('服務 {0} 在備份後新增，未被修改；請先還原並重新建立資源備份。' -f $snapshot.Name)
            }
            continue
        }
        if ($null -eq $current) {
            continue
        }
        if ([string]$current.State -ne 'Stopped' -or [string]$current.StartMode -ne 'Disabled') {
            throw ('可選服務 {0} 未完全停止或停用。' -f $snapshot.Name)
        }
    }

    foreach ($snapshot in @($Backup.Tasks)) {
        $current = Find-ScheduledTaskExact -TaskPath ([string]$snapshot.TaskPath) -TaskName ([string]$snapshot.TaskName)
        if (-not [bool]$snapshot.Existed) {
            if ($null -ne $current) {
                throw ('排程 {0}{1} 在備份後新增，未被修改；請先還原並重新建立資源備份。' -f
                    $snapshot.TaskPath, $snapshot.TaskName)
            }
            continue
        }
        if ($null -eq $current) {
            continue
        }
        if ([bool]$current.Settings.Enabled -or [string]$current.State -eq 'Running') {
            throw ('可選排程仍在啟用或執行：{0}{1}。' -f $snapshot.TaskPath, $snapshot.TaskName)
        }
    }
}

function Invoke-DisableOptionalProfiles {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ProfileIds)

    Assert-WriteAccess
    $resolved = @(Resolve-OptionalProfileIds -ProfileIds $ProfileIds)
    if ($resolved.Count -eq 0) {
        return
    }

    Invoke-WithOperationLock {
        $backup = Get-OrCreateOptionalBackup -ProfileIds $resolved
        Assert-OptionalBackupCoversSelection -Backup $backup -ProfileIds $resolved
        Assert-OptionalServicesCanStop -Snapshots $backup.Services
        Write-GuardLog ('開始套用資源最佳化選項：{0}。' -f ($resolved -join ', '))

        $tasksToDisable = @($backup.Tasks | Where-Object { [bool]$_.Existed })
        Disable-TelemetryTasks -Snapshots $tasksToDisable
        Disable-OptionalServices -Snapshots $backup.Services
        Assert-OptionalDisableMatchesBackup -Backup $backup
        $null = Read-OptionalBackupObject
        Write-GuardLog '資源最佳化選項已完成並通過驗證。'
    }
}

function Invoke-DisableConfiguration {
    param([AllowEmptyCollection()][string[]]$ProfileIds = @())

    Assert-WriteAccess
    $resolved = @(Resolve-OptionalProfileIds -ProfileIds $ProfileIds)
    Invoke-WithOperationLock {
        Invoke-DisableTelemetry
        if ($resolved.Count -gt 0) {
            Invoke-DisableOptionalProfiles -ProfileIds $resolved
        }
    }
}

function Restore-ServiceFromBackup {
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Warnings
    )

    if (-not [bool]$Snapshot.Existed) {
        $newService = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction Stop
        if ($null -ne $newService) {
            $message = 'Windows 在備份後新增了 DiagTrack；舊備份未涵蓋其原始狀態，因此保持不變。'
            $Warnings.Add($message)
            Write-GuardLog $message
        }
        return
    }

    $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction Stop
    if ($null -eq $serviceInfo) {
        $message = 'Windows 已移除備份中的 DiagTrack 服務；工具不會自行重建服務，已略過。'
        $Warnings.Add($message)
        Write-GuardLog $message
        return
    }
    $service = Get-Service -Name 'DiagTrack' -ErrorAction Stop

    $startupType = switch ([string]$Snapshot.StartMode) {
        'Auto' { 'Automatic' }
        'Manual' { 'Manual' }
        'Disabled' { 'Disabled' }
        default { 'Manual' }
    }
    if ([string]$Snapshot.State -eq 'Running' -and $startupType -eq 'Disabled') {
        # A service can legitimately be running while its future startup is disabled.
        # Temporarily make it startable, restore the running state, then disable it again.
        Set-Service -Name 'DiagTrack' -StartupType Manual -ErrorAction Stop
        $service.Refresh()
        if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
            Start-Service -Name 'DiagTrack' -ErrorAction Stop
        }
        Set-Service -Name 'DiagTrack' -StartupType Disabled -ErrorAction Stop
    }
    else {
        Set-Service -Name 'DiagTrack' -StartupType $startupType -ErrorAction Stop
        $service.Refresh()
        if ([string]$Snapshot.State -eq 'Running') {
            if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
                Start-Service -Name 'DiagTrack' -ErrorAction Stop
            }
        }
        elseif ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            Stop-Service -Name 'DiagTrack' -ErrorAction Stop
        }
    }

    if ($Snapshot.PSObject.Properties.Name -contains 'DelayedAutoStart') {
        Set-RegistryValueFromSnapshot -Snapshot $Snapshot.DelayedAutoStart
    }

    Write-GuardLog ('已還原 {0} 服務：啟動方式 {1}，原狀態 {2}。' -f $Snapshot.Name, $Snapshot.StartMode, $Snapshot.State)
}

function Restore-TasksFromBackup {
    param(
        [Parameter(Mandatory = $true)]$Snapshots,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Warnings
    )

    foreach ($snapshot in @($Snapshots)) {
        $task = Find-ScheduledTaskExact `
            -TaskPath ([string]$snapshot.TaskPath) `
            -TaskName ([string]$snapshot.TaskName)

        if ($null -eq $task) {
            $message = 'Windows 已移除備份中的排程；工具不會自行重建，已略過：{0}{1}。' -f
                $snapshot.TaskPath, $snapshot.TaskName
            $Warnings.Add($message)
            Write-GuardLog $message
            continue
        }

        if ([bool]$snapshot.Enabled) {
            Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
        }
        else {
            Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
        }
        Write-GuardLog ('已還原排程 {0}{1}，Enabled={2}。' -f $snapshot.TaskPath, $snapshot.TaskName, $snapshot.Enabled)
    }
}

function Assert-RestoreMatchesBackup {
    param([Parameter(Mandatory = $true)]$Backup)

    foreach ($snapshot in @($Backup.RegistryValues)) {
        $current = Get-RegistryValueSnapshot -Path ([string]$snapshot.Path) -Name ([string]$snapshot.Name)
        if ([bool]$current.Existed -ne [bool]$snapshot.Existed) {
            throw ('還原驗證失敗：政策值 {0} 的存在狀態不同。' -f $snapshot.Name)
        }
        if ([bool]$snapshot.Existed -and
            ([string]$current.Kind -ine [string]$snapshot.Kind -or
                [int64]$current.Value -ne [int64]$snapshot.Value)) {
            throw ('還原驗證失敗：政策值 {0} 的型別或內容不同。' -f $snapshot.Name)
        }
    }

    foreach ($snapshot in @($Backup.Tasks)) {
        $task = Find-ScheduledTaskExact `
            -TaskPath ([string]$snapshot.TaskPath) `
            -TaskName ([string]$snapshot.TaskName)
        if ($null -eq $task) {
            continue
        }
        if ([bool]$task.Settings.Enabled -ne [bool]$snapshot.Enabled) {
            throw ('還原驗證失敗：排程 {0}{1} 的 Enabled 狀態不同。' -f $snapshot.TaskPath, $snapshot.TaskName)
        }
    }

    $serviceNow = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction Stop
    if (-not [bool]$Backup.Service.Existed) {
        # A service added by Windows after the baseline was created was never
        # modified under that baseline, so it must be left untouched.
        return
    }
    if ($null -eq $serviceNow) {
        # Do not recreate a Windows service that the operating system removed.
        return
    }
    if ([string]$serviceNow.State -ne [string]$Backup.Service.State -or
        [string]$serviceNow.StartMode -ne [string]$Backup.Service.StartMode) {
        throw '還原驗證失敗：DiagTrack 的狀態或啟動方式不同。'
    }
    $delayedNow = Get-RegistryValueSnapshot `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack' `
        -Name 'DelayedAutoStart'
    $delayedBackup = $Backup.Service.DelayedAutoStart
    if ([bool]$delayedNow.Existed -ne [bool]$delayedBackup.Existed -or
        ([bool]$delayedBackup.Existed -and [int64]$delayedNow.Value -ne [int64]$delayedBackup.Value)) {
        throw '還原驗證失敗：DiagTrack 的延遲啟動設定不同。'
    }
}

function Archive-ActiveBackup {
    Ensure-StateRoot
    Assert-SecureAcl -Path $script:BackupPath -Directory $false
    $archiveName = 'backup-restored-{0}-{1}.json' -f
        ([DateTime]::Now.ToString('yyyyMMdd-HHmmss')),
        [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $archivePath = Join-Path $script:StateRoot $archiveName
    [IO.File]::Move($script:BackupPath, $archivePath)
    Assert-SecureAcl -Path $archivePath -Directory $false
    return $archivePath
}

function Invoke-RestoreTelemetry {
    Assert-WriteAccess
    return (Invoke-WithOperationLock {
        $backup = Read-BackupObject
        $warnings = New-Object System.Collections.Generic.List[string]

        Write-GuardLog '開始還原原始設定。'
        $backupTaskIds = @(
            @($backup.Tasks) | ForEach-Object {
                ('{0}|{1}' -f $_.TaskPath, $_.TaskName).ToLowerInvariant()
            }
        )
        foreach ($currentTask in @(Get-TargetScheduledTasks)) {
            $currentTaskId = ('{0}|{1}' -f $currentTask.TaskPath, $currentTask.TaskName).ToLowerInvariant()
            if ($backupTaskIds -notcontains $currentTaskId) {
                $message = 'Windows 在備份後新增了排程；舊備份未涵蓋其原始狀態，因此保持不變：{0}{1}。' -f
                    $currentTask.TaskPath, $currentTask.TaskName
                $warnings.Add($message)
                Write-GuardLog $message
            }
        }
        foreach ($snapshot in @($backup.RegistryValues)) {
            Set-RegistryValueFromSnapshot -Snapshot $snapshot
            Write-GuardLog ('已還原政策值 {0}。' -f $snapshot.Name)
        }
        Restore-TasksFromBackup -Snapshots $backup.Tasks -Warnings $warnings
        Restore-ServiceFromBackup -Snapshot $backup.Service -Warnings $warnings
        Assert-RestoreMatchesBackup -Backup $backup
        $archivePath = Archive-ActiveBackup
        if ($warnings.Count -eq 0) {
            Write-GuardLog ('原始設定已還原並通過驗證；備份封存於 {0}。' -f $archivePath)
        }
        else {
            Write-GuardLog ('仍存在的原始目標已還原並通過驗證；Windows 更新後的差異共 {0} 項，備份封存於 {1}。' -f
                $warnings.Count, $archivePath)
        }
        return [pscustomobject][ordered]@{
            ArchivePath = $archivePath
            Warnings = @($warnings)
        }
    })
}

function Restore-OptionalServiceFromBackup {
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Warnings
    )

    $serviceInfo = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $Snapshot.Name) -ErrorAction Stop
    if (-not [bool]$Snapshot.Existed) {
        if ($null -ne $serviceInfo) {
            $message = 'Windows 在資源備份後新增了服務 {0}；因舊備份沒有其原始狀態，保持不變。' -f $Snapshot.Name
            $Warnings.Add($message)
            Write-GuardLog $message
        }
        return
    }
    if ($null -eq $serviceInfo) {
        $message = 'Windows 已移除備份中的服務 {0}；工具不會自行重建，已略過。' -f $Snapshot.Name
        $Warnings.Add($message)
        Write-GuardLog $message
        return
    }

    $service = Get-Service -Name ([string]$Snapshot.Name) -ErrorAction Stop
    $startupType = switch ([string]$Snapshot.StartMode) {
        'Auto' { 'Automatic' }
        'Manual' { 'Manual' }
        'Disabled' { 'Disabled' }
        default { throw ('不支援的服務啟動方式：{0}。' -f $Snapshot.StartMode) }
    }

    if ([string]$Snapshot.State -eq 'Running' -and $startupType -eq 'Disabled') {
        Set-Service -Name ([string]$Snapshot.Name) -StartupType Manual -ErrorAction Stop
        $service.Refresh()
        if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
            Start-Service -Name ([string]$Snapshot.Name) -ErrorAction Stop
        }
        Set-Service -Name ([string]$Snapshot.Name) -StartupType Disabled -ErrorAction Stop
    }
    else {
        Set-Service -Name ([string]$Snapshot.Name) -StartupType $startupType -ErrorAction Stop
        $service.Refresh()
        if ([string]$Snapshot.State -eq 'Running') {
            if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
                Start-Service -Name ([string]$Snapshot.Name) -ErrorAction Stop
            }
        }
        elseif ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            Stop-Service -Name ([string]$Snapshot.Name) -ErrorAction Stop
        }
    }
    Set-RegistryValueFromSnapshot -Snapshot $Snapshot.DelayedAutoStart
    Write-GuardLog ('已還原可選服務 {0}：啟動方式 {1}，原狀態 {2}。' -f
        $Snapshot.Name, $Snapshot.StartMode, $Snapshot.State)
}

function Restore-OptionalTasksFromBackup {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Snapshots,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Warnings
    )

    foreach ($snapshot in @($Snapshots)) {
        $task = Find-ScheduledTaskExact -TaskPath ([string]$snapshot.TaskPath) -TaskName ([string]$snapshot.TaskName)
        if (-not [bool]$snapshot.Existed) {
            if ($null -ne $task) {
                $message = 'Windows 在資源備份後新增了排程；因舊備份沒有其原始狀態，保持不變：{0}{1}。' -f
                    $snapshot.TaskPath, $snapshot.TaskName
                $Warnings.Add($message)
                Write-GuardLog $message
            }
            continue
        }
        if ($null -eq $task) {
            $message = 'Windows 已移除備份中的排程；工具不會自行重建，已略過：{0}{1}。' -f
                $snapshot.TaskPath, $snapshot.TaskName
            $Warnings.Add($message)
            Write-GuardLog $message
            continue
        }
        if ([bool]$snapshot.Enabled) {
            Enable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
        }
        else {
            Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
        }
        Write-GuardLog ('已還原可選排程 {0}{1}，Enabled={2}。' -f
            $snapshot.TaskPath, $snapshot.TaskName, $snapshot.Enabled)
    }
}

function Assert-OptionalRestoreMatchesBackup {
    param([Parameter(Mandatory = $true)]$Backup)

    foreach ($snapshot in @($Backup.Services)) {
        $current = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $snapshot.Name) -ErrorAction Stop
        if (-not [bool]$snapshot.Existed -or $null -eq $current) {
            continue
        }
        if ([string]$current.State -ne [string]$snapshot.State -or
            [string]$current.StartMode -ne [string]$snapshot.StartMode) {
            throw ('資源還原驗證失敗：服務 {0} 的狀態或啟動方式不同。' -f $snapshot.Name)
        }
        $delayedNow = Get-RegistryValueSnapshot `
            -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\{0}' -f $snapshot.Name) `
            -Name 'DelayedAutoStart'
        $delayedBackup = $snapshot.DelayedAutoStart
        if ([bool]$delayedNow.Existed -ne [bool]$delayedBackup.Existed -or
            ([bool]$delayedBackup.Existed -and
                ([string]$delayedNow.Kind -ine [string]$delayedBackup.Kind -or
                    [int64]$delayedNow.Value -ne [int64]$delayedBackup.Value))) {
            throw ('資源還原驗證失敗：服務 {0} 的延遲啟動設定不同。' -f $snapshot.Name)
        }
    }

    foreach ($snapshot in @($Backup.Tasks)) {
        $task = Find-ScheduledTaskExact -TaskPath ([string]$snapshot.TaskPath) -TaskName ([string]$snapshot.TaskName)
        if (-not [bool]$snapshot.Existed -or $null -eq $task) {
            continue
        }
        if ([bool]$task.Settings.Enabled -ne [bool]$snapshot.Enabled) {
            throw ('資源還原驗證失敗：排程 {0}{1} 的 Enabled 狀態不同。' -f
                $snapshot.TaskPath, $snapshot.TaskName)
        }
    }
}

function Archive-OptionalBackup {
    Ensure-StateRoot
    Assert-SecureAcl -Path $script:OptionalBackupPath -Directory $false
    $archiveName = 'resource-backup-restored-{0}-{1}.json' -f
        ([DateTime]::Now.ToString('yyyyMMdd-HHmmss')),
        [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $archivePath = Join-Path $script:StateRoot $archiveName
    [IO.File]::Move($script:OptionalBackupPath, $archivePath)
    Assert-SecureAcl -Path $archivePath -Directory $false
    return $archivePath
}

function Invoke-RestoreOptionalProfiles {
    Assert-WriteAccess
    return (Invoke-WithOperationLock {
        $backup = Read-OptionalBackupObject
        $warnings = New-Object System.Collections.Generic.List[string]
        Write-GuardLog '開始還原資源最佳化原始設定。'

        Restore-OptionalTasksFromBackup -Snapshots $backup.Tasks -Warnings $warnings
        foreach ($snapshot in @($backup.Services)) {
            Restore-OptionalServiceFromBackup -Snapshot $snapshot -Warnings $warnings
        }
        Assert-OptionalRestoreMatchesBackup -Backup $backup
        $archivePath = Archive-OptionalBackup
        Write-GuardLog ('資源最佳化原始設定已還原；備份封存於 {0}。' -f $archivePath)
        return [pscustomobject][ordered]@{
            ArchivePath = $archivePath
            Warnings = @($warnings)
        }
    })
}

function Invoke-RestoreAvailableBackups {
    Assert-WriteAccess
    return (Invoke-WithOperationLock {
        $optionalRestoreResult = $null
        $telemetryRestoreResult = $null
        $errors = New-Object System.Collections.Generic.List[string]
        $attemptedAny = $false

        if (Test-Path -LiteralPath $script:OptionalBackupPath) {
            $attemptedAny = $true
            try {
                $optionalRestoreResult = Invoke-RestoreOptionalProfiles
            }
            catch {
                $errors.Add(('資源最佳化備份：{0}' -f $_.Exception.Message))
            }
        }
        if (Test-Path -LiteralPath $script:BackupPath) {
            $attemptedAny = $true
            try {
                $telemetryRestoreResult = Invoke-RestoreTelemetry
            }
            catch {
                $errors.Add(('診斷遙測備份：{0}' -f $_.Exception.Message))
            }
        }
        if (-not $attemptedAny) {
            throw '找不到任何可還原的備份。'
        }

        $restoredCount = 0
        if ($null -ne $telemetryRestoreResult) { $restoredCount++ }
        if ($null -ne $optionalRestoreResult) { $restoredCount++ }

        return [pscustomobject][ordered]@{
            TelemetryRestore = $telemetryRestoreResult
            OptionalRestore = $optionalRestoreResult
            RestoredCount = [int]$restoredCount
            Errors = @($errors)
        }
    })
}

function Get-CurrentPolicyValues {
    return @(
        foreach ($setting in @(Get-DesiredPolicySettings)) {
            $snapshot = Get-RegistryValueSnapshot -Path ([string]$setting.Path) -Name ([string]$setting.Name)
            [pscustomobject][ordered]@{
                Path = [string]$setting.Path
                Name = [string]$setting.Name
                Expected = [int]$setting.Value
                Exists = [bool]$snapshot.Existed
                Value = $snapshot.Value
                Matches = [bool]($snapshot.Existed -and ([int]$snapshot.Value -eq [int]$setting.Value))
            }
        }
    )
}

function Get-OptionalProfileStatuses {
    param([AllowEmptyCollection()][string[]]$ProfileIds = @())

    $profiles = if (@($ProfileIds).Count -eq 0) {
        @(Get-OptionalOptimizationProfiles)
    }
    else {
        @(Get-SelectedOptionalProfiles -ProfileIds $ProfileIds)
    }

    $serviceMap = @{}
    foreach ($service in @(Get-CimInstance Win32_Service -ErrorAction Stop)) {
        $serviceMap[[string]$service.Name] = $service
    }
    $processServiceMap = @{}
    foreach ($service in @($serviceMap.Values)) {
        if ([uint32]$service.ProcessId -eq 0) {
            continue
        }
        $processKey = ([uint32]$service.ProcessId).ToString()
        if (-not $processServiceMap.ContainsKey($processKey)) {
            $processServiceMap[$processKey] = New-Object System.Collections.Generic.List[string]
        }
        $processServiceMap[$processKey].Add([string]$service.Name)
    }
    $processStatusMap = @{}
    $candidateProcessKeys = @(
        foreach ($serviceName in $script:AllowedOptionalServiceNames) {
            if ($serviceMap.ContainsKey([string]$serviceName)) {
                $candidateService = $serviceMap[[string]$serviceName]
                if ([uint32]$candidateService.ProcessId -gt 0) {
                    ([uint32]$candidateService.ProcessId).ToString()
                }
            }
        }
    ) | Sort-Object -Unique
    foreach ($processKey in $candidateProcessKeys) {
        try {
            $process = Get-Process -Id ([int]$processKey) -ErrorAction Stop
            $processStatusMap[$processKey] = [pscustomobject][ordered]@{
                Available = $true
                Name = [string]$process.ProcessName
                WorkingSetMB = [Math]::Round($process.WorkingSet64 / 1MB, 1)
            }
        }
        catch {
            $processStatusMap[$processKey] = [pscustomobject][ordered]@{
                Available = $false
                Name = ''
                WorkingSetMB = 0.0
            }
        }
    }
    $taskMap = @{}
    foreach ($task in @(Get-ScheduledTask -ErrorAction Stop)) {
        $identity = ('{0}|{1}' -f $task.TaskPath, $task.TaskName).ToLowerInvariant()
        $taskMap[$identity] = $task
    }

    return @(
        foreach ($profile in $profiles) {
            $services = @(
                foreach ($serviceName in @($profile.Services)) {
                    $service = if ($serviceMap.ContainsKey([string]$serviceName)) { $serviceMap[[string]$serviceName] } else { $null }
                    $workingSetMb = 0.0
                    $measurementAvailable = $true
                    $hostProcessName = ''
                    if ($null -ne $service -and [string]$service.State -eq 'Running' -and
                        [uint32]$service.ProcessId -eq 0) {
                        $measurementAvailable = $false
                    }
                    if ($null -ne $service -and [uint32]$service.ProcessId -gt 0) {
                        $processKey = ([uint32]$service.ProcessId).ToString()
                        if ($processStatusMap.ContainsKey($processKey)) {
                            $processStatus = $processStatusMap[$processKey]
                            $measurementAvailable = [bool]$processStatus.Available
                            $hostProcessName = [string]$processStatus.Name
                            $workingSetMb = [double]$processStatus.WorkingSetMB
                        }
                        else {
                            $measurementAvailable = $false
                        }
                    }
                    $hostServiceNames = @()
                    if ($null -ne $service -and [uint32]$service.ProcessId -gt 0) {
                        $processKey = ([uint32]$service.ProcessId).ToString()
                        if ($processServiceMap.ContainsKey($processKey)) {
                            $hostServiceNames = @($processServiceMap[$processKey] | Sort-Object)
                        }
                    }
                    [pscustomobject][ordered]@{
                        Name = [string]$serviceName
                        Exists = [bool]($null -ne $service)
                        DisplayName = if ($null -ne $service) { [string]$service.DisplayName } else { '' }
                        State = if ($null -ne $service) { [string]$service.State } else { 'Missing' }
                        StartMode = if ($null -ne $service) { [string]$service.StartMode } else { '' }
                        ProcessId = if ($null -ne $service) { [uint32]$service.ProcessId } else { [uint32]0 }
                        WorkingSetMB = [double]$workingSetMb
                        MeasurementAvailable = [bool]$measurementAvailable
                        HostProcessName = $hostProcessName
                        SharedHost = [bool]($hostServiceNames.Count -gt 1)
                        HostServices = @($hostServiceNames)
                        Protected = [bool](($null -eq $service) -or
                            ([string]$service.State -eq 'Stopped' -and [string]$service.StartMode -eq 'Disabled'))
                    }
                }
            )
            $tasks = @(
                foreach ($definition in @($profile.Tasks)) {
                    $identity = ('{0}|{1}' -f $definition.TaskPath, $definition.TaskName).ToLowerInvariant()
                    $task = if ($taskMap.ContainsKey($identity)) { $taskMap[$identity] } else { $null }
                    [pscustomobject][ordered]@{
                        TaskPath = [string]$definition.TaskPath
                        TaskName = [string]$definition.TaskName
                        Exists = [bool]($null -ne $task)
                        Enabled = [bool]($null -ne $task -and [bool]$task.Settings.Enabled)
                        State = if ($null -ne $task) { [string]$task.State } else { 'Missing' }
                        Protected = [bool](($null -eq $task) -or
                            (-not [bool]$task.Settings.Enabled -and [string]$task.State -ne 'Running'))
                    }
                }
            )

            $processIds = @(
                $services |
                    Where-Object { $_.Exists -and $_.ProcessId -gt 0 } |
                    ForEach-Object { [uint32]$_.ProcessId } |
                    Sort-Object -Unique
            )
            $workingSetTotal = 0.0
            foreach ($processId in $processIds) {
                $row = @($services | Where-Object { $_.ProcessId -eq $processId } | Select-Object -First 1)
                if ($row.Count -gt 0) {
                    $workingSetTotal += [double]$row[0].WorkingSetMB
                }
            }
            $available = (@($services | Where-Object { $_.Exists }).Count -gt 0) -or
                (@($tasks | Where-Object { $_.Exists }).Count -gt 0)
            $protected = (@($services | Where-Object { -not $_.Protected }).Count -eq 0) -and
                (@($tasks | Where-Object { -not $_.Protected }).Count -eq 0)

            [pscustomobject][ordered]@{
                Id = [string]$profile.Id
                Title = [string]$profile.Title
                Impact = [string]$profile.Impact
                Available = [bool]$available
                Protected = [bool]$protected
                WorkingSetMB = [Math]::Round($workingSetTotal, 1)
                MeasurementAvailable = [bool](@($services | Where-Object { -not $_.MeasurementAvailable }).Count -eq 0)
                SharedHost = [bool](@($services | Where-Object { $_.SharedHost }).Count -gt 0)
                Services = $services
                Tasks = $tasks
            }
        }
    )
}

function Get-GuardStatus {
    $service = Get-CimInstance Win32_Service -Filter "Name='DiagTrack'" -ErrorAction Stop
    $tasks = @(
        Get-TargetScheduledTasks | ForEach-Object {
            [pscustomobject][ordered]@{
                TaskPath = [string]$_.TaskPath
                TaskName = [string]$_.TaskName
                Enabled = [bool]$_.Settings.Enabled
                State = [string]$_.State
            }
        }
    )
    $policies = @(Get-CurrentPolicyValues)
    $backupAvailable = $false
    $backupError = $null
    try {
        if (Test-Path -LiteralPath $script:BackupPath -ErrorAction Stop) {
            $null = Read-BackupObject
            $backupAvailable = $true
        }
    }
    catch {
        $backupError = $_.Exception.Message
    }

    $optionalBackupAvailable = $false
    $optionalBackupError = $null
    $optionalBackupProfiles = @()
    try {
        if (Test-Path -LiteralPath $script:OptionalBackupPath -ErrorAction Stop) {
            $optionalBackup = Read-OptionalBackupObject
            $optionalBackupAvailable = $true
            $optionalBackupProfiles = @($optionalBackup.SelectedProfiles | ForEach-Object { [string]$_ })
        }
    }
    catch {
        $optionalBackupError = $_.Exception.Message
    }
    $optionalProfileStatuses = @(Get-OptionalProfileStatuses)

    $serviceProtected = ($null -eq $service) -or
        ($service.State -eq 'Stopped' -and $service.StartMode -eq 'Disabled')
    $tasksProtected = (@($tasks | Where-Object { $_.Enabled -or $_.State -eq 'Running' }).Count -eq 0)
    $policiesProtected = (@($policies | Where-Object { -not $_.Matches }).Count -eq 0)

    return [pscustomobject][ordered]@{
        AppVersion = $script:AppVersion
        Windows = Get-WindowsInfo
        Protected = [bool]($serviceProtected -and $tasksProtected -and $policiesProtected)
        BackupAvailable = [bool]$backupAvailable
        BackupError = $backupError
        OptionalBackupAvailable = [bool]$optionalBackupAvailable
        OptionalBackupError = $optionalBackupError
        OptionalBackupProfiles = @($optionalBackupProfiles)
        AnyBackupAvailable = [bool]($backupAvailable -or $optionalBackupAvailable)
        Service = if ($null -eq $service) {
            [pscustomobject][ordered]@{ Exists = $false }
        }
        else {
            [pscustomobject][ordered]@{
                Exists = $true
                Name = 'DiagTrack'
                DisplayName = [string]$service.DisplayName
                State = [string]$service.State
                StartMode = [string]$service.StartMode
                Protected = [bool]$serviceProtected
            }
        }
        Policies = $policies
        Tasks = $tasks
        OptionalProfiles = $optionalProfileStatuses
    }
}

function Format-GuardStatus {
    param([Parameter(Mandatory = $true)]$Status)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('整體狀態：{0}' -f $(if ($Status.Protected) { '主要 Windows 遙測元件已關閉' } else { '尚未完整套用關閉設定' })))
    $lines.Add('')
    $lines.Add(('系統：{0}（{1}，Build {2}）' -f $Status.Windows.ProductName, $Status.Windows.EditionId, $Status.Windows.Build))

    if (-not $Status.Windows.SupportsManagementPolicies) {
        $lines.Add('版本提醒：此 Windows 版本不在官方診斷資料管理政策的支援清單內。')
        $lines.Add('本工具只會停止並停用影片所示服務與遙測排程。')
    }
    elseif (-not $Status.Windows.SupportsDiagnosticDataOff) {
        $lines.Add('版本提醒：此版本不支援官方「診斷資料關閉」等級；最低是「必要診斷資料」（政策值 1）。')
        $lines.Add('本工具仍會停止並停用影片所示服務與遙測排程。')
    }

    $lines.Add('')
    if (-not $Status.Service.Exists) {
        $lines.Add('DiagTrack 服務：此版本不存在')
    }
    else {
        $lines.Add(('DiagTrack 服務：{0}／啟動方式 {1}{2}' -f
                $Status.Service.State,
                $Status.Service.StartMode,
                $(if ($Status.Service.Protected) { '（已關閉）' } else { '（仍可能運作）' })))
    }

    $lines.Add('')
    $lines.Add('診斷資料政策：')
    if (@($Status.Policies).Count -eq 0) {
        $lines.Add('  此版本沒有適用的官方管理政策。')
    }
    else {
        foreach ($policy in @($Status.Policies)) {
            $displayValue = if ($policy.Exists) { [string]$policy.Value } else { '未設定' }
            $mark = if ($policy.Matches) { 'OK' } else { '待處理' }
            $lines.Add(('  [{0}] {1} = {2}（目標 {3}）' -f $mark, $policy.Name, $displayValue, $policy.Expected))
        }
    }

    $lines.Add('')
    $lines.Add('相容性／CEIP 排程：')
    if (@($Status.Tasks).Count -eq 0) {
        $lines.Add('  此版本沒有找到目標排程。')
    }
    else {
        foreach ($task in @($Status.Tasks)) {
            $mark = if ($task.State -eq 'Running') { '執行中' } elseif ($task.Enabled) { '啟用' } else { '停用' }
            $lines.Add(('  [{0}] {1}{2}' -f $mark, $task.TaskPath, $task.TaskName))
        }
    }

    $lines.Add('')
    $lines.Add('可勾選的資源最佳化候選：')
    foreach ($profile in @($Status.OptionalProfiles)) {
        $mark = if (-not $profile.Available) {
            '此系統無此項目'
        }
        elseif ($profile.Protected) {
            '已停用'
        }
        else {
            '可選'
        }
        $memoryNote = if ([bool]$profile.SharedHost) {
            '；含共用宿主，只能視為總值'
        }
        else {
            ''
        }
        $memoryDisplay = if ([bool]$profile.MeasurementAvailable) {
            '{0:N1} MB' -f [double]$profile.WorkingSetMB
        }
        else {
            '無法讀取'
        }
        $lines.Add(('  [{0}] {1}（相關宿主目前 {2}{3}）' -f
                $mark, $profile.Title, $memoryDisplay, $memoryNote))
    }

    $lines.Add('')
    $backupDisplay = if ($Status.BackupAvailable) {
        $script:BackupPath
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Status.BackupError)) {
        '不可用（' + [string]$Status.BackupError + '）'
    }
    else {
        '尚未建立'
    }
    $lines.Add(('遙測還原備份：{0}' -f $backupDisplay))
    $optionalBackupDisplay = if ($Status.OptionalBackupAvailable) {
        '{0}（{1}）' -f $script:OptionalBackupPath, (@($Status.OptionalBackupProfiles) -join ', ')
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Status.OptionalBackupError)) {
        '不可用（' + [string]$Status.OptionalBackupError + '）'
    }
    else {
        '尚未建立'
    }
    $lines.Add(('資源最佳化還原備份：{0}' -f $optionalBackupDisplay))
    $lines.Add('')
    $lines.Add('範圍說明：不變更 Windows Update、Microsoft Defender、網路連線核心、音效、hosts 或防火牆。')
    $lines.Add('只有勾選「額外遙測、錯誤回報與意見回饋」時，才會停用 Windows Error Reporting 服務。')
    $lines.Add('顯示的 MB 是服務宿主行程當下工作集，不保證全部可釋放；排程主要造成間歇性尖峰。')
    $lines.Add('此工具針對 Windows 診斷遙測，不代表阻止 Edge、Office 或其他 Microsoft 應用程式的所有連線。')

    return ($lines -join [Environment]::NewLine)
}

function Get-PreviewText {
    param([AllowEmptyCollection()][string[]]$ProfileIds = @())

    $resolved = @(Resolve-OptionalProfileIds -ProfileIds $ProfileIds)
    $taskNames = @(Get-TargetScheduledTasks | ForEach-Object { '{0}{1}' -f $_.TaskPath, $_.TaskName })
    $allowSetting = @(
        Get-DesiredPolicySettings | Where-Object { $_.Name -eq 'AllowTelemetry' }
    )
    $policyLine = if ($allowSetting.Count -gt 0) {
        '3. 將 AllowTelemetry 設為此 Windows 版本的官方最低值 {0}，並退出 CEIP。' -f $allowSetting[0].Value
    }
    else {
        '3. 此 Windows 版本沒有適用的官方診斷資料／CEIP 管理政策，略過政策寫入。'
    }
    $lines = @(
        '將執行下列動作（目前只是預覽，沒有變更設定）：',
        '',
        '1. 備份 DiagTrack、診斷資料政策與目標排程目前狀態。',
        '2. 停止 DiagTrack，並把啟動方式設為「停用」。',
        $policyLine,
        '4. 在支援版本限制額外診斷記錄與完整傾印收集。',
        '5. 停用下列 Microsoft 相容性／CEIP 排程：'
    )
    if ($taskNames.Count -eq 0) {
        $lines += '   （此版本沒有找到目標排程）'
    }
    else {
        $lines += @($taskNames | ForEach-Object { '   - ' + $_ })
    }
    $lines += @(
        '',
        '「還原原始設定」會使用本次套用前的受保護本機備份。'
    )
    if ($resolved.Count -gt 0) {
        $lines += @('', '另外會備份並停用下列已勾選候選：')
        foreach ($profile in @(Get-SelectedOptionalProfiles -ProfileIds $resolved)) {
            $lines += ('- {0}：{1}' -f $profile.Title, $profile.Impact)
        }
    }
    else {
        $lines += @('', '沒有選取額外的資源最佳化候選。')
    }
    return ($lines -join [Environment]::NewLine)
}

function Show-GuardGui {
    Assert-WriteAccess

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $createdNew = $false
    $mutex = [System.Threading.Mutex]::new($true, 'Global\TelemetryGuard.Gui', [ref]$createdNew)
    try {
        if (-not $createdNew) {
            [System.Windows.Forms.MessageBox]::Show(
                'Windows 遙測與資源最佳化工具已在執行中。',
                'TelemetryGuard',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'TelemetryGuard ' + $script:AppVersion + ' — Windows 遙測與資源最佳化'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(920, 780)
    $form.MinimumSize = New-Object System.Drawing.Size(850, 720)
    $form.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10)
    $form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Windows 遙測與資源最佳化'
    $title.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 18, [System.Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(24, 20)
    $form.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = '遙測核心會依影片與官方政策處理；其他服務只會在「可選資源最佳化」頁面勾選後停用。'
    $subtitle.AutoSize = $false
    $subtitle.Location = New-Object System.Drawing.Point(27, 62)
    $subtitle.Size = New-Object System.Drawing.Size(850, 46)
    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
    $form.Controls.Add($subtitle)

    $notice = New-Object System.Windows.Forms.Label
    $notice.Text = '不會自動判定所有高記憶體服務；僅操作固定白名單。Defender、Windows Update、網路連線與音效核心不在清單內。'
    $notice.AutoSize = $false
    $notice.Location = New-Object System.Drawing.Point(27, 106)
    $notice.Size = New-Object System.Drawing.Size(850, 38)
    $notice.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
    $form.Controls.Add($notice)

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Location = New-Object System.Drawing.Point(28, 148)
    $tabControl.Size = New-Object System.Drawing.Size(850, 510)
    $tabControl.Anchor = 'Top,Bottom,Left,Right'
    $form.Controls.Add($tabControl)

    $statusTab = New-Object System.Windows.Forms.TabPage
    $statusTab.Text = '目前狀態'
    $tabControl.TabPages.Add($statusTab)

    $optionsTab = New-Object System.Windows.Forms.TabPage
    $optionsTab.Text = '可選資源最佳化'
    $tabControl.TabPages.Add($optionsTab)

    $statusBox = New-Object System.Windows.Forms.RichTextBox
    $statusBox.ReadOnly = $true
    $statusBox.DetectUrls = $false
    $statusBox.BackColor = [System.Drawing.Color]::White
    $statusBox.BorderStyle = 'FixedSingle'
    $statusBox.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 9.5)
    $statusBox.Dock = 'Fill'
    $statusTab.Controls.Add($statusBox)

    $optionsHelp = New-Object System.Windows.Forms.Label
    $optionsHelp.Text = '只勾選確定不用的功能。MB 是宿主目前工作集；共用宿主是總值，不會被門檻按鈕自動勾選。'
    $optionsHelp.AutoSize = $false
    $optionsHelp.Location = New-Object System.Drawing.Point(10, 10)
    $optionsHelp.Size = New-Object System.Drawing.Size(805, 42)
    $optionsHelp.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
    $optionsTab.Controls.Add($optionsHelp)

    $thresholdLabel = New-Object System.Windows.Forms.Label
    $thresholdLabel.Text = '高記憶體門檻：'
    $thresholdLabel.AutoSize = $true
    $thresholdLabel.Location = New-Object System.Drawing.Point(12, 58)
    $optionsTab.Controls.Add($thresholdLabel)

    $thresholdSelector = New-Object System.Windows.Forms.NumericUpDown
    $thresholdSelector.Minimum = 10
    $thresholdSelector.Maximum = 2048
    $thresholdSelector.Increment = 10
    $thresholdSelector.Value = 50
    $thresholdSelector.Location = New-Object System.Drawing.Point(132, 54)
    $thresholdSelector.Size = New-Object System.Drawing.Size(82, 30)
    $thresholdSelector.TextAlign = 'Right'
    $optionsTab.Controls.Add($thresholdSelector)

    $thresholdUnit = New-Object System.Windows.Forms.Label
    $thresholdUnit.Text = 'MB'
    $thresholdUnit.AutoSize = $true
    $thresholdUnit.Location = New-Object System.Drawing.Point(220, 58)
    $optionsTab.Controls.Add($thresholdUnit)

    $selectHighButton = New-Object System.Windows.Forms.Button
    $selectHighButton.Text = '勾選目前 ≥ 50 MB'
    $selectHighButton.Location = New-Object System.Drawing.Point(630, 52)
    $selectHighButton.Size = New-Object System.Drawing.Size(180, 32)
    $selectHighButton.Anchor = 'Top,Right'
    $optionsTab.Controls.Add($selectHighButton)

    $optionsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $optionsPanel.Location = New-Object System.Drawing.Point(8, 92)
    $optionsPanel.Size = New-Object System.Drawing.Size(815, 374)
    $optionsPanel.Anchor = 'Top,Bottom,Left,Right'
    $optionsPanel.AutoScroll = $true
    $optionsPanel.FlowDirection = 'TopDown'
    $optionsPanel.WrapContents = $false
    $optionsPanel.BackColor = [System.Drawing.Color]::White
    $optionsTab.Controls.Add($optionsPanel)

    $profileCheckboxes = @{}
    foreach ($profile in @(Get-OptionalOptimizationProfiles)) {
        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Tag = [string]$profile.Id
        $checkbox.Text = "{0}`r`n影響：{1}" -f $profile.Title, $profile.Impact
        $checkbox.AutoSize = $false
        $checkbox.Size = New-Object System.Drawing.Size(775, 62)
        $checkbox.Margin = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)
        $checkbox.UseCompatibleTextRendering = $true
        $optionsPanel.Controls.Add($checkbox)
        $profileCheckboxes[[string]$profile.Id] = $checkbox
    }

    $applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Text = '關閉遙測＋已勾選項目'
    $applyButton.Location = New-Object System.Drawing.Point(28, 675)
    $applyButton.Size = New-Object System.Drawing.Size(240, 40)
    $applyButton.Anchor = 'Bottom,Left'
    $applyButton.BackColor = [System.Drawing.Color]::FromArgb(30, 105, 210)
    $applyButton.ForeColor = [System.Drawing.Color]::White
    $applyButton.FlatStyle = 'Flat'
    $form.Controls.Add($applyButton)

    $restoreButton = New-Object System.Windows.Forms.Button
    $restoreButton.Text = '還原原始設定'
    $restoreButton.Location = New-Object System.Drawing.Point(278, 675)
    $restoreButton.Size = New-Object System.Drawing.Size(180, 40)
    $restoreButton.Anchor = 'Bottom,Left'
    $form.Controls.Add($restoreButton)

    $refreshButton = New-Object System.Windows.Forms.Button
    $refreshButton.Text = '重新檢查'
    $refreshButton.Location = New-Object System.Drawing.Point(468, 675)
    $refreshButton.Size = New-Object System.Drawing.Size(130, 40)
    $refreshButton.Anchor = 'Bottom,Left'
    $form.Controls.Add($refreshButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = '關閉'
    $closeButton.Location = New-Object System.Drawing.Point(748, 675)
    $closeButton.Size = New-Object System.Drawing.Size(130, 40)
    $closeButton.Anchor = 'Bottom,Right'
    $form.Controls.Add($closeButton)

    $uiState = [pscustomobject]@{
        Busy = $false
        LastStatus = $null
    }
    $refreshStatus = {
        try {
            $status = Get-GuardStatus
            $uiState.LastStatus = $status
            $statusBox.Text = Format-GuardStatus -Status $status
            $lockedProfiles = @($status.OptionalBackupProfiles | ForEach-Object { [string]$_ })
            foreach ($profileStatus in @($status.OptionalProfiles)) {
                $checkbox = $profileCheckboxes[[string]$profileStatus.Id]
                $stateText = if (-not $profileStatus.Available) {
                    '此系統無此項目'
                }
                elseif ($profileStatus.Protected) {
                    '已停用'
                }
                else {
                    '目前可用'
                }
                $hostNote = if ([bool]$profileStatus.SharedHost) { '（共用宿主總值）' } else { '' }
                $memoryDisplay = if ([bool]$profileStatus.MeasurementAvailable) {
                    '{0:N1} MB' -f [double]$profileStatus.WorkingSetMB
                }
                else {
                    '無法讀取'
                }
                $checkbox.Text = "{0} — 相關宿主 {1}{2} — {3}`r`n影響：{4}" -f
                    $profileStatus.Title,
                    $memoryDisplay,
                    $hostNote,
                    $stateText,
                    $profileStatus.Impact
                if ($status.OptionalBackupAvailable) {
                    $checkbox.Checked = ($lockedProfiles -contains [string]$profileStatus.Id)
                    $checkbox.Enabled = $false
                }
                elseif (-not $uiState.Busy) {
                    $checkbox.Enabled = [bool]$profileStatus.Available
                    if (-not [bool]$profileStatus.Available) {
                        $checkbox.Checked = $false
                    }
                }
            }
            if (-not $uiState.Busy) {
                $hasBackupError = -not [string]::IsNullOrWhiteSpace([string]$status.BackupError) -or
                    -not [string]::IsNullOrWhiteSpace([string]$status.OptionalBackupError)
                $applyButton.Enabled = -not $hasBackupError
                $restoreButton.Enabled = [bool]$status.AnyBackupAvailable
                $selectHighButton.Enabled = [bool](-not $status.OptionalBackupAvailable -and -not $hasBackupError)
                $thresholdSelector.Enabled = [bool](-not $status.OptionalBackupAvailable -and -not $hasBackupError)
            }
        }
        catch {
            $uiState.LastStatus = $null
            $statusBox.Text = '狀態檢查失敗：' + $_.Exception.Message
            $applyButton.Enabled = $false
            $restoreButton.Enabled = $false
            $selectHighButton.Enabled = $false
            $thresholdSelector.Enabled = $false
            foreach ($checkbox in @($profileCheckboxes.Values)) {
                $checkbox.Enabled = $false
            }
        }
    }

    $setBusy = {
        param([bool]$Busy, [string]$Text)
        $uiState.Busy = $Busy
        $applyButton.Enabled = -not $Busy
        if ($Busy) { $restoreButton.Enabled = $false }
        $refreshButton.Enabled = -not $Busy
        $closeButton.Enabled = -not $Busy
        $selectHighButton.Enabled = $false
        $thresholdSelector.Enabled = $false
        foreach ($checkbox in @($profileCheckboxes.Values)) {
            $checkbox.Enabled = $false
        }
        if ($Busy) {
            $statusBox.Text = $Text
            $statusBox.Refresh()
        }
    }

    $thresholdSelector.Add_ValueChanged({
            $selectHighButton.Text = '勾選目前 ≥ {0} MB' -f [int]$thresholdSelector.Value
        })

    $selectHighButton.Add_Click({
            if ($uiState.Busy -or $null -eq $uiState.LastStatus -or
                $uiState.LastStatus.OptionalBackupAvailable) {
                return
            }
            $thresholdMb = [double]$thresholdSelector.Value
            foreach ($profileStatus in @($uiState.LastStatus.OptionalProfiles)) {
                if ($profileStatus.Available -and -not $profileStatus.Protected -and
                    [bool]$profileStatus.MeasurementAvailable -and
                    -not [bool]$profileStatus.SharedHost -and
                    [double]$profileStatus.WorkingSetMB -ge $thresholdMb) {
                    $profileCheckboxes[[string]$profileStatus.Id].Checked = $true
                }
            }
        })

    $applyButton.Add_Click({
            if ($uiState.Busy) { return }
            $selectedIds = @(
                Get-OptionalOptimizationProfiles |
                    Where-Object { $profileCheckboxes[[string]$_.Id].Checked } |
                    ForEach-Object { [string]$_.Id }
            )
            $optionalSummary = if ($selectedIds.Count -eq 0) {
                '額外勾選：無'
            }
            else {
                '額外勾選：' + (@(
                        Get-SelectedOptionalProfiles -ProfileIds $selectedIds |
                            ForEach-Object { $_.Title }
                    ) -join '、')
            }
            $message = "即將關閉 DiagTrack、診斷遙測／CEIP 與 Compatibility Appraiser。`r`n`r`n$optionalSummary`r`n`r`n每組設定都會先建立受保護備份；只有勾選的可選項目會被停用。是否繼續？"
            $answer = [System.Windows.Forms.MessageBox]::Show(
                $message,
                '確認套用',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }

            & $setBusy $true '正在備份並套用設定，請稍候……'
            try {
                Invoke-DisableConfiguration -ProfileIds $selectedIds
                [System.Windows.Forms.MessageBox]::Show(
                    '遙測與已勾選的資源最佳化項目已完成。若要改選其他項目，請先還原目前的資源備份。',
                    '完成',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    ('套用未完整完成：' + $_.Exception.Message + "`r`n`r`n部分項目可能已套用；已成功建立的備份仍可用來還原。"),
                    '發生錯誤',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
            finally {
                & $setBusy $false ''
                & $refreshStatus
            }
        })

    $restoreButton.Add_Click({
            if ($uiState.Busy) { return }
            $answer = [System.Windows.Forms.MessageBox]::Show(
                '將使用本次套用前的受保護本機備份，還原服務、政策與排程狀態。是否繼續？',
                '確認還原',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }

            & $setBusy $true '正在還原原始設定，請稍候……'
            try {
                $restoreResult = Invoke-RestoreAvailableBackups
                $restoreWarnings = New-Object System.Collections.Generic.List[string]
                foreach ($scopeResult in @($restoreResult.OptionalRestore, $restoreResult.TelemetryRestore)) {
                    if ($null -eq $scopeResult) { continue }
                    foreach ($warning in @($scopeResult.Warnings)) {
                        $restoreWarnings.Add([string]$warning)
                    }
                }

                $restoreSections = New-Object System.Collections.Generic.List[string]
                if ($restoreWarnings.Count -gt 0) {
                    $restoreSections.Add(
                        "Windows 更新後新增或移除的元件已安全略過：`r`n" +
                        (@($restoreWarnings) -join "`r`n")
                    )
                }
                if (@($restoreResult.Errors).Count -gt 0) {
                    $restoreSections.Add(
                        "以下備份無法還原，原檔已保留：`r`n" +
                        (@($restoreResult.Errors) -join "`r`n")
                    )
                }
                $restoreSummary = if ([int]$restoreResult.RestoredCount -gt 0) {
                    '通過驗證的原始設定已還原。'
                }
                else {
                    '沒有任何設定完成還原。'
                }
                $restoreMessage = $restoreSummary
                if ($restoreSections.Count -gt 0) {
                    $restoreMessage += "`r`n`r`n" + (@($restoreSections) -join "`r`n`r`n")
                }
                $restoreTitle = if (@($restoreResult.Errors).Count -gt 0) { '部分完成' } else { '完成' }
                $restoreIcon = if (@($restoreResult.Errors).Count -gt 0) {
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                }
                else {
                    [System.Windows.Forms.MessageBoxIcon]::Information
                }
                [System.Windows.Forms.MessageBox]::Show(
                    $restoreMessage,
                    $restoreTitle,
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    $restoreIcon
                ) | Out-Null
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    ('還原未完整完成：' + $_.Exception.Message + "`r`n`r`n已完成的部分不會再重複；仍存在的備份可再次還原。"),
                    '發生錯誤',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
            finally {
                & $setBusy $false ''
                & $refreshStatus
            }
        })

    $refreshButton.Add_Click({ & $refreshStatus })
    $closeButton.Add_Click({ $form.Close() })
    $form.Add_Shown({ & $refreshStatus })

        [void]$form.ShowDialog()
    }
    finally {
        if ($createdNew) {
            try { $mutex.ReleaseMutex() } catch { }
        }
        $mutex.Dispose()
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'TelemetryGuard 只支援 Windows。'
}

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $windowsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    if ([string]::IsNullOrWhiteSpace($windowsRoot)) {
        throw '無法從 Windows Known Folder 取得系統目錄；沒有執行任何系統變更。'
    }
    $nativePowerShell = Join-Path $windowsRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $nativePowerShell)) {
        throw '無法啟動 64 位元 Windows PowerShell；為避免讀到錯誤的系統設定，已停止。'
    }
    $nativeArguments = @(
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Mode', $Mode,
        '-ExpectedSourceHash', $script:LaunchSourceHash
    )
    if ($NoElevation) {
        $nativeArguments += '-NoElevation'
    }
    if (@($OptionalProfiles).Count -gt 0) {
        $nativeArguments += '-OptionalProfiles'
        $nativeArguments += (@($OptionalProfiles) -join ',')
    }
    & $nativePowerShell @nativeArguments
    exit $LASTEXITCODE
}

try {
    switch ($Mode) {
        'Status' {
            Get-GuardStatus | ConvertTo-Json -Depth 10
        }
        'Preview' {
            Get-PreviewText -ProfileIds $OptionalProfiles
        }
        'Disable' {
            Invoke-DisableConfiguration -ProfileIds $OptionalProfiles
            Get-GuardStatus | ConvertTo-Json -Depth 10
        }
        'Restore' {
            $restoreResult = Invoke-RestoreAvailableBackups
            if ([int]$restoreResult.RestoredCount -eq 0) {
                throw ('沒有任何備份完成還原：{0}' -f (@($restoreResult.Errors) -join '；'))
            }
            $restoreErrors = @($restoreResult.Errors)
            [pscustomobject][ordered]@{
                Succeeded = [bool]($restoreErrors.Count -eq 0)
                Partial = [bool]($restoreErrors.Count -gt 0)
                TelemetryRestore = $restoreResult.TelemetryRestore
                OptionalRestore = $restoreResult.OptionalRestore
                Errors = $restoreErrors
                Status = Get-GuardStatus
            } | ConvertTo-Json -Depth 10
            if ($restoreErrors.Count -gt 0) {
                exit 2
            }
        }
        default {
            Show-GuardGui
        }
    }
}
finally {
    if ($null -ne $script:LaunchSourceStream) {
        $script:LaunchSourceStream.Dispose()
        $script:LaunchSourceStream = $null
    }
}
