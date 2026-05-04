-- If LuaRocks is installed, make sure that packages installed through it are
-- found (e.g. lgi). If LuaRocks is not installed, do nothing.
pcall(require, "luarocks.loader")

-- Standard awesome library
local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")
-- Widget and layout library
local wibox = require("wibox")
-- Theme handling library
local beautiful = require("beautiful")
-- Notification library
local naughty = require("naughty")
local menubar = require("menubar")
local hotkeys_popup = require("awful.hotkeys_popup")
require("awful.hotkeys_popup.keys")

-- {{{ Error handling
if awesome.startup_errors then
    naughty.notify({ preset = naughty.config.presets.critical,
                     title = "Oops, there were errors during startup!",
                     text = awesome.startup_errors })
end

do
    local in_error = false
    awesome.connect_signal("debug::error", function (err)
        if in_error then return end
        in_error = true
        naughty.notify({ preset = naughty.config.presets.critical,
                         title = "Oops, an error happened!",
                         text = tostring(err) })
        in_error = false
    end)
end
-- }}}

-- {{{ Variable definitions
beautiful.init(gears.filesystem.get_themes_dir() .. "default/theme.lua")

-- ████████████████████████████████████████████████████████████████████████
-- ◀ НАСТРОЙКИ СТИЛЯ (как в polybar) ▶
-- ████████████████████████████████████████████████████████████████████████
beautiful.font = "JetBrains Mono 11"
if not beautiful.icon_font then
    beautiful.icon_font = "Symbols Nerd Font Mono 13"
end

beautiful.bg_normal     = "#000000"
beautiful.bg_focus      = "#000000"
beautiful.bg_urgent     = "#000000"
beautiful.bg_minimize   = "#000000"
beautiful.fg_normal     = "#ffffff"
beautiful.fg_focus      = "#fff8cb"
beautiful.fg_urgent     = "#ff5555"
beautiful.border_width  = 2
beautiful.border_color  = "#393869"
-- ████████████████████████████████████████████████████████████████████████

terminal = "kitty"
editor = os.getenv("EDITOR") or "nano"
editor_cmd = terminal .. " -e " .. editor
modkey = "Mod4"

awful.layout.layouts = {
    awful.layout.suit.floating,
    awful.layout.suit.tile,
    awful.layout.suit.tile.left,
    awful.layout.suit.tile.bottom,
    awful.layout.suit.tile.top,
}
-- }}}

-- {{{ Menu
myawesomemenu = {
   { "hotkeys", function() hotkeys_popup.show_help(nil, awful.screen.focused()) end },
   { "manual", terminal .. " -e man awesome" },
   { "edit config", editor_cmd .. " " .. awesome.conffile },
   { "restart", awesome.restart },
   { "quit", function() awesome.quit() end },
}

mymainmenu = awful.menu({ items = { { "awesome", myawesomemenu, beautiful.awesome_icon },
                                    { "open terminal", terminal }
                                  }
                        })

mylauncher = awful.widget.launcher({ image = beautiful.awesome_icon,
                                     menu = mymainmenu })

menubar.utils.terminal = terminal
-- }}}

-- ████████████████████████████████████████████████████████████████████████
-- ◀ ВИДЖЕТЫ В СТИЛЕ POLYBAR ▶
-- ████████████████████████████████████████████████████████████████████████

-- 1️⃣ Иконки для рабочих столов (NERD FONTS)
local tags_icons = {
    [1] = "",   -- web
    [2] = "",   -- code
    [3] = "",   -- music
    [4] = "",   -- files
    [5] = "",   -- chat
    [6] = "",   -- graphics
    [7] = "",   -- misc
    [8] = "",   -- term
    [9] = "",   -- video
}

