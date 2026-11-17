# Tunnel

## 📋 Tunnel

La instalación del puesto empieza sin VPN. La red sigue directa.<br/>
La importación es `sudo ./liltress vpn import openvpn <marca> <nombre> <carpeta o archivo>` o `sudo ./liltress vpn import wireguard <marca> <nombre> <carpeta o archivo>`.<br/>
La marca es obligatoria. Un archivo sin marca se rechaza.<br/>
El primer perfil válido pasa a ser el VPN de arranque y arma el killswitch.<br/>
Una carpeta inválida no se añade. Si es la primera, el killswitch sigue cortado.<br/>
Una importación posterior, mientras el modo está parado, no sustituye el VPN de arranque y no vuelve a armar el killswitch.<br/>
<br/>
En el arranque, un VPN de arranque válido arma el killswitch y después abre ese perfil.<br/>
`sudo ./liltress vpn default` muestra ese perfil, o ninguno.<br/>
`sudo ./liltress vpn default <nombre>` lo elige si es válido. La sesión en curso no cambia.<br/>
`sudo ./liltress vpn default off` retira esa elección. Un túnel abierto sigue abierto.<br/>
<br/>
`sudo ./liltress vpn mode on` arma el killswitch y abre un perfil válido.<br/>
Sin perfil válido, ese comando se rechaza y el killswitch sigue cortado.<br/>
`sudo ./liltress vpn mode off` desarma el killswitch y devuelve la red directa. El VPN de arranque se queda para el próximo arranque. Las carpetas de los perfiles se quedan.<br/>
El perfil aparece en Configuración → Red. El interruptor es el modo. La importación no es el botón +.<br/>
<br/>
`sudo ./liltress vpn switch <nombre>` pasa a otro perfil válido. El killswitch sigue armado durante el cambio. El VPN de arranque no cambia.<br/>
Un cambio fallido no devuelve Internet directo y no retira ningún perfil.<br/>
<br/>
Un perfil que ya respondió, y luego falla tres intentos de diez segundos, se retira.<br/>
Cuando ese retiro quita el último perfil, la red vuelve a ser directa y el killswitch se desarma.<br/>
El correo de alerta sale antes de ese desarme.<br/>
`sudo ./liltress vpn rm <nombre>` retira un perfil. Retirar el VPN de arranque prueba el perfil siguiente de la lista. Retirar el último quita el VPN de arranque y desarma el killswitch.<br/>
Un perfil activo que no es el VPN de arranque se queda mientras existe otro perfil.<br/>
Un fallo de `sudo ./liltress vpn test <nombre>` deja la carpeta.<br/>
<br/>
Cada VPN WireGuard es una carpeta `/opt/liltress-workstation/vpn/wireguard/<nombre>/`.<br/>
Cada VPN OpenVPN es una carpeta `/opt/liltress-workstation/vpn/openvpn/<nombre>/`.<br/>
El archivo `meta` de esa carpeta lleva la marca.<br/>
El registro es `/opt/liltress-workstation/vpn/vpn.json`.<br/>
<br/>
`sudo ./liltress vpn list` muestra el nombre, el protocolo, la marca y las fechas.<br/>
`sudo ./liltress vpn test <nombre>` repite la prueba.<br/>
SSH no pasa por el túnel.<br/>
<br/>
El archivo de desvío contiene un prefijo por línea, o una sola línea entre corchetes.<br/>
El ejemplo es `[192.168.1.0/24, 200.200.200.0/24]`.<br/>
Unbound se reinicia tras un cambio de modo o un cambio de perfil.<br/>
El IPv6 global se bloquea cuando el túnel no tiene IPv6.<br/>
Un rango público escrito en el archivo sale en claro.<br/>
Tras retirar el último perfil, el siguiente perfil válido vuelve a ser el VPN de arranque y arma el killswitch.

## 📋 Formas de importación

La carpeta o el archivo contiene exactamente los nombres de archivo de la marca.<br/>
Un archivo de más, un archivo que falta, o el archivo del otro protocolo se rechaza.<br/>
Se abre una sola carpeta. auth.txt puede estar a su lado.<br/>
El diario del día es `log/vpn/YYYY-MM-DD.log`.<br/>
Si la palabra REPLACE sigue presente, la importación se detiene antes de la prueba.<br/>
El ejemplo usa `203.0.113.10`. No puede abrir un túnel.<br/>
<br/>
`auth.txt` contiene dos líneas: el nombre, luego el secreto.<br/>
Un certificado escrito dentro del archivo se queda en el perfil.<br/>
Un certificado nombrado al lado se copia con ese nombre.<br/>
Los scripts `up` y `down` del proveedor no se copian.<br/>
El DNS del proveedor no se usa. Unbound sigue siendo el resolver.<br/>
El primer `remote` es el servidor abierto.

