#!/usr/bin/env bash
# optlib.sh - funções compartilhadas por videoopt, imgopt e a TUI.
#
# - Histórico de otimizações (arquivo texto TSV, sem dependências)
# - Impressão digital (fingerprint) de arquivos, independente do nome
# - Eventos em JSON lines para a TUI (--events)
# - Detecção de vídeos já eficientes (ffprobe, opcional)

OPT_DATA_DIR="${OPT_DATA_DIR:-${HOME}/.local/share/opt}"
OPT_HISTORY="${OPT_HISTORY:-${OPT_DATA_DIR}/history.tsv}"
OPT_EVENTS="${OPT_EVENTS:-0}"
OPT_FORCE="${OPT_FORCE:-0}"
OPT_EFFICIENT_BPP="${OPT_EFFICIENT_BPP:-0.08}"

export OPT_DATA_DIR OPT_HISTORY OPT_EVENTS OPT_FORCE OPT_EFFICIENT_BPP

mkdir -p "$OPT_DATA_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Arquivos
# ---------------------------------------------------------------------------

opt_file_size() {
    stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1" 2>/dev/null
}

opt_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | cut -d' ' -f1
    else
        md5 -q
    fi
}

# Impressão digital: tamanho + md5 de 3 blocos de 64 KiB (início, meio, fim).
# Não depende do nome nem do caminho. A TUI calcula o mesmo valor em Python.
opt_fingerprint() {
    local file="$1"
    local size
    local digest

    size="$(opt_file_size "$file")" || return 1

    digest="$(
        {
            head -c 65536 "$file"
            dd if="$file" bs=65536 skip=$((size / 2 / 65536)) count=1 2>/dev/null
            tail -c 65536 "$file"
        } | opt_md5
    )"

    printf '%s-%s\n' "$size" "$digest"
}

# ---------------------------------------------------------------------------
# Histórico
# Colunas: fingerprint kind status orig_size new_size data tool param
# status: ok | skip-larger | efficient
# ---------------------------------------------------------------------------

opt_history_has() {
    local fp="$1"

    [[ -f "$OPT_HISTORY" ]] || return 1

    grep -q "^${fp}	" "$OPT_HISTORY" 2>/dev/null
}

opt_history_add() {
    local fp="$1" kind="$2" status="$3" orig="$4" new="$5" tool="$6" param="${7:-}"

    [[ -n "$fp" ]] || return 0

    mkdir -p "$OPT_DATA_DIR" 2>/dev/null || true

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$fp" "$kind" "$status" "$orig" "$new" \
        "$(date '+%Y-%m-%dT%H:%M:%S')" "$tool" "$param" >> "$OPT_HISTORY"
}

# ---------------------------------------------------------------------------
# Eventos (JSON lines no fd 3)
# Uso: opt_emit ev=file i#=3 name="a.mp4"
#   chave terminada em '#' => número; caso contrário => string
# ---------------------------------------------------------------------------

opt_json_escape() {
    printf '%s' "$1" |
        sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
        tr '\t\r\n' '   '
}

opt_emit() {
    [[ "$OPT_EVENTS" == "1" ]] || return 0

    local json=""
    local pair key value

    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"

        if [[ "$key" == *'#' ]]; then
            key="${key%'#'}"
            [[ "$value" =~ ^-?[0-9]+$ ]] || value=0
            json+="\"${key}\":${value},"
        else
            json+="\"${key}\":\"$(opt_json_escape "$value")\","
        fi
    done

    printf '{%s}\n' "${json%,}" >&3
}

# Redireciona stdout/stderr para o log e reserva o fd 3 para os eventos.
opt_events_init() {
    local log_file="$1"

    [[ "$OPT_EVENTS" == "1" ]] || return 0

    exec 3>&1 1>>"$log_file" 2>&1
}

# ---------------------------------------------------------------------------
# Vídeo já eficiente?  (retorna 0 = pode pular)
# Sem ffprobe instalado, nunca pula.
# ---------------------------------------------------------------------------

opt_video_efficient() {
    local file="$1"

    command -v ffprobe >/dev/null 2>&1 || return 1

    local verdict

    verdict="$(
        ffprobe -v error -select_streams v:0 \
            -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate:format=bit_rate \
            -of flat "$file" 2>/dev/null |
        awk -F= -v limit="$OPT_EFFICIENT_BPP" '
            { v = $2; gsub(/"/, "", v) }
            $1 ~ /codec_name$/   { codec = v }
            $1 ~ /\.width$/      { w = v }
            $1 ~ /\.height$/     { h = v }
            $1 ~ /r_frame_rate$/ { fps = v }
            $1 ~ /^streams.*bit_rate$/ { sbr = v }
            $1 ~ /^format.*bit_rate$/  { fbr = v }
            END {
                if (codec == "hevc" || codec == "av1" || codec == "vp9") { print "yes"; exit }
                if (codec != "h264") { print "no"; exit }

                br = (sbr + 0 > 0) ? sbr + 0 : fbr + 0
                split(fps, f, "/")
                rate = (f[2] + 0 > 0) ? f[1] / f[2] : f[1] + 0

                if (br > 0 && w > 0 && h > 0 && rate > 0 && br / (w * h * rate) < limit + 0)
                    print "yes"
                else
                    print "no"
            }
        '
    )"

    [[ "$verdict" == "yes" ]]
}

# ---------------------------------------------------------------------------
# Garante o ffprobe (instala o ffmpeg sozinho, sem perguntar)
# ---------------------------------------------------------------------------

opt_ensure_ffprobe() {
    command -v ffprobe >/dev/null 2>&1 && return 0

    echo "ffprobe não encontrado. Instalando ffmpeg..."
    opt_emit ev=warn msg="ffprobe não encontrado. Instalando ffmpeg..."

    local -a SUDO=()

    if [[ "$(id -u)" != "0" ]]; then
        command -v sudo >/dev/null 2>&1 || return 1

        # Sem terminal (TUI) não há como digitar senha: exige sudo sem senha.
        if [[ "$OPT_EVENTS" == "1" ]]; then
            SUDO=(sudo -n)
        else
            SUDO=(sudo)
        fi
    fi

    if command -v apt-get >/dev/null 2>&1; then
        "${SUDO[@]}" apt-get update -qq &&
            "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y ffmpeg
    elif command -v dnf >/dev/null 2>&1; then
        "${SUDO[@]}" dnf install -y ffmpeg
    elif command -v pacman >/dev/null 2>&1; then
        "${SUDO[@]}" pacman -S --noconfirm ffmpeg
    elif command -v brew >/dev/null 2>&1; then
        brew install ffmpeg
    else
        return 1
    fi

    command -v ffprobe >/dev/null 2>&1
}

export -f opt_file_size opt_md5 opt_fingerprint opt_history_has opt_history_add \
          opt_json_escape opt_emit
