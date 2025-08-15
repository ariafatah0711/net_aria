#!/bin/bash

set -euo pipefail

# Konfigurasi default - lebih dinamis
QEMU_DIR="${QEMU_DIR:-/opt/unetlab/addons/qemu}"
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://download.mikrotik.com/routeros}"
WORK_DIR="${WORK_DIR:-/tmp/router/mikrotik}"
CACHE_DIR="${CACHE_DIR:-/opt/router}"
LIST_CACHE="${LIST_CACHE:-$CACHE_DIR/mikrotik_list.txt}"
INSTALLED_CACHE="${INSTALLED_CACHE:-$CACHE_DIR/mikrotik_install.txt}"

# Fungsi untuk memastikan direktori cache ada
ensure_cache_dir() {
    mkdir -p "$CACHE_DIR" 2>/dev/null || {
        echo "[WARNING] Tidak bisa membuat $CACHE_DIR, menggunakan /tmp"
        CACHE_DIR="/tmp/mikrotik_cache"
        LIST_CACHE="$CACHE_DIR/mikrotik_list.txt"
        INSTALLED_CACHE="$CACHE_DIR/mikrotik_install.txt"
        mkdir -p "$CACHE_DIR"
    }
}

print_usage() {
    echo "Usage: $0 <command> [options]"
    echo "Commands:"
    echo "  list                 Tampilkan daftar versi dengan nomor dan status instalasi"
    echo "  update               Update/refresh semua data dari arsip (lanjutkan tanpa hapus existing)"
    echo "  install <targets>    Instal CHR (targets: URL, nomor, atau multiple targets)"
    echo "  remove <targets>     Hapus CHR (targets: nomor, versi, atau multiple targets)"
    echo "  reset [--cache|--install] Reset data"
    echo "    --cache            Hapus cache saja (default)"
    echo "    --install          Hapus cache dan semua router Mikrotik"
    echo "  help                 Tampilkan bantuan"
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 update"
    echo "  $0 install 1"
    echo "  $0 install 1,2,3"
    echo "  $0 install 7.19.4,6.49.18"
    echo "  $0 install https://download.mikrotik.com/routeros/7.19.4/chr-7.19.4.img.zip"
    echo "  $0 remove 1"
    echo "  $0 remove 1,2,3"
    echo "  $0 remove 7.17,6.49.18"
    echo "  $0 reset"
    echo "  $0 reset --cache"
    echo "  $0 reset --install"
    echo "Multiple targets format:"
    echo "  - Comma separated: 1,2,3"
    echo "  - Space separated: 1 2 3"
    echo "  - Mixed: 1,7.19.4,6.49.18"
    echo "Environment variables:"
    echo "  QEMU_DIR            Directory untuk QEMU images (default: /opt/unetlab/addons/qemu)"
    echo "  CACHE_DIR           Directory untuk cache (default: /opt/router)"
    echo "  WORK_DIR            Directory untuk temporary files (default: /tmp/router/mikrotik)"
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
    # Ambil versi Mikrotik yang masuk akal dari halaman arsip (v6+ untuk CHR)
    # Sumber: https://mikrotik.com/download/archive
    if have_cmd curl; then
        curl -fsSL "https://mikrotik.com/download/archive"
    else
        require_cmd wget
        wget -qO- "https://mikrotik.com/download/archive"
    fi \
        | tr '\r' '\n' \
        | grep -oE '[6-9]\.[0-9]+(\.[0-9]+)?' \
        | sort -Vr \
        | uniq
}

