--[[
  NAMELESS LITE — Delta / cloud phone (low RAM)
  Chat: nameless:!cmd   or  !cmd for transfer/slot/load
  Keybinds editable below. No heavy GUI / world scans.
]]
getgenv().NAMELESS_BOOT = true
if getgenv()._NL_LITE_CLEAN then pcall(getgenv()._NL_LITE_CLEAN) end

local ControllerName = nil
local MySlot = 1
local PREFIX = "nameless:!"

-- keybinds (edit here)
local Keybinds = {
    Stop = Enum.KeyCode.X,
    Kill = Enum.KeyCode.V,
    Autokill = Enum.KeyCode.B,
}

-- movement / kill
local FollowBack, FollowHeight, FollowSpacing, HeightPerRow = 3, 1.2, 2.5, 1
local BehindDist, FrontDist, HitHold, MoveSpeed = 10000, 10000, 0.03, 100000
local UseGun, StompOnKill = true, true
local StompBotSlot = 1

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local VU = game:GetService("VirtualUser")
local StarterGui = game:GetService("StarterGui")
local LP = Players.LocalPlayer
local MainEvent = RS:FindFirstChild("MainEvent")
task.spawn(function()
    if not MainEvent then MainEvent = RS:WaitForChild("MainEvent", 8) end
end)

local ExtraOwners = {}
local CurrentAction = "idle"
local TargetPlayer = nil
local GlueMode, GlueTarget = "follow", nil
local glueConn, killConn, camConn = nil, nil, nil
local KillPhase, StompDone = "attack", false
local PendingAuto, SavedTargets = nil, nil
local Phase, HitUntil, LastStep = "behind", 0, 0
local StableLook = Vector3.new(0, 0, -1)
local FlyTrack, HoverTrack = nil, nil
local FLY_ID = "rbxassetid://3541044388"
local HOVER_ID = "rbxassetid://973771746"

local function root()
    local c = LP.Character
    if not c then return nil end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return nil end
    return h.RootPart or c:FindFirstChild("HumanoidRootPart")
end

local function setPhys(selfRoot, targetPart)
    if not sethiddenproperty or not selfRoot then return end
    pcall(function()
        sethiddenproperty(selfRoot, "PhysicsRepRootPart", targetPart or selfRoot)
    end)
end

local function findPlayer(name)
    if not name then return nil end
    name = name:lower()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local n, d = p.Name:lower(), (p.DisplayName or ""):lower()
            if n:find(name, 1, true) or d:find(name, 1, true) then return p end
        end
    end
end

local function findAny(name)
    if not name then return nil end
    name = name:lower()
    for _, p in ipairs(Players:GetPlayers()) do
        local n, d = p.Name:lower(), (p.DisplayName or ""):lower()
        if n:find(name, 1, true) or d:find(name, 1, true) then return p end
    end
end

local function getController()
    if not ControllerName then return nil end
    local c = Players:FindFirstChild(ControllerName)
    if c then return c end
    local w = ControllerName:lower()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == w or (p.DisplayName and p.DisplayName:lower() == w) then return p end
    end
end

local function isOwner(p)
    if not p then return false end
    if not ControllerName then return true end
    local w = ControllerName:lower()
    if p.Name:lower() == w or (p.DisplayName and p.DisplayName:lower() == w) then return true end
    for i = 1, #ExtraOwners do
        if p.Name:lower() == ExtraOwners[i]:lower() then return true end
    end
    return false
end

local function selfCtrl()
    if not ControllerName then return false end
    local w = ControllerName:lower()
    return LP.Name:lower() == w or (LP.DisplayName and LP.DisplayName:lower() == w)
end

local function knocked(char)
    if not char then return false end
    local be = char:FindFirstChild("BodyEffects")
    if be then
        local ko = be:FindFirstChild("K.O")
        if ko and ko.Value then return true end
    end
    local h = char:FindFirstChildOfClass("Humanoid")
    return h and h.Health <= 0
end

local function alive(p)
    if not p or not p.Character then return false end
    if knocked(p.Character) then return false end
    local h = p.Character:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    local ff = p.Character:FindFirstChildOfClass("ForceField")
    return not ff
