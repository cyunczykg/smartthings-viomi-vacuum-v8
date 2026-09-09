local discovery = {}

function discovery.create_device(driver)
    return driver:try_create_device({
        type = "LAN",
        device_network_id = "miio-viomi-vacuum-v8-" .. os.time(),
        label = "Viomi Vacuum V8",
        profile = "viomi-vacuum-v8",
        manufacturer = "Viomi",
        model = "viomi.vacuum.v8",
        vendor_provided_label = "Viomi Vacuum V8",
    })
end

function discovery.handle_discovery(driver, opts, cont)
    if #driver:get_devices() == 0 then
        discovery.create_device(driver)
    end
end

return discovery
