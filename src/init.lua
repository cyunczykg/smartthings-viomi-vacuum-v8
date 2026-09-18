local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
local discovery = require "discovery"
local miio = require "miio"
local viomi = require "viomi"

local POLLING_TIMER = "viomi_polling_timer"
local STATUS_CACHE = "viomi_status_cache"
local FAIL_COUNT = "viomi_fail_count"
local DEFAULT_POLLING_INTERVAL = 30

local ROOM_COMPONENTS = {
    { key = "room1", default_name = "Kuchnia", default_id = 10 },
    { key = "room2", default_name = "Salon", default_id = 11 },
    { key = "room3", default_name = "Korytarz", default_id = 12 },
    { key = "room4", default_name = "Sypialnia", default_id = 13 },
    { key = "room5", default_name = "Pokój Kasi", default_id = 14 },
    { key = "room6", default_name = "Pokój Maćka", default_id = 15 },
    { key = "room7", default_name = "Łazienka", default_id = 16 },
    { key = "room8", default_name = "Pokój 8", default_id = 17 }
}

local function get_device_config(device)
    local ip = device.preferences.ipAddress
    local raw_token = device.preferences.token
    local token = miio.sanitize_token(raw_token)

    if ip and ip ~= "" and token then
        return ip, token
    end
    return nil, nil
end

local function get_room_id(device, room_key)
    local detected = device:get_field("detected_room_ids")
    if detected and detected[room_key] then
        return detected[room_key]
    end
    for _, rc in ipairs(ROOM_COMPONENTS) do
        if rc.key == room_key then
            return rc.default_id
        end
    end
    return 10
end

local function reset_room_switches(device)
    for _, rc in ipairs(ROOM_COMPONENTS) do
        device:set_field("room_state_" .. rc.key, false)
        local comp = device.profile.components[rc.key]
        if comp then
            device:emit_component_event(comp, capabilities.switch.switch.off())
        end
    end
end

local function emit_vacuum_status(device, status)
    if not status then return end

    local prev_cache = device:get_field(STATUS_CACHE)
    local prev_state = prev_cache and prev_cache.run_state

    -- 1. Battery level
    if status.battary_life and status.battary_life >= 0 and status.battary_life <= 100 then
        device:emit_event(capabilities.battery.battery({ value = status.battary_life }))
    end

    -- 2. Operational state & Switch & Movement & Mode
    local rs = status.run_state
    if rs == viomi.RUN_STATE.CLEANING or rs == viomi.RUN_STATE.VACUUM_MOP or rs == viomi.RUN_STATE.MOP_ONLY then
        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.auto())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
    elseif rs == viomi.RUN_STATE.PAUSED then
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.part())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
    elseif rs == viomi.RUN_STATE.RETURNING then
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.homing())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    elseif rs == viomi.RUN_STATE.DOCKED then
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.charging())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    else -- IDLE
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    end

    -- Reset room selections when cleaning finishes and vacuum docks/idles
    if prev_state and (prev_state == viomi.RUN_STATE.CLEANING or prev_state == viomi.RUN_STATE.VACUUM_MOP or prev_state == viomi.RUN_STATE.MOP_ONLY or prev_state == viomi.RUN_STATE.RETURNING) then
        if rs == viomi.RUN_STATE.DOCKED or rs == viomi.RUN_STATE.IDLE_0 or rs == viomi.RUN_STATE.IDLE_1 then
            log.info(string.format("[%s] Sprzątanie zakończone. Resetowanie zaznaczenia pokojów...", device.label))
            reset_room_switches(device)
        end
    end

    -- 3. Fan speed & Turbo mode
    if status.suction_grade and status.suction_grade >= 0 and status.suction_grade <= 3 then
        device:emit_event(capabilities.fanSpeed.fanSpeed(status.suction_grade))
        if status.suction_grade == viomi.FAN_SPEEDS.TURBO then
            device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.on())
        else
            device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.off())
        end
    end

    device:set_field(STATUS_CACHE, status)
end

