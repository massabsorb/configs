pcall(require, "luarocks.loader")

-- Загрузка модулей
local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")
local wibox = require("wibox")
local beautiful = require("beautiful")
local naughty = require("naughty")
local menubar = require("menubar")
local hotkeys_popup = require("awful.hotkeys_popup")
require("awful.hotkeys_popup.keys")

-- ===== НАСТРОЙКИ =====
local APPS = {
    terminal = "kitty",
    editor = os.getenv("EDITOR") or "nano",
    launcher = "rofi -show drun -theme ~/.config/rofi/config.rasi",
    volume_control = "pavucontrol",
    emoji = "rofi -modi emoji -show emoji",
}

APPS.editor_cmd = APPS.terminal .. " -e " .. APPS.editor
local modkey = "Mod4"

-- ===== АВТОЗАПУСК =====
awful.spawn("picom -b")
awful.spawn("setxkbmap -layout us,ru -option grp:alt_shift_toggle,grp_led:scroll", false)

-- ===== ОБРАБОТКА ОШИБОК =====
if awesome.startup_errors then
    naughty.notify({
        preset = naughty.config.presets.critical,
        title = "Oops, there were errors during startup!",
        text = awesome.startup_errors
    })
end

do
    local in_error = false
    awesome.connect_signal("debug::error", function(err)
        if in_error then return end
        in_error = true
        naughty.notify({
            preset = naughty.config.presets.critical,
            title = "Oops, an error happened!",
            text = tostring(err)
        })
        in_error = false
    end)
end

-- ===== ТЕМА =====
beautiful.init(gears.filesystem.get_configuration_dir() .. "theme.lua")
beautiful.font = "Fira Code Retina 13"
beautiful.icon_font = beautiful.icon_font or "Symbols Nerd Font Mono 20"

-- Цветовая схема
beautiful.bg_normal     = "#000000"
beautiful.bg_focus      = "#000000"
beautiful.bg_urgent     = "#000000"
beautiful.bg_minimize   = "#000000"
beautiful.fg_normal     = "#ffffff"
beautiful.fg_focus      = "#ffffff"
beautiful.fg_urgent     = "#ff5555"
beautiful.border_width  = 1
beautiful.border_color  = "#393869"
beautiful.border_normal = "#000000"
beautiful.border_focus  = "#2B54F6"
beautiful.tag_color     = "#0000FF"
beautiful.tag_active    = "#FFFF00"

    -- Настройка всплывающего меню
beautiful.menu_width = 300  -- ширина меню
beautiful.menu_height = 30  -- высота пункта меню
beautiful.menu_font = beautiful.font
beautiful.menu_bg_normal = beautiful.bg_normal
beautiful.menu_fg_normal = beautiful.fg_normal
beautiful.menu_border_width = 2
beautiful.menu_border_color = beautiful.border_focus

-- ===== РАСКЛАДКИ =====
awful.layout.layouts = {
    awful.layout.suit.floating,
}

-- Разделитель
local small_separator = wibox.widget {
    widget = wibox.container.margin,
    top = 10,
    bottom = 10,
}

-- ===== ВИДЖЕТ ТЕГОВ =====
local function create_tag_widget(s)
    local container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }

    local icons = {
        active = "󰈈",
        occupied = "󰛨",
        empty = "",
        urgent = "󰚯",
    }

    local function update_tags()
        container:reset()
        for i, tag in ipairs(s.tags) do
            local icon
            local color
            
            if tag == s.selected_tag then
                icon = icons.active
                color = beautiful.fg_focus
            elseif #tag:clients() > 0 then
                icon = icons.occupied
                color = beautiful.tag_active
            elseif tag.urgent then
                icon = icons.urgent
                color = beautiful.fg_urgent
            else
                icon = icons.empty
                color = beautiful.tag_color
            end
            
            local textbox = wibox.widget.textbox()
            textbox.font = beautiful.icon_font
            textbox:set_markup(string.format('<span foreground="%s">%s</span>',
                color, icon))
            
            textbox:buttons(gears.table.join(
                awful.button({}, 1, function() tag:view_only() end),
                awful.button({modkey}, 1, function()
                    if client.focus then client.focus:move_to_tag(tag) end
                end),
                awful.button({}, 3, function() awful.tag.viewtoggle(tag) end),
                awful.button({modkey}, 3, function()
                    if client.focus then client.focus:toggle_tag(tag) end
                end),
                awful.button({}, 4, function() awful.tag.viewnext(s) end),
                awful.button({}, 5, function() awful.tag.viewprev(s) end)
            ))
            
            container:add(textbox)
        end
    end

    tag.connect_signal("property::selected", update_tags)
    tag.connect_signal("property::urgent", update_tags)
    client.connect_signal("tagged", update_tags)
    client.connect_signal("untagged", update_tags)
    client.connect_signal("unmanage", update_tags)

    update_tags()
    return container
end

-- ===== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ =====
local function create_icon_textbox(icon, color, font)
    return wibox.widget {
        markup = string.format('<span font="%s" foreground="%s">%s</span>', font or beautiful.icon_font, color, icon),
        widget = wibox.widget.textbox,
    }
end

local function is_floating_client(c)
    return c and (c.floating or (c.first_tag and c.first_tag.layout == awful.layout.suit.floating))
end


