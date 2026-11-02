--[[ ULTRA FIRE VFX SYSTEM — LocalScript único (StarterPlayerScripts) ]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FX = Instance.new("Folder")
FX.Name = "LocalFireFX"
FX.Parent = workspace

--------------------------------------------------------------------------
-- CONFIGURAÇÃO GLOBAL (ajuste livre)
--------------------------------------------------------------------------
local CONFIG = {
	Fireball = {Cooldown = 2.5, Speed = 110, Range = 220, CoreSize = 3.2},
	Nova     = {Cooldown = 6,   Scale = 1.6},
	Dash     = {Cooldown = 4,   Distance = 45, Duration = 0.35},
	Pillar   = {Cooldown = 9,   Distance = 40, Height = 70},
	Gravity  = Vector3.new(0, -60, 0),
}

--------------------------------------------------------------------------
-- UTILITÁRIOS
--------------------------------------------------------------------------
local rng = Random.new()
local function rand(a, b) return rng:NextNumber(a, b) end
local function randInt(a, b) return rng:NextInteger(a, b) end
local function randUnit() return rng:NextUnitVector() end

-- paleta de calor: 1 = branco incandescente, 0 = brasa escura
local HEAT = {
	{1.00, Color3.fromRGB(255, 255, 235)},
	{0.80, Color3.fromRGB(255, 236, 140)},
	{0.60, Color3.fromRGB(255, 170, 40)},
	{0.40, Color3.fromRGB(255, 95, 15)},
	{0.20, Color3.fromRGB(200, 35, 10)},
	{0.00, Color3.fromRGB(60, 15, 10)},
}
local function heatColor(h)
	h = math.clamp(h, 0, 1)
	for i = 1, #HEAT - 1 do
		local a, b = HEAT[i], HEAT[i + 1]
		if h <= a[1] and h >= b[1] then
			return b[2]:Lerp(a[2], (h - b[1]) / (a[1] - b[1]))
		end
	end
	return HEAT[#HEAT][2]
end

local function newPart(size, color, shape, transp, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape or Enum.PartType.Block
	p.Material = material or Enum.Material.Neon
	p.Size = size
	p.Color = color
	p.Transparency = transp or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = FX
	return p
end

local function getChar()
	local c = player.Character
	if not c then return end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end
	return c, hrp, hum
end

--------------------------------------------------------------------------
-- MOTOR DE ATORES (cada elemento tem seu próprio update)
--------------------------------------------------------------------------
local actors = {}
local function spawnActor(fn) table.insert(actors, fn) end

RunService.Heartbeat:Connect(function(dt)
	for i = #actors, 1, -1 do
		local ok, alive = pcall(actors[i], dt)
		if not ok or alive == false then table.remove(actors, i) end
	end
end)

--------------------------------------------------------------------------
-- LUZ DINÂMICA
--------------------------------------------------------------------------
local function flashLight(pos, brightness, range, duration)
	local holder = newPart(Vector3.new(0.1, 0.1, 0.1), Color3.new(), nil, 1)
	holder.Position = pos
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 50)
	light.Brightness = brightness
	light.Range = range
	light.Shadows = true
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad), {Brightness = 0, Range = range * 0.4}):Play()
	task.delay(duration + 0.1, function() holder:Destroy() end)
end

--------------------------------------------------------------------------
-- SEGMENTO DE RASTRO (deixado por faíscas)
--------------------------------------------------------------------------
local function trailSegment(a, b, width, heat)
	local len = (b - a).Magnitude
	if len < 0.05 then return end
	local seg = newPart(Vector3.new(width, width, len), heatColor(heat), nil, 0.1)
	seg.CFrame = CFrame.lookAt((a + b) / 2, b)
	local life, t = rand(0.15, 0.35), 0
	spawnActor(function(dt)
		t += dt
		local k = t / life
		if k >= 1 then seg:Destroy() return false end
		seg.Transparency = 0.1 + k * 0.9
		seg.Size = Vector3.new(width * (1 - k), width * (1 - k), len)
		seg.Color = heatColor(heat * (1 - k))
	end)
end

--------------------------------------------------------------------------
-- FAÍSCAS — 8 TRAJETÓRIAS DISTINTAS
--------------------------------------------------------------------------
local spark -- declaração antecipada (usada pela fragmentação)

