--[[
  ==============================================================================
  Realistic Clutch Pro - High-Speed Shared Memory Layout (IPC v4.1)
  ==============================================================================
  Defines the C-struct layout for zero-latency (<2ns) shared memory communication
  between the in-game simulation app (RealisticClutchPro) and the 333 Hz DirectInput
  FFB post-processor (RealisticClutchFFB).
  ==============================================================================
--]]

local M = {}

M.LAYOUT = {
  ac.StructItem.key("RealisticClutch_IPC_v41"),
  
  -- Master Handshake & Watchdog
  appActive             = ac.StructItem.boolean(),
  version               = ac.StructItem.int32(),
  heartbeat             = ac.StructItem.double(),

  -- Engine & Vehicle Configuration
  cylinderCount         = ac.StructItem.int32(),   -- e.g. 4, 6, 8
  idleRpm               = ac.StructItem.float(),   -- Target idle RPM (e.g. 850)
  stallRpm              = ac.StructItem.float(),   -- Minimum threshold before stall (e.g. 520)
  maxTorqueNm           = ac.StructItem.float(),   -- Peak engine torque

  -- Real-Time Clutch Simulation Telemetry (Written by RealisticClutchPro @ 333 Hz)
  clutchBitePosition    = ac.StructItem.float(),   -- Physical bite point [0..1]
  clutchEngagement      = ac.StructItem.float(),   -- Actual plate clamp [0..1]
  clutchSlipRpm         = ac.StructItem.float(),   -- Flywheel RPM - Input Shaft RPM
  clutchTorqueNm        = ac.StructItem.float(),   -- Instantaneous transmitted clutch torque
  clutchTemperatureC    = ac.StructItem.float(),   -- Plate temp in deg C
  clutchGlazeFactor     = ac.StructItem.float(),   -- Glazing/wear coefficient [0..1]
  drivelineWindupNm     = ac.StructItem.float(),   -- Torsional windup torque
  isStalling            = ac.StructItem.boolean(), -- True if engine is in stall-buck phase
  stallRecoilTrigger    = ac.StructItem.boolean(), -- Pulsed high when crankshaft locks up

  -- FFB Haptic Gain Tuning (From UI Sliders)
  gainMaster            = ac.StructItem.float(),   -- Master clutch FFB gain [0..2]
  gainJudder            = ac.StructItem.float(),   -- 8-14 Hz judder gain
  gainChatter           = ac.StructItem.float(),   -- 25-45 Hz micro-chatter gain
  gainCombustion        = ac.StructItem.float(),   -- Engine firing harmonics gain
  gainLugging           = ac.StructItem.float()    -- Pre-stall bucking & recoil gain
}

return M
