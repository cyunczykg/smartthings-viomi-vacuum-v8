local socket = require "socket"
local json = require "st.json"
local security = require "st.security"
local md5 = require "md5"

local miio = {}

local PORT = 54321
local HEADER_SIZE = 32
local DEV_ID = "miio_dev_id"
local TIME_OFFSET = "miio_time_offset"
local MESSAGE_ID = "miio_message_id"
local HELLO_PACKET = "\x21\x31\x00\x20" .. string.rep("\xff", 28)
local AES_OPTIONS = { cipher = "aes128-cbc", padding = true }

local function sanitize_token(token)
    if not token then return nil end
    local clean = token:gsub("%s+", ""):lower()
    if #clean == 32 and clean:match("^%x+$") then
        return clean
    end
    return nil
end

local function get_crypto_params(token)
    local clean_token = sanitize_token(token)
    if not clean_token then
        error("Invalid miIO token. Expected 32-character hex string.")
    end
    local token_bin = md5.hex_to_bin(clean_token)
    local key = md5.sum(token_bin)
    local iv = md5.sum(key .. token_bin)
    return token_bin, key, iv
end

local function create_udp(timeout)
    local udp = socket.udp()
    if not udp then error("Failed to create UDP socket") end
    udp:setsockname("0.0.0.0", 0)
    udp:settimeout(timeout or 2.5)
    return udp
end

local function clear_device_cache(device)
    device:set_field(DEV_ID, nil)
    device:set_field(TIME_OFFSET, nil)
end

local function next_message_id(device)
    local message_id = ((device:get_field(MESSAGE_ID) or 0) % 9999) + 1
    device:set_field(MESSAGE_ID, message_id)
    return message_id
end

-- Hello handshake with up to 3 attempts
local function send_hello(ip)
    local udp = create_udp(2.0)
    local response
    local last_err

    for attempt = 1, 3 do
        local sent, err = udp:sendto(HELLO_PACKET, ip, PORT)
        if sent then
            response, err = udp:receive()
            if response and #response >= 16 then
                break
            end
        end
        last_err = err
        if attempt < 3 then socket.sleep(0.2) end
    end
    udp:close()

    if not response or #response < 16 then
        error("Device did not respond to Hello packet: " .. tostring(last_err or "timeout"))
    end

    local device_id = string.unpack(">I4", response:sub(9, 12))
    local device_time = string.unpack(">I4", response:sub(13, 16))
    local time_offset = os.time() - device_time

    return device_id, time_offset
end

local function create_message(device, ip, token, method, params, force_hello)
    if device:get_field(DEV_ID) == nil or force_hello then
        local ok, dev_id, time_off = pcall(send_hello, ip)
        if not ok then
            clear_device_cache(device)
            error("miIO Handshake failed: " .. tostring(dev_id))
        end
        device:set_field(DEV_ID, dev_id)
        device:set_field(TIME_OFFSET, time_off)
    end

    local payload = json.encode({
        id = next_message_id(device),
        method = method,
        params = params or {}
    }) .. '\x00'

    local token_bin, key, iv = get_crypto_params(token)

    local opts = { cipher = AES_OPTIONS.cipher, iv = iv, padding = AES_OPTIONS.padding }
    local encrypted = security.encrypt_bytes(payload, key, opts)

    local device_id = device:get_field(DEV_ID)
    local timestamp = os.time() - (device:get_field(TIME_OFFSET) or 0)
    local length = HEADER_SIZE + #encrypted
    local header = string.pack(">c2 I2 I4 I4 I4", "\x21\x31", length, 0, device_id, timestamp) .. token_bin

    local checksum = md5.sum(header .. encrypted)
    header = header:sub(1, 16) .. checksum

    return header .. encrypted, key, iv
end

local function send_command_once(device, ip, token, method, params, force_hello)
    local udp = create_udp(3.0)
    local message, key, iv = create_message(device, ip, token, method, params, force_hello)

    local sent, err = udp:sendto(message, ip, PORT)
    if not sent then
        udp:close()
        error("Failed to send UDP packet: " .. tostring(err))
    end

    local response, rcv_err = udp:receive()
    udp:close()

    if not response then
        error("No response received from " .. tostring(ip) .. ": " .. tostring(rcv_err or "timeout"))
    end

    if #response <= HEADER_SIZE then
        error("Received packet too short (" .. #response .. " bytes)")
    end

    local encrypted_data = response:sub(HEADER_SIZE + 1)
    local opts = { cipher = AES_OPTIONS.cipher, iv = iv, padding = AES_OPTIONS.padding }
    local decrypted = security.decrypt_bytes(encrypted_data, key, opts)
    if not decrypted then
        error("Failed to decrypt miIO response payload")
    end

    decrypted = decrypted:gsub("%z+$", "")
    local ok, decoded = pcall(json.decode, decrypted)
    if not ok then
        error("Failed to parse JSON response: " .. tostring(decoded))
    end

    return decoded
end

local function send_with_retry(device, ip, token, method, params)
    local ok, response = pcall(send_command_once, device, ip, token, method, params, false)
    if ok and response then
        return response
    end

    -- Retry with fresh handshake
    clear_device_cache(device)
    socket.sleep(0.3)
    local ok2, response2 = pcall(send_command_once, device, ip, token, method, params, true)
    if ok2 and response2 then
        return response2
    end
    return nil
end

function miio.cmd(device, ip, token, method, params)
    return send_with_retry(device, ip, token, method, params)
end

function miio.get_prop(device, ip, token, props)
    local query_params
    if type(props) == "table" then
        query_params = props
    else
        query_params = { props }
    end

    local response = send_with_retry(device, ip, token, "get_prop", query_params)
    if response and response.result then
        if type(props) == "table" then
            return response.result
        else
            return response.result[1]
        end
    end
    return nil
end

function miio.set_prop(device, ip, token, method, params)
    local response = send_with_retry(device, ip, token, method, params)
    if response and response.result then
        local r = response.result
        if type(r) == "table" and (r[1] == "ok" or r[1] == 0) then
            return true
        elseif r == "ok" or r == 0 then
            return true
        end
    end
    return false
end

miio.sanitize_token = sanitize_token

return miio
