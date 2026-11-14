# Tunnel

## 📋 Tunnel

The workstation install starts with no VPN. The network stays direct.<br/>
Import with `sudo ./liltress vpn import openvpn <brand> <name> <archive or directory>` or `sudo ./liltress vpn import wireguard <brand> <name> <archive or directory>`.<br/>
The brand is required. A file without a brand is refused.<br/>
The first valid profile arms the killswitch.<br/>
An invalid bundle is not added. When it is the first, the killswitch stays off.<br/>
A later import, while mode is off, does not arm the killswitch again.<br/>
<br/>
`sudo ./liltress vpn mode on` arms the killswitch and opens a valid profile.<br/>
With no valid profile, that command is refused and the killswitch stays off.<br/>
`sudo ./liltress vpn mode off` disarms the killswitch and returns to the direct network. The profile directories stay.<br/>
The profile appears in Settings → Network. The toggle is the mode. Import is not the + button.<br/>
<br/>
`sudo ./liltress vpn switch <name>` moves to another valid profile. The killswitch stays armed during the switch.<br/>
A failed switch does not restore direct Internet and does not remove a profile.<br/>
<br/>
A profile that has already answered, then fails three tries of ten seconds, is removed.<br/>
When that removal takes the last profile, the network goes direct and the killswitch is disarmed.<br/>
The alert mail is sent before that disarm.<br/>
`sudo ./liltress vpn rm <name>` removes a profile. Removing the last one disarms the killswitch.<br/>
An active profile stays while another profile exists.<br/>
A failed `sudo ./liltress vpn test <name>` leaves the directory.<br/>
<br/>
Each WireGuard VPN is a directory `/opt/liltress-workstation/vpn/wireguard/<name>/`.<br/>
Each OpenVPN VPN is a directory `/opt/liltress-workstation/vpn/openvpn/<name>/`.<br/>
The `meta` file in that directory records the brand.<br/>
The registry is `/opt/liltress-workstation/vpn/vpn.json`.<br/>
<br/>
`sudo ./liltress vpn list` shows the name, the protocol, the brand, and the dates.<br/>
`sudo ./liltress vpn test <name>` runs the check again.<br/>
SSH stays off the tunnel.<br/>
<br/>
The bypass file is one prefix per line, or one bracket line.<br/>
The example is `[192.168.1.0/24, 200.200.200.0/24]`.<br/>
Unbound is restarted after a mode change or a switch.<br/>
Global IPv6 is blocked when the tunnel has no IPv6.<br/>
A public range written in the file leaves in the clear.<br/>
After the last profile is removed, the next valid profile arms the killswitch again.

## 📋 Import forms

The archive or the directory holds exactly the brand's file names.<br/>
An extra file, a missing file, or the other protocol's file is refused.<br/>
One directory at the top of the archive is opened. auth.txt may sit beside that directory.<br/>
The day's journal is `log/vpn/YYYY-MM-DD.log`.<br/>
If the word REPLACE is still present, the import stops before the handshake.<br/>
The example uses `203.0.113.10`. It cannot open a tunnel.<br/>
<br/>
`auth.txt` has two lines: the name, then the secret.<br/>
A certificate written inside the file stays in the profile.<br/>
A certificate named beside the file is copied under that name.<br/>
Provider `up` and `down` scripts are not copied.<br/>
Provider DNS is not used. Unbound stays the resolver.<br/>
The first `remote` is the server that is opened.

## ▪️ NordVPN

OpenVPN only.<br/>
Nord provides one `.ovpn` file. The certificates are inside the file.<br/>
`auth.txt`: the service username, then the service password. The account email is refused.<br/>
WireGuard and NordLynx are refused.<br/>
Replace REPLACE in `config.ovpn` and in both lines of `auth.txt`.<br/>
The example is [nordvpn.zip](../examples/nordvpn.zip).<br/>
`sudo ./liltress vpn import openvpn nordvpn nord-fr /chemin/nordvpn.zip`

## ▪️ ExpressVPN

OpenVPN only.<br/>
ExpressVPN provides one `.ovpn` file from the manual configuration page. The certificates are inside the file.<br/>
`auth.txt`: the username and the password shown on that page.<br/>
WireGuard and Lightway are refused.<br/>
Replace REPLACE in `config.ovpn` and in both lines of `auth.txt`.<br/>
The example is [expressvpn.zip](../examples/expressvpn.zip).<br/>
`sudo ./liltress vpn import openvpn expressvpn express-fr /chemin/expressvpn.zip`

## ▪️ Surfshark

