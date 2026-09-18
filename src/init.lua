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

-- Custom capabilities
local VACUUM_DOCK_CAP = capabilities["fluteriver09555.vacuumDock"]
local ROOM_SELECTOR_CAP = capabilities["fluteriver09555.vacuumRoomSelector"]
local VACUUM_LOCATE_CAP = capabilities["fluteriver09555.vacuumLocate"]

local ROOM_DEF = {
    { key = "kitchen",  pref = "room1Name", default_name = "Kuchnia",     default_id = 10 },
    { key = "living",   pref = "room2Name", default_name = "Salon",       default_id = 11 },
    { key = "hallway",  pref = "room3Name", default_name = "Korytarz",    default_id = 12 },
    { key = "bedroom",  pref = "room4Name", default_name = "Sypialnia",   default_id = 13 },
    { key = "kate",     pref = "room5Name", default_name = "Pokój Kasi",  default_id = 14 },
    { key = "maciek",   pref = "room6Name", default_name = "Pokój Maćka", default_id = 15 },
    { key = "bathroom", pref = "room7Name", default_name = "Łazienka",    default_id = 16 },
    { key = "room8",    pref = "room8Name", default_name = "Pokój 8",     default_id = 17 }
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

local function update_room_selector(device, last_action)
    local selected = device:get_field("selected_room_keys") or {}
    local names = {}
    local count = 0

    for _, r in ipairs(ROOM_DEF) do
        if selected[r.key] then
            count = count + 1
            local custom_name = device.preferences[r.pref]
            local name = (custom_name and custom_name ~= "") and custom_name or r.default_name
            table.insert(names, name)
        end
    end

    local summary
    if count == 0 then
        summary = "Brak (całe mieszkanie)"
    elseif count == #ROOM_DEF then
        summary = "Wszystkie pokoje"
    else
        summary = table.concat(names, ", ")
    end

    if ROOM_SELECTOR_CAP then
        device:emit_event(ROOM_SELECTOR_CAP.selectedRooms({ value = summary }))
        if last_action then
            device:emit_event(ROOM_SELECTOR_CAP.lastSelectedRoom({ value = last_action }))
        end
    end
end

local function emit_vacuum_status(device, status)
    if not status then return end

    local prev_cache = device:get_field(STATUS_CACHE)
    local prev_state = prev_cache and prev_cache.run_state

    -- 1. Poziom baterii
    if status.battary_life and status.battary_life >= 0 and status.battary_life <= 100 then
        device:emit_event(capabilities.battery.battery({ value = status.battary_life }))
    end

    -- 2. Stan pracy & Przełącznik & Ruch & OperatingState
    local rs = status.run_state
    if rs == viomi.RUN_STATE.CLEANING or rs == viomi.RUN_STATE.VACUUM_MOP or rs == viomi.RUN_STATE.MOP_ONLY then
        device:emit_event(capabilities.switch.switch.on())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.auto())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
        device:emit_event(capabilities.robotCleanerOperatingState.operatingState.running())
    elseif rs == viomi.RUN_STATE.PAUSED then
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.part())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.pause())
        device:emit_event(capabilities.robotCleanerOperatingState.operatingState.paused())
    elseif rs == viomi.RUN_STATE.RETURNING then
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.homing())
        device:emit_event(capabilities.robotCleanerOperatingState.operatingState.seekingCharger())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    elseif rs == viomi.RUN_STATE.DOCKED then
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.charging())
        device:emit_event(capabilities.robotCleanerOperatingState.operatingState.charging())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    else -- IDLE
        device:emit_event(capabilities.switch.switch.off())
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
        device:emit_event(capabilities.robotCleanerOperatingState.operatingState.docked())
        device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    end

    -- Resetowanie zaznaczenia pokojów po zakończeniu sprzątania i powrocie do bazy
    if prev_state and (prev_state == viomi.RUN_STATE.CLEANING or prev_state == viomi.RUN_STATE.VACUUM_MOP or prev_state == viomi.RUN_STATE.MOP_ONLY or prev_state == viomi.RUN_STATE.RETURNING) then
        if rs == viomi.RUN_STATE.DOCKED or rs == viomi.RUN_STATE.IDLE_0 or rs == viomi.RUN_STATE.IDLE_1 then
            log.info(string.format("[%s] Sprzątanie zakończone. Resetowanie zaznaczenia pokojów...", device.label))
            device:set_field("selected_room_keys", {})
            update_room_selector(device, "none")
        end
    end

    -- 3. Prędkość wentylatora & Turbo
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

-- Akcje sterowania odkurzaczem

