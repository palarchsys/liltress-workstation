# Tunnel

## 📋 Tunnel

Le poste reste en clair tant qu'aucun profil n'est validé.<br/>
L'import est `sudo ./liltress vpn import wireguard <nom> <fichier>` ou `sudo ./liltress vpn import openvpn <nom> <fichier>`.<br/>
Un import qui répond passe en mode VPN. Le killswitch reste armé jusqu'à `sudo ./liltress vpn mode off`.<br/>
`sudo ./liltress vpn mode on` le réactive lorsqu'un profil est valide.<br/>
<br/>
Chaque VPN WireGuard est un dossier `/opt/liltress-workstation/vpn/wireguard/<nom>/`.<br/>
Chaque VPN OpenVPN est un dossier `/opt/liltress-workstation/vpn/openvpn/<nom>/`.<br/>
Ce dossier garde la configuration et les fichiers certificat ou auth qu'elle cite.<br/>
Le registre est `/opt/liltress-workstation/vpn/vpn.json`.<br/>
<br/>
`sudo ./liltress vpn list` affiche les VPN et leurs dates. `sudo ./liltress vpn test <nom>` en refait l'essai.<br/>
`sudo ./liltress vpn rm <nom>` retire un profil qui n'est pas ouvert.<br/>
`sudo ./liltress vpn switch <nom>` passe à un autre profil valide.<br/>
SSH ne passe pas par le tunnel.<br/>
<br/>
Si plus aucun profil valide ne répond, la machine démarre quand même et le killswitch reste armé.<br/>
Le fichier de contournement contient un préfixe par ligne, ou une seule ligne entre crochets.<br/>
L'exemple est `[192.168.1.0/24, 200.200.200.0/24]`.<br/>
Un échec de `vpn switch` ne rend pas Internet direct.<br/>
<br/>
Unbound est relancé après un changement de mode ou une bascule.<br/>
L'IPv6 global est bloqué lorsque le tunnel n'a pas d'IPv6.<br/>
Une plage publique écrite dans le fichier sort en clair.

## 📋 Formes d'import

L'import copie le fichier donné et chaque fichier qu'il nomme dans le même dossier.<br/>
Un certificat écrit dans le fichier reste dans le profil.<br/>
Le premier `remote` est le serveur ouvert.<br/>
Les scripts `up` et `down` du fournisseur ne sont pas copiés.<br/>
Le DNS du fournisseur n'est pas utilisé. Unbound reste le résolveur.<br/>
<br/>
`auth.txt` contient deux lignes : le nom, puis le secret.<br/>
Il est à côté du `.ovpn` avant l'import, ou il est créé vide dans le profil.<br/>
Tant que ces deux lignes manquent, le profil est importé et n'est pas essayé.<br/>
`sudo ./liltress vpn test <nom>` lance l'essai une fois le fichier rempli.

## ▪️ NordVPN

OpenVPN. Un `.ovpn` de la page de configuration manuelle.<br/>
Les certificats sont dans le fichier.<br/>
`auth.txt` : le nom de service, puis le secret de service.<br/>
NordLynx n'est pas un fichier WireGuard importable.<br/>
`sudo ./liltress vpn import openvpn nord-fr fichier.ovpn`

## ▪️ ExpressVPN

OpenVPN. Un `.ovpn` de la configuration manuelle.<br/>
Les certificats sont dans le fichier.<br/>
`auth.txt` : le nom et le secret OpenVPN affichés sur cette page.<br/>
Lightway n'est pas importé.<br/>
`sudo ./liltress vpn import openvpn express-fr fichier.ovpn`

## ▪️ Surfshark

OpenVPN ou WireGuard.<br/>
OpenVPN : un `.ovpn`, certificats dans le fichier ou nommés à côté, et `auth.txt` avec le nom et le secret de la configuration manuelle.<br/>
WireGuard : un `.conf` du générateur, une clé privée, un pair, une extrémité.<br/>
`sudo ./liltress vpn import openvpn surf-fr fichier.ovpn`<br/>
`sudo ./liltress vpn import wireguard surf-fr fichier.conf`

## ▪️ Proton VPN

WireGuard ou OpenVPN.<br/>
WireGuard : un `.conf` téléchargé du compte.<br/>
OpenVPN : un `.ovpn` dont les certificats sont dans le fichier.<br/>
`auth.txt` : le nom OpenVPN du compte, puis son secret. Ce n'est pas le mot de passe de la boîte mail.<br/>
`sudo ./liltress vpn import wireguard proton-fr fichier.conf`

## ▪️ CyberGhost

OpenVPN. Le dossier contient `openvpn.ovpn`, `ca.crt`, `client.crt` et `client.key`.<br/>
Le fichier a `auth-user-pass` sans chemin, puis `ca ca.crt`, `cert client.crt` et `key client.key`.<br/>
`auth.txt` : le nom OpenVPN CyberGhost, puis le secret dédié.<br/>
`sudo ./liltress vpn import openvpn cyberghost-fr openvpn.ovpn`

## ▪️ Private Internet Access

OpenVPN ou WireGuard.<br/>
OpenVPN : le `.ovpn`, le fichier nommé par `ca`, le fichier nommé par `crl-verify` s'il est présent, et `auth.txt`.<br/>
`auth.txt` : le nom `p` suivi des chiffres du compte, puis le secret généré.<br/>
WireGuard : un `.conf` généré dans le compte.<br/>
`sudo ./liltress vpn import openvpn pia-fr fichier.ovpn`

## ▪️ Mullvad

WireGuard ou OpenVPN.<br/>
WireGuard : un `.conf` du compte. Pas de fichier d'authentification.<br/>
OpenVPN : le `.ovpn` et les certificats qu'il nomme.<br/>
`auth.txt` : le numéro de compte, puis `m`.<br/>
`sudo ./liltress vpn import wireguard mullvad fichier.conf`

## ▪️ PureVPN

OpenVPN ou WireGuard.<br/>
OpenVPN : le `.ovpn` et les fichiers `ca`, `cert` et `key` qu'il nomme.<br/>
`auth.txt` : le nom PureVPN, puis le secret.<br/>
WireGuard : un `.conf`.<br/>
`sudo ./liltress vpn import openvpn pure-fr fichier.ovpn`

## ▪️ IPVanish

OpenVPN. Un `.ovpn`. Les certificats sont en général dans le fichier.<br/>
`auth.txt` : le nom du compte, puis le secret.<br/>
`sudo ./liltress vpn import openvpn ipvanish-fr fichier.ovpn`

## ▪️ Windscribe

OpenVPN ou WireGuard.<br/>
OpenVPN : un `.ovpn` du générateur manuel. `tls-auth` est dans le fichier, ou à côté s'il est nommé.<br/>
`auth.txt` : le nom Windscribe, puis le secret.<br/>
WireGuard : un `.conf`.<br/>
`sudo ./liltress vpn import openvpn windscribe-fr fichier.ovpn`
