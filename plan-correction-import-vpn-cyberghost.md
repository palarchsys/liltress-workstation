# Plan de correction — import OpenVPN CyberGhost

Dépôt cible : https://github.com/palarchsys/liltress-workstation/
Constat fait sur l'installation `/opt/liltress-workstation` le 2026-11-14, avec l'archive `/home/pal/cyg_skudp.zip`.
Ce plan se limite au code du projet. Il ne contient aucun secret de l'archive.

## Constat

L'archive actuelle est conforme au contrat de la marque `cyberghost`.

Rejeu de `install_vpn_bundle openvpn cyberghost` en mode stage, sans publication et sans tunnel, sur le zip et sur le dossier `/home/pal/cyg_skudp` : code de retour 0. Le stage contient `openvpn.ovpn`, `ca.crt`, `client.crt`, `client.key`, `auth.txt`, `runtime` et `meta` avec `brand=cyberghost`.

Contrôles faits sur le contenu, sans recopier les secrets :

- Zip valide, 5 fichiers, un seul dossier racine `cyg_skudp/`. Aucun lien, aucun chemin `..`, aucun fichier au-dessus de 1 Mo.
- Noms attendus par `service/vpn/brands/cyberghost.sh` : `openvpn.ovpn`, `ca.crt`, `client.crt`, `client.key`, `auth.txt`.
- `auth.txt` a deux lignes non vides. Le mot `REPLACE` est absent.
- `ca.crt` et `client.crt` sont des PEM. `openssl verify -CAfile ca.crt client.crt` répond `OK`. La clé `BEGIN PRIVATE KEY` (4096 bits, non chiffrée) correspond au certificat client.
- `openvpn.ovpn` cite `ca ca.crt`, `cert client.crt`, `key client.key`, `auth-user-pass` sans chemin, `proto udp`, `remote <hôte> 443`.
- Le nom `87-1-kr.cg-dialup.net` se résout par le résolveur local `127.0.0.1:53`. Plusieurs adresses UDP/443 répondent à un hard-reset OpenVPN.

Aucune chaîne du catalogue ne dit « l'archive n'est pas conforme ». Les messages vagues les plus proches sont :

- `vpn.test.fail` : « Le profil {1} n'est pas valide. »
- `vpn.import.shape` : « Le dossier {1} n'a pas les fichiers de cette marque. »
- `vpn.profile.invalid` : « Le profil {1} est invalide. »

