# Net Aria
## mikrotik
### setup
```bash
wget -O /usr/bin/mikrotik https://raw.githubusercontent.com/ariafatah0711/net_aria/refs/heads/main/pnetlab/mikrotik.sh && chmod +x /usr/bin/mikrotik
```

### how to use
```bash
Usage: /usr/bin/mikrotik <command> [options]
Commands:
  list                 Tampilkan daftar versi dengan nomor dan status instalasi
  update               Update/refresh semua data dari arsip (lanjutkan tanpa hapus existing)
  install <targets>    Instal CHR (targets: URL, nomor, atau multiple targets)
  remove <targets>     Hapus CHR (targets: nomor, versi, atau multiple targets)
  reset [--cache|--install] Reset data
    --cache            Hapus cache saja (default)
    --install          Hapus cache dan semua router Mikrotik
  help                 Tampilkan bantuan
Examples:
  /usr/bin/mikrotik list
  /usr/bin/mikrotik update
  /usr/bin/mikrotik install 1
  /usr/bin/mikrotik install 1,2,3
  /usr/bin/mikrotik install 7.19.4,6.49.18
  /usr/bin/mikrotik install https://download.mikrotik.com/routeros/7.19.4/chr-7.19.4.img.zip
  /usr/bin/mikrotik remove 1
  /usr/bin/mikrotik remove 1,2,3
  /usr/bin/mikrotik remove 7.17,6.49.18
  /usr/bin/mikrotik reset
  /usr/bin/mikrotik reset --cache
  /usr/bin/mikrotik reset --install
Multiple targets format:
  - Comma separated: 1,2,3
  - Space separated: 1 2 3
  - Mixed: 1,7.19.4,6.49.18
Environment variables:
  QEMU_DIR            Directory untuk QEMU images (default: /opt/unetlab/addons/qemu)
  CACHE_DIR           Directory untuk cache (default: /opt/router)
  WORK_DIR            Directory untuk temporary files (default: /tmp/router/mikrotik)
```