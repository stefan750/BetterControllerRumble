local M = {}

local min = math.min
local max = math.max

-- Smoothing for vectors, based on temporalSmoothingNonLinear created by BeamNG
local vectorSmoothing = {}
vectorSmoothing.__index = vectorSmoothing

local function newVectorSmoothing(rate)
  local data = {rate = rate or 10, state = vec3(0,0,0)}
  setmetatable(data, vectorSmoothing)
  return data
end

function vectorSmoothing:get(sample, dt)
  local st = self.state
  local dif = sample - st
  st = st + dif * min(self.rate * dt, 1)
  self.state = st
  return st
end

function vectorSmoothing:set(sample)
  self.state = sample
end

function vectorSmoothing:reset()
  self.state = vec3(0,0,0)
end


-- Variables
local accSmoother = newVectorSmoothing(30)
local jerkSmoother = newVectorSmoothing(30)

local angAccSmoother = newVectorSmoothing(30)
local angJerkSmoother = newVectorSmoothing(30)

local totalJerkSmoother = newTemporalSmoothing(0.01, 1000)

local slipSmoother = newTemporalSmoothingNonLinear(30)
local overrevSmoother = newTemporalSmoothingNonLinear(30)

local jerkFactor = 0.00001
local jerkMax = 0.001
local angJerkFactor = 0.000001
local angJerkMax = 0.001
local slipFactor = 0.00005
local slipMax = 0.0005
local overrevFactor = 0.000002
local overrevMax = 0.0002

local jerkDeadzone = 50
local angJerkDeadzone = 500
local slipDeadzone = 3
local overrevDeadzone = -200

local origFFBCalc = nop
local ffiSensors = nil

local pitchAVMul = 0
local rollAVMul = 0
local yawAVMul = 0

local totalJerk = 0
local lastAcc = nil

local lastAngVel = nil
local lastAngAcc = nil

local totalSlip = 0
local totalOverrev = 0

local function newFFBCalc(wheelDispl, wheelPos)
	-- Calculate new FFB value
	local ffb = totalJerk + totalSlip + totalOverrev
	-- Pass new FFB value to the original function
	return origFFBCalc(ffb, 0)
end

local function onPhysicsStep(dt)
	local invDt = 1/dt

	-- Acceleration
	local acc = accSmoother:get(vec3(ffiSensors.sensorX, ffiSensors.sensorY, ffiSensors.sensorZnonInertial), dt)
	-- Jerk
	local jerk = jerkSmoother:get((acc - (lastAcc or acc))*invDt, dt)
	lastAcc = acc

	-- Angular Velocity
	local rollAV, pitchAV, yawAV = obj:getRollPitchYawAngularVelocity()
	local angVel = vec3(pitchAV * pitchAVMul, rollAV * rollAVMul, yawAV * yawAVMul)
	-- Angular acceleration
	local angAcc = angAccSmoother:get((angVel - (lastAngVel or angVel))*invDt, dt)
	lastAngVel = angVel
	-- Angular jerk
	local angJerk = angJerkSmoother:get((angAcc - (lastAngAcc or angAcc))*invDt, dt)
	lastAngAcc = angAcc

	totalJerk = totalJerkSmoother:get(clamp((jerk:length()-jerkDeadzone)*jerkFactor, 0, jerkMax) + clamp((angJerk:length()-angJerkDeadzone)*angJerkFactor, 0, angJerkMax), dt)

	-- Wheel slip
	local slip = 0
	local totalDownForce = 0
	local lwheels = wheels.wheels
	local wheelCount = tableSizeC(lwheels) - 1
	for i = 0, wheelCount - 1 do
		local wd = lwheels[i]
		if not wd.isBroken then
			local lastSlip = wd.lastSlip
			local downForce = wd.downForceRaw
			slip = slip + lastSlip * downForce
			totalDownForce = totalDownForce + downForce
		end
	end
	slip = slipSmoother:get(slip / (totalDownForce + 1e-25) - slipDeadzone, dt)
	totalSlip = clamp(slip*slipFactor, 0, slipMax)

	local overrev = overrevSmoother:get((electrics.values.rpm or 0) - (electrics.values.maxrpm or 100000) - overrevDeadzone, dt)
	totalOverrev = clamp(overrev*overrevFactor, 0, overrevMax)
end

local function onReset()
	ffiSensors = sensors.ffiSensors

	local vehLength = obj:getInitialLength()
	local vehWidth = obj:getInitialWidth()
	local vehHeight = obj:getInitialHeight()

	pitchAVMul = vec3(0, vehLength, vehHeight):length()
	rollAVMul = vec3(vehWidth, 0, vehHeight):length()
	yawAVMul = vec3(vehWidth, vehLength, 0):length()
	
	lastAcc = nil
	lastAngVel = nil
	lastAngAcc = nil

	accSmoother:reset()
	jerkSmoother:reset()
	angAccSmoother:reset()
	angJerkSmoother:reset()
	slipSmoother:reset()
	overrevSmoother:reset()
	totalJerkSmoother:reset()
end

local function setEnabled(enabled)
	local func = hydros.update
	
	-- Hook into FFBCalc function in hydros to add our custom code
	if enabled and not hydros.FFBCalcHooked then
		local i = 1
		while true do
			local name, upv = debug.getupvalue(func, i)
			if name == "FFBcalc" then
				origFFBCalc = upv
				debug.setupvalue(func, i, newFFBCalc)
				hydros.FFBCalcHooked = true
				break
			elseif not name then
				print("FFBcalc function not found")
				break
			end
			i = i + 1
		end

		M.onPhysicsStep = onPhysicsStep
		enablePhysicsStepHook()
		onReset()

	-- Restore original FFBCalc function
	elseif not enabled and hydros.FFBCalcHooked and origFFBCalc ~= nop then
		local i = 1
		while true do
			local name, upv = debug.getupvalue(func, i)
			if name == "FFBcalc" then
				debug.setupvalue(func, i, origFFBCalc)
				hydros.FFBCalcHooked = false
				break
			elseif not name then
				print("FFBcalc function not found")
				break
			end
			i = i + 1
		end

		M.onPhysicsStep = nop
	end
end

local function onExtensionUnloaded()
	setEnabled(false)
end


-- public interface
M.onPhysicsStep = nop
M.onExtensionUnloaded = onExtensionUnloaded
M.onReset = onReset
M.setEnabled = setEnabled

return M
