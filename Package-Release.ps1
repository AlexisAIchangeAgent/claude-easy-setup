#Requires -Version 5.1
<#
.SYNOPSIS
    Fabrique le zip d'une release de claude-easy-setup a partir du dernier commit.

.DESCRIPTION
    Package le contenu du depot (commit HEAD) dans dist\claude-easy-setup-<version>.zip,
    sans les fichiers propres au depot : .gitattributes, .gitignore, .claude, CLAUDE.md,
    ainsi que ce script lui-meme.

    Le zip est construit avec "git archive" plutot qu'avec Compress-Archive :
      - les fichiers .command gardent leur bit executable (sinon, sur Mac,
        "Permission denied" au premier lancement) ;
      - les chemins du zip utilisent "/" (Compress-Archive de PowerShell 5.1 ecrit
        des "\" que macOS decompresse en fichiers aux noms casses) ;
      - les fins de ligne suivent .gitattributes (.command en LF, .cmd en CRLF),
        et non la configuration de la machine qui fabrique le zip ;
      - seul ce qui est COMMITE est package, jamais l'etat du dossier de travail.

    Le zip contient un dossier racine claude-easy-setup-<version>\ : a l'extraction,
    on obtient un dossier unique, pas des fichiers eparpilles.

    Versionnage : semver (MAJEUR.MINEUR.CORRECTIF). La premiere release est 1.0.0.

.PARAMETER Version
    Numero de version semver, avec ou sans "v" initial : 1.0.0, v1.2.3, 2.0.0-rc.1.

.PARAMETER OutDir
    Dossier de sortie. Par defaut : dist\ a la racine du depot.

.PARAMETER Help
    Affiche l'aide et quitte. Accepte aussi --help, -h, /? et ?.

.EXAMPLE
    .\Package-Release.ps1 1.0.0

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Package-Release.ps1 -Version 1.1.0
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Version,

    [string]$OutDir,

    [switch]$Help,

    # Recupere les jetons non reconnus par le parseur (--help notamment).
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Aide
# ---------------------------------------------------------------------------
# /? et ? sont pris par PowerShell pour la valeur positionnelle $Version : on les
# cherche donc aussi bien dans $Version que dans les arguments restants.
$jetonsAide = @('/?', '/h', '?', 'help', '--help', '-help', '-h')
$aideDemandee = $Help -or
    ($Version -and ($Version.ToLower() -in $jetonsAide)) -or
    (@($RemainingArguments) | Where-Object { $_ -and ($_.ToLower() -in $jetonsAide) })

if ($aideDemandee) {
    @'
Package-Release.ps1
Fabrique le zip d'une release de claude-easy-setup a partir du dernier commit.

USAGE
    .\Package-Release.ps1 <version> [-OutDir <dossier>]
    powershell -ExecutionPolicy Bypass -File .\Package-Release.ps1 -Version <version>

ARGUMENTS
    <version>, -Version   Numero semver : MAJEUR.MINEUR.CORRECTIF
                          (ex. 1.0.0, v1.2.3, 2.0.0-rc.1). Obligatoire.
    -OutDir <dossier>     Dossier de sortie. Par defaut : dist\ a la racine du depot.
    --help, -h, -Help, /? Affiche cette aide et quitte.

EXEMPLES
    .\Package-Release.ps1 1.0.0
        Cree dist\claude-easy-setup-1.0.0.zip

    .\Package-Release.ps1 1.1.0 -OutDir C:\Temp\releases
        Cree le zip dans un autre dossier.

CE QUI EST PACKAGE
    Le contenu du dernier COMMIT (pas le dossier de travail), sans
    .gitattributes, .gitignore, .claude, CLAUDE.md et ce script.
    Des modifications non commitees sont signalees mais ne sont pas incluses.

APRES LE PACKAGING
    Pousser le commit, puis publier :
        gh release create v<version> dist\claude-easy-setup-<version>.zip --title "v<version>" --generate-notes
'@
    exit 0
}


# Ce qui ne part PAS dans la release (chemins relatifs a la racine du depot).
$Exclusions = @(
    '.gitattributes'
    '.gitignore'
    '.claude'
    'CLAUDE.md'
    'Package-Release.ps1'
)

$NomProjet = 'claude-easy-setup'

# Grammaire semver 2.0.0 officielle (semver.org).
$SemVer = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'

function Stop-Script {
    param([string]$Message)
    Write-Host ''
    Write-Host "  ERREUR : $Message" -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ---------------------------------------------------------------------------
# 1. La version
# ---------------------------------------------------------------------------
if (-not $Version) {
    Stop-Script "Version manquante. Exemple : .\Package-Release.ps1 1.0.0   (aide : -Help)"
}
$Version = $Version.Trim() -replace '^v', ''
if ($Version -notmatch $SemVer) {
    Stop-Script "'$Version' n'est pas un numero semver valide (attendu : MAJEUR.MINEUR.CORRECTIF, ex. 1.0.0)."
}

# ---------------------------------------------------------------------------
# 2. Le depot
# ---------------------------------------------------------------------------
$racine = $PSScriptRoot
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Stop-Script "git est introuvable dans le PATH."
}

# PowerShell 5.1 : sous 'Stop', le stderr d'une commande native redirigee devient une
# exception. On veut juste le code de sortie, donc on relache le mode le temps du test.
function Test-Git {
    $ancien = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $null = git -C $racine @args 2>$null; return ($LASTEXITCODE -eq 0) }
    finally { $ErrorActionPreference = $ancien }
}

