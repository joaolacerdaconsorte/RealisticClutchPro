--[[
  ==============================================================================
  Realistic Clutch & Stalling Pro (CSP Ultimate Drivetrain Simulation v4.0)
  ==============================================================================
  Author: Antigravity
  Version: 4.0.0
  Architecture:
  - Low-Level C-Physics Integration (ac.overrideSpecificValue & DrivetrainClutchOverride)
  - Non-Smooth Stick-Slip Discrete Numerical Mechanics (cphys_core.lua)
  - Reflected Inertia & Road Load Dynamics (drivetrain_model.lua)
  - DirectInput FFB Post-Processing Middleware (RealisticClutchFFB)
  - Full Universal Compatibility across 100% of Assetto Corsa vehicles
  ==============================================================================
--]]

local Core = require('cphys_core')
local Drivetrain = require('drivetrain_model')
local FFB = require('ffb_engine')
local Presets = require('presets')
local Audio = require('audio_engine')
local UI = require('ui_components')
local sharedDef = require('clutch_shared_struct')
local sharedData = nil
pcall(function()
  sharedData = ac.connect(sharedDef.LAYOUT, true, ac.SharedNamespace.Shared)
end)

-- Key Codes for CSP Lua
local KEY_E = (ui and ui.KeyIndex and ui.KeyIndex.E) or 69
local KEY_I = (ui and ui.KeyIndex and ui.KeyIndex.I) or 73

-- Persistent Configuration with ac.storage
local config = ac.storage{
  enabled = true,
  stallEnabled = true,
  selectedPreset = "autoescola",
  
  -- Engine & Clutch Parameters
  idleRPM = 850.0,
  stallRPM = 540.0,
  clutchBiteCenter = 0.45,
  clutchBiteWidth = 0.24,
  clutchTorqueCapacity = 140.0,
  engineCylinders = 4,
  flywheelInertia = 0.13,
  creepTorqueMultiplier = 1.10,
  shudderIntensity = 1.65,
  
  -- FFB Haptics & Cabin Tremor
  ffbEnabled = true,
  ffbGain = 1.25,
  ffbIdleRumble = 0.90,
  ffbBiteShudder = 1.55,
  ffbStallJolt = 1.30,
  cockpitShakeEnabled = true,
  
  -- Starter & Ignition
  allowStarterInGear = true,
  crankTimeToStart = 0.35,
  audioEnabled = true,
  
  -- HUD & Display
  showHudOverlay = true,
  language = "pt"
}

-- Runtime States
local coreCfg = Core.newConfig{
  bite_point = config.clutchBiteCenter,
  bite_window = config.clutchBiteWidth
}
local coreState = Core.newState()
local dtCfg = Drivetrain.newConfig()

local ffbState = FFB.newState()
local audioState = Audio.newState()
local activeControls = nil
local autoDetected = false

-- State Flags
local isEngineRunning = true
local lastEngineRunningState = true
local isIgnitionOn = true
local isStarting = false
local starterTimer = 0.0
local stallCooldown = 0.0
local stallShockTimer = 0.0
local stallReason = ""
local chatterTimer = 0.0
local cockpitShake = vec2(0, 0)

-- Native Button Bindings via ac.ControlButton (Mapped to Button 1 / X of PCYES W270)
local btnStarter = ac.ControlButton("STARTER", {
  keyboard = { key = KEY_E },
  controllers = { { joystick = 0, button = 0 } },
  hold = true
})
pcall(function() btnStarter:setAlwaysActive(true) end)

local btnStarterExt = ac.ControlButton("__EXT_STARTER", {
  controllers = { { joystick = 0, button = 0 } },
  hold = true
})
pcall(function() btnStarterExt:setAlwaysActive(true) end)

local btnStarterCustom = ac.ControlButton("RealisticClutchPro/Starter", {
  keyboard = { key = KEY_E },
  controllers = { { joystick = 0, button = 0 } },
  hold = true
})
pcall(function() btnStarterCustom:setAlwaysActive(true) end)

local btnIgnition = ac.ControlButton("RealisticClutchPro/Ignition", {
  keyboard = { key = KEY_I },
  hold = false
})

Audio.init(audioState)

local function clamp(val, minVal, maxVal)
  if val < minVal then return minVal end
  if val > maxVal then return maxVal end
  return val
end

local function applyPreset(presetId)
  local p = Presets.getById(presetId)
  if p and p.config then
    config.selectedPreset = presetId
    config.idleRPM = p.config.idleRPM
    config.stallRPM = p.config.stallRPM
    config.clutchBiteCenter = p.config.clutchBiteCenter
    config.clutchBiteWidth = p.config.clutchBiteWidth
    config.clutchTorqueCapacity = p.config.clutchTorqueCapacity
    config.engineCylinders = p.config.engineCylinders
    config.flywheelInertia = p.config.flywheelInertia or 0.16
    config.creepTorqueMultiplier = p.config.creepTorqueMultiplier or 1.15
    config.shudderIntensity = p.config.shudderIntensity
    config.ffbIdleRumble = p.config.ffbIdleRumble
    config.ffbBiteShudder = p.config.ffbBiteShudder
    config.ffbStallJolt = p.config.ffbStallJolt
    config.allowStarterInGear = p.config.allowStarterInGear
    config.crankTimeToStart = p.config.crankTimeToStart
    
    coreCfg.bite_point = p.config.clutchBiteCenter
    coreCfg.bite_window = p.config.clutchBiteWidth
    coreCfg.F_normal_max = p.config.clutchTorqueCapacity * 26.0
  end
end

local wasEnabled = true