local SparkTypes = {}

-- 1: sobe verticalmente, desacelera e desaparece
SparkTypes[1] = function(s, dt)
	s.vel = s.vel * (1 - 2.8 * dt)
end
-- 2: dispara diagonalmente para baixo (à direita do referencial)
SparkTypes[2] = function(s, dt)
	s.vel += Vector3.new(0, -25, 0) * dt
end
-- 3: curva para cima à esquerda (vetor gira a cada quadro)
SparkTypes[3] = function(s, dt)
	local rot = CFrame.fromAxisAngle(s.curveAxis, s.curveRate * dt)
	s.vel = rot:VectorToWorldSpace(s.vel) + Vector3.new(0, 18, 0) * dt
end
-- 4: sobe, perde velocidade e cai (gravidade plena)
SparkTypes[4] = function(s, dt)
	s.vel += CONFIG.Gravity * dt
end
-- 5: arco irregular (ruído de Perlin)
SparkTypes[5] = function(s, dt)
	local n = s.age * 6 + s.seed
	local jitter = Vector3.new(math.noise(n, 0, 0), math.noise(0, n, 0), math.noise(0, 0, n)) * 140
	s.vel += (jitter + CONFIG.Gravity * 0.5) * dt
end
-- 6: segue na horizontal e deixa um rastro
SparkTypes[6] = function(s, dt)
	s.vel = Vector3.new(s.vel.X, s.vel.Y * (1 - 4 * dt), s.vel.Z)
	if s.lastTrail then trailSegment(s.lastTrail, s.pos, s.size * 0.8, s.heat) end
	s.lastTrail = s.pos
end
-- 7: espiral
SparkTypes[7] = function(s, dt)
	s.spiralAngle += dt * s.spiralSpeed
	s.spiralRadius += dt * 3
	local axisCF = CFrame.lookAt(Vector3.zero, s.spiralAxis)
	local offset = axisCF:VectorToWorldSpace(Vector3.new(math.cos(s.spiralAngle), math.sin(s.spiralAngle), 0) * s.spiralRadius)
	s.spiralCenter += s.spiralAxis * s.speed * 0.5 * dt
	s.overridePos = s.spiralCenter + offset
end
-- 8: fragmenta-se em partículas menores
SparkTypes[8] = function(s, dt)
	s.vel += CONFIG.Gravity * 0.3 * dt
	if not s.fragmented and s.age > s.life * 0.45 then
		s.fragmented = true
		for _ = 1, randInt(4, 7) do
			spark(s.pos, randUnit() * rand(15, 35) + s.vel * 0.3, {
				type = ({1, 2, 4, 5})[randInt(1, 4)],
				size = s.size * 0.5, life = rand(0.25, 0.6), heat = s.heat * 0.9,
			})
		end
		s.age = s.life -- a original desaparece
	end
end

spark = function(origin, velocity, opts)
	opts = opts or {}
	local s = {
		type = opts.type or randInt(1, 8),
		pos = origin, vel = velocity, age = 0,
		life = opts.life or rand(0.5, 1.2),
		size = opts.size or rand(0.12, 0.3),
		heat = opts.heat or rand(0.85, 1),
		seed = rand(0, 1000),
		speed = velocity.Magnitude,
		curveAxis = randUnit(), curveRate = rand(3, 7) * (rng:NextInteger(0, 1) == 0 and -1 or 1),
		spiralAngle = rand(0, math.pi * 2), spiralSpeed = rand(10, 20), spiralRadius = rand(0.3, 1),
		spiralAxis = velocity.Magnitude > 0 and velocity.Unit or Vector3.yAxis,
		spiralCenter = origin,
	}
	local p = newPart(Vector3.new(s.size, s.size, s.size * 4), heatColor(s.heat))
	local behave = SparkTypes[s.type]
	spawnActor(function(dt)
		s.age += dt
		local k = s.age / s.life
		if k >= 1 then p:Destroy() return false end
		local prev = s.pos
		s.overridePos = nil
		behave(s, dt)
		s.pos = s.overridePos or (s.pos + s.vel * dt)
		local dir = s.pos - prev
		local stretch = math.clamp(dir.Magnitude / math.max(dt, 1e-3) * 0.02, 1, 10)
		local sz = s.size * (1 - k * 0.7)
		p.Size = Vector3.new(sz, sz, sz * 2 * stretch)
		if dir.Magnitude > 1e-4 then
			p.CFrame = CFrame.lookAt(s.pos, s.pos + dir)
		else
			p.Position = s.pos
		end
		local flicker = math.noise(s.seed, s.age * 20) * 0.15
		p.Color = heatColor(s.heat * (1 - k) + flicker)
		p.Transparency = math.clamp(k * k + flicker, 0, 1)
	end)
