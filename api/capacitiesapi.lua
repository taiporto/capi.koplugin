local BaseUtil = require("ffi/util")
local LuaSettings = require("luasettings")
local http = require("socket.http")
local ltn12 = require("ltn12")
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local HTTPRequest = require("lib.http_request")

local Utils = require("utils")

local API = {}

local BASE_URL = "https://api.capacities.io"

function API.buildListObjectsByStructureIdUrl(structure_id)
    return BASE_URL .. "/objects/structure?id=" .. structure_id 
end

function API.buildListObjectsByCollectionIdUrl(collection_id)
    return BASE_URL .. "/objects/collection?id=" .. collection_id
end
function API.buildGetObjectByIdUrl(object_id)
    return BASE_URL .. "/object?id=" .. object_id
end

function API.getItemTitle(item)
    return item.properties.title.title.value
end

function API.getAPIKey()
    return API.settings:readSetting("api_key")
end
function API.setAPIKey(api_key)
    API.settings:saveSetting("api_key", api_key)
end

function API.setLibraryVersion(version)
    return API.settings:saveSetting("library_version_nr", version)
end

-- Retrieve underlying settings object to make changes from the outside
function API.getSettings()
    return API.settings
end

function API.getItems()
    if API.items == nil then
        API.items = API.initializeLocalContent("items")
    end

    return API.items
end

function API.setItems(items)
    API.items = items
    local f = assert(io.open(BaseUtil.joinPath(API.capacities_dir, "items.json"), "w"))
    local content = JSON.encode(API.items)
    f:write(content)
    f:close()
end

function API.getCollections()
    if API.collections == nil then
        API.collections = API.initializeLocalContent("collections")
    end

    return API.collections
end

function API.setCollections(collections)
    API.collections = collections
    local f = assert(io.open(BaseUtil.joinPath(API.capacities_dir, "collections.json"), "w"))
    local content = JSON.encode(API.collections)
    f:write(content)
    f:close()
end

function API.ensureKey()
    local api_key = API.settings:readSetting("api_key", "")

    if api_key == "" then
        return "Error: must set API Key"
    end

    return nil, api_key
end

function API.getHeaders(api_key)
    return {
        ["Authorization"] = 'Bearer ' .. api_key,
    }
end


function API.verifyResponse(r, response_code)
    if r ~= 1 then
        return ("Error: " .. response_code)
    elseif response_code ~= 200 then
        return ("Error: API responded with status code " .. response_code)
    end

    return nil
end

function API.fetch(url)
    local error, api_key = API.ensureKey()
    if error ~= nil then return error end

    local headers = API.getHeaders(api_key)

    return HTTPRequest.fetch(url, headers)
end

function API.fetchObject(object_id)
    local url = API.buildGetObjectByIdUrl(object_id)
    local result, headers = API.fetch(url)

    local last_modified_version = 0

    if headers and headers["last-modified-version"] then
        last_modified_version = headers["last-modified-version"]
    end

    return result, last_modified_version
end

function API.fetchListPage(args)
    local url = args.url
    if args.cursor then
        url = url .. "&cursor=" .. args.cursor
    end

    if args.page_size then
        url = url .. "&pageSize=" .. args.page_size
    end

    print("Capi: Fetching page ", url)

    local result, headers = API.fetch(url)

    local last_modified_version = 0

    if headers and headers["last-modified-version"] then
        last_modified_version = headers["last-modified-version"]
    end

    if result == nil then
        return nil, "Error: no result available"
    end

    local results = result.results
    local has_more = result.hasMore
    local next_cursor = result.next_cursor

    if args.callback then
        args.callback(results)
    end

    return results, has_more, next_cursor, last_modified_version
end

