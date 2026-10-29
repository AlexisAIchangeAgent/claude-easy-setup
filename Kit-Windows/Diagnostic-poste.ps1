#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostic du poste avant la journee Agile en Seine du 22/09/2026.

.DESCRIPTION
    LECTURE SEULE. Ce script n'installe rien, ne modifie rien, ne demande
    aucun droit administrateur. Il regarde l'etat du poste et rend un verdict.

    Il repond a une seule question : ce poste peut-il faire la journee ?

    Il produit trois choses :
      1. un tableau lisible a l'ecran ;
      2. une LIGNE DE RESULTAT a renvoyer par mail (c'est elle qui compte) ;
      3. un fichier rapport depose a cote du script.

    Ce que le script ne peut PAS verifier est dit explicitement en fin
    d'execution, avec le geste manuel qui le remplace. Il n'y a pas de
    controle silencieux : soit c'est mesure, soit c'est annonce comme non
    mesurable.

.PARAMETER Help
    Affiche l'aide et quitte. Accepte aussi --help, -h, /? et ?.

.PARAMETER NoFile
    N'ecrit pas le fichier rapport (affichage seul).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Diagnostic-poste.ps1

    La forme qui marche partout. Sans -ExecutionPolicy Bypass, Windows
    refuse d'executer le script et le message d'erreur ne le dit pas
    clairement. Le lanceur Diagnostic.cmd evite ce piege.
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$NoFile,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# StrictMode fait echouer la lecture de $LASTEXITCODE tant qu'aucune commande
# native n'a tourne. On l'initialise avant tout usage.
if (-not (Test-Path Variable:\LASTEXITCODE)) { $global:LASTEXITCODE = 0 }

$script:SEUIL_BUILD_WIN10 = 19041   # Windows 10 version 2004 - exigence Cowork
$script:SEUIL_RAM_GO      = 7.5     # un "8 Go" annonce affiche 7.4 a 7.9 Go : memoire reservee au materiel
$script:SEUIL_DISQUE_GO   = 10
$script:NODE_MAJEUR_CIBLE = 24      # Node 24 LTS - voir le guide
$script:NODE_MAJEUR_MIN   = 20

# ---------------------------------------------------------------------------
# Aide
# ---------------------------------------------------------------------------
if ($Help -or (@($RemainingArguments) | Where-Object { $_ -and ($_.ToLower() -in @('/?', '/h', '?', 'help', '--help', '-help')) })) {
    Write-Host @"
Diagnostic-poste.ps1 - verifie un poste Windows pour la journee du 22/09/2026.

USAGE
    powershell -ExecutionPolicy Bypass -File .\Diagnostic-poste.ps1 [-NoFile]

Le script est en LECTURE SEULE : il n'installe rien et ne modifie rien.
Il rend un verdict VERT / ORANGE / ROUGE et une ligne de resultat a renvoyer.

Plus simple : double-cliquer sur Diagnostic.cmd.
"@
    exit 0
}

# ---------------------------------------------------------------------------
# Collecte des resultats
# ---------------------------------------------------------------------------
$script:Controles = [System.Collections.Generic.List[object]]::new()

function Add-Controle {
    param(
        [Parameter(Mandatory)][string]$Cle,       # code court pour la ligne de resultat
        [Parameter(Mandatory)][string]$Libelle,
        [Parameter(Mandatory)][ValidateSet('OK', 'ALERTE', 'BLOQUANT', 'INCONNU')][string]$Statut,
        [string]$Detail = '',
        [string]$QueFaire = ''
    )
    $script:Controles.Add([pscustomobject]@{
        Cle      = $Cle
        Libelle  = $Libelle
        Statut   = $Statut
        Detail   = $Detail
        QueFaire = $QueFaire
    })
}

function Write-Titre { param([string]$M) Write-Host "`n=== $M" -ForegroundColor Cyan }
function Write-Ligne { param([string]$M) Write-Host "    $M" -ForegroundColor Gray }

# ---------------------------------------------------------------------------
# Sonde une commande : presence ET execution reelle.
# Le -Motif est indispensable pour python.exe : Windows livre un alias
# d'execution qui existe dans le PATH, ne renvoie rien d'utile et ouvre le
# Microsoft Store. Sans controle de motif, il passerait pour un Python installe.
# ---------------------------------------------------------------------------
function Get-VersionOutil {
    param(
        [Parameter(Mandatory)][string]$Commande,
        [string[]]$Arguments = @('--version'),
        [string]$Motif
    )
    if (-not (Get-Command $Commande -ErrorAction SilentlyContinue)) { return $null }

    # PIEGE POWERSHELL 5.1 : avec $ErrorActionPreference = 'Stop' actif au niveau
    # du script, une commande native qui ecrit la moindre ligne sur stderr leve
    # un NativeCommandError TERMINANT. Un simple avertissement de Node ou de Git
    # ferait donc conclure "outil absent", et le poste passerait en ROUGE a tort.
    # On neutralise la preference le temps de l'appel, et on la restaure ensuite.
    $prefPrecedente = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $global:LASTEXITCODE = 0
        $sortie = & $Commande @Arguments 2>&1 |
                  Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
        if ($LASTEXITCODE -ne 0) { return $null }
        $texte = ($sortie | Out-String).Trim()
        if (-not $texte) { return $null }
        $premiere = ($texte -split "`r?`n")[0].Trim()
        if ($Motif -and $premiere -notmatch $Motif) { return $null }
        return $premiere
    }
    catch { return $null }
    finally { $ErrorActionPreference = $prefPrecedente }
}

