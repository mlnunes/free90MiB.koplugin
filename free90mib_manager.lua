local Manager = {}
Manager.__index = Manager

Manager.MIB = 1024 * 1024
Manager.LOWER_LIMIT = 70 * Manager.MIB
Manager.UPPER_LIMIT = 90 * Manager.MIB
Manager.FILLER_BYTES = 20 * Manager.MIB
Manager.STEP_BYTES = 1 * Manager.MIB
Manager.MAX_SERIAL = 99999

local Operation = {}
Operation.__index = Operation

local function buildResult(operation, initial_free, final_free, files, message)
    local changed_bytes
    if operation == "fill" then
        changed_bytes = math.max(0, initial_free - final_free)
    else
        changed_bytes = math.max(0, final_free - initial_free)
    end
    local result = {
        operation = operation,
        initial_free_bytes = initial_free,
        final_free_bytes = final_free,
        changed_bytes = changed_bytes,
        file_count = #files,
        message = message,
    }
    return result
end

function Manager:new(storage)
    return setmetatable({ storage = storage }, self)
end

function Manager:begin_reconcile()
    local status, err = self.storage:get_status()
    if not status then
        return nil, err
    end

    local mode, target
    if status.free_bytes > self.UPPER_LIMIT then
        mode = "fill"
        target = self.UPPER_LIMIT
    elseif status.free_bytes < self.LOWER_LIMIT then
        mode = "release"
        target = self.LOWER_LIMIT
    else
        mode = "noop"
        target = status.free_bytes
    end

    return setmetatable({
        manager = self,
        mode = mode,
        goal = "reconcile",
        initial_free = status.free_bytes,
        target_free = target,
        files = status.files,
        last_file = nil,
        finished = false,
    }, Operation)
end

function Manager:begin_release_space(requested_bytes)
    if type(requested_bytes) ~= "number" or requested_bytes ~= requested_bytes
        or requested_bytes == math.huge or requested_bytes == -math.huge
        or requested_bytes <= 0 or requested_bytes ~= math.floor(requested_bytes) then
        return nil, "requested_bytes must be a positive integer"
    end

    local status, err = self.storage:get_status()
    if not status then
        return nil, err
    end

    return setmetatable({
        manager = self,
        mode = "release",
        goal = "requested_release",
        initial_free = status.free_bytes,
        target_free = status.free_bytes + requested_bytes,
        requested_bytes = requested_bytes,
        files = status.files,
        last_file = nil,
        finished = false,
    }, Operation)
end

function Operation:_progress(current_free)
    local total
    local processed
    if self.mode == "fill" then
        total = self.initial_free - self.target_free
        processed = self.initial_free - current_free
    elseif self.goal == "requested_release" then
        total = self.requested_bytes
        processed = current_free - self.initial_free
    else
        total = self.target_free - self.initial_free
        processed = current_free - self.initial_free
    end
    total = math.max(total, 0)
    processed = math.max(processed, 0)

    return {
        phase = self.mode,
        current_free_bytes = current_free,
        initial_free_bytes = self.initial_free,
        target_free_bytes = self.target_free,
        processed_bytes = processed,
        total_bytes = total,
        percentage = total == 0 and 1 or math.min(processed / total, 1),
        file_name = self.last_file,
        file_count = #self.files,
    }
end

function Operation:_finish(current_free, message)
    self.finished = true
    local public_operation = self.mode
    if self.goal == "requested_release" then
        public_operation = "release_space"
    end
    local result = buildResult(public_operation, self.initial_free, current_free, self.files, message)
    result.requested_bytes = self.requested_bytes
    result.progress = self:_progress(current_free)
    self.result = result
    return "done", result
end

function Operation:_fail(current_free, message)
    self.finished = true
    local public_operation = self.mode
    if self.goal == "requested_release" then
        public_operation = "release_space"
    end
    local result = buildResult(public_operation, self.initial_free, current_free or self.initial_free, self.files, message)
    result.requested_bytes = self.requested_bytes
    result.progress = self:_progress(current_free or self.initial_free)
    self.result = result
    return "error", result
