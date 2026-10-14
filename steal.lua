-- language: Lua, executor: Xeno
-- *v13.0: retorna ao padrão de fatia que funciona no drop (150 studs) sem o cap de fatias
--  que quebrava em mapa grande, e adiciona um "sync-hold" de 1.5s depois do TP para o
--  servidor assimilar a posição antes de qualquer Drop.*

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local ghostAtivo = false
local noclipAtivo = false
local godmodeAtivo = true
local walkSpeedDesejado = nil
local baseWalkSpeed = 16
local anchorPos = nil
local anchorCFrame = nil
local autoReturn = true
local janelaGrab = 0
local returnEmCurso = false
local Y_MIN = (workspace.FallenPartsDestroyHeight or -100) + 30

-- parâmetros ajustáveis
local SLICE_SIZE = 150                -- tamanho da fatia em studs
local SYNC_HOLD = 1.5                 -- segundos de sync após o TP antes de liberar
local SYNC_REASSERT_INTERVAL = 0.1    -- reafirma posição a cada X s durante o hold

local function getChar() return LocalPlayer.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
-- HOOKS
-- ============================================================
pcall(function()
    if type(hookmetamethod) ~= "function" then error("sem hookmetamethod") end
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", function(self, key)
        if noclipAtivo and key == "CanCollide" and typeof(self) == "Instance" and self:IsA("BasePart") then
            local c = getChar()
            if c and self:IsDescendantOf(c) then return false end
        end
        return oldIndex(self, key)
    end)
end)

pcall(function()
    if type(hookmetamethod) ~= "function" then error("sem hookmetamethod") end
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local m = getnamecallmethod()
        if godmodeAtivo then
            if m == "TakeDamage" and typeof(self) == "Instance" and self:IsA("Humanoid") then
                local c = getChar()
                if c and self:IsDescendantOf(c) then return nil end
            elseif m == "Kick" and self == LocalPlayer then
                return nil
            elseif m == "BreakJoints" and typeof(self) == "Instance" and self:IsA("BasePart") then
                local c = getChar()
                if c and self:IsDescendantOf(c) then return nil end
            end
        end
        return oldNamecall(self, ...)
    end)
end)

RunService.Heartbeat:Connect(function()
    if not godmodeAtivo then return end
    local hum = getHum()
    if hum and hum.Health < hum.MaxHealth then
        pcall(function() hum.Health = hum.MaxHealth end)
    end
end)

RunService.Stepped:Connect(function()
    local c = getChar()
    if not c then return end
    if noclipAtivo then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                pcall(function() p.CanCollide = false end)
            end
        end
    end
    if godmodeAtivo then
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if hrp and hrp.Position.Y < Y_MIN and anchorPos then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(anchorPos + Vector3.new(0, 3, 0))
        end
    end
end)

-- ============================================================
-- GHOST
-- ============================================================
local function setFFlag(nome, valor)
    pcall(function() setfflag(nome, tostring(valor)) end)
end

local function ligarGhost()
    local hrp = getHRP()
    if not hrp then return false end
    anchorPos = hrp.Position
    anchorCFrame = hrp.CFrame
    setFFlag("DFIntS2PhysicsSenderRate", -30)
    ghostAtivo = true
    return true
end

local function desligarGhost()
    setFFlag("DFIntS2PhysicsSenderRate", 1)
    ghostAtivo = false
end

-- ============================================================
-- HELPERS
-- ============================================================
local function zerarFisica(hrp)
    if not hrp then return end
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function matarRagdoll(hum)
    if not hum then return end
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
    end)
    pcall(function() hum.PlatformStand = false end)
    pcall(function() hum.Sit = false end)
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
end

-- ============================================================
-- RETURN v13 — fatia grande sem cap + sync-hold
-- ============================================================
local function setStatus(texto, cor)
    if _G._statusLabel then
        _G._statusLabel.Text = texto
        _G._statusLabel.TextColor3 = cor
    end
end