-- ★★★ КАСТОМНЫЙ ВИДЖЕТ ТЕГОВ (ТОЛЬКО ИКОНКИ, С РАССТОЯНИЕМ) ★★★
local function create_tag_widget(s)
    local container = wibox.widget {
        layout = wibox.layout.fixed.horizontal,
        spacing = 8,   -- ← УВЕЛИЧЕННЫЙ ОТСТУП МЕЖДУ ТЕГАМИ (было 2)
    }
    
    local function update_tags()
        container:reset()
        local tags = s.tags
        for i, tag in ipairs(tags) do
            local icon = tags_icons[i] or "󰊠"
            local color
            if tag == s.selected_tag then
                color = beautiful.fg_focus
            elseif #tag:clients() > 0 then
                color = "#00ff00"
            elseif tag.urgent then
                color = beautiful.fg_urgent
            else
                color = "#D92639"
            end
            
            local textbox = wibox.widget {
                markup = '<span font="' .. beautiful.icon_font .. '" foreground="' .. color .. '">' .. icon .. '</span>',
                widget = wibox.widget.textbox,
            }
            
            textbox:buttons(gears.table.join(
                awful.button({ }, 1, function() tag:view_only() end),
                awful.button({ modkey }, 1, function()
                    if client.focus then client.focus:move_to_tag(tag) end
                end),
                awful.button({ }, 3, function() awful.tag.viewtoggle(tag) end),
                awful.button({ modkey }, 3, function()
                    if client.focus then client.focus:toggle_tag(tag) end
                end),
                awful.button({ }, 4, function() awful.tag.viewnext(s) end),
                awful.button({ }, 5, function() awful.tag.viewprev(s) end)
            ))
            
            container:add(textbox)
        end
    end
    
    tag.connect_signal("property::selected", update_tags)
    tag.connect_signal("property::urgent", update_tags)
    client.connect_signal("tagged", update_tags)
    client.connect_signal("untagged", update_tags)
    
    update_tags()
    return container
end

-- 2️⃣ Виджет громкости (единственный правый виджет, без клавиатуры)
local volume_widget = wibox.widget {
    {
        id = "icon",
        widget = wibox.widget.textbox,
        markup = '<span font="' .. beautiful.icon_font .. '">󰕾</span>',
    },
    layout = wibox.layout.fixed.horizontal,
}

local function update_volume_icon()
    awful.spawn.easy_async(
        "sh -c 'pactl get-sink-mute @DEFAULT_SINK@ && pactl get-sink-volume @DEFAULT_SINK@ | grep -oP \"\\d+%\" | head -1'",
        function(stdout)
            local mute, percent = stdout:match("(.+)\n(.+)")
            if not percent then percent = stdout end
            percent = tonumber(percent:match("(%d+)")) or 0
            local icon_char
            if mute and mute:match("Mute: yes") then
                icon_char = "󰝟"
            elseif percent == 0 then
                icon_char = "󰕿"
            elseif percent < 33 then
                icon_char = "󰕿"
            elseif percent < 66 then
                icon_char = "󰖀"
            else
                icon_char = "󰕾"
            end
            volume_widget.icon.markup = '<span font="' .. beautiful.icon_font .. '">' .. icon_char .. '</span>'
        end
    )
end

volume_widget:buttons(gears.table.join(
    awful.button({}, 1, function() awful.spawn("pavucontrol") end),
    awful.button({}, 4, function() awful.spawn("pactl set-sink-volume @DEFAULT_SINK@ +5%"); update_volume_icon() end),
    awful.button({}, 5, function() awful.spawn("pactl set-sink-volume @DEFAULT_SINK@ -5%"); update_volume_icon() end),
    awful.button({}, 2, function() awful.spawn("pactl set-sink-mute @DEFAULT_SINK@ toggle"); update_volume_icon() end)
))

gears.timer {
    timeout = 2,
    call_now = true,
    autostart = true,
    callback = update_volume_icon,
}

-- 3️⃣ Виджет даты/времени (будет выровнен по центру)
local clock_widget = wibox.widget.textclock('<span foreground="#ffffff">%a, %d %b %Y %H:%M:%S</span>', 1)
clock_widget.font = beautiful.font

-- ████████████████████████████████████████████████████████████████████████

