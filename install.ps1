<#
.SYNOPSIS
    Install the modular PowerShell profile from a git repository.
.DESCRIPTION
    Clones the profile repository to a local directory and runs setup.ps1
    to deploy the profile files. Supports update and uninstall operations
    against the same repository.

    Run this script from anywhere. It handles its own working directory.
.PARAMETER RepoUrl
    Git repository URL. Defaults to $env:PSPROFILE_REPO or prompts if unset.
.PARAMETER Branch
    Branch or tag to check out. Defaults to "main".
.PARAMETER InstallDir
    Where to clone the repository. Defaults to
    "$HOME\.powershell-profile".
.PARAMETER Update
    Pull the latest changes and re-run setup. Skips clone.
.PARAMETER Uninstall
    Remove the profile files and optionally the cloned repository.
.PARAMETER Force
    Pass through to setup.ps1 as -Force (overwrite without backups).
.PARAMETER SkipClink
    Pass through to setup.ps1 as -SkipClink.
.PARAMETER SkipModules
    Pass through to setup.ps1 as -SkipModules.
.EXAMPLE
    .\install.ps1 -RepoUrl https://github.com/me/pwsh-profile.git
.EXAMPLE
    .\install.ps1 -Update
.EXAMPLE
    .\install.ps1 -Uninstall
#>

[CmdletBinding(DefaultParameterSetName = "Install")]
param(
    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Update")]
    [string]$RepoUrl,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Update")]
    [string]$Branch = "main",

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Update")]
    [Parameter(ParameterSetName = "Uninstall")]
    [string]$InstallDir,

    [Parameter(ParameterSetName = "Update")]
    [switch]$Update,

    [Parameter(ParameterSetName = "Uninstall")]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Update")]
    [switch]$Force,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Update")]
    [switch]$SkipClink,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Update")]
    [switch]$SkipModules
)

$ErrorActionPreference = "Stop"

# ============================================================
# Helpers
# ============================================================

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Green
}

function Write-Warn2 {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Red
}

function Test-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git.exe not found on PATH. Install Git from https://git-scm.com/downloads or via winget: winget install --id Git.Git -e"
    }
}

function Resolve-InstallDir {
    if ($InstallDir) { return $InstallDir }
    return (Join-Path $HOME ".powershell-profile")
}

function Resolve-RepoUrl {
    if ($RepoUrl) { return $RepoUrl }

    $envUrl = $env:PSPROFILE_REPO
    if ($envUrl) { return $envUrl }

    throw "No repository URL provided. Pass -RepoUrl or set `$env:PSPROFILE_REPO."
}

# ============================================================
# Banner
# ============================================================

Write-Host ""
Write-Host "PowerShell Profile Installer" -ForegroundColor Magenta
Write-Host "=============================" -ForegroundColor Magenta

# ============================================================
# Uninstall
# ============================================================

if ($Uninstall) {
    Write-Step "Uninstalling profile"

    $target = Resolve-InstallDir

    # Remove deployed profile files.
    $profileFile = $PROFILE.CurrentUserCurrentHost
    $profileDir  = Split-Path -Parent $profileFile
    $profileD    = Join-Path $profileDir "Profile.d"

    if (Test-Path $profileD) {
        Remove-Item -Path $profileD -Recurse -Force
        Write-Ok "Removed $profileD"
    } else {
        Write-Warn2 "No Profile.d directory found at $profileD"
    }

    if (Test-Path $profileFile) {
        Remove-Item -Path $profileFile -Force
        Write-Ok "Removed $profileFile"
    } else {
        Write-Warn2 "No profile loader found at $profileFile"
    }

    # Optionally remove the cloned repository.
    if (Test-Path $target) {
        $answer = Read-Host "Remove cloned repository at $target? [y/N]"
        if ($answer -match '^(y|yes)$') {
            Remove-Item -Path $target -Recurse -Force
            Write-Ok "Removed $target"
        } else {
            Write-Warn2 "Kept $target"
        }
    }

    Write-Host ""
    Write-Host "Uninstall complete. Open a new PowerShell window to reset the session." -ForegroundColor Green
    return
}

# ============================================================
# Update
# ============================================================

if ($Update) {
    Test-Git

    $target = Resolve-InstallDir
    if (-not (Test-Path (Join-Path $target ".git"))) {
        throw "No git repository found at $target. Run install first."
    }

    Write-Step "Updating repository"
    Push-Location $target
    try {
        & git fetch --all --prune
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed." }

        & git checkout $Branch
        if ($LASTEXITCODE -ne 0) { throw "git checkout $Branch failed." }

        & git pull --ff-only origin $Branch
        if ($LASTEXITCODE -ne 0) { throw "git pull failed. Resolve conflicts manually." }

        Write-Ok "Repository updated to $Branch"
    } finally {
        Pop-Location
    }

    $setup = Join-Path $target "setup.ps1"
    if (-not (Test-Path $setup)) {
        throw "setup.ps1 not found in $target"
    }

    Write-Step "Running setup"
    $setupArgs = @()
    if ($Force)       { $setupArgs += "-Force" }
    if ($SkipClink)   { $setupArgs += "-SkipClink" }
    if ($SkipModules) { $setupArgs += "-SkipModules" }

    & $setup @setupArgs

    Write-Host ""
    Write-Host "Update complete. Open a new PowerShell window to pick up changes." -ForegroundColor Green
    return
}

# ============================================================
# Install
# ============================================================

Test-Git

$target = Resolve-InstallDir
$url    = Resolve-RepoUrl

Write-Host "Repository : $url"
Write-Host "Branch     : $Branch"
Write-Host "Install dir: $target"

# --- Clone or reuse existing checkout ------------------------
if (Test-Path $target) {
    $gitDir = Join-Path $target ".git"
    if (Test-Path $gitDir) {
        Write-Step "Existing repository found at $target"
        $answer = Read-Host "Run git pull to update it? [Y/n]"
        if (-not $answer -or $answer -match '^(y|yes)$') {
            Push-Location $target
            try {
                & git fetch --all --prune
                & git checkout $Branch
                & git pull --ff-only origin $Branch
                if ($LASTEXITCODE -ne 0) { throw "git pull failed." }
                Write-Ok "Repository updated"
            } finally {
                Pop-Location
            }
        } else {
            Write-Warn2 "Skipping git update."
        }
    } else {
        throw "Target directory exists but is not a git repository: $target. Remove it or pass -InstallDir."
    }
} else {
    Write-Step "Cloning repository"
    $parent = Split-Path -Parent $target
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    & git clone --branch $Branch --single-branch $url $target
    if ($LASTEXITCODE -ne 0) { throw "git clone failed." }
    Write-Ok "Cloned to $target"
}

# --- Run setup -----------------------------------------------
$setup = Join-Path $target "setup.ps1"
if (-not (Test-Path $setup)) {
    throw "setup.ps1 not found in $target. Is this the correct repository?"
}

Write-Step "Running setup"
$setupArgs = @()
if ($Force)       { $setupArgs += "-Force" }
if ($SkipClink)   { $setupArgs += "-SkipClink" }
if ($SkipModules) { $setupArgs += "-SkipModules" }

& $setup @setupArgs

# ============================================================
# Done
# ============================================================

Write-Host ""
Write-Host "Install complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Close and reopen PowerShell."
Write-Host "  2. Run:  menu"
Write-Host ""
Write-Host "To update later:" -ForegroundColor Cyan
Write-Host "  .\install.ps1 -Update"
Write-Host ""
Write-Host "To uninstall:" -ForegroundColor Cyan
Write-Host "  .\install.ps1 -Uninstall"