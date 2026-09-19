-- The Hyprland configuration for Luna Linux.
--
-- The format is Lua. In Hyprland 0.56 that is the primary format: it is what
-- the package ships as its example, and what the official wiki is written in.
-- The familiar hyprland.conf still works, but Hyprland itself calls it legacy
-- in its logs, so Luna starts out on the new one.
--
-- Documentation: https://wiki.hypr.land/Configuring/Start/
-- The full API description ships next to Hyprland: /usr/share/hypr/stubs/hl.meta.lua
--
-- Feel free to edit this file, it is yours. A package update will not
-- overwrite it, because it is copied to the user from /etc/skel at creation.

--------------------------------------------------------------------------
-- THE PALETTE
-- Change it here and it changes throughout this config. The same colours are
-- duplicated in waybar/style.css, mako and rofi: keep them in agreement.
--------------------------------------------------------------------------
local luna = {
    accent   = "b4a0ff",   -- lavender, the main one
    accent2  = "8bd5ff",   -- light blue, for the border gradient
    inactive = "2a2739",   -- the border of an inactive window
}

--------------------------------------------------------------------------
-- PROGRAMS
-- Defined once, then used in the key bindings below.
--------------------------------------------------------------------------
local terminal    = "kitty"
local fileManager = "thunar"
local launcher    = "rofi -show drun"
local windowList  = "rofi -show window"
local clipboard   = "cliphist list | rofi -dmenu -p Clipboard | cliphist decode | wl-copy"
local screenArea  = "grim -g \"$(slurp)\" - | swappy -f -"
local screenFull  = "grim - | swappy -f -"

--------------------------------------------------------------------------
-- MONITORS
-- An empty output means "all the rest": it suits a laptop, a virtual machine
-- and an external screen alike, with no edits to this config.
-- https://wiki.hypr.land/Configuring/Basics/Monitors/
--------------------------------------------------------------------------
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

--------------------------------------------------------------------------
-- ENVIRONMENT VARIABLES
-- Without these lines some applications fall back to X11 through XWayland
-- and look blurry at fractional scaling.
--------------------------------------------------------------------------
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

--------------------------------------------------------------------------
-- AUTOSTART
-- Empty, and deliberately so. The panel, the notifications, the wallpaper,
-- the idle lock, the polkit agent and the clipboard history are started by
-- systemd as user units, and systemd restarts them if any of them dies. This
-- works because the session starts through uwsm, which carries the boot all
-- the way to graphical-session.target.
-- graphical-session.target.
--
-- nm-applet was removed from here on purpose: it put a button with no icon
-- into the system tray. The network state is visible in the panel anyway,
-- clicking it opens nmtui, and on the live image the network is managed by
-- systemd-networkd, which the applet has nothing to say to.
--------------------------------------------------------------------------

-- A safety net for when Hyprland was started NOT through uwsm: by hand from
-- a console, say, or by picking the plain Hyprland entry in the login menu.
-- systemd then never brings graphical-session.target up, and the panel, the
-- wallpaper, the notifications and the polkit agent stay dead. Verified:
-- is-active reported inactive for all of them, and XDG_CURRENT_DESKTOP was empty.
-- If the session is already up under uwsm, this check does nothing.
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user is-active -q graphical-session.target || { systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE; systemctl --user start graphical-session.target; }")
end)

