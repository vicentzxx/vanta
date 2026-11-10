-- VANTA BloxStrike v0.5 TESTE | Luau / Roblox client
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
    MyTeam = "Auto",     -- Auto | CT | T. Os dois recursos selecionam apenas adversarios conhecidos.
    FOV = 150,           -- Raio em pixels, a partir do centro da tela.
    MaxDistance = 2500,  -- Alcance da mira em studs.
    ESPMaxDistance = 2500, -- Alcance independente do ESP; ajustavel no painel.
    AimStrength = 100,   -- 20 a 100. Em Camera, 100 centraliza diretamente no alvo.
    AimInput = "Camera", -- Camera por padrao; evita assumir semantica de mousemoverel no Xeno.
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
local resolveCharacter
local frameData -- Somente referencias/atributos do quadro atual; nunca conserva posicoes antigas.

-- BEGIN BLOXSTRIKE_HELPERS
local TEAM_ALIASES = {
    ct = "ct", counterterrorist = "ct", counterterrorists = "ct",
    contraterrorista = "ct", contraterroristas = "ct",
    t = "t", terrorist = "t", terrorists = "t", terrorista = "t", terroristas = "t",
}
local INACTIVE_TEAMS = { spectator = true, spectators = true, spec = true,
    observer = true, observers = true, lobby = true, neutral = true,
    unassigned = true, none = true, unknown = true }
local function normalizeTeam(value)
    if type(value) == "number" then
        if value ~= value or math.abs(value) == math.huge then return nil end
        return string.format("%.17g", value)
    end
    if type(value) == "string" then
        local text = value:match("^%s*(.-)%s*$")
        local numeric = tonumber(text)
        if numeric ~= nil and numeric == numeric and math.abs(numeric) ~= math.huge then
            return string.format("%.17g", numeric)
        end
        local compact = string.lower(text):gsub("[^%w]", "")
        if TEAM_ALIASES[compact] then return TEAM_ALIASES[compact] end
        if INACTIVE_TEAMS[compact] then return nil, "inactive" end
        if text ~= "" then return string.lower(text) end
    end
    return nil
end

local function readAttribute(object, name)
    if not object or type(object.GetAttribute) ~= "function" then return nil end
    if frameData and type(object.GetAttributes) == "function" then
        local attributes = frameData.attributes[object]
        if not attributes then
            local ok, values = pcall(object.GetAttributes, object)
            if ok and type(values) == "table" then
                attributes = values
                frameData.attributes[object] = attributes
            end
        end
        if attributes then return attributes[name] end
    end
    local ok, value = pcall(object.GetAttribute, object, name)
    if ok then return value end
    return nil
end

local function readPlayerTeam(other)
    local cached = frameData and frameData.teams[other]
    if cached then return cached[1], cached[2] end
    local function result(side, source)
        if frameData then frameData.teams[other] = { side, source } end
        return side, source
    end
    local fallback, source, inactive = nil, nil, false
    local character = other.Character
    if type(resolveCharacter) == "function" then character = resolveCharacter(other) or character end
    for _, entry in ipairs({ { other, "Player" }, { character, "Character" } }) do
        for _, key in ipairs({ "Team", "TeamName", "Side", "Faction", "team", "teamName", "side", "faction" }) do
            local side, kind = normalizeTeam(readAttribute(entry[1], key))
            if side == "ct" or side == "t" then return result(side, entry[2] .. "." .. key) end
            if kind == "inactive" then inactive = true end
            if side and fallback == nil then fallback, source = side, entry[2] .. "." .. key end
        end
    end
    if other.Team ~= nil and not other.Neutral then
        local side, kind = normalizeTeam(other.Team.Name)
        if side == "ct" or side == "t" then return result(side, "Player.Team") end
        if kind == "inactive" then inactive = true end
        if side and fallback == nil then fallback, source = side, "Player.Team" end
    end
    if inactive then return result(nil, "inactive") end
    return result(fallback, source or "desconhecida")
end