-- ===== ВИДЖЕТ ИКОНОК ЗАДАЧ + ЗМЕЙКА С ХВОСТОМ =====
local function create_task_icons_widget(s)
    local container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }

    -- ---- Настройки змейки ----
    local SNAKE_LEN     = 12        -- длина дорожки в символах
    local SNAKE_TICK    = 200       -- мс между кадрами (меньше = быстрее)
    local TAIL_LEN      = 6         -- длина видимого хвоста (в символах)
    local BODY_CHAR     = "●"
    local HEAD_CHAR     = "◉"
    local EMPTY_CHAR    = "·"
    local EMPTY_COLOR   = "#222222"
    local HEAD_COLOR    = "#ffffff"
    local BODY_COLOR    = "#00ff88"

    local snake_widget = wibox.widget {
        markup = "",
        font = beautiful.icon_font,
        align = "center",
        valign = "center",
        widget = wibox.widget.textbox,
    }

    local head_pos = 1              -- позиция головы (1..SNAKE_LEN)
    local head_dir = 1              -- 1 = вправо, -1 = влево
    local snake_timer = nil

    -- плавное затухание: берём цвет головы и линейно уводим к EMPTY_COLOR
    local function fade_color(t)
        -- t: 0 = голова (ярко), 1 = конец хвоста (пусто)
        -- возвращаем hex-цвет между BODY_COLOR и EMPTY_COLOR
        local function hex2rgb(hex)
            hex = hex:gsub("#", "")
            return tonumber(hex:sub(1,2), 16),
                   tonumber(hex:sub(3,4), 16),
                   tonumber(hex:sub(5,6), 16)
        end
        local r1,g1,b1 = hex2rgb(BODY_COLOR)
        local r2,g2,b2 = hex2rgb(EMPTY_COLOR)
        local r = math.floor(r1 + (r2 - r1) * t + 0.5)
        local g = math.floor(g1 + (g2 - g1) * t + 0.5)
        local b = math.floor(b1 + (b2 - b1) * t + 0.5)
        return string.format("#%02x%02x%02x", r, g, b)
    end

    local function render_snake()
        local parts = {}
        for i = 1, SNAKE_LEN do
            -- dist: сколько символов назад от головы (0 = голова)
            local dist
            if head_dir == 1 then
                dist = head_pos - i
            else
                dist = i - head_pos
            end

            if i == head_pos then
                parts[i] = string.format('<span foreground="%s">%s</span>',
                    HEAD_COLOR, HEAD_CHAR)
            elseif dist > 0 and dist <= TAIL_LEN then
                -- хвост: затухание от 0 (у головы) до 1 (конец хвоста)
                local t = (dist - 1) / TAIL_LEN
                local color = fade_color(t)
                parts[i] = string.format('<span foreground="%s">%s</span>',
                    color, BODY_CHAR)
            else
                -- пусто
                parts[i] = string.format('<span foreground="%s">%s</span>',
                    EMPTY_COLOR, EMPTY_CHAR)
            end
        end
        snake_widget.markup = table.concat(parts)
    end

    local function start_snake()
        if snake_timer then return end
        snake_timer = gears.timer {
            timeout = SNAKE_TICK / 1000,
            autostart = true,
            callback = function()
                head_pos = head_pos + head_dir
                if head_pos >= SNAKE_LEN then
                    head_pos = SNAKE_LEN
                    head_dir = -1
                elseif head_pos <= 1 then
                    head_pos = 1
                    head_dir = 1
                end
                render_snake()
            end
        }
        render_snake()
    end

    local function stop_snake()
        if snake_timer then
            snake_timer:stop()
            snake_timer = nil
        end
    end

    -- ---- Иконки задач ----
    local function update_task_icons()
        container:reset()

        local tag = s.selected_tag
        if not tag then
            container:add(snake_widget)
            start_snake()
            return
        end

        local clients = tag:clients()

        if #clients == 0 then
            container:add(snake_widget)
            start_snake()
            return
        end

        stop_snake()

        for _, c in ipairs(clients) do
            local icon_widget
            if c.icon then
                icon_widget = wibox.widget {
                    image = c.icon,
                    resize = true,
                    forced_width = 32,
                    forced_height = 32,
                    widget = wibox.widget.imagebox
                }
            else
                local first_letter = string.sub(c.name or "?", 1, 1)
                icon_widget = wibox.widget {
                    markup = '<span font="JetBrains Mono">' .. first_letter .. '</span>',
                    widget = wibox.widget.textbox
                }
            end

            icon_widget:buttons(gears.table.join(
                awful.button({}, 1, function()
                    c:emit_signal("request::activate", "task_icon", {raise = true})
                end)
            ))

            container:add(icon_widget)
        end
    end

    -- ---- Сигналы ----
    tag.connect_signal("property::selected", function(t)
        if t.screen == s then update_task_icons() end
    end)
    client.connect_signal("manage", function(c)
        if c.screen == s then update_task_icons() end
    end)
    client.connect_signal("unmanage", function(c)
        if c.screen == s then update_task_icons() end
    end)
    client.connect_signal("tagged", function(c)
        if c.screen == s then update_task_icons() end
    end)
    client.connect_signal("untagged", function(c)
        if c.screen == s then update_task_icons() end
    end)
    client.connect_signal("property::visible", function(c)
        if c.screen == s then update_task_icons() end
    end)
    client.connect_signal("property::icon", function(c)
        if c.screen == s then update_task_icons() end
    end)

    update_task_icons()
    return container
end

-- ===== ВИДЖЕТ ГРОМКОСТИ (для правой панели) =====
local volume_backend = (function()
    local handle = io.popen("command -v wpctl")
    local result = handle:read("*a")
    handle:close()
    return (result and result ~= "") and "wpctl" or "pactl"
end)()

local volume_widget = wibox.widget {
    {
        id = "icon",
        widget = wibox.widget.textbox,
        markup = '<span font="' .. beautiful.icon_font .. '">󰕾</span>',
    },
    layout = wibox.layout.fixed.vertical,
}

local function get_volume_icon(volume_percent, muted)
    if muted then return "󰝟" end
    if volume_percent < 33 then return "󰖀" end
    if volume_percent < 66 then return "󰕾" end
    return "󰕾"
end

local function update_volume_icon()
    if volume_backend == "wpctl" then
        awful.spawn.easy_async("wpctl get-volume @DEFAULT_AUDIO_SINK@", function(stdout)
            local volume_str = stdout:match("Volume: (%d+%.?%d*)")
            local volume_percent = volume_str and math.floor(tonumber(volume_str) * 100) or 0
            local muted = stdout:find("MUTED") ~= nil
            local icon = get_volume_icon(volume_percent, muted)
            volume_widget.icon.markup = '<span font="' .. beautiful.icon_font .. '">' .. icon .. '</span>'
        end)
    end
