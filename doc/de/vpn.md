# Tunnel

## 📋 Tunnel

Die Installation des Rechners startet ohne VPN. Das Netz bleibt direkt.<br/>
Der Import ist `sudo ./liltress vpn import openvpn <Marke> <Name> <Archiv oder Ordner>` oder `sudo ./liltress vpn import wireguard <Marke> <Name> <Archiv oder Ordner>`.<br/>
Die Marke ist Pflicht. Eine Datei ohne Marke wird abgelehnt.<br/>
Das erste gültige Profil schärft den Killswitch.<br/>
Ein ungültiger Ordner wird nicht hinzugefügt. Ist er der erste, bleibt der Killswitch aus.<br/>
Ein späterer Import, während der Modus aus ist, schärft den Killswitch nicht erneut.<br/>
<br/>
`sudo ./liltress vpn mode on` schärft den Killswitch und öffnet ein gültiges Profil.<br/>
Ohne gültiges Profil wird dieser Befehl abgelehnt und der Killswitch bleibt aus.<br/>
`sudo ./liltress vpn mode off` entschärft den Killswitch und stellt das direkte Netz her. Die Profilordner bleiben.<br/>
<br/>
`sudo ./liltress vpn switch <Name>` wechselt zu einem anderen gültigen Profil. Der Killswitch bleibt während des Wechsels scharf.<br/>
Ein fehlgeschlagener Wechsel stellt das direkte Internet nicht her und entfernt kein Profil.<br/>
<br/>
Ein Profil, das schon geantwortet hat und dann drei Versuche von zehn Sekunden verfehlt, wird entfernt.<br/>
Nimmt diese Entfernung das letzte Profil, wird das Netz direkt und der Killswitch wird entschärft.<br/>
Die Alarmmail geht vor dieser Entschärfung hinaus.<br/>
`sudo ./liltress vpn rm <Name>` entfernt ein Profil. Das Entfernen des letzten entschärft den Killswitch.<br/>
Ein aktives Profil bleibt, solange ein anderes Profil existiert.<br/>
Ein Fehlschlag von `sudo ./liltress vpn test <Name>` lässt den Ordner stehen.<br/>
<br/>
Jedes WireGuard-VPN ist ein Ordner `/opt/liltress-workstation/vpn/wireguard/<Name>/`.<br/>
Jedes OpenVPN-VPN ist ein Ordner `/opt/liltress-workstation/vpn/openvpn/<Name>/`.<br/>
Die Datei `meta` in diesem Ordner trägt die Marke.<br/>
Das Register ist `/opt/liltress-workstation/vpn/vpn.json`.<br/>
<br/>
`sudo ./liltress vpn list` zeigt den Namen, das Protokoll, die Marke und die Daten.<br/>
`sudo ./liltress vpn test <Name>` prüft erneut.<br/>
SSH geht nicht durch den Tunnel.<br/>
<br/>
Die Umgehungsdatei enthält ein Präfix je Zeile oder eine einzige Zeile in Klammern.<br/>
Das Beispiel ist `[192.168.1.0/24, 200.200.200.0/24]`.<br/>
Unbound wird nach einem Moduswechsel oder einer Umschaltung neu gestartet.<br/>
Globales IPv6 wird blockiert, wenn der Tunnel kein IPv6 hat.<br/>
Ein öffentlicher Bereich in der Datei geht im Klartext hinaus.<br/>
Nach dem Entfernen des letzten Profils schärft das nächste gültige Profil den Killswitch wieder.

## 📋 Importformen

Das Archiv oder der Ordner enthält genau die Dateinamen der Marke.<br/>
Eine zusätzliche Datei, eine fehlende Datei oder die Datei des anderen Protokolls wird abgelehnt.<br/>
Die Dateien liegen in der Wurzel. Es gibt keinen Unterordner.<br/>
Steht das Wort REPLACE noch da, stoppt der Import vor dem Versuch.<br/>
Das Beispiel nutzt `203.0.113.10`. Es kann keinen Tunnel öffnen.<br/>
<br/>
`auth.txt` enthält zwei Zeilen: den Namen, dann das Geheimnis.<br/>
Ein Zertifikat im Dateiinhalt bleibt im Profil.<br/>
Ein daneben benanntes Zertifikat wird unter diesem Namen kopiert.<br/>
Die `up`- und `down`-Skripte des Anbieters werden nicht kopiert.<br/>
Der DNS des Anbieters wird nicht benutzt. Unbound bleibt der Resolver.<br/>
Das erste `remote` ist der geöffnete Server.

