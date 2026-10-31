<div align="center">

# 🛡️ Liltress Workstation 🛡️

![Ubuntu 26.04 or newer](https://img.shields.io/badge/Ubuntu-26.04%2B-E95420?logo=ubuntu&logoColor=white)
![Workstation](https://img.shields.io/badge/profile-workstation-1f6feb)
![Unbound](https://img.shields.io/badge/DNS-Unbound-0055A4)
![UFW](https://img.shields.io/badge/firewall-UFW-0055A4)
![Security checks](https://img.shields.io/badge/checks-AIDE%20%C2%B7%20ClamAV%20%C2%B7%20Lynis-2ea44f)

Liltress Workstation bereitet einen Ubuntu-Arbeitsplatz 26.04 oder neuer vor.<br/>
Es installiert den lokalen DNS-Resolver, die Firewall und die Sicherheitskontrollen.<br/>
Das bereits angelegte Ubuntu-Konto auf der Maschine wird nicht ersetzt.<br/>
Das Installationsprogramm legt kein zweites Konto an.<br/>

</div>

## 📋 Bevor Sie beginnen

Drei Punkte gehen der Installation voraus: das System, der Zugang und die externen Voraussetzungen.

## ▪️ System

Ubuntu 26.04 oder neuer, einschließlich einer Zwischenversion.<br/>
Eine Neuinstallation ist vorzuziehen.<br/>
Benutzen Sie eine lokale Konsole oder die bereits geöffnete grafische Sitzung.<br/>
Die Maschine braucht Internetzugang.

## ▪️ Zugang

Sie brauchen `sudo` für `./liltress configure`, `./liltress run` und die Kontrollen.

## ▪️ Externe Voraussetzungen

| Bedarf             | Link und Verfahren                                                                                                                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ubuntu-Pro-Token   | Erforderlich. Öffnen Sie [https://ubuntu.com/pro/dashboard](https://ubuntu.com/pro/dashboard) und kopieren Sie das Token. `configure.sh` akzeptiert nur Buchstaben und Ziffern, Länge 6 bis 100, ohne Leerzeichen.                    |
| Anwendungskennwort | Nur wenn Sie die Alarme einschalten. Benutzen Sie das Anwendungskennwort des Mail-Anbieters. Geben Sie nie das Kontokennwort ein. Länge 8 bis 128. Eingegebene Leerzeichen werden entfernt.                                           |
| SMTP-Server        | Nur wenn die Alarme eingeschaltet sind. Form `Host:Port`. Das Beispiel in `configure.sh` ist `smtp-mail.outlook.com:587`. Klammern werden abgelehnt. `swaks` sendet eine Testnachricht. Die Erfolgszeile ist `Essai d'envoi accepté.` |

## 📋 Installation

Der Arbeitsplatz wird durch den Curl-Installer vorbereitet, oder durch einen Klon gefolgt von `sudo ./liltress configure`.

## ▪️ Curl

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git swaks tar
curl -fsSL https://raw.githubusercontent.com/palarchsys/liltress-workstation/main/install.sh | sudo bash
```

## ▪️ Klon

```bash
git clone https://github.com/palarchsys/liltress-workstation
cd liltress-workstation
sudo ./liltress configure
```

## Aktion von configure.sh

`sudo ./liltress configure` stellt die folgenden Fragen, schreibt `global.conf` mit Modus `644` und `secrets.conf` mit Modus `600` als root und startet dann `script/run.sh`.<br/>
`secrets.conf` bleibt auf der Maschine. Kopieren Sie es nicht in eine Nachricht, ein Ticket oder ein Repository.<br/>
Die erste Frage wählt die Sprache.<br/>
Der Wert ist `G_LANGUAGE`.<br/>
Die Vorgabe ist Englisch.<br/>

| Frage            | Erwartete Antwort                                                                                                                                                        |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Jeton Ubuntu Pro | Buchstaben und Ziffern, 6 bis 100, ohne Leerzeichen. Erforderlich.                                                                                                       |
| Activer          | `Y` oder `y` schaltet die Post ein. `N`, `n` oder `non` schaltet sie aus. Ausgeschaltet wird Postfix nicht installiert. Jede andere Antwort zeigt `Répondez Y ou N.` |
| Serveur          | `Host:Port`, zum Beispiel `smtp-mail.outlook.com:587`. Ohne Klammern. Nur wenn die Alarme eingeschaltet sind.                                                            |
| Login            | Eine E-Mail-Adresse.                                                                                                                                                     |
| Password         | Das Anwendungskennwort des Anbieters, 8 bis 128 Zeichen. Leerzeichen werden entfernt. Anführungszeichen, `$`, `\` und Backticks werden abgelehnt. Nie das Kontokennwort. |
| From             | Eine E-Mail-Adresse. `G_WATCHDOG_MAIL` erhält dieselbe Adresse.                                                                                                         |
| Activer l'envoi des alertes vers Google Drive (Y/N). | `Y` oder `y` schaltet die Kopie ein. `N`, `n` oder `non` schaltet sie aus. Bei Aktivierung fragt das Programm nach dem Remote-Namen und dem Ordner und startet dann `rclone config`. Das Token bleibt auf der Maschine, Modus 600. Bei Deaktivierung wird rclone nicht installiert. |
| Distant          | Name des Remote. Buchstaben, Ziffern oder Bindestrich, 1 bis 32 Zeichen. Nur wenn die Kopie eingeschaltet ist.                                                            |
| Dossier          | Ordner auf dem Remote. Kein `..` und kein lokaler absoluter Pfad. Nur wenn die Kopie eingeschaltet ist.                                                                  |
| Mode test        | `0` oder `1`.                                                                                                                                                            |

## Installierte Software und Dienste

Die Installation setzt die folgenden Pakete und Dienste.

| Name                                            | Rolle                                                                                                                                              |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| openssh-server                                  | SSH-Server. Root-Anmeldung ist abgelehnt. Kennwortanmeldung bleibt eingeschaltet. `PasswordAuthentication yes`. `AllowTcpForwarding no`. `AllowAgentForwarding no`. |
| ufw                                             | Host-Firewall.                                                                                                                                     |
| usbguard, usbguard-notifier                     | Erlaubt bereits angeschlossene Geräte sowie Tastaturen, Mäuse und Hubs. Ein neuer Datenträger wartet auf eine Bestätigung auf dem Desktop.          |
| fail2ban                                        | Sperrt wiederholte Anmeldefehlschläge.                                                                                                             |
| auditd                                          | Schreibt Audit-Regeln für die gewählten Pfade.                                                                                                     |
| rkhunter                                        | Rootkit- und Dateieigenschaftsprüfung.                                                                                                             |
| chkrootkit                                      | Rootkit-Prüfung. Die Binärdatei ist `/usr/sbin/chkrootkit`.                                                                                        |
| clamav                                          | Prüfung beim Zugriff und Prüfung beim Start.                                                                                                       |
| crowdsec                                        | Lokale Sicherheitsentscheidungen.                                                                                                                  |
| debsums                                         | Prüfsummen der Paketdateien.                                                                                                                       |
| unbound                                         | Lokaler DNS-Resolver auf `127.0.0.1` und `::1`, Port 53.                                                                                           |
| apparmor                                        | Distributionsprofile. `service/apparmor/userns.sh` entfernt ein w-Profil, das nicht geliefert wird.                                              |
| aide                                            | Integritätsbasis `/var/lib/aide/aide.db`.                                                                                                          |
| unattended-upgrades                             | Sicherheitsherkünfte. `Automatic-Reboot` ist `false`.                                                                                              |
| postfix                                         | Sendet die Alarmpost. Installiert nur wenn `G_MAIL_ALERTS=1`.                                                                                     |
| rclone                                          | Kopiert eine Alarmdatei nach Google Drive. Installiert nur wenn `G_RCLONE_ALERTS=1`.                                                               |
| lynis                                           | Härtungsaudit.                                                                                                                                     |
| ubuntu-pro-client                               | Hängt das Ubuntu-Pro-Token an. Außerhalb einer LTS werden esm-infra, esm-apps und Livepatch nicht aktiviert. Auf einer LTS stoppt ein Fehlschlag die Installation nicht. |
| acct, sysstat, libpam-pwquality                 | Prozessabrechnung, Aktivitätsstatistik, Kennwortqualität.                                                                                          |
| rng-tools-debian, haveged                       | Entropiequellen.                                                                                                                                   |
| apt-listchanges, needrestart, apt-show-versions | Hinweise auf Paketänderungen und Neustartprüfungen.                                                                                                |

## 📋 Alarm-E-Mails

Jede Alarmdatei liegt unter `/opt/liltress-workstation/cron/alerts`.<br/>
Die Nachricht folgt der Sprache `G_LANGUAGE`.<br/>
Post geht nur ab, wenn `G_MAIL_ALERTS=1`.<br/>
Eine Kopie geht nur nach Google Drive, wenn `G_RCLONE_ALERTS=1`, zum gewählten Remote und Ordner.<br/>
Die Post geht nur ab, wenn `G_MAIL_ALERTS=1`, wenn `G_WATCHDOG_MAIL` gesetzt ist, und wenn `/opt/liltress-workstation/cron/bin/send.sh` ausführbar ist.<br/>
Eine saubere Kontrolle sendet keine Post.<br/>
Wenn eine Journalzeile unbekannt ist, starten Sie den Befehl nicht.<br/>
Behalten Sie die Post.

Eine Kontrolle, die vor ihrem Ende abbricht, sendet eine Post.<br/>
Die Post nennt die Kontrolle.<br/>
Sie nennt das Signal oder den Exit-Code.

## ▪️ AIDE

Die Nachricht enthält die Zusammenfassungszeile und einen Auszug des Journals, dann den Hinweis und den Befehlsblock.<br/>
Die Nachricht enthält einen Prüfblock für jeden Befund des Journals, vor dem Befehlsblock, wenn dieser Block vorhanden ist.<br/>
Der Journalpfad in der Post ist die echte Datei.<br/>
Die Form ist `/opt/liltress-workstation/cron/security_logs/aide-YYYYMMDD-HHMMSS.log`.

```bash
sudo bash /opt/liltress-workstation/bin/aide-refresh-db.sh
```

Der Befehl baut die AIDE-Basis aus der aktuellen Platte neu auf.<br/>
Die Erfolgszeile ist `Base de référence AIDE enregistrée.`

## ▪️ chkrootkit

Die Nachricht enthält die Zusammenfassung und den Journalauszug, dann den Hinweis und den Befehl.<br/>
Die Nachricht enthält einen Prüfblock für jeden Befund des Journals, vor dem Befehlsblock, wenn dieser Block vorhanden ist.<br/>
Das Beispiel unten zeigt die Form.<br/>
Die Post enthält den echten Pfad.

```bash
sudo bash /opt/liltress-workstation/bin/chkrootkit-ignore-log.sh '/opt/liltress-workstation/cron/security_logs/chkrootkit-YYYYMMDD-HHMMSS.log'
```

Der Befehl zeichnet die Zeilen dieses Journals in `/opt/liltress-workstation/cron/chkrootkit.local.ignore` auf.<br/>
Die Erfolgszeile ist `Aucune nouvelle détection à enregistrer.`, wenn nichts Neues vorliegt, oder `N détection(s) enregistrée(s) dans /opt/liltress-workstation/cron/chkrootkit.local.ignore`.

Eine bestätigte Erkennung verschiebt die Datei und fügt stattdessen den Wiederherstellungsbefehl an.<br/>
Der Aufzeichnungsbefehl bleibt nur, wenn keine bestätigte Datei verschoben wurde.

## ▪️ debsums

Die Nachricht enthält die Zusammenfassung und den Journalauszug.<br/>
Sie fügt keinen Befehlsblock hinzu.<br/>
Die Kontrolle installiert jedes noch gemeldete Paket mit `apt-get install --reinstall` neu.<br/>
Die Post nennt jedes wiederhergestellte Paket.<br/>
Die Erfolgszeile ist `La somme correspond.`

Ein Paket, dessen Summe verschieden bleibt oder dessen Neuinstallation fehlschlägt, bleibt in der Post.<br/>
Eine Zeile für `/var/lib/rkhunter/db/mirrors.dat` wird vor dieser Neuinstallation nur entfernt, wenn ihr aktueller SHA-256 gleich `/opt/liltress-workstation/cron/rkhunter-mirrors.sha256` ist.<br/>
Eine geänderte Zeile unter `/usr/lib/*/perl-base/unicore/` des Pakets `perl-base` wird vor dieser Neuinstallation entfernt.<br/>
Die von Ubuntu gelieferte Datei entspricht nicht der Summe dieses Pakets.

## ▪️ ClamAV beim Zugriff

Die Nachricht enthält die Signatur, den Dateinamen, den Ursprungspfad und den Quarantänepfad, dann den Hinweis und einen Wiederherstellungsbefehl je verschobener Datei.<br/>
Dasselbe Journal nennt die Uhrzeit, den Erkennungstyp, die angewendeten Aktionen und eine kurze Empfehlung.<br/>
Eine Datei, deren Name `.clamav-quarantine-lock.*` entspricht, sendet keine Post.<br/>
Das Skript endet mit 0 vor dem Journal und vor `log_alert`.

```bash
sudo bash /opt/liltress-workstation/bin/quarantine-restore.sh <id>
```

Das Beispiel zeigt die Form.<br/>
Die Post enthält die echte Kennung.<br/>
Der Befehl legt diese Datei an ihren Ursprungsort zurück.<br/>
Die Erfolgszeile ist `fichier remis en place`.<br/>
Das Register ist `/opt/liltress-workstation/cron/quarantine.registry`.

## ▪️ ClamAV-Startprüfung

Die Nachricht enthält die Zusammenfassung und den Journalauszug.<br/>
Wenn eine Datei verschoben wurde, fügt die Post einen Wiederherstellungsbefehl je Datei hinzu.<br/>
Der Befehl ist derselbe wie in der Post beim Zugriff.<br/>
Die Journalform ist `/opt/liltress-workstation/cron/security_logs/clamav-YYYYMMDD-HHMMSS.log`.<br/>
Eine unlesbare Datei ohne Zeile `FOUND` sendet keine Post.<br/>
Die Zeilen `Known viruses` und `Infected files` werden nicht in die Post kopiert.<br/>
Ein durch ein Signal beendeter Prozess `clamscan` sendet eine Post.<br/>
Die Post nennt das Signal und jede ungelesene Datei.<br/>
Die übrigen Dateien des Laufs werden geprüft.<br/>
Zwei Abstürze nacheinander beenden den ClamAV-Lauf.<br/>
Die Post sagt dann, dass die übrigen Dateien nicht gelesen wurden.

## ▪️ Verzögerte ClamAV-Prüfung

Die Nachricht enthält die Zusammenfassung und den Journalauszug.<br/>
Wenn eine Datei verschoben wurde, fügt die Post einen Wiederherstellungsbefehl je Datei hinzu.<br/>
Der Befehl ist derselbe wie in der Post beim Zugriff.<br/>
Eine Signatur und ein Pfad, die bereits in `/opt/liltress-workstation/cron/scan-skip.seen` stehen, senden keine weitere Post.<br/>
Ein durch ein Signal beendeter Prozess `clamscan` sendet eine Post.<br/>
Die Post nennt das Signal und jede ungelesene Datei.<br/>
Die übrigen Dateien des Laufs werden geprüft.<br/>
Zwei Abstürze nacheinander beenden den ClamAV-Lauf.<br/>
Die Post sagt dann, dass die übrigen Dateien nicht gelesen wurden.<br/>
Der Stempel bleibt stehen.<br/>
Die Journalform ist `/opt/liltress-workstation/cron/security_logs/idle-scan-YYYYMMDD-HHMMSS.log`.

## ▪️ rkhunter

Die Warnpost enthält die Zusammenfassung und den Journalauszug, dann den Hinweis und den Befehlsblock.<br/>
Die Nachricht enthält einen Prüfblock für jeden Befund des Journals, vor dem Befehlsblock, wenn dieser Block vorhanden ist.<br/>
Die Post `mirrors.dat modifié hors rkhunter --update` fügt diesen Block nicht hinzu.<br/>
Eine Fehlerpost ebenfalls nicht.<br/>
Die Journalform ist `/opt/liltress-workstation/cron/security_logs/rkhunter-YYYYMMDD-HHMMSS.log`.

```bash
sudo bash /opt/liltress-workstation/bin/rkhunter-refresh-db.sh
```

Der Befehl berechnet die rkhunter-Eigenschaftsbasis aus der aktuellen Platte neu.<br/>
Die Erfolgszeile ist `Base de propriétés rkhunter enregistrée.`<br/>
Eine bestätigte Erkennung verschiebt die Datei und fügt stattdessen den Wiederherstellungsbefehl an.<br/>
Der Neuberechnungsbefehl bleibt nur, wenn keine bestätigte Datei verschoben wurde.<br/>
Die Dateien in `/dev/shm` und der Socket `/dev/log` sind in `rkhunter.conf.local` erlaubt.<br/>
Sie erzeugen nicht die Warnung `Suspicious file types found in /dev`.<br/>
Der Auszug behält die Warnzeile und die Pfade, die ihr folgen.

## ▪️ Neustart-Hinweis

Die Nachricht ist `Un redémarrage est utile. La machine n'a pas été redémarrée.`<br/>
Diese Post fügt keinen Befehlsblock hinzu.<br/>
Derselbe Paketsatz sendet keine weitere Post.<br/>
Ein laufendes Spiel überspringt die Post und lässt den Stempel unverändert.<br/>
Das Skript startet die Maschine nicht neu.<br/>
Die Journalform ist `/opt/liltress-workstation/cron/security_logs/reboot-notice-YYYYMMDD-HHMMSS.log`.

## 📋 Befehle nach der Installation

Starten Sie diese Befehle aus dem Quellverzeichnis (`/opt/liltress-workstation/src` nach dem Curl-Installer, oder das Klonverzeichnis).

## ▪️ liltress check

```bash
sudo ./liltress check
```

Prüft `global.conf` und `secrets.conf`.<br/>
Die Erfolgszeile ist `Configuration conforme`.<br/>

## ▪️ liltress run

```bash
sudo ./liltress run
```

Startet die Installation aus den vorbereiteten Dateien.<br/>
Das Installationsprogramm verweigert den Start, wenn die Prüfung nicht besteht.

## ▪️ verify/alerts.sh

```bash
sudo bash verify/alerts.sh
```

Prüft den Ketten-Timer, den verzögerten Timer, ClamAV beim Zugriff und den Postpfad.<br/>
Ohne `--no-send` geht eine Sonde ab, wenn die Alarme eingeschaltet sind.<br/>
Der Betreff endet mit `Contrôle`.<br/>
Die Erfolgszeile ist `Résultat : OK`.

```bash
sudo bash verify/alerts.sh --no-send
```

## ▪️ verify/workstation.sh

```bash
sudo bash verify/workstation.sh "$PWD"
```

Startet die Prüfung des Arbeitsplatzes.<br/>
Die Abschlusszeile hat die Form `Check : N OK / N WARN / N FAIL`.<br/>
Derselbe Lauf prüft die SSH-Weiterleitung, die SSH-Firewall-Regel, USBGuard, die sudo-Frist und `w-reboot-notice.timer`.

## ▪️ Prüfung nach dem Start

```bash
sudo bash /opt/liltress-workstation/bin/boot-check.sh
```

Prüft die Sicherheitsdienste des Starts und die drei Läufe dieser Sitzung.<br/>
Die Erfolgszeile ist `Contrôle de démarrage : OK`.<br/>
Ein noch laufender Lauf zeigt `Contrôle de démarrage : en cours` und endet mit Code 1.<br/>
Eine Abweichung zeigt `Contrôle de démarrage : écarts` und endet mit Code 1.

## ▪️ liltress lynis

```bash
sudo ./liltress lynis
```

Startet `lynis audit system --quick --no-colors` und schreibt den Bericht unter `<source>/log/lynis-<stamp>/`.<br/>
`G_LYNIS_MIN_SCORE` ist 80.<br/>
`verify/workstation.sh` akzeptiert einen `hardening_index` größer oder gleich diesem Schwellenwert.

## ▪️ AIDE-Basis

```bash
sudo bash /opt/liltress-workstation/bin/aide-refresh-db.sh
```

Baut `/var/lib/aide/aide.db` neu auf.<br/>
Die Erfolgszeile ist `Base de référence AIDE enregistrée.`

## ▪️ rkhunter-Spiegelstempel

```bash
sudo bash /opt/liltress-workstation/cron/bin/record-mirrors.sh save
```

Schreibt den SHA-256 von `/var/lib/rkhunter/db/mirrors.dat` nach `/opt/liltress-workstation/cron/rkhunter-mirrors.sha256` mit Modus `600`.<br/>
`rkhunter.sh` zeichnet diesen Stempel nur nach einem `rkhunter --update` auf, das 0 oder 2 zurückgibt.

## ▪️ Vom Scan ausgeschlossene Pfade

```bash
sudo bash /opt/liltress-workstation/bin/scan-skip.sh list
sudo bash /opt/liltress-workstation/bin/scan-skip.sh add $HOME/.cache/exemple
sudo bash /opt/liltress-workstation/bin/scan-skip.sh del $HOME/.cache/exemple
```

Die Listendatei ist `/opt/liltress-workstation/src/config/clamav/scan-skip.paths`.<br/>
Eine bereits vorhandene Liste bleibt, wenn das Installationsprogramm erneut läuft.<br/>
Eine Liste, die noch in `/opt/liltress-workstation/cron/scan-skip.paths` liegt, wird einmal kopiert, wenn die neue Datei noch die Vorlage ist.

| Aktion       | Angezeigte Zeile                    |
| ------------ | ----------------------------------- |
| `list`       | ein akzeptierter Pfad je Zeile      |
| `add`        | `Chemin ajouté : <path>`            |
| schon vorhanden | `Ce chemin est déjà exclu : <path>` |
| `del`        | `Chemin retiré : <path>`            |
| abgelehnt    | `Chemin refusé : <path>`            |

Ein abgelehnter Pfad lässt die Datei unverändert.<br/>
Der Befehl schreibt `/etc/clamav/clamd.conf` neu.<br/>
Er startet `clamav-daemon` neu, dann `clamav-clamonacc.service` oder `clamonacc.service`, wenn der Ausschlussblock sich ändert.<br/>