end

local function inGame(p)
    return p and p.Parent == Players and p.Character
end

-- fly anims (light)
local function stopFly()
    if FlyTrack then pcall(function() FlyTrack:Stop(0.1) end) FlyTrack = nil end
    if HoverTrack then pcall(function() HoverTrack:Stop(0.1) end) HoverTrack = nil end
end

local function loadFly()
    stopFly()
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local an = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    pcall(function()
        local a1 = Instance.new("Animation"); a1.AnimationId = FLY_ID
        local a2 = Instance.new("Animation"); a2.AnimationId = HOVER_ID
        FlyTrack = an:LoadAnimation(a1)
        HoverTrack = an:LoadAnimation(a2)
        FlyTrack.Looped, HoverTrack.Looped = true, true
        FlyTrack.Priority = Enum.AnimationPriority.Action
        HoverTrack.Priority = Enum.AnimationPriority.Action
    end)
end

local function updateFly()
    if CurrentAction ~= "follow" then stopFly() return end
    if not FlyTrack or not HoverTrack then loadFly() end
    if not FlyTrack then return end
    local ctrl = getController()
    local moving = false
    if ctrl and ctrl.Character then
        local h = ctrl.Character:FindFirstChildOfClass("Humanoid")
        local r = ctrl.Character:FindFirstChild("HumanoidRootPart")
        if h and h.MoveDirection.Magnitude > 0.08 then moving = true end
        if r and r.AssemblyLinearVelocity.Magnitude > 2 then moving = true end
    end
    if moving then
        if HoverTrack and HoverTrack.IsPlaying then HoverTrack:Stop(0.15) end
        if FlyTrack and not FlyTrack.IsPlaying then FlyTrack:Play(0.15, 1, 1) end
    else
        if FlyTrack and FlyTrack.IsPlaying then FlyTrack:Stop(0.15) end
        if HoverTrack and not HoverTrack.IsPlaying then HoverTrack:Play(0.15, 1, 1) end
    end
end

local function summonCF()
    local o = getController()
    if not o or not o.Character then return nil end
    local oroot = o.Character:FindFirstChild("HumanoidRootPart")
    if not oroot then return nil end
    local slot = ((MySlot or 1) - 1) % 20 + 1
    local col = ((slot - 1) % 4) - 1.5
    local row = math.floor((slot - 1) / 4)
    local cf = oroot.CFrame
    local pos = oroot.Position
        - cf.LookVector * (FollowBack + row * 0.6)
        + cf.RightVector * (col * FollowSpacing)
        + Vector3.new(0, FollowHeight + row * HeightPerRow, 0)
    return CFrame.new(pos, pos + cf.LookVector)
end

local function stopGlue()
    if glueConn then glueConn:Disconnect() glueConn = nil end
    getgenv().glue_active = false
    local r = root()
    if r then
        r.CanCollide = true
        setPhys(r, r)
        r.AssemblyLinearVelocity = Vector3.zero
    end
    GlueTarget = nil
end

local function startGlue(mode, target)
    stopGlue()
    GlueMode, GlueTarget = mode or "follow", target
    getgenv().glue_active = true
    glueConn = RunService.Heartbeat:Connect(function()
        if not getgenv().glue_active then return end
        local selfR = root()
        if not selfR then return end
        local dest
        if GlueMode == "follow" then
            dest = summonCF()
            local c = getController()
            local tr = c and c.Character and c.Character:FindFirstChild("HumanoidRootPart")
            if tr then setPhys(selfR, tr) selfR.CanCollide = false end
        elseif GlueMode == "custom" and CustomGlueCF then
            dest = CustomGlueCF
        end
        if dest then
            selfR.AssemblyLinearVelocity = Vector3.zero
            selfR.AssemblyAngularVelocity = Vector3.zero
            selfR.CFrame = dest
        end
    end)
end

local CustomGlueCF = nil

local function stopCam()
    if camConn then camConn:Disconnect() camConn = nil end
    local cam = workspace.CurrentCamera
    if cam then cam.CameraType = Enum.CameraType.Custom end
    local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if h and cam then cam.CameraSubject = h end