end

local function change_volume(delta)
    if volume_backend == "wpctl" then
        awful.spawn(string.format("wpctl set-volume @DEFAULT_AUDIO_SINK@ %d%%", delta), false)
    end
    update_volume_icon()
end

local function toggle_mute()
    local cmd = volume_backend == "wpctl" 
        and "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        or "pactl set-sink-mute @DEFAULT_SINK@ toggle"
    awful.spawn(cmd, false)
    update_volume_icon()
end

volume_widget:buttons(gears.table.join(
    awful.button({}, 1, function() awful.spawn(APPS.volume_control) end),
    awful.button({}, 4, function() change_volume(5) end),
    awful.button({}, 5, function() change_volume(-5) end),
    awful.button({}, 2, toggle_mute)
))

gears.timer {
    timeout = 2,
    call_now = true,
    autostart = true,
    callback = update_volume_icon,
}

-- ===== ВИДЖЕТ БАТАРЕИ (для правой панели) =====
local battery_widget = wibox.widget {
    {
        id = "icon",
        widget = wibox.widget.textbox,
        markup = '<span font="' .. beautiful.icon_font .. '">󰁹</span>',
    },
    layout = wibox.layout.fixed.vertical,
}

local function get_battery_icon(percent, charging)
    if charging then return "󰂄" end
    if percent <= 10 then return "󰁺" end
    if percent <= 25 then return "󰁻" end
    if percent <= 50 then return "󰁾" end
    if percent <= 75 then return "󰂀" end
    return "󰁹"
end

local function update_battery_widget()
    awful.spawn.easy_async_with_shell(
        "cat /sys/class/power_supply/BATT/capacity 2>/dev/null || cat /sys/class/power_supply/BAT1/capacity 2>/dev/null || cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 'NOT_FOUND'",
        function(stdout)
            local percent_str = stdout:match("%d+")
            
            if not percent_str then
                battery_widget.icon.markup = string.format(
                    '<span font="%s" foreground="#ffffff">󱄇</span>',
                    beautiful.icon_font
                )
                return
            end
            
            local percent = tonumber(percent_str) or 0

            awful.spawn.easy_async_with_shell(
                "cat /sys/class/power_supply/BATT/status 2>/dev/null || cat /sys/class/power_supply/BAT1/status 2>/dev/null || cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo 'Unknown'",
                function(status_out)
                    local charging = status_out:match("Charging") ~= nil
                    local icon = get_battery_icon(percent, charging)
                    local color = "#ffffff"

                    if percent <= 10 and not charging then
                        color = beautiful.fg_urgent
                    elseif percent <= 25 and not charging then
                        color = "#ffaa00"
                    elseif charging then
                        color = "#00ff00"
                    end

                    battery_widget.icon.markup = string.format(
                        '<span font="%s" foreground="%s">%s %d%%</span>',
                        beautiful.icon_font, color, icon, percent
                    )
                end
            )
        end
    )
end

gears.timer {
    timeout = 30,
    call_now = true,
    autostart = true,
    callback = update_battery_widget,
}

-- ===== ВИДЖЕТ РАСКЛАДКИ =====
local layout_text_widget = wibox.widget.textbox()
layout_text_widget.font = beautiful.font

local function update_layout_widget(s)
    local tag = s.selected_tag
    if tag then
        local layout_names = {
            [awful.layout.suit.floating] = "",
        }
        local name = layout_names[tag.layout] or "?"
        layout_text_widget.markup = '<span foreground="#ffffff">' .. name .. '</span>'
    end
end

tag.connect_signal("property::selected", function(t)
    update_layout_widget(t.screen)
end)

tag.connect_signal("property::layout", function(t)
    if t == t.screen.selected_tag then
        update_layout_widget(t.screen)
    end
end)

-- ===== ВИДЖЕТ ЧАСОВ =====
local clock_widget = wibox.widget.textbox()
clock_widget.font = beautiful.font

local months = { "⛄янв", "🥶фев", "💧мар", "🌞апр", "🌷май", "😎июн", "🥵июл", "🫠авг", "😊сен", "🌧️окт", "🧥ноя", "❄️дек" }

local weekdays = { "🥲Вс", "😐Пн", "😑Вт", "🫣Ср", "🙂Чт", "😊Пт", "😍Сб" }

local function update_clock()
    local now = os.date("*t")
    local date_str = string.format("%s %02d %s 󰥔 %02d:%02d ",
        weekdays[now.wday], now.day, months[now.month],
        now.hour, now.min, now.sec
    )
    clock_widget:set_markup('<span foreground="#ffffff">' .. date_str .. '</span>')
end

gears.timer {
    timeout = 1,
    call_now = true,
    autostart = true,
    callback = update_clock,
}

-- ===== СИСТЕМНЫЕ ВИДЖЕТЫ ДЛЯ ПРАВОЙ ПАНЕЛИ =====

-- ===== ВИДЖЕТ СЕТИ =====
local network_widget = wibox.widget {
    {
        id = "icon",
        widget = wibox.widget.textbox,
        markup = '<span font="' .. beautiful.icon_font .. '">󰈀</span>',
    },
    layout = wibox.layout.fixed.horizontal,
}

local function update_network_widget()
    awful.spawn.easy_async_with_shell(
        "nmcli -t -f TYPE,STATE device status 2>/dev/null",
        function(stdout)
            local icon, color
            local wifi_connected   = false
            local ethernet_connected = false

            for line in stdout:gmatch("[^\r\n]+") do
                local dtype, state = line:match("^([^:]+):([^:]+)$")
                if state == "connected" then
                    if dtype == "wifi" then
                        wifi_connected = true
                    elseif dtype == "ethernet" then
                        ethernet_connected = true
                    end
                end
            end

            if ethernet_connected then
                icon, color = "󰈀", "#00ff00"
            elseif wifi_connected then
                icon, color = "󰖩", "#00ff00"
            else
                icon, color = "", beautiful.fg_urgent
            end

            network_widget.icon.markup = string.format(
                '<span font="%s" foreground="%s">%s</span>',
                beautiful.icon_font, color, icon
            )
        end
    )
