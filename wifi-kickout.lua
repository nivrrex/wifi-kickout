#!/usr/bin/lua
require "ubus"

function log_sys(msg,logfile)
    local reset = string.format("%s[%sm",string.char(27), tostring(0))
    local green = string.format("%s[%sm",string.char(27), tostring(32))
    local message = string.format("%s%s [info] %s %s",green,os.date("%Y-%m-%d %H:%M:%S"),msg,reset)
    if logfile == nil then
        print(message)
    else
        logfile:write(message .. "\n")
    end
    io.flush()
end
function ubus.start()
    conn = ubus.connect()
    if not conn then error("Failed to connect to ubusd.") end
end
function ubus.stop()
    conn:close()
end
function get_wlan_list()
    data = {}
    local status = conn:call("iwinfo", "devices", {})
    for _, v in pairs(status) do
        for _,wlan in pairs(v) do
            table.insert(data,wlan)
        end
    end
    return data
end
function check_mhz(wlan)
    local status = conn:call("iwinfo","freqlist",{device=wlan})
    for _, v in pairs(status) do
        for _,freqlist in pairs(v) do
            if freqlist["channel"] == 1 then return 2.4
            elseif freqlist["channel"] == 36 then return 5
            else return -1 end
        end
    end
end
function get_mac_list(wlan)
    data = {}
    local status = conn:call("iwinfo","assoclist",{device=wlan})
    for _, v in pairs(status) do
        for _,client in pairs(v) do
            table.insert(data,client["mac"])
        end
    end
    return data
end
function get_signal(wlan, mac_client)
    local signal = 0
    local status = conn:call("iwinfo","assoclist",{device=wlan,mac=mac_client})
    if status ~= nil then
        for i, v in pairs(status) do
            if i ~= "results" then
                if string.upper(status["mac"]) == string.upper(mac_client) then
                    signal = status["signal_avg"]
                end
            end
        end
    end
    return signal
end
function kick_out(wlan, mac_client, ban_time_num)
    if mac_client == nil then return end
    local status = conn:call("hostapd."..wlan,"del_client",{addr=mac_client,reason=5,deauth=true,ban_time=ban_time_num})
    if status ~= nil then print("del client:",status) end
    local status = conn:call("hostapd."..wlan,"list_bans",{})
    if status ~= nil then
        for _, v in pairs(status) do
            for _,client in pairs(v) do
                print("list bans client:",client)
            end
        end
    end
end
function table.match(tbl,value)
    for k,v in ipairs(tbl) do
        if v == value then
            return true,k
        end
    end
    return false,nil
end

local black_list = {"00:00:00:00:00:00"}
local white_list = {"50:BD:5F:6E:34:DC","EC:55:F9:07:7B:55"}

local kickout_24G = -85
local kickout_5G = -75
local kickout_24G_5G = -55

logtofile = "/var/log/wifi-kickout.log"
logfile = io.open(logtofile, "a")
io.output(logfile)
--log_sys(string.format("Start wifi Kickout script."), logfile)

ubus.start()
local wlan = {}
for index,value in pairs(get_wlan_list()) do
    wlan[value] = {}
    wlan[value]["Name"] = value
    wlan[value]["MHz"] = check_mhz(value)
end

while true do
    local mac = {}
    for _,value in pairs(wlan) do
        local value_mac_array = get_mac_list(value["Name"])
        for _,value_mac in pairs(value_mac_array) do
            mac[value_mac] = {}
            mac[value_mac]["5G"] = 0
            mac[value_mac]["2.4G"] = 0
            for index_wlan,_ in pairs(wlan) do
                local signal = get_signal(index_wlan, value_mac)
                if signal ~= 0 then
                    --log_sys(string.format("Client %s. connect the %s(%s),signal:%s",value_mac,index_wlan,wlan[index_wlan]["MHz"],signal), logfile)
                    mac[value_mac]["WLAN"] = index_wlan
                    if wlan[index_wlan]["MHz"] == 5 then
                        mac[value_mac]["5G"] = signal
                    elseif wlan[index_wlan]["MHz"] == 2.4 then
                        mac[value_mac]["2.4G"] = signal
                    end
                end
            end
        end
    end
    for mac_index,value_mac_array in pairs(mac) do
        local wlan_name = mac[mac_index]["WLAN"]
        local signal_24g = mac[mac_index]["2.4G"]
        local signal_5g = mac[mac_index]["5G"]
        --print(mac_index,wlan_name,signal_24g,signal_5g)
        if not table.match(white_list, mac_index) then
            if table.match(black_list, mac_index ) then
                kick_out(wlan_name, mac_index, 3000)
                log_sys(string.format("Kickout the client %s , because in black list", mac_index), logfile)
            elseif signal_24g < kickout_24G then
                log_sys(string.format("Kickout the client %s , %d > %d (2.4G)", mac_index, signal_24g, kickout_24G), logfile)
                kick_out(wlan_name, mac_index, 3000)
            elseif signal_5g < kickout_5G then
                log_sys(string.format("Kickout the client %s , %d > %d (5G)", mac_index, signal_5g, kickout_5G), logfile)
                kick_out(wlan_name, mac_index, 3000)
            elseif (signal_24g ~= 0) and (signal_5g == 0) and (signal_24g > kickout_24G_5G) then
                log_sys(string.format("Kickout the client %s , %d < %d (change 2.4G to 5G)", mac_index, signal_24g, kickout_24G_5G), logfile)
                kick_out(wlan_name, mac_index, 3000)
            end
        end
    end
    os.execute("sleep 30")
end
logfile:close()
ubus.stop(conn)