end

local function startCam(target)
    stopCam()
    camConn = RunService.RenderStepped:Connect(function()
        if CurrentAction ~= "kill" and CurrentAction ~= "autokill" then return end
        if KillPhase ~= "attack" then return end
        local t = target or TargetPlayer
        if not t or not t.Character then return end
        local part = t.Character:FindFirstChild("Head") or t.Character:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        local r = root()
        if not part or not cam or not r then return end
        cam.CameraType = Enum.CameraType.Custom
        cam.CameraSubject = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        -- soft aim: look toward target without full scriptable cam
        pcall(function()
            if mousemoverel then
                local sp, on = cam:WorldToViewportPoint(part.Position)
                if on or sp.Z > 0 then
                    local vp = cam.ViewportSize
                    local dx = math.clamp(sp.X - vp.X * 0.5, -80, 80)
                    local dy = math.clamp(sp.Y - vp.Y * 0.5, -80, 80)
                    if math.abs(dx) > 1 or math.abs(dy) > 1 then mousemoverel(dx, dy) end
                end
            end
        end)
    end)
end

local function equip()
    local char = LP.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local bag = LP:FindFirstChild("Backpack")
    local function pick(from)
        if not from then return nil end
        for _, t in ipairs(from:GetChildren()) do
            if t:IsA("Tool") then
                local n = t.Name:lower()
                if UseGun then
                    if not n:find("knife") then return t end
                else
                    if n:find("knife") then return t end
                end
            end
        end
        for _, t in ipairs(from:GetChildren()) do
            if t:IsA("Tool") then return t end
        end
    end
    local held = char:FindFirstChildOfClass("Tool")
    if held then
        local n = held.Name:lower()
        if UseGun and not n:find("knife") then return held end
        if not UseGun and n:find("knife") then return held end
    end
    local tool = pick(bag) or pick(char)
    if tool and hum then pcall(function() hum:EquipTool(tool) end) end
    return char:FindFirstChildOfClass("Tool") or tool
end

local function hit(target)
    local tool = equip()
    if not tool then return end
    pcall(function() tool:Activate() end)
    if UseGun and MainEvent and target and target.Character then
        local part = target.Character:FindFirstChild("Head") or target.Character:FindFirstChild("HumanoidRootPart")
        if part then
            pcall(function()
                MainEvent:FireServer("Shoot", part.Position, part)
            end)
        end
    end
end

local function lookStable(tRoot)
    local hum = tRoot.Parent and tRoot.Parent:FindFirstChildOfClass("Humanoid")
    local md = hum and hum.MoveDirection or Vector3.zero
    local horiz
    if md.Magnitude > 0.15 then
        horiz = Vector3.new(md.X, 0, md.Z)
    else
        local lv = tRoot.CFrame.LookVector
        horiz = Vector3.new(lv.X, 0, lv.Z)
    end
    if horiz.Magnitude > 0.05 then StableLook = horiz.Unit end
    return StableLook
end

local function killStep(target)
    local tChar = target and target.Character
    if not tChar then return true end
    local tRoot = tChar:FindFirstChild("HumanoidRootPart") or tChar:FindFirstChild("UpperTorso")
    local r = root()
    if not tRoot or not r then return false end
    if knocked(tChar) then Phase = "behind" return true end

    local now = tick()
    local dt = LastStep > 0 and math.clamp(now - LastStep, 0, 0.05) or 0.016
    LastStep = now

    local look = lookStable(tRoot)
    local mid = tRoot.Position + Vector3.new(0, 1.2, 0)
    local behind = mid - look * BehindDist
    local front = mid + look * FrontDist

    stopGlue()
    setPhys(r, tRoot)
    r.CanCollide = false
    r.AssemblyLinearVelocity = Vector3.zero

    local function stepTo(goal)
        local dir = goal - r.Position
        local dist = dir.Magnitude
        if dist < 1.5 then
            r.CFrame = CFrame.lookAt(goal, mid)
            return true
        end
        local step = math.min(MoveSpeed * math.max(dt, 1/60), dist)
        r.CFrame = CFrame.lookAt(r.Position + dir.Unit * step, mid)
        return (dist - step) < 2
    end

    if Phase == "behind" then
        if stepTo(behind) or (r.Position - behind).Magnitude < 3 then
            r.CFrame = CFrame.lookAt(behind, mid)
            Phase = "hit"
            HitUntil = now + HitHold
            hit(target)
        end
    elseif Phase == "hit" then
        r.CFrame = CFrame.lookAt(behind, mid)
        hit(target)
        if now >= HitUntil then Phase = "front" end
    else
        if stepTo(front) or (r.Position - front).Magnitude < 4 then
            Phase = "behind"
        end
    end
    return false
