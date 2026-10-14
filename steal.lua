-- language: Lua, executor: Xeno
-- *v14.0: Script estável com sistema de Três Modos, GUI com minimizar e teclas de atalho.
--  Prioriza estabilidade sobre truques complexos que podem falhar.*

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- ==================== ESTADO GLOBAL ====================
local modoAtual = "OFF" -- "OFF", "SEGURO", "AGRESSIVO"
local noclipAtivo = false
local anchorPos = nil
local anchorCFrame = nil
local walkSpeedOriginal = 16
local returnEmCurso = false
local janelaMinimizada = false

-- ==================== FUNÇÕES AUXILIARES ====================
local function getChar() return LocalPlayer.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function setStatus(texto, cor)
    if _G._statusLabel then
        _G._statusLabel.Text = texto
        _G._statusLabel.TextColor3 = cor or Color3.fromRGB(200, 200, 200)
    end
end

local function zerarFisica()
    local hrp = getHRP()
    if hrp then
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

local function aplicarNoclipAtivo(ativo)
    local char = getChar()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function() part.CanCollide = not ativo end)
        end
    end
end

-- ==================== SISTEMA DE MODOS ====================
local function modoSeguro_Ativar()
    local hrp = getHRP()
    if not hrp then
        setStatus("ERRO: Personagem não encontrado", Color3.fromRGB(255, 100, 100))
        return false
    end
    anchorPos = hrp.Position
    anchorCFrame = hrp.CFrame
    pcall(function() setfflag("DFIntS2PhysicsSenderRate", "-30") end)
    setStatus("MODO SEGURO ATIVO - Âncora salva", Color3.fromRGB(0, 220, 120))
    return true
end

local function modoSeguro_Desativar()
    pcall(function() setfflag("DFIntS2PhysicsSenderRate", "1") end)
    setStatus("MODO SEGURO DESATIVADO", Color3.fromRGB(200, 200, 200))
end

local function modoAgressivo_Ativar()
    local hum = getHum()
    if hum then
        walkSpeedOriginal = hum.WalkSpeed
        hum.WalkSpeed = 150
    end
    setStatus("MODO AGRESSIVO ATIVO - Speed 150", Color3.fromRGB(255, 200, 100))
    return true
end

local function modoAgressivo_Desativar()
    local hum = getHum()
    if hum then hum.WalkSpeed = walkSpeedOriginal end
    setStatus("MODO AGRESSIVO DESATIVADO", Color3.fromRGB(200, 200, 200))
end

-- ==================== FUNÇÃO DE TELEPORTE UNIFICADA ====================
local function executarTeleporte()
    if returnEmCurso then return end
    if not anchorPos then
        setStatus("Nenhuma âncora definida. Ative o Modo Seguro primeiro.", Color3.fromRGB(255, 100, 100))
        return
    end
    returnEmCurso = true
    setStatus("TELEPORTANDO...", Color3.fromRGB(255, 200, 100))

    task.spawn(function()
        -- 1. Desativar modo seguro temporariamente
        local eraModoSeguro = (modoAtual == "SEGURO")
        if eraModoSeguro then
            modoSeguro_Desativar()
            task.wait(0.1)
        end

        -- 2. Zerar física e teleportar
        zerarFisica()
        local hrp = getHRP()
        if hrp and anchorCFrame then
            hrp.CFrame = anchorCFrame
            zerarFisica()
        end

        -- 3. Sincronizar (reafirmar posição)
        setStatus("SINCRONIZANDO...", Color3.fromRGB(255, 200, 100))
        for i = 1, 15 do -- 1.5 segundos
            hrp = getHRP()
            if hrp and anchorCFrame then
                zerarFisica()
                hrp.CFrame = anchorCFrame
            end
            task.wait(0.1)
        end

        -- 4. Reativar modo seguro se estava ativo
        if eraModoSeguro then
            modoSeguro_Ativar()
        end

        setStatus("PRONTO PARA DROP", Color3.fromRGB(0, 220, 120))
        returnEmCurso = false
    end)
end

