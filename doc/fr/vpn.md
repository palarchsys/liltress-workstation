# Tunnel

## 📋 Tunnel

Le poste s'installe sans VPN. Le réseau reste direct.<br/>
L'import est `sudo ./liltress vpn import openvpn <marque> <nom> <archive ou dossier>` ou `sudo ./liltress vpn import wireguard <marque> <nom> <archive ou dossier>`.<br/>
La marque est obligatoire. Un fichier sans marque est refusé.<br/>
Le premier profil valide arme le killswitch.<br/>
Un dossier invalide n'est pas ajouté. S'il est le premier, le killswitch reste coupé.<br/>
Un import plus tard, pendant que le mode est arrêté, ne réarme pas le killswitch.<br/>
<br/>
`sudo ./liltress vpn mode on` arme le killswitch et ouvre un profil valide.<br/>
Sans profil valide, cette commande est refusée et le killswitch reste coupé.<br/>
`sudo ./liltress vpn mode off` désarme le killswitch et rend le réseau direct. Les dossiers des profils restent.<br/>
Le profil s'affiche dans Paramètres → Réseau. L'interrupteur est le mode. L'import n'est pas le bouton +.<br/>
<br/>
`sudo ./liltress vpn switch <nom>` passe à un autre profil valide. Le killswitch reste armé pendant la bascule.<br/>
Un échec de bascule ne rend pas Internet direct et ne retire aucun profil.<br/>
<br/>
Un profil qui a déjà répondu, puis qui échoue trois essais de dix secondes, est retiré.<br/>
Quand ce retrait enlève le dernier profil, le réseau redevient direct et le killswitch est désarmé.<br/>
Le courrier d'alerte part avant ce désarmement.<br/>
`sudo ./liltress vpn rm <nom>` retire un profil. Le retrait du dernier désarme le killswitch.<br/>
Un profil actif reste tant qu'un autre profil existe.<br/>
Un échec de `sudo ./liltress vpn test <nom>` laisse le dossier.<br/>
<br/>
Chaque VPN WireGuard est un dossier `/opt/liltress-workstation/vpn/wireguard/<nom>/`.<br/>
Chaque VPN OpenVPN est un dossier `/opt/liltress-workstation/vpn/openvpn/<nom>/`.<br/>
Le fichier `meta` de ce dossier porte la marque.<br/>
Le registre est `/opt/liltress-workstation/vpn/vpn.json`.<br/>
<br/>
`sudo ./liltress vpn list` affiche le nom, le protocole, la marque et les dates.<br/>
`sudo ./liltress vpn test <nom>` refait l'essai.<br/>
SSH ne passe pas par le tunnel.<br/>
<br/>
Le fichier de contournement contient un préfixe par ligne, ou une seule ligne entre crochets.<br/>
L'exemple est `[192.168.1.0/24, 200.200.200.0/24]`.<br/>
Unbound est relancé après un changement de mode ou une bascule.<br/>
L'IPv6 global est bloqué lorsque le tunnel n'a pas d'IPv6.<br/>
Une plage publique écrite dans le fichier sort en clair.<br/>
Après le retrait du dernier profil, le prochain profil valide arme de nouveau le killswitch.

## 📋 Formes d'import

L'archive ou le dossier contient exactement les noms de fichiers de la marque.<br/>
Un fichier en trop, un fichier manquant, ou le fichier de l'autre protocole est refusé.<br/>
Un seul dossier en tête d'archive est ouvert. auth.txt peut être à côté de ce dossier.<br/>
Le journal du jour est `log/vpn/YYYY-MM-DD.log`.<br/>
Si le mot REPLACE est encore présent, l'import s'arrête avant l'essai.<br/>
L'exemple utilise `203.0.113.10`. Il ne peut pas ouvrir un tunnel.<br/>
<br/>
`auth.txt` contient deux lignes : le nom, puis le secret.<br/>
Un certificat écrit dans le fichier reste dans le profil.<br/>
Un certificat nommé à côté est copié sous ce nom.<br/>
Les scripts `up` et `down` du fournisseur ne sont pas copiés.<br/>
Le DNS du fournisseur n'est pas utilisé. Unbound reste le résolveur.<br/>
Le premier `remote` est le serveur ouvert.

