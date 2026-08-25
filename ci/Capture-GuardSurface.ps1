#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$serviceNames = @(
    'DiagTrack', 'WSearch', 'MixedRealityLinkSvc', 'Spooler', 'CDPSvc', 'PhoneSvc',
    'lfsvc', 'MapsBroker', 'XblAuthManager', 'XblGameSave', 'XboxGipSvc',
    'XboxNetApiSvc', 'WerSvc', 'PcaSvc', 'InstallService', 'WMPNetworkSvc',
    'icssvc', 'WebClient'
)

$taskIdentities = @(
    '\Microsoft\Windows\Application Experience\|Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\|Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\Customer Experience Improvement Program\|Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\|KernelCeipTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\|UsbCeip',
    '\Microsoft\Windows\Shell\|IndexerAutomaticMaintenance',
    '\Microsoft\Windows\Application Experience\|MareBackup',
    '\Microsoft\Windows\Maps\|MapsToastTask',
    '\Microsoft\Windows\Maps\|MapsUpdateTask',
    '\Microsoft\XblGameSave\|XblGameSaveTask',
    '\Microsoft\Windows\Feedback\Siuf\|DmClient',
    '\Microsoft\Windows\Feedback\Siuf\|DmClientOnScenarioDownload',
    '\Microsoft\Windows\Sustainability\|SustainabilityTelemetry',
    '\Microsoft\Windows\Windows Error Reporting\|QueueReporting'
)

$registryTargets = @(
    [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry' },
    [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDiagnosticLogCollection' },
    [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDumpCollection' },
    [pscustomobject]@{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; Name = 'CEIPEnable' }
)

$allServices = @(Get-CimInstance Win32_Service -ErrorAction Stop)
$services = @(
    foreach ($name in $serviceNames | Sort-Object) {
        $service = @($allServices | Where-Object { $_.Name -eq $name }) | Select-Object -First 1
        [pscustomobject][ordered]@{
            Name = $name
            Exists = [bool]($null -ne $service)
            StartMode = if ($null -eq $service) { $null } else { [string]$service.StartMode }
            State = if ($null -eq $service) { $null } else { [string]$service.State }
            DelayedAutoStart = if ($null -eq $service -or
                $service.PSObject.Properties.Name -notcontains 'DelayedAutoStart') {
                $null
            }
            else {
                [bool]$service.DelayedAutoStart
            }
        }
    }
)

$allTasks = @(Get-ScheduledTask -ErrorAction Stop)
$tasks = @(
    foreach ($identity in $taskIdentities | Sort-Object) {
        $parts = $identity -split '\|', 2
        $task = @($allTasks | Where-Object {
                $_.TaskPath -eq $parts[0] -and $_.TaskName -eq $parts[1]
            }) | Select-Object -First 1
        [pscustomobject][ordered]@{
            Identity = $identity
            Exists = [bool]($null -ne $task)
            Enabled = if ($null -eq $task) { $null } else { [bool]$task.Settings.Enabled }
            State = if ($null -eq $task) { $null } else { [string]$task.State }
        }
    }
)

$registry = @(
    foreach ($target in $registryTargets) {
        $item = Get-ItemProperty -LiteralPath $target.Path -ErrorAction SilentlyContinue
        $exists = $null -ne $item -and $item.PSObject.Properties.Name -contains $target.Name
        [pscustomobject][ordered]@{
            Path = $target.Path
            Name = $target.Name
            Exists = [bool]$exists
            Value = if ($exists) { [string]$item.($target.Name) } else { $null }
        }
    }
)

[pscustomobject][ordered]@{
    Services = $services
    Tasks = $tasks
    Registry = $registry
    StateRootExists = [bool](Test-Path -LiteralPath (Join-Path `
                ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) `
                'TelemetryGuard'))
} | ConvertTo-Json -Depth 6 -Compress
