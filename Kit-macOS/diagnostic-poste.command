#!/bin/bash
# ===========================================================================
#  Diagnostic du poste - journee Agile en Seine du 22/09/2026  (macOS)
#
#  LECTURE SEULE. Ce script n'installe rien, ne modifie rien, et ne demande
#  aucun mot de passe administrateur. Il regarde l'etat du poste et rend un
#  verdict.
#
#  Double-cliquez sur ce fichier. Si macOS refuse de l'ouvrir, voir le guide,
#  section "Premier lancement sur Mac".
#
#  Ecrit pour bash 3.2, la version livree avec macOS : pas de tableaux
#  associatifs, pas de mapfile, pas de ${var,,}. Ne pas "moderniser".
# ===========================================================================

set -u

SEUIL_MACOS_MAJEUR=14      # macOS 14 Sonoma - exigence Cowork
SEUIL_RAM_GO=8
SEUIL_DISQUE_GO=10
NODE_MAJEUR_CIBLE=24
NODE_MAJEUR_MIN=20

MOT_TEST="MARGUERITE-7431"

# Couleurs, desactivees si la sortie n'est pas un terminal.
if [ -t 1 ]; then
  C_TITRE=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'
  C_KO=$'\033[31m';    C_GRIS=$'\033[90m'; C_OFF=$'\033[0m'
else
  C_TITRE=""; C_OK=""; C_WARN=""; C_KO=""; C_GRIS=""; C_OFF=""
fi

# Tableaux paralleles - bash 3.2 n'a pas d'associatif.
CLES=(); LIBELLES=(); STATUTS=(); DETAILS=(); QUEFAIRE=()

ajouter() {
  # ajouter <cle> <libelle> <statut> <detail> <que_faire>
  CLES+=("$1"); LIBELLES+=("$2"); STATUTS+=("$3"); DETAILS+=("$4"); QUEFAIRE+=("$5")
}

titre() { printf '\n%s=== %s%s\n' "$C_TITRE" "$1" "$C_OFF"; }
ligne() { printf '    %s%s%s\n' "$C_GRIS" "$1" "$C_OFF"; }

# Les outils de developpement Apple sont-ils installes ?
#
# PIEGE macOS, et il est bloquant : sur un Mac sans ces outils, /usr/bin/python3
# et /usr/bin/git ne sont pas des programmes mais des amorces. Les executer
# ouvre une FENETRE MODALE Apple ("The python3 command requires the command line
# developer tools"), que 2>/dev/null ne masque pas. Un diagnostic annonce comme
# silencieux se mettrait a reclamer une installation de 1 Go.
CLT_PRESENTS=0
xcode-select -p >/dev/null 2>&1 && CLT_PRESENTS=1

