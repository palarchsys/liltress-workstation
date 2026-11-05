# Tunnel

## 📋 Tunnel

El puesto sigue en claro hasta que un perfil queda validado.<br/>
La importación es `sudo ./liltress vpn import wireguard <nombre> <archivo>` o `sudo ./liltress vpn import openvpn <nombre> <archivo>`.<br/>
Una importación que responde activa el modo VPN. El killswitch sigue armado hasta `sudo ./liltress vpn mode off`.<br/>
`sudo ./liltress vpn mode on` lo reactiva cuando un perfil es válido.<br/>
Cada VPN WireGuard es una carpeta `/opt/liltress-workstation/vpn/wireguard/<nombre>/`.<br/>
Cada VPN OpenVPN es una carpeta `/opt/liltress-workstation/vpn/openvpn/<nombre>/`.<br/>
Esa carpeta guarda la configuración y los archivos de certificado o auth que ella cita.<br/>
El registro es `/opt/liltress-workstation/vpn/vpn.json`.<br/>
`sudo ./liltress vpn list` muestra los perfiles y sus fechas. `sudo ./liltress vpn test <nombre>` repite la prueba.<br/>
`sudo ./liltress vpn rm <nombre>` retira un perfil que no está abierto.<br/>
`sudo ./liltress vpn switch <nombre>` pasa a otro perfil válido.<br/>
SSH no pasa por el túnel.<br/>
Si ningún perfil válido responde, la máquina arranca igual y el killswitch sigue armado.<br/>
El archivo de desvío lleva un prefijo por línea, o una sola línea entre corchetes.<br/>
El ejemplo es `[192.168.1.0/24, 200.200.200.0/24]`.<br/>
Un `vpn switch` fallido no devuelve Internet directo.<br/>
Unbound se reinicia tras un cambio de modo o un cambio de perfil.<br/>
El IPv6 global queda bloqueado cuando el túnel no tiene IPv6.<br/>
Un rango público escrito en el archivo sale en claro.

## 📋 Formas de importación

La importación copia el archivo indicado y cada archivo que nombra en la misma carpeta.<br/>
Un certificado escrito dentro del archivo permanece en el perfil.<br/>
El primer `remote` es el servidor que se abre.<br/>
Los scripts `up` y `down` del proveedor no se copian.<br/>
El DNS del proveedor no se usa. Unbound sigue siendo el resolutor.<br/>
`auth.txt` tiene dos líneas: el nombre, luego el secreto.<br/>
Está junto al `.ovpn` antes de la importación, o se crea vacío en el perfil.<br/>
Mientras faltan esas dos líneas, el perfil está importado y no se prueba.<br/>
`sudo ./liltress vpn test <nombre>` lanza la prueba cuando el archivo está lleno.

## ▪️ NordVPN

OpenVPN. Un `.ovpn` de la página de configuración manual.<br/>
Los certificados están dentro del archivo.<br/>
`auth.txt`: el nombre de servicio, luego el secreto de servicio.<br/>
NordLynx no es un archivo WireGuard importable.<br/>
`sudo ./liltress vpn import openvpn nord-es archivo.ovpn`

## ▪️ ExpressVPN

OpenVPN. Un `.ovpn` de la configuración manual.<br/>
Los certificados están dentro del archivo.<br/>
`auth.txt`: el nombre y el secreto OpenVPN que muestra esa página.<br/>
Lightway no se importa.<br/>
`sudo ./liltress vpn import openvpn express-es archivo.ovpn`

## ▪️ Surfshark

OpenVPN o WireGuard.<br/>
OpenVPN: un `.ovpn`, certificados dentro del archivo o nombrados al lado, y `auth.txt` con el nombre y el secreto de la configuración manual.<br/>
WireGuard: un `.conf` del generador, una clave privada, un par y un extremo.<br/>
`sudo ./liltress vpn import openvpn surf-es archivo.ovpn`<br/>
`sudo ./liltress vpn import wireguard surf-es archivo.conf`

## ▪️ Proton VPN

WireGuard u OpenVPN.<br/>
WireGuard: un `.conf` descargado de la cuenta.<br/>
OpenVPN: un `.ovpn` cuyos certificados están dentro del archivo.<br/>
`auth.txt`: el nombre OpenVPN de la cuenta, luego su secreto. No es la contraseña del correo.<br/>
`sudo ./liltress vpn import wireguard proton-es archivo.conf`

## ▪️ CyberGhost

OpenVPN. La carpeta contiene `openvpn.ovpn`, `ca.crt`, `client.crt` y `client.key`.<br/>
El archivo tiene `auth-user-pass` sin ruta, luego `ca ca.crt`, `cert client.crt` y `key client.key`.<br/>
`auth.txt`: el nombre OpenVPN de CyberGhost, luego el secreto dedicado.<br/>
`sudo ./liltress vpn import openvpn cyberghost-es openvpn.ovpn`

## ▪️ Private Internet Access

OpenVPN o WireGuard.<br/>
OpenVPN: el `.ovpn`, el archivo nombrado por `ca`, el archivo nombrado por `crl-verify` si aparece, y `auth.txt`.<br/>
`auth.txt`: el nombre `p` seguido de los dígitos de la cuenta, luego el secreto generado.<br/>
WireGuard: un `.conf` generado en la cuenta.<br/>
`sudo ./liltress vpn import openvpn pia-es archivo.ovpn`

## ▪️ Mullvad

WireGuard u OpenVPN.<br/>
WireGuard: un `.conf` de la cuenta. Sin archivo de autenticación.<br/>
OpenVPN: el `.ovpn` y los certificados que nombra.<br/>
`auth.txt`: el número de cuenta, luego `m`.<br/>
`sudo ./liltress vpn import wireguard mullvad archivo.conf`

## ▪️ PureVPN

OpenVPN o WireGuard.<br/>
OpenVPN: el `.ovpn` y los archivos `ca`, `cert` y `key` que nombra.<br/>
`auth.txt`: el nombre PureVPN, luego el secreto.<br/>
WireGuard: un `.conf`.<br/>
`sudo ./liltress vpn import openvpn pure-es archivo.ovpn`

## ▪️ IPVanish

OpenVPN. Un `.ovpn`. Los certificados suelen estar dentro del archivo.<br/>
`auth.txt`: el nombre de la cuenta, luego el secreto.<br/>
`sudo ./liltress vpn import openvpn ipvanish-es archivo.ovpn`

## ▪️ Windscribe

OpenVPN o WireGuard.<br/>
OpenVPN: un `.ovpn` del generador manual. `tls-auth` está dentro del archivo, o al lado si el archivo lo nombra.<br/>
`auth.txt`: el nombre Windscribe, luego el secreto.<br/>
WireGuard: un `.conf`.<br/>
`sudo ./liltress vpn import openvpn windscribe-es archivo.ovpn`
