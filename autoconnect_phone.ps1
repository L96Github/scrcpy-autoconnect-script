# Requires PowerShell 5.1 or later (Windows 10/11 default)
# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Configuration ---
# Path to your ADB executable (if not in system PATH)
# Example: $AdbPath = "C:\Users\YourUser\AppData\Local\Android\Sdk\platform-tools\adb.exe"
# If adb.exe is in your system PATH, leave this as just "adb.exe"
$AdbCommand = "adb.exe"

# Path to your scrcpy executable (if not in system PATH)
# Example: $ScrcpyPath = "C:\scrcpy-win64-v1.24\scrcpy.exe"
# If scrcpy.exe is in your system PATH, leave this as just "scrcpy.exe"
$ScrcpyCommand = "scrcpy.exe"

# Scrcpy arguments
$ScrcpyArgs = "--audio-buffer=200 --video-bit-rate 4M"

# --- Functions ---

function Resolve-ExecutablePath {
    param (
        [string]$Command
    )
    # If the command contains a path separator, assume it's a full path
    if ($Command -like "*\*" -or $Command -like "*/\*") {
        return $Command
    }
    # If it's just a filename, check if it exists in the current directory
    if (Test-Path ".\$Command" -PathType Leaf) {
        return ".\$Command"
    }
    # Otherwise, assume it's in PATH or will be resolved by the shell
    return $Command
}

function Test-AdbServer {
    # Tests if the ADB server is running.
    Write-Host "Checking ADB server status..." -ForegroundColor Cyan

    $commandToExecute = Resolve-ExecutablePath $AdbCommand

    # Ensure $AdbCommand (resolved path) points to an existing executable
    if (-not (Test-Path $commandToExecute -PathType Leaf)) {
        Write-Error "ADB executable not found at '$commandToExecute'. Please verify the path in the script's configuration or ensure it's in your system PATH."
        exit 1
    }

    try {
        # Pass command and arguments separately to the & operator
        $output = & $commandToExecute "devices" 2>&1
        if ($output -like "*daemon not running*") {
            Write-Host "ADB server is not running." -ForegroundColor Yellow
            return $false
        } elseif ($output -like "*daemon started successfully*") {
            Write-Host "ADB server started successfully." -ForegroundColor Green
            return $true
        } else {
            Write-Host "ADB server is running." -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Warning "Failed to execute '$commandToExecute devices'. Ensure ADB is installed and in your PATH, or '$AdbCommand' is correctly set."
        Write-Warning $_.Exception.Message
        exit 1
    }
}

function Start-AdbServer {
    # Starts the ADB server.
    Write-Host "Starting ADB server..." -ForegroundColor Cyan
    try {
        $commandToExecute = Resolve-ExecutablePath $AdbCommand
        # Pass command and arguments separately to the & operator
        & $commandToExecute "start-server" | Out-Null
        Start-Sleep -Seconds 2 # Give server a moment to start
        if (Test-AdbServer) {
            Write-Host "ADB server started successfully." -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Failed to start ADB server."
            return $false
        }
    } catch {
        Write-Warning "Error starting ADB server: $_.Exception.Message"
        return $false
    }
}

function Get-AdbDevices {
    # Gets a list of connected ADB devices and parses their info.
    Write-Host "Listing connected ADB devices..." -ForegroundColor Cyan
    $devices = @()
    try {
        $commandToExecute = Resolve-ExecutablePath $AdbCommand
        # Pass command and arguments separately to the & operator
        $output = & $commandToExecute "devices" "-l"

        # Skip the first line ("List of devices attached")
        $deviceLines = $output | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }

        if (-not $deviceLines) {
            Write-Host "No ADB devices found." -ForegroundColor Yellow
            return $devices
        }

        foreach ($line in $deviceLines) {
            # Regex to capture serial/ip:port, state, and optional properties
            if ($line -match '^(?<id>[\w\d\.:]+)\s+(?<state>\w+)\s*(?<properties>.*)$') {
                $deviceId = $matches.id
                $deviceState = $matches.state
                $deviceProperties = $matches.properties

                $isWireless = $deviceId -match '^\d{1,3}(\.\d{1,3}){3}:\d+$' # Checks for IP:PORT format

                $device = [PSCustomObject]@{
                    Id         = $deviceId
                    State      = $deviceState
                    IsWireless = $isWireless
                    IP         = if ($isWireless) { $deviceId.Split(':')[0] } else { $null }
                    Port       = if ($isWireless) { $deviceId.Split(':')[1] } else { $null }
                    Properties = $deviceProperties
                }
                $devices += $device
            }
        }
    } catch {
        Write-Warning "Error getting ADB devices: $_.Exception.Message"
    }
    return $devices
}