local function voltarAoAnchor()
    if returnEmCurso then return end
    if not anchorPos then return end
    returnEmCurso = true

    setStatus("TP em curso...", Color3.fromRGB(255, 200, 100))

    task.spawn(function()
        local t0 = tick()

        -- 1) ghost off
        if ghostAtivo then
            desligarGhost()
            task.wait(0.1)
        end

        -- 2) zera física
        local hrp = getHRP()
        zerarFisica(hrp)
        task.wait()

        -- 3) TP em fatias (SEM CAP)
        hrp = getHRP()
        if hrp then
            local dist = (hrp.Position - anchorPos).Magnitude
            if dist > 4 then
                local passos = math.max(1, math.ceil(dist / SLICE_SIZE))
                local inicio = hrp.Position
                local delta = anchorPos - inicio
                local tamanhoReal = dist / passos
                for i = 1, passos do
                    local h = getHRP()
                    if not h then break end
                    zerarFisica(h)
                    h.CFrame = CFrame.new(inicio + delta * (i / passos))
                    zerarFisica(h)
                    task.wait()
                end
                print(string.format("[v13] TP: dist=%.0f passos=%d tamanho=%.0f t=%.2fs",
                    dist, passos, tamanhoReal, tick() - t0))
            end
        end

        -- 4) chegada exata
        hrp = getHRP()
        if hrp and anchorCFrame then
            zerarFisica(hrp)
            hrp.CFrame = anchorCFrame
            zerarFisica(hrp)
        end

        -- 5) anti-ragdoll
        matarRagdoll(getHum())

        -- 6) sync-hold: reafirma posição enquanto servidor assimila
        setStatus("Sincronizando...", Color3.fromRGB(255, 200, 100))
        local tHold = tick()
        while tick() - tHold < SYNC_HOLD do
            local h = getHRP()
            if h and anchorCFrame then
                zerarFisica(h)
                h.CFrame = anchorCFrame
                zerarFisica(h)
            end
            task.wait(SYNC_REASSERT_INTERVAL)
        end

        -- 7) libera
        setStatus("PRONTO PARA DROP", Color3.fromRGB(0, 220, 120))
        if _G._ghostBtn then
            _G._ghostBtn.Text = "Ghost Mode: OFF"
            _G._ghostBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        end

        returnEmCurso = false
    end)
end

-- ============================================================
-- SPEED
-- ============================================================
local function aplicarSpeed()
    local hum = getHum()
    if hum and walkSpeedDesejado then hum.WalkSpeed = walkSpeedDesejado end
end

local function detectarBaseSpeed()
    local hum = getHum()
    if hum and hum.WalkSpeed > 0 then baseWalkSpeed = hum.WalkSpeed end
    if not walkSpeedDesejado then walkSpeedDesejado = baseWalkSpeed end
end

-- ============================================================
-- AUTO-RETURN
-- ============================================================
local function hookContainer(container)
    container.ChildAdded:Connect(function(child)
        if not autoReturn or not anchorPos then return end
        if not child:IsA("Tool") then return end
        if returnEmCurso then return end
        local agora = tick()
        if agora - janelaGrab < 0.5 then return end
        janelaGrab = agora
        task.wait(0.1)
        voltarAoAnchor()
    end)
end

local function onCharacterAdded(c)
    task.wait(0.4)
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum then
        if walkSpeedDesejado then hum.WalkSpeed = walkSpeedDesejado end
        matarRagdoll(hum)
    end
    hookContainer(c)
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then hookContainer(bp) end
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then task.spawn(onCharacterAdded, LocalPlayer.Character) end
local bpAtual = LocalPlayer:FindFirstChild("Backpack")
if bpAtual then hookContainer(bpAtual) end
LocalPlayer.ChildAdded:Connect(function(c)
    if c.Name == "Backpack" then hookContainer(c) end
end)

-- ============================================================
-- MONITOR
-- ============================================================
task.spawn(function()
    while task.wait(4) do
        local hrp = getHRP()
        local hum = getHum()
        if hrp and hum then
            local dist = anchorPos and (hrp.Position - anchorPos).Magnitude or 0
            print(string.format(
                "[v13][4s] ghost=%s noclip=%s ws=%.0f dist=%.0f slice=%d hold=%.1fs",
                tostring(ghostAtivo), tostring(noclipAtivo),
                hum.WalkSpeed, dist, SLICE_SIZE, SYNC_HOLD
            ))
        end
    end
end)