local function teamColorKey(other)
    local color = other.TeamColor
    if not color or type(color.Name) ~= "string" then return nil end
    local name = string.lower(color.Name):gsub("[^%w]", "")
    if name == "" or name == "white" or name == "institutionalwhite" or name == "mediumstonegrey" then
        return nil
    end
    return tostring(color.Number or color.Name)
end

-- Um lado desconhecido nunca e tratado como inimigo. CT e T sao canonizados
-- para que, por exemplo, CT e Counter-Terrorists representem a mesma equipe.
local function teamRelation(localPlayer, other, override)
    local mine, mineSource
    if override and override ~= "Auto" then
        mine, mineSource = normalizeTeam(override), "manual"
    else
        mine, mineSource = readPlayerTeam(localPlayer)
    end
    local theirs, theirSource = readPlayerTeam(other)
    if mineSource == "inactive" or theirSource == "inactive" then return false, "fora da rodada" end
    if mine ~= nil and theirs ~= nil then
        local mineCanonical = mine == "ct" or mine == "t"
        local theirCanonical = theirs == "ct" or theirs == "t"
        if mineCanonical ~= theirCanonical then return nil, "equipe desconhecida" end
        return mine ~= theirs, "equipes reconhecidas"
    end
    if mine == nil and theirs == nil and not localPlayer.Neutral and not other.Neutral
        and localPlayer.Team ~= nil and other.Team ~= nil then
        return localPlayer.Team ~= other.Team, "Teams"
    end
    local mineColor, theirColor = teamColorKey(localPlayer), teamColorKey(other)
    if mineColor ~= nil and theirColor ~= nil then
        return mineColor ~= theirColor, "Player.TeamColor"
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

