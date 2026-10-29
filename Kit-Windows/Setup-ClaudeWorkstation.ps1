#Requires -Version 5.1
<#
.SYNOPSIS
    Prepare un poste Windows 10 (build 19041+) ou Windows 11 pour Claude Code CLI.

.DESCRIPTION
    Derive de notes manuelles. Idempotent : chaque etape verifie l'etat
    avant d'agir. Une etape en echec n'interrompt pas les suivantes ;
    le bilan final liste ce qui est OK et ce qui ne l'est pas.

    Claude Desktop n'est PAS gere ici : son installation complete exige
    les droits administrateur (service de virtualisation Cowork), ce qui
    sort du perimetre de ce script. Voir claude.com/download.

    A lancer dans une session PowerShell NON administrateur.

.PARAMETER Help
    Affiche l'aide et quitte. Accepte aussi --help, -h, /? et ?.

.PARAMETER CliViaWinget
    Installe Claude Code via winget (Anthropic.ClaudeCode) au lieu du
    script officiel install.ps1.

.PARAMETER PythonPackageId
    Force l'identifiant winget de Python (ex. Python.Python.3.13).
    Par defaut le script interroge le catalogue winget et retient la
    derniere version STABLE, en ecartant les alphas, betas et release
    candidates que winget publie en avance.

.PARAMETER UserScopeOnly
    Ignore les paquets dont la portee par defaut est 'machine'
    (Node.js LTS, GitHub CLI). Aucune tentative, donc aucune invite UAC ;
    ils sont marques ACTION MANUELLE et le code de sortie reste 0.
    Ne force PAS --scope user partout : cela casserait Git, qui s'installe
    sans admin uniquement quand aucune contrainte de portee n'est passee.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeWorkstation.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeWorkstation.ps1 --help

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeWorkstation.ps1 -UserScopeOnly

    Installation limitee au profil local courant, sans droits administrateur.
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$CliViaWinget,
    [switch]$UserScopeOnly,
    [string]$PythonPackageId,

    # Recupere les jetons non reconnus par le parseur (/? et ? notamment).
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# StrictMode Latest fait echouer la lecture de $LASTEXITCODE tant qu'aucune
# commande native n'a tourne. On l'initialise avant tout usage.
if (-not (Test-Path Variable:\LASTEXITCODE)) { $global:LASTEXITCODE = 0 }

$script:WingetPath = $null
$script:IsAdmin    = $false

# ---------------------------------------------------------------------------
# Aide
# ---------------------------------------------------------------------------
function Show-ScriptHelp {
    $name = if ($PSCommandPath) { Split-Path $PSCommandPath -Leaf } else { 'Setup-ClaudeWorkstation.ps1' }
    @"
$name
Prepare un poste Windows 10 (build 19041+) ou Windows 11 pour Claude Code CLI.

USAGE
    powershell -ExecutionPolicy Bypass -File .\$name [options]

OPTIONS
    --help, -h, /?      Affiche cette aide et quitte.
    -CliViaWinget       Installe Claude Code via winget (Anthropic.ClaudeCode)
                        au lieu du script officiel install.ps1.
    -UserScopeOnly      Ignore tout ce qui exige l'administrateur.
                        Aucune tentative, donc aucune invite UAC.
    -PythonPackageId    Force l'identifiant winget de Python
                        (ex. Python.Python.3.13). Par defaut le script
                        detecte la derniere version STABLE du catalogue.

PORTEE PAR DEFAUT, PAR PAQUET

    Chaque paquet a sa propre politique. Il n'y a pas de reglage global,
    parce qu'aucun reglage global n'est correct pour tous.

    PROFIL UTILISATEUR, jamais d'admin :
        - Claude Code CLI            install.ps1 -> %USERPROFILE%\.local\bin
                                     ou winget en --scope user
        - PATH utilisateur           HKCU
        - CLAUDE_CODE_GIT_BASH_PATH  HKCU

    SANS CONTRAINTE DE PORTEE (aucun --scope passe) :
        - Git                        winget choisit l'installeur.
                                     Mesure : s'installe sans droits admin.
        - Python                     installe dans le profil courant, sous
                                     %LOCALAPPDATA%\Programs\Python\PythonXXX.
                                     --scope user est CONTRE-productif ici :
                                     il declenche une demande de droits
                                     admin (bug winget-cli #3285).

    INSTALLATION MACHINE, admin requis :
        - Node.js LTS
        - GitHub CLI

    Pourquoi Git n'est pas en "profil utilisateur" : --scope est une
    EXIGENCE pour winget, pas une preference. Ajouter --scope user retire
    des installeurs valides au lieu d'en ouvrir. Sur Git.Git, la commande

        winget install --id Git.Git -e --source winget

    aboutit sans admin, alors que la meme commande avec --scope user
    echoue en "No applicable installer found". D'ou le mode sans contrainte.

EXEMPLES

    Poste dont vous etes administrateur, installation complete :

        powershell -ExecutionPolicy Bypass -File .\$name

    Poste gere par l'IT, sans droits administrateur :

        powershell -ExecutionPolicy Bypass -File .\$name -UserScopeOnly

    Dans ce mode, Node.js et GitHub CLI sont ignores sans meme etre
    tentes, donc aucune invite UAC. Ils sont marques ACTION MANUELLE et
    le code de sortie reste 0. Claude Code CLI et Git s'installent
    normalement.

    A quoi servent reellement ces trois paquets :
        - Node.js    : vos propres projets JS. Claude Code embarque un
                       binaire autonome et n'appelle pas Node.
        - Git        : optionnel pour le CLI. Sans lui, Claude Code
                       utilise l'outil PowerShell au lieu de Bash.
        - GitHub CLI : confort, sans lien avec Claude Code.
        - Python     : vos propres projets. Installe dans le profil
                       courant, sans droits admin. Version detectee
                       automatiquement : la derniere STABLE du catalogue,
                       les pre-versions sont ecartees.

ETAPES
    0  Preflight            version PowerShell, droits, TLS 1.2
    1  winget               detection, avec repli hors PATH
    2  Outils de confort    Node.js LTS, Git, GitHub CLI, Python, npm
    3  Claude Code CLI      install.ps1 (defaut) ou winget
    4  PATH utilisateur     ajout de %USERPROFILE%\.local\bin
    5  Git Bash             detection et CLAUDE_CODE_GIT_BASH_PATH
    6  Bilan des etapes     journal de ce qu'a fait le script
    7  Outils installes     re-sondage de chaque commande, OK ou ECHEC

COMPORTEMENT
    Idempotent : une etape deja satisfaite est ignoree, rien n'est reinstalle.
    Non bloquant : une etape en echec est enregistree, le script continue.
    Le tableau des outils est binaire : la commande repond (OK) ou non
    (ECHEC). La colonne Note dit pourquoi.
    Code de sortie 1 si une etape a echoue, ou si Claude Code CLI n'a pas
    pu etre installe. Un outil facultatif absent, ou un Claude Code
    installe mais pas encore visible avant reouverture du terminal, ne
    font pas echouer le script.

A LANCER EN SESSION NON ADMINISTRATEUR : le script ecrit dans le PATH
utilisateur, qui differe entre votre compte et le compte administrateur.
Les paquets en portee machine declenchent leur propre invite UAC.

Claude Desktop n'est PAS gere ici : son installation complete exige
l'admin pour enregistrer le service de virtualisation dont depend Cowork.
Voir claude.com/download, ou faire provisionner le MSIX par l'IT.

Apres execution : fermer et rouvrir le terminal, puis verifier avec
claude --version.
"@
}

# PowerShell lie nativement --help et -h au parametre -Help.
# /? et ? tombent dans $RemainingArguments : on les rattrape ici.
$helpTokens = @('/?', '/h', '?', 'help', '--help', '-help')
$askedHelp = $Help -or (@($RemainingArguments) | Where-Object { $_ -and ($_.ToLower() -in $helpTokens) })

if ($askedHelp) {
    Show-ScriptHelp
    exit 0
}

if (@($RemainingArguments).Where({ $_ }).Count -gt 0) {
    Write-Warning "Arguments non reconnus : $((@($RemainingArguments) -join ' '))"
    Write-Warning "Utiliser --help pour la liste des options."
}

# ---------------------------------------------------------------------------
# Etat global : chaque etape pousse son resultat ici pour le bilan final.
# ---------------------------------------------------------------------------
$script:Report = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][ValidateSet('OK', 'ECHEC', 'IGNORE', 'ACTION MANUELLE')][string]$Status,
        [string]$Detail = ''
    )
    $script:Report.Add([pscustomobject]@{
        Etape  = $Step
        Statut = $Status
        Detail = $Detail
    })
}

