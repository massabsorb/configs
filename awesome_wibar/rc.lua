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
}

APPS.editor_cmd = APPS.terminal .. " -e " .. APPS.editor
local modkey = "Mod4"

-- ===== АВТОЗАПУСК =====
awful.spawn("picom -b")
awful.spawn("conky -c /home/mark/.config/conky/conky.conf")

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
beautiful.font = "Fira Code Retina 12"
beautiful.icon_font = beautiful.icon_font or "Symbols Nerd Font Mono 13"

-- Цветовая схема
beautiful.bg_normal     = "#000000"
beautiful.bg_focus      = "#000000"
beautiful.bg_urgent     = "#000000"
beautiful.bg_minimize   = "#000000"
beautiful.fg_normal     = "#ffffff"
beautiful.fg_focus      = "#fff8cb"
beautiful.fg_urgent     = "#ff5555"
beautiful.border_width  = 2
beautiful.border_color  = "#393869"
beautiful.tag_color     = "#D92639"
beautiful.tag_active    = "#00ff00"

-- ===== РАСКЛАДКИ =====
awful.layout.layouts = {
    awful.layout.suit.floating,
}

-- ===== ИКОНКИ ТЕГОВ =====
local tags_icons = {
    [1] = "󰬺", [2] = "󰬻", [3] = "󰬼", [4] = "󰬽", [5] = "󰬾",
    [6] = "󰬿", [7] = "󰭀", [8] = "󰭁", [9] = "󰭂",
}

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

-- ===== ВИДЖЕТ ТЕГОВ =====
local function create_tag_widget(s)
    local container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }
    
    local function update_tags()
        container:reset()
        for i, tag in ipairs(s.tags) do
            local icon = tags_icons[i] or "󰊠"
            local color
            
            if tag == s.selected_tag then
                color = beautiful.fg_focus
            elseif #tag:clients() > 0 then
                color = beautiful.tag_active
            elseif tag.urgent then
                color = beautiful.fg_urgent
            else
                color = beautiful.tag_color
            end
            
            local textbox = create_icon_textbox(icon, color)
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
    
    -- Подписка на обновления
    tag.connect_signal("property::selected", update_tags)
    tag.connect_signal("property::urgent", update_tags)
    client.connect_signal("tagged", update_tags)
    client.connect_signal("untagged", update_tags)
    client.connect_signal("unmanage", update_tags)
    
    update_tags()
    return container
end

-- ===== ВИДЖЕТ ИКОНОК ЗАДАЧ =====
local function create_task_icons_widget(s)
    local container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }

    local function update_task_icons()
        container:reset()
        local tag = s.selected_tag
        if not tag then return end

        for _, c in ipairs(tag:clients()) do
            local icon_widget
            
            if c.icon then
                icon_widget = wibox.widget {
                    image = c.icon,
                    resize = true,
                    forced_width = 24,
                    forced_height = 24,
                    widget = wibox.widget.imagebox
                }
            else
                local first_letter = string.sub(c.name or "?", 1, 1)
                icon_widget = wibox.widget {
                    markup = '<span font="JetBrains Mono 14">' .. first_letter .. '</span>',
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

    -- Подписка на обновления
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

    update_task_icons()
    return container
end

-- ===== ВИДЖЕТ ГРОМКОСТИ =====
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
    layout = wibox.layout.fixed.horizontal,
}

local function get_volume_icon(volume_percent, muted)
    if muted then return "󰝟" end
    if volume_percent < 33 then return "󰕿" end
    if volume_percent < 66 then return "󰖀" end
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
    else
        awful.spawn.easy_async(
            "sh -c 'pactl get-sink-mute @DEFAULT_SINK@ && pactl get-sink-volume @DEFAULT_SINK@ | grep -oP \"\\d+%\" | head -1'",
            function(stdout)
                local mute, percent = stdout:match("(.+)\n(.+)")
                percent = percent and tonumber(percent:match("(%d+)")) or 0
                local muted = mute and mute:match("Mute: yes") ~= nil
                local icon = get_volume_icon(percent, muted)
                volume_widget.icon.markup = '<span font="' .. beautiful.icon_font .. '">' .. icon .. '</span>'
            end
        )
    end
end

local function change_volume(delta)
    if volume_backend == "wpctl" then
        awful.spawn(string.format("wpctl set-volume @DEFAULT_AUDIO_SINK@ %d%%", delta), false)
    else
        local sign = delta >= 0 and "+" or ""
        awful.spawn(string.format("pactl set-sink-volume @DEFAULT_SINK@ %s%d%%", sign, delta), false)
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

-- ===== ВИДЖЕТ РАСКЛАДКИ =====
local layout_text_widget = wibox.widget.textbox()
layout_text_widget.font = beautiful.font

local function update_layout_widget(s)
    local tag = s.selected_tag
    if tag then
        local layout_names = {
            [awful.layout.suit.floating] = "FLOAT",
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

local months = { "янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек" }
local weekdays = { "Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб" }

local function update_clock()
    local now = os.date("*t")
    local date_str = string.format("%s %02d %s %02d:%02d:%02d",
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

    local left_box = wibox.widget {
        tag_widget,
        task_icons_widget,
        layout = wibox.layout.fixed.horizontal,
        spacing = 12,
    }

    local right_box = wibox.widget {
        clock_widget,
        layout_text_widget,
        volume_widget,
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,
    }

    s.mywibox = awful.wibar({
        position = "bottom",
        screen = s,
        height = 34,
        bg = beautiful.bg_normal,
        fg = beautiful.fg_normal,
        border_width = beautiful.border_width,
        border_color = beautiful.border_color,
        ontop = true,
        cursor = "arrow",
        visible = true,
        stretch = true,
    })

    s.mywibox:setup {
        layout = wibox.layout.align.horizontal,
        left_box,
        nil,
        right_box,
    }

    -- Автоматическое скрытие панели
    local function update_wibar_visibility()
        local has_maximized = false
        for _, c in ipairs(s.clients) do
            if c.maximized and c:isvisible() then
                has_maximized = true
                break
            end
        end
        s.mywibox.visible = not has_maximized
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
    awful.button({}, 3, function() mymainmenu:toggle() end),
    awful.button({}, 4, awful.tag.viewnext),
    awful.button({}, 5, awful.tag.viewprev)
))

-- ===== ГЛОБАЛЬНЫЕ КЛАВИШИ =====
globalkeys = gears.table.join(
    -- Управление размерами floating окон
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

    -- Перемещение floating окон
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

    -- Основные клавиши
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
    awful.key({modkey}, "j", function() awful.client.focus.byidx(1) end,
              {description = "focus next by index", group = "client"}),
    awful.key({modkey}, "k", function() awful.client.focus.byidx(-1) end,
              {description = "focus previous by index", group = "client"}),
    awful.key({modkey}, "w", function() mymainmenu:show() end,
              {description = "show main menu", group = "awesome"}),
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
