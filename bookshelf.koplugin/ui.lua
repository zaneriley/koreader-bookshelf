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
    title = _("My Library"),
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
    if options.align == "right" and options.width then
        paint_x = x + options.width - size.w
    elseif options.align == "center" and options.width then
        paint_x = x + math.floor((options.width - size.w) / 2)
    end
    widget:paintTo(bb, paint_x, y)
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
    bb:paintRect(x, y, w, math.max(1, scale(1)), color or Blitbuffer.COLOR_LIGHT_GRAY)
end

function LibraryUI:_paintRectBorder(bb, x, y, w, h, color)
    color = color or Blitbuffer.COLOR_LIGHT_GRAY
    local line = math.max(1, scale(1))
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

function LibraryUI:_paintBookGlyph(bb, x, y, w, h, selected)
    local color = selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    if selected then
        bb:paintRect(x, y, w, h, color)
        bb:paintRect(x + scale(5), y + scale(3), scale(1), h - scale(6), Blitbuffer.COLOR_WHITE)
    else
        self:_paintRectBorder(bb, x, y, w, h, color)
        bb:paintRect(x + scale(5), y + scale(3), scale(1), h - scale(6), color)
    end
end

function LibraryUI:_paintIcon(bb, icon, x, y, size, selected)
    local color = selected and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    local line = math.max(1, scale(1))
    local center_y = y + math.floor(size / 2)

    if icon == "search" then
        local lens = math.floor(size * 0.45)
        local lens_x = x + math.floor(size * 0.18)
        local lens_y = y + math.floor(size * 0.16)
        self:_paintRectBorder(bb, lens_x, lens_y, lens, lens, color)
        bb:paintRect(lens_x + lens - line, lens_y + lens, line, scale(5), color)
        bb:paintRect(lens_x + lens + line, lens_y + lens + scale(4), scale(7), line, color)
    elseif icon == "filter" then
        local left = x + math.floor(size * 0.28)
        local top = y + math.floor(size * 0.28)
        bb:paintRect(left, top, math.floor(size * 0.44), line, color)
        bb:paintRect(left + scale(4), top + scale(7), math.floor(size * 0.32), line, color)
        bb:paintRect(left + scale(8), top + scale(14), math.floor(size * 0.20), line, color)
    elseif icon == "more" then
        local dot = math.max(scale(2), math.floor(size * 0.09))
        local gap = scale(5)
        local start = x + math.floor((size - dot * 3 - gap * 2) / 2)
        for i = 0, 2 do
            bb:paintRect(start + i * (dot + gap), center_y - math.floor(dot / 2), dot, dot, color)
        end
    elseif icon == "dictionary" then
        self:_paintRectBorder(bb, x + scale(7), y + scale(6), size - scale(14), size - scale(12), color)
        bb:paintRect(x + math.floor(size / 2), y + scale(8), line, size - scale(16), color)
    elseif icon == "add" then
        self:_paintRectBorder(bb, x + scale(7), y + scale(7), size - scale(14), size - scale(14), color)
        bb:paintRect(x + math.floor(size / 2), y + scale(12), line, size - scale(24), color)
        bb:paintRect(x + scale(12), y + math.floor(size / 2), size - scale(24), line, color)
    elseif icon == "files" then
        local folder_x = x + scale(6)
        local folder_y = y + scale(10)
        bb:paintRect(folder_x, folder_y, scale(10), line, color)
        bb:paintRect(folder_x + scale(9), folder_y + scale(3), size - scale(20), line, color)
        self:_paintRectBorder(bb, folder_x, folder_y + scale(4), size - scale(12), size - scale(18), color)
    else
        self:_paintBookGlyph(bb, x + scale(8), y + scale(5), size - scale(16), size - scale(10), selected)
    end
end

function LibraryUI:_paintStatusBar(bb, x, y, w)
    local time_text = os.date("%I:%M %p"):gsub("^0", "")
    self:_paintText(bb, time_text, x, y, {
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
            size = 13,
            align = "right",
            width = w - scale(30),
            max_width = scale(64),
        })
        local icon_x = x + w - scale(26)
        local icon_y = y + scale(5)
        self:_paintRectBorder(bb, icon_x, icon_y, scale(20), scale(10), Blitbuffer.COLOR_DARK_GRAY)
        bb:paintRect(icon_x + scale(21), icon_y + scale(3), scale(2), scale(4), Blitbuffer.COLOR_DARK_GRAY)
    end
end

function LibraryUI:_paintHeaderAction(bb, id, icon, x, y, size, callback)
    self:_paintPressedRect(bb, id, x, y, size, size)
    self:_paintIcon(bb, icon, x, y, size, false)
    self:_zone(id, Geom:new{x = x, y = y, w = size, h = size}, callback)
