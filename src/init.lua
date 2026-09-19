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

local ROOM_DEF = {
    { key = "living",   pref = "room1Name", default_name = "Salon",     default_id = 11 },
    { key = "dining",   pref = "room2Name", default_name = "Jadalnia",   default_id = 12 },
    { key = "room1",    pref = "room3Name", default_name = "Pokój 1",    default_id = 13 },
    { key = "kitchen",  pref = "room4Name", default_name = "Kuchnia",    default_id = 10 },
    { key = "hallway",  pref = "room5Name", default_name = "Korytarz",   default_id = 14 },
    { key = "bedroom",  pref = "room6Name", default_name = "Sypialnia",  default_id = 15 },
    { key = "bathroom", pref = "room7Name", default_name = "Łazienka",   default_id = 16 }
}

local ROOM_BY_KEY = {}
for _, r in ipairs(ROOM_DEF) do
    ROOM_BY_KEY[r.key] = r
end

local function get_device_config(device)
    local ip = device.preferences.ipAddress
    local raw_token = device.preferences.token
    local token = miio.sanitize_token(raw_token)

    if ip and ip ~= "" and token then
        return ip, token
    end
    return nil, nil
end

local function get_room_name(device, room_def)
    if room_def.pref and device.preferences[room_def.pref] and device.preferences[room_def.pref] ~= "" then
        return device.preferences[room_def.pref]
    end
    return room_def.default_name
end

local function emit_room_selector_event(device, attr_name, value)
    local cap = capabilities["fluteriver09555.vacuumRoomSelector"]
    if cap and cap[attr_name] then
        device:emit_event(cap[attr_name]({ value = value }))
    else
        device:emit_event({
            capability = "fluteriver09555.vacuumRoomSelector",
            component = "main",
            attribute = attr_name,
            value = value
        })
    end
end