local function poll_device_status(device)
    local ip, token = get_device_config(device)
    if not ip or not token then
        log.info(string.format("[%s] Device IP or Token not configured yet.", device.label))
        return
    end

    local status = viomi.get_status(device, ip, token)
    if status then
        device:set_field(FAIL_COUNT, 0)
        device:online()
        emit_vacuum_status(device, status)
    else
        local fails = (device:get_field(FAIL_COUNT) or 0) + 1
        device:set_field(FAIL_COUNT, fails)
        log.warn(string.format("[%s] Failed to query status (failures: %d)", device.label, fails))
        if fails >= 3 then
            device:offline()
        end
    end
end

local function stop_polling_timer(device)
    local timer = device:get_field(POLLING_TIMER)
    if timer then
        device.thread:cancel_timer(timer)
        device:set_field(POLLING_TIMER, nil)
    end
end

local function start_polling_timer(device)
    stop_polling_timer(device)
    local interval = device.preferences.pollingInterval or DEFAULT_POLLING_INTERVAL
    if interval < 10 then interval = 10 end

    local timer = device.thread:call_on_schedule(interval, function()
        pcall(poll_device_status, device)
    end, "ViomiPolling")
    device:set_field(POLLING_TIMER, timer)
end

-- Capability handlers

local function switch_on_handler(_, device, command)
    local comp_id = command.component_id

    -- Obsługa włączenia konkretnego pokoju (zaznaczenie)
    if comp_id and comp_id:match("^room%d+") then
        log.info(string.format("[%s] Zaznaczono pokój: %s", device.label, comp_id))
        device:set_field("room_state_" .. comp_id, true)
        local comp = device.profile.components[comp_id]
        if comp then
            device:emit_component_event(comp, capabilities.switch.switch.on())
        end
        return
    end

    -- Obsługa włączenia głównego przełącznika (Start)
    local ip, token = get_device_config(device)
    if not ip or not token then
        log.error("Cannot start vacuum: IP or Token not configured")
        return
    end

    local cache = device:get_field(STATUS_CACHE)
    local mop_pref = device.preferences.mopMode

    -- Sprawdzenie, które pokoje są zaznaczone
    local selected_ids = {}
    local selected_names = {}
    for _, rc in ipairs(ROOM_COMPONENTS) do
        if device:get_field("room_state_" .. rc.key) == true then
            local r_id = get_room_id(device, rc.key)
            table.insert(selected_ids, r_id)
            local pref_name = device.preferences[rc.key .. "Name"] or rc.default_name
            table.insert(selected_names, pref_name)
        end
    end

    if #selected_ids > 0 and #selected_ids < #ROOM_COMPONENTS then
        log.info(string.format("[%s] Uruchamianie sprzątania wybranych pokojów: %s (IDs: %s)",
            device.label, table.concat(selected_names, ", "), table.concat(selected_ids, ", ")))
        viomi.clean_rooms(device, ip, token, cache, mop_pref, selected_ids)
    else
        log.info(string.format("[%s] Uruchamianie sprzątania całościowego (brak konkretnych pokojów)", device.label))
        viomi.clean_rooms(device, ip, token, cache, mop_pref, nil)
    end

    device:emit_event(capabilities.switch.switch.on())
    device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.auto())
    device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())

    device.thread:call_with_delay(2, function()
        pcall(poll_device_status, device)
    end)
end

local function switch_off_handler(_, device, command)
    local comp_id = command.component_id

    -- Obsługa wyłączenia konkretnego pokoju (odznaczenie)
    if comp_id and comp_id:match("^room%d+") then
        log.info(string.format("[%s] Odznaczono pokój: %s", device.label, comp_id))
        device:set_field("room_state_" .. comp_id, false)
        local comp = device.profile.components[comp_id]
        if comp then
            device:emit_component_event(comp, capabilities.switch.switch.off())
        end
        return
    end

    -- Obsługa wyłączenia głównego przełącznika (Stop / Dock)
    local ip, token = get_device_config(device)
    if not ip or not token then return end

    local cache = device:get_field(STATUS_CACHE)
    local off_action = device.preferences.offAction or "dock"

    if off_action == "stop" then
        viomi.stop_cleaning(device, ip, token, cache)
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
    elseif off_action == "pause" then
        viomi.pause_cleaning(device, ip, token, cache)
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
    else -- "dock"
        viomi.return_to_dock(device, ip, token)
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.homing())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    end

    device.thread:call_with_delay(2, function()
        pcall(poll_device_status, device)
    end)
end

