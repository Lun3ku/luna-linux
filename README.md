# Luna Linux

Дистрибутив на базе Arch: самое свежее стабильное ядро, Hyprland из коробки,
только QoL-функции. Пакетный менеджер — pacman.

`NAME="Luna Linux"`, `ID=luna`.

## Окружение сборки

Сборка идёт не в Windows, а в отдельном WSL-дистрибутиве Arch — `LunaBuild`,
лежит на диске **E:** (`E:\WSL\LunaBuild`), потому что на C: не хватает места,
а сборке нужно 15–25 ГБ. Существующий `PistachioLinux` не затрагивается.

Исходники живут здесь, на диске Windows, — это текст, единицы мегабайт.
Тяжёлая работа идёт на ext4 внутри `LunaBuild` в `/var/luna`.

| Что | Где |
|---|---|
| Исходники | `C:\Users\anyah\Documents\Claudes work\luna` |
| Они же из WSL | `/mnt/c/Users/anyah/Documents/Claudes work/luna` |
| Копия профиля на ext4 | `/var/luna/src` |
| Рабочий каталог mkarchiso | `/var/luna/work` |
| Готовые ISO | `/var/luna/out` |

Создание хоста с нуля (из PowerShell):

```powershell
wsl --install archlinux --name LunaBuild --location E:\WSL\LunaBuild --vhd-size 50GB --no-launch
wsl -d LunaBuild -u root -- bash '/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts/bootstrap-host.sh'
```

## Рабочий цикл

Все скрипты запускаются внутри `LunaBuild` от root:

```powershell
wsl -d LunaBuild -u root -- bash '/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts/<скрипт>'
```

| Скрипт | Что делает |
|---|---|
| `bootstrap-host.sh` | Разовая подготовка сборочного хоста. Идемпотентен. |
| `check-packages.sh` | Проверяет, что имена пакетов существуют в репозиториях. Arch — rolling, пакеты переименовывают. |
| `make-branding.sh` | Рендерит PNG брендинга из SVG-исходников в `branding/`. |
| `lint-configs.sh` | Проверяет синтаксис всех конфигов Luna. Битый конфиг оборачивается не ошибкой сборки, а неработающим рабочим столом. |
| `build-pkgs.sh` | Собирает пакеты `luna-*` и обновляет локальный репозиторий. |
| `build-iso.sh` | Синхронизирует профиль на ext4 и запускает `mkarchiso`. |
| `test-iso.sh` | Поднимает собранный образ в QEMU. |
| `test-install-auto.sh` | Автоматически проходит установщик с ответами по умолчанию. Регрессионный тест. |
| `vm-screenshot.sh` | Снимок экрана виртуалки через QMP. |
| `zoom-shot.py` | Вырезает область снимка и увеличивает — разглядывать панель в 36 пикселей иначе невозможно. |
| `vm-type.sh` | Ввод с клавиатуры в виртуалку через QMP, включая сочетания клавиш. |
| `vm-view.sh` | Веб-клиент noVNC для просмотра виртуалки в браузере. |

Для отладки сборку можно сильно ускорить, пожертвовав размером образа:

```bash
LUNA_COMP_LEVEL=3 ./scripts/build-iso.sh
```

## Как смотреть на виртуалку

Окно WSLg всплывает не на всех машинах, поэтому основной способ — браузер.
В двух разных долгоживущих процессах:

```powershell
wsl -d LunaBuild -u root -- bash '/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts/vm-view.sh'
wsl -d LunaBuild -u root -- bash '/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts/test-iso.sh' --vnc
```

Затем открыть:

```
http://localhost:8080/novnc/vnc.html?host=localhost&port=5700&path=&autoconnect=true&resize=scale&reconnect=true
```

`path=` обязателен и должен быть пустым: noVNC по умолчанию подключается к
`/websockify`, а встроенный websocket QEMU отдаёт VNC только по корню `/`
и на любой другой путь отвечает 404.

Не требующий браузера способ — снять кадр прямо из работающей VM:

