# Exclusions

One list records a path that a tool should ignore. The file is `config/service/exclusions/entries.yaml`. `scan-skip` still owns the on-access home list in `config/service/clamav/scan-skip.paths`. `config/service/integrity/paths.list` is the list of files to hash. It is not an exclusion list.

Each entry has an id, a path, one or more tools, a reason, the day it was added, and an optional expiry day. The tools are `clamav`, `aide`, `chkrootkit`, `rkhunter`, and `alert`. A past expiry stays in the list and leaves the generated fragments.

```bash
sudo "./liltress" maintain exclude list [--tool TOOL]
sudo "./liltress" maintain exclude add --path PATH --tools clamav,aide --reason TEXT
sudo "./liltress" maintain exclude del ID
sudo "./liltress" maintain exclude apply
sudo "./liltress" maintain exclude review [--older-than 90d]
```

`apply` writes `config/service/exclusions/generated/`. ClamAV, AIDE, chkrootkit, rkhunter, and the alert classifier read those fragments in addition to the lists already shipped. An empty fragment does not change those lists.