function Select-Device ($deviceList) {
    # Allows the user to select a device from a list.
    if (-not $deviceList) {
        Write-Host "No devices to select." -ForegroundColor Yellow
        return $null
    }

    if ($deviceList.Count -eq 1) {
        $selectedDevice = $deviceList[0]
        Write-Host "Automatically selected the only device found: $($selectedDevice.Id) ($($selectedDevice.State))" -ForegroundColor Green
        return $selectedDevice
    }

    Write-Host "Multiple devices found. Please select a device to connect to:" -ForegroundColor White
    for ($i = 0; $i -lt $deviceList.Count; $i++) {
        $device = $deviceList[$i]
        Write-Host "  $($i + 1). $($device.Id) ($($device.State))" -ForegroundColor Cyan
    }

    $selection = Read-Host "Enter the number of the device you want to use"
    if ($selection -match '^\d+$' -and ([int]$selection -ge 1) -and ([int]$selection -le $deviceList.Count)) {
        return $deviceList[[int]$selection - 1]
    } else {
        Write-Warning "Invalid selection. Please enter a valid number."
        return $null
    }
}

function Pair-WirelessDevice ($deviceIP) {
    # Handles the wireless pairing process.
    Write-Host "`n--- Wireless Device Pairing ---" -ForegroundColor Yellow
    Write-Host "On your Android device, go to 'Settings > Developer options > Wireless debugging'." -ForegroundColor White
    Write-Host "Tap 'Pair device with pairing code' to see the pairing details." -ForegroundColor White
    Write-Host "-------------------------------" -ForegroundColor Yellow

    $pairingPort = Read-Host "Enter the Pairing Port (e.g., 40404) shown on your phone"
    $pairingCode = Read-Host "Enter the 6-digit Pairing Code (e.g., 123456) shown on your phone"

    if (-not $pairingPort -or -not $pairingCode) {
        Write-Warning "Pairing port or code cannot be empty. Aborting pairing."
        return $false
    }

    Write-Host "Attempting to pair with ${deviceIP}:${pairingPort}..." -ForegroundColor Cyan
    try {
        $commandToExecute = Resolve-ExecutablePath $AdbCommand
        # Pass command and arguments separately to the & operator
        $pairOutput = & $commandToExecute "pair" "${deviceIP}:${pairingPort}" 2>&1
        Write-Host $pairOutput

        if ($pairOutput -like "*Successfully paired*") {
            Write-Host "Device successfully paired!" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Pairing failed: $pairOutput"
            return $false
        }
    } catch {
        Write-Warning "Error during pairing: $_.Exception.Message"
        return $false
    }
}

function Connect-WirelessDevice ($deviceIP, $connectionPort) {
    # Handles the wireless connection process.
    Write-Host "`n--- Wireless Device Connection ---" -ForegroundColor Yellow
    Write-Host "Attempting to connect to ${deviceIP}:${connectionPort}..." -ForegroundColor Cyan
    try {
        $commandToExecute = Resolve-ExecutablePath $AdbCommand
        # Pass command and arguments separately to the & operator
        $connectOutput = & $commandToExecute "connect" "${deviceIP}:${connectionPort}" 2>&1
        Write-Host $connectOutput

        if ($connectOutput -like "*connected to*") {
            Write-Host "Device successfully connected!" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Connection failed: $connectOutput"
            return $false
        }
    } catch {
        Write-Warning "Error during connection: $_.Exception.Message"
        return $false
    }
}

function Start-ScrcpySession ($scrcpyCmd, $scrcpyArgs) {
    # Starts the scrcpy session.
    Write-Host "`nStarting scrcpy with arguments: $scrcpyArgs" -ForegroundColor Green

    $commandToExecute = Resolve-ExecutablePath $ScrcpyCommand

    # Ensure $ScrcpyCommand (resolved path) points to an existing executable
    if (-not (Test-Path $commandToExecute -PathType Leaf)) {
        Write-Error "Scrcpy executable not found at '$commandToExecute'. Please verify the path in the script's configuration or ensure it's in your system PATH."
        exit 1
    }

    try {
        # Split arguments string into an array for correct passing to & operator
        $argsArray = $scrcpyArgs.Split(' ') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        & $commandToExecute @argsArray
    } catch {
        Write-Warning "Failed to start scrcpy. Ensure '$scrcpyCmd' is installed and in your PATH, or is correctly set."
        Write-Warning $_.Exception.Message
    }
}