```bash
./scripts/vm-screenshot.sh /путь/куда/положить.png
```

## Структура

```
branding/ SVG-исходники заставок и логотипа
iso/     профиль archiso (основан на releng)
pkg/     свои пакеты: luna-base, luna-cli, luna-desktop, luna-installer, luna-keyring
repo/    собранный локальный репозиторий pacman
scripts/ сборка и запуск
docs/    заметки по решениям
```

## Пакеты Luna

| Пакет | Что внутри | Где нужен |
|---|---|---|
| `luna-release` | Только `os-release` и идентификация системы. Ни от чего не зависит. | Образ и установленная система |
| `luna-base` | База (`base`, `base-devel`) и надёжность: btrfs + snapper + snap-pac, GRUB + grub-btrfs, zram, systemd-oomd, автоочистка кэша, зеркала. | Только установленная система |
| `luna-cli` | `fish` + `starship` и современный набор утилит с готовыми настройками в `/etc/skel`. | Образ и установленная система |
| `luna-desktop` | Hyprland, waybar, rofi, mako, экран входа, тема, обои. Конфиги в `/etc/skel`. | Образ и установленная система |
| `luna-keyring` | Публичный ключ, которым подписаны пакеты `luna-*`. | Образ и установленная система |

`luna-base` сознательно **не** попадает на загрузочный образ: он тянет
`base-devel` (+307 МБ), а компилятор на live-флешке не нужен. Ради этого
брендинг и вынесен в отдельный крошечный `luna-release`.

Ядро в зависимостях не указано: пользователь выбирает `linux` или
`linux-zen` в установщике, а `-headers` обязаны соответствовать выбранному
ядру. Пару «ядро + headers» ставит установщик.

## Подпись пакетов

Пакеты `luna-*` подписаны, и репозиторий `[luna]` объявлен с
`SigLevel = Required DatabaseOptional` — как официальные репозитории Arch.
Неподписанный или подписанный чужим ключом пакет установлен не будет.

Цепочка доверия устроена так:

1. `scripts/build-pkgs.sh` подписывает каждый пакет, а `repo-add
   --include-sigs` кладёт подпись внутрь базы репозитория.
2. Пакет `luna-keyring` несёт публичный ключ в
   `/usr/share/pacman/keyrings/` и попадает на образ.
3. На живом образе `pacman-init.service` при каждой загрузке наполняет
   связку ключей всем, что лежит в этом каталоге, — включая наш ключ.
4. Установщик ставит `luna-keyring` на целевой диск, поэтому после
   перезагрузки система проверяет подписи своих обновлений сама.

Секретная часть ключа живёт **только** в `~builder/.gnupg` на сборочной
машине и в репозиторий не попадает. Резервная копия и порядок
восстановления — `E:\Luna-Linux-Keys\README.txt`.

Создать ключ заново (нужно один раз или после потери):

```bash
./scripts/make-signing-key.sh
```

## Как добавить пакет

Смысл определяет место:

- **на загрузочный образ** (инструменты установки, live-окружение) —
  в [iso/packages.x86_64](iso/packages.x86_64);
- **на установленную машину** — в `pkg/luna-*/depends.txt`, тогда пакет
  приедет с нашим метапакетом и будет обновляться обычным `pacman -Syu`.

Дальше:

```bash
./scripts/check-packages.sh pkg/luna-desktop/depends.txt   # имена существуют?
./scripts/build-pkgs.sh luna-desktop                      # пересобрать пакет
./scripts/build-iso.sh                                    # пересобрать образ
```

Проверка имён обязательна: Arch — rolling, пакеты переименовывают и
выкидывают, и узнавать об этом в середине сборки образа неприятно.

Подробности принятых решений и неочевидных фактов — в
[docs/decisions.md](docs/decisions.md).

Конфигурация Luna оформляется **настоящими пакетами pacman**, а не оверлеем
`airootfs`: оверлей существует только на live-ISO и на установленную машину не
попадает, а нам нужно, чтобы поставленная система получала те же дефолты и
обновляла их обычным `pacman -Syu`.
