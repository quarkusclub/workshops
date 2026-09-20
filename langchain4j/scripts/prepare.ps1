<#
.SYNOPSIS
    Quarkus Club - machine preparation for the Quarkus LangChain4j workshop (Windows).

.DESCRIPTION
    Installs a per-user JDK if you need one, fetches the material, warms the
    caches that conference wifi cannot handle, and tells you exactly what is
    left. It never installs system packages and never elevates: everything it
    installs lives under your own user profile. Whatever needs administrator
    rights is printed at the end, with the exact command or click path.

.EXAMPLE
    irm https://quarkusclub.github.io/workshops/langchain4j/scripts/prepare.ps1 | iex

.EXAMPLE
    # Prefer to read it first (recommended):
    irm https://quarkusclub.github.io/workshops/langchain4j/scripts/prepare.ps1 -OutFile prepare.ps1
    notepad prepare.ps1 ; Unblock-File .\prepare.ps1 ; .\prepare.ps1

.EXAMPLE
    # With arguments, since a piped script cannot receive them:
    & ([scriptblock]::Create((irm https://quarkusclub.github.io/workshops/langchain4j/scripts/prepare.ps1))) -SkipBuild

.NOTES
    Licensed under the Apache License 2.0.
#>
[CmdletBinding()]
param(
    [string] $Workshop  = 'langchain4j',
    [string] $Dir       = (Join-Path $HOME 'quarkusclub-workshops'),
    [switch] $SkipBuild,
    [switch] $SkipImages,
    [switch] $NoPersistEnv
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$RepoUrl        = 'https://github.com/quarkusclub/workshops.git'
$RepoZip        = 'https://codeload.github.com/quarkusclub/workshops/zip/refs/heads/main'
$TarballMarker  = '.quarkusclub-tarball'
$PgvectorImage  = 'pgvector/pgvector:pg17'
$MinJava        = 21
$MinDiskGb      = 5
$AdoptiumApi    = 'https://api.adoptium.net/v3'

$QcHome = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'quarkusclub' } else { Join-Path $HOME '.quarkusclub' }
$JdkDir = Join-Path $QcHome "jdk-$MinJava"

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:Manual   = New-Object System.Collections.Generic.List[string]

function Write-Ok   ($m) { Write-Host '  * ' -ForegroundColor Green  -NoNewline; Write-Host $m }
function Write-Warn ($m) { Write-Host '  ! ' -ForegroundColor Yellow -NoNewline; Write-Host $m; $script:Warnings.Add($m) }
function Write-Fail ($m) { Write-Host '  x ' -ForegroundColor Red    -NoNewline; Write-Host $m; $script:Failures.Add($m) }
function Write-Step ($m) { Write-Host ''; Write-Host $m -ForegroundColor White }
function Write-Hint ($m) { Write-Host "      $m" -ForegroundColor DarkGray }
function Write-Busy ($m) { Write-Host "  ... $m" -ForegroundColor DarkGray }

# Everything that needs administrator rights, or that a failed repair leaves
# behind, is collected here and printed as the closing section.
function Add-Manual ($m) { $script:Manual.Add($m) }

Write-Host @'
  ___                 _              ___ _      _
 / _ \ _  _ __ _ _ _ | |___  _ ___  / __| |_  _| |__
| (_) | || / _` | '_|| / / || (_-< | (__| | || | '_ \
 \__\_\\_,_\__,_|_|  |_\_\\_,_/__/  \___|_|\_,_|_.__/
'@ -ForegroundColor Blue
Write-Host " Workshop machine preparation  ($Workshop)" -ForegroundColor DarkGray

# The zip fallback replaces the target directory, so never accept a drive root.
$Dir = $Dir.TrimEnd('\', '/')
if ([string]::IsNullOrWhiteSpace($Dir) -or $Dir -match '^[A-Za-z]:$' -or $Dir -eq $HOME.TrimEnd('\', '/')) {
    $Dir = Join-Path $HOME 'quarkusclub-workshops'
    Write-Warn "That target directory is too broad to replace safely. Using $Dir instead."
}

# ------------------------------------------------------------------ Java
Write-Step '1/8  Java'

function Get-JavaExe {
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
        return (Join-Path $env:JAVA_HOME 'bin\java.exe')
    }
    $c = Get-Command java -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Get-JavaMajor ($Exe) {
    if (-not $Exe) { return 0 }
    # A java.exe that cannot start at all must not spray the console: keep the
    # failure inside this function and report it as "no usable Java".
    $ErrorActionPreference = 'SilentlyContinue'
    $line = $null
    try { $line = (& $Exe -version 2>&1 | Select-Object -First 1) -as [string] } catch { return 0 }
    if ($line -match 'version "(\d+)') { return [int]$Matches[1] }
    return 0
}

function Get-AdoptiumArch {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    switch ($arch) {
        'X64'   { return 'x64' }
        'Arm64' { return 'aarch64' }
        default {
            if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return 'aarch64' }
            if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { return 'x64' }
            return $null
        }
    }
}

# The assets endpoint lists the .msi installer next to the .zip archive, so ask
# for the archive explicitly.
function Get-AdoptiumChecksum ($Arch) {
    try {
        $url = "$AdoptiumApi/assets/latest/$MinJava/hotspot?os=windows&architecture=$Arch&image_type=jdk"
        $assets = Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 30
        foreach ($a in $assets) {
            if ($a.binary.package.name -like '*.zip') { return $a.binary.package.checksum }
        }
    } catch { }
    return $null
}

function Test-ManagedJdk {
    $exe = Join-Path $JdkDir 'bin\java.exe'
    if (-not (Test-Path $exe)) { return $false }
    return ((Get-JavaMajor $exe) -ge $MinJava)
}

function Expand-ZipTo ($Zip, $Destination) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Destination)
        return $true
    } catch {
        try {
            Expand-Archive -Path $Zip -DestinationPath $Destination -Force -ErrorAction Stop
            return $true
        } catch { return $false }
    }
}

$JdkManualNote = @"
Install a JDK $MinJava yourself (no administrator needed)
Download the Windows x64 .zip from https://adoptium.net/temurin/releases/?version=$MinJava
Pick: JDK, hotspot, .zip. Then, in PowerShell, from your Downloads folder:
> Expand-Archive .\OpenJDK21U-jdk_x64_windows_hotspot_*.zip -DestinationPath "$QcHome"
> Rename-Item "$QcHome\jdk-21*" "$JdkDir"
> [Environment]::SetEnvironmentVariable('JAVA_HOME', "$JdkDir", 'User')
Close and reopen PowerShell afterwards.
Why we could not do it for you: the download or the checksum check did not succeed on this machine.
"@

function Install-Temurin {
    $arch = Get-AdoptiumArch
    if (-not $arch) {
        Write-Warn "Unsupported CPU architecture for the automatic JDK install: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
        return $false
    }

    $expected = Get-AdoptiumChecksum $arch
    if (-not $expected) {
        Write-Warn 'Could not read the expected SHA-256 from the Adoptium API. Not installing an unverified JDK.'
        return $false
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("quarkusclub-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    $zip = Join-Path $tmp 'jdk.zip'
    try { New-Item -ItemType Directory -Path $tmp -Force -ErrorAction Stop | Out-Null } catch { return $false }

    Write-Busy "downloading Eclipse Temurin $MinJava for windows/$arch (around 200MB)"
    try {
        Invoke-WebRequest -Uri "$AdoptiumApi/binary/latest/$MinJava/ga/windows/$arch/jdk/hotspot/normal/eclipse" `
            -OutFile $zip -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Warn 'The JDK download failed. Check your connection or proxy.'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # -ne on strings is case insensitive, and Get-FileHash returns upper case.
    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
    if ($actual -ne $expected) {
        Write-Fail 'The downloaded JDK does not match the SHA-256 published by Adoptium. Discarded.'
        Write-Hint "expected $expected"
        Write-Hint "got      $actual"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    Write-Ok 'SHA-256 verified against the Adoptium API'

    if (-not (Expand-ZipTo $zip (Join-Path $tmp 'x'))) {
        Write-Warn 'Could not unpack the JDK archive.'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    $top = Get-ChildItem -Path (Join-Path $tmp 'x') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $top -or -not (Test-Path (Join-Path $top.FullName 'bin\java.exe'))) {
        Write-Warn 'The JDK archive did not contain the expected layout.'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    try {
        New-Item -ItemType Directory -Path $QcHome -Force -ErrorAction Stop | Out-Null
        if (Test-Path $JdkDir) { Remove-Item $JdkDir -Recurse -Force -ErrorAction Stop }
        Move-Item -Path $top.FullName -Destination $JdkDir -ErrorAction Stop
    } catch {
        Write-Warn "The JDK was downloaded but could not be installed into $JdkDir"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    return (Test-ManagedJdk)
}

# Persisting is per-user only: the User scope never needs administrator rights.
function Save-UserEnvironment ($JavaHome) {
    $bin = Join-Path $JavaHome 'bin'
    try {
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $JavaHome, 'User')
        $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        if (-not $userPath) { $userPath = '' }
        $already = $userPath.Split(';') | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $bin.TrimEnd('\')) }
        if (-not $already) {
            [Environment]::SetEnvironmentVariable('PATH', ($bin + ';' + $userPath).TrimEnd(';'), 'User')
        }
        return $true
    } catch {
        return $false
    }
}

function Write-EnvFile ($Directory, $JavaHome) {
    $content = @"
# Generated by the Quarkus Club workshop preparation script.
# Gives this terminal the JDK the workshop expects:
#
#   . $Directory\env.ps1
#
`$env:JAVA_HOME = '$JavaHome'
`$env:PATH      = '$JavaHome\bin;' + `$env:PATH
"@
    try {
        Set-Content -Path (Join-Path $Directory 'env.ps1') -Value $content -Encoding UTF8 -ErrorAction Stop
        return $true
    } catch { return $false }
}

$javaExe     = Get-JavaExe
$javaMajor   = Get-JavaMajor $javaExe
$jdkManaged  = $false
$resolvedJavaHome = $null

if ($javaMajor -ge $MinJava) {
    Write-Ok "Java $javaMajor at $javaExe"
} else {
    $shortfall = if (-not $javaExe) { 'no Java on PATH' }
                 elseif ($javaMajor -eq 0) { 'could not read the version of the Java on PATH' }
                 else { "Java $javaMajor is older than $MinJava" }

    $ready = $false
    if (Test-ManagedJdk) {
        Write-Ok "$shortfall, reusing the JDK a previous run installed at $JdkDir"
        $ready = $true
    } else {
        Write-Busy "$shortfall, installing Eclipse Temurin $MinJava under your user profile"
        $ready = Install-Temurin
    }

    if ($ready) {
        $jdkManaged      = $true
        $env:JAVA_HOME   = $JdkDir
        $env:PATH        = (Join-Path $JdkDir 'bin') + ';' + $env:PATH
        $javaExe         = Get-JavaExe
        $javaMajor       = Get-JavaMajor $javaExe
        if ($javaMajor -ge $MinJava) {
            Write-Ok "Java $javaMajor at $javaExe"
        } else {
            Write-Fail "The JDK at $JdkDir is not usable."
            Add-Manual $JdkManualNote
        }
    } else {
        Write-Fail "Java $MinJava is missing and the automatic install did not succeed."
        Add-Manual $JdkManualNote
    }
}

if ($javaMajor -ge $MinJava) {
    if ($jdkManaged) {
        $resolvedJavaHome = $JdkDir
    } elseif ($env:JAVA_HOME) {
        $resolvedJavaHome = $env:JAVA_HOME
    } else {
        $resolvedJavaHome = Split-Path (Split-Path $javaExe -Parent) -Parent
    }
}

if ($jdkManaged -and $resolvedJavaHome) {
    if ($NoPersistEnv) {
        Write-Hint 'User environment left untouched (-NoPersistEnv)'
    } elseif (Save-UserEnvironment $resolvedJavaHome) {
        Write-Ok 'JAVA_HOME and PATH saved for your Windows user'
        Write-Hint 'New terminals pick it up. This one already has it.'
    } else {
        Write-Warn 'Could not save JAVA_HOME for your Windows user.'
        Add-Manual @"
Point your Windows user at the JDK yourself (no administrator needed)
Run these two lines in PowerShell, then close and reopen it:
> [Environment]::SetEnvironmentVariable('JAVA_HOME', '$resolvedJavaHome', 'User')
> [Environment]::SetEnvironmentVariable('PATH', '$resolvedJavaHome\bin;' + [Environment]::GetEnvironmentVariable('PATH','User'), 'User')
Or: Start menu > "Edit environment variables for your account".
Why we could not do it for you: writing your user environment was refused on this machine.
"@
    }
} elseif ($resolvedJavaHome) {
    Write-Hint 'Your own JDK is already on PATH, so your user environment was left untouched'
}

# ---------------------------------------------------- Container runtime
# The end question comes first: can anything here run a container? Only when
# the answer is no do we walk the chain backwards to name the broken link.
Write-Step '2/8  Container runtime'
$runtime = $null
foreach ($candidate in @('docker', 'podman')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        & $candidate info *> $null
        if ($LASTEXITCODE -eq 0) {
            $runtime = $candidate
            Write-Ok "$candidate is installed and running"
            break
        }
    }
}

$DockerInstallNote = @'
Docker Desktop for Windows  (needs administrator)
Download: https://www.docker.com/products/docker-desktop/
Run the installer, accept the defaults, reboot if it asks, then start Docker
Desktop from the Start menu and wait until the whale icon stops animating.
Why we cannot do it for you: the installer needs administrator rights.
Needed from step 06 on, where Quarkus starts a pgvector container for you.
Steps 01 to 05 run fine without it.
'@

$VirtualizationNote = @'
Turn hardware virtualization on in your firmware  (needs administrator AND a reboot)
Reboot and open the BIOS/UEFI setup: usually F2, F10, Del or Esc during the very
first screen. Look for "Intel VT-x", "Intel Virtualization Technology", "AMD-V" or
"SVM Mode", often under Advanced > CPU Configuration. Turn it on, save and reboot.
Only then install or start Docker Desktop: https://www.docker.com/products/docker-desktop/
Why we cannot do it for you: nothing running inside Windows can change a firmware setting.
DO THIS DAYS BEFORE THE WORKSHOP. It needs a reboot and an administrator, and it
cannot be fixed in the room.
'@

function Test-HypervisorPresent {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.HypervisorPresent) { return $true }
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        # HypervisorPresent is false whenever no hypervisor is up, which is not
        # proof of a firmware problem: only claim that when the CPU flag agrees.
        if ($null -ne $cpu.VirtualizationFirmwareEnabled -and -not $cpu.VirtualizationFirmwareEnabled) {
            return $false
        }
        return $true
    } catch {
        return $true
    }
}

function Show-RuntimeDiagnosis {
    $hasDocker = [bool] (Get-Command docker -ErrorAction SilentlyContinue)
    $hasPodman = [bool] (Get-Command podman -ErrorAction SilentlyContinue)
    $virtOk    = Test-HypervisorPresent

    if (-not $virtOk) {
        Write-Fail 'Hardware virtualization is turned off in your firmware. No container runtime can work until it is on.'
        Write-Hint 'This one needs a reboot into BIOS/UEFI, so deal with it before the workshop day.'
        Add-Manual $VirtualizationNote
        return
    }

    if (-not $hasDocker -and -not $hasPodman) {
        Write-Fail 'No container runtime installed. Steps 06 to 10 need Docker Desktop.'
        Write-Hint 'Steps 01 to 05 do not need one, so this is not fatal for the first half.'
        Add-Manual $DockerInstallNote
        return
    }

    if ($hasDocker) {
        $running = Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue
        if ($running) {
            Write-Fail 'Docker Desktop is running but not ready yet.'
            Write-Hint 'It can take a minute or two after login. Wait for the whale icon to stop animating.'
            Add-Manual @'
Wait for Docker Desktop to finish starting
It is already running, it just has not finished initialising.
Watch the whale icon in the system tray: when it stops animating, run this script again.
If it never settles, open Docker Desktop and use Troubleshoot > Restart.
Why we cannot do it for you: the script will not sit and babysit a desktop app.
'@
        } else {
            Write-Fail 'Docker Desktop is installed but not running.'
            Add-Manual @'
Start Docker Desktop
Start menu > Docker Desktop. Wait until the whale icon in the system tray stops animating,
then run this script again.
Tip: Docker Desktop > Settings > General > "Start Docker Desktop when you log in"
saves you this step on the workshop day.
Why we cannot do it for you: the script will not sit and babysit a desktop app.
'@
        }
        return
    }

    Write-Fail 'Podman is installed but its machine is not running.'
    Add-Manual @'
Start the Podman machine  (no administrator needed)
> podman machine init   # only the first time
> podman machine start
Then run this script again.
'@
}

if (-not $runtime) { Show-RuntimeDiagnosis }

# ------------------------------------------------------------------ Git
# Not required any more: the material can also arrive as a zip. Git is still
# preferred, because it is what makes a later 'git pull' work.
Write-Step '3/8  Git'
$hasGit = [bool] (Get-Command git -ErrorAction SilentlyContinue)
if ($hasGit) {
    Write-Ok ((git --version) -as [string])
} else {
    Write-Warn 'git not found. The material will be downloaded as a zip instead.'
    Add-Manual @'
git for Windows  (optional, nice to have)
Download: https://git-scm.com/download/win
Without git the material still arrives as a zip, but you cannot 'git pull' the
updates we may publish before the workshop.
Why we cannot do it for you: the installer needs administrator rights.
'@
}

# ----------------------------------------------------------------- Disk
Write-Step '4/8  Disk space'
try {
    $root    = [System.IO.Path]::GetPathRoot($Dir)
    $drive   = Get-PSDrive -Name $root.Substring(0,1) -ErrorAction Stop
    $freeGb  = [math]::Floor($drive.Free / 1GB)
    if ($freeGb -lt $MinDiskGb) {
        Write-Warn "Only ${freeGb}GB free on $root. Around ${MinDiskGb}GB is recommended."
    } else {
        Write-Ok "${freeGb}GB free on $root"
    }
} catch {
    Write-Warn 'Could not determine free disk space'
}

# -------------------------------------------------------------- Network
Write-Step '5/8  Network'
function Test-Endpoint ($Url, $Label) {
    try {
        Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15 -Method Head *> $null
        Write-Ok "$Label reachable"
    } catch {
        try {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15 *> $null
            Write-Ok "$Label reachable"
        } catch {
            Write-Warn "$Label unreachable ($Url). Check proxy or firewall."
        }
    }
}
Test-Endpoint 'https://repo1.maven.org/maven2/'          'Maven Central'
Test-Endpoint 'https://integrate.api.nvidia.com/v1/models' 'NVIDIA NIM API'
Test-Endpoint 'https://github.com'                        'GitHub'

# ---------------------------------------------------- Workshop material
Write-Step '6/8  Workshop material'
$workshopDir = Join-Path $Dir $Workshop
$markerPath  = Join-Path $Dir $TarballMarker

$MaterialManualNote = @"
Put the workshop material in place by hand
Open https://github.com/quarkusclub/workshops in a browser, use the green
'Code' button and 'Download ZIP', then unpack it so that this path exists:
> $workshopDir\mvnw.cmd
Why we could not do it for you: the download did not succeed, or $Dir already
holds something we did not put there and we will not overwrite it.
"@

function Get-MaterialZip {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("quarkusclub-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    $zip = Join-Path $tmp 'material.zip'
    try { New-Item -ItemType Directory -Path $tmp -Force -ErrorAction Stop | Out-Null } catch { return $false }

    Write-Busy 'downloading the material as a zip'
    try {
        Invoke-WebRequest -Uri $RepoZip -OutFile $zip -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Warn "Could not download $RepoZip"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    if (-not (Expand-ZipTo $zip (Join-Path $tmp 'x'))) {
        Write-Warn 'Could not unpack the material zip.'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    $top = Get-ChildItem -Path (Join-Path $tmp 'x') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $top) {
        Write-Warn 'The material zip did not contain the expected layout.'
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    try {
        if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force -ErrorAction Stop }
        $parent = Split-Path $Dir -Parent
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }
        Move-Item -Path $top.FullName -Destination $Dir -ErrorAction Stop
    } catch {
        Write-Warn "Could not move the material into $Dir"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType File -Path (Join-Path $Dir $TarballMarker) -Force -ErrorAction SilentlyContinue | Out-Null
    return $true
}

if ($hasGit -and (Test-Path (Join-Path $Dir '.git'))) {
    git -C $Dir pull --ff-only *> $null
    if ($LASTEXITCODE -eq 0) { Write-Ok "Updated $Dir" }
    else { Write-Warn "$Dir exists but could not fast-forward. Leaving it untouched." }
} elseif ((Test-Path $markerPath) -and (Test-Path (Join-Path $workshopDir 'mvnw.cmd'))) {
    # Ours, complete, and possibly holding work in progress: refreshing it would
    # overwrite whatever the attendee changed.
    Write-Ok "Material already in $Dir (downloaded by an earlier run)"
    Write-Hint 'Delete that folder and run this script again for a fresh copy'
} elseif ((Test-Path $Dir) -and -not (Test-Path $markerPath)) {
    Write-Warn "$Dir exists and was not created by this script. Leaving it untouched."
} else {
    $fetched = $false
    if ($hasGit -and -not (Test-Path $Dir)) {
        git clone --depth 1 $RepoUrl $Dir *> $null
        if ($LASTEXITCODE -eq 0) { Write-Ok "Cloned into $Dir"; $fetched = $true }
    }
    if (-not $fetched) {
        if (Get-MaterialZip) {
            Write-Ok "Downloaded into $Dir (zip)"
            if (-not $hasGit) { Write-Hint "Install git later to pick up updates with 'git pull'" }
        } else {
            Write-Fail 'Could not fetch the workshop material.'
        }
    }
}

# A clone can succeed and still be empty (unpublished repo), so verify the payload.
$materialOk = (Test-Path (Join-Path $workshopDir 'mvnw.cmd')) -and (Test-Path (Join-Path $workshopDir 'section-1'))
if (-not $materialOk) {
    Write-Fail "No workshop material found at $workshopDir"
    Add-Manual $MaterialManualNote
}

if ($resolvedJavaHome) {
    $envDir = if ($materialOk) { $Dir } else { $QcHome }
    try { New-Item -ItemType Directory -Path $envDir -Force -ErrorAction Stop | Out-Null } catch { }
    if (Write-EnvFile $envDir $resolvedJavaHome) {
        Write-Ok "Wrote $envDir\env.ps1"
        Write-Hint "Dot-source it in any terminal to get the right JAVA_HOME:  . $envDir\env.ps1"
    } else {
        Write-Warn 'Could not write env.ps1'
    }
}

# ------------------------------------------------------- Warm the caches
Write-Step '7/8  Warming caches'
if (-not $SkipImages -and $runtime) {
    Write-Busy "pulling $PgvectorImage (this is the big one)"
    & $runtime pull $PgvectorImage *> $null
    if ($LASTEXITCODE -eq 0) { Write-Ok "Image $PgvectorImage is local" }
    else { Write-Warn "Could not pull $PgvectorImage. Retry on a better connection." }
} else {
    Write-Hint 'Image pull skipped'
}

$mvnw = Join-Path $workshopDir 'mvnw.cmd'
if (-not $SkipBuild -and (Test-Path $mvnw)) {
    Write-Busy 'downloading Quarkus dependencies, several minutes on first run'
    Push-Location $workshopDir
    & $mvnw -B -q clean verify *> $null
    $buildExit = $LASTEXITCODE
    Pop-Location
    if ($buildExit -eq 0) {
        Write-Ok 'Maven cache warm, all step projects compile'
    } else {
        Write-Warn 'The warm-up build did not finish cleanly. Run it by hand to see why:'
        Write-Hint "cd $workshopDir ; .\mvnw.cmd clean verify"
        Add-Manual @"
Finish the dependency warm-up yourself (no administrator needed)
> cd $workshopDir
> .\mvnw.cmd clean verify
Getting this to pass before the workshop means the room's wifi only has to carry
the model calls, not a few hundred megabytes of Quarkus dependencies.
Why we could not do it for you: the build failed here and the error needs a human.
"@
    }
} else {
    Write-Hint 'Build skipped'
}


# ----------------------------------------------------------- Health check
# Independently verifies the END STATE. The stages above describe what the
# script found and did; this one answers a single question: is this machine
# ready to run the workshop right now?
Write-Step '8/8  Health check'

$healthPass = 0
$healthFail = 0

function Test-Health {
    param([string] $Label, [string] $Detail, [scriptblock] $Check)
    $result = $false
    try { $result = [bool] (& $Check) } catch { $result = $false }
    if ($result) {
        Write-Host '  * ' -ForegroundColor Green -NoNewline
        Write-Host $Label.PadRight(34) -NoNewline
        Write-Host $Detail -ForegroundColor DarkGray
        $script:healthPass++
    } else {
        Write-Host '  x ' -ForegroundColor Red -NoNewline
        Write-Host $Label.PadRight(34) -NoNewline
        Write-Host $Detail -ForegroundColor DarkGray
        $script:healthFail++
    }
}

function Get-WorkingRuntime {
    foreach ($c in @('docker', 'podman')) {
        if (Get-Command $c -ErrorAction SilentlyContinue) {
            & $c info *> $null
            if ($LASTEXITCODE -eq 0) { return $c }
        }
    }
    return $null
}

Test-Health "JDK $MinJava or newer" 'required to build every step' {
    (Get-JavaMajor (Get-JavaExe)) -ge $MinJava
}

Test-Health 'Container runtime running' 'pgvector Dev Service, step 06+' {
    $null -ne (Get-WorkingRuntime)
}

Test-Health "Image $PgvectorImage" 'pulled locally' {
    $r = Get-WorkingRuntime
    if (-not $r) { return $false }
    & $r image inspect $PgvectorImage *> $null
    return ($LASTEXITCODE -eq 0)
}

Test-Health 'Workshop material on disk' $workshopDir {
    (Test-Path (Join-Path $workshopDir 'mvnw.cmd')) -and
    (Test-Path (Join-Path $workshopDir 'section-1\step-01'))
}

Test-Health 'Quarkus dependencies cached' '~\.m2\repository\io\quarkus' {
    Test-Path (Join-Path $HOME '.m2\repository\io\quarkus')
}

Test-Health 'NVIDIA API reachable' 'integrate.api.nvidia.com' {
    try {
        Invoke-WebRequest -Uri 'https://integrate.api.nvidia.com/v1/models' -UseBasicParsing -TimeoutSec 15 *> $null
        return $true
    } catch { return $false }
}

# The key is created live during step 00, so its absence is expected beforehand.
if ($env:NVIDIA_API_KEY) {
    Write-Host '  * ' -ForegroundColor Green -NoNewline
    Write-Host 'NVIDIA_API_KEY is set'.PadRight(34) -NoNewline
    Write-Host 'already exported' -ForegroundColor DarkGray
} else {
    Write-Host '  . ' -ForegroundColor Blue -NoNewline
    Write-Host 'NVIDIA_API_KEY not set yet'.PadRight(34) -NoNewline
    Write-Host 'expected: you create it in step 00' -ForegroundColor DarkGray
}

# --------------------------------------------------------------- Verdict
Write-Host ''
Write-Host '--------------------------------------------------------'
$total = $healthPass + $healthFail
if ($healthFail -eq 0) {
    Write-Host '  READY' -ForegroundColor Green -NoNewline
    Write-Host "  $healthPass/$total health checks passed. This machine can run the workshop."
} else {
    Write-Host '  NOT READY' -ForegroundColor Red -NoNewline
    Write-Host "  $healthFail of $total health checks failed."
    Write-Host '  Fix the items marked x above and run this script again.'
}

# ------------------------------------------------- What is left for you
Write-Host ''
Write-Host '--------------------------------------------------------'
Write-Host '  WHAT YOU STILL HAVE TO DO YOURSELF'
Write-Host ''
if ($script:Manual.Count -eq 0) {
    Write-Host '  Nothing.' -ForegroundColor Green -NoNewline
    Write-Host ' This script installed or verified everything the workshop needs.'
} else {
    Write-Host '  This script never asks for administrator rights, so these are yours:' -ForegroundColor DarkGray
    Write-Host ''
    $i = 1
    foreach ($entry in $script:Manual) {
        $lines = $entry.Trim() -split "`r?`n"
        Write-Host ("  {0}) {1}" -f $i, $lines[0]) -ForegroundColor White
        foreach ($line in $lines[1..($lines.Count - 1)]) {
            # '> ' marks a line the attendee is meant to type. The marker is
            # stripped so what lands on screen can be pasted back verbatim.
            if ($line.StartsWith('> ')) {
                Write-Host ("       " + $line.Substring(2)) -ForegroundColor Cyan
            } else {
                Write-Host "     $line"
            }
        }
        Write-Host ''
        $i++
    }
}

if ($script:Warnings.Count -gt 0) {
    Write-Host '  Warnings (not blocking):' -ForegroundColor Yellow
    foreach ($w in $script:Warnings) { Write-Host "    ! $w" -ForegroundColor Yellow }
}

Write-Host ''
Write-Host '  Next: ' -NoNewline
Write-Host 'create your free NVIDIA API key during the workshop (step 00).'
Write-Host '  Guide: https://quarkusclub.github.io/workshops/langchain4j/'
Write-Host ''

# `irm ... | iex` evaluates this script inside the caller's own session, where a
# bare `exit` terminates the window before the verdict can be read. $PSCommandPath
# is set only when running from a file on disk, so exit only in that case and
# otherwise just leave the status behind for the caller to inspect.
$exitCode = if ($healthFail -gt 0) { 1 } else { 0 }
if ($PSCommandPath) { exit $exitCode }
$global:LASTEXITCODE = $exitCode
