--[[
  ==============================================================================
  Realistic Clutch & Stalling Pro - Vehicle Presets & Auto-Detection Database
  ==============================================================================
  Intelligent vehicle profiler for ANY car in Assetto Corsa (Fiat 500, Fiesta ST,
  BMW, Miata, Porsche, Diesels, Racecars, Drift, etc.)
  ==============================================================================
--]]

local Presets = {}

Presets.list = {
  {
    id = "autoescola",
    name = "★ Autoescola Brasil (1.0L Popular - Mobi / Gol / Onix / HB20)",
    desc = "Calibração idêntica ao carro da autoescola: motor 1.0 aspirado, ponto de embreagem a 45% com tremor nítido no volante e na tela, arrancada em marcha lenta e controle de rampa.",
    config = {
      idleRPM = 850.0,
      stallRPM = 540.0,
      clutchBiteCenter = 0.45,
      clutchBiteWidth = 0.24,
      biteAggressiveness = 2,
      clutchTorqueCapacity = 140.0,
      engineCylinders = 4,
      flywheelInertia = 0.13, -- Volante leve: afoga se soltar de vez, mas sai no plano se dosar no ponto
      creepTorqueMultiplier = 1.10,
      shudderIntensity = 1.65, -- Tremor visual e físico na tela acentuado para aprendizado
      ffbIdleRumble = 0.90,
      ffbBiteShudder = 1.55,  -- Vibração tátil no volante no ponto exato (15.5 Hz)
      ffbStallJolt = 1.30,
      allowStarterInGear = true,
      crankTimeToStart = 0.35
    }
  },
  {
    id = "city_compact",
    name = "Compacto / Urbano (Fiat 500 / Uno / Gol / Ka / 1.0L - 1.4L)",
    desc = "Volante de inércia leve, torque modesto em baixa rotação. Anda devagar no plano se soltar com carinho, mas morre na subida sem acelerador.",
    config = {
      idleRPM = 850.0,
      stallRPM = 520.0,
      clutchBiteCenter = 0.40,
      clutchBiteWidth = 0.26,
      biteAggressiveness = 2,
      clutchTorqueCapacity = 150.0,
      engineCylinders = 4,
      flywheelInertia = 0.12, -- Drena em ~0.45s sob carga total
      creepTorqueMultiplier = 1.0,
      shudderIntensity = 1.30,
      ffbIdleRumble = 0.85,
      ffbBiteShudder = 1.35,
      ffbStallJolt = 1.15,
      allowStarterInGear = true,
      crankTimeToStart = 0.35
    }
  },
  {
    id = "standard_road",
    name = "Carro de Rua Médio (Fiesta ST / Golf / Civic / Miata / 1.6L - 2.0L)",
    desc = "Comportamento equilibrado e progressivo. Arranca suavemente sem acelerar no plano, excelente sustentação na embreagem.",
    config = {
      idleRPM = 850.0,
      stallRPM = 500.0,
      clutchBiteCenter = 0.45,
      clutchBiteWidth = 0.28,
      biteAggressiveness = 2,
      clutchTorqueCapacity = 250.0,
      engineCylinders = 4,
      flywheelInertia = 0.18, -- Drena em ~0.60s sob carga
      creepTorqueMultiplier = 1.15,
      shudderIntensity = 1.10,
      ffbIdleRumble = 0.75,
      ffbBiteShudder = 1.15,
      ffbStallJolt = 1.10,
      allowStarterInGear = true,
      crankTimeToStart = 0.35
    }
  },
  {
    id = "turbodiesel",
    name = "Turbodiesel / Utilitário (TDI / Hilux / Ranger / Amarok / Toro)",
    desc = "Torque massivo em marcha lenta. Quase impossível de afogar no plano, sobe rampas leves apenas controlando a embreagem.",
    config = {
      idleRPM = 780.0,
      stallRPM = 440.0,
      clutchBiteCenter = 0.45,
      clutchBiteWidth = 0.32,
      biteAggressiveness = 4,
      clutchTorqueCapacity = 480.0,
      engineCylinders = 4,
      flywheelInertia = 0.32, -- Volante pesado
      creepTorqueMultiplier = 1.60,
      shudderIntensity = 1.45,
      ffbIdleRumble = 1.25,
      ffbBiteShudder = 1.10,
      ffbStallJolt = 1.40,
      allowStarterInGear = true,
      crankTimeToStart = 0.45
    }
  },
  {
    id = "sports_car",
    name = "Esportivo / Alta Performance (BMW M3 / Porsche 911 / Supra / V6-V8)",
    desc = "Resposta rápida e torque encorpado. Ponto de fricção direto e firme com harmônicos ricos no volante.",
    config = {
      idleRPM = 900.0,
      stallRPM = 580.0,
      clutchBiteCenter = 0.48,
      clutchBiteWidth = 0.22,
      biteAggressiveness = 3,
      clutchTorqueCapacity = 420.0,
      engineCylinders = 6,
      flywheelInertia = 0.15,
      creepTorqueMultiplier = 1.10,
      shudderIntensity = 1.05,
      ffbIdleRumble = 0.70,
      ffbBiteShudder = 1.20,
      ffbStallJolt = 1.25,
      allowStarterInGear = true,
      crankTimeToStart = 0.30
    }
  },
  {
    id = "race_multiplate",
    name = "Carro de Competição (Multidisco Cerâmica / GT3 / Cup / Drift)",
    desc = "Embreagem de competição On/Off. Zona de fricção estreita, trepidação metálica agressiva se patinar.",
    config = {
      idleRPM = 1100.0,
      stallRPM = 750.0,
      clutchBiteCenter = 0.52,
      clutchBiteWidth = 0.14,
      biteAggressiveness = 3,
      clutchTorqueCapacity = 750.0,
      engineCylinders = 8,
      flywheelInertia = 0.08, -- Volante ultraleve
      creepTorqueMultiplier = 0.70,
      shudderIntensity = 1.60,
      ffbIdleRumble = 0.90,
      ffbBiteShudder = 1.60,
      ffbStallJolt = 1.50,
      allowStarterInGear = false,
      crankTimeToStart = 0.25
    }
  }
}