end

--------------------------------------------------------------------------
-- LÍNGUA DE CHAMA (sobe, ondula, cresce, encolhe, esfria)
--------------------------------------------------------------------------
local function flameTongue(origin, opts)
	opts = opts or {}
	local life = opts.life or rand(0.5, 1.1)
	local baseSize = opts.size or rand(1, 2.4)
	local rise = opts.rise or rand(6, 14)
	local drift = opts.drift or Vector3.new(rand(-3, 3), 0, rand(-3, 3))
	local spin = Vector3.new(rand(-6, 6), rand(-6, 6), rand(-6, 6))
	local seed = rand(0, 1000)
	local heat0 = opts.heat or rand(0.8, 1)
	local p = newPart(Vector3.one * baseSize, heatColor(heat0), Enum.PartType.Ball, 0.2)
	local t, rotCF = 0, CFrame.Angles(rand(0, 6), rand(0, 6), rand(0, 6))
	spawnActor(function(dt)
		t += dt
		local k = t / life
		if k >= 1 then p:Destroy() return false end
		local wob = Vector3.new(math.noise(seed, t * 3) * 2, 0, math.noise(t * 3, seed) * 2)
		local pos = origin + Vector3.new(0, rise * (k ^ 0.8), 0) + drift * k + wob * k
		local grow = math.sin(math.min(k * 1.6, 1) * math.pi * 0.5) * (1 - k ^ 3)
		local stretchY = 1 + k * 1.5
		rotCF = rotCF * CFrame.Angles(spin.X * dt * 0.2, spin.Y * dt, spin.Z * dt * 0.2)
		p.Size = Vector3.new(baseSize * grow, baseSize * grow * stretchY, baseSize * grow)
		p.CFrame = CFrame.new(pos) * rotCF
		p.Color = heatColor(heat0 * (1 - k * 1.1))
		p.Transparency = 0.15 + k ^ 1.5 * 0.85
	end)
end

--------------------------------------------------------------------------
-- BRASA / FRAGMENTO INCANDESCENTE (rotaciona, cai, pisca)
--------------------------------------------------------------------------
local function ember(origin, velocity, opts)
	opts = opts or {}
	local life = opts.life or rand(1.2, 2.5)
	local sz = opts.size or rand(0.2, 0.55)
	local p = newPart(Vector3.new(sz, sz * rand(0.5, 1.2), sz * rand(0.6, 1.4)), heatColor(1))
	local vel, t, seed = velocity, 0, rand(0, 1000)
	local spin = CFrame.Angles(rand(-8, 8), rand(-8, 8), rand(-8, 8))
	local cf = CFrame.new(origin) * CFrame.Angles(rand(0, 6), rand(0, 6), rand(0, 6))
	spawnActor(function(dt)
		t += dt
		local k = t / life
		if k >= 1 then p:Destroy() return false end
		vel = vel * (1 - 1.2 * dt) + Vector3.new(0, -14, 0) * dt
		local rot = cf - cf.Position
		cf = CFrame.new(cf.Position + vel * dt) * rot:Lerp(rot * spin, dt)
		p.CFrame = cf
		local pulse = (math.sin(t * 25 + seed) + 1) * 0.5
		p.Color = heatColor(0.9 - k * 0.8 + pulse * 0.15)
		p.Transparency = k ^ 2
	end)
end