-- ============================================================
-- GUI
-- ============================================================
local pg = LocalPlayer:WaitForChild("PlayerGui", 10)
local sg = Instance.new("ScreenGui")
sg.Name = "XenoAllInOne_v13"
sg.ResetOnSpawn = false
sg.IgnoreGuiInset = true
sg.DisplayOrder = 500
sg.Parent = pg

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 320, 0, 640)
main.Position = UDim2.new(0, 20, 0, 20)
main.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, 0, 0, 32)
titulo.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
titulo.BorderSizePixel = 0
titulo.Text = "Ghost + Noclip + God v13"
titulo.TextColor3 = Color3.fromRGB(255, 255, 255)
titulo.TextSize = 15
titulo.Font = Enum.Font.GothamBold
titulo.Parent = main
Instance.new("UICorner", titulo).CornerRadius = UDim.new(0, 8)

local function criarBotao(texto, y, cor, corTexto)
    local b = Instance.new("TextButton", main)
    b.Size = UDim2.new(0.85, 0, 0, 28)
    b.Position = UDim2.new(0.075, 0, 0, y)
    b.BackgroundColor3 = cor
    b.Text = texto
    b.TextColor3 = corTexto
    b.TextSize = 12
    b.Font = Enum.Font.Gotham
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local ghostBtn = criarBotao("Ghost Mode: OFF", 40, Color3.fromRGB(45, 45, 55), Color3.fromRGB(200, 200, 200))
_G._ghostBtn = ghostBtn
ghostBtn.MouseButton1Click:Connect(function()
    if returnEmCurso then return end
    if not ghostAtivo then
        if ligarGhost() then
            ghostBtn.Text = "Ghost Mode: ON"
            ghostBtn.BackgroundColor3 = Color3.fromRGB(140, 0, 80)
            setStatus("Ghost ON - roube e aperte T", Color3.fromRGB(255, 200, 100))
        end
    else
        voltarAoAnchor()
    end
end)

local noclipBtn = criarBotao("Noclip: OFF", 72, Color3.fromRGB(45, 45, 55), Color3.fromRGB(200, 200, 200))
noclipBtn.MouseButton1Click:Connect(function()
    noclipAtivo = not noclipAtivo
    noclipBtn.Text = noclipAtivo and "Noclip: ON" or "Noclip: OFF"
    noclipBtn.BackgroundColor3 = noclipAtivo and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(45, 45, 55)
end)

local godBtn = criarBotao("Godmode: ON", 104, Color3.fromRGB(0, 140, 80), Color3.fromRGB(255, 255, 255))
godBtn.MouseButton1Click:Connect(function()
    godmodeAtivo = not godmodeAtivo
    godBtn.Text = godmodeAtivo and "Godmode: ON" or "Godmode: OFF"
    godBtn.BackgroundColor3 = godmodeAtivo and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(45, 45, 55)
end)

local salvarBtn = criarBotao("Definir Posicao (P)", 136, Color3.fromRGB(45, 55, 80), Color3.fromRGB(180, 210, 255))
local anchorLabel = Instance.new("TextLabel")
anchorLabel.Size = UDim2.new(0.85, 0, 0, 16)
anchorLabel.Position = UDim2.new(0.075, 0, 0, 168)
anchorLabel.BackgroundTransparency = 1
anchorLabel.Text = "Ancora: nenhuma"
anchorLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
anchorLabel.TextSize = 11
anchorLabel.Font = Enum.Font.Gotham
anchorLabel.TextXAlignment = Enum.TextXAlignment.Left
anchorLabel.Parent = main

local function salvarAnchor()
    local hrp = getHRP()
    if hrp then
        anchorPos = hrp.Position
        anchorCFrame = hrp.CFrame
        anchorLabel.Text = string.format("Ancora: %.0f, %.0f, %.0f",
            anchorPos.X, anchorPos.Y, anchorPos.Z)
        anchorLabel.TextColor3 = Color3.fromRGB(0, 200, 120)
        return true
    end
    return false
end

salvarBtn.MouseButton1Click:Connect(salvarAnchor)

local tpBtn = criarBotao("Forçar Volta ao Anchor (T)", 188, Color3.fromRGB(60, 40, 60), Color3.fromRGB(255, 200, 255))
tpBtn.MouseButton1Click:Connect(voltarAoAnchor)

