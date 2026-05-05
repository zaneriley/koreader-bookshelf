describe("Bookshelf home launcher", function()
    local UIManager
    local BookshelfHome
    local loadfile_stubbed
    local uimanager_show_stubbed

    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
    end)

    local function reloadHome()
        BookshelfHome = package.reload("apps/bookshelf/bookshelfhome")
        BookshelfHome.provider = nil
        BookshelfHome.shell = nil
        BookshelfHome.bookshelf_ui = nil
        return BookshelfHome
    end

    before_each(function()
        loadfile_stubbed = false
        uimanager_show_stubbed = false
        reloadHome()
    end)

    after_each(function()
        if loadfile_stubbed then
            _G.loadfile:revert()
        end
        if uimanager_show_stubbed then
            UIManager.show:revert()
        end
        package.unload("apps/bookshelf/bookshelfhome")
        package.unload("apps/reader/modules/readerdictionary")
    end)

    it("shows the bookshelf UI instead of file manager chrome", function()
        local shown_widget
        local captured_opts
        local provider = {
            getDownloaded = function()
                return {}
            end,
        }

        stub(_G, "loadfile", function(path)
            if path == "plugins/bookshelf.koplugin/ui.lua" then
                return function()
                    return {
                        new = function(_, opts)
                            captured_opts = opts
                            return { id = "bookshelf-widget" }
                        end,
                    }
                end
            elseif path == "plugins/bookshelf.koplugin/provider.lua" then
                return function()
                    return provider
                end
            end
            error("unexpected module load: " .. path)
        end)
        loadfile_stubbed = true
        stub(UIManager, "show", function(_, widget)
            shown_widget = widget
        end)
        uimanager_show_stubbed = true

        assert.is_true(BookshelfHome:show())
        assert.equals("bookshelf-widget", shown_widget.id)
        assert.are.same(provider, captured_opts.provider)
        assert.is_table(captured_opts.ui)
        assert.is_function(captured_opts.ui.openFile)
        assert.is_function(captured_opts.ui.showFileManager)
    end)

    it("keeps dictionary and OPDS modules lazy until tapped", function()
        local dictionary_new_count = 0
        local opds_new_count = 0
        package.replace("apps/reader/modules/readerdictionary", {
            new = function(_, opts)
                dictionary_new_count = dictionary_new_count + 1
                return { opts = opts }
            end,
        })

        stub(_G, "loadfile", function(path)
            if path == "plugins/opds.koplugin/main.lua" then
                return function()
                    return {
                        new = function(_, opts)
                            opds_new_count = opds_new_count + 1
                            return { opts = opts }
                        end,
                    }
                end
            end
            error("unexpected module load: " .. path)
        end)
        loadfile_stubbed = true

        local shell = BookshelfHome:getShell()
        assert.equals(0, dictionary_new_count)
        assert.equals(0, opds_new_count)

        assert.is_table(shell:getDictionary())
        assert.equals(1, dictionary_new_count)
        assert.are.same(shell.dictionary, shell:getDictionary())
        assert.equals(1, dictionary_new_count)

        assert.is_table(shell:getOPDS())
        assert.equals(1, opds_new_count)
        assert.are.same(shell.opds, shell:getOPDS())
        assert.equals(1, opds_new_count)
    end)
end)
