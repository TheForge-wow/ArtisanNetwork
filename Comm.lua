-- Artisan Network: addon-to-addon messaging, presence and data sync
--
-- Every message is one addon message on prefix ns.PREFIX, fields split by "^".
-- WoW: Forever only delivers addon messages on GUILD, PARTY / RAID / INSTANCE_CHAT and
-- WHISPER (whispers must be addressed to "First Surname", see ns.TellName).
--
--   H^ver^scope^hash^login^summary^class^level^session^busy^outside^faction^note
--        hello / heartbeat (GUILD, group, WHISPER). scope A/G/N = everyone / guild / nobody.
--        hash and summary ("id.rank.max[.spec]," per profession) and note are only filled
--        in when the receiver may see our recipes. login "1" asks them to hello back.
--   Q^hash                      "send me your recipe list" (WHISPER)
--   D^hash^part^total^chunk     recipe list split into chunks of CHUNK bytes (WHISPER);
--                               blocks "id:rank:max:spells:items:outputs:spec" joined by ";"
--   R^recipeKey^note            crafting request (WHISPER to each available crafter)
--   K^name,name,...             introductions: contacts a guildmate has met (GUILD only)
--   P / O                       ping / pong (WHISPER)
--   B                           logging out (GUILD, group, a few contacts)
--
-- Compatibility: older versions read fields by position and ignore extra ones, so new
-- data only ever goes at the END of a message or block, and existing fields never
-- change meaning. Breaking that splits the network between versions.
local ADDON, ns = ...

local SEP = "^"
local Handlers = {}   -- message handlers by first letter, filled in below
local CHUNK = 200
local MAX_INFLIGHT = 3

------------------------------------------------------------------------
-- Throttled send queue
------------------------------------------------------------------------
local queue = {}
local tokens, MAX_TOKENS, RATE = 6, 6, 1.0   -- burst of 6, then ~1 message per second

-- message counters for /artisan status
ns.stats = { sent = {}, recv = {}, fail = {}, lastErr = {}, senders = {}, echo = {} }
local function Count(t, k) t[k] = (t[k] or 0) + 1 end

local function ResultName(r)
    if Enum and Enum.SendAddonMessageResult then
        for name, v in pairs(Enum.SendAddonMessageResult) do
            if v == r then return name end
        end
    end
    return tostring(r)
end

local lastWhisperTo = {}   -- lower-case name -> when we last sent them an addon whisper
ns.lastWhisperTo = lastWhisperTo

local function RawSend(msg, chatType, target)
    if chatType == "WHISPER" then
        target = ns.TellName(target)
        if target then lastWhisperTo[target:lower()] = GetTime() end
    end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local ok, r = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, chatType, target)
        if not ok then                            -- hard error: drop it
            Count(ns.stats.fail, chatType)
            ns.stats.lastErr[chatType] = tostring(r)
            return true
        end
        if r == false then return false end       -- older clients return false when throttled
        if type(r) == "number" and Enum and Enum.SendAddonMessageResult then
            local E = Enum.SendAddonMessageResult
            if r == E.AddonMessageThrottle or r == E.ChannelThrottle then return false end
            if E.Success ~= nil and r ~= E.Success then
                Count(ns.stats.fail, chatType)
                ns.stats.lastErr[chatType] = ResultName(r)
                return true
            end
        end
        Count(ns.stats.sent, chatType)
        return true
    elseif SendAddonMessage then
        pcall(SendAddonMessage, ns.PREFIX, msg, chatType, target)
    end
    return true
end

