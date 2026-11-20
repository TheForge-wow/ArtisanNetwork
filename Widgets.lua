-- Artisan Network: flat, dark widget kit (EllesmereUI-inspired look)
local ADDON, ns = ...
local W = {}
ns.W = W

local FONT = STANDARD_TEXT_FONT
W.ONLINE_ICON = "Interface\\FriendsFrame\\StatusIcon-Online"
W.OFFLINE_ICON = "Interface\\FriendsFrame\\StatusIcon-Offline"

ns.ACCENTS = {
    { key = "teal",   c = { 0.20, 0.82, 0.74 } },
    { key = "blue",   c = { 0.29, 0.60, 1.00 } },
    { key = "violet", c = { 0.63, 0.47, 1.00 } },
    { key = "rose",   c = { 1.00, 0.42, 0.56 } },
    { key = "amber",  c = { 1.00, 0.73, 0.27 } },
    { key = "mint",   c = { 0.42, 0.93, 0.56 } },
}

W.C = {
    bg      = { 0.047, 0.047, 0.055, 0.97 },
    header  = { 0.062, 0.062, 0.072, 1 },
    side    = { 0.053, 0.053, 0.062, 1 },
    panel   = { 0.072, 0.072, 0.085, 1 },
    border  = { 1, 1, 1, 0.07 },
    text    = { 0.93, 0.93, 0.95 },
    dim     = { 0.58, 0.59, 0.64 },
    faint   = { 0.38, 0.39, 0.44 },
    online  = { 0.32, 0.87, 0.49 },
}
local C = W.C

-- "Forever" style: the warm brown, bronze and gold look of WoW: Forever's own windows.
-- Chosen in Settings and applied once at load (a /reload switches it), so every widget
-- below can just read W.forever when it is built.
local FOREVER = {
    bg      = { 0.145, 0.110, 0.082, 0.98 },
    header  = { 0.110, 0.070, 0.040, 1 },
    side    = { 0.165, 0.125, 0.094, 1 },
    panel   = { 0.165, 0.125, 0.094, 1 },
    border  = { 0.42, 0.33, 0.22, 1 },
    text    = { 0.95, 0.79, 0.30, 1 },
    dim     = { 0.68, 0.64, 0.58, 1 },
    faint   = { 0.50, 0.46, 0.41, 1 },
    online  = { 0.21, 0.89, 0.29, 1 },
}
W.GOLD = { 1, 0.82, 0.2 }
W.forever = false

function W.ApplyStyle()
    W.style = ns.settings and ns.settings.style or "artisan"
    W.forever = W.style == "forever"
    if not W.forever then return end
    -- update the shared color tables in place: every file holds a reference to them
    for k, v in pairs(FOREVER) do
        local t = C[k]
        for i = 1, 4 do t[i] = v[i] end
    end
end

function ns.Accent()
    if W.forever then return W.GOLD[1], W.GOLD[2], W.GOLD[3] end
    local key = ns.settings and ns.settings.accent
    for _, a in ipairs(ns.ACCENTS) do
        if a.key == key then return a.c[1], a.c[2], a.c[3] end
    end
    local c = ns.ACCENTS[1].c
    return c[1], c[2], c[3]
end

function ns.AccentHex()
    local r, g, b = ns.Accent()
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- objects that follow the accent color live
local accentObjs = {}
local function ApplyAccent(e)
    local r, g, b = ns.Accent()
    local o, kind, a = e[1], e[2], e[3]
    if kind == "tex" then o:SetColorTexture(r, g, b, a)
    elseif kind == "text" then o:SetTextColor(r, g, b, a)
    else o:SetVertexColor(r, g, b, a) end