`log_error` ajoute ensuite le bandeau `log.installation-could-not-finish` (« Installation n'a pas pu se terminer »), même quand la commande est `liltress vpn import`.

## Cause

`service/vpn/up.sh` lance OpenVPN sans `--cd` vers le dossier du profil. Les chemins écrits dans `runtime` sont relatifs (`ca ca.crt`, `cert client.crt`, `key client.key`, `auth-user-pass auth.txt`). OpenVPN 2.7.7 les résout depuis le répertoire courant du processus, pas depuis le dossier du fichier de config.

Rejeu du `runtime` produit par l'importeur :

- Sans `--cd`, depuis un autre répertoire : arrêt immédiat. `Options error` sur `ca.crt`, `client.crt`, `client.key` et `auth.txt` (`No such file or directory`).
- Avec `--cd` sur le dossier du profil, et avec les mêmes filtres que le produit (`--route-nopull`, `--route-noexec`, `--pull-filter ignore "dhcp-option DNS"`, `--pull-filter ignore redirect-gateway`) : le TLS aboutit, le certificat serveur est accepté, le serveur envoie `PUSH_REPLY` (l'authentification est donc acceptée). Le seul arrêt observé est `Cannot ioctl TUNSETIFF ... Operation not permitted`, parce que cet essai n'était pas root.

`apply_vpn_profile` envoie la sortie d'OpenVPN vers `/dev/null`. En cas d'échec, `finish_vpn_import` supprime le dossier du profil, donc `openvpn.log`, puis `run_vpn_test` affiche seulement `vpn.test.fail`. `AUTH_FAILED` est détecté dans `check_vpn_handshake` (code 2) puis ramené au même message.

Un import lancé par `sudo ./liltress vpn import` a pour répertoire courant le répertoire de l'utilisateur, pas `/opt/liltress-workstation/vpn/openvpn/<nom>/`. L'archive conforme est donc refusée après l'essai, sans le motif OpenVPN.

Les tests de `script/test/suites/10_vpn.sh` s'arrêtent à `VPN_IMPORT_STAGE_ONLY=1`. Ils ne lancent pas OpenVPN et ne voient pas l'absence de `--cd`.

## Ce qui n'est pas la cause

- Le dossier unique `cyg_skudp/` dans le zip. `open_vpn_bundle` l'accepte. L'essai `cg-wrap` de `10_vpn.sh` couvre déjà ce cas. La doc `doc/*/vpn.md` dit encore « Les fichiers sont à la racine. Il n'y a pas de sous-dossier. » Le message `vpn.import.zipdir` dit la même chose pour plusieurs fautes différentes (deux dossiers, fichier en trop à côté du dossier, collision de nom).
- `ca.crt` est en CRLF. OpenSSL et OpenVPN l'acceptent.
- L'importeur épingle une seule adresse A dans `runtime` et garde les autres dans `meta.endpoint4`. L'adresse épinglée lors du rejeu a mené le TLS jusqu'au `PUSH_REPLY`. Ce point reste un risque pour un nom CyberGhost à plusieurs adresses, pas le refus actuel.
- `persist-key` est ignoré par OpenVPN 2.7 (avertissement). Le serveur pousse aussi `route-ipv6 2000::/3`, ce qui journalise `Options error: option 'route-ipv6' cannot be used in this context ([PUSH-OPTIONS])` sans arrêter le processus avant l'ouverture du tun.

## Correctif

### 1. Lancer OpenVPN depuis le dossier du profil

Fichier : `service/vpn/up.sh`.

Dans `apply_vpn_profile` et dans `apply_vpn_probe`, ajouter `--cd` avec le dossier qui contient `runtime`, avant `--config`. Les deux appels sont les seuls `openvpn` du dépôt.

Le dossier est `$(get_vpn_profile_dir "${name}")`. Les fichiers `ca.crt`, `client.crt`, `client.key` et `auth.txt` y sont déjà copiés par `install_vpn_openvpn`.

Ne pas réécrire les chemins en absolus dans `runtime` : un profil déplacé ou restauré doit continuer à être autonome. `--cd` garde les noms relatifs.

### 2. Montrer le motif OpenVPN avant de supprimer le profil

Fichiers : `service/vpn/up.sh`, `service/vpn/import.sh`, `locale/{fr,en,de,es}/vpn.txt`.

- Si `openvpn` quitte tout de suite, lire `openvpn.log` ou `probe.log` avant tout `rm`.
- Publier une ligne courte, sans secret et sans chemin de clé : la première ligne utile parmi `Options error`, `AUTH_FAILED`, `TLS Error`, `VERIFY ERROR`, `Cannot ioctl TUNSETIFF`.
- Clés proposées :
  - `vpn.test.fail` reste le cas sans ligne exploitable : « Le profil {1} n'est pas valide. »
  - `vpn.test.fail-reason` : « Le profil {1} n'est pas valide : {2}. »
  - `vpn.import.auth-failed` : « Le serveur a refusé l'identifiant de {1}. »
- `check_vpn_handshake` retourne déjà 2 sur `AUTH_FAILED`. `run_vpn_test` doit utiliser `vpn.import.auth-failed` dans ce cas, pas `vpn.test.fail`.
- `finish_vpn_import` ne supprime le dossier qu'après l'émission du message.

`liltress vpn import` ne doit pas appeler `log_error` pour un échec de profil. `log_error` termine le processus et affiche « Installation n'a pas pu se terminer ». Ajouter un affichage d'erreur de commande qui écrit le message et retourne 1, sans le bandeau d'installation. Réserver `log_error` à l'installeur.

### 3. Filtrer `route-ipv6`

Fichier : `service/vpn/up.sh`, les deux lancements.

Ajouter `--pull-filter ignore route-ipv6` à côté du filtre `redirect-gateway`. Le poste bloque déjà l'IPv6 globale quand `has_ipv6=0`. La ligne poussée par CyberGhost ne doit plus produire un `Options error` dans le journal.

### 4. Aligner la doc et le message `zipdir`

Fichiers : `doc/fr/vpn.md`, `doc/en/vpn.md`, `doc/de/vpn.md`, `doc/es/vpn.md`, `locale/*/vpn.txt`.

- Écrire qu'un seul dossier en tête d'archive est accepté, et que `auth.txt` peut être à côté de ce dossier. C'est le comportement de `open_vpn_bundle`.
- Remplacer le texte unique de `vpn.import.zipdir` par trois motifs déjà distingués dans le code : plusieurs dossiers, fichier autre que `auth.txt` à côté du dossier, collision de nom. Ne plus dire « les fichiers doivent être à la racine » pour ces trois cas.

### 5. Tests

Fichier : `script/test/suites/10_vpn.sh`.

- `vpn.cd` : `apply_vpn_profile` et `apply_vpn_probe` contiennent `--cd`.
- `vpn.pull-filter` : les deux lancements contiennent `route-ipv6`.
- `vpn.fail-reason` : un faux `openvpn.log` contenant `Options error: --ca fails with 'ca.crt'` produit `vpn.test.fail-reason` et le nom `ca.crt`, sans chemin absolu.
- `vpn.auth-failed` : un journal contenant `AUTH_FAILED` produit `vpn.import.auth-failed`.
- Garder `cg-wrap` : un zip à un seul dossier reste accepté.
- Vérifier qu'un échec de `vpn import` n'émet pas la clé `log.installation-could-not-finish`.

Lancer `bash script/test/run.sh`. Le banc actuel n'a pas besoin de root. Il ne doit pas ajouter de `FAIL`.

## Vérification root du 2026-11-14

`sudo` demande encore un mot de passe dans cette session. L'élévation a été faite par `systemd-run --uid=0`, acceptée par polkit.

État du poste avant l'essai :

- `/opt/liltress-workstation/vpn/vpn.json` : `mode` off, `active` vide, `profiles` vide.
- `/opt/liltress-workstation/vpn/openvpn` et `wireguard` sont vides. Aucun import précédent.
- Le journal d'installation ne contient pas `vpn.import`, `cyberghost` ni `openvpn`.
- La table `nft` `inet w_vpn` est absente. La route par défaut est `192.168.122.1` par `enp1s0`.

Rejeu des drapeaux de `apply_vpn_profile`, avec `runtime` construit comme l'importeur, puis arrêt du processus :

- Sans `--cd`, répertoire courant `/var/tmp` : OpenVPN s'arrête sur `Options error` pour `ca.crt`, `client.crt`, `client.key` et `auth.txt`.
- Avec `--cd` sur le dossier du profil : `Peer Connection Initiated`, puis `Initialization Sequence Completed`. La ligne poussée `route-ipv6` journalise encore `Options error: option 'route-ipv6' cannot be used in this context ([PUSH-OPTIONS])` et n'empêche pas cette ligne de succès.

Après l'arrêt : l'interface `tun-verify` est absente, la route par défaut est inchangée, la table `inet w_vpn` est absente, le dossier extrait est supprimé. L'import `liltress vpn import` n'a pas été lancé, donc le killswitch n'a pas été armé.

## Vérification avec root, après le correctif

Le tunnel aboutit dès que le client est lancé depuis le dossier du profil. Il reste à refaire l'import par la commande du produit une fois `--cd` ajouté.

Après le correctif, sur la machine, avec root :

```bash
cd /tmp
sudo /opt/liltress-workstation/liltress vpn import openvpn cyberghost cg-essai /home/pal/cyg_skudp.zip
```

Le répertoire courant `/tmp` est voulu : c'est lui qui révélait les chemins relatifs.

Attendu :

- pas de bandeau « Installation n'a pas pu se terminer » ;
- soit « Le profil cg-essai est valide. », soit une ligne qui cite le motif OpenVPN ;
- en cas de succès, `openvpn.log` contient `Initialization Sequence Completed` ;
- en cas d'échec, le journal n'est pas effacé avant l'affichage du motif.

Puis retirer le profil d'essai pour ne pas laisser le tunnel en place :

```bash
sudo /opt/liltress-workstation/liltress vpn mode off
sudo /opt/liltress-workstation/liltress vpn rm cg-essai
```

Ne pas copier `auth.txt`, `client.key` ni les certificats dans le dépôt, dans le message de commit, ni dans ce plan.

## Hors de ce correctif

- Réécrire toutes les adresses A/AAAA du nom CyberGhost en lignes `remote`, au lieu d'épingler la première. Le pare-feu connaît déjà la liste via `endpoint4`. À traiter seulement si un essai root montre un serveur muet alors qu'une autre adresse répond.
- Retirer `persist-key` du `runtime` pour faire taire l'avertissement OpenVPN 2.7. Cosmétique.
- Normaliser les CRLF des PEM à l'import. OpenVPN a accepté `ca.crt` en CRLF.
