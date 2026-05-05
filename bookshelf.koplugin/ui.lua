local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = Device.screen
local T = ffiUtil.template

local source = debug.getinfo(1, "S").source or ""
local plugin_dir = source:match("^@(.+)/[^/]+$") or "plugins/bookshelf.koplugin"
local GridLayout = dofile(plugin_dir .. "/gridlayout.lua")
local Icons = dofile(plugin_dir .. "/icons.lua")

local FontTokens = {
    display = "NotoSerif-Regular.ttf",
    display_italic = "NotoSerif-Italic.ttf",
    serif_safe = "NotoSerif-Regular.ttf",
    sans = "NotoSans-Regular.ttf",
    sans_bold = "NotoSans-Bold.ttf",
}

local TypeScale = {
    book_meta_small = 9,
    book_meta_large = 10,
    book_title_small = 11,
    book_title_large = 12,
    category = 13,
    control = 13,
    page_title = 38,
}

local IconTokens = {
    visual = 24,
    tap = 40,
}

local function scale(n)
    return Screen:scaleBySize(n)
end

local function clampWidth(width)
    return math.max(scale(8), math.floor(width or 0))
end

local function clampPercent(value)
    value = tonumber(value) or 0
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

local LibraryUI = InputContainer:extend{
    title = _("Library"),
    is_borderless = true,
    zones = nil,
    library_page = 1,
    pressed_zone_id = nil,
}

function LibraryUI:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.ges_events.Tap = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        },
    }
    self.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            range = self.dimen,
        },
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

function LibraryUI:closeBookshelf()
    if self._closed then
        return
    end
    self._closed = true
    UIManager:close(self)
    if self.closed_callback then
        self.closed_callback()
    end
end

function LibraryUI:onClose()
    self:closeBookshelf()
    return true
end

function LibraryUI:onCloseAllMenus()
    self:closeBookshelf()
    return true
end

function LibraryUI:_providerOptions()
    return {
        ui = self.ui,
    }
end

function LibraryUI:_providerCall(method, ...)
    if type(self.provider) ~= "table" or type(self.provider[method]) ~= "function" then
        return nil
    end

    local fn = self.provider[method]
    local ok, result = pcall(fn, self:_providerOptions(), ...)
    if ok and result ~= nil then
        return result
    elseif not ok then
        logger.warn("Bookshelf provider static call failed:", method, result)
    end

    ok, result = pcall(fn, self.provider, self:_providerOptions(), ...)
    if ok then
        return result
    end
    logger.warn("Bookshelf provider method failed:", method, result)
    return nil
end

function LibraryUI:_providerList(...)
    local result
    for _, method in ipairs({...}) do
        result = self:_providerCall(method)
        if type(result) == "table" then
            break
        end
    end
    if type(result) ~= "table" then
        return {}
    end
    if type(result.items) == "table" then
        result = result.items
    end
    if type(result[1]) == "nil" then
        return {}
    end
    return result
end

function LibraryUI:_providerEntry(...)
    for _, method in ipairs({...}) do
        local result = self:_providerCall(method)
        if type(result) == "table" then
            return result
        end
    end
    return nil
end

function LibraryUI:_fileName(file)
    if type(file) ~= "string" or file == "" then
        return nil
    end
    local path, name = util.splitFilePathName(file) -- luacheck: no unused
    return BD.filename(name)
end

function LibraryUI:_cleanDisplayTitle(title)
    if type(title) ~= "string" or title == "" then
        return nil
    end
    title = title:gsub("^%s+", ""):gsub("%s+$", "")
    if title:lower():match("^quickstart[%s%-_]") then
        return _("Quickstart Guide")
    end
    return BD.auto(title)
end

