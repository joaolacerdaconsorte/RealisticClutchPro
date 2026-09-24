--[[
  ==============================================================================
  Realistic Clutch & Stalling Pro - UI Components (v2.0)
  ==============================================================================
--]]

local UI = {}

local function clamp(val, minVal, maxVal)
  if val < minVal then return minVal end
  if val > maxVal then return maxVal end
  return val
end

-- Draw 4-Stage OEM Interactive Clutch Curve
function UI.drawClutchCurve(biteCenter, biteWidth, currentPedal, engagement, stage, width, height)
  local pos = ui.getCursor()
  local w = width or 320
  local h = height or 95
  
  -- Card background
  ui.drawRectFilled(pos, pos + vec2(w, h), rgbm(0.08, 0.10, 0.13, 0.95), 5)
  ui.drawRect(pos, pos + vec2(w, h), rgbm(0.25, 0.32, 0.42, 0.8), 5, 1)

  local startBite = clamp(biteCenter - (biteWidth * 0.5), 0.15, 0.70)
  local endBite = clamp(biteCenter + (biteWidth * 0.5), startBite + 0.10, 0.95)

  -- Draw 4 colored zone bands
  -- Estágio 0: Folga (Cinza)
  local x0 = pos.x
  local x1 = pos.x + (startBite * w)
  local xCenter = pos.x + (biteCenter * w)
  local x2 = pos.x + (endBite * w)
  local x3 = pos.x + w

  ui.drawRectFilled(vec2(x0, pos.y), vec2(x1, pos.y + h), rgbm(0.2, 0.25, 0.3, 0.15), 0)
  -- Estágio 1: Arrasto / Creep (Azul esverdeado)
  ui.drawRectFilled(vec2(x1, pos.y), vec2(xCenter, pos.y + h), rgbm(0.1, 0.6, 0.8, 0.20), 0)
  -- Estágio 2: Ponto Crítico de Fricção (Laranja / Âmbar vibrante)
  ui.drawRectFilled(vec2(xCenter, pos.y), vec2(x2, pos.y + h), rgbm(0.95, 0.55, 0.1, 0.30), 0)
  -- Estágio 3: Travamento Total (Verde)
  ui.drawRectFilled(vec2(x2, pos.y), vec2(x3, pos.y + h), rgbm(0.2, 0.8, 0.3, 0.15), 0)

  -- Zone Divider lines
  ui.drawLine(vec2(x1, pos.y), vec2(x1, pos.y + h), rgbm(0.3, 0.7, 0.9, 0.5), 1)
  ui.drawLine(vec2(xCenter, pos.y), vec2(xCenter, pos.y + h), rgbm(1.0, 0.6, 0.1, 0.8), 1.5)
  ui.drawLine(vec2(x2, pos.y), vec2(x2, pos.y + h), rgbm(0.3, 0.9, 0.4, 0.5), 1)

  -- Plot 4-stage curve
  local lastPoint = nil
  local steps = 40
  for i = 0, steps do
    local t = i / steps -- 0 to 1
    local eng = 0.0
    if t < startBite then
      eng = 0.0
    elseif t >= endBite then
      eng = 1.0
    elseif t < biteCenter then
      local rel = (t - startBite) / (biteCenter - startBite)
      eng = rel * rel * 0.35
    else
      local rel = (t - biteCenter) / (endBite - biteCenter)
      local s = rel * (2.0 - rel)
      eng = 0.35 + (s * 0.65)
    end
    
    local px = pos.x + (t * w)
    local py = pos.y + h - (eng * (h - 14)) - 7
    local curPoint = vec2(px, py)
    
    if lastPoint then
      local lineCol = (eng > 0.35 and eng < 0.85) and rgbm(1.0, 0.65, 0.15, 1.0) or (eng >= 0.85 and rgbm(0.3, 0.95, 0.4, 1.0) or rgbm(0.4, 0.7, 0.9, 0.8))
      ui.drawLine(lastPoint, curPoint, lineCol, 2)
    end
    lastPoint = curPoint
  end

  -- Cursor do pedal atual (0.0 no fundo -> 1.0 solto)
  local curTravel = clamp(currentPedal, 0.0, 1.0)
  local cursorX = pos.x + (curTravel * w)
  local cursorY = pos.y + h - (engagement * (h - 14)) - 7
  
  ui.drawLine(vec2(cursorX, pos.y), vec2(cursorX, pos.y + h), rgbm(1.0, 1.0, 1.0, 0.75), 1.5)
  
  local dotCol = (stage == 2) and rgbm(1.0, 0.25, 0.25, 1.0) or ((stage == 1) and rgbm(1.0, 0.7, 0.1, 1.0) or rgbm(0.3, 0.8, 1.0, 1.0))
  ui.drawCircleFilled(vec2(cursorX, cursorY), 6.0, dotCol)
  ui.drawCircle(vec2(cursorX, cursorY), 7.0, rgbm(1, 1, 1, 0.9), 12, 1.5)

  ui.dummy(vec2(w, h))