local function movement_handler(_, device, command)
    local ip, token = get_device_config(device)
    if not ip or not token then return end

    local move = command.args.movement
    local cache = device:get_field(STATUS_CACHE)

    if move == "homing" or move == "charging" then
        viomi.return_to_dock(device, ip, token)
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.homing())
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    elseif move == "idle" then
        viomi.stop_cleaning(device, ip, token, cache)
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
        device:emit_event(capabilities.switch.switch.off())
    end

    device.thread:call_with_delay(2, function()
        pcall(poll_device_status, device)
    end)
end

local function cleaning_mode_handler(_, device, command)
    local ip, token = get_device_config(device)
    if not ip or not token then return end

    local mode = command.args.mode
    local cache = device:get_field(STATUS_CACHE)

    if mode == "auto" or mode == "repeat" then
        local mop_pref = device.preferences.mopMode
        viomi.start_cleaning(device, ip, token, cache, mop_pref)
        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode(mode))
    elseif mode == "stop" then
        viomi.stop_cleaning(device, ip, token, cache)
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
    end

    device.thread:call_with_delay(2, function()
        pcall(poll_device_status, device)
    end)
end

local function fan_speed_handler(_, device, command)
    local ip, token = get_device_config(device)
    if not ip or not token then return end

    local speed = command.args.speed
    viomi.set_fan_speed(device, ip, token, speed)
    device:emit_event(capabilities.fanSpeed.fanSpeed(speed))

    if speed == viomi.FAN_SPEEDS.TURBO then
        device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.on())
    else
        device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.off())
    end
end

local function turbo_mode_handler(_, device, command)
    local ip, token = get_device_config(device)
    if not ip or not token then return end

    local mode = command.args.mode
    if mode == "on" then
        viomi.set_fan_speed(device, ip, token, viomi.FAN_SPEEDS.TURBO)
        device:emit_event(capabilities.fanSpeed.fanSpeed(viomi.FAN_SPEEDS.TURBO))
        device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.on())
    else
        viomi.set_fan_speed(device, ip, token, viomi.FAN_SPEEDS.STANDARD)
        device:emit_event(capabilities.fanSpeed.fanSpeed(viomi.FAN_SPEEDS.STANDARD))
        device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.off())
    end
end

local function momentary_handler(_, device, command)
    local comp_id = command.component_id
    local ip, token = get_device_config(device)
    if not ip or not token then
        log.error("Cannot perform action: IP or Token not configured")
        return
    end

    if comp_id == "selectAll" then
        log.info(string.format("[%s] Akcja: Odkurz wszystko (zaznaczanie wszystkich pokojów i całościowy start)", device.label))
        for _, rc in ipairs(ROOM_COMPONENTS) do
            device:set_field("room_state_" .. rc.key, true)
            local comp = device.profile.components[rc.key]
            if comp then
                device:emit_component_event(comp, capabilities.switch.switch.on())
            end
        end

        local cache = device:get_field(STATUS_CACHE)
        local mop_pref = device.preferences.mopMode
        viomi.clean_rooms(device, ip, token, cache, mop_pref, nil)

        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.auto())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())

        local comp = device.profile.components.selectAll
        if comp then device:emit_component_event(comp, capabilities.momentary.push()) end

        device.thread:call_with_delay(2, function() pcall(poll_device_status, device) end)

    elseif comp_id == "deselectAll" then
        log.info(string.format("[%s] Akcja: Odznacz wszystko", device.label))
        reset_room_switches(device)

        local comp = device.profile.components.deselectAll
        if comp then device:emit_component_event(comp, capabilities.momentary.push()) end

    elseif comp_id == "syncRooms" then
        log.info(string.format("[%s] Akcja: Wczytaj pokoje z odkurzacza", device.label))
        local detected = viomi.get_rooms(device, ip, token)
        if detected and #detected > 0 then
            log.info(string.format("[%s] Pomyślnie wczytano %d pokojów z odkurzacza:", device.label, #detected))
            local room_id_map = {}
            for i, r in ipairs(detected) do
                log.info(string.format("  -> Pokój %d: '%s' (ID: %d)", i, r.name, r.id))
                if i <= #ROOM_COMPONENTS then
                    room_id_map[ROOM_COMPONENTS[i].key] = r.id
                end
            end
            device:set_field("detected_room_ids", room_id_map)
        else
            log.info(string.format("[%s] W pamięci odkurzacza nie znaleziono jeszcze przypisanych pokojów (stwórz nieaktywny harmonogram z pokojami w Xiaomi Home).", device.label))
        end

        local comp = device.profile.components.syncRooms
        if comp then device:emit_component_event(comp, capabilities.momentary.push()) end

    elseif comp_id == "dock" then
        log.info("Sending Viomi vacuum to dock")
        viomi.return_to_dock(device, ip, token)
        local comp = device.profile.components.dock
        if comp then
            device:emit_component_event(comp, capabilities.momentary.push())
        end
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.homing())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
        device.thread:call_with_delay(2, function()
            pcall(poll_device_status, device)
        end)

    elseif comp_id == "locate" then
        log.info("Triggering locator chime on Viomi vacuum")
        viomi.locate(device, ip, token)
        local comp = device.profile.components.locate
        if comp then
            device:emit_component_event(comp, capabilities.momentary.push())
        end
    end
end

local function refresh_handler(_, device, _)
    pcall(poll_device_status, device)
end

-- Lifecycle handlers

local function device_added(_, device)
    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.battery.battery({ value = 0 }))
    device:emit_event(capabilities.fanSpeed.fanSpeed(viomi.FAN_SPEEDS.STANDARD))
    device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.off())
    device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
    device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    reset_room_switches(device)