end
function W.Accentize(obj, kind, alpha)
    local e = { obj, kind, alpha or 1 }
    accentObjs[#accentObjs + 1] = e
    ApplyAccent(e)
end
function W.RefreshAccent()
    for _, e in ipairs(accentObjs) do ApplyAccent(e) end
    ns:Fire("ACCENT")
end

------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------
local function Pixel(tex, w, h)
    if PixelUtil then
        if w then PixelUtil.SetWidth(tex, w) end
        if h then PixelUtil.SetHeight(tex, h) end
    else
        if w then tex:SetWidth(w) end
        if h then tex:SetHeight(h) end
    end
end

function W.Fill(frame, color, layer, inset)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    if inset then
        t:SetPoint("TOPLEFT", inset, -inset)
        t:SetPoint("BOTTOMRIGHT", -inset, inset)
    else
        t:SetAllPoints()
    end
    t:SetColorTexture(unpack(color))
    return t
end

function W.Border(frame, color)
    color = color or C.border
    local b = {}
    local function line()
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(color))
        b[#b + 1] = t
        return t
    end
    local top = line(); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); Pixel(top, nil, 1)
    local bot = line(); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); Pixel(bot, nil, 1)
    local l = line(); l:SetPoint("TOPLEFT"); l:SetPoint("BOTTOMLEFT"); Pixel(l, 1, nil)
    local r = line(); r:SetPoint("TOPRIGHT"); r:SetPoint("BOTTOMRIGHT"); Pixel(r, 1, nil)
    frame.borders = b
    return b
end

function W.SetBorderColor(frame, r, g, b, a)
    for _, t in ipairs(frame.borders or {}) do t:SetColorTexture(r, g, b, a or 1) end
end

function W.Line(parent, horizontal, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(unpack(color or C.border))
    if horizontal then Pixel(t, nil, 1) else Pixel(t, 1, nil) end
    return t
end

function W.Text(parent, size, color, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetTextColor(unpack(color or C.text))
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.6)
    return fs
end

function W.Label(parent, text)
    local fs = W.Text(parent, 10, C.faint)
    fs:SetText(text:upper())
    return fs
end

function W.Panel(parent)
    local f = CreateFrame("Frame", nil, parent)
    W.Fill(f, C.panel)
    if W.forever then
        -- dark outer line with a bronze line just inside it, like the game's inset frames
        W.Border(f, { 0, 0, 0, 0.85 })
        local inner = CreateFrame("Frame", nil, f)
        inner:SetPoint("TOPLEFT", 2, -2)
        inner:SetPoint("BOTTOMRIGHT", -2, 2)
        W.Border(inner, C.border)
        f.inner = inner
    else
        W.Border(f)
    end
    return f
end

function W.Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    W.Fill(f, { 0, 0, 0, 0.7 })
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return f
end

-- Profession icon inside a list row: hover shows the profession and skill, a click still
-- selects the row. Set icon.prof (skill line id) and icon.rankText ("44 / 75") when filling it.
function W.ProfIconTip(icon, row)
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        if not self.prof then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ns.ProfName(self.prof), 1, 1, 1)
        if self.rankText and self.rankText ~= "" then GameTooltip:AddLine("Skill " .. self.rankText, 0.8, 0.8, 0.85) end
        if self.spec then GameTooltip:AddLine(self.spec, 0.79, 0.73, 0.54) end
        if ns.IsGathering(self.prof) then GameTooltip:AddLine("Gathering profession", 0.55, 0.56, 0.6) end
        GameTooltip:Show()
        if row and row.hl then row.hl:Show() end
    end)
    icon:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if row and row.hl and not row:IsMouseOver() then row.hl:Hide() end
    end)
    icon:SetScript("OnMouseUp", function(_, button)
        if row and row.Click and row:IsEnabled() then row:Click(button) end
    end)
end

