#!/bin/bash
# ===========================================================================
#  Preparer un Mac pour la journee Agile en Seine du 22/09/2026
#
#  Pendant macOS du script Setup-ClaudeWorkstation.ps1 (Windows).
#  Meme principe : idempotent (une etape deja satisfaite est ignoree) et
#  non bloquant (une etape en echec est enregistree, le script continue).
#
#  Ce script INSTALLE des logiciels. Il vous demandera votre mot de passe
#  au moins une fois - c'est Homebrew et l'installation d'applications qui
#  l'exigent, pas le script.
#
#  Double-cliquez sur ce fichier. Si macOS refuse de l'ouvrir, voir le guide,
#  section "Premier lancement sur Mac".
#
#  Ecrit pour bash 3.2, la version livree avec macOS.
# ===========================================================================

set -u

NODE_FORMULE="node@24"        # Node 24 est la ligne LTS active au 22/09/2026
SEUIL_MACOS_COWORK=14         # macOS 14 Sonoma - exigence de l'espace de travail

SANS_BREW=0
SANS_CLAUDE=0
# Garde volontaire : avec `set -u`, le bash 3.2 de macOS traite "$@" comme une
# variable non definie quand le script est lance sans argument - ce qui est le
# cas du double-clic, donc du cas nominal.
[ "$#" -eq 0 ] && set -- --aucun-argument
for arg in "$@"; do
  case "$arg" in
    --aucun-argument) : ;;
    --sans-brew)   SANS_BREW=1 ;;
    --sans-claude) SANS_CLAUDE=1 ;;
    -h|--help|help)
      cat <<'AIDE'
setup-claude-workstation.command - prepare un Mac pour la journee du 22/09/2026.

USAGE
    ./setup-claude-workstation.command [options]

OPTIONS
    --sans-brew     N'installe pas Homebrew s'il manque (les etapes qui en
                    dependent sont alors marquees ACTION MANUELLE).
    --sans-claude   N'installe pas Claude Desktop ni Claude Code.
    --help          Affiche cette aide.

CE QUI EST INSTALLE
    Homebrew (si absent) - node@24 - python3 - git
    Google Chrome - Obsidian - Claude Desktop - Claude Code (facultatif)

CE QUI NE PEUT PAS ETRE INSTALLE PAR UN SCRIPT
    L'extension Claude pour Chrome, et son reglage "Autoriser l'acces aux
    URL de fichier". Ces deux gestes sont manuels : voir le guide, section 3.

APRES EXECUTION
    Fermer et rouvrir le Terminal, puis lancer diagnostic-poste.command.
AIDE
      exit 0 ;;
  esac
done

if [ -t 1 ]; then
  C_TITRE=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'
  C_KO=$'\033[31m';    C_GRIS=$'\033[90m'; C_OFF=$'\033[0m'
else
  C_TITRE=""; C_OK=""; C_WARN=""; C_KO=""; C_GRIS=""; C_OFF=""
fi

# Les outils de developpement Apple sont-ils installes ?
#
# PIEGE macOS bloquant : sans eux, /usr/bin/python3 et /usr/bin/git ne sont pas des
# programmes mais des amorces. Les executer ouvre une FENETRE MODALE Apple que
# 2>/dev/null ne masque pas, en plein milieu de l'installation. Meme garde que dans
# diagnostic-poste.command.
CLT_PRESENTS=0
xcode-select -p >/dev/null 2>&1 && CLT_PRESENTS=1

