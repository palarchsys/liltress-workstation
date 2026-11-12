# Vérification du durcissement Liltress Workstation

Hôte `rchsys`, Ubuntu 26.10, session root. Utilisateur du poste : `pal` (uid 1000), session graphique toujours sur `tty2` en fin de contrôle. Date du contrôle : 2026-11-06. Produit installé sous `/opt/liltress-workstation`. Référence amont consultée en local : `/tmp/liltress-workstation-src`.

Ce contrôle ne réinstalle pas Liltress, ne redémarre pas la machine, n’importe pas de VPN, ne redémarre pas USBGuard, ssh ni Unbound, ne devine aucun mot de passe, et ne modifie aucun fichier de paquet pour forcer debsums. Les paquets ajoutés pour prouver l’usage du poste restent en place : `hello`, la chaîne de compilation, `gdb`, l’environnement Python `/home/pal/.local/liltress-venv`.

Check : 258 OK / 19 A_VOIR / 7 ECHEC

Le total additionne 214 contrôles statiques inchangés (`/root/liltress-verify/checks.tsv`), 6 états requalifiés parce que les minuteries et la table d’egress sont maintenant actives, 27 preuves d’usage (`phase3.tsv`), et 11 contrôles d’exécution listés plus bas. Les 19 A_VOIR et les 7 ECHEC sont détaillés. Aucune adresse de courrier n’est recopiée ici.

## Verdict

Le profil statique du poste tient : SSH limité au LAN, UFW, sysctl, Unbound en boucle locale, audit, AppArmor, PAM, Secure Boot, LUKS, CrowdSec et fail2ban sont en place, et `pal` peut installer, compiler, lancer un snap et ouvrir une session TLS. Lynis est à 89, au-dessus du seuil de 80.

L’exécution des contrôles planifiés est en échec. Les scripts de veille appellent `get_text` et `read_language_file`, définis dans `core/log/log.sh`, chargé par `core/watchdog/load.sh`. Ces deux fichiers sont dans l’archive amont et absents de l’arbre installé (`/opt/liltress-workstation/src` ne contient que `config`). La première passe de démarrage et la passe horaire sortent donc 127. La chaîne systemd affiche tout de même un succès, à cause du préfixe `-` sur son `ExecStart`.

La surveillance ClamAV à l’accès est également en échec. `clamdscan` reconnaît la chaîne d’essai standard. Le démon `clamonacc`, pourtant actif, laisse le fichier en place dans `/tmp`.

## ECHEC

- ECHEC — bibliothèque de textes absente. `cron/bin/common.sh` cherche `watchdog-load.sh`, ne le trouve pas, puis charge `watchdog.sh`. Celui-ci ne trouve pas `log.sh`. Toute phrase du produit (`get_text`, `read_language_file`) s’arrête avec « commande introuvable ». Les fichiers présents dans l’archive sont `/tmp/liltress-workstation-src/core/log/log.sh` et `watchdog-load.sh`. L’empreinte `cron/integrity.sha256` de l’arbre installé reste valide : le manque est un fichier jamais déployé, pas une modification ultérieure. Conséquence directe : les scripts de rafraîchissement AIDE et rkhunter ne peuvent pas afficher leur phrase de succès, et `quarantine-restore.sh` non plus. Les commandes de calcul, elles, ont bien tourné (voir OK).

- ECHEC — `w-boot-scan.service` le 2026-11-06 à 08:34:00, code 127, environ 19 s. AIDE a fini son contrôle, puis `aide.sh` ligne 28 a appelé `get_text`. Journal : `get_text: commande introuvable`. L’unité `w-boot-chain.service` se termine avec `Result=success` et `ExecMainStatus=0` : le préfixe `-` masque l’échec du scan. Il n’y a pas eu de phrase « Contrôle de démarrage : OK ».

- ECHEC — `w-hourly-scan.service` à 08:35:55, code 127. Même arrêt dans `aide.sh`. rkhunter, chkrootkit et debsums, prévus ensuite dans cette passe, n’ont pas été lancés par le produit. La minuterie est restée active et s’est reprogrammée.

- ECHEC — `/opt/liltress-workstation/bin/boot-check.sh` ne rend pas de verdict. Les titres de section s’affichent, puis `get_text` manque. Sortie conservée dans `/root/liltress-verify/boot-check.txt`.

- ECHEC — `/opt/liltress-workstation/bin/mail-test.sh` ne compose pas le message d’essai (`read_language_file` introuvable, code 127). L’acheminement SMTP lui-même fonctionne : voir le contrôle OK du message envoyé directement.

