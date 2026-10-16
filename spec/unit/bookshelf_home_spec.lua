describe("Bookshelf plugin FileManager choreography", function()
    local Bookshelf
    local FileChooser
    local UIManager

    setup(function()
        require("commonrequire")
        require("apps/filemanager/filemanager")
        Bookshelf = dofile("plugins/bookshelf.koplugin/main.lua")
        FileChooser = require("ui/widget/filechooser")
        UIManager = require("ui/uimanager")
    end)

    it("closes a temporary file manager overlay to reveal the existing Library", function()
        local closed_filemanager = false
        local plugin = setmetatable({
            ui = {
                return_to_previous_view = true,
                onClose = function()
                    closed_filemanager = true
                end,
            },
        }, { __index = Bookshelf })

        assert.is_true(plugin:onShowLibrary())
        assert.is_true(closed_filemanager)
    end)

    it("does not stack a second Library for the same plugin instance", function()
        local plugin = setmetatable({
            bookshelf_ui = {
                _closed = false,
            },
        }, { __index = Bookshelf })

        assert.is_true(plugin:onShowLibrary())
    end)

    it("uses Back to close a temporary file manager instead of prompting to exit", function()
        local closed_filemanager = false
        local fake_filechooser = setmetatable({
            ui = {
                return_to_previous_view = true,
                onClose = function()
                    closed_filemanager = true
                    return true
                end,
            },
        }, { __index = FileChooser })

        assert.is_true(fake_filechooser:onBack())
        assert.is_true(closed_filemanager)
    end)

    it("claims generic Home only when Library is the home view", function()
        local shown_library = false
        local original_reader_settings = _G.G_reader_settings
        finally(function()
            _G.G_reader_settings = original_reader_settings
        end)
        local plugin = setmetatable({
            onShowLibrary = function()
                shown_library = true
                return true
            end,
        }, { __index = Bookshelf })

        local function useSettings(settings)
            shown_library = false
            _G.G_reader_settings = {
                readSetting = function(_, name)
                    return settings[name]
                end,
            }
        end

        useSettings({
            home_view = "library",
        })
        assert.is_true(plugin:onShowHome())
        assert.is_true(shown_library)

        useSettings({
            start_with = "library",
        })
        assert.is_true(plugin:onShowHome())
        assert.is_true(shown_library)

        useSettings({
            home_view = "filemanager",
            start_with = "library",
        })
        assert.is_false(plugin:onShowHome())
        assert.is_false(shown_library)

        useSettings({})
        assert.is_false(plugin:onShowHome())
        assert.is_false(shown_library)

        useSettings({
            start_with = "filemanager",
        })
        assert.is_false(plugin:onShowHome())
        assert.is_false(shown_library)

        _G.G_reader_settings = original_reader_settings
    end)

    it("schedules Library after FileManager post-init when Library is the home view", function()
        local original_reader_settings = _G.G_reader_settings
        local post_init_callback
        local next_tick_callback
        local shown_library = false
        local registered_menu = false

        stub(UIManager, "nextTick", function(_, callback)
            next_tick_callback = callback
        end)

        _G.G_reader_settings = {
            readSetting = function(_, name)
                if name == "home_view" then
                    return "library"
                end
            end,
        }

        local plugin = setmetatable({
            ui = {
                menu = {
                    registerToMainMenu = function()
                        registered_menu = true
                    end,
                },
                registerPostInitCallback = function(_, callback)
                    post_init_callback = callback
                end,
            },
            onShowLibrary = function()
                shown_library = true
                return true
            end,
        }, { __index = Bookshelf })

        plugin:init()
        assert.is_true(registered_menu)
        assert.is_function(post_init_callback)
        assert.is_false(shown_library)

        post_init_callback()
        assert.is_function(next_tick_callback)
        assert.is_false(shown_library)

        next_tick_callback()
        assert.is_true(shown_library)

        UIManager.nextTick:revert()
        _G.G_reader_settings = original_reader_settings
    end)

    it("does not auto-show Library when the plugin is loaded inside a reader", function()
        local original_reader_settings = _G.G_reader_settings
        local post_init_callback
        local registered_menu = false

        _G.G_reader_settings = {
            readSetting = function(_, name)
                if name == "home_view" then
                    return "library"
                end
            end,
        }

        local plugin = setmetatable({
            ui = {
                document = {
                    file = "/books/current.epub",
                },
                menu = {
                    registerToMainMenu = function()
                        registered_menu = true
                    end,
                },
                registerPostInitCallback = function(_, callback)
                    post_init_callback = callback
                end,
            },
        }, { __index = Bookshelf })

        plugin:init()

        assert.is_true(registered_menu)
        assert.is_nil(post_init_callback)

        _G.G_reader_settings = original_reader_settings
    end)

    it("auto-applies the reading preset only on a book's first open", function()
        local LuaSettings = require("luasettings")
        local original_reader_settings = _G.G_reader_settings
        local old_next_tick = UIManager.nextTick
        finally(function()
            _G.G_reader_settings = original_reader_settings
            UIManager.nextTick = old_next_tick
        end)
        _G.G_reader_settings = {
            readSetting = function(_, name)
                if name == "bookshelf_auto_apply_reading_preset" then
                    return "comfortable"
                end
            end,
        }
        UIManager.nextTick = function(_, callback)
            callback()
        end

        local doc_settings = LuaSettings:open("/tmp/bookshelf-preset-first-open-spec.lua")
        local applied = 0
        local apply_ok = false
        local plugin = setmetatable({
            ui = { document = {}, doc_settings = doc_settings },
            _applyReadingPreset = function(_, preset_id)
                assert.equals("comfortable", preset_id)
                applied = applied + 1
                return apply_ok
            end,
        }, { __index = Bookshelf })

        -- a failed apply (e.g. language outside the preset) retries next open
        plugin:onReaderReady()
        assert.equals(1, applied)
        assert.is_false(doc_settings:isTrue("bookshelf_reading_preset_applied"))

        apply_ok = true
        plugin:onReaderReady()
        assert.equals(2, applied)
        assert.is_true(doc_settings:isTrue("bookshelf_reading_preset_applied"))

        -- reopening keeps the reader's own font changes
        plugin:onReaderReady()
        assert.equals(2, applied)
    end)
end)