if (-not (Test-Git rev-parse --git-dir))      { Stop-Script "$racine n'est pas un depot git." }
if (-not (Test-Git rev-parse --verify HEAD))  { Stop-Script "Le depot n'a aucun commit : rien a packager." }

$commit = (git -C $racine rev-parse --short HEAD).Trim()

# "git archive" package HEAD, pas le dossier de travail : des modifications non
# commitees seraient donc absentes du zip sans que rien ne le montre.
$modifs = @(git -C $racine status --porcelain)
if ($modifs.Count -gt 0) {
    Write-Host ''
    Write-Host "  ATTENTION : $($modifs.Count) modification(s) non commitee(s). Elles ne sont PAS dans le zip :" -ForegroundColor Yellow
    $modifs | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
}

# Une release doit correspondre a son tag : si v<version> existe deja ailleurs
# que sur HEAD, ce zip ne serait pas celui de cette version.
$tag = "v$Version"
if (Test-Git rev-parse --verify --quiet "refs/tags/$tag^{commit}") {
    $commitTag = (git -C $racine rev-parse --short "refs/tags/$tag^{commit}").Trim()
    if ($commitTag -ne $commit) {
        Write-Host ''
        Write-Host "  ATTENTION : le tag $tag existe deja sur le commit $commitTag, mais HEAD est $commit." -ForegroundColor Yellow
        Write-Host "  Ce zip ne correspondra pas au tag. Une version publiee ne se reecrit pas : incrementez-la." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# 3. Le zip
# ---------------------------------------------------------------------------
if (-not $OutDir) { $OutDir = Join-Path $racine 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$base = "$NomProjet-$Version"
$zip  = Join-Path (Resolve-Path $OutDir).Path "$base.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

$pathspecs = @('.') + ($Exclusions | ForEach-Object { ":(exclude)$_" })

# core.autocrlf=false : le contenu du zip ne doit pas dependre du poste qui le fabrique.
git -C $racine -c core.autocrlf=false archive --format=zip --prefix="$base/" --output="$zip" HEAD -- @pathspecs
if ($LASTEXITCODE -ne 0) { Stop-Script "git archive a echoue (code $LASTEXITCODE)." }

# ---------------------------------------------------------------------------
# 4. Controle du resultat
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entrees = @($archive.Entries | Where-Object { $_.FullName -notmatch '/$' } | ForEach-Object { $_.FullName.Substring($base.Length + 1) })
}
finally {
    $archive.Dispose()
}

$intrus = @($entrees | Where-Object {
    $chemin = $_
    $Exclusions | Where-Object { $chemin -eq $_ -or $chemin.StartsWith("$_/") }
})
if ($intrus.Count -gt 0) {
    Remove-Item $zip -Force
    Stop-Script "Des fichiers exclus se retrouvent dans le zip : $($intrus -join ', ')"
}

$taille = [math]::Round((Get-Item $zip).Length / 1KB, 1)
$sha    = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()

Write-Host ''
Write-Host "  Release $Version prete (commit $commit)" -ForegroundColor Green
Write-Host "    Fichier : $zip"
Write-Host "    Taille  : $taille Ko, $($entrees.Count) fichiers"
Write-Host "    SHA-256 : $sha"
Write-Host ''
Write-Host '  Contenu :' -ForegroundColor Cyan
$entrees | ForEach-Object { Write-Host "    $_" }
Write-Host ''
Write-Host '  Pour publier sur GitHub (apres avoir pousse le commit) :' -ForegroundColor Cyan
Write-Host "    gh release create $tag `"$zip`" --title `"$tag`" --generate-notes"
Write-Host ''
