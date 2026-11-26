#Requires -Version 5.1
# reverse-apk.ps1 - Windows port of ReverseAPK v1.2
# Credits: @xer0dayz - https://sn1persecurity.com
#
# USAGE:
#   .\reverse-apk.ps1 <path_to_apk>
#   reverse-apk <path_to_apk>   (after running install.ps1)

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$ApkPath
)

function Write-Banner {
    Write-Host @"

__________
\______   \ _______  __ ___________  ______ ____
 |       _// __ \  \/ // __ \_  __ \/  ___// __ \
 |    |   \  ___/\   /\  ___/|  | \/\___ \  ___/
 |____|_  /\___  >\_/  \___  >__|  /____  >\___  >
        \/     \/          \/           \/     \/
                                           _____ __________ ____  __.
                                          /  _  \\______   \    |/ _|
      --=[( by @xer0dayz )]=--           /  /_\  \|     ___/      <
   --=[( https://sn1persecurity.com )]=-- /    |    \    |   |    |  \
                                        \____|__  /____|   |____|__ \
                                                \/                 \/
"@ -ForegroundColor Yellow
}

function Write-Section([string]$Title) {
    Write-Host "`n $Title..." -ForegroundColor Red
    Write-Host " =====================================================================" -ForegroundColor Red
}

function Search-Java([string]$Dir, [string]$Pattern) {
    if (-not (Test-Path $Dir)) { return }
    $files = Get-ChildItem -Recurse -Filter '*.java' -Path $Dir -ErrorAction SilentlyContinue
    if (-not $files) { return }
    $files | Select-String -Pattern $Pattern -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line)" }
}

function Get-ApkStrings([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sb    = [System.Text.StringBuilder]::new()
    $out   = [System.Collections.Generic.List[string]]::new()
    foreach ($b in $bytes) {
        if ($b -ge 32 -and $b -le 126) { [void]$sb.Append([char]$b) }
        else {
            if ($sb.Length -ge 4) { $out.Add($sb.ToString()) }
            [void]$sb.Clear()
        }
    }
    if ($sb.Length -ge 4) { $out.Add($sb.ToString()) }
    $out
}

Write-Banner

if (-not (Test-Path $ApkPath)) {
    Write-Host " Error: File not found: $ApkPath" -ForegroundColor Red
    exit 1
}

$apk       = (Resolve-Path $ApkPath).Path
$apkBase   = $apk -replace '\.apk$', ''

# Dependency check
$deps = @('apktool', 'd2j-dex2jar', 'jadx', 'baksmali')
foreach ($dep in $deps) {
    if (-not (Get-Command $dep -ErrorAction SilentlyContinue)) {
        Write-Host " Command '$dep' not found." -ForegroundColor Red
        Write-Host " Run .\install.ps1 to install dependencies." -ForegroundColor Green
        exit 1
    }
}

$cpuCount  = [Environment]::ProcessorCount
$jadxDir   = "$apkBase-jadx"
$unzipDir  = "$apkBase-unzipped"
$unpackDir = "$apkBase-unpacked"
$manifest  = "$unpackDir\AndroidManifest.xml"

# Unpack APK
Write-Section "Unpacking APK file"
Expand-Archive -Path $apk -DestinationPath $unzipDir -Force -ErrorAction SilentlyContinue
$dex = "$unzipDir\classes.dex"
if (Test-Path $dex) {
    & baksmali d $dex -o "$unzipDir\classes.dex.out" 2>$null
}

# Convert to JAR
Write-Section "Converting APK to Java JAR file"
& d2j-dex2jar $apk -o "$apk.jar" --force

# Decompile with Jadx
Write-Section "Decompiling using Jadx"
& jadx $apk -j $cpuCount -d $jadxDir 2>$null

# Unpack with APKTool
Write-Section "Unpacking using APKTool"
& apktool d $apk -o $unpackDir -f

# APK file listing
Write-Section "Displaying APK files"
Get-ChildItem -Recurse "${apkBase}*" -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -match '\.(apk|class)$' } |
    Select-Object -ExpandProperty FullName

# OAuth secrets
Write-Section "Searching for OAuth secrets"
Get-ChildItem -Recurse "${apkBase}*" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -imatch 'oauth' } |
    Select-Object -ExpandProperty FullName

# AndroidManifest.xml
Write-Section "Displaying AndroidManifest.xml"
if (Test-Path $manifest) { Get-Content $manifest }

Write-Section "Displaying Package Info in AndroidManifest.xml"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern 'package=' }

Write-Section "Displaying Activities in AndroidManifest.xml"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern 'activity ' }

Write-Section "Displaying Services in AndroidManifest.xml"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern 'service ' }

