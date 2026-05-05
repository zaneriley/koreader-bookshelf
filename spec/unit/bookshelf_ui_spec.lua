describe("Bookshelf UI module", function()
    local Blitbuffer

    setup(function()
        require("commonrequire")
        Blitbuffer = require("ffi/blitbuffer")
    end)

    it("loads the componentized UI module", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")

        assert.is_table(LibraryUI)
        assert.is_function(LibraryUI.new)
    end)

    it("does not draw a border around book card text", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")
        local border_calls = 0
        local cover_calls = 0
        local icon_sizes = {}
        local fake = setmetatable({
            shelf_scale = 1,
            _paintPressedRect = function() end,
            _paintRectBorder = function()
                border_calls = border_calls + 1
            end,
            _paintBookCover = function()
                cover_calls = cover_calls + 1
            end,
            _paintTextBox = function() end,
            _paintIcon = function(_, _, _, _, _, size)
                table.insert(icon_sizes, size)
            end,
            _entryTitle = function()
                return "Quickstart Guide"
            end,
            _entryAuthor = function()
                return "Document"
            end,
        }, { __index = LibraryUI })

        LibraryUI._paintBookCard(fake, {}, nil, {
            x = 10,
            y = 20,
            w = 104,
            h = 208,
            cover = { x = 10, y = 20, w = 104, h = 156 },
            title = { x = 14, y = 182, w = 96, h = 28 },
            metadata = { x = 14, y = 210, w = 78, h = 13 },
            menu = { x = 96, y = 210, w = 18, h = 18 },
        }, "book_1", { kind = "small" })

        assert.equals(1, cover_calls)
        assert.equals(0, border_calls)
        assert.equals(24, icon_sizes[1])
    end)

    it("uses a shaded fill for generated placeholder covers", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")
        local fake = setmetatable({}, { __index = LibraryUI })

        assert.equals(tostring(Blitbuffer.COLOR_GRAY_E), tostring(LibraryUI._coverFillColor(fake, {})))
        assert.equals(tostring(Blitbuffer.COLOR_WHITE), tostring(LibraryUI._coverFillColor(fake, {
            cover_path = "/tmp/cover.png",
        })))
    end)

    it("paints the placeholder cover label without a text box", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")
        local text_calls = {}
        local text_box_calls = 0
        local fake = setmetatable({
            shelf_scale = 1,
            _paintRectBorder = function() end,
            _hairline = function()
                return 1
            end,
            _coverFillColor = function()
                return Blitbuffer.COLOR_GRAY_E
            end,
            _entryTitle = function()
                return "Quickstart Guide"
            end,
            _entryAuthor = function()
                return nil
            end,
            _paintLine = function() end,
            _paintText = function(_, _, text)
                table.insert(text_calls, text)
            end,
            _paintTextBox = function()
                text_box_calls = text_box_calls + 1
            end,
        }, { __index = LibraryUI })
        local bb = {
            paintRect = function() end,
        }

        LibraryUI._paintBookCover(fake, bb, {}, 0, 0, 148, 222, "large")

        assert.equals(0, text_box_calls)
        assert.equals("Document", text_calls[#text_calls])
    end)

    it("uses a dedicated compact empty state for continue reading", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")
        local border_calls = 0
        local icon_calls = {}
        local text_calls = {}
        local text_options = {}
        local fake = setmetatable({
            shelf_scale = 1,
            _paintRectBorder = function()
                border_calls = border_calls + 1
            end,
            _paintIcon = function(_, _, icon, x, y, size)
                table.insert(icon_calls, { icon = icon, x = x, y = y, size = size })
            end,
            _paintText = function(_, _, text, _, _, options)
                table.insert(text_calls, text)
                table.insert(text_options, options or {})
            end,
            _px = function(_, value)
                return value
            end,
        }, { __index = LibraryUI })

        local h = LibraryUI._paintContinueEmptyState(fake, {}, 16, 64, 568)

        assert.equals(116, h)
        assert.equals(1, border_calls)
        assert.equals("open_book", icon_calls[1].icon)
        assert.equals(24, icon_calls[1].size)
        assert.equals("Nothing in progress yet", text_calls[1])
        assert.equals("Start reading a book and it will appear here.", text_calls[2])
        assert.equals(13, text_options[1].size)
        assert.equals(9, text_options[2].size)
    end)

    it("uses the short library title", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")

        assert.equals("Library", LibraryUI.title)
    end)

    it("uses one category header style for titles, counts, and controls", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")
        local text_calls = {}
        local text_options = {}
        local fake = setmetatable({
            shelf_scale = 1,
            _paintPressedRect = function() end,
            _paintText = function(_, _, text, _, _, options)
                table.insert(text_calls, text)
                table.insert(text_options, options or {})
                return { w = #text * 7, h = 16 }
            end,
            _zone = function() end,
            _px = function(_, value)
                return value
            end,
        }, { __index = LibraryUI })

        LibraryUI._paintCategoryHeader(fake, {}, {
            title = "All books",
            count_text = "9 items",
            controls = {{ label = "Sort:", value = "Recent", width = 112 }},
            x = 16,
            y = 48,
            w = 420,
            id = "all",
            callback = function() end,
        })

        assert.same({ "All books", "9 items", "Sort:", "Recent" }, text_calls)
        for _, options in ipairs(text_options) do
            assert.equals(13, options.size)
        end
        assert.equals("NotoSans-Bold.ttf", text_options[1].face)
        assert.equals("NotoSans-Regular.ttf", text_options[2].face)
        assert.equals("NotoSans-Regular.ttf", text_options[3].face)
        assert.equals("NotoSans-Bold.ttf", text_options[4].face)
    end)

    it("uses the shared icon system for section chevrons", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")
        local text_calls = {}
        local text_options = {}
        local icon_calls = {}
        local fake = setmetatable({
            shelf_scale = 1,
            _paintPressedRect = function() end,
            _paintText = function(_, _, text, _, _, options)
                table.insert(text_calls, text)
                table.insert(text_options, options or {})
                return { w = 124, h = 22 }
            end,
            _paintIcon = function(_, _, icon, icon_x, icon_y, size)
                table.insert(icon_calls, { icon = icon, x = icon_x, y = icon_y, size = size })
            end,
            _zone = function() end,
            _px = function(_, value)
                return value
            end,
        }, { __index = LibraryUI })

        LibraryUI._paintSectionHeader(fake, {}, "Recently added", nil, nil, 16, 48, 420, "recent", function() end)

        assert.equals(13, text_options[1].size)
        assert.equals("chevron_right", icon_calls[1].icon)
        assert.equals(146, icon_calls[1].x)
        assert.equals(47, icon_calls[1].y)
        assert.equals(24, icon_calls[1].size)
        for _, text in ipairs(text_calls) do
            assert.not_equals(">", text)
        end
    end)

    it("renders recently added through the shared category header component", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")
        local header_calls = {}
        local fake = setmetatable({
            shelf_scale = 1,
            _recentlyAddedEntries = function()
                return {}
            end,
            _paintCategoryHeader = function(_, _, opts)
                table.insert(header_calls, opts)
            end,
            _paintEmptyShelfPlaceholder = function() end,
            _addBooks = function() end,
            _px = function(_, value)
                return value
            end,
        }, { __index = LibraryUI })

        LibraryUI._paintRecentlyAdded(fake, {}, 0, 100, 600)

        assert.equals(1, #header_calls)
        assert.equals("Recently added", header_calls[1].title)
        assert.is_true(header_calls[1].chevron)
        assert.equals(16, header_calls[1].x)
        assert.equals(568, header_calls[1].w)
    end)

    it("centers 24px header icons inside larger tap targets", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")
        local pressed = {}
        local icons = {}
        local zones = {}
        local fake = setmetatable({
            shelf_scale = 1,
            _paintPressedRect = function(_, _, id, x, y, w, h)
                table.insert(pressed, { id = id, x = x, y = y, w = w, h = h })
            end,
            _paintIcon = function(_, _, icon, x, y, size)
                table.insert(icons, { icon = icon, x = x, y = y, size = size })
            end,
            _zone = function(_, id, rect)
                table.insert(zones, { id = id, rect = rect })
            end,
            _px = function(_, value)
                return value
            end,
        }, { __index = LibraryUI })

        LibraryUI._paintHeaderAction(fake, {}, "search", "search", 100, 50, 40, function() end)

        assert.equals(40, pressed[1].w)
        assert.equals(40, pressed[1].h)
        assert.equals("search", icons[1].icon)
        assert.equals(108, icons[1].x)
        assert.equals(58, icons[1].y)
        assert.equals(24, icons[1].size)
        assert.equals(40, zones[1].rect.w)
        assert.equals(40, zones[1].rect.h)
    end)

    it("uses the category header for all books and omits the view control", function()
        local LibraryUI = dofile("plugins/bookshelf.koplugin/ui.lua")
        local header_calls = {}
        local fake = setmetatable({
            shelf_scale = 1,
            dimen = { x = 0, w = 600 },
            library_page = 1,
            _libraryEntries = function()
                return {}
            end,
            _paintLine = function() end,
            _paintCategoryHeader = function(_, _, opts)
                table.insert(header_calls, opts)
            end,
            _paintEmptyShelfPlaceholder = function() end,
            _showFilter = function() end,
            _px = function(_, value)
                return value
            end,
        }, { __index = LibraryUI })

        LibraryUI._paintAllBooks(fake, {}, 0, 100, 600, 260)

        assert.equals("All books", header_calls[1].title)
        assert.equals("0 items", header_calls[1].count_text)
        assert.equals(1, #header_calls[1].controls)
        assert.equals("Sort:", header_calls[1].controls[1].label)
        assert.equals("Recent", header_calls[1].controls[1].value)
    end)
end)
