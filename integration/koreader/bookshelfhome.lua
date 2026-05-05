local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local BOOKSHELF_PLUGIN_PATH = "plugins/bookshelf.koplugin"
local OPDS_PLUGIN_PATH = "plugins/opds.koplugin"

local PlaceholderProvider = {}

function PlaceholderProvider:getDownloaded()
    return {}
end

function PlaceholderProvider:getContinue()
    return nil
end

local BookshelfHome = {
    provider = nil,
    shell = nil,
    bookshelf_ui = nil,
}

local function loadModule(path)
    local loader, load_err = loadfile(path)
    if not loader then
        logger.warn("BookshelfHome: could not load", path, load_err)
        return nil
    end

    local ok, module = pcall(loader)
    if not ok then
        logger.warn("BookshelfHome: failed loading", path, module)
        return nil
    end
    return module
end

function BookshelfHome:getProvider()
    if self.provider then
        return self.provider
    end

    local provider = loadModule(BOOKSHELF_PLUGIN_PATH .. "/provider.lua")
    if type(provider) == "function" then
        local ok, provider_instance = pcall(provider, {
            ui = self:getShell(),
            plugin = self,
        })
        provider = ok and provider_instance or nil
        if not ok then
            logger.warn("BookshelfHome: provider factory failed:", provider_instance)
        end
    elseif type(provider) == "table" and type(provider.new) == "function" then
        local ok, provider_instance = pcall(provider.new, provider, {
            ui = self:getShell(),
            plugin = self,
        })
        provider = ok and provider_instance or nil
        if not ok then
            logger.warn("BookshelfHome: provider init failed:", provider_instance)
        end
    end

    self.provider = type(provider) == "table" and provider or PlaceholderProvider
    return self.provider
end

function BookshelfHome:getShell()
    if self.shell then
        return self.shell
    end

    local shell = {
        menu = {
            registerToMainMenu = function() end,
        },
    }

    function shell:openFile(file)
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(file)
    end

    function shell:showFileManager(path)
        require("apps/filemanager/filemanager"):showFiles(path)
    end

    function shell:getDictionary()
        if not self.dictionary then
            local ReaderDictionary = require("apps/reader/modules/readerdictionary")
            self.dictionary = ReaderDictionary:new{
                ui = self,
            }
        end
        return self.dictionary
    end

    function shell:getOPDS()
        if self.opds then
            return self.opds
        end

        local opds_path = OPDS_PLUGIN_PATH .. "/main.lua"
        if lfs.attributes(opds_path, "mode") ~= "file" then
            return nil
        end

        local OPDS = loadModule(opds_path)
        if type(OPDS) == "table" and type(OPDS.new) == "function" then
            local ok, opds = pcall(OPDS.new, OPDS, {
                ui = self,
            })
            if not ok then
                logger.warn("BookshelfHome: OPDS init failed:", opds)
                return nil
            end
            self.opds = opds
        end
        return self.opds
    end

    self.shell = shell
    return self.shell
end

function BookshelfHome:show()
    local LibraryUI = loadModule(BOOKSHELF_PLUGIN_PATH .. "/ui.lua")
    if not LibraryUI then
        require("apps/filemanager/filemanager"):showFiles()
        return false
    end

    self.bookshelf_ui = LibraryUI:new{
        ui = self:getShell(),
        provider = self:getProvider(),
        closed_callback = function()
            self.bookshelf_ui = nil
        end,
    }
    UIManager:show(self.bookshelf_ui)
    return true
end

return BookshelfHome