est_amorce_clt() {
  # est_amorce_clt <chemin_resolu> -> 0 si c'est une amorce Apple non utilisable
  case "$1" in
    /usr/bin/*) [ "$CLT_PRESENTS" -eq 0 ] && return 0 ;;
  esac
  return 1
}

# Sonde une commande : elle doit exister ET repondre, sans ouvrir de fenetre.
version_outil() {
  # version_outil <commande> [argument]
  local cmd="$1"; local arg="${2:---version}"; local chemin out
  chemin="$(command -v "$cmd" 2>/dev/null)" || return 1
  [ -n "$chemin" ] || return 1
  est_amorce_clt "$chemin" && return 1
  out=$("$cmd" "$arg" 2>/dev/null | head -n 1)
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

cd "$(dirname "$0")" 2>/dev/null || true
DOSSIER="$(pwd)"

printf '%s\n' "Diagnostic du poste - journee Agile en Seine du 22/09/2026"
printf '%s\n' "Lecture seule : rien n'est installe, rien n'est modifie."

# ===========================================================================
# 1. Systeme
# ===========================================================================
titre "Systeme"

OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo '')"
OS_MAJEUR="$(printf '%s' "$OS_VERSION" | cut -d. -f1)"
PUCE="$(uname -m 2>/dev/null || echo inconnue)"

if [ -z "$OS_VERSION" ]; then
  ajouter "OS" "Version de macOS" "INCONNU" "non lisible" \
    "Signaler : le script n'a pas pu lire la version du systeme."
elif [ "$OS_MAJEUR" -ge "$SEUIL_MACOS_MAJEUR" ] 2>/dev/null; then
  ajouter "OS" "Version de macOS" "OK" "macOS $OS_VERSION ($PUCE)" ""
  ligne "macOS $OS_VERSION - $PUCE"
else
  ajouter "OS" "Version de macOS" "BLOQUANT" "macOS $OS_VERSION (14 minimum)" \
    "L'espace de travail Cowork exige macOS 14 (Sonoma) au minimum. Claude Desktop s'installe sur des versions anterieures, mais Cowork n'y fonctionne pas - et c'est Cowork qu'on utilise toute la journee. Mettre a jour macOS, ou signaler le poste pour etre appaire en binome."
  ligne "macOS $OS_VERSION - INSUFFISANT (14 minimum)"
fi

# Puce : Apple Silicon et Intel sont tous deux supportes par Cowork
# (documentation officielle). Sur Intel, la machine virtuelle est simplement
# plus lourde. On informe, on ne bloque pas.
# Statut INFO, volontairement : un Mac Intel est SUPPORTE. Le classer en ALERTE
# ferait basculer tout le verdict en ORANGE pour un poste parfaitement prepare,
# et afficherait "des points restent a traiter" sans aucun point a traiter.
if [ "$PUCE" = "x86_64" ]; then
  ajouter "PUCE" "Processeur" "INFO" "Intel ($PUCE) - supporte, mais plus lent" ""
else
  ajouter "PUCE" "Processeur" "OK" "Apple Silicon ($PUCE)" ""
fi

# --- Memoire ---------------------------------------------------------------
RAM_OCTETS="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
if [ "$RAM_OCTETS" -gt 0 ] 2>/dev/null; then
  RAM_GO=$(( RAM_OCTETS / 1073741824 ))
  if [ "$RAM_GO" -ge "$SEUIL_RAM_GO" ]; then
    ajouter "RAM" "Memoire vive" "OK" "${RAM_GO} Go" ""
  else
    ajouter "RAM" "Memoire vive" "BLOQUANT" "${RAM_GO} Go" \
      "${SEUIL_RAM_GO} Go minimum. Ce poste ne pourra pas faire tourner l'espace de travail : prevoir un binome."
  fi
  ligne "Memoire : ${RAM_GO} Go"
else
  ajouter "RAM" "Memoire vive" "INCONNU" "non lisible" ""
fi

# --- Disque ----------------------------------------------------------------
DISQUE_KO="$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${DISQUE_KO:-}" ]; then
  DISQUE_GO=$(( DISQUE_KO / 1048576 ))
  if [ "$DISQUE_GO" -ge "$SEUIL_DISQUE_GO" ]; then
    ajouter "DISQUE" "Espace disque libre" "OK" "${DISQUE_GO} Go" ""
  else
    ajouter "DISQUE" "Espace disque libre" "BLOQUANT" "${DISQUE_GO} Go" \
      "${SEUIL_DISQUE_GO} Go libres minimum. Faire de la place avant le 22/09."
  fi
  ligne "Disque libre : ${DISQUE_GO} Go"
else
  ajouter "DISQUE" "Espace disque libre" "INCONNU" "non lisible" ""
fi

# --- Virtualisation --------------------------------------------------------
# Sur Apple Silicon le support est natif et systematique. Sur Intel,
# kern.hv_support dit si le materiel l'autorise.
titre "Virtualisation"
HV="$(sysctl -n kern.hv_support 2>/dev/null || echo '')"
if [ "$HV" = "1" ]; then
  ajouter "VIRT" "Virtualisation materielle" "OK" "supportee" ""
  ligne "Supportee."
elif [ "$HV" = "0" ]; then
  ajouter "VIRT" "Virtualisation materielle" "BLOQUANT" "non supportee par ce materiel" \
    "Ce Mac ne peut pas faire tourner l'espace de travail. Il faudra un binome avec un poste conforme."
  ligne "Non supportee."
else
  ajouter "VIRT" "Virtualisation materielle" "INCONNU" "non lisible" \
    "Non mesurable ici. Utiliser l'outil officiel 'Cowork readiness check' - voir le guide."
fi

# ===========================================================================
# 2. Claude Desktop
# ===========================================================================
titre "Claude Desktop"

CLAUDE_APP=""
for chemin in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
  if [ -d "$chemin" ]; then CLAUDE_APP="$chemin"; break; fi
done

if [ -n "$CLAUDE_APP" ]; then
  VERSION_CLAUDE="$(defaults read "$CLAUDE_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?')"
  ajouter "CLAUDE" "Claude Desktop" "OK" "$CLAUDE_APP (version $VERSION_CLAUDE)" ""
  ligne "$CLAUDE_APP - version $VERSION_CLAUDE"
else
  ajouter "CLAUDE" "Claude Desktop" "BLOQUANT" "absent" \
    "Installer depuis claude.com/download (le fichier .dmg), puis glisser Claude dans Applications. Un compte payant est necessaire."
  ligne "Absent."
fi

if CLI="$(version_outil claude)"; then
  ajouter "CLI" "Claude Code (ligne de commande)" "OK" "$CLI" ""
else
  ajouter "CLI" "Claude Code (ligne de commande)" "ALERTE" "absent ou non visible" \
    "Facultatif pour la journee. Si vous venez de l'installer, fermez et rouvrez le Terminal."
fi

# ===========================================================================
# 3. Outils
# ===========================================================================
titre "Outils"

# --- Node ------------------------------------------------------------------
if NODE="$(version_outil node)"; then
  NODE_MAJEUR="$(printf '%s' "$NODE" | sed -n 's/^v\{0,1\}\([0-9][0-9]*\)\..*/\1/p')"
  NODE_MAJEUR="${NODE_MAJEUR:-0}"
  if [ "$NODE_MAJEUR" -ge "$NODE_MAJEUR_CIBLE" ]; then
    ajouter "NODE" "Node.js" "OK" "$NODE" ""
  elif [ "$NODE_MAJEUR" -ge "$NODE_MAJEUR_MIN" ]; then
    ajouter "NODE" "Node.js" "ALERTE" "$NODE (cible : ${NODE_MAJEUR_CIBLE} LTS)" \
      "Version utilisable mais en dessous de la cible. Installer Node ${NODE_MAJEUR_CIBLE} LTS si possible."
  else
    ajouter "NODE" "Node.js" "BLOQUANT" "$NODE (trop ancienne)" \
      "Installer Node ${NODE_MAJEUR_CIBLE} LTS depuis nodejs.org."
  fi
else
  # Piege connu : 'brew install node@24' installe une formule keg-only, qui
  # n'est PAS reliee au PATH. Node est alors present sur le disque et
  # introuvable a la commande. On le dit, plutot que de conclure a une absence.
  INDICE_KEGONLY=""
  for prefixe in /opt/homebrew /usr/local; do
    if [ -d "$prefixe/opt/node@${NODE_MAJEUR_CIBLE}/bin" ]; then
      INDICE_KEGONLY="$prefixe/opt/node@${NODE_MAJEUR_CIBLE}/bin"
      break
    fi
  done
  if [ -n "$INDICE_KEGONLY" ]; then
    ajouter "NODE" "Node.js" "BLOQUANT" "installe mais pas dans le PATH ($INDICE_KEGONLY)" \
      "Node ${NODE_MAJEUR_CIBLE} est installe par Homebrew en version 'keg-only' : il existe, mais aucune commande ne le trouve. Executer : brew link --overwrite --force node@${NODE_MAJEUR_CIBLE} - puis fermer et rouvrir le Terminal."
  else
    ajouter "NODE" "Node.js" "BLOQUANT" "absent" \
      "Installer Node ${NODE_MAJEUR_CIBLE} LTS depuis nodejs.org. Attention : prendre la 24, pas la plus recente affichee."
  fi
fi

# --- Python ----------------------------------------------------------------
# Sur macOS la commande est python3 ; 'python' seul n'existe plus.
#
# Deux pieges cumules :
#   - /usr/bin/python3 livre par Apple est en 3.9.6, sous le seuil de 3.10 ;
#   - Homebrew installe python@3.13 sous le nom python3.13, qui n'est pas
#     forcement ce que 'python3' resout selon l'ordre du PATH.
# On essaie donc les noms versionnes d'abord, du plus recent au plus ancien,
# et 'python3' seulement en dernier recours.
PY=""
for candidat in python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
  if PY="$(version_outil "$candidat")"; then
    [ -n "$PY" ] && break
  fi
  PY=""
done
if [ -n "$PY" ]; then
  PY_MINEUR="$(printf '%s' "$PY" | sed -n 's/^Python 3\.\([0-9][0-9]*\).*/\1/p')"
  PY_MINEUR="${PY_MINEUR:--1}"
  if [ "$PY_MINEUR" -ge 10 ] 2>/dev/null; then
    ajouter "PY" "Python" "OK" "$PY" ""
  else
    ajouter "PY" "Python" "BLOQUANT" "$PY (3.10 minimum)" \
      "Installer Python 3.10 ou plus depuis python.org."
  fi
elif [ "$CLT_PRESENTS" -eq 0 ]; then
  ajouter "PY" "Python" "BLOQUANT" "absent (outils de developpement Apple absents)" \
    "Installer Python 3.10+ depuis python.org. Le python3 fourni par Apple ne convient pas : il est en 3.9."
else
  ajouter "PY" "Python" "BLOQUANT" "absent, ou uniquement en version 3.9" \
    "Installer Python 3.10+ depuis python.org, ou via Homebrew : brew install python@3.13"
fi

# --- Git -------------------------------------------------------------------
# Prudence : sur un Mac sans outils de developpement, taper 'git' ouvre une
# fenetre d'installation. On verifie donc d'abord que les outils sont la.
if xcode-select -p >/dev/null 2>&1 || [ -x /opt/homebrew/bin/git ] || [ -x /usr/local/bin/git ]; then
  if GIT="$(version_outil git)"; then
    ajouter "GIT" "Git" "OK" "$GIT" ""
  else
    ajouter "GIT" "Git" "ALERTE" "present mais sans reponse" \
      "Facultatif. Sans Git, Claude utilise un autre outil interne."
  fi
else
  ajouter "GIT" "Git" "ALERTE" "outils de developpement absents" \
    "Facultatif. Pour l'installer : ouvrir le Terminal et taper xcode-select --install (une fenetre Apple s'ouvre)."
fi

# --- Chrome ----------------------------------------------------------------
CHROME_APP=""
for chemin in "/Applications/Google Chrome.app" "$HOME/Applications/Google Chrome.app"; do
  if [ -d "$chemin" ]; then CHROME_APP="$chemin"; break; fi
done

if [ -n "$CHROME_APP" ]; then
  VERSION_CHROME="$(defaults read "$CHROME_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo '?')"
  ajouter "CHROME" "Google Chrome" "OK" "version $VERSION_CHROME" ""
