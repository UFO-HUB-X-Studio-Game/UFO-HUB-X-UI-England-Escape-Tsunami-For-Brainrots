-- ==== UFO HUB X • One-shot Boot Guard (PER SESSION; no cooldown reopen) ====
-- วางบนสุดของไฟล์ก่อนโค้ดทั้งหมด
do
    local BOOT = getgenv().UFO_BOOT or { status = "idle" }  -- status: idle|running|done
    -- ถ้ากำลังบูต หรือเคยบูตเสร็จแล้ว → ไม่ให้รันอีก
    if BOOT.status == "running" or BOOT.status == "done" then
        return
    end
    BOOT.status = "running"
    getgenv().UFO_BOOT = BOOT
end
-- ===== UFO HUB X • Local Save (executor filesystem) — per map (PlaceId) =====
do
    local HttpService = game:GetService("HttpService")
    local MarketplaceService = game:GetService("MarketplaceService")

    local FS = {
        isfolder   = (typeof(isfolder)=="function") and isfolder   or function() return false end,
        makefolder = (typeof(makefolder)=="function") and makefolder or function() end,
        isfile     = (typeof(isfile)=="function") and isfile       or function() return false end,
        readfile   = (typeof(readfile)=="function") and readfile   or function() return nil end,
        writefile  = (typeof(writefile)=="function") and writefile or function() end,
    }

    local ROOT = "UFO HUB X"  -- โฟลเดอร์หลักในตัวรัน
    local function safeMakeRoot() pcall(function() if not FS.isfolder(ROOT) then FS.makefolder(ROOT) end end) end
    safeMakeRoot()

    local placeId  = tostring(game.PlaceId)
    local gameId   = tostring(game.GameId)
    local mapName  = "Unknown"
    pcall(function()
        local inf = MarketplaceService:GetProductInfo(game.PlaceId)
        if inf and inf.Name then mapName = inf.Name end
    end)

    local FILE = string.format("%s/%s.json", ROOT, placeId)
    local _cache = nil
    local _dirty = false
    local _debounce = false

    local function _load()
        if _cache then return _cache end
        local ok, txt = pcall(function()
            if FS.isfile(FILE) then return FS.readfile(FILE) end
            return nil
        end)
        local data = nil
        if ok and txt and #txt > 0 then
            local ok2, t = pcall(function() return HttpService:JSONDecode(txt) end)
            data = ok2 and t or nil
        end
        if not data or type(data)~="table" then
            data = { __meta = { placeId = placeId, gameId = gameId, mapName = mapName, savedAt = os.time() } }
        end
        _cache = data
        return _cache
    end

    local function _flushNow()
        if not _cache then return end
        _cache.__meta = _cache.__meta or {}
        _cache.__meta.placeId = placeId
        _cache.__meta.gameId  = gameId
        _cache.__meta.mapName = mapName
        _cache.__meta.savedAt = os.time()
        local ok, json = pcall(function() return HttpService:JSONEncode(_cache) end)
        if ok and json then
            pcall(function()
                safeMakeRoot()
                FS.writefile(FILE, json)
            end)
        end
        _dirty = false
    end

    local function _scheduleFlush()
        if _debounce then return end
        _debounce = true
        task.delay(0.25, function()
            _debounce = false
            if _dirty then _flushNow() end
        end)
    end

    local Save = {}

    -- อ่านค่า: key = "Tab.Key" เช่น "RJ.enabled" / "A1.Reduce" / "AFK.Black"
    function Save.get(key, defaultValue)
        local db = _load()
        local v = db[key]
        if v == nil then return defaultValue end
        return v
    end

    -- เซ็ตค่า + เขียนไฟล์แบบดีบาวซ์
    function Save.set(key, value)
        local db = _load()
        db[key] = value
        _dirty = true
        _scheduleFlush()
    end

    -- ตัวช่วย: apply ค่าเซฟถ้ามี ไม่งั้นใช้ default แล้วเซฟกลับ
    function Save.apply(key, defaultValue, applyFn)
        local v = Save.get(key, defaultValue)
        if applyFn then
            local ok = pcall(applyFn, v)
            if ok and v ~= nil then Save.set(key, v) end
        end
        return v
    end

    -- ให้เรียกใช้ที่อื่นได้
    getgenv().UFOX_SAVE = Save
end
-- ===== [/Local Save] =====
--[[
UFO HUB X • One-shot = Toast(2-step) + Main UI (100%)
- Step1: Toast โหลด + แถบเปอร์เซ็นต์
- Step2: Toast "ดาวน์โหลดเสร็จ" โผล่ "พร้อมกับ" UI หลัก แล้วเลือนหายเอง
]]

------------------------------------------------------------
-- 1) ห่อ "UI หลักของคุณ (เดิม 100%)" ไว้ในฟังก์ชัน _G.UFO_ShowMainUI()
------------------------------------------------------------
_G.UFO_ShowMainUI = function()

--[[
UFO HUB X • Main UI + Safe Toggle (one-shot paste)
- ไม่ลบปุ่ม Toggle อีกต่อไป (ลบเฉพาะ UI หลัก)
- Toggle อยู่ของตัวเอง, มีขอบเขียว, ลากได้, บล็อกกล้องตอนลาก
- ซิงก์สถานะกับ UI หลักอัตโนมัติ และรีบอินด์ทุกครั้งที่ UI ถูกสร้างใหม่
]]

local Players  = game:GetService("Players")
local CoreGui  = game:GetService("CoreGui")
local UIS      = game:GetService("UserInputService")
local CAS      = game:GetService("ContextActionService")
local TS       = game:GetService("TweenService")
local RunS     = game:GetService("RunService")

-- ===== Theme / Size =====
local THEME = {
    GREEN=Color3.fromRGB(0,255,140),
    MINT=Color3.fromRGB(120,255,220),
    BG_WIN=Color3.fromRGB(16,16,16),
    BG_HEAD=Color3.fromRGB(6,6,6),
    BG_PANEL=Color3.fromRGB(22,22,22),
    BG_INNER=Color3.fromRGB(18,18,18),
    TEXT=Color3.fromRGB(235,235,235),
    RED=Color3.fromRGB(200,40,40),
    HILITE=Color3.fromRGB(22,30,24),
}
local SIZE={WIN_W=640,WIN_H=360,RADIUS=12,BORDER=3,HEAD_H=46,GAP_OUT=14,GAP_IN=8,BETWEEN=12,LEFT_RATIO=0.22}
local IMG_UFO="rbxassetid://100650447103028"
local ICON_HOME   = 134323882016779
local ICON_QUEST   = 72473476254744
local ICON_SHOP     = 139824330037901
local ICON_UPDATE   = 134419329246667
local ICON_SETTINGS = 72289858646360
local TOGGLE_ICON = "rbxassetid://117052960049460"

local function corner(p,r) local u=Instance.new("UICorner",p) u.CornerRadius=UDim.new(0,r or 10) return u end
local function stroke(p,th,col,tr) local s=Instance.new("UIStroke",p) s.Thickness=th or 1 s.Color=col or THEME.MINT s.Transparency=tr or 0.35 s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border s.LineJoinMode=Enum.LineJoinMode.Round return s end

-- ===== Utilities: find main UI + sync =====
local function findMain()
    local root = CoreGui:FindFirstChild("UFO_HUB_X_UI")
    if not root then
        local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
        if pg then root = pg:FindFirstChild("UFO_HUB_X_UI") end
    end
    local win = root and (root:FindFirstChild("Win") or root:FindFirstChildWhichIsA("Frame")) or nil
    return root, win
end

local function setOpen(open)
    local gui, win = findMain()
    if gui then gui.Enabled = open end
    if win then win.Visible = open end
    getgenv().UFO_ISOPEN = not not open
end

-- ====== SAFE TOGGLE (สร้าง/รีใช้, ไม่โดนลบ) ======
local ToggleGui = CoreGui:FindFirstChild("UFO_HUB_X_Toggle") :: ScreenGui
if not ToggleGui then
    ToggleGui = Instance.new("ScreenGui")
    ToggleGui.Name = "UFO_HUB_X_Toggle"
    ToggleGui.IgnoreGuiInset = true
    ToggleGui.DisplayOrder = 100001
    ToggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ToggleGui.ResetOnSpawn = false
    ToggleGui.Parent = CoreGui

    local Btn = Instance.new("ImageButton", ToggleGui)
    Btn.Name = "Button"
    Btn.Size = UDim2.fromOffset(64,64)
    Btn.Position = UDim2.fromOffset(90,220)
    Btn.Image = TOGGLE_ICON
    Btn.BackgroundColor3 = Color3.fromRGB(0,0,0)
    Btn.BorderSizePixel = 0
    corner(Btn,8); stroke(Btn,2,THEME.GREEN,0)

    -- drag + block camera
    local function block(on)
        local name="UFO_BlockLook_Toggle"
        if on then
            CAS:BindActionAtPriority(name,function() return Enum.ContextActionResult.Sink end,false,9000,
                Enum.UserInputType.MouseMovement,Enum.UserInputType.Touch,Enum.UserInputType.MouseButton1)
        else pcall(function() CAS:UnbindAction(name) end) end
    end
    local dragging=false; local start; local startPos
    Btn.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging=true; start=i.Position; startPos=Vector2.new(Btn.Position.X.Offset, Btn.Position.Y.Offset); block(true)
            i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false; block(false) end end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-start; Btn.Position=UDim2.fromOffset(startPos.X+d.X,startPos.Y+d.Y)
        end
    end)
end

-- (Re)bind toggle actions (กันผูกซ้ำ)
do
    local Btn = ToggleGui:FindFirstChild("Button")
    if getgenv().UFO_ToggleClick then pcall(function() getgenv().UFO_ToggleClick:Disconnect() end) end
    if getgenv().UFO_ToggleKey   then pcall(function() getgenv().UFO_ToggleKey:Disconnect() end) end
    getgenv().UFO_ToggleClick = Btn.MouseButton1Click:Connect(function() setOpen(not getgenv().UFO_ISOPEN) end)
    getgenv().UFO_ToggleKey   = UIS.InputBegan:Connect(function(i,gp) if gp then return end if i.KeyCode==Enum.KeyCode.RightShift then setOpen(not getgenv().UFO_ISOPEN) end end)
end

-- ====== ลบ "เฉพาะ" UI หลักเก่าก่อนสร้างใหม่ (ไม่ยุ่ง Toggle) ======
pcall(function() local old = CoreGui:FindFirstChild("UFO_HUB_X_UI"); if old then old:Destroy() end end)

-- ====== MAIN UI (เหมือนเดิม) ======
local GUI=Instance.new("ScreenGui")
GUI.Name="UFO_HUB_X_UI"
GUI.IgnoreGuiInset=true
GUI.ResetOnSpawn=false
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.DisplayOrder = 100000
GUI.Parent = CoreGui

local Win=Instance.new("Frame",GUI) Win.Name="Win"
Win.Size=UDim2.fromOffset(SIZE.WIN_W,SIZE.WIN_H)
Win.AnchorPoint=Vector2.new(0.5,0.5); Win.Position=UDim2.new(0.5,0,0.5,0)
Win.BackgroundColor3=THEME.BG_WIN; Win.BorderSizePixel=0
corner(Win,SIZE.RADIUS); stroke(Win,3,THEME.GREEN,0)

do local sc=Instance.new("UIScale",Win)
   local function fit() local v=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
       sc.Scale=math.clamp(math.min(v.X/860,v.Y/540),0.72,1.0) end
   fit(); RunS.RenderStepped:Connect(fit)
end

local Header=Instance.new("Frame",Win)
Header.Size=UDim2.new(1,0,0,SIZE.HEAD_H)
Header.BackgroundColor3=THEME.BG_HEAD; Header.BorderSizePixel=0
corner(Header,SIZE.RADIUS)
local Accent=Instance.new("Frame",Header)
Accent.AnchorPoint=Vector2.new(0.5,1); Accent.Position=UDim2.new(0.5,0,1,0)
Accent.Size=UDim2.new(1,-20,0,1); Accent.BackgroundColor3=THEME.MINT; Accent.BackgroundTransparency=0.35
local Title=Instance.new("TextLabel",Header)
Title.BackgroundTransparency=1; Title.AnchorPoint=Vector2.new(0.5,0)
Title.Position=UDim2.new(0.5,0,0,6); Title.Size=UDim2.new(0.8,0,0,36)
Title.Font=Enum.Font.GothamBold; Title.TextScaled=true; Title.RichText=true
Title.Text='<font color="#FFFFFF">UFO</font> <font color="#00FF8C">HUB X</font>'
Title.TextColor3=THEME.TEXT

local BtnClose=Instance.new("TextButton",Header)
BtnClose.AutoButtonColor=false; BtnClose.Size=UDim2.fromOffset(24,24)
BtnClose.Position=UDim2.new(1,-34,0.5,-12); BtnClose.BackgroundColor3=THEME.RED
BtnClose.Text="X"; BtnClose.Font=Enum.Font.GothamBold; BtnClose.TextSize=13
BtnClose.TextColor3=Color3.new(1,1,1); BtnClose.BorderSizePixel=0
corner(BtnClose,6); stroke(BtnClose,1,Color3.fromRGB(255,0,0),0.1)
BtnClose.MouseButton1Click:Connect(function() setOpen(false) end)

-- UFO icon
local UFO=Instance.new("ImageLabel",Win)
UFO.BackgroundTransparency=1; UFO.Image=IMG_UFO
UFO.Size=UDim2.fromOffset(168,168); UFO.AnchorPoint=Vector2.new(0.5,1)
UFO.Position=UDim2.new(0.5,0,0,84); UFO.ZIndex=4

-- === DRAG MAIN ONLY (ลากได้เฉพาะ UI หลักที่ Header; บล็อกกล้องระหว่างลาก) ===
do
    local dragging = false
    local startInputPos: Vector2
    local startWinOffset: Vector2
    local blockDrag = false

    -- กันเผลอลากตอนกดปุ่ม X
    BtnClose.MouseButton1Down:Connect(function() blockDrag = true end)
    BtnClose.MouseButton1Up:Connect(function() blockDrag = false end)

    local function blockCamera(on: boolean)
        local name = "UFO_BlockLook_MainDrag"
        if on then
            CAS:BindActionAtPriority(name, function()
                return Enum.ContextActionResult.Sink
            end, false, 9000,
            Enum.UserInputType.MouseMovement,
            Enum.UserInputType.Touch,
            Enum.UserInputType.MouseButton1)
        else
            pcall(function() CAS:UnbindAction(name) end)
        end
    end

    Header.InputBegan:Connect(function(input)
        if blockDrag then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startInputPos  = input.Position
            startWinOffset = Vector2.new(Win.Position.X.Offset, Win.Position.Y.Offset)
            blockCamera(true)
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    blockCamera(false)
                end
            end)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - startInputPos
        Win.Position = UDim2.new(0.5, startWinOffset.X + delta.X, 0.5, startWinOffset.Y + delta.Y)
    end)
end
-- === END DRAG MAIN ONLY ===

-- BODY
local Body=Instance.new("Frame",Win)
Body.BackgroundColor3=THEME.BG_INNER; Body.BorderSizePixel=0
Body.Position=UDim2.new(0,SIZE.GAP_OUT,0,SIZE.HEAD_H+SIZE.GAP_OUT)
Body.Size=UDim2.new(1,-SIZE.GAP_OUT*2,1,-(SIZE.HEAD_H+SIZE.GAP_OUT*2))
corner(Body,12); stroke(Body,0.5,THEME.MINT,0.35)

-- === LEFT (แทนที่บล็อกก่อนหน้าได้เลย) ================================
local LeftShell = Instance.new("Frame", Body)
LeftShell.BackgroundColor3 = THEME.BG_PANEL
LeftShell.BorderSizePixel  = 0
LeftShell.Position         = UDim2.new(0, SIZE.GAP_IN, 0, SIZE.GAP_IN)
LeftShell.Size             = UDim2.new(SIZE.LEFT_RATIO, -(SIZE.BETWEEN/2), 1, -SIZE.GAP_IN*2)
LeftShell.ClipsDescendants = true
corner(LeftShell, 10)
stroke(LeftShell, 1.2, THEME.GREEN, 0)
stroke(LeftShell, 0.45, THEME.MINT, 0.35)

local LeftScroll = Instance.new("ScrollingFrame", LeftShell)
LeftScroll.BackgroundTransparency = 1
LeftScroll.Size                   = UDim2.fromScale(1,1)
LeftScroll.ScrollBarThickness     = 0
LeftScroll.ScrollingDirection     = Enum.ScrollingDirection.Y
LeftScroll.AutomaticCanvasSize    = Enum.AutomaticSize.None
LeftScroll.ElasticBehavior        = Enum.ElasticBehavior.Never
LeftScroll.ScrollingEnabled       = true
LeftScroll.ClipsDescendants       = true