## ▪️ NordVPN

OpenVPN seulement.<br/>
Nord fournit un fichier `.ovpn`. Les certificats sont dans le fichier.<br/>
`auth.txt` : le nom de service, puis le mot de passe de service. Le courriel du compte est refusé.<br/>
WireGuard et NordLynx sont refusés.<br/>
Remplacez REPLACE dans `config.ovpn` et dans les deux lignes de `auth.txt`.<br/>
L'exemple est [nordvpn.zip](../examples/nordvpn.zip).<br/>
`sudo ./liltress vpn import openvpn nordvpn nord-fr /chemin/nordvpn.zip`

## ▪️ ExpressVPN

OpenVPN seulement.<br/>
ExpressVPN fournit un fichier `.ovpn` de la page de configuration manuelle. Les certificats sont dans le fichier.<br/>
`auth.txt` : le nom et le mot de passe affichés sur cette page.<br/>
WireGuard et Lightway sont refusés.<br/>
Remplacez REPLACE dans `config.ovpn` et dans les deux lignes de `auth.txt`.<br/>
L'exemple est [expressvpn.zip](../examples/expressvpn.zip).<br/>
`sudo ./liltress vpn import openvpn expressvpn express-fr /chemin/expressvpn.zip`

## ▪️ Surfshark

OpenVPN ou WireGuard.<br/>
OpenVPN : `config.ovpn`, certificats dans le fichier ou nommés à côté, et `auth.txt` avec le nom et le secret générés. Le courriel du site est refusé.<br/>
WireGuard : `config.conf` seulement, après la génération de la paire de clés. Pas de `auth.txt`.<br/>
Le fichier de l'autre protocole est refusé.<br/>
Remplacez REPLACE dans chaque fichier de l'archive choisie.<br/>
L'exemple OpenVPN est [surfshark-openvpn.zip](../examples/surfshark-openvpn.zip).<br/>
L'exemple WireGuard est [surfshark-wireguard.zip](../examples/surfshark-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn surfshark surf-fr /chemin/surfshark-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard surfshark surf-fr /chemin/surfshark-wireguard.zip`

## ▪️ Proton VPN

OpenVPN ou WireGuard.<br/>
OpenVPN : `config.ovpn` pour Linux, certificats dans le fichier, et `auth.txt` avec le nom OpenVPN puis le secret OpenVPN. Le mot de passe de la boîte mail est refusé.<br/>
WireGuard : `config.conf` seulement. Pas de `auth.txt`.<br/>
Le fichier de l'autre protocole est refusé.<br/>
Remplacez REPLACE dans chaque fichier de l'archive choisie.<br/>
L'exemple OpenVPN est [protonvpn-openvpn.zip](../examples/protonvpn-openvpn.zip).<br/>
L'exemple WireGuard est [protonvpn-wireguard.zip](../examples/protonvpn-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn protonvpn proton-fr /chemin/protonvpn-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard protonvpn proton-fr /chemin/protonvpn-wireguard.zip`

## ▪️ CyberGhost

OpenVPN seulement.<br/>
Le dossier contient `openvpn.ovpn`, `ca.crt`, `client.crt`, `client.key` et `auth.txt`.<br/>
`openvpn.ovpn` a `auth-user-pass` sans chemin, puis `ca ca.crt`, `cert client.crt` et `key client.key`.<br/>
`auth.txt` : le nom généré, puis le mot de passe généré. L'identifiant du compte est refusé.<br/>
WireGuard est refusé. Un des trois certificats manquant est refusé.<br/>
Remplacez REPLACE dans `openvpn.ovpn`, dans chaque certificat et dans les deux lignes de `auth.txt`.<br/>
L'exemple est [cyberghost.zip](../examples/cyberghost.zip).<br/>
`sudo ./liltress vpn import openvpn cyberghost cyberghost-fr /chemin/cyberghost.zip`