commande_sondable() {
  # commande_sondable <nom> -> 0 si on peut l'executer sans ouvrir de fenetre
  local chemin
  chemin="$(command -v "$1" 2>/dev/null)" || return 1
  [ -n "$chemin" ] || return 1
  case "$chemin" in
    /usr/bin/*) [ "$CLT_PRESENTS" -eq 0 ] && return 1 ;;
  esac
  return 0
}

ETAPES=(); RESULTATS=(); NOTES=()

resultat() { ETAPES+=("$1"); RESULTATS+=("$2"); NOTES+=("$3"); }
titre()    { printf '\n%s=== %s%s\n' "$C_TITRE" "$1" "$C_OFF"; }
info()     { printf '    %s%s%s\n' "$C_GRIS" "$1" "$C_OFF"; }
ok()       { printf '    %sOK   %s%s\n' "$C_OK" "$1" "$C_OFF"; }
attention(){ printf '    %s!    %s%s\n' "$C_WARN" "$1" "$C_OFF"; }
erreur()   { printf '    %sX    %s%s\n' "$C_KO" "$1" "$C_OFF"; }

cd "$(dirname "$0")" 2>/dev/null || true

# ===========================================================================
# 0. Preflight
# ===========================================================================
titre "Preflight"

if [ "$(uname -s)" != "Darwin" ]; then
  erreur "Ce script est pour macOS. Sur Windows, utiliser Setup-ClaudeWorkstation.ps1."
  exit 1
fi

OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo '')"
OS_MAJEUR="$(printf '%s' "$OS_VERSION" | cut -d. -f1)"
PUCE="$(uname -m)"

info "macOS $OS_VERSION - $PUCE - utilisateur ${USER:-?}"

if [ "${OS_MAJEUR:-0}" -lt "$SEUIL_MACOS_COWORK" ] 2>/dev/null; then
  attention "macOS $OS_VERSION : l'espace de travail Cowork exige macOS $SEUIL_MACOS_COWORK (Sonoma)."
  info "Les outils s'installeront, mais la journee ne pourra pas se faire sur ce poste."
  info "Signalez-le : un binome avec un poste conforme sera prevu."
fi

if [ "$PUCE" = "arm64" ]; then BREW_PREFIXE="/opt/homebrew"; else BREW_PREFIXE="/usr/local"; fi

# ===========================================================================
# 1. Homebrew
# ===========================================================================
titre "Homebrew"

# Inscrit brew dans le profil du shell. A appeler des que brew est resolu, y
# compris quand il etait DEJA installe mais absent du PATH : sinon le Terminal
# rouvert a l'etape suivante ne trouve ni brew ni node, et le diagnostic
# conclut a tort que rien n'est installe.
inscrire_brew_au_profil() {
  [ -x "$BREW_PREFIXE/bin/brew" ] || return 0
  local ecrit=0
  for profil in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    [ -e "$profil" ] || continue
    if ! grep -q 'brew shellenv' "$profil" 2>/dev/null; then
      printf '\neval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIXE" >> "$profil"
      info "ligne ajoutee a $profil"
    fi
    ecrit=1
  done
  if [ "$ecrit" -eq 0 ]; then
    printf 'eval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIXE" > "$HOME/.zprofile"
    info "profil cree : $HOME/.zprofile"
  fi
}

charger_brew() {
  if command -v brew >/dev/null 2>&1; then return 0; fi
  if [ -x "$BREW_PREFIXE/bin/brew" ]; then
    eval "$("$BREW_PREFIXE/bin/brew" shellenv)"
    # Present sur le disque mais absent du PATH : c'est precisement le cas
    # qu'il faut reparer durablement, pas seulement pour cette session.
    inscrire_brew_au_profil
    return 0
  fi
  return 1
}

if charger_brew; then
  ok "deja present : $(brew --version 2>/dev/null | head -n 1)"
  resultat "Homebrew" "OK" "deja present"
elif [ "$SANS_BREW" -eq 1 ]; then
  attention "absent, et --sans-brew est actif : aucune tentative."
  resultat "Homebrew" "ACTION MANUELLE" "--sans-brew"
else
  info "Homebrew est le gestionnaire de logiciels utilise ici. Tout le reste en depend."
  info "Son installation demande votre mot de passe et prend quelques minutes."
  attention "Une fenetre Apple peut s'ouvrir pour installer les outils de developpement."
  info "C'est normal : accepter, et compter une dizaine de minutes de plus."
  printf '    Installer Homebrew maintenant ? [O/n] (Entree = oui) '
  read -r reponse
  case "${reponse:-o}" in
    o|O|oui|OUI|y|Y|yes)
      # On telecharge dans un fichier AVANT d'executer, au lieu de
      # `bash -c "$(curl ...)"`. Raison : si curl echoue (reseau, proxy), la
      # substitution rend une chaine vide, `bash -c ""` sort en 0, et le script
      # conclurait a une installation reussie sans que rien ne se soit passe.
      INSTALLEUR="$(mktemp -t brew-install)" || INSTALLEUR=""
      TELECHARGE=0
      if [ -n "$INSTALLEUR" ] && curl -fsSL -o "$INSTALLEUR" \
           https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh; then
        if [ -s "$INSTALLEUR" ]; then TELECHARGE=1; fi
      fi

      if [ "$TELECHARGE" -eq 0 ]; then
        erreur "le programme d'installation de Homebrew n'a pas pu etre telecharge"
        info "verifier la connexion reseau, puis relancer ce script"
        resultat "Homebrew" "ECHEC" "telechargement impossible"
      elif /bin/bash "$INSTALLEUR"; then
        # On ne se fie PAS au code de retour seul : on reverifie que la commande
        # existe reellement avant d'annoncer une reussite.
        if charger_brew; then
          ok "installe : $(brew --version 2>/dev/null | head -n 1)"
          resultat "Homebrew" "OK" "installe"
        else
          erreur "installation terminee, mais la commande 'brew' reste introuvable"
          resultat "Homebrew" "ECHEC" "brew introuvable apres installation"
        fi
      else
        erreur "l'installation de Homebrew a echoue"
        resultat "Homebrew" "ECHEC" "voir la sortie ci-dessus"
      fi
      [ -n "$INSTALLEUR" ] && rm -f "$INSTALLEUR"
      ;;
    *)
      attention "installation refusee - AUCUN outil ne sera installe par ce script."
      info "Vous pourrez tout installer a la main : voir le guide, section 2."
      resultat "Homebrew" "ACTION MANUELLE" "refuse - rien n'a ete installe"
      ;;
  esac
fi

BREW_DISPO=0
command -v brew >/dev/null 2>&1 && BREW_DISPO=1

# ---------------------------------------------------------------------------
# Installe une formule ou un cask, en verifiant d'abord ce qui est deja la.
# ---------------------------------------------------------------------------
installer_brew() {
  # installer_brew <libelle> <formule|cask> <nom> <sonde_commande_ou_chemin>
  local libelle="$1" genre="$2" nom="$3" sonde="$4"

  titre "$libelle"

  # Deja present ?
  if [ -n "$sonde" ]; then
    if [ "${sonde:0:1}" = "/" ]; then
      if [ -e "$sonde" ]; then
        ok "deja present : $sonde"; resultat "$libelle" "OK" "deja present"; return
      fi
    elif command -v "$sonde" >/dev/null 2>&1; then
      ok "deja present : $("$sonde" --version 2>/dev/null | head -n 1)"
      resultat "$libelle" "OK" "deja present"; return
    fi
  fi

  if [ "$BREW_DISPO" -eq 0 ]; then
    attention "Homebrew indisponible : installation impossible."
    resultat "$libelle" "ACTION MANUELLE" "Homebrew absent - installation a faire a la main"
    return
  fi

  if [ "$genre" = "cask" ]; then
    info "brew install --cask $nom"
    if brew install --cask "$nom"; then
      # On re-sonde : brew peut rendre 0 sans que la cible soit joignable.
      if [ -n "$sonde" ] && [ "${sonde:0:1}" != "/" ] && ! command -v "$sonde" >/dev/null 2>&1; then
        attention "installe, mais la commande '$sonde' reste introuvable"
        resultat "$libelle" "ACTION MANUELLE" "installe - commande introuvable, rouvrir le Terminal"
      elif [ -n "$sonde" ] && [ "${sonde:0:1}" = "/" ] && [ ! -e "$sonde" ]; then
        attention "brew a rendu 0 mais $sonde n'existe pas"
        resultat "$libelle" "ECHEC" "installation sans effet"
      else
        ok "installe"; resultat "$libelle" "OK" "installe"
      fi
    else
      erreur "echec de l'installation"
      resultat "$libelle" "ECHEC" "brew install --cask $nom"
    fi
  else
    info "brew install $nom"
    if brew install "$nom"; then
      ok "installe"; resultat "$libelle" "OK" "installe"
    else
      erreur "echec de l'installation"
      resultat "$libelle" "ECHEC" "brew install $nom"
    fi
  fi
}

# ===========================================================================
# 2. Node.js 24
#
#    node@24 est une formule "keg-only" : Homebrew l'installe sans la relier
#    au PATH, parce que c'est une version alternative de la formule 'node'.
#    Resultat sans l'etape de liaison : Node est sur le disque et la commande
#    'node' reste introuvable. C'est le piege macOS equivalent a la case
#    "Add python.exe to PATH" sur Windows.
# ===========================================================================
titre "Node.js ($NODE_FORMULE)"

NODE_ACTUEL=""
command -v node >/dev/null 2>&1 && NODE_ACTUEL="$(node --version 2>/dev/null)"
NODE_MAJEUR="$(printf '%s' "$NODE_ACTUEL" | sed -n 's/^v\{0,1\}\([0-9][0-9]*\)\..*/\1/p')"
NODE_MAJEUR="${NODE_MAJEUR:-0}"

if [ "$NODE_MAJEUR" -ge 24 ] 2>/dev/null; then
  ok "deja present : $NODE_ACTUEL"
  resultat "Node.js" "OK" "deja present : $NODE_ACTUEL"
elif [ "$BREW_DISPO" -eq 0 ]; then
  attention "Homebrew indisponible."
  resultat "Node.js" "ACTION MANUELLE" "installer Node 24 LTS depuis nodejs.org"
else
  info "brew install $NODE_FORMULE"
  if brew install "$NODE_FORMULE"; then
    # Etape de liaison, sans laquelle rien ne trouve node.
    info "brew link --overwrite --force $NODE_FORMULE  (formule keg-only)"
    brew link --overwrite --force "$NODE_FORMULE" >/dev/null 2>&1 || true
    hash -r 2>/dev/null || true

    # On revalide la MAJEURE, pas la seule presence : un Node plus ancien place
    # avant Homebrew dans le PATH ferait afficher "OK v20" apres avoir installe la 24.
    NODE_APRES=""
    command -v node >/dev/null 2>&1 && NODE_APRES="$(node --version 2>/dev/null)"
    NODE_MAJ_APRES="$(printf '%s' "$NODE_APRES" | sed -n 's/^v\{0,1\}\([0-9][0-9]*\)\..*/\1/p')"
    if [ "${NODE_MAJ_APRES:-0}" -ge 24 ] 2>/dev/null; then
      ok "$NODE_APRES"
      resultat "Node.js" "OK" "$NODE_APRES"
    elif [ -n "$NODE_APRES" ]; then
      attention "node repond en $NODE_APRES : une version plus ancienne masque la 24"
      info "un autre Node precede Homebrew dans le PATH. A corriger a la main :"
      info "    brew link --overwrite --force $NODE_FORMULE"
      resultat "Node.js" "ACTION MANUELLE" "$NODE_APRES masque node@24"
    else
      # Surtout PAS "OK" ici : une formule keg-only non reliee est exactement le
      # piege que cette etape existe pour eviter. L'annoncer OK le rendrait
      # invisible jusqu'au 22 au matin.
      attention "installe, mais la commande 'node' reste introuvable"
      info "la liaison au PATH a echoue. A rejouer a la main :"
      info "    brew link --overwrite --force $NODE_FORMULE"
      resultat "Node.js" "ACTION MANUELLE" "keg-only non relie - rejouer brew link"
    fi
  else
    erreur "echec de l'installation"
    resultat "Node.js" "ECHEC" "brew install $NODE_FORMULE"
  fi
fi

# ===========================================================================
# 3. Python et Git
# ===========================================================================
# PIEGE macOS, et il fait echouer toute l'etape en silence : /usr/bin/python3
# EXISTE toujours sur macOS recent. Sonder la simple presence de la commande
# ferait donc conclure "deja present" a tous les coups, python@3.13 ne serait
# jamais installe, et le diagnostic classerait ensuite le poste ROUGE parce que
# le python3 d'Apple est en 3.9. On sonde la VERSION, pas la presence.
titre "Python"

PY_OK=0
for candidat in python3.14 python3.13 python3.12 python3.11 python3.10; do
  if commande_sondable "$candidat"; then
    ok "deja present : $("$candidat" --version 2>/dev/null)"
    resultat "Python" "OK" "deja present : $candidat"
    PY_OK=1
    break
  fi
done

if [ "$PY_OK" -eq 0 ] && commande_sondable python3; then
  PY_V="$(python3 --version 2>/dev/null)"
  PY_MIN="$(printf '%s' "$PY_V" | sed -n 's/^Python 3\.\([0-9][0-9]*\).*/\1/p')"
  if [ "${PY_MIN:-0}" -ge 10 ] 2>/dev/null; then
    ok "deja present : $PY_V"
    resultat "Python" "OK" "deja present : $PY_V"
    PY_OK=1
  else
    info "python3 present mais en $PY_V - sous le seuil de 3.10, on installe"
  fi
fi

if [ "$PY_OK" -eq 0 ]; then
  if [ "$BREW_DISPO" -eq 0 ]; then
    attention "Homebrew indisponible : installation impossible."
    resultat "Python" "ACTION MANUELLE" "installer Python 3.10+ depuis python.org"
  else
    info "brew install python@3.13"
    if brew install python@3.13; then
      # Meme piege que node@24 : la formule versionnee est keg-only des qu'elle
      # n'est plus la version par defaut. Sans liaison, python3.13 reste
      # introuvable apres reouverture du Terminal et le diagnostic dira BLOQUANT.
      info "brew link --overwrite --force python@3.13  (formule potentiellement keg-only)"
      brew link --overwrite --force python@3.13 >/dev/null 2>&1 || true
      hash -r 2>/dev/null || true
      if command -v python3.13 >/dev/null 2>&1; then
        ok "$(python3.13 --version)"
        resultat "Python" "OK" "$(python3.13 --version)"
      else
        # Surtout PAS "OK" : un Python installe et introuvable est exactement le
        # defaut que cette etape existe pour eviter.
        attention "installe, mais la commande python3.13 reste introuvable"
        info "la liaison au PATH a echoue. A rejouer a la main :"
        info "    brew link --overwrite --force python@3.13"
        resultat "Python" "ACTION MANUELLE" "keg-only non relie - rejouer brew link"
      fi
    else
      erreur "echec de l'installation"
      resultat "Python" "ECHEC" "brew install python@3.13"
    fi
  fi
fi

# Git est fourni par les outils de developpement Apple sur la plupart des Mac.
titre "Git"
if commande_sondable git && git --version >/dev/null 2>&1; then
  ok "deja present : $(git --version)"
  resultat "Git" "OK" "deja present"
elif xcode-select -p >/dev/null 2>&1; then
  attention "outils Apple presents mais git ne repond pas"
  resultat "Git" "ACTION MANUELLE" "verifier a la main"
elif [ "$BREW_DISPO" -eq 1 ]; then
  info "brew install git"
  if brew install git; then
    ok "installe"; resultat "Git" "OK" "installe"
  else
    erreur "echec"; resultat "Git" "ECHEC" "brew install git"
  fi
else
  attention "absent. Facultatif pour la journee."
  resultat "Git" "ACTION MANUELLE" "xcode-select --install"
fi

# ===========================================================================
# 4. Applications
# ===========================================================================
installer_brew "Google Chrome" "cask" "google-chrome" "/Applications/Google Chrome.app"
installer_brew "Obsidian"      "cask" "obsidian"      "/Applications/Obsidian.app"

if [ "$SANS_CLAUDE" -eq 1 ]; then
  titre "Claude Desktop"
  attention "--sans-claude actif : aucune tentative."
  resultat "Claude Desktop" "ACTION MANUELLE" "--sans-claude"
else
  installer_brew "Claude Desktop" "cask" "claude"      "/Applications/Claude.app"
  installer_brew "Claude Code"    "cask" "claude-code" "claude"
fi

# ===========================================================================
# 5. Bilan
# ===========================================================================
titre "Bilan"
printf '\n'
printf '  %-20s %-18s %s\n' "Etape" "Statut" "Detail"
printf '  %-20s %-18s %s\n' "--------------------" "------------------" "------"

NB=${#ETAPES[@]}
ECHECS=0
MANUELLES=0
i=0
while [ "$i" -lt "$NB" ]; do
  case "${RESULTATS[$i]}" in
    OK)     couleur="$C_OK" ;;
    ECHEC)  couleur="$C_KO"; ECHECS=$(( ECHECS + 1 )) ;;
    *)      couleur="$C_WARN"; MANUELLES=$(( MANUELLES + 1 )) ;;
  esac
  printf '  %-20s %s%-18s%s %s\n' "${ETAPES[$i]}" "$couleur" "${RESULTATS[$i]}" "$C_OFF" "${NOTES[$i]}"
  i=$(( i + 1 ))
