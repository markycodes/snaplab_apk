param(
    [string]$AdbPath,
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$packageName = 'com.photobooth.kiosk'
$adminComponent = 'com.photobooth.kiosk/.KioskDeviceAdminReceiver'

function Resolve-AdbPath {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidate = $RequestedPath
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $candidate = Join-Path $candidate 'adb.exe'
        }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        throw "ADB was not found at '$RequestedPath'. Pass the path to adb.exe or its platform-tools folder."
    }

    $onPath = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($null -ne $onPath -and (Test-Path -LiteralPath $onPath.Source -PathType Leaf)) {
        return $onPath.Source
    }

    $sdkAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $sdkAdb -PathType Leaf) {
        return $sdkAdb
    }

    $enteredPath = Read-Host 'Enter the full path to adb.exe or the platform-tools folder'
    if (Test-Path -LiteralPath $enteredPath -PathType Container) {
        $enteredPath = Join-Path $enteredPath 'adb.exe'
    }
    if (Test-Path -LiteralPath $enteredPath -PathType Leaf) {
        return (Resolve-Path -LiteralPath $enteredPath).Path
    }

    throw 'ADB was not found. Download and extract Android SDK Platform-Tools, then run this script again with -AdbPath.'
}

$adb = Resolve-AdbPath $AdbPath
Write-Host "Using ADB: $adb"

& $adb start-server
if ($LASTEXITCODE -ne 0) {
    throw 'ADB could not start. Reinstall Platform-Tools and check the Windows USB driver.'
}

$deviceLines = @(& $adb devices)
if ($LASTEXITCODE -ne 0) {
    throw 'ADB could not list devices.'
}
$devices = @(
    $deviceLines |
        Select-Object -Skip 1 |
        Where-Object { $_ -match '^\S+\s+\S+' } |
        ForEach-Object {
            $parts = $_ -split '\s+'
            [pscustomobject]@{ Serial = $parts[0]; Status = $parts[1] }
        }
)

if ([string]::IsNullOrWhiteSpace($Serial)) {
    if ($devices.Count -eq 0) {
        throw 'No Android device detected. Enable USB debugging, connect the tablet, and accept its USB debugging prompt.'
    }
    if ($devices.Count -gt 1) {
        $devices | Format-Table -AutoSize | Out-Host
        throw 'More than one device is connected. Run again with -Serial <device-serial>.'
    }
    $Serial = $devices[0].Serial
}

$selectedDevice = $devices | Where-Object { $_.Serial -eq $Serial } | Select-Object -First 1
if ($null -eq $selectedDevice) {
    $devices | Format-Table -AutoSize | Out-Host
    throw "Device '$Serial' is not listed by ADB."
}
if ($selectedDevice.Status -ne 'device') {
    throw "Device '$Serial' status is '$($selectedDevice.Status)'. Unlock it, accept the USB debugging prompt, and retry."
}

$packagePath = & $adb -s $Serial shell pm path $packageName
if ($LASTEXITCODE -ne 0 -or -not ($packagePath -match '^package:')) {
    throw "Photobooth is not installed for the active Android user on '$Serial'. Install the APK, launch it once, then retry."
}

$packageInfo = @(& $adb -s $Serial shell dumpsys package $packageName)
if ($LASTEXITCODE -ne 0 -or -not ($packageInfo -match 'com\.photobooth\.kiosk\.KioskDeviceAdminReceiver')) {
    throw @"
The installed Photobooth APK does not register KioskDeviceAdminReceiver. This causes Android's "Unknown admin" error.
Install build 156 or newer from this project, launch the app once, and retry. If adb install -r reports a signature
conflict, do not uninstall yet; the installed app was signed with a different key and uninstalling can erase its data.
"@
}

Write-Host ''
Write-Host 'Before continuing, confirm the tablet is new or factory-reset, no Google/work accounts were added,'
Write-Host 'and Android setup is complete. Setting a device owner may require factory reset to undo.'
Write-Host "Target device: $Serial"
$confirmation = Read-Host 'Type SET-OWNER to continue'
if ($confirmation -cne 'SET-OWNER') {
    Write-Host 'Cancelled. No device-owner change was made.'
    exit 1
}

& $adb -s $Serial shell dpm set-device-owner $adminComponent
if ($LASTEXITCODE -ne 0) {
    throw @"
Android rejected device-owner provisioning. This is not fixable by changing the ADB command on every device.
Common causes: an account is already added, the device was previously provisioned, another device owner/profile owner exists,
the OEM blocks ADB provisioning, or the Android build requires its enterprise enrollment flow.
Factory-reset only if you have backed up the device and are prepared to set it up again. Otherwise use the manufacturer's
dedicated-device/enterprise enrollment process. You can still use the app's screen-pinning fallback where available.
"@
}

Write-Host ''
Write-Host 'Device owner configured. Open Photobooth and check Admin diagnostics for "Kiosk mode active".'
