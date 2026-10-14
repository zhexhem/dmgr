# dmgr

# PowerShell Profile

A modular, git-installable PowerShell profile with an interactive menu, a
module manager, PSScriptAnalyzer integration, and Clink support for `cmd.exe`.

The profile loads small, focused `.ps1` files from a `Profile.d` directory
instead of a single monolithic profile script. A JSON manifest controls load
order. A CLI and a TUI are provided to create, enable, disable, edit, and
remove modules of three kinds: PowerShell, Clink, and PSScriptAnalyzer rules.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Repository Layout](#repository-layout)
- [Installed Layout](#installed-layout)
- [Usage](#usage)
  - [Interactive menu](#interactive-menu)
  - [Command line](#command-line)
  - [Module manager](#module-manager)
  - [Linter](#linter)
  - [Clink integration](#clink-integration)
- [Module Kinds](#module-kinds)
- [Configuration](#configuration)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)
- [Extending](#extending)
- [License](#license)

---

## Features

- Modular profile. Each concern lives in its own file under `Profile.d`.
- Manifest-driven load order via `Profile.d\modules.json`.
- Interactive menu (`menu` or `m`) built on Gum when available, with a
  plain `Read-Host` fallback when Gum is not installed.
- Module manager (`pm`, `pmnew`, `pmen`, `pmdis`, `pmrm`, `pmedit`) for
  three module kinds:
  - PowerShell `.ps1` files loaded at profile time.
  - Clink `.lua` files loaded by Clink into `cmd.exe`.
  - PSScriptAnalyzer `.psm1` rule modules auto-discovered by the linter.
- `Invoke-PSLint` wrapper around PSScriptAnalyzer with custom rule support.
- Auto-fix support (`-Fix`) and CI-friendly failure mode (`-FailOnIssue`).
- Optional PSReadLine preexec hook that lints commands before they run.
- Optional Clink preexec hook for `pwsh` and `powershell` invocations.
- Git-based installer with install, update, and uninstall paths.
- No elevation required. Everything is user-scoped.

---

## Requirements

| Component | Required | Notes |
|---|---|---|
| Windows 10 or 11 | Yes | Profile paths target Windows. |
| PowerShell 7+ | Recommended | Windows PowerShell 5.1 is supported. |
| Git | Yes | Used by `install.ps1`. Install via `winget install --id Git.Git -e`. |
| PSScriptAnalyzer | Recommended | Installed automatically by `setup.ps1` if missing. |
| Gum | Optional | Enables the styled TUI. Install via `winget install --id charmbracelet.gum -e`. |
| Clink | Optional | Enables the `cmd.exe` preexec hook. Install via `winget install --id chrisant996.Clink -e`. |

---

## Installation

### From a git repository

```powershell
git clone https://github.com/me/pwsh-profile.git
cd pwsh-profile
.\install.ps1 -RepoUrl https://github.com/me/pwsh-profile.git
```

Or install directly without a local clone:

```powershell
.\install.ps1 -RepoUrl https://github.com/me/pwsh-profile.git
```

The installer clones the repo into `$HOME\.powershell-profile` and runs
`setup.ps1` from inside the clone.

### Setting a default repository

Set `$env:PSPROFILE_REPO` once and the installer becomes a one-liner:

```powershell
[Environment]::SetEnvironmentVariable(
    "PSPROFILE_REPO",
    "https://github.com/me/pwsh-profile.git",
    "User"
)
```

Then:

```powershell
.\install.ps1
```

### Installer flags

| Flag | Effect |
|---|---|
| `-RepoUrl <url>` | Repository to clone. |
| `-Branch <name>` | Branch or tag to check out. Default: `main`. |
| `-InstallDir <path>` | Clone destination. Default: `$HOME\.powershell-profile`. |
| `-Update` | Pull latest and re-run setup. |
| `-Uninstall` | Remove profile files and optionally the cloned repo. |
| `-Force` | Pass through to `setup.ps1` to overwrite without backups. |
| `-SkipClink` | Skip Clink registration. |
| `-SkipModules` | Do not install PSScriptAnalyzer. |

After installation, close and reopen PowerShell, then run `menu`.

---

## Repository Layout

```
pwsh-profile/
├── install.ps1          Git-based installer
├── setup.ps1            Deploys profile files to $PROFILE
├── README.md
└── LICENSE
```

`setup.ps1` embeds every profile file as a here-string. If you later split
those into separate files, mirror this structure in the repo:

```
pwsh-profile/
├── install.ps1
├── setup.ps1
├── README.md
├── templates\
│   ├── variables.ps1
│   ├── functions.ps1
│   ├── aliases.ps1
│   ├── prompt.ps1
│   ├── psreadline.ps1
│   ├── clink.ps1
│   └── menu.ps1
├── tools\
│   ├── Invoke-PSLint.ps1
│   ├── PSScriptAnalyzerSettings.psd1
│   └── ClinkScripts\
│       └── pwsh.lua
└── rules\
```

---

## Installed Layout

After `setup.ps1` runs:

```
%USERPROFILE%\Documents\PowerShell\
├── Microsoft.PowerShell_profile.ps1    Loader
└── Profile.d\
    ├── modules.json                    Manifest
    ├── variables.ps1                   Paths and preferences
    ├── functions.ps1                   Function definitions and manager
    ├── aliases.ps1                     Aliases and thin wrappers
    ├── prompt.ps1                      Custom prompt
    ├── psreadline.ps1                  PSReadLine options and key handlers
    ├── clink.ps1                       Clink registration
    ├── menu.ps1                        Interactive menu and submenus
    └── tools\
        ├── Invoke-PSLint.ps1
        ├── PSScriptAnalyzerSettings.psd1
        ├── ClinkScripts\
        │   └── pwsh.lua
        └── Rules\
```

For Windows PowerShell 5.1, the path is
`%USERPROFILE%\Documents\WindowsPowerShell\` instead.

---

## Usage

### Interactive menu

```powershell
menu
```

Or with the short alias:

```powershell
m
```

Main menu structure:

```
PowerShell Profile
├── Modules
│   ├── PowerShell modules
│   ├── Clink scripts
│   ├── Analyzer rules
│   ├── All modules (flat list)
│   └── Create module (choose kind)
├── Linter
├── Clink
├── Profile
├── Tools
├── History
├── Setup
├── Quick lint current directory
└── Exit
```

Each kind submenu supports: List, Create, Edit, Enable, Disable, Remove,
Duplicate, and Show details.

### Command line

| Alias | Command | Purpose |
|---|---|---|
| `menu` / `m` | `Show-ProfileMenuMain` | Open the interactive menu. |
| `pm` / `pml` | `Get-ProfileModule` | List modules. |
| `pmnew` | `New-ProfileModule` | Create a module. |
| `pmen` | `Enable-ProfileModule` | Enable a disabled module. |
| `pmdis` | `Disable-ProfileModule` | Disable a module without deleting it. |
| `pmrm` | `Remove-ProfileModule` | Delete a module. |
| `pmedit` | `Edit-ProfileModule` | Open a module in `$env:EDITOR`. |
| `pm-ps` | `Get-ProfileModule -Kind PowerShell` | List PowerShell modules. |
| `pm-clink` | `Get-ProfileModule -Kind Clink` | List Clink scripts. |
| `pm-rules` | `Get-ProfileModule -Kind Analyzer` | List analyzer rules. |
| `lint` | `Invoke-PSLint` | Run PSScriptAnalyzer. |
| `ep` | `Edit-Profile` | Open the profile loader. |
| `rp` | `Reload-Profile` | Reload the profile in place. |
| `clink-register` | `Register-ClinkScripts` | Register the Clink scripts folder. |

### Module manager

List all modules:

```powershell
pm
```

List only Clink scripts:

```powershell
pm-clink
```

Create a new PowerShell module with a function stub and enable it:

```powershell
pmnew -Name git-helpers -Template Function -Enable
```

Create a Clink preexec hook:

```powershell
pmnew -Name history-guard -Kind Clink -Template Preexec
```

Create a PSScriptAnalyzer rule:

```powershell
pmnew -Name NoInvokeExpression -Kind Analyzer -Template CommandRule
```

Disable a module:

```powershell
pmdis clink.ps1
```

Re-enable it at position 2:

```powershell
pmen clink.ps1 -Order 2
```

Remove permanently:

```powershell
pmrm old-stuff -Force
```

Edit:

```powershell
pmedit git-helpers
```

### Linter

Lint a single file:

```powershell
Invoke-PSLint -Path .\MyScript.ps1
```

Lint a directory recursively:

```powershell
Invoke-PSLint -Path .\src\ -Recurse
```

Use a custom settings file:

```powershell
Invoke-PSLint -Path .\src\ -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

Fail the build on any issue (useful for CI):

```powershell
Invoke-PSLint -Path .\src\ -Recurse -FailOnIssue
```

Auto-fix where possible:

```powershell
Invoke-PSLint -Path .\MyScript.ps1 -Fix
```

Custom rules placed in `tools\Rules\*.psm1` are auto-discovered on every run.

### Clink integration

Clink extends `cmd.exe` with readline-style editing and a Lua scripting API.
The profile registers `tools\ClinkScripts\` so any `.lua` file placed there is
loaded into every new `cmd.exe` window.

Register manually:

```powershell
clink-register
```

Verify registration:

```cmd
clink info
```

The default `pwsh.lua` ships with the linter stubbed out. To enable preexec
linting of `pwsh` and `powershell` commands, edit `pwsh.lua` and set
`PSLINT_SCRIPT` to the full path of `Invoke-PSLint.ps1`.

---

## Module Kinds

| Kind | Extension | Location | Discovery |
|---|---|---|---|
| PowerShell | `.ps1` | `Profile.d\` | Loader reads `modules.json` |
| Clink | `.lua` | `tools\ClinkScripts\` | Clink scans the registered directory |
| Analyzer | `.psm1` | `tools\Rules\` | `Invoke-PSLint` auto-includes as `-CustomRulePath` |

Disabling a module appends `.disabled` to the filename. Each consumer skips
those automatically:

- The loader matches only `*.ps1`, so `*.ps1.disabled` is ignored.
- Clink loads only `*.lua`, so `*.lua.disabled` is ignored.
- `Invoke-PSLint` filters for `*.psm1` and excludes `.disabled`.

To restore a disabled module, use `pmen`, which renames it back and, for
PowerShell modules, reinserts it into `modules.json`.

---

## Configuration

### `modules.json`

```json
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
```

- `loadOrder` controls execution sequence.
- `disabled` is informational. The `.disabled` suffix on disk is the source
  of truth for skipping.

If the file is missing or malformed, the loader falls back to a static order.
Run `Invoke-ResetModulesFlow` from the menu, or manually rebuild it, to
regenerate from the current files.

### Editor

`Edit-Profile`, `Edit-ProfileModule`, and `Edit-ProfileD` use `$env:EDITOR`
when set, otherwise `notepad.exe`.

```powershell
$env:EDITOR = "code --wait"
```

### PSScriptAnalyzer settings

`tools\PSScriptAnalyzerSettings.psd1` is created with a conservative default:

```powershell
@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
```

Pass it explicitly to `Invoke-PSLint` with `-Settings`. It is not applied by
default.

---

## Updating

```powershell
.\install.ps1 -Update
```

This fetches, checks out the target branch, fast-forwards, and re-runs
`setup.ps1`. Pulls that would require a merge fail loudly; resolve manually
in the install directory.

To update a specific branch:

```powershell
.\install.ps1 -Update -Branch develop
```

To update without backing up existing files:

```powershell
.\install.ps1 -Update -Force
```

Without `-Force`, `setup.ps1` backs up each existing file to `<file>.bak`
before overwriting. This applies to profile files only, not to user-created
modules inside `Profile.d` that are not part of the repo.

---

## Uninstalling

```powershell
.\install.ps1 -Uninstall
```

This removes:

- `Profile.d\`
- `Microsoft.PowerShell_profile.ps1`

It then asks whether to also delete the cloned repository at
`$HOME\.powershell-profile`.

After uninstalling, open a new PowerShell window to reset the session.

To reset PSReadLine's Enter binding separately:

```powershell
Set-PSReadLineKeyHandler -Key Enter -Function AcceptLine
```

---

## Troubleshooting

**Profile does not load**

Check that the profile file path matches the shell you are in. PowerShell 7
uses `Documents\PowerShell\`, while Windows PowerShell 5.1 uses
`Documents\WindowsPowerShell\`.

```powershell
$PROFILE.CurrentUserCurrentHost
```

**`modules.json` parse errors**

The loader logs a warning and falls back to a static order. Rebuild the file
from the Profile menu or delete it entirely to trigger the fallback.

**`Invoke-PSLint` reports PSScriptAnalyzer missing**

Install it manually:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
```

**Clink scripts do not load**

Confirm Clink is on PATH and the scripts directory is registered:

```cmd
clink info
```

The `scripts` line in the output lists registered directories. If
`tools\ClinkScripts` is not listed, run `clink-register`.

**Menu falls back to plain text**

Gum is not installed. Install it with:

```powershell
winget install --id charmbracelet.gum -e
```

The fallback uses `Read-Host` and `Out-GridView` and is fully functional.

**Menu is slow to open**

Each submenu calls `Clear-Host`. If you prefer scroll-back, remove those
calls and rely on `Pause-Menu` alone.

**Profile load is slow**

The `clink.ps1` module spawns `clink.exe` once per session, which can add
50 to 150 ms. Comment out `clink.ps1` in `modules.json`, or move the
registration into a function and call it manually.

---

## Extending

### Adding a new profile module

```powershell
pmnew -Name my-feature -Template Function -Enable
```

This creates `Profile.d\my-feature.ps1` and adds it to `loadOrder`. Open a
new shell, or run `rp` to reload the current session.

### Adding a new module kind

The manager is organized around the `-Kind` parameter. To add a fourth kind:

1. Add the new value to the `ValidateSet` attributes on the manager functions
   in `functions.ps1`.
2. Add a new case to `Resolve-ProfileModulePath` for the extension and
   directory.
3. Add a branch to `Get-ProfileModule` so the new files are listed.
4. Add templates to `Get-ProfileModuleTemplate`.
5. Add a top-level entry and a router case in `Show-ModuleMenu`.

### Adding a new menu section

1. Add a string to the choices array in `Show-ProfileMenuMain`.
2. Add a `switch` case that calls your new `Show-*Submenu` function.
3. Write the submenu following the pattern of `Show-LintMenu` or
   `Show-ClinkMenu`. Each iteration calls `Read-MenuChoice`, wraps actions
   in try/catch, and uses `Pause-Menu` to wait for input.

### Custom PSScriptAnalyzer rules

```powershell
pmnew -Name MyRule -Kind Analyzer -Template CommandRule
```

Edit the generated `.psm1` in `tools\Rules\` to implement the rule. The file
is picked up automatically by `Invoke-PSLint` on the next run.

---

## License

MIT. See `LICENSE`.