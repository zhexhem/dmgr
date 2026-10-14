<#
.SYNOPSIS
    Bootstrap script for the modular PowerShell profile.
.DESCRIPTION
    Creates the Profile.d layout, writes every module file, registers the
    Clink scripts directory, and verifies the install.

    Safe to re-run. Existing files are backed up to .bak before being
    overwritten unless -Force is used.
.PARAMETER Force
    Overwrite existing files without backing them up.
.PARAMETER SkipClink
    Skip Clink script registration.
.PARAMETER SkipModules
    Do not install PSScriptAnalyzer.
.EXAMPLE
    .\setup.ps1
.EXAMPLE
    .\setup.ps1 -Force
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$SkipClink,
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

function Write-Skip {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Write-Warn2 {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Yellow
}

function New-FileSafe {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    if (Test-Path $Path) {
        if ($Force) {
            Remove-Item $Path -Force
        } else {
            $backup = "$Path.bak"
            Copy-Item $Path $backup -Force
            Write-Warn2 "Backed up existing file to $backup"
        }
    }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Set-Content -Path $Path -Value $Content -Encoding UTF8
    Write-Ok $Path
}

# ============================================================
# Paths
# ============================================================

$ProfileFile = $PROFILE.CurrentUserCurrentHost
$ProfileDir  = Split-Path -Parent $ProfileFile
$ProfileD    = Join-Path $ProfileDir "Profile.d"
$ToolsDir    = Join-Path $ProfileD   "tools"
$ClinkDir    = Join-Path $ToolsDir   "ClinkScripts"
$RulesDir    = Join-Path $ToolsDir   "Rules"

Write-Host ""
Write-Host "PowerShell Profile Setup" -ForegroundColor Magenta
Write-Host "=========================" -ForegroundColor Magenta
Write-Host "Profile file : $ProfileFile"
Write-Host "Profile dir  : $ProfileDir"
Write-Host "Profile.d    : $ProfileD"

# ============================================================
# 1. Directories
# ============================================================

Write-Step "Creating directories"

foreach ($dir in @($ProfileDir, $ProfileD, $ToolsDir, $ClinkDir, $RulesDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Ok $dir
    } else {
        Write-Skip "Exists: $dir"
    }
}

# ============================================================
# 2. Profile loader
# ============================================================

Write-Step "Writing profile loader"

$profileLoader = @'
# ============================================================
# PowerShell Profile Loader
# ============================================================
# Loads modular files from Profile.d in the order defined by
# modules.json. Falls back to a static order when the file is
# missing. Anything else in Profile.d is loaded alphabetically.

$ProfileD   = Join-Path (Split-Path -Parent $PROFILE.CurrentUserCurrentHost) "Profile.d"
$configFile = Join-Path $ProfileD "modules.json"

$FallbackOrder = @(
    "variables.ps1",
    "functions.ps1",
    "aliases.ps1",
    "prompt.ps1",
    "psreadline.ps1",
    "clink.ps1",
    "menu.ps1"
)

if (Test-Path $ProfileD) {
    if (Test-Path $configFile) {
        try {
            $cfg       = Get-Content $configFile -Raw | ConvertFrom-Json
            $LoadOrder = @($cfg.loadOrder)
        } catch {
            Write-Warning "Failed to parse modules.json. Using fallback order."
            $LoadOrder = $FallbackOrder
        }
    } else {
        $LoadOrder = $FallbackOrder
    }

    $loaded = @{}

    foreach ($name in $LoadOrder) {
        $file = Join-Path $ProfileD $name
        if (Test-Path $file) {
            try {
                . $file
                $loaded[$name] = $true
            } catch {
                Write-Warning "Failed to load $name : $_"
            }
        }
    }

    Get-ChildItem -Path $ProfileD -Filter *.ps1 -File | ForEach-Object {
        if (-not $loaded.ContainsKey($_.Name)) {
            try {
                . $_.FullName
            } catch {
                Write-Warning "Failed to load $($_.Name) : $_"
            }
        }
    }
}
'@

New-FileSafe -Path $ProfileFile -Content $profileLoader

# ============================================================
# 3. modules.json
# ============================================================

Write-Step "Writing modules.json"

$modulesJson = @'
{
  "loadOrder": [
    "variables.ps1",
    "functions.ps1",
    "aliases.ps1",
    "prompt.ps1",
    "psreadline.ps1",
    "clink.ps1",
    "menu.ps1"
  ],
  "disabled": []
}
'@

New-FileSafe -Path (Join-Path $ProfileD "modules.json") -Content $modulesJson

# ============================================================
# 4. variables.ps1
# ============================================================

Write-Step "Writing variables.ps1"

$variables = @'
# ============================================================
# Variables and Preferences
# ============================================================

# --- Paths ---------------------------------------------------
$Global:PSToolsRoot    = Join-Path $PSScriptRoot "tools"
$Global:PSLintScript   = Join-Path $PSToolsRoot "Invoke-PSLint.ps1"
$Global:PSLintSettings = Join-Path $PSToolsRoot "PSScriptAnalyzerSettings.psd1"
$Global:ClinkScriptDir = Join-Path $PSToolsRoot "ClinkScripts"
$Global:RulesDir       = Join-Path $PSToolsRoot "Rules"

# --- Preferences ---------------------------------------------
$PSDefaultParameterValues['Out-File:Encoding']   = 'utf8'
$PSDefaultParameterValues['Get-ChildItem:Force'] = $true

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$ConfirmPreference     = 'High'

# --- Module search path --------------------------------------
if ((Test-Path $PSToolsRoot) -and ($env:PSModulePath -notlike "*$PSToolsRoot*")) {
    $env:PSModulePath = "$PSToolsRoot;$env:PSModulePath"
}
'@

New-FileSafe -Path (Join-Path $ProfileD "variables.ps1") -Content $variables

# ============================================================
# 5. functions.ps1
# ============================================================

Write-Step "Writing functions.ps1"

$functions = @'
# ============================================================
# Function Definitions
# ============================================================

if (Test-Path $Global:PSLintScript) {
    . $Global:PSLintScript
}

function Get-GitBranch {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $branch = & git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -eq 0) { return $branch }
    return $null
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PortOwner {
    param([Parameter(Mandatory)][int]$Port)
    Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, State,
            @{n='PID';e={$_.OwningProcess}},
            @{n='Process';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}}
}

function New-TempScript {
    param([Parameter(Mandatory)][string]$Content)
    $path = Join-Path $env:TEMP ("tmp_" + [guid]::NewGuid().ToString("N") + ".ps1")
    Set-Content -Path $path -Value $Content -Encoding UTF8
    return $path
}

function Register-ClinkScripts {
    if (-not (Get-Command clink -ErrorAction SilentlyContinue)) {
        Write-Warning "clink.exe not found on PATH."
        return
    }
    if (-not (Test-Path $Global:ClinkScriptDir)) {
        Write-Warning "ClinkScripts directory not found: $Global:ClinkScriptDir"
        return
    }
    & clink installscripts $Global:ClinkScriptDir 2>$null | Out-Null
    Write-Host "Registered Clink scripts from $Global:ClinkScriptDir"
}