function W.Tip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(type(title) == "function" and title() or title, 1, 1, 1)
        local b = type(body) == "function" and body() or body
        if b then GameTooltip:AddLine(b, 0.7, 0.7, 0.75, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Controls
------------------------------------------------------------------------
function W.Button(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 100, h or 24)
    b.bg = W.Fill(b, { 1, 1, 1, 0.05 })
    W.Border(b)
    b.text = W.Text(b, 11, C.text, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(label or "")
    function b:Paint(hover)
        if W.forever then
            -- red button, gold rim and gold text; grey when it can't be used
            if not self:IsEnabled() then
                self.bg:SetColorTexture(0.20, 0.18, 0.16, 1)
                W.SetBorderColor(self, 0.36, 0.33, 0.29, 1)
                self.text:SetTextColor(unpack(C.faint))
            elseif self.active then
                self.bg:SetColorTexture(0.62, 0.10, 0.05, 1)
                W.SetBorderColor(self, 1, 0.82, 0.2, 1)
                self.text:SetTextColor(1, 1, 1)
            else
                self.bg:SetColorTexture(hover and 0.56 or 0.42, hover and 0.09 or 0.06, hover and 0.05 or 0.03, 1)
                W.SetBorderColor(self, 0.80, 0.62, 0.25, 1)
                self.text:SetTextColor(hover and 1 or W.GOLD[1], hover and 0.92 or W.GOLD[2], hover and 0.5 or W.GOLD[3])
            end
            return
        end
        local r, g, bb = ns.Accent()
        if self.active then
            self.bg:SetColorTexture(r, g, bb, hover and 0.30 or 0.20)
            W.SetBorderColor(self, r, g, bb, 0.9)
            self.text:SetTextColor(r, g, bb)
        elseif hover and self:IsEnabled() then
            self.bg:SetColorTexture(r, g, bb, 0.12)
            W.SetBorderColor(self, r, g, bb, 0.7)
            self.text:SetTextColor(unpack(C.text))
        else
            self.bg:SetColorTexture(1, 1, 1, 0.05)
            W.SetBorderColor(self, unpack(C.border))
            self.text:SetTextColor(unpack(self:IsEnabled() and C.text or C.faint))
        end
    end
    function b:SetActive(on) self.active = on; self:Paint(self:IsMouseOver()) end
    function b:SetLabel(t) self.text:SetText(t) end
    b:SetScript("OnEnter", function(self) self:Paint(true) end)
    b:SetScript("OnLeave", function(self) self:Paint(false) end)
    b:HookScript("OnEnable", function(self) self:Paint(false) end)
    b:HookScript("OnDisable", function(self) self:Paint(false) end)
    b:Paint(false)
    return b
end

local function Checkbox(parent, label, get, set)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(280, 22)
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(18, 18)
    box:SetPoint("LEFT", 1, 0)
    W.Fill(box, { 0, 0, 0, 0.85 })
    W.Border(box, C.border)
    local check = box:CreateTexture(nil, "OVERLAY")
    check:SetSize(24, 24)
    check:SetPoint("CENTER", 1, 1)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    f.text = W.Text(f, 12, C.text)
    f.text:SetPoint("LEFT", box, "RIGHT", 9, 0)
    f.text:SetText(label)
    function f:Refresh() check:SetShown(get() and true or false) end
    f:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
    end)
    f:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        W.SetBorderColor(box, unpack(W.GOLD))
    end)
    f:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(C.text))
        W.SetBorderColor(box, unpack(C.border))
    end)
    f:Refresh()
    return f
end

function W.Toggle(parent, label, get, set)
    if W.forever then return Checkbox(parent, label, get, set) end
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(280, 22)
    local track = CreateFrame("Frame", nil, f)
    track:SetSize(30, 16)
    track:SetPoint("LEFT")
    track.bg = W.Fill(track, { 1, 1, 1, 0.1 })
    W.Border(track)
    local knob = track:CreateTexture(nil, "ARTWORK")
    knob:SetSize(10, 10)
    knob:SetColorTexture(1, 1, 1, 0.95)
    f.text = W.Text(f, 12, C.text)
    f.text:SetPoint("LEFT", track, "RIGHT", 10, 0)
    f.text:SetText(label)
    function f:Refresh()
        local on = get()
        local r, g, b = ns.Accent()
        knob:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", track, "RIGHT", -3, 0)
            track.bg:SetColorTexture(r, g, b, 0.85)
            W.SetBorderColor(track, r, g, b, 1)
        else
            knob:SetPoint("LEFT", track, "LEFT", 3, 0)
            track.bg:SetColorTexture(1, 1, 1, 0.08)
            W.SetBorderColor(track, unpack(C.border))
        end
    end
    f:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
    end)
    f:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    f:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(C.text)) end)
    f:Refresh()
    return f
