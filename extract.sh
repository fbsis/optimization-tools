#!/usr/bin/env bash
#
# extract.sh - descompacta um arquivo (rar / zip / 7z) e, em seguida, extrai
# recursivamente os compactados que encontrarem dentro dele, mostrando um painel
# ao vivo: barra, porcentagem, tamanho, velocidade e tempo restante.
#
# Uso:
#   ./extract.sh <arquivo.(rar|zip|7z)> [destino]
#
# Exemplo:
#   ./extract.sh "/mnt/tmp-downloads/PB Nikole 76 Pic Sets 15 Vids/PB Nikole 76 Pic Sets 15 Vids.rar"
#
set -uo pipefail

FILE="${1:-}"
DEST="${2:-}"

if [[ -z "$FILE" ]]; then
    echo "uso: $0 <arquivo.(rar|zip|7z)> [destino]" >&2
    exit 2
fi
if [[ ! -e "$FILE" ]]; then
    echo "não encontrado: $FILE" >&2
    exit 2
fi

FILE="$(realpath "$FILE")"
[[ -n "$DEST" ]] || DEST="$(dirname "$FILE")/$(basename "${FILE%.*}")"
mkdir -p "$DEST"

# ---------------------------------------------------------------- cores --
COLS="${COLUMNS:-$(tput cols 2>/dev/null || echo 84)}"
(( COLS > 100 )) && COLS=100
BARW=$(( COLS - 38 )); (( BARW < 12 )) && BARW=12

B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0m'
G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; E=$'\033[31m'
EL=$'\033[2K'

hr()   { printf '%s\n' "${D}$(printf '─%.0s' $(seq 1 $((COLS-1))))${R}"; }
hb()   { numfmt --to=iec-i --suffix=B --format='%.1f' "${1:-0}" 2>/dev/null || echo "${1:-0}"; }
tm()   { local s=${1%.*}; (( s < 0 )) && s=0; printf '%02d:%02d:%02d' $((s/3600)) $(((s%3600)/60)) $((s%60)); }
mkbar() {
    local f w n i o=""
    f="${1:-0}"; w="${2:-20}"
    f=$(awk "BEGIN{x=$f; if(x<0)x=0; if(x>1)x=1; printf \"%.4f\", x}")
    n=$(awk "BEGIN{printf \"%d\", $f*$w}")
    for ((i=0;i<n;i++));     do o+="█"; done
    for ((i=n;i<w;i++));     do o+="░"; done
    printf '%s' "$o"
}

# tamanho descompactado do arquivo
total_of() {
    local f="$1"
    case "${f,,}" in
        *.zip)      unzip -l "$f" 2>/dev/null | awk 'END{print $1+0}' ;;
        *.rar|*.7z) 7z l "$f" 2>/dev/null | awk '$1 ~ /^[0-9]{4}-/ && / files/ {print $3; exit}' ;;
        *)          echo 0 ;;
    esac
}

# extrai um arquivo para um destino (silencioso; o progresso é lido do destino)
do_extract() {
    local f="$1" d="$2"
    case "${f,,}" in
        *.rar) unrar x -o+ -inul "$f" "$d/" ;;
        *.zip) unzip -o -qq "$f" -d "$d" ;;
        *.7z)  7z x -y -bd -bso0 -bsp0 -o"$d" "$f" ;;
        *)     return 1 ;;
    esac
}

