--[[--
Plugin to sync capacities PDF objects to KOReader.

@module koplugin.CapiPDF
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local SpinWidget = require("ui/widget/spinwidget")
local DataStorage = require("datastorage")
local FrameContainer = require("ui/widget/container/framecontainer")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local Menu = require("ui/widget/menu")
local Geom = require("ui/geometry")
local _ = require("gettext")
local CapacitiesAPI = require("api.capacitiesapi")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local lfs = require("libs/libkoreader-lfs")


local DEFAULT_LINES_PER_PAGE = 14

local table_empty = function(table)
    -- see https://stackoverflow.com/a/1252776
    local next = next
    return (next(table) == nil)
end

local CapiPDF = Menu:extend{
    no_title = false,
    is_borderless = true,
    is_popout = false,
    parent = nil,
    title_bar_left_icon = "appbar.search",
    covers_full_screen = true,
    return_arrow_propagation = false,
}


function CapiPDF:init()
    Menu.init(self)
    self.paths = {}
end

-- Show search input
function CapiPDF:onLeftButtonTap()
    table.insert(self.paths, "search")
    local search_query_dialog
    search_query_dialog = InputDialog:new{
        title = _("Search Capacities titles"),
        input = "",
        input_hint = "search query",
        description = _("This will search title, first author and DOI of all entries."),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(search_query_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(search_query_dialog)
                        self:displaySearchResults(search_query_dialog:getInputText())
                    end,
                },
            }
        }
    }
    UIManager:show(search_query_dialog)
    search_query_dialog:onShowKeyboard()
end


