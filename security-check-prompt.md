# Contrôle de sécurité — Liltress Workstation

Prompt pour GROK-BUILD, exécuté en root sur la machine déjà installée. Il constate. Il ne répare pas.

## Rôle

Tu es root sur un poste Ubuntu durci par Liltress Workstation. La base est `/opt/liltress-workstation`. Tu produis un rapport que un autre tour pourra lire sans revenir sur la machine.

Tu ne réinstalles pas. Tu ne redémarres pas. Tu n'importes pas de VPN. Tu ne redémarres pas ssh, Unbound, USBGuard, ni le pare-feu. Tu ne changes aucun fichier de paquet, aucun mot de passe, aucun compte. Tu n'installes aucun paquet. Tu effaces chaque fichier d'essai avant la fin.

## Secret

Ne lis pas `secrets.conf` pour le recopier. Ne recopie pas un jeton, un mot de passe, une clé privée, une adresse de courrier, ni le corps d'un courrier. Tu peux dire qu'un fichier existe, son mode, et son propriétaire. Une adresse s'écrit `courrier configuré`, jamais le texte.

## Contrat du poste

Ces faits sont voulus. Les noter OK. Ne pas les classer ECHEC.

- `PasswordAuthentication yes`. Pas de `AllowUsers`. Pas de port SSH imposé autre que celui déjà détecté.
- UFW : entrant refusé, sortant autorisé. IPv6 du pare-feu actif.
- IPv6 du noyau non coupé. `ip_forward=1`. `rp_filter=2`. `kernel.randomize_va_space=2`. `kernel.yama.ptrace_scope=1`.
- `kernel.apparmor_restrict_unprivileged_userns=1`. `unshare -Ur` refusé, snap et bwrap utilisables : OK.
- `/tmp` sans `noexec`. Compilateurs en 755, pas en 700. Stockage USB non blacklisté.
- Plancher Lynis 80. Une suggestion Lynis n'est pas un échec. `CRON_CHECK=no` dans `/etc/default/debsums` est voulu.
- `MODE_TEST=1` sans bloc dans `/etc/hosts` est normal sur le poste.
- Sources réduites à la configuration : normal si `log.sh` et les catalogues restent sous la base.
- CUPS purgé, paquet encore installable : normal. Un service d'impression étranger écoutant un port, refusé par UFW depuis l'extérieur : A_VOIR, pas ECHEC.

## Statut

- `OK` : le fait attendu est présent, avec une preuve.
- `A_VOIR` : le poste fonctionne, un écart existe, l'usage de l'utilisateur n'est pas bloqué.
- `ECHEC` : un contrôle du produit ne tient pas, ou une porte de sécurité est ouverte.

Une commande qui manque parce que le paquet n'est pas installé est `ECHEC` si le produit doit l'installer. Un délai de minuterie pas encore échu est `A_VOIR`, avec l'heure prévue.

## Méthode

Lis `/opt/liltress-workstation/config/global.conf` pour `LANGUAGE`, `MODE_TEST`, `MAIL_ALERTS`, `RCLONE_ALERTS`, `LYNIS_MIN_SCORE`, `CONFIG_BASE_DIRECTORY`. Ne source pas `secrets.conf` dans le rapport.

Chaque contrôle a un identifiant stable. Une preuve est une commande et une ligne de résultat. Pas de vidage de journal. Vingt lignes au plus par preuve, coupées.

Écris deux fichiers, mode `600`, répertoire `/root/liltress-verify/` :

- `controle-AAAAMMJJ-HHMMSS.md` — le rapport ci-dessous
- `checks.tsv` — une ligne par contrôle : `id`, tabulation, `OK` ou `A_VOIR` ou `ECHEC`, tabulation, preuve en une ligne sans tabulation

Affiche le markdown entier à la fin. Le TSV est la liste complète. Le markdown reprend chaque ECHEC et chaque A_VOIR, puis les OK en une ligne chacun.

## Format du rapport

```
# Contrôle Liltress Workstation

hôte: 
date: 
os: 
noyau: 
utilisateur: 
uid: 
base: /opt/liltress-workstation
langue: 
mode_test: 
mail_alerts: 
rclone_alerts: 
lynis_min: 

## Synthèse

OK: 
A_VOIR: 
ECHEC: 

## ECHEC

- id — fait. Preuve : commande → ligne.

## A_VOIR

- id — fait. Impact pour l'utilisateur. Preuve : commande → ligne.

## OK

- id — fait.

## Non fait

- ce qui n'a pas été lancé, et pourquoi.
```

Aucun secret dans ces sections. Si une preuve contient un secret, remplace-le par `secret omis` avant d'écrire.

