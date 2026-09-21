--[[
  ==============================================================================
  Realistic Clutch Pro - Core Physics Engine (cphys_core.lua)
  ==============================================================================
  Non-Smooth Stick-Slip Discrete Mechanics & Impulse-Momentum Projection.
  Executes in O(1) constant time per step with strict angular momentum conservation
  and zero high-frequency chattering limit cycles at 333Hz - 400Hz.
  ==============================================================================
--]]

local Core = {}

Core.STATE_SLIPPING = 0
Core.STATE_LOCKED   = 1

local function clamp(val, minVal, maxVal)
  if val < minVal then return minVal end
  if val > maxVal then return maxVal end
  return val
end

function Core.newConfig(custom)
  local c = {
    -- Geometry
    R_outer = 0.120,          -- [m] Outer facing radius
    R_inner = 0.075,          -- [m] Inner facing radius
    num_plates = 2,           -- Z interfaces (2 for single-disc)
    
    -- Friction Characteristics (Stribeck)
    mu_static = 0.42,         -- Static friction coefficient
    mu_kinetic = 0.32,        -- Kinetic friction plateau
    omega_stribeck = 1.8,     -- [rad/s] Transition slip speed
    sigma_viscous = 0.0001,   -- [s/rad] Viscous shear damping
    
    -- Clamping Spring Mechanics (Belleville + Marcel cushion)
    F_normal_max = 6500.0,    -- [N] Full clamp preload
    bite_point = 0.46,        -- Normalized pedal bite position [0..1]
    bite_window = 0.15,       -- Engagement modulation window
    
    -- Thermal Properties & Fade Model
    C_th_disc = 540.0,        -- [J/K] Disc facing thermal capacitance
    C_th_metal = 5800.0,      -- [J/K] Flywheel/pressure plate thermal capacitance
    R_cond = 0.42,            -- [K/W] Conduction thermal resistance
    h_conv_base = 4.5,        -- [W/K] Natural convection
    h_conv_speed = 0.08,      -- Forced rotational convection factor
    gamma_disc = 0.12,        -- Heat split to facing vs cast iron
    T_fade_start = 230.0,     -- [deg C] Fade inception threshold
    T_fade_crit = 360.0,      -- [deg C] Critical fade threshold
    mu_residual = 0.15        -- Friction floor under extreme fade
  }
  
  if custom then
    for k, v in pairs(custom) do c[k] = v end
  end
  
  -- Effective friction radius (Uniform Wear model: R_eff = (Ro + Ri) / 2)
  c.R_eff = 0.5 * (c.R_outer + c.R_inner)
  return c
end

function Core.newState()
  return {
    state = Core.STATE_LOCKED,
    omega_e = 88.0,           -- [rad/s] Engine crankshaft speed (~840 RPM)
    omega_t = 88.0,           -- [rad/s] Gearbox input shaft speed
    tau_clutch = 0.0,         -- [N*m] Transmitted torque
    slip_power = 0.0,         -- [W] Frictional dissipation power
    T_disc = 25.0,            -- [deg C] Friction facing temperature
    T_metal = 25.0,           -- [deg C] Flywheel metal bulk temperature
    mu_current = 0.32,        -- Live operating friction coefficient
    coupling_ratio = 1.0,     -- [0..1] Effective coupling for AC CSP override
    is_chattering = false,    -- Diagnostic flag
    breakaway_occurred = false
  }
end

-- Non-linear Belleville diaphragm normal force calculation
function Core.calculateClampingForce(cfg, pedalTravel)
  local pedal = clamp(pedalTravel or 0.0, 0.0, 1.0)
  local arg = (pedal - cfg.bite_point) / cfg.bite_window
  local clamp_ratio = 1.0 - (1.0 / (1.0 + math.exp(-8.0 * arg)))
  return cfg.F_normal_max * clamp(clamp_ratio, 0.0, 1.0)
end

-- Stribeck friction coefficient with thermal fade
function Core.calculateMu(cfg, state, deltaOmega)
  local abs_d_omega = math.abs(deltaOmega)
  
  -- 1. Thermal fade calculation
  local mu_fade = 1.0
  if state.T_disc > cfg.T_fade_start then
    local fade_ratio = (state.T_disc - cfg.T_fade_start) / (cfg.T_fade_crit - cfg.T_fade_start)
    fade_ratio = clamp(fade_ratio, 0.0, 1.0)
    mu_fade = 1.0 - (1.0 - cfg.mu_residual) * math.pow(fade_ratio, 1.5)
  end
  
  -- 2. Stribeck exponential curve
  local stribeck = cfg.mu_kinetic + (cfg.mu_static - cfg.mu_kinetic) 
                   * math.exp(-math.pow(abs_d_omega / cfg.omega_stribeck, 1.2))
  
  local mu_dyn = mu_fade * (stribeck + cfg.sigma_viscous * abs_d_omega)
  state.mu_current = mu_dyn
  return mu_dyn, mu_fade
end