# ===========================================================================
# 1. Systeme d'exploitation
# ===========================================================================
Write-Titre 'Systeme'

$build = 0
try {
    $os      = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $caption = $os.Caption
    $build   = [int]($os.BuildNumber)
    $arch    = $env:PROCESSOR_ARCHITECTURE

    if ($build -ge $script:SEUIL_BUILD_WIN10) {
        Add-Controle -Cle 'OS' -Libelle 'Version de Windows' -Statut 'OK' `
                     -Detail "$caption (build $build, $arch)"
    }
    else {
        Add-Controle -Cle 'OS' -Libelle 'Version de Windows' -Statut 'BLOQUANT' `
                     -Detail "$caption (build $build)" `
                     -QueFaire "Cowork exige Windows 10 build $($script:SEUIL_BUILD_WIN10) (version 2004) au minimum. Faire Windows Update, ou signaler le poste."
    }
    Write-Ligne "$caption - build $build - $arch"
}
catch {
    Add-Controle -Cle 'OS' -Libelle 'Version de Windows' -Statut 'INCONNU' `
                 -Detail $_.Exception.Message -QueFaire 'Signaler : le script n a pas pu lire la version du systeme.'
}

# ---------------------------------------------------------------------------
# Memoire et disque
# ---------------------------------------------------------------------------
try {
    $cs    = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $ramGo = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    if ($ramGo -ge $script:SEUIL_RAM_GO) {
        Add-Controle -Cle 'RAM' -Libelle 'Memoire vive' -Statut 'OK' -Detail "$ramGo Go"
    }
    else {
        Add-Controle -Cle 'RAM' -Libelle 'Memoire vive' -Statut 'BLOQUANT' -Detail "$ramGo Go" `
                     -QueFaire "$($script:SEUIL_RAM_GO) Go minimum. Ce poste ne pourra pas faire tourner l espace de travail : prevoir un binome."
    }
    Write-Ligne "Memoire : $ramGo Go"
}
catch {
    Add-Controle -Cle 'RAM' -Libelle 'Memoire vive' -Statut 'INCONNU' -Detail $_.Exception.Message
}

try {
    $lettre  = ($env:SystemDrive)
    $disque  = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$lettre'" -ErrorAction Stop
    $libreGo = [math]::Round($disque.FreeSpace / 1GB, 1)
    if ($libreGo -ge $script:SEUIL_DISQUE_GO) {
        Add-Controle -Cle 'DISQUE' -Libelle 'Espace disque libre' -Statut 'OK' -Detail "$libreGo Go sur $lettre"
    }
    else {
        Add-Controle -Cle 'DISQUE' -Libelle 'Espace disque libre' -Statut 'BLOQUANT' -Detail "$libreGo Go sur $lettre" `
                     -QueFaire "$($script:SEUIL_DISQUE_GO) Go libres minimum. Faire de la place avant le 22/09."
    }
    Write-Ligne "Disque libre : $libreGo Go"
}
catch {
    Add-Controle -Cle 'DISQUE' -Libelle 'Espace disque libre' -Statut 'INCONNU' -Detail $_.Exception.Message
}

# ---------------------------------------------------------------------------
# Virtualisation - le point qui ne se rattrape pas le jour J
#
# Trois etats distincts, et c'est la distinction qui rend le resultat utile :
#   hyperviseur present            -> la virtualisation tourne deja, rien a faire
#   firmware OK, pas d hyperviseur -> la fonctionnalite Windows n est pas active,
#                                     l installeur de Claude sait le faire
#   firmware desactive             -> il faut entrer dans le BIOS/UEFI, redemarrage
# ---------------------------------------------------------------------------
Write-Titre 'Virtualisation'
try {
    $cs2         = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $hyperviseur = [bool]$cs2.HypervisorPresent

    $firmware = $null
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu.PSObject.Properties.Name -contains 'VirtualizationFirmwareEnabled') {
            $firmware = $cpu.VirtualizationFirmwareEnabled
        }
    }
    catch { }

    if ($hyperviseur) {
        Add-Controle -Cle 'VIRT' -Libelle 'Virtualisation materielle' -Statut 'OK' `
                     -Detail 'hyperviseur actif'
        Write-Ligne 'Hyperviseur actif : rien a faire.'
    }
    elseif ($firmware -eq $false) {
        Add-Controle -Cle 'VIRT' -Libelle 'Virtualisation materielle' -Statut 'BLOQUANT' `
                     -Detail 'desactivee dans le BIOS/UEFI' `
                     -QueFaire 'Activer la virtualisation dans le BIOS/UEFI (Intel VT-x ou AMD-V). Redemarrage necessaire. C est le point a traiter EN PREMIER : il ne se rattrape pas le 22/09.'
        Write-Ligne 'Desactivee dans le BIOS/UEFI.'
    }
    else {
        Add-Controle -Cle 'VIRT' -Libelle 'Virtualisation materielle' -Statut 'ALERTE' `
                     -Detail 'firmware OK, aucun hyperviseur actif' `
                     -QueFaire 'La fonctionnalite Windows "Plateforme de machine virtuelle" n est probablement pas activee. L installation de Claude Desktop la met en place. A reverifier apres installation.'
        Write-Ligne 'Firmware OK, mais aucun hyperviseur actif pour l instant.'
    }
}
catch {
    Add-Controle -Cle 'VIRT' -Libelle 'Virtualisation materielle' -Statut 'INCONNU' -Detail $_.Exception.Message `
                 -QueFaire 'Non mesurable ici. Utiliser l outil officiel "Cowork readiness check" - voir le guide.'
}

