-- VANTA BloxStrike v0.2 TESTE | Luau / Roblox client
-- Execute o arquivo inteiro. Mira, ESP e Anti-Kick local comecam desligados.
-- Adaptacao experimental; ainda sem teste real no BloxStrike/executores.
-- Anti-Kick local depende de APIs do executor; nao impede banimento ou kick do servidor.
-- X desativa os recursos e limpa a UI/conexoes. O hook, se instalado, fica inerte.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Universo da experiencia oficial: inclui seus diferentes places.
assert(game.GameId == 7633926880, "VANTA BloxStrike: entre na experiencia BloxStrike antes de executar.")

local player = Players.LocalPlayer
assert(player, "Execute no cliente, depois de entrar no jogo.")
local playerGui = player:WaitForChild("PlayerGui", 15)
assert(playerGui, "PlayerGui indisponivel. Entre no jogo e tente novamente.")

local Config = {
    Aim = false,
    ESP = false,
    AntiKick = false,
    WallCheck = true,
    TeamCheck = true,
    FOV = 150,           -- Raio em pixels, a partir do centro da tela.
    MaxDistance = 2500,  -- Distancia em studs.
    AimStrength = 85,    -- 20 a 100. Em Camera, 100 centraliza diretamente no alvo.
    AimInput = "Auto",   -- Auto | Mouse | Camera. Auto prefere mouse em PCs sem toque.
    ScanInterval = 0.03,
    ESPInterval = 0.15,
}

local GUI_NAME = "VANTA_Mobile_Arsenal"
local FOLDER_NAME = "VANTA_LocalESP_" .. tostring(player.UserId)
local RENDER_NAME = "VANTA_Aim_" .. tostring(player.UserId)

local previous = playerGui:FindFirstChild(GUI_NAME)
if previous then
    local stop = previous:FindFirstChild("Shutdown")
    if stop and stop:IsA("BindableEvent") then
        stop:Fire()
    end
    previous:Destroy()
end
RunService:UnbindFromRenderStep(RENDER_NAME)
local oldFolder = Workspace:FindFirstChild(FOLDER_NAME)
if oldFolder then
    oldFolder:Destroy()
end

local connections = {}
local espItems = {}
local active = true
local target = nil
local scanElapsed = Config.ScanInterval
local espElapsed = Config.ESPInterval

-- BEGIN LOCAL_KICK_GUARD
-- Modulo isolado para chamadas locais de Player:Kick(). Sem downloads externos.
local function makeLocalKickGuard(gameObject, localPlayer, hooks)
    local guard = { enabled = false, installed = false, blocked = 0, error = nil }
    local stopped = false
    local attempted = false

    function guard:SetEnabled(wanted)
        if stopped then
            return false, "Recurso encerrado. Execute o script novamente."
        end
        if not wanted then
            self.enabled = false
            return true
        end
        if self.installed then
            self.enabled = true
            return true
        end
        if attempted then
            return false, self.error
        end
        attempted = true

        local hook = hooks.hookmetamethod
        local getMethod = hooks.getnamecallmethod
        local ownCaller = hooks.checkcaller
        local wrap = hooks.newcclosure
        local getMeta = hooks.getrawmetatable
        if type(hook) ~= "function" or type(getMethod) ~= "function"
            or type(ownCaller) ~= "function" or type(wrap) ~= "function"
            or type(getMeta) ~= "function" then
            self.error = "Executor sem suporte ao Anti-Kick local."
            return false, self.error
        end

        -- Captura o destino anterior antes de instalar, para manter o encaminhamento
        -- mesmo quando um executor falha durante a instalacao ou retorna um valor invalido.
        local metaOK, meta = pcall(getMeta, gameObject)
        local previous = metaOK and type(meta) == "table" and rawget(meta, "__namecall")
        if type(previous) ~= "function" then
            self.error = "Nao foi possivel obter o metodo original."
            return false, self.error
        end

        local function handler(object, ...)
            if not stopped and guard.enabled and object == localPlayer then
                local methodOK, method = pcall(getMethod)
                if methodOK and (method == "Kick" or method == "kick") then
                    local callerOK, isOwn = pcall(ownCaller)
                    if callerOK and isOwn == false then
                        guard.blocked = guard.blocked + 1
                        return nil
                    end
                end
            end
            return previous(object, ...)
        end

        local wrapOK, wrapped = pcall(wrap, handler)
        if not wrapOK or type(wrapped) ~= "function" then
            self.error = "Executor nao conseguiu preparar o Anti-Kick local."
            return false, self.error
        end
        local hookOK, original = pcall(hook, gameObject, "__namecall", wrapped)
        if not hookOK or type(original) ~= "function" or original == wrapped then
            -- O handler continua desligado e encaminha ao metodo previamente capturado.
            self.error = "Executor nao confirmou a instalacao do Anti-Kick local."
            return false, self.error
        end
        previous = original
        self.installed = true
        self.enabled = true
        return true
    end

    function guard:Shutdown()
        self.enabled = false
        stopped = true
        -- Nao substitui novamente o __namecall: outros scripts podem ter instalado
        -- hooks depois deste. A funcao inerte apenas encaminha ao destino anterior.
    end

    return guard