end

gears.timer {
    timeout = 5,
    call_now = true,
    autostart = true,
    callback = update_network_widget,
}

-- ===== ВИДЖЕТ BLUETOOTH =====
local bluetooth_widget = wibox.widget {
    {
        id = "icon",
        widget = wibox.widget.textbox,
        markup = '<span font="' .. beautiful.icon_font .. '">󰂲</span>',
    },
    layout = wibox.layout.fixed.horizontal,
}

local bluetooth_active = false

local function update_bluetooth_widget()
    awful.spawn.easy_async_with_shell(
        "systemctl is-active bluetooth 2>/dev/null",
        function(stdout)
            -- ВАЖНО: убираем все пробелы/переводы строк и сравниваем точно.
            -- Иначе "inactive" содержит "active" как подстроку и даёт ложное срабатывание.
            local state = stdout:gsub("%s+", "")
            bluetooth_active = (state == "active")

            if bluetooth_active then
                bluetooth_widget.icon.markup = string.format(
                    '<span font="%s" foreground="#00aaff">󰂯</span>',
                    beautiful.icon_font
                )
            else
                bluetooth_widget.icon.markup = string.format(
                    '<span font="%s" foreground="%s">󰂲</span>',
                    beautiful.icon_font, beautiful.fg_urgent
                )
            end
        end
    )
end

bluetooth_widget:buttons(gears.table.join(
    awful.button({}, 1, function()
        if bluetooth_active then
            awful.spawn(APPS.terminal .. " -e bluetui", false)
        end
    end)
))

gears.timer {
    timeout = 5,
    call_now = true,
    autostart = true,
    callback = update_bluetooth_widget,
}

-- ===== ВИДЖЕТ РАСКЛАДКИ КЛАВИАТУРЫ (setxkbmap) =====
local kb_layout_widget = wibox.widget {
    {
        id = "icon",
        widget = wibox.widget.textbox,
        markup = '<span font="' .. beautiful.icon_font .. '">🇺🇸</span>',
    },
    layout = wibox.layout.fixed.horizontal,
}

local current_layout = "us"

function set_keyboard_layout(layout)
    current_layout = layout
    awful.spawn("setxkbmap " .. layout, false)

    local flag = (layout == "ru") and "🇷🇺" or "🇺🇸"
    local name = (layout == "ru") and "Русский" or "English"

    kb_layout_widget.icon.markup = string.format(
        '<span font="%s">%s</span>',
        beautiful.icon_font, flag
    )

    naughty.notify({
        preset = naughty.config.presets.normal,
        title = "⌨️KKeyboard layout",
        text = flag .. "  " .. name,
        timeout = 3.0,
        width = 300,
    })
end

function toggle_keyboard_layout()
    if current_layout == "us" then
        set_keyboard_layout("ru")
    else
        set_keyboard_layout("us")
    end
end

kb_layout_widget:buttons(gears.table.join(
    awful.button({}, 1, function() toggle_keyboard_layout() end)
))

awful.spawn.easy_async_with_shell(
    "setxkbmap -query | awk '/layout/ {print $2}' | cut -d',' -f1",
    function(stdout)
        local layout = stdout:match("(%a+)") or "us"
        set_keyboard_layout(layout)
    end
)



-- ===== ОБОИ =====
local function set_wallpaper(s)
    if beautiful.wallpaper then
        local wallpaper = beautiful.wallpaper
        if type(wallpaper) == "function" then
            wallpaper = wallpaper(s)
        end
        gears.wallpaper.maximized(wallpaper, s, true)
    end
end

screen.connect_signal("property::geometry", set_wallpaper)


