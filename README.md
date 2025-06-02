# scrcpy-autoconnect-script

A simple script to streamline the process of connecting to your Android device using **scrcpy**. This repository provides an automated solution for connecting and mirroring your device, making it even easier to use scrcpy with minimal effort.

## Features

- **Automatic Connection**: The script automates the connection process to your Android device.
- **Easy Setup**: Just add the necessary scrcpy files and run the script.
- **Minimal Configuration**: No complex setup required.

## Requirements

- **scrcpy v3.2 (64-bit)**:  
  Download the official 64-bit release files from [@Genymobile/scrcpy](https://github.com/Genymobile/scrcpy/releases/tag/v3.2).
- **Windows PowerShell**:  
  The script is written in PowerShell (`.ps1`), compatible with Windows.

## Setup Instructions

1. **Download latest version of scrcpy**
    - Get the release files from the [scrcpy GitHub repository](https://github.com/Genymobile/scrcpy/releases).

2. **Copy scrcpy Files**
    - Place all the required scrcpy files in this repository directory, alongside the script. Currently already done in repo, it has downloaded v3.2 (64-bit)
3. **Connect Your Device**
    - Make sure your Android device is connected via USB and USB debugging is enabled in developer settings. Or Wireless debugging enabled if you wish to connect via Wi-Fi
4. **Enable additional setting "USB Debugging (Security settings)", if applicatble to your device**
4. **Use the Script**
    - The main script is:  
      **`.\autoconnect_phone.ps1`**
    - Run this file with PowerShell to automatically connect your Android device using scrcpy.


## File Structure

- `autoconnect_phone.ps1`  
  The custom script that automates scrcpy connection.
- All other files  
  Required binaries and dependencies from scrcpy v3.2 64-bit.

## Credits

- **scrcpy** by [Genymobile](https://github.com/Genymobile/scrcpy)
- Script and automation by [L96Github](https://github.com/L96Github)

## License

Refer to the scrcpy license for the binaries.