end

-- Telemetry bar
function UI.drawCustomBar(title, value, maxVal, formatStr, barColor, height)
  local h = height or 16
  local val = clamp(value, 0.0, maxVal)
  local fraction = val / maxVal
  
  ui.text(title)
  ui.sameLine(ui.availableSpaceX() - 65)
  ui.text(string.format(formatStr, value * 100.0))

  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  
  ui.drawRectFilled(p, p + vec2(w, h), rgbm(0.12, 0.14, 0.18, 0.9), 3)
  if fraction > 0.005 then
    ui.drawRectFilled(p, p + vec2(w * fraction, h), barColor, 3)
  end
  ui.drawRect(p, p + vec2(w, h), rgbm(0.3, 0.35, 0.42, 0.6), 3, 1)

  ui.dummy(vec2(w, h + 3))
end

-- Incline & Hill balance meter
function UI.drawInclineMeter(pitchDeg, gradePercent, gravityForce, isBalancing)
  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  local h = 48
  
  local bgColor = isBalancing and rgbm(0.15, 0.45, 0.2, 0.8) or rgbm(0.12, 0.14, 0.18, 0.9)
  ui.drawRectFilled(p, p + vec2(w, h), bgColor, 4)
  ui.drawRect(p, p + vec2(w, h), isBalancing and rgbm(0.3, 1.0, 0.4, 0.95) or rgbm(0.25, 0.3, 0.38, 0.6), 4, 1)

  local icon = math.abs(pitchDeg) < 1.0 and "― PLANO" or (pitchDeg > 0 and "▲ SUBIDA (UPHILL)" or "▼ DESCIDA (DOWNHILL)")
  local stateText = isBalancing and " [PONTO DE EQUILÍBRIO SEGURO - NÃO CAI]" or ""
  
  ui.setCursor(p + vec2(8, 6))
  ui.textColored(icon .. stateText, isBalancing and rgbm(0.4, 1.0, 0.4, 1) or rgbm(0.9, 0.9, 0.9, 1))
  
  ui.setCursor(p + vec2(8, 26))
  local textIncline = string.format("Inclinação: %.1f° (%.1f%%) | Gravidade: %.0f N", pitchDeg, gradePercent, math.abs(gravityForce))
  ui.textColored(textIncline, rgbm(0.7, 0.75, 0.8, 1))

  ui.setCursor(p + vec2(0, h + 4))
  ui.dummy(vec2(w, 0))
end