end

local function stopKill()
    if killConn then killConn:Disconnect() killConn = nil end
end

local function stopAll()
    CurrentAction = "idle"
    TargetPlayer = nil
    KillPhase, StompDone = "attack", false
    Phase, HitUntil = "behind", 0
    stopKill()
    stopGlue()
    stopCam()
    stopFly()
end

local function doStomp(target)
    if (MySlot or 1) ~= StompBotSlot or not StompOnKill then return end
    local tc = target and target.Character
    if not tc then return end
    local ut = tc:FindFirstChild("UpperTorso") or tc:FindFirstChild("HumanoidRootPart")
    local r = root()
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if not ut or not r or not hum then return end
    stopGlue()
    stopCam()
    pcall(function() hum:UnequipTools() end)
    local t0 = tick()
    while tick() - t0 < 0.45 and ut.Parent and r.Parent do
        local goal = ut.Position + Vector3.new(0, 0.4, 0)
        local dir = goal - r.Position
        if dir.Magnitude < 1.2 then
            r.CFrame = CFrame.new(goal)
            break
        end
        r.CFrame = CFrame.new(r.Position + dir.Unit * math.min(dir.Magnitude, 8))
        r.AssemblyLinearVelocity = Vector3.zero
        RunService.Heartbeat:Wait()
    end
    for _ = 1, 5 do
        if MainEvent then pcall(function() MainEvent:FireServer("Stomp") end) end
    end
end

local StartFollow, StartKill

StartFollow = function()
    local ctrl = getController()
    if not ctrl then
        task.spawn(function()
            for _ = 1, 25 do
                ctrl = getController()
                if ctrl then break end
                task.wait(0.12)
            end
            if ctrl then StartFollow() end
        end)
        return
    end
    local pa, st = PendingAuto, SavedTargets
    stopAll()
    PendingAuto, SavedTargets = pa, st
    CurrentAction = "follow"
    startGlue("follow", ctrl)
    task.defer(function()
        loadFly()
        updateFly()
        if CurrentAction == "follow" and not getgenv().glue_active then
            startGlue("follow", getController() or ctrl)
        end
    end)
end