## ▪️ NordVPN

Nur OpenVPN.<br/>
Nord liefert eine `.ovpn`-Datei. Die Zertifikate stehen in der Datei.<br/>
`auth.txt`: der Dienstname, dann das Dienstpasswort. Die Konto-E-Mail wird abgelehnt.<br/>
WireGuard und NordLynx werden abgelehnt.<br/>
Ersetzen Sie REPLACE in `config.ovpn` und in beiden Zeilen von `auth.txt`.<br/>
Das Beispiel ist [nordvpn.zip](../examples/nordvpn.zip).<br/>
`sudo ./liltress vpn import openvpn nordvpn nord-fr /chemin/nordvpn.zip`

## ▪️ ExpressVPN

Nur OpenVPN.<br/>
ExpressVPN liefert eine `.ovpn`-Datei von der Seite für die manuelle Konfiguration. Die Zertifikate stehen in der Datei.<br/>
`auth.txt`: der Name und das Passwort von dieser Seite.<br/>
WireGuard und Lightway werden abgelehnt.<br/>
Ersetzen Sie REPLACE in `config.ovpn` und in beiden Zeilen von `auth.txt`.<br/>
Das Beispiel ist [expressvpn.zip](../examples/expressvpn.zip).<br/>
`sudo ./liltress vpn import openvpn expressvpn express-fr /chemin/expressvpn.zip`

## ▪️ Surfshark