check_url_exists() {
    local url="$1"
    if have_cmd curl; then
        curl -fsI --connect-timeout 3 --max-time 5 "$url" >/dev/null 2>&1
    else
        require_cmd wget
        wget -q --spider --timeout=5 --tries=1 "$url" >/dev/null 2>&1
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
    ensure_cache_dir
    mkdir -p "$WORK_DIR"
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
    ensure_cache_dir
    mkdir -p "$WORK_DIR"
    update_installed_cache

    # Muat daftar yang sudah di-cache
    if [ ! -f "$LIST_CACHE" ]; then
        echo "[INFO] Cache kosong, jalankan 'update' dulu"
        return 1
    fi

    # Hitung total versi
    local total_versions
    total_versions=$(wc -l < "$LIST_CACHE" 2>/dev/null || echo "0")
    
    echo "======================================================================================================"
    echo "                              MIKROTIK CHR VERSIONS LIST"
    echo "======================================================================================================"
    echo "[✓] = Installed  |  [ ] = Not Installed  |  Total: $total_versions versions"
    echo "======================================================================================================"

    local line_num=1
    local installed_count=0
    local current_major=""
    
    while read -r line; do
        local version url
        version="$(echo "$line" | awk '{print $1}')"
        url="$(echo "$line" | awk '{print $2}')"
        if [ -n "$version" ] && [ -n "$url" ]; then
            local status="[ ]"
            if is_installed "$version"; then
                status="[✓]"
                installed_count=$((installed_count + 1))
            fi
            
            # Check if major version changed
            local major_version
            major_version=$(echo "$version" | cut -d. -f1)
            if [ "$major_version" != "$current_major" ]; then
                if [ "$current_major" != "" ]; then
                    echo ""
                fi
                echo "--- RouterOS v$major_version ---"
                current_major="$major_version"
            fi
            
            # Format version dengan padding yang konsisten
            local version_padded
            version_padded=$(printf "%-8s" "$version")
            
            # Tampilkan dengan format yang rapi
            printf "%3d. %s %s | %s\n" "$line_num" "$status" "$version_padded" "$url"
            line_num=$((line_num + 1))
        fi
    done < "$LIST_CACHE"
    
    echo "======================================================================================================"
    echo "Installed: $installed_count versions  |  Available: $((total_versions - installed_count)) versions"
    echo "======================================================================================================"
}

reset_data() {
    local reset_type="${1:-cache}"
    
    case "$reset_type" in
        cache|--cache)
            echo "[INFO] Menghapus cache..."
            if [ -f "$LIST_CACHE" ]; then
                rm -f "$LIST_CACHE"
                echo "[INFO] Cache list dihapus: $LIST_CACHE"
            fi
            if [ -f "$INSTALLED_CACHE" ]; then
                rm -f "$INSTALLED_CACHE"
                echo "[INFO] Cache installed dihapus: $INSTALLED_CACHE"
            fi
            echo "[DONE] Cache berhasil dihapus"
            ;;
        install|--install)
            echo "[WARNING] Akan menghapus cache dan SEMUA router Mikrotik yang terinstall!"
            read -r -p "Lanjutkan? (y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "[INFO] Dibatalkan"
                return 0
            fi
            
            # Hapus cache
            if [ -f "$LIST_CACHE" ]; then
                rm -f "$LIST_CACHE"
                echo "[INFO] Cache list dihapus: $LIST_CACHE"
            fi
            if [ -f "$INSTALLED_CACHE" ]; then
                rm -f "$INSTALLED_CACHE"
                echo "[INFO] Cache installed dihapus: $INSTALLED_CACHE"
            fi
            
            # Hapus semua router Mikrotik
            if [ -d "$QEMU_DIR" ]; then
                local count=0
                for dir in "$QEMU_DIR"/mikrotik-*; do
                    if [ -d "$dir" ]; then
                        echo "[INFO] Menghapus: $dir"
                        rm -rf "$dir"
                        count=$((count + 1))
                    fi
                done
                echo "[INFO] $count router Mikrotik dihapus"
            fi
            
            # Perbaiki permission jika perlu
            if [ -x "/opt/unetlab/wrappers/unl_wrapper" ]; then
                echo "[INFO] Memperbaiki permission..."
                /opt/unetlab/wrappers/unl_wrapper -a fixpermissions || true
            fi
            
            echo "[DONE] Cache dan semua router Mikrotik berhasil dihapus"
            ;;
        *)
            echo "[ERROR] Opsi reset tidak valid: $reset_type" >&2
            echo "Gunakan: --cache atau --install" >&2
            return 1
            ;;
    esac
}