local padL = Instance.new("UIPadding", LeftScroll)
padL.PaddingTop    = UDim.new(0, 8)
padL.PaddingLeft   = UDim.new(0, 8)
padL.PaddingRight  = UDim.new(0, 8)
padL.PaddingBottom = UDim.new(0, 8)

local LeftList = Instance.new("UIListLayout", LeftScroll)
LeftList.Padding   = UDim.new(0, 8)
LeftList.SortOrder = Enum.SortOrder.LayoutOrder

-- ===== คุม Canvas + กันเด้งกลับตอนคลิกแท็บ =====
local function refreshLeftCanvas()
    local contentH = LeftList.AbsoluteContentSize.Y + padL.PaddingTop.Offset + padL.PaddingBottom.Offset
    LeftScroll.CanvasSize = UDim2.new(0, 0, 0, contentH)
end

local function clampTo(yTarget)
    local contentH = LeftList.AbsoluteContentSize.Y + padL.PaddingTop.Offset + padL.PaddingBottom.Offset
    local viewH    = LeftScroll.AbsoluteSize.Y
    local maxY     = math.max(0, contentH - viewH)
    LeftScroll.CanvasPosition = Vector2.new(0, math.clamp(yTarget or 0, 0, maxY))
end

-- ✨ จำตำแหน่งล่าสุดไว้ใช้ “ทุกครั้ง” ที่มีการจัดเลย์เอาต์ใหม่
local lastY = 0

LeftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    refreshLeftCanvas()
    clampTo(lastY) -- ใช้ค่าเดิมที่จำไว้ ไม่อ่านจาก CanvasPosition ที่อาจโดนรีเซ็ต
end)

task.defer(refreshLeftCanvas)

-- name/icon = ชื่อ/ไอคอนฝั่งขวา, setFns = ฟังก์ชันเซ็ต active, btn = ปุ่มที่ถูกกด
local function onTabClick(name, icon, setFns, btn)
    -- บันทึกตำแหน่งปัจจุบัน “ไว้ก่อน” ที่เลย์เอาต์จะขยับ
    lastY = LeftScroll.CanvasPosition.Y

    setFns()
    showRight(name, icon)

    task.defer(function()
        refreshLeftCanvas()
        clampTo(lastY) -- คืนตำแหน่งเดิมเสมอ

        -- ถ้าปุ่มอยู่นอกจอ ค่อยเลื่อนเข้าเฟรมอย่างพอดี (จะปรับ lastY ด้วย)
        if btn and btn.Parent then
            local viewH   = LeftScroll.AbsoluteSize.Y
            local btnTop  = btn.AbsolutePosition.Y - LeftScroll.AbsolutePosition.Y
            local btnBot  = btnTop + btn.AbsoluteSize.Y
            local pad     = 8
            local y = LeftScroll.CanvasPosition.Y
            if btnTop < 0 then
                y = y + (btnTop - pad)
            elseif btnBot > viewH then
                y = y + (btnBot - viewH) + pad
            end
            lastY = y
            clampTo(lastY)
        end
    end)
end

-- === ผูกคลิกแท็บทั้ง 7 (เหมือนเดิม) ================================
task.defer(function()
    repeat task.wait() until
        btnHome and btnQuest and btnShop and btnSettings
  

   btnHome.MouseButton1Click:Connect(function()
        onTabClick("Home", ICON_HOME, function()
            setHomeActive(true); setQuestActive(false)
            setShopActive(false); setSettingsActive(false)
        end, btnHome)
    end)


btnShop.MouseButton1Click:Connect(function()
        onTabClick("Shop", ICON_SHOP, function()
            setHomeActive(false); setQuestActive(false)
            setShopActive(true); setSettingsActive(false)
        end, btnShop)
    end)
    

    btnSettings.MouseButton1Click:Connect(function()
        onTabClick("Settings", ICON_SETTINGS, function()
            setHomeActive(false); setQuestActive(false)
            setShopActive(false); setSettingsActive(true)
        end, btnSettings)
    end)
end)
-- ===================================================================

----------------------------------------------------------------
-- LEFT (ปุ่มแท็บ) + RIGHT (คอนเทนต์) — เวอร์ชันครบ + แก้บัคสกอร์ลแยกแท็บ
----------------------------------------------------------------

-- ========== LEFT ==========
local LeftShell=Instance.new("Frame",Body)
LeftShell.BackgroundColor3=THEME.BG_PANEL; LeftShell.BorderSizePixel=0
LeftShell.Position=UDim2.new(0,SIZE.GAP_IN,0,SIZE.GAP_IN)
LeftShell.Size=UDim2.new(SIZE.LEFT_RATIO,-(SIZE.BETWEEN/2),1,-SIZE.GAP_IN*2)
LeftShell.ClipsDescendants=true
corner(LeftShell,10); stroke(LeftShell,1.2,THEME.GREEN,0); stroke(LeftShell,0.45,THEME.MINT,0.35)

local LeftScroll=Instance.new("ScrollingFrame",LeftShell)
LeftScroll.BackgroundTransparency=1
LeftScroll.Size=UDim2.fromScale(1,1)
LeftScroll.ScrollBarThickness=0
LeftScroll.ScrollingDirection=Enum.ScrollingDirection.Y
LeftScroll.AutomaticCanvasSize=Enum.AutomaticSize.None
LeftScroll.ElasticBehavior=Enum.ElasticBehavior.Never
LeftScroll.ScrollingEnabled=true
LeftScroll.ClipsDescendants=true

local padL=Instance.new("UIPadding",LeftScroll)
padL.PaddingTop=UDim.new(0,8); padL.PaddingLeft=UDim.new(0,8); padL.PaddingRight=UDim.new(0,8); padL.PaddingBottom=UDim.new(0,8)
local LeftList=Instance.new("UIListLayout",LeftScroll); LeftList.Padding=UDim.new(0,8); LeftList.SortOrder=Enum.SortOrder.LayoutOrder

local function refreshLeftCanvas()
    local contentH = LeftList.AbsoluteContentSize.Y + padL.PaddingTop.Offset + padL.PaddingBottom.Offset
    LeftScroll.CanvasSize = UDim2.new(0,0,0,contentH)
end
local lastLeftY = 0
LeftList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    refreshLeftCanvas()
    local viewH = LeftScroll.AbsoluteSize.Y
    local maxY  = math.max(0, LeftScroll.CanvasSize.Y.Offset - viewH)
    LeftScroll.CanvasPosition = Vector2.new(0, math.clamp(lastLeftY,0,maxY))
end)
task.defer(refreshLeftCanvas)

-- สร้างปุ่มแท็บ
local function makeTabButton(parent, label, iconId)
    local holder = Instance.new("Frame", parent) holder.BackgroundTransparency=1 holder.Size = UDim2.new(1,0,0,38)
    local b = Instance.new("TextButton", holder) b.AutoButtonColor=false b.Text="" b.Size=UDim2.new(1,0,1,0) b.BackgroundColor3=THEME.BG_INNER corner(b,8)
    local st = stroke(b,1,THEME.MINT,0.35)
    local ic = Instance.new("ImageLabel", b) ic.BackgroundTransparency=1 ic.Image="rbxassetid://"..tostring(iconId) ic.Size=UDim2.fromOffset(22,22) ic.Position=UDim2.new(0,10,0.5,-11)
    local tx = Instance.new("TextLabel", b) tx.BackgroundTransparency=1 tx.TextColor3=THEME.TEXT tx.Font=Enum.Font.GothamMedium tx.TextSize=15 tx.TextXAlignment=Enum.TextXAlignment.Left tx.Position=UDim2.new(0,38,0,0) tx.Size=UDim2.new(1,-46,1,0) tx.Text = label
    local flash=Instance.new("Frame",b) flash.BackgroundColor3=THEME.GREEN flash.BackgroundTransparency=1 flash.BorderSizePixel=0 flash.AnchorPoint=Vector2.new(0.5,0.5) flash.Position=UDim2.new(0.5,0,0.5,0) flash.Size=UDim2.new(0,0,0,0) corner(flash,12)
    b.MouseButton1Down:Connect(function() TS:Create(b, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1,0,1,-2)}):Play() end)
    b.MouseButton1Up:Connect(function() TS:Create(b, TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(1,0,1,0)}):Play() end)
    local function setActive(on)
        if on then
            b.BackgroundColor3=THEME.HILITE; st.Color=THEME.GREEN; st.Transparency=0; st.Thickness=2
            flash.BackgroundTransparency=0.35; flash.Size=UDim2.new(0,0,0,0)
            TS:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1}):Play()
        else
            b.BackgroundColor3=THEME.BG_INNER; st.Color=THEME.MINT; st.Transparency=0.35; st.Thickness=1
        end
    end
    return b, setActive
end

local btnHome,setHomeActive = makeTabButton(LeftScroll, "Home",ICON_HOME)
local btnShop,setShopActive = makeTabButton(LeftScroll, "Shop",ICON_SHOP)
local btnSettings,setSettingsActive = makeTabButton(LeftScroll, "Settings",ICON_SETTINGS)

-- ========== RIGHT ==========
local RightShell=Instance.new("Frame",Body)
RightShell.BackgroundColor3=THEME.BG_PANEL; RightShell.BorderSizePixel=0
RightShell.Position=UDim2.new(SIZE.LEFT_RATIO,SIZE.BETWEEN,0,SIZE.GAP_IN)
RightShell.Size=UDim2.new(1-SIZE.LEFT_RATIO,-SIZE.GAP_IN-SIZE.BETWEEN,1,-SIZE.GAP_IN*2)
corner(RightShell,10); stroke(RightShell,1.2,THEME.GREEN,0); stroke(RightShell,0.45,THEME.MINT,0.35)

local RightScroll=Instance.new("ScrollingFrame",RightShell)
RightScroll.BackgroundTransparency=1; RightScroll.Size=UDim2.fromScale(1,1)
RightScroll.ScrollBarThickness=0; RightScroll.ScrollingDirection=Enum.ScrollingDirection.Y
RightScroll.AutomaticCanvasSize=Enum.AutomaticSize.None   -- คุมเองเพื่อกันเด้ง/จำ Y ได้
RightScroll.ElasticBehavior=Enum.ElasticBehavior.Never

local padR=Instance.new("UIPadding",RightScroll)
padR.PaddingTop=UDim.new(0,12); padR.PaddingLeft=UDim.new(0,12); padR.PaddingRight=UDim.new(0,12); padR.PaddingBottom=UDim.new(0,12)
local RightList=Instance.new("UIListLayout",RightScroll); RightList.Padding=UDim.new(0,10); RightList.SortOrder = Enum.SortOrder.LayoutOrder

local function refreshRightCanvas()
    local contentH = RightList.AbsoluteContentSize.Y + padR.PaddingTop.Offset + padR.PaddingBottom.Offset
    RightScroll.CanvasSize = UDim2.new(0,0,0,contentH)
end
RightList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    local yBefore = RightScroll.CanvasPosition.Y
    refreshRightCanvas()
    local viewH = RightScroll.AbsoluteSize.Y
    local maxY  = math.max(0, RightScroll.CanvasSize.Y.Offset - viewH)
    RightScroll.CanvasPosition = Vector2.new(0, math.clamp(yBefore,0,maxY))
end)
-- ================= RIGHT: Modular per-tab (drop-in) =================
-- ใส่หลังจากสร้าง RightShell เสร็จ (และก่อนผูกปุ่มกด)

-- 1) เก็บ/ใช้ state กลาง
if not getgenv().UFO_RIGHT then getgenv().UFO_RIGHT = {} end
local RSTATE = getgenv().UFO_RIGHT
RSTATE.frames   = RSTATE.frames   or {}
RSTATE.builders = RSTATE.builders or {}
RSTATE.scrollY  = RSTATE.scrollY  or {}
RSTATE.current  = RSTATE.current

-- 2) ถ้ามี RightScroll เก่าอยู่ ให้ลบทิ้ง
pcall(function()
    local old = RightShell:FindFirstChildWhichIsA("ScrollingFrame")
    if old then old:Destroy() end
end)

-- 3) สร้าง ScrollingFrame ต่อแท็บ
local function makeTabFrame(tabName)
    local root = Instance.new("Frame")
    root.Name = "RightTab_"..tabName
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1,1)
    root.Visible = false
    root.Parent = RightShell

    local sf = Instance.new("ScrollingFrame", root)
    sf.Name = "Scroll"
    sf.BackgroundTransparency = 1
    sf.Size = UDim2.fromScale(1,1)
    sf.ScrollBarThickness = 0      -- ← ซ่อนสกรอลล์บาร์ (เดิม 4)
    sf.ScrollingDirection = Enum.ScrollingDirection.Y
    sf.AutomaticCanvasSize = Enum.AutomaticSize.None
    sf.ElasticBehavior = Enum.ElasticBehavior.Never
    sf.CanvasSize = UDim2.new(0,0,0,600)  -- เลื่อนได้ตั้งแต่เริ่ม

    local pad = Instance.new("UIPadding", sf)
    pad.PaddingTop    = UDim.new(0,12)
    pad.PaddingLeft   = UDim.new(0,12)
    pad.PaddingRight  = UDim.new(0,12)
    pad.PaddingBottom = UDim.new(0,12)

    local list = Instance.new("UIListLayout", sf)
    list.Padding = UDim.new(0,10)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.VerticalAlignment = Enum.VerticalAlignment.Top

    local function refreshCanvas()
        local h = list.AbsoluteContentSize.Y + pad.PaddingTop.Offset + pad.PaddingBottom.Offset
        sf.CanvasSize = UDim2.new(0,0,0, math.max(h,600))
    end

    list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        local yBefore = sf.CanvasPosition.Y
        refreshCanvas()
        local viewH = sf.AbsoluteSize.Y
        local maxY  = math.max(0, sf.CanvasSize.Y.Offset - viewH)
        sf.CanvasPosition = Vector2.new(0, math.clamp(yBefore, 0, maxY))
    end)

    task.defer(refreshCanvas)

    RSTATE.frames[tabName] = {root=root, scroll=sf, list=list, built=false}
    return RSTATE.frames[tabName]
end

-- 4) ลงทะเบียนฟังก์ชันสร้างคอนเทนต์ต่อแท็บ (รองรับหลายตัว)
local function registerRight(tabName, builderFn)
    RSTATE.builders[tabName] = RSTATE.builders[tabName] or {}
    table.insert(RSTATE.builders[tabName], builderFn)
end

-- 5) หัวเรื่อง
local function addHeader(parentScroll, titleText, iconId)
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1,0,0,28)
    row.Parent = parentScroll

    local icon = Instance.new("ImageLabel", row)
    icon.BackgroundTransparency = 1
    icon.Image = "rbxassetid://"..tostring(iconId or "")
    icon.Size = UDim2.fromOffset(20,20)
    icon.Position = UDim2.new(0,0,0.5,-10)

    local head = Instance.new("TextLabel", row)
    head.BackgroundTransparency = 1
    head.Font = Enum.Font.GothamBold
    head.TextSize = 18
    head.TextXAlignment = Enum.TextXAlignment.Left
    head.TextColor3 = THEME.TEXT
    head.Position = UDim2.new(0,26,0,0)
    head.Size = UDim2.new(1,-26,1,0)
    head.Text = titleText
end

------------------------------------------------------------
-- 6) API หลัก + แปลชื่อหัวข้อเป็นภาษาไทย
------------------------------------------------------------

-- map ชื่อแท็บ (key ภาษาอังกฤษด้านใน) -> หัวข้อภาษาไทยที่โชว์
local TAB_TITLE_TH = {
    Home = "Home",
    Shop = "Shop",
    Settings = "Settings",
}

function showRight(tabKey, iconId)
    -- tabKey = key ภาษาอังกฤษ ("Player","Home","Settings",...)
    local tab = tabKey
    -- ข้อความที่โชว์บนหัวข้อ ใช้ภาษาไทย ถ้ามีในตาราง ไม่มีก็ใช้อังกฤษเดิม
    local titleText = TAB_TITLE_TH[tabKey] or tabKey

    if RSTATE.current and RSTATE.frames[RSTATE.current] then
        RSTATE.scrollY[RSTATE.current] = RSTATE.frames[RSTATE.current].scroll.CanvasPosition.Y
        RSTATE.frames[RSTATE.current].root.Visible = false
    end

    local f = RSTATE.frames[tab] or makeTabFrame(tab)
    f.root.Visible = true

    if not f.built then
        -- ตรงนี้ใช้ titleText (ไทย) สำหรับหัวข้อ
        addHeader(f.scroll, titleText, iconId)

        local list = RSTATE.builders[tab] or {}
        for _, builder in ipairs(list) do
            pcall(builder, f.scroll)
        end
        f.built = true
    end

    task.defer(function()
        local y = RSTATE.scrollY[tab] or 0
        local viewH = f.scroll.AbsoluteSize.Y
        local maxY  = math.max(0, f.scroll.CanvasSize.Y.Offset - viewH)
        f.scroll.CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY))
    end)

    RSTATE.current = tab
