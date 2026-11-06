local lfs = require("libs/libkoreader-lfs")

local Storage = {}
Storage.__index = Storage

Storage.MOUNT_PATH = "/mnt/us"
Storage.DATA_DIR = "/mnt/us/koreader/free90MiB"
Storage.MIB = 1024 * 1024
Storage.FILLER_BYTES = 20 * Storage.MIB

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function commandSucceeded(a, b, c)
    -- LuaJIT/Lua 5.1 returns the numeric status. Newer Lua versions return
    -- true, "exit", status.
    return a == true or a == 0 or (b == "exit" and c == 0)
end

function Storage:new()
    return setmetatable({}, self)
end

function Storage:ensure_dir()
    local attrs = lfs.symlinkattributes(self.DATA_DIR)
    if attrs then
        if attrs.mode == "directory" then
            return true
        end
        return nil, self.DATA_DIR .. " exists but is not a directory"
    end

    local ok, err = lfs.mkdir(self.DATA_DIR)
    if not ok then
        -- Another caller may have created it between attributes() and mkdir().
        attrs = lfs.symlinkattributes(self.DATA_DIR)
        if attrs and attrs.mode == "directory" then
            return true
        end
        return nil, "cannot create " .. self.DATA_DIR .. ": " .. tostring(err)
    end
    return true
end

function Storage:free_bytes()
    local command = "df -Pk " .. shellQuote(self.MOUNT_PATH) .. " 2>/dev/null"
    local pipe, err = io.popen(command, "r")
    if not pipe then
        return nil, "cannot run df: " .. tostring(err)
    end

    local output = pipe:read("*a") or ""
    local ok, reason, code = pipe:close()
    if not commandSucceeded(ok, reason, code) then
        return nil, "df failed: " .. output
    end

    local available_kib
    for line in output:gmatch("[^\r\n]+") do
        local total, used, available = line:match("^%s*%S+%s+(%d+)%s+(%d+)%s+(%d+)%s+")
        if available then
            available_kib = tonumber(available)
        end
    end
    if not available_kib then
        return nil, "could not parse available space from df output"
    end
    return available_kib * 1024
end

function Storage:list_files()
    local attrs = lfs.symlinkattributes(self.DATA_DIR)
    if not attrs then
        return {}
    end
    if attrs.mode ~= "directory" then
        return nil, self.DATA_DIR .. " is not a directory"
    end

    local files = {}
    for entry in lfs.dir(self.DATA_DIR) do
        local serial = entry:match("^trash(%d%d%d%d%d)%.bin$")
        if serial then
            local path = self.DATA_DIR .. "/" .. entry
            local file_attrs = lfs.symlinkattributes(path)
            if not file_attrs or file_attrs.mode ~= "file" then
                return nil, "managed path is not a regular file: " .. entry
            end
            table.insert(files, {
                name = entry,
                serial = tonumber(serial),
                size = file_attrs.size,
            })
        end
    end

    table.sort(files, function(a, b)
        return a.serial < b.serial
    end)

    for index, file in ipairs(files) do
        if file.serial ~= index - 1 then
            return nil, "gap in filler file serials near " .. file.name
        end
        if file.size <= 0 or file.size > self.FILLER_BYTES then
            return nil, "invalid filler file size: " .. file.name
        end
        if index < #files and file.size ~= self.FILLER_BYTES then
            return nil, "only the last filler file may be smaller than 20 MiB: " .. file.name
        end
    end

    return files
end

function Storage:get_status()
    local ok, err = self:ensure_dir()
    if not ok then
        return nil, err
    end

    local files
    files, err = self:list_files()
    if not files then
        return nil, err
    end

    local free_bytes
    free_bytes, err = self:free_bytes()
    if not free_bytes then
        return nil, err
    end

    local managed_bytes = 0
    for _, file in ipairs(files) do
        managed_bytes = managed_bytes + file.size
    end
    return {
        free_bytes = free_bytes,
        managed_bytes = managed_bytes,
        files = files,
    }
end

function Storage:append_zeros(name, bytes)
    if not name:match("^trash%d%d%d%d%d%.bin$") then
        return nil, "invalid filler filename"
    end
    if bytes <= 0 or bytes % 1024 ~= 0 then
        return nil, "filler writes must be positive multiples of 1 KiB"
    end

    local path = self.DATA_DIR .. "/" .. name
    local attrs = lfs.symlinkattributes(path)
    if attrs and attrs.mode ~= "file" then
        return nil, "managed path is not a regular file: " .. name
    end
    local original_size = attrs and attrs.size or 0

    -- Use dd against /dev/zero and append to a regular file (not a sparse file).
    -- File names are strictly validated above and the data directory is fixed.
    local command = string.format(
        "dd if=/dev/zero bs=1024 count=%d 2>/dev/null >> %s",
        bytes / 1024,
        shellQuote(path)
    )
    local a, b, c = os.execute(command)
    if not commandSucceeded(a, b, c) then
        return nil, "dd failed while writing " .. name
    end
    local written_attrs = lfs.symlinkattributes(path)
    if not written_attrs or written_attrs.mode ~= "file" or written_attrs.size ~= original_size + bytes then
        return nil, "dd did not write the expected number of bytes to " .. name
    end
    return true
end

function Storage:remove_file(name)
    if not name:match("^trash%d%d%d%d%d%.bin$") then
        return nil, "invalid filler filename"
    end

    local path = self.DATA_DIR .. "/" .. name
    local attrs = lfs.symlinkattributes(path)
    if not attrs then
        return nil, "filler file disappeared: " .. name
    end
    if attrs.mode ~= "file" then
        return nil, "managed path is not a regular file: " .. name
    end
    local ok, err = os.remove(path)
    if not ok then
        return nil, "cannot remove " .. name .. ": " .. tostring(err)
    end
    if lfs.symlinkattributes(path) then
        return nil, "filler file still exists after removal: " .. name
    end
    return true
end

return Storage
