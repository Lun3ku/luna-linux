# Дефолтная конфигурация оболочки Luna Linux.
# Живёт в /etc/skel, то есть достаётся каждому новому пользователю
# и дальше правится им свободно — обновления пакета её не перезапишут.

if status is-interactive
    # Приветствие fish при каждом запуске никому не нужно.
    set -g fish_greeting

    set -gx EDITOR nvim
    set -gx VISUAL nvim
    set -gx PAGER less
    set -gx MANPAGER 'less -R'

    # ls заменяем — синтаксис совместим, выигрыш очевиден.
    # А вот grep, find, cat и du сознательно НЕ трогаем: у ripgrep, fd и
    # dust другие аргументы, и подмена ломала бы привычные команды и скрипты,
    # которые копируешь из интернета. Они доступны под своими именами.
    alias ls  'eza --group-directories-first --icons=auto'
    alias ll  'eza -l  --group-directories-first --icons=auto --git'
    alias la  'eza -la --group-directories-first --icons=auto --git'
    alias lt  'eza --tree --level=2 --icons=auto'

    # Сокращения раскрываются в полную команду при нажатии пробела,
    # поэтому видно, что именно выполнится.
    abbr -a gs  'git status --short --branch'
    abbr -a gd  'git diff'
    abbr -a ga  'git add'
    abbr -a gc  'git commit'
    abbr -a gl  'git log --oneline --graph --decorate -20'
    abbr -a gp  'git push'
    abbr -a pS  'sudo pacman -S'
    abbr -a pSyu 'sudo pacman -Syu'
    abbr -a pQs 'pacman -Qs'
    abbr -a pRns 'sudo pacman -Rns'

    # Приглашение.
    starship init fish | source

    # cd запоминает, куда ты ходишь: «cd luna» находит каталог из любого места.
    # Обычное поведение cd с путями при этом сохраняется.
    zoxide init fish --cmd cd | source

    # Ctrl+R по истории, Ctrl+T по файлам, Alt+C по каталогам.
    fzf --fish | source
end