## ▪️ NordVPN

Solo OpenVPN.<br/>
Nord entrega un archivo `.ovpn`. Los certificados están dentro del archivo.<br/>
`auth.txt`: el nombre de servicio, luego la contraseña de servicio. El correo de la cuenta se rechaza.<br/>
WireGuard y NordLynx se rechazan.<br/>
Sustituya REPLACE en `config.ovpn` y en las dos líneas de `auth.txt`.<br/>
El ejemplo es [nordvpn](../examples/nordvpn).<br/>
`sudo ./liltress vpn import openvpn nordvpn nord-fr /chemin/nordvpn`

## ▪️ ExpressVPN

Solo OpenVPN.<br/>
ExpressVPN entrega un archivo `.ovpn` de la página de configuración manual. Los certificados están dentro del archivo.<br/>
`auth.txt`: el nombre y la contraseña que muestra esa página.<br/>
WireGuard y Lightway se rechazan.<br/>
Sustituya REPLACE en `config.ovpn` y en las dos líneas de `auth.txt`.<br/>
El ejemplo es [expressvpn](../examples/expressvpn).<br/>
`sudo ./liltress vpn import openvpn expressvpn express-fr /chemin/expressvpn`

## ▪️ Surfshark

OpenVPN o WireGuard.<br/>
OpenVPN: `config.ovpn`, certificados dentro del archivo o nombrados al lado, y `auth.txt` con el nombre y el secreto generados. El correo del sitio se rechaza.<br/>
WireGuard: solo `config.conf`, tras generar el par de claves. Sin `auth.txt`.<br/>
El archivo del otro protocolo se rechaza.<br/>
Sustituya REPLACE en cada archivo de la carpeta, o en el archivo WireGuard.<br/>
El ejemplo OpenVPN es [surfshark-openvpn](../examples/surfshark-openvpn).<br/>
El ejemplo WireGuard es [surfshark-wireguard.conf](../examples/surfshark-wireguard.conf).<br/>
`sudo ./liltress vpn import openvpn surfshark surf-fr /chemin/surfshark-openvpn`<br/>
`sudo ./liltress vpn import wireguard surfshark surf-fr /chemin/surfshark-wireguard.conf`

## ▪️ Proton VPN

OpenVPN o WireGuard.<br/>
OpenVPN: `config.ovpn` para Linux, certificados dentro del archivo, y `auth.txt` con el nombre OpenVPN y luego el secreto OpenVPN. La contraseña del buzón se rechaza.<br/>
WireGuard: solo `config.conf`. Sin `auth.txt`.<br/>
El archivo del otro protocolo se rechaza.<br/>
Sustituya REPLACE en cada archivo de la carpeta, o en el archivo WireGuard.<br/>
El ejemplo OpenVPN es [protonvpn-openvpn](../examples/protonvpn-openvpn).<br/>
El ejemplo WireGuard es [protonvpn-wireguard.conf](../examples/protonvpn-wireguard.conf).<br/>
`sudo ./liltress vpn import openvpn protonvpn proton-fr /chemin/protonvpn-openvpn`<br/>
`sudo ./liltress vpn import wireguard protonvpn proton-fr /chemin/protonvpn-wireguard.conf`

## ▪️ CyberGhost

Solo OpenVPN.<br/>
La carpeta contiene `openvpn.ovpn`, `ca.crt`, `client.crt`, `client.key` y `auth.txt`.<br/>
`openvpn.ovpn` tiene `auth-user-pass` sin ruta, luego `ca ca.crt`, `cert client.crt` y `key client.key`.<br/>
`auth.txt`: el nombre generado, luego la contraseña generada. El acceso de la cuenta se rechaza.<br/>
WireGuard se rechaza. Si falta uno de los tres certificados, se rechaza.<br/>
Sustituya REPLACE en `openvpn.ovpn`, en cada certificado y en las dos líneas de `auth.txt`.<br/>
El ejemplo es [cyberghost](../examples/cyberghost).<br/>
`sudo ./liltress vpn import openvpn cyberghost cyberghost-fr /chemin/cyberghost`

## ▪️ Private Internet Access