function Write-Step { param([string]$Message) Write-Host "`n=== $Message" -ForegroundColor Cyan }
function Write-Info { param([string]$Message) Write-Host "    $Message" -ForegroundColor Gray }
function Write-Ok   { param([string]$Message) Write-Host "    OK   $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    !    $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "    X    $Message" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Recharge le PATH dans la session courante (Machine + User).
# Evite d'avoir a fermer/rouvrir le terminal entre deux etapes.
#
# On FUSIONNE avec le PATH du processus au lieu de le remplacer. Remplacer
# ferait disparaitre les entrees ajoutees par le terminal, un venv, conda
# ou un profil - invisibles dans le registre et pourtant necessaires a la
# session en cours. La deduplication est insensible a la casse et ignore
# les barres obliques finales, comme Windows.
# ---------------------------------------------------------------------------
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')

    $ordered = New-Object System.Collections.Generic.List[string]
    $seen    = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($block in @($machine, $user, $env:Path)) {
        if (-not $block) { continue }
        foreach ($entry in ($block -split ';')) {
            $e = $entry.Trim()
            if (-not $e) { continue }
            $key = $e.TrimEnd('\', '/')
            if ($seen.Add($key)) { $ordered.Add($e) }
        }
    }

    if ($ordered.Count -gt 0) { $env:Path = $ordered -join ';' }
}

# ---------------------------------------------------------------------------
# Teste si une commande repond vraiment (presence ET execution).
# Retourne la premiere ligne de sortie, ou $null.
# ---------------------------------------------------------------------------
function Get-ToolVersion {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string[]]$Arguments = @('--version'),

        # Motif que la sortie doit respecter pour etre acceptee.
        # Indispensable pour python.exe : Windows livre un alias d'execution
        # qui existe dans le PATH, ne renvoie rien d'utile et ouvre le
        # Microsoft Store. Sans controle, il passerait pour un Python installe.
        [string]$Pattern
    )
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { return $null }

    # PIEGE POWERSHELL 5.1 : avec $ErrorActionPreference = 'Stop' actif au niveau du
    # script (ligne 62), une commande native qui ecrit la moindre ligne sur stderr
    # sous 2>&1 leve un NativeCommandError TERMINANT. Le catch renverrait $null, et
    # un outil PRESENT serait declare absent - donc reinstalle, puis marque ECHEC.
    # On neutralise la preference le temps de l'appel, on la restaure en finally.
    $prefPrecedente = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = 0
        # 2>&1 evite que les erreurs polluent la console, mais transforme
        # stderr en ErrorRecord dans le flux. On les ecarte : sinon une
        # banniere ou un avertissement ecrit sur stderr avant stdout
        # deviendrait la "version" affichee dans le tableau final.
        $out = & $Command @Arguments 2>&1 |
               Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
        if ($LASTEXITCODE -ne 0) { return $null }
        $text = ($out | Out-String).Trim()
        if (-not $text) { return $null }
        $first = ($text -split "`r?`n")[0].Trim()
        if ($Pattern -and $first -notmatch $Pattern) { return $null }
        return $first
    }
    catch { return $null }
    finally { $ErrorActionPreference = $prefPrecedente }
}