StartKill = function(targets, isAuto)
    if typeof(targets) ~= "table" then targets = { targets } end
    if #targets == 0 then return end
    stopAll()
    TargetPlayer = targets[1]
    CurrentAction = isAuto and "autokill" or "kill"
    KillPhase, StompDone = "attack", false
    Phase, HitUntil, LastStep = "behind", 0, 0
    if isAuto then PendingAuto, SavedTargets = true, targets else PendingAuto, SavedTargets = nil, nil end
    startCam(TargetPlayer)
    stopKill()
    killConn = RunService.Heartbeat:Connect(function()
        if CurrentAction ~= "kill" and CurrentAction ~= "autokill" then return end
        if KillPhase ~= "attack" then return end
        local t = TargetPlayer
        if not t or not inGame(t) then return end
        if not t.Character or knocked(t.Character) then return end
        killStep(t)
    end)
    task.spawn(function()
        while CurrentAction == "kill" or CurrentAction == "autokill" do
            local t = TargetPlayer
            if not inGame(t) then
                PendingAuto, SavedTargets = nil, nil
                if not selfCtrl() then StartFollow() else stopAll() end
                break
            end
            local myH = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if not myH or myH.Health <= 0 then stopKill() break end
            local tc = t.Character
            local ko = tc and knocked(tc)
            if KillPhase == "attack" then
                if not tc or ko then
                    pcall(function()
                        local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                        if h then h:UnequipTools() end
                    end)
                    stopKill()
                    stopCam()
                    KillPhase = "stomp"
                    StompDone = false
                end
            elseif KillPhase == "stomp" then
                if not StompDone then doStomp(t) StompDone = true end
                if selfCtrl() then
                    if isAuto then KillPhase = "waitff"
                    else PendingAuto, SavedTargets = nil, nil stopAll() break end
                else
                    KillPhase = "summon"
                end
            elseif KillPhase == "summon" then
                stopKill()
                stopCam()
                StartFollow()
                CurrentAction = isAuto and "autokill" or "kill"
                task.wait(0.4)
                if not isAuto then
                    PendingAuto, SavedTargets = nil, nil
                    CurrentAction = "follow"
                    break
                end
                KillPhase = "waitff"
            elseif KillPhase == "waitff" then
                if not inGame(t) then
                    PendingAuto, SavedTargets = nil, nil
                    if not selfCtrl() then StartFollow() else stopAll() end
                    break
                end
                if alive(t) then
                    StompDone = false
                    KillPhase = "attack"
                    Phase, HitUntil, LastStep = "behind", 0, 0
                    startCam(t)
                    CurrentAction = "autokill"
                    stopKill()
                    killConn = RunService.Heartbeat:Connect(function()
                        if CurrentAction ~= "autokill" or KillPhase ~= "attack" then return end
                        local tt = TargetPlayer
                        if not tt or not inGame(tt) or not tt.Character or knocked(tt.Character) then return end
                        killStep(tt)
                    end)
                else
                    if not selfCtrl() and getController() then
                        if GlueMode ~= "follow" then startGlue("follow", getController()) end
                    end
                    task.wait(0.2)
                end
            end
            task.wait(KillPhase == "attack" and 0.05 or 0.08)
        end
        stopKill()
        stopCam()
    end)
end

-- light anti-stomp: force reset on KO
local function forceReset()
    stopAll()
    local c = LP.Character
    if not c then return end
    if replicatesignal then pcall(replicatesignal, LP.Kill) return end
    local h = c:FindFirstChildOfClass("Humanoid")
    if h then pcall(function() h.Health = 0 end) end
end

local function hookKO(char)
    task.spawn(function()
        local be = char:WaitForChild("BodyEffects", 5)
        if not be then return end
        local ko = be:WaitForChild("K.O", 5)
        if not ko then return end
        local function check()
            if ko.Value then
                task.delay(0.15, function()
                    if ko.Value then forceReset() end
                end)
            end
        end
        ko:GetPropertyChangedSignal("Value"):Connect(check)
        check()
    end)
end

if LP.Character then hookKO(LP.Character) end
LP.CharacterAdded:Connect(function(char)
    stopFly()
    hookKO(char)
    if PendingAuto and SavedTargets then
        task.delay(0.6, function()
            if PendingAuto and SavedTargets then StartKill(SavedTargets, true) end
        end)
    elseif CurrentAction == "follow" then
        task.delay(0.4, StartFollow)
    end
end)

-- fly update only while following (cheap)
RunService.Heartbeat:Connect(function()
    if CurrentAction == "follow" then updateFly() end
end)

-- anti afk light
LP.Idled:Connect(function()
    pcall(function() VU:CaptureController() VU:ClickButton2(Vector2.zero) end)
end)

local function closest()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local mouse = UIS:GetMouseLocation()
    local best, bd = nil, 1e9
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local h = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("HumanoidRootPart")
            if h then
                local sp, on = cam:WorldToViewportPoint(h.Position)
                local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                if on and d < bd then bd, best = d, p end
            end
        end
    end
    return best or TargetPlayer
end

UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    local k = input.KeyCode
    if k == Keybinds.Stop then
        PendingAuto, SavedTargets = nil, nil
        stopAll()
    elseif k == Keybinds.Kill then
        local t = closest()
        if t then StartKill({ t }, false) end
    elseif k == Keybinds.Autokill then
        local t = closest()
        if t then StartKill({ t }, true) end
    end
