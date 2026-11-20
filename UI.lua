-- Artisan Network: main window
local ADDON, ns = ...
local W, C = ns.W, ns.W.C
local UI = {}
ns.UI = UI

local main, content
local pages, nav = {}, {}
local current
local header = {}
local side = {}

local WIDTH, HEIGHT, SIDE_W, DETAIL_W = 920, 580, 184, 300
UI.DETAIL_W = DETAIL_W
UI.Build = {}   -- page builders, one file each in UI\: function(content) -> page

------------------------------------------------------------------------
-- Shared actions
------------------------------------------------------------------------
local function OpenChat(text)
    local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
    if open then open(text) end
end
UI.OpenChat = OpenChat

ns.CURSEFORGE = "https://www.curseforge.com/wow/addons/artisan-network"

-- fills your chat box (guild chat when you're in one) with a short invite; you press Enter
function ns:InviteText()
    local msg = "I'm using Artisan Network to find crafters and share professions. Get it here: " .. ns.CURSEFORGE
    OpenChat((IsInGuild() and "/g " or "") .. msg)
end

-- Open a whisper to a player with some text typed. SendTell sets the target directly, which
-- also works for names with a space ("First Surname" on WoW: Forever).
function ns:WhisperText(name, text)
    local tell = ns.TellName(name) or ns.Short(name)
    local sendTell = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
    if sendTell and pcall(sendTell, tell) then
        local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if eb and text and text ~= "" then eb:Insert(text) end
        return
    end
    OpenChat("/w " .. tell .. " " .. (text or ""))
end

function ns:Whisper(name, key)
    local msg = ""
    if key then
        local rname, _, link = ns.RecipeInfo(key)
        local what = link or rname
        if what then msg = "Hi! Could you craft " .. what .. " for me?" end
    end
    ns:WhisperText(name, msg)
end

function ns:LinkRecipe(key)
    local name, _, link = ns.RecipeInfo(key)
    link = link or name
    if not link then return end
    ns.linking = true   -- don't treat our own link as a shift-click search
    local done = ChatEdit_InsertLink and ChatEdit_InsertLink(link)
    ns.linking = nil
    if not done then OpenChat(link) end
end

function ns.SortedProfs(rec)
    local t = {}
    for _, id in ipairs(ns.PROF_ORDER) do
        if rec.profs and rec.profs[id] then t[#t + 1] = id end
    end
    return t
end

local function IsTest(name) return ns.testPlayers and ns.testPlayers[name] ~= nil end

-- how we know a player: guild, met in a group, introduced by a guildmate, added by you, contact
local VIA_TEXT = { group = "met in a group", intro = "introduced", added = "added by you", contact = "contact" }
local VIA_SHORT = { group = "group", intro = "introduced", added = "added", contact = "contact" }
function ns.ViaLabel(name, rec, short)
    if not rec or (ns.testPlayers and ns.testPlayers[name]) then return nil end
    if ns:IsGuildmate(name) then return short and "guild" or "Guild" end
    return (short and VIA_SHORT or VIA_TEXT)[rec.via or ""]
end

local function NameText(name, rec)
    local tag = ""
    if name == ns.me then tag = " |cff8a8b94(you)|r"
    elseif ns:IsMine(name) then tag = " |cff8a8b94(alt)|r"
    elseif IsTest(name) then tag = " |cff8a8b94(test)|r" end
    return "|cff" .. ns.ClassHex(rec and rec.class) .. ((rec and rec.display) or ns.Short(name)) .. "|r" .. tag
end

local function PresenceText(name, rec)
    if ns:IsOnline(name) then
        return ns:IsBusy(name) and "|cffffba45busy|r" or "|cff52de7conline|r"
    end
    return "seen " .. ns.Ago(rec and rec.lastSeen)
end

-- shared with the page files
UI.IsTest, UI.NameText, UI.PresenceText = IsTest, NameText, PresenceText

-- "2 online / 5", "<offlineText> / 5", "only you" or "no known crafters" on a font string.
-- Counts are other players only (ns:CountOnline).
function UI.SetCrafterCount(fs, on, others, mine, offlineText)
    if on > 0 then
        fs:SetText(on .. " online  |cff62636c/ " .. others .. "|r")
        fs:SetTextColor(unpack(C.online))
    else
        fs:SetText(others > 0 and (offlineText .. "  |cff62636c/ " .. others .. "|r")
            or mine and "only you" or "no known crafters")
        fs:SetTextColor(unpack(C.faint))
    end
end

------------------------------------------------------------------------
-- Window chrome
------------------------------------------------------------------------
local NAV = {
    { key = "search",   label = "Find a Crafter", icon = "Interface\\Icons\\INV_Misc_Spyglass_03" },
    { key = "players",  label = "Players",        icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude" },
    { key = "mine",     label = "My Characters",  icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "watch",    label = "Watchlist",      icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "requests", label = "Requests",       icon = "Interface\\Icons\\INV_Letter_01" },
    { key = "settings", label = "Settings",       icon = "Interface\\Icons\\INV_Misc_Gear_01" },
}

function UI:UpdateNav()
    if not main then return end
    local r, g, bb = ns.Accent()
    for key, b in pairs(nav) do
        local on = key == current
        b.bar:SetColorTexture(r, g, bb, 1)
        b.bar:SetShown(on)
        b.bg:SetColorTexture(r, g, bb, on and 0.10 or 0)
        if W.forever then
            b.text:SetTextColor(on and 1 or 0.85, on and 0.82 or 0.70, on and 0.2 or 0.32)
        else
            b.text:SetTextColor(unpack(on and C.text or C.dim))
        end
        b.icon:SetDesaturated(not on)
        b.icon:SetAlpha(on and 1 or 0.55)
    end
    local watchCount = 0
    for _ in pairs(ns.db.watch) do watchCount = watchCount + 1 end
    nav.watch.badge:SetText(watchCount > 0 and watchCount or "")
    local on = ns:OnlineCount()
    nav.players.badge:SetText(on > 0 and on or "")
    -- unseen received requests, in the accent color so they stand out
    if current == "requests" and main:IsShown() and (ns.db.requestsUnseen or 0) > 0 then
        ns.db.requestsUnseen = 0
        if ns.UpdateBroker then ns:UpdateBroker() end
    end
    local unseen = ns.db.requestsUnseen or 0
    nav.requests.badge:SetText(unseen > 0 and ("|cff" .. ns.AccentHex() .. unseen .. "|r") or "")
end

local function CreateMain()
    main = CreateFrame("Frame", "ArtisanNetFrame", UIParent)
    UI.main = main
    main:SetSize(WIDTH, HEIGHT)
    main:SetPoint("CENTER")
    main:SetFrameStrata("HIGH")
    main:SetToplevel(true)
    main:SetClampedToScreen(true)
    main:SetMovable(true)
    main:EnableMouse(true)
    main:SetScale(ns.settings.scale or 1)
    main:Hide()
    W.Fill(main, C.bg)
    W.Border(main, { 0, 0, 0, 1 })
    if W.forever then
        -- bronze frame line inside the black edge
        local rim = CreateFrame("Frame", nil, main)
        rim:SetPoint("TOPLEFT", 2, -2)
        rim:SetPoint("BOTTOMRIGHT", -2, 2)
        rim:SetFrameLevel(main:GetFrameLevel() + 5)
        W.Border(rim, { 0.62, 0.49, 0.30, 1 })
    end
    tinsert(UISpecialFrames, "ArtisanNetFrame")
    local pos = ns.settings.window
    if pos then
        main:ClearAllPoints()
        main:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end

    -- header
    local h = CreateFrame("Frame", nil, main)
    h:SetPoint("TOPLEFT", 1, -1)
    h:SetPoint("TOPRIGHT", -1, -1)
    h:SetHeight(44)
    W.Fill(h, C.header)
    local hl = W.Line(h, true, W.forever and { 0.62, 0.49, 0.30, 1 } or { 1, 1, 1, 0.06 })
    hl:SetPoint("BOTTOMLEFT")
    hl:SetPoint("BOTTOMRIGHT")
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function() main:StartMoving() end)
    h:SetScript("OnDragStop", function()
        main:StopMovingOrSizing()
        local p1, _, p2, x, y = main:GetPoint()
        ns.settings.window = { p1, p2, x, y }
    end)

    local mark = h:CreateTexture(nil, "ARTWORK")
    mark:SetSize(24, 24)
    mark:SetPoint("LEFT", 14, 0)
    mark:SetTexture(ns.MEDIA .. "Icon")
    local title = W.Text(h, 15)
    title:SetPoint("LEFT", mark, "RIGHT", 10, 0)
    title:SetText("ARTISAN")
    W.Accentize(title, "text")
    local title2 = W.Text(h, 15, C.text)
    title2:SetPoint("LEFT", title, "RIGHT", 5, 0)
    title2:SetText("NETWORK")
    local ver = W.Text(h, 10, C.faint)
    ver:SetPoint("LEFT", title2, "RIGHT", 10, -1)
    ver:SetText("v" .. ns.VERSION)

    header.update = CreateFrame("Frame", nil, h)
    header.update:SetSize(150, 20)
    header.update:SetPoint("LEFT", ver, "RIGHT", 12, 0)
    if W.forever then
        -- Forever look: centered gold title and a round portrait over the top-left corner
        mark:Hide(); title:Hide(); title2:Hide(); ver:Hide()
        local ftitle = W.Text(h, 16, W.GOLD, "CENTER")
        ftitle:SetPoint("CENTER", 0, 0)
        ftitle:SetText("Artisan Network")
        local por = CreateFrame("Frame", nil, main)
        por:SetSize(62, 62)
        por:SetPoint("CENTER", main, "TOPLEFT", 22, -20)
        por:SetFrameLevel(main:GetFrameLevel() + 20)
        local ring = por:CreateTexture(nil, "BACKGROUND")
        ring:SetAllPoints()
        ring:SetColorTexture(0.62, 0.49, 0.30, 1)
        local disc = por:CreateTexture(nil, "BORDER")
        disc:SetPoint("TOPLEFT", 4, -4)
        disc:SetPoint("BOTTOMRIGHT", -4, 4)
        disc:SetColorTexture(0.07, 0.10, 0.16, 1)
        local icon = por:CreateTexture(nil, "ARTWORK")
        icon:SetSize(38, 38)
        icon:SetPoint("CENTER")
        icon:SetTexture(ns.MEDIA .. "Icon")
        -- round the ring and disc; if masks aren't available they simply stay square
        pcall(function()
            for _, t in ipairs({ ring, disc }) do
                local m = por:CreateMaskTexture()
                m:SetAllPoints(t)
                m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                t:AddMaskTexture(m)
            end
        end)
        header.update:ClearAllPoints()
        header.update:SetPoint("LEFT", h, "LEFT", 62, 0)
    end
    header.update.text = W.Text(header.update, 10, { 1, 0.73, 0.27 })
    header.update.text:SetPoint("LEFT")
    header.update:EnableMouse(true)
    W.Tip(header.update, function() return "Artisan Network " .. (ns:UpdateAvailable() or "") .. " is available" end,
        function() return "You have v" .. ns.VERSION .. ". Download the new version from CurseForge, then restart the game." end)
    header.update:Hide()

    local close = CreateFrame("Button", nil, h)
    close:SetSize(30, 30)
    close:SetPoint("RIGHT", -8, 0)
    close.bg = W.Fill(close, { 1, 1, 1, 0 })
    close.text = W.Text(close, 14, C.dim, "CENTER")
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("x")
    close:SetScript("OnClick", function() main:Hide() end)
    close:SetScript("OnEnter", function(s) s.bg:SetColorTexture(1, 0.3, 0.35, 0.25); s.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function(s) s.bg:SetColorTexture(1, 1, 1, 0); s.text:SetTextColor(unpack(C.dim)) end)
    if W.forever then
        -- red square with a gold rim and a gold X, like the game's close button
        close:SetSize(24, 24)
        close.bg:SetColorTexture(0.55, 0.08, 0.04, 1)
        W.Border(close, { 0.80, 0.62, 0.25, 1 })
        close.text:SetFont(STANDARD_TEXT_FONT, 13, "")
        close.text:SetText("X")
        close.text:SetTextColor(unpack(W.GOLD))
        close:SetScript("OnEnter", function(s) s.bg:SetColorTexture(0.75, 0.12, 0.06, 1); s.text:SetTextColor(1, 1, 1) end)
        close:SetScript("OnLeave", function(s) s.bg:SetColorTexture(0.55, 0.08, 0.04, 1); s.text:SetTextColor(unpack(W.GOLD)) end)
    end

    header.status = W.Text(h, 11, C.dim, "RIGHT")
    header.status:SetPoint("RIGHT", close, "LEFT", -14, 0)
    header.dot = h:CreateTexture(nil, "ARTWORK")
    header.dot:SetSize(12, 12)
    header.dot:SetPoint("RIGHT", header.status, "LEFT", -4, 0)

    -- Available / Busy switch
    local avail = CreateFrame("Button", nil, h)
    avail:SetSize(132, 22)
    avail:SetPoint("RIGHT", header.dot, "LEFT", -16, 0)
    avail.bg = W.Fill(avail, { 1, 1, 1, 0.04 })
    W.Border(avail)
    avail.light = avail:CreateTexture(nil, "ARTWORK")
    avail.light:SetSize(8, 8)
    avail.light:SetPoint("LEFT", 10, 0)
    avail.text = W.Text(avail, 11, C.text)
    avail.text:SetPoint("LEFT", avail.light, "RIGHT", 7, 0)
    function avail:Paint(hover)
        local busy = ns.me and ns:MyRecord().busy
        local c = busy and { 1, 0.73, 0.27 } or C.online
        self.light:SetColorTexture(c[1], c[2], c[3], 1)
        self.text:SetText(busy and "Busy" or "Available to craft")
        self.text:SetTextColor(c[1], c[2], c[3])
        self.bg:SetColorTexture(c[1], c[2], c[3], hover and 0.16 or 0.08)
        W.SetBorderColor(self, c[1], c[2], c[3], hover and 0.7 or 0.35)
    end
    avail:SetScript("OnClick", function() ns:SetBusy(not ns:MyRecord().busy) end)
    avail:SetScript("OnEnter", function(self)
        self:Paint(true)
        local busy = ns:MyRecord().busy
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(busy and "Busy" or "Available to craft", 1, 1, 1)
        GameTooltip:AddLine(busy
            and "You're still listed as a crafter, but marked busy and shown without a Whisper button. Click to become available."
            or "Other players see you as available and can whisper you from the crafter list. Click to switch to Busy while you raid or level.",
            0.7, 0.7, 0.75, true)
        GameTooltip:Show()
    end)
    avail:SetScript("OnLeave", function(self) self:Paint(false); GameTooltip:Hide() end)
    header.avail = avail
    header.dot:SetTexture(W.ONLINE_ICON)

    -- sidebar
    local s = CreateFrame("Frame", nil, main)
    s:SetPoint("TOPLEFT", h, "BOTTOMLEFT")
    s:SetPoint("BOTTOMLEFT", 1, 1)
    s:SetWidth(SIDE_W)
    W.Fill(s, C.side)
    local sl = W.Line(s, false, W.forever and C.border or { 1, 1, 1, 0.05 })
    sl:SetPoint("TOPRIGHT")
    sl:SetPoint("BOTTOMRIGHT")

    for i, n in ipairs(NAV) do
        local b = CreateFrame("Button", nil, s)
        b:SetHeight(36)
        b:SetPoint("TOPLEFT", 0, -14 - (i - 1) * 38)
        b:SetPoint("TOPRIGHT", -1, -14 - (i - 1) * 38)
        b.bg = W.Fill(b, { 0, 0, 0, 0 })
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetWidth(2)
        b.bar:SetPoint("TOPLEFT")
        b.bar:SetPoint("BOTTOMLEFT")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 20, 0)
        b.icon:SetTexture(n.icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.text = W.Text(b, 12, C.dim)
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 12, 0)
        b.text:SetText(n.label)
        b.badge = W.Text(b, 10, C.faint, "RIGHT")
        b.badge:SetPoint("RIGHT", -14, 0)
        b:SetScript("OnClick", function() UI:Show(n.key) end)
        b:SetScript("OnEnter", function(self)
            if current ~= n.key then
                self.text:SetTextColor(unpack(C.text))
                self.bg:SetColorTexture(1, 1, 1, 0.03)
            end
        end)
        b:SetScript("OnLeave", function() UI:UpdateNav() end)
        nav[n.key] = b
    end

    side.net = W.Text(s, 10, C.dim)
    side.net:SetPoint("BOTTOMLEFT", 20, 36)
    side.share = W.Text(s, 10, C.dim)
    side.share:SetPoint("BOTTOMLEFT", 20, 18)

    content = CreateFrame("Frame", nil, main)
    content:SetPoint("TOPLEFT", s, "TOPRIGHT")
    content:SetPoint("BOTTOMRIGHT", -1, 1)

    pages.search = UI.Build.Search(content)
    pages.players = UI.Build.Players(content, false)
    pages.mine = UI.Build.Mine(content)
    pages.watch = UI.Build.Watch(content)
    pages.requests = UI.Build.Requests(content)
    pages.settings = UI.Build.Settings(content)
    for _, pg in pairs(pages) do pg.frame:Hide() end

    main:SetScript("OnShow", function() UI:Refresh() end)
end

------------------------------------------------------------------------
-- Public functions (used by the other files)
------------------------------------------------------------------------
local SHARE_TEXT = { ALL = "Everyone", GUILD = "Guild only", NONE = "Nobody" }

function UI:Refresh()
    if not main or not main:IsShown() then return end
    local on, known = ns:OnlineCount(), 0
    for name in pairs(ns:AllPlayers()) do
        if not ns:IsMine(name) then known = known + 1 end
    end
    header.status:SetText(on .. (on == 1 and " other" or " others") .. " online  |cff62636c·|r  " .. known .. " known")
    local upd = ns:UpdateAvailable()
    header.update.text:SetText(upd and ("Update available: v" .. upd) or "")
    header.update:SetShown(upd ~= nil)
    header.dot:SetTexture(on > 0 and W.ONLINE_ICON or W.OFFLINE_ICON)
    header.avail:Paint(header.avail:IsMouseOver())
    side.net:SetText("Network  |cff52de7c" .. (ns.settings.outside and "guild + contacts" or "guild only") .. "|r")
    side.share:SetText("Sharing  |cffd0d0d6" .. (SHARE_TEXT[ns:EffectiveScope()] or "?") .. "|r")
    UI:UpdateNav()
    if current and pages[current] then pages[current].refresh() end
end

function UI:Show(key, arg, query)
    if not main then CreateMain() end
    key = pages[key] and key or "search"
    current = key
    for k, pg in pairs(pages) do pg.frame:SetShown(k == key) end
    if pages[key].onShow then pages[key].onShow(arg, query) end
    main:Show()
    UI:Refresh()
end

function UI:ShowPlayer(name)
    UI:Show(ns:IsMine(name) and "mine" or "players", name)
end

function ns:ToggleUI()
    if main and main:IsShown() then main:Hide() else UI:Show(current or "search") end
end

function ns:ShowUI(key, arg, query) UI:Show(key, arg, query) end

------------------------------------------------------------------------
-- Request popup
------------------------------------------------------------------------
local req
function UI:OpenRequest(key)
    if not main then return end
    if not req then
        req = CreateFrame("Frame", nil, main)
        req:SetSize(380, 188)
        req:SetFrameStrata("DIALOG")
        ns:MakeMovable(req, "request", { "CENTER", UIParent, "CENTER", 0, 0 })
        W.Fill(req, { 0.06, 0.06, 0.07, 0.99 })
        W.Border(req, { 0, 0, 0, 1 })
        local bar = req:CreateTexture(nil, "ARTWORK")
        bar:SetHeight(2)
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("TOPRIGHT")
        W.Accentize(bar, "tex")
        req.title = W.Text(req, 14)
        req.title:SetPoint("TOPLEFT", 18, -16)
        req.title:SetText("Request a craft")
        req.icon = W.Icon(req, 20)
        req.icon:SetPoint("TOPLEFT", 18, -42)
        req.name = W.Text(req, 12)
        req.name:SetPoint("LEFT", req.icon, "RIGHT", 8, 0)
        req.name:SetWidth(320)
        req.info = W.Text(req, 11, C.dim)
        req.info:SetPoint("TOPLEFT", 18, -70)
        req.info:SetWidth(344)
        req.info:SetWordWrap(true)

        local e = CreateFrame("EditBox", nil, req)
        e:SetSize(344, 28)
        e:SetPoint("TOPLEFT", 18, -106)
        e:SetAutoFocus(false)
        e:SetMaxLetters(80)
        e:SetFont(STANDARD_TEXT_FONT, 12, "")
        e:SetTextColor(unpack(C.text))
        e:SetTextInsets(8, 8, 0, 0)
        W.Fill(e, { 0, 0, 0, 0.35 })
        W.Border(e)
        e.ph = W.Text(e, 12, C.faint)
        e.ph:SetPoint("LEFT", 8, 0)
        e.ph:SetText("Add a note (optional): have mats, will tip 5g...")
        e:SetScript("OnTextChanged", function(s) s.ph:SetShown(s:GetText() == "") end)
        e:SetScript("OnEscapePressed", function() req:Hide() end)
        req.edit = e

        local send = W.Button(req, "Send request", 120, 26)
        send:SetPoint("BOTTOMRIGHT", -18, 16)
        send:SetActive(true)
        local cancel = W.Button(req, "Cancel", 80, 26)
        cancel:SetPoint("RIGHT", send, "LEFT", -8, 0)
        cancel:SetScript("OnClick", function() req:Hide() end)
        local function Send()
            local n, err = ns:SendRequest(req.key, e:GetText())
            if n then
                ns.Print("Request sent to " .. n .. (n == 1 and " crafter" or " crafters")
                    .. ". They'll get a pop-up and can whisper you.")
                req:Hide()
            else
                req.info:SetText("|cffff6b6b" .. err .. "|r")
            end
        end
        send:SetScript("OnClick", Send)
        e:SetScript("OnEnterPressed", Send)
    end
    local ent = ns:GetIndex() and ns.byKey[key]
    if not ent then return end
    req.key = key
    req.icon.tex:SetTexture(ent.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    req.name:SetText(ent.name)
    local n = #ns:RequestTargets(ent)
    req.info:SetText(n > 0 and ("Sends a pop-up to " .. n .. " available " .. (n == 1 and "crafter" or "crafters")
        .. " online who can make this. They answer by whispering you.")
        or "|cffff6b6bNobody who can craft this is online and available right now.|r")
    req.edit:SetText("")
    req:Show()
    req.edit:SetFocus()
end

local function RequestRefresh()
    if main and main:IsShown() then ns:Debounce("ui", 0.15, function() UI:Refresh() end) end
end
-- reagent counts on the recipe panel follow your bags
ns:On("BAG_UPDATE_DELAYED", function()
    if main and main:IsShown() then ns:Debounce("bagsui", 0.4, function() UI:Refresh() end) end
end)
for _, msg in ipairs({ "INDEX", "PLAYERS", "PRESENCE", "DATA_CHANGED", "NETWORK", "ACCENT", "UPDATE", "COOLDOWNS", "HIDDEN", "REQUESTS", "FAVORITES" }) do
    ns:Listen(msg, RequestRefresh)
end