function Edit-Profile {
    $editor = $env:EDITOR
    if (-not $editor) { $editor = "notepad.exe" }
    & $editor $PROFILE.CurrentUserCurrentHost
}

function Edit-ProfileD {
    $dir = Join-Path (Split-Path -Parent $PROFILE.CurrentUserCurrentHost) "Profile.d"
    $file = Get-ChildItem -Path $dir -Filter *.ps1 |
        Select-Object -ExpandProperty FullName |
        Out-GridView -Title "Select a file to edit" -PassThru
    if ($file) {
        $editor = $env:EDITOR
        if (-not $editor) { $editor = "notepad.exe" }
        & $editor $file
    }
}

function Reload-Profile {
    . $PROFILE.CurrentUserCurrentHost
}

# ============================================================
# Profile Module Manager
# ============================================================

function Get-ProfileModuleConfig {
    $profileD   = Join-Path (Split-Path -Parent $PROFILE.CurrentUserCurrentHost) "Profile.d"
    $configFile = Join-Path $profileD "modules.json"

    if (-not (Test-Path $configFile)) {
        return [pscustomobject]@{
            loadOrder = @()
            disabled  = @()
            Path      = $configFile
        }
    }

    $json = Get-Content -Path $configFile -Raw | ConvertFrom-Json
    if (-not $json.loadOrder) { $json | Add-Member -NotePropertyName loadOrder -NotePropertyValue @() -Force }
    if (-not $json.disabled)  { $json | Add-Member -NotePropertyName disabled  -NotePropertyValue @() -Force }
    $json | Add-Member -NotePropertyName Path -NotePropertyValue $configFile -Force
    return $json
}

function Save-ProfileModuleConfig {
    param([Parameter(Mandatory)]$Config)
    $out = [ordered]@{
        loadOrder = @($Config.loadOrder)
        disabled  = @($Config.disabled)
    }
    $out | ConvertTo-Json -Depth 5 | Set-Content -Path $Config.Path -Encoding UTF8
}

function Resolve-ProfileModulePath {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet("PowerShell","Clink","Analyzer")][string]$Kind
    )
    $root      = Split-Path -Parent $PROFILE.CurrentUserCurrentHost
    $profileD  = Join-Path $root "Profile.d"
    $toolsRoot = Join-Path $profileD "tools"

    $ext = switch ($Kind) {
        "PowerShell" { "ps1" }
        "Clink"      { "lua" }
        "Analyzer"   { "psm1" }
    }
    $dir = switch ($Kind) {
        "PowerShell" { $profileD }
        "Clink"      { Join-Path $toolsRoot "ClinkScripts" }
        "Analyzer"   { Join-Path $toolsRoot "Rules" }
    }

    $base = $Name -replace "\.$ext(\.disabled)?$",''
    [pscustomobject]@{
        Enabled  = Join-Path $dir "$base.$ext"
        Disabled = Join-Path $dir "$base.$ext.disabled"
        Base     = "$base.$ext"
        Kind     = $Kind
    }
}

function Get-ProfileModule {
    [CmdletBinding()]
    param(
        [ValidateSet("All","PowerShell","Clink","Analyzer")]
        [string]$Kind = "All"
    )

    $root      = Split-Path -Parent $PROFILE.CurrentUserCurrentHost
    $profileD  = Join-Path $root "Profile.d"
    $toolsRoot = Join-Path $profileD "tools"
    $config    = Get-ProfileModuleConfig
    $rows      = @()

    if ($Kind -in @("All","PowerShell") -and (Test-Path $profileD)) {
        Get-ChildItem $profileD -File | Where-Object { $_.Name -match '\.ps1(\.disabled)?$' } | ForEach-Object {
            $isDisabled = $_.Name -match '\.disabled$'
            $baseName   = $_.Name -replace '\.disabled$',''
            $idx        = [array]::IndexOf($config.loadOrder, $baseName)
            $rows += [pscustomobject]@{
                Kind     = "PowerShell"
                Name     = $baseName
                State    = if ($isDisabled) { "Disabled" } else { "Enabled" }
                Order    = if ($idx -ge 0) { $idx } else { "-" }
                SizeKB   = [math]::Round($_.Length / 1KB, 2)
                Modified = $_.LastWriteTime
                Path     = $_.FullName
            }
        }
    }

    if ($Kind -in @("All","Clink")) {
        $clinkDir = Join-Path $toolsRoot "ClinkScripts"
        if (Test-Path $clinkDir) {
            Get-ChildItem $clinkDir -File | Where-Object { $_.Name -match '\.lua(\.disabled)?$' } | ForEach-Object {
                $isDisabled = $_.Name -match '\.disabled$'
                $rows += [pscustomobject]@{
                    Kind     = "Clink"
                    Name     = $_.Name -replace '\.disabled$',''
                    State    = if ($isDisabled) { "Disabled" } else { "Enabled" }
                    Order    = "-"
                    SizeKB   = [math]::Round($_.Length / 1KB, 2)
                    Modified = $_.LastWriteTime
                    Path     = $_.FullName
                }
            }
        }
    }

    if ($Kind -in @("All","Analyzer")) {
        $rulesDir = Join-Path $toolsRoot "Rules"
        if (Test-Path $rulesDir) {
            Get-ChildItem $rulesDir -File | Where-Object { $_.Name -match '\.psm1(\.disabled)?$' } | ForEach-Object {
                $isDisabled = $_.Name -match '\.disabled$'
                $rows += [pscustomobject]@{
                    Kind     = "Analyzer"
                    Name     = $_.Name -replace '\.disabled$',''
                    State    = if ($isDisabled) { "Disabled" } else { "Enabled" }
                    Order    = "-"
                    SizeKB   = [math]::Round($_.Length / 1KB, 2)
                    Modified = $_.LastWriteTime
                    Path     = $_.FullName
                }
            }
        }
    }

    $rows | Sort-Object Kind, @{Expression={ if ($_.Order -eq "-") { [int]::MaxValue } else { [int]$_.Order } }}, Name
}

function New-ProfileModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet("PowerShell","Clink","Analyzer")]
        [string]$Kind = "PowerShell",
        [string]$Template,
        [switch]$Enable
    )

    $validTemplates = switch ($Kind) {
        "PowerShell" { @("Blank","Function","Alias","Hook") }
        "Clink"      { @("Preexec","Prompt","Complete","Keybind") }
        "Analyzer"   { @("CommandRule","FunctionRule","FileRule") }
    }
    if (-not $Template) { $Template = $validTemplates[0] }
    if ($Template -notin $validTemplates) {
        throw "Invalid template '$Template' for Kind '$Kind'. Valid: $($validTemplates -join ', ')"
    }

    $root      = Split-Path -Parent $PROFILE.CurrentUserCurrentHost
    $profileD  = Join-Path $root "Profile.d"
    $toolsRoot = Join-Path $profileD "tools"

    $file = switch ($Kind) {
        "PowerShell" { Join-Path $profileD "$Name.ps1" }
        "Clink"      { Join-Path $toolsRoot "ClinkScripts\$Name.lua" }
        "Analyzer"   { Join-Path $toolsRoot "Rules\$Name.psm1" }
    }

    $dir = Split-Path -Parent $file
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path $file) { throw "Module already exists: $file" }

    $content = Get-ProfileModuleTemplate -Kind $Kind -Template $Template -Name $Name
    Set-Content -Path $file -Value $content -Encoding UTF8
    Write-Host "Created $file" -ForegroundColor Green

    if ($Enable -and $Kind -eq "PowerShell") {
        Enable-ProfileModule -Name $Name
    }
    if ($Kind -eq "Clink" -and (Get-Command Register-ClinkScripts -ErrorAction SilentlyContinue)) {
        Register-ClinkScripts
    }

    return Get-Item $file
}

