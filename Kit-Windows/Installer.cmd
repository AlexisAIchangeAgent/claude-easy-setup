@echo off
REM ===========================================================================
REM  Installation des outils - journee Agile en Seine du 22/09/2026
REM
REM  Double-cliquez sur ce fichier. C'est tout.
REM
REM  Pourquoi ce lanceur existe : lance directement, un script PowerShell est
REM  refuse par Windows, et le message d'erreur ne dit pas que la cause est la
REM  politique d'execution. C'est le piege le plus courant, et il fait croire
REM  a tort que le script ne marche pas sur votre version de Windows.
REM  Ce fichier passe l'option qui le contourne, pour cette execution
REM  uniquement.
REM
REM  Ce script INSTALLE des logiciels. Windows affichera des demandes
REM  d'autorisation (UAC) : elles sont normales, il faut les accepter.
REM ===========================================================================

setlocal
cd /d "%~dp0"

if not exist "%~dp0Setup-ClaudeWorkstation.ps1" (
    echo.
    echo   ERREUR : Setup-ClaudeWorkstation.ps1 est introuvable a cote de ce lanceur.
    echo.
    echo   Cause la plus frequente : le dossier n'a pas ete DEZIPPE. Lance depuis
    echo   l'interieur d'un fichier .zip, un script ne voit pas ses voisins.
    echo   Extrayez d'abord le dossier, puis double-cliquez a nouveau.
    echo.
    pause
    exit /b 9
)

echo.
echo   Installation des outils pour la journee du 22/09/2026.
echo   Des demandes d'autorisation Windows vont apparaitre : acceptez-les.
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-ClaudeWorkstation.ps1"
set CODE=%ERRORLEVEL%

echo.
if not "%CODE%"=="0" (
    echo   ATTENTION : au moins une etape d'installation a echoue ^(code %CODE%^).
    echo   Ce n'est pas bloquant a ce stade : le diagnostic de l'etape 4 dira
    echo   exactement ce qui manque encore, et dans quel ordre le traiter.
    echo.
)

echo   ---------------------------------------------------------------------
echo   ETAPE SUIVANTE, ET ELLE COMPTE :
echo.
echo     1. Installer Google Chrome et Obsidian s'ils ne sont pas deja la
echo     2. Installer Claude Desktop a la main depuis  https://claude.com/download
echo        (le script ne le fait pas : il faut les droits administrateur,
echo         et surtout il ne faut PAS passer par winget)
echo     3. FERMER cette fenetre, en rouvrir une neuve
echo     4. Double-cliquer sur  Diagnostic.cmd
echo     5. Renvoyer la ligne de resultat
echo   ---------------------------------------------------------------------
echo.
pause
endlocal