## Contrôles

Exécute-les dans cet ordre. Un échec n'arrête pas la suite.

### Identité

- `id.os` — Ubuntu, version 26.04 ou plus récente. Une intermédiaire est acceptée.
- `id.user` — un compte humain uid 1000 à 59999, groupe `sudo`, home sous `/home`. Le hash dans `shadow` n'est pas vide, `!` ni `*`. Ne pas afficher le hash : écrire `hash présent` ou `hash absent`.
- `id.root` — le hash root est verrouillé (`!`, `*`, `!!`) ou présent sans que tu le changes. Ne pas afficher le hash.
- `id.chage` — `chage -l` du compte humain : le maximum n'est pas forcé à 90 jours.
- `id.base` — la base existe. Dire si `liltress` est dans le `PATH`, et si `src/` ne contient que la configuration.
- `id.mode` — valeur de `MODE_TEST`. Absence de bloc `# BEGIN liltress MODE_TEST` dans `/etc/hosts` : OK sur le poste.

### Texte du produit

- `text.log` — un de ces fichiers existe et se source : `cron/bin/log.sh`, `bin/log.sh`, `src/core/log.sh`. Après source, `declare -F get_text` et `declare -F read_language_file` réussissent.
- `text.catalog` — `core/text/<langue>` ou `locale/<langue>` contient des fichiers `.txt`. `get_text` sur une clé connue de veille ne renvoie pas la clé brute.
- `text.common` — `bash -c 'source cron/bin/common.sh; declare -F get_text'` depuis la base ne sort pas `commande introuvable`. Ne pas lancer la passe entière.
- `text.boot` — `bin/boot-check.sh` affiche un verdict, pas seulement des titres. S'il sort 127 ou `get_text absent` : ECHEC.
- `text.integrity` — `sha256sum -c cron/integrity.sha256 --quiet` réussit. Un écart est ECHEC. Dire le nombre de lignes, pas chaque chemin, sauf les écarts.

### SSH

Fichier effectif : `sshd -T`. Attendu :

- `ssh.root` — `permitrootlogin no`
- `ssh.password` — `passwordauthentication yes`. La valeur `no` est ECHEC sur le poste.
- `ssh.allowusers` — aucune directive `AllowUsers`.
- `ssh.forward` — `allowtcpforwarding no`, `allowagentforwarding no`, `x11forwarding no`, `permittunnel no`
- `ssh.banner` — bannière configurée, fichier présent.
- `ssh.file` — le drop-in du produit est en `600` ou plus strict pour `sshd_config` si le produit l'a posé ainsi. Noter le mode réel.
- `ssh.local` — `ssh -o BatchMode=yes` vers le compte et vers root est refusé sans demander de mot de passe. Ne pas tenter de mot de passe.
- `ssh.ufw` — le port SSH n'est pas ouvert vers le monde. Il est limité au préfixe connecté et, pour le lien local IPv6, à `fe80::/10`. Un `ufw status` world-open sur ce port est ECHEC.

### Pare-feu et sysctl

- `ufw.policy` — défaut entrant deny, sortant allow, routé noter la valeur. IPv6 actif dans UFW.
- `ufw.listen` — chaque écoute `ss` non locale : dire le processus, le port, et si UFW la refuse depuis un préfixe qui n'est pas le LAN. Ne pas ouvrir de port.
- `sysctl.forward` — `net.ipv4.ip_forward=1`
- `sysctl.rp` — `net.ipv4.conf.all.rp_filter=2`
- `sysctl.aslr` — `kernel.randomize_va_space=2`
- `sysctl.ptrace` — `kernel.yama.ptrace_scope=1`
- `sysctl.ipv6` — `net.ipv6.conf.all.disable_ipv6=0`. La valeur 1 est ECHEC.
- `sysctl.userns` — les user namespaces ne sont pas coupés par un sysctl à 0. La restriction AppArmor à 1 est OK.
- `egress.table` — la table `inet w_egress` existe. `curl -fsS -o /dev/null -w '%{http_code}' https://example.com` répond 200 pour l'utilisateur du poste. À la fin, `inet w_isolate` est absente.

### Résolveur

- `dns.unbound` — Unbound n'écoute que sur `127.0.0.1` et `::1`.
- `dns.resolved` — systemd-resolved pointe vers ces adresses. `FallbackDNS` vide.
- `dns.user` — `getent hosts example.com` réussit en tant que l'utilisateur du poste.

### Comptes, PAM, noyau utile