end
    
-- 7) ตัวอย่างแท็บ (ลบเดโมรายการออกแล้ว)
registerRight("Home", function(scroll)
    -- วาง UI ของ Player ที่นี่ (ตอนนี้ปล่อยว่าง ไม่มี Item#)
end)

registerRight("Home", function(scroll) end)
registerRight("Shop", function(scroll) end)
registerRight("Settings", function(scroll) end)
--===== UFO HUB X • Unlock System (Immortal + Camera + Anti-Lag No Cooldown) – MODEL A V1 =====
-- Feature 1: 999 Trillion Health + Real-time Re-fill + Damage Protection
-- Feature 2: Unlock Camera Max Zoom (Infinite Zoom)
-- Feature 3: No Cooldown Click (No-Lag / Event-Based / Screen UI Only)
-- UI Model: A V1 (Green Glow Border / Dynamic Switch / LayoutOrder 0)

registerRight("Home", function(scroll)
    local TweenService = game:GetService("TweenService")
    local RunService = game:GetService("RunService")
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local ProximityPromptService = game:GetService("ProximityPromptService")
    local LocalPlayer = Players.LocalPlayer

    ------------------------------------------------------------------------
    -- AA1 SAVE SYSTEM
    ------------------------------------------------------------------------
    local SAVE = (getgenv and getgenv().UFOX_SAVE) or {
        get = function(_, _, d) return d end,
        set = function() end
    }
    local SCOPE = ("UFO_UnlockSystemV4/%d/%d"):format(tonumber(game.GameId) or 0, tonumber(game.PlaceId) or 0)
    local function K(k) return SCOPE .. "/" .. k end
    local function SaveGet(key, default)
        local ok, v = pcall(function() return SAVE.get(K(key), default) end)
        return ok and v or default
    end
    local function SaveSet(key, value) pcall(function() SAVE.set(K(key), value) end) end

    ------------------------------------------------------------------------
    -- THEME & HELPERS (Model A V1)
    ------------------------------------------------------------------------
    local THEME = {
        GREEN = Color3.fromRGB(25, 255, 125),
        RED   = Color3.fromRGB(255, 40, 40),
        WHITE = Color3.fromRGB(255, 255, 255),
        BLACK = Color3.fromRGB(0, 0, 0),
    }

    local function corner(ui, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 12)
        c.Parent = ui
    end

    local function stroke(ui, th, col)
        local s = Instance.new("UIStroke")
        s.Thickness = th or 2.2
        s.Color = col or THEME.GREEN
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = ui
        return s
    end

    local function tween(o, p, d)
        TweenService:Create(o, TweenInfo.new(d or 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), p):Play()
    end

    ------------------------------------------------------------------------
    -- SYSTEM 1: IMMORTAL LOGIC
    ------------------------------------------------------------------------
    local godModeOn = SaveGet("godModeOn", false)
    local godConn = nil
    local SUPREME_HEALTH = 9.9e14 

    local function applyGodMode()
        if godConn then godConn:Disconnect() godConn = nil end
        if godModeOn then
            godConn = RunService.PreRender:Connect(function()
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum.MaxHealth = SUPREME_HEALTH
                    hum.Health = SUPREME_HEALTH
                    hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
                    if not char:FindFirstChildOfClass("ForceField") then
                        local ff = Instance.new("ForceField", char)
                        ff.Visible = false
                    end
                end
                
                local gui = LocalPlayer:FindFirstChild("PlayerGui")
                if gui then
                    local b1 = gui:FindFirstChild("BloodGui")
                    local b2 = gui:FindFirstChild("HealthGui")
                    if b1 then b1.Enabled = false end
                    if b2 then b2.Enabled = false end
                end
            end)
        else
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.MaxHealth = 100 hum.Health = 100
                hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
            end
            if char and char:FindFirstChildOfClass("ForceField") then
                char:FindFirstChildOfClass("ForceField"):Destroy()
            end
        end
    end
    applyGodMode()

    ------------------------------------------------------------------------
    -- SYSTEM 2: UNLOCK CAMERA LOGIC
    ------------------------------------------------------------------------
    local camUnlockOn = SaveGet("camUnlockOn", false)
    local camConn = nil

    local function applyCamUnlock()
        if camConn then camConn:Disconnect() camConn = nil end
        if camUnlockOn then
            camConn = RunService.RenderStepped:Connect(function()
                LocalPlayer.CameraMaxZoomDistance = 100000 
            end)
        else
            LocalPlayer.CameraMaxZoomDistance = 128 
        end
    end
    applyCamUnlock()

    ------------------------------------------------------------------------
    -- SYSTEM 3: NO COOLDOWN CLICK V4 (EVENT-BASED / NO LAG)
    ------------------------------------------------------------------------
    local noCooldownOn = SaveGet("noCooldownOn", false)
    local inputConn = nil
    local promptConn = nil

    local function handleUIUnblock()
        local gui = LocalPlayer:FindFirstChild("PlayerGui")
        if not gui then return end
        
        -- ตรวจเฉพาะปุ่มที่กำลังแสดงบนหน้าจอ (Visible) เท่านั้น
        for _, v in pairs(gui:GetDescendants()) do
            if (v:IsA("TextButton") or v:IsA("ImageButton")) and v.Visible then
                local name = v.Name:lower()
                if name:find("takeprompt") or name:find("cooldown") or name:find("wait") then
                    v.Active = true
                    v.Interactable = true
                    -- ปิด Overlay ที่มาบังปุ่ม
                    for _, child in pairs(v:GetChildren()) do
                        if (child:IsA("Frame") or child:IsA("ImageLabel")) and child.Visible then
                            if child.Name:lower():find("lock") or child.Name:lower():find("wait") or child.BackgroundTransparency < 1 then
                                child.Visible = false
                            end
                        end
                    end
                end
            end
        end
    end

    local function applyNoCooldown()
        if inputConn then inputConn:Disconnect() inputConn = nil end
        if promptConn then promptConn:Disconnect() promptConn = nil end

        if noCooldownOn then
            -- 1. ทำงานเฉพาะตอนมีการคลิกหรือกดจอ (ประหยัด CPU 100%)
            inputConn = UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    handleUIUnblock()
                end
            end)

            -- 2. จัดการ ProximityPrompt เฉพาะตัวที่โผล่ขึ้นมาใกล้ตัว
            promptConn = ProximityPromptService.PromptShown:Connect(function(prompt)
                prompt.HoldDuration = 0
                prompt.Enabled = true
            end)
            
            -- รันครั้งแรกหนึ่งรอบเพื่อล้างค่าปุ่มที่มีอยู่
            handleUIUnblock()
        end
    end
    applyNoCooldown()

    ------------------------------------------------------------------------
    -- UI CONSTRUCTION (Model A V1 - LAYOUT ORDER 0 ALL)
    ------------------------------------------------------------------------
    
    local header = Instance.new("TextLabel", scroll)
    header.Name = "Unlock_Header"
    header.BackgroundTransparency = 1; header.Size = UDim2.new(1, 0, 0, 36)
    header.Font = Enum.Font.GothamBold; header.TextSize = 16; header.TextColor3 = THEME.WHITE
    header.TextXAlignment = Enum.TextXAlignment.Left; header.Text = "》》》  Unlock 🔓 《《《"
    header.LayoutOrder = 0

    -- รายการที่ 1: Immortal 1 time
    local row1 = Instance.new("Frame", scroll)
    row1.Name = "Immortal_Row"; row1.Size = UDim2.new(1, -6, 0, 46); row1.BackgroundColor3 = THEME.BLACK; row1.LayoutOrder = 0
    corner(row1, 12); stroke(row1, 2.2, THEME.GREEN)

    local lab1 = Instance.new("TextLabel", row1)
    lab1.BackgroundTransparency = 1; lab1.Size = UDim2.new(1, -160, 1, 0); lab1.Position = UDim2.new(0, 16, 0, 0)
    lab1.Font = Enum.Font.GothamBold; lab1.TextSize = 13; lab1.TextColor3 = THEME.WHITE
    lab1.TextXAlignment = Enum.TextXAlignment.Left; lab1.Text = "Immortal 1 time"

    local sw1 = Instance.new("Frame", row1)
    sw1.AnchorPoint = Vector2.new(1, 0.5); sw1.Position = UDim2.new(1, -12, 0.5, 0); sw1.Size = UDim2.fromOffset(52, 26); sw1.BackgroundColor3 = THEME.BLACK
    corner(sw1, 13); local swStroke1 = stroke(sw1, 1.8, THEME.RED)
    local knob1 = Instance.new("Frame", sw1)
    knob1.Size = UDim2.fromOffset(22, 22); knob1.BackgroundColor3 = THEME.WHITE; knob1.Position = UDim2.new(0, 2, 0.5, -11)
    corner(knob1, 11)

    local function updateUI1(on)
        swStroke1.Color = on and THEME.GREEN or THEME.RED
        tween(knob1, { Position = UDim2.new(on and 1 or 0, on and -24 or 2, 0.5, -11) }, 0.08)
    end
    
    local btn1 = Instance.new("TextButton", sw1)
    btn1.BackgroundTransparency = 1; btn1.Size = UDim2.fromScale(1, 1); btn1.Text = ""; btn1.AutoButtonColor = false
    btn1.MouseButton1Click:Connect(function()
        godModeOn = not godModeOn; SaveSet("godModeOn", godModeOn); applyGodMode(); updateUI1(godModeOn)
    end)
    updateUI1(godModeOn)

    -- รายการที่ 2: Unlock Camera Max Zoom
    local row2 = Instance.new("Frame", scroll)
    row2.Name = "Camera_Row"; row2.Size = UDim2.new(1, -6, 0, 46); row2.BackgroundColor3 = THEME.BLACK; row2.LayoutOrder = 0
    corner(row2, 12); stroke(row2, 2.2, THEME.GREEN)

    local lab2 = Instance.new("TextLabel", row2)
    lab2.BackgroundTransparency = 1; lab2.Size = UDim2.new(1, -160, 1, 0); lab2.Position = UDim2.new(0, 16, 0, 0)
    lab2.Font = Enum.Font.GothamBold; lab2.TextSize = 13; lab2.TextColor3 = THEME.WHITE
    lab2.TextXAlignment = Enum.TextXAlignment.Left; lab2.Text = "Unlock Camera Max Zoom"

    local sw2 = Instance.new("Frame", row2)
    sw2.AnchorPoint = Vector2.new(1, 0.5); sw2.Position = UDim2.new(1, -12, 0.5, 0); sw2.Size = UDim2.fromOffset(52, 26); sw2.BackgroundColor3 = THEME.BLACK
    corner(sw2, 13); local swStroke2 = stroke(sw2, 1.8, THEME.RED)
    local knob2 = Instance.new("Frame", sw2)
    knob2.Size = UDim2.fromOffset(22, 22); knob2.BackgroundColor3 = THEME.WHITE; knob2.Position = UDim2.new(0, 2, 0.5, -11)
    corner(knob2, 11)

    local function updateUI2(on)
        swStroke2.Color = on and THEME.GREEN or THEME.RED
        tween(knob2, { Position = UDim2.new(on and 1 or 0, on and -24 or 2, 0.5, -11) }, 0.08)
    end

    local btn2 = Instance.new("TextButton", sw2)
    btn2.BackgroundTransparency = 1; btn2.Size = UDim2.fromScale(1, 1); btn2.Text = ""; btn2.AutoButtonColor = false
    btn2.MouseButton1Click:Connect(function()
        camUnlockOn = not camUnlockOn; SaveSet("camUnlockOn", camUnlockOn); applyCamUnlock(); updateUI2(camUnlockOn)
    end)
    updateUI2(camUnlockOn)

    -- รายการที่ 3: No Cooldown Click
    local row3 = Instance.new("Frame", scroll)
    row3.Name = "NoCooldown_Row"; row3.Size = UDim2.new(1, -6, 0, 46); row3.BackgroundColor3 = THEME.BLACK; row3.LayoutOrder = 0
    corner(row3, 12); stroke(row3, 2.2, THEME.GREEN)

    local lab3 = Instance.new("TextLabel", row3)
    lab3.BackgroundTransparency = 1; lab3.Size = UDim2.new(1, -160, 1, 0); lab3.Position = UDim2.new(0, 16, 0, 0)
    lab3.Font = Enum.Font.GothamBold; lab3.TextSize = 13; lab3.TextColor3 = THEME.WHITE
    lab3.TextXAlignment = Enum.TextXAlignment.Left; lab3.Text = "No Cooldown Click"

    local sw3 = Instance.new("Frame", row3)
    sw3.AnchorPoint = Vector2.new(1, 0.5); sw3.Position = UDim2.new(1, -12, 0.5, 0); sw3.Size = UDim2.fromOffset(52, 26); sw3.BackgroundColor3 = THEME.BLACK
    corner(sw3, 13); local swStroke3 = stroke(sw3, 1.8, THEME.RED)
    local knob3 = Instance.new("Frame", sw3)
    knob3.Size = UDim2.fromOffset(22, 22); knob3.BackgroundColor3 = THEME.WHITE; knob3.Position = UDim2.new(0, 2, 0.5, -11)
    corner(knob3, 11)

    local function updateUI3(on)
        swStroke3.Color = on and THEME.GREEN or THEME.RED
        tween(knob3, { Position = UDim2.new(on and 1 or 0, on and -24 or 2, 0.5, -11) }, 0.08)
    end

    local btn3 = Instance.new("TextButton", sw3)
    btn3.BackgroundTransparency = 1; btn3.Size = UDim2.fromScale(1, 1); btn3.Text = ""; btn3.AutoButtonColor = false
    btn3.MouseButton1Click:Connect(function()
        noCooldownOn = not noCooldownOn; SaveSet("noCooldownOn", noCooldownOn); applyNoCooldown(); updateUI3(noCooldownOn)
    end)
    updateUI3(noCooldownOn)

end)
--===== UFO HUB X • Move System (AAA1 + AA1 + AAA2 COMBO) – FULL NEON EDITION =====
-- Target Map: Escape the tsunami and head to Brainrots
-- Feature: Added Rocket Button (Emoji 🚀) - Fly to Current Selected Number Position
-- LayoutOrder: 0