- ECHEC — `w-reboot-notice.service` s’est terminé sans évaluer le redémarrage. Le journal montre `get_text` à `reboot-notice.sh` ligne 48. L’unité systemd est au statut succès. Le journal de passe ne contient qu’un horodatage.

- ECHEC — surveillance ClamAV à l’accès inopérante. `clamav-clamonacc.service` est actif depuis 07:48 (`/usr/sbin/clamonacc -F --move=/var/lib/clamav/quarantine`). Le journal annonce des veilles inotify sur `/tmp`, `/var/tmp`, `/opt`, `/media`, `/mnt` et les dossiers personnels `Téléchargements`, `Bureau`, `Documents`, `Musique`, `Images`, `Vidéos`, puis `ERROR: ClamInotif: can't exclude '/opt/liltress-workstation'`. Le descripteur fanotify du processus n’a aucune marque dans `fdinfo`, et le thread principal reste dans `pselect` sur ce descripteur. Deux dépôts du fichier d’essai dans `/tmp`, propriétaire `pal` (modes 600 puis 644, racine exclue par `OnAccessExcludeRootUID`), sont restés en place plus de dix secondes. `clamd` n’a rien journalisé, la quarantaine n’a pas reçu le fichier, la table `inet w_isolate` n’est pas apparue, `w-net-release` non plus. Le fichier a été effacé. La réponse prévue (quarantaine, arrêt du processus écrivain, rejet des nouvelles sorties pendant 120 s) n’a donc pas pu être observée : elle n’a pas été appelée. Un `clamdscan` explicite, hors de ces chemins, trouve bien la même chaîne d’essai.

## A_VOIR

Impact pour `pal` à chaque ligne. Ce ne sont pas des contrôles morts, ni des blocages de l’usage normal du poste.

- A_VOIR — la commande `liltress` n’est pas dans le `PATH`. Les sources installées ont été réduites aux fragments de configuration. Importer un profil VPN ou relancer l’installeur depuis cette machine demande de récupérer les sources. `vpn.json` est `mode=off`, sans profil. Les unités VPN et le killswitch sont désactivés. Rien n’a été importé.

- A_VOIR — `MODE_TEST=1` dans `config/global.conf`. La valeur est lue à la configuration. Aucun bloc `# BEGIN liltress MODE_TEST` dans `/etc/hosts`, aucun effet observé au runtime. La valeur n’a pas été changée.

- A_VOIR — `/etc/cron.daily/debsums` charge `/etc/default/debsums`, qui n’existe pas, puis sort. Le cron quotidien du paquet est donc un no-op. Les scripts hebdomadaire et mensuel sont là. Lynis le signale (PKGS-7370). Ce n’est pas le contrôle Liltress, qui, lui, n’atteint pas debsums à cause de l’échec horaire.

- A_VOIR — fail2ban jail `sshd` : bantime 1 h, maxretry 5, `ignoreip` vide. Cinq échecs depuis la boucle locale peuvent bannir `127.0.0.1`. Aucune rafale n’a été envoyée. Compteur actuel : 0 banni, 0 échec.

- A_VOIR — `lynis.timer` est `failed` / unité introuvable (disparue vers 07:43). Le binaire Lynis est installé et l’audit manuel a tourné. Le score ne dépend pas de cette minuterie.

- A_VOIR — `fwupd-refresh.service` est en échec. Hors du contrat Liltress. Les mises à jour firmware du poste ne partent pas toutes seules par ce timer.

- A_VOIR — `chkrootkit.timer` du paquet est activé en plus des passes Liltress. Doublon de charge. Il n’a pas été masqué.

- A_VOIR — `dailyaidecheck.timer` du paquet est activé en plus des passes Liltress. Doublon de charge. Il n’a pas été masqué.

- A_VOIR — `legacy-printer-app` écoute sur `*:8000`. Depuis un préfixe non autorisé, ce port est refusé par UFW, comme le port 22 hors LAN. Le service n’a pas été purgé.

- A_VOIR — les paquets CUPS ont été purgés. Le candidat `cups` `2.4.16-1ubuntu3` reste installable (`Candidat` dans `apt-cache policy`). `pal` peut réinstaller une impression plus tard.

- A_VOIR — `unshare -Ur` lancé par `pal` est refusé par AppArmor (`kernel.apparmor_restrict_unprivileged_userns=1`, laissé à 1). `bwrap --unshare-user` et `snap run hello-world` fonctionnent. Firefox est installé en snap. Refus du `unshare` brut, outils profilés utilisables : comportement Ubuntu attendu, pas un blocage du poste.