--------------------------------------------------------------------------
-- FUMAÇA
--------------------------------------------------------------------------
local function smoke(origin, opts)
	opts = opts or {}
	local life = opts.life or rand(1.5, 3)
	local sz = opts.size or rand(2, 4)
	local p = newPart(Vector3.one * sz, Color3.fromRGB(45, 38, 35), Enum.PartType.Ball, 0.6, Enum.Material.SmoothPlastic)
	local drift = Vector3.new(rand(-2, 2), rand(4, 8), rand(-2, 2))
	local t = 0
	spawnActor(function(dt)
		t += dt
		local k = t / life
		if k >= 1 then p:Destroy() return false end
		p.Position = origin + drift * t
		p.Size = Vector3.one * sz * (1 + k * 2)
		p.Transparency = 0.6 + k * 0.4
	end)
end

--------------------------------------------------------------------------
-- NÚCLEO DE FOGO (rotação, deformação, camadas internas/externas, anéis)
--------------------------------------------------------------------------
local function createCore(size)
	local core = {pos = Vector3.zero, alive = true, size = size, t = 0}
	local inner  = newPart(Vector3.one * size * 0.55, heatColor(1), Enum.PartType.Ball, 0)
	local middle = newPart(Vector3.one * size * 0.8, heatColor(0.65), Enum.PartType.Ball, 0.3)
	local outer  = newPart(Vector3.one * size, heatColor(0.4), Enum.PartType.Ball, 0.55)
	local rings = {}
	for i = 1, 3 do
		local r = newPart(Vector3.new(0.15, size * 1.4, size * 1.4), heatColor(0.7), Enum.PartType.Cylinder, 0.4)
		rings[i] = {part = r, axis = randUnit(), speed = rand(4, 9) * (i % 2 == 0 and -1 or 1), cf = CFrame.Angles(rand(0, 6), rand(0, 6), 0)}
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 40)
	light.Range = 22
	light.Brightness = 4
	light.Parent = inner

	spawnActor(function(dt)
		if not core.alive then
			inner:Destroy() middle:Destroy() outer:Destroy()
			for _, r in ipairs(rings) do r.part:Destroy() end
			return false
		end
		core.t += dt
		local t = core.t
		local pulse = 1 + math.sin(t * 14) * 0.12
		local deform = Vector3.new(1 + math.sin(t * 9) * 0.15, 1 + math.sin(t * 11 + 1) * 0.15, 1 + math.sin(t * 7 + 2) * 0.15)
		inner.Size  = deform * size * 0.55 * pulse
		middle.Size = Vector3.new(deform.Z, deform.X, deform.Y) * size * 0.8 * (2 - pulse)
		outer.Size  = Vector3.new(deform.Y, deform.Z, deform.X) * size * (1 + math.sin(t * 5) * 0.08)
		inner.CFrame  = CFrame.new(core.pos) * CFrame.Angles(t * 5, t * 7, t * 3)
		middle.CFrame = CFrame.new(core.pos) * CFrame.Angles(-t * 4, t * 2, -t * 6)
		outer.CFrame  = CFrame.new(core.pos) * CFrame.Angles(t * 2, -t * 3, t * 1.5)
		middle.Color = heatColor(0.6 + math.noise(t * 4) * 0.2)
		outer.Transparency = 0.5 + math.noise(t * 6, 1) * 0.2
		for _, r in ipairs(rings) do
			r.cf = r.cf * CFrame.fromAxisAngle(r.axis, r.speed * dt)
			r.part.CFrame = CFrame.new(core.pos) * r.cf
			r.part.Transparency = 0.35 + (math.sin(t * 10 + r.speed) + 1) * 0.25
		end
		light.Brightness = 3 + math.noise(t * 10) * 2
	end)
	return core
end

