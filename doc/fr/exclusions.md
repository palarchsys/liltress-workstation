# Exclusions

Une liste enregistre un chemin qu'un outil doit ignorer. Le fichier est `config/service/exclusions/entries.yaml`. `scan-skip` garde la liste d'accès du compte dans `config/service/clamav/scan-skip.paths`. `config/service/integrity/paths.list` est la liste des fichiers à empreindre. Ce n'est pas une liste d'exclusion.

Chaque entrée a un id, un chemin, un ou plusieurs outils, une raison, le jour d'ajout, et un jour d'expiration facultatif. Les outils sont `clamav`, `aide`, `chkrootkit`, `rkhunter` et `alert`. Une expiration passée reste dans la liste et sort des fragments générés.

```bash
sudo "./liltress" maintain exclude list [--tool TOOL]
sudo "./liltress" maintain exclude add --path PATH --tools clamav,aide --reason TEXT
sudo "./liltress" maintain exclude del ID
sudo "./liltress" maintain exclude apply
sudo "./liltress" maintain exclude review [--older-than 90d]
```

`apply` écrit `config/service/exclusions/generated/`. ClamAV, AIDE, chkrootkit, rkhunter et le classement des alertes lisent ces fragments en plus des listes déjà livrées. Un fragment vide ne change pas ces listes.