Solo OpenVPN.<br/>
La carpeta contiene `config.ovpn` y `auth.txt`.<br/>
`auth.txt`: el nombre `p` seguido de los dígitos, luego la contraseña de ese mismo acceso.<br/>
Si `config.ovpn` nombra `ca` o `crl-verify`, esos archivos están en la carpeta con el nombre citado.<br/>
El ejemplo tiene los certificados dentro de `config.ovpn`.<br/>
WireGuard se rechaza. Un nombre SOCKS se rechaza.<br/>
Sustituya REPLACE en `config.ovpn` y en las dos líneas de `auth.txt`.<br/>
El ejemplo es [pia](../examples/pia).<br/>
`sudo ./liltress vpn import openvpn pia pia-fr /chemin/pia`

## ▪️ Mullvad

Solo WireGuard.<br/>
La importación recibe el archivo y lo copia como `config.conf`. Sin `auth.txt`.<br/>
El número de cuenta sirve para obtener el archivo en Mullvad. La importación pide `config.conf`.<br/>
OpenVPN se rechaza.<br/>
Sustituya REPLACE en las líneas PrivateKey, Address, PublicKey, Endpoint y AllowedIPs.<br/>
El ejemplo es [mullvad.conf](../examples/mullvad.conf).<br/>
`sudo ./liltress vpn import wireguard mullvad mullvad-se /chemin/mullvad.conf`

## ▪️ PureVPN

OpenVPN o WireGuard.<br/>
OpenVPN: `config.ovpn`, los archivos `ca`, `cert` y `key` si están nombrados, y `auth.txt` con el nombre VPN y luego el secreto VPN del área de miembros. El correo se rechaza.<br/>
WireGuard: solo `config.conf`. Sin `auth.txt`.<br/>
Un archivo WireGuard no activado en treinta minutos falla la prueba. El perfil no se publica.<br/>
El archivo del otro protocolo se rechaza.<br/>
Sustituya REPLACE en cada archivo de la carpeta, o en el archivo WireGuard.<br/>
El ejemplo OpenVPN es [purevpn-openvpn](../examples/purevpn-openvpn).<br/>
El ejemplo WireGuard es [purevpn-wireguard.conf](../examples/purevpn-wireguard.conf).<br/>
`sudo ./liltress vpn import openvpn purevpn pure-fr /chemin/purevpn-openvpn`<br/>
`sudo ./liltress vpn import wireguard purevpn pure-fr /chemin/purevpn-wireguard.conf`

## ▪️ IPVanish

Solo OpenVPN.<br/>
La carpeta contiene `config.ovpn` y `auth.txt`. Los certificados están dentro del archivo, o al lado si están nombrados.<br/>
`auth.txt`: el nombre de la cuenta, luego la contraseña de la cuenta.<br/>
WireGuard se rechaza.<br/>
Sustituya REPLACE en `config.ovpn` y en las dos líneas de `auth.txt`.<br/>
El ejemplo es [ipvanish](../examples/ipvanish).<br/>
`sudo ./liltress vpn import openvpn ipvanish ipvanish-fr /chemin/ipvanish`

## ▪️ Windscribe

OpenVPN o WireGuard.<br/>
OpenVPN: `config.ovpn` y `auth.txt`. `tls-auth` está dentro del archivo, o al lado si está nombrado.<br/>
`auth.txt`: el nombre y la contraseña de Get Credentials. El acceso del sitio se rechaza.<br/>
WireGuard: solo `config.conf`, con el lugar, el puerto y el par de claves. Sin `auth.txt`.<br/>
IKEv2 se rechaza.<br/>
El generador WireGuard es una opción de pago en Windscribe.<br/>
Sustituya REPLACE en cada archivo de la carpeta, o en el archivo WireGuard.<br/>
El ejemplo OpenVPN es [windscribe-openvpn](../examples/windscribe-openvpn).<br/>
El ejemplo WireGuard es [windscribe-wireguard.conf](../examples/windscribe-wireguard.conf).<br/>
`sudo ./liltress vpn import openvpn windscribe windscribe-fr /chemin/windscribe-openvpn`<br/>
`sudo ./liltress vpn import wireguard windscribe windscribe-fr /chemin/windscribe-wireguard.conf`

## ▪️ Perso

Solo WireGuard. El archivo viene de la página wg-easy del servidor.<br/>
La importación recibe ese archivo y lo copia como `config.conf`. Sin `auth.txt`.<br/>
OpenVPN se rechaza. Un archivo comprimido se rechaza.<br/>
El ejemplo es [perso.conf](../examples/perso.conf).<br/>
`Endpoint` es `203.0.113.10:51820`. `Address` es `10.8.0.2/24`.<br/>
`sudo ./liltress vpn import wireguard perso poste-1 /chemin/perso.conf`