registerRight("Home", function(scroll)
    local TweenService = game:GetService("TweenService")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local LocalPlayer = Players.LocalPlayer

    ------------------------------------------------------------------------
    -- AA1 SAVE SYSTEM (UFO HUB X / MAP FOLDER)
    ------------------------------------------------------------------------
    local MAIN_FOLDER = "UFO HUB X"
    local MAP_FOLDER = "Escape the tsunami and head to Brainrots"
    local SAVE_PATH = MAIN_FOLDER .. "/" .. MAP_FOLDER .. "/Settings.json"

    if makefolder then
        pcall(function() makefolder(MAIN_FOLDER .. "/" .. MAP_FOLDER) end)
    end

    local function SaveSettings(data)
        if writefile then
            local success, str = pcall(function() return HttpService:JSONEncode(data) end)
            if success then writefile(SAVE_PATH, str) end
        end
    end

    local function LoadSettings()
        if isfile and isfile(SAVE_PATH) then
            local success, data = pcall(function() return HttpService:JSONDecode(readfile(SAVE_PATH)) end)
            if success then return data end
        end
        return nil
    end

    local config = LoadSettings() or {
        Enabled = false,
        FlySpeed = 1.0,
        BtnSize = 60,
        Pos = {X = 30, Y = 150}
    }

    ------------------------------------------------------------------------
    -- THEME & HELPERS
    ------------------------------------------------------------------------
    local THEME = {
        GREEN  = Color3.fromRGB(25, 255, 140),
        NEON_GREEN = Color3.fromRGB(50, 255, 50),
        RED    = Color3.fromRGB(255, 40, 40),
        BLUE   = Color3.fromRGB(0, 170, 255),
        PURPLE = Color3.fromRGB(180, 50, 255),
        YELLOW = Color3.fromRGB(255, 220, 0),
        WHITE  = Color3.fromRGB(255, 255, 255),
        BLACK  = Color3.fromRGB(0, 0, 0),
    }

    local function corner(ui, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 15)
        c.Parent = ui
    end

    local function stroke(ui, th, col)
        local s = Instance.new("UIStroke")
        s.Thickness = th or 3.2
        s.Color = col or THEME.GREEN
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = ui
        return s
    end

    ------------------------------------------------------------------------
    -- FLY & NOCLIP LOGIC
    ------------------------------------------------------------------------
    local isFlying = false
    local noclipConn = nil
    local currentIdx = 0 

    local Positions = {
        [1] = Vector3.new(200, -2.742, 0), [2] = Vector3.new(284, -2.742, 0),
        [3] = Vector3.new(398, -2.742, 0), [4] = Vector3.new(542, -2.742, 0),
        [5] = Vector3.new(756, -2.742, 0), [6] = Vector3.new(1074, -2.742, 0),
        [7] = Vector3.new(1546, -2.742, 0), [8] = Vector3.new(2247, -2.742, 0),
        [9] = Vector3.new(2602, -2.742, 0)
    }

    local function stopNoclip()
        if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
        if LocalPlayer.Character then
            for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
    end

    local function startNoclip()
        if noclipConn then noclipConn:Disconnect() end
        noclipConn = RunService.Stepped:Connect(function()
            if isFlying and LocalPlayer.Character then
                for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end)
    end

    local function flyTo(pos)
        if not pos or isFlying then return end 
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            isFlying = true
            startNoclip()
            local baseSpeed = 400 * math.max(0.1, config.FlySpeed)
            local duration = (hrp.Position - pos).Magnitude / baseSpeed
            local tw = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(pos)})
            tw:Play()
            tw.Completed:Connect(function()
                isFlying = false
                stopNoclip() 
            end)
        end
    end

    ------------------------------------------------------------------------
    -- EXTERNAL UI
    ------------------------------------------------------------------------
    local oldControl = LocalPlayer.PlayerGui:FindFirstChild("UFO_Move_Control_V10")
    if oldControl then oldControl:Destroy() end

    local sg = Instance.new("ScreenGui", LocalPlayer.PlayerGui)
    sg.Name = "UFO_Move_Control_V10"
    sg.ResetOnSpawn = false

    local mainFrame = Instance.new("Frame", sg)
    mainFrame.Name = "MainDrag"
    mainFrame.Position = UDim2.new(0, config.Pos.X, 0, config.Pos.Y)
    mainFrame.Size = UDim2.new(0, 200, 0, 300)
    mainFrame.BackgroundTransparency = 1
    mainFrame.Visible = config.Enabled

    local function createBtn(name, text, pos)
        local b = Instance.new("TextButton", mainFrame)
        b.Name = name
        b.Size = UDim2.new(0, config.BtnSize, 0, config.BtnSize)
        b.Position = pos
        b.BackgroundColor3 = THEME.BLACK
        b.TextColor3 = THEME.WHITE
        b.Font = Enum.Font.GothamBold
        b.TextSize = config.BtnSize * 0.45
        b.Text = text
        b.AutoButtonColor = false
        corner(b, 15)
        stroke(b, 3.5, THEME.NEON_GREEN)
        return b
    end

    local btnRed    = createBtn("Btn_Red", "⬆️", UDim2.new(0, 0, 0, 0))
    local btnWarp   = createBtn("Btn_Warp", "🔄", UDim2.new(0, -(config.BtnSize + 15), 0, config.BtnSize + 15))
    local btnGreen  = createBtn("Btn_Green", "0", UDim2.new(0, 0, 0, config.BtnSize + 15))
    local btnYellow = createBtn("Btn_Yellow", "⚙️", UDim2.new(0, config.BtnSize + 15, 0, config.BtnSize + 15))
    local btnBlue   = createBtn("Btn_Blue", "⬇️", UDim2.new(0, 0, 0, (config.BtnSize + 15) * 2))

    local function refreshUI()
        local s = config.BtnSize
        local p = 15
        btnRed.Size, btnWarp.Size, btnGreen.Size, btnYellow.Size, btnBlue.Size = UDim2.fromOffset(s,s), UDim2.fromOffset(s,s), UDim2.fromOffset(s,s), UDim2.fromOffset(s,s), UDim2.fromOffset(s,s)
        btnRed.Position    = UDim2.new(0, 0, 0, 0)
        btnWarp.Position   = UDim2.new(0, -(s + p), 0, s + p)
        btnGreen.Position  = UDim2.new(0, 0, 0, s + p)
        btnYellow.Position = UDim2.new(0, s + p, 0, s + p)
        btnBlue.Position   = UDim2.new(0, 0, 0, (s + p) * 2)
        local ts = s * 0.45
        btnRed.TextSize, btnWarp.TextSize, btnGreen.TextSize, btnYellow.TextSize, btnBlue.TextSize = ts, ts, ts, ts, ts
    end

    -- ปุ่มจรวดจรวด 🚀: บินไปยังตำแหน่งหมายเลขปัจจุบัน (ไม่ใช่วาร์ป)
    btnWarp.MouseButton1Click:Connect(function()
        if editMode or isFlying then return end
        local targetPos = Positions[currentIdx]
        if targetPos then
            flyTo(targetPos)
        end
    end)

    local function resetToZero()
        currentIdx = 0
        btnGreen.Text = "0"
        isFlying = false
        stopNoclip()
    end

    LocalPlayer.CharacterAdded:Connect(resetToZero)

    local editMode, dragging, dragStart, startPos = false, false, nil, nil
    local function makeDraggable(b)
        b.InputBegan:Connect(function(input)
            if editMode and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                dragging = true; dragStart = input.Position; startPos = mainFrame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then 
                        dragging = false 
                        config.Pos = {X = mainFrame.AbsolutePosition.X, Y = mainFrame.AbsolutePosition.Y}
                        SaveSettings(config)
                    end
                end)
            end
        end)
    end
    makeDraggable(btnRed); makeDraggable(btnWarp); makeDraggable(btnGreen); makeDraggable(btnBlue); makeDraggable(btnYellow)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    btnYellow.MouseButton1Click:Connect(function()
        editMode = not editMode
        btnYellow.Text = editMode and "❌" or "⚙️"
        btnYellow.BackgroundColor3 = editMode and Color3.fromRGB(60, 0, 0) or THEME.BLACK
    end)

    btnRed.MouseButton1Click:Connect(function()
        if not isFlying and not editMode and currentIdx < 9 then
            currentIdx = currentIdx + 1; btnGreen.Text = tostring(currentIdx); flyTo(Positions[currentIdx])
        end
    end)

    btnBlue.MouseButton1Click:Connect(function()
        if not isFlying and not editMode and currentIdx > 0 then
            currentIdx = currentIdx - 1; btnGreen.Text = tostring(currentIdx)
            if currentIdx ~= 0 then flyTo(Positions[currentIdx]) else stopNoclip() end
        end
    end)

    ------------------------------------------------------------------------
    -- MODEL AAA2 SLIDER
    ------------------------------------------------------------------------
    local function createAAA2Slider(parent, title, defaultRel, callback)
        local row = Instance.new("Frame", parent)
        row.LayoutOrder = 0; row.Size = UDim2.new(1, -6, 0, 70); row.BackgroundColor3 = THEME.BLACK; corner(row, 12); stroke(row, 2.2, THEME.GREEN)
        local currentRel = defaultRel
        local visRel = defaultRel
        local sDragging, sMaybeDrag, sDownX = false, false, nil
        local label = Instance.new("TextLabel", row)
        label.BackgroundTransparency = 1; label.Position = UDim2.new(0, 16, 0, 4); label.Size = UDim2.new(1, -32, 0, 24)
        label.Font = Enum.Font.GothamBold; label.TextSize = 13; label.TextColor3 = THEME.WHITE
        label.TextXAlignment = Enum.TextXAlignment.Left; label.Text = title
        local bar = Instance.new("Frame", row)
        bar.Position = UDim2.new(0, 16, 0, 34); bar.Size = UDim2.new(1, -32, 0, 16); bar.BackgroundColor3 = THEME.BLACK; corner(bar, 8); stroke(bar, 1.8, THEME.GREEN)
        local fill = Instance.new("Frame", bar)
        fill.BackgroundColor3 = THEME.GREEN; fill.Size = UDim2.fromScale(currentRel, 1); corner(fill, 8)
        local knobBtn = Instance.new("ImageButton", bar)
        knobBtn.Size = UDim2.fromOffset(16, 32); knobBtn.AnchorPoint = Vector2.new(0.5, 0.5); knobBtn.Position = UDim2.new(currentRel, 0, 0.5, 0); knobBtn.BackgroundColor3 = Color3.fromRGB(180,180,180); knobBtn.AutoButtonColor = false; corner(knobBtn, 4); stroke(knobBtn, 1.2, THEME.WHITE)
        local centerVal = Instance.new("TextLabel", bar)
        centerVal.BackgroundTransparency = 1; centerVal.Size = UDim2.fromScale(1, 1); centerVal.Font = Enum.Font.GothamBlack; centerVal.TextSize = 16; centerVal.TextColor3 = THEME.WHITE; centerVal.TextStrokeTransparency = 0; centerVal.TextStrokeColor3 = Color3.new(0,0,0); centerVal.Text = math.floor(currentRel * 100) .. "%"
        local function sync(instant)
            visRel = instant and currentRel or (visRel + (currentRel - visRel) * 0.2)
            fill.Size = UDim2.fromScale(math.clamp(visRel, 0, 1), 1)
            knobBtn.Position = UDim2.new(math.clamp(visRel, 0, 1), 0, 0.5, 0)
            centerVal.Text = math.floor(currentRel * 100 + 0.5) .. "%"
        end
        local function update(px)
            local rel = math.clamp((px - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            currentRel = rel; callback(currentRel)
            if not sDragging then sync(true) end
        end
        bar.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then sMaybeDrag = true; sDownX = io.Position.X; scroll.ScrollingEnabled = false; update(io.Position.X) end end)
        knobBtn.InputBegan:Connect(function(io) if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then sMaybeDrag = true; sDownX = io.Position.X; scroll.ScrollingEnabled = false end end)
        UserInputService.InputChanged:Connect(function(io) if sMaybeDrag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then if math.abs(io.Position.X - sDownX) > 5 then sDragging = true end; if sDragging then update(io.Position.X) end end end)
        UserInputService.InputEnded:Connect(function(io) if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then sDragging = false; sMaybeDrag = false; scroll.ScrollingEnabled = true; SaveSettings(config) end end)
        RunService.RenderStepped:Connect(function() sync(false) end)
    end

    ------------------------------------------------------------------------
    -- MAIN HUB UI
    ------------------------------------------------------------------------
    local header = Instance.new("TextLabel", scroll)
    header.LayoutOrder = 0; header.Size = UDim2.new(1, 0, 0, 36); header.BackgroundTransparency = 1; header.Font = Enum.Font.GothamBold; header.TextSize = 16; header.TextColor3 = THEME.WHITE; header.TextXAlignment = Enum.TextXAlignment.Left; header.Text = "》》》Move System 📍《《《"
    local row1 = Instance.new("Frame", scroll)
    row1.LayoutOrder = 0; row1.Size = UDim2.new(1, -6, 0, 46); row1.BackgroundColor3 = THEME.BLACK; corner(row1, 12); stroke(row1, 2.2, THEME.GREEN)
    local lab1 = Instance.new("TextLabel", row1)
    lab1.Size = UDim2.new(1, -160, 1, 0); lab1.Position = UDim2.new(0, 16, 0, 0); lab1.BackgroundTransparency = 1; lab1.Font = Enum.Font.GothamBold; lab1.TextSize = 13; lab1.TextColor3 = THEME.WHITE; lab1.Text = "Enable Move Position"; lab1.TextXAlignment = Enum.TextXAlignment.Left
    local sw = Instance.new("Frame", row1)
    sw.Size = UDim2.fromOffset(52, 26); sw.Position = UDim2.new(1, -12, 0.5, 0); sw.AnchorPoint = Vector2.new(1, 0.5); sw.BackgroundColor3 = THEME.BLACK; corner(sw, 13)
    local swStroke = stroke(sw, 1.8, config.Enabled and THEME.GREEN or THEME.RED)
    local knob = Instance.new("Frame", sw)
    knob.Size = UDim2.fromOffset(22, 22); knob.BackgroundColor3 = THEME.WHITE; corner(knob, 11); knob.Position = config.Enabled and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)
    local function updateSwitch(on)
        swStroke.Color = on and THEME.GREEN or THEME.RED
        TweenService:Create(knob, TweenInfo.new(0.1), {Position = on and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)}):Play()
        mainFrame.Visible = on
    end
    local swBtn = Instance.new("TextButton", sw)
    swBtn.Size = UDim2.fromScale(1, 1); swBtn.BackgroundTransparency = 1; swBtn.Text = ""; swBtn.MouseButton1Click:Connect(function() config.Enabled = not mainFrame.Visible; updateSwitch(config.Enabled); SaveSettings(config) end)

    createAAA2Slider(scroll, "Adjust Fly Sensitivity", (config.FlySpeed - 0.1) / 4.9, function(rel) config.FlySpeed = 0.1 + (rel * 4.9) end)
    createAAA2Slider(scroll, "Adjust Button Scale", (config.BtnSize - 40) / 60, function(rel) config.BtnSize = 40 + (rel * 60); refreshUI() end)

    updateSwitch(config.Enabled); refreshUI()
end)
--===== UFO HUB X • Upgrade System (Full Auto: Rebirth & Base) – MODEL A V1 + AAA2 =====
-- Feature 1: Auto Rebirth (InvokeServer)
-- Feature 2: Rebirth Speed Slider (AAA2)
-- Feature 3: Auto Upgrade Base (FireServer)
-- Feature 4: Adjust Base Upgrade Speed (AAA2)
-- UI Model: A V1 (Green Glow Border) / AAA2 (Smooth Slider)
-- LayoutOrder: 0