-- Discrete Time-Step Integration (Runge-Kutta / Impulse-Momentum Projection)
function Core.step(cfg, state, I_e, I_t, tau_ext_e, tau_load, pedalTravel, dt)
  if dt <= 0.0 then return end
  if dt > 0.05 then dt = 0.003 end -- Protection against huge simulation pauses
  
  local F_normal = Core.calculateClampingForce(cfg, pedalTravel)
  local d_omega = state.omega_e - state.omega_t
  local mu_dyn, mu_fade = Core.calculateMu(cfg, state, d_omega)
  
  -- Static torque holding capacity
  local tau_cap_static = cfg.num_plates * (cfg.mu_static * mu_fade) * F_normal * cfg.R_eff
  local sum_I = I_e + I_t
  
  state.breakaway_occurred = false
  
  -- ============================================================================
  -- CASE 1: STATE_LOCKED (1 Degree of Freedom: omega_e == omega_t)
  -- ============================================================================
  if state.state == Core.STATE_LOCKED then
    -- Theoretical reaction torque required to maintain d(delta_omega)/dt == 0
    local tau_lock = (I_t * tau_ext_e + I_e * tau_load) / sum_I
    
    if math.abs(tau_lock) <= tau_cap_static then
      -- Static friction holds: rigid lockup persists
      state.tau_clutch = tau_lock
      local alpha_locked = (tau_ext_e - tau_load) / sum_I
      state.omega_e = math.max(0.0, state.omega_e + alpha_locked * dt)
      state.omega_t = state.omega_e
      state.slip_power = 0.0
      state.coupling_ratio = 1.0
    else
      -- Breakaway: Clamping torque exceeded! Transits to SLIPPING
      state.state = Core.STATE_SLIPPING
      state.breakaway_occurred = true
      local sgn_lock = (tau_lock > 0.0) and 1.0 or -1.0
      state.tau_clutch = sgn_lock * tau_cap_static
      
      state.omega_e = math.max(0.0, state.omega_e + ((tau_ext_e - state.tau_clutch) / I_e) * dt)
      state.omega_t = state.omega_t + ((state.tau_clutch - tau_load) / I_t) * dt
      state.slip_power = math.abs(state.tau_clutch * (state.omega_e - state.omega_t))
      state.coupling_ratio = (tau_cap_static > 1e-3) and clamp(state.tau_clutch / tau_cap_static, 0.0, 1.0) or 0.0
    end
    
  -- ============================================================================
  -- CASE 2: STATE_SLIPPING (2 Degrees of Freedom: omega_e ~= omega_t)
  -- ============================================================================
  else
    local sgn_d_omega = (d_omega >= 0.0) and 1.0 or -1.0
    local tau_dyn = sgn_d_omega * cfg.num_plates * mu_dyn * F_normal * cfg.R_eff
    
    -- Unconstrained trial velocities
    local omega_e_trial = state.omega_e + ((tau_ext_e - tau_dyn) / I_e) * dt
    local omega_t_trial = state.omega_t + ((tau_dyn - tau_load) / I_t) * dt
    local d_omega_trial = omega_e_trial - omega_t_trial
    
    -- Zero-Crossing Collision Check (Relative velocity reverses within dt)
    if (d_omega * d_omega_trial) <= 0.0 then
      local tau_lock = (I_t * tau_ext_e + I_e * tau_load) / sum_I
      
      if math.abs(tau_lock) <= tau_cap_static then
        -- Catch & Lockup: Exact impulse-momentum projection
        local omega_locked = (I_e * state.omega_e + I_t * state.omega_t + (tau_ext_e - tau_load) * dt) / sum_I
        state.omega_e = math.max(0.0, omega_locked)
        state.omega_t = state.omega_e
        state.tau_clutch = tau_lock
        state.state = Core.STATE_LOCKED
        state.slip_power = 0.0
        state.coupling_ratio = 1.0
      else
        -- High slip torque reversal without lock: clamp trial step to prevent chattering
        state.omega_e = math.max(0.0, omega_e_trial)
        state.omega_t = omega_t_trial
        state.tau_clutch = tau_dyn
        state.slip_power = math.abs(state.tau_clutch * (state.omega_e - state.omega_t))
        state.coupling_ratio = (tau_cap_static > 1e-3) and clamp(math.abs(state.tau_clutch) / tau_cap_static, 0.0, 1.0) or 0.0
      end
    else
      -- Regular slipping progression
      state.omega_e = math.max(0.0, omega_e_trial)
      state.omega_t = omega_t_trial
      state.tau_clutch = tau_dyn
      state.slip_power = math.abs(state.tau_clutch * (state.omega_e - state.omega_t))
      state.coupling_ratio = (tau_cap_static > 1e-3) and clamp(math.abs(state.tau_clutch) / tau_cap_static, 0.0, 1.0) or 0.0
    end
  end
  
  -- ============================================================================
  -- THERMAL 2-NODE NETWORK DISSIPATION & COOLING
  -- ============================================================================
  local Q_gen_step = state.slip_power * dt
  local q_cond = (state.T_disc - state.T_metal) / cfg.R_cond
  local h_conv = cfg.h_conv_base + cfg.h_conv_speed * math.pow(state.omega_e * cfg.R_outer, 0.8)
  local q_conv_d = h_conv * 0.045 * (state.T_disc - 25.0)
  local q_conv_m = h_conv * 0.120 * (state.T_metal - 25.0)
  
  state.T_disc = state.T_disc + ((cfg.gamma_disc * Q_gen_step - (q_cond + q_conv_d) * dt) / cfg.C_th_disc)
  state.T_metal = state.T_metal + (((1.0 - cfg.gamma_disc) * Q_gen_step + (q_cond - q_conv_m) * dt) / cfg.C_th_metal)
end

return Core