--------------------------------------------------------------------------
-- EXPLOSÃO (montada camada por camada)
--------------------------------------------------------------------------
local function explosion(pos, scale)
	scale = scale or 1
	flashLight(pos, 12, 50 * scale, 1.2)

	-- Camada 1: clarão branco
	local flash = newPart(Vector3.one, heatColor(1), Enum.PartType.Ball, 0)
	flash.Position = pos
	TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = Vector3.one * 14 * scale, Transparency = 1}):Play()
	task.delay(0.3, function() flash:Destroy() end)

	-- Camada 2: bola de fogo em expansão e contração
	local ball = newPart(Vector3.one * 2, heatColor(0.8), Enum.PartType.Ball, 0.1)
	ball.Position = pos
	local bt = 0
	spawnActor(function(dt)
		bt += dt
		local k = bt / 1.1
		if k >= 1 then ball:Destroy() return false end
		local s = (k < 0.25) and (k / 0.25) or (1 - (k - 0.25) / 0.75 * 0.4)
		ball.Size = Vector3.one * 18 * scale * s * (1 + math.sin(bt * 30) * 0.04)
		ball.CFrame = CFrame.new(pos) * CFrame.Angles(bt * 2, bt * 3, 0)
		ball.Color = heatColor(0.85 - k)
		ball.Transparency = 0.1 + k ^ 1.3 * 0.9
	end)

	-- Camada 3: ondas de choque (duas, defasadas)
	for i = 1, 2 do
		task.delay((i - 1) * 0.08, function()
			local ring = newPart(Vector3.new(0.4, 2, 2), heatColor(0.7), Enum.PartType.Cylinder, 0.2)
			ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(rand(-0.2, 0.2), 0, rand(-0.2, 0.2))
			TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quint), {Size = Vector3.new(0.05, 40 * scale / i, 40 * scale / i), Transparency = 1}):Play()
			task.delay(0.75, function() ring:Destroy() end)
		end)
	end

	-- Camada 4: as 8 trajetórias de faísca, cada uma com parâmetros próprios
	local count = math.floor(14 * scale)
	for typeId = 1, 8 do
		for _ = 1, count do
			local dir
			if typeId == 1 then dir = Vector3.new(rand(-0.15, 0.15), 1, rand(-0.15, 0.15)).Unit * rand(30, 55)
			elseif typeId == 2 then dir = (randUnit() * Vector3.new(1, 0, 1) + Vector3.new(0, -0.5, 0)).Unit * rand(35, 60)
			elseif typeId == 3 then dir = (randUnit() + Vector3.new(0, 0.6, 0)).Unit * rand(25, 40)
			elseif typeId == 4 then dir = Vector3.new(rand(-0.5, 0.5), 1, rand(-0.5, 0.5)).Unit * rand(30, 50)
			elseif typeId == 5 then dir = randUnit() * rand(20, 40)
			elseif typeId == 6 then dir = Vector3.new(rand(-1, 1), rand(-0.05, 0.1), rand(-1, 1)).Unit * rand(40, 70)
			elseif typeId == 7 then dir = randUnit() * rand(15, 25)
			else dir = (randUnit() + Vector3.new(0, 0.8, 0)).Unit * rand(25, 45) end
			spark(pos, dir * math.sqrt(scale), {type = typeId, life = rand(0.5, 1.3)})
		end
	end

	-- Camada 5: línguas de chama internas e externas
	for _ = 1, math.floor(35 * scale) do
		local off = randUnit() * rand(0, 4 * scale)
		flameTongue(pos + off, {size = rand(1.5, 3.5) * scale, rise = rand(5, 16) * scale, drift = off * 1.5, life = rand(0.6, 1.3)})
	end
	for _ = 1, math.floor(20 * scale) do
		local off = randUnit() * Vector3.new(1, 0.3, 1) * rand(4, 8) * scale
		flameTongue(pos + off, {size = rand(1, 2) * scale, heat = rand(0.5, 0.75), drift = off, life = rand(0.8, 1.5)})
	end

	-- Camada 6: fragmentos incandescentes
	for _ = 1, math.floor(30 * scale) do
		ember(pos, (randUnit() + Vector3.new(0, 0.7, 0)).Unit * rand(20, 50) * scale)
	end

	-- Camada 7: fumaça e dissipação
	task.delay(0.3, function()
		for _ = 1, math.floor(14 * scale) do
			smoke(pos + randUnit() * rand(1, 5) * scale, {size = rand(3, 6) * scale})
		end
	end)
end