-- ===== НАСТРОЙКА ЭКРАНОВ =====
awful.screen.connect_for_each_screen(function(s)
    set_wallpaper(s)
    awful.tag({"1", "2", "3", "4", "5", "6", "7", "8", "9"}, s, awful.layout.layouts[1])

    s.mypromptbox = awful.widget.prompt()
    s.mylayoutbox = awful.widget.layoutbox(s)
    s.mylayoutbox:buttons(gears.table.join(
        awful.button({}, 1, function() awful.layout.inc(1) end),
        awful.button({}, 3, function() awful.layout.inc(-1) end),
        awful.button({}, 4, function() awful.layout.inc(1) end),
        awful.button({}, 5, function() awful.layout.inc(-1) end)
    ))

    local tag_widget = create_tag_widget(s)
    local task_icons_widget = create_task_icons_widget(s)

    local logo_widget = wibox.widget {
        markup = '<span font="' .. beautiful.icon_font .. '" foreground="#ffffff">󰣇</span>',
        widget = wibox.widget.textbox,
    }

        -- ===== ПАНЕЛЬ С ЛОГОТИПОМ =====
    -- Меню с программами
    mainmenu = awful.menu({
        items = {
            { " Firefox", function() mainmenu:hide() awful.spawn("firefox") end },
            { " Thunar", function() mainmenu:hide() awful.spawn("thunar") end },
            { " Terminal", function() mainmenu:hide(); awful.spawn(APPS.terminal) end },
            { " Editor", function() mainmenu:hide(); awful.spawn(APPS.editor_cmd) end },
            { "󱓞 Launcher", function() mainmenu:hide() gears.timer.start_new(0.1, function() awful.spawn(APPS.launcher) return false end) end},
            { " Volume Control", function() mainmenu:hide(); awful.spawn(APPS.volume_control) end },
	    { "󰧱 Appearance", function() mainmenu:hide(); awful.spawn("lxappearance") end }, 
            { "------------------", nil },
            { " Restart Awesome", function() mainmenu:hide(); awesome.restart() end },
            { " Quit Awesome", function() mainmenu:hide(); awesome.quit() end },
        }
    })

        mainmenu:connect_signal("mouse::leave", function()
        mainmenu:hide()
    end)

    -- Кликабельный логотип
    local logo_widget = wibox.widget {
        markup = '<span font="' .. beautiful.icon_font .. '" foreground="#ffffff">󰣇</span>',
        widget = wibox.widget.textbox,
    }

    logo_widget:buttons(gears.table.join(
        awful.button({}, 1, function()
            mainmenu:toggle()  -- показать/скрыть меню
        end)
    ))

    -- Панель с логотипом
    s.logobar = wibox({
        width = 40,
        height = 40,
        bg = beautiful.bg_normal,
        fg = beautiful.fg_normal,
        border_width = 2,
        border_color = "#2B54F6",
        shape = gears.shape.rounded_rect,
        ontop = true,
        visible = true,
        x = 10,
        y = 10,
        screen = s,
        type = "dock",
    })

    s.logobar:setup {
        {
            logo_widget,
            left = 5,
            right = 5,
            top = 5,
            bottom = 5,
            widget = wibox.container.margin,
        },
        layout = wibox.layout.align.horizontal,
    }
    -- ===== ПАНЕЛЬ С ТЭГАМИ =====
    s.mywibox = wibox({
        width = 320, 
        height = 40,
        bg = beautiful.bg_normal,
        fg = beautiful.fg_normal,
        border_width = 2,
        border_color = "#2B54F6",
        shape = gears.shape.rounded_rect,
        ontop = true,
        visible = true,
	x = 60,
        y = 10,
        screen = s,
        type = "dock",
    })

    s.mywibox:setup {
        {
            tag_widget,
            layout = wibox.layout.fixed.horizontal,
            spacing = 10,
        },
	widget = wibox.container.place,
        halign = "center",
        valign = "center",
    }

    -- ===== ПАНЕЛЬ АКТИВНЫХ ПРОГРАММ =====
    s.taskbar = wibox({
        width = 300,  -- ширина панели задач
        height = 40,
        bg = beautiful.bg_normal,
        fg = beautiful.fg_normal,
        border_width = 3,
        border_color = "#2B54F6",
        shape = gears.shape.rounded_rect,
        ontop = true,
        visible = true,
        x = 400,
        y = 10,
        screen = s,
        type = "dock",
    })

    s.taskbar:setup {
        {
            task_icons_widget,
            layout = wibox.layout.fixed.horizontal,
            spacing = 8,
        },
        widget = wibox.container.place,
        halign = "center",
        valign = "center",
    }

    -- ===== ПАНЕЛЬ С ЧАСАМИ =====
    s.clockbar = wibox({
        width = 250,
        height = 40,
        bg = beautiful.bg_normal,
        fg = beautiful.fg_normal,
        border_width = 3,
        border_color = "#2B54F6",
        shape = gears.shape.rounded_rect,
        ontop = true,
        visible = true,
        x = 1140,  
        y = 10,
        screen = s,
        type = "dock",
    })

    s.clockbar:setup {
        {
            clock_widget,
            layout_text_widget,
            layout = wibox.layout.fixed.horizontal,
            spacing = 10,
        },
        widget = wibox.container.place,
        halign = "center",
        valign = "center",
    }

    -- ===== ПРАВАЯ ПАНЕЛЬ (системные виджеты) =====
    s.rightbar = wibox({
        width = 500,
        height = 40,
        bg = beautiful.bg_normal,
        fg = beautiful.fg_normal,
        border_width = 3,
        border_color = "#2B54F6",
        shape = gears.shape.rounded_rect,
        ontop = true,
        visible = true,
        x = 1400,
        y = 10,
        screen = s,
        type = "dock",
    })

    s.rightbar:setup {
        {
	    kb_layout_widget,
	    network_widget,
	    bluetooth_widget,
	    volume_widget,
            battery_widget,
            layout = wibox.layout.fixed.horizontal,
            spacing = 15,
        },
        widget = wibox.container.place,
        halign = "center",
        valign = "center",
    }

    -- Автоматическое скрытие всех панелей при максимизации
    local function update_wibar_visibility()
        local has_maximized = false
        for _, c in ipairs(s.clients) do
            if c.maximized and c:isvisible() then
                has_maximized = true
                break
            end
        end
        s.logobar.visible = not has_maximized  -- добавьте эту строку
        s.mywibox.visible = not has_maximized
        s.taskbar.visible = not has_maximized
        s.clockbar.visible = not has_maximized
        s.rightbar.visible = not has_maximized
    end

    client.connect_signal("property::maximized", function(c)
        if c.screen == s then update_wibar_visibility() end
    end)

    client.connect_signal("unmanage", function(c)
        if c.screen == s then update_wibar_visibility() end
    end)

    tag.connect_signal("property::selected", function(t)
        if t.screen == s then update_wibar_visibility() end
    end)
end)
-- ===== КНОПКИ КОРНЕВОГО ОКНА =====
root.buttons(gears.table.join(
--    awful.button({}, 3, function() mymainmenu:toggle() end),
    awful.button({}, 4, awful.tag.viewnext),
    awful.button({}, 5, awful.tag.viewprev)
))


-- ===== ИНФО-ОКНО (system info) =====
local function get_username()
    return os.getenv("USER") or os.getenv("LOGNAME") or "unknown"
end

local function collect_system_info(callback)
    local info = {
        username = get_username(),
        cpu_temp = "—",
        ram      = "—",
        disk     = "—",
        packages = "—",
    }

    local pending = 4
    local function done()
        pending = pending - 1
        if pending == 0 then callback(info) end
    end

    awful.spawn.easy_async_with_shell(
        "for hwmon in /sys/class/hwmon/hwmon*; do " ..
        "if [ -f \"$hwmon/name\" ]; then " ..
        "name=$(cat \"$hwmon/name\"); " ..
        "if [ \"$name\" = \"k10temp\" ] || [ \"$name\" = \"coretemp\" ] || [ \"$name\" = \"zenpower\" ]; then " ..
        "cat \"$hwmon/temp1_input\"; break; " ..
        "fi; fi; done 2>/dev/null | awk '{printf \"%.1f\", $1/1000}'",
        function(stdout)
            if stdout and stdout ~= "" then info.cpu_temp = stdout .. " °C" end
            done()
        end
    )

    awful.spawn.easy_async_with_shell(
        "free -h | awk '/^Mem:/ {print $3 \" / \" $2}'",
        function(stdout)
            if stdout and stdout ~= "" then info.ram = stdout:gsub("%s+$", "") end
            done()
        end
    )

    awful.spawn.easy_async_with_shell(
        "df -h / | awk 'NR==2 {print $3 \" / \" $2 \" (\" $5 \")\"}'",
        function(stdout)
            if stdout and stdout ~= "" then info.disk = stdout:gsub("%s+$", "") end
            done()
        end
    )

    awful.spawn.easy_async_with_shell(
        "pacman -Q 2>/dev/null | wc -l",
        function(stdout)
            local n = stdout and stdout:match("%d+")
            if n then info.packages = n end
            done()
        end
    )