-- {{{ Wibar
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

awful.screen.connect_for_each_screen(function(s)
    set_wallpaper(s)
    awful.tag({ "1", "2", "3", "4", "5", "6", "7", "8", "9" }, s, awful.layout.layouts[1])

    s.mypromptbox = awful.widget.prompt()
    s.mylayoutbox = awful.widget.layoutbox(s)
    s.mylayoutbox:buttons(gears.table.join(
        awful.button({ }, 1, function () awful.layout.inc( 1) end),
        awful.button({ }, 3, function () awful.layout.inc(-1) end),
        awful.button({ }, 4, function () awful.layout.inc( 1) end),
        awful.button({ }, 5, function () awful.layout.inc(-1) end)
    ))

    -- Кастомный виджет тегов
    local tag_widget = create_tag_widget(s)
    
    -- Левая часть (теги) и правая часть (только громкость)
    local left_box = wibox.widget { tag_widget, layout = wibox.layout.fixed.horizontal }
    local right_box = wibox.widget { volume_widget, layout = wibox.layout.fixed.horizontal }
    
    -- Центрирование часов
    local centered_clock = wibox.container.place(clock_widget, { halign = "center", valign = "center" })
    
    -- Панель внизу
    s.mywibox = awful.wibar({
        position = "bottom",
        screen = s,
        height = 28,
        bg = beautiful.bg_normal,
        fg = beautiful.fg_normal,
        border_width = beautiful.border_width,
        border_color = beautiful.border_color,
        ontop = true,
        cursor = "arrow",
        visible = true,
        stretch = true,
    })
    
    -- Размещение: лево, центр (расширяется), право
    s.mywibox:setup {
        layout = wibox.layout.align.horizontal,
        left_box,
        centered_clock,
        right_box,
    }
end)
-- }}}

-- {{{ Mouse bindings
root.buttons(gears.table.join(
    awful.button({ }, 3, function () mymainmenu:toggle() end),
    awful.button({ }, 4, awful.tag.viewnext),
    awful.button({ }, 5, awful.tag.viewprev)
))
-- }}}