# ---------------------------------------------------------------------------
# Localise winget, y compris quand il n'est pas dans le PATH.
# On ne parcourt PAS tout WindowsApps : le dossier est verrouille par ACL
# et une recursion complete est lente et bruyante.
# ---------------------------------------------------------------------------
function Resolve-Winget {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))
    }

    $pkgRoot = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'WindowsApps' } else { $null }
    if ($pkgRoot -and (Test-Path $pkgRoot)) {
        try {
            Get-ChildItem -Path $pkgRoot -Filter 'Microsoft.DesktopAppInstaller_*' -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { $candidates.Add((Join-Path $_.FullName 'winget.exe')) }
        }
        catch { }
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Le paquet est-il connu de winget comme installe ?
# Utilise pour les applications GUI, qui n'ont pas de commande a sonder.
# ---------------------------------------------------------------------------
function Test-WingetPackageInstalled {
    param([Parameter(Mandatory)][string]$PackageId)

    if (-not $script:WingetPath) { return $false }
    try {
        $global:LASTEXITCODE = 0
        $out = & $script:WingetPath list --id $PackageId --exact --accept-source-agreements 2>&1 | Out-String
        return ($LASTEXITCODE -eq 0 -and $out -match [regex]::Escape($PackageId))
    }
    catch { return $false }
}

# ---------------------------------------------------------------------------
# Installe un paquet winget s'il manque.
#   -VerifyCommand : sonde par commande (outils CLI)
#   sinon          : sonde par winget list (applications GUI)
# ---------------------------------------------------------------------------
function Install-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$PackageId,
        [string]$VerifyCommand,
        [string[]]$VerifyArguments = @('--version'),
        [string]$VerifyPattern,

        # Politique de portee, par paquet :
        #   user    -> --scope user. Reste dans le profil, jamais d'UAC.
        #   machine -> --scope machine. Declenche l'UAC, exige l'admin.
        #   auto    -> AUCUN --scope. winget choisit l'installeur.
        #
        # 'auto' n'est pas un defaut mou, c'est le seul mode correct pour
        # certains paquets. Exemple mesure : Git.Git s'installe sans droits
        # admin avec
        #     winget install --id Git.Git -e --source winget
        # alors que la meme commande avec --scope user echoue en
        # "No applicable installer found". --scope est une EXIGENCE pour
        # winget, pas une preference : l'ajouter retire des installeurs
        # valides au lieu d'en ouvrir. Ne jamais forcer --scope user sur un
        # paquet qui s'installe deja sans admin.
        [ValidateSet('user', 'machine', 'auto')][string]$Scope = 'auto',

        [string[]]$ExtraArguments = @(),
        [switch]$NoHeader
    )

    if (-not $NoHeader) { Write-Step "$Label ($PackageId)" }

    $probe = {
        if ($VerifyCommand) {
            Get-ToolVersion -Command $VerifyCommand -Arguments $VerifyArguments -Pattern $VerifyPattern
        }
        elseif (Test-WingetPackageInstalled -PackageId $PackageId) { 'installe' }
        else { $null }
    }

    $existing = & $probe
    if ($existing) {
        Write-Ok "deja present : $existing"
        Add-Result -Step $Label -Status 'OK' -Detail "deja present : $existing"
        return
    }

    # -UserScopeOnly ne force PAS --scope user partout : cela casserait les
    # paquets 'auto'. Il coupe uniquement ce qui exige l'admin, sans meme
    # tenter, pour ne declencher aucune invite UAC.
    if ($UserScopeOnly -and $Scope -eq 'machine') {
        Write-Warn 'ignore : installation machine, droits administrateur requis'
        Write-Info '-UserScopeOnly actif -> aucune tentative, aucune invite UAC'
        Add-Result -Step $Label -Status 'ACTION MANUELLE' -Detail 'scope machine - demande IT'
        return
    }

    if (-not $script:WingetPath) {
        Write-Err 'winget indisponible, installation impossible'
        Add-Result -Step $Label -Status 'ECHEC' -Detail 'winget indisponible'
        return
    }

    if ($Scope -eq 'machine' -and -not $script:IsAdmin) {
        Write-Warn 'scope machine sans session admin : une invite UAC va apparaitre'
    }

    # --accept-*-agreements evite les prompts interactifs. A valider :
    # cela accepte les licences editeur et source sans les afficher.
    $wingetArgs = @(
        'install', '--id', $PackageId, '--exact',
        '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements'
    )

    if ($Scope -ne 'auto') { $wingetArgs += @('--scope', $Scope) }

    $wingetArgs += $ExtraArguments

    Write-Info "winget $($wingetArgs -join ' ')"
    try {
        $global:LASTEXITCODE = 0
        & $script:WingetPath @wingetArgs
        $code = $LASTEXITCODE
    }
    catch {
        Write-Err $_.Exception.Message
        Add-Result -Step $Label -Status 'ECHEC' -Detail $_.Exception.Message
        return
    }

    Update-SessionPath

    $result = & $probe
    if ($result) {
        Write-Ok $result
        Add-Result -Step $Label -Status 'OK' -Detail $result
    }
    elseif ($code -eq 0) {
        # Installe mais pas encore visible : PATH non propage a ce process.
        Write-Warn 'installe, mais non visible dans cette session'
        Add-Result -Step $Label -Status 'OK' -Detail 'installe - rouvrir le terminal pour verifier'
    }
    else {
        # 0x8A15002B = APPINSTALLER_CLI_ERROR_NO_APPLICABLE_INSTALLER,
        # soit -1978335189 en entier signe. Reponse attendue quand aucun
        # installeur ne satisfait le --scope demande.
        $noApplicableInstaller = -1978335189

        if ($code -eq $noApplicableInstaller -and $Scope -ne 'auto') {
            Write-Warn "aucun installeur disponible en scope $Scope"
            Write-Info "essayer sans contrainte de portee : Scope = 'auto'"
            Add-Result -Step $Label -Status 'ACTION MANUELLE' -Detail "pas d installeur en scope $Scope"
        }
        elseif ($Scope -eq 'machine' -and -not $script:IsAdmin) {
            Write-Warn "echec en scope machine (code $code) sans session admin"
            Write-Info 'relancer en session administrateur, ou faire installer par l IT'
            Add-Result -Step $Label -Status 'ACTION MANUELLE' -Detail "scope machine, code $code - admin requis"
        }
        else {
            Write-Err "code de sortie winget : $code"
            Add-Result -Step $Label -Status 'ECHEC' -Detail "code winget $code"
        }
    }
}

