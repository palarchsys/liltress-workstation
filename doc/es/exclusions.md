# Exclusiones

Una lista registra una ruta que una herramienta debe ignorar. El archivo es `config/service/exclusions/entries.yaml`. `scan-skip` conserva la lista de acceso de la cuenta en `config/service/clamav/scan-skip.paths`. `config/service/integrity/paths.list` es la lista de archivos a resumir. No es una lista de exclusión.

Cada entrada tiene un id, una ruta, una o varias herramientas, un motivo, el día en que se añadió y un día de caducidad opcional. Las herramientas son `clamav`, `aide`, `chkrootkit`, `rkhunter` y `alert`. Una caducidad pasada permanece en la lista y sale de los fragmentos generados.

```bash
sudo "./liltress" maintain exclude list [--tool TOOL]
sudo "./liltress" maintain exclude add --path PATH --tools clamav,aide --reason TEXT
sudo "./liltress" maintain exclude del ID
sudo "./liltress" maintain exclude apply
sudo "./liltress" maintain exclude review [--older-than 90d]
```

`apply` escribe `config/service/exclusions/generated/`. ClamAV, AIDE, chkrootkit, rkhunter y la clasificación de alertas leen esos fragmentos además de las listas ya entregadas. Un fragmento vacío no cambia esas listas.