end

function Operation:step()
    if self.finished then
        return "done", self.result
    end

    local current_free, err = self.manager.storage:free_bytes()
    if not current_free then
        return self:_fail(self.initial_free, err)
    end

    if self.mode == "noop" then
        return self:_finish(current_free, "free space is already within 70–90 MiB")
    end

    if self.mode == "fill" then
        if current_free < self.manager.LOWER_LIMIT then
            return self:_fail(current_free, "free space fell below 70 MiB during filling; stopped for safety")
        end
        if current_free <= self.target_free then
            return self:_finish(current_free, "filler files adjusted")
        end

        local file = self.files[#self.files]
        local name, file_size
        if file and file.size < self.manager.FILLER_BYTES then
            name, file_size = file.name, file.size
        else
            local serial = file and (file.serial + 1) or 0
            if serial > self.manager.MAX_SERIAL then
                return self:_fail(current_free, "all 100000 filler filenames are in use")
            end
            name = string.format("trash%05d.bin", serial)
            file_size = 0
            file = { name = name, serial = serial, size = 0 }
            table.insert(self.files, file)
        end

        local amount = math.min(
            self.manager.STEP_BYTES,
            self.manager.FILLER_BYTES - file_size,
            current_free - self.target_free
        )
        amount = math.floor(amount / 1024) * 1024
        if amount <= 0 then
            return self:_fail(current_free, "no safe filler write size is available")
        end

        local ok
        ok, err = self.manager.storage:append_zeros(name, amount)
        if not ok then
            -- A failed dd can leave a short file and may coincide with a
            -- competing writer consuming the remaining free space. Remove
            -- only this plugin's current tail file to recover what we can.
            self.manager.storage:remove_file(name)
            if self.files[#self.files] and self.files[#self.files].name == name then
                table.remove(self.files)
            end
            local recovered_free = self.manager.storage:free_bytes()
            return self:_fail(recovered_free or current_free, err)
        end
        file.size = file.size + amount
        self.last_file = name

        local after_free
        after_free, err = self.manager.storage:free_bytes()
        if not after_free then
            return self:_fail(current_free, err)
        end
        if after_free >= current_free then
            return self:_fail(after_free, "writing filler data did not reduce available space")
        end
        if after_free < self.manager.LOWER_LIMIT then
            local cleanup_ok = self.manager.storage:remove_file(name)
            if cleanup_ok then
                if self.files[#self.files] and self.files[#self.files].name == name then
                    table.remove(self.files)
                end
                local recovered_free = self.manager.storage:free_bytes()
                if recovered_free then
                    after_free = recovered_free
                end
            end
            return self:_fail(after_free, "free space fell below 70 MiB after a filler write")
        end
        if after_free <= self.target_free then
            return self:_finish(after_free, "filler files adjusted")
        end
        return "pending", self:_progress(after_free)
    end

    -- Both reconciliation below 70 MiB and explicit requests release space by
    -- removing only the highest-numbered plugin-owned filler files.
    if current_free >= self.target_free then
        return self:_finish(current_free, "space released")
    end

    local file = self.files[#self.files]
    if not file then
        return self:_fail(current_free, "not enough plugin-owned filler files to release the requested space")
    end

    local ok
    ok, err = self.manager.storage:remove_file(file.name)
    if not ok then
        return self:_fail(current_free, err)
    end
    table.remove(self.files)
    self.last_file = file.name

    local after_free
    after_free, err = self.manager.storage:free_bytes()
    if not after_free then
        return self:_fail(current_free, err)
    end
    if after_free <= current_free then
        return self:_fail(after_free, "removing a filler file did not increase available space")
    end
    if after_free >= self.target_free then
        return self:_finish(after_free, "space released")
    end
    return "pending", self:_progress(after_free)
end

return Manager
