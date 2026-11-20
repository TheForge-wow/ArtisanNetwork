-- Artisan Network: core (database, events, helpers, slash commands)
local ADDON, ns = ...
_G.ArtisanNet = ns

ns.VERSION        = "1.6.7"
ns.MEDIA          = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ns.PREFIX         = "ArtisanNet"   -- addon message prefix (max 16 chars)
ns.ONLINE_TIMEOUT = 660            -- seconds without a heartbeat before an addon user counts as offline
ns.HEARTBEAT      = 300            -- seconds between presence broadcasts

local DEFAULTS = {
    settings = {
        shareScope = "ALL",      -- ALL = everyone, GUILD = guild only, NONE = don't share recipes
        note       = "",         -- crafter note shown to other players ("Free with your mats")
        tooltip    = true,       -- show crafters on item tooltips
        alerts     = true,       -- toast when a watched crafter comes online
        alertSound = true,
        pruneDays  = 30,         -- forget players not seen for this many days
        accent     = "teal",
        style      = "artisan",  -- "artisan" or "forever"; applied at load
        stylePicked = false,     -- the one-time "Choose a look" pop-up has been answered
        scale      = 1,
        onlineOnly = false,
        hideLow    = false,      -- hide recipes whose crafted item is below lowCutoff
        lowCutoff  = 40,
        showHidden = false,      -- temporarily show hidden recipes (dimmed)
        requests   = true,       -- receive crafting request pop-ups
        outside    = true,       -- find addon users outside the guild (groups, contacts, introductions)
        showBoP    = false,      -- list Bind on Pickup recipes in Find a Crafter
        hideStart  = false,      -- hide the "Getting started" card in Find a Crafter
        positions  = {},         -- saved spots of movable pop-ups: [name] = { point, relPoint, x, y }
        minimap    = { angle = 215, hide = false },
    },
    players = {},   -- [Name-Realm] = record received from other users
    chars   = {},   -- [Name-Realm] = your own characters (account wide)
    watch   = {},   -- [recipeKey] = true
    favorites = {}, -- [recipeKey] = true: starred in Find a Crafter (no pop-ups, unlike watch)
    collapsed = {}, -- [group label] = true: slot headers folded away in Find a Crafter
    outputs = {},   -- [recipe spellID] = itemID it creates (learned from scans and other players)
    intros  = {},   -- [name] = { from, t, probed, failed }: players a guildmate introduced, not heard yet
    myNames = {},   -- [character GUID] = "First Surname", learned when our own messages come back (Forever)
    cdSpells = {},  -- [recipe spellID] = profession id, recipes seen with a cooldown
    hidden  = {},   -- [recipeKey] = true (hidden by hand) / false (always shown)
    reagents = {},  -- [recipeKey] = { {itemID, count}, ... } captured from profession windows
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
    if not handlers[event] then
        -- some events only exist on Retail or only on Classic; ignore the ones this client lacks
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- internal message bus (UI refreshes, presence changes, ...)
local listeners = {}
function ns:Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end
function ns:Fire(msg, ...)
    local l = listeners[msg]
    if not l then return end
    for i = 1, #l do
        local ok, err = pcall(l[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end

local pendingDebounce = {}
function ns:Debounce(key, delay, fn)
    if pendingDebounce[key] then return end
    pendingDebounce[key] = true
    C_Timer.After(delay, function()
        pendingDebounce[key] = nil
        fn()
    end)
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
function ns.Print(...)
    local hex = ns.AccentHex and ns.AccentHex() or "33d1bd"
    print("|cff" .. hex .. "Artisan|r", ...)
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
function ns.B36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local r = n % 36
        s = DIGITS:sub(r + 1, r + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

function ns.UnB36(s)
    if not s or s == "" then return nil end
    return tonumber(s, 36)
end

function ns.Hash(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 4294967296
    end
    return ns.B36(h)
end

function ns.Realm()
    local r = GetNormalizedRealmName and GetNormalizedRealmName()
    if r and r ~= "" then return r end
    return ((GetRealmName() or ""):gsub("[%s%-]", ""))
end

------------------------------------------------------------------------
-- Names. On WoW: Forever characters have a first name and a surname, and the
-- realm is split into sub-realms that share one set of names. The server stamps
-- addon messages "First Surname-SubRealm" but only delivers whispers addressed
-- to the plain "First Surname". So on Forever ns.splitNames is true and a
-- player's identity is "First Surname" with no realm; elsewhere it is "Name-Realm".
------------------------------------------------------------------------
ns.splitNames = false

function ns.DetectSplitNames()
    local build = select(4, GetBuildInfo())
    local forever = type(build) == "number" and build >= 16000 and build < 20000
    -- The first name comes from UnitName, which is right as soon as the character loads.
    -- On Forever UnitFullName can still hold the previous character's name at that point,
    -- so its surname is only used when its first name agrees.
    local first = UnitName("player")
    local home = ns.Realm()
    local function IsSurname(s) return type(s) == "string" and s ~= "" and s ~= home and not s:find("%d") end
    local surname
    if UnitFullName then
        local f, s = UnitFullName("player")
        if f == first and IsSurname(s) then surname = s end
    end
    if not surname and GetUnitName then
        -- some clients give "First-Surname" here instead
        local full = GetUnitName("player", true)
        local f, s = (type(full) == "string" and full or ""):match("^([^%-]+)%-([^%-]+)$")
        if f == first and IsSurname(s) then surname = s end
    end
    local hasSurname = IsSurname(surname)
    ns.splitNames = forever or hasSurname or false
    if ns.splitNames then
        ns.myOldKey = first .. "-" .. home   -- how 1.0.4 to 1.4.0 saved you
        ns.myFirst = first                    -- how 1.4.1 saved you when it missed your surname
        if hasSurname then return first .. " " .. surname end
        -- not exposed by the game: use the full name heard on an earlier session of THIS character.
        -- Keyed by GUID: on Forever several characters can share a first name ("Scryptik Mortis",
        -- "Scryptik Coldsnap").
        local guid = UnitGUID and UnitGUID("player")
        local known = ns.db and guid and ns.db.myNames[guid]
        if known and known:sub(1, #first + 1) == first .. " " then return known end
        return first
    end
    return (first or UnitName("player")) .. "-" .. home
end

-- realm names look like "CAMWOWUS1Realm2PvP" or "ForeverPvE"; surnames never have digits
local function IsRealmPart(s)
    return s == ns.Realm() or s:find("%d") ~= nil or s:find("^Forever") ~= nil or s:find("^Classic") ~= nil
end

function ns.FullName(name)
    if not name or name == "" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if ns.splitNames then
        -- forms seen: "First Surname-Realm" (messages, roster), "First-Surname" (unit functions),
        -- "First-Surname-Realm", "First Surname" (whisper targets, system messages)
        local first, rest = name:match("^([^%-]+)%-(.+)$")
        if not first then return name end
        if first:find(" ", 1, true) then return first end            -- "First Surname-Realm"
        local surname, realm = rest:match("^([^%-]+)%-(.+)$")
        if surname and IsRealmPart(realm) then return first .. " " .. surname end
        if IsRealmPart(rest) then return first end                     -- "First-Realm" (no surname)
        return first .. " " .. rest                                     -- "First-Surname"
    end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. ns.Realm()
end

-- Our own message came back from the server under a fuller name than we had (Forever
-- surname the game didn't expose): adopt it, move our saved record, remember it.
function ns:AdoptMyName(full)
    if not full or full == ns.me then return end
    local old = ns.me
    local rec = ns.db.chars[old]
    local guid = UnitGUID and UnitGUID("player")
    -- only carry over the record if it's provably this character's (first names can repeat)
    if rec and (not rec.guid or rec.guid == guid) then
        ns.db.chars[old] = nil
        if not ns.db.chars[full] then ns.db.chars[full] = rec end
    end
    ns.db.players[full] = nil
    ns.me = full
    if guid then ns.db.myNames[guid] = full end
    ns:MyRecord().guid = guid
    ns:Fire("PLAYERS")
end

-- Make a frame draggable and remember where it was put. click: also a Button whose
-- OnClick should ignore the click that ends a drag.
function ns:MakeMovable(frame, key, defaultPoint)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self.dragged = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.settings.positions[key] = { p, rp, x, y }
        C_Timer.After(0.05, function() self.dragged = nil end)
    end)
    function frame:RestorePosition()
        local pos = ns.settings.positions[key]
        self:ClearAllPoints()
        if pos then
            self:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        else
            self:SetPoint(unpack(defaultPoint))
        end
    end
    frame:RestorePosition()
end

-- the name to whisper (addon messages, chat whispers, pings)
function ns.TellName(name)
    if not name then return nil end
    if ns.splitNames then return ns.FullName(name) end
    local base, realm = name:match("^(.+)%-([^%-]+)$")
    if realm and realm == ns.Realm() then return base end
    return name
end

-- "Scryptik Mortis" for display; nil when the name has no last name
function ns.DisplayName(raw)
    local base = raw and (raw:match("^([^%-]+)") or raw)
    if base and base:find("%S%s+%S") then return (base:gsub("^%s+", ""):gsub("%s+$", "")) end
end

function ns.Short(name)
    if not name then return "?" end
    if Ambiguate then return Ambiguate(name, "none") end
    return (name:gsub("%-.*$", ""))
end

function ns.ClassHex(class)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = class and colors and colors[class]
    if c then
        return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return "d0d0d6"
end

function ns.ClassName(class)
    if not class or class == "" then return "" end
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[class]) or (class:sub(1, 1) .. class:sub(2):lower())
end

function ns.Ago(t)
    if not t then return "never" end
    local d = time() - t
    if d < 60 then return "just now"
    elseif d < 3600 then return math.floor(d / 60) .. "m ago"
    elseif d < 86400 then return math.floor(d / 3600) .. "h ago"
    else return math.floor(d / 86400) .. "d ago" end
end

function ns.VersionNewer(a, b)
    local function parts(v)
        local t = {}
        for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

------------------------------------------------------------------------
-- Records & presence
------------------------------------------------------------------------
function ns:MyRecord()
    local rec = ns.db.chars[ns.me]
    if not rec then
        rec = { profs = {}, recipes = {}, hash = "" }
        ns.db.chars[ns.me] = rec
    end
    rec.profs = rec.profs or {}
    rec.recipes = rec.recipes or {}
    return rec
end

function ns:GetRecord(name)
    if ns.testPlayers and ns.testPlayers[name] then return ns.testPlayers[name] end
    if ns.testChars and ns.testChars[name] then return ns.testChars[name] end
    return ns.db.chars[name] or ns.db.players[name]
end

function ns:IsMine(name) return ns.db.chars[name] ~= nil end

-- your characters (plus sample alts while test mode is on)
function ns:MyChars()
    local t = {}
    for n, r in pairs(ns.db.chars) do t[n] = r end
    if ns.testChars then
        for n, r in pairs(ns.testChars) do t[n] = r end
    end
    return t
end

-- "Busy": still listed as a crafter, but marked busy and without a Whisper button
function ns:IsBusy(name)
    local rec = ns:GetRecord(name)
    return rec and rec.busy and true or false
end

function ns:SetBusy(busy)
    if not ns.me then return end
    ns:MyRecord().busy = busy and true or nil
    ns:BroadcastHello(false)
    ns.Print(busy and "You're now |cffffba45Busy|r. You stay listed as a crafter, but others see you as busy with no Whisper button."
        or "You're now |cff52de7cAvailable to craft|r.")
    ns:Fire("PLAYERS")
end

-- the share setting, narrowed by this character's own "Share this character" toggle
function ns:EffectiveScope()
    local rec = ns.me and ns.db.chars[ns.me]
    if rec and rec.share == false then return "NONE" end
    return ns.settings.shareScope
end

ns:On("PLAYER_LOGOUT", function()
    if ns.me and ns.db.chars[ns.me] then ns.db.chars[ns.me].lastSeen = time() end
end)

-- Everyone we know about: other users, your own characters, and test players.
function ns:AllPlayers()
    local t = {}
    for n, r in pairs(ns.db.players) do
        if not ns.db.chars[n] then t[n] = r end
    end
    for n, r in pairs(ns.db.chars) do t[n] = r end
    if ns.testPlayers then
        for n, r in pairs(ns.testPlayers) do t[n] = r end
    end
    return t
end

ns.presence = {}

function ns:IsOnline(name)
    if name == ns.me then return true end
    if ns.testPlayers and ns.testPlayers[name] then return ns.testPlayers[name].online end
    local p = ns.presence[name]
    if not p or not p.state then return false end
    if p.src == "addon" then return (GetTime() - p.t) < ns.ONLINE_TIMEOUT end
    return true
end

function ns:SetOnline(name, state, source)
    if not name or name == ns.me then return end
    local was = ns:IsOnline(name)
    local p = ns.presence[name] or {}
    ns.presence[name] = p
    p.state, p.t, p.src, p.expired = state and true or false, GetTime(), source, nil
    if state then
        local rec = ns.db.players[name]
        if rec then rec.lastSeen = time() end
    end
    local now = ns:IsOnline(name)
    if now ~= was then ns:Fire("PRESENCE", name, now) end
end

function ns:OnlineCount()
    local n = 0
    for name in pairs(ns:AllPlayers()) do
        if name ~= ns.me and not ns:IsMine(name) and ns:IsOnline(name) then n = n + 1 end
    end
    return n
end

function ns:ResetData()
    wipe(ns.db.players)
    wipe(ns.presence)
    ns:MarkIndexDirty()
    ns:Fire("PLAYERS")
    ns.Print("Forgot all other players. Their data will come back as they announce themselves.")
end

------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    ArtisanNetDB = ArtisanNetDB or {}
    CopyDefaults(DEFAULTS, ArtisanNetDB)
    ns.db = ArtisanNetDB
    ns.settings = ns.db.settings
    if ns.W and ns.W.ApplyStyle then ns.W.ApplyStyle() end

    local cutoff = time() - (ns.settings.pruneDays or 30) * 86400
    for n, r in pairs(ns.db.players) do
        if (r.lastSeen or 0) < cutoff then ns.db.players[n] = nil end
    end
end)

-- Re-key saved data to the current name format. 1.0.4 to 1.4.0 keyed everyone as
-- "First-Realm" on Forever; the surname survives in rec.display when we heard it.
function ns:MigrateNames()
    local function Rekey(tbl, isChars)
        local old = {}
        for n, r in pairs(tbl) do old[n] = r end
        for n, r in pairs(old) do
            local k
            local legacy = not n:find(" ", 1, true) and n:find("-", 1, true)
            if ns.splitNames then
                local myGuid = UnitGUID and UnitGUID("player")
                local mine = (r.guid and r.guid == myGuid) or (not r.guid and r.display == ns.me)
                if isChars and (n == ns.myOldKey or n == ns.myFirst) and n ~= ns.me then
                    -- "Scryptik-Realm" / "Scryptik" could be any character named Scryptik:
                    -- only take it over when it is provably this one
                    k = mine and ns.me or n
                elseif legacy and r.display and r.display:find(" ", 1, true) then
                    k = r.display
                elseif legacy then
                    -- an alt keeps its old key until you log in on it; another player we only
                    -- knew by first name can't be whispered, so forget them until heard again
                    k = isChars and n or false
                else
                    k = ns.FullName(n)
                end
            else
                k = ns.FullName(n)
            end
            if k == false then
                tbl[n] = nil
            elseif k ~= n then
                tbl[n] = nil
                local cur = tbl[k]
                if not cur then
                    tbl[k] = r
                elseif isChars then
                    -- keep the richer record (the one with recipes), but take the newer sightings
                    if not next(cur.recipes or {}) and next(r.recipes or {}) then tbl[k] = r; cur, r = r, cur end
                    cur.lastSeen = math.max(cur.lastSeen or 0, r.lastSeen or 0)
                end
            end
        end
    end
    Rekey(ns.db.chars, true)
    Rekey(ns.db.players, false)
end

-- Write this character's basics, remembering what was there so a wrong name can be undone.
local function StampMyRecord()
    local existing = ns.db.chars[ns.me]
    ns.loginSnapshot = { key = ns.me, existed = existing ~= nil,
        class = existing and existing.class, level = existing and existing.level,
        lastSeen = existing and existing.lastSeen }
    local rec = ns:MyRecord()
    rec.class = select(2, UnitClass("player"))
    rec.level = UnitLevel("player")
    rec.lastSeen = time()
    rec.guid = UnitGUID and UnitGUID("player")
end

-- The name read at login turned out to be someone else's: undo what was written under it
-- and switch to the right one.
function ns:Reidentify()
    local snap = ns.loginSnapshot
    if snap and snap.key == ns.me then
        local rec = ns.db.chars[snap.key]
        if not snap.existed then
            ns.db.chars[snap.key] = nil
        elseif rec then
            rec.class, rec.level, rec.lastSeen = snap.class, snap.level, snap.lastSeen
        end
    end
    ns.me = ns.DetectSplitNames()
    ns.myLoginName = UnitName("player")
    ns:MigrateNames()
    ns.db.players[ns.me] = nil
    StampMyRecord()
    ns:ScanSkillLevels()
    ns:RebuildPayload()
    ns:MarkIndexDirty()
    ns:Fire("PLAYERS")
    if ns.BroadcastHello then ns:BroadcastHello(false) end
end

local function Init()
    ns.me = ns.DetectSplitNames()
    ns.myLoginName = UnitName("player")
    ns.loginTime = GetTime()
    ns.session = ns.B36(math.random(1, 2000000000))
    ns:MigrateNames()
    ns.db.players[ns.me] = nil
    for n in pairs(ns.db.chars) do ns.db.players[n] = nil end
    StampMyRecord()

    ns:ScanSkillLevels()
    ns:RebuildPayload()
    ns:MarkIndexDirty()
    ns:InitComm()
    ns:InitExtras()
    ns:Fire("READY")

    -- double-check the name once everything has settled
    for _, delay in ipairs({ 10, 30 }) do
        C_Timer.After(delay, function()
            if UnitName("player") ~= ns.myLoginName then ns:Reidentify() end
        end)
    end
end

-- Start once the character is in the world and its name reads the same twice in a row.
local initStarted = false
ns:On("PLAYER_ENTERING_WORLD", function()
    if initStarted then return end
    initStarted = true
    local tries = 0
    local function Attempt()
        tries = tries + 1
        local a = UnitName("player")
        C_Timer.After(0.5, function()
            if UnitName("player") ~= a and tries < 8 then Attempt() else Init() end
        end)
    end
    C_Timer.After(1, Attempt)
end)

ns:On("PLAYER_LEVEL_UP", function(level)
    if ns.me then ns:MyRecord().level = level end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_ARTISANNET1 = "/artisan"
SLASH_ARTISANNET2 = "/an"
SlashCmdList.ARTISANNET = function(msg)
    if not ns.me then
        ns.Print("Still loading, try again in a moment.")
        return
    end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        ns:ToggleUI()
    elseif cmd == "search" or cmd == "s" then
        ns:ShowUI("search", nil, rest)
    elseif cmd == "who" then
        ns:PrintWho(rest)
    elseif cmd == "players" then
        ns:ShowUI("players")
    elseif cmd == "settings" or cmd == "config" then
        ns:ShowUI("settings")
    elseif cmd == "scan" then
        ns:ScanSkillLevels()
        ns:RebuildPayload()
        ns.Print("Skill levels rescanned. Open each profession window to capture its recipes.")
    elseif cmd == "ping" and rest ~= "" then
        local name, many = ns:ResolveName(rest)
        if ns.splitNames and not name:find(" ", 1, true) then
            if (many or 0) > 1 then
                ns.Print("More than one player named " .. name .. " is known. Use their full name, like /artisan ping " .. name .. " Surname.")
                return
            end
            ns.Print("Tip: on WoW: Forever use the full name, like /artisan ping " .. name .. " Surname. Trying anyway...")
        end
        ns.Print("Pinging " .. ns.Short(name) .. "...")
        ns:Ping(name, true)
    elseif cmd == "busy" then
        ns:SetBusy(not ns:MyRecord().busy)
    elseif cmd == "available" then
        ns:SetBusy(false)
    elseif cmd == "add" and rest ~= "" then
        ns:AddContact(rest)
    elseif cmd == "status" then
        ns:PrintStatus()
    elseif cmd == "broadcast" then
        ns:BroadcastHello(false)
        ns.Print("Presence sent.")
    elseif cmd == "test" then
        ns:ToggleTestMode()
    elseif cmd == "resetpos" then
        wipe(ns.settings.positions)
        ns.Print("Pop-up positions reset. They'll appear in their default spots next time.")
    elseif cmd == "minimap" then
        ns.settings.minimap.hide = not ns.settings.minimap.hide
        ns:UpdateMinimap()
    elseif cmd == "reset" then
        ns:ResetData()
    else
        ns.Print("commands:")
        print("  /artisan  - open the window")
        print("  /artisan search <text>  - find a crafter")
        print("  /artisan who <text>  - list crafters in chat")
        print("  /artisan ping <name>  - check if a player is online")
        print("  /artisan busy  - switch between Available to craft and Busy")
        print("  /artisan add <First Surname>  - add an addon user outside your guild to your contacts")
        print("  /artisan status  - network check (who you can see, messages sent and received)")
        print("  /artisan resetpos  - put moved pop-ups back in their default spots")
        print("  /artisan test  - add sample players to try every screen (run again to turn off)")
        print("  /artisan scan | broadcast | minimap | reset")
    end
end