# ===========================================================================
# 2. Claude Desktop - et surtout SOUS QUELLE FORME il est installe
#
# Point critique et invisible autrement : sur Windows, Cowork n existe que
# dans le paquet MSIX. Un poste installe avec l ancien .exe a bien Claude
# Desktop, il ouvre, il repond - et Cowork n y est pas. Le participant ne
# peut pas deviner que c est la cause.
# ===========================================================================
Write-Titre 'Claude Desktop'

# On distingue "la mesure a abouti et n a rien trouve" de "la mesure a echoue".
# Sans cette distinction, un poste durci ou un provider Appx indisponible ferait
# conclure "Claude absent" - donc ROUGE - sur une machine parfaitement installee.
$msix        = $null
$appxMesurable = $true
try { $msix = Get-AppxPackage -Name '*Claude*' -ErrorAction Stop | Select-Object -First 1 }
catch { $appxMesurable = $false }

if ($msix) {
    Add-Controle -Cle 'CLAUDE' -Libelle 'Claude Desktop (paquet MSIX)' -Statut 'OK' `
                 -Detail "$($msix.Name) $($msix.Version)"
    Write-Ligne "Paquet MSIX : $($msix.Name) $($msix.Version) - Cowork peut fonctionner."
}
else {
    # Pas de MSIX : chercher une installation classique, qui est le piege.
    $pistes = New-Object System.Collections.Generic.List[string]
    foreach ($racine in @($env:LOCALAPPDATA, $env:APPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $racine) { continue }
        foreach ($sous in @('AnthropicClaude', 'Claude', 'Programs\Claude', 'Programs\AnthropicClaude')) {
            $chemin = Join-Path $racine $sous
            if (Test-Path $chemin) { $pistes.Add($chemin) }
        }
    }

    if (-not $appxMesurable) {
        Add-Controle -Cle 'CLAUDE' -Libelle 'Claude Desktop (paquet MSIX)' -Statut 'INCONNU' `
                     -Detail 'la liste des applications n a pas pu etre lue sur ce poste' `
                     -QueFaire 'Le script n a pas pu mesurer : ce n est PAS une absence. Verifiez a la main que Claude s ouvre et que l espace de travail (Cowork) demarre, et signalez-le tel quel.'
        Write-Ligne 'Mesure impossible (liste des applications illisible).'
    }
    elseif ($pistes.Count -gt 0) {
        Add-Controle -Cle 'CLAUDE' -Libelle 'Claude Desktop (paquet MSIX)' -Statut 'BLOQUANT' `
                     -Detail "installation hors MSIX detectee : $($pistes[0])" `
                     -QueFaire 'Claude est installe, mais pas sous la forme qui embarque Cowork. Desinstaller, puis reinstaller depuis claude.com/download en acceptant l invite administrateur. Ne PAS installer via winget : le paquet winget installe sans elevation et Cowork ne fonctionne pas (winget-pkgs, ticket 366857).'
        Write-Ligne "Installation detectee hors MSIX : $($pistes[0])"
    }
    else {
        Add-Controle -Cle 'CLAUDE' -Libelle 'Claude Desktop (paquet MSIX)' -Statut 'BLOQUANT' `
                     -Detail 'absent' `
                     -QueFaire 'Installer depuis claude.com/download, en acceptant l invite administrateur. Ne PAS passer par winget (winget-pkgs, ticket 366857).'
        Write-Ligne 'Absent.'
    }
}

# Claude Code CLI - utile, pas indispensable a la journee.
$cli = Get-VersionOutil -Commande 'claude'
if ($cli) {
    Add-Controle -Cle 'CLI' -Libelle 'Claude Code (ligne de commande)' -Statut 'OK' -Detail $cli
}
else {
    Add-Controle -Cle 'CLI' -Libelle 'Claude Code (ligne de commande)' -Statut 'ALERTE' -Detail 'absent ou non visible' `
                 -QueFaire 'Facultatif pour la journee. Si vous venez de l installer, fermez et rouvrez le terminal.'
}

