#Requires -Version 5.1
<#
.SYNOPSIS
    Tests des kits : seuil de RAM du diagnostic Windows, et scripts macOS executes sous zsh via WSL.

.DESCRIPTION
    Ne modifie rien sur le poste et n'installe rien.

    1. Diagnostic Windows : le script est lance avec une fausse memoire (Get-CimInstance est
       remplace par une fonction), pour verifier le seuil de RAM aux valeurs limites.
    2. Scripts macOS : il n'y a pas de Mac ici. Ils sont verifies sous zsh dans WSL :
       - zsh -n (syntaxe) ;
       - execution avec des commandes macOS simulees (voir macos-zsh-harness.sh), qui couvre
         le seuil de RAM, les parcours du diagnostic et de l'installeur.

    Ces tests REMPLACENT l'essai sur un Mac, sans le valoir : sw_vers, sysctl, Homebrew,
    Gatekeeper et les amorces des outils Apple ne sont que simules.

    Code de sortie : 0 = tout passe, 1 = au moins un echec, 2 = tests macOS non executes
    (WSL, distribution ou zsh absents) : dans ce cas le macOS est NON VERIFIE.

.PARAMETER Distro
    Distribution WSL qui a zsh. Par defaut : Ubuntu-24.04.

.PARAMETER SansWsl
    Ne lance que les tests Windows (les tests macOS comptent alors comme non executes).

.PARAMETER Help
    Affiche l'aide et quitte. Accepte aussi --help, -h, /? et ?.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Kits.ps1
#>

[CmdletBinding()]
param(
    [string]$Distro = 'Ubuntu-24.04',
    [switch]$SansWsl,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$jetonsAide = @('/?', '/h', '?', 'help', '--help', '-help', '-h')
if ($Help -or (@($RemainingArguments) | Where-Object { $_ -and ($_.ToLower() -in $jetonsAide) })) {
    @'
Test-Kits.ps1 - tests du seuil de RAM Windows et des scripts macOS sous zsh (WSL).

USAGE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Kits.ps1 [-Distro <nom>] [-SansWsl]

    -Distro <nom>   Distribution WSL qui a zsh (defaut : Ubuntu-24.04).
    -SansWsl        Ne lance que les tests Windows.
    --help, -h      Affiche cette aide.

CODE DE SORTIE
    0 = tout passe   1 = au moins un echec   2 = tests macOS non executes (macOS NON VERIFIE)
'@
    exit 0
}

$racine   = Split-Path $PSScriptRoot -Parent
$script:Passes  = 0
$script:Echecs  = 0

function Assert-Test {
    param([string]$Nom, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:Passes++
        Write-Host ("  ok    {0}" -f $Nom) -ForegroundColor Green
    }
    else {
        $script:Echecs++
        Write-Host ("  ECHEC {0}" -f $Nom) -ForegroundColor Red
        if ($Detail) { Write-Host ("        {0}" -f $Detail) -ForegroundColor Red }
    }
}

# ===========================================================================
# 1. Diagnostic Windows : seuil de RAM
# ===========================================================================
Write-Host ''
Write-Host '=== Diagnostic Windows : seuil de RAM (7.5 Go)' -ForegroundColor Cyan

$diag = Join-Path $racine 'Kit-Windows\Diagnostic-poste.ps1'

# Une fonction masque la commande du meme nom : le script teste voit une fausse memoire,
# tout le reste passe par la vraie commande.
$proxy = @'
function Get-CimInstance {
    if ($args.Count -gt 0 -and $args[0] -eq 'Win32_ComputerSystem') {
        [pscustomobject]@{ TotalPhysicalMemory = [int64]$env:FAKE_RAM; HypervisorPresent = $true }
    }
    else {
        $reel = Get-Command Get-CimInstance -CommandType Cmdlet
        & $reel @args
    }
}
'@

function Invoke-DiagnosticRam {
    param([double]$Go)
    $env:FAKE_RAM = [string][int64]($Go * 1GB)
    # Fichier temporaire + -File : -EncodedCommand renvoie du CLIXML quand la sortie est capturee.
    # ASCII : le fichier ne contient aucun accent (voir la regle du depot sur les scripts).
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("diag-ram-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    try {
        Set-Content -Path $temp -Value "$proxy`r`n& '$diag' -NoFile" -Encoding ASCII
        $sortie = powershell -NoProfile -ExecutionPolicy Bypass -File $temp | Out-String
    }
    finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\FAKE_RAM -ErrorAction SilentlyContinue
    }
    return $sortie
}