OpenVPN or WireGuard.<br/>
OpenVPN: `config.ovpn`, certificates inside the file or named beside it, and `auth.txt` with the generated username and secret. The site email is refused.<br/>
WireGuard: `config.conf` only, after the key pair is generated. No `auth.txt`.<br/>
The other protocol's file is refused.<br/>
Replace REPLACE in each file of the chosen archive.<br/>
The OpenVPN example is [surfshark-openvpn.zip](../examples/surfshark-openvpn.zip).<br/>
The WireGuard example is [surfshark-wireguard.zip](../examples/surfshark-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn surfshark surf-fr /chemin/surfshark-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard surfshark surf-fr /chemin/surfshark-wireguard.zip`

## ▪️ Proton VPN

OpenVPN or WireGuard.<br/>
OpenVPN: `config.ovpn` for Linux, certificates inside the file, and `auth.txt` with the OpenVPN username then the OpenVPN secret. The mailbox password is refused.<br/>
WireGuard: `config.conf` only. No `auth.txt`.<br/>
The other protocol's file is refused.<br/>
Replace REPLACE in each file of the chosen archive.<br/>
The OpenVPN example is [protonvpn-openvpn.zip](../examples/protonvpn-openvpn.zip).<br/>
The WireGuard example is [protonvpn-wireguard.zip](../examples/protonvpn-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn protonvpn proton-fr /chemin/protonvpn-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard protonvpn proton-fr /chemin/protonvpn-wireguard.zip`

## ▪️ CyberGhost

OpenVPN only.<br/>
The directory holds `openvpn.ovpn`, `ca.crt`, `client.crt`, `client.key`, and `auth.txt`.<br/>
`openvpn.ovpn` has `auth-user-pass` with no path, then `ca ca.crt`, `cert client.crt`, and `key client.key`.<br/>
`auth.txt`: the generated username, then the generated password. The account login is refused.<br/>
WireGuard is refused. A missing one of the three certificates is refused.<br/>
Replace REPLACE in `openvpn.ovpn`, in each certificate, and in both lines of `auth.txt`.<br/>
The example is [cyberghost.zip](../examples/cyberghost.zip).<br/>
`sudo ./liltress vpn import openvpn cyberghost cyberghost-fr /chemin/cyberghost.zip`

## ▪️ Private Internet Access

OpenVPN only.<br/>
The directory holds `config.ovpn` and `auth.txt`.<br/>
`auth.txt`: the `p` username followed by the digits, then the password of that same login.<br/>
When `config.ovpn` names `ca` or `crl-verify`, those files sit in the directory under the cited names.<br/>
The example keeps the certificates inside `config.ovpn`.<br/>
WireGuard is refused. A SOCKS username is refused.<br/>
Replace REPLACE in `config.ovpn` and in both lines of `auth.txt`.<br/>
The example is [pia.zip](../examples/pia.zip).<br/>
`sudo ./liltress vpn import openvpn pia pia-fr /chemin/pia.zip`

## ▪️ Mullvad

WireGuard only.<br/>
The directory holds `config.conf`. No `auth.txt`.<br/>
The account number is how the file is obtained from Mullvad. The import asks for `config.conf`.<br/>
OpenVPN is refused.<br/>
Replace REPLACE on the PrivateKey, Address, PublicKey, Endpoint, and AllowedIPs lines.<br/>
The example is [mullvad.zip](../examples/mullvad.zip).<br/>
`sudo ./liltress vpn import wireguard mullvad mullvad-se /chemin/mullvad.zip`

## ▪️ PureVPN

OpenVPN or WireGuard.<br/>
OpenVPN: `config.ovpn`, the `ca`, `cert`, and `key` files when they are named, and `auth.txt` with the VPN username then the VPN secret from the member area. The email is refused.<br/>
WireGuard: `config.conf` only. No `auth.txt`.<br/>
A WireGuard file that is not activated within thirty minutes fails the handshake. The profile is not published.<br/>
The other protocol's file is refused.<br/>
Replace REPLACE in each file of the chosen archive.<br/>
The OpenVPN example is [purevpn-openvpn.zip](../examples/purevpn-openvpn.zip).<br/>
The WireGuard example is [purevpn-wireguard.zip](../examples/purevpn-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn purevpn pure-fr /chemin/purevpn-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard purevpn pure-fr /chemin/purevpn-wireguard.zip`

## ▪️ IPVanish

OpenVPN only.<br/>
The directory holds `config.ovpn` and `auth.txt`. The certificates are inside the file, or beside it when they are named.<br/>
`auth.txt`: the account username, then the account password.<br/>
WireGuard is refused.<br/>
Replace REPLACE in `config.ovpn` and in both lines of `auth.txt`.<br/>
The example is [ipvanish.zip](../examples/ipvanish.zip).<br/>
`sudo ./liltress vpn import openvpn ipvanish ipvanish-fr /chemin/ipvanish.zip`

## ▪️ Windscribe

OpenVPN or WireGuard.<br/>
OpenVPN: `config.ovpn` and `auth.txt`. `tls-auth` is inside the file, or beside it when it is named.<br/>
`auth.txt`: the Get Credentials username and password. The website login is refused.<br/>
WireGuard: `config.conf` only, with the location, the port, and the key pair. No `auth.txt`.<br/>
IKEv2 is refused.<br/>
The WireGuard generator is a paid option at Windscribe.<br/>
Replace REPLACE in each file of the chosen archive.<br/>
The OpenVPN example is [windscribe-openvpn.zip](../examples/windscribe-openvpn.zip).<br/>
The WireGuard example is [windscribe-wireguard.zip](../examples/windscribe-wireguard.zip).<br/>
`sudo ./liltress vpn import openvpn windscribe windscribe-fr /chemin/windscribe-openvpn.zip`<br/>
`sudo ./liltress vpn import wireguard windscribe windscribe-fr /chemin/windscribe-wireguard.zip`