function Get-ProfileModuleTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$Name
    )

    $safeName = $Name -replace '[^a-zA-Z0-9]',''

    switch ("$Kind-$Template") {
        "PowerShell-Blank" {
"# ============================================================
# $Name
# ============================================================
"
        }
        "PowerShell-Function" {
"# ============================================================
# $Name
# ============================================================

function Verb-$safeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][object]`$InputObject
    )
    process { `$InputObject }
}
"
        }
        "PowerShell-Alias" {
"# ============================================================
# $Name
# ============================================================

# Set-Alias -Name shortname -Value Get-Something
"
        }
        "PowerShell-Hook" {
"# ============================================================
# $Name
# ============================================================

# Runs at profile load. Keep it fast and side-effect free.
"
        }
        "Clink-Preexec" {
"-- $Name.lua
-- Clink preexec hook.

function clink.onprovideline(line)
    return line
end
"
        }
        "Clink-Prompt" {
"-- $Name.lua
-- Clink prompt filter.

local function prompt_filter(prompt)
    return prompt
end

clink.promptfilter(1, prompt_filter)
"
        }
        "Clink-Complete" {
"-- $Name.lua
-- Clink argument completion.

local function complete_$($safeName.ToLower()) (word, word_index, line_state)
    return {}
end

clink.argmatcher("yourcommand")
    :addarg({ complete_$($safeName.ToLower()) })
"
        }
        "Clink-Keybind" {
"-- $Name.lua
-- Clink custom key binding.

local function handler()
    return false
end

clink.bindkey("ctrl-alt-x", handler)
"
        }
        "Analyzer-CommandRule" {
"function Measure-$safeName {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]`$Ast
    )

    `$results  = @()
    `$commands = `$Ast.FindAll({ `$args[0] -is [System.Management.Automation.Language.CommandAst] }, `$true)

    foreach (`$command in `$commands) {
        if (`$command.GetCommandName() -eq 'Invoke-Expression') {
            `$results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                Message  = 'Avoid using Invoke-Expression.'
                Extent   = `$command.Extent
                RuleName = `$PSCmdlet.MyInvocation.InvocationName
                Severity = 'Warning'
            }
        }
    }
    return `$results
}
"
        }
        "Analyzer-FunctionRule" {
"function Measure-$safeName {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]`$Ast
    )

    `$results   = @()
    `$functions = `$Ast.FindAll({ `$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, `$true)

    foreach (`$fn in `$functions) {
        if (`$fn.Name -match '^Temp') {
            `$results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                Message  = 'Avoid temporary function name.'
                Extent   = `$fn.Extent
                RuleName = `$PSCmdlet.MyInvocation.InvocationName
                Severity = 'Information'
            }
        }
    }
    return `$results
}
"
        }
        "Analyzer-FileRule" {
"function Measure-$safeName {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]`$Ast
    )

    `$results = @()
    `$tokens  = `$Ast.FindAll({ `$args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, `$true)

    foreach (`$token in `$tokens) {
        if (`$token.Value -match 'TODO|FIXME') {
            `$results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                Message  = 'Placeholder string found.'
                Extent   = `$token.Extent
                RuleName = `$PSCmdlet.MyInvocation.InvocationName
                Severity = 'Information'
            }
        }
    }
    return `$results
}
"
        }
    }
}

function Enable-ProfileModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet("PowerShell","Clink","Analyzer")][string]$Kind = "PowerShell",
        [int]$Order = -1
    )

    $paths = Resolve-ProfileModulePath -Name $Name -Kind $Kind

    if (Test-Path $paths.Disabled) {
        if (Test-Path $paths.Enabled) { throw "Both enabled and disabled files exist." }
        Move-Item -Path $paths.Disabled -Destination $paths.Enabled
    }
    if (-not (Test-Path $paths.Enabled)) { throw "Module not found: $($paths.Base)" }

    if ($Kind -eq "PowerShell") {
        $config = Get-ProfileModuleConfig
        $order  = @($config.loadOrder | Where-Object { $_ -ne $paths.Base })

        if ($Order -lt 0 -or $Order -ge $order.Count) {
            $order += $paths.Base
        } else {
            $before = if ($Order -gt 0) { $order[0..($Order - 1)] } else { @() }
            $after  = if ($Order -lt $order.Count) { $order[$Order..($order.Count - 1)] } else { @() }
            $order  = @($before) + $paths.Base + @($after)
        }

        $config.loadOrder = $order
        $config.disabled  = @($config.disabled | Where-Object { $_ -ne $paths.Base })
        Save-ProfileModuleConfig -Config $config
    }
    elseif ($Kind -eq "Clink") {
        if (Get-Command Register-ClinkScripts -ErrorAction SilentlyContinue) {
            Register-ClinkScripts
        }
    }

    Write-Host "Enabled $Kind module: $($paths.Base)" -ForegroundColor Green
}

function Disable-ProfileModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet("PowerShell","Clink","Analyzer")][string]$Kind = "PowerShell"
    )

    $paths = Resolve-ProfileModulePath -Name $Name -Kind $Kind

    if (-not (Test-Path $paths.Enabled)) {
        if (Test-Path $paths.Disabled) { Write-Host "Already disabled."; return }
        throw "Module not found: $($paths.Base)"
    }

    Move-Item -Path $paths.Enabled -Destination $paths.Disabled

    if ($Kind -eq "PowerShell") {
        $config = Get-ProfileModuleConfig
        $config.loadOrder = @($config.loadOrder | Where-Object { $_ -ne $paths.Base })
        if ($config.disabled -notcontains $paths.Base) { $config.disabled += $paths.Base }
        Save-ProfileModuleConfig -Config $config
    }

    Write-Host "Disabled $Kind module: $($paths.Base)" -ForegroundColor Yellow
}

function Remove-ProfileModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet("PowerShell","Clink","Analyzer")][string]$Kind = "PowerShell",
        [switch]$Force
    )

    $paths  = Resolve-ProfileModulePath -Name $Name -Kind $Kind
    $target = if (Test-Path $paths.Enabled) { $paths.Enabled }
              elseif (Test-Path $paths.Disabled) { $paths.Disabled }
              else { throw "Module not found: $($paths.Base)" }

    if (-not $Force -and -not $PSCmdlet.ShouldProcess($target, "Delete module")) { return }

    Remove-Item -Path $target -Force

    if ($Kind -eq "PowerShell") {
        $config = Get-ProfileModuleConfig
        $config.loadOrder = @($config.loadOrder | Where-Object { $_ -ne $paths.Base })
        $config.disabled  = @($config.disabled  | Where-Object { $_ -ne $paths.Base })
        Save-ProfileModuleConfig -Config $config
    }

    Write-Host "Removed $Kind module: $($paths.Base)" -ForegroundColor Yellow
}

