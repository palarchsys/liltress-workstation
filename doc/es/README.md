<div align="center">

# 🛡️ Liltress Workstation 🛡️

![Ubuntu 26.04 or newer](https://img.shields.io/badge/Ubuntu-26.04%2B-E95420?logo=ubuntu&logoColor=white)
![Workstation](https://img.shields.io/badge/profile-workstation-1f6feb)
![Unbound](https://img.shields.io/badge/DNS-Unbound-0055A4)
![UFW](https://img.shields.io/badge/firewall-UFW-0055A4)
![Security checks](https://img.shields.io/badge/checks-AIDE%20%C2%B7%20ClamAV%20%C2%B7%20Lynis-2ea44f)

Liltress Workstation prepara un puesto Ubuntu 26.04 o posterior.<br/>
Instala el resolutor DNS local, el cortafuegos y los controles de seguridad.<br/>
La cuenta Ubuntu ya creada en la máquina no se sustituye.<br/>
El instalador no crea una segunda cuenta.<br/>

</div>

## 📋 Antes de comenzar

Tres puntos preceden a la instalación: el sistema, el acceso y las necesidades externas.

## ▪️ Sistema

Ubuntu 26.04 o posterior, incluida una versión intermedia.<br/>
Una instalación nueva es preferible.<br/>
Use una consola local o la sesión gráfica ya abierta.<br/>
La máquina necesita Internet.

## ▪️ Acceso

Usted necesita `sudo` para `./liltress configure`, `./liltress run` y los controles.

## ▪️ Necesidades externas

| Necesidad                | Enlace y procedimiento                                                                                                                                                                                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Token de Ubuntu Pro      | Obligatorio. Abra [https://ubuntu.com/pro/dashboard](https://ubuntu.com/pro/dashboard) y copie el token. `configure.sh` acepta solo letras y dígitos, longitud de 6 a 100, sin espacio.                                                     |
| Contraseña de aplicación | Se pide solo si usted activa las alertas. Use la contraseña de aplicación del proveedor de correo. No escriba nunca la contraseña de la cuenta. Longitud de 8 a 128. Los espacios escritos se quitan.                                       |
| Servidor SMTP            | Se pide solo si las alertas están activadas. Forma `host:puerto`. El ejemplo de `configure.sh` es `smtp-mail.outlook.com:587`. Los corchetes se rechazan. `swaks` envía un mensaje de prueba. La línea de éxito es `Essai d'envoi accepté.` |

## 📋 Instalación

El puesto se prepara con el instalador curl, o con un clon seguido de `sudo ./liltress configure`.

## ▪️ Curl

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git swaks tar
curl -fsSL https://raw.githubusercontent.com/palarchsys/liltress-workstation/main/install.sh | sudo bash
```

## ▪️ Clon

```bash
git clone https://github.com/palarchsys/liltress-workstation
cd liltress-workstation
sudo ./liltress configure
```

## Acción de configure.sh

`sudo ./liltress configure` hace las preguntas de abajo, escribe `global.conf` en modo `644` y `secrets.conf` en modo `600` como root, y después inicia `script/run.sh`.<br/>
`secrets.conf` permanece en la máquina. No lo copie en un mensaje, un ticket o un repositorio.<br/>
La primera pregunta elige el idioma.<br/>
El valor es `G_LANGUAGE`.<br/>
El valor predeterminado es el inglés.<br/>

| Pregunta         | Respuesta esperada                                                                                                                                                                   |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Jeton Ubuntu Pro | Letras y dígitos, de 6 a 100, sin espacio. Obligatorio.                                                                                                                              |
| Activer          | `Y` o `y` activa el correo. `N`, `n` o `non` lo corta. Cortado, Postfix no se instala. Cualquier otra respuesta muestra `Répondez Y ou N.`                                  |
| Serveur          | `host:puerto`, por ejemplo `smtp-mail.outlook.com:587`. Sin corchetes. Solo si las alertas están activadas.                                                                          |
| Login            | Una dirección de correo.                                                                                                                                                             |
| Password         | La contraseña de aplicación del proveedor, de 8 a 128 caracteres. Los espacios se quitan. Las comillas, `$`, `\` y la comilla inversa se rechazan. Nunca la contraseña de la cuenta. |
| From             | Una dirección de correo. `G_WATCHDOG_MAIL` recibe la misma dirección.                                                                                                               |
| Activer l'envoi des alertes vers Google Drive (Y/N). | `Y` o `y` activa la copia. `N`, `n` o `non` la corta. Activada, se le pregunta el nombre remoto y la carpeta, y después se ejecuta `rclone config`. El testigo permanece en la máquina, modo 600. Cortada, rclone no se instala. |
| Distant          | Nombre remoto. Letras, dígitos o guion, de 1 a 32 caracteres. Solo si la copia está activada.                                                                                        |
| Dossier          | Carpeta remota. Sin `..` y sin ruta local absoluta. Solo si la copia está activada.                                                                                                  |
| Mode test        | `0` o `1`.                                                                                                                                                                           |

## Programas y servicios instalados

La instalación coloca los paquetes y servicios de abajo.

| Nombre                                          | Función                                                                                                                                                                        |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| openssh-server                                  | Servidor SSH. El acceso de root se rechaza. La autenticación por contraseña permanece activada. `PasswordAuthentication yes`. `AllowTcpForwarding no`. `AllowAgentForwarding no`. |
| ufw                                             | Cortafuegos del puesto.                                                                                                                                                        |
| usbguard, usbguard-notifier                     | Autoriza los aparatos ya conectados, así como los teclados, los ratones y los concentradores. Un soporte de almacenamiento nuevo espera una confirmación en el escritorio.     |
| fail2ban                                        | Bloquea los fallos de autenticación repetidos.                                                                                                                                |
| auditd                                          | Escribe las reglas de auditoría de las rutas elegidas.                                                                                                                         |
| rkhunter                                        | Control de rootkit y de propiedades de archivos.                                                                                                                               |
| chkrootkit                                      | Control de rootkit. El binario es `/usr/sbin/chkrootkit`.                                                                                                                      |
| clamav                                          | Análisis al acceso y análisis al arranque.                                                                                                                                     |
| crowdsec                                        | Decisiones de seguridad locales.                                                                                                                                               |
| debsums                                         | Sumas de comprobación de los archivos de los paquetes.                                                                                                                         |
| unbound                                         | Resolutor DNS local en `127.0.0.1` y `::1`, puerto 53.                                                                                                                         |
| apparmor                                        | Perfiles de la distribución. `service/apparmor/userns.sh` retira un perfil hfu que no se entrega.                                                                              |
| aide                                            | Base de integridad `/var/lib/aide/aide.db`.                                                                                                                                    |
| unattended-upgrades                             | Orígenes de seguridad. `Automatic-Reboot` vale `false`.                                                                                                                        |
| postfix                                         | Envía el correo de alerta. Instalado solo cuando `G_MAIL_ALERTS=1`.                                                                                                           |
| rclone                                          | Copia un archivo de alerta a Google Drive. Instalado solo cuando `G_RCLONE_ALERTS=1`.                                                                                         |
| lynis                                           | Auditoría de endurecimiento.                                                                                                                                                   |
| ubuntu-pro-client                               | Adjunta el token de Ubuntu Pro. Fuera de una LTS no se activan esm-infra, esm-apps ni Livepatch. En una LTS, un fallo al activarlos no detiene la instalación. |
| acct, sysstat, libpam-pwquality                 | Contabilidad de procesos, estadísticas de actividad, calidad de las contraseñas.                                                                                               |
| rng-tools-debian, haveged                       | Fuentes de entropía.                                                                                                                                                           |
| apt-listchanges, needrestart, apt-show-versions | Avisos de cambios de paquetes y controles de reinicio.                                                                                                                         |

## 📋 Correos de alerta

Cada archivo de alerta queda en `/opt/liltress-workstation/cron/alerts`.<br/>
El mensaje sigue el idioma `G_LANGUAGE`.<br/>
El correo sale solo si `G_MAIL_ALERTS=1`.<br/>
Una copia sale hacia Google Drive solo si `G_RCLONE_ALERTS=1`, hacia el remoto y la carpeta elegidos.<br/>
El correo sale solo si `G_MAIL_ALERTS=1`, si `G_WATCHDOG_MAIL` está definido, y si `/opt/liltress-workstation/cron/bin/send.sh` es ejecutable.<br/>
Un control limpio no envía correo.<br/>
Si una línea del diario es desconocida, no lance la orden.<br/>
Conserve el correo.

Un control que se detiene antes de su fin envía un correo.<br/>
El correo nombra el control.<br/>
Nombra la señal, o el código de salida.

## ▪️ AIDE

El mensaje contiene la línea de resumen y un extracto del diario, luego la nota y el bloque de orden.<br/>
El mensaje contiene un bloque de verificación para cada hallazgo del diario, antes del bloque de orden cuando ese bloque existe.<br/>
La ruta del diario en el correo es el archivo real.<br/>
La forma es `/opt/liltress-workstation/cron/security_logs/aide-YYYYMMDD-HHMMSS.log`.

```bash
sudo bash /opt/liltress-workstation/bin/aide-refresh-db.sh
```

La orden reconstruye la base AIDE a partir del disco actual.<br/>
La línea de éxito es `Base de référence AIDE enregistrée.`

## ▪️ chkrootkit

El mensaje contiene el resumen y el extracto del diario, luego la nota y la orden.<br/>
El mensaje contiene un bloque de verificación para cada hallazgo del diario, antes del bloque de orden cuando ese bloque existe.<br/>
El ejemplo de abajo muestra la forma.<br/>
El correo contiene la ruta real.

```bash
sudo bash /opt/liltress-workstation/bin/chkrootkit-ignore-log.sh '/opt/liltress-workstation/cron/security_logs/chkrootkit-YYYYMMDD-HHMMSS.log'
```

La orden registra las líneas de ese diario en `/opt/liltress-workstation/cron/chkrootkit.local.ignore`.<br/>
La línea de éxito es `Aucune nouvelle détection à enregistrer.` cuando no hay nada nuevo, o `N détection(s) enregistrée(s) dans /opt/liltress-workstation/cron/chkrootkit.local.ignore`.

Una detección confirmada mueve el archivo y adjunta la orden de restauración en su lugar.<br/>
La orden de registro permanece solo cuando ningún archivo confirmado fue movido.

## ▪️ debsums

El mensaje contiene el resumen y el extracto del diario.<br/>
No añade un bloque de orden.<br/>
El control reinstala cada paquete todavía señalado con `apt-get install --reinstall`.<br/>
El correo nombra cada paquete restablecido.<br/>
La línea de éxito es `La somme correspond.`

Un paquete cuya suma sigue siendo distinta, o cuya reinstalación falla, permanece en el correo.<br/>
Una línea para `/var/lib/rkhunter/db/mirrors.dat` se retira antes de esa reinstalación solo si su SHA-256 actual es igual a `/opt/liltress-workstation/cron/rkhunter-mirrors.sha256`.<br/>
Una línea modificada bajo `/usr/lib/*/perl-base/unicore/` del paquete `perl-base` se retira antes de esa reinstalación.<br/>
El archivo entregado por Ubuntu no corresponde a la suma de ese paquete.

## ▪️ ClamAV al acceso

El mensaje contiene la firma, el nombre del archivo, la ruta de origen y la ruta de cuarentena, luego la nota y una orden de restauración por archivo movido.<br/>
El mismo diario indica la hora, el tipo de detección, las acciones aplicadas y una recomendación corta.<br/>
Un archivo cuyo nombre corresponde a `.clamav-quarantine-lock.*` no envía correo.<br/>
El script sale con 0 antes del diario y antes de `log_alert`.

```bash
sudo bash /opt/liltress-workstation/bin/quarantine-restore.sh <id>
```

El ejemplo muestra la forma.<br/>
El correo contiene el identificador real.<br/>
La orden devuelve ese archivo a su lugar de origen.<br/>
La línea de éxito es `fichier remis en place`.<br/>
El registro es `/opt/liltress-workstation/cron/quarantine.registry`.

## ▪️ Análisis ClamAV al arranque

El mensaje contiene el resumen y el extracto del diario.<br/>
Cuando un archivo fue movido, el correo añade una orden de restauración por archivo.<br/>
La orden es la misma que la del correo al acceso.<br/>
La forma del diario es `/opt/liltress-workstation/cron/security_logs/clamav-YYYYMMDD-HHMMSS.log`.<br/>
Un archivo ilegible, sin línea `FOUND`, no envía correo.<br/>
Las líneas `Known viruses` e `Infected files` no se copian en el correo.<br/>
Un proceso `clamscan` detenido por una señal envía un correo.<br/>
El correo nombra la señal y cada archivo no leído.<br/>
Los demás archivos de la pasada se analizan.<br/>
Dos fallos seguidos detienen la pasada ClamAV.<br/>
El correo dice entonces que los archivos restantes no fueron leídos.

## ▪️ Análisis ClamAV diferido

El mensaje contiene el resumen y el extracto del diario.<br/>
Cuando un archivo fue movido, el correo añade una orden de restauración por archivo.<br/>
La orden es la misma que la del correo al acceso.<br/>
Una firma y una ruta ya registradas en `/opt/liltress-workstation/cron/scan-skip.seen` no vuelven a enviar correo.<br/>
Un proceso `clamscan` detenido por una señal envía un correo.<br/>
El correo nombra la señal y cada archivo no leído.<br/>
Los demás archivos de la pasada se analizan.<br/>
Dos fallos seguidos detienen la pasada ClamAV.<br/>
El correo dice entonces que los archivos restantes no fueron leídos.<br/>
El sello permanece en su lugar.<br/>
La forma del diario es `/opt/liltress-workstation/cron/security_logs/idle-scan-YYYYMMDD-HHMMSS.log`.

## ▪️ rkhunter

El correo de avisos contiene el resumen y el extracto del diario, luego la nota y el bloque de orden.<br/>
El mensaje contiene un bloque de verificación para cada hallazgo del diario, antes del bloque de orden cuando ese bloque existe.<br/>
El correo `mirrors.dat modifié hors rkhunter --update` no añade ese bloque.<br/>
Un correo de error tampoco.<br/>
La forma del diario es `/opt/liltress-workstation/cron/security_logs/rkhunter-YYYYMMDD-HHMMSS.log`.

```bash
sudo bash /opt/liltress-workstation/bin/rkhunter-refresh-db.sh
```

La orden recalcula la base de propiedades rkhunter a partir del disco actual.<br/>
La línea de éxito es `Base de propriétés rkhunter enregistrée.`<br/>
Una detección confirmada mueve el archivo y adjunta la orden de restauración en su lugar.<br/>
La orden de recálculo permanece solo cuando ningún archivo confirmado fue movido.<br/>
Los archivos de `/dev/shm` y el socket `/dev/log` están autorizados en `rkhunter.conf.local`.<br/>
No producen el aviso `Suspicious file types found in /dev`.<br/>
El extracto conserva la línea de aviso y las rutas que la siguen.

## ▪️ Aviso de reinicio

El mensaje es `Un redémarrage est utile. La machine n'a pas été redémarrée.`<br/>
Este correo no añade un bloque de orden.<br/>
El mismo conjunto de paquetes no vuelve a enviar correo.<br/>
Un juego en curso omite el correo y deja la huella sin cambio.<br/>
El script no reinicia la máquina.<br/>
La forma del diario es `/opt/liltress-workstation/cron/security_logs/reboot-notice-YYYYMMDD-HHMMSS.log`.

## 📋 Comandos después de la instalación

Lance estas órdenes desde el directorio de las fuentes (`/opt/liltress-workstation/src` después del instalador curl, o el directorio del clon).

## ▪️ liltress check

```bash
sudo ./liltress check
```

Comprueba `global.conf` y `secrets.conf`.<br/>
La línea de éxito es `Configuration conforme`.<br/>

## ▪️ liltress run

```bash
sudo ./liltress run
```

Lanza la instalación a partir de los archivos preparados.<br/>
El instalador rechaza arrancar cuando el control no pasa.

## ▪️ verify/alerts.sh

```bash
sudo bash verify/alerts.sh
```

Comprueba el temporizador de la cadena, el temporizador diferido, ClamAV al acceso y la ruta del correo.<br/>
Sin `--no-send`, una sonda sale cuando las alertas están activadas.<br/>
El asunto termina por `Contrôle`.<br/>
La línea de éxito es `Résultat : OK`.

```bash
sudo bash verify/alerts.sh --no-send
```

## ▪️ verify/workstation.sh

```bash
sudo bash verify/workstation.sh "$PWD"
```

Lanza la comprobación del puesto.<br/>
La línea de cierre tiene la forma `Check : N OK / N WARN / N FAIL`.<br/>
La misma pasada comprueba el reenvío SSH, la regla de cortafuegos SSH, USBGuard, el plazo sudo y `w-reboot-notice.timer`.

## ▪️ Comprobación después del arranque

```bash
sudo bash /opt/liltress-workstation/bin/boot-check.sh
```

Comprueba los servicios de seguridad del arranque y las tres pasadas de esta sesión.<br/>
La línea de éxito es `Contrôle de démarrage : OK`.<br/>
Una pasada todavía en curso muestra `Contrôle de démarrage : en cours` y termina con el código 1.<br/>
Una diferencia muestra `Contrôle de démarrage : écarts` y termina con el código 1.

## ▪️ liltress lynis

```bash
sudo ./liltress lynis
```

Lanza `lynis audit system --quick --no-colors` y escribe el informe bajo `<source>/log/lynis-<stamp>/`.<br/>
`G_LYNIS_MIN_SCORE` vale 80.<br/>
`verify/workstation.sh` acepta un `hardening_index` superior o igual a ese umbral.

## ▪️ Base AIDE

```bash
sudo bash /opt/liltress-workstation/bin/aide-refresh-db.sh
```

Reconstruye `/var/lib/aide/aide.db`.<br/>
La línea de éxito es `Base de référence AIDE enregistrée.`

## ▪️ Huella de los espejos rkhunter

```bash
sudo bash /opt/liltress-workstation/cron/bin/record-mirrors.sh save
```

Escribe el SHA-256 de `/var/lib/rkhunter/db/mirrors.dat` en `/opt/liltress-workstation/cron/rkhunter-mirrors.sha256` en modo `600`.<br/>
`rkhunter.sh` registra esta huella solo después de un `rkhunter --update` que devuelve 0 o 2.

## ▪️ Rutas excluidas del análisis

```bash
sudo bash /opt/liltress-workstation/bin/scan-skip.sh list
sudo bash /opt/liltress-workstation/bin/scan-skip.sh add $HOME/.cache/exemple
sudo bash /opt/liltress-workstation/bin/scan-skip.sh del $HOME/.cache/exemple
```

El archivo de lista es `/opt/liltress-workstation/src/config/clamav/scan-skip.paths`.<br/>
Una lista ya presente permanece cuando el instalador vuelve a ejecutarse.<br/>
Una lista que todavía está en `/opt/liltress-workstation/cron/scan-skip.paths` se copia una vez, cuando el archivo nuevo todavía es la plantilla.

| Acción       | Línea mostrada                      |
| ------------ | ----------------------------------- |
| `list`       | una ruta aceptada por línea         |
| `add`        | `Chemin ajouté : <path>`            |
| ya presente  | `Ce chemin est déjà exclu : <path>` |
| `del`        | `Chemin retiré : <path>`            |
| rechazada    | `Chemin refusé : <path>`            |

Una ruta rechazada deja el archivo sin cambio.<br/>
La orden reescribe `/etc/clamav/clamd.conf`.<br/>
Relanza `clamav-daemon`, luego `clamav-clamonacc.service` o `clamonacc.service`, cuando el bloque de exclusión cambia.<br/>