# --- Main Script Logic ---

Write-Host "--- Scrcpy Wireless Connection Automation ---" -ForegroundColor Green

# 1. Check and start ADB server
if (-not (Test-AdbServer)) {
    if (-not (Start-AdbServer)) {
        Write-Error "Could not start ADB server. Exiting."
        exit 1
    }
}

# 2. Get and select a device
$allDevices = Get-AdbDevices
if (-not $allDevices) {
    Write-Host "No devices found to connect. Ensure your device is in developer mode and USB debugging is enabled." -ForegroundColor Yellow
    exit 0
}

$selectedDevice = Select-Device $allDevices
if (-not $selectedDevice) {
    Write-Host "No device selected. Exiting." -ForegroundColor Yellow
    exit 0
}

# 3. Handle Wireless Connection/Pairing
if ($selectedDevice.IsWireless) {
    $deviceIP = $selectedDevice.IP
    $connectionPort = $selectedDevice.Port # This is the port from adb devices output

    Write-Host "`nSelected wireless device: $($selectedDevice.Id)" -ForegroundColor Cyan

    # Check if device is already connected/authorized
    if ($selectedDevice.State -eq "device") {
        Write-Host "Device is already in 'device' state. Attempting to connect directly." -ForegroundColor Green
        # Even if 'device' state, sometimes a re-connect helps with stability
        if (-not (Connect-WirelessDevice $deviceIP $connectionPort)) {
            Write-Warning "Direct connection failed. You might need to re-pair or check connection port."
            # Fallback to pairing if direct connect fails
            if (Pair-WirelessDevice $deviceIP) {
                # After successful pairing, try connecting again
                # Note: The connection port might change after pairing, so re-prompt for it.
                Write-Host "`nPairing successful. Now, please get the new Connection Port from your phone's 'Wireless debugging' screen (it's usually 5555, or similar to the IP:PORT listed for your device)." -ForegroundColor White
                $newConnectionPort = Read-Host "Enter the Connection Port for $deviceIP"
                if (-not $newConnectionPort) {
                    Write-Warning "Connection port not provided. Aborting."
                    exit 1
                }
                if (-not (Connect-WirelessDevice $deviceIP $newConnectionPort)) {
                    Write-Error "Failed to connect after pairing. Exiting."
                    exit 1
                }
            } else {
                Write-Error "Pairing failed. Exiting."
                exit 1
            }
        }
    } else { # Device is unauthorized, offline, or needs initial pairing
        Write-Host "Device state is '$($selectedDevice.State)'. It likely needs pairing or re-authorization." -ForegroundColor Yellow
        if (Pair-WirelessDevice $deviceIP) {
            # After successful pairing, the connection port might change.
            # The port listed in 'adb devices' might be the old one or not the one for direct connection.
            # It's safer to ask the user for the connection port again.
            Write-Host "`nPairing successful. Now, please get the new Connection Port from your phone's 'Wireless debugging' screen (it's usually 5555, or similar to the IP:PORT listed for your device)." -ForegroundColor White
            $newConnectionPort = Read-Host "Enter the Connection Port for $deviceIP"
            if (-not $newConnectionPort) {
                Write-Warning "Connection port not provided. Aborting."
                exit 1
            }
            if (-not (Connect-WirelessDevice $deviceIP $newConnectionPort)) {
                Write-Error "Failed to connect after pairing. Exiting."
                exit 1
            }
        } else {
            Write-Error "Pairing failed. Exiting."
            exit 1
        }
    }
} elseif ($selectedDevice.State -ne "device") {
    Write-Warning "Selected USB device is not in 'device' state ($($selectedDevice.State)). Please ensure it's authorized for USB debugging."
    Write-Host "On your phone, you should see a prompt 'Allow USB debugging?'. Check 'Always allow from this computer' and tap 'Allow'." -ForegroundColor White
    exit 1
} else {
    Write-Host "`nSelected USB device is connected: $($selectedDevice.Id)" -ForegroundColor Green
    # For USB, scrcpy should just work without explicit connect command
}

# 4. Start scrcpy in the background
Start-ScrcpySession $ScrcpyCommand $ScrcpyArgs &

Write-Host "`nScript finished." -ForegroundColor Green
