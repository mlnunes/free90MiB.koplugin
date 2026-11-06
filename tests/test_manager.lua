package.path = "./?.lua;" .. package.path

local Manager = require("free90mib_manager")
local MIB = Manager.MIB

local FakeStorage = {}
FakeStorage.__index = FakeStorage

function FakeStorage:new(free_bytes, files)
    local copy = {}
    for _, file in ipairs(files or {}) do
        table.insert(copy, {
            name = file.name,
            serial = file.serial,
            size = file.size,
        })
    end
    return setmetatable({ free = free_bytes, files = copy }, self)
end

function FakeStorage:get_status()
    local files = {}
    local total = 0
    for _, file in ipairs(self.files) do
        table.insert(files, {
            name = file.name,
            serial = file.serial,
            size = file.size,
        })
        total = total + file.size
    end
    return { free_bytes = self.free, managed_bytes = total, files = files }
end

function FakeStorage:free_bytes()
    return self.free
end

function FakeStorage:append_zeros(name, bytes)
    local file = self.files[#self.files]
    if not file or file.name ~= name then
        local serial = tonumber(name:match("trash(%d%d%d%d%d)%.bin"))
        file = { name = name, serial = serial, size = 0 }
        table.insert(self.files, file)
    end
    file.size = file.size + bytes
    self.free = self.free - bytes
    return true
end

function FakeStorage:remove_file(name)
    local file = table.remove(self.files)
    assert(file and file.name == name, "unexpected file removal")
    self.free = self.free + file.size
    return true
end

local function run(operation)
    local result
    for _ = 1, 1000 do
        local state, value = operation:step()
        if state == "done" then
            result = value
            break
        elseif state == "error" then
            error(value.message)
        end
    end
    assert(result, "operation did not finish")
    return result
end

local function testFillUsesPartialLastFile()
    local storage = FakeStorage:new(100 * MIB)
    local manager = Manager:new(storage)
    local result = run(assert(manager:begin_reconcile()))
    assert(result.final_free_bytes == 90 * MIB)
    assert(#storage.files == 1)
    assert(storage.files[1].name == "trash00000.bin")
    assert(storage.files[1].size == 10 * MIB)
end

local function testFillCreatesFullBlocksWhenNeeded()
    local storage = FakeStorage:new(150 * MIB)
    local manager = Manager:new(storage)
    local result = run(assert(manager:begin_reconcile()))
    assert(result.final_free_bytes == 90 * MIB)
    assert(#storage.files == 3)
    for index, file in ipairs(storage.files) do
        assert(file.name == string.format("trash%05d.bin", index - 1))
        assert(file.size == 20 * MIB)
    end
end

local function testFillAddsPartialLastAfterFullFiles()
    local files = {
        { name = "trash00000.bin", serial = 0, size = 20 * MIB },
    }
    local storage = FakeStorage:new(100 * MIB, files)
    local manager = Manager:new(storage)
    local result = run(assert(manager:begin_reconcile()))
    assert(result.final_free_bytes == 90 * MIB)
    assert(#storage.files == 2)
    assert(storage.files[1].size == 20 * MIB)
    assert(storage.files[2].name == "trash00001.bin")
    assert(storage.files[2].size == 10 * MIB)
end

local function testNoopInsideTargetBand()
    local storage = FakeStorage:new(80 * MIB)
    local manager = Manager:new(storage)
    local result = run(assert(manager:begin_reconcile()))
    assert(result.final_free_bytes == 80 * MIB)
    assert(#storage.files == 0)
end

local function testReconcileRemovesOnlyManagedFiller()
    local files = {
        { name = "trash00000.bin", serial = 0, size = 20 * MIB },
        { name = "trash00001.bin", serial = 1, size = 20 * MIB },
        { name = "trash00002.bin", serial = 2, size = 20 * MIB },
    }
    local storage = FakeStorage:new(65 * MIB, files)
    local manager = Manager:new(storage)
    local result = run(assert(manager:begin_reconcile()))
    assert(result.final_free_bytes == 85 * MIB)
    assert(#storage.files == 2)
    assert(storage.files[2].name == "trash00001.bin")
end

local function testReleaseRequestMayRoundUpByWholeFile()
    local files = {
        { name = "trash00000.bin", serial = 0, size = 20 * MIB },
        { name = "trash00001.bin", serial = 1, size = 20 * MIB },
    }
    local storage = FakeStorage:new(90 * MIB, files)
    local manager = Manager:new(storage)
    local result = run(assert(manager:begin_release_space(1 * MIB)))
    assert(result.final_free_bytes == 110 * MIB)
    assert(result.changed_bytes == 20 * MIB)
    assert(#storage.files == 1)
end

local function testCannotRaiseSpaceWithoutOwnFiller()
    local storage = FakeStorage:new(50 * MIB)
    local manager = Manager:new(storage)
    local operation = assert(manager:begin_reconcile())
    local state, result = operation:step()
    assert(state == "error")
    assert(result.message:match("not enough plugin%-owned filler files"))
    assert(storage.free == 50 * MIB)
end

testFillUsesPartialLastFile()
testFillCreatesFullBlocksWhenNeeded()
testFillAddsPartialLastAfterFullFiles()
testNoopInsideTargetBand()
testReconcileRemovesOnlyManagedFiller()
testReleaseRequestMayRoundUpByWholeFile()
testCannotRaiseSpaceWithoutOwnFiller()

print("manager tests passed")