# ===========================================================================
# 3. Outils dont le kit se sert
# ===========================================================================
Write-Titre 'Outils'

# --- Node.js ---------------------------------------------------------------
$node = Get-VersionOutil -Commande 'node'
if ($node) {
    $majeur = 0
    if ($node -match 'v?(\d+)\.') { $majeur = [int]$Matches[1] }
    if ($majeur -ge $script:NODE_MAJEUR_CIBLE) {
        Add-Controle -Cle 'NODE' -Libelle 'Node.js' -Statut 'OK' -Detail $node
    }
    elseif ($majeur -ge $script:NODE_MAJEUR_MIN) {
        Add-Controle -Cle 'NODE' -Libelle 'Node.js' -Statut 'ALERTE' -Detail "$node (cible : $($script:NODE_MAJEUR_CIBLE) LTS)" `
                     -QueFaire "Version utilisable mais en dessous de la cible. Installer Node $($script:NODE_MAJEUR_CIBLE) LTS depuis nodejs.org si possible."
    }
    else {
        Add-Controle -Cle 'NODE' -Libelle 'Node.js' -Statut 'BLOQUANT' -Detail "$node (trop ancienne)" `
                     -QueFaire "Installer Node $($script:NODE_MAJEUR_CIBLE) LTS depuis nodejs.org."
    }
}
else {
    Add-Controle -Cle 'NODE' -Libelle 'Node.js' -Statut 'BLOQUANT' -Detail 'absent' `
                 -QueFaire "Installer Node $($script:NODE_MAJEUR_CIBLE) LTS depuis nodejs.org. Attention : prendre la 24, pas la plus recente affichee."
}

# --- Python ----------------------------------------------------------------
# On essaie les deux formes : sur Windows la commande est 'python', mais un
# poste peut n avoir que 'python3'. Le motif ecarte l alias du Microsoft Store.
$python = Get-VersionOutil -Commande 'python'  -Motif '^Python\s+3\.'
if (-not $python) { $python = Get-VersionOutil -Commande 'python3' -Motif '^Python\s+3\.' }

if ($python) {
    $mineur = -1
    if ($python -match '^Python\s+3\.(\d+)') { $mineur = [int]$Matches[1] }
    if ($mineur -ge 10) {
        Add-Controle -Cle 'PY' -Libelle 'Python' -Statut 'OK' -Detail $python
    }
    else {
        Add-Controle -Cle 'PY' -Libelle 'Python' -Statut 'BLOQUANT' -Detail "$python (3.10 minimum)" `
                     -QueFaire 'Installer Python 3.10 ou plus depuis python.org.'
    }
}
else {
    Add-Controle -Cle 'PY' -Libelle 'Python' -Statut 'BLOQUANT' -Detail 'absent, ou present sans etre dans le PATH' `
                 -QueFaire 'Deux causes possibles. (1) Python n est pas installe : le prendre sur python.org en cochant "Add python.exe to PATH" sur le PREMIER ecran de l installeur - la case n est pas cochee par defaut, et sans elle la commande reste introuvable. (2) Python est installe mais masque par l alias du Microsoft Store : Parametres > Applications > Parametres avances des applications > Alias d execution d application, puis desactiver python.exe et python3.exe.'
}

# --- Git -------------------------------------------------------------------
$git = Get-VersionOutil -Commande 'git'
if ($git) {
    Add-Controle -Cle 'GIT' -Libelle 'Git' -Statut 'OK' -Detail $git
}
else {
    Add-Controle -Cle 'GIT' -Libelle 'Git' -Statut 'ALERTE' -Detail 'absent' `
                 -QueFaire 'Facultatif. Sans Git, Claude utilise l outil PowerShell au lieu de Bash. Installable depuis git-scm.com.'
}