# painel: acompanha <pid> medindo o crescimento de <dir> a partir de <base>
progress() {
    local pid="$1" dir="$2" base="$3" total="$4" tag="$5" log="$6"
    local t0 last_t last_s cur dt speed frac eta files atual

    t0=$(date +%s); last_t=$t0; last_s=$base; speed=0

    while kill -0 "$pid" 2>/dev/null; do
        sleep 0.5
        local now; now=$(date +%s)
        cur=$(du -sb "$dir" 2>/dev/null | awk '{print $1}'); cur=${cur:-0}
        local done=$(( cur - base )); (( done < 0 )) && done=0

        dt=$(( now - last_t ))
        if (( dt >= 1 )); then
            speed=$(( (cur-last_s)/dt )); (( speed < 0 )) && speed=0
            last_t=$now; last_s=$cur
        fi

        if (( total > 0 )); then frac=$(awk "BEGIN{printf \"%.4f\", $done/$total}"); else frac=0; fi
        if (( speed > 0 && total > 0 )); then eta=$(awk "BEGIN{printf \"%d\", ($total-$done)/$speed}"); else eta=0; fi

        files=$(find "$dir" -type f 2>/dev/null | wc -l)
        atual=$(grep -aoE 'Extracting .*' "$log" 2>/dev/null | tail -1 | sed -E 's/^Extracting +//; s/ +OK$//' | cut -c1-$((BARW+6)))

        printf '%s\r' "$EL"
        printf '  %s %s   %s / %s\n' "$(mkbar "$frac" "$BARW")" \
            "${B}$(awk "BEGIN{printf \"%5.1f%%\", $frac*100}")${R}" "$(hb "$done")" "$(hb "$total")"
        printf '%s\r' "$EL"
        printf '  %s  %s/s  restam %s  %s\n' "$tag" "${G}$(hb "$speed")${R}" "${Y}$(tm "$eta")${R}" "${D}${files} arq${R}"
        printf '%s\r' "$EL"
        printf '  %s %s\n' "${D}atual:${R}" "${atual:-...}"
        printf '\033[3A'
    done

    wait "$pid"; local rc=$?
    printf '\033[3B'
    return $rc
}

# ----------------------------------------------------------------- fluxo --
printf '%s\n' "${B}${C}DESCOMPACTAR${R}"
printf '  %s  %s\n' "${B}$(basename "$FILE")${R}" "${D}$(hb "$(stat -c%s "$FILE" 2>/dev/null)")${R}"
printf '  %s %s\n' "${D}destino:${R}" "$DEST"
hr

# 1) arquivo principal
TOT="$(total_of "$FILE")"; LOG="$(mktemp)"
printf '%s\n' "${B}[1]${R} ${B}$(basename "$FILE")${R}  ${D}$(hb "$TOT") descompactados${R}"
do_extract "$FILE" "$DEST" >"$LOG" 2>&1 &
progress $! "$DEST" 0 "$TOT" "extraindo:" "$LOG"; RC=$?
rm -f "$LOG"

if (( RC != 0 )) && [[ "$(find "$DEST" -type f 2>/dev/null | wc -l)" == "0" ]]; then
    printf '\n%s\n' "${E}✗ falhou ao extrair $(basename "$FILE")${R}"
    exit 1
fi

# 2) compactados internos (recursivo)
shopt -s nullglob nocaseglob
while :; do
    mapfile -t LIST < <(find "$DEST" -type f \( -iname '*.7z' -o -iname '*.zip' -o -iname '*.rar' \) 2>/dev/null | sort)
    (( ${#LIST[@]} == 0 )) && break

    printf '\n'; hr
    printf '%s\n' "${B}[2]${R} ${B}compactados internos${R}  ${D}(${#LIST[@]})${R}"
    hr

    n=0
    for f in "${LIST[@]}"; do
        (( n++ ))
        t="$(total_of "$f")"
        log="$(mktemp)"; base=$(du -sb "$(dirname "$f")" 2>/dev/null | awk '{print $1}'); base=${base:-0}

        do_extract "$f" "$(dirname "$f")" >"$log" 2>&1 &
        progress $! "$(dirname "$f")" "$base" "$t" "[$n/${#LIST[@]}] ${B}$(basename "$f")${R}" "$log"; rc=$?
        rm -f "$log"

        if (( rc == 0 )); then
            printf '  %s %s\n' "${G}✓${R}" "$(basename "$f")"
            rm -f -- "$f"
        else
            printf '  %s %s %s\n' "${Y}⚠${R}" "$(basename "$f")" "${D}(mantido)${R}"
        fi
    done
done
shopt -u nullglob nocaseglob

hr
printf '%s\n' "${G}${B}✓ Concluído${R}  ${D}$DEST${R}"
printf '  %s %s   %s %s\n' "${D}arquivos:${R}" "$(find "$DEST" -type f 2>/dev/null | wc -l)" \
    "${D}tamanho:${R}" "$(du -sh "$DEST" 2>/dev/null | cut -f1)"