OpenVPN oder WireGuard.<br/>
OpenVPN: `config.ovpn`, Zertifikate in der Datei oder daneben benannt, und `auth.txt` mit dem erzeugten Namen und Geheimnis. Die Seiten-E-Mail wird abgelehnt.<br/>
WireGuard: nur `config.conf`, nach der Erzeugung des Schlüsselpaars. Kein `auth.txt`.<br/>
Die Datei des anderen Protokolls wird abgelehnt.<br/>
Ersetzen Sie REPLACE in jeder Datei des gewählten Archivs.<br/>
Das OpenVPN-Beispiel ist [surfshark-openvpn.zip](../examples/surfshark-openvpn.zip).<br/>
Das WireGuard-Beispiel ist [surfshark-wireguard.zip](../examples/surfshark-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn surfshark surf-fr /chemin/surfshark-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard surfshark surf-fr /chemin/surfshark-wireguard.zip`

## ▪️ Proton VPN

OpenVPN oder WireGuard.<br/>
OpenVPN: `config.ovpn` für Linux, Zertifikate in der Datei, und `auth.txt` mit dem OpenVPN-Namen, dann dem OpenVPN-Geheimnis. Das Postfachpasswort wird abgelehnt.<br/>
WireGuard: nur `config.conf`. Kein `auth.txt`.<br/>
Die Datei des anderen Protokolls wird abgelehnt.<br/>
Ersetzen Sie REPLACE in jeder Datei des gewählten Archivs.<br/>
Das OpenVPN-Beispiel ist [protonvpn-openvpn.zip](../examples/protonvpn-openvpn.zip).<br/>
Das WireGuard-Beispiel ist [protonvpn-wireguard.zip](../examples/protonvpn-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn protonvpn proton-fr /chemin/protonvpn-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard protonvpn proton-fr /chemin/protonvpn-wireguard.zip`

## ▪️ CyberGhost

Nur OpenVPN.<br/>
Der Ordner enthält `openvpn.ovpn`, `ca.crt`, `client.crt`, `client.key` und `auth.txt`.<br/>
`openvpn.ovpn` hat `auth-user-pass` ohne Pfad, dann `ca ca.crt`, `cert client.crt` und `key client.key`.<br/>
`auth.txt`: der erzeugte Name, dann das erzeugte Passwort. Die Kontoanmeldung wird abgelehnt.<br/>
WireGuard wird abgelehnt. Fehlt eines der drei Zertifikate, wird abgelehnt.<br/>
Ersetzen Sie REPLACE in `openvpn.ovpn`, in jedem Zertifikat und in beiden Zeilen von `auth.txt`.<br/>
Das Beispiel ist [cyberghost.zip](../examples/cyberghost.zip).<br/>
`sudo ./liltress vpn import openvpn cyberghost cyberghost-fr /chemin/cyberghost.zip`

## ▪️ Private Internet Access

Nur OpenVPN.<br/>
Der Ordner enthält `config.ovpn` und `auth.txt`.<br/>
`auth.txt`: der Name `p` mit den Ziffern, dann das Passwort desselben Zugangs.<br/>
Nennt `config.ovpn` `ca` oder `crl-verify`, liegen diese Dateien im Ordner unter dem genannten Namen.<br/>
Das Beispiel hat die Zertifikate in `config.ovpn`.<br/>
WireGuard wird abgelehnt. Ein SOCKS-Name wird abgelehnt.<br/>
Ersetzen Sie REPLACE in `config.ovpn` und in beiden Zeilen von `auth.txt`.<br/>
Das Beispiel ist [pia.zip](../examples/pia.zip).<br/>
`sudo ./liltress vpn import openvpn pia pia-fr /chemin/pia.zip`

## ▪️ Mullvad

Nur WireGuard.<br/>
Der Ordner enthält `config.conf`. Kein `auth.txt`.<br/>
Die Kontonummer dient dazu, die Datei bei Mullvad zu holen. Der Import verlangt `config.conf`.<br/>
OpenVPN wird abgelehnt.<br/>
Ersetzen Sie REPLACE in den Zeilen PrivateKey, Address, PublicKey, Endpoint und AllowedIPs.<br/>
Das Beispiel ist [mullvad.zip](../examples/mullvad.zip).<br/>
`sudo ./liltress vpn import wireguard mullvad mullvad-se /chemin/mullvad.zip`

## ▪️ PureVPN

OpenVPN oder WireGuard.<br/>
OpenVPN: `config.ovpn`, die Dateien `ca`, `cert` und `key`, wenn sie genannt sind, und `auth.txt` mit dem VPN-Namen, dann dem VPN-Geheimnis aus dem Mitgliederbereich. Die E-Mail wird abgelehnt.<br/>
WireGuard: nur `config.conf`. Kein `auth.txt`.<br/>
Eine WireGuard-Datei, die nicht innerhalb von dreißig Minuten aktiviert wird, scheitert am Versuch. Das Profil wird nicht veröffentlicht.<br/>
Die Datei des anderen Protokolls wird abgelehnt.<br/>
Ersetzen Sie REPLACE in jeder Datei des gewählten Archivs.<br/>
Das OpenVPN-Beispiel ist [purevpn-openvpn.zip](../examples/purevpn-openvpn.zip).<br/>
Das WireGuard-Beispiel ist [purevpn-wireguard.zip](../examples/purevpn-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn purevpn pure-fr /chemin/purevpn-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard purevpn pure-fr /chemin/purevpn-wireguard.zip`

## ▪️ IPVanish

Nur OpenVPN.<br/>
Der Ordner enthält `config.ovpn` und `auth.txt`. Die Zertifikate stehen in der Datei oder daneben, wenn sie genannt sind.<br/>
`auth.txt`: der Kontoname, dann das Kontopasswort.<br/>
WireGuard wird abgelehnt.<br/>
Ersetzen Sie REPLACE in `config.ovpn` und in beiden Zeilen von `auth.txt`.<br/>
Das Beispiel ist [ipvanish.zip](../examples/ipvanish.zip).<br/>
`sudo ./liltress vpn import openvpn ipvanish ipvanish-fr /chemin/ipvanish.zip`

## ▪️ Windscribe

OpenVPN oder WireGuard.<br/>
OpenVPN: `config.ovpn` und `auth.txt`. `tls-auth` steht in der Datei oder daneben, wenn es genannt ist.<br/>
`auth.txt`: Name und Passwort von Get Credentials. Die Website-Anmeldung wird abgelehnt.<br/>
WireGuard: nur `config.conf`, mit Ort, Port und Schlüsselpaar. Kein `auth.txt`.<br/>
IKEv2 wird abgelehnt.<br/>
Der WireGuard-Generator ist bei Windscribe eine kostenpflichtige Option.<br/>
Ersetzen Sie REPLACE in jeder Datei des gewählten Archivs.<br/>
Das OpenVPN-Beispiel ist [windscribe-openvpn.zip](../examples/windscribe-openvpn.zip).<br/>
Das WireGuard-Beispiel ist [windscribe-wireguard.zip](../examples/windscribe-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn windscribe windscribe-fr /chemin/windscribe-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard windscribe windscribe-fr /chemin/windscribe-wireguard.zip`