function Edit-ProfileModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet("PowerShell","Clink","Analyzer")][string]$Kind = "PowerShell"
    )

    $paths = Resolve-ProfileModulePath -Name $Name -Kind $Kind
    $file  = if (Test-Path $paths.Enabled) { $paths.Enabled }
             elseif (Test-Path $paths.Disabled) { $paths.Disabled }
             else { throw "Module not found: $($paths.Base)" }

    $editor = $env:EDITOR
    if (-not $editor) { $editor = "notepad.exe" }
    & $editor $file
}

function Set-ProfileModuleOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory, Position = 1)][int]$Order
    )
    Enable-ProfileModule -Name $Name -Order $Order
}
'@

New-FileSafe -Path (Join-Path $ProfileD "functions.ps1") -Content $functions

# ============================================================
# 6. aliases.ps1
# ============================================================

Write-Step "Writing aliases.ps1"

$aliases = @'
# ============================================================
# Aliases
# ============================================================

# --- Navigation ----------------------------------------------
Set-Alias -Name ll   -Value Get-ChildItem
Set-Alias -Name la   -Value Get-ChildItem
Set-Alias -Name grep -Value Select-String

# --- Linting -------------------------------------------------
if (Get-Command Invoke-PSLint -ErrorAction SilentlyContinue) {
    Set-Alias -Name lint -Value Invoke-PSLint
}

# --- Git helpers ---------------------------------------------
function gs  { git status @args }
function gd  { git diff @args }
function gl  { git log --oneline --graph --decorate -20 @args }
function gco { git checkout @args }
function gb  { git branch @args }

# --- Profile management --------------------------------------
Set-Alias -Name ep  -Value Edit-Profile
Set-Alias -Name epd -Value Edit-ProfileD
Set-Alias -Name rp  -Value Reload-Profile
Set-Alias -Name clink-register -Value Register-ClinkScripts

# --- Profile module manager ----------------------------------
Set-Alias -Name pm     -Value Get-ProfileModule
Set-Alias -Name pml    -Value Get-ProfileModule
Set-Alias -Name pmnew  -Value New-ProfileModule
Set-Alias -Name pmen   -Value Enable-ProfileModule
Set-Alias -Name pmdis  -Value Disable-ProfileModule
Set-Alias -Name pmrm   -Value Remove-ProfileModule
Set-Alias -Name pmedit -Value Edit-ProfileModule

function pm-clink { Get-ProfileModule -Kind Clink }
function pm-rules { Get-ProfileModule -Kind Analyzer }
function pm-ps    { Get-ProfileModule -Kind PowerShell }

# --- Menu ----------------------------------------------------
Set-Alias -Name menu -Value Show-ProfileMenuMain
Set-Alias -Name m    -Value Show-ProfileMenuMain
'@

New-FileSafe -Path (Join-Path $ProfileD "aliases.ps1") -Content $aliases

# ============================================================
# 7. prompt.ps1
# ============================================================

Write-Step "Writing prompt.ps1"

$prompt = @'
# ============================================================
# Prompt
# ============================================================

function prompt {
    $cwd      = $ExecutionContext.SessionState.Path.CurrentLocation
    $branch   = Get-GitBranch
    $elevated = if (Test-Admin) { " [admin]" } else { "" }
    $gitPart  = if ($branch)   { " ($branch)" } else { "" }

    "PS $cwd$gitPart$elevated> "
}
'@

New-FileSafe -Path (Join-Path $ProfileD "prompt.ps1") -Content $prompt

# ============================================================
# 8. psreadline.ps1
# ============================================================

Write-Step "Writing psreadline.ps1"

$psreadline = @'
# ============================================================
# PSReadLine
# ============================================================

if (-not (Get-Module -Name PSReadLine -ListAvailable)) { return }
Import-Module PSReadLine -ErrorAction SilentlyContinue

Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineOption -MaximumHistoryCount 10000

Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Key Ctrl+d    -Function DeleteCharOrExit
'@

New-FileSafe -Path (Join-Path $ProfileD "psreadline.ps1") -Content $psreadline

# ============================================================
# 9. clink.ps1
# ============================================================

Write-Step "Writing clink.ps1"

$clink = @'
# ============================================================
# Clink Integration
# ============================================================

if (Get-Command clink -ErrorAction SilentlyContinue) {
    if (Test-Path $Global:ClinkScriptDir) {
        & clink installscripts $Global:ClinkScriptDir 2>$null | Out-Null
    }
}
'@

New-FileSafe -Path (Join-Path $ProfileD "clink.ps1") -Content $clink

# ============================================================
# 10. menu.ps1
# ============================================================

Write-Step "Writing menu.ps1"

$menu = @'
# ============================================================
# Profile Menu
# ============================================================

# --- Gum helpers ---------------------------------------------
function Test-Gum {
    return [bool](Get-Command gum -ErrorAction SilentlyContinue)
}

function Show-Banner {
    param([string]$Title, [string]$Subtitle = "")

    if (Test-Gum) {
        $args = @(
            "--border", "double",
            "--margin", "1 2",
            "--padding", "1 2",
            "--foreground", "212",
            "--border-foreground", "212",
            $Title
        )
        if ($Subtitle) { $args += $Subtitle }
        gum style @args
    } else {
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor Magenta
        if ($Subtitle) { Write-Host "  $Subtitle" -ForegroundColor DarkGray }
        Write-Host ""
    }
}

function Read-MenuChoice {
    param(
        [Parameter(Mandatory)][string]$Header,
        [Parameter(Mandatory)][string[]]$Choices
    )

    if (Test-Gum) {
        $pick = gum choose @("--header", $Header, @Choices)
        return $pick
    } else {
        Write-Host ""
        Write-Host $Header -ForegroundColor Cyan
        for ($i = 0; $i -lt $Choices.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $Choices[$i])
        }
        $raw = Read-Host "Select"
        if ($raw -match '^\d+$') {
            $idx = [int]$raw - 1
            if ($idx -ge 0 -and $idx -lt $Choices.Count) { return $Choices[$idx] }
        }
        return $null
    }
}

function Read-TextInput {
    param([string]$Placeholder = "")

    if (Test-Gum) {
        if ($Placeholder) {
            return gum input --placeholder $Placeholder
        } else {
            return gum input
        }
    } else {
        return Read-Host "Enter value"
    }
}

function Read-Confirm {
    param([string]$Prompt, [bool]$Default = $false)

    if (Test-Gum) {
        $defaultFlag = if ($Default) { "--default=true" } else { "--default=false" }
        gum confirm $Prompt $defaultFlag
        return ($LASTEXITCODE -eq 0)
    } else {
        $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
        $answer = Read-Host "$Prompt $suffix"
        if (-not $answer) { return $Default }
        return ($answer -match '^(y|yes)$')
    }
}

