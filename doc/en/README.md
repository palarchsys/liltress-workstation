<div align="center">

# 🛡️ Liltress Workstation 🛡️

![Ubuntu 26.04 or newer](https://img.shields.io/badge/Ubuntu-26.04%2B-E95420?logo=ubuntu&logoColor=white)
![Workstation](https://img.shields.io/badge/profile-workstation-1f6feb)
![Unbound](https://img.shields.io/badge/DNS-Unbound-0055A4)
![UFW](https://img.shields.io/badge/firewall-UFW-0055A4)
![Security checks](https://img.shields.io/badge/checks-AIDE%20%C2%B7%20ClamAV%20%C2%B7%20Lynis-2ea44f)

Liltress Workstation prepares an Ubuntu 26.04 or newer workstation.<br/>
It installs the local DNS resolver, the firewall, and the security checks.<br/>
The Ubuntu account already created on the machine is not replaced.<br/>
The installer does not create a second account.<br/>

</div>

## 📋 Before you start

Three points come before installation: the system, access, and the external needs.

## ▪️ System

Ubuntu 26.04 or newer, including an interim release.<br/>
A fresh installation is preferred.<br/>
Use a local console or the existing graphical session.<br/>
The machine needs Internet access.

## ▪️ Access

You need `sudo` for `./liltress configure`, `./liltress run`, and the checks.

## ▪️ External needs

| Need                 | Link and procedure                                                                                                                                                                                                   |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ubuntu Pro token     | Required. Open [https://ubuntu.com/pro/dashboard](https://ubuntu.com/pro/dashboard) and copy the token. `configure.sh` accepts letters and digits only, length 6 to 100, with no space.                              |
| Application password | Asked only if you enable mail alerts. Use the application password of the mail provider. Never type the account password. Length 8 to 128. Spaces typed in the prompt are removed.                                   |
| SMTP server          | Asked only if alerts are enabled. Form `host:port`. The example in `configure.sh` is `smtp-mail.outlook.com:587`. Brackets are refused. `swaks` sends one test message. The success line is `Essai d'envoi accepté.` |

## 📋 Installation

The workstation is prepared by the curl installer, or by a clone followed by `sudo ./liltress configure`.

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

## What configure.sh does

`sudo ./liltress configure` asks the questions below, writes `global.conf` mode `644` and `secrets.conf` mode `600` as root, then starts `script/run.sh`.<br/>
`secrets.conf` stays on the machine. Do not copy it into a message, a ticket, or a repository.<br/>
The first question chooses the language.<br/>
The value is `G_LANGUAGE`.<br/>
The default is English.<br/>

| Question         | Expected answer                                                                                                                                     |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Jeton Ubuntu Pro | Letters and digits, 6 to 100, no space. Required.                                                                                                   |
| Activer          | `Y` or `y` enables mail. `N`, `n` or `non` disables mail. Disabled does not install Postfix. Any other answer prints `Répondez Y ou N.`            |
| Serveur          | `host:port`, for example `smtp-mail.outlook.com:587`. No brackets. Asked only when alerts are enabled.                                              |
| Login            | An e-mail address.                                                                                                                                  |
| Password         | The provider application password, 8 to 128 characters. Spaces are removed. Quotes, `$`, `\` and backticks are refused. Never the account password. |
| From             | An e-mail address. `G_WATCHDOG_MAIL` receives the same address.                                                                                    |
| Activer l'envoi des alertes vers Google Drive (Y/N). | `Y` or `y` enables the copy. `N`, `n` or `non` disables it. Enabled asks for the remote name and the folder, then runs `rclone config`. The token stays on the machine, mode 600. Disabled does not install rclone. |
| Distant          | Remote name. Letters, digits or a hyphen, 1 to 32 characters. Asked only when the copy is enabled.                                                  |
| Dossier          | Remote folder. No `..` and no local absolute path. Asked only when the copy is enabled.                                                             |
| Mode test        | `0` or `1`.                                                                                                                                         |

## Installed software and services

The installation places the packages and services below.

| Name                                            | Role                                                                                                                     |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| openssh-server                                  | SSH server. Root login is refused. Password authentication stays enabled. `PasswordAuthentication yes`. `AllowTcpForwarding no`. `AllowAgentForwarding no`. |
| ufw                                             | Host firewall.                                                                                                           |
| usbguard, usbguard-notifier                     | Allows devices already plugged in, plus keyboards, mice and hubs. A new storage device waits for a desktop confirmation. |
| fail2ban                                        | Bans repeated authentication failures.                                                                                   |
| auditd                                          | Writes audit rules for selected paths.                                                                                   |
| rkhunter                                        | Rootkit and file-property check.                                                                                         |
| chkrootkit                                      | Rootkit check. The binary is `/usr/sbin/chkrootkit`.                                                                     |
| clamav                                          | On-access scan and boot scan.                                                                                            |
| crowdsec                                        | Local security decisions.                                                                                                |
| debsums                                         | Checksums of packaged files.                                                                                             |
| unbound                                         | Local DNS resolver on `127.0.0.1` and `::1`, port 53.                                                                    |
| apparmor                                        | Distribution profiles. `service/apparmor/userns.sh` removes an hfu profile that is not shipped.                          |
| aide                                            | File integrity database `/var/lib/aide/aide.db`.                                                                         |
| unattended-upgrades                             | Security origins. `Automatic-Reboot` is `false`.                                                                         |
| postfix                                         | Sends alert mail. Installed only when `G_MAIL_ALERTS=1`.                                                                |
| rclone                                          | Copies an alert file to Google Drive. Installed only when `G_RCLONE_ALERTS=1`.                                          |
| lynis                                           | Hardening audit.                                                                                                         |
| ubuntu-pro-client                               | Attaches the Ubuntu Pro token. A non-LTS release does not enable esm-infra, esm-apps or Livepatch. On an LTS release, a failure to enable them does not stop the installation. |
| acct, sysstat, libpam-pwquality                 | Process accounting, activity stats, password quality.                                                                    |
| rng-tools-debian, haveged                       | Entropy sources.                                                                                                         |
| apt-listchanges, needrestart, apt-show-versions | Package change notices and restart checks.                                                                               |

## 📋 Alert emails

Each alert file is stored under `/opt/liltress-workstation/cron/alerts`.<br/>
The mail follows the `G_LANGUAGE` language.<br/>
Mail leaves only when `G_MAIL_ALERTS=1`.<br/>
A copy leaves for Google Drive only when `G_RCLONE_ALERTS=1`, to the chosen remote and folder.<br/>
Mail is sent only when `G_MAIL_ALERTS=1`, `G_WATCHDOG_MAIL` is set, and `/opt/liltress-workstation/cron/bin/send.sh` is executable.<br/>
A clean check does not send mail.<br/>
If a journal line is unknown, do not run the command.<br/>
Keep the mail.

A check that stops before its normal end sends mail.<br/>
The mail names the check.<br/>
It names the signal, or the exit code.

## ▪️ AIDE

The message contains the summary line and an excerpt of the journal, then the note and the command block.<br/>
The message contains a verification block for each finding in the journal, before the command block when that block exists.<br/>
The journal path in the mail is the real file.<br/>
The form is `/opt/liltress-workstation/cron/security_logs/aide-YYYYMMDD-HHMMSS.log`.

```bash
sudo bash /opt/liltress-workstation/bin/aide-refresh-db.sh
```

The command rebuilds the AIDE database from the current disk.<br/>
The success line is `Base de référence AIDE enregistrée.`

## ▪️ chkrootkit

The message contains the summary and the journal excerpt, then the note and the command.<br/>
The message contains a verification block for each finding in the journal, before the command block when that block exists.<br/>
The example below shows the form.<br/>
The mail contains the real path.

```bash
sudo bash /opt/liltress-workstation/bin/chkrootkit-ignore-log.sh '/opt/liltress-workstation/cron/security_logs/chkrootkit-YYYYMMDD-HHMMSS.log'
```

The command records the lines of that journal in `/opt/liltress-workstation/cron/chkrootkit.local.ignore`.<br/>
The success line is `Aucune nouvelle détection à enregistrer.` when there is nothing new, or `N détection(s) enregistrée(s) dans /opt/liltress-workstation/cron/chkrootkit.local.ignore`.

A confirmed detection moves the file and attaches the restore command instead.<br/>
The record command stays only when no confirmed file was moved.

## ▪️ debsums

The message contains the summary and the journal excerpt.<br/>
It does not add a command block.<br/>
The check reinstalls each package still reported with `apt-get install --reinstall`.<br/>
The mail names each package restored.<br/>
The success line is `La somme correspond.`

A package whose checksum stays different, or whose reinstall fails, stays in the mail.<br/>
A line for `/var/lib/rkhunter/db/mirrors.dat` is removed before that reinstall only when its current SHA-256 equals `/opt/liltress-workstation/cron/rkhunter-mirrors.sha256`.<br/>
A changed line under `/usr/lib/*/perl-base/unicore/` of the `perl-base` package is removed before that reinstall.<br/>
The file shipped by Ubuntu does not match that package checksum.

## ▪️ ClamAV on access

The message contains the signature, the file name, the original path and the quarantine path, then the note and one restore command per moved file.<br/>
The same journal gives the time, the detection type, the actions applied and a short recommendation.<br/>
A file whose name matches `.clamav-quarantine-lock.*` does not send mail.<br/>
The script exits 0 before the journal and before `log_alert`.

```bash
sudo bash /opt/liltress-workstation/bin/quarantine-restore.sh <id>
```

The example shows the form.<br/>
The mail contains the real identifier.<br/>
The command puts that file back in its original place.<br/>
The success line is `fichier remis en place`.<br/>
The registry is `/opt/liltress-workstation/cron/quarantine.registry`.

## ▪️ ClamAV boot scan

The message contains the summary and the journal excerpt.<br/>
When a file was moved, the mail adds one restore command per file.<br/>
The command is the same as in the on-access mail.<br/>
The journal form is `/opt/liltress-workstation/cron/security_logs/clamav-YYYYMMDD-HHMMSS.log`.<br/>
An unreadable file, with no `FOUND` line, does not send mail.<br/>
The lines `Known viruses` and `Infected files` are not copied into the mail.<br/>
A `clamscan` process stopped by a signal sends mail.<br/>
The mail names the signal and each unread file.<br/>
The other files of the pass are scanned.<br/>
Two crashes in a row stop the ClamAV pass.<br/>
The mail then says that the remaining files were not read.

## ▪️ ClamAV idle scan

The message contains the summary and the journal excerpt.<br/>
When a file was moved, the mail adds one restore command per file.<br/>
The command is the same as in the on-access mail.<br/>
A signature and a path already recorded in `/opt/liltress-workstation/cron/scan-skip.seen` do not send mail again.<br/>
A `clamscan` process stopped by a signal sends mail.<br/>
The mail names the signal and each unread file.<br/>
The other files of the pass are scanned.<br/>
Two crashes in a row stop the ClamAV pass.<br/>
The mail then says that the remaining files were not read.<br/>
The stamp stays in place.<br/>
The journal form is `/opt/liltress-workstation/cron/security_logs/idle-scan-YYYYMMDD-HHMMSS.log`.

## ▪️ rkhunter

The warning mail contains the summary and the journal excerpt, then the note and the command block.<br/>
The message contains a verification block for each finding in the journal, before the command block when that block exists.<br/>
The mail `mirrors.dat modifié hors rkhunter --update` does not add that block.<br/>
An error mail does not either.<br/>
The journal form is `/opt/liltress-workstation/cron/security_logs/rkhunter-YYYYMMDD-HHMMSS.log`.

```bash
sudo bash /opt/liltress-workstation/bin/rkhunter-refresh-db.sh
```

The command recalculates the rkhunter property database from the current disk.<br/>
The success line is `Base de propriétés rkhunter enregistrée.`<br/>
A confirmed detection moves the file and attaches the restore command instead.<br/>
The recalculation command stays only when no confirmed file was moved.<br/>
The files in `/dev/shm` and the socket `/dev/log` are allowed in `rkhunter.conf.local`.<br/>
They do not produce the warning `Suspicious file types found in /dev`.<br/>
The excerpt keeps the warning line and the paths that follow it.

## ▪️ Reboot notice

The message is `Un redémarrage est utile. La machine n'a pas été redémarrée.`<br/>
This mail does not add a command block.<br/>
The same set of packages does not send mail again.<br/>
A game that is running skips the mail and leaves the stamp unchanged.<br/>
The script does not reboot the machine.<br/>
The journal form is `/opt/liltress-workstation/cron/security_logs/reboot-notice-YYYYMMDD-HHMMSS.log`.

## 📋 Commands after installation

Run these commands from the source directory (`/opt/liltress-workstation/src` after the curl installer, or the clone directory).

## ▪️ liltress check

```bash
sudo ./liltress check
```

Checks `global.conf` and `secrets.conf`.<br/>
The success line is `Configuration conforme`.<br/>

## ▪️ liltress run

```bash
sudo ./liltress run
```

Starts the installation from the prepared files.<br/>
The installer refuses to start when the check does not pass.

## ▪️ verify/alerts.sh

```bash
sudo bash verify/alerts.sh
```

Checks the chain timer, the deferred timer, on-access ClamAV, and the mail path.<br/>
Without `--no-send`, a probe is sent when alerts are enabled.<br/>
The subject ends with `Contrôle`.<br/>
The success line is `Résultat : OK`.

```bash
sudo bash verify/alerts.sh --no-send
```

## ▪️ verify/workstation.sh

```bash
sudo bash verify/workstation.sh "$PWD"
```

Runs the workstation check.<br/>
The closing line has the form `Check : N OK / N WARN / N FAIL`.<br/>
The same pass checks SSH forwarding, the SSH firewall rule, USBGuard, the sudo timeout and `w-reboot-notice.timer`.

## ▪️ Check after boot

```bash
sudo bash /opt/liltress-workstation/bin/boot-check.sh
```

Checks the boot security services and the three passes of this session.<br/>
The success line is `Contrôle de démarrage : OK`.<br/>
A pass still running prints `Contrôle de démarrage : en cours` and exits with code 1.<br/>
A gap prints `Contrôle de démarrage : écarts` and exits with code 1.

## ▪️ liltress lynis

```bash
sudo ./liltress lynis
```

Runs `lynis audit system --quick --no-colors` and writes the report under `<source>/log/lynis-<stamp>/`.<br/>
`G_LYNIS_MIN_SCORE` is 80.<br/>
`verify/workstation.sh` accepts a `hardening_index` greater than or equal to that score.

## ▪️ AIDE baseline

```bash
sudo bash /opt/liltress-workstation/bin/aide-refresh-db.sh
```

Rebuilds `/var/lib/aide/aide.db`.<br/>
The success line is `Base de référence AIDE enregistrée.`

## ▪️ rkhunter mirror stamp

```bash
sudo bash /opt/liltress-workstation/cron/bin/record-mirrors.sh save
```

Writes the SHA-256 of `/var/lib/rkhunter/db/mirrors.dat` to `/opt/liltress-workstation/cron/rkhunter-mirrors.sha256` mode `600`.<br/>
`rkhunter.sh` records that stamp only after an `rkhunter --update` that returns 0 or 2.

## ▪️ Excluded scan paths

```bash
sudo bash /opt/liltress-workstation/bin/scan-skip.sh list
sudo bash /opt/liltress-workstation/bin/scan-skip.sh add $HOME/.cache/exemple
sudo bash /opt/liltress-workstation/bin/scan-skip.sh del $HOME/.cache/exemple
```

The list file is `/opt/liltress-workstation/src/config/clamav/scan-skip.paths`.<br/>
A list already present stays in place when the installer runs again.<br/>
A list still in `/opt/liltress-workstation/cron/scan-skip.paths` is copied once, when the new file is still the template.

| Action       | Printed line                        |
| ------------ | ----------------------------------- |
| `list`       | one accepted path per line          |
| `add`        | `Chemin ajouté : <path>`            |
| already there | `Ce chemin est déjà exclu : <path>` |
| `del`        | `Chemin retiré : <path>`            |
| refused      | `Chemin refusé : <path>`            |

A refused path leaves the file unchanged.<br/>
The command rewrites `/etc/clamav/clamd.conf`.<br/>
It restarts `clamav-daemon`, then `clamav-clamonacc.service` or `clamonacc.service`, when the exclusion block changes.<br/>
