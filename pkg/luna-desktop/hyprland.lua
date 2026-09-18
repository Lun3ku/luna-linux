-- Конфигурация Hyprland для Luna Linux.
--
-- Формат — Lua. В Hyprland 0.56 это основной формат: именно его пакет везёт
-- как пример, и на нём написана официальная вики. Привычный hyprland.conf
-- тоже ещё работает, но сам Hyprland называет его legacy в своих логах,
-- поэтому Luna сразу на новом.
--
-- Документация: https://wiki.hypr.land/Configuring/Start/
-- Полное описание API лежит рядом с Hyprland: /usr/share/hypr/stubs/hl.meta.lua
--
-- Файл можно смело править — он ваш. Обновление пакета его не перезапишет,
-- потому что пользователю он копируется из /etc/skel при создании.

--------------------------------------------------------------------------
-- ПАЛИТРА
-- Меняешь здесь — меняется во всём конфиге. Те же цвета продублированы
-- в waybar/style.css, mako и rofi: держи их в согласии.
--------------------------------------------------------------------------
local luna = {
    accent   = "b4a0ff",   -- лавандовый, основной
    accent2  = "8bd5ff",   -- голубой, для градиента рамки
    inactive = "2a2739",   -- рамка неактивного окна
}

--------------------------------------------------------------------------
-- ПРОГРАММЫ
-- Задаются один раз, дальше используются в горячих клавишах.
--------------------------------------------------------------------------
local terminal    = "kitty"
local fileManager = "thunar"
local launcher    = "rofi -show drun"
local windowList  = "rofi -show window"
local clipboard   = "cliphist list | rofi -dmenu -p Буфер | cliphist decode | wl-copy"
local screenArea  = "grim -g \"$(slurp)\" - | swappy -f -"
local screenFull  = "grim - | swappy -f -"

--------------------------------------------------------------------------
-- МОНИТОРЫ
-- Пустой output означает «все остальные»: подходит и ноутбуку, и виртуалке,
-- и внешнему экрану без правки конфига.
-- https://wiki.hypr.land/Configuring/Basics/Monitors/
--------------------------------------------------------------------------
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

--------------------------------------------------------------------------
-- ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ
-- Без этих строк часть приложений уходит в режим X11 через XWayland
-- и выглядит размыто при дробном масштабе.
--------------------------------------------------------------------------
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

--------------------------------------------------------------------------
-- АВТОЗАПУСК
-- Пусто, и это осознанно. Панель, уведомления, обои, автоблокировку,
-- агент прав и историю буфера обмена поднимает systemd как юниты
-- пользователя — он же их перезапустит, если что-то упадёт. Работает это
-- потому, что сеанс стартует через uwsm, который доводит загрузку до
-- graphical-session.target.
--
-- nm-applet отсюда убран намеренно: он показывал в системном лотке
-- кнопку без иконки. Состояние сети и так видно в панели, по клику на
-- неё открывается nmtui, а на живом образе сетью управляет
-- systemd-networkd, с которым апплету и говорить не о чем.
--------------------------------------------------------------------------

-- Страховка на случай, когда Hyprland запустили НЕ через uwsm: например
-- вручную из консоли или выбрав в меню входа обычный пункт Hyprland.
-- Тогда systemd не поднимает graphical-session.target, и панель, обои,
-- уведомления и агент прав остаются мёртвыми. Проверено: is-active
-- показывал inactive у всех, а XDG_CURRENT_DESKTOP был пуст.
-- Если сеанс уже поднят uwsm, проверка ничего не делает.
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user is-active -q graphical-session.target || { systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE; systemctl --user start graphical-session.target; }")
end)

