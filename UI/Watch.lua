-- Artisan Network: Watchlist page
local ADDON, ns = ...
local W, C = ns.W, ns.W.C
local UI = ns.UI

------------------------------------------------------------------------
-- Watchlist page
------------------------------------------------------------------------
function UI.Build.Watch(content)
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()
    local title = W.Text(p, 15)
    title:SetPoint("TOPLEFT", 24, -22)
    title:SetText("Watchlist")
    local desc = W.Text(p, 11, C.dim)
    desc:SetPoint("TOPLEFT", 24, -44)
    desc:SetText("You get a pop-up whenever someone who can craft one of these comes online.")

    local list = W.List(p, 40, function(lst)
        local r = W.RowBase(lst)
        r.icon = W.Icon(r, 28)
        r.icon:SetPoint("LEFT", 10, 0)
        r.name = W.Text(r, 12)
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -1)
        r.name:SetWidth(320)
        r.sub = W.Text(r, 10, C.dim)
        r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 1)
        r.remove = W.Button(r, "Remove", 70, 22)
        r.remove:SetPoint("RIGHT", -8, 0)
        r.remove:SetScript("OnClick", function() if r.item then ns.db.watch[r.item.key] = nil; UI:Refresh() end end)
        r.count = W.Text(r, 11, C.text, "RIGHT")
        r.count:SetPoint("RIGHT", r.remove, "LEFT", -14, 0)
        r:SetScript("OnClick", function(self) if self.item then ns:ShowUI("search", self.item.key) end end)
        return r
    end, function(r, e, i)
        r:SetStripe(i)
        r.icon.tex:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.name:SetText(e.name)
        r.sub:SetText(e.prof and ns.ProfName(e.prof) or "")
        local on, others, mine = ns:CountOnline(e)
        UI.SetCrafterCount(r.count, on, others, mine, "nobody online")
        r:SetSelected(false)
    end)
    list:SetPoint("TOPLEFT", 20, -74)
    list:SetPoint("BOTTOMRIGHT", -20, 18)

    local page = { frame = p }
    function page.refresh()
        ns:GetIndex()
        local data = {}
        for key in pairs(ns.db.watch) do
            local e = ns.byKey[key]
            if not e then
                local name, icon = ns.RecipeInfo(key)
                e = { key = key, name = name or key, icon = icon, crafters = {} }
            end
            data[#data + 1] = e
        end
        table.sort(data, function(a, b) return (a.name or "") < (b.name or "") end)
        list:SetData(data, "Your watchlist is empty.\n\nOpen any recipe in Find a Crafter and press Watch.")
    end
    return page
end
