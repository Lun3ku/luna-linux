#!/usr/bin/env bash
# Собирает картинки брендинга из SVG-исходников.
#
# Исходники лежат в branding/ и правятся текстом; PNG — производные и
# перегенерируются этой командой. Так брендинг версионируется осмысленно,
# а не как непрозрачные двоичные файлы.
#
# Рендерит rsvg-convert из librsvg. Он уже есть на сборочном хосте как
# зависимость gtk, поэтому отдельный imagemagick не нужен.
set -euo pipefail

LUNA_SRC=${LUNA_SRC:-/mnt/c/Users/anyah/Documents/Claudes work/luna}
SVG="$LUNA_SRC/branding"

msg() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!!\033[0m %s\n' "$*" >&2; exit 1; }

command -v rsvg-convert >/dev/null || die "нет rsvg-convert (пакет librsvg)"

render() { # исходник ширина высота приёмник
  rsvg-convert -w "$2" -h "$3" -o "$4" "$1"
  printf '  %-52s %s\n' "$(basename "$4")" "$(du -h "$4" | cut -f1)"
}

msg "Заставка загрузочного меню (syslinux, BIOS)"
render "$SVG/splash.svg" 640 480 "$LUNA_SRC/iso/syslinux/splash.png"

# 16:9, а не 4:3. GRUB растягивает фон на весь экран, не сохраняя
# пропорции: отрендеренная в 4:3 луна на широком экране становилась
# заметно эллиптической.
msg "Фон загрузчика GRUB"
render "$SVG/splash.svg" 1920 1080 "$LUNA_SRC/pkg/luna-base/grub-background.png"

msg "Водяной знак загрузочной заставки Plymouth"
render "$SVG/plymouth-watermark.svg" 200 200 "$LUNA_SRC/pkg/luna-base/plymouth-watermark.png"

msg "Готово"