else
  ajouter "CHROME" "Google Chrome" "BLOQUANT" "absent" \
    "Chrome est impose : l'extension de verification visuelle n'existe que la. Installer depuis google.com/chrome."
fi

# --- Extension Claude pour Chrome ------------------------------------------
# Detection au mieux : indice, pas preuve. Le test visuel en fin de script
# est la seule verification qui tranche.
EXT_TROUVEE=0
PROFILS_LUS=0
CHROME_DATA="$HOME/Library/Application Support/Google/Chrome"
if [ -d "$CHROME_DATA" ]; then
  for profil in "$CHROME_DATA"/Default "$CHROME_DATA"/Profile*; do
    [ -d "$profil" ] || continue
    PROFILS_LUS=$(( PROFILS_LUS + 1 ))
    [ -d "$profil/Extensions" ] || continue
    if grep -ril --include='manifest.json' --include='messages.json' \
        'claude' "$profil/Extensions" >/dev/null 2>&1; then
      EXT_TROUVEE=1
      break
    fi
  done
fi

if [ "$EXT_TROUVEE" -eq 1 ]; then
  ajouter "EXT" "Extension Claude pour Chrome" "OK" "detectee ($PROFILS_LUS profil(s) lu(s))" \
    "Presence detectee. Son REGLAGE reste a verifier a la main - voir le test visuel en fin de script."
