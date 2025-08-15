#!/bin/bash

set -euo pipefail

# Konfigurasi default
QEMU_DIR="/opt/unetlab/addons/qemu"
DOWNLOAD_BASE="https://download.mikrotik.com/routeros"
WORK_DIR="/tmp/router/mikrotik"
LIST_CACHE="/opt/router/mikrotik_list.txt"
INSTALLED_CACHE="/opt/router/mikrotik_install.txt"

print_usage() {
    echo "Usage: $0 <command> [options]"
    echo "\nCommands:"
    echo "  list                 Tampilkan daftar versi dengan nomor dan status instalasi"
    echo "  update               Update/refresh semua data dari arsip"
    echo "  install <target>     Instal CHR (target: URL atau nomor dari list)"
    echo "  remove <target>      Hapus CHR (target: nomor dari list atau versi)"
    echo "  help                 Tampilkan bantuan"
    echo "\nExamples:"
    echo "  $0 list"
    echo "  $0 update"
    echo "  $0 install 1"
    echo "  $0 install https://download.mikrotik.com/routeros/7.19.4/chr-7.19.4.img.zip"
    echo "  $0 remove 1"
    echo "  $0 remove 7.17"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

require_cmd() {
    local cmd="$1"
    if ! have_cmd "$cmd"; then
        echo "[ERROR] Perintah '$cmd' tidak ditemukan. Mohon instal dulu." >&2
        exit 1
    fi
}

download_file() {
    local url="$1"
    local out="$2"
    if have_cmd wget; then
        wget -q --show-progress -O "$out" "$url"
    else
        require_cmd curl
        curl -fSL -o "$out" "$url"
    fi
}

get_versions_from_archive() {
    # Ambil daftar versi v7 dari halaman arsip  
    # Sumber: https://mikrotik.com/download/archive
    if have_cmd curl; then
        curl -fsSL "https://mikrotik.com/download/archive"
    else
        require_cmd wget
        wget -qO- "https://mikrotik.com/download/archive"
    fi \
        | tr '\r' '\n' \
        | grep -oE '7\.[0-9]+(\.[0-9]+)?' \
        | sort -Vr \
        | uniq
}

check_url_exists() {
    local url="$1"
    if have_cmd curl; then
        curl -fsI "$url" >/dev/null 2>&1
    else
        require_cmd wget
        wget -q --spider "$url" >/dev/null 2>&1
    fi
}

is_installed() {
    local version="$1"
    local name="mikrotik-$version"
    local target_dir="$QEMU_DIR/$name"
    if [ -f "$target_dir/hda.qcow2" ]; then
        return 0
    else
        return 1
    fi
}

update_installed_cache() {
    mkdir -p "$WORK_DIR"
    mkdir -p "$(dirname "$INSTALLED_CACHE")"
    : > "$INSTALLED_CACHE"
    if [ -d "$QEMU_DIR" ]; then
        for dir in "$QEMU_DIR"/mikrotik-*; do
            if [ -d "$dir" ] && [ -f "$dir/hda.qcow2" ]; then
                local version
                version="$(basename "$dir" | sed 's/^mikrotik-//')"
                echo "$version" >> "$INSTALLED_CACHE"
            fi
        done
    fi
}

list_chr_img_links() {
    mkdir -p "$WORK_DIR"
    update_installed_cache

    # Muat daftar yang sudah di-cache
    if [ ! -f "$LIST_CACHE" ]; then
        echo "[INFO] Cache kosong, jalankan 'update' dulu"
        return 1
    fi

    local line_num=1
    while read -r line; do
        local version url
        version="$(echo "$line" | awk '{print $1}')"
        url="$(echo "$line" | awk '{print $2}')"
        if [ -n "$version" ] && [ -n "$url" ]; then
            local status="[ ]"
            if is_installed "$version"; then
                status="[✓]"
            fi
            printf "%2d. %s %s %s\n" "$line_num" "$status" "$version" "$url"
            line_num=$((line_num + 1))
        fi
    done < "$LIST_CACHE"
}

update_chr_list() {
    echo "[INFO] Update daftar CHR dari arsip..."
    mkdir -p "$WORK_DIR"
    mkdir -p "$(dirname "$LIST_CACHE")"
    : > "$LIST_CACHE"

    local versions
    mapfile -t versions < <(get_versions_from_archive)
    if [ ${#versions[@]} -eq 0 ]; then
        echo "[ERROR] Gagal mengambil daftar versi dari arsip." >&2
        return 1
    fi

    local count=0
    for v in "${versions[@]}"; do
        local url="$DOWNLOAD_BASE/$v/chr-$v.img.zip"
        if check_url_exists "$url"; then
            echo "$v $url" >> "$LIST_CACHE"
            count=$((count + 1))
        fi
    done

    echo "[INFO] Update selesai: $count versi ditemukan"
}

extract_version_from_url() {
    local url="$1"
    # Ekstrak pola chr-<version>.*
    local ver
    ver="$(echo "$url" | sed -n 's#.*chr-\([0-9][0-9.]*\)\..*#\1#p')"
    echo "$ver"
}

get_url_by_number() {
    local num="$1"
    if [ ! -f "$LIST_CACHE" ]; then
        echo "[ERROR] Cache kosong, jalankan 'update' dulu" >&2
        return 1
    fi

    local line_num=1
    while read -r line; do
        local version url
        version="$(echo "$line" | awk '{print $1}')"
        url="$(echo "$line" | awk '{print $2}')"
        if [ -n "$version" ] && [ -n "$url" ]; then
            if [ "$line_num" -eq "$num" ]; then
                echo "$url"
                return 0
            fi
            line_num=$((line_num + 1))
        fi
    done < "$LIST_CACHE"

    echo "[ERROR] Nomor $num tidak ditemukan dalam daftar" >&2
    return 1
}

install_from_url() {
    local url="$1"
    if [ -z "$url" ]; then
        echo "[ERROR] URL tidak diberikan" >&2
        return 1
    fi
    if ! check_url_exists "$url"; then
        echo "[ERROR] URL tidak dapat diakses: $url" >&2
        return 1
    fi

    local version
    version="$(extract_version_from_url "$url")"
    local name
    if [ -n "$version" ]; then
        name="mikrotik-$version"
    else
        name="mikrotik-custom"
    fi

    # Cek apakah sudah terinstall
    if [ -n "$version" ] && is_installed "$version"; then
        echo "[INFO] Versi $version sudah terinstall di $QEMU_DIR/$name"
        echo "[INFO] Skip download dan install"
        return 0
    fi

    local target_dir="$QEMU_DIR/$name"
    local tmp_dir="$WORK_DIR/install"
    mkdir -p "$tmp_dir"
    mkdir -p "$target_dir"

    local out_zip="$tmp_dir/chr.zip"
    echo "[INFO] Unduh: $url"
    download_file "$url" "$out_zip"

    echo "[INFO] Ekstrak: $out_zip"
    require_cmd unzip
    unzip -o "$out_zip" -d "$tmp_dir"

    local qcow2_file img_file
    qcow2_file=$(find "$tmp_dir" -maxdepth 1 -type f -name "*.qcow2" | head -n1 || true)
    img_file=$(find "$tmp_dir" -maxdepth 1 -type f -name "*.img" | head -n1 || true)

    if [ -n "$qcow2_file" ]; then
        echo "[INFO] Salin QCOW2 ke $target_dir/hda.qcow2"
        cp -f "$qcow2_file" "$target_dir/hda.qcow2"
    elif [ -n "$img_file" ]; then
        require_cmd qemu-img
        echo "[INFO] Konversi RAW IMG -> QCOW2"
        qemu-img convert -f raw -O qcow2 "$img_file" "$target_dir/hda.qcow2"
    else
        echo "[ERROR] Tidak menemukan .qcow2 atau .img di dalam ZIP" >&2
        return 1
    fi

    if [ -x "/opt/unetlab/wrappers/unl_wrapper" ]; then
        echo "[INFO] Memperbaiki permission..."
        /opt/unetlab/wrappers/unl_wrapper -a fixpermissions || true
    fi

    echo "[DONE] CHR terpasang di $target_dir"
}

remove_chr() {
    local target="$1"
    local version=""
    local name=""
    
    # Cek apakah target adalah nomor
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        # Ambil versi dari nomor list
        local line_num=1
        while read -r line; do
            local ver url
            ver="$(echo "$line" | awk '{print $1}')"
            url="$(echo "$line" | awk '{print $2}')"
            if [ -n "$ver" ] && [ -n "$url" ]; then
                if [ "$line_num" -eq "$target" ]; then
                    version="$ver"
                    break
                fi
                line_num=$((line_num + 1))
            fi
        done < "$LIST_CACHE"
        
        if [ -z "$version" ]; then
            echo "[ERROR] Nomor $target tidak ditemukan dalam daftar" >&2
            return 1
        fi
    else
        # Target adalah versi langsung
        version="$target"
    fi
    
    name="mikrotik-$version"
    local target_dir="$QEMU_DIR/$name"
    
    # Cek apakah versi terinstall
    if ! is_installed "$version"; then
        echo "[ERROR] Versi $version tidak terinstall" >&2
        return 1
    fi
    
    # Konfirmasi penghapusan
    echo "[WARNING] Akan menghapus CHR versi $version dari $target_dir"
    read -r -p "Lanjutkan? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "[INFO] Dibatalkan"
        return 0
    fi
    
    # Hapus folder
    echo "[INFO] Menghapus $target_dir"
    rm -rf "$target_dir"
    
    # Perbaiki permission jika perlu
    if [ -x "/opt/unetlab/wrappers/unl_wrapper" ]; then
        echo "[INFO] Memperbaiki permission..."
        /opt/unetlab/wrappers/unl_wrapper -a fixpermissions || true
    fi
    
    echo "[DONE] CHR versi $version berhasil dihapus"
}

main() {
    if [ $# -eq 0 ]; then
        print_usage
        exit 1
    fi

    case "$1" in
        list)
            list_chr_img_links
            ;;
        update)
            update_chr_list
            ;;
        install)
            if [ $# -lt 2 ]; then
                echo "[ERROR] Target instalasi diperlukan" >&2
                print_usage
                exit 1
            fi
            local target="$2"
            local url
            # Cek apakah target adalah nomor
            if [[ "$target" =~ ^[0-9]+$ ]]; then
                url="$(get_url_by_number "$target")"
                if [ $? -ne 0 ]; then
                    exit 1
                fi
            else
                url="$target"
            fi
            install_from_url "$url"
            ;;
        remove)
            if [ $# -lt 2 ]; then
                echo "[ERROR] Target penghapusan diperlukan" >&2
                print_usage
                exit 1
            fi
            remove_chr "$2"
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            echo "[ERROR] Perintah tidak dikenal: $1" >&2
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
