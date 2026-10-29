# claude-easy-setup

Installation simplifiée de Claude, automatisée par scripts pour Windows 11+ et macOS 14+ (Sonoma).

Ce dépôt contient deux kits (un par système), un guide pour demander l'installation à un administrateur, et une procédure d'installation manuelle pour les cas où les scripts ne passent pas.

## Sommaire

- [Quel kit choisir ?](#quel-kit-choisir-)
- [Kit-Windows : installation automatisée et diagnostic](#kit-windows--installation-automatisée-et-diagnostic)
- [Kit-macOS : installation automatisée et diagnostic](#kit-macos--installation-automatisée-et-diagnostic)
- [Demande à l'administrateur](#demande-à-ladministrateur)
- [Installation manuelle pas à pas (Windows)](#installation-manuelle-pas-à-pas-windows)
- [Ce que les scripts ne peuvent pas faire](#ce-que-les-scripts-ne-peuvent-pas-faire)
- [Publier une release (mainteneurs)](#publier-une-release-mainteneurs)

## Quel kit choisir ?

| Situation | À utiliser |
|---|---|
| Poste Windows, installation automatique | [`Kit-Windows`](Kit-Windows) |
| Poste Mac, installation automatique | [`Kit-macOS`](Kit-macOS) |
| Poste Windows verrouillé, il faut passer par le support informatique | [`Comment Installer claude ticket admin.txt`](Comment%20Installer%20claude%20ticket%20admin.txt) |
| Les scripts échouent, ou vous voulez comprendre chaque étape | [`Installation manuelle.txt`](Installation%20manuelle.txt) |

**Dans tous les cas : dézippez le dossier avant de lancer quoi que ce soit.** Lancé depuis l'intérieur d'un `.zip`, un script ne voit pas ses voisins et échoue.

Chaque kit suit le même principe : **installer**, puis **diagnostiquer**. Le diagnostic est en lecture seule : il n'installe rien, ne modifie rien et ne demande aucun mot de passe.

---

## Kit-Windows : installation automatisée et diagnostic

Prépare un poste **Windows 11** (le script accepte aussi Windows 10 build 19041 ou supérieur) pour Claude.

| Fichier | Rôle |
|---|---|
| `Installer.cmd` | Lanceur à double-cliquer. Appelle `Setup-ClaudeWorkstation.ps1` en contournant la politique d'exécution PowerShell, pour cette exécution seulement. |
| `Setup-ClaudeWorkstation.ps1` | Installe Node.js LTS, Python, Git, GitHub CLI et Claude Code. |
| `Diagnostic.cmd` | Lanceur à double-cliquer pour le diagnostic. |
| `Diagnostic-poste.ps1` | Contrôle le poste et rend un verdict. |
| `test-vision.html` | Page de test de l'extension Chrome (voir [plus bas](#ce-que-les-scripts-ne-peuvent-pas-faire)). |
| `LISEZ-MOI.txt` | Guide rapide du kit. |

### Marche à suivre

1. **Double-cliquer sur `Installer.cmd`.** Windows demande des autorisations (UAC) : acceptez-les.
2. **Installer à la main**, s'ils ne sont pas déjà là : [Google Chrome](https://www.google.com/chrome/) et [Obsidian](https://obsidian.md).
3. **Installer Claude Desktop à la main** depuis <https://claude.com/download>.
   > Ne passez **pas** par winget : le paquet winget s'installe sans les droits nécessaires et l'espace de travail ne fonctionne pas.
4. **Installer l'extension Claude pour Chrome**, puis activer « Autoriser l'accès aux URL de fichier » dans ses paramètres. Ce réglage échoue en silence.
5. **Fermer toutes les fenêtres** et en rouvrir une neuve : les changements de PATH ne s'appliquent pas aux fenêtres déjà ouvertes.
6. **Double-cliquer sur `Diagnostic.cmd`**, puis renvoyer la ligne de résultat (ou le fichier rapport), même si le verdict est ROUGE.

Si Windows affiche « Windows a protégé votre ordinateur » : *Informations complémentaires* → *Exécuter quand même*.

### Ce que fait l'installation

Le script est **idempotent** (une étape déjà satisfaite est ignorée) et **non bloquant** (une étape en échec est notée, les suivantes continuent). Le bilan final liste ce qui est OK et ce qui ne l'est pas. Il se lance dans une session PowerShell **non administrateur**.

| Paquet | Portée | Droits admin |
|---|---|---|
| Claude Code CLI (`%USERPROFILE%\.local\bin`), PATH utilisateur | Profil utilisateur | Non |
| Git | Choisie par winget | Non |
| Python | Profil courant (`%LOCALAPPDATA%\Programs\Python`) | Non |
| Node.js LTS, GitHub CLI | Machine | **Oui** (invite UAC) |

Options, si vous lancez le script directement :

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-ClaudeWorkstation.ps1 [options]
```

| Option | Effet |
|---|---|
| `--help`, `-h`, `/?` | Affiche l'aide et quitte. |
| `-UserScopeOnly` | Ignore les paquets qui exigent l'administrateur (Node.js, GitHub CLI) : aucune invite UAC, ils sont marqués « ACTION MANUELLE ». |
| `-CliViaWinget` | Installe Claude Code via winget au lieu du script officiel `install.ps1`. |
| `-PythonPackageId` | Force l'identifiant winget de Python (ex. `Python.Python.3.13`). Par défaut, la dernière version stable est retenue. |

### Ce que contrôle le diagnostic

`Diagnostic-poste.ps1` vérifie le système (build Windows, RAM d'au moins 7,5 Go (un poste « 8 Go » en affiche un peu moins), 10 Go de disque libre), Claude Desktop et la forme sous laquelle il est installé, puis les outils dont le kit se sert (Node.js, Git, etc.). Il produit trois choses :

1. un tableau lisible à l'écran ;
2. une **ligne de résultat** à renvoyer, avec le verdict **VERT** (le poste est prêt), **ORANGE** (utilisable, des points restent à traiter) ou **ROUGE** (le poste n'est pas prêt) ;
3. un fichier rapport `Diagnostic-<utilisateur>-<date>.txt` déposé à côté du script (option `-NoFile` pour s'en passer).

---

## Kit-macOS : installation automatisée et diagnostic

Prépare un Mac sous **macOS 14 (Sonoma) ou plus récent**, Intel ou Apple Silicon. macOS 14 est le minimum exigé par l'espace de travail Cowork ; les Mac Intel sont supportés, simplement plus lents.

| Fichier | Rôle |
|---|---|
| `setup-claude-workstation.command` | Installe Homebrew, Node 24, Python, Git, Chrome, Obsidian, Claude Desktop et Claude Code. |
| `diagnostic-poste.command` | Contrôle le poste et rend un verdict (lecture seule). |
| `LISEZ-MOI.txt` | Guide rapide du kit. |

### Premier lancement : macOS bloque les fichiers `.command` téléchargés

C'est normal, ce n'est pas le signe d'un problème.

- **macOS 14 (Sonoma)** : clic droit sur le fichier → *Ouvrir* → *Ouvrir*.
- **macOS 15 et plus** : double-clic (macOS refuse), puis *Réglages Système* → *Confidentialité et sécurité* → *Ouvrir quand même*.

Si les fichiers refusent toujours de s'ouvrir, passez par le Terminal :

```bash
cd ~/Downloads/Kit-macOS
chmod +x *.command
./diagnostic-poste.command
```

### Marche à suivre

1. **Lancer `setup-claude-workstation.command`.** Votre mot de passe sera demandé : c'est Homebrew qui l'exige.
2. **Installer l'extension Claude pour Chrome**, puis activer « Autoriser l'accès aux URL de fichier » dans ses paramètres. Ce réglage échoue en silence.
3. **Fermer le Terminal** et en rouvrir un neuf.
4. **Lancer `diagnostic-poste.command`**, puis renvoyer la ligne de résultat (ou le fichier rapport), même si le verdict est ROUGE.

Comme sur Windows, l'installation est idempotente et non bloquante, et le diagnostic rend un verdict VERT, ORANGE ou ROUGE.

Options du script d'installation :

```bash
./setup-claude-workstation.command [options]
```

| Option | Effet |
|---|---|
| `--sans-brew` | N'installe pas Homebrew s'il manque (les étapes qui en dépendent sont marquées « ACTION MANUELLE »). |
| `--sans-claude` | N'installe ni Claude Desktop ni Claude Code. |
| `--help` | Affiche l'aide. |

---

## Demande à l'administrateur

[`Comment Installer claude ticket admin.txt`](Comment%20Installer%20claude%20ticket%20admin.txt) est un **modèle de ticket** à copier dans l'outil de ticketing du support informatique, pour les postes Windows où l'utilisateur n'a pas la main sur tous les réglages.

Il demande à l'administrateur de :

1. **Activer les paramètres Windows avancés** : chemins longs dans l'Explorateur de fichiers, PowerShell comme terminal par défaut, mode développeur (*Système → Avancé*).
2. **Lancer l'installation automatisée** : double-clic sur `Installer.cmd` (Node, Python, Git, GitHub CLI, Claude Code), puis installation manuelle de Chrome, d'Obsidian et de Claude Desktop (sans winget), puis de l'extension Chrome avec « Autoriser l'accès aux URL de fichier ».
3. **Fermer toutes les fenêtres**, en rouvrir une neuve, lancer `Diagnostic.cmd` et **renvoyer la ligne de résultat** ou le fichier rapport, même si le verdict est ROUGE.

---

## Installation manuelle pas à pas (Windows)

[`Installation manuelle.txt`](Installation%20manuelle.txt) décrit, commande par commande, ce que font les scripts. Utile si l'automatisation échoue ou pour comprendre ce qui est installé.

1. **Activer les paramètres Windows avancés** (*Système → Avancé*) : chemins longs, terminal PowerShell, mode développeur. Puis **redémarrer** l'ordinateur.
2. **Ouvrir `cmd` sans les droits administrateur**, et vérifier que winget est disponible :
   ```bat
   winget --version
   where.exe winget
   ```
3. **Installer Node.js LTS, GitHub CLI et Git** :
   ```bat
   winget install -e --id OpenJS.NodeJS.LTS
   winget install --id GitHub.cli
   winget install --id Git.Git -e --source winget
   ```
4. **Vérifier les installations** :
   ```bat
   node --version
   npm --version
   gh --version
   ```
5. **Installer Claude Desktop** avec les droits administrateur depuis <https://claude.com/download>, puis **Claude Code CLI** :
   ```powershell
   irm https://claude.ai/install.ps1 | iex
   ```
6. **Ajouter `~/.local/bin` au PATH utilisateur** de façon permanente :
   ```powershell
   $dir  = Join-Path $env:USERPROFILE ".local\bin"
   $user = [Environment]::GetEnvironmentVariable("Path", "User")
   if ($user -split ';' -notcontains $dir) {
       [Environment]::SetEnvironmentVariable("Path", ($user.TrimEnd(';') + ";$dir"), "User")
   }
   ```
7. **Fermer puis rouvrir le terminal** (le PATH ne s'applique pas aux fenêtres déjà ouvertes), et vérifier :
   ```bat
   claude --version
   ```

---

## Ce que les scripts ne peuvent pas faire

Deux réglages échouent **en silence** et ne sont pas lisibles depuis un script. Le diagnostic le dit explicitement plutôt que de faire semblant.

1. **L'autorisation « Autoriser l'accès aux URL de fichier »** de l'extension Claude pour Chrome. Sans elle, Claude ne voit jamais vos écrans, et il ne dit pas pourquoi. Pour la tester :
   1. Ouvrir **Chrome d'abord**, puis **faire glisser** `test-vision.html` sur la fenêtre (un double-clic l'ouvrirait peut-être dans un autre navigateur).
   2. Cliquer sur l'extension Claude et demander : `Quel mot est affiché sur cette page ?`
   3. La réponse attendue est `MARGUERITE-7431`. Toute autre réponse signifie que l'autorisation manque.
2. **Le réglage Obsidian « Détecter toutes les extensions de fichier »** (*Réglages → Fichiers et liens*). Sans lui, les fichiers HTML produits sont invisibles dans la liste.

Claude Desktop, Chrome, Obsidian et l'extension Chrome s'installent aussi à la main sous Windows, pour des raisons de droits administrateur.

---

## Publier une release (mainteneurs)

Les versions suivent [semver](https://semver.org/lang/fr/) (`MAJEUR.MINEUR.CORRECTIF`). La première est `1.0.0`.

Le script `Package-Release.ps1`, à la racine du dépôt, fabrique le zip de la release à partir du **dernier commit**, puis la publie sur GitHub avec [`gh`](https://cli.github.com/) si on le demande. Il n'est pas inclus dans le zip, pas plus que `.gitattributes`, `.gitignore`, `.claude` et `CLAUDE.md`.

1. **Commiter et pousser** les changements : seul ce qui est commité est packagé, et la publication exige que le commit soit déjà sur GitHub.
2. **Fabriquer le zip**, depuis PowerShell, à la racine du dépôt :
   ```powershell
   .\Package-Release.ps1 1.0.0
   ```
   Si l'exécution de scripts est bloquée :
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Package-Release.ps1 -Version 1.0.0
   ```
   Le zip est écrit dans `dist/claude-easy-setup-1.0.0.zip` (option `-OutDir` pour changer de dossier). Rien n'est publié à ce stade.
3. **Publier la release** en ajoutant `-Publish` :
   ```powershell
   .\Package-Release.ps1 1.0.0 -Publish
   ```
   Le script crée le tag `v1.0.0` sur le commit courant, joint le zip et génère les notes de release. Une version avec suffixe (`2.0.0-rc.1`) est publiée comme pré-release. Avec `-Publish -DryRun`, il fait toutes les vérifications et affiche la commande `gh` sans rien publier.

   Avant de fabriquer le zip, il vérifie que `gh` est installé et connecté (`gh auth login`), que l'arbre de travail est propre, que le commit est poussé et que la version n'existe pas déjà : une version publiée ne se réécrit pas.

`.\Package-Release.ps1 -Help` affiche l'aide complète du script.