-- ==================== LÓGICA DE AUTO-RETURN ====================
local function configurarAutoReturn()
    local function hookContainer(container)
        container.ChildAdded:Connect(function(child)
            if not anchorPos or returnEmCurso then return end
            if not child:IsA("Tool") then return end
            task.wait(0.1)
            executarTeleporte()
        end)
    end

    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then hookContainer(bp) end
    LocalPlayer.ChildAdded:Connect(function(c)
        if c.Name == "Backpack" then hookContainer(c) end
    end)
end

-- ==================== EVENTOS DE PERSONAGEM ====================
local function onCharacterAdded(c)
    task.wait(0.5)
    -- Resetar estados
    noclipAtivo = false
    modoAtual = "OFF"
    pcall(function() setfflag("DFIntS2PhysicsSenderRate", "1") end)
    -- Reconfigurar
    aplicarNoclipAtivo(false)
    configurarAutoReturn()
    local hum = getHum()
    if hum then
        hum.WalkSpeed = walkSpeedOriginal
    end
    setStatus("PRONTO - Ative um modo", Color3.fromRGB(180, 180, 200))
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then
    task.spawn(onCharacterAdded, LocalPlayer.Character)
end

-- ==================== LOOP DE NOCLIP ====================
RunService.Stepped:Connect(function()
    if noclipAtivo then
        aplicarNoclipAtivo(true)
    end
    -- Proteção contra void
    local hrp = getHRP()
    local yMin = (workspace.FallenPartsDestroyHeight or -100) + 30
    if hrp and hrp.Position.Y < yMin and anchorPos then
        hrp.CFrame = CFrame.new(anchorPos + Vector3.new(0, 3, 0))
        zerarFisica()
    end
end)

-- ==================== GUI ====================
local pg = LocalPlayer:WaitForChild("PlayerGui", 10)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "XenoHub_v14"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 500
screenGui.Parent = pg

-- Container principal
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 320, 0, 340)
mainFrame.Position = UDim2.new(0, 20, 0, 80)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

-- Título
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -80, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Xeno Hub v14"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 15
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- Botão Minimizar
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
minimizeBtn.Position = UDim2.new(1, -40, 0, 3)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
minimizeBtn.Text = "−"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.TextSize = 20
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Parent = titleBar
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 6)

-- Container de conteúdo (para esconder ao minimizar)
local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, 0, 1, -36)
contentFrame.Position = UDim2.new(0, 0, 0, 36)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = mainFrame

-- Função Minimizar
local function toggleMinimize()
    janelaMinimizada = not janelaMinimizada
    contentFrame.Visible = not janelaMinimizada
    minimizeBtn.Text = janelaMinimizada and "+" or "−"
    mainFrame.Size = janelaMinimizada and UDim2.new(0, 320, 0, 36) or UDim2.new(0, 320, 0, 340)
end

minimizeBtn.MouseButton1Click:Connect(toggleMinimize)

-- Botões de Modo
local function criarBotaoModo(texto, y, cor)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.85, 0, 0, 36)
    btn.Position = UDim2.new(0.075, 0, 0, y)
    btn.BackgroundColor3 = cor
    btn.Text = texto
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent = contentFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    return btn
end

local btnSeguro = criarBotaoModo("Ativar MODO SEGURO", 10, Color3.fromRGB(0, 120, 70))
local btnAgressivo = criarBotaoModo("Ativar MODO AGRESSIVO", 52, Color3.fromRGB(150, 90, 0))
local btnOff = criarBotaoModo("MODO OFF (Resetar)", 94, Color3.fromRGB(80, 40, 40))

-- Lógica dos Modos
local function resetarModos()
    if modoAtual == "SEGURO" then modoSeguro_Desativar() end
    if modoAtual == "AGRESSIVO" then modoAgressivo_Desativar() end
    modoAtual = "OFF"
    btnSeguro.BackgroundColor3 = Color3.fromRGB(0, 120, 70)
    btnAgressivo.BackgroundColor3 = Color3.fromRGB(150, 90, 0)
end

btnSeguro.MouseButton1Click:Connect(function()
    resetarModos()
    if modoSeguro_Ativar() then
        modoAtual = "SEGURO"
        btnSeguro.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
    end
end)

btnAgressivo.MouseButton1Click:Connect(function()
    resetarModos()
    if modoAgressivo_Ativar() then
        modoAtual = "AGRESSIVO"
        btnAgressivo.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
    end
end)