end
-- END LOCAL_KICK_GUARD

local kickGuard = makeLocalKickGuard(game, player, {
    hookmetamethod = hookmetamethod,
    getnamecallmethod = getnamecallmethod,
    checkcaller = checkcaller,
    newcclosure = newcclosure,
    getrawmetatable = getrawmetatable,
})
local kickNotice = nil
local kickNoticeUntil = 0
local mouseMover = mousemoverel
local inputNotice = nil
local inputNoticeUntil = 0
local espNotice = nil
local espNoticeUntil = 0
local espCounters = { compatible = 0, drawn = 0, unknown = 0 }

-- BEGIN BLOXSTRIKE_HELPERS
local function normalizeTeam(value)
    if type(value) == "number" then
        if value ~= value or math.abs(value) == math.huge then return nil end
        return tostring(value)
    end
    if type(value) == "string" then
        local text = value:match("^%s*(.-)%s*$")
        if text ~= "" then return string.lower(text) end
    end
    return nil
end

-- Consulta somente valores replicados publicamente. Resultado nil significa
-- equipe desconhecida; com o filtro ligado esses jogadores nao sao selecionados.
local function teamRelation(localPlayer, other)
    local mine = normalizeTeam(localPlayer:GetAttribute("Team"))
    local theirs = normalizeTeam(other:GetAttribute("Team"))
    if mine ~= nil and theirs ~= nil then
        return mine ~= theirs, "atributo Player"
    end
    local myCharacter, theirCharacter = localPlayer.Character, other.Character
    mine = myCharacter and normalizeTeam(myCharacter:GetAttribute("Team"))
    theirs = theirCharacter and normalizeTeam(theirCharacter:GetAttribute("Team"))
    if mine ~= nil and theirs ~= nil then
        return mine ~= theirs, "atributo Character"
    end
    if not localPlayer.Neutral and not other.Neutral
        and localPlayer.Team ~= nil and other.Team ~= nil then
        return localPlayer.Team ~= other.Team, "Teams"
    end
    return nil, "desconhecida"
end

local function computeMouseStep(dx, dy, dt, speed, gain, maxStep, deadzone)
    if dx ~= dx or dy ~= dy or dt ~= dt
        or math.abs(dx) == math.huge or math.abs(dy) == math.huge then
        return 0, 0
    end
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= deadzone or dt <= 0 then return 0, 0 end
    local frameTime = math.min(dt, 0.1)
    local alpha = 1 - math.exp(-speed * frameTime)
    local step = math.min(distance * alpha * gain, maxStep * frameTime * 60)
    local scale = step / distance
    return dx * scale, dy * scale
end