# ---------------------------------------------------------------------------
# winget n'expose pas d'identifiant stable pour "le dernier Python 3" :
# les paquets sont versionnes (Python.Python.3.14, .3.13, ...) et le moniker
# python3 est ambigu.
#
# PIEGE : la presence d'un paquet ne signifie PAS que la version est sortie.
# winget publie Python.Python.3.NN des les alphas. Le ticket winget-pkgs
# #132377 montre Python.Python.3.13 valant 3.13.0a2 alors que 3.12 etait la
# stable. Choisir le numero le plus haut installerait donc une pre-version.
#
# On interroge le catalogue en UN appel, puis on ecarte toute version qui
# n'est pas purement numerique : 3.14.2 est stable, 3.15.0a1 / 3.15.0b2 /
# 3.15.0rc1 ne le sont pas.
# ---------------------------------------------------------------------------
function Resolve-PythonPackage {
    param([string[]]$Fallback = @('Python.Python.3.14', 'Python.Python.3.13', 'Python.Python.3.12'))

    if (-not $script:WingetPath) { return $null }

    $found = [System.Collections.Generic.List[object]]::new()

    try {
        $global:LASTEXITCODE = 0
        $out = & $script:WingetPath search --id 'Python.Python.' --source winget `
                   --accept-source-agreements 2>&1 |
               Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
               Out-String

        if ($LASTEXITCODE -eq 0 -and $out) {
            # Id et Version sont adjacents sur chaque ligne du tableau.
            # On regexe le contenu, pas les en-tetes : ceux-ci sont traduits
            # selon la langue de winget, les numeros de version non.
            foreach ($m in [regex]::Matches($out, 'Python\.Python\.3\.(\d+)\s+(\S+)')) {
                $found.Add([pscustomobject]@{
                    Id      = "Python.Python.3.$($m.Groups[1].Value)"
                    Minor   = [int]$m.Groups[1].Value
                    Version = $m.Groups[2].Value
                })
            }
        }
    }
    catch { }

    $stable = @($found |
        Where-Object { $_.Version -match '^\d+(\.\d+)+$' } |
        Sort-Object Minor -Descending |
        Group-Object Id | ForEach-Object { $_.Group[0] })

    if ($stable.Count -gt 0) {
        $best = $stable | Sort-Object Minor -Descending | Select-Object -First 1
        $rejetes = @($found | Where-Object { $_.Version -notmatch '^\d+(\.\d+)+$' })
        return [pscustomobject]@{
            Id       = $best.Id
            Version  = $best.Version
            Source   = 'catalogue winget'
            Rejetees = ($rejetes | ForEach-Object { "$($_.Id) ($($_.Version))" }) -join ', '
        }
    }

    # Repli : la recherche n'a rien donne d'exploitable (source indisponible,
    # sortie inattendue). On revient au sondage d'existence, moins sur.
    foreach ($id in $Fallback) {
        try {
            $global:LASTEXITCODE = 0
            & $script:WingetPath show --id $id --exact --source winget `
                --accept-source-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return [pscustomobject]@{
                    Id       = $id
                    Version  = '(inconnue)'
                    Source   = 'repli sur liste figee'
                    Rejetees = ''
                }
            }
        }
        catch { }
    }
    return $null
}

# ===========================================================================
# 0. Preflight
# ===========================================================================
Write-Step 'Preflight'
Write-Info "PowerShell $($PSVersionTable.PSVersion)"
Write-Info "Utilisateur : $env:USERNAME"
Write-Info "Profil      : $env:USERPROFILE"

$script:IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($script:IsAdmin) {
    Write-Warn 'session ADMINISTRATEUR : le PATH utilisateur modifie sera celui de l administrateur'
    Write-Warn 'les notes prevoient une session non-admin'
}
else {
    Write-Ok 'session non-administrateur'
}

if ($UserScopeOnly) {
    Write-Info 'Mode -UserScopeOnly : les paquets en scope machine sont ignores.'
    Write-Info 'Node.js et GitHub CLI seront signales ACTION MANUELLE, sans invite UAC.'
    Write-Info 'Claude Code CLI et Git restent installes : ils ne demandent pas l admin.'
}

# TLS 1.2 explicite : necessaire pour irm sur certaines configs PowerShell 5.1.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

Update-SessionPath

# ===========================================================================
# 1. winget
# ===========================================================================
Write-Step 'Verification de winget'
$script:WingetPath = Resolve-Winget