- A_VOIR — chkrootkit marque `basename`, `date`, `dirname`, `echo` et `env` INFECTED. Ce sont des liens vers coreutils Rust (`coreutils-from-uutils`, `/usr/lib/cargo/bin/coreutils/`). L’outil cherche des chaînes des coreutils GNU. Les autres binaires contrôlés sont « not infected ». L’avertissement de fichiers suspects ne cite que des fichiers de paquets Debian (jeux d’essai fail2ban `.htaccess`, `.build-id`, firmware). Aucune famille de rootkit connue n’est rapportée. Les faux positifs n’ont pas été ajoutés à une liste d’ignorance.

- A_VOIR — `rkhunter --check` a avancé jusqu’aux chaînes de `/dev/ptyq` (08:36:47) puis est resté bloqué : `head` et `cut` en attente sur un tube sans écrivain. Aucune ligne d’avertissement. Processus arrêté (signal 15, code 143). Ce n’est pas une détection. Le rafraîchissement des propriétés, plus court, s’est terminé.

- A_VOIR — trois écarts debsums, aucun binaire du système modifié pendant ce contrôle. `mirrors.dat` de rkhunter est une donnée d’exécution (97 octets, écrite à l’installation). `/usr/lib/crowdsec/plugins/notification-email` a un ctime 07:46, pendant l’installation Liltress, mtime du paquet au 27 octobre. `Encode/Byte/Byte.so` (libperl 5.42.3-1) ne correspond pas au md5 du paquet, mais naissance et ctime sont au 27 octobre : le fichier n’a pas été réécrit aujourd’hui. `libasan` et `libwebkitgtk`, signalés une fois, correspondent au md5 du paquet quand on les relit. `dpkg -V` ne retient que la configuration rkhunter et `mirrors.dat`.

- A_VOIR — après incorporation des paquets de la phase 3 dans la base AIDE, chaque `--check` suivant signale un seul gros fichier dont l’empreinte diffère, et le fichier n’est pas le même d’une passe à l’autre (`Byte.so`, puis `libwebkit2gtk`, puis `libLLVM.so.22.1`). Leurs ctime restent en octobre, et debsums accepte webkit et LLVM. Le contrôle de 09:01, contre l’ancienne base, était stable. La nouvelle base contient les 1 420 ajouts légitimes. Une troisième initialisation n’a pas été lancée.

- A_VOIR — le chemin IPv6 vers le relais SMTP du courrier d’alerte répond « Network is unreachable ». L’envoi est parti en IPv4 (`status=sent`, accusé 250). IPv6 n’est pas désactivé par le sysctl du profil. Limite de cette VM, pas un filtre du poste.

- A_VOIR — `w-periodic-scan.timer` est actif, première échéance vers 09:31 (OnBootSec=2 h après le boot de 07:31). La passe n’a pas encore tourné. Son script charge le même `common.sh` : le même arrêt 127 est attendu. Elle n’a pas été avancée à la main.

- A_VOIR — la passe différée déclenchée par la chaîne a écrit `clamscan OK` dans `idle-scan-20261106-083419.log`. La liste de fichiers à examiner était vide, donc le code de sortie 0 ne couvre pas `/home`. `scan-skip.sh list` montre les exclusions `/home/pal/.cache`, `/home/pal/snap`, `/var/jeux`, qui recoupent `OnAccessExcludePath`. Ce n’est pas un scan du domicile.

- A_VOIR — AIDE a vu la disparition du lien `/etc/systemd/system/timers.target.wants/apt-listchanges.timer`. Le paquet `apt-listchanges` 4.8+nmu3 est toujours installé, son timer est désactivé. Écart de cohérence du paquet, pas une suppression faite par ce contrôle.

Les limites assumées du profil, déjà comptées OK dans le relevé statique, ont cet impact pour `pal` : UDF et HFS+ sont bloqués au chargement (`vfat`, `exfat`, `ntfs3` et `fuse` se chargent) ; `ptrace_scope=1` empêche gdb d’attacher un processus qui n’est pas son fils ; `dmesg` est refusé à `pal` ; perf, BPF non privilégié et kexec sont restreints. Secure Boot est actif. La racine est un volume LUKS (`vda3` → LVM → ext4). `/home` est sur cette racine. `/tmp` est un tmpfs `rw,nosuid,nodev`, sans `noexec`.

## OK — relevé statique