$casRam = @(
    @{ Go = 4.0; Attendu = 'KO' },
    @{ Go = 7.4; Attendu = 'KO' },
    @{ Go = 7.5; Attendu = 'OK' },     # pile sur le seuil
    @{ Go = 7.6; Attendu = 'OK' },
    @{ Go = 8.0; Attendu = 'OK' },
    @{ Go = 16.0; Attendu = 'OK' }
)
foreach ($cas in $casRam) {
    $sortie = Invoke-DiagnosticRam -Go $cas.Go
    $code   = if ($sortie -match 'RAM:(\S+)') { $Matches[1] } else { 'absent' }
    Assert-Test ("RAM {0} Go -> RAM:{1}" -f $cas.Go, $cas.Attendu) ($code -eq $cas.Attendu) "obtenu RAM:$code"
}
$s74 = Invoke-DiagnosticRam -Go 7.4
Assert-Test 'RAM 7.4 Go : le message annonce 7.5 Go minimum' ($s74 -match '7\.5 Go minimum')
$s75 = Invoke-DiagnosticRam -Go 7.5
Assert-Test 'RAM 7.5 Go : affichage "Memoire : 7.5 Go"' ($s75 -match 'Memoire : 7\.5 Go')

# ===========================================================================
# 2. Scripts macOS sous zsh, via WSL
# ===========================================================================
Write-Host ''
Write-Host ("=== Scripts macOS sous zsh (WSL, {0})" -f $Distro) -ForegroundColor Cyan

$macOsNonExecute = $false
$wslOk = $false
if (-not $SansWsl -and (Get-Command wsl -ErrorAction SilentlyContinue)) {
    # wsl.exe ecrit ses propres messages en UTF-16 : on ne s'y fie qu'au code de sortie.
    $ancien = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $null = wsl -d $Distro -- sh -c 'command -v zsh' 2>$null
    $wslOk = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $ancien
}

