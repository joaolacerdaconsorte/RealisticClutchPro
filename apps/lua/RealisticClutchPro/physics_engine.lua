--[[
  ==============================================================================
  Realistic Clutch & Stalling Pro - Advanced Kinetic Drivetrain Simulation (v3.5)
  ==============================================================================
  Master Physics & Drivetrain Architecture:
  1. Pure Mechanical Decoupling: In AC, car.clutch is the mechanical coupling:
     - 0.0 = Pedal fully pressed to the floor (0% coupled / 100% disengaged).
     - 1.0 = Pedal fully released (100% coupled / locked to flywheel).
  2. Road Speed Stall Immunity: Cruising / decelerating at road speed (e.g. 3000 to
     1500 RPM, engine braking) CANNOT stall the engine. The car's kinetic energy
     drives the drivetrain smoothly.
  3. Progressive 4-Stage Hermite Bite Curve: Ultra-smooth transition from disengaged,
     light creep/drag, critical bite friction zone with tactile shudder, to lockup.
  4. Real Dynamic Stall: Dropping clutch at 0 km/h in gear without gas or braking to
     a stop in gear without clutch causes real stalling with violent mechanical jolt.
  5. Physical Chassis Vibration: Real micro-forces applied to car chassis in bite zone
     and lugging state for authentic visual cockpit/camera trembling.
  ==============================================================================
--]]

local Physics = {}

local function clamp(val, minVal, maxVal)
  if val < minVal then return minVal end
  if val > maxVal then return maxVal end
  return val
end

function Physics.newState()
  return {
    -- Engine core states
    isEngineRunning = true,
    isIgnitionOn = true,
    isStarterEngaged = false,
    isStarting = false,
    starterSequenceTimer = 0.0,
    isStalled = false,
    
    -- Kinetic Flywheel & Bog-down Dynamics
    flywheelEnergy = 1.0,        -- 1.0 = 100% healthy kinetic momentum, 0.0 = stalled
    engineBogState = 0.0,        -- 0.0 to 1.0 (severity of struggling/sputtering)
    lastClutch = 1.0,
    clutchReleaseVelocity = 0.0, -- d(clutch)/dt
    creepTorque = 0.0,
    chatterTimer = 0.0,
    
    -- Timers
    crankingDuration = 0.0,
    stallShockTimer = 0.0,
    stallReason = "",
    bumpStartTimer = 0.0,
    stallCooldown = 0.0,
    
    -- Live Clutch Mechanics
    clutchStage = 3,             -- 0: Free play, 1: Slip/Creep, 2: Critical Bite, 3: Locked
    clutchEngagement = 1.0,      -- 0.0 to 1.0
    clutchTorqueTransfer = 0.0,  -- Nm
    clutchSlipVelocity = 0.0,    -- RPM difference
    clutchTemperature = 25.0,    -- Celsius
    
    -- Engine Simulation
    simulatedRPM = 850.0,
    engineLoad = 0.0,            -- 0 to 1
    engineShudder = 0.0,         -- 0 to 1
    cockpitShakeOffset = vec2(0, 0), -- Screen / HUD pixel tremor
    
    -- Incline & Hill Roll
    inclinePitchAngle = 0.0,     -- Degrees (+ Uphill, - Downhill)
    inclineGradePercent = 0.0,   -- %
    gravityParallelForce = 0.0,  -- Newtons
    isHillBalancing = false,     -- Holding on slope with clutch
    hillRollVelocity = 0.0,      -- Rolling speed downhill
    
    -- Overrides applied to AC
    overrideGas = 0.0,
    overrideBrake = 0.0,
    overrideClutch = 0.0,
    overrideHandbrake = 0.0,
    killThrottle = false,
    
    -- Starter lurch
    starterLurchForce = 0.0
  }
end