elif [ -n "$CHROME_APP" ]; then
  ajouter "EXT" "Extension Claude pour Chrome" "ALERTE" "non detectee ($PROFILS_LUS profil(s) lu(s))" \
    "Installer l'extension Claude depuis le Chrome Web Store, puis activer 'Autoriser l'acces aux URL de fichier'. La detection automatique est imparfaite : si vous savez l'avoir installee, faites le test visuel en fin de script."
else
  ajouter "EXT" "Extension Claude pour Chrome" "ALERTE" "Chrome absent" "Installer Chrome d'abord."
fi

# --- Obsidian --------------------------------------------------------------
OBS_APP=""
for chemin in "/Applications/Obsidian.app" "$HOME/Applications/Obsidian.app"; do
  if [ -d "$chemin" ]; then OBS_APP="$chemin"; break; fi
done

if [ -n "$OBS_APP" ]; then
  ajouter "OBS" "Obsidian" "OK" "$OBS_APP" ""
else
  ajouter "OBS" "Obsidian" "ALERTE" "absent" \
    "Installer depuis obsidian.md. Sans lui, vous ne verrez pas l'arborescence de votre travail."
fi

# ===========================================================================
# 4. Le tableau
# ===========================================================================
titre "Resultat"
printf '\n'
printf '  %-34s %-9s %s\n' "Controle" "Statut" "Detail"
printf '  %-34s %-9s %s\n' "----------------------------------" "---------" "------"