if ($script:WingetPath) {
    $wingetVersion = Get-ToolVersion -Command $script:WingetPath
    Write-Ok "$script:WingetPath ($wingetVersion)"
    Add-Result -Step 'winget' -Status 'OK' -Detail "$wingetVersion"
}
else {
    Write-Err 'winget introuvable'
    Write-Info 'Piste 1 : installer "App Installer" depuis le Microsoft Store'
    Write-Info 'Piste 2 : Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
    Add-Result -Step 'winget' -Status 'ECHEC' -Detail 'introuvable - voir App Installer'
}

# ===========================================================================
# 2. Outils de confort : Node.js LTS, Git, GitHub CLI
#    Aucun n'est requis par Claude Code : le CLI embarque un binaire
#    autonome. Ils servent a vos projets et a l'outil Bash.
# ===========================================================================
# Politique de portee, par paquet. Voir le parametre -Scope de
# Install-WingetPackage pour le raisonnement complet.
# -VerifyPattern sur Node : sans lui, un poste ou Node 18 ou 20 traine deja sort
# "deja present", Node 24 n'est jamais installe, et le diagnostic classera le poste
# ORANGE ou ROUGE sans que le participant comprenne pourquoi le script disait OK.
Install-WingetPackage -Label 'Node.js LTS' -PackageId 'OpenJS.NodeJS.LTS' -VerifyCommand 'node' `
                      -VerifyPattern '^v(2[4-9]|[3-9]\d)\.' -Scope machine
Install-WingetPackage -Label 'Git'         -PackageId 'Git.Git'           -VerifyCommand 'git'  -Scope auto
Install-WingetPackage -Label 'GitHub CLI'  -PackageId 'GitHub.cli'        -VerifyCommand 'gh'   -Scope machine

# --- Chrome et Obsidian ------------------------------------------------------
# Ajoutes le 08/09 pour supprimer une ASYMETRIE avec le script macOS, qui les
# installait deja. Le guide etant commun aux deux systemes, un participant Windows
# suivant "le chemin le plus court" finissait ROUGE (Chrome absent est bloquant)
# la ou son binome Mac finissait VERT. Aucune commande a sonder pour une
# application graphique : la verification passe par winget list.
Install-WingetPackage -Label 'Google Chrome' -PackageId 'Google.Chrome'      -Scope auto
Install-WingetPackage -Label 'Obsidian'      -PackageId 'Obsidian.Obsidian'  -Scope auto

# --- Python -----------------------------------------------------------------
# Scope 'auto' et non 'user', bien que le besoin soit une installation dans
# le profil courant. Raison mesuree : sans --scope, winget installe deja
# Python pour le seul utilisateur courant, sous
#   %LOCALAPPDATA%\Programs\Python\PythonXXX
# alors que --scope user declenche une demande de droits admin (bug winget-cli
# #3285). Meme piege que Git.Git : --scope est une exigence qui retire des
# installeurs, pas un moyen d'en obtenir.
Write-Step 'Python'

if ($PythonPackageId) {
    $python = [pscustomobject]@{ Id = $PythonPackageId; Version = '(impose)'; Source = '-PythonPackageId'; Rejetees = '' }
}
else {
    Write-Info 'recherche de la derniere version stable dans le catalogue winget...'
    $python = Resolve-PythonPackage
}

if (-not $python) {
    Write-Err 'aucun paquet Python stable trouve dans le catalogue winget'
    Write-Info 'lister les versions : winget search Python.Python'
    Write-Info 'puis relancer avec -PythonPackageId Python.Python.3.XX'
    Add-Result -Step 'Python' -Status 'ECHEC' -Detail 'aucune version stable trouvee'
}
else {
    Write-Info "retenu : $($python.Id) $($python.Version) [$($python.Source)]"
    if ($python.Rejetees) {
        Write-Info "ecarte (pre-version) : $($python.Rejetees)"
    }
    Install-WingetPackage -Label 'Python' -PackageId $python.Id `
                          -VerifyCommand 'python' -VerifyPattern '^Python\s+3\.' `
                          -Scope auto -NoHeader
}

# npm arrive avec Node : verification seule, jamais d'installation.
# Cette etape ne peut donc pas "echouer" : elle constate. Sur un poste ou
# Node vient d'etre installe, npm n'est pas encore visible dans CE process,
# ce qui est normal et ne doit pas faire sortir le script en code 1.
Write-Step 'Verification de npm'
$npm = Get-ToolVersion -Command 'npm'
$nodeStep = $script:Report | Where-Object { $_.Etape -eq 'Node.js LTS' } | Select-Object -Last 1

if ($npm) {
    Write-Ok "npm $npm"
    Add-Result -Step 'npm' -Status 'OK' -Detail $npm
}
elseif ($nodeStep -and $nodeStep.Statut -eq 'OK') {
    Write-Info 'pas encore visible - arrive avec Node, apres reouverture du terminal'
    Add-Result -Step 'npm' -Status 'IGNORE' -Detail 'arrive avec Node - rouvrir le terminal'
}
else {
    Write-Info 'absent - Node.js n est pas installe'
    Add-Result -Step 'npm' -Status 'IGNORE' -Detail 'Node.js absent'
}

# ===========================================================================
# 3. Claude Code CLI
# ===========================================================================
Write-Step 'Claude Code CLI'

$claudeVersion = Get-ToolVersion -Command 'claude'
if ($claudeVersion) {
    Write-Ok "deja present : $claudeVersion"
    Add-Result -Step 'Claude Code CLI' -Status 'OK' -Detail "deja present : $claudeVersion"
}
elseif ($CliViaWinget) {
    # Paquet portable : winget l'installe sous %LOCALAPPDATA%, sans admin.
    Install-WingetPackage -Label 'Claude Code CLI' -PackageId 'Anthropic.ClaudeCode' `
                          -VerifyCommand 'claude' -Scope user -NoHeader
}
else {
    Write-Info 'Source : https://claude.ai/install.ps1'
    try {
        $installer = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1' -UseBasicParsing

        # Le script distant est execute dans un PROCESSUS SEPARE, pas via
        # Invoke-Expression. Raison mesuree : un 'exit' dans le code recupere
        # termine le script appelant. Tout ce qui suit - PATH, Git Bash,
        # les deux tableaux finaux - serait saute en silence, avec un code
        # de sortie 0 laissant croire a une reussite complete.
        # L'isolation ne coute rien : on relit de toute facon le PATH depuis
        # le registre juste apres.
        # On reutilise l'executable de l'hote courant quand il est
        # identifiable ; sinon on retombe sur le nom generique. Evite de
        # lancer pwsh quand le script tourne sous Windows PowerShell 5.1,
        # et inversement.
        $psExe = try { (Get-Process -Id $PID).Path } catch { $null }
        if (-not $psExe -or $psExe -notmatch '(powershell|pwsh)(\.exe)?$') {
            $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        }
        $global:LASTEXITCODE = 0
        & $psExe -NoProfile -ExecutionPolicy Bypass -Command $installer
        $installCode = $LASTEXITCODE

        Update-SessionPath
        $claudeVersion = Get-ToolVersion -Command 'claude'

        if ($claudeVersion) {
            Write-Ok $claudeVersion
            Add-Result -Step 'Claude Code CLI' -Status 'OK' -Detail $claudeVersion
        }
        elseif ($installCode -eq 0) {
            # Le code 0 seul ne prouve rien : un script distant qui echoue sans 'exit'
            # explicite rend 0. On exige la presence du binaire avant de conclure OK,
            # sinon un echec reel se presenterait comme un simple probleme de PATH.
            $binaire = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.local\bin\claude.exe' } else { $null }
            if ($binaire -and (Test-Path $binaire)) {
                Write-Warn 'installe, mais commande non visible - voir etape PATH ci-dessous'
                Add-Result -Step 'Claude Code CLI' -Status 'OK' -Detail 'installe - verifier apres reouverture du terminal'
            }
            else {
                Write-Err 'l installeur a rendu 0 mais aucun binaire claude.exe n a ete depose'
                Add-Result -Step 'Claude Code CLI' -Status 'ECHEC' -Detail 'install.ps1 sans effet (code 0, binaire absent)'
            }
        }
        else {
            Write-Err "l installeur a retourne le code $installCode"
            Add-Result -Step 'Claude Code CLI' -Status 'ECHEC' -Detail "install.ps1 code $installCode"
        }
    }
    catch {
        Write-Err $_.Exception.Message
        Add-Result -Step 'Claude Code CLI' -Status 'ECHEC' -Detail $_.Exception.Message
    }
}