--------------------------------------------------------------------------
-- HABILIDADE 1: BOLA DE FOGO
--------------------------------------------------------------------------
local function castFireball()
	local char, hrp = getChar()
	if not char then return end
	local cfg = CONFIG.Fireball
	local origin = hrp.Position + hrp.CFrame.LookVector * 3 + Vector3.new(0, 1.5, 0)
	local dir = camera.CFrame.LookVector
	if (dir * Vector3.new(1, 0, 1)).Magnitude < 0.2 then dir = hrp.CFrame.LookVector end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {char, FX}

	-- carga: faíscas convergindo para a mão
	for _ = 1, 25 do
		local from = origin + randUnit() * rand(3, 6)
		spark(from, (origin - from) * 4, {type = 1, life = 0.25, size = 0.12})
	end

	local core = createCore(cfg.CoreSize)
	core.pos = origin
	local traveled, lastPos = 0, origin
	spawnActor(function(dt)
		local step = cfg.Speed * dt
		local hit = workspace:Raycast(core.pos, dir * step, params)
		if hit or traveled > cfg.Range then
			core.alive = false
			explosion(hit and hit.Position or core.pos, 1)
			return false
		end
		core.pos += dir * step
		traveled += step
		-- rastro de chamas
		for _ = 1, 4 do
			flameTongue(core.pos + randUnit() * cfg.CoreSize * 0.4, {size = rand(0.8, 2), rise = rand(1, 4), drift = -dir * rand(2, 6), life = rand(0.3, 0.6)})
		end
		-- faíscas de esteira
		for _ = 1, 3 do
			spark(core.pos, (-dir + randUnit() * 0.8) * rand(10, 25), {type = ({4, 5, 6, 8})[randInt(1, 4)], life = rand(0.3, 0.7)})
		end
		if rng:NextNumber() < 0.5 then ember(core.pos, -dir * rand(5, 15) + randUnit() * 6, {life = rand(0.8, 1.4)}) end
		trailSegment(lastPos, core.pos, cfg.CoreSize * 0.5, 0.8)
		lastPos = core.pos
	end)
end

--------------------------------------------------------------------------
-- HABILIDADE 2: EXPLOSÃO SOLAR (nova ao redor do jogador)
--------------------------------------------------------------------------
local function castNova()
	local char, hrp = getChar()
	if not char then return end
	local pos = hrp.Position
	-- círculo de chamas em espiral antes da detonação
	for i = 1, 36 do
		task.delay(i * 0.012, function()
			local a = i / 36 * math.pi * 2
			local p = pos + Vector3.new(math.cos(a) * 7, -2.5, math.sin(a) * 7)
			flameTongue(p, {size = rand(1.2, 2), rise = rand(3, 7), drift = (pos - p) * 0.5, life = 0.5})
			spark(p, Vector3.new(0, rand(20, 35), 0), {type = 7, life = 0.6})
		end)
	end
	task.delay(0.45, function() explosion(pos, CONFIG.Nova.Scale) end)
end

--------------------------------------------------------------------------
-- HABILIDADE 3: INVESTIDA FLAMEJANTE
--------------------------------------------------------------------------
local function castDash()
	local char, hrp = getChar()
	if not char then return end
	local cfg = CONFIG.Dash
	local look = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0 and look.Unit or Vector3.zAxis
	local startPos = hrp.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {char, FX}
	local hit = workspace:Raycast(startPos, look * cfg.Distance, params)
	local dist = hit and (hit.Distance - 3) or cfg.Distance
	local t, last = 0, startPos
	explosion(startPos, 0.5)
	spawnActor(function(dt)
		t += dt
		local k = math.min(t / cfg.Duration, 1)
		local e = 1 - (1 - k) ^ 3
		local newPos = startPos + look * dist * e
		hrp.CFrame = CFrame.lookAt(newPos, newPos + look)
		hrp.AssemblyLinearVelocity = Vector3.zero
		local segs = math.max(1, math.floor((newPos - last).Magnitude / 1.2))
		for i = 1, segs do
			local p = last:Lerp(newPos, i / segs) - Vector3.new(0, 2.5, 0)
			flameTongue(p + Vector3.new(rand(-1.5, 1.5), 0, rand(-1.5, 1.5)), {size = rand(1.5, 2.8), rise = rand(4, 9), life = rand(0.7, 1.4)})
			spark(p, Vector3.new(rand(-10, 10), rand(15, 30), rand(-10, 10)), {type = randInt(1, 8)})
			if i % 2 == 0 then ember(p, Vector3.new(rand(-6, 6), rand(8, 16), rand(-6, 6))) end
		end
		trailSegment(last, newPos, 1.2, 0.95)
		last = newPos
		if k >= 1 then explosion(newPos, 0.6) return false end
	end)