function Presets.getById(id)
  for _, p in ipairs(Presets.list) do
    if p.id == id then
      return p
    end
  end
  return Presets.list[1] -- Default to Autoescola Brasil
end

-- Detecção Inteligente Automática para qualquer carro no jogo
function Presets.detectForCar(car)
  if not car then return Presets.list[1] end

  local carName = ""
  pcall(function()
    if car and car.id then carName = string.lower(car.id) end
    if carName == "" and ac.getCarID then carName = string.lower(ac.getCarID(0) or "") end
    if carName == "" and ac.getCarName then carName = string.lower(ac.getCarName(0) or "") end
  end)

  local mass = car.mass or 1200.0

  -- 1. Carros de Corrida / GT3 / Cup / Drift
  if string.find(carName, "gt3") or string.find(carName, "gt4") or string.find(carName, "cup") 
     or string.find(carName, "race") or string.find(carName, "formula") or string.find(carName, "drift") 
     or string.find(carName, "f1") or string.find(carName, "soper") then
    return Presets.list[6]
  end

  -- 2. Carros Turbodiesel / Pickups / Vans
  if string.find(carName, "diesel") or string.find(carName, "tdi") or string.find(carName, "dci") 
     or string.find(carName, "hilux") or string.find(carName, "ranger") or string.find(carName, "amarok") 
     or string.find(carName, "transit") or string.find(carName, "iveco") then
    return Presets.list[4]
  end

  -- 3. Superesportivos / Muscle / V6 / V8
  if string.find(carName, "ferrari") or string.find(carName, "porsche") or string.find(carName, "lamborghini") 
     or string.find(carName, "m3") or string.find(carName, "m4") or string.find(carName, "m5") 
     or string.find(carName, "amg") or string.find(carName, "corvette") or string.find(carName, "mustang") 
     or string.find(carName, "supra") or string.find(carName, "gtr") or string.find(carName, "viper") then
    return Presets.list[5]
  end

  -- 4. Autoescola Brasil & Compactos Populares (Mobi, Onix, Gol, HB20, Uno, Palio, Kwid, 500, Abarth, Ka, Corsa, etc.)
  if string.find(carName, "mobi") or string.find(carName, "onix") or string.find(carName, "hb20")
     or string.find(carName, "kwid") or string.find(carName, "gol") or string.find(carName, "uno")
     or string.find(carName, "palio") or string.find(carName, "siena") or string.find(carName, "etios")
     or string.find(carName, "500") or string.find(carName, "abarth") or string.find(carName, "fiat") 
     or string.find(carName, "ka") or string.find(carName, "corsa") or string.find(carName, "clio") 
     or string.find(carName, "polo") or string.find(carName, "up") or string.find(carName, "c1") 
     or string.find(carName, "aygo") or string.find(carName, "yaris") or string.find(carName, "206") 
     or string.find(carName, "208") or mass < 1120.0 then
    return Presets.list[1]
  end

  -- 5. Carro de Rua Padrão (Fiesta, Focus, Golf, Civic, Astra, Cruze, etc.)
  return Presets.list[3]
end

return Presets