local function start_vacuum_cleaning(device)
    local ip, token = get_device_config(device)
    if not ip or not token then
        log.error("Nie można uruchomić odkurzacza: brak IP lub Tokena")
        return
    end

    local selected = device:get_field("selected_room_keys") or {}
    local ids = {}
    local detected = device:get_field("detected_room_ids") or {}

    for _, r in ipairs(ROOM_DEF) do
        if selected[r.key] then
            local r_id = detected[r.key] or r.default_id
            table.insert(ids, r_id)
        end
    end

    local cache = device:get_field(STATUS_CACHE)
    local mop_pref = device.preferences.mopMode

    if #ids == 0 or #ids == #ROOM_DEF then
        log.info(string.format("[%s] Start: Odkurzanie całego mieszkania", device.label))
        viomi.clean_rooms(device, ip, token, cache, mop_pref, nil)
    else
        log.info(string.format("[%s] Start: Odkurzanie %d wybranych pokojów (ID: %s)",
            device.label, #ids, table.concat(ids, ", ")))
        viomi.clean_rooms(device, ip, token, cache, mop_pref, ids)
    end

    device:emit_event(capabilities.switch.switch.on())
    device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.auto())
    device:emit_event(capabilities.robotCleanerOperatingState.operatingState.running())
    device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())

    device.thread:call_with_delay(2, function()
        pcall(poll_device_status, device)
    end)
end

local function dock_vacuum(device)
    local ip, token = get_device_config(device)
    if not ip or not token then
        log.error("Nie można odesłać do bazy: brak IP lub Tokena")
        return
    end

    log.info(string.format("[%s] Akcja: Powrót do bazy", device.label))
    viomi.return_to_dock(device, ip, token)

    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.homing())
    device:emit_event(capabilities.robotCleanerOperatingState.operatingState.seekingCharger())
    device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())

    device:set_field("selected_room_keys", {})
    update_room_selector(device, "none")

    device.thread:call_with_delay(2, function()
        pcall(poll_device_status, device)
    end)
end

local function pause_vacuum(device)
    local ip, token = get_device_config(device)
    if not ip or not token then return end

    log.info(string.format("[%s] Akcja: Wstrzymanie odkurzacza (Pauza)", device.label))
    local cache = device:get_field(STATUS_CACHE)
    viomi.pause_cleaning(device, ip, token, cache)

    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.pause())
    device:emit_event(capabilities.robotCleanerOperatingState.operatingState.paused())

    device.thread:call_with_delay(2, function()
        pcall(poll_device_status, device)
    end)
end

local function stop_vacuum(device)
    local ip, token = get_device_config(device)
    if not ip or not token then return end

    log.info(string.format("[%s] Akcja: Zatrzymanie odkurzacza w miejscu", device.label))
    local cache = device:get_field(STATUS_CACHE)
    viomi.stop_cleaning(device, ip, token, cache)

    device:emit_event(capabilities.switch.switch.off())
    device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
    device:emit_event(capabilities.robotCleanerOperatingState.operatingState.stopped())
    device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())

    device.thread:call_with_delay(2, function()
        pcall(poll_device_status, device)
    end)
end

-- Obsługa przełącznika głównego (Switch ON/OFF)
local function switch_on_handler(_, device, _)
    start_vacuum_cleaning(device)
end

local function switch_off_handler(_, device, _)
    local off_action = device.preferences.switchOffAction or "dock"
    if off_action == "stop" then
        stop_vacuum(device)
    elseif off_action == "pause" then
        pause_vacuum(device)
    else -- "dock"
        dock_vacuum(device)
    end
end

-- Obsługa custom capability: Wybór pokoi (fluteriver09555.vacuumRoomSelector)
local function select_room_handler(_, device, command)
    local room = command.args.room
    log.info(string.format("[%s] Interakcja z wyborem pokoju: %s", device.label, tostring(room)))

    local selected = device:get_field("selected_room_keys") or {}

    if room == "clear" then
        selected = {}
        device:set_field("selected_room_keys", selected)
        update_room_selector(device, "clear")

    elseif room == "all" then
        selected = {}
        for _, r in ipairs(ROOM_DEF) do
            selected[r.key] = true
        end
        device:set_field("selected_room_keys", selected)
        update_room_selector(device, "all")

    elseif room == "start" then
        update_room_selector(device, "start")
        start_vacuum_cleaning(device)

    else
        -- Przełączanie stanu pojedynczego pokoju (toggle)
        if selected[room] then
            selected[room] = nil
        else
            selected[room] = true
        end
        device:set_field("selected_room_keys", selected)
        update_room_selector(device, room)
    end