function LibraryUI:_fileTitle(file)
    if type(file) ~= "string" or file == "" then
        return nil
    end
    local title = filemanagerutil.splitFileNameType(file)
    if type(title) ~= "string" or title == "" then
        return self:_fileName(file)
    end
    title = title:gsub("[_-]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if title:lower():match("^quickstart%s+") then
        title = _("Quickstart Guide")
    end
    return BD.filename(title)
end

function LibraryUI:_entryTitle(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local title = self:_cleanDisplayTitle(entry.display_title)
        or self:_cleanDisplayTitle(entry.title)
        or self:_cleanDisplayTitle(entry.text)
        or self:_cleanDisplayTitle(entry.name)
    if title then
        return title
    end
    return self:_fileTitle(entry.file or entry.path)
end

function LibraryUI:_entryAuthor(entry)
    if type(entry) ~= "table" then
        return nil
    end
    return self:_cleanDisplayTitle(entry.authors)
        or self:_cleanDisplayTitle(entry.author)
        or self:_cleanDisplayTitle(entry.subtitle)
        or self:_cleanDisplayTitle(entry.series)
end

function LibraryUI:_currentFile()
    local document = self.ui and self.ui.document
    return document and document.file
end

function LibraryUI:_isCurrentFile(file)
    return type(file) == "string" and file ~= "" and file == self:_currentFile()
end

function LibraryUI:_currentPageInfo()
    local current_page
    if self.ui and type(self.ui.getCurrentPage) == "function" then
        local ok, page = pcall(self.ui.getCurrentPage, self.ui)
        if ok then
            current_page = page
        end
    end

    local page_count
    local document = self.ui and self.ui.document
    if document and type(document.getPageCount) == "function" then
        local ok, count = pcall(document.getPageCount, document)
        if ok then
            page_count = count
        end
    end

    return tonumber(current_page), tonumber(page_count)
end

function LibraryUI:_currentPercentFinished()
    local footer = self.ui and self.ui.view and self.ui.view.footer
    if footer and footer.percent_finished then
        return clampPercent(footer.percent_finished)
    end
    local doc_settings = self.ui and self.ui.doc_settings
    if doc_settings and type(doc_settings.readSetting) == "function" then
        return clampPercent(doc_settings:readSetting("percent_finished"))
    end
    return 0
end

function LibraryUI:_normalizeContinueEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end
    if not entry.current and self:_isCurrentFile(entry.file or entry.path) then
        entry = util.tableDeepCopy(entry)
        entry.current = true
        entry.mandatory = _("Reading")
    end
    return entry
end

function LibraryUI:_currentDocumentEntry()
    local file = self:_currentFile()
    if not file then
        return nil
    end
    local doc_props = self.ui and self.ui.doc_props or {}
    local current_page, page_count = self:_currentPageInfo()
    return {
        text = self:_cleanDisplayTitle(doc_props.display_title)
            or self:_cleanDisplayTitle(doc_props.title)
            or self:_fileTitle(file)
            or _("Current book"),
        file = file,
        current = true,
        mandatory = _("Reading"),
        percent_finished = self:_currentPercentFinished(),
        current_page = current_page,
        pages = page_count,
        authors = self:_cleanDisplayTitle(doc_props.authors),
    }
end

function LibraryUI:_lastFileEntry()
    local file = G_reader_settings:readSetting("lastfile")
    if not file then
        return nil
    end
    return {
        text = self:_fileTitle(file) or _("Last book"),
        file = file,
        mandatory = _("Last"),
    }
end

function LibraryUI:_continueEntry()
    return self:_normalizeContinueEntry(self:_providerEntry("getContinue", "getContinueItem", "getLastReading"))
        or self:_currentDocumentEntry()
        or self:_lastFileEntry()
end

function LibraryUI:_downloadedEntries()
    return self:_providerList("getDownloaded", "getDownloadedItems", "getDownloadedBooks")
end

function LibraryUI:_uniqueEntries(entries)
    local unique = {}
    local seen = {}
    for _, entry in ipairs(entries) do
        local key = entry.id or entry.file or entry.path or self:_entryTitle(entry)
        if key and not seen[key] then
            seen[key] = true
            table.insert(unique, entry)
        end
    end
    return unique
end

function LibraryUI:_libraryEntries()
    local entries = {}
    local continue = self:_continueEntry()
    if continue then
        table.insert(entries, continue)
    end
    for _, entry in ipairs(self:_downloadedEntries()) do
        table.insert(entries, entry)
    end
    return self:_uniqueEntries(entries)
end

function LibraryUI:_recentlyAddedEntries()
    local entries = self:_providerList("getRecentlyAdded", "getRecentBooks", "getNewBooks")
    if #entries == 0 then
        entries = self:_libraryEntries()
    end
    return entries
end

function LibraryUI:_dictionary()
    if not self.ui then
        return nil
    end
    if self.ui.dictionary then
        return self.ui.dictionary
    end
    if type(self.ui.getDictionary) == "function" then
        return self.ui:getDictionary()
    end
    return nil
end

function LibraryUI:_opds()
    if not self.ui then
        return nil
    end
    if self.ui.opds then
        return self.ui.opds
    end
    if type(self.ui.getOPDS) == "function" then
        return self.ui:getOPDS()
    end
    return nil
end

function LibraryUI:_showInfo(text)
    UIManager:show(InfoMessage:new{
        text = text,
    })
end

function LibraryUI:_showDictionaryLookup()
    local dictionary = self:_dictionary()
    if dictionary and type(dictionary.onShowDictionaryLookup) == "function" then
        dictionary:onShowDictionaryLookup()
        return
    end

    self:_showInfo(_("Dictionary lookup is unavailable."))
end

function LibraryUI:_showFilter()
    self:_showInfo(_("Sort and filter controls are not configured yet."))
end

function LibraryUI:_showMore()
    self:_showInfo(_("Library actions are not configured yet."))
end

function LibraryUI:_showFiles(path)
    self:closeBookshelf()
    if self.ui and self.ui.file_chooser then
        if path then
            self.ui.file_chooser:changeToPath(path)
        end
        UIManager:setDirty(nil, "full")
        return
    end
    if self.ui and type(self.ui.showFileManager) == "function" then
        self.ui:showFileManager(path)
        return
    end
    require("apps/filemanager/filemanager"):showFiles(path)
end

function LibraryUI:_openEntry(entry)
    if type(entry) ~= "table" then
        return
    end
    if type(entry.callback) == "function" then
        local ok, err = pcall(entry.callback, entry, self)
        if not ok then
            logger.warn("Bookshelf entry callback failed:", err)
            self:_showInfo(_("This book could not be opened."))
        end
        return
    end

    local file = entry.file or entry.path
    if type(file) ~= "string" or file == "" then
        self:_showInfo(_("This book has no file to open."))
        return
    end

    local mode = lfs.attributes(file, "mode")
    if mode == "directory" then
        self:_showFiles(file)
    elseif mode == "file" then
        filemanagerutil.openFile(self.ui, file, function()
            self:closeBookshelf()
        end)
    else
        self:_showInfo(T(_("Book not found: %1"), BD.filepath(file)))
    end
end

function LibraryUI:_continue()
    local entry = self:_continueEntry()
    if not entry then
        return true
    elseif entry.current then
        self:closeBookshelf()
    else
        self:_openEntry(entry)
    end
end

function LibraryUI:_addBooks()
    local opds = self:_opds()
    if opds and type(opds.onShowOPDSCatalog) == "function" then
        opds:onShowOPDSCatalog()
        return
    end

    self:_showInfo(_("No book sources are configured."))
end

function LibraryUI:_zone(id, rect, callback)
    table.insert(self.zones, {
        id = id,
        rect = rect,
        callback = callback,
    })
end

function LibraryUI:_zoneAt(pos)
    if not pos then
        return nil
    end
    for i = #self.zones, 1, -1 do
        local zone = self.zones[i]
        if zone.rect:contains(pos) then
            return zone
        end
    end
end

function LibraryUI:_setPressedZone(zone)
    self.pressed_zone_id = zone.id
    UIManager:setDirty(self, "ui", zone.rect)
    UIManager:scheduleIn(0.05, function()
        if self._closed then
            return
        end
        self.pressed_zone_id = nil
        UIManager:setDirty(self, "ui", zone.rect)
        zone.callback()
    end)
end

function LibraryUI:_px(n)
    return GridLayout.scaleValue(n, self.shelf_scale or 1)
end

function LibraryUI:_iconSize()
    return self:_px(IconTokens.visual)
end

function LibraryUI:_iconTapSize()
    return self:_px(IconTokens.tap)
end

function LibraryUI:_hairline()
    return 1
end

function LibraryUI:_paintText(bb, text, x, y, options)
    options = options or {}
    local widget = TextWidget:new{
        text = text or "",
        face = Font:getFace(options.face or "smallinfofont", options.size or 22),
        bold = options.bold,
        fgcolor = options.color,
        max_width = options.max_width and clampWidth(options.max_width) or nil,
    }
    local size = widget:getSize()
    local paint_x = x
    local paint_y = y
    if options.align == "right" and options.width then
        paint_x = x + options.width - size.w
    elseif options.align == "center" and options.width then
        paint_x = x + math.floor((options.width - size.w) / 2)
    end
    if options.valign == "center" and options.height then
        paint_y = y + math.floor((options.height - size.h) / 2)
    end
    widget:paintTo(bb, paint_x, paint_y)
    widget:free()
    return size
end

function LibraryUI:_paintTextBox(bb, text, x, y, width, options)
    options = options or {}
    local widget = TextBoxWidget:new{
        text = text or "",
        face = Font:getFace(options.face or "cfont", options.size or 22),
        bold = options.bold,
        fgcolor = options.color,
        width = clampWidth(width),
        height = options.height and clampWidth(options.height) or nil,
        height_adjust = options.height_adjust,
        height_overflow_show_ellipsis = options.height ~= nil,
        alignment = options.align or "left",
        line_height = options.line_height or 0.18,
    }
    local size = widget:getSize()
    widget:paintTo(bb, x, y)
    widget:free(true)
    return size
end

function LibraryUI:_paintLine(bb, x, y, w, color)
    bb:paintRect(x, y, w, self:_hairline(), color or Blitbuffer.COLOR_LIGHT_GRAY)
end

function LibraryUI:_paintRectBorder(bb, x, y, w, h, color)
    color = color or Blitbuffer.COLOR_LIGHT_GRAY
    local line = self:_hairline()
    self:_paintLine(bb, x, y, w, color)
    self:_paintLine(bb, x, y + h - line, w, color)
    bb:paintRect(x, y, line, h, color)
    bb:paintRect(x + w - line, y, line, h, color)
end

function LibraryUI:_paintPressedRect(bb, id, x, y, w, h)
    if self.pressed_zone_id == id then
        bb:paintRect(x, y, w, h, Blitbuffer.COLOR_GRAY_E or Blitbuffer.COLOR_LIGHT_GRAY)
    end
end

function LibraryUI:_paintIcon(bb, icon, x, y, size, selected)
    Icons.paint(bb, icon, x, y, size, {
        selected = selected,
    })
end

function LibraryUI:_paintCenteredIcon(bb, icon, x, y, w, h, selected)
    local icon_size = self:_iconSize()
    local icon_x = x + math.floor((w - icon_size) / 2)
    local icon_y = y + math.floor((h - icon_size) / 2)
    self:_paintIcon(bb, icon, icon_x, icon_y, icon_size, selected)
    return icon_size
end

function LibraryUI:_paintStatusBar(bb, x, y, w)
    local time_text = os.date("%I:%M %p"):gsub("^0", "")
    self:_paintText(bb, time_text, x, y, {
        face = FontTokens.sans,
        size = 13,
        max_width = math.floor(w * 0.4),
    })

    local battery = nil
    if Device.powerd and type(Device.powerd.getCapacity) == "function" then
        local ok, capacity = pcall(Device.powerd.getCapacity, Device.powerd)
        if ok and capacity then
            battery = tonumber(capacity)
        end
    end
    if battery and battery > 0 then
        local battery_text = string.format("%d%%", battery)
        self:_paintText(bb, battery_text, x, y, {
            face = FontTokens.sans,
            size = 13,
            align = "right",
            width = w - self:_px(30),
            max_width = self:_px(64),
        })
        local icon_x = x + w - self:_px(26)
        local icon_y = y + self:_px(5)
        self:_paintRectBorder(bb, icon_x, icon_y, self:_px(20), self:_px(10), Blitbuffer.COLOR_DARK_GRAY)
        bb:paintRect(icon_x + self:_px(21), icon_y + self:_px(3), self:_px(2), self:_px(4), Blitbuffer.COLOR_DARK_GRAY)
    end
end

function LibraryUI:_paintHeaderAction(bb, id, icon, x, y, tap_size, callback)
    self:_paintPressedRect(bb, id, x, y, tap_size, tap_size)
    self:_paintCenteredIcon(bb, icon, x, y, tap_size, tap_size, false)
    self:_zone(id, Geom:new{x = x, y = y, w = tap_size, h = tap_size}, callback)
end

function LibraryUI:_paintHeader(bb, x, y, w)
    self:_paintText(bb, self.title, x, y, {
        face = FontTokens.display_italic,
        size = TypeScale.page_title,
        max_width = w - self:_px(164),
    })
    self:_paintLine(bb, x, y + self:_px(54), self:_px(24), Blitbuffer.COLOR_BLACK)

    local action = self:_iconTapSize()
    local gap = self:_px(10)
    local right = x + w - action
    self:_paintHeaderAction(bb, "more", "more", right, y + self:_px(4), action, function()
        self:_showMore()
    end)
    right = right - action - gap
    self:_paintHeaderAction(bb, "filter", "filter", right, y + self:_px(4), action, function()
        self:_showFilter()
    end)
    right = right - action - gap
    self:_paintHeaderAction(bb, "search", "search", right, y + self:_px(4), action, function()
        self:_showDictionaryLookup()
    end)
end

function LibraryUI:_paintCategoryControl(bb, control, x, y)
    local gap = self:_px(4)
    local width = control.width or self:_px(112)
    local label_size = self:_paintText(bb, control.label, x, y, {
        face = FontTokens.sans,
        size = TypeScale.category,
        max_width = math.floor(width * 0.46),
    })
    self:_paintText(bb, control.value, x + label_size.w + gap, y, {
        face = FontTokens.sans_bold,
        size = TypeScale.category,
        max_width = width - label_size.w - gap,
    })
end

function LibraryUI:_paintCategoryHeader(bb, opts)
    opts = opts or {}
    local x = opts.x
    local y = opts.y
    local w = opts.w
    local id = opts.id
    local callback = opts.callback

    self:_paintPressedRect(bb, id, x, y - self:_px(6), w, self:_px(34))
    local title_size = self:_paintText(bb, opts.title, x, y, {
        face = FontTokens.sans_bold,
        size = TypeScale.category,
        max_width = math.floor(w * 0.38),
    })
    if opts.count_text and opts.count_text ~= "" then
        self:_paintText(bb, opts.count_text, x + title_size.w + self:_px(12), y, {
            face = FontTokens.sans,
            size = TypeScale.category,
            color = Blitbuffer.COLOR_DARK_GRAY,
            max_width = math.floor(w * 0.24),
        })
    end

    local right = x + w
    for i = #(opts.controls or {}), 1, -1 do
        local control = opts.controls[i]
        local control_w = control.width or self:_px(112)
        self:_paintCategoryControl(bb, control, right - control_w, y)
        right = right - control_w - self:_px(24)
    end

    if opts.chevron then
        local icon_size = self:_iconSize()
        self:_paintIcon(bb, "chevron_right", x + title_size.w + self:_px(6),
            y + math.floor((title_size.h - icon_size) / 2), icon_size, false)
    end
    if id and callback then
        self:_zone(id, Geom:new{x = x, y = y - self:_px(6), w = w, h = self:_px(34)}, callback)
    end
end

function LibraryUI:_paintSectionHeader(bb, text, count_text, action_text, x, y, w, id, callback)
    self:_paintCategoryHeader(bb, {
        title = text,
        count_text = count_text,
        controls = action_text and {{ label = "", value = action_text, width = math.floor(w * 0.42) }} or nil,
        chevron = not action_text,
        x = x,
        y = y,
        w = w,
        id = id,
        callback = callback,
    })
end

function LibraryUI:_coverTitleLines(title, max_lines)
    title = tostring(title or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if title == "" then
        return { _("Untitled") }
    end

    local words = {}
    for word in title:gmatch("%S+") do
        table.insert(words, word)
    end
    if #words <= 1 then
        return { title }
    end

    local target = math.max(8, math.ceil(#title / max_lines))
    local lines = {}
    local current = ""
    for _, word in ipairs(words) do
        if current ~= "" and #lines < max_lines and #current + 1 + #word > target then
            table.insert(lines, current)
            current = word
        elseif current == "" then
            current = word
        else
            current = current .. " " .. word
        end
    end
    if current ~= "" then
        table.insert(lines, current)
    end
    while #lines > max_lines do
        lines[max_lines] = lines[max_lines] .. " " .. table.remove(lines, max_lines + 1)
    end
    return lines
end

function LibraryUI:_entryHasCoverArtwork(entry)
    if type(entry) ~= "table" then
        return false
    end
    return entry.has_cover == true
        or entry.cover ~= nil
        or entry.cover_image ~= nil
        or entry.cover_path ~= nil
        or entry.thumbnail ~= nil
        or entry.thumbnail_path ~= nil
end

function LibraryUI:_coverFillColor(entry)
    if self:_entryHasCoverArtwork(entry) then
        return Blitbuffer.COLOR_WHITE
    elseif entry and entry.current then
        return Blitbuffer.COLOR_GRAY_D or Blitbuffer.COLOR_GRAY_E
    end
    return Blitbuffer.COLOR_GRAY_E
end

function LibraryUI:_paintBookCover(bb, entry, x, y, w, h, kind)
    self:_paintRectBorder(bb, x, y, w, h, Blitbuffer.COLOR_LIGHT_GRAY)
    local inset = self:_hairline()
    local fill = self:_coverFillColor(entry)
    bb:paintRect(x + inset, y + inset, w - inset * 2, h - inset * 2, fill)

    local title = self:_entryTitle(entry) or _("Untitled")
    local lines = self:_coverTitleLines(title, 2)
    local compact = kind == "small"
    local font_size = compact and 11 or 14
    local line_step = self:_px(compact and 14 or 19)
    local title_block_h = #lines * line_step
    local title_y = y + math.floor((h - title_block_h) / 2) - self:_px(compact and 3 or 8)
    for i, line in ipairs(lines) do
        self:_paintText(bb, line, x + self:_px(8), title_y + (i - 1) * line_step, {
            face = FontTokens.sans_bold,
            size = font_size,
            align = "center",
            width = w - self:_px(16),
            max_width = w - self:_px(16),
        })
    end

    if compact then
        local motif_y = y + h - self:_px(24)
        self:_paintLine(bb, x + self:_px(16), motif_y, w - self:_px(32), Blitbuffer.COLOR_LIGHT_GRAY)
        self:_paintLine(bb, x + self:_px(24), motif_y + self:_px(7), w - self:_px(48), Blitbuffer.COLOR_LIGHT_GRAY)
    else
        local author = self:_entryAuthor(entry) or _("Document")
        self:_paintText(bb, author, x + self:_px(12), y + h - self:_px(34), {
            face = FontTokens.sans,
            size = 10,
            color = Blitbuffer.COLOR_DARK_GRAY,
            align = "center",
            width = w - self:_px(24),
            max_width = w - self:_px(24),
        })
        local rule_w = math.floor(w * 0.34)
        self:_paintLine(bb, x + math.floor((w - rule_w) / 2), y + self:_px(18), rule_w, Blitbuffer.COLOR_LIGHT_GRAY)
    end
end

function LibraryUI:_progressSummary(entry)
    if type(entry) ~= "table" then
        return ""
    end
    local percent = clampPercent(entry.percent_finished)
    local percent_text = string.format("%d%% read", math.floor(percent * 100 + 0.5))
    local page = tonumber(entry.current_page)
    local pages = tonumber(entry.pages)
    if page and pages and pages > 1 then
        return T(_("%1 - Page %2 of %3"), percent_text, page, pages)
    end
    return percent_text
end

function LibraryUI:_paintProgressLine(bb, x, y, w, percentage)
    local bar_h = math.max(1, scale(2))
    percentage = clampPercent(percentage)
    bb:paintRect(x, y, w, bar_h, Blitbuffer.COLOR_LIGHT_GRAY)
    bb:paintRect(x, y, math.floor(w * percentage), bar_h, Blitbuffer.COLOR_BLACK)
end

function LibraryUI:_paintBookCard(bb, entry, slot, id, options)
    options = options or {}
    local kind = options.kind or "small"
    local metrics = GridLayout.metrics(kind, self.shelf_scale)
    local title = self:_entryTitle(entry) or _("Untitled")
    local author = self:_entryAuthor(entry) or ""

    self:_paintPressedRect(bb, id, slot.x, slot.y, slot.w, slot.h)
    self:_paintBookCover(bb, entry, slot.cover.x, slot.cover.y, slot.cover.w, slot.cover.h, kind)
    self:_paintTextBox(bb, title, slot.title.x, slot.title.y, slot.title.w, {
        face = FontTokens.sans_bold,
        size = metrics.title_size,
        height = slot.title.h,
        line_height = 0.05,
    })
    if author == "" and options.show_state then
        author = entry and entry.status == "reading" and _("Reading") or _("New")
    end
    self:_paintTextBox(bb, author, slot.metadata.x, slot.metadata.y, slot.metadata.w, {
        face = FontTokens.sans,
        size = metrics.metadata_size,
        color = Blitbuffer.COLOR_DARK_GRAY,
        height = slot.metadata.h,
        line_height = 0.02,
    })

    self:_paintCenteredIcon(bb, "more", slot.menu.x, slot.menu.y, slot.menu.w, slot.menu.h, false)
    if entry then
        self:_zone(id, Geom:new{x = slot.x, y = slot.y, w = slot.w, h = slot.h}, function()
            self:_openEntry(entry)
        end)
        self:_zone(id .. "_menu", Geom:new{x = slot.menu.x - self:_px(8), y = slot.menu.y - self:_px(8),
            w = slot.menu.w + self:_px(16), h = slot.menu.h + self:_px(16)}, function()
            self:_showMore()
        end)
    end
end

function LibraryUI:_paintEmptyShelf(bb, x, y, w, centered)
    local title = centered and _("Your library is empty") or _("No books yet")
    local body = centered
        and _("Books, PDFs, and documents you add will appear here.")
        or _("Books you add will appear here.")
    self:_paintText(bb, title, x, y, {
        face = centered and FontTokens.display or FontTokens.sans_bold,
        size = centered and 28 or 14,
        align = centered and "center" or nil,
        width = centered and w or nil,
        max_width = w,
    })
    self:_paintTextBox(bb, body, x, y + self:_px(centered and 42 or 32), w, {
        face = FontTokens.sans,
        size = centered and 14 or 12,
        color = Blitbuffer.COLOR_DARK_GRAY,
        align = centered and "center" or "left",
        height = self:_px(centered and 52 or 36),
        line_height = 0.12,
    })
end

function LibraryUI:_paintEmptyHome(bb, x, y, w)
    self:_paintEmptyShelf(bb, x, y, w, true)
    local action_y = y + self:_px(124)
    local item_w = math.floor(w / 2)
    self:_paintText(bb, _("Add Books"), x, action_y, {
        face = FontTokens.sans_bold,
        size = 17,
        align = "center",
        width = item_w,
        max_width = item_w,
    })
    self:_paintText(bb, _("Dictionary"), x + item_w, action_y, {
        face = FontTokens.sans,
        size = 17,
        align = "center",
        width = item_w,
        max_width = item_w,
    })
    self:_zone("empty_add", Geom:new{x = x, y = action_y - self:_px(18), w = item_w, h = self:_px(56)}, function()
        self:_addBooks()
    end)
    self:_zone("empty_dictionary", Geom:new{x = x + item_w, y = action_y - self:_px(18), w = item_w, h = self:_px(56)}, function()
        self:_showDictionaryLookup()
    end)
end

function LibraryUI:_paintEmptyShelfPlaceholder(bb, x, y, w, h)
    local line = self:_hairline()
    local dash = self:_px(8)
    local gap = self:_px(6)
    local color = Blitbuffer.COLOR_LIGHT_GRAY
    for cursor = x, x + w - dash, dash + gap do
        bb:paintRect(cursor, y, math.min(dash, x + w - cursor), line, color)
        bb:paintRect(cursor, y + h - line, math.min(dash, x + w - cursor), line, color)
    end
    for cursor = y, y + h - dash, dash + gap do
        bb:paintRect(x, cursor, line, math.min(dash, y + h - cursor), color)
        bb:paintRect(x + w - line, cursor, line, math.min(dash, y + h - cursor), color)
    end
    self:_paintEmptyShelf(bb, x + self:_px(16), y + math.floor((h - self:_px(48)) / 2), w - self:_px(32), true)
end

function LibraryUI:_paintContinueEmptyState(bb, x, y, w)
    local h = self:_px(116)
    self:_paintRectBorder(bb, x, y, w, h, Blitbuffer.COLOR_LIGHT_GRAY)

    local icon_size = self:_iconSize()
    local icon_x = x + math.floor((w - icon_size) / 2)
    local icon_y = y + self:_px(22)
    self:_paintIcon(bb, "open_book", icon_x, icon_y, icon_size, false)

    self:_paintText(bb, _("Nothing in progress yet"), x + self:_px(16), icon_y + icon_size + self:_px(10), {
        face = FontTokens.serif_safe,
        size = 13,
        align = "center",
        width = w - self:_px(32),
        max_width = w - self:_px(32),
    })
    self:_paintText(bb, _("Start reading a book and it will appear here."), x + self:_px(16), icon_y + icon_size + self:_px(34), {
        face = FontTokens.sans,
        size = 9,
        color = Blitbuffer.COLOR_DARK_GRAY,
        align = "center",
        width = w - self:_px(32),
        max_width = w - self:_px(32),
    })

    return h
end

function LibraryUI:_paintGridCards(bb, kind, entries, x, y, w, rows, id_prefix, options)
    local grid = GridLayout.grid(kind, {
        x = x,
        y = y,
        w = w,
        rows = rows,
        item_count = #entries,
        scale = self.shelf_scale,
    })
    for i, slot in ipairs(grid.slots) do
        self:_paintBookCard(bb, entries[i], slot, id_prefix .. tostring(i), {
            kind = kind,
            show_state = options and options.show_state,
        })
    end
    return grid
end

function LibraryUI:_sectionHeaderHeight()
    return self:_px(30)
end

function LibraryUI:_sectionGap()
    return self:_px(12)
end

function LibraryUI:_paintContinueShelf(bb, x, y, w)
    local entry = self:_continueEntry()
    local entries = entry and { entry } or {}
    local metrics = GridLayout.metrics("large", self.shelf_scale)
    local header_x = x + metrics.outer
    local header_w = w - metrics.outer * 2
    self:_paintSectionHeader(bb, _("Continue reading"), nil, nil, header_x, y, header_w, "continue_header", function()
        self:_continue()
    end)

    local grid_y = y + self:_sectionHeaderHeight() + self:_sectionGap()
    if #entries == 0 then
        local empty_h = self:_paintContinueEmptyState(bb, x + metrics.outer, grid_y, header_w)
        return self:_sectionHeaderHeight() + self:_sectionGap() + empty_h
    end

    local grid = self:_paintGridCards(bb, "large", entries, x, grid_y, w, 1, "continue_", {
        show_state = false,
    })
    return self:_sectionHeaderHeight() + self:_sectionGap() + grid.metrics.card_h
end

function LibraryUI:_paintRecentlyAdded(bb, x, y, w)
    local entries = self:_recentlyAddedEntries()
    local metrics = GridLayout.metrics("large", self.shelf_scale)
    local header_x = x + metrics.outer
    local header_w = w - metrics.outer * 2
    self:_paintSectionHeader(bb, _("Recently added"), nil, nil, header_x, y, header_w, "recently_added", function()
        self:_addBooks()
    end)
    local grid_y = y + self:_sectionHeaderHeight() + self:_sectionGap()
    if #entries == 0 then
        self:_paintEmptyShelfPlaceholder(bb, x + metrics.outer, grid_y, metrics.card_w * 2 + metrics.gutter, metrics.card_h)
        return self:_sectionHeaderHeight() + self:_sectionGap() + metrics.card_h
    end

    local grid = self:_paintGridCards(bb, "large", entries, x, grid_y, w, 1, "recent_", {
        show_state = true,
    })
    return self:_sectionHeaderHeight() + self:_sectionGap() + grid.metrics.card_h
end

function LibraryUI:_allBookColumns(w)
    return GridLayout.columns("small", w, self.shelf_scale)
end

function LibraryUI:_paintAllBooks(bb, x, y, w, h)
    local entries = self:_libraryEntries()
    local count = #entries
    local count_text = T(N_("%1 item", "%1 items", count), count)
    local metrics = GridLayout.metrics("small", self.shelf_scale)
    local header_x = x + metrics.outer
    local header_w = w - metrics.outer * 2
    self:_paintLine(bb, self.dimen.x, y - self:_px(18), self.dimen.w, Blitbuffer.COLOR_LIGHT_GRAY)
    self:_paintCategoryHeader(bb, {
        title = _("All books"),
        count_text = count_text,
        controls = {
            {
                label = _("Sort:"),
                value = _("Recent"),
                width = self:_px(112),
            },
        },
        x = header_x,
        y = y,
        w = header_w,
        id = "all_books_header",
        callback = function()
            self:_showFilter()
        end,
    })

    local grid_y = y + self:_sectionHeaderHeight() + self:_sectionGap()
    local grid_h = h - self:_sectionHeaderHeight() - self:_sectionGap()
    local rows = GridLayout.rowsForHeight("small", grid_h, self.shelf_scale)
    local cols = self:_allBookColumns(w)
    if rows == 0 then
        self.all_books_page_size = 1
        return
    end

    local page_size = math.max(1, cols * rows)
    self.all_books_page_size = page_size

    if count == 0 then
        self:_paintEmptyShelfPlaceholder(bb, x + metrics.outer, grid_y, metrics.card_w * 2 + metrics.gutter, metrics.card_h)
        return
    end

    local first = (self.library_page - 1) * page_size + 1
    local max_page = math.max(1, math.ceil(count / page_size))
    self.library_page = math.max(1, math.min(self.library_page, max_page))
    first = (self.library_page - 1) * page_size + 1

    local page_entries = {}
    for i = 0, math.min(page_size, count - first + 1) - 1 do
        page_entries[#page_entries + 1] = entries[first + i]
    end
    local grid = GridLayout.grid("small", {
        x = x,
        y = grid_y,
        w = w,
        rows = math.max(1, rows),
        columns = cols,
        item_count = #page_entries,
        scale = self.shelf_scale,
    })
    for i, slot in ipairs(grid.slots) do
        self:_paintBookCard(bb, page_entries[i], slot, "book_" .. tostring(first + i - 1), {
            kind = "small",
        })
    end
end

function LibraryUI:_paintBottomNav(bb, x, y, w, h)
    self:_paintLine(bb, x, y, w)
    local labels = {
        { id = "nav_library", text = _("Library"), icon = "library", callback = function() end, selected = true },
        { id = "nav_dictionary", text = _("Dictionary"), icon = "dictionary", callback = function() self:_showDictionaryLookup() end },
        { id = "nav_add", text = _("Add Books"), icon = "add", callback = function() self:_addBooks() end },
        { id = "nav_files", text = _("Files"), icon = "files", callback = function() self:_showFiles() end },
    }
    local nav = GridLayout.bottomTabs{
        x = x,
        y = y,
        w = w,
        count = #labels,
        scale = self.shelf_scale,
    }
    for i, item in ipairs(labels) do
        local slot = nav.slots[i]
        self:_paintPressedRect(bb, item.id, slot.tap.x, slot.tap.y, slot.tap.w, slot.tap.h)
        self:_paintIcon(bb, item.icon, slot.icon.x, slot.icon.y, slot.icon.w, item.selected)
        self:_paintText(bb, item.text, slot.label.x, slot.label.y, {
            face = item.selected and FontTokens.sans_bold or FontTokens.sans,
            size = 11,
            color = item.selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
            align = "center",
            width = slot.label.w,
            height = slot.label.h,
            valign = "center",
            max_width = slot.label.w - self:_px(4),
        })
        self:_zone(item.id, Geom:new{x = slot.tap.x, y = slot.tap.y, w = slot.tap.w, h = slot.tap.h}, item.callback)
    end
end

function LibraryUI:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    self.dimen.w = Screen:getWidth()
    self.dimen.h = Screen:getHeight()
    self.zones = {}

    local w = self.dimen.w
    local h = self.dimen.h
    self.shelf_scale = GridLayout.scaleForViewport(w, h)
    local margin = GridLayout.metrics("small", self.shelf_scale).outer
    local inner_w = w - 2 * margin
    local nav_h = GridLayout.bottomTabs{w = w, count = 4, scale = self.shelf_scale}.h
    local cursor_y = y + self:_px(16)
    local has_books = #self:_libraryEntries() > 0
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)

    self:_paintStatusBar(bb, x + margin, cursor_y, inner_w)
    cursor_y = cursor_y + self:_px(34)

    self:_paintHeader(bb, x + margin, cursor_y, inner_w)
    cursor_y = cursor_y + self:_px(72)

    if not has_books then
        self:_paintEmptyHome(bb, x + margin, cursor_y + self:_px(64), inner_w)
        self:_paintBottomNav(bb, x, h - nav_h, w, nav_h)
        return
    end

    cursor_y = cursor_y + self:_paintContinueShelf(bb, x, cursor_y, w) + self:_px(28)

    cursor_y = cursor_y + self:_paintRecentlyAdded(bb, x, cursor_y, w) + self:_px(32)

    local all_h = h - cursor_y - nav_h - self:_px(14)
    self:_paintAllBooks(bb, x, cursor_y, w, all_h)

    self:_paintBottomNav(bb, x, h - nav_h, w, nav_h)
end

function LibraryUI:onTap(arg, ges)
    local zone = self:_zoneAt(ges and ges.pos)
    if zone and zone.callback then
        self:_setPressedZone(zone)
        return true
    end
    return true
end

function LibraryUI:onSwipe(arg, ges)
    local entries = self:_libraryEntries()
    local visible_slots = self.all_books_page_size or self:_allBookColumns(self.dimen.w)
    if #entries <= visible_slots then
        return true
    end
    local max_page = math.ceil(#entries / visible_slots)
    if ges.direction == "west" then
        self.library_page = math.min(self.library_page + 1, max_page)
    elseif ges.direction == "east" then
        self.library_page = math.max(self.library_page - 1, 1)
    end
    UIManager:setDirty(self, "ui", self.dimen)
    return true
end

return LibraryUI
