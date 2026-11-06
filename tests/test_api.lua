package.path = "./?.lua;" .. package.path

local MIB = 1024 * 1024
local queue = {}
local UIManager = {}

function UIManager:nextTick(callback)
    table.insert(queue, callback)
end

function UIManager:scheduleIn(_, callback)
    table.insert(queue, callback)
end

package.preload["ui/uimanager"] = function()
    return UIManager
end

local FakeStorage = {}
FakeStorage.__index = FakeStorage

function FakeStorage:new()
    return setmetatable({ free = 100 * MIB, files = {} }, self)
end

function FakeStorage:get_status()
    local files, managed = {}, 0
    for _, file in ipairs(self.files) do
        table.insert(files, {
            name = file.name,
            serial = file.serial,
            size = file.size,
        })
        managed = managed + file.size
    end
    return { free_bytes = self.free, managed_bytes = managed, files = files }
end

function FakeStorage:free_bytes()
    return self.free
end

function FakeStorage:append_zeros(name, bytes)
    local file = self.files[#self.files]
    if not file or file.name ~= name then
        file = {
            name = name,
            serial = tonumber(name:match("trash(%d%d%d%d%d)%.bin")),
            size = 0,
        }
        table.insert(self.files, file)
    end
    file.size = file.size + bytes
    self.free = self.free - bytes
    return true
end

function FakeStorage:remove_file(name)
    local file = table.remove(self.files)
    assert(file and file.name == name)
    self.free = self.free + file.size
    return true
end

package.preload["free90mib_storage"] = function()
    return FakeStorage
end

local API = require("free90mib_api")
local progress_events = 0
local completion

assert(API.reconcile(function(progress)
    progress_events = progress_events + 1
    assert(progress.percentage >= 0 and progress.percentage <= 1)
end, function(success, result)
    completion = { success = success, result = result }
end))

while #queue > 0 do
    table.remove(queue, 1)()
end

assert(completion and completion.success)
assert(completion.result.final_free_bytes == 90 * MIB)
assert(progress_events > 0)
assert(#API.get_status().files == 1)

completion = nil
assert(API.release_space(1 * MIB, nil, function(success, result)
    completion = { success = success, result = result }
end))

while #queue > 0 do
    table.remove(queue, 1)()
end

assert(completion and completion.success)
assert(completion.result.changed_bytes == 10 * MIB)
assert(API.get_status().free_bytes == 100 * MIB)
assert(#API.get_status().files == 0)

print("api tests passed")