NB=${#CLES[@]}
i=0
while [ "$i" -lt "$NB" ]; do
  detail="${DETAILS[$i]}"
  if [ ${#detail} -gt 58 ]; then detail="$(printf '%.55s' "$detail")..."; fi
  case "${STATUTS[$i]}" in
    OK)       couleur="$C_OK" ;;
    INFO)     couleur="$C_GRIS" ;;
    ALERTE)   couleur="$C_WARN" ;;
    BLOQUANT) couleur="$C_KO" ;;
    *)        couleur="$C_GRIS" ;;
  esac
  printf '  %-34s %s%-9s%s %s\n' "${LIBELLES[$i]}" "$couleur" "${STATUTS[$i]}" "$C_OFF" "$detail"
  i=$(( i + 1 ))
done

NB_BLOQUANTS=0; NB_ALERTES=0; NB_INCONNUS=0
i=0
while [ "$i" -lt "$NB" ]; do
  case "${STATUTS[$i]}" in
    BLOQUANT) NB_BLOQUANTS=$(( NB_BLOQUANTS + 1 )) ;;
    ALERTE)   NB_ALERTES=$(( NB_ALERTES + 1 )) ;;
    INCONNU)  NB_INCONNUS=$(( NB_INCONNUS + 1 )) ;;
  esac
  i=$(( i + 1 ))
done

if [ "$NB_BLOQUANTS" -gt 0 ]; then
  VERDICT="ROUGE"
  printf '\n%sVERDICT : ROUGE - en l etat, ce poste ne peut pas faire la journee.%s\n' "$C_KO" "$C_OFF"
elif [ "$NB_ALERTES" -gt 0 ] || [ "$NB_INCONNUS" -gt 0 ]; then
  VERDICT="ORANGE"
  printf '\n%sVERDICT : ORANGE - utilisable, mais des points restent a traiter.%s\n' "$C_WARN" "$C_OFF"
