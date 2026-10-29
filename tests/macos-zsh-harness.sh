#!/bin/bash
# ===========================================================================
#  Banc d'essai des scripts macOS, execute SOUS ZSH dans WSL (Linux).
#  Lance par tests\Test-Kits.ps1 : ne pas l'executer sur un Mac.
#
#  Il n'y a pas de Mac ici : les commandes macOS (sw_vers, sysctl, defaults,
#  xcode-select, brew, uname) sont remplacees par de faux programmes, dans un
#  PATH isole et un faux HOME jetables. Rien n'est installe, rien n'est ecrit
#  hors du dossier temporaire.
#
#  Sortie lisible par machine, une ligne par fait :
#    SCEN|<scenario>|<code_sortie>|<octets_stderr>|<ligne de resultat ou vide>
#    LIGNE|<scenario>|<ligne du bilan>
# ===========================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../Kit-macOS"
ZSH="$(command -v zsh)" || { echo "ERREUR|zsh absent de WSL (sudo apt install zsh)"; exit 3; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stubs" "$T/tools" "$T/run"

# PATH isole : quelques utilitaires de base seulement. SANS node, python, git :
# le WSL a les siens, qui masqueraient les chemins "outil absent" et "a installer".
for t in chmod sed cut head grep dirname cat rm mktemp date hostname df awk tr env; do
  ln -s "$(command -v "$t")" "$T/tools/$t"
done
P="$T/stubs:$T/tools"

stub() { printf '#!/bin/sh\n%s\n' "$2" > "$T/stubs/$1"; chmod +x "$T/stubs/$1"; }
stub sw_vers      '[ "$1" = "-productVersion" ] && echo 14.5'
stub sysctl       'case "$2" in hw.memsize) echo "${FAKE_MEMSIZE:-17179869184}";; kern.hv_support) echo 1;; esac'
stub defaults     'echo 1.2.3'
stub xcode-select 'exit 0'
stub uname        'case "$1" in -s) echo Darwin;; -m) echo arm64;; esac'
stub claude       'echo 2.0.0'
stub node         'echo v24.1.0'
stub python3.13   'echo Python 3.13.1'
stub git          'echo git version 2.45.0'

# Faux Homebrew : "installe" node et python en creant leur commande.
cat > "$T/stubs/brew" <<'B'
#!/bin/sh
case "$1" in
  --version) echo "Homebrew 4.4.0";;
  install) case "$*" in
      *node@24*)     printf '#!/bin/sh\necho v24.1.0\n' > "$BREW_STUBS/node"; chmod +x "$BREW_STUBS/node";;
      *python@3.13*) printf '#!/bin/sh\necho Python 3.13.1\n' > "$BREW_STUBS/python3.13"; chmod +x "$BREW_STUBS/python3.13";;
    esac; exit 0;;
  link) exit 0;;
esac
B
chmod +x "$T/stubs/brew"

# mkhome <nom> <claude:0|1> <dossier_extension:Default|"Profile 1"|aucun>
mkhome() {
  local H="$T/$1" C
  mkdir -p "$H/Applications/Google Chrome.app" "$H/Applications/Obsidian.app"
  [ "$2" = 1 ] && mkdir -p "$H/Applications/Claude.app"
  C="$H/Library/Application Support/Google/Chrome"; mkdir -p "$C/Default"
  if [ "$3" != aucun ]; then
    mkdir -p "$C/$3/Extensions/abc/1.0"; echo '{"name":"Claude"}' > "$C/$3/Extensions/abc/1.0/manifest.json"
  fi
}

cp "$SRC/diagnostic-poste.command"       "$T/run/diag.command"
cp "$SRC/setup-claude-workstation.command" "$T/run/setup.command"
chmod +x "$T/run/diag.command" "$T/run/setup.command"

# diag <scenario> <home> <path> [memsize_octets]
diag() {
  local nom="$1" home="$2" path="$3" mem="${4:-17179869184}" code
  ( cd "$T/run" && printf '\n' | /usr/bin/env -i HOME="$home" PATH="$path" USER=testeur FAKE_MEMSIZE="$mem" "$ZSH" ./diag.command ) > "$T/o.txt" 2> "$T/e.txt"
  code=$?
  printf 'SCEN|%s|%s|%s|%s\n' "$nom" "$code" "$(wc -c < "$T/e.txt" | tr -d ' ')" "$(grep AES2026 "$T/o.txt" | sed 's/.*VERDICT/VERDICT/')"
}

# setup <scenario> <stdin> <path> [options...]
setup() {
  local nom="$1" entree="$2" path="$3" code; shift 3
  ( cd "$T/run" && printf "$entree" | /usr/bin/env -i HOME="$T/homeS" PATH="$path" USER=testeur BREW_STUBS="$T/stubs" "$ZSH" ./setup.command "$@" ) > "$T/o.txt" 2> "$T/e.txt"
  code=$?
  printf 'SCEN|%s|%s|%s|\n' "$nom" "$code" "$(wc -c < "$T/e.txt" | tr -d ' ')"
  sed -n '/Etape  /,/^$/p' "$T/o.txt" | grep -v '^$' | sed "s/^/LIGNE|$nom|/"
}

# ---- Diagnostic : seuil de RAM (7.5 Go) et cas limites ------------------------------
mkhome R 1 Default
diag ram_7_4   "$T/R" "$P" 7945689498     # 7.4 Go  -> BLOQUANT
diag ram_7_5   "$T/R" "$P" 8053063680     # 7.5 Go  -> OK (pile sur le seuil)
diag ram_8     "$T/R" "$P" 8589934592     # 8 Go    -> OK
diag ram_16    "$T/R" "$P" 17179869184    # 16 Go   -> OK

# ---- Diagnostic : parcours complets ---------------------------------------------------
diag tout_ok   "$T/R" "$P"

mkhome B 0 aucun
mkdir -p "$T/stubs-sans-node"; for s in "$T/stubs"/*; do [ "$(basename "$s")" != node ] && cp "$s" "$T/stubs-sans-node/"; done
diag sans_claude_ni_node "$T/B" "$T/stubs-sans-node:$T/tools"

mkhome C 1 "Profile 1"
diag extension_profile_1 "$T/C" "$P"       # glob Profile*(N) AVEC correspondance et un espace

# ---- Installation ----------------------------------------------------------------------
mkdir -p "$T/homeS"
setup aide  '\n' "$P" --help

rm -f "$T/stubs/node" "$T/stubs/python3.13"
setup installe_node_python  '\n'   "$P"       # brew "installe", puis la commande doit etre retrouvee

rm -f "$T/stubs/brew" "$T/stubs/node" "$T/stubs/python3.13"
setup refus_homebrew        'n\n\n' "$P"      # question [O/n], reponse n