local function strengthSettings(strength)
    local value = math.max(20, math.min(100, strength))
    return value, 8 + value * 0.35, 0.7 + value / 200, 18 + value * 0.42,
        value >= 100 and 0.5 or 1
end

local function computeAimAlpha(dt, strength)
    if dt ~= dt or dt <= 0 then return 0 end
    local value, speed = strengthSettings(strength)
    if value >= 100 then return 1 end
    return 1 - math.exp(-speed * math.min(dt, 0.1))
end

local function espRelation(enemy, teamCheck)
    if teamCheck and enemy == false then return nil end
    if enemy == nil then return "unknown" end
    return enemy and "enemy" or "ally"
end

-- Projecao 2D sem dependencia de Highlight, BillboardGui ou Drawing do executor.
local function screenBox(tx, ty, tz, bx, by, bz, viewX, viewY)
    for _, value in ipairs({ tx, ty, tz, bx, by, bz, viewX, viewY }) do
        if value ~= value or math.abs(value) == math.huge then return nil end
    end
    if tz <= 0.05 or bz <= 0.05 or viewX <= 0 or viewY <= 0 then return nil end
    local height = math.max(8, math.abs(by - ty))
    if height > viewY * 4 then return nil end
    local width = math.max(6, height * 0.45)
    local x = (tx + bx) * 0.5 - width * 0.5
    local y = math.min(ty, by)
    if x + width < 0 or x > viewX or y + height < 0 or y > viewY then return nil end
    return x, y, width, height
end
-- END BLOXSTRIKE_HELPERS

local function mouseAvailable()
    return type(mouseMover) == "function" and UserInputService.MouseEnabled
end