- OK — 214 contrôles de `checks.tsv`. Comptes et verrouillage root, identité de `pal` et groupe `sudo`, faillock (deny 8, unlock 600, intervalle 900) et pwquality (minlen 12), sudoers (timeout 5, umask 0022, NOPASSWD ClamAV limité à `clamav-event.sh`). SSH : `PermitRootLogin no`, `PasswordAuthentication yes`, pas de relais TCP, agent, X11 ni tunnel, bannière, `sshd_config` en 600, limite UFW du port 22 au préfixe connecté `192.168.122.0/24` et à `fe80::/10`. Les essais locaux en `BatchMode` refusent `pal` et root ; aucun mot de passe n’a été tenté. UFW : entrant refusé, sortant autorisé, forward ACCEPT, IPv6 actif, journalisation medium. Sysctl du profil conforme, y compris `ip_forward=1`, `rp_filter=2`, ASLR 2, userns clone autorisé et restriction AppArmor des userns. Unbound n’écoute que sur `127.0.0.1` et `::1`, systemd-resolved pointe vers ces adresses, `FallbackDNS` vide, `root.hints` surveillé. Auditd actif, règles en `-F key=`, perte 0. Une création puis suppression de `/etc/ssh/.liltress-audit-probe` est bien dans le journal d’audit ; le fichier n’est plus là. AppArmor chargé, profils en enforce, y compris les profils userns et les navigateurs. CrowdSec : API en boucle locale, bouncer firewall valide, durée de ban 48 h, aucune décision active. Journaux persistants, core dumps désactivés, `rng-tools-debian` et haveged actifs, chrony actif. Ubuntu Pro attaché sur cette version intermédiaire : l’absence d’ESM et de Livepatch est conforme. Mises à jour automatiques sans redémarrage forcé. Postfix n’écoute qu’en boucle locale. Les secrets du produit sont en 0700 ; seul le chemin a été contrôlé. USBGuard autorise les périphériques déjà présents, les HID et les hubs ; le stockage USB n’est pas blacklisté. Le module i386 est une architecture étrangère du poste. La liste d’intégrité du produit passe `sha256sum -c` sans écart.

## OK — minuteries et egress

Ces six lignes étaient « enabled / inactive » parce que l’installation a fini après le boot (boot 07:31, install vers 07:42–07:50) sans `enable --now`. Elles ont été démarrées pendant le contrôle. Aucune n’a été masquée.

- OK — `w-boot-chain.timer` actif. Il a tiré à 08:34:00. Pas de prochaine échéance (`OnBootSec=0`).
- OK — `w-hourly-scan.timer` actif. Déclenché à 08:35:55 parce que `OnBootSec=1h` était déjà dépassé. Prochaine passe vers 09:35.
- OK — `w-idle-scan.timer` actif. Prochaine échéance vers 09:34.
- OK — `w-periodic-scan.timer` actif. Prochaine échéance vers 09:31.
- OK — `w-reboot-notice.timer` actif. Prochaine échéance vers 14:34.
- OK — `w-egress-table.service` actif (`RemainAfterExit`). Table `inet w_egress` présente : établi, boucle locale, DNS, 80, 443, NTP et quelques ports de poste acceptés, le reste journalisé. `curl` vers `https://example.com` répond 200 après l’ensemble des tests. Plafond des passes : `CPUQuota=200%`, `Nice=19`, classe d’E/S idle.

## OK — usage du poste

Vingt-sept preuves, utilisateur `pal` sauf les opérations de pare-feu qui exigent root. Les quatre modes des compilateurs, les trois refus de port, la pose et le retrait de la règle, et les quatre systèmes de fichiers comptent chacun pour un contrôle. Le réseau de test, le veth, la règle UFW temporaire et le serveur HTTP local ont été retirés.

- OK — `curl` HTTPS vers `example.com` en tant que `pal`.
- OK — résolution de nom par `getent` en tant que `pal`.
- OK — `gcc`, `g++`, `cc` et `make` en mode 755 (via `stat -L`).
- OK — compilation et exécution d’un programme dans `/home/pal` et dans `/tmp`.
- OK — cette compilation n’a rien mis en quarantaine ClamAV.
- OK — `python3 -m venv` puis `pip install six` dans `/home/pal/.local/liltress-venv`.
- OK — `snap version` répond.
- OK — `snap install hello-world` puis `snap run hello-world` affiche Hello World.
- OK — `gdb` exécute `/usr/bin/hello` comme fils.
- OK — `gdb` ne s’attache pas à un `sleep` qui n’est pas son fils.
- OK — `dmesg` est refusé à `pal`.
- OK — `pal` est dans le groupe `sudo` ; `sudo -n -l` échoue sans ticket. Le mot de passe n’a pas été demandé ni réinitialisé.
- OK — un `http.server` sur `127.0.0.1:8765` répond.
- OK — depuis le préfixe `10.77.0.0/30`, les ports 8765, 8000 et 22 sont refusés tant qu’aucune règle ne les ouvre.
- OK — `ufw allow 8765/tcp` avec le commentaire de contrôle laisse ce préfixe se connecter.
- OK — la suppression de cette règle rétablit le refus. Aucune règle `liltress-verify` ne reste.
- OK — `vfat`, `exfat`, `ntfs3` et `fuse` sont chargeables.
- OK — la session graphique de `pal` est restée sur `tty2` après ces opérations, et elle y est encore à la clôture.