end

function W.Segmented(parent, options, get, set, segW)
    segW = segW or 90
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(segW * #options, 24)
    W.Fill(f, { 1, 1, 1, 0.04 })
    W.Border(f)
    f.buttons = {}
    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(segW, 24)
        b:SetPoint("LEFT", (i - 1) * segW, 0)
        b.bg = W.Fill(b, { 0, 0, 0, 0 }, "BACKGROUND", 1)
        b.text = W.Text(b, 11, C.dim, "CENTER")
        b.text:SetPoint("CENTER")
        b.text:SetText(opt.label)
        b.value = opt.value
        b:SetScript("OnClick", function()
            set(opt.value)
            f:Refresh()
        end)
        b:SetScript("OnEnter", function() if get() ~= opt.value then b.text:SetTextColor(unpack(C.text)) end end)
        b:SetScript("OnLeave", function() f:Refresh() end)
        if opt.tip then W.Tip(b, opt.label, opt.tip) end
        f.buttons[i] = b
    end
    function f:Refresh()
        local cur = get()
        local r, g, bb = ns.Accent()
        for _, b in ipairs(self.buttons) do
            if b.value == cur then
                b.bg:SetColorTexture(r, g, bb, 0.2)
                b.text:SetTextColor(r, g, bb)
            else
                b.bg:SetColorTexture(0, 0, 0, 0)
                b.text:SetTextColor(unpack(C.dim))
            end
        end
    end
    f:Refresh()
    return f
end

function W.EditBox(parent, w, h, placeholder)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w or 200, h or 28)
    e:SetAutoFocus(false)
    e:SetFont(FONT, 12, "")
    e:SetTextColor(unpack(C.text))
    e:SetTextInsets(30, 8, 0, 0)
    e.bg = W.Fill(e, W.forever and { 0, 0, 0, 0.8 } or { 0, 0, 0, 0.35 })
    W.Border(e)
    local icon = e:CreateTexture(nil, "OVERLAY")
    e.icon = icon
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 9, 0)
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetVertexColor(0.6, 0.6, 0.65)
    e.ph = W.Text(e, 12, C.faint)
    e.ph:SetPoint("LEFT", 30, 0)
    e.ph:SetText(placeholder or "")
    e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    e:SetScript("OnEditFocusGained", function(s)
        local r, g, b = ns.Accent()
        W.SetBorderColor(s, r, g, b, 0.8)
    end)
    e:SetScript("OnEditFocusLost", function(s) W.SetBorderColor(s, unpack(C.border)) end)
    e:SetScript("OnTextChanged", function(s)
        s.ph:SetShown(s:GetText() == "")
        if s.onChange then s.onChange(s:GetText()) end
    end)
    return e
end

------------------------------------------------------------------------
-- Virtual scrolling list
------------------------------------------------------------------------
function W.RowBase(parent)
    local r = CreateFrame("Button", nil, parent)
    r.stripe = W.Fill(r, { 1, 1, 1, 0 })
    r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.05)
    r.hl:Hide()
    r.sel = r:CreateTexture(nil, "BACKGROUND", nil, 2)
    r.sel:SetAllPoints()
    r.sel:Hide()
    r.selBar = r:CreateTexture(nil, "ARTWORK")
    r.selBar:SetWidth(2)
    r.selBar:SetPoint("TOPLEFT")
    r.selBar:SetPoint("BOTTOMLEFT")
    r.selBar:Hide()
    r:SetScript("OnEnter", function(s) s.hl:Show() end)
    r:SetScript("OnLeave", function(s) s.hl:Hide() end)
    function r:SetSelected(on)
        local cr, cg, cb = ns.Accent()
        self.sel:SetColorTexture(cr, cg, cb, 0.10)
        self.selBar:SetColorTexture(cr, cg, cb, 1)
        self.sel:SetShown(on)
        self.selBar:SetShown(on)
    end
    function r:SetStripe(i)
        self.stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.022 or 0)
    end
    return r