update_chr_list() {
    echo "[INFO] Update daftar CHR dari arsip..."
    ensure_cache_dir
    mkdir -p "$WORK_DIR"
    
    # Buat file temporary untuk menyimpan hasil baru
    local temp_list="$WORK_DIR/temp_list.txt"
    : > "$temp_list"

    echo "[INFO] Mengambil daftar versi dari arsip..."
    local versions
    mapfile -t versions < <(get_versions_from_archive)
    if [ ${#versions[@]} -eq 0 ]; then
        echo "[ERROR] Gagal mengambil daftar versi dari arsip." >&2
        return 1
    fi

    echo "[INFO] Ditemukan ${#versions[@]} versi di arsip, membuat daftar download..."
    
    local count=0
    local total_versions=${#versions[@]}
    
    # Tanya user apakah mau cek URL atau tidak
    echo "[INFO] Pilih mode update:"
    echo "  1. Fast mode (tanpa cek URL) - Recommended"
    echo "  2. Safe mode (dengan cek URL) - Lebih lama tapi akurat"
    read -r -p "Pilih (1/2) [default: 1]: " mode_choice
    mode_choice="${mode_choice:-1}"
    
    if [ "$mode_choice" = "2" ]; then
        echo "[INFO] Safe mode: Memeriksa ketersediaan URL..."
        for i in "${!versions[@]}"; do
            local v="${versions[$i]}"
            local current=$((i + 1))
            local progress=$((current * 100 / total_versions))
            
            printf "\r[INFO] Progress: [%-50s] %d%% (%d/%d) - Checking v%s" \
                "$(printf '#%.0s' $(seq 1 $((progress / 2))))" \
                "$progress" "$current" "$total_versions" "$v"
            
            local url="$DOWNLOAD_BASE/$v/chr-$v.img.zip"
            if check_url_exists "$url"; then
                echo "$v $url" >> "$temp_list"
                count=$((count + 1))
            fi
        done
        echo ""
        echo "[INFO] Pemeriksaan selesai: $count dari $total_versions versi tersedia"
    else
        echo "[INFO] Fast mode: Membuat daftar URL download..."
        for i in "${!versions[@]}"; do
            local v="${versions[$i]}"
            local current=$((i + 1))
            local progress=$((current * 100 / total_versions))
            
            printf "\r[INFO] Progress: [%-50s] %d%% (%d/%d) - Processing v%s" \
                "$(printf '#%.0s' $(seq 1 $((progress / 2))))" \
                "$progress" "$current" "$total_versions" "$v"
            
            local url="$DOWNLOAD_BASE/$v/chr-$v.img.zip"
            echo "$v $url" >> "$temp_list"
            count=$((count + 1))
        done
        echo ""
        echo "[INFO] Daftar selesai dibuat: $count versi"
    fi

    # Replace cache dengan data baru
    mv "$temp_list" "$LIST_CACHE"
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
    # Buat temporary directory unik untuk setiap install
    local tmp_dir="$WORK_DIR/install_${version:-$(date +%s)}"
    mkdir -p "$tmp_dir"

    local out_zip="$tmp_dir/chr.zip"
    echo "[INFO] Unduh: $url"
    download_file "$url" "$out_zip"

    echo "[INFO] Ekstrak: $out_zip"
    require_cmd unzip
    unzip -o "$out_zip" -d "$tmp_dir"

    local qcow2_file img_file
    qcow2_file=$(find "$tmp_dir" -maxdepth 1 -type f -name "*.qcow2" | head -n1 || true)
    img_file=$(find "$tmp_dir" -maxdepth 1 -type f -name "*.img" | head -n1 || true)

    if [ -z "$qcow2_file" ] && [ -z "$img_file" ]; then
        echo "[ERROR] Tidak menemukan .qcow2 atau .img di dalam ZIP" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    # Buat target directory setelah download dan extract berhasil
    mkdir -p "$target_dir"

    if [ -n "$qcow2_file" ]; then
        echo "[INFO] Salin QCOW2 ke $target_dir/hda.qcow2"
        cp -f "$qcow2_file" "$target_dir/hda.qcow2"
    elif [ -n "$img_file" ]; then
        require_cmd qemu-img
        echo "[INFO] Konversi RAW IMG -> QCOW2"
        qemu-img convert -f raw -O qcow2 "$img_file" "$target_dir/hda.qcow2"
    fi

    if [ -x "/opt/unetlab/wrappers/unl_wrapper" ]; then
        echo "[INFO] Memperbaiki permission..."
        /opt/unetlab/wrappers/unl_wrapper -a fixpermissions || true
    fi

    # Bersihkan temporary directory
    rm -rf "$tmp_dir"

    echo "[DONE] CHR terpasang di $target_dir"
}

install_multiple() {
    local targets="$1"
    local success_count=0
    local total_count=0
    
    # Split targets by comma or space
    local targets_array
    IFS=', ' read -ra targets_array <<< "$targets"
    
    echo "[INFO] Memulai instalasi multiple versions..."
    echo "[INFO] Targets: ${targets_array[*]}"
    echo ""
    
    for target in "${targets_array[@]}"; do
        # Skip empty targets
        if [ -z "$target" ]; then
            continue
        fi
        
        total_count=$((total_count + 1))
        echo "[INFO] Processing target $total_count: $target"
        
        local url
        # Cek apakah target adalah nomor
        if [[ "$target" =~ ^[0-9]+$ ]]; then
            url="$(get_url_by_number "$target")"
            if [ $? -ne 0 ]; then
                echo "[ERROR] Skip target $target (nomor tidak valid)"
                continue
            fi
        else
            url="$target"
        fi
        
        if install_from_url "$url"; then
            success_count=$((success_count + 1))
        else
            echo "[ERROR] Gagal install target: $target"
        fi
        
        echo ""
    done
    
    echo "[SUMMARY] Instalasi selesai: $success_count/$total_count berhasil"
    if [ $success_count -eq $total_count ]; then
        echo "[SUCCESS] Semua target berhasil diinstall!"
    elif [ $success_count -gt 0 ]; then
        echo "[PARTIAL] Beberapa target berhasil diinstall"
    else
        echo "[FAILED] Tidak ada target yang berhasil diinstall"
        return 1
    fi
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

remove_multiple() {
    local targets="$1"
    local success_count=0
    local total_count=0
    
    # Split targets by comma or space
    local targets_array
    IFS=', ' read -ra targets_array <<< "$targets"
    
    echo "[INFO] Memulai penghapusan multiple versions..."
    echo "[INFO] Targets: ${targets_array[*]}"
    echo ""
    
    for target in "${targets_array[@]}"; do
        # Skip empty targets
        if [ -z "$target" ]; then
            continue
        fi
        
        total_count=$((total_count + 1))
        echo "[INFO] Processing target $total_count: $target"
        
        if remove_chr "$target"; then
            success_count=$((success_count + 1))
        else
            echo "[ERROR] Gagal remove target: $target"
        fi
        
        echo ""
    done
    
    echo "[SUMMARY] Penghapusan selesai: $success_count/$total_count berhasil"
    if [ $success_count -eq $total_count ]; then
        echo "[SUCCESS] Semua target berhasil dihapus!"
    elif [ $success_count -gt 0 ]; then
        echo "[PARTIAL] Beberapa target berhasil dihapus"
    else
        echo "[FAILED] Tidak ada target yang berhasil dihapus"
        return 1
    fi
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
            local targets="$2"
            # Cek apakah ada comma atau space (multiple targets)
            if [[ "$targets" =~ [,\ ] ]]; then
                install_multiple "$targets"
            else
                local url
                # Cek apakah target adalah nomor
                if [[ "$targets" =~ ^[0-9]+$ ]]; then
                    url="$(get_url_by_number "$targets")"
                    if [ $? -ne 0 ]; then
                        exit 1
                    fi
                else
                    url="$targets"
                fi
                install_from_url "$url"
            fi
            ;;
        remove)
            if [ $# -lt 2 ]; then
                echo "[ERROR] Target penghapusan diperlukan" >&2
                print_usage
                exit 1
            fi
            local targets="$2"
            # Cek apakah ada comma atau space (multiple targets)
            if [[ "$targets" =~ [,\ ] ]]; then
                remove_multiple "$targets"
            else
                remove_chr "$targets"
            fi
            ;;
        reset)
            local reset_type="${2:-cache}"
            reset_data "$reset_type"
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