done

# ===========================================================================
# 6. Ce qui reste manuel - et qui n'est pas optionnel
# ===========================================================================
titre "Deux gestes qu'aucun script ne peut faire a votre place"
printf '\n'
printf '  1. %sInstaller l extension Claude pour Chrome%s\n' "$C_TITRE" "$C_OFF"
printf '     %sChrome Web Store, rechercher "Claude", installer.%s\n' "$C_GRIS" "$C_OFF"
printf '\n'
printf '  2. %sActiver "Autoriser l acces aux URL de fichier"%s\n' "$C_TITRE" "$C_OFF"
printf '     %sChrome > menu Extensions (piece de puzzle) > Claude > ... >%s\n' "$C_GRIS" "$C_OFF"
printf '     %sGerer l extension > faire defiler jusqu au reglage.%s\n' "$C_GRIS" "$C_OFF"
printf '     %sSans lui, Claude ne verra jamais vos ecrans - et ne dira pas pourquoi.%s\n' "$C_GRIS" "$C_OFF"
printf '\n'
printf '  3. %sRegler Obsidian%s\n' "$C_TITRE" "$C_OFF"
printf '     %sReglages > Fichiers et liens > Detecter toutes les extensions de fichier.%s\n' "$C_GRIS" "$C_OFF"
printf '     %sSans lui, les fichiers HTML que vous produirez seront invisibles dans la liste.%s\n' "$C_GRIS" "$C_OFF"

titre "Etape suivante"
printf '\n'
printf '  1. %sFermer et rouvrir le Terminal%s (les changements de PATH ne s appliquent\n' "$C_TITRE" "$C_OFF"
printf '     pas aux fenetres deja ouvertes).\n'
printf '  2. Lancer %sdiagnostic-poste.command%s et renvoyer la ligne de resultat.\n' "$C_TITRE" "$C_OFF"
printf '\n'

if [ "$ECHECS" -gt 0 ]; then
  attention "$ECHECS etape(s) en echec - le diagnostic dira ce qui manque encore."
fi
if [ "$MANUELLES" -gt 0 ]; then
  attention "$MANUELLES etape(s) NON FAITES, a reprendre a la main (colonne Statut ci-dessus)."
  info "Ne les ignorez pas : le diagnostic les comptera comme manquantes."
fi

# Pause volontaire : le Terminal peut etre regle sur "Fermer si le shell s est
# termine normalement", et la fenetre disparaitrait avec le bilan.
printf '\n%sAppuyez sur Entree pour fermer cette fenetre.%s ' "$C_TITRE" "$C_OFF"
read -r _ 2>/dev/null || true
printf '\n'

[ "$ECHECS" -gt 0 ] && exit 1
exit 0
