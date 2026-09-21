--[[
  ==============================================================================
  Realistic Clutch & Stalling Pro - Sound & Audio Engine
  Assetto Corsa CSP Lua Audio Feedback & Sound Synthesizer
  ==============================================================================
--]]

local Audio = {}

local function clamp(val, minVal, maxVal)
  if val < minVal then return minVal end
  if val > maxVal then return maxVal end
  return val
end

function Audio.newState()
  return {
    starterSoundPlaying = false,
    stallSoundTriggered = false,
    crankAudioTimer = 0.0,
    grindAudioTimer = 0.0,
    beepTimer = 0.0,
    audioAvailable = false,
    audioEvents = {}
  }
end

function Audio.init(audioState)
  -- Check if CSP AudioEvent is available
  if ac.AudioEvent then
    audioState.audioAvailable = true
  end
end

-- Update and play audio cues based on physics events
function Audio.update(audioState, physicsState, config, car, dt)
  if not config.audioEnabled then return end
  if dt <= 0 or dt > 0.5 then dt = 0.016 end

  -- 1. Starter Cranking Audio
  if physicsState.isStarterEngaged and physicsState.isIgnitionOn then
    audioState.crankAudioTimer = audioState.crankAudioTimer + dt
    if not audioState.starterSoundPlaying then
      audioState.starterSoundPlaying = true
      -- If CSP audio event exists, play starter sound
      if audioState.audioAvailable and ac.AudioEvent then
        pcall(function()
          local ev = ac.AudioEvent("cars/own/starter_crank")
          if ev then ev:start() end
        end)
      end
    end
  else
    audioState.starterSoundPlaying = false
    audioState.crankAudioTimer = 0.0
  end

  -- 2. Engine Stall Sputter Sound
  if physicsState.isStalled and not audioState.stallSoundTriggered then
    audioState.stallSoundTriggered = true
    if audioState.audioAvailable and ac.AudioEvent then
      pcall(function()
        local ev = ac.AudioEvent("cars/own/engine_stall")
        if ev then ev:start() end
      end)
    end
  elseif not physicsState.isStalled then
    audioState.stallSoundTriggered = false
  end
end

return Audio
