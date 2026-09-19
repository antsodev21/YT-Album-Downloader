# Información del Script
Bueno, resulta que necesitaba descargar un álbum de música de un anime y con yt-dlp pude descargarlo pero no seguía el orden que debía así que le pregunte a Kimi que como se haría para solucionar este fallo y me creo un script que usa yt-dlp, necesita un modulo de Python llamado mutagen y depende de ffmpeg, para convertirlo a mp3 o flac.
Volví a probar a descargarlo y no solo lo descargo como debía sino que también lo convirtió a flac.

Como me pareció buen script a pesar que este vibecodeado pues lo subo a GitHub por si alguien quiere descargar algún álbum entero sin complicarse con todas las flags que usa yt-dlp

# Instalación :
Lo primero es descargar las dependencias que son : python, pip, pipx, ffmpeg y mutagen, el mutagen es muy importante que este instalado ya que tiene relación con el tema de metadatos y si los metadatos no están correctos pueden haber fallos con la organización del álbum y otras cosas.

**En Debian :** 
- ```sudo apt install pip pipx ffmpeg```

**En Arch :**
- ```sudo pacman -S python-pip python-pipx ffmpeg```

**En Void :**
- ```sudo xbps-install python3-pip python3-pipx ffmpeg```

**Después :**
- ```pipx install yt-dlp```
- ```pipx install mutagen```
- ```pipx inject yt-dlp mutagen```
