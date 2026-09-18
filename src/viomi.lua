local miio = require "miio"

local viomi = {}

viomi.ALL_PROPS = {
    "run_state",
    "mode",
    "err_state",
    "battary_life",
    "box_type",
    "mop_type",
    "s_time",
    "s_area",
    "suction_grade",
    "water_grade",
    "remember_map",
    "has_map",
    "is_mop",
    "has_newmap",
    "hw_info",
    "sw_info",
    "start_time",
    "order_time",
    "v_state",
    "zone_data",
    "repeat_state",
    "light_state",
    "is_charge",
    "is_work"
}

-- Viomi run_state code mapping
viomi.RUN_STATE = {
    IDLE_0 = 0,     -- Idle / Sleeping
    IDLE_1 = 1,     -- Idle
    PAUSED = 2,     -- Paused
    CLEANING = 3,   -- Cleaning (Vacuum)
    RETURNING = 4,  -- Returning to dock
    DOCKED = 5,     -- Docked / Charging
    VACUUM_MOP = 6, -- Cleaning (Vacuum & Mop)
    MOP_ONLY = 7    -- Cleaning (Mop only)
}

-- Viomi suction / fan speed grades
viomi.FAN_SPEEDS = {
    SILENT = 0,
    STANDARD = 1,
    MEDIUM = 2,
    TURBO = 3
}

-- Viomi water grades for mopping
viomi.WATER_GRADES = {
    LOW = 11,
    MEDIUM = 12,
    HIGH = 13
}

-- Viomi box types
viomi.BOX_TYPES = {
    NONE = 0,
    VACUUM_ONLY = 1,
    VACUUM_AND_WATER = 2,
    WATER_ONLY = 3
}

-- Viomi mop modes
viomi.MOP_MODES = {
    VACUUM = 0,
    MOP = 1,
    VACUUM_AND_MOP = 2
}

-- Parse raw array from get_prop into table
function viomi.parse_status(raw)
    if not raw or type(raw) ~= "table" then return nil end

    local status = {}
    if #raw >= #viomi.ALL_PROPS then
        for idx, prop_name in ipairs(viomi.ALL_PROPS) do
            status[prop_name] = raw[idx]
        end
    else
        for idx, prop_name in ipairs(viomi.ALL_PROPS) do
            status[prop_name] = raw[prop_name] or raw[idx]
        end
    end

    status.run_state = tonumber(status.run_state)
    status.mode = tonumber(status.mode)
    status.err_state = tonumber(status.err_state)
    status.battary_life = tonumber(status.battary_life)
    status.box_type = tonumber(status.box_type)
    status.mop_type = tonumber(status.mop_type)
    status.s_time = tonumber(status.s_time)
    status.s_area = tonumber(status.s_area)
    status.suction_grade = tonumber(status.suction_grade)
    status.water_grade = tonumber(status.water_grade)
    status.is_mop = tonumber(status.is_mop)
    status.v_state = tonumber(status.v_state)
    status.is_charge = tonumber(status.is_charge)
    status.is_work = tonumber(status.is_work)

    return status
end

-- Query device state
function viomi.get_status(device, ip, token)
    local result = miio.get_prop(device, ip, token, viomi.ALL_PROPS)
    if result and type(result) == "table" and #result > 0 then
        return viomi.parse_status(result)
    end
    return nil
end

-- Parse room names and IDs from get_ordertime schedules
function viomi.parse_rooms_from_ordertime(schedules)
    if not schedules or type(schedules) ~= "table" then return {} end
    local rooms = {}
    local seen_ids = {}

    for _, raw_sched in ipairs(schedules) do
        if type(raw_sched) == "string" then
            local parts = {}
            for part in string.gmatch(raw_sched, "[^_]+") do
                table.insert(parts, part)
            end
            -- Format: id, enabled, repeat, hour, min, ?, ?, ?, ?, ?, ?, nbRooms, id1, name1, id2, name2...
            local nb_rooms = tonumber(parts[12]) or 0
            if nb_rooms > 0 then
                local idx = 13
                for i = 1, nb_rooms do
                    local r_id = tonumber(parts[idx])
                    local r_name = parts[idx + 1]
                    if r_id and r_name and not seen_ids[r_id] then
                        seen_ids[r_id] = true
                        table.insert(rooms, { id = r_id, name = r_name })
                    end
                    idx = idx + 2
                end
            end
        end
    end

    return rooms
end

-- Query room list from vacuum schedules
function viomi.get_rooms(device, ip, token)
    local result = miio.cmd(device, ip, token, "get_ordertime", {})
    if result and type(result) == "table" then
        return viomi.parse_rooms_from_ordertime(result)
    end
    return {}
end