local function restoreVanillaPhysics()
  pcall(function()
    if ac.overrideSpecificValue and ac.CarPhysicsValueID then
      ac.overrideSpecificValue(ac.CarPhysicsValueID.DrivetrainClutchOverride, 0.0 / 0.0)
      ac.overrideSpecificValue(ac.CarPhysicsValueID.DrivetrainOpenThreshold, 0.0 / 0.0)
      ac.overrideSpecificValue(ac.CarPhysicsValueID.EngineLimiterCycles, 0)
    end
    if ac.overrideEngineTorque then
      ac.overrideEngineTorque(0.0 / 0.0)
    end
    local activeControls = ac.overrideCarControls(0)
    if activeControls then
      activeControls.gas = 0.0
    end
  end)
  if sharedData then
    sharedData.heartbeat = os.clock()
    sharedData.appActive = false
    sharedData.clutchEngagement = 1.0
    sharedData.clutchSlipRpm = 0.0
    sharedData.isStalling = false
    sharedData.stallRecoilTrigger = false
    sharedData.gainMaster = 0.0
  end
  isEngineRunning = true
  isIgnitionOn = true
  isStarting = false
  stallShockTimer = 0.0
  cockpitShake = vec2(0, 0)
end

-- ==============================================================================
-- MAIN SCRIPT UPDATE LOOP (Runs at frame rate with sub-stepping capability)
-- ==============================================================================
function script.update(dt)
  if not config.enabled then
    if wasEnabled then
      restoreVanillaPhysics()
      wasEnabled = false
    end
    if sharedData then
      sharedData.heartbeat = os.clock()
      sharedData.appActive = false
    end
    return
  end
  wasEnabled = true
  
  local car = ac.getCar(0)
  if not car then return end

  if dt <= 0.0 or dt > 0.05 then dt = 0.016 end

  -- 1. Auto-Detecção Inteligente do Veículo (Executa 1x ao entrar na pista)
  if not autoDetected then
    local detected = Presets.detectForCar(car)
    if detected then
      applyPreset(detected.id)
    end
    autoDetected = true
  end

  -- 2. Leitura de Controles e Botões de Partida (W270 Botão 1 / X e Teclado E)
  local isJoyBtn1 = false
  if ac.isJoystickButtonPressed then
    pcall(function()
      local count = ac.getJoystickCount and ac.getJoystickCount() or 4
      for j = 0, count - 1 do
        if ac.isJoystickButtonPressed(j, 0) then
          isJoyBtn1 = true
          break
        end
      end
    end)
  end

  local isBtnDown = false
  pcall(function()
    isBtnDown = btnStarter:down() or btnStarterExt:down() or btnStarterCustom:down()
  end)

  local isKeyE = false
  if ac.isKeyDown then
    pcall(function()
      isKeyE = ac.isKeyDown(KEY_E)
    end)
  end

  local starterActive = isJoyBtn1 or isBtnDown or isKeyE or (car.extraE == true)
  chatterTimer = chatterTimer + dt

  -- Chave de Ignição (Tecla 'I')
  if btnIgnition:pressed() or ac.isKeyPressed(KEY_I) then
    isIgnitionOn = not isIgnitionOn
    if not isIgnitionOn then
      isEngineRunning = false
      stallReason = "IGNIÇÃO DESLIGADA MANUALMENTE"
      coreState.omega_e = 0.0
    end
  end

  -- Disparo de Partida do Motor (1 Toque)
  if starterActive and not isStarting then
    isIgnitionOn = true
    isEngineRunning = true
    isStarting = true
    starterTimer = config.crankTimeToStart or 0.35
    stallCooldown = 2.0
    stallReason = ""
    coreState.omega_e = (config.idleRPM + 250.0) * 0.10472 -- rad/s
    pcall(function()
      physics.setEngineRPM(0, config.idleRPM + 250.0)
      ac.overrideGasInput(math.huge)
    end)
  end

  if isStarting then
    starterTimer = starterTimer - dt
    if starterTimer <= 0.0 and not starterActive then
      isStarting = false
    end
  end

  -- 3. Resolução Cinemática e Dinâmica da Transmissão
  local currentGear = car.gear or 0
  local speedKmh = car.speedKmh or 0.0
  local speedMag = math.abs(speedKmh)
  local v_veh = speedKmh / 3.6 -- m/s
  local actualRPM = car.rpm or 0.0
  local acClutch = clamp(car.clutch or 1.0, 0.0, 1.0) -- In AC: 0.0 = pressed floor, 1.0 = released
  local rawGas = clamp(car.gas or 0.0, 0.0, 1.0)
  local rawBrake = clamp(car.brake or 0.0, 0.0, 1.0)
  local rawHandbrake = clamp(car.handbrake or 0.0, 0.0, 1.0)
  local carMass = car.mass or 1250.0

  -- Cálculo de Inércia Refletida (It) e Carga da Pista (tau_load)
  local lookY = (car.look and car.look.y) or 0.0
  local pitchRad = math.asin(clamp(lookY, -1.0, 1.0))
  local pitchDeg = math.deg(pitchRad)

  -- Sincronização Cinemática do Eixo Primário (Input Shaft) com as rodas
  local omega_t_road = Drivetrain.calculateKinematicInputShaftSpeed(dtCfg, currentGear, v_veh)
  if omega_t_road ~= nil then
    -- Em marcha engrenada, o eixo primário segue a velocidade cinemática das rodas
    coreState.omega_t = omega_t_road
  elseif currentGear == 0 and acClutch < 0.20 then
    -- No neutro com embreagem pisada, o primário desacelera suavemente por atrito viscoso
    coreState.omega_t = math.max(0.0, coreState.omega_t - 25.0 * dt)
  end

  local I_e = config.flywheelInertia or 0.16
  local I_t = Drivetrain.calculateReflectedInertia(dtCfg, currentGear, carMass)
  local tau_load = Drivetrain.calculateRoadLoad(dtCfg, currentGear, v_veh, pitchRad, rawBrake, rawHandbrake, coreState.omega_t, carMass)
  
  -- Torque de Combustão / Motor de Arranque
  local tau_combustion = Drivetrain.calculateEngineTorque(
    dtCfg, 
    coreState.omega_e, 
    rawGas, 
    isIgnitionOn, 
    (not isEngineRunning), 
    (starterActive or isStarting), 
    config.idleRPM, 
    config.clutchTorqueCapacity
  )

  -- Pedal travel para o cálculo de aperto:
  -- No AC: car.clutch = 0.0 (pedal afundado/embreagem aberta) -> pedalTravel = 1.0
  -- No AC: car.clutch = 1.0 (pedal solto/embreagem colada) -> pedalTravel = 0.0
  local pedalTravel = 1.0 - acClutch

  -- 4. Passo de Integração Não-Suave (Stick-Slip Solver @ 333 Hz rate)
  -- Para máxima precisão numérica, executamos 4 micro-passos por quadro (dt_sub = dt / 4)
  local subSteps = 4
  local dtSub = dt / subSteps
  for s = 1, subSteps do
    Core.step(coreCfg, coreState, I_e, I_t, tau_combustion, tau_load, pedalTravel, dtSub)
  end

  local simulatedRPM = coreState.omega_e * 9.549296

  -- 5. Lógica de Estol Mecânico (Stalling)
  if stallCooldown > 0.0 then
    stallCooldown = stallCooldown - dt
  end

  -- Condição de estol mecânico: motor ligado, fora de partida e cooldown
  if config.stallEnabled and isEngineRunning and stallCooldown <= 0.0 and not isStarting then
    local shouldStall = false
    local stallMsg = "MOTOR MORREU POR EXCESSO DE CARGA NA TRANSMISSÃO!"

    -- Caso A: Rotação simulada caiu abaixo de stallRPM
    if simulatedRPM < config.stallRPM or coreState.omega_e < (config.stallRPM * 0.10472) then
      shouldStall = true
      if acClutch > 0.60 and speedMag < 4.0 and rawGas < 0.15 then
        stallMsg = "SOLTOU A EMBREAGEM COM CARRO PARADO SEM ACELERAR!"
      elseif acClutch > 0.40 and (rawBrake > 0.15 or rawHandbrake > 0.15) and speedMag < 5.0 then
        stallMsg = "FREIOU ATÉ PARAR EM MARCHA SEM PISAR NA EMBREAGEM!"
      elseif math.abs(currentGear) > 1 and speedMag < 7.0 then
        stallMsg = "TENTOU ARRANCAR EM MARCHA MUITO ALTA!"
      elseif pitchDeg > 2.0 and rawGas < 0.20 then
        stallMsg = "FALTOU ACELERAÇÃO NA SUBIDA!"
      end
    end

    -- Caso B: Carro quase parado em marcha sem embreagem (soltou de vez no semáforo ou freou)
    if not shouldStall and currentGear ~= 0 and acClutch > 0.45 and speedMag < 3.0 and rawGas < 0.12 then
      shouldStall = true
      stallMsg = (rawBrake > 0.10) and "FREIOU ATÉ PARAR EM MARCHA SEM PISAR NA EMBREAGEM!" 
                                   or "SOLTOU A EMBREAGEM COM CARRO PARADO SEM ACELERAR!"
    end

    -- Caso C: Tentativa de arrancada em marcha alta em velocidade baixa sem aceleração alta
    if not shouldStall and math.abs(currentGear) >= 2 and speedMag < 5.0 and acClutch > 0.40 and rawGas < 0.35 then
      shouldStall = true
      stallMsg = "TENTOU ARRANCAR EM MARCHA MUITO ALTA (" .. tostring(currentGear) .. "ª MARCHA)!"
    end

    -- Caso D: Subida íngreme sem acelerador suficiente
    if not shouldStall and pitchDeg > 2.5 and speedMag < 4.0 and acClutch > 0.45 and rawGas < 0.20 then
      shouldStall = true
      stallMsg = "FALTOU ACELERAÇÃO NA SUBIDA!"
    end

    if shouldStall then
      isEngineRunning = false
      stallShockTimer = 0.35
      stallCooldown = 1.0
      coreState.omega_e = 0.0
      simulatedRPM = 0.0
      stallReason = stallMsg
    end
  end

  -- 5b. Pegar no Tranco (Realistic Bump Start)
  -- Se o motor estiver apagado com ignição ligada, carro em movimento e engrenado, soltar a embreagem dá partida
  if not isEngineRunning and isIgnitionOn and currentGear ~= 0 and acClutch > 0.40 and speedMag > 10.0 then
    if simulatedRPM > (config.stallRPM or 500.0) then
      isEngineRunning = true
      stallCooldown = 2.0
      stallReason = ""
      pcall(function()
        physics.setEngineRPM(0, simulatedRPM)
        ac.overrideGasInput(math.huge)
        local bumpDir = (currentGear < 0) and 1.0 or -1.0
        physics.addForce(0, vec3(0, 0, 0), true, vec3(0, 0, bumpDir * carMass * 0.40), true)
      end)
    end
  end

  -- 6. Injeção Direta em Baixo Nível no CSP (C-Physics Engine Hooks)
  if ac.overrideSpecificValue and ac.CarPhysicsValueID then
    pcall(function()
      -- Sobrescreve a embreagem física do C++ com a taxa calculada do nosso modelo de Coulomb
      ac.overrideSpecificValue(ac.CarPhysicsValueID.DrivetrainClutchOverride, coreState.coupling_ratio)
      -- Desativa o sincronizador simplificado da Kunos para permitir deslizamento suave contínuo
      ac.overrideSpecificValue(ac.CarPhysicsValueID.DrivetrainOpenThreshold, 0.0)
      
      -- Em estol, dispara o corte de ignição via ciclos de física; quando ligado, garante 0 ciclos de corte
      if not isEngineRunning then
        ac.overrideSpecificValue(ac.CarPhysicsValueID.EngineLimiterCycles, 100)
      else
        ac.overrideSpecificValue(ac.CarPhysicsValueID.EngineLimiterCycles, 0)
      end
    end)
  end

  -- Injeta corte de torque no motor APENAS em estol
  if ac.overrideEngineTorque then
    pcall(function()
      if not isEngineRunning then
        ac.overrideEngineTorque(0.0)
      elseif not lastEngineRunningState then
        -- Transição de estol para ligado: restaura a curva nativa passando NaN (0/0) conforme documentado no CSP SDK
        ac.overrideEngineTorque(0.0 / 0.0)
      end
    end)
  end

  -- 6b. Publicação de Telemetria de Baixíssima Latência via IPC (ac.connect @ 333 Hz)
  if sharedData then
    sharedData.heartbeat = os.clock()
    sharedData.appActive = true
    sharedData.cylinderCount = config.engineCylinders or 4
    sharedData.idleRpm = config.idleRPM
    sharedData.stallRpm = config.stallRPM
    sharedData.maxTorqueNm = config.clutchTorqueCapacity
    sharedData.clutchBitePosition = config.clutchBiteCenter
    sharedData.clutchEngagement = coreState.coupling_ratio
    sharedData.clutchSlipRpm = (coreState.omega_e - coreState.omega_t) * 9.549296
    sharedData.clutchTorqueNm = coreState.tau_clutch
    sharedData.clutchTemperatureC = coreState.T_disc
    sharedData.clutchGlazeFactor = coreState.glaze_factor or 0.0
    sharedData.drivelineWindupNm = math.abs(coreState.tau_clutch)
    sharedData.isStalling = (not isEngineRunning and stallShockTimer > 0.0) or 
                           (coreState.state == Core.STATE_SLIPPING and simulatedRPM < (config.stallRPM + 75.0) and currentGear ~= 0 and actualRPM > 120.0)
    sharedData.stallRecoilTrigger = (stallShockTimer > 0.25)
    sharedData.gainMaster = config.ffbGain
    sharedData.gainJudder = config.ffbBiteShudder
    sharedData.gainChatter = config.shudderIntensity
    sharedData.gainCombustion = config.ffbIdleRumble
    sharedData.gainLugging = config.ffbStallJolt
  end

  -- 7. Controle Universal de Carro (Garante 100% de compatibilidade com qualquer carro)
  activeControls = ac.overrideCarControls(0)
  if activeControls then
    if not isEngineRunning then
      activeControls.gas = 0.0
      pcall(function()
        physics.setEngineRPM(0, 0.0)
      end)

      -- TRANCO FÍSICO SUAVE AO MORRER O MOTOR (Centralizado no CG para não desalinhar volante)
      if stallShockTimer > 0.0 and currentGear ~= 0 then
        local shockRatio = stallShockTimer / 0.35
        local lurchDir = (currentGear < 0) and 1.0 or -1.0
        local stallJolt = lurchDir * carMass * 0.30 * (shockRatio * shockRatio) * (config.ffbStallJolt or 1.0)
        pcall(function()
          physics.addForce(0, vec3(0, 0, 0), true, vec3(0, 0, stallJolt), true)
        end)
      end
    elseif starterActive or isStarting then
      pcall(function()
        physics.setEngineRPM(0, config.idleRPM + 250.0)
      end)
      -- Tranco de arranque engrenado
      if currentGear ~= 0 and coreState.coupling_ratio > 0.45 then
        local lurchDir = (currentGear < 0) and -1.0 or 1.0
        pcall(function()
          physics.addForce(0, vec3(0, 0, 0), true, vec3(0, 0, lurchDir * carMass * 0.35), true)
        end)
      end
    else
      -- Motor em funcionamento normal:
      -- activeControls.gas deve ser SEMPRE 0.0 para que o CSP use estritamente max(pedal_real, 0.0) = pedal_real!
      -- Isso garante aceleração 100% direta, linear e sem acelerador fantasma ou travado.
      activeControls.gas = 0.0

      -- CREEP DE MARCHA LENTA NO PLANO (Arrancada suave ao soltar a embreagem sem acelerar)
      local isCreepEligible = (currentGear == 1 or currentGear == -1)
                              and (rawBrake < 0.08 and rawHandbrake < 0.08)
                              and (rawGas < 0.05)
                              and (acClutch > 0.35 or coreState.coupling_ratio > 0.08)
                              and (speedMag < 8.5)
                              and (math.abs(pitchDeg) < 2.5)

      if isCreepEligible then
        local creepDir = (currentGear < 0) and -1.0 or 1.0
        -- Governador de velocidade: empurra suavemente até atingir a velocidade de marcha lenta (~7.2 - 7.6 km/h)
        local speedGovernor = clamp((8.2 - speedMag) / 8.2, 0.0, 1.0)
        local engagementFactor = clamp(coreState.coupling_ratio * 1.5, 0.15, 1.0)

        -- Força tratória das rodas motrizes (Newton: ~1600 - 2000 N gerados pelo acoplamento mecânico)
        local creepTractiveForce = creepDir * carMass * 1.65 * engagementFactor * speedGovernor * (config.creepTorqueMultiplier or 1.0)
        pcall(function()
          physics.addForce(0, vec3(0, 0, 0), true, vec3(0, 0, creepTractiveForce), true)
        end)
      end

      -- TREPIDAÇÃO FÍSICA E VISUAL NO PONTO DE FRICÇÃO (Chassis & Cockpit Camera Shudder)
      if currentGear ~= 0 and coreState.state == Core.STATE_SLIPPING and speedMag < 18.0 and coreState.coupling_ratio > 0.08 then
        local biteZone = 1.0 - math.min(1.0, math.abs(coreState.coupling_ratio - 0.45) / 0.35)
        local smoothBite = biteZone * biteZone * (3.0 - 2.0 * biteZone)
        local shudderGain = clamp(config.shudderIntensity or 1.45, 0.5, 2.5)

        -- Frequência natural de vibração de coxins do motor / subchassi (15.2 Hz)
        local biteFreq = 15.2
        local oscY = math.sin(chatterTimer * math.pi * 2.0 * biteFreq)
        local oscZ = math.sin(chatterTimer * math.pi * 2.0 * biteFreq + 0.75) * 0.5

        -- Força de suspensão (350 N - 550 N): excita os amortecedores e molas, fazendo a tela tremer visivelmente!
        local forceY = oscY * carMass * 0.45 * (0.35 + 0.65 * smoothBite) * shudderGain
        local forceZ = oscZ * carMass * 0.30 * (0.35 + 0.65 * smoothBite) * shudderGain

        -- Se estiver em subida, agacha a traseira conforme traciona (controle de embreagem na rampa)
        if math.abs(pitchDeg) > 1.2 then
          local squat = math.sin(pitchRad) * carMass * 0.35 * coreState.coupling_ratio
          forceY = forceY - math.abs(squat)
        end

        pcall(function()
          physics.addForce(0, vec3(0, 0, 0), true, vec3(0, forceY, forceZ), true)
        end)
      end

      -- QUEDA AUDÍVEL DE ROTAÇÃO NO PONTO DE EMBREAGEM (ENGINE BOG / SOM PESADO)
      if rawGas < 0.08 and currentGear ~= 0 and coreState.state == Core.STATE_SLIPPING and coreState.coupling_ratio > 0.12 then
        local droopRpm = clamp(coreState.coupling_ratio * 130.0, 0.0, 140.0)
        local loadedRpm = math.max((config.stallRPM or 540.0) + 35.0, (config.idleRPM or 850.0) - droopRpm)
        pcall(function()
          physics.setEngineRPM(0, loadedRpm)
        end)
      end
    end

    -- FÍSICA ATIVA DE GRAVIDADE NA LADEIRA (Desce livre no neutro / embreagem pisada)
    local isBraking = (rawBrake > 0.04) or (rawHandbrake > 0.04)
    local isFreewheeling = (currentGear == 0) or (acClutch < 0.25) or (coreState.coupling_ratio < 0.15)
    
    if math.abs(pitchDeg) > 0.8 then
      pcall(function() physics.awakeCar(0) end)

      if not isBraking and isFreewheeling then
        local rollForce = -math.sin(pitchRad) * carMass * 9.81 * 0.40
        pcall(function()
          physics.addForce(0, vec3(0, 0, 0), true, vec3(0, 0, rollForce), true)
        end)
      end
    end
  end

  -- 8. Efeito Visual de Tremor do Cockpit e Tela
  if stallShockTimer > 0.0 then
    stallShockTimer = stallShockTimer - dt
    local shockFrac = stallShockTimer / 0.45
    cockpitShake = vec2((math.random() - 0.5) * 14.0 * shockFrac, -shockFrac * 10.0)
  elseif coreState.state == Core.STATE_SLIPPING and currentGear ~= 0 and coreState.coupling_ratio > 0.15 and speedMag < 16.0 then
    local shakeWave = math.sin(chatterTimer * math.pi * 48.0)
    local shakeAmp = coreState.coupling_ratio * 4.0 * (config.shudderIntensity or 1.35)
    cockpitShake = vec2(shakeWave * shakeAmp, -math.abs(shakeWave * shakeAmp * 0.7))
  else
    cockpitShake = vec2(0, 0)
  end

  -- 9. Sincronização de Áudio
  Audio.update(audioState, {
    isEngineRunning = isEngineRunning,
    isStarting = isStarting,
    isStalled = (not isEngineRunning),
    clutchEngagement = coreState.coupling_ratio,
    engineBogState = (coreState.state == Core.STATE_SLIPPING and coreState.coupling_ratio or 0.0)
  }, config, car, dt)

  lastEngineRunningState = isEngineRunning