function Show-Message {
    param([string]$Message, [string]$Kind = "info")

    $color = switch ($Kind) {
        "info"    { "212" }
        "success" { "82"  }
        "warn"    { "214" }
        "error"   { "196" }
        default   { "212" }
    }

    if (Test-Gum) {
        gum style --foreground $color --margin "0 2" $Message
    } else {
        $fg = switch ($Kind) {
            "success" { "Green" }
            "warn"    { "Yellow" }
            "error"   { "Red" }
            default   { "Magenta" }
        }
        Write-Host $Message -ForegroundColor $fg
    }
}

function Pause-Menu {
    if (Test-Gum) {
        gum style --foreground 244 "Press any key to continue"
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } else {
        $null = Read-Host "Press Enter to continue"
    }
}

# ============================================================
# Kind submenu
# ============================================================

function Show-KindSubmenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("PowerShell","Clink","Analyzer")]
        [string]$Kind
    )

    while ($true) {
        Clear-Host
        Show-Banner -Title "$Kind Modules" -Subtitle "Operations scoped to $Kind"

        $choice = Read-MenuChoice -Header "$Kind" -Choices @(
            "List",
            "Create",
            "Edit",
            "Enable",
            "Disable",
            "Remove",
            "Duplicate",
            "Show details",
            "Back"
        )
        if (-not $choice -or $choice -eq "Back") { return }

        try {
            switch -Regex ($choice) {
                "^List"         { Invoke-KindListFlow       -Kind $Kind }
                "^Create"       { Invoke-KindCreateFlow     -Kind $Kind }
                "^Edit"         { Invoke-KindEditFlow       -Kind $Kind }
                "^Enable"       { Invoke-KindToggleFlow     -Kind $Kind -Action Enable }
                "^Disable"      { Invoke-KindToggleFlow     -Kind $Kind -Action Disable }
                "^Remove"       { Invoke-KindRemoveFlow     -Kind $Kind }
                "^Duplicate"    { Invoke-KindDuplicateFlow  -Kind $Kind }
                "^Show details" { Invoke-KindDetailsFlow    -Kind $Kind }
            }
        } catch {
            Show-Message "Error: $_" -Kind error
            Pause-Menu
        }
    }
}

function Invoke-KindListFlow {
    param([string]$Kind)
    Get-ProfileModule -Kind $Kind | Format-Table -AutoSize
    Pause-Menu
}

function Invoke-KindCreateFlow {
    param([string]$Kind)

    $name = Read-TextInput -Placeholder "Module name (no extension)"
    if (-not $name) { return }

    $templates = switch ($Kind) {
        "PowerShell" { @("Blank","Function","Alias","Hook") }
        "Clink"      { @("Preexec","Prompt","Complete","Keybind") }
        "Analyzer"   { @("CommandRule","FunctionRule","FileRule") }
    }
    $template = Read-MenuChoice -Header "Template" -Choices $templates
    if (-not $template) { return }

    $params = @{ Name = $name; Kind = $Kind; Template = $template }
    if ($Kind -eq "PowerShell" -and (Read-Confirm "Enable immediately?" $true)) {
        $params.Enable = $true
    }

    $file = New-ProfileModule @params
    Show-Message "Created: $($file.FullName)" -Kind success
    Pause-Menu
}

function Invoke-KindEditFlow {
    param([string]$Kind)

    $mods = Get-ProfileModule -Kind $Kind
    if (-not $mods) { Show-Message "No $Kind modules." -Kind warn; Pause-Menu; return }

    $labels = $mods | ForEach-Object { "{0,-25} {1}" -f $_.Name, $_.State }
    $pick   = Read-MenuChoice -Header "Edit $Kind" -Choices $labels
    if (-not $pick) { return }

    $picked = $mods[ [array]::IndexOf($labels, $pick) ]
    Edit-ProfileModule -Name $picked.Name -Kind $Kind
}

function Invoke-KindToggleFlow {
    param(
        [string]$Kind,
        [ValidateSet("Enable","Disable")][string]$Action
    )

    $targets = Get-ProfileModule -Kind $Kind | Where-Object {
        if ($Action -eq "Enable") { $_.State -eq "Disabled" } else { $_.State -eq "Enabled" }
    }
    if (-not $targets) {
        Show-Message "No $Kind modules to $($Action.ToLower())." -Kind warn
        Pause-Menu
        return
    }

    $labels = $targets | ForEach-Object { "{0,-25} {1}" -f $_.Name, $_.State }
    $pick   = Read-MenuChoice -Header "$Action $Kind" -Choices $labels
    if (-not $pick) { return }

    $picked = $targets[ [array]::IndexOf($labels, $pick) ]

    if ($Action -eq "Enable") {
        Enable-ProfileModule  -Name $picked.Name -Kind $Kind
    } else {
        Disable-ProfileModule -Name $picked.Name -Kind $Kind
    }
    Pause-Menu
}

function Invoke-KindRemoveFlow {
    param([string]$Kind)

    $mods = Get-ProfileModule -Kind $Kind
    if (-not $mods) { Show-Message "No $Kind modules." -Kind warn; Pause-Menu; return }

    $labels = $mods | ForEach-Object { "{0,-25} {1}" -f $_.Name, $_.State }
    $pick   = Read-MenuChoice -Header "Remove $Kind" -Choices $labels
    if (-not $pick) { return }

    $picked = $mods[ [array]::IndexOf($labels, $pick) ]
    if (Read-Confirm "Delete '$($picked.Name)' permanently?" $false) {
        Remove-ProfileModule -Name $picked.Name -Kind $Kind -Force
        Show-Message "Removed." -Kind success
    }
    Pause-Menu
}

function Invoke-KindDuplicateFlow {
    param([string]$Kind)

    $mods = Get-ProfileModule -Kind $Kind
    if (-not $mods) { Show-Message "No $Kind modules." -Kind warn; Pause-Menu; return }

    $labels = $mods | ForEach-Object { "{0,-25} {1}" -f $_.Name, $_.State }
    $pick   = Read-MenuChoice -Header "Duplicate $Kind" -Choices $labels
    if (-not $pick) { return }

    $picked  = $mods[ [array]::IndexOf($labels, $pick) ]
    $newName = Read-TextInput -Placeholder "New name (no extension)"
    if (-not $newName) { return }

    $srcPaths = Resolve-ProfileModulePath -Name $picked.Name -Kind $Kind
    $dstPaths = Resolve-ProfileModulePath -Name $newName    -Kind $Kind

    if ((Test-Path $dstPaths.Enabled) -or (Test-Path $dstPaths.Disabled)) {
        Show-Message "Target exists." -Kind error
        Pause-Menu
        return
    }

    $src = if (Test-Path $srcPaths.Enabled) { $srcPaths.Enabled } else { $srcPaths.Disabled }
    Copy-Item -Path $src -Destination $dstPaths.Enabled

    $content = Get-Content -Path $dstPaths.Enabled -Raw
    $content = $content -replace [regex]::Escape($picked.Name), $newName
    Set-Content -Path $dstPaths.Enabled -Value $content -Encoding UTF8

    Show-Message "Duplicated to $($dstPaths.Enabled)" -Kind success
    Pause-Menu
}