end

-- виджет с текстом (создаём один раз)
local info_text_widget = wibox.widget {
    markup = '<span foreground="#aaaaaa">Загрузка...</span>',
    align = "left",
    valign = "top",
    font = beautiful.font,
    widget = wibox.widget.textbox,
}

local info_popup = wibox {
    width  = 420,
    height = 390,
    ontop  = true,
    visible = false,
    bg = "#000000",
    border_width = 2,
    border_color = beautiful.border_focus,
    type = "notification",
    widget = wibox.container.background,
}

info_popup:setup {
    {
        {
            {
                markup = '<span foreground="#00ff88" font="' .. beautiful.icon_font .. '">󰍹</span>  ' ..
                         '<span foreground="#ffffff" font="' .. beautiful.font .. '"><b>System Info</b></span>',
                widget = wibox.widget.textbox,
            },
            {
                forced_height = 1,
                bg = "#333333",
                widget = wibox.widget.separator,
            },
            info_text_widget,
            {
                markup = '<span foreground="#666666">Esc — закрыть</span>',
                align = "right",
                font = beautiful.font,
                widget = wibox.widget.textbox,
            },
            layout = wibox.layout.fixed.vertical,
            spacing = 12,
        },
        margins = 20,
        widget = wibox.container.margin,
    },
    bg = "#000000",
    widget = wibox.container.background,
}

-- ===== ПЕРЕТАСКИВАНИЕ ИНФО-ОКНА =====
info_popup:buttons(gears.table.join(
    awful.button({modkey}, 1, function()
        local start_x, start_y = mouse.coords().x, mouse.coords().y
        local orig_x, orig_y   = info_popup.x, info_popup.y

        mousegrabber.run(function(m)
            -- КЛЮЧЕВОЕ: если кнопка отпущена — граббер останавливается
            if not m or not m.buttons or not m.buttons[1] then
                return false
            end
            info_popup.x = orig_x + (m.x - start_x)
            info_popup.y = orig_y + (m.y - start_y)
            return true
        end, "fleur")
    end)
))

local function refresh_info_popup()
    info_text_widget.markup = '<span foreground="#aaaaaa">Загрузка...</span>'
    collect_system_info(function(info)
        info_text_widget.markup = table.concat({
            string.format('<span foreground="#aaaaaa">Пользователь:</span>     <span foreground="#ffffff">%s</span>', info.username),
            string.format('<span foreground="#aaaaaa">Температура CPU:</span>  <span foreground="#ffffff">%s</span>', info.cpu_temp),
            string.format('<span foreground="#aaaaaa">ОЗУ:</span>             <span foreground="#ffffff">%s</span>', info.ram),
            string.format('<span foreground="#aaaaaa">Диск /:</span>           <span foreground="#ffffff">%s</span>', info.disk),
            string.format('<span foreground="#aaaaaa">Пакетов pacman:</span>   <span foreground="#ffffff">%s</span>', info.packages),
        }, "\n\n")
    end)
end

local function toggle_info_popup()
    if info_popup.visible then
        info_popup.visible = false
        return
    end

    local s = awful.screen.focused()
    -- центрируем на текущем экране
    info_popup.x = s.geometry.x + math.floor((s.geometry.width  - info_popup.width)  / 2)
    info_popup.y = s.geometry.y + math.floor((s.geometry.height - info_popup.height) / 2)
    info_popup.screen = s

    refresh_info_popup()
    info_popup.visible = true
end

gears.timer {
    timeout = 3, autostart = true,
    callback = function()
        if info_popup.visible then refresh_info_popup() end
    end,
}