describe("Bookshelf reader home integration", function()
    local DocSettings
    local FileManager
    local ReaderUI
    local UIManager
    local original_save_settings_arc_file
    local original_filemanager_instance
    local original_reader_settings
    local uimanager_send_event_stubbed

    setup(function()
        require("commonrequire")
        DocSettings = require("docsettings")
        FileManager = require("apps/filemanager/filemanager")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        original_save_settings_arc_file = DocSettings.saveSettingsArcFile
        original_filemanager_instance = FileManager.instance
        original_reader_settings = _G.G_reader_settings
        uimanager_send_event_stubbed = false
    end)

    after_each(function()
        if uimanager_send_event_stubbed then
            UIManager.sendEvent:revert()
        end
        DocSettings.saveSettingsArcFile = original_save_settings_arc_file
        FileManager.instance = original_filemanager_instance
        _G.G_reader_settings = original_reader_settings
    end)

    it("saves settings when running against v2026.03 without metadata archive support", function()
        local doc_settings_flushed = false
        local reader_settings_flushed = false
        local handled_save_settings = false

        DocSettings.saveSettingsArcFile = nil
        _G.G_reader_settings = {
            flush = function()
                reader_settings_flushed = true
            end,
        }

        local fake_reader = setmetatable({
            doc_settings = {
                flush = function()
                    doc_settings_flushed = true
                end,
            },
            handleEvent = function(_, event)
                handled_save_settings = event.handler == "onSaveSettings"
            end,
        }, { __index = ReaderUI })

        assert.has_no.errors(function()
            fake_reader:saveSettings()
        end)
        assert.is_true(handled_save_settings)
        assert.is_true(doc_settings_flushed)
        assert.is_true(reader_settings_flushed)
    end)

    it("keeps the explicit File browser action separate from Library", function()
        local closed_reader = false
        local shown_file
        local fake_reader = setmetatable({
            document = {
                file = "/books/current.epub",
            },
            onClose = function()
                closed_reader = true
            end,
            showFileManager = function(_, file)
                shown_file = file
            end,
        }, { __index = ReaderUI })

        assert.is_true(fake_reader:onShowFileManager())
        assert.is_true(closed_reader)
        assert.equals("/books/current.epub", shown_file)
    end)

    it("sends generic Home after closing the reader", function()
        local shown_file
        local sent_event
        stub(UIManager, "sendEvent", function(_, event)
            sent_event = event
        end)
        uimanager_send_event_stubbed = true

        local fake_reader = setmetatable({
            document = {
                file = "/books/current.epub",
            },
            onClose = function() end,
            showFileManager = function(_, file)
                shown_file = file
            end,
        }, { __index = ReaderUI })

        assert.is_true(fake_reader:onHome())
        assert.equals("/books/current.epub", shown_file)
        assert.equals("onShowHome", sent_event.handler)
    end)
end)