function Invoke-KindDetailsFlow {
    param([string]$Kind)

    $mods = Get-ProfileModule -Kind $Kind
    if (-not $mods) { Show-Message "No $Kind modules." -Kind warn; Pause-Menu; return }

    $labels = $mods | ForEach-Object { "{0,-25} {1}" -f $_.Name, $_.State }
    $pick   = Read-MenuChoice -Header "Details" -Choices $labels
    if (-not $pick) { return }

    $picked = $mods[ [array]::IndexOf($labels, $pick) ]

    Clear-Host
    Show-Banner -Title $picked.Name -Subtitle "$Kind module"

    [ordered]@{
        Kind     = $picked.Kind
        Name     = $picked.Name
        State    = $picked.State
        Order    = $picked.Order
        SizeKB   = $picked.SizeKB
        Modified = $picked.Modified
        Path     = $picked.Path
    }.GetEnumerator() | ForEach-Object { "{0,-10} {1}" -f ($_.Key + ":"), $_.Value }

    Write-Host ""
    Write-Host "--- Preview (first 30 lines) ---" -ForegroundColor Cyan
    Get-Content -Path $picked.Path -TotalCount 30

    Pause-Menu
}

# ============================================================
# Modules router
# ============================================================

function Show-ModuleMenu {
    while ($true) {
        Clear-Host
        Show-Banner -Title "Modules" -Subtitle "Pick a module kind to manage"

        $choice = Read-MenuChoice -Header "Module kind" -Choices @(
            "PowerShell modules",
            "Clink scripts",
            "Analyzer rules",
            "All modules (flat list)",
            "Create module (choose kind)",
            "Back"
        )
        if (-not $choice -or $choice -eq "Back") { return }

        switch -Regex ($choice) {
            "^PowerShell modules" { Show-KindSubmenu -Kind PowerShell }
            "^Clink scripts"      { Show-KindSubmenu -Kind Clink }
            "^Analyzer rules"     { Show-KindSubmenu -Kind Analyzer }
            "^All modules" {
                Get-ProfileModule | Format-Table -AutoSize
                Pause-Menu
            }
            "^Create module"      { Invoke-CreateModuleFlow }
        }
    }
}

function Invoke-CreateModuleFlow {
    $name = Read-TextInput -Placeholder "Module name (no extension)"
    if (-not $name) { return }

    $kind = Read-MenuChoice -Header "Module kind" -Choices @("PowerShell","Clink","Analyzer")
    if (-not $kind) { return }

    $templates = switch ($kind) {
        "PowerShell" { @("Blank","Function","Alias","Hook") }
        "Clink"      { @("Preexec","Prompt","Complete","Keybind") }
        "Analyzer"   { @("CommandRule","FunctionRule","FileRule") }
    }
    $template = Read-MenuChoice -Header "Template" -Choices $templates
    if (-not $template) { return }

    $enable = $false
    if ($kind -eq "PowerShell") { $enable = Read-Confirm "Enable immediately?" $true }

    $params = @{ Name = $name; Kind = $kind; Template = $template }
    if ($enable) { $params.Enable = $true }

    $file = New-ProfileModule @params
    Show-Message "Created: $($file.FullName)" -Kind success
    Pause-Menu
}

# ============================================================
# Linter submenu
# ============================================================

function Show-LintMenu {
    while ($true) {
        Clear-Host
        Show-Banner -Title "Linter" -Subtitle "PSScriptAnalyzer"

        $choice = Read-MenuChoice -Header "Linter" -Choices @(
            "Lint a file",
            "Lint a directory",
            "Lint current directory",
            "Edit PSScriptAnalyzer settings",
            "List analyzer rules",
            "Back"
        )
        if (-not $choice -or $choice -eq "Back") { return }

        try {
            switch -Regex ($choice) {
                "^Lint a file" {
                    $path = Read-TextInput -Placeholder "Path to .ps1 file"
                    if ($path) { Invoke-PSLint -Path $path | Format-Table -AutoSize }
                    Pause-Menu
                }
                "^Lint a directory" {
                    $path = Read-TextInput -Placeholder "Directory path"
                    if ($path) { Invoke-PSLint -Path $path -Recurse | Format-Table -AutoSize }
                    Pause-Menu
                }
                "^Lint current" {
                    Invoke-PSLint -Path . -Recurse | Format-Table -AutoSize
                    Pause-Menu
                }
                "^Edit PSScriptAnalyzer" {
                    $editor = $env:EDITOR; if (-not $editor) { $editor = "notepad.exe" }
                    & $editor $Global:PSLintSettings
                }
                "^List analyzer" {
                    Get-ProfileModule -Kind Analyzer | Format-Table -AutoSize
                    Pause-Menu
                }
            }
        } catch {
            Show-Message "Error: $_" -Kind error
            Pause-Menu
        }
    }
}

# ============================================================
# Clink submenu
# ============================================================

function Show-ClinkMenu {
    while ($true) {
        Clear-Host
        Show-Banner -Title "Clink" -Subtitle "cmd.exe integration"

        $choice = Read-MenuChoice -Header "Clink" -Choices @(
            "Register script directory",
            "Show Clink info",
            "List Clink scripts",
            "Edit Clink script",
            "Back"
        )
        if (-not $choice -or $choice -eq "Back") { return }

        try {
            switch -Regex ($choice) {
                "^Register"       { Register-ClinkScripts; Pause-Menu }
                "^Show Clink"     {
                    if (Get-Command clink -ErrorAction SilentlyContinue) { clink info }
                    else { Show-Message "clink.exe not found on PATH." -Kind warn }
                    Pause-Menu
                }
                "^List Clink"     { Get-ProfileModule -Kind Clink | Format-Table -AutoSize; Pause-Menu }
                "^Edit Clink"     { Invoke-KindEditFlow -Kind Clink }
            }
        } catch {
            Show-Message "Error: $_" -Kind error
            Pause-Menu
        }
    }
}

# ============================================================
# Profile submenu
# ============================================================

function Show-ProfileMenu {
    while ($true) {
        Clear-Host
        Show-Banner -Title "Profile" -Subtitle "Loader and module registry"

        $choice = Read-MenuChoice -Header "Profile" -Choices @(
            "Reload profile",
            "Edit profile loader",
            "Open Profile.d folder",
            "Show loaded modules",
            "Reset modules.json",
            "Back"
        )
        if (-not $choice -or $choice -eq "Back") { return }

        try {
            switch -Regex ($choice) {
                "^Reload profile"      { Reload-Profile; Show-Message "Reloaded." -Kind success; Pause-Menu }
                "^Edit profile loader" { Edit-Profile }
                "^Open Profile.d"      { Start-Process explorer.exe (Split-Path -Parent $PROFILE.CurrentUserCurrentHost) }
                "^Show loaded"         { Get-ProfileModule | Format-Table -AutoSize; Pause-Menu }
                "^Reset modules.json"  { Invoke-ResetModulesFlow }
            }
        } catch {
            Show-Message "Error: $_" -Kind error
            Pause-Menu
        }
    }
}

function Invoke-ResetModulesFlow {
    $profileD = Join-Path (Split-Path -Parent $PROFILE.CurrentUserCurrentHost) "Profile.d"
    $current  = Get-ChildItem -Path $profileD -Filter *.ps1 -File |
        Where-Object { $_.Name -notmatch '\.disabled$' } |
        Select-Object -ExpandProperty Name

    if (Read-Confirm "Rebuild modules.json from current files?" $true) {
        $config = Get-ProfileModuleConfig
        $config.loadOrder = @($current)
        $config.disabled  = @()
        Save-ProfileModuleConfig -Config $config
        Show-Message "modules.json rebuilt." -Kind success
    }
    Pause-Menu
}