local function espRelation(enemy)
    return enemy == true and "enemy" or nil
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
    Text = "VANTA | BLOX v0.5",
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
    CanvasSize = UDim2.fromOffset(0, 520),
    ScrollBarThickness = 3,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    BorderSizePixel = 0,
    BackgroundTransparency = 1,
    ZIndex = 3,
}, panel)
local aimButton = button(body, "Mira: OFF", UDim2.fromOffset(216, 34))
local espButton = button(body, "ESP inimigos: OFF", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 40))
local wallButton = button(body, "Checar paredes: ON", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 80))
local kickButton = button(body, "Anti-Kick local: OFF", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 120))
local teamButton = button(body, "Minha equipe: Auto", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 160))
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
local espDistanceLess = button(body, "-", UDim2.fromOffset(38, 32), UDim2.fromOffset(0, 320))
local espDistanceMore = button(body, "+", UDim2.fromOffset(38, 32), UDim2.fromOffset(178, 320))
local espDistanceLabel = make("TextLabel", {
    Position = UDim2.fromOffset(42, 320),
    Size = UDim2.fromOffset(132, 32),
    BackgroundTransparency = 1,
    Text = "ESP: " .. Config.ESPMaxDistance .. " studs",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(235, 235, 245),
    ZIndex = 3,
}, body)
local status = make("TextLabel", {
    Position = UDim2.fromOffset(0, 358),
    Size = UDim2.fromOffset(216, 78),
    BackgroundTransparency = 1,
    Text = "Alvo: nenhum",
    TextWrapped = true,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(211, 211, 228),
    ZIndex = 3,
}, body)
local diagnosticButton = button(body, "Copiar diagnostico", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 440))
make("TextLabel", {
    Position = UDim2.fromOffset(0, 480),
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
    paintButton(espButton, Config.ESP, "ESP inimigos")
    paintButton(wallButton, Config.WallCheck, "Checar paredes")
    paintButton(kickButton, kickGuard.enabled, "Anti-Kick local")
    if kickGuard.error then
        kickButton.Text = "Anti-Kick: indisponivel"
    end
    local side = Config.MyTeam ~= "Auto" and normalizeTeam(Config.MyTeam) or readPlayerTeam(player)
    teamButton.Text = "Minha equipe: " .. (side and string.upper(side) or "Auto (?)")
    inputButton.Text = "Entrada: " .. Config.AimInput .. " (" .. aimInput() .. ")"
    fovLabel.Text = "FOV: " .. Config.FOV
    strengthLabel.Text = "Forca: " .. Config.AimStrength .. "%"
    espDistanceLabel.Text = "ESP: " .. Config.ESPMaxDistance .. " studs"
    espDistanceLess.Active = Config.ESPMaxDistance > 250
    espDistanceMore.Active = Config.ESPMaxDistance < 10000
    espDistanceLess.TextTransparency = Config.ESPMaxDistance <= 250 and 0.6 or 0
    espDistanceMore.TextTransparency = Config.ESPMaxDistance >= 10000 and 0.6 or 0
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
    if Config.MyTeam == "Auto" then Config.MyTeam = "CT"
    elseif Config.MyTeam == "CT" then Config.MyTeam = "T"
    else Config.MyTeam = "Auto" end
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
connect(espDistanceLess.Activated, function()
    Config.ESPMaxDistance = math.clamp(Config.ESPMaxDistance - 250, 250, 10000)
    refreshUI()
end)
connect(espDistanceMore.Activated, function()
    Config.ESPMaxDistance = math.clamp(Config.ESPMaxDistance + 250, 250, 10000)
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

-- BEGIN CHARACTER_RESOLVER
local function finiteHealth(value)
    local number = tonumber(value)
    if number == nil or number ~= number or math.abs(number) == math.huge then return nil end
    return number
end

local function worldCharacter(character)
    return character ~= nil and character.Parent ~= nil
        and type(character.IsDescendantOf) == "function" and character:IsDescendantOf(Workspace)
end

local function bodyPartBelongs(part, character)
    if not part or not part.Parent or not part:IsA("BasePart") or not part:IsDescendantOf(character) then
        return false
    end
    return not part:FindFirstAncestorOfClass("Tool") and not part:FindFirstAncestorOfClass("Accessory")
end

local function namedBodyPart(character, name)
    local parts = frameData and frameData.parts[character]
    if parts and parts[name] ~= nil then
        local part = parts[name]
        return part ~= false and bodyPartBelongs(part, character) and part or nil
    end
    local part = character:FindFirstChild(name)
    if not bodyPartBelongs(part, character) then part = character:FindFirstChild(name, true) end
    if not bodyPartBelongs(part, character) then part = nil end
    if frameData then
        parts = parts or {}
        parts[name] = part or false
        frameData.parts[character] = parts
    end
    return part
end

local function findBodyPart(character)
    for _, name in ipairs({ "Head", "HeadHB", "UpperTorso", "Torso", "HumanoidRootPart" }) do
        local part = namedBodyPart(character, name)
        if part then return part end
    end
    return nil
end

local function resolveWorldCharacter(other)
    local character = other.Character
    if worldCharacter(character) and findBodyPart(character) then return character end
    if type(Workspace.FindFirstChild) == "function" then
        for _, folderName in ipairs({ "Characters", "Players", "PlayerCharacters" }) do
            local folder = Workspace:FindFirstChild(folderName)
            if folder then
                local model = folder:FindFirstChild(other.Name)
                    or (other.UserId and folder:FindFirstChild(tostring(other.UserId)))
                if worldCharacter(model) and findBodyPart(model) then return model end
            end
        end
        local model = other.Name and Workspace:FindFirstChild(other.Name)
        if worldCharacter(model) and findBodyPart(model) then return model end
    end
    return worldCharacter(character) and character or nil
end

resolveCharacter = function(other)
    local cached = frameData and frameData.models[other]
    if cached ~= nil then return cached ~= false and cached or nil end
    local character = resolveWorldCharacter(other)
    if frameData then frameData.models[other] = character or false end
    return character
end

local function lifeData(character, owner)
    local cached = frameData and frameData.lives[owner or character]
    if cached and cached.character == character then return cached.stats, cached.dead end
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid and character and type(character.FindFirstChildWhichIsA) == "function" then
        humanoid = character:FindFirstChildWhichIsA("Humanoid", true)
    end
    local health = finiteHealth(readAttribute(character, "Health"))
        or finiteHealth(readAttribute(owner, "Health"))
    local attributeHealth = health ~= nil
    local alive = readAttribute(character, "Alive")
    if alive == nil then alive = readAttribute(owner, "Alive") end
    if health == nil and humanoid and alive ~= true then health = finiteHealth(humanoid.Health) end
    local dead = alive == false or (health ~= nil and health <= 0)
    local maxHealth = finiteHealth(readAttribute(character, "MaxHealth"))
        or finiteHealth(readAttribute(owner, "MaxHealth"))
        or (humanoid and finiteHealth(humanoid.MaxHealth))
    local hipHeight = humanoid and finiteHealth(humanoid.HipHeight) or 2
    local stats = { Health = health, MaxHealth = maxHealth, HipHeight = hipHeight or 2,
        humanoid = humanoid, LifeKnown = attributeHealth or health ~= nil or alive ~= nil }
    if frameData and (owner or character) then
        frameData.lives[owner or character] = { character = character, stats = stats, dead = dead }
    end
    return stats, dead
end

local function characterParts(other)
    local character = resolveCharacter(other)
    if not character then return nil, nil, nil, "sem modelo" end
    local part = findBodyPart(character)
    if not part then return nil, nil, nil, "sem partes" end
    local stats, dead = lifeData(character, other)
    if dead then return nil, nil, nil, "morto" end
    return character, stats, part
end

local function localAlive(owner)
    owner = owner or player
    local _, dead = lifeData(resolveCharacter(owner), owner)
    -- Um FPS pode manter so o viewmodel local. Ausencia de corpo nao significa morte.
    -- Vida zero ou Alive=false continuam interrompendo a mira.
    return not dead
end
-- END CHARACTER_RESOLVER

-- BEGIN PLAYER_OBSERVATION
local function getEnemy(other)
    if other == player or other.Parent ~= Players then
        return nil
    end
    local enemy = teamRelation(player, other, Config.MyTeam)
    if enemy ~= true then return nil end
    return characterParts(other)
end

local function rosterStatus()
    local listed, models, ready, unknown = 0, 0, 0, 0
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            listed = listed + 1
            if resolveCharacter(other) then models = models + 1 end
            if characterParts(other) then
                ready = ready + 1
                if teamRelation(player, other, Config.MyTeam) == nil then unknown = unknown + 1 end
            end
        end
    end
    return "Jogadores: " .. listed .. " | Modelos: " .. models .. "\nAlvos com partes: " .. ready .. " | Equipe ?: " .. unknown
end

local function getESPCharacter(other)
    if other == player or other.Parent ~= Players then return nil end
    local enemy = teamRelation(player, other, Config.MyTeam)
    local relation = espRelation(enemy)
    if not relation then return nil, nil, nil, enemy == nil and "unknown" or "ally" end
    local character, humanoid, part = characterParts(other)
    if not character then return nil end
    return character, humanoid, part, relation
end
-- END PLAYER_OBSERVATION

-- BEGIN VISIBILITY_CHECK
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function lineOfSight(camera, character, part)
    if not worldCharacter(character) or not bodyPartBelongs(part, character) then return false, "corpo invalido" end
    local origin, position = camera.CFrame.Position, part.Position
    local cached = frameData and frameData.visibility[part]
    if cached and cached.origin == origin and cached.position == position and cached.character == character then
        return cached.clear, cached.reason
    end
    local function result(clear, reason)
        if frameData then
            frameData.visibility[part] = { origin = origin, position = position, character = character,
                clear = clear, reason = reason }
        end
        return clear, reason
    end
    -- Ignorar o proprio alvo permite testar o percurso inteiro ate sua posicao,
    -- sem aceitar um hitbox externo que intercepte o raio antes de uma parede.
    local ignore = { camera, character }
    local localCharacter = resolveCharacter(player)
    if localCharacter then table.insert(ignore, localCharacter) end
    rayParams.FilterDescendantsInstances = ignore
    local rayOK, hit = pcall(Workspace.Raycast, Workspace, origin, position - origin, rayParams)
    if not rayOK then return result(false, "consulta falhou") end
    if hit ~= nil then return result(false, "parede/obstaculo") end

    -- Consulta complementar da camera; continua sem bloquear o desenho do ESP.
    local cameraOK, blockers = pcall(camera.GetPartsObscuringTarget, camera, { position }, ignore)
    if not cameraOK then return result(false, "consulta da camera falhou") end
    for _, blocker in ipairs(blockers) do
        if blocker.Transparency < 1 and blocker.LocalTransparencyModifier < 1 then
            return result(false, "parede/obstaculo")
        end
    end
    return result(true, "livre")
end

local function visible(camera, character, part)
    if not Config.WallCheck then return true end
    return lineOfSight(camera, character, part)
end
-- END VISIBILITY_CHECK

-- BEGIN ESP_WORLD_BOUNDS
local function espWorldBounds(character, stats, anchor)
    -- Caixa e mira usam a mesma ancora. A raiz/pes so ajustam a altura se
    -- pertencerem ao mesmo corpo e estiverem proximos dessa ancora.
    local position = anchor.Position
    local isHead = anchor.Name == "Head" or anchor.Name == "HeadHB"
    local topY = position.Y + anchor.Size.Y * 0.5 + (isHead and 0.2 or 2)
    local bottomY = position.Y - (isHead and 4.5 or 3)
    local root = namedBodyPart(character, "HumanoidRootPart")
    if root and (root.Position - position).Magnitude <= 12 then
        local candidate = root.Position.Y - root.Size.Y * 0.5 - math.max(stats.HipHeight, 1.5)
        if candidate < topY and topY - candidate <= 14 then bottomY = candidate end
    end
    local footFound = false
    for _, name in ipairs({ "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }) do
        local foot = namedBodyPart(character, name)
        if foot and (foot.Position - position).Magnitude <= 12 then
            local footY = foot.Position.Y - foot.Size.Y * 0.5
            if footY < topY and topY - footY <= 14 then
                bottomY = footFound and math.min(bottomY, footY) or footY
                footFound = true
            end
        end
    end
    return Vector3.new(position.X, topY, position.Z), Vector3.new(position.X, bottomY, position.Z)
end
-- END ESP_WORLD_BOUNDS

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

-- BEGIN ESP_RENDERER
local function updateESPItem(camera, other)
    local view = camera.ViewportSize
    local character, humanoid, head, relation = getESPCharacter(other)
    if relation == "unknown" then espCounters.unknown = espCounters.unknown + 1 end
    local distance = head and (head.Position - camera.CFrame.Position).Magnitude or math.huge
    if not character or distance > Config.ESPMaxDistance then
        removeESP(other)
    else
        espCounters.compatible = espCounters.compatible + 1
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
            item = { character = character, box = box, label = label, outline = outline }
            espItems[other] = item
        end

        local topPosition, bottomPosition = espWorldBounds(character, humanoid, head)
        local top = camera:WorldToViewportPoint(topPosition)
        local bottom = camera:WorldToViewportPoint(bottomPosition)
        local x, y, width, height = screenBox(top.X, top.Y, top.Z, bottom.X, bottom.Y, bottom.Z, view.X, view.Y)
        item.box.Visible = x ~= nil
        if x ~= nil then
            item.box.Position = UDim2.fromOffset(x, y)
            item.box.Size = UDim2.fromOffset(width, height)
            espCounters.drawn = espCounters.drawn + 1
            local clear, reason = lineOfSight(camera, character, head)
            local blocked = reason == "parede/obstaculo"
            local color = clear and Color3.fromRGB(255, 85, 110) or Color3.fromRGB(255, 190, 80)
            item.outline.Color = color
            item.label.TextColor3 = color
            local suffix = blocked and " [parede]" or (not clear and " [?]" or "")
            item.label.Text = "@" .. other.Name .. suffix
        end
    end
end

local function hideESP()
    for _, item in pairs(espItems) do item.box.Visible = false end
end

local function updateESP(camera)
    espCounters.compatible, espCounters.drawn, espCounters.unknown = 0, 0, 0
    hideESP()
    if not Config.ESP then return end
    for _, other in ipairs(Players:GetPlayers()) do
        local ok, reason = pcall(updateESPItem, camera, other)
        if not ok then
            removeESP(other)
            if not espNotice or os.clock() >= espNoticeUntil then
                espNotice = "Um corpo falhou. Copie o diagnostico."
                espNoticeUntil = os.clock() + 6
                warn("VANTA ESP v0.5: @" .. other.Name .. ": " .. tostring(reason))
            end
        end
    end
end
-- END ESP_RENDERER

connect(diagnosticButton.Activated, function()
    -- Leitura pontual nova; o relatorio fica local ate o usuario decidir envia-lo.
    frameData = nil
    local camera = Workspace.CurrentCamera
    local report = { "VANTA BloxStrike v0.5", "StreamingEnabled=" .. tostring(Workspace.StreamingEnabled),
        "WallCheck=" .. tostring(Config.WallCheck) .. " | MinhaEquipe=" .. Config.MyTeam,
        "AlcanceESP=" .. Config.ESPMaxDistance .. " | AlcanceMira=" .. Config.MaxDistance }
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local ok, line = pcall(function()
                local model, stats, part, state = characterParts(other)
                local side = readPlayerTeam(other)
                local original = other.Character and other.Character:GetFullName() or "nil"
                local details = "@" .. other.Name .. " | equipe=" .. tostring(side) .. " | Character=" .. original
                if not model then return details .. " | " .. tostring(state) end
                local reason = "sem camera"
                if camera then
                    local clear
                    clear, reason = lineOfSight(camera, model, part)
                end
                return details .. " | modelo=" .. model:GetFullName() .. " | parte=" .. part:GetFullName()
                    .. " | pos=" .. tostring(part.Position) .. " | HP=" .. tostring(stats.Health)
                    .. " | vidaConhecida=" .. tostring(stats.LifeKnown) .. " | percurso=" .. tostring(reason)
            end)
            table.insert(report, ok and line or ("@" .. other.Name .. " | erro=" .. tostring(line)))
        end
    end
    local text = table.concat(report, "\n")
    print(text)
    local copied = type(setclipboard) == "function" and pcall(setclipboard, text)
    inputNotice = copied and "Diagnostico copiado. Cole no chat." or "Diagnostico no console (F9)."
    inputNoticeUntil = os.clock() + 7
end)

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

local function updateAim(camera, size, dt, input)
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
end

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value + 1, function(dt)
    if not active then return end
    -- A UI antiga fica escondida ate ser redesenhada com observacoes deste quadro.
    -- Assim ausencia de camera/corpo nao conserva uma caixa na ultima posicao.
    hideESP()
    local camera = Workspace.CurrentCamera
    if not camera then target = nil; frameData = nil; return end
    frameData = { attributes = {}, teams = {}, models = {}, parts = {}, lives = {}, visibility = {} }
    local size = camera.ViewportSize
    ring.Position = UDim2.fromOffset(size.X * 0.5, size.Y * 0.5)
    scanElapsed = scanElapsed + dt
    espElapsed = espElapsed + dt
    local input = aimInput()
    local aimOK, aimError = pcall(updateAim, camera, size, dt, input)
    if not aimOK then
        Config.Aim = false
        target = nil
        inputNotice = "Falha na mira. Copie o diagnostico."
        inputNoticeUntil = os.clock() + 10
        warn("VANTA Mira v0.5: " .. tostring(aimError))
        refreshUI()
    end

    local espOK, espError = pcall(updateESP, camera)
    if not espOK then
        Config.ESP = false
        clearESP()
        espNotice = "Falha no ESP. Veja a mensagem no console."
        espNoticeUntil = os.clock() + 10
        warn("VANTA ESP v0.5: " .. tostring(espError))
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
            local side = Config.MyTeam ~= "Auto" and normalizeTeam(Config.MyTeam) or readPlayerTeam(player)
            teamButton.Text = "Minha equipe: " .. (side and string.upper(side) or "Auto (?)")
        end
    end
    frameData = nil
end)

print("VANTA BloxStrike v0.5 TESTE carregado. Alcance ESP ajustavel: 250 a 10000 studs. X encerra.")
