--[[
  ==============================================================================
  Realistic Clutch Pro - Drivetrain & Vehicle Load Dynamics (drivetrain_model.lua)
  ==============================================================================
  Calculates reflected inertia (It), road resistance forces (aerodynamic,
  rolling friction, gravitational incline, wheel brake torque), and
  engine combustion / starter torque maps.
  ==============================================================================
--]]

local Drivetrain = {}

local function clamp(val, minVal, maxVal)
  if val < minVal then return minVal end
  if val > maxVal then return maxVal end
  return val
end

-- Default Drivetrain Physical Specifications
function Drivetrain.newConfig(custom)
  local c = {
    I_shaft_bare = 0.012,       -- [kg*m^2] Bare gearbox input shaft inertia in neutral
    wheel_inertia = 4.8,        -- [kg*m^2] Combined 4-wheel/rotor polar inertia
    wheel_radius = 0.315,       -- [m] Loaded tire dynamic rolling radius
    dt_efficiency = 0.94,       -- Transmission & differential mechanical efficiency
    final_drive = 3.85,         -- Final drive axle ratio
    gear_ratios = {
      [-1] = -3.45,             -- Reverse
      [0]  = 0.0,               -- Neutral
      [1]  = 3.58,              -- 1st Gear
      [2]  = 2.05,              -- 2nd Gear
      [3]  = 1.35,              -- 3rd Gear
      [4]  = 1.03,              -- 4th Gear
      [5]  = 0.82,              -- 5th Gear
      [6]  = 0.68               -- 6th Gear
    },
    car_mass = 1250.0,          -- [kg]
    cd_area = 0.72,             -- Cd * Af (drag area)
    c_rr = 0.015,               -- Rolling resistance coefficient
    max_brake_force = 14000.0,  -- [N] Full brake hydraulic clamping force
    
    -- Starter Motor Specs
    starter_torque_max = 500.0, -- [N*m] Starter ring-gear stall torque
    starter_no_load_rpm = 1400.0-- [RPM] Starter cutoff speed
  }

  if custom then
    for k, v in pairs(custom) do c[k] = v end
  end
  return c
end

-- Effective Reflected Inertia (It) at the gearbox input shaft
function Drivetrain.calculateReflectedInertia(cfg, gear, carMass)
  local m = carMass or cfg.car_mass
  local ratio = cfg.gear_ratios[gear] or 0.0
  
  if gear == 0 or math.abs(ratio) < 1e-4 then
    -- NEUTRAL: Input shaft completely decoupled from road mass
    return cfg.I_shaft_bare
  end
  
  local i_tot = ratio * cfg.final_drive
  local I_reflected = (cfg.wheel_inertia + m * cfg.wheel_radius * cfg.wheel_radius)
                      / (i_tot * i_tot * cfg.dt_efficiency)
  
  return cfg.I_shaft_bare + I_reflected
end

function Drivetrain.calculateKinematicInputShaftSpeed(cfg, gear, v_veh)
  local ratio = cfg.gear_ratios[gear] or 0.0
  if gear == 0 or math.abs(ratio) < 1e-4 then
    return nil -- Neutral: input shaft is decoupled from road wheels
  end
  local u_gear = (gear > 0) and 1.0 or ((gear == -1) and -1.0 or 0.0)
  local abs_ratio = math.abs(ratio)
  local i_tot = abs_ratio * cfg.final_drive
  local v_drive = v_veh * u_gear
  local omega_wheel = (cfg.wheel_radius > 0.0) and (v_drive / cfg.wheel_radius) or 0.0
  return omega_wheel * i_tot
end

-- Road Load Torque (tau_load) reflected back onto the input shaft
function Drivetrain.calculateRoadLoad(cfg, gear, v_veh, pitchRad, brakeInput, handbrakeInput, omega_t, carMass)
  local m = carMass or cfg.car_mass
  local ratio = cfg.gear_ratios[gear] or 0.0
  
  -- In Neutral: pure viscous bearing / transmission oil churning drag
  if gear == 0 or math.abs(ratio) < 1e-4 then
    return 0.06 * omega_t
  end
  
  local u_gear = (gear > 0) and 1.0 or ((gear == -1) and -1.0 or 0.0)
  local abs_ratio = math.abs(ratio)
  local i_tot = abs_ratio * cfg.final_drive
  local v_drive = v_veh * u_gear
  local sgn_drive = (v_drive > 0.02) and 1.0 or ((v_drive < -0.02) and -1.0 or 1.0)
  
  -- 1. Aerodynamic drag (opposes drive direction)
  local F_aero = 0.5 * 1.225 * cfg.cd_area * (v_veh * v_veh) * sgn_drive
  
  -- 2. Rolling resistance (opposes drive direction)
  local cosPitch = math.cos(pitchRad)
  local F_roll = m * 9.81 * cosPitch * cfg.c_rr * sgn_drive
  
  -- 3. Gravitational incline force (+ Opposes drive uphill, - Assists drive downhill)
  local sinPitch = math.sin(pitchRad)
  local F_grade = m * 9.81 * sinPitch * u_gear
  
  -- 4. Brakes (Wheel friction pads oppose drive direction)
  local brakeCombined = clamp((brakeInput or 0.0) + (handbrakeInput or 0.0), 0.0, 1.0)
  local F_brakes = brakeCombined * cfg.max_brake_force * sgn_drive
  
  local F_total = F_aero + F_roll + F_grade + F_brakes
  
  -- Reflect to input shaft through total ratio and efficiency
  local tau_load = (F_total * cfg.wheel_radius) / (i_tot * cfg.dt_efficiency)
  return tau_load
end

-- Combustion Indicated Torque & Electric Starter Torque
function Drivetrain.calculateEngineTorque(cfg, omega_e, throttleInput, isIgnitionOn, isStalled, starterActive, idleRPM, maxTorque)
  if not isIgnitionOn or isStalled then
    -- Engine dead: only starter motor can spin crankshaft
    if starterActive and omega_e < (cfg.starter_no_load_rpm * 0.10472) then
      local starterRatio = 1.0 - (omega_e / (cfg.starter_no_load_rpm * 0.10472))
      return cfg.starter_torque_max * clamp(starterRatio, 0.0, 1.0)
    end
    return 0.0
  end
  
  local rpm = omega_e * 9.549296 -- rad/s to RPM
  local targetIdle = idleRPM or 850.0
  local peakT = maxTorque or 240.0
  
  -- Natural ICE indicated torque curve (WOT envelope)
  local normRPM = clamp((rpm - targetIdle) / 5500.0, 0.0, 1.0)
  local wotTorque = peakT * (0.65 + 0.35 * math.sin(normRPM * math.pi))
  
  -- Throttled combustion torque
  local tps = clamp(throttleInput or 0.0, 0.0, 1.0)
  local tau_combustion = (0.12 + 0.88 * tps) * wotTorque
  
  -- Active Idle Speed Governor (anti-stall closed loop)
  if rpm < (targetIdle + 80.0) and tps < 0.15 then
    local deficit = clamp((targetIdle - rpm) / targetIdle, 0.0, 1.0)
    tau_combustion = tau_combustion + (peakT * 0.40 * clamp(deficit * 2.5, 0.0, 1.0))
  end
  
  -- Starter motor torque assist during cranking
  if starterActive and rpm < 1200.0 then
    tau_combustion = tau_combustion + (cfg.starter_torque_max * 0.5)
  end
  
  -- Parasitic mechanical engine drag (pumping losses + journal bearing friction)
  local tau_drag = 10.0 + (0.04 * omega_e)
  
  return math.max(0.0, tau_combustion - tau_drag)
end

return Drivetrain