local autoBtn = criarBotao("Auto-Return: ON", 220, Color3.fromRGB(0, 140, 80), Color3.fromRGB(255, 255, 255))
autoBtn.MouseButton1Click:Connect(function()
    autoReturn = not autoReturn
    autoBtn.Text = autoReturn and "Auto-Return: ON" or "Auto-Return: OFF"
    autoBtn.BackgroundColor3 = autoReturn and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(45, 45, 55)
end)

-- STATUS
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0.85, 0, 0, 24)
statusLabel.Position = UDim2.new(0.075, 0, 0, 254)
statusLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
statusLabel.BorderSizePixel = 0
statusLabel.Text = "AGUARDANDO"
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.GothamBold
statusLabel.Parent = main
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 6)
_G._statusLabel = statusLabel

-- SLICE
local sliceLabel = Instance.new("TextLabel")
sliceLabel.Size = UDim2.new(0.85, 0, 0, 16)
sliceLabel.Position = UDim2.new(0.075, 0, 0, 284)
sliceLabel.BackgroundTransparency = 1
sliceLabel.Text = "Slice: 150 studs"
sliceLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
sliceLabel.TextSize = 11
sliceLabel.Font = Enum.Font.Gotham
sliceLabel.TextXAlignment = Enum.TextXAlignment.Left
sliceLabel.Parent = main

local sliceTrack = Instance.new("Frame")
sliceTrack.Size = UDim2.new(0.85, 0, 0, 8)
sliceTrack.Position = UDim2.new(0.075, 0, 0, 306)
sliceTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
sliceTrack.BorderSizePixel = 0
sliceTrack.Parent = main
Instance.new("UICorner", sliceTrack).CornerRadius = UDim.new(0, 4)

local sliceFill = Instance.new("Frame")
sliceFill.Size = UDim2.new(0.36, 0, 1, 0)
sliceFill.BackgroundColor3 = Color3.fromRGB(180, 120, 0)
sliceFill.BorderSizePixel = 0
sliceFill.Parent = sliceTrack
Instance.new("UICorner", sliceFill).CornerRadius = UDim.new(0, 4)

local sliceHandle = Instance.new("TextButton")
sliceHandle.Size = UDim2.new(0, 16, 0, 16)
sliceHandle.Position = UDim2.new(0.36, -8, 0.5, -8)
sliceHandle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
sliceHandle.Text = ""
sliceHandle.BorderSizePixel = 0
sliceHandle.Parent = sliceTrack
Instance.new("UICorner", sliceHandle).CornerRadius = UDim.new(1, 0)

local arrastandoSlice = false
local SLICE_MIN, SLICE_MAX = 30, 400

local function setSliceFromX(x)
    local rel = math.clamp((x - sliceTrack.AbsolutePosition.X) / sliceTrack.AbsoluteSize.X, 0, 1)
    SLICE_SIZE = math.floor(SLICE_MIN + (SLICE_MAX - SLICE_MIN) * rel)
    sliceFill.Size = UDim2.new(rel, 0, 1, 0)
    sliceHandle.Position = UDim2.new(rel, -8, 0.5, -8)
    sliceLabel.Text = "Slice: " .. SLICE_SIZE .. " studs"
end

sliceHandle.MouseButton1Down:Connect(function() arrastandoSlice = true end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then arrastandoSlice = false end
end)
UserInputService.InputChanged:Connect(function(i)
    if arrastandoSlice and i.UserInputType == Enum.UserInputType.MouseMovement then
        setSliceFromX(i.Position.X)
    end
end)
sliceTrack.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        setSliceFromX(i.Position.X)
    end
end)

-- SYNC HOLD
local holdLabel = Instance.new("TextLabel")
holdLabel.Size = UDim2.new(0.85, 0, 0, 16)
holdLabel.Position = UDim2.new(0.075, 0, 0, 326)
holdLabel.BackgroundTransparency = 1
holdLabel.Text = "Sync-Hold: 1.5s"
holdLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
holdLabel.TextSize = 11
holdLabel.Font = Enum.Font.Gotham
holdLabel.TextXAlignment = Enum.TextXAlignment.Left
holdLabel.Parent = main