local function aimInput()
    if Config.AimInput == "Mouse" then return "Mouse" end
    if Config.AimInput == "Auto" and mouseAvailable() and not UserInputService.TouchEnabled then
        return "Mouse"
    end
    return "Camera"
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function make(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local gui = make("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 90,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
local shutdownEvent = make("BindableEvent", { Name = "Shutdown" }, gui)
local espLayer = make("Frame", {
    Name = "ESP2D",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 1,
}, gui)

local function removeESP(other)
    local item = espItems[other]
    if item then
        item.box:Destroy()
        espItems[other] = nil
    end
end

local function clearESP()
    local pending = {}
    for other in pairs(espItems) do
        table.insert(pending, other)
    end
    for _, other in ipairs(pending) do
        removeESP(other)
    end
    espCounters.compatible = 0
    espCounters.drawn = 0
    espCounters.unknown = 0
end

local function shutdown()
    if not active then
        return
    end
    active = false
    Config.AntiKick = false
    kickGuard:Shutdown()
    RunService:UnbindFromRenderStep(RENDER_NAME)
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    clearESP()
    gui:Destroy()
end
connect(shutdownEvent.Event, shutdown)
connect(gui.Destroying, shutdown)

local accent = Color3.fromRGB(124, 100, 255)
local muted = Color3.fromRGB(60, 64, 82)
local initialCamera = Workspace.CurrentCamera
local panelHeight = math.clamp((initialCamera and initialCamera.ViewportSize.Y or 700) - 84, 220, 472)
local ring = make("Frame", {
    Name = "FOV",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(Config.FOV * 2, Config.FOV * 2),
    BackgroundTransparency = 1,
    Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
local ringStroke = make("UIStroke", {
    Color = accent,
    Thickness = 1.5,
    Transparency = 0.15,
}, ring)

local panel = make("Frame", {
    Name = "Panel",
    Position = UDim2.new(1, -252, 0, 48),
    Size = UDim2.fromOffset(236, panelHeight),
    BackgroundColor3 = Color3.fromRGB(20, 22, 31),
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 2,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
make("UIStroke", { Color = muted, Thickness = 1 }, panel)

local dragHandle = make("TextLabel", {
    Size = UDim2.fromOffset(154, 40),
    Position = UDim2.fromOffset(10, 0),
    BackgroundTransparency = 1,
    Text = "VANTA | BLOX v0.2",
    TextColor3 = Color3.fromRGB(240, 240, 248),
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
    Active = true,
    ZIndex = 3,
}, panel)

local function button(parent, text, size, position)
    local object = make("TextButton", {
        Size = size,
        Position = position or UDim2.fromOffset(0, 0),
        BackgroundColor3 = muted,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = Color3.fromRGB(248, 248, 255),
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = true,
        ZIndex = 3,
    }, parent)
    make("UICorner", { CornerRadius = UDim.new(0, 7) }, object)
    return object
end

local minimize = button(panel, "-", UDim2.fromOffset(28, 28), UDim2.fromOffset(168, 6))
local close = button(panel, "X", UDim2.fromOffset(28, 28), UDim2.fromOffset(202, 6))
local body = make("ScrollingFrame", {
    Position = UDim2.fromOffset(10, 44),
    Size = UDim2.fromOffset(216, panelHeight - 54),
    CanvasSize = UDim2.fromOffset(0, 440),
    ScrollBarThickness = 3,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    BorderSizePixel = 0,
    BackgroundTransparency = 1,
    ZIndex = 3,
}, panel)
local aimButton = button(body, "Mira: OFF", UDim2.fromOffset(216, 34))
local espButton = button(body, "ESP: OFF", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 40))
local wallButton = button(body, "Checar paredes: ON", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 80))
local kickButton = button(body, "Anti-Kick local: OFF", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 120))
local teamButton = button(body, "Equipes: ON", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 160))
local inputButton = button(body, "Mira: Auto", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 200))
local less = button(body, "-", UDim2.fromOffset(38, 32), UDim2.fromOffset(0, 240))
local more = button(body, "+", UDim2.fromOffset(38, 32), UDim2.fromOffset(178, 240))
local fovLabel = make("TextLabel", {
    Position = UDim2.fromOffset(42, 240),
    Size = UDim2.fromOffset(132, 32),
    BackgroundTransparency = 1,
    Text = "FOV: " .. Config.FOV,
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(235, 235, 245),
    ZIndex = 3,
}, body)
local strengthLess = button(body, "-", UDim2.fromOffset(38, 32), UDim2.fromOffset(0, 280))
local strengthMore = button(body, "+", UDim2.fromOffset(38, 32), UDim2.fromOffset(178, 280))
local strengthLabel = make("TextLabel", {
    Position = UDim2.fromOffset(42, 280),
    Size = UDim2.fromOffset(132, 32),
    BackgroundTransparency = 1,
    Text = "Forca: " .. Config.AimStrength .. "%",
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(235, 235, 245),
    ZIndex = 3,
}, body)
local status = make("TextLabel", {
    Position = UDim2.fromOffset(0, 318),
    Size = UDim2.fromOffset(216, 78),
    BackgroundTransparency = 1,
    Text = "Alvo: nenhum",
    TextWrapped = true,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(211, 211, 228),
    ZIndex = 3,
}, body)
make("TextLabel", {
    Position = UDim2.fromOffset(0, 400),
    Size = UDim2.fromOffset(216, 34),
    BackgroundTransparency = 1,
    Text = "Versao de teste. Arraste o titulo.\nAnti-Kick local nao impede banimento.",
    TextWrapped = true,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = Color3.fromRGB(160, 164, 185),
    ZIndex = 3,
}, body)

local function paintButton(object, enabled, label)
    object.Text = label .. (enabled and ": ON" or ": OFF")
    object.BackgroundColor3 = enabled and accent or muted
end

local function refreshUI()
    paintButton(aimButton, Config.Aim, "Mira")
    paintButton(espButton, Config.ESP, "ESP")
    paintButton(wallButton, Config.WallCheck, "Checar paredes")
    paintButton(kickButton, kickGuard.enabled, "Anti-Kick local")
    if kickGuard.error then
        kickButton.Text = "Anti-Kick: indisponivel"
    end
    paintButton(teamButton, Config.TeamCheck, "Equipes")
    inputButton.Text = "Entrada: " .. Config.AimInput .. " (" .. aimInput() .. ")"
    fovLabel.Text = "FOV: " .. Config.FOV
    strengthLabel.Text = "Forca: " .. Config.AimStrength .. "%"
    ring.Size = UDim2.fromOffset(Config.FOV * 2, Config.FOV * 2)
    ring.Visible = Config.Aim
end
refreshUI()

connect(aimButton.Activated, function()
    Config.Aim = not Config.Aim
    target = nil
    scanElapsed = Config.ScanInterval
    refreshUI()
end)
connect(espButton.Activated, function()
    Config.ESP = not Config.ESP
    espNotice = nil
    if not Config.ESP then
        clearESP()
    end
    espElapsed = Config.ESPInterval
    refreshUI()
end)
connect(wallButton.Activated, function()
    Config.WallCheck = not Config.WallCheck
    target = nil
    scanElapsed = Config.ScanInterval
    refreshUI()
end)
connect(kickButton.Activated, function()
    local wanted = not kickGuard.enabled
    local ok, reason = kickGuard:SetEnabled(wanted)
    Config.AntiKick = kickGuard.enabled
    if not ok then
        kickNotice = reason or "Anti-Kick local indisponivel."
        kickNoticeUntil = os.clock() + 6
        warn("VANTA: " .. kickNotice)
    else
        kickNotice = nil
    end
    refreshUI()
end)
connect(teamButton.Activated, function()
    Config.TeamCheck = not Config.TeamCheck
    target = nil
    scanElapsed = Config.ScanInterval
    clearESP()
    espElapsed = Config.ESPInterval
    refreshUI()
end)
connect(inputButton.Activated, function()
    if Config.AimInput == "Auto" then
        Config.AimInput = mouseAvailable() and "Mouse" or "Camera"
    elseif Config.AimInput == "Mouse" then
        Config.AimInput = "Camera"
    else
        Config.AimInput = "Auto"
    end
    target = nil
    scanElapsed = Config.ScanInterval
    inputNotice = nil
    refreshUI()
end)
connect(less.Activated, function()
    Config.FOV = math.clamp(Config.FOV - 25, 50, 350)
    target = nil
    scanElapsed = Config.ScanInterval
    refreshUI()
end)
connect(more.Activated, function()
    Config.FOV = math.clamp(Config.FOV + 25, 50, 350)
    refreshUI()
end)
connect(strengthLess.Activated, function()
    Config.AimStrength = math.clamp(Config.AimStrength - 5, 20, 100)
    refreshUI()
end)
connect(strengthMore.Activated, function()
    Config.AimStrength = math.clamp(Config.AimStrength + 5, 20, 100)
    refreshUI()
end)
local collapsed = false
connect(minimize.Activated, function()
    collapsed = not collapsed
    body.Visible = not collapsed
    panel.Size = UDim2.fromOffset(236, collapsed and 40 or panelHeight)
    minimize.Text = collapsed and "+" or "-"
end)
connect(close.Activated, shutdown)

-- Arraste pelo titulo; os demais toques continuam disponiveis para o jogo.
local dragging = false
local dragInput, dragStart, panelStart
connect(dragHandle.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragInput = input
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        panelStart = panel.AbsolutePosition
    end
end)
connect(UserInputService.InputChanged, function(input)
    if not dragging then
        return
    end
    local touchMove = input == dragInput
    local mouseMove = dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement
    if not touchMove and not mouseMove then
        return
    end
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
    local size = camera.ViewportSize
    local x = math.clamp(panelStart.X + delta.X, 0, math.max(0, size.X - panel.AbsoluteSize.X))
    local y = math.clamp(panelStart.Y + delta.Y, 0, math.max(0, size.Y - panel.AbsoluteSize.Y))
    panel.Position = UDim2.fromOffset(x, y)
end)
connect(UserInputService.InputEnded, function(input)
    if input == dragInput then
        dragging = false
        dragInput = nil
    end
end)

local function localAlive()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

-- BEGIN CHARACTER_RESOLVER
local function characterParts(other)
    local character = other.Character
    if not character or not character:IsDescendantOf(Workspace) then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return nil
    end
    for _, name in ipairs({ "Head", "UpperTorso", "Torso", "HumanoidRootPart" }) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return character, humanoid, part
        end
    end
    return nil
end
-- END CHARACTER_RESOLVER

local function getEnemy(other)
    if other == player or other.Parent ~= Players then
        return nil
    end
    if Config.TeamCheck then
        local enemy = teamRelation(player, other)
        if enemy ~= true then return nil end
    end
    return characterParts(other)
end

local function rosterStatus()
    local ready, unknown = 0, 0
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and characterParts(other) then
            ready = ready + 1
            if Config.TeamCheck and teamRelation(player, other) == nil then
                unknown = unknown + 1
            end
        end
    end
    if ready == 0 then return "Aguardando personagens compativeis." end
    if unknown > 0 then return "Equipe indefinida: " .. unknown .. " jogador(es)." end
    return "Personagens detectados: " .. ready
end

local function getESPCharacter(other)
    if other == player or other.Parent ~= Players then return nil end
    local character, humanoid, part = characterParts(other)
    if not character then return nil end
    local enemy = teamRelation(player, other)
    local relation = espRelation(enemy, Config.TeamCheck)
    if not relation then return nil end
    return character, humanoid, part, relation
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function visible(camera, character, head)
    if not Config.WallCheck then
        return true
    end
    local ignore = { camera }
    if player.Character then
        table.insert(ignore, player.Character)
    end
    rayParams.FilterDescendantsInstances = ignore
    local origin = camera.CFrame.Position
    local hit = Workspace:Raycast(origin, head.Position - origin, rayParams)
    return hit == nil or hit.Instance:IsDescendantOf(character)
end

-- BEGIN TARGET_SELECTOR
local function targetScore(camera, other)
    local character, _, head = getEnemy(other)
    if not character or (head.Position - camera.CFrame.Position).Magnitude > Config.MaxDistance then
        return nil
    end
    local center = camera.ViewportSize * 0.5
    local screen, onScreen = camera:WorldToViewportPoint(head.Position)
    if not onScreen or screen.Z <= 0 then return nil end
    local score = (Vector2.new(screen.X, screen.Y) - center).Magnitude
    if score > Config.FOV or not visible(camera, character, head) then return nil end
    return score
end

local function chooseTarget(camera)
    -- Mantem o alvo atual enquanto ele continuar elegivel, evitando trocas constantes.
    if target and targetScore(camera, target) ~= nil then return target end
    local chosen = nil
    local best = Config.FOV
    for _, other in ipairs(Players:GetPlayers()) do
        local score = targetScore(camera, other)
        if score and score <= best then
            best = score
            chosen = other
        end
    end
    return chosen
end
-- END TARGET_SELECTOR

local function updateESP(camera)
    espCounters.compatible, espCounters.drawn, espCounters.unknown = 0, 0, 0
    if not Config.ESP then return end
    local now = os.clock()
    local view = camera.ViewportSize
    for _, other in ipairs(Players:GetPlayers()) do
        local character, humanoid, head, relation = getESPCharacter(other)
        local distance = head and (head.Position - camera.CFrame.Position).Magnitude or math.huge
        if not character or distance > Config.MaxDistance then
            removeESP(other)
        else
            espCounters.compatible = espCounters.compatible + 1
            if relation == "unknown" then espCounters.unknown = espCounters.unknown + 1 end
            local item = espItems[other]
            if item and item.character ~= character then
                removeESP(other)
                item = nil
            end
            if not item then
                local box = make("Frame", {
                    Name = "PlayerBox",
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Visible = false,
                    ZIndex = 1,
                }, espLayer)
                local outline = make("UIStroke", { Thickness = 1.5, Color = accent }, box)
                local label = make("TextLabel", {
                    AnchorPoint = Vector2.new(0.5, 0),
                    Position = UDim2.new(0.5, 0, 0, -34),
                    Size = UDim2.fromOffset(200, 32),
                    BackgroundTransparency = 1,
                    TextColor3 = Color3.fromRGB(255, 240, 245),
                    TextStrokeTransparency = 0.1,
                    Font = Enum.Font.GothamBold,
                    TextSize = 12,
                    TextWrapped = true,
                    ZIndex = 1,
                }, box)
                local healthTrack = make("Frame", {
                    Position = UDim2.fromOffset(-6, 0),
                    Size = UDim2.new(0, 3, 1, 0),
                    BackgroundColor3 = Color3.fromRGB(35, 35, 40),
                    BorderSizePixel = 0,
                    ZIndex = 1,
                }, box)
                local healthFill = make("Frame", {
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.fromScale(0, 1),
                    Size = UDim2.fromScale(1, 1),
                    BackgroundColor3 = Color3.fromRGB(80, 240, 125),
                    BorderSizePixel = 0,
                    ZIndex = 1,
                }, healthTrack)
                item = { character = character, box = box, label = label, outline = outline,
                    healthFill = healthFill, lastLabelTime = -math.huge }
                espItems[other] = item
            end

            local root = character:FindFirstChild("HumanoidRootPart")
            if not root or not root:IsA("BasePart") then root = head end
            local actualHead = character:FindFirstChild("Head")
            if not actualHead or not actualHead:IsA("BasePart") then actualHead = nil end
            local topPosition = actualHead and (actualHead.Position + Vector3.new(0, actualHead.Size.Y * 0.5 + 0.2, 0))
                or (root.Position + Vector3.new(0, root.Size.Y * 0.5 + 2, 0))
            local bottomY = root.Position.Y - root.Size.Y * 0.5 - math.max(humanoid.HipHeight, 1.5)
            local footFound = false
            for _, name in ipairs({ "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }) do
                local foot = character:FindFirstChild(name)
                if foot and foot:IsA("BasePart") then
                    local footY = foot.Position.Y - foot.Size.Y * 0.5
                    bottomY = footFound and math.min(bottomY, footY) or footY
                    footFound = true
                end
            end
            local bottomPosition = Vector3.new(root.Position.X, bottomY, root.Position.Z)
            local top = camera:WorldToViewportPoint(topPosition)
            local bottom = camera:WorldToViewportPoint(bottomPosition)
            local x, y, width, height = screenBox(top.X, top.Y, top.Z, bottom.X, bottom.Y, bottom.Z, view.X, view.Y)
            item.box.Visible = x ~= nil
            if x ~= nil then
                item.box.Position = UDim2.fromOffset(x, y)
                item.box.Size = UDim2.fromOffset(width, height)
                espCounters.drawn = espCounters.drawn + 1
                local color = relation == "unknown" and Color3.fromRGB(255, 190, 75)
                    or (relation == "ally" and Color3.fromRGB(90, 170, 255) or Color3.fromRGB(255, 85, 110))
                item.outline.Color = color
                item.label.TextColor3 = color
                local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
                item.healthFill.Size = UDim2.fromScale(1, ratio)
                if now - item.lastLabelTime >= Config.ESPInterval or item.relation ~= relation then
                    local tag = relation == "unknown" and " | EQUIPE ?" or (relation == "ally" and " | ALIADO" or "")
                    item.label.Text = string.format("@%s%s\n%d HP | %d studs",
                        other.Name, tag, math.ceil(humanoid.Health), math.floor(distance))
                    item.lastLabelTime = now
                    item.relation = relation
                end
            end
        end
    end
end

connect(Players.PlayerRemoving, function(other)
    removeESP(other)
    if target == other then
        target = nil
    end
end)
connect(player.CharacterAdded, function()
    target = nil
    scanElapsed = Config.ScanInterval
end)

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value + 1, function(dt)
    if not active then
        return
    end
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    local size = camera.ViewportSize
    ring.Position = UDim2.fromOffset(size.X * 0.5, size.Y * 0.5)

    scanElapsed = scanElapsed + dt
    espElapsed = espElapsed + dt
    local input = aimInput()
    local canAim = UserInputService:GetFocusedTextBox() == nil and not dragging
    if input == "Mouse" and (not mouseAvailable()
        or UserInputService.MouseBehavior == Enum.MouseBehavior.Default) then
        canAim = false
    end
    if Config.Aim and localAlive() and canAim then
        if scanElapsed >= Config.ScanInterval then
            scanElapsed = 0
            target = chooseTarget(camera)
        end
        if target then
            local character, _, head = getEnemy(target)
            if character and targetScore(camera, target) ~= nil then
                local origin = camera.CFrame.Position
                if (head.Position - origin).Magnitude > 0.01 then
                    if input == "Mouse" then
                        local screen, onScreen = camera:WorldToViewportPoint(head.Position)
                        local dx, dy = screen.X - size.X * 0.5, screen.Y - size.Y * 0.5
                        if onScreen and screen.Z > 0 and dx * dx + dy * dy <= Config.FOV * Config.FOV then
                            local _, speed, gain, maxStep, deadzone = strengthSettings(Config.AimStrength)
                            local moveX, moveY = computeMouseStep(dx, dy, dt, speed, gain, maxStep, deadzone)
                            if moveX ~= 0 or moveY ~= 0 then
                                local moved = pcall(mouseMover, moveX, moveY)
                                if not moved then
                                    Config.Aim = false
                                    target = nil
                                    inputNotice = "Falha na entrada mouse. Mira desligada."
                                    inputNoticeUntil = os.clock() + 6
                                    refreshUI()
                                end
                            end
                        else
                            target = nil
                        end
                    else
                        local wanted = CFrame.lookAt(origin, head.Position)
                        local alpha = computeAimAlpha(dt, Config.AimStrength)
                        camera.CFrame = camera.CFrame:Lerp(wanted, alpha)
                    end
                end
            else
                target = nil
            end
        end
    else
        target = nil
    end

    local espOK, espError = pcall(updateESP, camera)
    if not espOK then
        Config.ESP = false
        clearESP()
        espNotice = "Falha no ESP. Veja a mensagem no console."
        espNoticeUntil = os.clock() + 10
        warn("VANTA ESP v0.2: " .. tostring(espError))
        refreshUI()
    end

    ringStroke.Color = target and Color3.fromRGB(100, 255, 170) or accent
    if espElapsed >= Config.ESPInterval then
        espElapsed = 0
        if espNotice and os.clock() < espNoticeUntil then
            status.Text = espNotice
        elseif inputNotice and os.clock() < inputNoticeUntil then
            status.Text = inputNotice
        elseif kickNotice and os.clock() < kickNoticeUntil then
            status.Text = kickNotice
        else
            local targetText = target and ("Alvo: @" .. target.Name) or "Alvo: nenhum"
            local espText = Config.ESP and ("ESP: " .. espCounters.drawn .. "/" .. espCounters.compatible
                .. " | Equipe ?: " .. espCounters.unknown) or "ESP: OFF"
            status.Text = targetText .. "\n" .. rosterStatus() .. "\n" .. espText
            if kickGuard.enabled then
                status.Text = status.Text .. "\nKick local bloqueado: " .. kickGuard.blocked
            end
            inputButton.Text = "Entrada: " .. Config.AimInput .. " (" .. input .. ")"
        end
    end
end)

print("VANTA BloxStrike v0.2 TESTE carregado. ESP 2D; Forca da mira ajustavel de 20 a 100. X encerra.")