end

--------------------------------------------------------------------------
-- HABILIDADE 4: PILAR INFERNAL (meteoro + coluna espiral)
--------------------------------------------------------------------------
local function castPillar()
	local char, hrp = getChar()
	if not char then return end
	local cfg = CONFIG.Pillar
	local target = hrp.Position + hrp.CFrame.LookVector * cfg.Distance
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {char, FX}
	local ground = workspace:Raycast(target + Vector3.new(0, 30, 0), Vector3.new(0, -200, 0), params)
	target = ground and ground.Position or target - Vector3.new(0, 3, 0)

	-- marcador no solo
	local mark = newPart(Vector3.new(0.2, 1, 1), heatColor(0.5), Enum.PartType.Cylinder, 0.3)
	mark.CFrame = CFrame.new(target + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(mark, TweenInfo.new(0.8), {Size = Vector3.new(0.2, 22, 22)}):Play()

	local core = createCore(5)
	local startPos = target + Vector3.new(rand(-20, 20), cfg.Height, rand(-20, 20))
	local t = 0
	spawnActor(function(dt)
		t += dt
		local k = math.min(t / 0.8, 1)
		local prev = core.pos
		core.pos = startPos:Lerp(target, k ^ 2)
		if prev ~= Vector3.zero then trailSegment(prev, core.pos, 3, 0.9) end
		for _ = 1, 6 do
			flameTongue(core.pos + randUnit() * 2, {size = rand(1.5, 3), rise = rand(2, 5), life = 0.5})
			spark(core.pos, randUnit() * rand(10, 25), {type = randInt(1, 8), life = 0.5})
		end
		if k < 1 then return end
		core.alive = false
		mark:Destroy()
		explosion(target, 1.8)
		-- coluna de chamas em espiral (3 hélices)
		local pt = 0
		spawnActor(function(dt2)
			pt += dt2
			if pt > 1.6 then return false end
			for h = 1, 3 do
				for _ = 1, 3 do
					local y = rand(0, cfg.Height * 0.6)
					local a = pt * 8 + h * (math.pi * 2 / 3) + y * 0.15
					local r = 3 + y * 0.05
					local p = target + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
					flameTongue(p, {size = rand(1.5, 3.2), rise = rand(5, 12), life = rand(0.4, 0.8), drift = Vector3.new(math.cos(a), 0, math.sin(a)) * 2})
				end
			end
			spark(target, Vector3.new(rand(-6, 6), rand(50, 80), rand(-6, 6)), {type = ({1, 4, 7})[randInt(1, 3)], life = rand(0.8, 1.4)})
			if rng:NextNumber() < 0.6 then ember(target + Vector3.new(0, rand(5, 40), 0), randUnit() * rand(10, 25)) end
		end)
	end)
end

--------------------------------------------------------------------------
-- INTERFACE MOBILE
--------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "FireAbilities"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- container responsivo (proporcional ao menor lado da tela)
local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(1, 1)
holder.Position = UDim2.new(1, -16, 1, -16)
holder.Parent = gui

local function resize()
	local vp = camera.ViewportSize
	local s = math.clamp(math.min(vp.X, vp.Y) * 0.42, 180, 320)
	holder.Size = UDim2.fromOffset(s, s)
end
resize()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)

local ABILITIES = {
	{name = "Bola",     key = Enum.KeyCode.Q, icon = "◉", cast = castFireball, cfg = CONFIG.Fireball, pos = Vector2.new(0.30, 0.82), size = 0.30},
	{name = "Solar",    key = Enum.KeyCode.E, icon = "✺", cast = castNova,     cfg = CONFIG.Nova,     pos = Vector2.new(0.40, 0.48), size = 0.25},
	{name = "Investida",key = Enum.KeyCode.R, icon = "➶", cast = castDash,     cfg = CONFIG.Dash,     pos = Vector2.new(0.72, 0.28), size = 0.25},
	{name = "Pilar",    key = Enum.KeyCode.F, icon = "▲", cast = castPillar,   cfg = CONFIG.Pillar,   pos = Vector2.new(0.80, 0.70), size = 0.30},
}