-- ==============================================================================
-- ASSISTENTE VISUAL DE PONTO DE EMBREAGEM (TREINO AUTOESCOLA)
-- ==============================================================================
-- ASSISTENTE VISUAL DE PONTO DE EMBREAGEM (TREINO AUTOESCOLA)
-- ==============================================================================
function UI.drawBitePointRadar(currentPedal, biteCenter, biteWidth, couplingRatio, isSlipping, isStalled, isNearStall, pt)
  local p = ui.getCursor()
  local w = ui.availableSpaceX()
  local h = 54
  
  local startBite = clamp(biteCenter - (biteWidth * 0.5), 0.10, 0.80)
  local endBite = clamp(biteCenter + (biteWidth * 0.5), startBite + 0.08, 0.95)
  local ped = clamp(currentPedal, 0.0, 1.0)
  local inBite = (ped >= startBite and ped <= endBite)

  -- Vibração visual dinâmica do widget no ponto de fricção
  local jitter = vec2(0, 0)
  if inBite and isSlipping then
    local now = os.clock()
    local jX = math.sin(now * 80.0) * 3.5 + (math.random() - 0.5) * 2.0
    local jY = math.cos(now * 70.0) * 2.5 + (math.random() - 0.5) * 1.5
    jitter = vec2(jX, jY)
  elseif isNearStall then
    local now = os.clock()
    jitter = vec2((math.random() - 0.5) * 5.0, (math.random() - 0.5) * 4.0)
  end

  local pJitter = p + jitter

  -- Card background com pulsação
  local bgCol = isStalled and rgbm(0.25, 0.08, 0.08, 0.92) or (isNearStall and rgbm(0.28, 0.16, 0.04, 0.92) or rgbm(0.09, 0.11, 0.15, 0.94))
  local borderCol = isStalled and rgbm(0.9, 0.2, 0.2, 0.8) or (isNearStall and rgbm(1.0, 0.6, 0.1, 0.9) or (inBite and rgbm(0.2, 0.95, 0.4, 0.9) or rgbm(0.25, 0.32, 0.42, 0.7)))
  ui.drawRectFilled(pJitter, pJitter + vec2(w, h), bgCol, 5)
  ui.drawRect(pJitter, pJitter + vec2(w, h), borderCol, 5, (inBite or isNearStall) and 2 or 1)

  if isStalled then
    ui.setCursor(pJitter + vec2(8, 8))
    ui.textColored(pt and "❌ MOTOR MORREU / AFOGOU!" or "❌ ENGINE STALLED!", rgbm(1.0, 0.3, 0.3, 1))
    ui.setCursor(pJitter + vec2(8, 28))
    ui.textColored(pt and "Pise na embreagem e aperte o Botão 1 (X) para ligar" or "Press clutch & Button 1 (X) to restart", rgbm(0.85, 0.85, 0.85, 1))
    ui.setCursor(p + vec2(0, h + 4))
    ui.dummy(vec2(w, 0))
    return
  end

  -- Header text & Status
  ui.setCursor(pJitter + vec2(8, 5))
  if isNearStall then
    ui.textColored(pt and "⚡ TREPIDANDO FORTE: ACELERE OU PISE!" or "⚡ VIOLENT SHUDDER: GAS OR CLUTCH!", rgbm(1.0, 0.65, 0.1, 1))
  elseif inBite then
    ui.textColored(pt and "★ PONTO DE FRICÇÃO: SEGURE O PEDAL AQUI! ★" or "★ BITE POINT: HOLD PEDAL HERE! ★", rgbm(0.2, 1.0, 0.35, 1))
  elseif ped < startBite then
    ui.textColored(pt and "● Embreagem Aberta (Desacoplada)" or "● Clutch Open (Disengaged)", rgbm(0.4, 0.7, 0.9, 1))
  else
    ui.textColored(pt and "✔ Embreagem Totalmente Acoplada" or "✔ Clutch Fully Engaged", rgbm(0.4, 0.9, 0.5, 1))
  end

  -- Horizontal Pedal & Bite Zone Track
  local trackY = pJitter.y + 28
  local trackH = 16
  local trackStart = pJitter.x + 8
  local trackW = w - 16

  -- Base track
  ui.drawRectFilled(vec2(trackStart, trackY), vec2(trackStart + trackW, trackY + trackH), rgbm(0.14, 0.17, 0.22, 0.95), 3)

  -- Target Bite Zone Box
  local bzX1 = trackStart + (startBite * trackW)
  local bzX2 = trackStart + (endBite * trackW)
  local bzCol = inBite and rgbm(0.2, 0.9, 0.35, 0.55) or rgbm(0.9, 0.6, 0.1, 0.30)
  local bzBorder = inBite and rgbm(0.3, 1.0, 0.45, 1.0) or rgbm(0.95, 0.65, 0.15, 0.75)
  ui.drawRectFilled(vec2(bzX1, trackY), vec2(bzX2, trackY + trackH), bzCol, 3)
  ui.drawRect(vec2(bzX1, trackY), vec2(bzX2, trackY + trackH), bzBorder, 3, inBite and 2.5 or 1.5)

  -- Center Bite Target Line
  local bzCenter = trackStart + (biteCenter * trackW)
  ui.drawLine(vec2(bzCenter, trackY - 2), vec2(bzCenter, trackY + trackH + 2), rgbm(1, 1, 1, 0.9), 2)

  -- Live Foot Position Indicator Cursor
  local curX = trackStart + (ped * trackW)
  local cursorCol = inBite and rgbm(0.3, 1.0, 0.4, 1.0) or rgbm(1.0, 1.0, 1.0, 0.9)
  ui.drawLine(vec2(curX, trackY - 4), vec2(curX, trackY + trackH + 4), cursorCol, 3.0)
  ui.drawCircleFilled(vec2(curX, trackY + trackH * 0.5), 6.0, cursorCol)
  ui.drawCircle(vec2(curX, trackY + trackH * 0.5), 7.5, rgbm(0, 0, 0, 0.8), 12, 1.5)

  ui.setCursor(p + vec2(0, h + 4))
  ui.dummy(vec2(w, 0))
end

return UI