# ===========================================================================
# 4. PATH utilisateur : %USERPROFILE%\.local\bin
#
#    Deux pieges evites ici.
#
#    1. Comparaison. Windows ne distingue ni la casse ni la barre oblique
#       finale : "C:\Users\X\.local\bin\" est deja dans le PATH si
#       "C:\Users\x\.local\bin" y est. Une comparaison naive ajoute un
#       doublon a chaque execution.
#
#    2. Type de valeur registre. [Environment]::GetEnvironmentVariable
#       DEVELOPPE les %VARIABLES% d'un PATH stocke en REG_EXPAND_SZ, et
#       SetEnvironmentVariable le reecrit developpe. Un PATH contenant
#       %JAVA_HOME%\bin serait alors fige sur sa valeur du moment. On lit
#       et on reecrit donc la valeur BRUTE via le registre, en conservant
#       son type. Repli sur l'API .NET si l'acces registre echoue.
# ===========================================================================
Write-Step 'PATH utilisateur : .local\bin'

if (-not $env:USERPROFILE) {
    Write-Err 'USERPROFILE non defini : impossible de determiner .local\bin'
    Add-Result -Step 'PATH .local\bin' -Status 'ECHEC' -Detail 'USERPROFILE absent'
}
else {

$dir = Join-Path $env:USERPROFILE '.local\bin'

if (-not (Test-Path $dir)) {
    Write-Warn "$dir n existe pas encore (normal si le CLI n est pas installe)"
}

# Lecture brute (non developpee) + type, avec repli sur l'API .NET.
$userPath = $null
$pathKind = $null
try {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
    if ($key) {
        $userPath = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $pathKind = $key.GetValueKind('Path')
        $key.Close()
    }
}
catch {
    Write-Info 'lecture registre indisponible - repli sur l API .NET'
}
if ($null -eq $userPath) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
}
if (-not $userPath) { $userPath = '' }