# --- Chrome ----------------------------------------------------------------
$cheminsChrome = New-Object System.Collections.Generic.List[string]
foreach ($racine in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
    if ($racine) { $cheminsChrome.Add((Join-Path $racine 'Google\Chrome\Application\chrome.exe')) }
}
$chrome = $null
foreach ($c in $cheminsChrome) {
    if (Test-Path $c) { $chrome = $c; break }
}

if ($chrome) {
    $versionChrome = ''
    try { $versionChrome = (Get-Item $chrome).VersionInfo.ProductVersion } catch { }
    $detailChrome = if ($versionChrome) { "version $versionChrome" } else { 'present (version non lisible)' }
    Add-Controle -Cle 'CHROME' -Libelle 'Google Chrome' -Statut 'OK' -Detail $detailChrome
}
else {
    Add-Controle -Cle 'CHROME' -Libelle 'Google Chrome' -Statut 'BLOQUANT' -Detail 'absent' `
                 -QueFaire 'Chrome est impose : l extension de verification visuelle n existe que la. Installer depuis google.com/chrome.'
}

# --- Extension Claude pour Chrome ------------------------------------------
# Detection au mieux : on parcourt les profils Chrome et on lit le nom declare
# par chaque extension. Une extension dont le nom est localise s affiche sous
# la forme __MSG_xxx__ : on retombe alors sur les fichiers de traduction.
# Resultat a lire comme un INDICE, pas comme une preuve - la seule verification
# qui tranche est le test visuel decrit en fin de script.
$extensionTrouvee = $false
$profilsLus       = 0
try {
    $userData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    if (Test-Path $userData) {
        $profils = @(Get-ChildItem -Path $userData -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        foreach ($profil in $profils) {
            $profilsLus++
            $dossierExt = Join-Path $profil.FullName 'Extensions'
            if (-not (Test-Path $dossierExt)) { continue }

            foreach ($manifeste in (Get-ChildItem -Path $dossierExt -Filter 'manifest.json' -Recurse -Depth 2 -ErrorAction SilentlyContinue)) {
                $texte = ''
                try { $texte = Get-Content $manifeste.FullName -Raw -ErrorAction Stop } catch { continue }
                if ($texte -match '(?i)claude') { $extensionTrouvee = $true; break }

                # Nom localise : le vrai libelle est dans _locales/<lang>/messages.json
                if ($texte -match '__MSG_') {
                    $racineExt = Split-Path $manifeste.FullName -Parent
                    $locales   = Join-Path $racineExt '_locales'
                    if (Test-Path $locales) {
                        $messages = @(Get-ChildItem -Path $locales -Filter 'messages.json' -Recurse -ErrorAction SilentlyContinue)
                        foreach ($m in $messages) {
                            try {
                                if ((Get-Content $m.FullName -Raw -ErrorAction Stop) -match '(?i)claude') {
                                    $extensionTrouvee = $true; break
                                }
                            }
                            catch { }
                        }
                    }
                }
                if ($extensionTrouvee) { break }
            }
            if ($extensionTrouvee) { break }
        }
    }
}
catch { }

if ($extensionTrouvee) {
    Add-Controle -Cle 'EXT' -Libelle 'Extension Claude pour Chrome' -Statut 'OK' `
                 -Detail "detectee dans les profils Chrome ($profilsLus profil(s) lu(s))" `
                 -QueFaire 'Presence detectee. Son REGLAGE reste a verifier a la main - voir le test visuel en fin de script.'
}
elseif ($chrome) {
    Add-Controle -Cle 'EXT' -Libelle 'Extension Claude pour Chrome' -Statut 'ALERTE' `
                 -Detail "non detectee ($profilsLus profil(s) Chrome lu(s))" `
                 -QueFaire 'Installer l extension Claude depuis le Chrome Web Store, puis activer "Autoriser l acces aux URL de fichier". La detection automatique est imparfaite : si vous savez l avoir installee, faites le test visuel en fin de script.'
}
else {
    Add-Controle -Cle 'EXT' -Libelle 'Extension Claude pour Chrome' -Statut 'ALERTE' -Detail 'Chrome absent' `
                 -QueFaire 'Installer Chrome d abord.'
}

