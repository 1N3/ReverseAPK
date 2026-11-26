#Requires -Version 5.1
# install.ps1 - Windows installer for ReverseAPK v1.2 dependencies
# Credits: @xer0dayz - https://sn1persecurity.com
#
# Run from an elevated (Administrator) PowerShell prompt:
#   .\install.ps1

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step([string]$Msg) {
    Write-Host "`n $Msg..." -ForegroundColor Red
    Write-Host " =====================================================================" -ForegroundColor Red
}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host @"
 Installing ReverseAPK dependencies for Windows...
 =====================================================================
"@ -ForegroundColor Yellow

if (-not (Test-Admin)) {
    Write-Host " ERROR: This script requires administrator privileges." -ForegroundColor Red
    Write-Host " Re-run from an elevated PowerShell prompt." -ForegroundColor Yellow
    exit 1
}

# Java
Write-Step "Checking for Java"
if (Get-Command java -ErrorAction SilentlyContinue) {
    Write-Host " Java found: $((Get-Command java).Source)" -ForegroundColor Green
} else {
    Write-Host " Java not found — installing OpenJDK 21 via winget..." -ForegroundColor Yellow
    winget install -e --id Microsoft.OpenJDK.21 --accept-source-agreements --accept-package-agreements
    $env:PATH = [Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [Environment]::GetEnvironmentVariable("PATH","User")
    if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
        Write-Host " Java install may require a terminal restart. Continuing..." -ForegroundColor Yellow
    }
}

# Chocolatey
Write-Step "Checking for Chocolatey"
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host " Installing Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
} else {
    Write-Host " Chocolatey found." -ForegroundColor Green
}

# apktool
Write-Step "Installing apktool"
choco install apktool -y

# dex2jar — Chocolatey package is broken; download directly from GitHub
Write-Step "Installing dex2jar"
$dex2jarVersion = "v2.4"
$dex2jarZip     = "$env:TEMP\dex-tools-$dex2jarVersion.zip"
$dex2jarDir     = "C:\ProgramData\dex2jar"
$dex2jarBinDir = "$dex2jarDir\dex-tools-$dex2jarVersion"
if (Test-Path $dex2jarBinDir) {
    Write-Host " dex2jar $dex2jarVersion already installed." -ForegroundColor Green
} else {
    if (-not (Test-Path $dex2jarDir)) { New-Item -ItemType Directory -Path $dex2jarDir | Out-Null }
    Write-Host " Downloading dex-tools $dex2jarVersion..." -ForegroundColor Yellow
    (New-Object System.Net.WebClient).DownloadFile(
        "https://github.com/pxb1988/dex2jar/releases/download/$dex2jarVersion/dex-tools-$dex2jarVersion.zip",
        $dex2jarZip)
    Expand-Archive -Path $dex2jarZip -DestinationPath $dex2jarDir -Force
    Write-Host " dex2jar installed to $dex2jarBinDir" -ForegroundColor Green
}
$machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($machinePath -notlike "*$dex2jarBinDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$machinePath;$dex2jarBinDir", "Machine")
    $env:PATH += ";$dex2jarBinDir"
}

# jadx
Write-Step "Installing jadx"
choco install jadx -y

# baksmali — smali package removed from Chocolatey; download JAR directly and create wrapper
Write-Step "Installing baksmali"
$baksmaliVersion = "2.5.2"
$baksmaliJar     = "C:\ProgramData\baksmali\baksmali.jar"
if (Test-Path $baksmaliJar) {
    Write-Host " baksmali already installed." -ForegroundColor Green
} else {
    if (-not (Test-Path "C:\ProgramData\baksmali")) { New-Item -ItemType Directory -Path "C:\ProgramData\baksmali" | Out-Null }
    Write-Host " Downloading baksmali $baksmaliVersion..." -ForegroundColor Yellow
    $baksmaliUrls = @(
        "https://repo1.maven.org/maven2/org/smali/baksmali/$baksmaliVersion/baksmali-$baksmaliVersion.jar",
        "https://github.com/JesusFreke/smali/releases/download/$baksmaliVersion/baksmali-$baksmaliVersion.jar",
        "https://github.com/google/smali/releases/download/$baksmaliVersion/baksmali-$baksmaliVersion.jar"
    )
    $downloaded = $false
    foreach ($url in $baksmaliUrls) {
        Write-Host " Trying $url ..." -ForegroundColor Yellow
        & curl.exe -L --silent --show-error --fail -o $baksmaliJar $url 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $baksmaliJar) -and (Get-Item $baksmaliJar).Length -gt 10000) {
            $downloaded = $true
            break
        }
        Remove-Item $baksmaliJar -ErrorAction SilentlyContinue
    }
    if ($downloaded) {
        @"
@echo off
java -jar "$baksmaliJar" %*
"@ | Out-File -FilePath "C:\ProgramData\baksmali\baksmali.bat" -Encoding ASCII
        $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($machinePath -notlike "*C:\ProgramData\baksmali*") {
            [Environment]::SetEnvironmentVariable("PATH", "$machinePath;C:\ProgramData\baksmali", "Machine")
            $env:PATH += ";C:\ProgramData\baksmali"
        }
        Write-Host " baksmali installed; wrapper at C:\ProgramData\baksmali\baksmali.bat" -ForegroundColor Green
    } else {
        Write-Host " baksmali download failed from all sources." -ForegroundColor Red
        Write-Host " Download baksmali-$baksmaliVersion.jar manually and place it at: $baksmaliJar" -ForegroundColor Yellow
        Write-Host " Then re-run this script to create the wrapper and PATH entry." -ForegroundColor Yellow
    }
}

# Install reverse-apk itself to PATH
Write-Step "Installing reverse-apk"
$installDir = "$env:ProgramFiles\reverse-apk"
if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir | Out-Null }

Copy-Item "$PSScriptRoot\reverse-apk.ps1" "$installDir\reverse-apk.ps1" -Force

# Wrapper batch file so 'reverse-apk' works from any prompt
@"
@echo off
powershell.exe -ExecutionPolicy Bypass -File "$installDir\reverse-apk.ps1" %*
"@ | Out-File -FilePath "$installDir\reverse-apk.bat" -Encoding ASCII

$machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($machinePath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$machinePath;$installDir", "Machine")
    $env:PATH += ";$installDir"
    Write-Host " Added $installDir to system PATH." -ForegroundColor Green
}

Write-Host @"

 Done! Restart your terminal, then run:
   reverse-apk <path_to_apk>

"@ -ForegroundColor Green