end

-- Obsługa custom capability: Powrót do bazy (fluteriver09555.vacuumDock)
local function custom_dock_handler(_, device, _)
    dock_vacuum(device)
end

-- Obsługa custom capability: Zlokalizuj odkurzacz (fluteriver09555.vacuumLocate)
local function custom_locate_handler(_, device, _)
    local ip, token = get_device_config(device)
    if not ip or not token then return end
    log.info(string.format("[%s] Akcja: Zlokalizuj odkurzacz (sygnał dźwiękowy)", device.label))
    viomi.locate(device, ip, token)
end

-- Obsługa standardowego robotCleanerOperatingState (Start, Pause, GoHome)
local function op_state_start_handler(_, device, _)
    start_vacuum_cleaning(device)
end

local function op_state_pause_handler(_, device, _)
    pause_vacuum(device)
end

local function op_state_gohome_handler(_, device, _)
    dock_vacuum(device)
end

-- Obsługa robotCleanerMovement
local function movement_handler(_, device, command)
    local move = command.args.movement
    if move == "homing" or move == "charging" then
        dock_vacuum(device)
    elseif move == "idle" then
        stop_vacuum(device)
    elseif move == "pause" then
        pause_vacuum(device)
    end
end

-- Obsługa robotCleanerCleaningMode
local function cleaning_mode_handler(_, device, command)
    local mode = command.args.mode
    if mode == "auto" or mode == "repeat" then
        start_vacuum_cleaning(device)
    elseif mode == "stop" then
        stop_vacuum(device)
    end
end

-- Obsługa regulacji mocy ssania (Fan Speed & Turbo)
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

local function refresh_handler(_, device, _)
    pcall(function()
        log.info(string.format('[%s] Wywołanie try_update_metadata dla profilu viomi-vacuum-v8', device.label))
        local success, err = device:try_update_metadata({ profile = 'viomi-vacuum-v8' })
        log.info(string.format('[%s] try_update_metadata wynik: %s, err: %s', device.label, tostring(success), tostring(err)))
    end)
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
    device:emit_event(capabilities.robotCleanerOperatingState.operatingState.docked())

    device:set_field("selected_room_keys", {})
    update_room_selector(device, "none")
end

local function device_init(_, device)
    device:online()

    pcall(function()
        device:try_update_metadata({ profile = "viomi-vacuum-v8" })
    end)

    -- Rejestracja obsługiwanych stanów i komend dla robotCleanerOperatingState
    device:emit_event(capabilities.robotCleanerOperatingState.supportedOperatingStateCommands({
        "start", "pause", "goHome"
    }))
    device:emit_event(capabilities.robotCleanerOperatingState.supportedOperatingStates({
        "stopped", "running", "paused", "seekingCharger", "charging", "docked"
    }))

    -- Inicjalizacja stanu wyboru pokoi
    local selected = device:get_field("selected_room_keys") or {}
    device:set_field("selected_room_keys", selected)
    update_room_selector(device, "none")

    local ip, token = get_device_config(device)
    if ip and token then
        start_polling_timer(device)
        pcall(poll_device_status, device)

        -- Próba automatycznego pobrania mapy pokoi z harmonogramów
        device.thread:call_with_delay(3, function()
            local detected = viomi.get_rooms(device, ip, token)
            if detected and #detected > 0 then
                log.info(string.format("[%s] Pomyślnie zsynchronizowano %d pokojów z odkurzacza", device.label, #detected))
                local room_id_map = {}
                for i, r in ipairs(detected) do
                    if i <= #ROOM_DEF then
                        room_id_map[ROOM_DEF[i].key] = r.id
                    end
                end
                device:set_field("detected_room_ids", room_id_map)
            end
        end)
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

    -- Aktualizacja nazw pokoi w interfejsie jeśli zmieniono preferencje
    update_room_selector(device, nil)

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
        [capabilities.robotCleanerOperatingState.ID] = {
            [capabilities.robotCleanerOperatingState.commands.start.NAME] = op_state_start_handler,
            [capabilities.robotCleanerOperatingState.commands.pause.NAME] = op_state_pause_handler,
            [capabilities.robotCleanerOperatingState.commands.goHome.NAME] = op_state_gohome_handler
        },
        ["fluteriver09555.vacuumDock"] = {
            ["dock"] = custom_dock_handler
        },
        ["fluteriver09555.vacuumRoomSelector"] = {
            ["selectRoom"] = select_room_handler
        },
        ["fluteriver09555.vacuumLocate"] = {
            ["locate"] = custom_locate_handler
        }
    }
})

driver:run()