-- ===== ГЛОБАЛЬНЫЕ КЛАВИШИ =====
globalkeys = gears.table.join(
    awful.key({modkey, "Shift"}, "Left", function()
        local c = client.focus
        if is_floating_client(c) then
            local geo = c:geometry()
            c:geometry({x = geo.x, y = geo.y, width = math.max(50, geo.width - 30), height = geo.height})
        end
    end, {description = "уменьшить ширину float окна", group = "client"}),

    awful.key({modkey, "Shift"}, "Right", function()
        local c = client.focus
        if is_floating_client(c) then
            local geo = c:geometry()
            c:geometry({x = geo.x, y = geo.y, width = geo.width + 30, height = geo.height})
        end
    end, {description = "увеличить ширину float окна", group = "client"}),

    awful.key({modkey, "Shift"}, "Up", function()
        local c = client.focus
        if is_floating_client(c) then
            local geo = c:geometry()
            c:geometry({x = geo.x, y = geo.y, width = geo.width, height = math.max(50, geo.height - 30)})
        end
    end, {description = "уменьшить высоту float окна", group = "client"}),

    awful.key({modkey, "Shift"}, "Down", function()
        local c = client.focus
        if is_floating_client(c) then
            local geo = c:geometry()
            c:geometry({x = geo.x, y = geo.y, width = geo.width, height = geo.height + 30})
        end
    end, {description = "увеличить высоту float окна", group = "client"}),

    awful.key({modkey, "Control"}, "Left", function()
        local c = client.focus
        if is_floating_client(c) then
            c:relative_move(-60, 0, 0, 0)
        end
    end, {description = "переместить float окно влево", group = "client"}),

    awful.key({modkey, "Control"}, "Right", function()
        local c = client.focus
        if is_floating_client(c) then
            c:relative_move(60, 0, 0, 0)
        end
    end, {description = "переместить float окно вправо", group = "client"}),

    awful.key({modkey, "Control"}, "Up", function()
        local c = client.focus
        if is_floating_client(c) then
            c:relative_move(0, -60, 0, 0)
        end
    end, {description = "переместить float окно вверх", group = "client"}),

    awful.key({modkey, "Control"}, "Down", function()
        local c = client.focus
        if is_floating_client(c) then
            c:relative_move(0, 60, 0, 0)
        end
    end, {description = "переместить float окно вниз", group = "client"}),
    awful.key({modkey}, "i", function() toggle_info_popup() end,
          {description = "system info popup", group = "awesome"}),
awful.key({}, "Escape", function()
    if info_popup and info_popup.visible then
        info_popup.visible = false
    end
end, {description = "close info popup", group = "awesome"}),
    awful.key({"Mod1"}, "Shift_L", function() toggle_keyboard_layout() end,
              {description = "switch keyboard layout (ru/us)", group = "keyboard"}),
    awful.key({"Mod1"}, "Shift_R", function() toggle_keyboard_layout() end,
              {description = "switch keyboard layout (ru/us)", group = "keyboard"}),
    awful.key({modkey}, "s", hotkeys_popup.show_help,
              {description = "show help", group = "awesome"}),
    awful.key({modkey}, "Left", awful.tag.viewprev,
              {description = "view previous", group = "tag"}),
    awful.key({modkey}, "Right", awful.tag.viewnext,
              {description = "view next", group = "tag"}),
    awful.key({modkey}, "Escape", awful.tag.history.restore,
              {description = "go back", group = "tag"}),
    awful.key({modkey}, "p", function() awful.spawn(APPS.launcher) end,
              {description = "run launcher", group = "launcher"}),
    awful.key({modkey}, "e", function() awful.spawn(APPS.emoji) end,
              {description = "emoji picker", group = "launcher"}),
    awful.key({modkey}, "j", function() awful.client.focus.byidx(1) end,
              {description = "focus next by index", group = "client"}),
    awful.key({modkey}, "k", function() awful.client.focus.byidx(-1) end,
              {description = "focus previous by index", group = "client"}),
    --awful.key({modkey}, "w", function() mymainmenu:show() end,
      --        {description = "show main menu", group = "awesome"}),
    awful.key({modkey, "Shift"}, "j", function() awful.client.swap.byidx(1) end,
              {description = "swap with next client by index", group = "client"}),
    awful.key({modkey, "Shift"}, "k", function() awful.client.swap.byidx(-1) end,
              {description = "swap with previous client by index", group = "client"}),
    awful.key({modkey, "Control"}, "j", function() awful.screen.focus_relative(1) end,
              {description = "focus the next screen", group = "screen"}),
    awful.key({modkey, "Control"}, "k", function() awful.screen.focus_relative(-1) end,
              {description = "focus the previous screen", group = "screen"}),
    awful.key({modkey}, "u", awful.client.urgent.jumpto,
              {description = "jump to urgent client", group = "client"}),
    awful.key({modkey}, "Tab", function()
        awful.client.focus.history.previous()
        if client.focus then client.focus:raise() end
    end, {description = "go back", group = "client"}),
    awful.key({modkey}, "Return", function() awful.spawn(APPS.terminal) end,
              {description = "open a terminal", group = "launcher"}),
    awful.key({modkey, "Control"}, "r", awesome.restart,
              {description = "reload awesome", group = "awesome"}),
    awful.key({modkey, "Shift"}, "q", awesome.quit,
              {description = "quit awesome", group = "awesome"}),
    awful.key({modkey}, "l", function() awful.tag.incmwfact(0.05) end,
              {description = "increase master width factor", group = "layout"}),
    awful.key({modkey}, "h", function() awful.tag.incmwfact(-0.05) end,
              {description = "decrease master width factor", group = "layout"}),
    awful.key({modkey, "Shift"}, "h", function() awful.tag.incnmaster(1, nil, true) end,
              {description = "increase the number of master clients", group = "layout"}),
    awful.key({modkey, "Shift"}, "l", function() awful.tag.incnmaster(-1, nil, true) end,
              {description = "decrease the number of master clients", group = "layout"}),
    awful.key({modkey, "Control"}, "h", function() awful.tag.incncol(1, nil, true) end,
              {description = "increase the number of columns", group = "layout"}),
    awful.key({modkey, "Control"}, "l", function() awful.tag.incncol(-1, nil, true) end,
              {description = "decrease the number of columns", group = "layout"}),
    awful.key({modkey}, "space", function() awful.layout.inc(1) end,
              {description = "select next", group = "layout"}),
    awful.key({modkey, "Shift"}, "space", function() awful.layout.inc(-1) end,
              {description = "select previous", group = "layout"}),
    awful.key({modkey, "Control"}, "n", function()
        local c = awful.client.restore()
        if c then
            c:emit_signal("request::activate", "key.unminimize", {raise = true})
        end
    end, {description = "restore minimized", group = "client"}),
    awful.key({modkey}, "r", function() awful.screen.focused().mypromptbox:run() end,
              {description = "run prompt", group = "launcher"}),
    awful.key({modkey}, "x", function()
        awful.prompt.run {
            prompt = "Run Lua code: ",
            textbox = awful.screen.focused().mypromptbox.widget,
            exe_callback = awful.util.eval,
            history_path = awful.util.get_cache_dir() .. "/history_eval"
        }
    end, {description = "lua execute prompt", group = "awesome"})
)

