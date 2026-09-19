#!/usr/bin/env bash
# ============================================
# descargar_album.sh  (versión 5 - álbum unificado)
# Descarga un álbum completo con yt-dlp con:
#   - Metadatos completos incrustados (mutagen)
#   - Portada del álbum incrustada, RECORTADA A CUADRADO
#     (sin franjas negras de YouTube)
#   - Número de pista correcto (track)
#   - Archivos nombrados en orden: 01 - Titulo.ext
#   - TODAS las pistas en UNA sola carpeta y con el MISMO tag de álbum
#
# Novedad v5: el nombre del álbum se obtiene UNA sola vez al inicio
# (título de la playlist, o el álbum de la primera pista si no hay
# playlist) y se usa como CONSTANTE para la carpeta. Al terminar la
# descarga, mutagen fuerza el tag "album" con ese mismo nombre en todos
# los archivos. Así, aunque cada pista tenga artistas colaboradores
# distintos (p. ej. la OST de Deltarune: "Toby Fox", "Toby Fox, Laura
# Shigihara", ...), el álbum NUNCA se divide en varias carpetas ni tags
# distintos, funcione con URL de playlist, de álbum de YouTube Music o
# vídeo suelto.
#
# Uso:
#   ./descargar_album.sh "URL_DEL_ALBUM" [FORMATO] [CARPETA] [ARTISTA_ALBUM]
#
# Ejemplos:
#   ./descargar_album.sh "https://music.youtube.com/playlist?list=XXXX"
#   ./descargar_album.sh "https://..." mp3
#   ./descargar_album.sh "https://..." flac "Mis Álbumes/Artista"
#   ./descargar_album.sh "https://..." mp3 Albumes "Toby Fox"
# ============================================

set -euo pipefail

# ---------- Argumentos ----------
URL="${1:-}"
FORMATO="${2:-flac}"       # flac, mp3, m4a, opus, wav
CARPETA="${3:-Albumes}"    # carpeta de destino
ARTISTA_ALBUM="${4:-}"     # artista del álbum (album artist). Si se omite, se autodetecta.

if [[ -z "$URL" ]]; then
    echo "❌ Error: debes pasar la URL del álbum/playlist."
    echo "Uso: $0 \"URL\" [FORMATO] [CARPETA] [ARTISTA_ALBUM]"
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

# mutagen (librería de Python) para incrustar metadatos/portada
if ! python3 -c "import mutagen" &>/dev/null && ! python -c "import mutagen" &>/dev/null 2>&1; then
    error "Falta: mutagen (librería de Python para metadatos)"
    FALTA=1
fi

if [[ "$FALTA" -eq 1 ]]; then
    echo ""
    echo "Instala las dependencias:"
    echo "  Ubuntu/Debian: sudo apt install yt-dlp ffmpeg atomicparsley python3-mutagen"
    echo "  macOS (brew):  brew install yt-dlp ffmpeg atomicparsley"
    echo "  pip:           pip install -U yt-dlp mutagen"
    echo "  pipx:          pipx inject yt-dlp mutagen   (si usaste pipx)"
    exit 1
fi
ok "Dependencias OK"

# ---------- Crear carpeta ----------
mkdir -p "$CARPETA"
ok "Carpeta destino: $CARPETA"

# ---------- Obtener el nombre del álbum UNA sola vez ----------
# FIX v5: antes la carpeta y el tag se construían con campos que cambian
# por pista (%(album)s, o %(playlist_title,album)s cuando no había
# playlist), de modo que con artistas colaboradores el álbum se dividía
# en varias carpetas/tags. Ahora el nombre se calcula una vez y se usa
# como constante para TODAS las pistas.
info "Obteniendo el nombre del álbum..."

# 1) Título de la playlist (idéntico para todas las pistas). Solo leemos
#    la primera entrada, así que es rápido (no descarga nada).
ALBUM_FIJO=$(yt-dlp --flat-playlist --playlist-items 1 \
    --print "%(playlist_title)s" "$URL" 2>/dev/null | head -n1 || true)

# YouTube Music añade a veces el prefijo "Album - "; lo quitamos
ALBUM_FIJO="${ALBUM_FIJO#"Album - "}"

# 2) Si no hay playlist (URL de álbum/vídeo suelto): usamos el álbum de
#    la primera pista con extracción completa (sin descargar)
if [[ -z "$ALBUM_FIJO" || "$ALBUM_FIJO" == "NA" ]]; then
    ALBUM_FIJO=$(yt-dlp --playlist-items 1 --no-download \
        --print "%(album)s" "$URL" 2>/dev/null | head -n1 || true)
fi

# 3) Último recurso
if [[ -z "$ALBUM_FIJO" || "$ALBUM_FIJO" == "NA" ]]; then
    ALBUM_FIJO="Desconocido"
fi