end)

local function parsePrefix(msg)
    local lower = msg:lower()
    if lower:sub(1, 10) == "nameless:!" then return msg:sub(11):match("^%s*(.-)%s*$") end
    if lower:sub(1, 9) == "nameless:" then
        local b = msg:sub(10)
        if b:sub(1, 1) == "!" then b = b:sub(2) end
        return b:match("^%s*(.-)%s*$")
    end
    if lower:sub(1, 1) == "!" then return msg:sub(2):match("^%s*(.-)%s*$") end
    return nil
end

local function onChat(player, message)
    message = (message or ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    local body = parsePrefix(message)
    if not body then return end
    local args = {}
    for w in body:gmatch("%S+") do args[#args + 1] = w:lower() end
    local cmd = args[1]
    if not cmd then return end

    if cmd == "slot" and args[2] then
        local n = tonumber(args[2])
        if n and n >= 1 and n <= 20 and (isOwner(player) or player == LP) then
            MySlot = math.floor(n)
        end
        return
    end
    if cmd == "transfer" and args[2] then
        if not (isOwner(player) or player == LP or not ControllerName) then return end
        if args[2] == "me" or args[2] == "self" then
            ControllerName = player.Name
            ExtraOwners = {}
            return
        end
        local t = findAny(args[2])
        ControllerName = t and t.Name or args[2]
        return
    end
    if not isOwner(player) and player ~= LP then return end
    if not ControllerName then ControllerName = player.Name end

    if cmd == "stop" or cmd == "idle" then
        PendingAuto, SavedTargets = nil, nil
        stopAll()
    elseif cmd == "summon" or cmd == "follow" or cmd == "come" then
        PendingAuto, SavedTargets = nil, nil
        StartFollow()
    elseif cmd == "gun" then
        UseGun = true
    elseif cmd == "knife" and not args[2] then
        UseGun = false
    elseif cmd == "kill" or cmd == "kc" or (cmd == "knife" and args[2]) then
        local t = args[2] and findPlayer(args[2])
        if t then StartKill({ t }, false) end
    elseif cmd == "autokill" or cmd == "ak" then
        local t = args[2] and findPlayer(args[2])
        if t then StartKill({ t }, true) end
    elseif cmd == "stomp" then
        if args[2] == "on" then StompOnKill = true
        elseif args[2] == "off" then StompOnKill = false
        else StompOnKill = not StompOnKill end
    elseif cmd == "reset" or cmd == "r" then
        forceReset()
    elseif cmd == "addowner" and args[2] then
        ExtraOwners[#ExtraOwners + 1] = args[2]
    elseif cmd == "removeowner" and args[2] then
        for i = #ExtraOwners, 1, -1 do
            if ExtraOwners[i]:lower() == args[2] then table.remove(ExtraOwners, i) end
        end
    elseif cmd == "unloads" and player == LP then
        pcall(getgenv()._NL_LITE_CLEAN)
    elseif cmd == "help" or cmd == "cmds" then
        if player == LP then
            print("[NAMELESS LITE] summon stop gun knife kill/autokill NAME stomp on/off slot N transfer me|NAME reset")
            print("Keys: X stop | V kill | B autokill")
        end
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    p.Chatted:Connect(function(m) onChat(p, m) end)
end
Players.PlayerAdded:Connect(function(p)
    p.Chatted:Connect(function(m) onChat(p, m) end)
end)

getgenv()._NL_LITE_CLEAN = function()
    stopAll()
    getgenv().NAMELESS_BOOT = false
    getgenv()._NL_LITE_CLEAN = nil
end

task.defer(function()
    local msg = "NAMELESS LITE ready | nameless:!summon | keys X/V/B | !help"
    warn("[NAMELESS LITE] " .. msg)
    pcall(function()
        StarterGui:SetCore("ChatMakeSystemMessage", {
            Text = msg,
            Color = Color3.fromRGB(160, 210, 255),
            Font = Enum.Font.SourceSans,
            TextSize = 15,
        })
    end)
end)
