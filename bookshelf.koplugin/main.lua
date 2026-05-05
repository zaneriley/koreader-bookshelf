local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local PlaceholderProvider = {
    is_placeholder = true,
}

function PlaceholderProvider:getDownloaded()
    return {}
end

function PlaceholderProvider:getContinue()
    return nil
end

local Bookshelf = WidgetContainer:extend{
    name = "bookshelf",
    is_doc_only = false,
    provider = nil,
}

function Bookshelf:onDispatcherRegisterActions()
    Dispatcher:registerAction("bookshelf_show", {
        category = "none",
        event = "ShowBookshelf",
        title = _("Library"),
        general = true,
    })
end

function Bookshelf:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Bookshelf:addToMainMenu(menu_items)
    menu_items.bookshelf = {
        text = _("Library"),
        sorting_hint = "main",
        callback = function()
            self:onShowBookshelf()
        end,
    }
end

function Bookshelf:getProvider()
    if self.provider then
        return self.provider
    end

    local provider_path = self.path and (self.path .. "/provider.lua")
    if provider_path and lfs.attributes(provider_path, "mode") == "file" then
        local loader, load_err = loadfile(provider_path)
        if loader then
            local ok, provider = pcall(loader)
            if ok then
                if type(provider) == "function" then
                    local provider_ok, provider_instance = pcall(provider, {
                        ui = self.ui,
                        plugin = self,
                    })
                    if provider_ok then
                        provider = provider_instance
                    else
                        logger.warn("Bookshelf provider factory failed:", provider_instance)
                        provider = nil
                    end
                elseif type(provider) == "table" and type(provider.new) == "function" then
                    local provider_ok, provider_instance = pcall(provider.new, provider, {
                        ui = self.ui,
                        plugin = self,
                    })
                    if provider_ok then
                        provider = provider_instance
                    else
                        logger.warn("Bookshelf provider init failed:", provider_instance)
                        provider = nil
                    end
                end

                if type(provider) == "table" then
                    self.provider = provider
                    return self.provider
                end
            else
                logger.warn("Bookshelf provider failed:", provider)
            end
        else
            logger.warn("Bookshelf provider could not be loaded:", load_err)
        end
    end

    self.provider = PlaceholderProvider
    return self.provider
end

function Bookshelf:onShowBookshelf()
    local BookshelfUI = dofile(self.path .. "/ui.lua")

    self.bookshelf_ui = BookshelfUI:new{
        ui = self.ui,
        provider = self:getProvider(),
        closed_callback = function()
            self.bookshelf_ui = nil
        end,
    }
    UIManager:show(self.bookshelf_ui)
    return true
end

return Bookshelf
