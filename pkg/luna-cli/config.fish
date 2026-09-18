# The default shell configuration of Luna Linux.
# It lives in /etc/skel, so every new user gets a copy and is then free to edit
# it; a package update will not overwrite it.

if status is-interactive
    # Nobody needs the fish greeting on every start.
    set -g fish_greeting

    set -gx EDITOR nvim
    set -gx VISUAL nvim
    set -gx PAGER less
    set -gx MANPAGER 'less -R'

    # ls is replaced: the syntax is compatible and the gain is obvious.
    # grep, find, cat and du are deliberately left alone: ripgrep, fd and dust
    # take different arguments, and shadowing the originals would break
    # familiar commands and the scripts one copies off the internet. They are
    # all available under their own names.
    alias ls  'eza --group-directories-first --icons=auto'
    alias ll  'eza -l  --group-directories-first --icons=auto --git'
    alias la  'eza -la --group-directories-first --icons=auto --git'
    alias lt  'eza --tree --level=2 --icons=auto'

    # Abbreviations expand into the full command when space is pressed, so it
    # is visible what is about to run.
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

    # The prompt.
    starship init fish | source

    # cd remembers where you go: "cd luna" finds the directory from anywhere.
    # The ordinary behaviour of cd with a path is preserved.
    zoxide init fish --cmd cd | source

    # Ctrl+R through history, Ctrl+T through files, Alt+C through directories.
    fzf --fish | source
end