-- Start cleaning: either selected rooms or whole home
function viomi.clean_rooms(device, ip, token, status_cache, mop_pref, room_ids)
    local mode = (status_cache and status_cache.mode) or 0
    local is_mop = (status_cache and status_cache.is_mop) or 0
    local box_type = (status_cache and status_cache.box_type) or 1

    local target_mop = is_mop
    if mop_pref == "vacuum" then
        target_mop = viomi.MOP_MODES.VACUUM
    elseif mop_pref == "mop" then
        target_mop = viomi.MOP_MODES.MOP
    elseif mop_pref == "vacuum_and_mop" then
        target_mop = viomi.MOP_MODES.VACUUM_AND_MOP
    elseif mop_pref == "auto" or not mop_pref then
        if box_type == viomi.BOX_TYPES.VACUUM_AND_WATER and is_mop ~= viomi.MOP_MODES.VACUUM_AND_MOP then
            target_mop = viomi.MOP_MODES.VACUUM_AND_MOP
        elseif box_type == viomi.BOX_TYPES.WATER_ONLY and is_mop ~= viomi.MOP_MODES.MOP then
            target_mop = viomi.MOP_MODES.MOP
        elseif box_type == viomi.BOX_TYPES.VACUUM_ONLY and is_mop ~= viomi.MOP_MODES.VACUUM then
            target_mop = viomi.MOP_MODES.VACUUM
        end
    end

    if target_mop ~= is_mop then
        pcall(miio.cmd, device, ip, token, "set_mop", { target_mop })
        is_mop = target_mop
    end

    local action_mode = 0
    if mode == 2 then
        action_mode = 2
    else
        if is_mop == 2 then
            action_mode = 3
        else
            action_mode = is_mop
        end
    end

    if not room_ids or #room_ids == 0 then
        -- Całościowe odkurzanie (bez wskazywania konkretnych pokojów)
        if mode == 3 then
            return miio.cmd(device, ip, token, "set_mode", { 3, 1 })
        else
            return miio.cmd(device, ip, token, "set_mode_withroom", { action_mode, 1, 0 })
        end
    else
        -- Sprzątanie wskazanych pokojów: [action_mode, 1, #room_ids, id1, id2, ...]
        local params = { action_mode, 1, #room_ids }
        for _, id in ipairs(room_ids) do
            table.insert(params, id)
        end
        return miio.cmd(device, ip, token, "set_mode_withroom", params)
    end
end

-- Start or resume whole cleaning
function viomi.start_cleaning(device, ip, token, status_cache, mop_pref)
    return viomi.clean_rooms(device, ip, token, status_cache, mop_pref, nil)
end

-- Pause cleaning
function viomi.pause_cleaning(device, ip, token, status_cache)
    local mode = (status_cache and status_cache.mode) or 0
    local is_mop = (status_cache and status_cache.is_mop) or 0

    local action_mode = 0
    if mode == 2 then
        action_mode = 2
    else
        if is_mop == 2 then
            action_mode = 3
        else
            action_mode = is_mop
        end
    end

    if mode == 3 then
        return miio.cmd(device, ip, token, "set_mode", { 3, 3 })
    else
        return miio.cmd(device, ip, token, "set_mode_withroom", { action_mode, 3, 0 })
    end
end

-- Stop cleaning
function viomi.stop_cleaning(device, ip, token, status_cache)
    local mode = (status_cache and status_cache.mode) or 0
    if mode == 3 then
        return miio.cmd(device, ip, token, "set_mode", { 3, 0 })
    else
        return miio.cmd(device, ip, token, "set_mode", { 0 })
    end
end

-- Return to dock / charge
function viomi.return_to_dock(device, ip, token)
    return miio.cmd(device, ip, token, "set_charge", { 1 })
end

-- Locate vacuum (sound alert)
function viomi.locate(device, ip, token)
    return miio.cmd(device, ip, token, "set_resetpos", { 1 })
end

-- Set fan speed / suction grade (0: Silent, 1: Standard, 2: Medium, 3: Turbo)
function viomi.set_fan_speed(device, ip, token, speed)
    local val = tonumber(speed) or 1
    if val < 0 then val = 0 end
    if val > 3 then val = 3 end
    return miio.cmd(device, ip, token, "set_suction", { val })
end

-- Set water grade (11: Low, 12: Medium, 13: High)
function viomi.set_water_grade(device, ip, token, grade)
    local val = tonumber(grade) or 11
    return miio.cmd(device, ip, token, "set_suction", { val })
end

-- Set mop mode directly (0: Vacuum, 1: Mop, 2: Vacuum & Mop)
function viomi.set_mop(device, ip, token, mop_mode)
    local val = tonumber(mop_mode) or 0
    return miio.cmd(device, ip, token, "set_mop", { val })
end

return viomi
