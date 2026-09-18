#!/usr/bin/env bash
# Автоматический прогон установщика с ответами по умолчанию.
#
# Регрессионный тест: проверяет, что установка проходит целиком, не требуя
# сидеть за клавиатурой. Порядок нажатий соответствует текущим экранам
# установщика — добавишь или уберёшь экран, поправь и здесь.
#
# Запускать ПОСЛЕ старта виртуалки с чистым диском:
#     rm -f /var/luna/test-disk.qcow2
#     scripts/test-iso.sh --install --vnc     (в одном процессе)
#     scripts/test-install-auto.sh            (в другом)
set -uo pipefail
L='/mnt/c/Users/anyah/Documents/Claudes work/luna/scripts'
SHOT=${SHOT:-/var/luna}
t() { bash "$L/vm-type.sh" "$@" >/dev/null; sleep "${DELAY:-3}"; }

echo "== жду загрузку живого образа =="
sleep 125

echo "== открываю терминал и запускаю установщик =="
t meta_l+ret
sleep 8
t 'sudo luna-install' ret
sleep 8

echo "== прохожу экраны =="
t ret                 # Welcome -> Continue
t ret                 # Keymap  -> us
t ret                 # Region  -> UTC (первый пункт, экран города пропускается)
t ret                 # Disk    -> /dev/vda
t ret                 # Scheme  -> auto
t left ret            # Confirm erase -> Erase
t ret                 # Hostname -> luna
t 'anya' ret          # User
t 'lunatest' ret      # Password
t 'lunatest' ret      # Password again
t ret                 # Kernel  -> linux
t ret                 # Profile -> desktop
bash "$L/vm-screenshot.sh" "$SHOT/auto-summary.png" >/dev/null
t left ret            # Summary -> Install

echo "== установка пошла, жду =="
for i in $(seq 1 40); do
    sleep 30
    bash "$L/vm-screenshot.sh" "$SHOT/auto-progress.png" >/dev/null 2>&1 || true
done
