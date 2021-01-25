local event = require "core.event"
local timer = require "core.timer"
local task = require "core.task"
local contextManager = require "core.contextManager"
local createEvent = require "core.DOM.event"
local createExternWindow = require "core.externWindow"

local datamodels = {}
local datamodel_mt = {
    __index = rmlui.DataModelGet,
    __call  = rmlui.DataModelDirty,
    __gc    = rmlui.DataModelDelete,
}
function datamodel_mt:__newindex(k, v)
    if type(v) == "function" then
        local ov = v
        v = function(e,...)
            ov(createEvent(e), ...)
        end
    end
    rmlui.DataModelSet(self,k,v)
end

function event.OnDocumentCreate(document)
    datamodels[document] = {}
end

function event.OnDocumentDestroy(document)
    for _, model in pairs(datamodels[document]) do
        rmlui.DataModelRelease(model)
    end
    datamodels[document] = nil
end

local function createWindow(document, source)
    --TODO: pool
    local window = {}
    local timer_object = setmetatable({}, {__mode="k"})
    function window.createModel(name)
        return function (init)
            local model = rmlui.DataModelCreate(document, name, init)
            datamodels[document][name] = model
            debug.setmetatable(model, datamodel_mt)
            return model
        end
    end
    function window.open(url)
        local newdoc = contextManager.open(url)
        if not newdoc then
            return
        end
        event("OnDocumentExternName", newdoc, document)
        return createWindow(newdoc, document)
    end
    function window.close()
        task.new(function ()
            contextManager.close(document)
            for t in pairs(timer_object) do
                t:remove()
            end
        end)
    end
    function window.setTimeout(f, delay)
        local t = timer.wait(delay, f)
        timer_object[t] = true
        return t
    end
    function window.setInterval(f, delay)
        local t = timer.loop(delay, f)
        timer_object[t] = true
        return t
    end
    function window.clearTimeout(t)
        t:remove()
    end
    function window.clearInterval(t)
        t:remove()
    end
    function window.addEventListener(type, listener, useCapture)
        rmlui.DocumentAddEventListener(document, type, function(e) listener(createEvent(e)) end, useCapture)
    end
    function window.postMessage(data)
        rmlui.DocumentDispatchEvent(document, "message", {
            source = source,
            data = data,
        })
    end
    return window
end

function event.OnDocumentCreate(document, globals)
    globals.window = createWindow(document)
    globals.window.extern = createExternWindow(document)
end

return createWindow