-- 4-Stage OEM Clutch Engagement Curve with Hermite Smoothstep
-- acClutch: In AC, 0.0 = pedal no fundo (desconectado), 1.0 = pedal solto (100% colado)
function Physics.calculateClutchEngagement(acClutch, biteCenter, biteWidth)
  local travel = clamp(acClutch, 0.0, 1.0)
  
  local center = biteCenter or 0.44
  local width = biteWidth or 0.28
  
  local startBite = clamp(center - (width * 0.5), 0.15, 0.65)
  local endBite = clamp(center + (width * 0.5), startBite + 0.12, 0.90)
  
  if travel < startBite then
    -- Estágio 0: Totalmente Livre / Desacoplado
    return 0.0, 0
  elseif travel >= endBite then
    -- Estágio 3: Travamento Total / 100% Acoplado
    return 1.0, 3
  elseif travel < center then
    -- Estágio 1: Arrasto / Creep Suave (0.0 até 0.35)
    local t = (travel - startBite) / (center - startBite)
    local smooth = t * t * (3.0 - 2.0 * t)
    return smooth * 0.35, 1
  else
    -- Estágio 2: PONTO CRÍTICO DE FRICÇÃO (Bite Zone: 0.35 até 1.00)
    local t = (travel - center) / (endBite - center)
    local smooth = t * t * (3.0 - 2.0 * t)
    return 0.35 + (smooth * 0.65), 2
  end
end

-- Calculate road pitch incline angle in degrees
function Physics.calculateIncline(car)
  if not car then return 0.0 end
  local lookY = (car.look and car.look.y) or 0.0
  local pitchRad = math.asin(clamp(lookY, -1.0, 1.0))
  return math.deg(pitchRad)
end