function API.fetchCollectionPaginated(collection_url, callback)
    print("Capi: Fetching items.")
    local items = {}

    local result, has_more, next_cursor, library_version = API.fetchListPage{
        url = collection_url,
        callback = callback,
    }
    if type(result) ~= "table" then
        return nil, "Error: Couldn't read result"
    end
    table.move(result, 1, #result, #items + 1, items)

    if not has_more then
        if callback then
            return library_version, nil
        else
            return items, nil
        end
    else
        while has_more do
            result, has_more, next_cursor, library_version = API.fetchListPage{
                url = collection_url,
                cursor = next_cursor,
                callback = callback,
            }
            if type(result) ~= "table" then
                return nil, "Error: Couldn't read result"
            end
            table.move(result, 1, #result, #items + 1, items)
        end
    end

    if callback then
        return library_version, nil
    else
        return items, nil
    end

end

function API.init(capacities_dir)
    print("Capi: initializing API")
    API.capacities_dir = capacities_dir
    local settings_path = BaseUtil.joinPath(API.capacities_dir, "meta.lua")
    print("Capi: settings path " .. settings_path)
    API.settings = LuaSettings:open(settings_path)
    print("Capi: settings opened")

    API.storage_dir = BaseUtil.joinPath(API.capacities_dir, "storage")
    if not Utils.file_exists(API.storage_dir) then
        lfs.mkdir(API.storage_dir)
    end

    print("Capi: storage dir " .. API.storage_dir)
end

-- This just syncs them to disk, it will not modify the collection
function API.saveModifiedItems()
    API.settings:flush()
end

function API.initializeLocalContent(content_type)
    local file_name = content_type .. ".json"
    local path = BaseUtil.joinPath(API.capacities_dir, file_name)
    local file_exists = lfs.attributes(path)

    local text_content = Utils.file_slurp(path)

    if not file_exists or not text_content then
        return {}
    else
        return JSON.decode(Utils.file_slurp(path))
    end
end

function API.syncAllItems()
    local error, api_key = API.ensureKey()
    if error ~= nil then return error end
    print(error, api_key)

    local items_url = API.buildListObjectsByStructureIdUrl("MediaPDF")
    local collections_url = API.buildListObjectsByStructureIdUrl("RootDatabase")

    print("Capi: " .. items_url)

    -- Sync library items
    local items = API.getItems()
    print("Capi: loaded items: " .. #items)
    local _, error = API.fetchCollectionPaginated(items_url, function(partial_entries)
        print("Received callback, processing item entries: " .. #partial_entries)
        for i = 1, #partial_entries do
            -- Ruthlessly update our local items
            local item = partial_entries[i]
            
            local full_item = API.fetchObject(item.id)

            if full_item == nil then
                print("Capi: Unable to fetch item data")
                goto continue
            end

            local key = item.id

            items[key] = full_item

            ::continue::
        end
    end)
    if error ~= nil then return error end
    API.setItems(items)

    -- Sync library collections
    local collections = API.getCollections()
    local library_version, error = API.fetchCollectionPaginated(collections_url, function(partial_entries)
        print("Received callback, processing collection entries: " .. #partial_entries)
        for i = 1, #partial_entries do
            local collection = partial_entries[i]

            if collection.title ~= "" then
                local url = API.buildListObjectsByCollectionIdUrl(collection.id)
                local result = API.fetchListPage{
                    url = url,
                    page_size = 1,
                }

                if result == nil then
                    print("Capi: Unable to fetch collection")
                    goto continue
                end

                if #result == 0 then
                    print("Capi: Empty collection. Skipping.")
                    goto continue
                end

                print("Capi: result size " .. #result)

                if result[1].structureId == "MediaPDF" then
                    local key = collection.id
                    collections[key] = collection
                end
                
                ::continue::
            end

        end
    end)
    if error ~= nil then return error end
    API.setCollections(collections)

    API.setLibraryVersion(library_version)
    API.settings:flush()
    return nil
end

function API.getDirAndPath(attachmentKey)
    local items = API.getItems()
    local attachment = items[attachmentKey]

    if attachment == nil then
        return nil, nil
    end

    local targetDir = API.storage_dir .. "/"
    if attachment.collections ~= nil then
        targetDir = targetDir .. attachment.collections[1]
    else
        targetDir = targetDir .. attachmentKey
    end
    local targetPath = targetDir .. "/" .. API.getItemTitle(attachment) .. ".pdf"

    return targetDir, targetPath
end

function API.downloadAndGetPath(key, download_callback)
    local error = API.ensureKey()
    if error ~= nil then return nil, error end

    local items = API.getItems()
    if items[key] == nil then
        return nil, "Error: the requested file can not be found in the database"
    end
    local item = items[key]
    local file = item.files[1]

    if file.fileType ~= "application/pdf" then
        return nil, "Error: this item is not a PDF"
    end

    if not file.url then
        return nil, "Error: this item doesn't have a download URL."
    end

    local attachment = file

    local targetDir, targetPath = API.getDirAndPath(key)

    if not targetPath or targetPath == nil then
        return nil, "Error: no valid targetPath"
    end

    lfs.mkdir(targetDir)

    local local_version = tonumber(Utils.file_slurp(targetDir .. "/version"))

    if local_version ~= nil and local_version >= attachment.version and Utils.file_exists(targetPath) then
        return targetPath, nil -- all done, local file is up to date
    end

    if download_callback ~= nil then download_callback() end

    local url = file.url
    print("Fetching " .. url)

    local r, c = http.request {
        url = url,
        sink = ltn12.sink.file(io.open(targetPath, "wb"))
    }

    local error = API.verifyResponse(r, c)
    if error ~= nil then return nil, error end

    local versionFile = io.open(targetDir .. "/version", "w")
    if versionFile == nil then
        return nil, "Could not write version file"
    end
    versionFile:write(tostring(attachment.version))
    versionFile:close()

    return targetPath, nil
end

function API.displayCollection(key)
    local comparator = function(a,b)
        return (a["text"] < b["text"])
    end

    -- Get list of items
    -- Careful: linear search. Can be optimized quite a bit!
    local items = API.getItems()
    local itemsArray = {}

    if items == nil then
        return itemsArray
    end

    if key == nil then
        local collectionsArray = {}
        local collections = API.getCollections()

        if collections == nil then
            goto skip_collections
        end

        for k, collection in pairs(collections) do
            table.insert(collectionsArray, {
                ['key'] = k,
                ["text"] = collection.title .. "/",
                ["collection"] = true,
            })
        end

        table.sort(collectionsArray, comparator)

        ::skip_collections::

        for k, item in pairs(items) do
            local item_collections = item.collections
            if item_collections == nil or #item_collections == 0 then
                table.insert(itemsArray, {
                        ["key"] = k,
                        ["text"] = API.getItemTitle(item)
                    })
            end
        end

        table.sort(itemsArray, comparator)

        return Utils.join_tables(collectionsArray, itemsArray)
    end

    for k, item in pairs(items) do
        local item_collections = item.collections
        if item_collections ~= nil and #item_collections ~= 0 then
            if Utils.table_contains(item_collections, key) then
                table.insert(itemsArray, {
                    ["key"] = k,
                    ["text"] = API.getItemTitle(item)
                })
            end
        end
    end

    table.sort(itemsArray, comparator)

    return itemsArray
end

function API.displaySearchResults(query)
    print("displaySearchResults for " .. query)
    local queryRegex = ".*" .. string.gsub(string.lower(query), " ", ".*") .. ".*"
    print("Searching for " .. queryRegex)
    -- Careful: linear search. Can be optimized quite a bit!
    local items = API.getItems()
    local results = {}

    for k, item in pairs(items) do
        if item.collections ~= nil and items[item.collections] ~= nil then
            local name = API.getItemTitle(item)
            if string.match(string.lower(name), queryRegex) then
                table.insert(results, {
                    ["key"] = k,
                    ["text"] = name
                })
            end
        end
    end

    return results
end

function API.resetSyncState()
    API.setItems({})
    API.setCollections({})
    API.setLibraryVersion(0)
end

return API