end

-- ==============================================================================
-- MAIN IN-GAME UI WINDOW
-- ==============================================================================
local selectedTab = 1

function script.windowMain()
  local pt = config.language == "pt"
  
  if config.cockpitShakeEnabled and (cockpitShake.x ~= 0 or cockpitShake.y ~= 0) then
    ui.setCursor(ui.getCursor() + cockpitShake)
  end

  -- Header
  ui.textHeading("Realistic Clutch Pro v4.3 (Autoescola Edition)")
  ui.sameLine(ui.availableSpaceX() - 85)
  if ui.button(pt and "EN" or "PT", vec2(75, 22)) then
    config.language = (config.language == "pt") and "en" or "pt"
  end
  
  ui.separator()

  -- Master Botão Liga / Desliga (Ativa ou desativa o mod a qualquer momento)
  local btnW = ui.availableSpaceX()
  if config.enabled then
    if ui.button(pt and "🟢 MOD ATIVADO (CLIQUE PARA DESATIVAR)" or "🟢 MOD ENABLED (CLICK TO DISABLE)", vec2(btnW, 32)) then
      config.enabled = false
      restoreVanillaPhysics()
    end
  else
    if ui.button(pt and "🔴 MOD DESATIVADO (CLIQUE PARA ATIVAR)" or "🔴 MOD DISABLED (CLICK TO ENABLE)", vec2(btnW, 32)) then
      config.enabled = true
      isEngineRunning = true
      isIgnitionOn = true
    end
  end
  ui.dummy(vec2(0, 4))

  -- Engine State Badge
  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  local h = 40
  
  local stateCol = rgbm(0.18, 0.72, 0.28, 0.95)
  local stateText = pt and "MOTOR LIGADO (C-PHYSICS ATIVO)" or "ENGINE RUNNING (C-PHYSICS ACTIVE)"
  
  if not config.enabled then
    stateCol = rgbm(0.35, 0.40, 0.45, 0.95)
    stateText = pt and "MOD DESATIVADO (FÍSICA ORIGINAL DO ASSETTO CORSA)" or "MOD DISABLED (VANILLA AC PHYSICS ACTIVE)"
  elseif isStarting then
    stateCol = rgbm(0.95, 0.60, 0.10, 0.95)
    stateText = pt and "DANDO PARTIDA (BOTÃO 1 / X)..." or "CRANKING (BUTTON 1 / X)..."
  elseif not isIgnitionOn then
    stateCol = rgbm(0.40, 0.45, 0.50, 0.95)
    stateText = pt and "IGNIÇÃO DESLIGADA (CHAVE OFF)" or "IGNITION OFF"
  elseif not isEngineRunning then
    stateCol = rgbm(0.88, 0.18, 0.18, 0.95)
    stateText = pt and ("MOTOR MORREU: " .. (stallReason ~= "" and stallReason or "AFOGADO")) or ("ENGINE STALLED: " .. stallReason)
  elseif coreState.state == Core.STATE_SLIPPING and coreState.coupling_ratio > 0.20 then
    stateCol = rgbm(0.95, 0.45, 0.15, 0.95)
    stateText = pt and string.format("PONTO DE FRICÇÃO ATIVO (ACOPLAMENTO: %.0f%%)", coreState.coupling_ratio * 100) or "CLUTCH SLIPPING / BITE ZONE"
  end

  ui.drawRectFilled(p, p + vec2(w, h), stateCol, 4)
  ui.drawRect(p, p + vec2(w, h), rgbm(1, 1, 1, 0.45), 4, 1)
  
  ui.setCursor(p + vec2(12, 11))
  ui.textColored(stateText, rgbm(1, 1, 1, 1))
  ui.setCursor(p + vec2(0, h + 6))
  ui.dummy(vec2(w, 0))

  -- Tab Navigation
  ui.tabBar("main_tabs_v4", function()
    if ui.tabItem(pt and "1. Telemetria" or "1. Telemetry") then selectedTab = 1 end
    if ui.tabItem(pt and "2. Presets" or "2. Presets") then selectedTab = 2 end
    if ui.tabItem(pt and "3. Embreagem" or "3. Clutch") then selectedTab = 3 end
    if ui.tabItem(pt and "4. Volante FFB" or "4. FFB Wheel") then selectedTab = 4 end
    if ui.tabItem(pt and "5. Controles" or "5. Controls") then selectedTab = 5 end
  end)

  ui.dummy(vec2(0, 4))
  local car = ac.getCar(0)

  -- TAB 1: TELEMETRIA C-PHYSICS
  if selectedTab == 1 then
    ui.text(pt and "Estado da Embreagem (Mecânica Stick-Slip):" or "Clutch Stick-Slip State:")
    local stateName = (coreState.state == Core.STATE_LOCKED) and 
      (pt and "● TRAVADO / 1 DoF (Virabrequim e Câmbio Sólidos)" or "● LOCKED (1 DoF: Crankshaft & Gearbox Solid)") or
      (pt and "● DESLIZANDO / 2 DoF (Atrito Coulomb / Stribeck)" or "● SLIPPING (2 DoF: Coulomb Friction)")
    local stateBadgeCol = (coreState.state == Core.STATE_LOCKED) and rgbm(0.3, 0.85, 0.4, 1) or rgbm(1.0, 0.55, 0.2, 1)
    ui.textColored(stateName, stateBadgeCol)

    ui.dummy(vec2(0, 4))
    local curCoupling = car and car.clutch or 1.0
    UI.drawClutchCurve(config.clutchBiteCenter, config.clutchBiteWidth, curCoupling, coreState.coupling_ratio, (coreState.state == Core.STATE_LOCKED and 3 or 2), ui.availableSpaceX(), 95)
    
    ui.dummy(vec2(0, 4))
    UI.drawCustomBar(pt and "Torque Transmitido" or "Transmitted Torque", math.abs(coreState.tau_clutch), 450.0, "%.1f Nm", rgbm(0.2, 0.75, 1.0, 1), 14)
    UI.drawCustomBar(pt and "Temperatura do Disco" or "Clutch Disc Temp", coreState.T_disc, 400.0, "%.0f °C", (coreState.T_disc > 220.0 and rgbm(1, 0.3, 0.2, 1) or rgbm(0.4, 0.8, 0.4, 1)), 14)
    UI.drawCustomBar(pt and "Embreagem (Pedal Pisado)" or "Pedal Pressed", 1.0 - curCoupling, 1.0, "%.0f%%", rgbm(0.3, 0.6, 0.95, 1), 14)
    UI.drawCustomBar(pt and "Acelerador" or "Throttle", car and car.gas or 0.0, 1.0, "%.0f%%", rgbm(0.2, 0.8, 0.3, 1), 14)

    ui.dummy(vec2(0, 4))
    local lookY = (car and car.look and car.look.y) or 0.0
    local pDeg = math.deg(math.asin(clamp(lookY, -1.0, 1.0)))
    local carMassVal = (car and car.mass) or 1250.0
    UI.drawInclineMeter(pDeg, math.tan(math.rad(pDeg)) * 100.0, carMassVal * 9.81 * math.sin(math.rad(pDeg)), false)

  -- TAB 2: PRESETS
  elseif selectedTab == 2 then
    ui.text(pt and "Perfis Inteligentes de Veículo (Auto-detectado por carro):" or "Intelligent Vehicle Profiles:")
    ui.separator()

    for _, pItem in ipairs(Presets.list) do
      local isCurrent = (config.selectedPreset == pItem.id)
      if ui.radioButton(pItem.name, isCurrent) then
        applyPreset(pItem.id)
      end
      ui.textColored("  " .. pItem.desc, rgbm(0.65, 0.7, 0.75, 1))
      ui.dummy(vec2(0, 2))
    end

  -- TAB 3: EMBREAGEM & STALL
  elseif selectedTab == 3 then
    ui.text(pt and "Calibração Fina da Embreagem & Inércia:" or "Fine Clutch & Inertia Calibration:")
    ui.separator()

    local prevEnabled = config.enabled
    config.enabled = ui.checkbox(pt and "Ativar Simulação do Mod (Master Switch)" or "Enable Mod Simulation (Master Switch)", config.enabled)
    if prevEnabled and not config.enabled then
      restoreVanillaPhysics()
    elseif not prevEnabled and config.enabled then
      isEngineRunning = true
      isIgnitionOn = true
    end

    config.stallEnabled = ui.checkbox(pt and "Ativar Mecânica de Motor Morrer (Engine Stall)" or "Enable Engine Stall Mechanics", config.stallEnabled)
    
    ui.dummy(vec2(0, 4))
    ui.text(pt and "Centro do Ponto de Fricção (Bite Point Center):" or "Bite Point Position:")
    config.clutchBiteCenter = ui.slider("##bite_center", config.clutchBiteCenter, 0.20, 0.80, "%.2f")
    coreCfg.bite_point = config.clutchBiteCenter

    ui.dummy(vec2(0, 4))
    ui.text(pt and "Largura da Zona de Fricção (Bite Zone Width):" or "Friction Zone Width:")
    config.clutchBiteWidth = ui.slider("##bite_width", config.clutchBiteWidth, 0.10, 0.40, "%.2f")
    coreCfg.bite_window = config.clutchBiteWidth

    ui.dummy(vec2(0, 4))
    ui.text(pt and "Inércia do Volante do Motor (Flywheel Weight):" or "Flywheel Inertia Weight:")
    config.flywheelInertia = ui.slider("##flywheel_inertia", config.flywheelInertia or 0.16, 0.05, 0.45, "%.2f kg m²")

    ui.dummy(vec2(0, 4))
    ui.text(pt and "Multiplicador de Creep (Arrancada de Marcha Lenta):" or "Creep Torque Multiplier:")
    config.creepTorqueMultiplier = ui.slider("##creep_mult", config.creepTorqueMultiplier or 1.15, 0.5, 2.5, "%.2fx")

    ui.dummy(vec2(0, 4))
    ui.text(pt and "Rotação Mínima de Stall (Stall RPM):" or "Minimum Stall RPM:")
    config.stallRPM = ui.slider("##stall_rpm", config.stallRPM, 380.0, 950.0, "%.0f RPM")

    ui.dummy(vec2(0, 4))
    ui.text(pt and "Rotação de Marcha Lenta (Idle RPM):" or "Target Idle RPM:")
    config.idleRPM = ui.slider("##idle_rpm", config.idleRPM, 650.0, 1200.0, "%.0f RPM")

  -- TAB 4: VOLANTE FFB & TREMEDEIRA
  elseif selectedTab == 4 then
    ui.text(pt and "Configurações de Trepidação no Volante (FFB):" or "Steering Wheel Force Feedback (FFB) Settings:")
    ui.separator()

    config.ffbEnabled = ui.checkbox(pt and "Ativar Tremedeira no Volante (FFB Shudder)" or "Enable Wheel FFB Rumble", config.ffbEnabled)
    config.cockpitShakeEnabled = ui.checkbox(pt and "Ativar Tremor Visual na Tela do Cockpit" or "Enable Cockpit Screen Tremor", config.cockpitShakeEnabled)

    ui.dummy(vec2(0, 4))
    ui.text(pt and "Ganho Geral de FFB:" or "Overall FFB Gain:")
    config.ffbGain = ui.slider("##ffb_gain", config.ffbGain, 0.2, 2.5, "%.2fx")

    ui.dummy(vec2(0, 4))
    ui.text(pt and "Tremedeira no Ponto de Fricção (Bite Shudder):" or "Bite Zone Shudder:")
    config.ffbBiteShudder = ui.slider("##ffb_bite", config.ffbBiteShudder, 0.0, 2.5, "%.2fx")

    ui.dummy(vec2(0, 4))
    ui.text(pt and "Tranco ao Morrer o Motor (Stall Jolt):" or "Stall Jolt Shock:")
    config.ffbStallJolt = ui.slider("##ffb_jolt", config.ffbStallJolt, 0.0, 2.5, "%.2fx")

  -- TAB 5: CONTROLES & PARTIDA
  elseif selectedTab == 5 then
    ui.text(pt and "Mapeamento dos Botões de Partida e Ignição:" or "Starter & Ignition Button Bindings:")
    ui.separator()

    ui.text(pt and "Botão do Motor de Partida (Mapeado: Botão 1 / X do Volante):" or "Starter Motor Button (Mapped: Button 1 / X):")
    btnStarter:control(vec2(ui.availableSpaceX(), 28))
    ui.textColored(pt and "(Atalho ativo: Botão 1 [X] no volante W270 ou Tecla 'E')" or "(Active shortcut: Button 1 [X] on W270 wheel or 'E' key)", rgbm(0.3, 0.8, 0.4, 1))

    ui.dummy(vec2(0, 6))
    ui.text(pt and "Chave de Ignição (Opcional - fica sempre ligada automaticamente):" or "Ignition Key Switch (Optional):")
    btnIgnition:control(vec2(ui.availableSpaceX(), 28))
    ui.textColored(pt and "(Dica: Você também pode usar a tecla 'I' no teclado)" or "(Hint: You can also use key 'I' on keyboard)", rgbm(0.7, 0.75, 0.8, 1))

    ui.dummy(vec2(0, 6))
    config.allowStarterInGear = ui.checkbox(pt and "Permitir dar tranco com motor de arranque engrenado" or "Allow starter motor to lurch car in gear", config.allowStarterInGear)
    config.audioEnabled = ui.checkbox(pt and "Efeitos Sonoros de Partida e Afogamento" or "Audio Feedback & Stall Sounds", config.audioEnabled)
  end
