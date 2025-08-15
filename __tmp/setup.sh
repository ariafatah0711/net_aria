#!/bin/bash

# Variabel
REPO_URL="https://github.com/ariafatah0711/net_aria.git"   # ganti sesuai repo kamu
PARENT_DIR="/tmp"  # atau lokasi pnetlab-nya
PNETLAB_DIR="$PARENT_DIR/net_aria"
QEMU_DIR="/opt/unetlab/addons/qemu"
ROUTER_SRC="$PNETLAB_DIR/pnetlab/router"

# 1. Clone repo
echo "[INFO] Cloning repository..."
if [ ! -d "$PNETLAB_DIR" ]; then
    git clone "$REPO_URL" "$PNETLAB_DIR"
else
    echo "[INFO] Folder pnetlab sudah ada, skip cloning."
fi

# 2. Proses file ZIP di folder router
echo "[INFO] Mengekstrak file zip di $ROUTER_SRC..."
for zipfile in "$ROUTER_SRC"/*.zip; do
    if [ -f "$zipfile" ]; then
        basename_noext=$(basename "$zipfile" .zip)
        target_dir="$ROUTER_SRC/$basename_noext"

        # create folder
        echo "[INFO] Membuat folder $target_dir..."
        mkdir -p "$target_dir"

        # unzip
        echo "[INFO] Unzip $zipfile ke $target_dir..."
        unzip -o "$zipfile" -d "$target_dir"

        # rename img to hda.qcow2
        echo "[INFO] Cari file .img untuk di-rename..."
        img_file=$(find "$target_dir" -type f -iname "*.img" | head -n 1)

        if [ -n "$img_file" ]; then
            echo "[INFO] Rename $img_file jadi $target_dir/hda.qcow2"
            mv "$img_file" "$target_dir/hda.qcow2"
        else
            echo "[WARNING] Tidak ada file .img di $target_dir"
        fi

        # # delete file zip
        # echo "[INFO] Hapus file zip $zipfile..."
        # rm -f "$zipfile"
    fi
done

# 4. Pindahkan folder hasil ekstrak ke QEMU_DIR dan rename QCOW2 jadi hda.qcow2
echo "[INFO] Memindahkan folder hasil ekstrak ke $QEMU_DIR..."
for folder in "$ROUTER_SRC"/mikrotik-*; do
    if [ -d "$folder" ]; then
        echo "[INFO] Memproses folder $folder..."
        # Rename file img di dalam folder jadi hda.qcow2
        qcow_file=$(find "$folder" -type f -name "*.img" | head -n 1)
        if [ -n "$qcow_file" ]; then
            mv "$qcow_file" "$(dirname "$qcow_file")/hda.qcow2"
        fi
        cp -r "$folder" "$QEMU_DIR"/
    fi
done

# 5. Fix permissions
echo "[INFO] Memperbaiki permission..."
/opt/unetlab/wrappers/unl_wrapper -a fixpermissions

echo "[DONE] Semua selesai."