Write-Section "Displaying Content Providers in AndroidManifest.xml"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern 'provider' }

Write-Section "Displaying Broadcast Receivers in AndroidManifest.xml"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern 'receiver' }

Write-Section "Displaying Intent Filter Actions in AndroidManifest.xml"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern 'action|category' }

Write-Section "Displaying Permissions in AndroidManifest.xml"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern 'android\.permission' }

Write-Section "Displaying Exports in AndroidManifest.xml"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern 'exported="true"' }

Write-Section "Displaying Backups in AndroidManifest.xml"
if (Test-Path $manifest) { Select-String -Path $manifest -Pattern 'backup' }

# Device Info
Write-Section "Searching for DeviceId references"
Search-Java $jadxDir 'getDeviceId'

# Intents
Write-Section "Searching for android.intent references"
Search-Java $jadxDir 'android\.intent'

Write-Section "Searching for Intent references"
Search-Java $jadxDir 'intent\.'

# Command execution
Write-Section "Searching for command execution references"
Search-Java $jadxDir 'Runtime\.getRuntime\(\)\.exec'

# SQLite
Write-Section "Searching for SQLiteDatabase references"
Search-Java $jadxDir 'SQLiteDatabase'

# Logging
Write-Section "Searching for Log.d references"
Search-Java $jadxDir 'log\.d|Log\.'

# Content Providers
Write-Section "Displaying Content Providers"
Get-ChildItem -Recurse "${apkBase}*" -ErrorAction SilentlyContinue |
    Select-String -Pattern 'content://' -ErrorAction SilentlyContinue
Search-Java $jadxDir '://'

# Broadcast Receivers
Write-Section "Searching for Broadcast Receiver references"
Search-Java $jadxDir 'BroadcastReceiver|onReceive|sendBroadcast'

# Services
Write-Section "Searching for Service references"
Search-Java $jadxDir 'stopService|startService'

# File references
Write-Section "Searching for file:// references"
Search-Java $jadxDir 'file://'

Write-Section "Searching for getSharedPreferences references"
Search-Java $jadxDir 'getSharedPreferences'

Write-Section "Searching for getExternal references"
Search-Java $jadxDir 'getExternal'

# Crypto
Write-Section "Searching for Crypto references"
Search-Java $jadxDir 'crypto\.'

Write-Section "Searching for MessageDigest references"
Search-Java $jadxDir 'MessageDigest'

Write-Section "Searching for java.util.Random references"
Search-Java $jadxDir 'java\.util\.Random'

Write-Section "Searching for Base64 references"
Search-Java $jadxDir 'Base64'

Write-Section "Searching for Hex references"
Search-Java $jadxDir 'Hex|hex\.'

# Hardcoded secrets
Write-Section "Searching for hardcoded secrets"
if (Test-Path $jadxDir) {
    Get-ChildItem -Recurse -Filter '*.java' $jadxDir -ErrorAction SilentlyContinue |
        Select-String -Pattern 'secret|password|username' -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line)" }
}

Write-Section "Searching for sensitive information"
$stringsFile = "$apk-strings.txt"
Get-ApkStrings $apk | Out-File -FilePath $stringsFile -Encoding UTF8
Write-Host " Strings saved to: $stringsFile"

# URLs
Write-Section "Searching for URLs"
Search-Java $jadxDir 'https?:'

Write-Section "Searching for HTTP headers"
Search-Java $jadxDir 'addHeader'

Write-Section "Searching for UDP and TCP Sockets"
Search-Java $jadxDir '\.connect\(|\.disconnect|serverSocket|DatagramSocket'

# SSL / Certificates
Write-Section "Searching for client certificates"
if (Test-Path $unzipDir) {
    Get-ChildItem -Recurse $unzipDir -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '\.(pkcs|p12|cer|der)$' } |
        Select-Object -ExpandProperty FullName
}

Write-Section "Searching for SSL certificate pinning"
Search-Java $jadxDir 'getCertificatePinningSSL'

Write-Section "Searching for SSL connections"
Search-Java $jadxDir 'ssl\.SSL'

# WebView
Write-Section "Searching for WebView activity"
Search-Java $jadxDir 'WebView'

Write-Section "Searching for addJavascriptInterface references"
Search-Java $jadxDir 'addJavascriptInterface'

Write-Section "Searching for setJavaScriptEnabled references"
Search-Java $jadxDir 'setJavaScriptEnabled'

Write-Section "Searching for setAllowFileAccess references"
Search-Java $jadxDir 'setAllow'

Write-Section "Searching for setSavePassword references"
Search-Java $jadxDir 'setSavePassword'

Write-Host "`n DONE!" -ForegroundColor Red
Write-Host " =====================================================================" -ForegroundColor Red
