#Requires -Version 5.1
<#
.SYNOPSIS
    Fabrique le zip d'une release de claude-easy-setup a partir du dernier commit.

.DESCRIPTION
    Package le contenu du depot (commit HEAD) dans dist\claude-easy-setup-<version>.zip,
    sans les fichiers propres au depot : .gitattributes, .gitignore, .claude, CLAUDE.md,
    le dossier tests\, ainsi que ce script lui-meme.

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

    Avec -Publish, le script publie ensuite la release sur GitHub via "gh" : il cree
    le tag v<version> sur le commit HEAD, joint le zip et genere les notes de release.
    Sans -Publish, rien n'est envoye nulle part.

.PARAMETER Version
    Numero de version semver, avec ou sans "v" initial : 1.0.0, v1.2.3, 2.0.0-rc.1.
    Une version avec suffixe (2.0.0-rc.1) est publiee comme pre-release.

.PARAMETER OutDir
    Dossier de sortie. Par defaut : dist\ a la racine du depot.

.PARAMETER Publish
    Publie la release sur GitHub avec gh, apres avoir fabrique le zip. Les verifications
    sont faites AVANT la fabrication : gh installe et connecte, arbre de travail propre,
    commit HEAD deja pousse, version pas encore publiee.

.PARAMETER DryRun
    Avec -Publish : fait toutes les verifications et affiche la commande gh sans
    l'executer. Rien n'est publie.

.PARAMETER Help
    Affiche l'aide et quitte. Accepte aussi --help, -h, /? et ?.

.EXAMPLE
    .\Package-Release.ps1 1.0.0

.EXAMPLE
    .\Package-Release.ps1 1.0.0 -Publish

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Package-Release.ps1 -Version 1.1.0 -Publish -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Version,

    [string]$OutDir,

    [switch]$Publish,

    [switch]$DryRun,

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
    .\Package-Release.ps1 <version> [-Publish [-DryRun]] [-OutDir <dossier>]
    powershell -ExecutionPolicy Bypass -File .\Package-Release.ps1 -Version <version>

ARGUMENTS
    <version>, -Version   Numero semver : MAJEUR.MINEUR.CORRECTIF
                          (ex. 1.0.0, v1.2.3, 2.0.0-rc.1). Obligatoire.
                          Un suffixe (2.0.0-rc.1) donne une pre-release.
    -Publish              Publie la release sur GitHub avec gh (tag + zip + notes).
                          Sans lui, le script fabrique le zip et s'arrete.
    -DryRun               Avec -Publish : verifie tout, affiche la commande gh,
                          ne publie rien.
    -OutDir <dossier>     Dossier de sortie. Par defaut : dist\ a la racine du depot.
    --help, -h, -Help, /? Affiche cette aide et quitte.

EXEMPLES
    .\Package-Release.ps1 1.0.0
        Cree dist\claude-easy-setup-1.0.0.zip, sans rien publier.

    .\Package-Release.ps1 1.0.0 -Publish -DryRun
        Idem, plus toutes les verifications de publication, sans publier.

    .\Package-Release.ps1 1.0.0 -Publish
        Cree le zip, puis publie la release v1.0.0 sur GitHub.

    .\Package-Release.ps1 1.1.0 -OutDir C:\Temp\releases
        Cree le zip dans un autre dossier.

CE QUI EST PACKAGE
    Le contenu du dernier COMMIT (pas le dossier de travail), sans
    .gitattributes, .gitignore, .claude, CLAUDE.md, tests\ et ce script.
    Des modifications non commitees sont signalees mais ne sont pas incluses.