else
  VERDICT="VERT"
  printf '\n%sVERDICT : VERT - ce poste peut faire la journee.%s\n' "$C_OK" "$C_OFF"
fi

# --- Ce qu'il reste a faire ------------------------------------------------
if [ "$NB_BLOQUANTS" -gt 0 ] || [ "$NB_ALERTES" -gt 0 ]; then
  titre "Ce qu il reste a faire"
  rang=0
  for cible in BLOQUANT ALERTE; do
    i=0
    while [ "$i" -lt "$NB" ]; do
      if [ "${STATUTS[$i]}" = "$cible" ] && [ -n "${QUEFAIRE[$i]}" ]; then
        rang=$(( rang + 1 ))
        if [ "$cible" = "BLOQUANT" ]; then
          printf '  %s%d. [BLOQUANT] %s%s\n' "$C_KO" "$rang" "${LIBELLES[$i]}" "$C_OFF"
        else
          printf '  %s%d. [a traiter] %s%s\n' "$C_WARN" "$rang" "${LIBELLES[$i]}" "$C_OFF"
        fi
        printf '     %s%s%s\n' "$C_GRIS" "${QUEFAIRE[$i]}" "$C_OFF"
      fi
      i=$(( i + 1 ))
    done
  done
fi

# ===========================================================================
# 5. Ce que ce script ne peut PAS verifier
# ===========================================================================
titre "Les deux points que ce script ne peut pas verifier"

TEST_HTML="$DOSSIER/test-vision.html"
TEST_ECRIT=0
if cat > "$TEST_HTML" <<HTML 2>/dev/null
<!doctype html>
<html lang="fr">
<head><meta charset="utf-8"><title>Test de vision - AES 2026</title></head>
<body style="font-family:system-ui,sans-serif;background:#101418;color:#f2f4f7;
             display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
  <div style="text-align:center">
    <p style="font-size:14px;letter-spacing:.14em;text-transform:uppercase;color:#9aa4b2;margin:0 0 12px">
      Mot de controle
    </p>
    <p style="font-size:44px;font-weight:700;margin:0;color:#ffd479">$MOT_TEST</p>
  </div>
</body>
</html>
HTML
then TEST_ECRIT=1; fi

printf '\n  1. L autorisation "Autoriser l acces aux URL de fichier" de l extension Chrome\n'
printf '     %sElle n est pas lisible depuis un script. Sans elle, Claude ne voit jamais vos%s\n' "$C_GRIS" "$C_OFF"
printf '     %secrans - et il ne dit pas pourquoi.%s\n\n' "$C_GRIS" "$C_OFF"
if [ "$TEST_ECRIT" -eq 1 ]; then
  printf '     TEST (1 minute) :\n'
  printf '       %sa. Ouvrir CHROME d abord, puis FAIRE GLISSER ce fichier sur la fenetre :%s\n' "$C_GRIS" "$C_OFF"
  printf '          %s%s%s\n' "$C_GRIS" "$TEST_HTML" "$C_OFF"
  printf '          %s(un double-clic l ouvrirait dans votre navigateur par defaut, qui%s\n' "$C_GRIS" "$C_OFF"
  printf '           %sn est peut-etre pas Chrome - le test conclurait faux)%s\n' "$C_GRIS" "$C_OFF"
  printf '       %sb. Cliquer sur l extension Claude, et taper exactement :%s\n' "$C_GRIS" "$C_OFF"
  printf '            %sQuel mot est affiche sur cette page ?%s\n' "$C_TITRE" "$C_OFF"
  printf '       %sc. Reponse attendue : %s%s\n' "$C_GRIS" "$MOT_TEST" "$C_OFF"
  printf '       %sd. Toute autre reponse = l autorisation manque. Voir le guide, section 3.%s\n' "$C_GRIS" "$C_OFF"