local holdTrack = Instance.new("Frame")
holdTrack.Size = UDim2.new(0.85, 0, 0, 8)
holdTrack.Position = UDim2.new(0.075, 0, 0, 348)
holdTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
holdTrack.BorderSizePixel = 0
holdTrack.Parent = main
Instance.new("UICorner", holdTrack).CornerRadius = UDim.new(0, 4)

local holdFill = Instance.new("Frame")
holdFill.Size = UDim2.new(0.5, 0, 1, 0)
holdFill.BackgroundColor3 = Color3.fromRGB(0, 100, 180)
holdFill.BorderSizePixel = 0
holdFill.Parent = holdTrack
Instance.new("UICorner", holdFill).CornerRadius = UDim.new(0, 4)

local holdHandle = Instance.new("TextButton")
holdHandle.Size = UDim2.new(0, 16, 0, 16)
holdHandle.Position = UDim2.new(0.5, -8, 0.5, -8)
holdHandle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
holdHandle.Text = ""
holdHandle.BorderSizePixel = 0
holdHandle.Parent = holdTrack
Instance.new("UICorner", holdHandle).CornerRadius = UDim.new(1, 0)

local arrastandoHold = false
local HOLD_MIN, HOLD_MAX = 0.5, 4.0

local function setHoldFromX(x)
    local rel = math.clamp((x - holdTrack.AbsolutePosition.X) / holdTrack.AbsoluteSize.X, 0, 1)
    SYNC_HOLD = HOLD_MIN + (HOLD_MAX - HOLD_MIN) * rel
    holdFill.Size = UDim2.new(rel, 0, 1, 0)
    holdHandle.Position = UDim2.new(rel, -8, 0.5, -8)
    holdLabel.Text = string.format("Sync-Hold: %.1fs", SYNC_HOLD)
end

holdHandle.MouseButton1Down:Connect(function() arrastandoHold = true end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then arrastandoHold = false end
end)
UserInputService.InputChanged:Connect(function(i)
    if arrastandoHold and i.UserInputType == Enum.UserInputType.MouseMovement then
        setHoldFromX(i.Position.X)
    end
end)
holdTrack.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        setHoldFromX(i.Position.X)
    end
end)

-- SPEED
local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0.85, 0, 0, 16)
speedLabel.Position = UDim2.new(0.075, 0, 0, 368)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "WalkSpeed: --"
speedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedLabel.TextSize = 11
speedLabel.Font = Enum.Font.Gotham
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = main

local speedInput = Instance.new("TextBox")
speedInput.Size = UDim2.new(0.35, 0, 0, 24)
speedInput.Position = UDim2.new(0.075, 0, 0, 386)
speedInput.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
speedInput.BorderSizePixel = 0
speedInput.Text = "0"
speedInput.TextColor3 = Color3.fromRGB(255, 255, 255)
speedInput.TextSize = 12
speedInput.Font = Enum.Font.Gotham
speedInput.ClearTextOnFocus = false
speedInput.Parent = main
Instance.new("UICorner", speedInput).CornerRadius = UDim.new(0, 6)

local baseBtn = Instance.new("TextButton")
baseBtn.Size = UDim2.new(0.22, 0, 0, 24)
baseBtn.Position = UDim2.new(0.44, 0, 0, 386)
baseBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 80)
baseBtn.BorderSizePixel = 0
baseBtn.Text = "Base"
baseBtn.TextColor3 = Color3.fromRGB(200, 220, 255)
baseBtn.TextSize = 12
baseBtn.Font = Enum.Font.Gotham
baseBtn.Parent = main
Instance.new("UICorner", baseBtn).CornerRadius = UDim.new(0, 6)

local maxBtn = Instance.new("TextButton")
maxBtn.Size = UDim2.new(0.22, 0, 0, 24)
maxBtn.Position = UDim2.new(0.69, 0, 0, 386)
maxBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 60)
maxBtn.BorderSizePixel = 0
maxBtn.Text = "Max"
maxBtn.TextColor3 = Color3.fromRGB(255, 200, 220)
maxBtn.TextSize = 12
maxBtn.Font = Enum.Font.Gotham
maxBtn.Parent = main
Instance.new("UICorner", maxBtn).CornerRadius = UDim.new(0, 6)

