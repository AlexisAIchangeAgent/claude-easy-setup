@echo off
REM ===========================================================================
REM  Diagnostic du poste - journee Agile en Seine du 22/09/2026
REM
REM  Double-cliquez sur ce fichier. C'est tout.
REM
REM  Pourquoi ce lanceur existe : lance directement, un script PowerShell est
REM  refuse par Windows, et le message d'erreur ne dit pas que la cause est la
REM  politique d'execution. Ce fichier passe l'option qui la contourne, pour
REM  cette execution uniquement. Rien n'est modifie sur votre poste.
REM ===========================================================================

setlocal
cd /d "%~dp0"

if not exist "%~dp0Diagnostic-poste.ps1" (
    echo.
    echo   ERREUR : Diagnostic-poste.ps1 est introuvable a cote de ce lanceur.
    echo.
    echo   Cause la plus frequente : le dossier n'a pas ete DEZIPPE. Lance depuis
    echo   l'interieur d'un fichier .zip, un script ne voit pas ses voisins.
    echo   Extrayez d'abord le dossier, puis double-cliquez a nouveau.
    echo.
    pause
    exit /b 9
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnostic-poste.ps1"
set CODE=%ERRORLEVEL%

echo.
if "%CODE%"=="10" goto VERT
if "%CODE%"=="11" goto ORANGE
if "%CODE%"=="12" goto ROUGE
goto PLANTE

:VERT
echo   Verdict VERT. Renvoyez quand meme la ligne de resultat.
goto FIN

:ORANGE
echo   Verdict ORANGE. Renvoyez la ligne de resultat.
goto FIN

:ROUGE
echo   Verdict ROUGE. Renvoyez la ligne de resultat : c'est ce qui permet
echo   de vous aider AVANT le 22, et ca prend dix minutes a distance.
goto FIN

:PLANTE
echo   ---------------------------------------------------------------------
echo   LE DIAGNOSTIC N'A PAS PU S'EXECUTER (code %CODE%^).
echo.
echo   Il n'y a donc aucune ligne de resultat a renvoyer. Ce n'est pas votre
echo   faute et ce n'est pas un verdict.
echo.
echo   Cause la plus frequente sur un poste d'entreprise : une strategie de
echo   securite qui interdit les scripts, et qui prime sur ce lanceur.
echo.
echo   Signalez-le en repondant simplement : "diagnostic bloque, code %CODE%".
echo   ---------------------------------------------------------------------
goto FIN

:FIN
echo.
echo   Un fichier rapport a ete depose dans ce dossier : vous pouvez le
echo   joindre a votre reponse plutot que de recopier la ligne a la main.
echo.
pause
endlocal