else
  printf '     %s(le fichier de test n a pas pu etre ecrit dans %s)%s\n' "$C_WARN" "$DOSSIER" "$C_OFF"
fi
printf '\n  2. Le reglage Obsidian "Detecter toutes les extensions de fichier"\n'
printf '     %sReglages > Fichiers et liens > Detecter toutes les extensions de fichier.%s\n' "$C_GRIS" "$C_OFF"
printf '     %sSans lui, les fichiers HTML que vous produirez seront invisibles dans la liste.%s\n' "$C_GRIS" "$C_OFF"

# ===========================================================================
# 6. La ligne de resultat
# ===========================================================================
CODES=""
i=0
while [ "$i" -lt "$NB" ]; do
  case "${STATUTS[$i]}" in
    OK)       abrege="OK" ;;
    INFO)     abrege="--" ;;
    ALERTE)   abrege="!!" ;;
    BLOQUANT) abrege="KO" ;;
    *)        abrege="??" ;;
  esac
  CODES="$CODES ${CLES[$i]}:$abrege"
  i=$(( i + 1 ))
done
CODES="$(printf '%s' "$CODES" | sed 's/^ //')"

HORODATAGE="$(date '+%Y-%m-%d %H:%M')"
ETIQ_OS="macOS ${OS_VERSION:-inconnue} $PUCE"
LIGNE="AES2026 | $ETIQ_OS | ${USER:-utilisateur} | $HORODATAGE | VERDICT:$VERDICT | $CODES"

titre "A renvoyer par mail - copier la ligne ci-dessous"
printf '\n%s%s%s\n\n' "$C_TITRE" "$LIGNE" "$C_OFF"

# ===========================================================================
# 7. Le fichier rapport
# ===========================================================================
RAPPORT="$DOSSIER/Diagnostic-${USER:-poste}-$(date '+%Y%m%d-%H%M').txt"
{
  printf '%s\n' "Diagnostic du poste - journee Agile en Seine du 22/09/2026"
  printf '%s\n\n' "Genere le $HORODATAGE sur $(hostname 2>/dev/null || echo '?') par ${USER:-?}"
  printf '%s\n\n' "$LIGNE"
  printf '%s\n' "Detail complet :"
  i=0
  while [ "$i" -lt "$NB" ]; do
    printf '  [%s] %s - %s\n' "${STATUTS[$i]}" "${LIBELLES[$i]}" "${DETAILS[$i]}"
    if [ -n "${QUEFAIRE[$i]}" ]; then printf '      -> %s\n' "${QUEFAIRE[$i]}"; fi
    i=$(( i + 1 ))
  done
  printf '\n%s\n' "Non verifiable par script : autorisation 'acces aux URL de fichier' de"
  printf '%s\n' "l extension Chrome, et reglage Obsidian 'detecter toutes les extensions'."
} > "$RAPPORT" 2>/dev/null && ligne "Rapport ecrit : $RAPPORT"

printf '\n%sRenvoyez la ligne de resultat, meme si elle est ROUGE.%s\n' "$C_TITRE" "$C_OFF"
printf '%sUn poste rouge signale a l avance se traite ; un poste rouge decouvert%s\n' "$C_GRIS" "$C_OFF"
printf '%sle 22 au matin coute la matinee.%s\n' "$C_GRIS" "$C_OFF"
printf '%sVous pouvez aussi joindre le fichier rapport plutot que de recopier la ligne.%s\n\n' "$C_GRIS" "$C_OFF"

# Pause volontaire. Le Terminal de macOS peut etre regle sur "Fermer si le shell
# s est termine normalement" : sans ce read, la fenetre disparaitrait pile dans
# le cas VERT, en emportant la ligne de resultat - la seule chose qu'on demande.
printf '%sAppuyez sur Entree pour fermer cette fenetre.%s ' "$C_TITRE" "$C_OFF"
read -r _ 2>/dev/null || true
printf '\n'

case "$VERDICT" in
  VERT)   exit 0 ;;
  ORANGE) exit 1 ;;
  *)      exit 2 ;;
esac