registerRight("Home", function(scroll)
    local TweenService = game:GetService("TweenService")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    ------------------------------------------------------------------------
    -- AA1 SAVE SYSTEM
    ------------------------------------------------------------------------
    local SAVE = (getgenv and getgenv().UFOX_SAVE) or {
        get = function(_, _, d) return d end,
        set = function() end
    }
    local SCOPE = ("UFO_UpgradeSystemV4/%d/%d"):format(tonumber(game.GameId) or 0, tonumber(game.PlaceId) or 0)
    local function K(k) return SCOPE .. "/" .. k end
    local function SaveGet(key, default)
        local ok, v = pcall(function() return SAVE.get(K(key), default) end)
        return ok and v or default
    end
    local function SaveSet(key, value) pcall(function() SAVE.set(K(key), value) end) end

    ------------------------------------------------------------------------
    -- THEME & HELPERS
    ------------------------------------------------------------------------
    local THEME = {
        GREEN = Color3.fromRGB(25, 255, 125),
        RED   = Color3.fromRGB(255, 40, 40),
        WHITE = Color3.fromRGB(255, 255, 255),
        BLACK = Color3.fromRGB(0, 0, 0),
    }

    local function corner(ui, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 12)
        c.Parent = ui
    end

    local function stroke(ui, th, col)
        local s = Instance.new("UIStroke")
        s.Thickness = th or 2.2
        s.Color = col or THEME.GREEN
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = ui
        return s
    end

    local function tween(o, p, d)
        TweenService:Create(o, TweenInfo.new(d or 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), p):Play()
    end

    ------------------------------------------------------------------------
    -- LOGIC: AUTO SYSTEMS
    ------------------------------------------------------------------------
    local autoRebirthOn = SaveGet("autoRebirthOn", false)
    local rebirthSpeed = SaveGet("rebirthSpeed", 0.5)
    local autoBaseOn = SaveGet("autoBaseOn", false)
    local baseSpeed = SaveGet("baseSpeed", 0.5)

    -- Loop for Rebirth
    task.spawn(function()
        while true do
            if autoRebirthOn then
                pcall(function()
                    local remote = ReplicatedStorage:WaitForChild("RemoteFunctions", 5):WaitForChild("Rebirth", 5)
                    if remote then remote:InvokeServer() end
                end)
            end
            task.wait(rebirthSpeed)
        end
    end)

    -- Loop for Base Upgrade
    task.spawn(function()
        while true do
            if autoBaseOn then
                pcall(function()
                    local remote = ReplicatedStorage:WaitForChild("Packages", 5):WaitForChild("Net", 5):WaitForChild("RE/Plot.UpgradeBase", 5)
                    if remote then remote:FireServer() end
                end)
            end
            task.wait(baseSpeed)
        end
    end)

    ------------------------------------------------------------------------
    -- AAA2 SLIDER COMPONENT
    ------------------------------------------------------------------------
    local function createAAA2Slider(parent, title, min, max, default, callback)
        local row = Instance.new("Frame", parent)
        row.LayoutOrder = 0
        row.Size = UDim2.new(1, -6, 0, 70)
        row.BackgroundColor3 = THEME.BLACK
        corner(row, 12)
        stroke(row, 2.2, THEME.GREEN)
        
        local currentVal = default
        local rel = (default - min) / (max - min)
        local visRel = rel
        local sDragging, sMaybeDrag, sDownX = false, false, nil

        local label = Instance.new("TextLabel", row)
        label.BackgroundTransparency = 1; label.Position = UDim2.new(0, 16, 0, 4); label.Size = UDim2.new(1, -32, 0, 24)
        label.Font = Enum.Font.GothamBold; label.TextSize = 13; label.TextColor3 = THEME.WHITE
        label.TextXAlignment = Enum.TextXAlignment.Left; label.Text = title

        local bar = Instance.new("Frame", row)
        bar.Position = UDim2.new(0, 16, 0, 34); bar.Size = UDim2.new(1, -32, 0, 16); bar.BackgroundColor3 = THEME.BLACK
        corner(bar, 8); stroke(bar, 1.8, THEME.GREEN)

        local fill = Instance.new("Frame", bar)
        fill.BackgroundColor3 = THEME.GREEN; fill.Size = UDim2.fromScale(rel, 1); corner(fill, 8)

        local knobBtn = Instance.new("ImageButton", bar)
        knobBtn.Size = UDim2.fromOffset(16, 32); knobBtn.AnchorPoint = Vector2.new(0.5, 0.5)
        knobBtn.Position = UDim2.new(rel, 0, 0.5, 0); knobBtn.BackgroundColor3 = Color3.fromRGB(180,180,180); knobBtn.AutoButtonColor = false
        corner(knobBtn, 4); stroke(knobBtn, 1.2, THEME.WHITE)

        local centerVal = Instance.new("TextLabel", bar)
        centerVal.BackgroundTransparency = 1; centerVal.Size = UDim2.fromScale(1, 1)
        centerVal.Font = Enum.Font.GothamBlack; centerVal.TextSize = 14; centerVal.TextColor3 = THEME.WHITE
        centerVal.TextStrokeTransparency = 0; centerVal.TextStrokeColor3 = Color3.new(0,0,0)
        centerVal.Text = string.format("%.2f s", currentVal)

        local function sync(instant)
            visRel = instant and rel or (visRel + (rel - visRel) * 0.2)
            fill.Size = UDim2.fromScale(math.clamp(visRel, 0, 1), 1)
            knobBtn.Position = UDim2.new(math.clamp(visRel, 0, 1), 0, 0.5, 0)
            centerVal.Text = string.format("%.2f s", currentVal)
        end

        local function update(px)
            rel = math.clamp((px - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            currentVal = min + (rel * (max - min))
            callback(currentVal)
            if not sDragging then sync(true) end
        end

        bar.InputBegan:Connect(function(io)
            if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
                sMaybeDrag = true; sDownX = io.Position.X; scroll.ScrollingEnabled = false; update(io.Position.X)
            end
        end)
        knobBtn.InputBegan:Connect(function(io)
            if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
                sMaybeDrag = true; sDownX = io.Position.X; scroll.ScrollingEnabled = false
            end
        end)
        UserInputService.InputChanged:Connect(function(io)
            if sMaybeDrag and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
                if math.abs(io.Position.X - sDownX) > 5 then sDragging = true end
                if sDragging then update(io.Position.X) end
            end
        end)
        UserInputService.InputEnded:Connect(function(io)
            if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
                sDragging = false; sMaybeDrag = false; scroll.ScrollingEnabled = true
            end
        end)
        RunService.RenderStepped:Connect(function() sync(false) end)
    end

    ------------------------------------------------------------------------
    -- UI CONSTRUCTION
    ------------------------------------------------------------------------
    
    local header = Instance.new("TextLabel", scroll)
    header.LayoutOrder = 0; header.BackgroundTransparency = 1; header.Size = UDim2.new(1, 0, 0, 36)
    header.Font = Enum.Font.GothamBold; header.TextSize = 16; header.TextColor3 = THEME.WHITE
    header.TextXAlignment = Enum.TextXAlignment.Left; header.Text = "》》》  Upgrade Auto ⚡《《《"

    -- รายการที่ 1: rebirth auto
    local row1 = Instance.new("Frame", scroll)
    row1.LayoutOrder = 0; row1.Size = UDim2.new(1, -6, 0, 46); row1.BackgroundColor3 = THEME.BLACK
    corner(row1, 12); stroke(row1, 2.2, THEME.GREEN)

    local lab1 = Instance.new("TextLabel", row1)
    lab1.BackgroundTransparency = 1; lab1.Size = UDim2.new(1, -160, 1, 0); lab1.Position = UDim2.new(0, 16, 0, 0)
    lab1.Font = Enum.Font.GothamBold; lab1.TextSize = 13; lab1.TextColor3 = THEME.WHITE
    lab1.TextXAlignment = Enum.TextXAlignment.Left; lab1.Text = "Rebirth Auto"

    local sw1 = Instance.new("Frame", row1)
    sw1.AnchorPoint = Vector2.new(1, 0.5); sw1.Position = UDim2.new(1, -12, 0.5, 0); sw1.Size = UDim2.fromOffset(52, 26); sw1.BackgroundColor3 = THEME.BLACK
    corner(sw1, 13); local swStroke1 = stroke(sw1, 1.8, THEME.RED)
    local knob1 = Instance.new("Frame", sw1)
    knob1.Size = UDim2.fromOffset(22, 22); knob1.BackgroundColor3 = THEME.WHITE; knob1.Position = UDim2.new(0, 2, 0.5, -11); corner(knob1, 11)

    local function updateUI1(on)
        swStroke1.Color = on and THEME.GREEN or THEME.RED
        tween(knob1, { Position = UDim2.new(on and 1 or 0, on and -24 or 2, 0.5, -11) }, 0.08)
    end
    
    local btn1 = Instance.new("TextButton", sw1)
    btn1.BackgroundTransparency = 1; btn1.Size = UDim2.fromScale(1, 1); btn1.Text = ""
    btn1.MouseButton1Click:Connect(function()
        autoRebirthOn = not autoRebirthOn; SaveSet("autoRebirthOn", autoRebirthOn); updateUI1(autoRebirthOn)
    end)
    updateUI1(autoRebirthOn)

    -- รายการที่ 2: Adjust Rebirth Speed
    createAAA2Slider(scroll, "Adjust Rebirth Speed", 0.1, 5.0, rebirthSpeed, function(val)
        rebirthSpeed = val; SaveSet("rebirthSpeed", val)
    end)

    -- รายการที่ 3: upgrade base auto
    local row3 = Instance.new("Frame", scroll)
    row3.LayoutOrder = 0; row3.Size = UDim2.new(1, -6, 0, 46); row3.BackgroundColor3 = THEME.BLACK
    corner(row3, 12); stroke(row3, 2.2, THEME.GREEN)

    local lab3 = Instance.new("TextLabel", row3)
    lab3.BackgroundTransparency = 1; lab3.Size = UDim2.new(1, -160, 1, 0); lab3.Position = UDim2.new(0, 16, 0, 0)
    lab3.Font = Enum.Font.GothamBold; lab3.TextSize = 13; lab3.TextColor3 = THEME.WHITE
    lab3.TextXAlignment = Enum.TextXAlignment.Left; lab3.Text = "Upgrade Base Auto"

    local sw3 = Instance.new("Frame", row3)
    sw3.AnchorPoint = Vector2.new(1, 0.5); sw3.Position = UDim2.new(1, -12, 0.5, 0); sw3.Size = UDim2.fromOffset(52, 26); sw3.BackgroundColor3 = THEME.BLACK
    corner(sw3, 13); local swStroke3 = stroke(sw3, 1.8, THEME.RED)
    local knob3 = Instance.new("Frame", sw3)
    knob3.Size = UDim2.fromOffset(22, 22); knob3.BackgroundColor3 = THEME.WHITE; knob3.Position = UDim2.new(0, 2, 0.5, -11); corner(knob3, 11)

    local function updateUI3(on)
        swStroke3.Color = on and THEME.GREEN or THEME.RED
        tween(knob3, { Position = UDim2.new(on and 1 or 0, on and -24 or 2, 0.5, -11) }, 0.08)
    end
    
    local btn3 = Instance.new("TextButton", sw3)
    btn3.BackgroundTransparency = 1; btn3.Size = UDim2.fromScale(1, 1); btn3.Text = ""
    btn3.MouseButton1Click:Connect(function()
        autoBaseOn = not autoBaseOn; SaveSet("autoBaseOn", autoBaseOn); updateUI3(autoBaseOn)
    end)
    updateUI3(autoBaseOn)

    -- รายการที่ 4: Adjust Base Upgrade Speed
    createAAA2Slider(scroll, "Adjust Base Upgrade Speed", 0.1, 5.0, baseSpeed, function(val)
        baseSpeed = val; SaveSet("baseSpeed", val)
    end)

end)
--===== UFO HUB X • Auto Collect System [FULL UNABRIDGED STABLE VER] =====
-- [RULE] : NEVER SHORTEN THE SCRIPT (FULL LENGTH)
-- [RULE] : SYSTEM MUST BE 100% ACCURATE TO PREVIOUS STABLE MODEL
-- [RULE] : START AT 5% DEFAULT
-- [RULE] : AAA1 SAVE SYSTEM INTEGRATED

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local lp = Players.LocalPlayer

------------------------------------------------------------------
-- [ AAA1 SAVE SYSTEM - DEFINED FULLY ]
------------------------------------------------------------------
local function SaveGet(key, default)
    if getgenv and getgenv().UFOX_SAVE and getgenv().UFOX_SAVE.get then
        -- บันทึกข้อมูลแยกตาม PlaceId ในโฟลเดอร์ AAA1
        return getgenv().UFOX_SAVE.get("AAA1/UFOX/" .. game.PlaceId .. "/" .. key, default)
    end
    return default
end

local function SaveSet(key, val)
    if getgenv and getgenv().UFOX_SAVE and getgenv().UFOX_SAVE.set then
        pcall(function() 
            getgenv().UFOX_SAVE.set("AAA1/UFOX/" .. game.PlaceId .. "/" .. key, val) 
        end)
    end
end

-- โหลดค่า State จาก AAA1
_G.UFOX_AAA1 = _G.UFOX_AAA1 or {}
_G.UFOX_AAA1["AutoCollect"] = _G.UFOX_AAA1["AutoCollect"] or {
    Enabled = SaveGet("Enabled", false),
    Selected = SaveGet("Selected", {["All"] = true}),
    SpeedRel = SaveGet("SpeedRel", 0.05), -- ตั้งค่าเริ่มต้นที่ 5% (0.05) ตามสั่ง
}
local STATE = _G.UFOX_AAA1["AutoCollect"]

------------------------------------------------------------------
-- [ PLOT DETECTOR - FULL SYSTEM ]
------------------------------------------------------------------
local function getMyPlotID()
    local foundID = nil
    local bases = Workspace:FindFirstChild("Bases")
    if bases then
        for _, baseFolder in ipairs(bases:GetChildren()) do
            local title = baseFolder:FindFirstChild("Title")
            if title then
                local titleGui = title:FindFirstChild("TitleGui")
                if titleGui then
                    local frame = titleGui:FindFirstChild("Frame")
                    if frame then
                        local playerNameLabel = frame:FindFirstChild("PlayerName")
                        if playerNameLabel and (playerNameLabel.Text == lp.Name or playerNameLabel.Text == lp.DisplayName) then
                            foundID = title.Parent.Name 
                            break
                        end
                    end
                end
            end
        end
    end
    -- Fallback GUID if not found
    return foundID or "7aa9fb6a-ebb4-40b5-af4d-bbf68d798324"
end

-- ระบบเก็บเงินวนลูป (Looping System)
task.spawn(function()
    while true do
        if STATE.Enabled then
            local myID = getMyPlotID()
            -- ตรวจสอบรูปแบบ GUID ให้ถูกต้อง
            if not myID:find("{") then myID = "{" .. myID .. "}" end
            
            local rf = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net"):WaitForChild("RF/Plot.PlotAction")
            
            -- คำนวณความเร็ว: 0% = 1.0s, 100% = 0.01s
            local waitTime = 1.0 - (STATE.SpeedRel * 0.99)
            
            if STATE.Selected["All"] then
                -- เก็บทุกช่องพร้อมกัน (30 ช่อง)
                for i = 1, 30 do
                    task.spawn(function() 
                        pcall(function() 
                            rf:InvokeServer("Collect Money", myID, tostring(i)) 
                        end) 
                    end)
                end
            else
                -- เก็บเฉพาะช่องที่เลือก
                for slot, active in pairs(STATE.Selected) do
                    if not STATE.Enabled or STATE.Selected["All"] then break end
                    if slot ~= "All" and active then
                        task.spawn(function() 
                            pcall(function() 
                                rf:InvokeServer("Collect Money", myID, tostring(slot)) 
                            end) 
                        end)
                    end
                end
            end
            task.wait(math.max(waitTime, 0.01))
        else
            task.wait(0.5)
        end
    end
end)

------------------------------------------------------------------
-- [ UI REGISTRATION SYSTEM - NO SHORTENING ]
------------------------------------------------------------------
registerRight("Home", function(scroll)
    -- Color Theme
    local THEME = {
        GREEN = Color3.fromRGB(25,255,125),
        GREEN_DARK = Color3.fromRGB(0,120,60),
        WHITE = Color3.fromRGB(255,255,255),
        BLACK = Color3.fromRGB(0,0,0),
        DARK = Color3.fromRGB(15,15,15),
        GREY = Color3.fromRGB(200,200,205),
        RED = Color3.fromRGB(255,40,40)
    }

    local function corner(ui, r) 
        local c = Instance.new("UICorner", ui)
        c.CornerRadius = UDim.new(0, r or 12) 
        return c
    end
    
    local function stroke(ui, th, col)
        local s = Instance.new("UIStroke", ui)
        s.Thickness = th or 2.2
        s.Color = col or THEME.GREEN
        s.ApplyStrokeMode = "Border"
        return s
    end

    -- ล้าง UI เก่าถ้ามีค้างอยู่
    for _, name in ipairs({"VA2_Header","VA2_Row1","VA2_Row2","Row_Sens","VA2_OptionsPanel"}) do
        local old = scroll:FindFirstChild(name) or scroll.Parent:FindFirstChild(name)
        if old then old:Destroy() end
    end

    -- ตั้งค่า Scroll
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    local vlist = scroll:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout", scroll)
    vlist.Padding = UDim.new(0, 12)
    vlist.SortOrder = "LayoutOrder"

    -- [1] Header
    local header = Instance.new("TextLabel", scroll)
    header.Name = "VA2_Header"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, 30)
    header.Font = "GothamBold"
    header.TextSize = 16
    header.TextColor3 = THEME.WHITE
    header.TextXAlignment = "Left"
    header.Text = "Auto Collect System"
    header.LayoutOrder = 1

    -- [2] Row 1: Main Toggle
    local row1 = Instance.new("Frame", scroll)
    row1.Name = "VA2_Row1"
    row1.Size = UDim2.new(1, -6, 0, 46)
    row1.BackgroundColor3 = THEME.BLACK
    row1.LayoutOrder = 2
    corner(row1)
    stroke(row1)

    local lab1 = Instance.new("TextLabel", row1)
    lab1.Name = "TitleLabel"
    lab1.BackgroundTransparency = 1
    lab1.Size = UDim2.new(0, 200, 1, 0)
    lab1.Position = UDim2.new(0, 16, 0, 0)
    lab1.Font = "GothamBold"
    lab1.TextSize = 13
    lab1.TextColor3 = THEME.WHITE
    lab1.TextXAlignment = "Left"
    lab1.Text = "Auto Collect Money"

    local sw = Instance.new("Frame", row1)
    sw.Name = "Switch"
    sw.AnchorPoint = Vector2.new(1, 0.5)
    sw.Position = UDim2.new(1, -16, 0.5, 0)
    sw.Size = UDim2.new(0, 52, 0, 26)
    sw.BackgroundColor3 = THEME.BLACK
    corner(sw, 13)
    local swStr = stroke(sw, 1.8, THEME.RED)

    local knob = Instance.new("Frame", sw)
    knob.Name = "Knob"
    knob.Size = UDim2.new(0, 22, 0, 22)
    knob.Position = UDim2.new(0, 2, 0.5, -11)
    knob.BackgroundColor3 = THEME.WHITE
    corner(knob, 11)

    local function updateSw(on)
        swStr.Color = on and THEME.GREEN or THEME.RED
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = on and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)
        }):Play()
    end

    local swBtn = Instance.new("TextButton", sw)
    swBtn.Size = UDim2.fromScale(1, 1)
    swBtn.BackgroundTransparency = 1
    swBtn.Text = ""
    swBtn.MouseButton1Click:Connect(function()
        STATE.Enabled = not STATE.Enabled
        SaveSet("Enabled", STATE.Enabled)
        updateSw(STATE.Enabled)
    end)
    updateSw(STATE.Enabled)

    -- [3] Row 2: Select Slots (Multi-Selection Panel)
    local row2 = Instance.new("Frame", scroll)
    row2.Name = "VA2_Row2"
    row2.Size = UDim2.new(1, -6, 0, 46)
    row2.BackgroundColor3 = THEME.BLACK
    row2.LayoutOrder = 3
    corner(row2)
    stroke(row2)

    local lab2 = Instance.new("TextLabel", row2)
    lab2.BackgroundTransparency = 1
    lab2.Size = UDim2.new(0, 200, 1, 0)
    lab2.Position = UDim2.new(0, 16, 0, 0)
    lab2.Font = "GothamBold"
    lab2.TextSize = 13
    lab2.TextColor3 = THEME.WHITE
    lab2.TextXAlignment = "Left"
    lab2.Text = "Select Target Slots"

    local selectBtn = Instance.new("TextButton", row2)
    selectBtn.AnchorPoint = Vector2.new(1, 0.5)
    selectBtn.Position = UDim2.new(1, -16, 0.5, 0)
    selectBtn.Size = UDim2.new(0, 180, 0, 28)
    selectBtn.BackgroundColor3 = THEME.BLACK
    selectBtn.Text = "🔍 Select Options"
    selectBtn.Font = "GothamBold"
    selectBtn.TextSize = 13
    selectBtn.TextColor3 = THEME.WHITE
    corner(selectBtn, 8)
    local selectStroke = stroke(selectBtn, 1.8, THEME.GREEN_DARK)
    selectStroke.Transparency = 0.4

    local optionsPanel, inputConn, opened = nil, nil, false
    
    local function closePanel()
        if optionsPanel then optionsPanel:Destroy() optionsPanel = nil end
        if inputConn then inputConn:Disconnect() inputConn = nil end
        opened = false
        selectStroke.Color = THEME.GREEN_DARK
        selectStroke.Transparency = 0.4
    end

    selectBtn.MouseButton1Click:Connect(function()
        if opened then closePanel() return end
        opened = true
        selectStroke.Color = THEME.GREEN
        selectStroke.Transparency = 0

        -- สร้างหน้าต่างรายการ (Options Panel)
        local mainUI = scroll.Parent
        optionsPanel = Instance.new("Frame", mainUI)
        optionsPanel.Name = "VA2_OptionsPanel"
        optionsPanel.BackgroundColor3 = THEME.BLACK
        optionsPanel.Position = UDim2.new(0.65, 0, 0.05, 0)
        optionsPanel.Size = UDim2.new(0.33, 0, 0.9, 0)
        optionsPanel.ZIndex = 100
        corner(optionsPanel)
        stroke(optionsPanel, 2, THEME.GREEN)

        local scroller = Instance.new("ScrollingFrame", optionsPanel)
        scroller.Size = UDim2.new(1, -10, 1, -20)
        scroller.Position = UDim2.new(0, 5, 0, 10)
        scroller.BackgroundTransparency = 1
        scroller.ScrollBarThickness = 3
        scroller.ScrollBarImageColor3 = THEME.GREEN
        scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroller.CanvasSize = UDim2.new(0,0,0,0)

        local llist = Instance.new("UIListLayout", scroller)
        llist.Padding = UDim.new(0, 6)
        llist.HorizontalAlignment = Enum.HorizontalAlignment.Center

        local allButtons = {}
        
        local function makeItem(id, txt)
            local b = Instance.new("TextButton", scroller)
            b.Size = UDim2.new(0.92, 0, 0, 32)
            b.BackgroundColor3 = THEME.BLACK
            b.Font = "GothamBold"
            b.TextSize = 11
            b.TextColor3 = THEME.WHITE
            b.Text = txt
            corner(b, 6)
            local st = stroke(b, 1.5, THEME.GREEN_DARK)
            st.Transparency = 0.5

            local function refresh()
                local active = (id == "All" and STATE.Selected["All"]) or (not STATE.Selected["All"] and STATE.Selected[tostring(id)])
                st.Color = active and THEME.GREEN or THEME.GREEN_DARK
                st.Transparency = active and 0 or 0.5
            end

            b.MouseButton1Click:Connect(function()
                if id == "All" then
                    STATE.Selected = {["All"] = not STATE.Selected["All"]}
                else
                    STATE.Selected["All"] = false
                    STATE.Selected[tostring(id)] = not STATE.Selected[tostring(id)]
                end
                SaveSet("Selected", STATE.Selected)
                for _, btnData in ipairs(allButtons) do btnData.ref() end
            end)

            refresh()
            table.insert(allButtons, {ref = refresh})
        end

        -- สร้างรายการ 1-30 ครบถ้วน
        makeItem("All", "Collect All Money")
        for i = 1, 30 do
            makeItem(i, "Collect Money Slot " .. i)
        end

        -- ปิดเมื่อกดข้างนอก
        inputConn = UserInputService.InputBegan:Connect(function(input)
            if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
                local p = optionsPanel.AbsolutePosition
                local s = optionsPanel.AbsoluteSize
                local m = input.Position
                if not (m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y) then
                    closePanel()
                end
            end
        end)
    end)

    -- [4] Row 3: Metal Speed Slider (STRICT INPUT LOCK)
    local sRow = Instance.new("Frame", scroll)
    sRow.Name = "Row_Sens"
    sRow.Size = UDim2.new(1, -6, 0, 70)
    sRow.BackgroundColor3 = THEME.BLACK
    sRow.LayoutOrder = 4
    corner(sRow, 12)
    stroke(sRow, 2.2, THEME.GREEN)

    local sLab = Instance.new("TextLabel", sRow)
    sLab.BackgroundTransparency = 1
    sLab.Position = UDim2.new(0, 16, 0, 4)
    sLab.Size = UDim2.new(1, -32, 0, 24)
    sLab.Font = "GothamBold"
    sLab.TextSize = 13
    sLab.TextColor3 = THEME.WHITE
    sLab.TextXAlignment = "Left"
    sLab.Text = "Adjust Collect Speed"

    local bar = Instance.new("Frame", sRow)
    bar.Name = "SliderBar"
    bar.Position = UDim2.new(0, 16, 0, 34)
    bar.Size = UDim2.new(1, -32, 0, 16)
    bar.BackgroundColor3 = THEME.BLACK
    bar.Active = true
    corner(bar, 8)
    stroke(bar, 1.8, THEME.GREEN)

    local fill = Instance.new("Frame", bar)
    fill.BackgroundColor3 = THEME.GREEN
    fill.Size = UDim2.fromScale(STATE.SpeedRel, 1)
    corner(fill, 8)

    local knob = Instance.new("ImageButton", bar)
    knob.Name = "Knob"
    knob.AutoButtonColor = false
    knob.BackgroundColor3 = THEME.GREY
    knob.Size = UDim2.fromOffset(16, 32)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(STATE.SpeedRel, 0, 0.5, 0)
    knob.ZIndex = 5
    corner(knob, 4)
    stroke(knob, 1.2, THEME.WHITE)

    local valLab = Instance.new("TextLabel", bar)
    valLab.BackgroundTransparency = 1
    valLab.Size = UDim2.fromScale(1, 1)
    valLab.Font = "GothamBlack"
    valLab.TextSize = 16
    valLab.TextColor3 = THEME.WHITE
    valLab.TextStrokeTransparency = 0.5
    valLab.Text = math.floor(STATE.SpeedRel * 100 + 0.5) .. "%"

    local dragging = false
    local function updateSlider(input)
        local barPos = bar.AbsolutePosition
        local barSize = bar.AbsoluteSize
        local rel = math.clamp((input.Position.X - barPos.X) / barSize.X, 0, 1)
        STATE.SpeedRel = rel
        SaveSet("SpeedRel", rel)
        fill.Size = UDim2.fromScale(rel, 1)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        valLab.Text = math.floor(rel * 100 + 0.5) .. "%"
    end

    -- ป้องกัน Slider เลื่อนเอง (Locking System)
    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            scroll.ScrollingEnabled = false -- ล็อคหน้าจอไม่ให้เลื่อนตาม
        end
    end)

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            scroll.ScrollingEnabled = false
            updateSlider(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            scroll.ScrollingEnabled = true -- ปลดล็อคหน้าจอ
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateSlider(input)
        end
    end)