-- {{{ Key bindings (ваши старые, сохранены)
globalkeys = gears.table.join(
    awful.key({ modkey,           }, "s",      hotkeys_popup.show_help,
              {description="show help", group="awesome"}),
    awful.key({ modkey,           }, "Left",   awful.tag.viewprev,
              {description = "view previous", group = "tag"}),
    awful.key({ modkey,           }, "Right",  awful.tag.viewnext,
              {description = "view next", group = "tag"}),
    awful.key({ modkey,           }, "Escape", awful.tag.history.restore,
              {description = "go back", group = "tag"}),
    awful.key({modkey, }, "p", function () awful.spawn("rofi -show drun -theme ~/.config/rofi/config.rasi") end),
    awful.key({ modkey,           }, "j",
        function () awful.client.focus.byidx( 1) end,
        {description = "focus next by index", group = "client"}),
    awful.key({ modkey,           }, "k",
        function () awful.client.focus.byidx(-1) end,
        {description = "focus previous by index", group = "client"}),
    awful.key({ modkey,           }, "w", function () mymainmenu:show() end,
              {description = "show main menu", group = "awesome"}),
    awful.key({ modkey, "Shift"   }, "j", function () awful.client.swap.byidx( 1)    end,
              {description = "swap with next client by index", group = "client"}),
    awful.key({ modkey, "Shift"   }, "k", function () awful.client.swap.byidx(-1)    end,
              {description = "swap with previous client by index", group = "client"}),
    awful.key({ modkey, "Control" }, "j", function () awful.screen.focus_relative( 1) end,
              {description = "focus the next screen", group = "screen"}),
    awful.key({ modkey, "Control" }, "k", function () awful.screen.focus_relative(-1) end,
              {description = "focus the previous screen", group = "screen"}),
    awful.key({ modkey,           }, "u", awful.client.urgent.jumpto,
              {description = "jump to urgent client", group = "client"}),
    awful.key({ modkey,           }, "Tab",
        function ()
            awful.client.focus.history.previous()
            if client.focus then client.focus:raise() end
        end,
        {description = "go back", group = "client"}),
    awful.key({ modkey,           }, "Return", function () awful.spawn(terminal) end,
              {description = "open a terminal", group = "launcher"}),
    awful.key({ modkey, "Control" }, "r", awesome.restart,
              {description = "reload awesome", group = "awesome"}),
    awful.key({ modkey, "Shift"   }, "q", awesome.quit,
              {description = "quit awesome", group = "awesome"}),
    awful.key({ modkey,           }, "l",     function () awful.tag.incmwfact( 0.05)          end,
              {description = "increase master width factor", group = "layout"}),
    awful.key({ modkey,           }, "h",     function () awful.tag.incmwfact(-0.05)          end,
              {description = "decrease master width factor", group = "layout"}),
    awful.key({ modkey, "Shift"   }, "h",     function () awful.tag.incnmaster( 1, nil, true) end,
              {description = "increase the number of master clients", group = "layout"}),
    awful.key({ modkey, "Shift"   }, "l",     function () awful.tag.incnmaster(-1, nil, true) end,
              {description = "decrease the number of master clients", group = "layout"}),
    awful.key({ modkey, "Control" }, "h",     function () awful.tag.incncol( 1, nil, true)    end,
              {description = "increase the number of columns", group = "layout"}),
    awful.key({ modkey, "Control" }, "l",     function () awful.tag.incncol(-1, nil, true)    end,
              {description = "decrease the number of columns", group = "layout"}),
    awful.key({ modkey,           }, "space", function () awful.layout.inc( 1)                end,
              {description = "select next", group = "layout"}),
    awful.key({ modkey, "Shift"   }, "space", function () awful.layout.inc(-1)                end,
              {description = "select previous", group = "layout"}),
    awful.key({ modkey, "Control" }, "n",
              function ()
                  local c = awful.client.restore()
                  if c then
                    c:emit_signal("request::activate", "key.unminimize", {raise = true})
                  end
              end,
              {description = "restore minimized", group = "client"}),
    awful.key({ modkey },            "r",     function () awful.screen.focused().mypromptbox:run() end,
              {description = "run prompt", group = "launcher"}),
    awful.key({ modkey }, "x",
              function ()
                  awful.prompt.run {
                    prompt       = "Run Lua code: ",
                    textbox      = awful.screen.focused().mypromptbox.widget,
                    exe_callback = awful.util.eval,
                    history_path = awful.util.get_cache_dir() .. "/history_eval"
                  }
              end,
              {description = "lua execute prompt", group = "awesome"})
)

clientkeys = gears.table.join(
    awful.key({ modkey,           }, "f",
        function (c) c.fullscreen = not c.fullscreen; c:raise() end,
        {description = "toggle fullscreen", group = "client"}),
    awful.key({ modkey, "Shift"   }, "c",      function (c) c:kill() end,
              {description = "close", group = "client"}),
    awful.key({ modkey, "Control" }, "space",  awful.client.floating.toggle,
              {description = "toggle floating", group = "client"}),
    awful.key({ modkey, "Control" }, "Return", function (c) c:swap(awful.client.getmaster()) end,
              {description = "move to master", group = "client"}),
    awful.key({ modkey,           }, "o",      function (c) c:move_to_screen() end,
              {description = "move to screen", group = "client"}),
    awful.key({ modkey,           }, "t",      function (c) c.ontop = not c.ontop end,
              {description = "toggle keep on top", group = "client"}),
    awful.key({ modkey, "Control" }, "w", function(c) c:relative_move(0, 0, 0, -20) end),
    awful.key({ modkey, "Control" }, "s", function(c) c:relative_move(0, 0, 0,  20) end),
    awful.key({ modkey, "Control" }, "a", function(c) c:relative_move(0, 0, -20, 0) end),
    awful.key({ modkey, "Control" }, "d", function(c) c:relative_move(0, 0,  20, 0) end),
    awful.key({ modkey,           }, "n", function (c) c.minimized = true end,
              {description = "minimize", group = "client"}),
    awful.key({ modkey,           }, "m", function (c) c.maximized = not c.maximized; c:raise() end,
              {description = "(un)maximize", group = "client"}),
    awful.key({ modkey, "Control" }, "m", function (c) c.maximized_vertical = not c.maximized_vertical; c:raise() end,
              {description = "(un)maximize vertically", group = "client"}),
    awful.key({ modkey, "Shift"   }, "m", function (c) c.maximized_horizontal = not c.maximized_horizontal; c:raise() end,
              {description = "(un)maximize horizontally", group = "client"})
)

for i = 1, 9 do
    globalkeys = gears.table.join(globalkeys,
        awful.key({ modkey }, "#" .. i + 9,
                  function ()
                        local screen = awful.screen.focused()
                        local tag = screen.tags[i]
                        if tag then tag:view_only() end
                  end,
                  {description = "view tag #"..i, group = "tag"}),
        awful.key({ modkey, "Control" }, "#" .. i + 9,
                  function ()
                      local screen = awful.screen.focused()
                      local tag = screen.tags[i]
                      if tag then awful.tag.viewtoggle(tag) end
                  end,
                  {description = "toggle tag #" .. i, group = "tag"}),
        awful.key({ modkey, "Shift" }, "#" .. i + 9,
                  function ()
                      if client.focus then
                          local tag = client.focus.screen.tags[i]
                          if tag then client.focus:move_to_tag(tag) end
                      end
                  end,
                  {description = "move focused client to tag #"..i, group = "tag"}),
        awful.key({ modkey, "Control", "Shift" }, "#" .. i + 9,
                  function ()
                      if client.focus then
                          local tag = client.focus.screen.tags[i]
                          if tag then client.focus:toggle_tag(tag) end
                      end
                  end,
                  {description = "toggle focused client on tag #" .. i, group = "tag"})
    )
end

clientbuttons = gears.table.join(
    awful.button({ }, 1, function (c) c:emit_signal("request::activate", "mouse_click", {raise = true}) end),
    awful.button({ modkey }, 1, function (c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
        awful.mouse.client.move(c)
    end),
    awful.button({ modkey }, 3, function (c)
        c:emit_signal("request::activate", "mouse_click", {raise = true})
        awful.mouse.client.resize(c)
    end)
)

root.keys(globalkeys)
-- }}}

-- {{{ Rules
awful.rules.rules = {
    { rule = { },
      properties = { border_width = beautiful.border_width,
                     border_color = beautiful.border_normal,
                     focus = awful.client.focus.filter,
                     raise = true,
                     keys = clientkeys,
                     buttons = clientbuttons,
                     screen = awful.screen.preferred,
                     placement = awful.placement.no_overlap+awful.placement.no_offscreen
     }
    },
    { rule_any = {
        instance = { "DTA", "copyq", "pinentry" },
        class = { "Arandr", "Blueman-manager", "Gpick", "Kruler", "MessageWin",
                  "Sxiv", "Tor Browser", "Wpa_gui", "veromix", "xtightvncviewer" },
        name = { "Event Tester" },
        role = { "AlarmWindow", "ConfigManager", "pop-up" }
      }, properties = { floating = true } },
    { rule_any = {type = { "normal", "dialog" } }, properties = { titlebars_enabled = false } }
}
-- }}}

-- {{{ Signals
client.connect_signal("manage", function (c)
    if awesome.startup and not c.size_hints.user_position and not c.size_hints.program_position then
        awful.placement.no_offscreen(c)
    end
end)

client.connect_signal("request::titlebars", function(c)
    local buttons = gears.table.join(
        awful.button({ }, 1, function()
            c:emit_signal("request::activate", "titlebar", {raise = true})
            awful.mouse.client.move(c)
        end),
        awful.button({ }, 3, function()
            c:emit_signal("request::activate", "titlebar", {raise = true})
            awful.mouse.client.resize(c)
        end)
    )
    awful.titlebar(c) : setup {
        { awful.titlebar.widget.iconwidget(c), buttons = buttons, layout = wibox.layout.fixed.horizontal },
        { { align = "center", widget = awful.titlebar.widget.titlewidget(c) }, buttons = buttons, layout = wibox.layout.flex.horizontal },
        { awful.titlebar.widget.floatingbutton(c), awful.titlebar.widget.maximizedbutton(c),
          awful.titlebar.widget.stickybutton(c), awful.titlebar.widget.ontopbutton(c),
          awful.titlebar.widget.closebutton(c), layout = wibox.layout.fixed.horizontal() },
        layout = wibox.layout.align.horizontal
    }
end)

client.connect_signal("mouse::enter", function(c)
    c:emit_signal("request::activate", "mouse_enter", {raise = false})
end)

client.connect_signal("focus", function(c) c.border_color = beautiful.border_focus end)
client.connect_signal("unfocus", function(c) c.border_color = beautiful.border_normal end)
-- }}}