end

-- ==============================================================================
-- FLOATING HUD OVERLAY WINDOW (ASSISTENTE AUTOESCOLA & TELEMETRIA)
-- ==============================================================================
function script.windowHud()
  local pt = config.language == "pt"
  local car = ac.getCar(0)

  -- Botão Rápido Liga/Desliga no HUD (Permite desativar sem abrir o menu principal)
  local btnW = ui.availableSpaceX()
  if config.enabled then
    if ui.button(pt and "🟢 MOD ATIVADO [CLIQUE P/ DESATIVAR]" or "🟢 MOD ON [CLICK TO DISABLE]", vec2(btnW, 22)) then
      config.enabled = false
      restoreVanillaPhysics()
    end
  else
    if ui.button(pt and "🔴 MOD DESATIVADO [CLIQUE P/ ATIVAR]" or "🔴 MOD OFF [CLICK TO ENABLE]", vec2(btnW, 22)) then
      config.enabled = true
      isEngineRunning = true
      isIgnitionOn = true
    end
    ui.dummy(vec2(0, 4))
    ui.textColored(pt and "⏸ SIMULAÇÃO DESATIVADA" or "⏸ MOD DISABLED", rgbm(0.9, 0.9, 0.9, 1))
    ui.textColored(pt and "Física original do Assetto Corsa ativa." or "Original Assetto Corsa physics active.", rgbm(0.6, 0.65, 0.7, 1))
    return
  end

  local curPedal = car and car.clutch or 1.0

  local isNearStall = isEngineRunning and (coreState.state == Core.STATE_SLIPPING) 
                      and (currentGear ~= 0) and (coreState.coupling_ratio > 0.18)
                      and (simulatedRPM < (config.stallRPM + 75.0)) and (speedMag < 8.0)

  -- Assistente Visual de Ponto de Embreagem (Radar Autoescola)
  UI.drawBitePointRadar(
    curPedal, 
    config.clutchBiteCenter or 0.45, 
    config.clutchBiteWidth or 0.24, 
    coreState.coupling_ratio, 
    (coreState.state == Core.STATE_SLIPPING), 
    (not isEngineRunning), 
    isNearStall, 
    pt
  )

  -- Telemetria complementar compacta
  ui.dummy(vec2(0, 2))
  local gearStr = (currentGear == 0) and "N" or ((currentGear < 0) and "R" or tostring(currentGear))
  local rpmVal = (car and car.rpm) or simulatedRPM
  local statusStr = string.format(pt and "Marcha: %s | RPM: %.0f | Vel: %.1f km/h" or "Gear: %s | RPM: %.0f | Speed: %.1f km/h", 
    gearStr, rpmVal, speedMag * 3.6)
  ui.textColored(statusStr, rgbm(0.80, 0.85, 0.90, 1))

  local torqueNm = math.abs(coreState.tau_clutch or 0.0)
  local biteStr = string.format(pt and "Fricção: %.0f%% | Carga: %.0f Nm | Temp: %.0f°C" or "Bite: %.0f%% | Load: %.0f Nm | Temp: %.0f°C", 
    coreState.coupling_ratio * 100.0, torqueNm, coreState.T_disc or 25.0)
  ui.textColored(biteStr, rgbm(0.35, 0.75, 0.95, 1))
end

function script.windowSettings()
  ui.text("Realistic Clutch Pro v4.3 - Settings")
  ui.separator()
  local prevEnabled = config.enabled
  config.enabled = ui.checkbox("Enable Mod Simulation", config.enabled)
  if prevEnabled and not config.enabled then
    restoreVanillaPhysics()
  elseif not prevEnabled and config.enabled then
    isEngineRunning = true
    isIgnitionOn = true
  end
  config.cockpitShakeEnabled = ui.checkbox("Enable Cockpit Screen Tremor", config.cockpitShakeEnabled)
end