--------------------------------------------------------------------------
-- APPEARANCE
-- https://wiki.hypr.land/Configuring/Basics/Variables/
--------------------------------------------------------------------------
hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 12,
        border_size = 2,

        col = {
            -- A gradient from lavender to light blue at 45 degrees.
            active_border   = { colors = { "rgba(" .. luna.accent .. "ee)",
                                           "rgba(" .. luna.accent2 .. "ee)" }, angle = 45 },
            inactive_border = "rgba(" .. luna.inactive .. "aa)",
        },

        -- Resize a window by dragging its border or the gap between windows.
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
        -- A new window inherits the split direction, otherwise the layout
        -- "jumps" every time something opens.
        preserve_split = true,
    },

    misc = {
        -- The stock wallpaper and Hyprland logo are not wanted: the wallpaper
        -- is set by our own unit.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        -- And the joke caption at the bottom of the screen goes too.
        disable_splash_rendering = true,

        -- The colour behind the wallpaper. If hyprpaper somehow failed to
        -- start, the desktop still looks deliberate rather than like a black hole.
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
-- ANIMATIONS
-- The curves and speeds are taken from the reference Hyprland example: they
-- are tuned to make the interface feel fast rather than slowly beautiful.
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
-- TOUCHPAD GESTURES
--------------------------------------------------------------------------
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

--------------------------------------------------------------------------
-- KEY BINDINGS
-- The layout is the one tiling users expect: Super+Enter for a terminal,
-- Super+Q to close a window. The reference Hyprland example has it the other
-- way round (Q starts a terminal), but that throws off everyone coming from
-- i3 or sway.
-- https://wiki.hypr.land/Configuring/Basics/Binds/
--------------------------------------------------------------------------
local mod = "SUPER"

-- Every binding carries a description. It is not decoration: a Lua config
-- reports its dispatcher to hyprctl as "__lua" and its argument as the number
-- of an internal callback, so without these the cheat sheet on Super+/ reads
-- "Super+1  __lua 56" and tells nobody anything. With them it reads
-- "Super+1  Workspace 1". Checked against hyprctl binds -j, which returns the
-- description and sets has_description.

-- Programs
hl.bind(mod .. " + Return",    hl.dsp.exec_cmd(terminal),    { description = "Terminal" })
hl.bind(mod .. " + E",         hl.dsp.exec_cmd(fileManager), { description = "File manager" })
hl.bind(mod .. " + R",         hl.dsp.exec_cmd(launcher),    { description = "Run a program" })
hl.bind(mod .. " + Tab",       hl.dsp.exec_cmd(windowList),  { description = "Switch between windows" })
hl.bind(mod .. " + SHIFT + V", hl.dsp.exec_cmd(clipboard),   { description = "Clipboard history" })

-- Windows
hl.bind(mod .. " + Q",         hl.dsp.window.close(),                     { description = "Close the window" })
hl.bind(mod .. " + F",         hl.dsp.window.fullscreen(),                { description = "Fullscreen" })
hl.bind(mod .. " + V",         hl.dsp.window.float({ action = "toggle" }), { description = "Float the window" })
hl.bind(mod .. " + C",         hl.dsp.window.center(),                    { description = "Centre the window" })
hl.bind(mod .. " + P",         hl.dsp.window.pin(),                       { description = "Pin above the rest" })
hl.bind(mod .. " + T",         hl.dsp.layout("togglesplit"),              { description = "Split sideways or down" })

-- Session
hl.bind(mod .. " + L",         hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock the screen" })
hl.bind(mod .. " + M",         hl.dsp.exec_cmd("hyprshutdown"),          { description = "Shut down, restart, log out" })

-- Screenshots
hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd(screenArea),        { description = "Screenshot a region" })
hl.bind("Print",               hl.dsp.exec_cmd(screenFull),        { description = "Screenshot the whole screen" })
hl.bind(mod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"),   { description = "Pick a colour off the screen" })

-- Tools
-- Super+/ lists the key bindings, asking the running compositor rather
-- than a cheat sheet kept by hand, so it cannot go stale.
-- Super+N forces night mode on or off outside the evening schedule.
hl.bind(mod .. " + slash", hl.dsp.exec_cmd("luna-keys"),  { description = "These key bindings" })
hl.bind(mod .. " + N",     hl.dsp.exec_cmd("luna-night"), { description = "Night mode on or off" })

-- Focus: with the arrow keys and with the vim hjk layout.
--
-- There is no Super+L here, and that is on purpose rather than an
-- oversight: the same key already locks the screen a few lines above.
-- Two bindings on one key is not a thing Hyprland resolves in any way
-- worth relying on, and of the two, locking is the one that must not
-- misfire. Focus to the right is still on Super+Right.
hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }),  { description = "Focus left" })
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Focus right" })
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }),    { description = "Focus up" })
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }),  { description = "Focus down" })
hl.bind(mod .. " + H",     hl.dsp.focus({ direction = "left" }),  { description = "Focus left (vim)" })
hl.bind(mod .. " + K",     hl.dsp.focus({ direction = "up" }),    { description = "Focus up (vim)" })
hl.bind(mod .. " + J",     hl.dsp.focus({ direction = "down" }),  { description = "Focus down (vim)" })

-- Workspaces: Super+digit to switch, Super+Shift+digit to move a window there.
for i = 1, 10 do
    local key = i % 10                      -- the tenth workspace lives on key 0
    hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }),
            { description = "Workspace " .. i })
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }),
            { description = "Move the window to workspace " .. i })
end

-- Switching workspaces with the mouse wheel
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })

-- A separate "pocket" workspace, handy for a messenger or music
hl.bind(mod .. " + S",              hl.dsp.workspace.toggle_special("magic"),
        { description = "The pocket workspace" })
hl.bind(mod .. " + SHIFT + Return", hl.dsp.window.move({ workspace = "special:magic" }),
        { description = "Put the window in the pocket" })

-- Dragging and resizing with the mouse
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Drag the window" })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize the window" })

-- Multimedia keys.
-- locked means they work on a locked screen, repeating means while held.
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, description = "Mute" })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, description = "Mute the microphone" })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true, description = "Brighter screen" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true, description = "Dimmer screen" })
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play or pause" })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Next track" })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Previous track" })

--------------------------------------------------------------------------
-- WINDOW RULES
--------------------------------------------------------------------------
-- The polkit prompt must not get lost behind other windows.
hl.window_rule({
    name  = "float-polkit",
    match = { class = "^(hyprpolkitagent|polkit-gnome-authentication-agent-1)$" },
    float = true,
})

-- The volume control is more convenient as a floating window than tiled.
hl.window_rule({
    name  = "float-pavucontrol",
    match = { class = "^(org.pulseaudio.pavucontrol|pavucontrol)$" },
    float = true,
})
