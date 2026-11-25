# Exclusions

Eine Liste hält einen Pfad fest, den ein Werkzeug ignorieren soll. Die Datei ist `config/service/exclusions/entries.yaml`. `scan-skip` behält die Zugriffsliste des Kontos in `config/service/clamav/scan-skip.paths`. `config/service/integrity/paths.list` ist die Liste der Dateien für den Fingerabdruck. Das ist keine Ausschlussliste.

Jeder Eintrag hat eine Id, einen Pfad, ein oder mehrere Werkzeuge, einen Grund, den Tag des Hinzufügens und einen optionalen Ablauftag. Die Werkzeuge sind `clamav`, `aide`, `chkrootkit`, `rkhunter` und `alert`. Ein überschrittenes Ablaufdatum bleibt in der Liste und verlässt die erzeugten Fragmente.

```bash
sudo "./liltress" maintain exclude list [--tool TOOL]
sudo "./liltress" maintain exclude add --path PATH --tools clamav,aide --reason TEXT
sudo "./liltress" maintain exclude del ID
sudo "./liltress" maintain exclude apply
sudo "./liltress" maintain exclude review [--older-than 90d]
```

`apply` schreibt `config/service/exclusions/generated/`. ClamAV, AIDE, chkrootkit, rkhunter und die Alarm-Einordnung lesen diese Fragmente zusätzlich zu den bereits gelieferten Listen. Ein leeres Fragment ändert diese Listen nicht.
