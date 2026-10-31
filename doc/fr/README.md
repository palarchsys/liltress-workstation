<div align="center">

# 🛡️ Liltress Workstation 🛡️

![Ubuntu 26.04 or newer](https://img.shields.io/badge/Ubuntu-26.04%2B-E95420?logo=ubuntu&logoColor=white)
![Workstation](https://img.shields.io/badge/profile-workstation-1f6feb)
![Unbound](https://img.shields.io/badge/DNS-Unbound-0055A4)
![UFW](https://img.shields.io/badge/firewall-UFW-0055A4)
![Security checks](https://img.shields.io/badge/checks-AIDE%20%C2%B7%20ClamAV%20%C2%B7%20Lynis-2ea44f)

Liltress Workstation prépare un poste Ubuntu 26.04 ou plus récent.<br/>
Il installe le résolveur DNS local, le pare-feu et les contrôles de sécurité.<br/>
Le compte Ubuntu déjà créé sur la machine n'est pas remplacé.<br/>
L'installeur ne crée pas un second compte.

</div>

## 📋 Avant de commencer

Trois points précèdent l'installation : le système, l'accès, et les besoins externes.

## ▪️ Système

Ubuntu 26.04 ou plus récent, version intermédiaire comprise.<br/>
Une installation neuve est préférable.<br/>
Utilisez une console locale ou la session graphique déjà ouverte.<br/>
La machine a besoin d'Internet.

## ▪️ Accès

Vous avez besoin de `sudo` pour `./liltress configure`, `./liltress run` et les contrôles.

## ▪️ Besoins externes

| Besoin                     | Lien et procédure                                                                                                                                                                                                                             |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Jeton Ubuntu Pro           | Obligatoire. Ouvrez [https://ubuntu.com/pro/dashboard](https://ubuntu.com/pro/dashboard) et copiez le jeton. `configure.sh` accepte seulement des lettres et des chiffres, longueur 6 à 100, sans espace.                                     |
| Mot de passe d'application | Demandé seulement si vous activez les alertes. Utilisez le mot de passe d'application du fournisseur de courrier. Ne saisissez jamais le mot de passe du compte. Longueur 8 à 128. Les espaces saisis sont retirés.                           |
| Serveur SMTP               | Demandé seulement si les alertes sont activées. Forme `hôte:port`. L'exemple de `configure.sh` est `smtp-mail.outlook.com:587`. Les crochets sont refusés. `swaks` envoie un message d'essai. La ligne de succès est `Essai d'envoi accepté.` |

## 📋 Installation

Le poste se prépare par l'installeur curl, ou par un clone suivi de `sudo ./liltress configure`.

## ▪️ Curl

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git swaks tar
curl -fsSL https://raw.githubusercontent.com/palarchsys/liltress-workstation/main/install.sh | sudo bash
```

## ▪️ Clone

```bash
git clone https://github.com/palarchsys/liltress-workstation
cd liltress-workstation
sudo ./liltress configure
```

## Action de configure.sh

`sudo ./liltress configure` pose les questions ci-dessous, écrit `global.conf` en mode `644` et `secrets.conf` en mode `600` en root, puis lance `script/run.sh`.<br/>
`secrets.conf` reste sur la machine. Ne le copiez pas dans un message, un ticket ou un dépôt.<br/>
La première question choisit la langue.<br/>
La valeur est `G_LANGUAGE`.<br/>
Le défaut est l'anglais.<br/>

| Question | Réponse attendue |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Jeton Ubuntu Pro | Lettres et chiffres, de 6 à 100, sans espace. Obligatoire. |
| Activer | `Y` ou `y` active le courrier. `N`, `n` ou `non` le coupe. Coupé, Postfix n'est pas installé. Toute autre réponse affiche `Répondez Y ou N.` |
| Serveur | `hôte:port`, par exemple `smtp-mail.outlook.com:587`. Sans crochets. Demandé seulement si les alertes sont activées. |
| Login | Une adresse e-mail. |
| Password | Le mot de passe d'application du fournisseur, de 8 à 128 caractères. Les espaces sont retirés. Les guillemets, `$`, `\` et l'apostrophe inverse sont refusés. Jamais le mot de passe du compte. |
| From | Une adresse e-mail. `G_WATCHDOG_MAIL` reçoit la même adresse. |
| Activer l'envoi des alertes vers Google Drive (Y/N). | `Y` ou `y` active la copie. `N`, `n` ou `non` la coupe. Activé demande le nom distant et le dossier, puis lance `rclone config`. Le jeton reste sur la machine, mode 600. Coupé, rclone n'est pas installé. |
| Distant | Nom distant. Lettres, chiffres ou tiret, 1 à 32 caractères. Seulement si la copie est activée. |
| Dossier | Dossier distant. Pas de `..` et pas de chemin local absolu. Seulement si la copie est activée. |
| Mode test | `0` ou `1`. |

## Logiciels et services installés

L'installation pose les paquets et les services ci-dessous.

| Nom | Rôle |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| openssh-server | Serveur SSH. La connexion root est refusée. L'authentification par mot de passe reste activée. `PasswordAuthentication yes`. `AllowTcpForwarding no`. `AllowAgentForwarding no`. |
| ufw | Pare-feu de l'hôte. |
| usbguard, usbguard-notifier | Autorise les appareils déjà branchés, ainsi que les claviers, les souris et les concentrateurs. Un nouveau support de stockage attend une confirmation sur le bureau. |
| fail2ban | Bannit les échecs d'authentification répétés. |
| auditd | Écrit les règles d'audit des chemins choisis. |
| rkhunter | Contrôle rootkit et propriétés de fichiers. |
| chkrootkit | Contrôle rootkit. Le binaire est `/usr/sbin/chkrootkit`. |
| clamav | Analyse à l'accès et analyse au démarrage. |
| crowdsec | Décisions de sécurité locales. |
| debsums | Sommes de contrôle des fichiers des paquets. |
| unbound | Résolveur DNS local sur `127.0.0.1` et `::1`, port 53. |
| apparmor | Profils de la distribution. `service/apparmor/userns.sh` retire un profil hfu qui n'est pas livré. |
| aide | Base d'intégrité `/var/lib/aide/aide.db`. |
| unattended-upgrades | Origines de sécurité. `Automatic-Reboot` vaut `false`. |
| postfix | Envoie le courrier d'alerte. Posé seulement lorsque `G_MAIL_ALERTS=1`. |
| rclone | Copie un fichier d'alerte vers Google Drive. Posé seulement lorsque `G_RCLONE_ALERTS=1`. |
| lynis | Audit de durcissement. |
| ubuntu-pro-client | Attache le jeton Ubuntu Pro. Hors LTS, esm-infra, esm-apps et Livepatch ne sont pas activés. Sur une LTS, leur échec n'arrête pas l'installation. |
| acct, sysstat, libpam-pwquality | Comptabilité des processus, statistiques d'activité, qualité des mots de passe. |
| rng-tools-debian, haveged | Sources d'entropie. |
| apt-listchanges, needrestart, apt-show-versions | Avis de changements de paquets et contrôles de redémarrage. |

## 📋 E-mails d'alerte

Chaque fichier d'alerte est sous `/opt/liltress-workstation/cron/alerts`.<br/>
Le courrier suit la langue `G_LANGUAGE`.<br/>
Le courrier part seulement si `G_MAIL_ALERTS=1`.<br/>
Une copie part vers Google Drive seulement si `G_RCLONE_ALERTS=1`, vers le distant et le dossier choisis.<br/>
Le courrier part seulement si `G_MAIL_ALERTS=1`, si `G_WATCHDOG_MAIL` est défini, et si `/opt/liltress-workstation/cron/bin/send.sh` est exécutable.<br/>
Un contrôle propre n'envoie pas de courrier.<br/>
Si une ligne du journal est inconnue, ne lancez pas la commande.<br/>
Gardez le courrier.

Un contrôle qui s'arrête avant sa fin envoie un courrier.<br/>
Le courrier nomme le contrôle.<br/>
Il nomme le signal, ou le code de sortie.

## ▪️ AIDE

Le message contient la ligne de résumé et un extrait du journal, puis la note et le bloc de commande.<br/>
Le message contient un bloc de vérification pour chaque constat du journal, avant le bloc de commande quand ce bloc existe.<br/>
Le chemin du journal dans le courrier est le fichier réel.<br/>
La forme est `/opt/liltress-workstation/cron/security_logs/aide-YYYYMMDD-HHMMSS.log`.

```bash
sudo bash /opt/liltress-workstation/bin/aide-refresh-db.sh
```

La commande reconstruit la base AIDE à partir du disque actuel.<br/>
La ligne de succès est `Base de référence AIDE enregistrée.`

## ▪️ chkrootkit

Le message contient le résumé et l'extrait du journal, puis la note et la commande.<br/>
Le message contient un bloc de vérification pour chaque constat du journal, avant le bloc de commande quand ce bloc existe.<br/>
L'exemple ci-dessous montre la forme.<br/>
Le courrier contient le chemin réel.

```bash
sudo bash /opt/liltress-workstation/bin/chkrootkit-ignore-log.sh '/opt/liltress-workstation/cron/security_logs/chkrootkit-YYYYMMDD-HHMMSS.log'
```

La commande enregistre les lignes de ce journal dans `/opt/liltress-workstation/cron/chkrootkit.local.ignore`.<br/>
La ligne de succès est `Aucune nouvelle détection à enregistrer.` lorsqu'il n'y a rien de nouveau, ou `N détection(s) enregistrée(s) dans /opt/liltress-workstation/cron/chkrootkit.local.ignore`.

Une détection avérée déplace le fichier et joint la commande de restauration à la place.<br/>
La commande d'enregistrement reste seulement lorsqu'aucun fichier avéré n'a été déplacé.

## ▪️ debsums

Le message contient le résumé et l'extrait du journal.<br/>
Il n'ajoute pas de bloc de commande.<br/>
Le contrôle réinstalle chaque paquet encore signalé avec `apt-get install --reinstall`.<br/>
Le courrier nomme chaque paquet rétabli.<br/>
La ligne de succès est `La somme correspond.`

Un paquet dont la somme reste différente, ou dont la réinstallation échoue, reste dans le courrier.<br/>
Une ligne pour `/var/lib/rkhunter/db/mirrors.dat` est retirée avant cette réinstallation seulement si son SHA-256 actuel est égal à `/opt/liltress-workstation/cron/rkhunter-mirrors.sha256`.<br/>
Une ligne modifiée sous `/usr/lib/*/perl-base/unicore/` du paquet `perl-base` est retirée avant cette réinstallation.<br/>
Le fichier livré par Ubuntu ne correspond pas à la somme de ce paquet.

## ▪️ ClamAV à l'accès

Le message contient la signature, le nom du fichier, le chemin d'origine et le chemin de quarantaine, puis la note et une commande de restauration par fichier déplacé.<br/>
Le même journal indique l'heure, le type de détection, les actions appliquées et une recommandation courte.<br/>
Un fichier dont le nom correspond à `.clamav-quarantine-lock.*` n'envoie pas de courrier.<br/>
Le script sort en 0 avant le journal et avant `log_alert`.

```bash
sudo bash /opt/liltress-workstation/bin/quarantine-restore.sh <id>
```

L'exemple montre la forme.<br/>
Le courrier contient l'identifiant réel.<br/>
La commande remet ce fichier à son emplacement d'origine.<br/>
La ligne de succès est `fichier remis en place`.<br/>
Le registre est `/opt/liltress-workstation/cron/quarantine.registry`.

## ▪️ Analyse ClamAV au démarrage

Le message contient le résumé et l'extrait du journal.<br/>
Lorsqu'un fichier a été déplacé, le courrier ajoute une commande de restauration par fichier.<br/>
La commande est la même que celle du courrier à l'accès.<br/>
La forme du journal est `/opt/liltress-workstation/cron/security_logs/clamav-YYYYMMDD-HHMMSS.log`.<br/>
Un fichier illisible, sans ligne `FOUND`, n'envoie pas de courrier.<br/>
Les lignes `Known viruses` et `Infected files` ne sont pas recopiées dans le courrier.<br/>
Un processus `clamscan` arrêté par un signal envoie un courrier.<br/>
Le courrier nomme le signal et chaque fichier non lu.<br/>
Les autres fichiers de la passe sont analysés.<br/>
Deux plantages de suite arrêtent la passe ClamAV.<br/>
Le courrier dit alors que les fichiers restants n'ont pas été lus.

## ▪️ Analyse ClamAV différée

Le message contient le résumé et l'extrait du journal.<br/>
Lorsqu'un fichier a été déplacé, le courrier ajoute une commande de restauration par fichier.<br/>
La commande est la même que celle du courrier à l'accès.<br/>
Une signature et un chemin déjà enregistrés dans `/opt/liltress-workstation/cron/scan-skip.seen` ne renvoient pas de courrier.<br/>
Un processus `clamscan` arrêté par un signal envoie un courrier.<br/>
Le courrier nomme le signal et chaque fichier non lu.<br/>
Les autres fichiers de la passe sont analysés.<br/>
Deux plantages de suite arrêtent la passe ClamAV.<br/>
Le courrier dit alors que les fichiers restants n'ont pas été lus.<br/>
Le tampon reste en place.<br/>
La forme du journal est `/opt/liltress-workstation/cron/security_logs/idle-scan-YYYYMMDD-HHMMSS.log`.

## ▪️ rkhunter

Le courrier d'avertissements contient le résumé et l'extrait du journal, puis la note et le bloc de commande.<br/>
Le message contient un bloc de vérification pour chaque constat du journal, avant le bloc de commande quand ce bloc existe.<br/>
Le courrier `mirrors.dat modifié hors rkhunter --update` n'ajoute pas ce bloc.<br/>
Un courrier d'erreur non plus.<br/>
La forme du journal est `/opt/liltress-workstation/cron/security_logs/rkhunter-YYYYMMDD-HHMMSS.log`.

```bash
sudo bash /opt/liltress-workstation/bin/rkhunter-refresh-db.sh
```

La commande recalcule la base de propriétés rkhunter à partir du disque actuel.<br/>
La ligne de succès est `Base de propriétés rkhunter enregistrée.`<br/>
Une détection avérée déplace le fichier et joint la commande de restauration à la place.<br/>
La commande de recalcul reste seulement lorsqu'aucun fichier avéré n'a été déplacé.<br/>
Les fichiers de `/dev/shm` et la socket `/dev/log` sont autorisés dans `rkhunter.conf.local`.<br/>
Ils ne produisent pas l'avertissement `Suspicious file types found in /dev`.<br/>
L'extrait garde la ligne d'avertissement et les chemins qui la suivent.

## ▪️ Avis de redémarrage

Le message est `Un redémarrage est utile. La machine n'a pas été redémarrée.`<br/>
Ce courrier n'ajoute pas de bloc de commande.<br/>
Le même ensemble de paquets ne renvoie pas de courrier.<br/>
Un jeu en cours saute le courrier et laisse l'empreinte inchangée.<br/>
Le script ne redémarre pas la machine.<br/>
La forme du journal est `/opt/liltress-workstation/cron/security_logs/reboot-notice-YYYYMMDD-HHMMSS.log`.

## 📋 Commandes après l'installation

Lancez ces commandes depuis le répertoire des sources (`/opt/liltress-workstation/src` après l'installeur curl, ou le répertoire du clone).

## ▪️ liltress check

```bash
sudo ./liltress check
```

Contrôle `global.conf` et `secrets.conf`.<br/>
La ligne de succès est `Configuration conforme`.<br/>

## ▪️ liltress run

```bash
sudo ./liltress run
```

Lance l'installation à partir des fichiers préparés.<br/>
L'installeur refuse de démarrer lorsque le contrôle ne passe pas.

## ▪️ verify/alerts.sh

```bash
sudo bash verify/alerts.sh
```

Contrôle le timer de la chaîne, le timer différé, ClamAV à l'accès, et le chemin du courrier.<br/>
Sans `--no-send`, une sonde part lorsque les alertes sont activées.<br/>
Le sujet se termine par `Contrôle`.<br/>
La ligne de succès est `Résultat : OK`.

```bash
sudo bash verify/alerts.sh --no-send
```

## ▪️ verify/workstation.sh

```bash
sudo bash verify/workstation.sh "$PWD"
```

Lance la vérification du poste.<br/>
La ligne de clôture a la forme `Check : N OK / N WARN / N FAIL`.<br/>
La même passe contrôle le relais SSH, la règle de pare-feu SSH, USBGuard, le délai sudo et `w-reboot-notice.timer`.

## ▪️ Contrôle après démarrage

```bash
sudo bash /opt/liltress-workstation/bin/boot-check.sh
```

Vérifie les services de sécurité du démarrage et les trois passes de cette session.<br/>
La ligne de succès est `Contrôle de démarrage : OK`.<br/>
Une passe encore en cours affiche `Contrôle de démarrage : en cours` et termine avec le code 1.<br/>
Un écart affiche `Contrôle de démarrage : écarts` et termine avec le code 1.

## ▪️ liltress lynis

```bash
sudo ./liltress lynis
```

Lance `lynis audit system --quick --no-colors` et écrit le rapport sous `<source>/log/lynis-<stamp>/`.<br/>
`G_LYNIS_MIN_SCORE` vaut 80.<br/>
`verify/workstation.sh` accepte un `hardening_index` supérieur ou égal à ce seuil.

## ▪️ Base AIDE

```bash
sudo bash /opt/liltress-workstation/bin/aide-refresh-db.sh
```

Reconstruit `/var/lib/aide/aide.db`.<br/>
La ligne de succès est `Base de référence AIDE enregistrée.`

## ▪️ Empreinte des miroirs rkhunter

```bash
sudo bash /opt/liltress-workstation/cron/bin/record-mirrors.sh save
```

Écrit le SHA-256 de `/var/lib/rkhunter/db/mirrors.dat` dans `/opt/liltress-workstation/cron/rkhunter-mirrors.sha256` en mode `600`.<br/>
`rkhunter.sh` enregistre cette empreinte seulement après un `rkhunter --update` qui retourne 0 ou 2.

## ▪️ Chemins exclus du scan

```bash
sudo bash /opt/liltress-workstation/bin/scan-skip.sh list
sudo bash /opt/liltress-workstation/bin/scan-skip.sh add $HOME/.cache/exemple
sudo bash /opt/liltress-workstation/bin/scan-skip.sh del $HOME/.cache/exemple
```

Le fichier de liste est `/opt/liltress-workstation/src/config/clamav/scan-skip.paths`.<br/>
Une liste déjà présente reste en place lorsque l'installeur tourne de nouveau.<br/>
Une liste encore dans `/opt/liltress-workstation/cron/scan-skip.paths` est copiée une fois, lorsque le nouveau fichier est encore le modèle.

| Action       | Ligne affichée                      |
| ------------ | ----------------------------------- |
| `list`       | un chemin accepté par ligne         |
| `add`        | `Chemin ajouté : <path>`            |
| déjà présent | `Ce chemin est déjà exclu : <path>` |
| `del`        | `Chemin retiré : <path>`            |
| refusé       | `Chemin refusé : <path>`            |

Un chemin refusé laisse le fichier inchangé.<br/>
La commande réécrit `/etc/clamav/clamd.conf`.<br/>
Elle relance `clamav-daemon`, puis `clamav-clamonacc.service` ou `clamonacc.service`, lorsque le bloc d'exclusion change.<br/>