## ▪️ Private Internet Access

OpenVPN seulement.<br/>
Le dossier contient `config.ovpn` et `auth.txt`.<br/>
`auth.txt` : le nom `p` suivi des chiffres, puis le mot de passe de ce même accès.<br/>
Si `config.ovpn` nomme `ca` ou `crl-verify`, ces fichiers sont dans le dossier, sous le nom cité.<br/>
L'exemple a les certificats dans `config.ovpn`.<br/>
WireGuard est refusé. Un identifiant SOCKS est refusé.<br/>
Remplacez REPLACE dans `config.ovpn` et dans les deux lignes de `auth.txt`.<br/>
L'exemple est [pia.zip](../examples/pia.zip).<br/>
`sudo ./liltress vpn import openvpn pia pia-fr /chemin/pia.zip`

## ▪️ Mullvad

WireGuard seulement.<br/>
Le dossier contient `config.conf`. Pas de `auth.txt`.<br/>
Le numéro de compte sert à obtenir ce fichier chez Mullvad. L'import demande `config.conf`.<br/>
OpenVPN est refusé.<br/>
Remplacez REPLACE sur les lignes PrivateKey, Address, PublicKey, Endpoint et AllowedIPs.<br/>
L'exemple est [mullvad.zip](../examples/mullvad.zip).<br/>
`sudo ./liltress vpn import wireguard mullvad mullvad-se /chemin/mullvad.zip`

## ▪️ PureVPN

OpenVPN ou WireGuard.<br/>
OpenVPN : `config.ovpn`, les fichiers `ca`, `cert` et `key` s'ils sont nommés, et `auth.txt` avec le nom VPN puis le secret VPN de l'espace membre. Le courriel est refusé.<br/>
WireGuard : `config.conf` seulement. Pas de `auth.txt`.<br/>
Un fichier WireGuard non activé dans les trente minutes échoue à l'essai. Le profil n'est pas publié.<br/>
Le fichier de l'autre protocole est refusé.<br/>
Remplacez REPLACE dans chaque fichier de l'archive choisie.<br/>
L'exemple OpenVPN est [purevpn-openvpn.zip](../examples/purevpn-openvpn.zip).<br/>
L'exemple WireGuard est [purevpn-wireguard.zip](../examples/purevpn-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn purevpn pure-fr /chemin/purevpn-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard purevpn pure-fr /chemin/purevpn-wireguard.zip`

## ▪️ IPVanish

OpenVPN seulement.<br/>
Le dossier contient `config.ovpn` et `auth.txt`. Les certificats sont dans le fichier, ou à côté s'ils sont nommés.<br/>
`auth.txt` : le nom du compte, puis le mot de passe du compte.<br/>
WireGuard est refusé.<br/>
Remplacez REPLACE dans `config.ovpn` et dans les deux lignes de `auth.txt`.<br/>
L'exemple est [ipvanish.zip](../examples/ipvanish.zip).<br/>
`sudo ./liltress vpn import openvpn ipvanish ipvanish-fr /chemin/ipvanish.zip`

## ▪️ Windscribe

OpenVPN ou WireGuard.<br/>
OpenVPN : `config.ovpn` et `auth.txt`. `tls-auth` est dans le fichier, ou à côté s'il est nommé.<br/>
`auth.txt` : le nom et le mot de passe de Get Credentials. L'identifiant du site est refusé.<br/>
WireGuard : `config.conf` seulement, avec le lieu, le port et la paire de clés. Pas de `auth.txt`.<br/>
IKEv2 est refusé.<br/>
Le générateur WireGuard est une option payante chez Windscribe.<br/>
Remplacez REPLACE dans chaque fichier de l'archive choisie.<br/>
L'exemple OpenVPN est [windscribe-openvpn.zip](../examples/windscribe-openvpn.zip).<br/>
L'exemple WireGuard est [windscribe-wireguard.zip](../examples/windscribe-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn windscribe windscribe-fr /chemin/windscribe-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard windscribe windscribe-fr /chemin/windscribe-wireguard.zip`