CE QUE -Publish EXIGE (verifie avant de fabriquer le zip)
    - gh installe et connecte (gh auth login)
    - aucune modification non commitee
    - le commit HEAD est deja pousse sur la branche suivie
    - la version n'existe pas encore sur GitHub : une version publiee ne se reecrit pas
    Le tag v<version> est cree par gh sur le commit HEAD.
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
    'tests'
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
if ($DryRun -and -not $Publish) {
    Stop-Script "-DryRun ne s'utilise qu'avec -Publish."
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
$tag    = "v$Version"

# Meme precaution que Test-Git, pour gh. gh a besoin d'etre lance depuis le depot.
function Test-Gh {
    $ancien = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $racine
    try { $null = gh @args 2>$null; return ($LASTEXITCODE -eq 0) }
    finally { Pop-Location; $ErrorActionPreference = $ancien }
}

# ---------------------------------------------------------------------------
# 2a. Prealables de la publication (seulement avec -Publish)
#
# Tout est verifie ICI, avant de fabriquer le zip : une publication qui echoue a
# mi-chemin laisserait un tag ou une release a moitie faits sur GitHub.
# ---------------------------------------------------------------------------
$depot = $null
if ($Publish) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Stop-Script "gh (GitHub CLI) est introuvable dans le PATH. Installez-le : winget install --id GitHub.cli"
    }
    if (-not (Test-Gh auth status)) {
        Stop-Script "gh n'est pas connecte a GitHub. Lancez : gh auth login"
    }

    Push-Location $racine
    try { $depot = (gh repo view --json nameWithOwner --jq .nameWithOwner) }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0 -or -not $depot) {
        Stop-Script "gh ne trouve pas de depot GitHub pour $racine."
    }
    $depot = $depot.Trim()

    # On rafraichit les tags distants : un tag cree ailleurs doit etre vu par le controle plus bas.
    if (-not (Test-Git fetch origin --tags --quiet)) {
        Stop-Script "git fetch origin a echoue : impossible de verifier l'etat distant."
    }

    if (-not (Test-Git rev-parse --abbrev-ref --symbolic-full-name '@{u}')) {
        Stop-Script "La branche courante ne suit aucune branche distante. Poussez-la : git push -u origin <branche>"
    }
    if (-not (Test-Git merge-base --is-ancestor HEAD '@{u}')) {
        Stop-Script "Le commit HEAD ($commit) n'est pas pousse. Lancez git push, puis relancez le script."
    }

    if (Test-Gh release view $tag) {
        Stop-Script "La release $tag existe deja sur $depot. Une version publiee ne se reecrit pas : incrementez la version."
    }
}

# "git archive" package HEAD, pas le dossier de travail : des modifications non
# commitees seraient donc absentes du zip sans que rien ne le montre.
$modifs = @(git -C $racine status --porcelain)
if ($modifs.Count -gt 0) {
    Write-Host ''
    Write-Host "  ATTENTION : $($modifs.Count) modification(s) non commitee(s). Elles ne sont PAS dans le zip :" -ForegroundColor Yellow
    $modifs | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    if ($Publish) {
        Stop-Script "Publication refusee : une release doit correspondre a un commit pousse. Commitez et poussez d'abord."
    }
}

# Une release doit correspondre a son tag : si v<version> existe deja ailleurs
# que sur HEAD, ce zip ne serait pas celui de cette version.
if (Test-Git rev-parse --verify --quiet "refs/tags/$tag^{commit}") {
    $commitTag = (git -C $racine rev-parse --short "refs/tags/$tag^{commit}").Trim()
    if ($commitTag -ne $commit) {
        Write-Host ''
        Write-Host "  ATTENTION : le tag $tag existe deja sur le commit $commitTag, mais HEAD est $commit." -ForegroundColor Yellow
        Write-Host "  Ce zip ne correspondra pas au tag. Une version publiee ne se reecrit pas : incrementez-la." -ForegroundColor Yellow
        if ($Publish) {
            Stop-Script "Publication refusee : le tag $tag pointe sur $commitTag, pas sur HEAD ($commit)."
        }
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

# ---------------------------------------------------------------------------
# 5. Publication sur GitHub (seulement avec -Publish)
# ---------------------------------------------------------------------------
if (-not $Publish) {
    Write-Host '  Pour publier sur GitHub (commit pousse, arbre propre) :' -ForegroundColor Cyan
    Write-Host "    .\Package-Release.ps1 $Version -Publish"
    Write-Host ''
    exit 0
}

# --target : le tag est cree sur le commit packageable, pas sur le HEAD distant du moment.
$cible = (git -C $racine rev-parse HEAD).Trim()
$ghArgs = @('release', 'create', $tag, $zip, '--repo', $depot, '--title', $tag, '--generate-notes', '--target', $cible)

# Un suffixe semver (2.0.0-rc.1) designe une pre-release : elle ne doit pas devenir "Latest".
$estPrerelease = ($Version -split '\+')[0] -match '-'
if ($estPrerelease) { $ghArgs += '--prerelease' }

if ($DryRun) {
    Write-Host "  [DryRun] Rien n'est publie. Commande qui serait executee :" -ForegroundColor Yellow
    Write-Host "    gh $($ghArgs -join ' ')"
    Write-Host ''
    exit 0
}

Write-Host "  Publication de $tag sur $depot..." -ForegroundColor Cyan
Push-Location $racine
try { & gh @ghArgs; $codeGh = $LASTEXITCODE }
finally { Pop-Location }

if ($codeGh -ne 0) {
    Stop-Script "gh release create a echoue (code $codeGh). Verifiez sur GitHub qu'aucune release $tag n'a ete creee a moitie."
}

# Recupere le tag cree par gh, pour que le depot local le connaisse.
$null = Test-Git fetch origin --tags --quiet
Write-Host ''
Write-Host "  Release $tag publiee." -ForegroundColor Green
Write-Host ''