--------------------------------------------------------------------------
-- ВНЕШНИЙ ВИД
-- https://wiki.hypr.land/Configuring/Basics/Variables/
--------------------------------------------------------------------------
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 12,
        border_size = 2,

        col = {
            -- Градиент от лавандового к голубому под 45 градусов.
            active_border   = { colors = { "rgba(" .. luna.accent .. "ee)",
                                           "rgba(" .. luna.accent2 .. "ee)" }, angle = 45 },
            inactive_border = "rgba(" .. luna.inactive .. "aa)",
        },

        -- Менять размер окна, потянув за рамку или промежуток между окнами.
        resize_on_border = true,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 3,
            color        = 0x44000000,
        },

        blur = {
            enabled = true,
            size    = 6,
            passes  = 2,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        -- Новое окно наследует направление деления, иначе раскладка
        -- «прыгает» при каждом открытии.
        preserve_split = true,
    },

    misc = {
        -- Штатные обои и логотип Hyprland не нужны: обои ставит hyprpaper.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        -- И подпись-шутку внизу экрана тоже убираем.
        disable_splash_rendering = true,

        -- Цвет под обоями. Если hyprpaper почему-то не поднялся, рабочий
        -- стол всё равно выглядит намеренно, а не как чёрный провал.
        background_color = "rgb(12111a)",
    },

    input = {
        kb_layout    = "us,ru",
        kb_options   = "grp:alt_shift_toggle,caps:escape",
        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
        },
    },
})

--------------------------------------------------------------------------
-- АНИМАЦИИ
-- Кривые и скорости взяты из эталонного примера Hyprland: они выверены
-- так, чтобы интерфейс казался быстрым, а не медленно-красивым.
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
--------------------------------------------------------------------------
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}    } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}  } })
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",     enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",     enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",  enabled = true, speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",     enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",    enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",     enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",   enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",  enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

--------------------------------------------------------------------------
-- ЖЕСТЫ ТАЧПАДА
--------------------------------------------------------------------------
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

--------------------------------------------------------------------------
-- ГОРЯЧИЕ КЛАВИШИ
-- Раскладка привычная для тайлингов: Super+Enter — терминал,
-- Super+Q — закрыть окно. В эталонном примере Hyprland наоборот
-- (Q запускает терминал), но это сбивает всех, кто пришёл из i3 или sway.
-- https://wiki.hypr.land/Configuring/Basics/Binds/
--------------------------------------------------------------------------
local mod = "SUPER"

-- Программы
hl.bind(mod .. " + Return",    hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + E",         hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + R",         hl.dsp.exec_cmd(launcher))
hl.bind(mod .. " + Tab",       hl.dsp.exec_cmd(windowList))
hl.bind(mod .. " + SHIFT + V", hl.dsp.exec_cmd(clipboard))

-- Окна
hl.bind(mod .. " + Q",         hl.dsp.window.close())
hl.bind(mod .. " + F",         hl.dsp.window.fullscreen())
hl.bind(mod .. " + V",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + C",         hl.dsp.window.center())
hl.bind(mod .. " + P",         hl.dsp.window.pin())
hl.bind(mod .. " + T",         hl.dsp.layout("togglesplit"))

-- Сеанс
hl.bind(mod .. " + L",         hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mod .. " + M",         hl.dsp.exec_cmd("hyprshutdown"))

-- Снимки экрана
hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd(screenArea))
hl.bind("Print",               hl.dsp.exec_cmd(screenFull))
hl.bind(mod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"))

-- Фокус: стрелками и по vim-раскладке hjkl
hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + H",     hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + L",     hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + K",     hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + J",     hl.dsp.focus({ direction = "down" }))

-- Рабочие столы: Super+цифра — перейти, Super+Shift+цифра — унести окно.
for i = 1, 10 do
    local key = i % 10                      -- десятый стол живёт на клавише 0
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Переключение столов колесом мыши
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Отдельный «карманный» стол — удобно держать там мессенджер или музыку
hl.bind(mod .. " + S",             hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + Return", hl.dsp.window.move({ workspace = "special:magic" }))

-- Перетаскивание и изменение размера мышью
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Мультимедийные клавиши.
-- locked — работают и на заблокированном экране, repeating — при удержании.
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

--------------------------------------------------------------------------
-- ПРАВИЛА ОКОН
--------------------------------------------------------------------------
-- Окно запроса прав не должно теряться за другими.
hl.window_rule({
    name  = "float-polkit",
    match = { class = "^(hyprpolkitagent|polkit-gnome-authentication-agent-1)$" },
    float = true,
})

-- Регулятор звука удобнее плавающим окном, а не во всю раскладку.
hl.window_rule({
    name  = "float-pavucontrol",
    match = { class = "^(org.pulseaudio.pavucontrol|pavucontrol)$" },
    float = true,
})
