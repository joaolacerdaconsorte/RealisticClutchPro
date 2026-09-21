--[[
  ==============================================================================
  Realistic Clutch & Engine FFB Haptics (CSP FFB Post-Processing Middleware v4.0)
  ==============================================================================
  Injects real-time engine harmonics, clutch friction zone chatter, and
  pre-stall bucking directly into the low-level DirectInput / Direct Drive FFB
  pipeline at 333 Hz to 1000 Hz.
  ==============================================================================
--]]

local phase = 0.0
local chatterPhase = 0.0
local stallPulseTimer = 0.0
local lastRPM = 850.0

local config = ac.storage{
  enabled = true,
  idleGain = 0.12,
  biteGain = 0.50,
  stallGain = 0.60,
  cylinders = 4
}

local function clamp(val, minVal, maxVal)
  if val < minVal then return minVal end
  if val > maxVal then return maxVal end
  return val
end

function script.update(ffb, dt)
  if not config.enabled then
    return ffb
  end

  local car = ac.getCar(0)
  if not car then
    return ffb
  end

  if dt <= 0.0 or dt > 0.05 then dt = 0.003 end -- Fixed sub-frame physics interval
  phase = phase + dt

  local rpm = car.rpm or 0.0
  local clutchPedal = car.clutch or 1.0 -- In AC: 0.0 = floored, 1.0 = released
  local gear = car.gear or 0
  local speedKmh = math.abs(car.speedKmh or 0.0)
  local extraForce = 0.0

  -- Detect sudden engine stall (rapid RPM collapse)
  if lastRPM > 350.0 and rpm < 150.0 and gear ~= 0 and clutchPedal > 0.40 then
    stallPulseTimer = 0.40 -- Trigger 400ms mechanical jolt
  end
  lastRPM = rpm

  -- 1. PRIMARY & SECONDARY ENGINE COMBUSTION HARMONICS
  if rpm > 180.0 then
    local engineOrder = (config.cylinders or 4) * 0.5
    local fundamentalFreq = (rpm / 60.0) * engineOrder
    
    -- Primary firing frequency + secondary half-order chassis rumble
    local wave1 = math.sin(phase * 2.0 * math.pi * fundamentalFreq)
    local wave2 = math.sin(phase * math.pi * fundamentalFreq) * 0.35
    
    -- Attenuate idle vibration as road speed and RPM rise
    local idleAtten = clamp(1.0 - (rpm / 2200.0), 0.08, 1.0)
    extraForce = extraForce + ((wave1 + wave2) * (config.idleGain or 0.12) * idleAtten)
  end

  -- 2. CLUTCH BITE ZONE FRICTION CHATTER (High-Frequency Micro-Slip 24-42 Hz)
  -- Operates when in gear and clutch is in the mechanical friction zone (clutchPedal 0.25 to 0.75)
  if gear ~= 0 and clutchPedal > 0.22 and clutchPedal < 0.78 and rpm > 220.0 and speedKmh < 22.0 then
    local chatterFreq = 26.0 + (rpm * 0.012)
    chatterPhase = chatterPhase + (dt * chatterFreq)
    
    local chatterWave1 = math.sin(chatterPhase * 2.0 * math.pi)
    local chatterWave2 = math.cos(chatterPhase * 3.14 * 1.6) * 0.5
    local textureNoise = (math.random() - 0.5) * 0.25
    local compositeChatter = (chatterWave1 * 0.65) + (chatterWave2 * 0.35) + textureNoise
    
    -- Triangular / Hermite modulation peaking around 46% bite center
    local distFromBite = math.abs(clutchPedal - 0.46) / 0.25
    local biteFactor = clamp(1.0 - distFromBite, 0.0, 1.0)
    local smoothBite = biteFactor * biteFactor * (3.0 - 2.0 * biteFactor)
    
    extraForce = extraForce + (compositeChatter * (config.biteGain or 0.50) * smoothBite * 0.45)
  end

  -- 3. PRE-STALL LUGGING BUCKING (Violent low-frequency 11-15 Hz judder)
  if gear ~= 0 and rpm > 180.0 and rpm < 620.0 and clutchPedal > 0.30 then
    local lugFreq = 12.0
    local lugWave = math.sin(phase * 2.0 * math.pi * lugFreq)
    local severity = clamp((620.0 - rpm) / 380.0, 0.0, 1.0)
    extraForce = extraForce + (lugWave * (config.stallGain or 0.60) * severity * 0.40)
  end

  -- 4. VIOLENT STALL RECOIL JOLT (Damped mechanical impulse)
  if stallPulseTimer > 0.0 then
    stallPulseTimer = stallPulseTimer - dt
    local progress = stallPulseTimer / 0.40
    local pulse = math.sin((1.0 - progress) * math.pi * 6.0) * (progress * progress)
    extraForce = extraForce + (pulse * (config.stallGain or 0.60) * 0.75)
  end

  -- Return combined FFB signal clamped safely to [-1, 1]
  local finalFFB = ffb + extraForce
  if finalFFB > 1.0 then return 1.0 end
  if finalFFB < -1.0 then return -1.0 end
  return finalFFB
end
