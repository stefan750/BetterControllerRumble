local M = {}

local modEnabled = false

-- Notify vehicles on spawn
local function onVehicleSpawned(vid)
    local veh = be:getObjectByID(vid)
	
	if veh then
		veh:queueLuaCommand("controllerFFB.setEnabled("..tostring(modEnabled)..")")
	end
end

local function onExtensionLoaded()
	-- Pretend a device changed so onInputBindingsChanged gets triggered
    core_input_bindings.onDeviceChanged()
end

local function onInputBindingsChanged(assignedPlayers)
    -- Check assigned devices and disable the mod if a wheel or joystick is detected
    local enabled = true
    for device, player in pairs(assignedPlayers) do
        if device:startswith("wheel") or device:startswith("joystick") then
            enabled = false
            break
        end
    end

    -- Only show the toast message once
    if modEnabled and not enabled then
        guihooks.trigger("toastrMsg", {type="error", title="Better Controller Rumble", msg="Wheel or joystick device detected, disabling the mod."})
    end

    modEnabled = enabled

    -- Notify all vehicles
    local vehs = getAllVehicles()
	for _, veh in ipairs(vehs) do
		onVehicleSpawned(veh:getID())
	end
end

M.onExtensionLoaded = onExtensionLoaded
M.onInputBindingsChanged = onInputBindingsChanged
M.onVehicleSpawned = onVehicleSpawned

return M