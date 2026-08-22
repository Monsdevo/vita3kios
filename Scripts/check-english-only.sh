#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

cd "${repo_root}"

scan_args=(
    --hidden
    --glob '!External/**'
    --glob '!Build/**'
    --glob '!CMakeFiles/**'
    --glob '!.git/**'
    --glob '!Scripts/check-english-only.sh'
)

failed=0

if rg -n "${scan_args[@]}" '[çğıöşüÇĞİÖŞÜ]' .; then
    echo "error: Turkish-specific characters were found in repository-owned files." >&2
    failed=1
fi

turkish_words='\b(ayarlar|ayrintili|baslangic|cekirdek|degisiklik|desteklenmiyor|dogrulanir|emulatoru|gosterilir|icerik|kullanici|olacaktir|oyunlar|uygulama|yalnizca)\b'
if rg -n -i -P "${scan_args[@]}" "${turkish_words}" .; then
    echo "error: Common Turkish words were found in repository-owned files." >&2
    failed=1
fi

if (( failed != 0 )); then
    exit 1
fi

echo "English-only repository text check passed."
