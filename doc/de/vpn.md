# Tunnel

## 📋 Tunnel

Der Rechner bleibt im direkten Netz, bis ein Profil bestätigt ist.<br/>
Der Import ist `sudo ./liltress vpn import wireguard <Name> <Datei>` oder `sudo ./liltress vpn import openvpn <Name> <Datei>`.<br/>
Ein Import, der antwortet, schaltet den VPN-Modus ein. Der Killswitch bleibt scharf bis `sudo ./liltress vpn mode off`.<br/>
`sudo ./liltress vpn mode on` schaltet ihn wieder ein, wenn ein Profil gültig ist.<br/>
Jedes WireGuard-VPN ist ein Ordner `/opt/liltress-workstation/vpn/wireguard/<Name>/`.<br/>
Jedes OpenVPN-VPN ist ein Ordner `/opt/liltress-workstation/vpn/openvpn/<Name>/`.<br/>
Der Ordner behält die Konfiguration und die Zertifikat- oder Auth-Dateien, die sie nennt.<br/>
Das Register ist `/opt/liltress-workstation/vpn/vpn.json`.<br/>
`sudo ./liltress vpn list` zeigt die Profile und ihre Daten. `sudo ./liltress vpn test <Name>` prüft eines erneut.<br/>
`sudo ./liltress vpn rm <Name>` entfernt ein Profil, das nicht offen ist.<br/>
`sudo ./liltress vpn switch <Name>` wechselt zu einem anderen gültigen Profil.<br/>
SSH geht nicht durch den Tunnel.<br/>
Wenn kein gültiges Profil mehr antwortet, startet der Rechner trotzdem und der Killswitch bleibt scharf.<br/>
Die Umgehungsdatei hat ein Präfix pro Zeile, oder eine Zeile in Klammern.<br/>
Das Beispiel ist `[192.168.1.0/24, 200.200.200.0/24]`.<br/>
Ein fehlgeschlagener `vpn switch` stellt das direkte Internet nicht wieder her.<br/>
Unbound wird nach einem Moduswechsel oder einer Umschaltung neu gestartet.<br/>
Globales IPv6 ist gesperrt, wenn der Tunnel kein IPv6 hat.<br/>
Ein öffentlicher Bereich in der Datei geht im Klartext hinaus.

## 📋 Importformen

Der Import kopiert die angegebene Datei und jede Datei, die sie im selben Ordner nennt.<br/>
Ein Zertifikat im Dateitext bleibt im Profil.<br/>
Das erste `remote` ist der geöffnete Server.<br/>
Die `up`- und `down`-Skripte des Anbieters werden nicht kopiert.<br/>
Der DNS des Anbieters wird nicht benutzt. Unbound bleibt der Resolver.<br/>
`auth.txt` hat zwei Zeilen: den Namen, dann das Geheimnis.<br/>
Die Datei liegt vor dem Import neben der `.ovpn`, oder sie wird leer im Profil angelegt.<br/>
Solange diese zwei Zeilen fehlen, ist das Profil importiert und wird nicht geprüft.<br/>
`sudo ./liltress vpn test <Name>` startet die Prüfung, sobald die Datei gefüllt ist.

## ▪️ NordVPN

OpenVPN. Eine `.ovpn` von der Seite der manuellen Konfiguration.<br/>
Die Zertifikate stehen in der Datei.<br/>
`auth.txt`: der Dienstname, dann das Dienstgeheimnis.<br/>
NordLynx ist keine importierbare WireGuard-Datei.<br/>
`sudo ./liltress vpn import openvpn nord-de datei.ovpn`

## ▪️ ExpressVPN

OpenVPN. Eine `.ovpn` der manuellen Konfiguration.<br/>
Die Zertifikate stehen in der Datei.<br/>
`auth.txt`: der OpenVPN-Name und das Geheimnis von dieser Seite.<br/>
Lightway wird nicht importiert.<br/>
`sudo ./liltress vpn import openvpn express-de datei.ovpn`

## ▪️ Surfshark

OpenVPN oder WireGuard.<br/>
OpenVPN: eine `.ovpn`, Zertifikate in der Datei oder daneben genannt, und `auth.txt` mit Name und Geheimnis der manuellen Einrichtung.<br/>
WireGuard: eine `.conf` des Generators, ein privater Schlüssel, ein Peer, ein Endpunkt.<br/>
`sudo ./liltress vpn import openvpn surf-de datei.ovpn`<br/>
`sudo ./liltress vpn import wireguard surf-de datei.conf`

## ▪️ Proton VPN

WireGuard oder OpenVPN.<br/>
WireGuard: eine `.conf` aus dem Konto.<br/>
OpenVPN: eine `.ovpn`, deren Zertifikate in der Datei stehen.<br/>
`auth.txt`: der OpenVPN-Name des Kontos, dann sein Geheimnis. Das ist nicht das Postfachpasswort.<br/>
`sudo ./liltress vpn import wireguard proton-de datei.conf`

## ▪️ CyberGhost

OpenVPN. Der Ordner enthält `openvpn.ovpn`, `ca.crt`, `client.crt` und `client.key`.<br/>
Die Datei hat `auth-user-pass` ohne Pfad, dann `ca ca.crt`, `cert client.crt` und `key client.key`.<br/>
`auth.txt`: der OpenVPN-Name von CyberGhost, dann das eigene Geheimnis.<br/>
`sudo ./liltress vpn import openvpn cyberghost-de openvpn.ovpn`

## ▪️ Private Internet Access

OpenVPN oder WireGuard.<br/>
OpenVPN: die `.ovpn`, die von `ca` genannte Datei, die von `crl-verify` genannte Datei, wenn sie vorkommt, und `auth.txt`.<br/>
`auth.txt`: der Name `p` mit den Ziffern des Kontos, dann das erzeugte Geheimnis.<br/>
WireGuard: eine `.conf` aus dem Konto.<br/>
`sudo ./liltress vpn import openvpn pia-de datei.ovpn`

## ▪️ Mullvad

WireGuard oder OpenVPN.<br/>
WireGuard: eine `.conf` aus dem Konto. Keine Authentifizierungsdatei.<br/>
OpenVPN: die `.ovpn` und die Zertifikate, die sie nennt.<br/>
`auth.txt`: die Kontonummer, dann `m`.<br/>
`sudo ./liltress vpn import wireguard mullvad datei.conf`

## ▪️ PureVPN

OpenVPN oder WireGuard.<br/>
OpenVPN: die `.ovpn` und die Dateien `ca`, `cert` und `key`, die sie nennt.<br/>
`auth.txt`: der PureVPN-Name, dann das Geheimnis.<br/>
WireGuard: eine `.conf`.<br/>
`sudo ./liltress vpn import openvpn pure-de datei.ovpn`

## ▪️ IPVanish

OpenVPN. Eine `.ovpn`. Die Zertifikate stehen in der Regel in der Datei.<br/>
`auth.txt`: der Kontoname, dann das Geheimnis.<br/>
`sudo ./liltress vpn import openvpn ipvanish-de datei.ovpn`

## ▪️ Windscribe

OpenVPN oder WireGuard.<br/>
OpenVPN: eine `.ovpn` des manuellen Generators. `tls-auth` steht in der Datei oder daneben, wenn die Datei sie nennt.<br/>
`auth.txt`: der Windscribe-Name, dann das Geheimnis.<br/>
WireGuard: eine `.conf`.<br/>
`sudo ./liltress vpn import openvpn windscribe-de datei.ovpn`