- `pam.length` — la longueur minimale est 12, pas un plancher de serveur à 32.
- `pam.faillock` — deny, unlock et intervalle sont ceux du profil. Les noter.
- `pam.hash` — `yescrypt` ou la méthode écrite par le produit est présente. Ne pas changer un mot de passe.
- `compiler.mode` — `gcc`, `g++`, `cc`, `make` sont en 755 s'ils sont installés. 700 est ECHEC. S'ils sont absents : A_VOIR, ne pas les installer.
- `tmp.mount` — `/tmp` est `rw` sans `noexec`.
- `coredump` — les core dumps sont désactivés ou le socket systemd-coredump est masqué.
- `usb.storage` — `usb-storage` n'est pas blacklisté.
- `pro.attach` — Ubuntu Pro est attaché. Sur une version intermédiaire, l'absence d'ESM et de Livepatch est OK.

### SSH du service et durcissement local

- `apparmor.state` — AppArmor est chargé, les profils du produit sont en enforce. Ne pas lancer `aa-enforce` sur tout.
- `apparmor.unshare` — en tant que l'utilisateur, `unshare -Ur true` est refusé. Le noter OK si le refus vient d'AppArmor.
- `auditd.live` — auditd est actif, au moins une règle porte `-F key=`. Créer puis effacer `/etc/ssh/.liltress-audit-probe`. La création doit apparaître dans le journal d'audit. Le fichier ne reste pas.
- `crowdsec.api` — l'API n'écoute qu'en boucle locale. Aucune décision active n'est exigée. Une décision qui bannit le LAN sans événement est A_VOIR.
- `fail2ban.local` — la prison `sshd` existe. `ignoreip` contient `127.0.0.1/8` et `::1`. S'il est vide : A_VOIR, ne pas envoyer de rafale.
- `usbguard.policy` — le service est actif. Les périphériques déjà branchés sont autorisés. Aucune classe entière de stockage n'est refusée. Ne pas redémarrer USBGuard.

### ClamAV à l'accès