function CapiPDF:onReturn()
    table.remove(self.paths, #self.paths)
    if #self.paths == 0 then
        self:displayCollection(nil)
    else
        self:displayCollection(self.paths[#self.paths])
    end
    return true
end


function CapiPDF:onMenuSelect(item)
    if item.collection ~= nil then
        table.insert(self.paths, item.key)
        self:displayCollection(item.key)
    elseif item.wildcard_collection ~= nil then
        table.insert(self.paths, "root")
        self:displaySearchResults("")
    else
        self.download_dialog = InfoMessage:new{
            text = _("Downloading file"),
            timeout = 5,
            icon = "notice-info",
        }
        UIManager:scheduleIn(0.05, function()
            local full_path, e = CapacitiesAPI.downloadAndGetPath(item.key)
            if e ~= nil then
                local b = InfoMessage:new{
                    text = _("Could not open file.") .. e,
                    timeout = 5,
                    icon = "notice-warning"
                }
                UIManager:show(b)
            else
                UIManager:close(self.download_dialog)
                local ReaderUI = require("apps/reader/readerui")
                self.close_callback()
                ReaderUI:showReader(full_path)
            end
        end)
        UIManager:show(self.download_dialog)
    end
end

function CapiPDF:displaySearchResults(query)
    local items = CapacitiesAPI.displaySearchResults(query)
    if table_empty(items) then
        table.insert(items, 1, {
            ["text"] = _("No Results"),
            ["is_label"] = true,
        })
    end
    self:setItems(items)
end

function CapiPDF:displayCollection(collection_id)
    local items = CapacitiesAPI.displayCollection(collection_id)
--[[ 
    if collection_id == nil then
        table.insert(items, 1, {
            ["text"] = _("All Items"),
            ["wildcard_collection"] = true
        })
    end ]]

    if table_empty(items) then
        table.insert(items, 1, {
            ["text"] = _("No Items"),
            ["is_label"] = true,
        })
    end

    self:setItems(items)
end

function CapiPDF:setItems(items)
    self:switchItemTable("Capacities", items)
end

local Plugin = WidgetContainer:new{
    name = "CapiPDF",
    is_doc_only = false
}

function Plugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("Capacities_open_action", {
        category="none",
        event="CapacitiesOpenAction",
        title=_("Capacities Open"),
        general=true,
    })
    Dispatcher:registerAction("Capacities_sync_action", {
        category="none",
        event="CapacitiesSyncAction",
        title=_("Capacities Sync"),
        general=true
    })
end

function Plugin:init()
    self.initialized = false
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    xpcall(self.initAPIAndBrowser, self.initError, self)
    self.initialized = true
    print("C: successfully initialized!")
end

function Plugin:initError(e)
    print("Could not initialize Capacities: " .. e)
end

function Plugin:checkInitialized()
    if not self.initialized  or self.browser == nil then
        UIManager:show(InfoMessage:new{
            text = _("Capacities not initialized. Please set the plugin directory first."),
            timeout = 3,
            icon = "notice-warning"
        })
    end

    return self.initialized
end

function Plugin:initAPIAndBrowser()
    self.capacities_dir_path = DataStorage:getDataDir() .. "/capi"
    lfs.mkdir(self.capacities_dir_path)
    CapacitiesAPI.init(self.capacities_dir_path)
    self.small_font_face = Font:getFace("smallffont")
    self.browser = CapiPDF:new{
        refresh_callback = function()
            UIManager:setDirty(self.capacities_dialog)
            self.ui:onRefresh()
        end,
        close_callback = function()
            UIManager:close(self.capacities_dialog)
        end,
		items_per_page = self:getItemsPerPage()
    }
    self.capacities_dialog = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.browser
    }
    self.browser.show_parent = self.capacities_dialog
    print("C: Plugin initialized")
end

function Plugin:addToMainMenu(menu_items)
    menu_items.capacities = {
        text = _("Capacities"),
        sorting_hint = "search",
        sub_item_table = {
            {
                text = _("Browse"),
                callback = function()
                    self:onCapacitiesOpenAction()
                end,
            },
            {
                text = _("Synchronize"),
                callback = function()
                    self:onCapacitiesSyncAction()
                end,

            },
            {
                text = _("Maintenance"),
                callback = function()
                    return nil
                end,
                sub_item_table = {
                    {
                        text = _("Resync entire collection"),
                        callback = function()
                            CapacitiesAPI.resetSyncState()
                            self:onCapacitiesSyncAction()
                        end,
                    },
                },
            },
            {
                text = _("Settings"),
                callback = function()
                    return nil
                end,
                sub_item_table = {
                    {
                        text = _("Configure Capacities account"),
                        callback = function()
                            self:setAccount()
                        end,
                    },
                    {
                        text = _("Items per page"),
                        callback = function()
                            self:setItemsPerPage()
                        end,

                    },
                }
            }
        },
    }
end

function Plugin:setAccount()
    self.account_dialog = MultiInputDialog:new{
        title = _("Edit User Info"),
        fields = {
            {
                text = CapacitiesAPI.getAPIKey(),
                hint = _("API Key"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        self.account_dialog:onClose()
                        UIManager:close(self.account_dialog)
                    end
                },
                {
                    text = _("Update"),
                    callback = function()
                        local fields = self.account_dialog:getFields()
                        CapacitiesAPI.setAPIKey(fields[0])
                        CapacitiesAPI.saveModifiedItems()
                        self.account_dialog:onClose()
                        UIManager:close(self.account_dialog)
                    end
                },
            },
        },
    }
    UIManager:show(self.account_dialog)
    self.account_dialog:onShowKeyboard()
end

function Plugin:setItemsPerPage()
    assert(CapacitiesAPI.getSettings ~= nil)
	print("setting to " .. self:getItemsPerPage())
    self.items_per_page_dialog = SpinWidget:new {
        title_text = _("Set items per page"),
        value = self:getItemsPerPage(),
		value_min = 1,
		value_max = 1000,
        callback = function(d)
						CapacitiesAPI.getSettings():saveSetting("items_per_page", d.value)
						CapacitiesAPI.getSettings():flush()
                        UIManager:show(InfoMessage:new{
                            text = _("This change requires a restart of KOReader to take effect."),
                            timeout = 3,
                            icon = "notice"
                        })
                    end,
    }
	UIManager:show(self.items_per_page_dialog)
end

function Plugin:getItemsPerPage()
    return CapacitiesAPI.getSettings():readSetting("items_per_page", DEFAULT_LINES_PER_PAGE)
end

function Plugin:onCapacitiesOpenAction()
    if not self:checkInitialized() then
        return
    end

    self.browser:init()
    UIManager:show(self.capacities_dialog, "full", Geom:new{
        w = Screen:getWidth(),
        h = Screen:getHeight()
    })
    self.browser:displayCollection(nil)
end

function Plugin:onCapacitiesSyncAction()
    if not self:checkInitialized() then
        return
    end
    UIManager:scheduleIn(1, function()
        local e = CapacitiesAPI.syncAllItems()

        if e == nil then
            UIManager:show(InfoMessage:new{
                text = _("Success."),
                timeout = 3,
                icon = "check"
            })
        else
            UIManager:show(InfoMessage:new{
                text = e,
                timeout = 3,
                icon = "notice-warning"
            })
        end
    end)

    UIManager:show(InfoMessage:new{
        text = _("Synchronizing Capacities library. This might take some time."),
        timeout = 3,
        icon = "notice-info"
    })

end

return Plugin