# Limpiar caracteres que rompen rutas de carpeta o el parse-metadata
ALBUM_FIJO=$(printf '%s' "$ALBUM_FIJO" \
    | sed 's#[/:]# - #g; s/|/-/g; s/  */ /g' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

ok "Álbum detectado: $ALBUM_FIJO"

# ---------- Obtener el artista del álbum (album artist) UNA sola vez ----------
# FIX v5: los reproductores (p. ej. Navidrome) agrupan las pistas por
# "album + album artist". Si el album artist difiere por pista (OST con
# colaboradores: "Toby Fox" vs "Toby Fox & @it0ki"), el mismo álbum aparece
# DIVIDIDO en el reproductor aunque las carpetas y el tag album sean iguales.
# Aquí se captura el artista del álbum una vez y se aplica constante a todas
# las pistas, conservando el artista real de cada una en el tag "artist".
if [[ -z "$ARTISTA_ALBUM" ]]; then
    info "Autodetectando el artista del álbum..."
    ARTISTA_ALBUM=$(yt-dlp --playlist-items 1 --no-download \
        --print "%(album_artist)s" "$URL" 2>/dev/null | head -n1 || true)
fi
if [[ -z "$ARTISTA_ALBUM" || "$ARTISTA_ALBUM" == "NA" ]]; then
    ARTISTA_ALBUM=$(yt-dlp --playlist-items 1 --no-download \
        --print "%(artist)s" "$URL" 2>/dev/null | head -n1 || true)
fi
if [[ -z "$ARTISTA_ALBUM" || "$ARTISTA_ALBUM" == "NA" ]]; then
    ARTISTA_ALBUM=$(yt-dlp --playlist-items 1 --no-download \
        --print "%(uploader)s" "$URL" 2>/dev/null | head -n1 || true)
fi
if [[ -z "$ARTISTA_ALBUM" || "$ARTISTA_ALBUM" == "NA" ]]; then
    ARTISTA_ALBUM="Varios Artistas"
fi
ok "Artista del álbum: $ARTISTA_ALBUM"

# ---------- Descarga ----------
info "Descargando álbum en formato $FORMATO..."
info "URL: $URL"
info "Portada: recortada a cuadrado (sin franjas de YouTube)"
info "Álbum: $ALBUM_FIJO (fijo para todas las pistas)"

yt-dlp \
  --yes-playlist \
  --ignore-errors \
  --no-overwrites \
  -x --audio-format "$FORMATO" --audio-quality 0 \
  --embed-metadata \
  --embed-thumbnail \
  --convert-thumbnails jpg \
  --ppa "ThumbnailsConvertor:-vf crop=ih:ih" \
  --parse-metadata "playlist_index:%(track_number)s" \
  --parse-metadata "title:%(meta_title)s" \
  -o "$CARPETA/$ALBUM_FIJO/%(playlist_index,playlist_autonumber)02d - %(title)s.%(ext)s" \
  --progress \
  "$URL"

# ---------- Forzar el tag "album" y "album artist" en todos los archivos ----------
# Las plantillas de yt-dlp no admiten valores por defecto con paréntesis
# (p. ej. "Soundtrack (Official)"), así que aquí se fuerzan los tags con
# mutagen una vez descargado:
#   - album  -> igual en TODAS las pistas (evita dividir el álbum)
#   - album artist -> igual en TODAS las pistas (así el reproductor agrupa
#     todo en un solo álbum aunque cada pista tenga colaboradores distintos).
# El tag "artist" se DEJA tal cual: cada pista conserva sus artistas reales.
info "Forzando tags 'album'=$ALBUM_FIJO y 'album artist'=$ARTISTA_ALBUM..."
python3 - "$CARPETA/$ALBUM_FIJO/" "$ALBUM_FIJO" "$ARTISTA_ALBUM" <<'PY'
import sys
from pathlib import Path
import mutagen
from mutagen.id3 import TALB, TPE2

carpeta, album, album_artist = sys.argv[1], sys.argv[2], sys.argv[3]
exts = {".flac", ".mp3", ".m4a", ".mp4", ".opus", ".ogg", ".wav", ".aac"}
n = 0
for p in Path(carpeta).rglob("*"):
    if not p.is_file() or p.suffix.lower() not in exts:
        continue
    try:
        f = mutagen.File(p)
        if f is None or f.tags is None:
            continue
        if isinstance(f.tags, mutagen.id3.ID3):
            f.tags.add(TALB(encoding=3, text=[album]))
            f.tags.add(TPE2(encoding=3, text=[album_artist]))
        elif isinstance(f.tags, mutagen.mp4.MP4Tags):
            f.tags["\xa9alb"] = [album]
            f.tags["\xa9aART"] = [album_artist]
        else:  # VorbisComment (FLAC/Ogg/Opus) y otros
            f.tags["album"] = [album]
            f.tags["albumartist"] = [album_artist]
        f.save()
        n += 1
    except Exception as e:
        print(f"  aviso: {p.name}: {e}")
print(f"  Tags aplicados a {n} archivos.")
PY

# ---------- Resumen ----------
TOTAL=$(find "$CARPETA" -type f \( -name "*.$FORMATO" -o -name "*.flac" -o -name "*.mp3" -o -name "*.m4a" -o -name "*.opus" \) | wc -l)
ok "Descarga completada. Archivos de audio encontrados en '$CARPETA': $TOTAL"

# ---------- Verificación opcional ----------
read -r -p "¿Verificar metadatos de los archivos descargados? (s/n): " RESP
if [[ "${RESP,,}" == "s" ]]; then
    find "$CARPETA" -type f \( -name "*.flac" -o -name "*.mp3" -o -name "*.m4a" -o -name "*.opus" \) | sort | while read -r f; do
        echo ""
        echo -e "${AZUL}=== $(basename "$f") ===${NC}"
        ffprobe -v quiet -show_entries format_tags=title,artist,album_artist,album,track,date -of default=noprint_wrappers=1 "$f" 2>/dev/null || echo "(sin metadatos)"
    done
fi

ok "¡Listo!"