local function update_selected_rooms_display(device, last_toggled_key, was_added)
    local sel = device:get_field("selected_rooms") or {}
    if #sel == 0 then
        emit_room_selector_event(device, "lastSelectedRoom", "all")
        emit_room_selector_event(device, "selectedRooms", "Wszystkie pokoje (całe mieszkanie)")
        log.info(string.format("[%s] Wybór pokojów: Wszystkie pokoje", device.label))
    else
        local names = {}
        for _, k in ipairs(sel) do
            local r = ROOM_BY_KEY[k]
            local name = r and get_room_name(device, r) or k
            table.insert(names, name)
        end
        local display_str = table.concat(names, ", ")
        emit_room_selector_event(device, "selectedRooms", display_str)

        local active_key = last_toggled_key
        if not was_added or not active_key then
            active_key = sel[#sel]
        end
        emit_room_selector_event(device, "lastSelectedRoom", active_key)
        log.info(string.format("[%s] Wybór pokojów: %s (przycisk aktywny: %s)", device.label, display_str, tostring(active_key)))
    end
end

local function sync_rooms_from_vacuum(device)
    local ip, token = get_device_config(device)
    local detected = {}
    if ip and token then
        detected = viomi.get_rooms(device, ip, token) or {}
        log.info(string.format("[%s] viomi.get_rooms zwróciło %d pomieszczeń", device.label, #detected))
    end

    local room_id_map = {}
    local available_keys = {}

    if #detected > 0 then
        local matched = {}
        for _, det in ipairs(detected) do
            local det_name_lower = (det.name or ""):lower()
            local found_key = nil
            for _, r in ipairs(ROOM_DEF) do
                if not matched[r.key] then
                    local r_name_lower = get_room_name(device, r):lower()
                    if det_name_lower == r_name_lower or det_name_lower:find(r.key) then
                        found_key = r.key
                        break
                    end
                end
            end
            if not found_key then
                for _, r in ipairs(ROOM_DEF) do
                    if not matched[r.key] then
                        found_key = r.key
                        break
                    end
                end
            end

            if found_key then
                matched[found_key] = true
                room_id_map[found_key] = det.id
                table.insert(available_keys, found_key)
            end
        end
    else
        log.info(string.format("[%s] Brak harmonogramów w odkurzaczu - załadowano domyślne pomieszczenia (Salon, Jadalnia, Pokój 1, Kuchnia)", device.label))
        local default_keys = { "living", "dining", "room1", "kitchen" }
        for _, k in ipairs(default_keys) do
            local r = ROOM_BY_KEY[k]
            if r then
                room_id_map[k] = r.default_id
                table.insert(available_keys, k)
            end
        end
    end

    device:set_field("detected_room_ids", room_id_map)
    device:set_field("available_room_keys", available_keys)

    -- Dynamiczna lista przycisków w sekcji Zakres:
    -- [ Wszystko ] [ Pokój 1 ] [ Pokój 2 ] ... [ Wczytaj pomieszczenia ]
    local supported = { "all" }
    for _, k in ipairs(available_keys) do
        table.insert(supported, k)
    end
    table.insert(supported, "sync")

    emit_room_selector_event(device, "supportedRooms", supported)
    log.info(string.format("[%s] Zaktualizowano supportedRooms: %s", device.label, table.concat(supported, ", ")))

    local sel = device:get_field("selected_rooms") or {}
    if #sel == 0 then
        emit_room_selector_event(device, "lastSelectedRoom", "all")
        emit_room_selector_event(device, "selectedRooms", "Wszystkie pokoje (całe mieszkanie)")
    else
        update_selected_rooms_display(device)
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
        device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.cleaning())
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

    -- Resetowanie wyboru pokojów po zakończeniu sprzątania i powrocie do bazy
    if prev_state and (prev_state == viomi.RUN_STATE.CLEANING or prev_state == viomi.RUN_STATE.VACUUM_MOP or prev_state == viomi.RUN_STATE.MOP_ONLY or prev_state == viomi.RUN_STATE.RETURNING) then
        if rs == viomi.RUN_STATE.DOCKED or rs == viomi.RUN_STATE.IDLE_0 or rs == viomi.RUN_STATE.IDLE_1 then
            log.info(string.format("[%s] Sprzątanie zakończone. Resetowanie wyboru pokojów na 'Wszystko'...", device.label))
            device:set_field("selected_rooms", {})
            emit_room_selector_event(device, "lastSelectedRoom", "all")
            emit_room_selector_event(device, "selectedRooms", "Wszystkie pokoje (całe mieszkanie)")
        end
    end

    -- 3. Prędkość wentylatora & Turbo
    if status.suction_grade and status.suction_grade >= 0 and status.suction_grade <= 3 then
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

    local sel = device:get_field("selected_rooms") or {}
    local detected = device:get_field("detected_room_ids") or {}

    local ids = {}
    local names = {}
    for _, k in ipairs(sel) do
        local r_def = ROOM_BY_KEY[k]
        local r_id = detected[k] or (r_def and r_def.default_id)
        if r_id then
            table.insert(ids, r_id)
            local name = r_def and get_room_name(device, r_def) or k
            table.insert(names, name)
        end
    end

    local cache = device:get_field(STATUS_CACHE)
    local mop_pref = device.preferences.mopMode

    if #ids == 0 then
        log.info(string.format("[%s] Start: Odkurzanie całego mieszkania", device.label))
        viomi.clean_rooms(device, ip, token, cache, mop_pref, nil)
    else
        log.info(string.format("[%s] Start: Odkurzanie %d wybranych pokojów w kolejności: %s (ID: %s)",
            device.label, #ids, table.concat(names, " -> "), table.concat(ids, ", ")))
        viomi.clean_rooms(device, ip, token, cache, mop_pref, ids)
    end

    device:emit_event(capabilities.switch.switch.on())
    device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.auto())
    device:emit_event(capabilities.robotCleanerOperatingState.operatingState.running())
    device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.cleaning())

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

    device:set_field("selected_rooms", {})
    emit_room_selector_event(device, "lastSelectedRoom", "all")
    emit_room_selector_event(device, "selectedRooms", "Wszystkie pokoje (całe mieszkanie)")

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

-- Handlery komend SmartThings

local function switch_on_handler(_, device, _)
    start_vacuum_cleaning(device)
end

local function switch_off_handler(_, device, _)
    local off_action = device.preferences.switchOffAction or "dock"
    if off_action == "stop" then
        stop_vacuum(device)
    elseif off_action == "pause" then
        pause_vacuum(device)
    else
        dock_vacuum(device)
    end
end

local function movement_handler(_, device, command)
    local move = command.args.mode or command.args.movement
    log.info(string.format("[%s] movement_handler: %s", device.label, tostring(move)))
    if move == "cleaning" then
        start_vacuum_cleaning(device)
    elseif move == "pause" then
        pause_vacuum(device)
    elseif move == "homing" or move == "charging" then
        dock_vacuum(device)
    elseif move == "idle" or move == "powerOff" then
        stop_vacuum(device)
    end
end

local function op_state_start_handler(_, device, _)
    start_vacuum_cleaning(device)
end

local function op_state_pause_handler(_, device, _)
    pause_vacuum(device)
end

local function op_state_gohome_handler(_, device, _)
    dock_vacuum(device)
end

local function cleaning_mode_handler(_, device, command)
    local mode = command.args.mode
    if mode == "auto" or mode == "repeat" then
        start_vacuum_cleaning(device)
    elseif mode == "stop" then
        stop_vacuum(device)
    end
end

local function turbo_mode_handler(_, device, command)
    local ip, token = get_device_config(device)
    if not ip or not token then return end

    local mode = command.args.mode
    if mode == "on" then
        viomi.set_fan_speed(device, ip, token, viomi.FAN_SPEEDS.TURBO)
        device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.on())
    else
        viomi.set_fan_speed(device, ip, token, viomi.FAN_SPEEDS.STANDARD)
        device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.off())
    end