if (-not $wslOk) {
    $macOsNonExecute = $true
    Write-Host '  NON EXECUTE : WSL, la distribution ou zsh est introuvable (ou -SansWsl).' -ForegroundColor Yellow
    Write-Host ("  Installer zsh : wsl -d {0} -u root -- apt-get install -y zsh" -f $Distro) -ForegroundColor Yellow
    Write-Host '  Les scripts macOS sont NON VERIFIES.' -ForegroundColor Yellow
}
else {
    $kit = Join-Path $racine 'Kit-macOS'

    # --- 2a. Syntaxe
    foreach ($f in (Get-ChildItem -Path $kit -Filter '*.command')) {
        $null = wsl -d $Distro --cd $kit -- zsh -n $f.Name
        Assert-Test ("zsh -n {0}" -f $f.Name) ($LASTEXITCODE -eq 0) "code $LASTEXITCODE"
    }

    # --- 2b. Execution avec commandes macOS simulees
    $tests = Join-Path $racine 'tests'
    $brut  = wsl -d $Distro --cd $tests -- bash ./macos-zsh-harness.sh
    $harnaisCode = $LASTEXITCODE
    $lignes = @($brut | ForEach-Object { ([string]$_) -replace "`0", '' })

    $scen   = @{}     # nom -> objet (exit, stderr, resultat, lignes)
    foreach ($l in $lignes) {
        $p = $l -split '\|', 5
        if ($p[0] -eq 'SCEN' -and $p.Count -ge 4) {
            $scen[$p[1]] = [pscustomobject]@{
                Exit = [int]$p[2]; Stderr = [int]$p[3]
                Resultat = $(if ($p.Count -ge 5) { $p[4] } else { '' })
                Bilan = (New-Object System.Collections.Generic.List[string])
            }
        }
        elseif ($p[0] -eq 'LIGNE' -and $p.Count -ge 3 -and $scen.ContainsKey($p[1])) {
            $scen[$p[1]].Bilan.Add(($l -split '\|', 3)[2])
        }
        elseif ($p[0] -eq 'ERREUR') {
            Assert-Test 'harnais macOS' $false $l
        }
    }
    Assert-Test 'le harnais macOS a produit ses scenarios' ($scen.Count -ge 10) ("{0} scenario(s), code {1}" -f $scen.Count, $harnaisCode)

    function Get-Scen { param([string]$Nom) if ($scen.ContainsKey($Nom)) { $scen[$Nom] } else { [pscustomobject]@{ Exit = -1; Stderr = -1; Resultat = ''; Bilan = @() } } }

    foreach ($nom in @($scen.Keys | Sort-Object)) {
        Assert-Test ("{0} : rien sur stderr" -f $nom) ($scen[$nom].Stderr -eq 0) ("{0} octet(s) sur stderr" -f $scen[$nom].Stderr)
    }

    # Diagnostic macOS : seuil de RAM
    Assert-Test 'macOS RAM 7.4 Go -> RAM:KO' ((Get-Scen 'ram_7_4').Resultat  -match 'RAM:KO') (Get-Scen 'ram_7_4').Resultat
    Assert-Test 'macOS RAM 7.5 Go -> RAM:OK' ((Get-Scen 'ram_7_5').Resultat  -match 'RAM:OK') (Get-Scen 'ram_7_5').Resultat
    Assert-Test 'macOS RAM 8 Go -> RAM:OK'   ((Get-Scen 'ram_8').Resultat    -match 'RAM:OK') (Get-Scen 'ram_8').Resultat
    Assert-Test 'macOS RAM 16 Go -> RAM:OK'  ((Get-Scen 'ram_16').Resultat   -match 'RAM:OK') (Get-Scen 'ram_16').Resultat

    # Diagnostic macOS : parcours
    $ok = Get-Scen 'tout_ok'
    Assert-Test 'macOS tout OK : VERT, code 0' ($ok.Exit -eq 0 -and $ok.Resultat -match 'VERDICT:VERT') ("code {0} : {1}" -f $ok.Exit, $ok.Resultat)
    Assert-Test 'macOS tout OK : 13 controles, du premier (OS) au dernier (OBS)' (($ok.Resultat -split ' ' | Where-Object { $_ -match '^[A-Z]+:\S+$' -and $_ -notmatch '^VERDICT:' }).Count -eq 13 -and $ok.Resultat -match 'OS:OK' -and $ok.Resultat -match 'OBS:OK') $ok.Resultat
    $rouge = Get-Scen 'sans_claude_ni_node'
    Assert-Test 'macOS sans Claude ni Node : ROUGE, code 2' ($rouge.Exit -eq 2 -and $rouge.Resultat -match 'VERDICT:ROUGE' -and $rouge.Resultat -match 'CLAUDE:KO' -and $rouge.Resultat -match 'NODE:KO') $rouge.Resultat
    Assert-Test 'macOS extension dans "Profile 1" : EXT:OK (glob Profile*(N))' ((Get-Scen 'extension_profile_1').Resultat -match 'EXT:OK') (Get-Scen 'extension_profile_1').Resultat

    # Installeur macOS
    Assert-Test 'macOS installeur --help : code 0' ((Get-Scen 'aide').Exit -eq 0)
    $inst = Get-Scen 'installe_node_python'
    $bilanInst = $inst.Bilan -join "`n"
    Assert-Test 'macOS installeur : Node installe puis retrouve (OK)'   ($bilanInst -match 'Node\.js\s+OK')
    Assert-Test 'macOS installeur : Python installe puis retrouve (OK)' ($bilanInst -match 'Python\s+OK')
    Assert-Test 'macOS installeur : app non creee par brew = ECHEC, pas OK, code 1' ($bilanInst -match 'Google Chrome\s+ECHEC' -and $inst.Exit -eq 1) ("code {0}" -f $inst.Exit)
    $refus = Get-Scen 'refus_homebrew'
    Assert-Test 'macOS installeur : Homebrew refuse = ACTION MANUELLE, code 0' (($refus.Bilan -join "`n") -match 'Homebrew\s+ACTION MANUELLE' -and $refus.Exit -eq 0) ("code {0}" -f $refus.Exit)
}

# ===========================================================================
# Bilan
# ===========================================================================
Write-Host ''
Write-Host ("  {0} test(s) passe(s), {1} echec(s)" -f $script:Passes, $script:Echecs) -ForegroundColor $(if ($script:Echecs -eq 0) { 'Green' } else { 'Red' })
if ($macOsNonExecute) { Write-Host '  Tests macOS NON EXECUTES : macOS NON VERIFIE.' -ForegroundColor Yellow }
Write-Host ''

if ($script:Echecs -gt 0) { exit 1 }
if ($macOsNonExecute)     { exit 2 }
exit 0
