-- NameplateThreat: shows threat difference (or just a tank-status colour) on enemy nameplates.
-- Written defensively for Midnight-style restrictions: any threat value that is "secret",
-- or any call that errors, drops the addon into colour-only mode instead of breaking.

local issecret = issecretvalue or function() return false end

NameplateThreatDB = NameplateThreatDB or {}
local DB

local COLORS = {
    secure   = { 0.10, 1.00, 0.10 }, -- tanking, comfortable lead
    tanking  = { 1.00, 0.90, 0.10 }, -- tanking, another tank is second
    insecure = { 1.00, 0.50, 0.00 }, -- tanking, non-tank close behind
    other    = { 0.20, 0.50, 1.00 }, -- another tank has it
    untanked = { 1.00, 0.10, 0.10 }, -- nobody tanking
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Group unit list is cached and only rebuilt when the roster or pets change.
-- In a raid, "raidN" includes the player (and "raidpetN" the player's pet), so those
-- are skipped; otherwise the player counts twice, the runner-up threat equals your own,
-- and the differential is always 0 ("!!!") when you tank.
local groupCache

local function GroupUnits()
    if groupCache then return groupCache end
    local units = { "player", "pet" }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u, p = "raid" .. i, "raidpet" .. i
            if not UnitIsUnit(u, "player") then units[#units + 1] = u end
            if not UnitIsUnit(p, "pet") then units[#units + 1] = p end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
            units[#units + 1] = "partypet" .. i
        end
    end
    groupCache = units
    return units
end

local function IsTank(unit)
    if not unit then return false end
    if UnitGroupRolesAssigned(unit) == "TANK" then return true end
    if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return true end
    return false
end

local function GetText(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local fs = plate.NTText
    if not fs then
        -- pcall: some nameplate frames may be protected/forbidden under the new rules
        local ok, created = pcall(function()
            local f = plate:CreateFontString(nil, "OVERLAY")
            f:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
            f:SetPoint("RIGHT", plate, "LEFT", -4, 0)
            return f
        end)
        if not ok then return end
        fs = created
        plate.NTText = fs
    end
    return fs
end

---------------------------------------------------------------------------
-- Full mode: threat numbers (may be blocked in Forever / Midnight rules)
---------------------------------------------------------------------------

local function ComputeFull(unit)
    local isTanking, _, _, _, value = UnitDetailedThreatSituation("player", unit)
    if value == nil or issecret(value) or issecret(isTanking) then
        return nil
    end

    local firstUnit, firstThreat, secondUnit, secondThreat = nil, 0, nil, 0
    for _, member in ipairs(GroupUnits()) do
        if UnitExists(member) then
            local t = select(5, UnitDetailedThreatSituation(member, unit))
            if t then
                if issecret(t) then return nil end
                if t > firstThreat then
                    secondUnit, secondThreat = firstUnit, firstThreat
                    firstUnit, firstThreat = member, t
                elseif t > secondThreat then
                    secondUnit, secondThreat = member, t
                end
            end
        end
    end

    local colour, diff
    if isTanking then
        diff = value - secondThreat
        if math.abs(diff) / 100 > DB.secureThreshold then
            colour = COLORS.secure
        elseif secondUnit and not UnitIsUnit(secondUnit, "player") and IsTank(secondUnit) then
            colour = COLORS.tanking
        else
            colour = COLORS.insecure
        end
    else
        diff = value - firstThreat
        if firstUnit and not UnitIsUnit(firstUnit, "player") and IsTank(firstUnit) then
            colour = COLORS.other
        else
            colour = COLORS.untanked
        end
    end

    local shown = math.floor(math.abs(diff) / 100 + 0.5)
    local text
    if isTanking and shown < 1 then
        text = "!!!"
    else
        text = AbbreviateNumbers and AbbreviateNumbers(shown) or tostring(shown)
    end
    return colour, text
end

---------------------------------------------------------------------------
-- Fallback mode: colour only, from the plain threat status (0-3)
---------------------------------------------------------------------------

local function ComputeColourOnly(unit)
    local status = UnitThreatSituation("player", unit)
    if status == nil or issecret(status) then return nil end
    if status == 3 then return COLORS.secure, ""
    elseif status == 2 then return COLORS.insecure, "!!!"
    elseif status == 1 then return COLORS.tanking, ""
    else return COLORS.untanked, "" end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

local usingFallback = false

local function UpdateUnit(unit)
    -- Check the unit first so no text objects are created on friendly/player plates
    if UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate and plate.NTText then plate.NTText:SetText("") end
        return
    end

    local fs = GetText(unit)
    if not fs then return end

    local colour, text
    local ok, c, t = pcall(ComputeFull, unit)
    if ok and c then
        colour, text = c, t
        usingFallback = false
    else
        local ok2, c2, t2 = pcall(ComputeColourOnly, unit)
        if ok2 and c2 then
            colour, text = c2, t2
            usingFallback = true
        end
    end

    if colour then
        fs:SetTextColor(colour[1], colour[2], colour[3])
        fs:SetText(text or "")
    else
        fs:SetText("")
    end
end

local function UpdateAll()
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then UpdateUnit(unit) end
    end
end

---------------------------------------------------------------------------
-- Events (throttled)
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
local dirty, elapsed = false, 0

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
f:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("UNIT_PET")
f:RegisterEvent("PLAYER_TARGET_CHANGED")

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "NameplateThreat" then return end
        DB = NameplateThreatDB
        if DB.secureThreshold == nil then DB.secureThreshold = 1000 end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        UpdateUnit(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate.GetNamePlateForUnit(arg1)
        if plate and plate.NTText then plate.NTText:SetText("") end
    else
        if event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
            groupCache = nil
        end
        dirty = true
    end
end)

f:SetScript("OnUpdate", function(_, dt)
    if not dirty then return end
    elapsed = elapsed + dt
    if elapsed >= 0.2 then
        elapsed, dirty = 0, false
        UpdateAll()
    end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_NAMEPLATETHREAT1 = "/nthreat"
SlashCmdList["NAMEPLATETHREAT"] = function(msg)
    local n = tonumber(msg)
    if n then
        DB.secureThreshold = n
        print("NameplateThreat: secure threshold = " .. n)
    else
        print("NameplateThreat: secure threshold = " .. DB.secureThreshold
            .. " (change with /nthreat 1500)")
        print("Mode: " .. (usingFallback and "colour only (threat numbers unavailable)" or "full"))
    end
    UpdateAll()
end