end)
--===== UFO HUB X • SETTINGS — Smoother 🚀 (A V1 • fixed 3 rows) + Runner Save (per-map) + AA1 =====
registerRight("Settings", function(scroll)
    local TweenService = game:GetService("TweenService")
    local Lighting     = game:GetService("Lighting")
    local Players      = game:GetService("Players")
    local Http         = game:GetService("HttpService")
    local MPS          = game:GetService("MarketplaceService")
    local lp           = Players.LocalPlayer

    --=================== PER-MAP SAVE (file: UFO HUB X/<PlaceId - Name>.json; fallback RAM) ===================
    local function safePlaceName()
        local ok,info = pcall(function() return MPS:GetProductInfo(game.PlaceId) end)
        local n = (ok and info and info.Name) or ("Place_"..tostring(game.PlaceId))
        return n:gsub("[^%w%-%._ ]","_")
    end
    local SAVE_DIR  = "UFO HUB X"
    local SAVE_FILE = SAVE_DIR .. "/" .. tostring(game.PlaceId) .. " - " .. safePlaceName() .. ".json"
    local hasFS = (typeof(isfolder)=="function" and typeof(makefolder)=="function"
                and typeof(readfile)=="function" and typeof(writefile)=="function")
    if hasFS and not isfolder(SAVE_DIR) then pcall(makefolder, SAVE_DIR) end
    getgenv().UFOX_RAM = getgenv().UFOX_RAM or {}
    local RAM = getgenv().UFOX_RAM

    local function loadSave()
        if hasFS and pcall(function() return readfile(SAVE_FILE) end) then
            local ok, data = pcall(function() return Http:JSONDecode(readfile(SAVE_FILE)) end)
            if ok and type(data)=="table" then return data end
        end
        return RAM[SAVE_FILE] or {}
    end
    local function writeSave(t)
        t = t or {}
        if hasFS then pcall(function() writefile(SAVE_FILE, Http:JSONEncode(t)) end) end
        RAM[SAVE_FILE] = t
    end
    local function getSave(path, default)
        local cur = loadSave()
        for seg in string.gmatch(path, "[^%.]+") do cur = (type(cur)=="table") and cur[seg] or nil end
        return (cur==nil) and default or cur
    end
    local function setSave(path, value)
        local data, p, keys = loadSave(), nil, {}
        for seg in string.gmatch(path, "[^%.]+") do table.insert(keys, seg) end
        p = data
        for i=1,#keys-1 do local k=keys[i]; if type(p[k])~="table" then p[k] = {} end; p = p[k] end
        p[keys[#keys]] = value
        writeSave(data)
    end
    --==========================================================================================================

    -- THEME (A V1)
    local THEME = {
        GREEN = Color3.fromRGB(25,255,125),
        WHITE = Color3.fromRGB(255,255,255),
        BLACK = Color3.fromRGB(0,0,0),
        TEXT  = Color3.fromRGB(255,255,255),
        RED   = Color3.fromRGB(255,40,40),
    }
    local function corner(ui,r) local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 12) c.Parent=ui end
    local function stroke(ui,th,col) local s=Instance.new("UIStroke") s.Thickness=th or 2.2 s.Color=col or THEME.GREEN s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border s.Parent=ui end
    local function tween(o,p) TweenService:Create(o,TweenInfo.new(0.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),p):Play() end

    -- Ensure ListLayout
    local list = scroll:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout", scroll)
    list.Padding = UDim.new(0,12); list.SortOrder = Enum.SortOrder.LayoutOrder
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    -- STATE
    _G.UFOX_SMOOTH = _G.UFOX_SMOOTH or { mode=0, plastic=false, _snap={}, _pp={} }
    local S = _G.UFOX_SMOOTH

    -- ===== restore from SAVE =====
    S.mode    = getSave("Settings.Smoother.Mode",    S.mode)      -- 0/1/2
    S.plastic = getSave("Settings.Smoother.Plastic", S.plastic)   -- boolean

    -- Header
    local head = scroll:FindFirstChild("A1_Header") or Instance.new("TextLabel", scroll)
    head.Name="A1_Header"; head.BackgroundTransparency=1; head.Size=UDim2.new(1,0,0,36)
    head.Font=Enum.Font.GothamBold; head.TextSize=16; head.TextColor3=THEME.TEXT
    head.TextXAlignment=Enum.TextXAlignment.Left; head.Text="》》》Smoothness Settings 🚀《《《"; head.LayoutOrder = 10

    -- Remove any old rows
    for _,n in ipairs({"A1_Reduce","A1_Remove","A1_Plastic"}) do local old=scroll:FindFirstChild(n); if old then old:Destroy() end end

    -- Row factory
    local function makeRow(name, label, order, onToggle)
        local row = Instance.new("Frame", scroll)
        row.Name=name; row.Size=UDim2.new(1,-6,0,46); row.BackgroundColor3=THEME.BLACK
        row.LayoutOrder=order; corner(row,12); stroke(row,2.2,THEME.GREEN)

        local lab=Instance.new("TextLabel", row)
        lab.BackgroundTransparency=1; lab.Size=UDim2.new(1,-160,1,0); lab.Position=UDim2.new(0,16,0,0)
        lab.Font=Enum.Font.GothamBold; lab.TextSize=13; lab.TextColor3=THEME.WHITE
        lab.TextXAlignment=Enum.TextXAlignment.Left; lab.Text=label

        local sw=Instance.new("Frame", row)
        sw.AnchorPoint=Vector2.new(1,0.5); sw.Position=UDim2.new(1,-12,0.5,0)
        sw.Size=UDim2.fromOffset(52,26); sw.BackgroundColor3=THEME.BLACK
        corner(sw,13)
        local swStroke=Instance.new("UIStroke", sw); swStroke.Thickness=1.8; swStroke.Color=THEME.RED

        local knob=Instance.new("Frame", sw)
        knob.Size=UDim2.fromOffset(22,22); knob.BackgroundColor3=THEME.WHITE
        knob.Position=UDim2.new(0,2,0.5,-11); corner(knob,11)

        local state=false
        local function setState(v)
            state=v
            swStroke.Color = v and THEME.GREEN or THEME.RED
            tween(knob, {Position=UDim2.new(v and 1 or 0, v and -24 or 2, 0.5, -11)})
            if onToggle then onToggle(v) end
        end
        local btn=Instance.new("TextButton", sw)
        btn.BackgroundTransparency=1; btn.Size=UDim2.fromScale(1,1); btn.Text=""
        btn.MouseButton1Click:Connect(function() setState(not state) end)

        return setState
    end

    -- ===== FX helpers (same as before) =====
    local FX = {ParticleEmitter=true, Trail=true, Beam=true, Smoke=true, Fire=true, Sparkles=true}
    local PP = {BloomEffect=true, ColorCorrectionEffect=true, DepthOfFieldEffect=true, SunRaysEffect=true, BlurEffect=true}

    local function capture(inst)
        if S._snap[inst] then return end
        local t={}; pcall(function()
            if inst:IsA("ParticleEmitter") then t.Rate=inst.Rate; t.Enabled=inst.Enabled
            elseif inst:IsA("Trail") then t.Enabled=inst.Enabled; t.Brightness=inst.Brightness
            elseif inst:IsA("Beam") then t.Enabled=inst.Enabled; t.Brightness=inst.Brightness
            elseif inst:IsA("Smoke") then t.Enabled=inst.Enabled; t.Opacity=inst.Opacity
            elseif inst:IsA("Fire") then t.Enabled=inst.Enabled; t.Heat=inst.Heat; t.Size=inst.Size
            elseif inst:IsA("Sparkles") then t.Enabled=inst.Enabled end
        end)
        S._snap[inst]=t
    end
    for _,d in ipairs(workspace:GetDescendants()) do if FX[d.ClassName] then capture(d) end end

    local function applyHalf()
        for i,t in pairs(S._snap) do if i.Parent then pcall(function()
            if i:IsA("ParticleEmitter") then i.Rate=(t.Rate or 10)*0.5
            elseif i:IsA("Trail") or i:IsA("Beam") then i.Brightness=(t.Brightness or 1)*0.5
            elseif i:IsA("Smoke") then i.Opacity=(t.Opacity or 1)*0.5
            elseif i:IsA("Fire") then i.Heat=(t.Heat or 5)*0.5; i.Size=(t.Size or 5)*0.7
            elseif i:IsA("Sparkles") then i.Enabled=false end
        end) end end
        for _,obj in ipairs(Lighting:GetChildren()) do
            if PP[obj.ClassName] then
                S._pp[obj]={Enabled=obj.Enabled, Intensity=obj.Intensity, Size=obj.Size}
                obj.Enabled=true; if obj.Intensity then obj.Intensity=(obj.Intensity or 1)*0.5 end
                if obj.ClassName=="BlurEffect" and obj.Size then obj.Size=math.floor((obj.Size or 0)*0.5) end
            end
        end
    end
    local function applyOff()
        for i,_ in pairs(S._snap) do if i.Parent then pcall(function() i.Enabled=false end) end end
        for _,obj in ipairs(Lighting:GetChildren()) do if PP[obj.ClassName] then obj.Enabled=false end end
    end
    local function restoreAll()
        for i,t in pairs(S._snap) do if i.Parent then for k,v in pairs(t) do pcall(function() i[k]=v end) end end end
        for obj,t in pairs(S._pp)   do if obj.Parent then for k,v in pairs(t) do pcall(function() obj[k]=v end) end end end
    end

    local function plasticMode(on)
        for _,p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") and not p:IsDescendantOf(lp.Character) then
                if on then
                    if not p:GetAttribute("Mat0") then p:SetAttribute("Mat0",p.Material.Name); p:SetAttribute("Refl0",p.Reflectance) end
                    p.Material=Enum.Material.SmoothPlastic; p.Reflectance=0
                else
                    local m=p:GetAttribute("Mat0"); local r=p:GetAttribute("Refl0")
                    if m then pcall(function() p.Material=Enum.Material[m] end) p:SetAttribute("Mat0",nil) end
                    if r~=nil then p.Reflectance=r; p:SetAttribute("Refl0",nil) end
                end
            end
        end
    end

    -- ===== 3 switches (fixed orders 11/12/13) + SAVE =====
    local set50, set100, setPl

    set50  = makeRow("A1_Reduce", "Reduce Effects 50%", 11, function(v)
        if v then
            S.mode=1; applyHalf()
            if set100 then set100(false) end
        else
            if S.mode==1 then S.mode=0; restoreAll() end
        end
        setSave("Settings.Smoother.Mode", S.mode)
    end)

    set100 = makeRow("A1_Remove", "Remove Effects 100%", 12, function(v)
        if v then
            S.mode=2; applyOff()
            if set50 then set50(false) end
        else
            if S.mode==2 then S.mode=0; restoreAll() end
        end
        setSave("Settings.Smoother.Mode", S.mode)
    end)

    setPl   = makeRow("A1_Plastic","Change Map to Plastic)", 13, function(v)
        S.plastic=v; plasticMode(v)
        setSave("Settings.Smoother.Plastic", v)
    end)

    -- ===== Apply restored saved state to UI/World =====
    if S.mode==1 then
        set50(true)
    elseif S.mode==2 then
        set100(true)
    else
        set50(false); set100(false); restoreAll()
    end
    setPl(S.plastic)
end)

-- ########## AA1 — Auto-run Smoother from SaveState (ไม่ต้องกดปุ่ม UI) ##########
task.defer(function()
    local TweenService = game:GetService("TweenService")
    local Lighting     = game:GetService("Lighting")
    local Players      = game:GetService("Players")
    local Http         = game:GetService("HttpService")
    local MPS          = game:GetService("MarketplaceService")
    local lp           = Players.LocalPlayer

    -- ใช้ SAVE เดิมแบบเดียวกับด้านบน
    local function safePlaceName()
        local ok,info = pcall(function() return MPS:GetProductInfo(game.PlaceId) end)
        local n = (ok and info and info.Name) or ("Place_"..tostring(game.PlaceId))
        return n:gsub("[^%w%-%._ ]","_")
    end
    local SAVE_DIR  = "UFO HUB X"
    local SAVE_FILE = SAVE_DIR .. "/" .. tostring(game.PlaceId) .. " - " .. safePlaceName() .. ".json"
    local hasFS = (typeof(isfolder)=="function" and typeof(makefolder)=="function"
                and typeof(readfile)=="function" and typeof(writefile)=="function")
    if hasFS and not isfolder(SAVE_DIR) then pcall(makefolder, SAVE_DIR) end
    getgenv().UFOX_RAM = getgenv().UFOX_RAM or {}
    local RAM = getgenv().UFOX_RAM

    local function loadSave()
        if hasFS and pcall(function() return readfile(SAVE_FILE) end) then
            local ok, data = pcall(function() return Http:JSONDecode(readfile(SAVE_FILE)) end)
            if ok and type(data)=="table" then return data end
        end
        return RAM[SAVE_FILE] or {}
    end
    local function getSave(path, default)
        local cur = loadSave()
        for seg in string.gmatch(path, "[^%.]+") do cur = (type(cur)=="table") and cur[seg] or nil end
        return (cur==nil) and default or cur
    end

    -- ใช้ state เดียวกับ UI
    _G.UFOX_SMOOTH = _G.UFOX_SMOOTH or { mode=0, plastic=false, _snap={}, _pp={} }
    local S = _G.UFOX_SMOOTH

    local FX = {ParticleEmitter=true, Trail=true, Beam=true, Smoke=true, Fire=true, Sparkles=true}
    local PP = {BloomEffect=true, ColorCorrectionEffect=true, DepthOfFieldEffect=true, SunRaysEffect=true, BlurEffect=true}

    local function capture(inst)
        if S._snap[inst] then return end
        local t={}; pcall(function()
            if inst:IsA("ParticleEmitter") then t.Rate=inst.Rate; t.Enabled=inst.Enabled
            elseif inst:IsA("Trail") then t.Enabled=inst.Enabled; t.Brightness=inst.Brightness
            elseif inst:IsA("Beam") then t.Enabled=inst.Enabled; t.Brightness=inst.Brightness
            elseif inst:IsA("Smoke") then t.Enabled=inst.Enabled; t.Opacity=inst.Opacity
            elseif inst:IsA("Fire") then t.Enabled=inst.Enabled; t.Heat=inst.Heat; t.Size=inst.Size
            elseif inst:IsA("Sparkles") then t.Enabled=inst.Enabled end
        end)
        S._snap[inst]=t
    end
    for _,d in ipairs(workspace:GetDescendants()) do
        if FX[d.ClassName] then capture(d) end
    end

    local function applyHalf()
        for i,t in pairs(S._snap) do
            if i.Parent then pcall(function()
                if i:IsA("ParticleEmitter") then i.Rate=(t.Rate or 10)*0.5
                elseif i:IsA("Trail") or i:IsA("Beam") then i.Brightness=(t.Brightness or 1)*0.5
                elseif i:IsA("Smoke") then i.Opacity=(t.Opacity or 1)*0.5
                elseif i:IsA("Fire") then i.Heat=(t.Heat or 5)*0.5; i.Size=(t.Size or 5)*0.7
                elseif i:IsA("Sparkles") then i.Enabled=false end
            end) end
        end
        for _,obj in ipairs(Lighting:GetChildren()) do
            if PP[obj.ClassName] then
                S._pp[obj] = S._pp[obj] or {}
                local snap = S._pp[obj]
                if snap.Enabled == nil then
                    snap.Enabled = obj.Enabled
                    if obj.Intensity ~= nil then snap.Intensity = obj.Intensity end
                    if obj.ClassName=="BlurEffect" and obj.Size then snap.Size = obj.Size end
                end
                obj.Enabled = true
                if obj.Intensity and snap.Intensity ~= nil then
                    obj.Intensity = (snap.Intensity or obj.Intensity or 1)*0.5
                end
                if obj.ClassName=="BlurEffect" and obj.Size and snap.Size ~= nil then
                    obj.Size = math.floor((snap.Size or obj.Size or 0)*0.5)
                end
            end
        end
    end

    local function applyOff()
        for i,_ in pairs(S._snap) do
            if i.Parent then pcall(function() i.Enabled=false end) end
        end
        for _,obj in ipairs(Lighting:GetChildren()) do
            if PP[obj.ClassName] then obj.Enabled=false end
        end
    end

    local function restoreAll()
        for i,t in pairs(S._snap) do
            if i.Parent then
                for k,v in pairs(t) do pcall(function() i[k]=v end) end
            end
        end
        for obj,t in pairs(S._pp) do
            if obj.Parent then
                for k,v in pairs(t) do pcall(function() obj[k]=v end) end
            end
        end
    end

    local function plasticMode(on)
        for _,p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") and not p:IsDescendantOf(lp.Character) then
                if on then
                    if not p:GetAttribute("Mat0") then
                        p:SetAttribute("Mat0", p.Material.Name)
                        p:SetAttribute("Refl0", p.Reflectance)
                    end
                    p.Material = Enum.Material.SmoothPlastic
                    p.Reflectance = 0
                else
                    local m = p:GetAttribute("Mat0")
                    local r = p:GetAttribute("Refl0")
                    if m then pcall(function() p.Material = Enum.Material[m] end); p:SetAttribute("Mat0", nil) end
                    if r ~= nil then p.Reflectance = r; p:SetAttribute("Refl0", nil) end
                end
            end
        end
    end

    -- อ่าน SaveState แล้ว apply อัตโนมัติ (AA1)
    local mode    = getSave("Settings.Smoother.Mode",    S.mode or 0)
    local plastic = getSave("Settings.Smoother.Plastic", S.plastic or false)
    S.mode    = mode
    S.plastic = plastic

    if mode == 1 then
        applyHalf()
    elseif mode == 2 then
        applyOff()
    else
        restoreAll()
    end
    plasticMode(plastic)
end)
-- ===== UFO HUB X • Settings — AFK 💤 (MODEL A LEGACY, full systems) + Runner Save + AA1 =====
-- 1) Black Screen (Performance AFK)  [toggle]
-- 2) White Screen (Performance AFK)  [toggle]
-- 3) AFK Anti-Kick (20 min)          [toggle default ON]
-- 4) Activity Watcher (5 min → enable #3) [toggle default ON]
-- + AA1: Auto-run จาก SaveState โดยตรง ไม่ต้องแตะ UI

-- ########## SERVICES ##########
local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local UIS           = game:GetService("UserInputService")
local RunService    = game:GetService("RunService")
local VirtualUser   = game:GetService("VirtualUser")
local Http          = game:GetService("HttpService")
local MPS           = game:GetService("MarketplaceService")
local lp            = Players.LocalPlayer

-- ########## PER-MAP SAVE (file + RAM fallback) ##########
local function safePlaceName()
    local ok,info = pcall(function() return MPS:GetProductInfo(game.PlaceId) end)
    local n = (ok and info and info.Name) or ("Place_"..tostring(game.PlaceId))
    return n:gsub("[^%w%-%._ ]","_")
end

local SAVE_DIR  = "UFO HUB X"
local SAVE_FILE = SAVE_DIR.."/"..tostring(game.PlaceId).." - "..safePlaceName()..".json"

local hasFS = (typeof(isfolder)=="function" and typeof(makefolder)=="function"
            and typeof(writefile)=="function" and typeof(readfile)=="function")

if hasFS and not isfolder(SAVE_DIR) then pcall(makefolder, SAVE_DIR) end

getgenv().UFOX_RAM = getgenv().UFOX_RAM or {}
local RAM = getgenv().UFOX_RAM

local function loadSave()
    if hasFS and pcall(function() return readfile(SAVE_FILE) end) then
        local ok,dec = pcall(function() return Http:JSONDecode(readfile(SAVE_FILE)) end)
        if ok and type(dec)=="table" then return dec end
    end
    return RAM[SAVE_FILE] or {}
end

local function writeSave(t)
    t = t or {}
    if hasFS then
        pcall(function()
            writefile(SAVE_FILE, Http:JSONEncode(t))
        end)
    end
    RAM[SAVE_FILE] = t
end

local function getSave(path, default)
    local data = loadSave()
    local cur  = data
    for seg in string.gmatch(path,"[^%.]+") do
        cur = (type(cur)=="table") and cur[seg] or nil
    end
    return (cur==nil) and default or cur
end

local function setSave(path, value)
    local data = loadSave()
    local keys = {}
    for seg in string.gmatch(path,"[^%.]+") do table.insert(keys, seg) end
    local p = data
    for i=1,#keys-1 do
        local k = keys[i]
        if type(p[k])~="table" then p[k] = {} end
        p = p[k]
    end
    p[keys[#keys]] = value
    writeSave(data)
end

-- ########## THEME / HELPERS ##########
local THEME = {
    GREEN = Color3.fromRGB(25,255,125),
    RED   = Color3.fromRGB(255,40,40),
    WHITE = Color3.fromRGB(255,255,255),
    BLACK = Color3.fromRGB(0,0,0),
    TEXT  = Color3.fromRGB(255,255,255),
}

local function corner(ui,r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0,r or 12)
    c.Parent = ui
end

local function stroke(ui,th,col)
    local s = Instance.new("UIStroke")
    s.Thickness = th or 2.2
    s.Color = col or THEME.GREEN
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = ui
end

local function tween(o,p)
    TweenService:Create(o, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), p):Play()
end

-- ########## GLOBAL AFK STATE ##########
_G.UFOX_AFK = _G.UFOX_AFK or {
    blackOn    = false,
    whiteOn    = false,
    antiIdleOn = true,   -- default ON
    watcherOn  = true,   -- default ON
    lastInput  = tick(),
    antiIdleLoop = nil,
    idleHooked   = false,
    gui          = nil,
    watcherConn  = nil,
    inputConns   = {},
}

local S = _G.UFOX_AFK

-- ===== restore from SAVE → override defaults =====
S.blackOn    = getSave("Settings.AFK.Black",    S.blackOn)
S.whiteOn    = getSave("Settings.AFK.White",    S.whiteOn)
S.antiIdleOn = getSave("Settings.AFK.AntiKick", S.antiIdleOn)
S.watcherOn  = getSave("Settings.AFK.Watcher",  S.watcherOn)

-- ########## CORE: OVERLAY (Black / White) ##########
local function ensureGui()
    if S.gui and S.gui.Parent then return S.gui end
    local gui = Instance.new("ScreenGui")
    gui.Name="UFOX_AFK_GUI"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn   = false
    gui.DisplayOrder   = 999999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = lp:WaitForChild("PlayerGui")
    S.gui = gui
    return gui
end

local function clearOverlay(name)
    if S.gui then
        local f = S.gui:FindFirstChild(name)
        if f then f:Destroy() end
    end
end

local function showBlack(v)
    clearOverlay("WhiteOverlay")
    clearOverlay("BlackOverlay")
    if not v then return end
    local gui = ensureGui()
    local black = Instance.new("Frame", gui)
    black.Name = "BlackOverlay"
    black.BackgroundColor3 = Color3.new(0,0,0)
    black.Size = UDim2.fromScale(1,1)
    black.ZIndex = 200
    black.Active = true
end

local function showWhite(v)
    clearOverlay("BlackOverlay")
    clearOverlay("WhiteOverlay")
    if not v then return end
    local gui = ensureGui()
    local white = Instance.new("Frame", gui)
    white.Name = "WhiteOverlay"
    white.BackgroundColor3 = Color3.new(1,1,1)
    white.Size = UDim2.fromScale(1,1)
    white.ZIndex = 200
    white.Active = true
end

local function syncOverlays()
    if S.blackOn then
        S.whiteOn = false
        showWhite(false)
        showBlack(true)
    elseif S.whiteOn then
        S.blackOn = false
        showBlack(false)
        showWhite(true)
    else
        showBlack(false)
        showWhite(false)
    end
end

-- ########## CORE: Anti-Kick / Activity ##########
local function pulseOnce()
    local cam = workspace.CurrentCamera
    local cf  = cam and cam.CFrame or CFrame.new()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0,0), cf)
    end)