for _, ab in ipairs(ABILITIES) do
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromScale(ab.pos.X, ab.pos.Y)
	btn.Size = UDim2.fromScale(ab.size, ab.size)
	btn.BackgroundColor3 = Color3.fromRGB(22, 14, 12)
	btn.BackgroundTransparency = 0.25
	btn.ClipsDescendants = true
	btn.Parent = holder
	Instance.new("UIAspectRatioConstraint", btn)
	Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.15
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = btn
	local sg = Instance.new("UIGradient")
	sg.Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(200, 40, 10))
	sg.Rotation = 45
	sg.Parent = stroke

	-- brilho interno de baixo para cima
	local glow = Instance.new("Frame")
	glow.Size = UDim2.fromScale(1, 1)
	glow.BackgroundColor3 = Color3.fromRGB(255, 110, 20)
	glow.BackgroundTransparency = 0
	glow.BorderSizePixel = 0
	glow.Parent = btn
	Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)
	local gg = Instance.new("UIGradient")
	gg.Rotation = -90
	gg.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1)})
	gg.Parent = glow

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.6, 0.6)
	icon.Position = UDim2.fromScale(0.2, 0.12)
	icon.Text = ab.icon
	icon.TextScaled = true
	icon.Font = Enum.Font.GothamBlack
	icon.TextColor3 = Color3.fromRGB(255, 225, 160)
	icon.ZIndex = 3
	icon.Parent = btn

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.8, 0.16)
	label.Position = UDim2.fromScale(0.1, 0.70)
	label.Text = string.upper(ab.name)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 170, 110)
	label.ZIndex = 3
	label.Parent = btn

	-- overlay de cooldown (desce de cima para baixo)
	local cd = Instance.new("Frame")
	cd.AnchorPoint = Vector2.new(0, 1)
	cd.Position = UDim2.fromScale(0, 1)
	cd.Size = UDim2.fromScale(1, 0)
	cd.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	cd.BackgroundTransparency = 0.35
	cd.BorderSizePixel = 0
	cd.ZIndex = 4
	cd.Parent = btn

	local cdText = Instance.new("TextLabel")
	cdText.BackgroundTransparency = 1
	cdText.Size = UDim2.fromScale(0.5, 0.35)
	cdText.Position = UDim2.fromScale(0.25, 0.32)
	cdText.TextScaled = true
	cdText.Font = Enum.Font.GothamBlack
	cdText.TextColor3 = Color3.new(1, 1, 1)
	cdText.Text = ""
	cdText.ZIndex = 5
	cdText.Parent = btn

	local scale = Instance.new("UIScale")
	scale.Parent = btn

	local readyAt = 0
	local function activate()
		local now = os.clock()
		if now < readyAt then
			-- tremida de "indisponível"
			TweenService:Create(btn, TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 3, true), {Rotation = 8}):Play()
			return
		end
		if not getChar() then return end
		readyAt = now + ab.cfg.Cooldown
		ab.cast()
		cd.Size = UDim2.fromScale(1, 1)
		TweenService:Create(cd, TweenInfo.new(ab.cfg.Cooldown, Enum.EasingStyle.Linear), {Size = UDim2.fromScale(1, 0)}):Play()
		task.spawn(function()
			while os.clock() < readyAt do
				cdText.Text = string.format("%.1f", readyAt - os.clock())
				task.wait(0.05)
			end
			cdText.Text = ""
			-- pulso de "pronto"
			glow.BackgroundColor3 = Color3.fromRGB(255, 240, 180)
			TweenService:Create(glow, TweenInfo.new(0.4), {BackgroundColor3 = Color3.fromRGB(255, 110, 20)}):Play()
		end)
	end

	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), {Scale = 0.86}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.08), {Thickness = 4}):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), {Scale = 1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), {Thickness = 2}):Play()
	end
	btn.MouseButton1Up:Connect(release)
	btn.MouseLeave:Connect(release)
	btn.Activated:Connect(activate)

	-- gradiente do contorno girando devagar
	spawnActor(function(dt) sg.Rotation = (sg.Rotation + dt * 60) % 360 end)

	UIS.InputBegan:Connect(function(input, gp)
		if not gp and input.KeyCode == ab.key then activate() end
	end)
end