# ============================================================
# Tools submenu
# ============================================================

function Show-ToolsSubmenu {
    while ($true) {
        Clear-Host
        Show-Banner -Title "Tools" -Subtitle "Utilities and diagnostics"

        $choice = Read-MenuChoice -Header "Tools" -Choices @(
            "Show environment info",
            "Show git branch",
            "Show port owner",
            "Create temp script",
            "Open Profile.d in Explorer",
            "Open tools folder",
            "Open rules folder",
            "Open Clink scripts folder",
            "Back"
        )
        if (-not $choice -or $choice -eq "Back") { return }

        try {
            switch -Regex ($choice) {
                "^Show environment" {
                    [pscustomobject]@{
                        PSVersion      = $PSVersionTable.PSVersion.ToString()
                        Edition        = $PSVersionTable.PSEdition
                        ProfilePath    = $PROFILE.CurrentUserCurrentHost
                        ProfileD       = Split-Path -Parent $PROFILE.CurrentUserCurrentHost
                        PSLintScript   = $Global:PSLintScript
                        ClinkScriptDir = $Global:ClinkScriptDir
                        RulesDir       = $Global:RulesDir
                        HasGum         = Test-Gum
                        HasClink       = [bool](Get-Command clink -ErrorAction SilentlyContinue)
                        HasPSSA        = [bool](Get-Module PSScriptAnalyzer -ListAvailable)
                    } | Format-List
                    Pause-Menu
                }
                "^Show git branch" {
                    $b = Get-GitBranch
                    if ($b) { Show-Message "Branch: $b" -Kind success }
                    else    { Show-Message "Not in a git repository." -Kind warn }
                    Pause-Menu
                }
                "^Show port owner" {
                    $p = Read-TextInput -Placeholder "TCP port number"
                    if ($p -match '^\d+$') { Get-PortOwner -Port ([int]$p) | Format-Table -AutoSize }
                    Pause-Menu
                }
                "^Create temp script" {
                    $body = Read-TextInput -Placeholder "Single-line script body"
                    if ($body) {
                        $f = New-TempScript -Content $body
                        Show-Message "Created: $f" -Kind success
                    }
                    Pause-Menu
                }
                "^Open Profile.d"    { Start-Process explorer.exe (Split-Path -Parent $PROFILE.CurrentUserCurrentHost) }
                "^Open tools folder" { Start-Process explorer.exe $Global:PSToolsRoot }
                "^Open rules folder" { Start-Process explorer.exe $Global:RulesDir }
                "^Open Clink"        { Start-Process explorer.exe $Global:ClinkScriptDir }
            }
        } catch {
            Show-Message "Error: $_" -Kind error
            Pause-Menu
        }
    }
}

# ============================================================
# History submenu
# ============================================================

function Show-HistorySubmenu {
    while ($true) {
        Clear-Host
        Show-Banner -Title "History" -Subtitle "Command history and PSReadLine"

        $choice = Read-MenuChoice -Header "History" -Choices @(
            "Search history",
            "Show last 50 commands",
            "Clear history (this session)",
            "Clear history file",
            "Show history file path",
            "Back"
        )
        if (-not $choice -or $choice -eq "Back") { return }

        try {
            switch -Regex ($choice) {
                "^Search history" {
                    $q = Read-TextInput -Placeholder "Search term"
                    if ($q) {
                        Get-History | Where-Object { $_.CommandLine -match [regex]::Escape($q) } |
                            Format-Table Id, CommandLine -AutoSize -Wrap
                    }
                    Pause-Menu
                }
                "^Show last 50" {
                    Get-History -Count 50 | Format-Table Id, CommandLine -AutoSize -Wrap
                    Pause-Menu
                }
                "^Clear history \(this" {
                    Clear-History
                    Show-Message "Session history cleared." -Kind success
                    Pause-Menu
                }
                "^Clear history file" {
                    if (Read-Confirm "Delete the PSReadLine history file?" $false) {
                        $histFile = (Get-PSReadLineOption).HistorySavePath
                        if (Test-Path $histFile) { Remove-Item $histFile -Force }
                        Show-Message "History file removed." -Kind success
                    }
                    Pause-Menu
                }
                "^Show history file" {
                    $histFile = (Get-PSReadLineOption).HistorySavePath
                    Show-Message "Path: $histFile" -Kind info
                    if (Test-Path $histFile) {
                        $size = (Get-Item $histFile).Length
                        Show-Message "Size: $([math]::Round($size/1KB,2)) KB" -Kind info
                    }
                    Pause-Menu
                }
            }
        } catch {
            Show-Message "Error: $_" -Kind error
            Pause-Menu
        }
    }
}

# ============================================================
# Setup submenu
# ============================================================

function Show-SetupMenu {
    while ($true) {
        Clear-Host
        Show-Banner -Title "Setup" -Subtitle "Install optional dependencies"

        $choice = Read-MenuChoice -Header "Setup" -Choices @(
            "Install PSScriptAnalyzer",
            "Install Gum",
            "Install Clink",
            "Show environment info",
            "Back"
        )
        if (-not $choice -or $choice -eq "Back") { return }

        try {
            switch -Regex ($choice) {
                "^Install PSScriptAnalyzer" {
                    if (Get-Module -Name PSScriptAnalyzer -ListAvailable) {
                        Show-Message "Already installed." -Kind success
                    } else {
                        Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber
                        Show-Message "Installed." -Kind success
                    }
                    Pause-Menu
                }
                "^Install Gum" {
                    if (Get-Command gum -ErrorAction SilentlyContinue) {
                        Show-Message "Already installed." -Kind success
                    } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
                        winget install --id charmbracelet.gum -e
                        Show-Message "Install requested via winget." -Kind success
                    } else {
                        Show-Message "winget not available. Install Gum manually." -Kind warn
                    }
                    Pause-Menu
                }
                "^Install Clink" {
                    if (Get-Command clink -ErrorAction SilentlyContinue) {
                        Show-Message "Already installed." -Kind success
                    } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
                        winget install --id chrisant996.Clink -e
                        Show-Message "Install requested via winget." -Kind success
                    } else {
                        Show-Message "winget not available. Install Clink manually." -Kind warn
                    }
                    Pause-Menu
                }
                "^Show environment" { Show-ToolsSubmenu; }
            }
        } catch {
            Show-Message "Error: $_" -Kind error
            Pause-Menu
        }
    }
}

# ============================================================
# Main menu
# ============================================================

