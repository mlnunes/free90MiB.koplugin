local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ProgressWidget = require("ui/widget/progresswidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Device = require("device")
local logger = require("logger")
local _ = require("gettext")

local Free90MiB = WidgetContainer:extend{
    name = "free90MiB",
    is_doc_only = false,
}

local API = require("free90mib_api")
local MIB = API.MIB

local function formatMiB(bytes)
    return string.format("%.1f", bytes / MIB)
end

function Free90MiB:init()
    self.ui.menu:registerToMainMenu(self)

    -- Create the plugin-owned data directory without automatically changing
    -- the device's free space. Filling remains an explicit user/API action.
    local status, err = API.get_status()
    if not status then
        logger.warn("free90MiB could not initialize its data directory:", err)
    end
end

function Free90MiB:addToMainMenu(menu_items)
    menu_items.free90MiB = {
        text = _("Free 90 MiB"),
        sorting_hint = "more_tools",
        callback = function()
            self:showMenu()
        end,
    }
end

function Free90MiB:showInfo(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 8,
    })
end

function Free90MiB:showMenu()
    local status, err = API.get_status()
    if not status then
        self:showInfo(_("Unable to read storage status:") .. "\n" .. tostring(err))
        return
    end

    local menu
    menu = ButtonDialog:new{
        title = _("Free space on /mnt/us: ") .. formatMiB(status.free_bytes) .. " MiB\n"
            .. _("Managed filler files: ") .. formatMiB(status.managed_bytes) .. " MiB",
        buttons = {
            {
                {
                    text = _("Normalize to 70–90 MiB"),
                    callback = function()
                        UIManager:close(menu)
                        self:startOperation("reconcile")
                    end,
                },
            },
            {
                {
                    text = _("Release requested space…"),
                    callback = function()
                        UIManager:close(menu)
                        self:askSpaceAmount()
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(menu)
                    end,
                },
            },
        },
    }
    UIManager:show(menu)
end

function Free90MiB:askSpaceAmount()
    local dialog
    dialog = InputDialog:new{
        title = _("Release space"),
        description = _("Enter the amount in MiB. Whole filler files may be removed, so the actual amount can be larger."),
        input = "20",
        input_hint = _("MiB"),
        input_type = "number",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Release"),
                    is_enter_default = true,
                    callback = function()
                        local amount_mib = dialog:getInputValue()
                        if not amount_mib or amount_mib <= 0 or amount_mib ~= amount_mib
                            or amount_mib == math.huge or amount_mib == -math.huge then
                            self:showInfo(_("Enter a positive amount in MiB."))
                            return
                        end
                        UIManager:close(dialog)
                        self:startOperation("release", math.ceil(amount_mib * MIB))
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Free90MiB:startOperation(operation, requested_bytes)
    local title = operation == "release" and _("Releasing space…") or _("Normalizing free space…")
    local dialog
    local progress_bar
    local handle
    local user_cancelled = false
    local last_progress_bucket = -1

    dialog = InputDialog:new{
        title = title,
        input = _("Preparing…"),
        readonly = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        user_cancelled = true
                        if handle then
                            handle:cancel()
                        end
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    progress_bar = ProgressWidget:new{
        width = math.floor(Device.screen:getWidth() * 0.72),
        height = Device.screen:scaleBySize(12),
        percentage = 0,
    }
    dialog:addWidget(progress_bar)
    UIManager:show(dialog)

    local function on_progress(progress)
        if not UIManager:isWidgetShown(dialog) then
            return
        end
        local percent = math.floor((progress.percentage or 0) * 100)
        local progress_bucket = math.min(math.floor(percent / 5) * 5, 100)
        if progress_bucket == last_progress_bucket then
            return
        end
        last_progress_bucket = progress_bucket
        local label = _("Free space: ") .. formatMiB(progress.current_free_bytes or 0) .. " MiB\n"
            .. _("Progress: ") .. tostring(percent) .. "%"
        if progress.file_name then
            label = label .. "\n" .. progress.file_name
        end
        dialog:setInputText(label)
        progress_bar:setPercentage(progress.percentage or 0)
        UIManager:setDirty(dialog, "ui")
    end

    local function on_done(success, result)
        if UIManager:isWidgetShown(dialog) then
            UIManager:close(dialog)
        end
        if user_cancelled or (result and result.cancelled) then
            return
        end

        if not success then
            local message = result and result.message or _("Operation failed.")
            local free = result and result.final_free_bytes
            if free then
                message = message .. "\n" .. _("Free space now: ") .. formatMiB(free) .. " MiB"
            end
            self:showInfo(message)
            return
        end

        local free = formatMiB(result.final_free_bytes or 0)
        local changed = formatMiB(result.changed_bytes or 0)
        if operation == "release" then
            self:showInfo(_("Released ") .. changed .. " MiB.\n" .. _("Free space now: ") .. free .. " MiB")
        else
            self:showInfo(_("Space normalized.\nFree space now: ") .. free .. " MiB")
        end
    end

    local err
    if operation == "release" then
        handle, err = API.release_space(requested_bytes, on_progress, on_done)
    else
        handle, err = API.reconcile(on_progress, on_done)
    end

    if not handle then
        UIManager:close(dialog)
        self:showInfo(_("Could not start operation:") .. "\n" .. tostring(err))
    end
end

return Free90MiB