end

function W.List(parent, rowH, createRow, updateRow)
    local list = CreateFrame("Frame", nil, parent)
    list.rowH, list.rows, list.data, list.offset = rowH, {}, {}, 0

    local track = CreateFrame("Frame", nil, list)
    track:SetWidth(4)
    track:SetPoint("TOPRIGHT")
    track:SetPoint("BOTTOMRIGHT")
    W.Fill(track, { 1, 1, 1, 0.04 })
    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(4)
    W.Accentize(W.Fill(thumb, { 1, 1, 1, 1 }), "tex", 0.6)
    thumb:EnableMouse(true)

    list.empty = W.Text(list, 12, C.faint, "CENTER")
    list.empty:SetPoint("TOPLEFT", 20, -40)
    list.empty:SetPoint("TOPRIGHT", -20, -40)
    list.empty:SetWordWrap(true)

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, d) self:SetOffset(self.offset - d * 3) end)
    list:SetScript("OnSizeChanged", function(self) self:Layout() end)

    thumb:SetScript("OnMouseDown", function(self)
        self.dragging = true
        local _, y = GetCursorPosition()
        self.startY = y / self:GetEffectiveScale()
        self.startOff = list.offset
    end)
    thumb:SetScript("OnMouseUp", function(self) self.dragging = false end)
    thumb:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        if not IsMouseButtonDown("LeftButton") then self.dragging = false return end
        local _, y = GetCursorPosition()
        y = y / self:GetEffectiveScale()
        local maxOff = list:MaxOffset()
        local trackH = track:GetHeight() - self:GetHeight()
        if maxOff <= 0 or trackH <= 0 then return end
        list:SetOffset(math.floor(self.startOff + (self.startY - y) / trackH * maxOff + 0.5))
    end)

    function list:Visible() return math.max(1, math.floor((self:GetHeight() or 0) / self.rowH)) end
    function list:MaxOffset() return math.max(0, #self.data - self:Visible()) end
    function list:SetOffset(o)
        self.offset = math.max(0, math.min(self:MaxOffset(), o or 0))
        self:Refresh()
    end
    function list:Layout()
        for i = #self.rows + 1, self:Visible() do
            local row = createRow(self, i)
            row:SetHeight(self.rowH)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * self.rowH)
            row:SetPoint("RIGHT", track, "LEFT", -4, 0)
            self.rows[i] = row
        end
        self:SetOffset(self.offset)
    end
    function list:SetData(d, emptyText)
        self.data = d or {}
        self.empty:SetText(emptyText or "")
        self.empty:SetShown(#self.data == 0)
        self:SetOffset(self.offset)
    end
    function list:Refresh()
        local vis = self:Visible()
        for i, row in ipairs(self.rows) do
            local item = self.data[self.offset + i]
            if item and i <= vis then
                row.item = item
                row:Show()
                updateRow(row, item, self.offset + i)
            else
                row.item = nil
                row:Hide()
            end
        end
        local maxOff = self:MaxOffset()
        if maxOff <= 0 then
            track:Hide()
        else
            track:Show()
            local h = track:GetHeight()
            local th = math.max(24, h * vis / #self.data)
            thumb:SetHeight(th)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -((h - th) * self.offset / maxOff))
        end
    end
    function list:Repaint() if self:IsShown() then self:Refresh() end end
    return list
end