# Comparaison normalisee : casse ignoree, barre oblique finale ignoree.
$normalise = { param($p) $p.Trim().TrimEnd('\', '/') }
$cible     = & $normalise $dir
$deja      = @($userPath -split ';' |
                Where-Object { $_.Trim() } |
                ForEach-Object { & $normalise $_ }) -contains $cible

if ($deja) {
    Write-Ok "deja present : $dir"
    Add-Result -Step 'PATH .local\bin' -Status 'OK' -Detail 'deja present'
}
else {
    try {
        $newPath = if ($userPath) { $userPath.TrimEnd(';') + ";$dir" } else { $dir }

        $ecrit = $false
        if ($null -ne $pathKind) {
            try {
                $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
                if ($key) {
                    # On conserve le type d'origine : REG_EXPAND_SZ reste
                    # REG_EXPAND_SZ, sinon les %VARIABLES% cessent d'etre
                    # developpees pour toutes les sessions futures.
                    $key.SetValue('Path', $newPath, $pathKind)
                    $key.Close()
                    $ecrit = $true
                }
            }
            catch { }
        }
        if (-not $ecrit) {
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        }

        Write-Ok "ajoute : $dir"
        Add-Result -Step 'PATH .local\bin' -Status 'OK' -Detail 'ajoute'
    }
    catch {
        Write-Err $_.Exception.Message
        Add-Result -Step 'PATH .local\bin' -Status 'ECHEC' -Detail $_.Exception.Message
    }
}

}   # fin du bloc USERPROFILE

Update-SessionPath

Write-Info 'PATH utilisateur apres mise a jour :'
[Environment]::GetEnvironmentVariable('Path', 'User') -split ';' |
    Where-Object { $_ } |
    ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }

# ===========================================================================
# 5. Detection de Git Bash pour Claude Code
#
#    Git n'est PAS requis : sans Git for Windows, Claude Code bascule sur
#    l outil PowerShell. Avec Git, il utilise Git Bash pour l outil Bash.
#    Quand Claude Code ne trouve pas Git Bash, le repli est la variable
#    CLAUDE_CODE_GIT_BASH_PATH, qui doit pointer sur bash.exe
#    (PAS sur git.exe).
#
#    Cette etape est donc informative : l absence de Git degrade les
#    capacites, elle ne casse rien. Statut IGNORE, jamais ECHEC.
# ===========================================================================
Write-Step 'Detection de Git Bash (CLAUDE_CODE_GIT_BASH_PATH)'

function Find-GitBash {
    $candidates = New-Object System.Collections.Generic.List[string]

    # ProgramFiles(x86) peut etre absent (ARM, images minimales).
    # Join-Path leve si Path est $null : on construit les racines d'abord,
    # on filtre, et seulement ensuite on assemble.
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
    if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA 'Programs') }

    foreach ($root in $roots) {
        if ($root) { $candidates.Add((Join-Path $root 'Git\bin\bash.exe')) }
    }

    # Deduction depuis l emplacement reel de git.exe :
    #   ...\Git\cmd\git.exe  ->  ...\Git\bin\bash.exe
    $gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gitRoot = Split-Path (Split-Path $gitCmd.Source -Parent) -Parent
        if ($gitRoot) { $candidates.Add((Join-Path $gitRoot 'bin\bash.exe')) }
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    return $null
}

$currentBashPath = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User')
$detectedBash    = Find-GitBash

if ($currentBashPath -and (Test-Path $currentBashPath)) {
    Write-Ok "variable deja definie et valide : $currentBashPath"
    Add-Result -Step 'Git Bash' -Status 'OK' -Detail $currentBashPath
}
elseif (-not $detectedBash) {
    Write-Warn 'bash.exe introuvable - Claude Code utilisera l outil PowerShell'
    Write-Info 'Ce n est pas une erreur : Git for Windows est optionnel pour le CLI.'
    Write-Info 'Pour activer l outil Bash, installer Git puis relancer ce script.'
    Add-Result -Step 'Git Bash' -Status 'IGNORE' -Detail 'absent - repli sur l outil PowerShell'
}
else {
    if ($currentBashPath) {
        Write-Warn "variable existante invalide : $currentBashPath"
        Write-Info "correction vers : $detectedBash"
    }
    try {
        [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $detectedBash, 'User')
        $env:CLAUDE_CODE_GIT_BASH_PATH = $detectedBash
        Write-Ok "definie : $detectedBash"
        Add-Result -Step 'Git Bash' -Status 'OK' -Detail "definie : $detectedBash"
    }
    catch {
        Write-Err $_.Exception.Message
        Add-Result -Step 'Git Bash' -Status 'ECHEC' -Detail $_.Exception.Message
    }
}

Write-Info 'Relecture depuis le registre :'
$readBack = [Environment]::GetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', 'User')
Write-Host "      $(if ($readBack) { $readBack } else { '(non definie)' })" -ForegroundColor DarkGray

# ===========================================================================
# 6. Bilan des etapes
# ===========================================================================
Write-Step 'Bilan des etapes'
# -Width explicite : sans lui, Format-Table rend un tableau VIDE quand l hote
# n a pas de largeur de console (sortie redirigee, tache planifiee, CI).
$script:Report | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$echecs = @($script:Report | Where-Object { $_.Statut -eq 'ECHEC' })
if ($echecs.Count -gt 0) {
    Write-Warn "$($echecs.Count) etape(s) en echec - voir le detail ci-dessus"
}

# ===========================================================================
# 7. Outils installes
#
#    Ce tableau ne rejoue pas le journal des etapes : il RE-SONDE chaque
#    commande maintenant. C'est la seule verification qui compte, puisqu'une
#    etape peut avoir renvoye OK alors que la commande reste introuvable
#    (PATH non propage, installeur silencieusement inoperant).
#
#    Statut binaire : OK ou ECHEC. La commande repond, ou elle ne repond
#    pas. Toute la nuance est dans la colonne Note.
#
#    npm n'y figure pas : le script ne l'installe jamais, il arrive avec
#    Node. Son controle reste dans le journal des etapes.
# ===========================================================================
Write-Step 'Outils installes'