end

function LibraryUI:_paintHeader(bb, x, y, w)
    self:_paintText(bb, self.title, x, y, {
        face = "NotoSerif-Regular.ttf",
        size = 38,
        max_width = w - scale(190),
    })
    self:_paintLine(bb, x, y + scale(56), scale(30), Blitbuffer.COLOR_BLACK)

    local action = scale(36)
    local gap = scale(16)
    local right = x + w - action
    self:_paintHeaderAction(bb, "more", "more", right, y + scale(9), action, function()
        self:_showMore()
    end)
    right = right - action - gap
    self:_paintHeaderAction(bb, "filter", "filter", right, y + scale(9), action, function()
        self:_showFilter()
    end)
    right = right - action - gap
    self:_paintHeaderAction(bb, "search", "search", right, y + scale(9), action, function()
        self:_showDictionaryLookup()
    end)
end

function LibraryUI:_paintSectionHeader(bb, text, count_text, action_text, x, y, w, id, callback)
    self:_paintPressedRect(bb, id, x, y - scale(6), w, scale(36))
    local title_size = self:_paintText(bb, text, x, y, {
        size = 17,
        bold = true,
        max_width = math.floor(w * 0.38),
    })
    if count_text and count_text ~= "" then
        self:_paintText(bb, count_text, x + title_size.w + scale(16), y + scale(1), {
            size = 16,
            color = Blitbuffer.COLOR_DARK_GRAY,
            max_width = math.floor(w * 0.24),
        })
    end
    if action_text then
        self:_paintText(bb, action_text, x, y, {
            size = 16,
            align = "right",
            width = w,
            max_width = math.floor(w * 0.42),
        })
    else
        self:_paintText(bb, ">", x + title_size.w + scale(14), y + scale(1), {
            size = 16,
            max_width = scale(20),
        })
    end
    if id and callback then
        self:_zone(id, Geom:new{x = x, y = y - scale(6), w = w, h = scale(36)}, callback)
    end
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

function LibraryUI:_paintBookCover(bb, entry, x, y, w, h, compact)
    self:_paintRectBorder(bb, x, y, w, h, Blitbuffer.COLOR_LIGHT_GRAY)
    local inset = math.max(1, scale(1))
    local fill = entry and entry.current and Blitbuffer.COLOR_GRAY_E or Blitbuffer.COLOR_WHITE
    bb:paintRect(x + inset, y + inset, w - inset * 2, h - inset * 2, fill)

    local title = self:_entryTitle(entry) or _("Untitled")
    local lines = self:_coverTitleLines(title, compact and 2 or 3)
    local font_size = compact and 11 or 16
    if #title > 28 then
        font_size = font_size - 1
    end
    local line_step = scale(compact and 15 or 22)
    local title_block_h = #lines * line_step
    local title_y = y + math.floor((h - title_block_h) / 2) - (compact and scale(4) or scale(12))
    for i, line in ipairs(lines) do
        self:_paintText(bb, line, x + scale(8), title_y + (i - 1) * line_step, {
            face = "NotoSerif-Bold.ttf",
            size = font_size,
            align = "center",
            width = w - scale(16),
            max_width = w - scale(16),
        })
    end

    local author = self:_entryAuthor(entry)
    if author and not compact then
        self:_paintTextBox(bb, author, x + scale(12), y + h - scale(40), w - scale(24), {
            size = 12,
            align = "center",
            height = scale(28),
            line_height = 0.05,
        })
    end

    if not compact then
        local rule_w = math.floor(w * 0.34)
        self:_paintLine(bb, x + math.floor((w - rule_w) / 2), y + scale(20), rule_w, Blitbuffer.COLOR_LIGHT_GRAY)
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

function LibraryUI:_paintContinueCard(bb, x, y, w, h)
    local entry = self:_continueEntry()
    self:_paintSectionHeader(bb, _("Continue reading"), nil, nil, x, y, w, "continue_header", function()
        self:_continue()
    end)

    local card_y = y + scale(36)
    local card_h = h - scale(36)
    self:_paintPressedRect(bb, "continue", x, card_y, w, card_h)
    self:_paintRectBorder(bb, x, card_y, w, card_h, Blitbuffer.COLOR_LIGHT_GRAY)

    local cover_w = math.floor(card_h * 0.62)
    self:_paintBookCover(bb, entry, x, card_y, cover_w, card_h, true)

    local text_x = x + cover_w + scale(28)
    local text_w = w - cover_w - scale(68)
    self:_paintTextBox(bb, self:_entryTitle(entry) or _("No recent book"), text_x, card_y + scale(30), text_w, {
        face = "NotoSerif-Bold.ttf",
        size = 22,
        height = scale(44),
        line_height = 0.08,
    })
    local author = self:_entryAuthor(entry)
    if author then
        self:_paintText(bb, author, text_x, card_y + scale(66), {
            size = 15,
            max_width = text_w,
        })
    end

    local progress_y = card_y + card_h - scale(26)
    self:_paintText(bb, entry and self:_progressSummary(entry) or "", text_x, progress_y - scale(28), {
        size = 15,
        color = Blitbuffer.COLOR_DARK_GRAY,
        max_width = text_w,
    })
    self:_paintProgressLine(bb, text_x, progress_y, text_w - scale(38), entry and entry.percent_finished or 0)
    self:_paintIcon(bb, "more", x + w - scale(48), card_y + scale(14), scale(32), false)
    if entry then
        self:_zone("continue", Geom:new{x = x, y = card_y, w = w, h = card_h}, function()
            self:_continue()
        end)
    end
