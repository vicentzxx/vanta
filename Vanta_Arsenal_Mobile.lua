-- VANTA Mobile | Luau / Roblox client
-- Execute o arquivo inteiro. Mira e ESP comecam desligados.
-- Compativel com APIs padrao do cliente; nao testado no Arsenal/executores.
-- X encerra e limpa os objetos/conexoes. Executar novamente substitui a UI.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
assert(player, "Execute no cliente, depois de entrar no jogo.")
local playerGui = player:WaitForChild("PlayerGui", 15)
assert(playerGui, "PlayerGui indisponivel. Entre no jogo e tente novamente.")

local Config = {
    Aim = false,
    ESP = false,
    WallCheck = true,
    TeamCheck = true,
    FOV = 150,           -- Raio em pixels, a partir do centro da tela.
    MaxDistance = 2500,  -- Distancia em studs.
    AimSpeed = 14,       -- Quanto maior, mais rapida a mira.
    ScanInterval = 0.05,
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
local espFolder = make("Folder", { Name = FOLDER_NAME }, Workspace)

local function removeESP(other)
    local item = espItems[other]
    if item then
        item.highlight:Destroy()
        item.billboard:Destroy()
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
end

local function shutdown()
    if not active then
        return
    end
    active = false
    RunService:UnbindFromRenderStep(RENDER_NAME)
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    clearESP()
    espFolder:Destroy()
    gui:Destroy()
end
connect(shutdownEvent.Event, shutdown)
connect(gui.Destroying, shutdown)

local accent = Color3.fromRGB(124, 100, 255)
local muted = Color3.fromRGB(60, 64, 82)
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
    Size = UDim2.fromOffset(236, 292),
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
    Text = "VANTA | ARSENAL",
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
local body = make("Frame", {
    Position = UDim2.fromOffset(10, 44),
    Size = UDim2.fromOffset(216, 238),
    BackgroundTransparency = 1,
    ZIndex = 3,
}, panel)
local aimButton = button(body, "Mira: OFF", UDim2.fromOffset(216, 34))
local espButton = button(body, "ESP: OFF", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 40))
local wallButton = button(body, "Checar paredes: ON", UDim2.fromOffset(216, 34), UDim2.fromOffset(0, 80))
local less = button(body, "-", UDim2.fromOffset(38, 32), UDim2.fromOffset(0, 120))
local more = button(body, "+", UDim2.fromOffset(38, 32), UDim2.fromOffset(178, 120))
local fovLabel = make("TextLabel", {
    Position = UDim2.fromOffset(42, 120),
    Size = UDim2.fromOffset(132, 32),
    BackgroundTransparency = 1,
    Text = "FOV: " .. Config.FOV,
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(235, 235, 245),
    ZIndex = 3,
}, body)
local status = make("TextLabel", {
    Position = UDim2.fromOffset(0, 158),
    Size = UDim2.fromOffset(216, 44),
    BackgroundTransparency = 1,
    Text = "Alvo: nenhum",
    TextWrapped = true,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(211, 211, 228),
    ZIndex = 3,
}, body)
make("TextLabel", {
    Position = UDim2.fromOffset(0, 204),
    Size = UDim2.fromOffset(216, 30),
    BackgroundTransparency = 1,
    Text = "Arraste o titulo para mover.\nMira acompanha o centro da tela.",
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
    fovLabel.Text = "FOV: " .. Config.FOV
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
local collapsed = false
connect(minimize.Activated, function()
    collapsed = not collapsed
    body.Visible = not collapsed
    panel.Size = UDim2.fromOffset(236, collapsed and 40 or 292)
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

local function getEnemy(other)
    if other == player or other.Parent ~= Players then
        return nil
    end
    if Config.TeamCheck and not player.Neutral and not other.Neutral
        and player.Team ~= nil and player.Team == other.Team then
        return nil
    end
    local character = other.Character
    if not character or not character:IsDescendantOf(Workspace) then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local head = character:FindFirstChild("Head")
    if not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
        return nil
    end
    return character, humanoid, head
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

local function chooseTarget(camera)
    local center = camera.ViewportSize * 0.5
    local chosen = nil
    local best = Config.FOV
    for _, other in ipairs(Players:GetPlayers()) do
        local character, _, head = getEnemy(other)
        if character then
            local distance = (head.Position - camera.CFrame.Position).Magnitude
            if distance <= Config.MaxDistance then
                local screen, onScreen = camera:WorldToViewportPoint(head.Position)
                if onScreen and screen.Z > 0 then
                    local score = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                    if score <= best and visible(camera, character, head) then
                        best = score
                        chosen = other
                    end
                end
            end
        end
    end
    return chosen
end

local function updateESP(camera)
    if not Config.ESP then
        return
    end
    for _, other in ipairs(Players:GetPlayers()) do
        local character, humanoid, head = getEnemy(other)
        local distance = head and (head.Position - camera.CFrame.Position).Magnitude or math.huge
        if not character or distance > Config.MaxDistance then
            removeESP(other)
        else
            local item = espItems[other]
            if item and item.character ~= character then
                removeESP(other)
                item = nil
            end
            if not item then
                local highlight = make("Highlight", {
                    Adornee = character,
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                    FillColor = Color3.fromRGB(255, 80, 110),
                    FillTransparency = 0.72,
                    OutlineColor = Color3.fromRGB(255, 230, 235),
                    OutlineTransparency = 0,
                }, espFolder)
                local billboard = make("BillboardGui", {
                    Name = "PlayerInfo",
                    Adornee = head,
                    Size = UDim2.fromOffset(180, 42),
                    StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0),
                    AlwaysOnTop = true,
                    MaxDistance = Config.MaxDistance,
                }, espFolder)
                local label = make("TextLabel", {
                    Size = UDim2.fromScale(1, 1),
                    BackgroundTransparency = 1,
                    TextColor3 = Color3.fromRGB(255, 240, 245),
                    TextStrokeTransparency = 0.25,
                    Font = Enum.Font.GothamBold,
                    TextSize = 12,
                    TextWrapped = true,
                }, billboard)
                item = { character = character, highlight = highlight, billboard = billboard, label = label }
                espItems[other] = item
            end
            item.billboard.Adornee = head
            item.label.Text = string.format("%s (@%s)\n%d HP | %d studs",
                other.DisplayName, other.Name, math.ceil(humanoid.Health), math.floor(distance))
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

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
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
    if Config.Aim and localAlive() then
        if scanElapsed >= Config.ScanInterval then
            scanElapsed = 0
            target = chooseTarget(camera)
        end
        if target then
            local character, _, head = getEnemy(target)
            if character then
                local origin = camera.CFrame.Position
                if (head.Position - origin).Magnitude > 0.01 then
                    local wanted = CFrame.lookAt(origin, head.Position)
                    local alpha = 1 - math.exp(-Config.AimSpeed * math.min(dt, 0.1))
                    camera.CFrame = camera.CFrame:Lerp(wanted, alpha)
                end
            else
                target = nil
            end
        end
    else
        target = nil
    end

    ringStroke.Color = target and Color3.fromRGB(100, 255, 170) or accent
    if espElapsed >= Config.ESPInterval then
        espElapsed = 0
        updateESP(camera)
        status.Text = target and ("Alvo: @" .. target.Name) or "Alvo: nenhum"
    end
end)

print("VANTA Mobile carregado. Use os botoes Mira e ESP. X encerra.")