# --- Obsidian --------------------------------------------------------------
$obsidian = $null
foreach ($racine in @($env:LOCALAPPDATA, $env:ProgramFiles)) {
    if (-not $racine) { continue }
    foreach ($sous in @('Obsidian\Obsidian.exe', 'Programs\Obsidian\Obsidian.exe', 'Obsidian\obsidian.exe')) {
        $c = Join-Path $racine $sous
        if (Test-Path $c) { $obsidian = $c; break }
    }
    if ($obsidian) { break }
}

if ($obsidian) {
    Add-Controle -Cle 'OBS' -Libelle 'Obsidian' -Statut 'OK' -Detail $obsidian
}
else {
    Add-Controle -Cle 'OBS' -Libelle 'Obsidian' -Statut 'ALERTE' -Detail 'absent' `
                 -QueFaire 'Installer depuis obsidian.md. Sans lui, vous ne verrez pas l arborescence de votre travail.'
}

# ===========================================================================
# 4. Le tableau
# ===========================================================================
Write-Titre 'Resultat'

$affichage = $script:Controles | ForEach-Object {
    [pscustomobject]@{
        Controle = $_.Libelle
        Statut   = $_.Statut
        Detail   = if ($_.Detail.Length -gt 58) { $_.Detail.Substring(0, 55) + '...' } else { $_.Detail }
    }
}
# -Width explicite : sans lui, Format-Table rend un tableau VIDE quand l hote
# n a pas de largeur de console (sortie redirigee, double-clic sur un .cmd).
$tableau = $affichage | Format-Table -AutoSize | Out-String -Width 200
Write-Host $tableau

$bloquants = @($script:Controles | Where-Object { $_.Statut -eq 'BLOQUANT' })
$alertes   = @($script:Controles | Where-Object { $_.Statut -eq 'ALERTE' })
$inconnus  = @($script:Controles | Where-Object { $_.Statut -eq 'INCONNU' })

if ($bloquants.Count -gt 0)                            { $verdict = 'ROUGE' }
elseif ($alertes.Count -gt 0 -or $inconnus.Count -gt 0) { $verdict = 'ORANGE' }
else                                                    { $verdict = 'VERT' }

switch ($verdict) {
    'VERT'   { Write-Host "VERDICT : VERT - ce poste peut faire la journee." -ForegroundColor Green }
    'ORANGE' { Write-Host "VERDICT : ORANGE - utilisable, mais des points restent a traiter." -ForegroundColor Yellow }
    'ROUGE'  { Write-Host "VERDICT : ROUGE - en l etat, ce poste ne peut pas faire la journee." -ForegroundColor Red }
}

# --- Ce qu il y a a faire, dans l ordre ------------------------------------
if ($bloquants.Count -gt 0 -or $alertes.Count -gt 0) {
    Write-Titre 'Ce qu il reste a faire'
    $rang = 0
    foreach ($c in ($bloquants + $alertes)) {
        if (-not $c.QueFaire) { continue }
        $rang++
        $marque = if ($c.Statut -eq 'BLOQUANT') { '[BLOQUANT]' } else { '[a traiter]' }
        Write-Host "  $rang. $marque $($c.Libelle)" -ForegroundColor $(if ($c.Statut -eq 'BLOQUANT') { 'Red' } else { 'Yellow' })
        Write-Host "     $($c.QueFaire)" -ForegroundColor Gray
    }
}

# ===========================================================================
# 5. Ce que ce script ne peut PAS verifier
#
# Les deux reglages qui echouent EN SILENCE ne sont pas lisibles de l exterieur.
# Plutot que de faire semblant, le script fabrique le materiel du test et donne
# la phrase exacte a taper. Le participant n a rien a juger : il compare la
# reponse de Claude a la reponse attendue.
# ===========================================================================
Write-Titre 'Les deux points que ce script ne peut pas verifier'

$dossier = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$testHtml = Join-Path $dossier 'test-vision.html'
$motTest  = 'MARGUERITE-7431'

$contenuTest = @"
<!doctype html>
<html lang="fr">
<head><meta charset="utf-8"><title>Test de vision - AES 2026</title></head>
<body style="font-family:system-ui,sans-serif;background:#101418;color:#f2f4f7;
             display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
  <div style="text-align:center">
    <p style="font-size:14px;letter-spacing:.14em;text-transform:uppercase;color:#9aa4b2;margin:0 0 12px">
      Mot de controle
    </p>
    <p style="font-size:44px;font-weight:700;margin:0;color:#ffd479">$motTest</p>
  </div>
</body>
</html>
"@

# Ecriture SANS BOM : Set-Content -Encoding UTF8 en PowerShell 5.1 prefixe le
# fichier d une marque d octets, qui se retrouverait avant le <!doctype html>.
function Write-TexteUtf8SansBom {
    param([Parameter(Mandatory)][string]$Chemin, [Parameter(Mandatory)][string]$Texte)
    $encodage = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Chemin, $Texte, $encodage)
}

$testEcrit = $false
if (-not $NoFile) {
    try {
        Write-TexteUtf8SansBom -Chemin $testHtml -Texte $contenuTest
        $testEcrit = $true
    }
    catch { }
}

Write-Host ''
Write-Host '  1. L autorisation "Autoriser l acces aux URL de fichier" de l extension Chrome' -ForegroundColor White
Write-Host '     Elle n est pas lisible depuis un script. Sans elle, Claude ne voit jamais vos' -ForegroundColor Gray
Write-Host '     ecrans - et il ne dit pas pourquoi.' -ForegroundColor Gray
Write-Host ''
if ($testEcrit) {
    Write-Host '     TEST (1 minute) :' -ForegroundColor White
    Write-Host '       a. Ouvrir CHROME d abord, puis FAIRE GLISSER ce fichier sur la fenetre :' -ForegroundColor Gray
    Write-Host "          $testHtml" -ForegroundColor Gray
    Write-Host '          (un double-clic l ouvrirait dans votre navigateur par defaut, qui' -ForegroundColor DarkGray
    Write-Host '           n est peut-etre pas Chrome - le test conclurait faux)' -ForegroundColor DarkGray
    Write-Host '       b. Cliquer sur l extension Claude, et taper exactement :' -ForegroundColor Gray
    Write-Host '            Quel mot est affiche sur cette page ?' -ForegroundColor Cyan
    Write-Host "       c. Reponse attendue : $motTest" -ForegroundColor Gray
    Write-Host '       d. Toute autre reponse = l autorisation manque. Voir le guide, section 3.' -ForegroundColor Gray
}
elseif ($NoFile) {
    Write-Host '     (mode -NoFile : le fichier de test n a pas ete cree)' -ForegroundColor Yellow
}
else {
    Write-Host "     (le fichier de test n a pas pu etre ecrit dans $dossier)" -ForegroundColor Yellow
}
Write-Host ''
Write-Host '  2. Le reglage Obsidian "Detecter toutes les extensions de fichier"' -ForegroundColor White
Write-Host '     Reglages > Fichiers et liens > Detecter toutes les extensions de fichier.' -ForegroundColor Gray
Write-Host '     Sans lui, les fichiers HTML que vous produirez seront invisibles dans la liste.' -ForegroundColor Gray

# ===========================================================================
# 6. La ligne de resultat - c est elle qu on renvoie
# ===========================================================================
$codes = ($script:Controles | ForEach-Object {
    $abrege = switch ($_.Statut) {
        'OK'       { 'OK' }
        'ALERTE'   { '!!' }
        'BLOQUANT' { 'KO' }
        default    { '??' }
    }
    "$($_.Cle):$abrege"
}) -join ' '

$horodatage  = Get-Date -Format 'yyyy-MM-dd HH:mm'
$etiqBuild   = if ($build -gt 0) { "WIN build $build" } else { 'WIN build inconnu' }
$etiqUser    = if ($env:USERNAME) { $env:USERNAME } else { 'utilisateur inconnu' }
$ligne = "AES2026 | $etiqBuild | $etiqUser | $horodatage | VERDICT:$verdict | $codes"

Write-Titre 'A renvoyer par mail - copier la ligne ci-dessous'
Write-Host ''
Write-Host $ligne -ForegroundColor Cyan
Write-Host ''

# ===========================================================================
# 7. Le fichier rapport
# ===========================================================================
if (-not $NoFile) {
    $nomRapport = "Diagnostic-$env:USERNAME-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
    $chemin     = Join-Path $dossier $nomRapport

    $lignes = New-Object System.Collections.Generic.List[string]
    $lignes.Add('Diagnostic du poste - journee Agile en Seine du 22/09/2026')
    $lignes.Add("Genere le $horodatage sur $env:COMPUTERNAME par $env:USERNAME")
    $lignes.Add('')
    $lignes.Add($ligne)
    $lignes.Add('')
    $lignes.Add($tableau.Trim())
    $lignes.Add('')
    $lignes.Add('Detail complet :')
    foreach ($c in $script:Controles) {
        $lignes.Add("  [$($c.Statut)] $($c.Libelle) - $($c.Detail)")
        if ($c.QueFaire) { $lignes.Add("      -> $($c.QueFaire)") }
    }
    $lignes.Add('')
    $lignes.Add('Non verifiable par script : autorisation "acces aux URL de fichier" de')
    $lignes.Add('l extension Chrome, et reglage Obsidian "detecter toutes les extensions".')

    try {
        Write-TexteUtf8SansBom -Chemin $chemin -Texte (($lignes -join [Environment]::NewLine) + [Environment]::NewLine)
        Write-Ligne "Rapport ecrit : $chemin"
        Write-Ligne 'Vous pouvez joindre ce fichier a votre reponse plutot que de recopier la ligne.'
    }
    catch {
        Write-Ligne "Rapport non ecrit ($($_.Exception.Message)) - la ligne ci-dessus suffit."
    }
}

Write-Host ''
Write-Host 'Renvoyez la ligne de resultat, meme si elle est ROUGE.' -ForegroundColor Cyan
Write-Host 'Un poste rouge signale a l avance se traite ; un poste rouge decouvert' -ForegroundColor Gray
Write-Host 'le 22 au matin coute la matinee.' -ForegroundColor Gray
Write-Host ''

# Codes de sortie VOLONTAIREMENT eloignes de 0/1/2.
#
# Raison : PowerShell rend lui-meme 1 quand le script n a pas pu s executer du
# tout - refus de la politique d execution, exception non rattrapee. Si le
# verdict ORANGE valait aussi 1, le lanceur annoncerait "ORANGE" a quelqu un
# dont le diagnostic a plante et qui n a aucune ligne a renvoyer. Avec 10/11/12,
# tout autre code signifie "le diagnostic n a pas tourne".
switch ($verdict) {
    'VERT'   { exit 10 }
    'ORANGE' { exit 11 }
    default  { exit 12 }
}