end

function LibraryUI:_paintBookTile(bb, entry, x, y, w, h, id, options)
    options = options or {}
    local compact_tile = h < scale(180)
    local title_h = compact_tile and scale(28) or scale(38)
    local author_h = compact_tile and 0 or scale(28)
    local state_h = options.show_state and scale(22) or 0
    local detail_h = title_h + author_h + state_h + scale(14)
    local cover_min_h = compact_tile and scale(50) or scale(70)
    local cover_h = options.cover_h or math.min(math.floor(w * 1.43), math.max(cover_min_h, h - detail_h))
    local title_y = y + cover_h + scale(8)
    local title = self:_entryTitle(entry) or _("Untitled")
    local author = self:_entryAuthor(entry) or ""

    self:_paintPressedRect(bb, id, x, y, w, h)
    self:_paintBookCover(bb, entry, x, y, w, cover_h, w < scale(130))
    self:_paintTextBox(bb, title, x, title_y, w, {
        size = compact_tile and 13 or 15,
        bold = true,
        height = title_h,
        line_height = 0.05,
    })
    if author ~= "" and not compact_tile then
        self:_paintTextBox(bb, author, x, title_y + title_h, w, {
            size = 12,
            height = author_h,
            line_height = 0.05,
        })
    end
    if options.show_state then
        self:_paintText(bb, entry and entry.status == "reading" and _("Reading") or _("New"), x, y + h - scale(22), {
            size = 12,
            color = Blitbuffer.COLOR_DARK_GRAY,
            max_width = math.floor(w * 0.65),
        })
        self:_paintIcon(bb, "more", x + w - scale(30), y + h - scale(28), scale(26), false)
    end
    if entry then
        self:_zone(id, Geom:new{x = x, y = y, w = w, h = h}, function()
            self:_openEntry(entry)
        end)
    end
end

function LibraryUI:_paintEmptyShelf(bb, x, y, w, centered)
    local title = _("No books downloaded")
    local body = _("Add books from your library server, then they will appear here for offline reading.")
    self:_paintText(bb, title, x, y, {
        face = "NotoSerif-Regular.ttf",
        size = 24,
        align = centered and "center" or nil,
        width = centered and w or nil,
        max_width = w,
    })
    self:_paintTextBox(bb, body, x, y + scale(42), w, {
        size = 16,
        color = Blitbuffer.COLOR_DARK_GRAY,
        align = centered and "center" or "left",
        height = scale(52),
        line_height = 0.12,
    })
end

function LibraryUI:_paintEmptyHome(bb, x, y, w)
    self:_paintEmptyShelf(bb, x, y, w, true)
    local action_y = y + scale(124)
    local item_w = math.floor(w / 2)
    self:_paintText(bb, _("Add Books"), x, action_y, {
        size = 17,
        bold = true,
        align = "center",
        width = item_w,
        max_width = item_w,
    })
    self:_paintText(bb, _("Dictionary"), x + item_w, action_y, {
        size = 17,
        align = "center",
        width = item_w,
        max_width = item_w,
    })
    self:_zone("empty_add", Geom:new{x = x, y = action_y - scale(18), w = item_w, h = scale(56)}, function()
        self:_addBooks()
    end)
    self:_zone("empty_dictionary", Geom:new{x = x + item_w, y = action_y - scale(18), w = item_w, h = scale(56)}, function()
        self:_showDictionaryLookup()
    end)
end