end

local function device_init(_, device)
    device:online()

    -- Inicjalizacja przełączników pokojów
    for _, rc in ipairs(ROOM_COMPONENTS) do
        local comp = device.profile.components[rc.key]
        if comp then
            local is_on = device:get_field("room_state_" .. rc.key) or false
            if is_on then
                device:emit_component_event(comp, capabilities.switch.switch.on())
            else
                device:emit_component_event(comp, capabilities.switch.switch.off())
            end
        end
    end

    local ip, token = get_device_config(device)
    if ip and token then
        start_polling_timer(device)
        pcall(poll_device_status, device)
    else
        log.info(string.format("[%s] Device initialized. Waiting for IP and Token preferences.", device.label))
    end
end

local function device_removed(_, device)
    stop_polling_timer(device)
end

local function device_info_changed(driver, device, _, args)
    if not args.old_st_store or not args.old_st_store.preferences then
        return
    end

    local old = args.old_st_store.preferences
    local new = device.preferences

    if old.createDev == false and new.createDev == true then
        discovery.create_device(driver)
    end

    if old.ipAddress ~= new.ipAddress or old.token ~= new.token or old.pollingInterval ~= new.pollingInterval then
        stop_polling_timer(device)

        local ip, token = get_device_config(device)
        if ip and token then
            start_polling_timer(device)
            pcall(poll_device_status, device)
        end
    end
end

local driver = Driver("viomi-vacuum-v8", {
    discovery = discovery.handle_discovery,
    lifecycle_handlers = {
        added = device_added,
        init = device_init,
        removed = device_removed,
        infoChanged = device_info_changed
    },
    capability_handlers = {
        [capabilities.switch.ID] = {
            [capabilities.switch.commands.on.NAME] = switch_on_handler,
            [capabilities.switch.commands.off.NAME] = switch_off_handler
        },
        [capabilities.refresh.ID] = {
            [capabilities.refresh.commands.refresh.NAME] = refresh_handler
        },
        [capabilities.robotCleanerMovement.ID] = {
            [capabilities.robotCleanerMovement.commands.setRobotCleanerMovement.NAME] = movement_handler
        },
        [capabilities.robotCleanerCleaningMode.ID] = {
            [capabilities.robotCleanerCleaningMode.commands.setRobotCleanerCleaningMode.NAME] = cleaning_mode_handler
        },
        [capabilities.robotCleanerTurboMode.ID] = {
            [capabilities.robotCleanerTurboMode.commands.setRobotCleanerTurboMode.NAME] = turbo_mode_handler
        },
        [capabilities.fanSpeed.ID] = {
            [capabilities.fanSpeed.commands.setFanSpeed.NAME] = fan_speed_handler
        },
        [capabilities.momentary.ID] = {
            [capabilities.momentary.commands.push.NAME] = momentary_handler
        }
    }
})

driver:run()