- `clam.daemon` — `clamdscan --ping` répond PONG. Les signatures ont une date. La noter.
- `clam.unit` — `clamav-clamonacc.service` ou `clamonacc.service` est actif. La ligne de commande contient `--move=` vers la quarantaine.
- `clam.exclude` — le journal de l'unité, depuis le boot, ne contient pas `can't exclude`. Cette ligne est ECHEC même si l'unité est active.
- `clam.marks` — le descripteur fanotify du processus a au moins une marque dans `/proc/<pid>/fdinfo`. Zéro marque est ECHEC.
- `clam.include` — `clamd.conf` contient `OnAccessIncludePath` pour `/tmp`, `/var/tmp` et `/opt`, et pas pour `/` ni pour `/home` entier.
- `clam.product` — `OnAccessExcludePath` ne vise pas `/opt/liltress-workstation`. Cette exclusion est ECHEC : elle coupe toutes les veilles.
- `clam.eicar` — déposer la chaîne d'essai standard dans un fichier mode `644`, propriétaire l'utilisateur du poste, sous `/tmp`, hors d'un chemin exclu. Attendre quinze secondes. Attendu : le fichier quitte `/tmp`, la quarantaine le reçoit, ou `clamd` journalise la détection. S'il reste en place : ECHEC. Effacer le fichier et la copie en quarantaine de cet essai. Ne pas laisser `inet w_isolate` : si elle apparaît, la noter, puis la retirer seulement si la règle porte le commentaire de cet essai. Sinon la noter ECHEC et ne pas y toucher.
- `clam.scan` — `clamdscan` d'un fichier sain `/usr/bin/true` ou équivalent retourne 0.

### Passes planifiées

Unités : `w-boot-chain`, `w-hourly-scan`, `w-idle-scan`, `w-periodic-scan`, `w-reboot-notice`, `w-egress-table`.

- `timer.enabled` — chaque minuterie est enabled. Une minuterie seulement enabled et jamais partie depuis l'installation : A_VOIR, avec la prochaine échéance.
- `timer.active` — celles dont l'échéance est passée sont active. `w-egress-table.service` est active.
- `timer.mask` — `dailyaidecheck.timer` et `chkrootkit.timer` du paquet sont masqués ou absents. Présents et actifs : A_VOIR.
- `timer.foreign` — `lynis.timer` et `fwupd-refresh.service` en échec : A_VOIR, hors contrat. Ne pas les réparer.
- `boot.result` — dernier `w-boot-scan.service` : code de sortie. 127 ou `get_text: commande introuvable` est ECHEC. Si `w-boot-chain.service` est `success` alors que le scan est `failed` : ECHEC, le préfixe `-` a masqué l'échec.
- `hour.result` — dernier journal de `w-hourly-scan`. S'il s'arrête dans `aide.sh` avant rkhunter, chkrootkit et debsums : ECHEC.
- `reboot.result` — `w-reboot-notice` a évalué le redémarrage. Un journal qui ne contient qu'un horodatage : ECHEC.
- `idle.empty` — si la dernière passe différée dit `clamscan OK` avec une liste vide : A_VOIR. La phrase attendue est qu'aucun fichier n'était à examiner.
- `rkhunter.hang` — ne pas relancer un `--check` complet s'il a déjà bloqué dans ce boot. Lire le dernier journal. Un processus `rkhunter` encore en `head` ou `cut` sur un tube : A_VOIR, ne pas le tuer sauf s'il a été lancé par ce contrôle.

### Intégrité et courrier

- `aide.db` — la base `/var/lib/aide/aide.db` existe. Ne pas lancer un `--init`. Un `--check` n'est lancé que s'il n'y en a pas déjà un dans les deux dernières heures. S'il signale un seul gros fichier dont l'empreinte change d'une passe à l'autre alors que debsums l'accepte : A_VOIR.
- `debsums.file` — `/etc/default/debsums` existe et contient `CRON_CHECK=no`. Fichier absent : A_VOIR. `CRON_CHECK=yes` n'est pas demandé.
- `debsums.known` — `mirrors.dat` de rkhunter et les fichiers Perl `unicore` ne sont pas, à eux seuls, un ECHEC. Un binaire du système modifié hors de cette liste est ECHEC.
- `chk.ignore` — `cron/bin/chkrootkit.ignore` ou `src/config/chkrootkit/patterns.ignore` existe et cite `basename`, `date`, `dirname`, `echo`, `env`. Les INFECTED de chkrootkit limités à ces noms sont A_VOIR si le fichier d'ignorance manque, OK s'il est là.
- `mail.postfix` — si `MAIL_ALERTS=1`, Postfix n'écoute qu'en boucle locale.
- `mail.test` — lancer `bin/mail-test.sh` une seule fois si `MAIL_ALERTS=1` et si aucun essai n'a déjà été envoyé aujourd'hui. Attendu : le script charge `get_text`, le message part par le chemin du produit, le sujet vient du catalogue. Un corps qui dit que `mail-test.sh` ne charge pas `get_text` et que le message est envoyé par `mail` est ECHEC. Ne pas envoyer un second message. Si les alertes sont coupées : OK, aucun envoi.
- `mail.ipv6` — si le journal du relais montre `Network is unreachable` en IPv6 puis un accusé 250 en IPv4 : A_VOIR. Ne pas couper l'IPv6.
- `mail.drive` — `RCLONE_ALERTS=0` et rclone absent : OK. `RCLONE_ALERTS=1` sans binaire : ECHEC.

### VPN

- `vpn.mode` — lire `vpn/vpn.json` sans afficher de clé. Noter `mode` et le nombre de profils. `mode=off` sans profil : OK.
- `vpn.units` — sans profil valide, les unités de tunnel et le killswitch ne sont pas actifs. C'est OK.
- `vpn.ssh` — la configuration dit que SSH ne passe pas par le tunnel. Le vérifier dans les règles, pas en ouvrant un tunnel.

### Usage

Seulement si l'outil est déjà là. Ne rien installer. Effacer les fichiers créés.

- `use.https` — `curl` HTTPS vers `example.com` en tant que l'utilisateur répond 200.
- `use.compile` — si `gcc` est là, compiler un programme de trois lignes dans `/tmp`, l'exécuter, l'effacer. Il ne doit pas finir en quarantaine.
- `use.sudo` — l'utilisateur est dans `sudo`. `sudo -n -l` échoue sans ticket. Ne pas demander le mot de passe.
- `use.session` — la session graphique, si elle existe, est encore sur le même tty à la fin.

### Fermeture

- `end.isolate` — `inet w_isolate` absente.
- `end.egress` — `inet w_egress` présente.
- `end.probe` — aucun fichier d'essai restant, y compris sous `/tmp`, la quarantaine de cet essai, et `/etc/ssh/.liltress-audit-probe`.
- `end.faillock` — le faillock de l'utilisateur est vide. S'il ne l'est pas à cause de ce contrôle : A_VOIR.

## Fin

Compte OK, A_VOIR et ECHEC sur le TSV. Le même compte est dans la synthèse. Chaque ECHEC du markdown a le même identifiant que le TSV. Trie les ECHEC avant les A_VOIR. N'ajoute pas de conseil de réparation dans le rapport : le fait et la preuve suffisent.