$toolChecks = @(
    [pscustomobject]@{ Outil = 'Claude Code CLI'; Commande = 'claude'; Etape = 'Claude Code CLI'; Requis = $true;  Motif = '' }
    [pscustomobject]@{ Outil = 'Git';             Commande = 'git';    Etape = 'Git';             Requis = $false; Motif = '' }
    [pscustomobject]@{ Outil = 'Python';          Commande = 'python'; Etape = 'Python';          Requis = $false; Motif = '^Python\s+3\.' }
    [pscustomobject]@{ Outil = 'Node.js';         Commande = 'node';   Etape = 'Node.js LTS';     Requis = $false; Motif = '' }
    [pscustomobject]@{ Outil = 'GitHub CLI';      Commande = 'gh';     Etape = 'GitHub CLI';      Requis = $false; Motif = '' }
)

$toolReport = [System.Collections.Generic.List[object]]::new()

foreach ($t in $toolChecks) {
    $version = Get-ToolVersion -Command $t.Commande -Pattern $t.Motif

    # Statut de l'etape correspondante, pour expliquer une absence.
    $stepResult = $script:Report | Where-Object { $_.Etape -eq $t.Etape } | Select-Object -Last 1
    $stepStatus = if ($stepResult) { $stepResult.Statut } else { '' }

    if ($version) {
        $statut  = 'OK'
        # Les versions sont verbeuses (gh en particulier) : on tronque.
        $version = if ($version.Length -gt 46) { $version.Substring(0, 43) + '...' } else { $version }
        $note    = if ($t.Requis) { 'requis' } else { 'facultatif' }
    }
    else {
        $statut  = 'ECHEC'
        $version = '-'
        $note    = if ($stepStatus -eq 'OK')              { 'installe - rouvrir le terminal' }
                   elseif ($stepStatus -eq 'ACTION MANUELLE') { 'admin requis / demande IT' }
                   elseif ($stepStatus -eq 'IGNORE')      { 'volontairement ignore' }
                   elseif ($t.Requis)                     { 'ABSENT - Claude Code ne fonctionnera pas' }
                   else                                   { 'absent - facultatif pour Claude Code' }
    }

    $toolReport.Add([pscustomobject]@{
        Outil   = $t.Outil
        Statut  = $statut
        Version = $version
        Note    = $note
    })
}

$toolReport | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

# Le tableau est binaire, mais le code de sortie ne doit pas mentir :
# Claude Code installe a l'instant et pas encore visible dans CE process
# n'est pas un echec d'installation, seulement de propagation du PATH.
$claudeRow  = $toolReport | Where-Object { $_.Outil -eq 'Claude Code CLI' } | Select-Object -First 1
$claudeStep = $script:Report | Where-Object { $_.Etape -eq 'Claude Code CLI' } | Select-Object -Last 1

$claudeVisible   = ($null -ne $claudeRow)  -and ($claudeRow.Statut  -eq 'OK')
$claudeInstalle  = ($null -ne $claudeStep) -and ($claudeStep.Statut -eq 'OK')
$claudeBloquant  = (-not $claudeVisible) -and (-not $claudeInstalle)

if ($claudeVisible) {
    Write-Ok 'Claude Code CLI operationnel.'
}
elseif ($claudeInstalle) {
    Write-Warn 'Claude Code CLI installe mais pas encore visible dans cette session.'
    Write-Info 'Fermer et rouvrir le terminal, puis : claude --version'
}
else {
    Write-Err 'Claude Code CLI introuvable : c est le seul echec bloquant de ce script.'
    Write-Info 'Fermer et rouvrir le terminal, puis relancer. Sinon voir claude doctor.'
}

# ===========================================================================
# 8. Ce qu'aucun script ne peut faire a votre place
#
#    Ajoute le 08/09. Le script se terminait sans jamais nommer Claude Desktop,
#    l'extension Chrome ni les deux reglages silencieux : toute l'information
#    manuelle reposait sur des fichiers annexes. Un participant qui lance le
#    script et s'arrete la croit avoir termine, et sera classe ROUGE.
# ===========================================================================
Write-Step 'Trois choses restent a faire a la main'
Write-Host ''
Write-Host '  1. Installer CLAUDE DESKTOP' -ForegroundColor White
Write-Host '     https://claude.com/download - en acceptant l invite administrateur.' -ForegroundColor Gray
Write-Host '     NE PAS passer par winget : le paquet winget s installe sans elevation' -ForegroundColor Gray
Write-Host '     et l espace de travail Cowork n y fonctionne pas.' -ForegroundColor Gray
Write-Host ''
Write-Host '  2. Installer l EXTENSION CLAUDE POUR CHROME' -ForegroundColor White
Write-Host '     Chrome Web Store, rechercher "Claude", installer. Puis activer' -ForegroundColor Gray
Write-Host '     "Autoriser l acces aux URL de fichier" : Chrome > menu Extensions' -ForegroundColor Gray
Write-Host '     (piece de puzzle) > Claude > ... > Gerer l extension > faire defiler.' -ForegroundColor Gray
Write-Host '     Sans ce reglage, Claude ne verra jamais vos ecrans, et ne dira pas pourquoi.' -ForegroundColor Gray
Write-Host ''
Write-Host '  3. Regler OBSIDIAN' -ForegroundColor White
Write-Host '     Reglages > Fichiers et liens > Detecter toutes les extensions de fichier.' -ForegroundColor Gray
Write-Host '     Sans ce reglage, les fichiers HTML que vous produirez seront invisibles.' -ForegroundColor Gray
Write-Host ''
Write-Host 'Etape suivante : fermer et rouvrir le terminal, puis :' -ForegroundColor Cyan
Write-Host '    claude --version'
Write-Host '    claude doctor      # diagnostic complet de l installation'
Write-Host ''
Write-Host 'Puis lancer Diagnostic.cmd et renvoyer la ligne de resultat.' -ForegroundColor Cyan
Write-Host ''

# Un outil facultatif absent n'est pas un echec du script.
if ($echecs.Count -gt 0 -or $claudeBloquant) { exit 1 } else { exit 0 }
