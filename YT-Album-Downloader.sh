#!/usr/bin/env bash
# ============================================
# descargar_album.sh
# Descarga un álbum completo con yt-dlp con:
#   - Metadatos completos incrustados
#   - Portada del álbum incrustada
#   - Número de pista correcto (track)
#   - Archivos nombrados en orden: 01 - Titulo.ext
#
# Uso:
#   ./descargar_album.sh "URL_DEL_ALBUM" [FORMATO] [CARPETA]
#
# Ejemplos:
#   ./descargar_album.sh "https://music.youtube.com/playlist?list=XXXX"
#   ./descargar_album.sh "https://..." mp3
#   ./descargar_album.sh "https://..." flac "Mis Álbumes/Artista"
# ============================================

set -euo pipefail

# ---------- Argumentos ----------
URL="${1:-}"
FORMATO="${2:-flac}"       # flac, mp3, m4a, opus, wav
CARPETA="${3:-Albumes}"    # carpeta de destino

if [[ -z "$URL" ]]; then
    echo "❌ Error: debes pasar la URL del álbum/playlist."
    echo "Uso: $0 \"URL\" [FORMATO] [CARPETA]"
    exit 1
fi

# ---------- Colores ----------
VERDE='\033[0;32m'
AZUL='\033[0;34m'
ROJO='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${AZUL}[INFO]${NC} $1"; }
ok()    { echo -e "${VERDE}[OK]${NC} $1"; }
error() { echo -e "${ROJO}[ERROR]${NC} $1"; }

# ---------- Verificar dependencias ----------
info "Verificando dependencias..."
FALTA=0
for cmd in yt-dlp ffmpeg; do
    if ! command -v "$cmd" &>/dev/null; then
        error "Falta: $cmd"
        FALTA=1
    fi
done

# atomicparsley solo es necesario para m4a con portada
if [[ "$FORMATO" == "m4a" ]] && ! command -v AtomicParsley &>/dev/null; then
    error "Falta: AtomicParsley (necesario para m4a con portada)"
    FALTA=1
fi

if [[ "$FALTA" -eq 1 ]]; then
    echo ""
    echo "Instala las dependencias:"
    echo "  Ubuntu/Debian: sudo apt install yt-dlp ffmpeg atomicparsley"
    echo "  macOS (brew):  brew install yt-dlp ffmpeg atomicparsley"
    echo "  pip:           pip install -U yt-dlp"
    exit 1
fi
ok "Dependencias OK"

# ---------- Crear carpeta ----------
mkdir -p "$CARPETA"
ok "Carpeta destino: $CARPETA"

# ---------- Descarga ----------
info "Descargando álbum en formato $FORMATO..."
info "URL: $URL"

yt-dlp \
  --yes-playlist \
  --ignore-errors \
  --no-overwrites \
  -x --audio-format "$FORMATO" --audio-quality 0 \
  --embed-metadata \
  --embed-thumbnail \
  --convert-thumbnails jpg \
  --parse-metadata "playlist_index:%(track_number)s" \
  --parse-metadata "title:%(meta_title)s" \
  -o "$CARPETA/%(album|Desconocido)s/%(playlist_index)02d - %(title)s.%(ext)s" \
  --progress \
  "$URL"

# ---------- Resumen ----------
TOTAL=$(find "$CARPETA" -type f \( -name "*.$FORMATO" -o -name "*.flac" -o -name "*.mp3" -o -name "*.m4a" -o -name "*.opus" \) | wc -l)
ok "Descarga completada. Archivos de audio encontrados en '$CARPETA': $TOTAL"

# ---------- Verificación opcional ----------
read -r -p "¿Verificar metadatos de los archivos descargados? (s/n): " RESP
if [[ "${RESP,,}" == "s" ]]; then
    find "$CARPETA" -type f -name "*.flac" -o -name "*.mp3" -o -name "*.m4a" -o -name "*.opus" | sort | while read -r f; do
        echo ""
        echo -e "${AZUL}=== $(basename "$f") ===${NC}"
        ffprobe -v quiet -show_entries format_tags=title,artist,album,track,date -of default=noprint_wrappers=1 "$f" 2>/dev/null || echo "(sin metadatos)"
    done
fi

ok "¡Listo!"