end

local function custom_dock_handler(_, device, _)
    dock_vacuum(device)
end

local function custom_locate_handler(_, device, _)
    local ip, token = get_device_config(device)
    if not ip or not token then return end
    log.info(string.format("[%s] Akcja: Zlokalizuj odkurzacz (sygnał dźwiękowy)", device.label))
    viomi.locate(device, ip, token)
end

local function custom_select_room_handler(_, device, command)
    local room = command.args.room or command.args[1]
    if type(room) == "table" and room.value then room = room.value end
    log.info(string.format("[%s] custom_select_room_handler: %s", device.label, tostring(room)))

    if not room or room == "all" then
        device:set_field("selected_rooms", {})
        update_selected_rooms_display(device)
    elseif room == "sync" then
        sync_rooms_from_vacuum(device)
    else
        -- Przełączenie (toggle) wybranego pokoju
        local sel = device:get_field("selected_rooms") or {}
        local exists = false
        local new_sel = {}

        for _, k in ipairs(sel) do
            if k == room then
                exists = true
            else
                table.insert(new_sel, k)
            end
        end

        if not exists then
            table.insert(new_sel, room)
        end

        device:set_field("selected_rooms", new_sel)
        update_selected_rooms_display(device, room, not exists)
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
    device:emit_event(capabilities.robotCleanerTurboMode.robotCleanerTurboMode.off())
    device:emit_event(capabilities.robotCleanerMovement.robotCleanerMovement.idle())
    device:emit_event(capabilities.robotCleanerCleaningMode.robotCleanerCleaningMode.stop())
    device:emit_event(capabilities.robotCleanerOperatingState.operatingState.docked())

    device:set_field("selected_rooms", {})
    emit_room_selector_event(device, "supportedRooms", { "all", "sync" })
    emit_room_selector_event(device, "lastSelectedRoom", "all")
    emit_room_selector_event(device, "selectedRooms", "Wszystkie pokoje (całe mieszkanie)")
end

local function device_init(_, device)
    device:online()

    pcall(function()
        device:try_update_metadata({ profile = "viomi-vacuum-v8" })
    end)

    device:emit_event(capabilities.robotCleanerOperatingState.supportedOperatingStateCommands({
        "start", "pause", "goHome"
    }))
    device:emit_event(capabilities.robotCleanerOperatingState.supportedOperatingStates({
        "stopped", "running", "paused", "seekingCharger", "charging", "docked"
    }))

    -- Inicjalizacja zakresu (początkowo tylko Wszystko i Wczytaj pomieszczenia, chyba że już załadowano)
    local available_keys = device:get_field("available_room_keys")
    if available_keys and #available_keys > 0 then
        local supported = { "all" }
        for _, k in ipairs(available_keys) do
            table.insert(supported, k)
        end
        table.insert(supported, "sync")
        emit_room_selector_event(device, "supportedRooms", supported)
    else
        emit_room_selector_event(device, "supportedRooms", { "all", "sync" })
    end

    local sel = device:get_field("selected_rooms") or {}
    if #sel == 0 then
        emit_room_selector_event(device, "lastSelectedRoom", "all")
        emit_room_selector_event(device, "selectedRooms", "Wszystkie pokoje (całe mieszkanie)")
    else
        update_selected_rooms_display(device)
    end

    local ip, token = get_device_config(device)
    if ip and token then
        start_polling_timer(device)
        pcall(poll_device_status, device)
    else
        log.info(string.format("[%s] Urządzenie zainicjalizowane. Oczekiwanie na konfigurację IP i Tokena w preferencjach.", device.label))
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

    update_selected_rooms_display(device)
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
        [capabilities.robotCleanerOperatingState.ID] = {
            [capabilities.robotCleanerOperatingState.commands.start.NAME] = op_state_start_handler,
            [capabilities.robotCleanerOperatingState.commands.pause.NAME] = op_state_pause_handler,
            [capabilities.robotCleanerOperatingState.commands.goHome.NAME] = op_state_gohome_handler
        },
        ["fluteriver09555.vacuumDock"] = {
            ["dock"] = custom_dock_handler
        },
        ["fluteriver09555.vacuumLocate"] = {
            ["locate"] = custom_locate_handler
        },
        ["fluteriver09555.vacuumRoomSelector"] = {
            ["selectRoom"] = custom_select_room_handler
        }
    }
})

driver:run()