-- ===== КЛАВИШИ КЛИЕНТОВ =====
clientkeys = gears.table.join(
    awful.key({modkey}, "f", function(c) c.fullscreen = not c.fullscreen; c:raise() end,
              {description = "toggle fullscreen", group = "client"}),
    awful.key({modkey, "Shift"}, "c", function(c) c:kill() end,
              {description = "close", group = "client"}),
    awful.key({modkey, "Control"}, "space", awful.client.floating.toggle,
              {description = "toggle floating", group = "client"}),
    awful.key({modkey, "Control"}, "Return", function(c) c:swap(awful.client.getmaster()) end,
              {description = "move to master", group = "client"}),
    awful.key({modkey}, "o", function(c) c:move_to_screen() end,
              {description = "move to screen", group = "client"}),
    awful.key({modkey}, "t", function(c) c.ontop = not c.ontop end,
              {description = "toggle keep on top", group = "client"}),
    awful.key({modkey, "Control"}, "w", function(c) c:relative_move(0, 0, 0, -20) end),
    awful.key({modkey, "Control"}, "s", function(c) c:relative_move(0, 0, 0, 20) end),
    awful.key({modkey, "Control"}, "a", function(c) c:relative_move(0, 0, -20, 0) end),
    awful.key({modkey, "Control"}, "d", function(c) c:relative_move(0, 0, 20, 0) end),
    awful.key({modkey}, "n", function(c) c.minimized = true end,
              {description = "minimize", group = "client"}),
    awful.key({modkey}, "m", function(c) c.maximized = not c.maximized; c:raise() end,
              {description = "(un)maximize", group = "client"}),
    awful.key({modkey, "Control"}, "m", function(c) c.maximized_vertical = not c.maximized_vertical; c:raise() end,
              {description = "(un)maximize vertically", group = "client"}),
    awful.key({modkey, "Shift"}, "m", function(c) c.maximized_horizontal = not c.maximized_horizontal; c:raise() end,
              {description = "(un)maximize horizontally", group = "client"})
)

-- ===== КЛАВИШИ ТЕГОВ =====
for i = 1, 9 do
    globalkeys = gears.table.join(globalkeys,
        awful.key({modkey}, "#" .. i + 9, function()
            local screen = awful.screen.focused()
            local tag = screen.tags[i]
            if tag then tag:view_only() end
        end, {description = "view tag #" .. i, group = "tag"}),
        
        awful.key({modkey, "Control"}, "#" .. i + 9, function()
            local screen = awful.screen.focused()
            local tag = screen.tags[i]
            if tag then awful.tag.viewtoggle(tag) end
        end, {description = "toggle tag #" .. i, group = "tag"}),
        
        awful.key({modkey, "Shift"}, "#" .. i + 9, function()
            if client.focus then
                local tag = client.focus.screen.tags[i]
                if tag then client.focus:move_to_tag(tag) end
            end
        end, {description = "move focused client to tag #" .. i, group = "tag"}),
        
        awful.key({modkey, "Control", "Shift"}, "#" .. i + 9, function()
            if client.focus then
                local tag = client.focus.screen.tags[i]
                if tag then client.focus:toggle_tag(tag) end
            end
        end, {description = "toggle focused client on tag #" .. i, group = "tag"})
    )
end

-- ===== КНОПКИ КЛИЕНТОВ =====
clientbuttons = gears.table.join(
    awful.button({}, 1, function(c) 
        c:emit_signal("request::activate", "mouse_click", {raise = true}) 
    end),
    awful.button({modkey}, 1, function(c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
        awful.mouse.client.move(c)
    end),
    awful.button({modkey}, 3, function(c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
        awful.mouse.client.resize(c)
    end)
)

-- ===== ПРИМЕНЕНИЕ КЛАВИШ =====
root.keys(globalkeys)

-- ===== ПРАВИЛА =====
awful.rules.rules = {
    {
        rule = {},
        properties = {
            border_width = beautiful.border_width,
            border_color = beautiful.border_normal,
            focus = awful.client.focus.filter,
            raise = true,
            keys = clientkeys,
            buttons = clientbuttons,
            screen = awful.screen.preferred,
            placement = awful.placement.no_overlap + awful.placement.no_offscreen
        }
    },
    {
        rule_any = {
            instance = {"DTA", "copyq", "pinentry"},
            class = {"Arandr", "Blueman-manager", "Gpick", "Kruler", "MessageWin",
                     "Sxiv", "Tor Browser", "Wpa_gui", "veromix", "xtightvncviewer"},
            name = {"Event Tester"},
            role = {"AlarmWindow", "ConfigManager", "pop-up"}
        },
        properties = {floating = true}
    },
    {
        rule_any = {type = {"normal", "dialog"}},
        properties = {titlebars_enabled = false}
    }
}

-- ===== СИГНАЛЫ КЛИЕНТОВ =====
client.connect_signal("manage", function(c)
    if awesome.startup and not c.size_hints.user_position and not c.size_hints.program_position then
        awful.placement.no_offscreen(c)
    end
end)

client.connect_signal("request::titlebars", function(c)
    local buttons = gears.table.join(
        awful.button({}, 1, function()
            c:emit_signal("request::activate", "titlebar", {raise = true})
            awful.mouse.client.move(c)
        end),
        awful.button({}, 3, function()
            c:emit_signal("request::activate", "titlebar", {raise = true})
            awful.mouse.client.resize(c)
        end)
    )
    
    awful.titlebar(c):setup {
        {
            awful.titlebar.widget.iconwidget(c),
            buttons = buttons,
            layout = wibox.layout.fixed.horizontal
        },
        {
            {
                align = "center",
                widget = awful.titlebar.widget.titlewidget(c)
            },
            buttons = buttons,
            layout = wibox.layout.flex.horizontal
        },
        {
            awful.titlebar.widget.floatingbutton(c),
            awful.titlebar.widget.maximizedbutton(c),
            awful.titlebar.widget.stickybutton(c),
            awful.titlebar.widget.ontopbutton(c),
            awful.titlebar.widget.closebutton(c),
            layout = wibox.layout.fixed.horizontal()
        },
        layout = wibox.layout.align.horizontal
    }
end)

client.connect_signal("mouse::enter", function(c)
    c:emit_signal("request::activate", "mouse_enter", {raise = false})
end)

client.connect_signal("focus", function(c) 
    c.border_color = beautiful.border_focus 
end)

client.connect_signal("unfocus", function(c) 
    c.border_color = beautiful.border_normal 
end)