function ns:Send(msg, chatType, target, priority)
    local item = { msg = msg, chatType = chatType, target = target, tries = 0 }
    if priority then table.insert(queue, 1, item) else queue[#queue + 1] = item end
end

-- Background lane: contact check-ins and introductions. Only sent when nothing else is
-- waiting and some of the burst allowance is left, so recipes and requests never wait.
local bgQueue, bgKeys = {}, {}
local BG_MAX = 200
function ns:SendBg(msg, chatType, target, key)
    key = key or (chatType .. ":" .. tostring(target) .. ":" .. msg:sub(1, 1))
    if bgKeys[key] then
        bgKeys[key].msg = msg   -- newer content replaces the queued one
        return
    end
    if #bgQueue >= BG_MAX then return end
    local item = { msg = msg, chatType = chatType, target = target, key = key }
    bgKeys[key] = item
    bgQueue[#bgQueue + 1] = item
end
function ns:BgQueued() return #bgQueue end

local function Pump()
    -- hold traffic during combat; it's never urgent and some clients restrict it there
    if InCombatLockdown() then return end
    tokens = math.min(MAX_TOKENS, tokens + RATE * 0.25)
    while tokens >= 1 and #queue > 0 do
        local item = table.remove(queue, 1)
        if RawSend(item.msg, item.chatType, item.target) then
            tokens = tokens - 1
        else
            item.tries = item.tries + 1
            if item.tries < 4 then table.insert(queue, 1, item) end
            tokens = 0
            break
        end
    end
    if #queue == 0 and tokens >= 3 and #bgQueue > 0 then
        local item = table.remove(bgQueue, 1)
        bgKeys[item.key] = nil
        if RawSend(item.msg, item.chatType, item.target) then tokens = tokens - 1 else tokens = 0 end
    end
end

------------------------------------------------------------------------
-- Guild / friends helpers
------------------------------------------------------------------------
ns.guildies = {}

-- The guild of the character you're playing now (players are saved for the whole account,
-- so "in my guild" must mean this character's guild, not any of your characters').
function ns:MyGuild()
    if not IsInGuild() then return nil end
    local g = GetGuildInfo and GetGuildInfo("player")
    return (g and g ~= "") and g or nil
end

function ns:IsGuildmate(name)
    if ns.guildies[name] then return true end
    local g = ns:MyGuild()
    local rec = ns.db.players[name]
    return (g and rec and rec.guildName == g) or false
end

local function ScanGuild()
    if not IsInGuild() then wipe(ns.guildies) return end
    local seen = {}
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name then
            name = ns.FullName(name)
            seen[name] = true
            local rec = ns.db.players[name]
            if rec then
                rec.guildName = ns:MyGuild()
                if online then
                    if not ns:IsOnline(name) then ns:SetOnline(name, true, "guild") end
                else
                    ns:SetOnline(name, false, "guild")
                end
            end
        end
    end
    ns.guildies = seen
end

-- how many in your guild run Artisan Network (you included), and the guild's size.
-- nil when you're not in a guild or the roster hasn't loaded yet
function ns:GuildAdoption()
    if not IsInGuild() then return nil end
    local total, users = 0, 1
    for name in pairs(ns.guildies) do
        total = total + 1
        local rec = ns.db.players[name]
        if rec and rec.version and not ns:IsMine(name) then users = users + 1 end
    end
    if total == 0 then return nil end
    return math.min(users, total), total
end

local function ScanFriends()
    if not C_FriendList or not C_FriendList.GetNumFriends then return end
    for i = 1, (C_FriendList.GetNumFriends() or 0) do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name then
            local name = ns.FullName(info.name)
            if ns.db.players[name] then ns:SetOnline(name, info.connected and true or false, "friend") end
        end
    end
end

local function RequestRoster()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
end

------------------------------------------------------------------------
-- Presence
------------------------------------------------------------------------
local SCOPE_CHAR = { ALL = "A", GUILD = "G", NONE = "N" }

-- Player-typed text (crafter notes, request notes) travels inside our messages, so it's
-- kept short and plain: no "^" (our field separator), no "|" (chat escape codes), no
-- line breaks, single spaces. Cut to whole UTF-8 characters.
ns.NOTE_MAX = 60
function ns.CleanText(s, max)
    s = tostring(s or ""):gsub("[%c|^]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    max = max or ns.NOTE_MAX
    if #s > max then
        s = s:sub(1, max)
        -- drop a cut-off multi-byte character at the end
        s = s:gsub("[\192-\255][\128-\191]*$", function(c)
            local lead = c:byte(1)
            local need = lead >= 240 and 4 or lead >= 224 and 3 or 2
            return #c == need and c or ""
        end)
        s = s:match("^(.-)%s*$")
    end
    return s
end

function ns:HelloMsg(login, includeData)
    local rec = ns:MyRecord()
    local scope = ns:EffectiveScope()
    local share = includeData and scope ~= "NONE"
    return table.concat({
        "H", ns.VERSION, SCOPE_CHAR[scope] or "A",
        share and (rec.hash or "") or "",
        login and "1" or "0",
        share and ns:SummaryString(rec.profs) or "",
        rec.class or "", tostring(rec.level or 0),
        ns.session or "",
        rec.busy and "1" or "0",
        ns.settings.outside and "1" or "0",
        (UnitFactionGroup("player") or "?"):sub(1, 1),
        share and ns.CleanText(ns.settings.note) or "",
    }, SEP)
end

-- the party, raid or instance group we're in, as addon messages name it
function ns:GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

-- Hello to our group: players there may be from other guilds or sub-realms. Recipes go in
-- only when we share with everyone.
function ns:GroupHello(login)
    if not ns.settings.outside then return end
    local ch = ns:GroupChannel()
    if not ch then return end
    ns:Send(ns:HelloMsg(login, ns:EffectiveScope() == "ALL"), ch, nil, true)
end

-- Hello to the guild and our group. Contacts outside the guild hear from us through
-- their own login hellos and the 5-minute check-ins.
function ns:BroadcastHello(login)
    if IsInGuild() then
        ns:Send(ns:HelloMsg(login, true), "GUILD", nil, true)
    end
    ns:GroupHello(login)
end

local repliedTo = {}
local function ReplyHello(target)
    if not ns.settings.outside and not ns:IsGuildmate(target) then return end
    if repliedTo[target] and GetTime() - repliedTo[target] < 300 then return end
    repliedTo[target] = GetTime()
    C_Timer.After(1 + math.random() * 9, function()
        local scope = ns:EffectiveScope()
        local include = scope == "ALL" or (scope == "GUILD" and ns:IsGuildmate(target))
        ns:Send(ns:HelloMsg(false, include), "WHISPER", target)
    end)
end

local function SendBye()
    local msg = "B"
    if IsInGuild() then RawSend(msg, "GUILD") end
    local ch = ns:GroupChannel()
    if ch and ns.settings.outside then RawSend(msg, ch) end
    -- tell a few online contacts directly; the rest notice when our check-ins stop
    local n = 0
    for _, name in ipairs(ns:ContactList(true)) do
        if n >= 4 then break end
        RawSend(msg, "WHISPER", name)
        n = n + 1
    end
end

------------------------------------------------------------------------
-- Data requests
------------------------------------------------------------------------
local requests, inflight, incoming, served = {}, {}, {}, {}

function ns:QueueRequest(name, hash, now)
    if inflight[name] and inflight[name].hash == hash then return end
    for _, r in ipairs(requests) do
        if r.name == name then r.hash = hash; return end
    end
    requests[#requests + 1] = { name = name, hash = hash, at = GetTime() + (now and 0 or math.random(2, 12)) }
end

function ns:RequestNow(name)
    local rec = ns.db.players[name]
    inflight[name] = nil
    ns:QueueRequest(name, (rec and rec.hash) or "?", true)
end

local function ProcessRequests()
    local now = GetTime()
    local n = 0
    for name, v in pairs(inflight) do
        if now - v.t > 90 then inflight[name] = nil else n = n + 1 end
    end
    for name, inc in pairs(incoming) do
        if now - inc.t > 120 then incoming[name] = nil end
    end
    local i = 1
    while i <= #requests and n < MAX_INFLIGHT do
        local r = requests[i]
        if now >= r.at then
            table.remove(requests, i)
            if ns:IsOnline(r.name) then
                inflight[r.name] = { hash = r.hash, t = now }
                ns:Send("Q" .. SEP .. r.hash, "WHISPER", r.name)
                n = n + 1
            end
        else
            i = i + 1
        end
    end
end

function ns:SendData(target)
    local rec = ns:MyRecord()
    local payload = ns.myPayload or ""
    local total = math.max(1, math.ceil(#payload / CHUNK))
    for i = 1, total do
        local part = payload:sub((i - 1) * CHUNK + 1, i * CHUNK)
        ns:Send(table.concat({ "D", rec.hash or "", ns.B36(i), ns.B36(total), part }, SEP), "WHISPER", target)
    end
end

function ns:TransferState(name)
    if incoming[name] then return "receiving", incoming[name].n, incoming[name].total end
    if inflight[name] then return "requested" end
end

------------------------------------------------------------------------
-- Contacts: addon users met outside the guild (in a group, introduced by a
-- guildmate, added by name, or who said hello to us). Reached by whisper.
------------------------------------------------------------------------
local CONTACT_DAYS = 14      -- contacts seen this recently get a hello at login
local CONTACT_HELLOS = 60    -- at most this many hellos per round
local CONTACT_CAP = 200      -- contacts kept (oldest forgotten first)
local INTRO_CAP = 300
local INTRO_RETRY = 86400    -- an introduced name that didn't answer is tried again after a day
local INTRO_FORGET = 7 * 86400
local sharedAt = {}          -- name -> when it was last introduced on our guild (by anyone)
ns.pendingAdd = {}           -- lower-case name -> true while /artisan add waits for an answer

local myFaction
local function SameFaction(rec)
    myFaction = myFaction or (UnitFactionGroup("player") or "?"):sub(1, 1)
    return not rec.faction or rec.faction == myFaction
end

-- Any known player outside our guild. Records saved before 1.5.0 have no "via" yet; they
-- count too (PruneContacts marks them "contact" at login).
function ns:IsContact(name, rec)
    rec = rec or ns.db.players[name]
    if not rec or ns:IsGuildmate(name) or ns:IsMine(name) then return false end
    if ns.testPlayers and ns.testPlayers[name] then return false end
    return true
end

-- contacts to whisper, most recently seen first
function ns:ContactList(onlineOnly)
    local list, cutoff = {}, time() - CONTACT_DAYS * 86400
    for name, rec in pairs(ns.db.players) do
        if ns:IsContact(name, rec) and SameFaction(rec) and (rec.lastSeen or 0) >= cutoff
            and (not onlineOnly or ns:IsOnline(name)) then
            list[#list + 1] = name
        end
    end
    table.sort(list, function(a, b) return (ns.db.players[a].lastSeen or 0) > (ns.db.players[b].lastSeen or 0) end)
    while #list > CONTACT_HELLOS do table.remove(list) end
    return list
end

function ns:ContactCounts()
    local total, online = 0, 0
    for name, rec in pairs(ns.db.players) do
        if ns:IsContact(name, rec) then
            total = total + 1
            if ns:IsOnline(name) then online = online + 1 end
        end
    end
    local intros = 0
    for _ in pairs(ns.db.intros) do intros = intros + 1 end
    return total, online, intros
end

local function HelloContacts(login)
    if not ns.settings.outside then return end
    local include = ns:EffectiveScope() == "ALL"
    for _, name in ipairs(ns:ContactList(not login)) do
        ns:SendBg(ns:HelloMsg(login, include), "WHISPER", name, "hello:" .. name:lower())
    end
end

local function PruneContacts()
    local list = {}
    for name, rec in pairs(ns.db.players) do
        -- older saves: an account-wide "in my guild" flag, and "guild" as how we met
        rec.guild = nil
        if rec.via == "guild" then rec.via = nil end
        if ns:IsContact(name, rec) then
            if not rec.via then rec.via = "contact" end   -- saved by a version before 1.5.0
            list[#list + 1] = name
        end
    end
    if #list <= CONTACT_CAP then return end
    table.sort(list, function(a, b) return (ns.db.players[a].lastSeen or 0) > (ns.db.players[b].lastSeen or 0) end)
    for i = CONTACT_CAP + 1, #list do ns.db.players[list[i]] = nil end
end

-- Introductions: "K^Name One,Name Two,..." over GUILD. Only contacts who share with everyone,
-- have the outside option on, are on our faction and were heard from in the last 3 days.
local function ShareIntroductions()
    if not ns.settings.outside or not IsInGuild() then return end
    local names, len, now = {}, 2, GetTime()
    for name, rec in pairs(ns.db.players) do
        if ns:IsContact(name, rec) and rec.scope == "A" and rec.outside and SameFaction(rec)
            and (rec.lastSeen or 0) >= time() - 3 * 86400
            and (not sharedAt[name] or now - sharedAt[name] > 3600)
            and len + #name + 1 <= 230 and #names < 12 then
            names[#names + 1] = name
            len = len + #name + 1
        end
    end
    if #names == 0 then return end
    for _, n in ipairs(names) do sharedAt[n] = now end
    ns:Send("K" .. SEP .. table.concat(names, ","), "GUILD")
end

Handlers.K = function(sender, msg, chatType)
    if chatType ~= "GUILD" or not ns.settings.outside then return end
    local list = msg:sub(3)
    local now = GetTime()
    for name in list:gmatch("[^,]+") do
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if #name >= 2 and #name <= 40 and not name:find("[%^|]") then
            sharedAt[name] = now
            if name ~= ns.me and not ns.db.chars[name] and not ns.db.players[name] and not ns.db.intros[name] then
                ns.db.intros[name] = { from = sender, t = time() }
            end
        end
    end
    -- keep the list bounded
    local n, oldest, oldestT = 0
    for nm, it in pairs(ns.db.intros) do
        n = n + 1
        if not oldestT or it.t < oldestT then oldest, oldestT = nm, it.t end
    end
    if n > INTRO_CAP and oldest then ns.db.intros[oldest] = nil end
end

-- say hello to one introduced player at a time, slowly, in the background
local function ProbeIntroduction()
    if not ns.settings.outside then return end
    local now = time()
    for name, it in pairs(ns.db.intros) do
        if now - (it.t or now) > INTRO_FORGET then
            ns.db.intros[name] = nil
        elseif not it.probed or now - it.probed > INTRO_RETRY then
            it.probed = now
            ns:SendBg(ns:HelloMsg(true, ns:EffectiveScope() == "ALL"), "WHISPER", name, "hello:" .. name:lower())
            return
        end
    end
end

-- /artisan add First Surname
function ns:AddContact(typed)
    local name = ns:ResolveName(typed)
    if not name then return end
    if ns.splitNames and not name:find(" ", 1, true) then
        ns.Print("Use their full first and last name, like /artisan add " .. name .. " Surname.")
        return
    end
    if not ns.settings.outside then
        ns.Print("Turn on \"Find addon users outside my guild\" in Settings first.")
        return
    end
    ns.pendingAdd[name:lower()] = true
    ns.Print("Saying hello to " .. ns.Short(name) .. "...")
    ns:Send(ns:HelloMsg(true, ns:EffectiveScope() == "ALL"), "WHISPER", name, true)
    C_Timer.After(15, function()
        if ns.pendingAdd[name:lower()] then
            ns.pendingAdd[name:lower()] = nil
            ns.Print(ns.Short(name) .. " didn't answer: offline, not running Artisan Network 1.5.0 or newer, "
                .. "on the other faction, or the name isn't quite right.")
        end
    end)
end

------------------------------------------------------------------------
-- Ping
------------------------------------------------------------------------
local pinged = {}   -- keyed by lower-case name: the answer may come back capitalized differently

-- A typed name as the addon knows the player: matched against known players ignoring case,
-- and on WoW: Forever a first name alone is completed when exactly one known player has it.
function ns:ResolveName(typed)
    local full = ns.FullName(typed)
    if not full then return nil end
    local low = full:lower()
    local matches = {}
    for name in pairs(ns:AllPlayers()) do
        local l = name:lower()
        if l == low then return name end
        if ns.splitNames and not low:find(" ", 1, true) and l:sub(1, #low + 1) == low .. " " then
            matches[#matches + 1] = name
        end
    end
    if #matches == 1 then return matches[1] end
    return full, #matches
end

-- Players page "Refresh": announce ourselves and quietly ping everyone we know who isn't
-- showing as online (most recently seen first), in the background lane.
local lastRefresh = -math.huge
ns.REFRESH_COOLDOWN = 30
function ns:RefreshNetwork()
    if GetTime() - lastRefresh < ns.REFRESH_COOLDOWN then return false end
    lastRefresh = GetTime()
    ns:BroadcastHello(false)
    RequestRoster()
    local list, cutoff = {}, time() - 30 * 86400
    for name, rec in pairs(ns.db.players) do
        if not ns:IsMine(name) and not ns:IsOnline(name) and (rec.lastSeen or 0) >= cutoff and SameFaction(rec)
            and (ns:IsGuildmate(name) or ns.settings.outside) then
            list[#list + 1] = name
        end
    end
    table.sort(list, function(a, b) return (ns.db.players[a].lastSeen or 0) > (ns.db.players[b].lastSeen or 0) end)
    for i = 1, math.min(40, #list) do
        local name = list[i]
        pinged[name:lower()] = { t = GetTime(), report = false }
        ns:SendBg("P", "WHISPER", name, "ping:" .. name:lower())
    end
    return true, math.min(40, #list)
end
function ns:RefreshReadyIn()
    return math.max(0, math.ceil(ns.REFRESH_COOLDOWN - (GetTime() - lastRefresh)))
end

function ns:Ping(name, report)
    if not name or name == ns.me then return end
    local key = name:lower()
    pinged[key] = { t = GetTime(), report = report }
    ns:Send("P", "WHISPER", name, true)
    C_Timer.After(8, function()
        local p = pinged[key]
        if p and p.t and GetTime() - p.t >= 7.9 then
            pinged[key] = nil
            if report then
                ns.Print(ns.Short(name) .. " did not answer (offline, or not running Artisan Network).")
            end
            ns:Fire("PLAYERS")
        end
    end)
end

------------------------------------------------------------------------
-- Incoming messages
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Update notice: addons can't reach the internet, so a new version is learned from
-- other players who already run it. The newest version seen is remembered between
-- sessions and forgotten if nobody has been seen with it for 14 days.
------------------------------------------------------------------------
local notifiedUpdate
local UPDATE_EXPIRY = 14 * 86400

function ns:UpdateAvailable()
    local u = ns.db and ns.db.update
    if u and u.ver and ns.VersionNewer(u.ver, ns.VERSION) and time() - (u.t or 0) < UPDATE_EXPIRY then
        return u.ver
    end
end

function ns:NotifyUpdate()
    local v = ns:UpdateAvailable()
    if not v or notifiedUpdate == v then return end
    notifiedUpdate = v
    ns.Print("Version |cffffffff" .. v .. "|r is available (you have " .. ns.VERSION .. "). Update through CurseForge.")
    if ns.ShowToast then
        ns.ShowToast(ns.MEDIA .. "Icon",
            "|cff" .. ns.AccentHex() .. "Artisan Network " .. v .. "|r is available",
            "Update through CurseForge. You have v" .. ns.VERSION .. ".")
    end
    ns:Fire("UPDATE")
end

function ns:NoteVersion(ver)
    if type(ver) ~= "string" or not ver:match("^%d+%.%d+%.%d+$") then return end
    if not ns.VersionNewer(ver, ns.VERSION) then return end
    -- ignore wildly higher numbers (typos or someone messing about)
    local major, mine = tonumber(ver:match("^(%d+)")), tonumber(ns.VERSION:match("^(%d+)")) or 0
    if major > mine + 1 then return end
    local u = ns.db.update
    if not u or not u.ver or ns.VersionNewer(ver, u.ver) then
        ns.db.update = { ver = ver, t = time() }
        ns:NotifyUpdate()
    elseif u.ver == ver then
        u.t = time()
    end
end


-- how we came to know a player, strongest first
local VIA_RANK = { guild = 1, added = 2, group = 3, intro = 4, contact = 5 }

Handlers.H = function(sender, msg, chatType)
    local _, ver, scope, hash, login, summary, class, level, _, busy, outside, faction, note = strsplit(SEP, msg)
    local fromGuild = chatType == "GUILD" or ns:IsGuildmate(sender)
    -- with "Find addon users outside my guild" off, strangers are ignored
    if not fromGuild and not ns.settings.outside and not ns.db.players[sender] then return end
    local rec = ns.db.players[sender]
    if not rec then
        rec = { profs = {}, recipes = {} }
        ns.db.players[sender] = rec
    end
    local via = (fromGuild and "guild")
        or ((chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT") and "group")
        or (ns.pendingAdd and ns.pendingAdd[sender:lower()] and "added")
        or (ns.db.intros[sender] and "intro")
        or "contact"
    -- guild membership is per character (rec.guildName), so "via" only records other ways we met
    if via ~= "guild" and (not rec.via or (VIA_RANK[via] or 9) < (VIA_RANK[rec.via] or 9)) then rec.via = via end
    if via == "added" then
        ns.pendingAdd[sender:lower()] = nil
        ns.Print(ns.Short(sender) .. " added to your contacts.")
    end
    ns.db.intros[sender] = nil
    rec.outside = outside ~= "0" or nil
    if faction and faction ~= "" then rec.faction = faction end
    if class and class ~= "" then rec.class = class end
    if ns.lastDisplay then rec.display = ns.lastDisplay end
    local wasBusy = rec.busy
    rec.busy = (busy == "1") or nil
    if wasBusy ~= rec.busy then ns:Fire("PRESENCE", sender, true) end
    rec.level = tonumber(level) or rec.level
    rec.version = ver
    rec.scope = scope
    rec.lastSeen = time()
    if chatType == "GUILD" then rec.guildName = ns:MyGuild() end

    -- "Nobody", or "Guild only" when we're not in their guild (their message then carries no
    -- recipe hash): forget any recipes we saved from them earlier
    local notForUs = scope == "G" and (not hash or hash == "") and chatType ~= "GUILD" and not ns:IsGuildmate(sender)
    if scope == "N" or notForUs then
        if rec.hash or next(rec.recipes or {}) then
            rec.recipes, rec.hash = {}, nil
            ns:MarkIndexDirty()
        end
        rec.note = nil
    elseif hash and hash ~= "" then
        if summary and summary ~= "" then rec.profs = ns:DecodeSummary(summary) end
        -- the note comes with the recipe data (older versions send none)
        note = ns.CleanText(note, 80)
        rec.note = note ~= "" and note or nil
        if hash ~= rec.hash then ns:QueueRequest(sender, hash) end
    end

    ns:SetOnline(sender, true, "addon")
    if login == "1" then ReplyHello(sender) end

    ns:NoteVersion(ver)
    ns:Fire("PLAYERS")
end

Handlers.Q = function(sender)
    local scope = ns:EffectiveScope()
    if scope == "NONE" then return end
    if scope == "GUILD" and not ns:IsGuildmate(sender) then return end
    if served[sender] and GetTime() - served[sender] < 30 then return end
    served[sender] = GetTime()
    ns:SendData(sender)
end

Handlers.D = function(sender, msg)
    local _, hash, idx, total, part = strsplit(SEP, msg, 5)
    idx, total = ns.UnB36(idx), ns.UnB36(total)
    if not idx or not total or total < 1 or total > 400 or idx > total then return end
    local inc = incoming[sender]
    if not inc or inc.hash ~= hash or inc.total ~= total then
        inc = { hash = hash, total = total, parts = {}, n = 0 }
        incoming[sender] = inc
    end
    inc.t = GetTime()
    if not inc.parts[idx] then
        inc.parts[idx] = part or ""
        inc.n = inc.n + 1
    end
    if inc.n < inc.total then
        ns:Debounce("transferui", 1, function() ns:Fire("PLAYERS") end)
        return
    end

    local payload = table.concat(inc.parts, "", 1, inc.total)
    incoming[sender], inflight[sender] = nil, nil
    local profs, recipes = ns:DecodePayload(payload)
    local rec = ns.db.players[sender] or {}
    ns.db.players[sender] = rec
    rec.profs, rec.recipes, rec.hash = profs, recipes, hash
    rec.lastSeen, rec.updated = time(), time()
    ns:SetOnline(sender, true, "addon")
    ns:MarkIndexDirty()
    ns:Fire("PLAYERS")
end

------------------------------------------------------------------------
-- Crafting requests: "R^recipeKey^note", whispered to each online,
-- available crafter who knows the recipe (never broadcast).
------------------------------------------------------------------------
local MAX_REQUEST_TARGETS = 10
local lastRequest, lastRequestFrom = {}, {}

local function CleanNote(note) return ns.CleanText(note, 80) end

function ns:RequestTargets(e)
    local t = {}
    for _, c in ipairs(ns:SortedCrafters(e)) do
        if c.online and not c.busy and not ns:IsMine(c.name)
            and not (ns.testPlayers and ns.testPlayers[c.name]) then
            t[#t + 1] = c.name
            if #t >= MAX_REQUEST_TARGETS then break end
        end
    end
    return t
end

-- Request history: the last 30 requests you sent or received, kept for a day so a
-- closed pop-up or a /reload doesn't lose them. Newest first.
local LOG_MAX, LOG_AGE = 30, 24 * 3600
function ns:RequestLog()
    local log = ns.db.requestLog
    if type(log) ~= "table" then log = {}; ns.db.requestLog = log end
    local cutoff = time() - LOG_AGE
    for i = #log, 1, -1 do
        if type(log[i]) ~= "table" or (log[i].t or 0) < cutoff then table.remove(log, i) end
    end
    return log
end

local function LogRequest(entry)
    local log = ns:RequestLog()
    entry.t = time()
    table.insert(log, 1, entry)
    while #log > LOG_MAX do table.remove(log) end
    if entry.dir == "in" then ns.db.requestsUnseen = (ns.db.requestsUnseen or 0) + 1 end
    ns:Fire("REQUESTS")
end

function ns:ClearRequestLog()
    ns.db.requestLog = {}
    ns.db.requestsUnseen = 0
    ns:Fire("REQUESTS")
end

-- returns number sent, or nil and a reason
function ns:SendRequest(key, note)
    local e = ns:GetIndex() and ns.byKey[key]
    if not e then return nil, "Unknown recipe." end
    if ns.RecipeBoP(key) then return nil, "Bind on Pickup: crafters can only make this for themselves." end
    if lastRequest[key] and GetTime() - lastRequest[key] < 60 then
        return nil, "You just requested this. Wait a minute before asking again."
    end
    local targets = ns:RequestTargets(e)
    if #targets == 0 then return nil, "Nobody who can craft this is online and available right now." end
    lastRequest[key] = GetTime()
    local msg = "R" .. SEP .. key .. SEP .. CleanNote(note)
    for _, name in ipairs(targets) do ns:Send(msg, "WHISPER", name, true) end
    LogRequest({ dir = "out", key = key, note = CleanNote(note), n = #targets })
    return #targets
end

local function IKnow(key)
    local kind, id = key:sub(1, 1), tonumber(key:sub(2))
    for _, rec in pairs(ns.db.chars) do
        for _, r in pairs(rec.recipes or {}) do
            for _, v in ipairs((kind == "s" and r.s or r.i) or {}) do
                if v == id then return true end
            end
        end
    end
end

Handlers.R = function(sender, msg)
    if not ns.settings.requests or ns:MyRecord().busy then return end
    local _, key, note = strsplit(SEP, msg, 3)
    if type(key) ~= "string" or not key:match("^[si]%d+$") or not IKnow(key) then return end
    if lastRequestFrom[sender] and GetTime() - lastRequestFrom[sender] < 30 then return end
    lastRequestFrom[sender] = GetTime()
    note = CleanNote(note)
    LogRequest({ dir = "in", key = key, note = note, from = sender })
    local rname, icon, link = ns.RecipeInfo(key)
    local rec = ns.db.players[sender]
    local who = (rec and rec.display) or ns.Short(sender)
    local colored = "|cff" .. ns.ClassHex(rec and rec.class) .. who .. "|r"
    ns.Print(colored .. " is looking for " .. (link or rname or "a recipe you know")
        .. (note ~= "" and (': "' .. note .. '"') or "") .. ". Open the pop-up or whisper them to answer.")
    if ns.ShowToast then
        ns.ShowToast(icon, colored .. " wants " .. (rname or "a craft"),
            note ~= "" and note or "Click to whisper them.", nil,
            function() ns:WhisperText(sender, "Hi! I can craft " .. (link or rname or "that") .. " for you.") end)
    end
end

Handlers.P = function(sender)
    ns:Send("O", "WHISPER", sender, true)
    if ns.db.players[sender] then ns:SetOnline(sender, true, "addon") end
end

Handlers.O = function(sender)
    local p = pinged[sender:lower()]
    pinged[sender:lower()] = nil
    ns:SetOnline(sender, true, "addon")
    if p and p.report then ns.Print(ns.Short(sender) .. " is online and running Artisan Network.") end
    ns:Fire("PLAYERS")
end

Handlers.B = function(sender)
    ns:SetOnline(sender, false, "addon")
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------
function ns:InitComm()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(ns.PREFIX)
    end

    ns:On("CHAT_MSG_ADDON", function(prefix, msg, chatType, sender)
        if prefix ~= ns.PREFIX or type(msg) ~= "string" then return end
        local raw = sender
        sender = ns.FullName(sender)
        if not sender then return end
        if sender == ns.me then
            -- our own echo: learn our last name for display, then ignore it
            local d = ns.DisplayName(raw)
            if d then ns:MyRecord().display = d end
            Count(ns.stats.echo, chatType)
            return
        end
        -- our own broadcast echoed back under a name we didn't know we had (Forever surname)
        if msg:sub(1, 1) == "H" and ns.session and select(9, strsplit(SEP, msg)) == ns.session then
            Count(ns.stats.echo, chatType)
            if ns.splitNames and sender:sub(1, #ns.me + 1) == ns.me .. " " then ns:AdoptMyName(sender) end
            return
        end
        ns.lastDisplay = ns.DisplayName(raw)
        Count(ns.stats.recv, chatType)
        ns.stats.senders[sender] = true
        ns.stats.lastRecv = { who = sender, t = GetTime(), via = chatType }
        local h = Handlers[msg:sub(1, 1)]
        if h then h(sender, msg, chatType) end
    end)

    local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if addFilter then
        -- "No player named X is currently playing" -> mark offline, and hide the message
        -- when it was caused by our own background whisper
        local pattern
        if ERR_CHAT_PLAYER_NOT_FOUND_S then
            pattern = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            pattern = "^" .. pattern:gsub("%%s", "(.+)") .. "$"
        end
        addFilter("CHAT_MSG_SYSTEM", function(_, _, text)
            if not pattern or type(text) ~= "string" then return end
            local who = text:match(pattern)
            if not who then return end
            local full = ns.FullName(who)
            local key = full and full:lower()
            -- only lines caused by our own addon whispers are hidden: your own /w to someone
            -- offline still shows the usual message
            local ours = (lastWhisperTo[who:lower()] and GetTime() - lastWhisperTo[who:lower()] < 15)
                or (key and pinged[key])
            if not ours then return end
            if ns.db.players[full] then ns:SetOnline(full, false, "addon") end
            inflight[full] = nil
            if ns.db.intros[full] then ns.db.intros[full].failed = time() end
            if key and pinged[key] and pinged[key].report then
                ns.Print(ns.Short(full) .. " is offline, or that name isn't quite right"
                    .. (ns.splitNames and " (use their full first and last name)." or "."))
            end
            if key then pinged[key] = nil end
            return true
        end)
    end

    ns:On("GUILD_ROSTER_UPDATE", function() ns:Debounce("guildscan", 1, ScanGuild) end)
    ns:On("FRIENDLIST_UPDATE", function() ns:Debounce("friendscan", 1, ScanFriends) end)

    ns:On("PLAYER_CAMPING", SendBye)
    ns:On("PLAYER_QUITING", SendBye)
    ns:On("LOGOUT_CANCEL", function() ns:BroadcastHello(false) end)
    ns:On("QUIT_CANCEL", function() ns:BroadcastHello(false) end)
    ns:On("PLAYER_GUILD_UPDATE", function() ns:Debounce("guildhello", 5, function() ns:BroadcastHello(false) end) end)

    C_Timer.NewTicker(0.25, Pump)
    C_Timer.NewTicker(1, ProcessRequests)

    -- a few seconds after login, once the game is settled
    C_Timer.After(6, function()
        RequestRoster()
        C_Timer.After(3, function() ns:BroadcastHello(true) end)
    end)
    -- a second hello in case the first was lost while the game was still loading; anyone who
    -- already answered the first won't answer again (they only reply once per 5 minutes)
    C_Timer.After(60 + math.random(0, 15), function()
        RequestRoster()
        ns:BroadcastHello(true)
    end)

    C_Timer.After(ns.HEARTBEAT * (0.5 + math.random() * 0.5), function()
        ns:BroadcastHello(false)
        C_Timer.NewTicker(ns.HEARTBEAT, function() ns:BroadcastHello(false) end)
    end)

    C_Timer.NewTicker(60, RequestRoster)

    -- outside the guild: groups, contacts and introductions
    local groupSize = 0
    ns:On("GROUP_ROSTER_UPDATE", function()
        ns:Debounce("grouphello", 3, function()
            local n = GetNumGroupMembers and GetNumGroupMembers() or 0
            -- someone new joined (or we joined a group): say hello so they can reply
            if n > groupSize then ns:GroupHello(true) end
            groupSize = n
        end)
    end)
    PruneContacts()
    C_Timer.After(20, function() HelloContacts(true) end)
    -- second round, like the guild's: contacts who already answered won't answer twice
    C_Timer.After(75 + math.random(0, 15), function() HelloContacts(true) end)
    C_Timer.After(ns.HEARTBEAT * (0.6 + math.random() * 0.4), function()
        HelloContacts(false)
        C_Timer.NewTicker(ns.HEARTBEAT, function() HelloContacts(false) end)
    end)
    C_Timer.After(120 + math.random(0, 300), function()
        ShareIntroductions()
        C_Timer.NewTicker(900, ShareIntroductions)
    end)
    C_Timer.NewTicker(20, ProbeIntroduction)

    -- remind about an update seen in an earlier session; clear it once you've updated
    C_Timer.After(12, function()
        if ns:UpdateAvailable() then ns:NotifyUpdate() else ns.db.update = nil end
    end)

    -- notice when addon users silently time out (crash, disconnect)
    C_Timer.NewTicker(20, function()
        local now = GetTime()
        for name, p in pairs(ns.presence) do
            if p.src == "addon" and p.state and not p.expired and now - p.t >= ns.ONLINE_TIMEOUT then
                p.expired = true
                ns:Fire("PRESENCE", name, false)
            end
        end
    end)
end

------------------------------------------------------------------------
-- /artisan status
------------------------------------------------------------------------
local function Counts(t)
    local group = (t.PARTY or 0) + (t.RAID or 0) + (t.INSTANCE_CHAT or 0)
    return string.format("guild %d, group %d, whisper %d", t.GUILD or 0, group, t.WHISPER or 0)
end

function ns:PrintStatus()
    local W, G, D = "|cffffffff", "|cff52de7c", "|cffe0b050"
    ns.Print("Network status  |cff8a8b94(v" .. ns.VERSION .. ")|r")
    print("  Character: " .. W .. (ns.me or "?") .. "|r  (" .. (UnitFactionGroup("player") or "?") .. ")"
        .. "  realm " .. ns.Realm())
    if ns.splitNames then
        print("  WoW: Forever mode: " .. G .. "on|r (whispers go to \"First Surname\")")
    end

    local users, total = ns:GuildAdoption()
    print("  Guild: " .. (IsInGuild() and (G .. "yes|r") or "no")
        .. (users and ("  (" .. users .. " of " .. total .. " use Artisan Network)") or ""))
    if ns.BrokerStatus then print("  Data bar: " .. ns.BrokerStatus()) end
    if ns.settings.outside then
        local total, online, intros = ns:ContactCounts()
        local group = ns:GroupChannel()
        print(string.format("  Outside your guild: %d contacts (%d online), %d introductions waiting%s",
            total, online, intros, group and (", sharing with your " .. group:lower():gsub("_chat", "")) or ""))
        if ns:BgQueued() > 0 then print("  Background messages waiting: " .. ns:BgQueued()) end
    else
        print("  Outside your guild: " .. D .. "off in Settings|r")
    end

    local s = ns.stats
    print("  Sent: " .. Counts(s.sent))
    print("  Received: " .. Counts(s.recv))
    local echoes = (s.echo.GUILD or 0)
    if IsInGuild() then
        print("  Your own guild messages heard back: " .. (echoes > 0 and (G .. echoes .. "|r (guild delivery works)")
            or (D .. "0|r (wait a minute after login, or the guild isn't delivering)")))
    end
    local failed = Counts(s.fail)
    if (s.fail.GUILD or 0) + (s.fail.WHISPER or 0) > 0 then
        local errs = {}
        for k, v in pairs(s.lastErr) do errs[#errs + 1] = k:lower() .. ": " .. v end
        print("  " .. D .. "Failed sends:|r " .. failed .. "  (" .. table.concat(errs, ", ") .. ")")
    end
    local heard = 0
    for _ in pairs(s.senders) do heard = heard + 1 end
    if s.lastRecv then
        print(string.format("  Heard from %d player(s) this session. Last: %s via %s, %ds ago",
            heard, ns.Short(s.lastRecv.who), s.lastRecv.via:lower(), math.floor(GetTime() - s.lastRecv.t)))
    else
        print("  Heard from nobody yet this session.")
    end

    local online, known = {}, 0
    for name, rec in pairs(ns.db.players) do
        if not ns:IsMine(name) then
            known = known + 1
            if ns:IsOnline(name) then
                local n = 0
                for _, r in pairs(rec.recipes or {}) do n = n + #(r.s or {}) + #(r.i or {}) end
                online[#online + 1] = string.format("%s (v%s, %d recipes)", ns.Short(name), rec.version or "?", n)
            end
        end
    end
    table.sort(online)
    print(string.format("  Players: %d known, %d online now", known, #online))
    for i = 1, math.min(10, #online) do print("    " .. online[i]) end
    if #online > 10 then print("    ...and " .. (#online - 10) .. " more") end
end