-- Main Physics Step
function Physics.update(state, config, car, dt)
  if not car then return end
  if dt <= 0 or dt > 0.1 then dt = 0.016 end

  -- In Assetto Corsa:
  -- car.clutch: 0.0 = pedal totalmente pisado no fundo, 1.0 = pedal totalmente solto
  local acClutch = clamp(car.clutch or 1.0, 0.0, 1.0)
  local rawGas = car.gas or 0.0            -- 0 a 1
  local rawBrake = car.brake or 0.0        -- 0 a 1
  local rawHandbrake = car.handbrake or 0.0 -- 0 a 1
  local currentGear = car.gear or 0         -- 0 = N, -1 = R, 1+ = 1ª, 2ª...
  local currentSpeed = car.speedKmh or 0.0
  local actualRPM = car.rpm or 0.0
  local idleRPM = config.idleRPM or 850.0
  local stallRPM = config.stallRPM or 520.0
  local carMass = car.mass or 1200.0
  local flywheelInertia = config.flywheelInertia or 0.18
  local creepMultiplier = config.creepTorqueMultiplier or 1.15
  local speedMagnitude = math.abs(currentSpeed)
  local absGear = math.abs(currentGear)

  -- Velocidade com que a embreagem está acoplando (+ soltando pedal, - pisando)
  local clutchVel = (acClutch - state.lastClutch) / dt
  state.clutchReleaseVelocity = clutchVel
  state.lastClutch = acClutch

  state.chatterTimer = (state.chatterTimer or 0.0) + dt

  -- 1. CÁLCULO DE LADEIRA E GRAVIDADE (SUBIDA / DESCIDA)
  local pitchDeg = Physics.calculateIncline(car)
  state.inclinePitchAngle = pitchDeg
  state.inclineGradePercent = math.tan(math.rad(pitchDeg)) * 100.0
  
  local sinPitch = math.sin(math.rad(pitchDeg))
  local gravityForce = carMass * 9.81 * sinPitch
  state.gravityParallelForce = gravityForce

  -- 2. CÁLCULO DO PONTO DE FRICÇÃO DA EMBREAGEM (4 ESTÁGIOS)
  local engagement, stage = Physics.calculateClutchEngagement(
    acClutch,
    config.clutchBiteCenter or 0.44,
    config.clutchBiteWidth or 0.28
  )
  state.clutchEngagement = engagement
  state.clutchStage = stage

  local maxTorqueCapacity = config.clutchTorqueCapacity or 260.0
  state.clutchTorqueTransfer = engagement * maxTorqueCapacity

  -- 3. SISTEMA DE PARTIDA AUTOMÁTICA LATCHED (1 TOQUE LIGA E MANTÉM FUNCIONANDO)
  if not state.isIgnitionOn then
    state.isEngineRunning = false
    state.isStalled = true
    state.simulatedRPM = 0.0
    state.flywheelEnergy = 0.0
  end

  if state.isStarterEngaged and state.isIgnitionOn then
    state.isStarting = true
    state.starterSequenceTimer = 0.40
    state.isEngineRunning = true
    state.isStalled = false
    state.stallReason = ""
    state.stallCooldown = 2.0 -- 2.0s de proteção ao ligar
    state.flywheelEnergy = 1.0
  end

  if state.isStarting then
    state.starterSequenceTimer = state.starterSequenceTimer - dt
    state.crankingDuration = state.crankingDuration + dt
    state.flywheelEnergy = 1.0
    state.isEngineRunning = true
    state.isStalled = false

    local startupRatio = math.max(0.0, state.starterSequenceTimer / 0.40)
    state.simulatedRPM = idleRPM + (320.0 * startupRatio) + (math.sin(state.crankingDuration * 32.0) * 30.0)
    
    local crankShake = (math.sin(state.crankingDuration * 40.0) * 3.0 * startupRatio)
    state.cockpitShakeOffset = vec2(crankShake, -math.abs(crankShake * 0.75))

    if state.starterSequenceTimer <= 0.0 and not state.isStarterEngaged then
      state.isStarting = false
      state.crankingDuration = 0.0
      state.cockpitShakeOffset = vec2(0, 0)
    end
  else
    state.crankingDuration = 0.0
    if not state.isStalled and state.engineBogState <= 0.05 then
      state.cockpitShakeOffset = vec2(0, 0)
    end
  end

  -- 4. PEGAR NO TRANCO (BUMP START)
  if not state.isEngineRunning and state.isIgnitionOn and currentGear ~= 0 and speedMagnitude > 7.0 then
    if acClutch > 0.65 then
      state.bumpStartTimer = state.bumpStartTimer + dt
      if state.bumpStartTimer > 0.15 then
        state.isEngineRunning = true
        state.isStalled = false
        state.flywheelEnergy = 1.0
        state.stallCooldown = 1.5
        state.bumpStartTimer = 0.0
        state.stallReason = ""
        state.simulatedRPM = idleRPM + 200.0
      end
    else
      state.bumpStartTimer = 0.0
    end
  end

  -- 5. DINÂMICA MECÂNICA DE TRANSMISSÃO & INÉRCIA DO MOTOR
  if state.isEngineRunning and state.isIgnitionOn then
    -- DESACOPLAMENTO TOTAL: Em Ponto Morto (N) ou com pedal da embreagem afundado (stage == 0 ou acClutch < 0.25)
    local isDisengaged = (currentGear == 0) or (acClutch < 0.25) or (stage == 0)
    
    -- VELOCIDADE DE CONDUÇÃO SEGURA (RODANDO NA PISTA):
    -- Quando o carro está em movimento acima da velocidade mínima da marcha (ex: > 8 km/h em 1ª, > 14 km/h em 2ª, etc.)
    -- E o motor está acima de ~600 RPM, o freio motor e a inércia do carro mantêm o motor 100% vivo!
    local minGearRollingSpeed = (absGear >= 1) and (absGear * 5.5) or 5.5
    local isCruisingOrEngineBraking = (currentGear ~= 0) and (speedMagnitude >= minGearRollingSpeed) and (actualRPM > (stallRPM + 70.0))

    if isDisengaged or isCruisingOrEngineBraking then
      -- MOTOR TOTALMENTE SEGURO / OPERANDO LIVRE OU FREIO MOTOR:
      -- Desacelerar de 3000 pra 1500 RPM, reduzir marcha, coasting na subida etc. NUNCA afoga o motor!
      state.flywheelEnergy = math.min(1.0, state.flywheelEnergy + (dt * 8.0))
      state.engineBogState = 0.0
      state.engineLoad = 0.0
      state.engineShudder = 0.0
      state.isHillBalancing = false
      state.simulatedRPM = math.max(actualRPM, idleRPM)
      state.creepTorque = 0.0
    else
      -- SITUAÇÕES CRÍTICAS DE ARRANCADA, PARADA E FRICÇÃO (speedMagnitude < minGearRollingSpeed ou RPM muito baixa):
      
      -- Multiplicador por marcha alta parada (1ª = 1.0x, 2ª = 1.6x, 3ª = 2.6x, 4ª+ = 4.0x)
      local gearMult = 1.0
      if absGear == 2 then gearMult = 1.6
      elseif absGear == 3 then gearMult = 2.6
      elseif absGear >= 4 then gearMult = 4.0
      end

      -- Carga de subida em baixa velocidade de arrancada
      local hillLoad = 0.0
      if currentGear > 0 and pitchDeg > 0.8 then
        hillLoad = clamp((pitchDeg / 10.0) * 1.5, 0.0, 2.5)
      elseif currentGear < 0 and pitchDeg < -0.8 then
        hillLoad = clamp((math.abs(pitchDeg) / 10.0) * 1.5, 0.0, 2.5)
      end

      -- Déficit em relação à velocidade de marcha lenta (~7.5 km/h)
      local targetIdleSpeed = 7.5 / gearMult
      local speedDeficit = clamp((targetIdleSpeed - speedMagnitude) / targetIdleSpeed, 0.0, 1.0)

      -- Força gerada pelo acelerador do motorista
      local throttlePower = clamp(rawGas * 4.5, 0.0, 4.0)

      -- Detecção de soltura brusca (Clutch Dump: soltou rápido de uma vez)
      local isDumpingClutch = (clutchVel > 1.8) or (acClutch > 0.72 and state.lastClutch < 0.35)

      local transmissionDrag = 0.0
      local antiStallAssist = 0.0

      if stage <= 2 and acClutch <= 0.72 then
        -- A) ZONA DE FRICÇÃO / PATINAÇÃO (Estágio 1 ou 2, acClutch entre 0.25 e 0.72)
        -- Na fricção, o freio das rodas NÃO afoga o motor diretamente (apenas aumenta o deslizamento)!
        if not isDumpingClutch and absGear <= 1 and rawBrake < 0.08 and rawHandbrake < 0.08 and math.abs(pitchDeg) < 3.0 then
          state.creepTorque = engagement * 0.38 * creepMultiplier
          antiStallAssist = engagement * 0.48 * creepMultiplier
        else
          state.creepTorque = 0.0
        end

        -- Arrasto proporcional à fricção e subida
        transmissionDrag = engagement * (speedDeficit * 0.55 + hillLoad) * gearMult
      else
        -- B) TRAVAMENTO TOTAL DA EMBREAGEM (Estágio 3, acClutch > 0.72)
        -- Disco 100% prensado ao volante:
        state.creepTorque = 0.0
        local brakeDrag = clamp((rawBrake * 3.0 + rawHandbrake * 3.0), 0.0, 3.0)

        if speedMagnitude < 4.0 then
          -- Parado com embreagem 100% solta: virabrequim é forçado a parar!
          transmissionDrag = (1.20 + brakeDrag + hillLoad) * gearMult
          antiStallAssist = 0.0
        else
          transmissionDrag = (speedDeficit * 0.90 + brakeDrag + hillLoad) * gearMult
          antiStallAssist = 0.0
        end
      end

      -- C) BALANÇO DE EMBREAGEM NA SUBIDA (Hill Hold Equilibrium)
      if math.abs(pitchDeg) > 1.8 and speedMagnitude < 3.5 and rawBrake < 0.08 and rawHandbrake < 0.08 then
        local isUphillFacing = (currentGear > 0 and pitchDeg > 0) or (currentGear < 0 and pitchDeg < 0)
        if isUphillFacing and stage >= 1 and stage <= 2 and rawGas > 0.06 then
          state.isHillBalancing = true
          antiStallAssist = transmissionDrag
        else
          state.isHillBalancing = false
        end
      else
        state.isHillBalancing = false
      end

      -- Déficit efetivo de torque
      local torqueDeficit = math.max(0.0, transmissionDrag - throttlePower - antiStallAssist)
      state.engineLoad = clamp(transmissionDrag, 0.0, 1.0)

      -- D) BALANÇO CINÉTICO DA ENERGIA DO VOLANTE DO MOTOR
      if torqueDeficit > 0.08 and state.stallCooldown <= 0.0 and not state.isStarting then
        local dumpMult = isDumpingClutch and 3.8 or 1.0
        local drainRate = (torqueDeficit / flywheelInertia) * 1.5 * dumpMult
        state.flywheelEnergy = math.max(0.0, state.flywheelEnergy - (drainRate * dt))
      else
        state.flywheelEnergy = math.min(1.0, state.flywheelEnergy + (dt * 4.5))
      end

      -- E) AFOGAMENTO (BOG-DOWN), CHATTER E VIBRAÇÃO MECÂNICA
      state.engineBogState = clamp(1.0 - state.flywheelEnergy, 0.0, 1.0)

      if state.engineBogState > 0.08 or (stage >= 1 and stage <= 2 and state.engineLoad > 0.08) then
        local chatterFreq = 22.0 + (state.flywheelEnergy * 16.0) -- 22Hz a 38Hz
        local shudderWave = math.sin((state.chatterTimer or 0) * math.pi * 2.0 * chatterFreq)
        
        local biteShakeFactor = (stage == 2) and 1.8 or (stage == 1 and 0.9 or 0.0)
        local totalShudderIntensity = (state.engineBogState * 1.2 + engagement * 0.45 * biteShakeFactor) * (config.shudderIntensity or 1.35)
        state.engineShudder = clamp(totalShudderIntensity, 0.0, 1.0)

        state.simulatedRPM = idleRPM * math.max(0.20, math.pow(state.flywheelEnergy, 0.65))

        local shakeAmp = (state.engineBogState * 5.0) + (engagement * 2.6 * biteShakeFactor)
        state.cockpitShakeOffset = vec2(shudderWave * shakeAmp, -math.abs(shudderWave * shakeAmp * 0.75))
      else
        state.engineShudder = 0.0
        state.cockpitShakeOffset = vec2(0, 0)
        state.simulatedRPM = idleRPM
      end

      -- F) GATILHO DEFINITIVO DE ESTOL
      if config.stallEnabled and state.stallCooldown <= 0.0 and not state.isStarting and state.flywheelEnergy <= 0.02 then
        state.isEngineRunning = false
        state.isStalled = true
        state.stallShockTimer = 0.45
        state.stallCooldown = 0.80
        
        if isDumpingClutch then
          state.stallReason = "SOLTOU A EMBREAGEM RAPIDO DEMAIS (CLUTCH DUMP)!"
        elseif acClutch > 0.72 and speedMagnitude < 4.0 and rawGas < 0.12 then
          state.stallReason = "SOLTOU A EMBREAGEM COM O CARRO PARADO SEM ACELERAR!"
        elseif acClutch > 0.72 and rawBrake > 0.25 and speedMagnitude < 4.0 then
          state.stallReason = "FREIOU ATE PARAR EM MARCHA SEM PISAR NA EMBREAGEM!"
        elseif absGear > 1 and speedMagnitude < 6.0 then
          state.stallReason = "TENTOU ARRANCAR EM MARCHA MUITO ALTA!"
        elseif math.abs(pitchDeg) > 3.0 then
          state.stallReason = "FALTOU ACELERAÇÃO NA SUBIDA!"
        else
          state.stallReason = "MOTOR MORREU POR EXCESSO DE CARGA NA EMBREAGEM!"
        end
      end
    end
  end

  if state.stallCooldown > 0.0 then
    state.stallCooldown = state.stallCooldown - dt
  end

  -- 6. EXECUÇÃO DO ESTADO DE MOTOR MORTO (CORTE TOTAL)
  if state.isStalled then
    state.killThrottle = true
    state.simulatedRPM = 0.0
    state.engineLoad = 0.0
    state.flywheelEnergy = 0.0
    
    if state.stallShockTimer > 0.0 then
      state.stallShockTimer = state.stallShockTimer - dt
      local shockFrac = state.stallShockTimer / 0.45
      state.cockpitShakeOffset = vec2((math.random() - 0.5) * 14.0 * shockFrac, -shockFrac * 10.0)
      state.engineShudder = shockFrac
    else
      state.cockpitShakeOffset = vec2(0, 0)
      state.engineShudder = 0.0
    end
  else
    state.killThrottle = false
  end

  return state
end

return Physics