function Show-ProfileMenuMain {
    [CmdletBinding()]
    param()

    while ($true) {
        Clear-Host
        Show-Banner -Title "PowerShell Profile" -Subtitle "Manage modules, linting, Clink, and setup"

        $choice = Read-MenuChoice -Header "Main menu" -Choices @(
            "Modules",
            "Linter",
            "Clink",
            "Profile",
            "Tools",
            "History",
            "Setup",
            "Quick lint current directory",
            "Exit"
        )

        if (-not $choice -or $choice -eq "Exit") {
            Show-Message "Bye." -Kind info
            return
        }

        switch -Regex ($choice) {
            "^Modules"    { Show-ModuleMenu }
            "^Linter"     { Show-LintMenu }
            "^Clink"      { Show-ClinkMenu }
            "^Profile"    { Show-ProfileMenu }
            "^Tools"      { Show-ToolsSubmenu }
            "^History"    { Show-HistorySubmenu }
            "^Setup"      { Show-SetupMenu }
            "^Quick lint" {
                try { Invoke-PSLint -Path . -Recurse | Format-Table -AutoSize }
                catch { Show-Message "Error: $_" -Kind error }
                Pause-Menu
            }
        }
    }
}

function menu { Show-ProfileMenuMain }
'@

New-FileSafe -Path (Join-Path $ProfileD "menu.ps1") -Content $menu

# ============================================================
# 11. Invoke-PSLint.ps1
# ============================================================

Write-Step "Writing Invoke-PSLint.ps1"

$invokePslint = @'
function Invoke-PSLint {
    <#
    .SYNOPSIS
        Runs PSScriptAnalyzer against files or directories.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Path,
        [switch]$Recurse,
        [string]$Settings,
        [switch]$Fix,
        [string]$CustomRulePath,
        [switch]$FailOnIssue
    )

    if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
        throw "PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"
    }
    if (-not (Test-Path -Path $Path)) {
        throw "Path not found: $Path"
    }

    $params = @{ Path = $Path; Recurse = $Recurse }
    if ($Settings)       { $params.Settings       = $Settings }
    if ($Fix)            { $params.Fix            = $true      }
    if ($CustomRulePath) { $params.CustomRulePath = $CustomRulePath }

    $rulesDir = Join-Path $PSScriptRoot "Rules"
    if (Test-Path $rulesDir) {
        $ruleFiles = Get-ChildItem $rulesDir -Filter *.psm1 -File |
            Where-Object { $_.Name -notmatch '\.disabled$' } |
            Select-Object -ExpandProperty FullName

        if ($ruleFiles) {
            if ($params.ContainsKey('CustomRulePath')) {
                $params.CustomRulePath = @($params.CustomRulePath) + $ruleFiles
            } else {
                $params.CustomRulePath = $ruleFiles
            }
        }
    }

    try {
        $results = Invoke-ScriptAnalyzer @params -ErrorAction Stop
    } catch {
        throw "Linter error: $_"
    }

    if (-not $results) {
        Write-Host "No issues found." -ForegroundColor Green
        return
    }

    Write-Host "Found $($results.Count) issue(s):" -ForegroundColor Yellow
    $results | Format-Table -AutoSize -Property RuleName, Severity, ScriptName, Line, Message

    if ($FailOnIssue) {
        throw "Linting failed with $($results.Count) issue(s)."
    }
    return $results
}
'@

New-FileSafe -Path (Join-Path $ToolsDir "Invoke-PSLint.ps1") -Content $invokePslint

# ============================================================
# 12. PSScriptAnalyzerSettings.psd1
# ============================================================

Write-Step "Writing PSScriptAnalyzerSettings.psd1"

$analyzerSettings = @'
@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
'@

New-FileSafe -Path (Join-Path $ToolsDir "PSScriptAnalyzerSettings.psd1") -Content $analyzerSettings

# ============================================================
# 13. pwsh.lua
# ============================================================

Write-Step "Writing pwsh.lua"

$pwshLua = @'
-- pwsh.lua
-- Clink preexec linter for pwsh and powershell commands.

local PSLINT_SCRIPT = nil  -- Set to full path of Invoke-PSLint.ps1 to enable.
local BLOCK_ON_ISSUE = true
local FAIL_ON_ISSUE  = true
local SETTINGS_FILE  = nil

local function is_powershell_command(line)
    return line:match("^%s*pwsh[%s%-]") ~= nil
        or line:match("^%s*pwsh$") ~= nil
        or line:match("^%s*powershell[%s%-]") ~= nil
        or line:match("^%s*powershell$") ~= nil
end

function clink.onprovideline(line)
    if not is_powershell_command(line) then
        return line
    end
    -- Linter invocation is a stub. Configure PSLINT_SCRIPT to enable blocking.
    return line
end
'@

New-FileSafe -Path (Join-Path $ClinkDir "pwsh.lua") -Content $pwshLua

# ============================================================
# 14. Install PSScriptAnalyzer
# ============================================================

if (-not $SkipModules) {
    Write-Step "Checking PSScriptAnalyzer"

    if (Get-Module -Name PSScriptAnalyzer -ListAvailable) {
        Write-Skip "PSScriptAnalyzer already installed."
    } else {
        Write-Host "    Installing PSScriptAnalyzer..." -ForegroundColor Yellow
        try {
            Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Ok "PSScriptAnalyzer installed."
        } catch {
            Write-Warn2 "Failed to install PSScriptAnalyzer: $_"
            Write-Warn2 "Run manually: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"
        }
    }
}

# ============================================================
# 15. Register Clink scripts
# ============================================================

if (-not $SkipClink) {
    Write-Step "Registering Clink scripts"

    if (-not (Get-Command clink -ErrorAction SilentlyContinue)) {
        Write-Warn2 "clink.exe not found on PATH. Skipping."
        Write-Warn2 "Install with: winget install --id chrisant996.Clink -e"
    } else {
        try {
            & clink installscripts $ClinkDir 2>$null | Out-Null
            Write-Ok "Registered $ClinkDir"
        } catch {
            Write-Warn2 "Clink registration failed: $_"
        }
    }
}

# ============================================================
# 16. Verify
# ============================================================

Write-Step "Verifying installation"

$expected = @(
    $ProfileFile,
    (Join-Path $ProfileD "modules.json"),
    (Join-Path $ProfileD "variables.ps1"),
    (Join-Path $ProfileD "functions.ps1"),
    (Join-Path $ProfileD "aliases.ps1"),
    (Join-Path $ProfileD "prompt.ps1"),
    (Join-Path $ProfileD "psreadline.ps1"),
    (Join-Path $ProfileD "clink.ps1"),
    (Join-Path $ProfileD "menu.ps1"),
    (Join-Path $ToolsDir "Invoke-PSLint.ps1"),
    (Join-Path $ToolsDir "PSScriptAnalyzerSettings.psd1"),
    (Join-Path $ClinkDir "pwsh.lua")
)

$missing = @()
foreach ($f in $expected) {
    if (Test-Path $f) {
        Write-Ok "OK  $f"
    } else {
        $missing += $f
        Write-Warn2 "MISSING  $f"
    }
}

Write-Host ""
if ($missing.Count -eq 0) {
    Write-Host "Setup complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Close and reopen PowerShell."
    Write-Host "  2. Run:  menu"
    Write-Host "  3. Or:   pm"
    Write-Host "  4. Or:   Invoke-PSLint -Path .\some-script.ps1"
    Write-Host ""
    Write-Host "Open a new cmd.exe window to activate the Clink Lua hook."
} else {
    Write-Host "Setup finished with $($missing.Count) missing file(s)." -ForegroundColor Yellow
}