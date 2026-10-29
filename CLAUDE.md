# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Tools that make the Claude requirements, Claude Desktop and Claude CLI easy to install on a workstation. Two mirrored kits (`Kit-Windows/`, `Kit-macOS/`) each provide an **installer** and a **read-only diagnostic**; `Package-Release.ps1` builds and publishes the release zip. Users and docs are French: script output, comments and docs are in French (ASCII only in scripts, see below).

## Runtime targets (hard constraints)

- **Windows: Windows PowerShell 5.1 only** (what ships with Windows 10 and 11). Never use PowerShell 7 syntax or features: no `&&`/`||`, `??`, ternary, `?.`, `-AsHashtable`, `ForEach-Object -Parallel`. Always test with `powershell.exe`, never `pwsh`.
- **macOS: zsh** (`#!/bin/zsh`, the shell shipped with macOS; zsh became the default shell for new accounts in macOS 10.15, but a `.command` runs under its shebang regardless of the user's shell). Both scripts were migrated from bash 3.2 to zsh: write zsh, not bash. The only bash left is Homebrew's installer, run explicitly with `/bin/bash` because it is a bash script.

## Test gate: run before every commit/push and before every publication

There is **no automated test suite yet**. Until one exists, the gate is the checks below. Run all of them, from the repo root, and report failures instead of pushing. Do not claim "tests pass" for anything not listed here.

```powershell
# 1. Syntax of every .ps1 under Windows PowerShell 5.1 (run in powershell.exe)
Get-ChildItem -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notmatch '\\(dist|\.git)\\' } | ForEach-Object {
  $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$e)
  if ($e) { $e | ForEach-Object { "KO $($_.Extent.File):$($_.Extent.StartLineNumber) $($_.Message)" } } else { "ok $($_.Name)" } }

# 2. No byte > 127 in .ps1/.cmd (5.1 reads BOM-less UTF-8 as ANSI and corrupts accents)
Get-ChildItem -Recurse -Include *.ps1,*.cmd | Where-Object { $_.FullName -notmatch '\\(dist|\.git)\\' } | ForEach-Object {
  $n = @([IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -gt 127 }).Count; "{0,-32} octets>127={1}" -f $_.Name, $n }

# 3. Smoke: help paths exit 0 (do NOT pipe to Select-Object -First: it truncates the pipe and gives exit -1)
foreach ($s in 'Kit-Windows\Setup-ClaudeWorkstation.ps1','Kit-Windows\Diagnostic-poste.ps1','Package-Release.ps1') {
  powershell -NoProfile -ExecutionPolicy Bypass -File ".\$s" --help | Out-Null; "$s exit=$LASTEXITCODE" }

# 4. Diagnostic is read-only: safe to run for real. -NoFile avoids writing the report and test-vision.html
powershell -NoProfile -ExecutionPolicy Bypass -File .\Kit-Windows\Diagnostic-poste.ps1 -NoFile
```

```bash
# 5. macOS scripts: executable bit and line endings in the git index
git ls-files -s 'Kit-macOS/*.command'        # must show 100755
git ls-files --eol 'Kit-macOS/*.command'     # must show i/lf w/lf

```powershell
# 6. macOS scripts: zsh syntax, run from PowerShell through WSL (Ubuntu-24.04 has zsh 5.9, the version macOS 14+ ships).
#    Do NOT use `bash -n`: the scripts contain zsh-only syntax such as the (N) glob qualifier.
#    wsl --cd needs an absolute path; from Git Bash set MSYS_NO_PATHCONV=1 or /mnt/... paths get rewritten.
$kit = (Resolve-Path Kit-macOS).Path
Get-ChildItem Kit-macOS\*.command | ForEach-Object { wsl -d Ubuntu-24.04 --cd $kit -- zsh -n $_.Name; "{0} zsh -n exit={1}" -f $_.Name, $LASTEXITCODE }
```

`zsh -n` only proves the syntax parses. The macOS scripts have also been executed under that zsh with **simulated macOS commands** (stub `sw_vers`, `sysctl`, `defaults`, `xcode-select`, `brew`, an isolated `PATH` and a throwaway `HOME`; WSL has its own `node`/`python`, which must be kept off the `PATH` or they mask the install paths), but that harness is not in the repo yet. If WSL/zsh is missing, say the macOS scripts are **unverified** rather than reporting the gate as passed.

**Publication gate:** the checks above, then `.\Package-Release.ps1 <version> -Publish -DryRun`, then `-Publish`. Never publish without the dry-run passing in the same session.

### Exit codes are not "0 = success"
- `Diagnostic-poste.ps1` (Windows): **10 = VERT, 11 = ORANGE, 12 = ROUGE** (0 only for help). A non-zero code is normal.
- `diagnostic-poste.command` (macOS): **0 = VERT, 1 = ORANGE, 2 = ROUGE**: a different mapping from Windows.
- `Setup-ClaudeWorkstation.ps1`: 0 = ok, 1 = a step failed or Claude Desktop is blocking. `setup-claude-workstation.command`: 0 = ok, 1 = a step failed.

### Never run on the dev machine
`Installer.cmd` and `Setup-ClaudeWorkstation.ps1` (without `--help`) and `setup-claude-workstation.command` **install software** (winget, UAC prompts, Homebrew, PATH changes). Only `--help` is safe here. Real install runs need a clean VM or machine, which this environment does not have.

### What cannot be verified here (say so, do not assume)
real macOS behaviour (no Mac here: `sw_vers`, `sysctl`, `defaults`, Homebrew, Gatekeeper, the Apple command-line-tools stubs are only simulated), a clean Windows machine without tools, non-admin vs UAC paths, offline/winget-missing cases. Pester 3.4.0 is the only test framework present (in-box with 5.1, so v3 syntax: `Should Be`, not `Should -Be`); PSScriptAnalyzer and shellcheck are not installed.

## Architecture

The two kits implement the same design twice; a change to one usually needs the mirror change in the other.

- **Installer** (`Setup-ClaudeWorkstation.ps1`, `setup-claude-workstation.command`): *idempotent* (each step checks state first) and *non-blocking* (a failed step is recorded, the next ones still run; a final summary lists OK/failed). `Installer.cmd` is only a launcher that calls the `.ps1` with `-ExecutionPolicy Bypass` (otherwise Windows refuses the script with a misleading error) and checks the `.ps1` sits next to it (unzip check).
- **Diagnostic** (`Diagnostic-poste.ps1`, `diagnostic-poste.command`): read-only. Each check is registered (`Add-Controle` / `ajouter`) with a status OK / ALERTE / BLOQUANT / INCONNU; any BLOQUANT gives ROUGE, otherwise any ALERTE or INCONNU gives ORANGE, else VERT. It emits a table, one **result line** (`AES2026 | <os> | <user> | <date> | VERDICT:… | codes`) that users send back, and a report file. Anything it cannot measure is announced as not measurable, never skipped silently.
- **`Package-Release.ps1`**: `git archive` of HEAD into `dist/claude-easy-setup-<semver>.zip`, minus `.gitattributes`, `.gitignore`, `.claude`, `CLAUDE.md` and itself. `git archive` is used deliberately (keeps the `.command` exec bit, `/` path separators, `.gitattributes` line endings; `core.autocrlf=false` makes the zip reproducible across machines). `-Publish` creates the GitHub release with `gh` (tag on HEAD, zip, generated notes; semver suffix = pre-release) and checks its preconditions *before* building: `gh` authenticated, clean tree, HEAD pushed, version not already released.

### Values duplicated across files: keep in sync
- Node target **24 LTS**: `NODE_FORMULE` and the hard-coded `-ge 24` tests in the macOS setup, `NODE_MAJEUR_CIBLE` in both diagnostics. The Windows setup installs `OpenJS.NodeJS.LTS` without pinning a major, so the diagnostic's 24 is what actually enforces it there.
- Thresholds: Windows build 19041, RAM 8 Go, disk 10 Go (Windows diagnostic); macOS 14 Sonoma (Cowork). `README.md` and the `LISEZ-MOI.txt` files restate the OS requirements: update them with the scripts.
- The vision test: `test-vision.html` (tracked) and the HTML generated inside each diagnostic share the control word `MARGUERITE-7431`.
- The install procedure is described four times: the setup scripts, `Installation manuelle.txt`, `Comment Installer claude ticket admin.txt`, and the two `LISEZ-MOI.txt`/`README.md`. Update them together.
- Script text and the result-line prefix are tied to the "Agile en Seine" day of 22/09/2026 (`AES2026`).

## Pitfalls already paid for (do not reintroduce)

- **PS 5.1 + `$ErrorActionPreference='Stop'`**: redirecting a native command's stderr (`2>$null`, `*>`) turns it into a terminating exception. Scripts use a helper that relaxes the preference around the call (`Get-ToolVersion` in the Windows setup, `Test-Git`/`Test-Gh` in `Package-Release.ps1`).
- `Set-StrictMode -Version Latest` makes reading `$LASTEXITCODE` fail before any native command ran: initialise it first (done at the top of the setup and diagnostic).
- macOS Node: `node@24` is a keg-only Homebrew formula; it must be linked (`brew link --overwrite --force`) or an older `node` on the PATH masks it. The setup and diagnostic both handle this.
- `Set-Content -Encoding UTF8` writes a BOM in 5.1; files that must be BOM-less (the generated HTML) are written with `[IO.File]::WriteAllText(..., (New-Object Text.UTF8Encoding($false)))`.
- Scripts stay **ASCII only** (no accents in strings or comments), see gate check 2.
- winget scope: do not pass `--scope user` globally. It breaks Git and makes Python ask for admin (winget-cli #3285). Node.js LTS and GitHub CLI are machine-scope and need admin; the setup is run from a **non-admin** session.
- **Claude Desktop must not be installed through winget** (installs without the rights Cowork needs). It is a documented manual step, so the installer must not add it on Windows.
- Windows `Diagnostic.cmd`/`Installer.cmd` must stay CRLF (`.gitattributes`); macOS `.command` must stay LF and `100755`. Git's "LF will be replaced by CRLF" warnings on this Windows box are expected.
- macOS: without Apple's command line tools, `/usr/bin/git` and `/usr/bin/python3` are stubs that open a modal dialog; guard with `xcode-select -p` before probing them. zsh differences that matter in these scripts: arrays are **1-indexed** (the parallel arrays are walked from 1 to `$NB`; walking from 0 under `set -u` aborts with `parameter not set`), a glob with no match is an error (`Profile*(N)` in the diagnostic: add `(N)` to any new glob), and both scripts start with `emulate -R zsh` because `~/.zshenv` is read even for scripts. Avoid variable names zsh reserves (`path`, `status`, `argv`, `options`, `commands`, `functions`).
- Gatekeeper blocks downloaded `.command` files on first launch; this is documented in the README and must stay documented.

## Workflow

- The repo is public (`AlexisAIchangeAgent/claude-easy-setup`, branch `main`); versions follow semver, first release `1.0.0`. Publishing creates a public tag and release and cannot be undone: only publish when the user asks.
- A published version is never rewritten: bump the version instead.