end

local function startAntiIdle()
    if S.antiIdleLoop then return end
    S.antiIdleLoop = task.spawn(function()
        while S.antiIdleOn do
            pulseOnce()
            for i=1,540 do  -- ~9 นาที (ตรงกับค่าเดิม)
                if not S.antiIdleOn then break end
                task.wait(1)
            end
        end
        S.antiIdleLoop = nil
    end)
end

-- hook Roblox Idle แค่ครั้งเดียว (เหมือนเดิม แต่ global)
if not S.idleHooked then
    S.idleHooked = true
    lp.Idled:Connect(function()
        if S.antiIdleOn then
            pulseOnce()
        end
    end)
end

-- input watcher (mouse/keyboard/touch) → update lastInput
local function ensureInputHooks()
    if S.inputConns and #S.inputConns > 0 then return end
    local function markInput() S.lastInput = tick() end
    table.insert(S.inputConns, UIS.InputBegan:Connect(markInput))
    table.insert(S.inputConns, UIS.InputChanged:Connect(function(io)
        if io.UserInputType ~= Enum.UserInputType.MouseWheel then
            markInput()
        end
    end))
end

local INACTIVE = 5*60 -- 5 นาที
local function startWatcher()
    if S.watcherConn then return end
    S.watcherConn = RunService.Heartbeat:Connect(function()
        if not S.watcherOn then return end
        if tick() - S.lastInput >= INACTIVE then
            -- เปิด Anti-Kick อัตโนมัติ (เหมือนเดิม)
            S.antiIdleOn = true
            setSave("Settings.AFK.AntiKick", true)
            if not S.antiIdleLoop then startAntiIdle() end
            pulseOnce()
            S.lastInput = tick()
        end
    end)