local speedTrack = Instance.new("Frame")
speedTrack.Size = UDim2.new(0.85, 0, 0, 8)
speedTrack.Position = UDim2.new(0.075, 0, 0, 420)
speedTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
speedTrack.BorderSizePixel = 0
speedTrack.Parent = main
Instance.new("UICorner", speedTrack).CornerRadius = UDim.new(0, 4)

local speedFill = Instance.new("Frame")
speedFill.Size = UDim2.new(0, 0, 1, 0)
speedFill.BackgroundColor3 = Color3.fromRGB(0, 140, 80)
speedFill.BorderSizePixel = 0
speedFill.Parent = speedTrack
Instance.new("UICorner", speedFill).CornerRadius = UDim.new(0, 4)

local speedHandle = Instance.new("TextButton")
speedHandle.Size = UDim2.new(0, 16, 0, 16)
speedHandle.Position = UDim2.new(0, -8, 0.5, -8)
speedHandle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
speedHandle.Text = ""
speedHandle.BorderSizePixel = 0
speedHandle.Parent = speedTrack
Instance.new("UICorner", speedHandle).CornerRadius = UDim.new(1, 0)

local MAX_SPEED = 500
local MIN_SPEED = 0
local arrastandoSpeed = false

local function atualizarMax() MAX_SPEED = math.max(500, baseWalkSpeed * 20) end

local function setSpeedFromX(x)
    local rel = math.clamp((x - speedTrack.AbsolutePosition.X) / speedTrack.AbsoluteSize.X, 0, 1)
    walkSpeedDesejado = math.floor(MIN_SPEED + (MAX_SPEED - MIN_SPEED) * rel)
    speedFill.Size = UDim2.new(rel, 0, 1, 0)
    speedHandle.Position = UDim2.new(rel, -8, 0.5, -8)
    speedInput.Text = tostring(walkSpeedDesejado)
    speedLabel.Text = "WalkSpeed: " .. walkSpeedDesejado
    aplicarSpeed()
end

local function setSliderFromValue(v)
    local rel = math.clamp((v - MIN_SPEED) / (MAX_SPEED - MIN_SPEED), 0, 1)
    speedFill.Size = UDim2.new(rel, 0, 1, 0)
    speedHandle.Position = UDim2.new(rel, -8, 0.5, -8)
    speedInput.Text = tostring(v)
    speedLabel.Text = "WalkSpeed: " .. v
    walkSpeedDesejado = v
    aplicarSpeed()
end

speedHandle.MouseButton1Down:Connect(function() arrastandoSpeed = true end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then arrastandoSpeed = false end
end)
UserInputService.InputChanged:Connect(function(i)
    if arrastandoSpeed and i.UserInputType == Enum.UserInputType.MouseMovement then
        setSpeedFromX(i.Position.X)
    end
end)
speedTrack.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        setSpeedFromX(i.Position.X)
    end
end)

speedInput.FocusLost:Connect(function()
    local n = tonumber(speedInput.Text)
    if n then setSliderFromValue(math.floor(n)) else speedInput.Text = tostring(walkSpeedDesejado or 0) end
end)

baseBtn.MouseButton1Click:Connect(function()
    detectarBaseSpeed()
    setSliderFromValue(baseWalkSpeed)
end)

maxBtn.MouseButton1Click:Connect(function() setSliderFromValue(MAX_SPEED) end)

UserInputService.InputBegan:Connect(function(i, p)
    if p then return end
    if i.KeyCode == Enum.KeyCode.P then
        salvarAnchor()
    elseif i.KeyCode == Enum.KeyCode.T then
        voltarAoAnchor()
    elseif i.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
    end
end)

task.spawn(function()
    task.wait(0.5)
    detectarBaseSpeed()
    atualizarMax()
    setSliderFromValue(baseWalkSpeed)
    print(string.format("[v13] WalkSpeed detectado: %.0f | slider max: %.0f", baseWalkSpeed, MAX_SPEED))
    print(string.format("[v13] slice: %d studs | sync-hold: %.1fs", SLICE_SIZE, SYNC_HOLD))
    setStatus("PRONTO - aperte P para anchor", Color3.fromRGB(0, 220, 120))
end)

print("[v13] carregado. fatia de 150 studs SEM cap + sync-hold de 1.5s.")
print("[v13] apos o T, o status fica verde 'PRONTO PARA DROP' - so entao aperte Drop.")
