-- Public API for other KOReader plugins.
-- Example: local Free90MiB = require("free90mib_api")

local UIManager = require("ui/uimanager")
local Manager = require("free90mib_manager")
local Storage = require("free90mib_storage")

local manager = Manager:new(Storage:new())
local active_operation

local API = {
    MIB = Manager.MIB,
    LOWER_LIMIT_BYTES = Manager.LOWER_LIMIT,
    UPPER_LIMIT_BYTES = Manager.UPPER_LIMIT,
}

local function safeCallback(callback, ...)
    if type(callback) == "function" then
        local ok, err = pcall(callback, ...)
        if not ok then
            local logger = require("logger")
            logger.err("free90MiB API callback failed:", err)
        end
    end
end

function API.get_status()
    return manager.storage:get_status()
end

local function start_operation(begin_operation, on_progress, on_done)
    if active_operation then
        return nil, "another free90MiB operation is already in progress"
    end

    local operation, err = begin_operation()
    if not operation then
        return nil, err
    end

    local handle = {
        cancelled = false,
    }
    function handle:cancel()
        self.cancelled = true
    end
    active_operation = handle

    local function finish(success, result)
        if active_operation == handle then
            active_operation = nil
        end
        safeCallback(on_done, success, result)
    end

    local function tick()
        if active_operation ~= handle then
            return
        end
        if handle.cancelled then
            local status = manager.storage:get_status()
            finish(false, {
                cancelled = true,
                message = "operation cancelled; completed file changes were retained",
                final_free_bytes = status and status.free_bytes,
            })
            return
        end

        local state, result = operation:step()
        if result and result.current_free_bytes then
            safeCallback(on_progress, result)
        elseif result and result.progress then
            safeCallback(on_progress, result.progress)
        end

        if state == "pending" then
            UIManager:scheduleIn(0.01, tick)
        elseif state == "done" then
            finish(true, result)
        else
            finish(false, result)
        end
    end

    UIManager:nextTick(tick)
    return handle
end

function API.reconcile(on_progress, on_done)
    return start_operation(function()
        return manager:begin_reconcile()
    end, on_progress, on_done)
end

function API.release_space(requested_bytes, on_progress, on_done)
    if type(requested_bytes) == "number" and (requested_bytes == math.huge or requested_bytes == -math.huge) then
        return nil, "requested_bytes must be finite"
    end
    return start_operation(function()
        return manager:begin_release_space(requested_bytes)
    end, on_progress, on_done)
end

return API
