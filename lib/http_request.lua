local http = require("socket.http")
local ltn12 = require("ltn12")
local JSON = require("json")

local HTTPRequest = {}

function HTTPRequest.verifyResponse(body, response_code)
    if body ~= 1 then
        return ("Error: " .. response_code)
    elseif response_code ~= 200 then
        return ("Error: API responded with status code " .. response_code)
    end

    return nil
end

function HTTPRequest.fetch(url, request_headers)
    print("HTTPRequest: Fetching url ", url)

    local page_data = {}
    local body, code, headers = http.request {
        method = "GET",
        url = url,
        headers = request_headers,
        sink = ltn12.sink.table(page_data)
    }

    local error = HTTPRequest.verifyResponse(body, code)
    if error ~= nil then return nil, error end

    local content = table.concat(page_data, "")
    local ok, result = pcall(JSON.decode, content)
    if not ok then
        return nil, "Error: failed to parse JSON in response"
    end

    return result, headers
end

return HTTPRequest