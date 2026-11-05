# Tunnel

## 📋 Tunnel

The workstation stays on the direct network until a profile is validated.<br/>
Import with `sudo ./liltress vpn import wireguard <name> <file>` or `sudo ./liltress vpn import openvpn <name> <file>`.<br/>
A working import turns VPN mode on. The killswitch stays on until `sudo ./liltress vpn mode off`.<br/>
`sudo ./liltress vpn mode on` turns it on again when a profile is valid.<br/>
Each WireGuard VPN is a directory `/opt/liltress-workstation/vpn/wireguard/<name>/`.<br/>
Each OpenVPN VPN is a directory `/opt/liltress-workstation/vpn/openvpn/<name>/`.<br/>
That directory keeps the configuration and the certificate or auth files it names.<br/>
The registry is `/opt/liltress-workstation/vpn/vpn.json`.<br/>
`sudo ./liltress vpn list` shows the profiles and their dates. `sudo ./liltress vpn test <name>` checks one again.<br/>
`sudo ./liltress vpn rm <name>` removes one that is not up.<br/>
`sudo ./liltress vpn switch <name>` moves to another valid profile.<br/>
SSH stays off the tunnel.<br/>
If no validated profile answers, the machine still boots and the killswitch stays on.<br/>
The bypass file is one prefix per line, or one bracket line.<br/>
The example is `[192.168.1.0/24, 200.200.200.0/24]`.<br/>
A failed `vpn switch` does not restore direct Internet.<br/>
Unbound is restarted after a mode change or a switch.<br/>
Global IPv6 is blocked when the tunnel has no IPv6.<br/>
A public range written in the file leaves in the clear.

## 📋 Import forms

The import copies the given file and every file it names in the same directory.<br/>
A certificate written inside the file stays in the profile.<br/>
The first `remote` is the server that is opened.<br/>
Provider `up` and `down` scripts are not copied.<br/>
Provider DNS is not used. Unbound stays the resolver.<br/>
`auth.txt` has two lines: the name, then the secret.<br/>
Put it next to the `.ovpn` before import, or fill the empty file created in the profile.<br/>
Until those two lines exist, the profile is imported and is not tested.<br/>
`sudo ./liltress vpn test <name>` runs the test after the file is filled.

## ▪️ NordVPN

OpenVPN. One `.ovpn` from the manual configuration page.<br/>
The certificates are inside the file.<br/>
`auth.txt`: the service name, then the service secret.<br/>
NordLynx is not an importable WireGuard file.<br/>
`sudo ./liltress vpn import openvpn nord-fr file.ovpn`

## ▪️ ExpressVPN

OpenVPN. One `.ovpn` from the manual configuration.<br/>
The certificates are inside the file.<br/>
`auth.txt`: the OpenVPN name and secret shown on that page.<br/>
Lightway is not imported.<br/>
`sudo ./liltress vpn import openvpn express-fr file.ovpn`

## ▪️ Surfshark

OpenVPN or WireGuard.<br/>
OpenVPN: one `.ovpn`, certificates inside the file or named beside it, and `auth.txt` with the manual-setup name and secret.<br/>
WireGuard: one `.conf` from the generator, one private key, one peer, one endpoint.<br/>
`sudo ./liltress vpn import openvpn surf-fr file.ovpn`<br/>
`sudo ./liltress vpn import wireguard surf-fr file.conf`

## ▪️ Proton VPN

WireGuard or OpenVPN.<br/>
WireGuard: one `.conf` downloaded from the account.<br/>
OpenVPN: one `.ovpn` whose certificates are inside the file.<br/>
`auth.txt`: the account OpenVPN name, then its secret. This is not the mailbox password.<br/>
`sudo ./liltress vpn import wireguard proton-fr file.conf`

## ▪️ CyberGhost

OpenVPN. The directory holds `openvpn.ovpn`, `ca.crt`, `client.crt` and `client.key`.<br/>
The file has `auth-user-pass` with no path, then `ca ca.crt`, `cert client.crt` and `key client.key`.<br/>
`auth.txt`: the CyberGhost OpenVPN name, then the dedicated secret.<br/>
`sudo ./liltress vpn import openvpn cyberghost-fr openvpn.ovpn`

## ▪️ Private Internet Access

OpenVPN or WireGuard.<br/>
OpenVPN: the `.ovpn`, the file named by `ca`, the file named by `crl-verify` when present, and `auth.txt`.<br/>
`auth.txt`: the `p` name followed by the account digits, then the generated secret.<br/>
WireGuard: one `.conf` generated in the account.<br/>
`sudo ./liltress vpn import openvpn pia-fr file.ovpn`

## ▪️ Mullvad

WireGuard or OpenVPN.<br/>
WireGuard: one `.conf` from the account. No authentication file.<br/>
OpenVPN: the `.ovpn` and the certificates it names.<br/>
`auth.txt`: the account number, then `m`.<br/>
`sudo ./liltress vpn import wireguard mullvad file.conf`

## ▪️ PureVPN

OpenVPN or WireGuard.<br/>
OpenVPN: the `.ovpn` and the `ca`, `cert` and `key` files it names.<br/>
`auth.txt`: the PureVPN name, then the secret.<br/>
WireGuard: one `.conf`.<br/>
`sudo ./liltress vpn import openvpn pure-fr file.ovpn`

## ▪️ IPVanish

OpenVPN. One `.ovpn`. The certificates are usually inside the file.<br/>
`auth.txt`: the account name, then the secret.<br/>
`sudo ./liltress vpn import openvpn ipvanish-fr file.ovpn`

## ▪️ Windscribe

OpenVPN or WireGuard.<br/>
OpenVPN: one `.ovpn` from the manual generator. `tls-auth` is inside the file, or beside it when the file names it.<br/>
`auth.txt`: the Windscribe name, then the secret.<br/>
WireGuard: one `.conf`.<br/>
`sudo ./liltress vpn import openvpn windscribe-fr file.ovpn`