btnOff.MouseButton1Click:Connect(function()
    resetarModos()
    setStatus("TODOS OS MODOS DESATIVADOS", Color3.fromRGB(200, 200, 200))
end)

-- Botão de Teleporte
local btnTeleporte = Instance.new("TextButton")
btnTeleporte.Size = UDim2.new(0.85, 0, 0, 36)
btnTeleporte.Position = UDim2.new(0.075, 0, 0, 140)
btnTeleporte.BackgroundColor3 = Color3.fromRGB(50, 50, 130)
btnTeleporte.Text = "TELEPORTAR PARA ÂNCORA (T)"
btnTeleporte.TextColor3 = Color3.fromRGB(255, 255, 255)
btnTeleporte.TextSize = 13
btnTeleporte.Font = Enum.Font.GothamBold
btnTeleporte.BorderSizePixel = 0
btnTeleporte.Parent = contentFrame
Instance.new("UICorner", btnTeleporte).CornerRadius = UDim.new(0, 8)
btnTeleporte.MouseButton1Click:Connect(executarTeleporte)

-- Toggle Noclip
local btnNoclip = Instance.new("TextButton")
btnNoclip.Size = UDim2.new(0.85, 0, 0, 36)
btnNoclip.Position = UDim2.new(0.075, 0, 0, 186)
btnNoclip.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
btnNoclip.Text = "NOCLIP: OFF"
btnNoclip.TextColor3 = Color3.fromRGB(200, 200, 200)
btnNoclip.TextSize = 13
btnNoclip.Font = Enum.Font.GothamBold
btnNoclip.BorderSizePixel = 0
btnNoclip.Parent = contentFrame
Instance.new("UICorner", btnNoclip).CornerRadius = UDim.new(0, 8)

btnNoclip.MouseButton1Click:Connect(function()
    noclipAtivo = not noclipAtivo
    aplicarNoclipAtivo(noclipAtivo)
    btnNoclip.Text = noclipAtivo and "NOCLIP: ON" or "NOCLIP: OFF"
    btnNoclip.BackgroundColor3 = noclipAtivo and Color3.fromRGB(0, 120, 70) or Color3.fromRGB(45, 45, 55)
    btnNoclip.TextColor3 = noclipAtivo and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 200)
end)

-- Rótulo de Status
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0.85, 0, 0, 22)
statusLabel.Position = UDim2.new(0.075, 0, 0, 240)
statusLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
statusLabel.BorderSizePixel = 0
statusLabel.Text = "AGUARDANDO..."
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.GothamBold
statusLabel.Parent = contentFrame
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 6)
_G._statusLabel = statusLabel

-- Instruções
local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(0.85, 0, 0, 56)
infoLabel.Position = UDim2.new(0.075, 0, 0, 270)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Teclas: [T] Teleporte | [N] Noclip | [RightShift] Mostrar/Esconder GUI\n1. Ative o Modo Seguro. 2. Vá até o item. 3. Aperte [T]."
infoLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
infoLabel.TextSize = 10
infoLabel.Font = Enum.Font.Gotham
infoLabel.TextWrapped = true
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.TextYAlignment = Enum.TextYAlignment.Top
infoLabel.Parent = contentFrame

-- ==================== KEYBINDS ====================
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.RightShift then
        mainFrame.Visible = not mainFrame.Visible
    elseif input.KeyCode == Enum.KeyCode.T then
        executarTeleporte()
    elseif input.KeyCode == Enum.KeyCode.N then
        noclipAtivo = not noclipAtivo
        aplicarNoclipAtivo(noclipAtivo)
        btnNoclip.Text = noclipAtivo and "NOCLIP: ON" or "NOCLIP: OFF"
        btnNoclip.BackgroundColor3 = noclipAtivo and Color3.fromRGB(0, 120, 70) or Color3.fromRGB(45, 45, 55)
    end
end)

-- ==================== INICIALIZAÇÃO ====================
print("[v14] Carregado. Use [RightShift] para a GUI. Modo Seguro é o mais estável.")
setStatus("PRONTO - Ative o Modo Seguro", Color3.fromRGB(180, 180, 200))
