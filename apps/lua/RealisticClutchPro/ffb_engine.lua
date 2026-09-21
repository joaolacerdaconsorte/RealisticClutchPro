--[[
  ==============================================================================
  Realistic Clutch & Stalling Pro - Force Feedback & Haptics Engine (v2.0)
  ==============================================================================
--]]

local FFB = {}

local function clamp(val, minVal, maxVal)
  if val < minVal then return minVal end
  if val > maxVal then return maxVal end
  return val
end

function FFB.newState()
  return {
    phaseTime = 0.0,
    chatterPhase = 0.0,
    crankingPhase = 0.0,
    currentFFBOutput = 0.0,
    rumbleIntensity = 0.0,
    harmonicFrequency = 28.0
  }
end

function FFB.calculateEngineFrequency(rpm, cylinders)
  local cyl = cylinders or 4
  local freq = (math.max(rpm, 100.0) / 60.0) * (cyl * 0.5)
  return clamp(freq, 8.0, 180.0)
end

function FFB.synthesize(ffbState, physicsState, config, car, dt)
  if not config.ffbEnabled or not car then
    ffbState.currentFFBOutput = 0.0
    ffbState.rumbleIntensity = 0.0
    return 0.0
  end

  if dt <= 0 or dt > 0.3 then dt = 0.016 end
  ffbState.phaseTime = ffbState.phaseTime + dt

  local totalVibration = 0.0
  local actualRPM = car.rpm or 0.0
  local cylinders = config.engineCylinders or 4
  local gain = config.ffbGain or 1.2

  -- 1. MARCHA LENTA E HARMÔNICOS DO MOTOR
  if physicsState.isEngineRunning and actualRPM > 120.0 then
    local engineFreq = FFB.calculateEngineFrequency(actualRPM, cylinders)
    ffbState.harmonicFrequency = engineFreq

    local primaryWave = math.sin(ffbState.phaseTime * 2.0 * math.pi * engineFreq)
    local subWave = math.sin(ffbState.phaseTime * math.pi * engineFreq * 0.5) * 0.4

    local idleRPM = config.idleRPM or 850.0
    local idleFactor = clamp(1.0 - ((actualRPM - idleRPM) / (idleRPM * 1.8)), 0.05, 1.0)
    
    local idleAmp = (config.ffbIdleRumble or 0.8) * 0.08 * idleFactor
    totalVibration = totalVibration + ((primaryWave + subWave) * idleAmp)
  end

  -- 2. TREPIDAÇÃO FORTE NO PONTO DE FRICÇÃO (CLUTCH BITE SHUDDER)
  -- Quando a embreagem está patinando na zona crítica (Estágio 1 ou 2)
  if physicsState.isEngineRunning and physicsState.clutchEngagement > 0.05 and physicsState.clutchEngagement < 0.95 then
    if car.gear ~= 0 and physicsState.engineLoad > 0.08 then
      ffbState.chatterPhase = ffbState.chatterPhase + (dt * (24.0 + (physicsState.engineLoad * 16.0)))
      
      local chatterWave1 = math.sin(ffbState.chatterPhase * 2.0 * math.pi)
      local chatterWave2 = math.cos(ffbState.chatterPhase * 3.14 * 1.7) * 0.6
      local noise = (math.random() - 0.5) * 0.4
      
      local chatterSignal = (chatterWave1 * 0.6) + (chatterWave2 * 0.4) + noise
      local biteMultiplier = (physicsState.clutchStage == 2) and 1.5 or 1.0
      local chatterStrength = (config.ffbBiteShudder or 1.2) * 0.30 * physicsState.engineLoad * biteMultiplier
      chatterStrength = clamp(chatterStrength, 0.0, 0.55)

      totalVibration = totalVibration + (chatterSignal * chatterStrength)
    end
  end

  -- 3. ALERTA DE PRÉ-ESTOL / CARRO AFOGANDO (VIOLENT BUCKING)
  if physicsState.isEngineRunning and car.gear ~= 0 and actualRPM < (config.stallRPM * 1.30) and actualRPM > 180.0 then
    if physicsState.clutchEngagement > 0.20 then
      local buckFreq = 11.5 -- 11.5 Hz de chacoalhada bruta
      local buckWave = math.sin(ffbState.phaseTime * 2.0 * math.pi * buckFreq)
      local severity = clamp(1.0 - (actualRPM / (config.stallRPM * 1.30)), 0.0, 1.0)
      
      local buckAmplitude = (config.ffbStallJolt or 1.2) * 0.45 * severity
      totalVibration = totalVibration + (buckWave * buckAmplitude)
    end
  end

  -- 4. TRANCO MECÂNICO DO MOTOR MORRENDO
  if physicsState.stallShockTimer > 0.0 then
    local shockProgress = physicsState.stallShockTimer / 0.40
    local shockPulse = math.sin(shockProgress * math.pi * 8.0) * shockProgress
    local shockAmplitude = (config.ffbStallJolt or 1.2) * 0.65
    totalVibration = totalVibration + (shockPulse * shockAmplitude)
  end

  -- 5. PULSO DE PARTIDA NO ARRANQUE
  if physicsState.isStarterEngaged and physicsState.isIgnitionOn then
    ffbState.crankingPhase = ffbState.crankingPhase + (dt * 6.0)
    local crankPulse = math.sin(ffbState.crankingPhase * 2.0 * math.pi)
    local sharpCrank = math.pow(math.max(0.0, crankPulse), 3.0)
    totalVibration = totalVibration + (sharpCrank * 0.20)
  end

  local finalFFB = clamp(totalVibration * gain, -0.75, 0.75)
  ffbState.currentFFBOutput = finalFFB
  ffbState.rumbleIntensity = math.abs(finalFFB)

  return finalFFB
end

return FFB