## OK — exécution complémentaire

- OK — Lynis `audit system` : indice 89, 253 tests, 0 warning, 8 suggestions (démarrage, durcissement des services, processus, PAM rounds, nom DNS, purge d’un paquet retiré, cron debsums, fichiers supprimés encore ouverts). Seuil du profil : 80. Rapport dans `/root/liltress-verify/lynis.txt` et `/var/log/lynis-report.dat`.
- OK — chkrootkit code 0. Aucune signature de rootkit connu. Les INFECTED sont l’A_VOIR coreutils Rust.
- OK — `clamdscan` de la chaîne d’essai déposée sous `/home/pal/liltress-verify-eicar/`, hors des chemins surveillés à l’accès : 1 fichier trouvé. Le répertoire a été supprimé. La table `inet w_isolate` n’est pas apparue, ce qui est le comportement attendu hors surveillance à l’accès.
- OK — `clamdscan` de `/usr/bin/hello` retourne 0. Les CVD ClamAV sont du 2026-11-06. `clamdscan --ping` répond PONG.
- OK — `sha256sum -c /opt/liltress-workstation/cron/integrity.sha256 --quiet` réussit en fin de contrôle.
- OK — un seul message d’essai, sujet se terminant par « Contrôle », envoyé avec `mail` vers le destinataire déjà configuré. File Postfix vide. Le journal du relais montre l’échec IPv6 puis l’accusé IPv4 250. `mail-test.sh` n’a pas servi à cet envoi. Aucun second message n’a été émis. rclone reste absent, conforme à `RCLONE_ALERTS=0`.
- OK — AIDE 0.19, base du 07:50, contrôle de 09:01 : 53 274 entrées, 1 420 ajouts, 1 suppression, 7 changements. Les ajouts sont la chaîne de compilation, Python de `pip`/`venv`, `hello`, et les montages snap `core` et `hello-world`. La suppression est le lien `apt-listchanges.timer`. Les changements sont `/etc/ld.so.cache` et les nombres de liens de répertoires sous `/usr/lib`. Aucun chemin de compte, de SSH, de cron ou de pare-feu dans les ajouts.
- OK — `aide-refresh-db.sh` a initialisé une nouvelle base et l’a installée (`/var/lib/aide/aide.db`, 09:02, 4 906 020 octets). La phrase « Base de référence AIDE enregistrée. » n’est pas sortie, faute de `get_text`. Une seconde initialisation a été faite après un écart d’empreinte non reproductible. L’instabilité restante est l’A_VOIR ci-dessus.
- OK — `rkhunter-refresh-db.sh` a mis à jour les propriétés (`rkhunter.dat` à 09:02, « File updated: searched for 180 files, found 181 »). La phrase de succès du script n’est pas sortie, même cause.
- OK — `scan-skip.sh list` fonctionne et n’a rien ajouté ni retiré.
- OK — clôture : table `inet w_isolate` absente, table `inet w_egress` présente, aucun fichier d’essai restant, `faillock` de `pal` vide, aucun netns de test, `curl` HTTPS renvoie 200, session `pal` sur `tty2`.

## Ce qui n’a pas été refait

Pas de reboot pour rejouer `OnBootSec` à froid. Pas d’import VPN. Pas de redémarrage d’USBGuard, ssh ou Unbound. Pas de rafale SSH contre fail2ban ou CrowdSec. Pas de second courrier. Le cœur manquant n’a pas été copié dans l’arbre installé : ce contrôle constate, il ne répare pas.

Les prochaines passes horaire (vers 09:35) et périodique (vers 09:31) chargeront le même `common.sh`. Sans remise en place de `core/log/log.sh` et `core/watchdog/load.sh`, elles s’arrêteront au même endroit, et la chaîne de démarrage continuera d’afficher un succès systemd.

Check : 258 OK / 19 A_VOIR / 7 ECHEC