function LibraryUI:_paintRecentlyAdded(bb, x, y, w, h)
    local entries = self:_recentlyAddedEntries()
    self:_paintSectionHeader(bb, _("Recently added"), nil, nil, x, y, w, "recently_added", function()
        self:_addBooks()
    end)
    if #entries == 0 then
        self:_paintEmptyShelf(bb, x, y + scale(48), w)
        return
    end

    local cols = math.min(5, math.max(2, math.floor(w / scale(122))))
    local gap = scale(16)
    local tile_w = math.floor((w - gap * (cols - 1)) / cols)
    local tile_h = h - scale(44)
    local tile_y = y + scale(44)
    for i = 1, math.min(cols, #entries) do
        self:_paintBookTile(bb, entries[i], x + (i - 1) * (tile_w + gap), tile_y, tile_w, tile_h,
            "recent_" .. tostring(i), { show_state = true })
    end
end

function LibraryUI:_allBookColumns(w)
    return math.min(5, math.max(2, math.floor(w / scale(128))))
end

function LibraryUI:_paintAllBooks(bb, x, y, w, h)
    local entries = self:_libraryEntries()
    local count = #entries
    local count_text = T(N_("%1 item", "%1 items", count), count)
    self:_paintLine(bb, self.dimen.x, y - scale(20), self.dimen.w, Blitbuffer.COLOR_LIGHT_GRAY)
    self:_paintPressedRect(bb, "all_books_header", x, y - scale(6), w, scale(36))
    local title_size = self:_paintText(bb, _("All books"), x, y, {
        size = 17,
        bold = true,
        max_width = math.floor(w * 0.32),
    })
    self:_paintText(bb, count_text, x + title_size.w + scale(16), y + scale(1), {
        size = 16,
        color = Blitbuffer.COLOR_DARK_GRAY,
        max_width = math.floor(w * 0.2),
    })
    self:_paintText(bb, _("View: Grid"), x + w - scale(98), y + scale(1), {
        size = 15,
        max_width = scale(98),
    })
    self:_paintText(bb, _("Sort: Recent"), x + w - scale(228), y + scale(1), {
        size = 15,
        max_width = scale(118),
    })
    self:_zone("all_books_header", Geom:new{x = x, y = y - scale(6), w = w, h = scale(36)}, function()
        self:_showFilter()
    end)

    if count == 0 then
        self:_paintEmptyShelf(bb, x, y + scale(58), w)
        return
    end

    local cols = self:_allBookColumns(w)
    local gap = scale(16)
    local tile_w = math.floor((w - gap * (cols - 1)) / cols)
    local tile_h = h - scale(56)
    local first = (self.library_page - 1) * cols + 1
    local max_page = math.max(1, math.ceil(count / cols))
    self.library_page = math.max(1, math.min(self.library_page, max_page))
    for i = 0, math.min(cols, count - first + 1) - 1 do
        self:_paintBookTile(bb, entries[first + i], x + i * (tile_w + gap), y + scale(58), tile_w, tile_h,
            "book_" .. tostring(first + i))
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
    local item_w = math.floor(w / #labels)
    for i, item in ipairs(labels) do
        local item_x = x + (i - 1) * item_w
        self:_paintPressedRect(bb, item.id, item_x, y + scale(10), item_w, h - scale(10))
        if item.selected then
            bb:paintRect(item_x + math.floor((item_w - scale(28)) / 2), y + scale(6), scale(28), math.max(1, scale(2)), Blitbuffer.COLOR_BLACK)
        end
        self:_paintIcon(bb, item.icon, item_x + math.floor((item_w - scale(26)) / 2), y + scale(14), scale(26), item.selected)
        self:_paintText(bb, item.text, item_x, y + scale(38), {
            size = 13,
            bold = item.selected,
            align = "center",
            width = item_w,
            max_width = item_w - scale(10),
        })
        self:_zone(item.id, Geom:new{x = item_x, y = y, w = item_w, h = h}, item.callback)
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
    local margin = scale(32)
    local inner_w = w - 2 * margin
    local nav_h = scale(56)
    local cursor_y = y + scale(24)
    local has_books = #self:_libraryEntries() > 0
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)

    self:_paintStatusBar(bb, x + margin, cursor_y, inner_w)
    cursor_y = cursor_y + scale(44)

    self:_paintHeader(bb, x + margin, cursor_y, inner_w)
    cursor_y = cursor_y + scale(76)

    if not has_books then
        self:_paintEmptyHome(bb, x + margin, cursor_y + scale(64), inner_w)
        self:_paintBottomNav(bb, x, h - nav_h, w, nav_h)
        return
    end

    self:_paintContinueCard(bb, x + margin, cursor_y, inner_w, scale(172))
    cursor_y = cursor_y + scale(204)

    self:_paintRecentlyAdded(bb, x + margin, cursor_y, inner_w, scale(204))
    cursor_y = cursor_y + scale(228)

    local all_h = h - cursor_y - nav_h - scale(14)
    self:_paintAllBooks(bb, x + margin, cursor_y, inner_w, all_h)

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
    local visible_slots = self:_allBookColumns(self.dimen.w - 2 * scale(44))
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