end

-- ########## AA1: AUTO-RUN จาก SaveState (ไม่ต้องแตะ UI) ##########
task.defer(function()
    -- sync หน้าจอ AFK (black/white) ตามค่าที่เซฟไว้
    syncOverlays()

    -- ถ้า Anti-Kick ON → start loop ให้เลย
    if S.antiIdleOn then
        startAntiIdle()
    end

    -- watcher & input hooks (ดูการขยับทุก 5 นาทีเหมือนเดิม)
    ensureInputHooks()
    startWatcher()
end)

-- ########## UI ฝั่งขวา (MODEL A LEGACY • เหมือนเดิม) ##########
registerRight("Settings", function(scroll)
    -- ลบ section เก่า (ถ้ามี)
    local old = scroll:FindFirstChild("Section_AFK_Preview"); if old then old:Destroy() end
    local old2 = scroll:FindFirstChild("Section_AFK_Full");  if old2 then old2:Destroy() end

    -- layout เดิม
    local vlist = scroll:FindFirstChildOfClass("UIListLayout") or Instance.new("UIListLayout", scroll)
    vlist.Padding = UDim.new(0,12)
    vlist.SortOrder = Enum.SortOrder.LayoutOrder
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local nextOrder = 10
    for _,ch in ipairs(scroll:GetChildren()) do
        if ch:IsA("GuiObject") and ch ~= vlist then
            nextOrder = math.max(nextOrder, (ch.LayoutOrder or 0)+1)
        end
    end

    -- Header
    local header = Instance.new("TextLabel", scroll)
    header.Name = "Section_AFK_Full"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1,0,0,36)
    header.Font = Enum.Font.GothamBold
    header.TextSize = 16
    header.TextColor3 = THEME.TEXT
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Text = "AFK 💤"
    header.LayoutOrder = nextOrder

    -- Row helper (เหมือนโค้ดเดิม)
    local function makeRow(textLabel, defaultOn, onToggle)
        local row = Instance.new("Frame", scroll)
        row.Size = UDim2.new(1,-6,0,46)
        row.BackgroundColor3 = THEME.BLACK
        corner(row,12)
        stroke(row,2.2,THEME.GREEN)
        row.LayoutOrder = header.LayoutOrder + 1

        local lab = Instance.new("TextLabel", row)
        lab.BackgroundTransparency = 1
        lab.Size = UDim2.new(1,-160,1,0)
        lab.Position = UDim2.new(0,16,0,0)
        lab.Font = Enum.Font.GothamBold
        lab.TextSize = 13
        lab.TextColor3 = THEME.WHITE
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.Text = textLabel

        local sw = Instance.new("Frame", row)
        sw.AnchorPoint = Vector2.new(1,0.5)
        sw.Position = UDim2.new(1,-12,0.5,0)
        sw.Size = UDim2.fromOffset(52,26)
        sw.BackgroundColor3 = THEME.BLACK
        corner(sw,13)

        local swStroke = Instance.new("UIStroke", sw)
        swStroke.Thickness = 1.8
        swStroke.Color = defaultOn and THEME.GREEN or THEME.RED

        local knob = Instance.new("Frame", sw)
        knob.Size = UDim2.fromOffset(22,22)
        knob.Position = UDim2.new(defaultOn and 1 or 0, defaultOn and -24 or 2, 0.5, -11)
        knob.BackgroundColor3 = THEME.WHITE
        corner(knob,11)

        local state = defaultOn
        local function setState(v)
            state = v
            swStroke.Color = v and THEME.GREEN or THEME.RED
            tween(knob, {Position = UDim2.new(v and 1 or 0, v and -24 or 2, 0.5, -11)})
            if onToggle then onToggle(v) end
        end

        local btn = Instance.new("TextButton", sw)
        btn.BackgroundTransparency = 1
        btn.Size = UDim2.fromScale(1,1)
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.MouseButton1Click:Connect(function()
            setState(not state)
        end)

        return setState
    end

    -- ===== Rows + bindings (ใช้ STATE เดิม + SAVE + CORE) =====
    local setBlack = makeRow("Black Screen (Performance AFK)", S.blackOn, function(v)
        S.blackOn = v
        if v then S.whiteOn = false end
        syncOverlays()
        setSave("Settings.AFK.Black", v)
        if v == true then
            setSave("Settings.AFK.White", false)
        end
    end)

    local setWhite = makeRow("White Screen (Performance AFK)", S.whiteOn, function(v)
        S.whiteOn = v
        if v then S.blackOn = false end
        syncOverlays()
        setSave("Settings.AFK.White", v)
        if v == true then
            setSave("Settings.AFK.Black", false)
        end
    end)

    local setAnti  = makeRow("AFK Anti-Kick (20 min)", S.antiIdleOn, function(v)
        S.antiIdleOn = v
        setSave("Settings.AFK.AntiKick", v)
        if v then
            startAntiIdle()
        end
    end)

    local setWatch = makeRow("Activity Watcher (5 min → enable #3)", S.watcherOn, function(v)
        S.watcherOn = v
        setSave("Settings.AFK.Watcher", v)
        -- watcher loop จะเช็ค S.watcherOn อยู่แล้ว
    end)

    -- ===== Init เมื่อเปิดแท็บ Settings (ให้ตรงกับสถานะจริง) =====
    syncOverlays()
    if S.antiIdleOn then
        startAntiIdle()
    end
    ensureInputHooks()
    startWatcher()
end)
---- ========== ผูกปุ่มแท็บ + เปิดแท็บแรก ==========
local tabs = {
    {btn = btnHome, set = setHomeActive, name = "Home", icon = ICON_HOME},
    {btn = btnShop, set = setShopActive, name = "Shop", icon = ICON_SHOP},
    {btn = btnSettings, set = setSettingsActive, name = "Settings", icon = ICON_SETTINGS},
}

local function activateTab(t)
    -- จดตำแหน่งสกอร์ลซ้ายไว้ก่อน (กันเด้ง)
    lastLeftY = LeftScroll.CanvasPosition.Y
    for _,x in ipairs(tabs) do x.set(x == t) end
    showRight(t.name, t.icon)
    task.defer(function()
        refreshLeftCanvas()
        local viewH = LeftScroll.AbsoluteSize.Y
        local maxY  = math.max(0, LeftScroll.CanvasSize.Y.Offset - viewH)
        LeftScroll.CanvasPosition = Vector2.new(0, math.clamp(lastLeftY,0,maxY))
        -- ถ้าปุ่มอยู่นอกเฟรม ค่อยเลื่อนให้อยู่พอดี
        local btn = t.btn
        if btn and btn.Parent then
            local top = btn.AbsolutePosition.Y - LeftScroll.AbsolutePosition.Y
            local bot = top + btn.AbsoluteSize.Y
            local pad = 8
            if top < 0 then
                LeftScroll.CanvasPosition = LeftScroll.CanvasPosition + Vector2.new(0, top - pad)
            elseif bot > viewH then
                LeftScroll.CanvasPosition = LeftScroll.CanvasPosition + Vector2.new(0, (bot - viewH) + pad)
            end
            lastLeftY = LeftScroll.CanvasPosition.Y
        end
    end)
end

for _,t in ipairs(tabs) do
    t.btn.MouseButton1Click:Connect(function() activateTab(t) end)
end

-- เปิดด้วยแท็บแรก
activateTab(tabs[1])

-- ===== Start visible & sync toggle to this UI =====
setOpen(true)

-- ===== Rebind close buttons inside this UI (กันกรณีชื่อ X หลายตัว) =====
for _,o in ipairs(GUI:GetDescendants()) do
    if o:IsA("TextButton") and (o.Text or ""):upper()=="X" then
        o.MouseButton1Click:Connect(function() setOpen(false) end)
    end
end

-- ===== Auto-rebind ถ้า UI หลักถูกสร้างใหม่ภายหลัง =====
local function hookContainer(container)
    if not container then return end
    container.ChildAdded:Connect(function(child)
        if child.Name=="UFO_HUB_X_UI" then
            task.wait() -- ให้ลูกพร้อม
            for _,o in ipairs(child:GetDescendants()) do
                if o:IsA("TextButton") and (o.Text or ""):upper()=="X" then
                    o.MouseButton1Click:Connect(function() setOpen(false) end)
                end
            end
        end
    end)
end
hookContainer(CoreGui)
local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
hookContainer(pg)

end -- <<== จบ _G.UFO_ShowMainUI() (โค้ด UI หลักของคุณแบบ 100%)

------------------------------------------------------------
-- 2) Toast chain (2-step) • โผล่ Step2 พร้อมกับ UI หลัก แล้วเลือนหาย
------------------------------------------------------------
do
    -- ล้าง Toast เก่า (ถ้ามี)
    pcall(function()
        local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        for _,n in ipairs({"UFO_Toast_Test","UFO_Toast_Test_2"}) do
            local g = pg:FindFirstChild(n); if g then g:Destroy() end
        end
    end)

    -- CONFIG
    local EDGE_RIGHT_PAD, EDGE_BOTTOM_PAD = 2, 2
    local TOAST_W, TOAST_H = 320, 86
    local RADIUS, STROKE_TH = 10, 2
    local GREEN = Color3.fromRGB(0,255,140)
    local BLACK = Color3.fromRGB(10,10,10)
    local LOGO_STEP1 = "rbxassetid://89004973470552"
    local LOGO_STEP2 = "rbxassetid://83753985156201"
    local TITLE_TOP, MSG_TOP = 12, 34
    local BAR_LEFT, BAR_RIGHT_PAD, BAR_H = 68, 12, 10
    local LOAD_TIME = 2.0

    local TS = game:GetService("TweenService")
    local RunS = game:GetService("RunService")
    local PG = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

    local function tween(inst, ti, ease, dir, props)
        return TS:Create(inst, TweenInfo.new(ti, ease or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    end
    local function makeToastGui(name)
        local gui = Instance.new("ScreenGui")
        gui.Name = name
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 999999
        gui.Parent = PG
        return gui
    end
    local function buildBox(parent)
        local box = Instance.new("Frame")
        box.Name = "Toast"
        box.AnchorPoint = Vector2.new(1,1)
        box.Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -(EDGE_BOTTOM_PAD - 24))
        box.Size = UDim2.fromOffset(TOAST_W, TOAST_H)
        box.BackgroundColor3 = BLACK
        box.BorderSizePixel = 0
        box.Parent = parent
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, RADIUS)
        local stroke = Instance.new("UIStroke", box)
        stroke.Thickness = STROKE_TH
        stroke.Color = GREEN
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.LineJoinMode = Enum.LineJoinMode.Round
        return box
    end
    local function buildTitle(box)
        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.RichText = true
        title.Text = '<font color="#FFFFFF">UFO</font> <font color="#00FF8C">HUB X</font>'
        title.TextSize = 18
        title.TextColor3 = Color3.fromRGB(235,235,235)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Position = UDim2.fromOffset(68, TITLE_TOP)
        title.Size = UDim2.fromOffset(TOAST_W - 78, 20)
        title.Parent = box
        return title
    end
    local function buildMsg(box, text)
        local msg = Instance.new("TextLabel")
        msg.BackgroundTransparency = 1
        msg.Font = Enum.Font.Gotham
        msg.Text = text
        msg.TextSize = 13
        msg.TextColor3 = Color3.fromRGB(200,200,200)
        msg.TextXAlignment = Enum.TextXAlignment.Left
        msg.Position = UDim2.fromOffset(68, MSG_TOP)
        msg.Size = UDim2.fromOffset(TOAST_W - 78, 18)
        msg.Parent = box
        return msg
    end
    local function buildLogo(box, imageId)
        local logo = Instance.new("ImageLabel")
        logo.BackgroundTransparency = 1
        logo.Image = imageId
        logo.Size = UDim2.fromOffset(54, 54)
        logo.AnchorPoint = Vector2.new(0, 0.5)
        logo.Position = UDim2.new(0, 8, 0.5, -2)
        logo.Parent = box
        return logo
    end

    -- Step 1 (progress)
    local gui1 = makeToastGui("UFO_Toast_Test")
    local box1 = buildBox(gui1)
    buildLogo(box1, LOGO_STEP1)
    buildTitle(box1)
    local msg1 = buildMsg(box1, "Initializing... please wait")

    local barWidth = TOAST_W - BAR_LEFT - BAR_RIGHT_PAD
    local track = Instance.new("Frame"); track.BackgroundColor3 = Color3.fromRGB(25,25,25); track.BorderSizePixel = 0
    track.Position = UDim2.fromOffset(BAR_LEFT, TOAST_H - (BAR_H + 12))
    track.Size = UDim2.fromOffset(barWidth, BAR_H); track.Parent = box1
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, BAR_H // 2)

    local fill = Instance.new("Frame"); fill.BackgroundColor3 = GREEN; fill.BorderSizePixel = 0
    fill.Size = UDim2.fromOffset(0, BAR_H); fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, BAR_H // 2)

    local pct = Instance.new("TextLabel")
    pct.BackgroundTransparency = 1; pct.Font = Enum.Font.GothamBold; pct.TextSize = 12
    pct.TextColor3 = Color3.new(1,1,1); pct.TextStrokeTransparency = 0.15; pct.TextStrokeColor3 = Color3.new(0,0,0)
    pct.TextXAlignment = Enum.TextXAlignment.Center; pct.TextYAlignment = Enum.TextYAlignment.Center
    pct.AnchorPoint = Vector2.new(0.5,0.5); pct.Position = UDim2.fromScale(0.5,0.5); pct.Size = UDim2.fromScale(1,1)
    pct.Text = "0%"; pct.ZIndex = 20; pct.Parent = track

    tween(box1, 0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out,
        {Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -EDGE_BOTTOM_PAD)}):Play()

    task.spawn(function()
        local t0 = time()
        local progress = 0
        while progress < 100 do
            progress = math.clamp(math.floor(((time() - t0)/LOAD_TIME)*100 + 0.5), 0, 100)
            fill.Size = UDim2.fromOffset(math.floor(barWidth*(progress/100)), BAR_H)
            pct.Text = progress .. "%"
            RunS.Heartbeat:Wait()
        end
        msg1.Text = "Loaded successfully."
        task.wait(0.25)
        local out1 = tween(box1, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut,
            {Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -(EDGE_BOTTOM_PAD - 24))})
        out1:Play(); out1.Completed:Wait(); gui1:Destroy()

        -- Step 2 (no progress) + เปิด UI หลักพร้อมกัน
        local gui2 = makeToastGui("UFO_Toast_Test_2")
        local box2 = buildBox(gui2)
        buildLogo(box2, LOGO_STEP2)
        buildTitle(box2)
        buildMsg(box2, "Download UI completed. ✅")
        tween(box2, 0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out,
            {Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -EDGE_BOTTOM_PAD)}):Play()

        -- เปิด UI หลัก "พร้อมกัน" กับ Toast ขั้นที่ 2
        if _G.UFO_ShowMainUI then pcall(_G.UFO_ShowMainUI) end

        -- ให้ผู้ใช้เห็นข้อความครบ แล้วค่อยเลือนลง (ปรับเวลาได้ตามใจ)
        task.wait(1.2)
        local out2 = tween(box2, 0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut,
            {Position = UDim2.new(1, -EDGE_RIGHT_PAD, 1, -(EDGE_BOTTOM_PAD - 24))})
        out2:Play(); out2.Completed:Wait(); gui2:Destroy()
    end)
end
-- ==== mark boot done (lock forever until reset) ====
do
    local B = getgenv().UFO_BOOT or {}
    B.status = "done"
    getgenv().UFO_BOOT = B
end
