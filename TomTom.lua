----------------------------------------------------------------------------
--  TomTom: A navigational assistant for World of Warcraft
--  CrazyTaxi: A crazy-taxi style arrow used for waypoint navigation.
--  concept taken from MapNotes2 (Thanks to Mery for the idea, along
--  with the artwork.)
----------------------------------------------------------------------------
-- Ace3v.  AceDB-3.0 is not an embeddable mixin in Ace3, so it is called directly in
-- OnInitialize.  AceDebug-2.0 has no Ace3 equivalent and was never used; AceEvent-2.0 was
-- mixed in but never used either -- this addon drives its own frames with SetScript.
-- AceConfig-3.0 is not used at all.  Its Cmd path drove the old /tomtom text tree, which the
-- LibConfig-1.0 window replaces, and its Dialog path needs AceGUI-3.0, which does not work on
-- Unreal Azeroth.  AceConsole-3.0 still provides RegisterChatCommand and :Print.
TomTom = LibStub("AceAddon-3.0"):NewAddon("TomTom", "AceConsole-3.0")

local twopi = math.pi * 2

local hbd = LibStub("LibHereBeDragons-1.0")
local hbdp = LibStub("LibHereBeDragons-Pins-1.0")

-- A waypoint is identified by a mapID.  AddMFWaypoint still accepts the old
-- (continent, zoneIndex) pair, because third-party addons pass that -- see there.
local function resolveMapID(a, b)
    if type(a) ~= "number" then return nil end
    -- Continent indices are 0, 1 and 2; the lowest real mapID is 4, so the two spaces
    -- cannot collide and one argument is enough to tell them apart.
    if a <= 2 then
        return hbd:GetMapIDFromCZ(a, b)
    end
    return a
end

TomTom.active_waypoint = nil
TomTom.active_point = nil -- {c, z, x, y}
TomTom.arrive_distance = nil -- num of yards to show down icon
TomTom.clear_distance = nil -- num of yards to remove arrow
TomTom.showDownArrow = nil
TomTom.point_title = nil
TomTom.isHide = false
TomTom.wayframe = nil
TomTom.waypoints = {}
TomTom.arrowTab = {}
TomTom.feedTab = {}
-- Zone-name aliases.  Most of what this table used to do is gone: it existed because
-- Astrolabe keyed its geometry on the mapFile ("Tirisfal") while the user types the zone name
-- ("Tirisfal Glades"), and the map library now resolves names, mapFiles and localized names
-- itself.  What is left is genuine user typos and short forms, which no name table will cover.
TomTom.extraZones = {
    thehinterlands = 'Hinterlands',
    tarrenmill = 'Hilsbrad',
    hillsbrad = 'Hilsbrad',
    hillsbradfoothills = 'Hilsbrad',
    alteracmountains = 'Alterac',
    silverpineforest = 'Silverpine',
    trisfalglades = 'Tirisfal',
    tirisfalglades = 'Tirisfal',
    theundercity = 'Undercity',
    stranglethornvale = 'Stranglethorn',
    redridgemountains = 'Redridge',
    elwynnforest = 'Elwynn',
    arathihighlands = 'Arathi',
    thebarrens = 'Barrens',
    darnassus = 'Darnassis',
    dustwallowmarsh = 'Dustwallow',
    duskwallowmarsh = 'Dustwallow',
    orgrimmar = 'Ogrimmar',
    stonetalon = 'StonetalonMountains',
    swampofsorrow='SwampOfSorrows',
}

TomTom.defaults = {
    profile = {
        persistence = {
            cleardistance = 10,
            savewaypoints = false,
        },
        arrow = {
            autoqueue = true,
            arrival = 30,
            locked = true,
            location = nil,
            enablePing = true,
            menu = true,
            continueclosest = false,
        },
        general = {
            announce = false,
            confirmremoveall = true,
            corpsewaypoint = true,
        },
        worldmap = {
            create_modifier = "C",
            enable = true,
            tooltip = true,
            menu = true,
        },
        minimap = {
            enable = true,
            tooltip = true,
            menu = true,
        },
    },
}

function TomTom:log(msg)
    DEFAULT_CHAT_FRAME:AddMessage(msg) -- alias for convenience
end

function TomTom:Modulo(val, by)
    return val - math.floor(val / by) * by
end

function TomTom:modf(number)
    local fractional = self:Modulo(number, 1)
    local integral = number - fractional
    return integral, fractional
end

-- Was: ({Minimap:GetChildren()})[9]:GetFacing().  The ninth child is not the player arrow on
-- this client, so that died with "GetFacing (a nil value)" at TomTom.lua:103 -- every frame,
-- from the crazy arrow's own OnUpdate.  The library finds the arrow by its model path instead.
--
-- The library returns nil when no source can answer.  Both callers here (:246 and :435) then
-- do "angle - player", which would be an arithmetic error on nil, so substitute 0: the arrow
-- keeps working and simply shows the absolute bearing instead of one relative to the player.
function TomTom:GetPlayerFacing()
    return LibStub("LibHereBeDragons-1.0"):GetPlayerFacing() or 0
end

function TomTom:ColorGradient(perc, tablee)
    local num = table.getn(tablee)
    local hexes = tablee[1] == "string"
    if perc == 1 then
        return tablee[num-2], tablee[num-1], tablee[num]
    end
    num = num / 3
    local segment, relperc = self:modf(perc*(num-1))
    local r1, g1, b1, r2, g2, b2
    r1, g1, b1 = tablee[(segment*3)+1], tablee[(segment*3)+2], tablee[(segment*3)+3]
    r2, g2, b2 = tablee[(segment*3)+4], tablee[(segment*3)+5], tablee[(segment*3)+6]
    if not r1 then return end
    if not r2 or not g2 or not b2 then
        return r1, g1, b1
    else
        return r1 + (r2-r1)*relperc,
        g1 + (g2-g1)*relperc,
        b1 + (b2-b1)*relperc
    end
end

function TomTom:WayFrame_OnClick()
    if arg1 == "RightButton" and IsShiftKeyDown() then
        TomTom:GoToNextWayPoint(TomTom.active_waypoint);
    elseif arg1 == "RightButton" then
        if TomTom.db.profile.arrow.menu then
            TomTom:InitializeDropdown(TomTom.active_waypoint, true)
            ToggleDropDownMenu(1, nil, TomTom.dropdown, "cursor", 0, 0)
        end
    end
end

function TomTom:OnInitialize()
    self:CreateFrames();

    -- self.defaults is already { profile = {...} }, i.e. exactly AceDB-3.0's shape, so the
    -- old RegisterDefaults("profile", ...) call disappears.  No defaultProfile argument:
    -- that keeps the default profile character-specific, as AceDB-2.0 had it, so existing
    -- per-character settings are preserved.
    self.db = LibStub("AceDB-3.0"):New("TomTomDB", self.defaults)

    -- AceDB-2.0 called OnProfileEnable for us; AceDB-3.0 has no such hook, so wire it up.
    -- Note the DOT: RegisterCallback is CallbackHandler's consumer API, not a method.
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileEnable")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileEnable")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileEnable")

    self:OnProfileEnable()
    self:InitConsole()
end

-- Throttled: this used to run UnitIsDeadOrGhost and GetCorpseMapPosition on every frame, and
-- neither answer can change faster than a death or a resurrection.
local nextCorpseCheck = 0
function TomTom:OnEventsUpdate(self)
    local now = GetTime()
    if now < nextCorpseCheck then return end
    nextCorpseCheck = now + 0.5

    if self.profile.general.corpsewaypoint and UnitIsDeadOrGhost("player") and not self.deadWayPoint then
        local deadx, deady = GetCorpseMapPosition();
        if deadx and deady and deadx ~= 0 and deady ~= 0 then
            local cont,zoneid = self:GetCurrentPlayerPosition()
            self.deadWayPoint = self:SetCrazyArrow({c = cont, z = zoneid, x = deadx, y = deady}, 20, "My possibly dead corpse", true)
        end
    elseif not UnitIsDeadOrGhost("player") and self.deadWayPoint then
        if self.active_waypoint == self.deadWayPoint then
            self:GoToNextWayPoint(self.active_waypoint)
        else
            self:RemoveWaypoint(self.deadWayPoint)
        end
        self.deadWayPoint = nil
    end
end

function TomTom:OnEvents()
    if (event == "PLAYER_ENTERING_WORLD") then
        for k, w in pairs(TomTom.waypoints) do
            TomTom:SetWaypoint(w, w.callbacks, w.minimap, w.world)
        end
    elseif (event == "PLAYER_LEAVING_WORLD") then
        for k, w in pairs(TomTom.waypoints) do
            TomTom:ClearWaypoint(w)
        end
    end
end

function TomTom:CreateFrames()
    self.eventsFrame = CreateFrame("Frame", nil, UIParent)
    self.eventsFrame:SetScript("OnUpdate", function() self:OnEventsUpdate(self) end)
    self.eventsFrame:RegisterEvent("PLAYER_LEAVING_WORLD");
    self.eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
    self.eventsFrame:SetScript("OnEvent", self.OnEvents);

    self.dropdown = CreateFrame("Frame", "TomTomDropdown", nil, "UIDropDownMenuTemplate")

    local wayframe = CreateFrame("Button", "TomTomCrazyArrow", UIParent)
    self.wayframe = wayframe
    wayframe:SetHeight(42)
    wayframe:SetWidth(56)
    wayframe:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    wayframe:EnableMouse(true)
    wayframe:SetMovable(true)
    wayframe:Hide()
    wayframe.count = 0
    wayframe.last_distance = 0
    wayframe.tta_throttle = 0
    wayframe.speed = 0
    wayframe.speed_count = 0

    -- Frame used to control the scaling of the title and friends
    local titleframe = CreateFrame("Frame", nil, wayframe)
    wayframe.titleframe = titleframe
    wayframe.title = titleframe:CreateFontString("OVERLAY", nil, "GameFontHighlightSmall")
    wayframe.status = titleframe:CreateFontString("OVERLAY", nil, "GameFontNormalSmall")
    wayframe.tta = titleframe:CreateFontString("OVERLAY", nil, "GameFontNormalSmall")
    wayframe.title:SetPoint("TOP", wayframe, "BOTTOM", 0, 0)
    wayframe.status:SetPoint("TOP", wayframe.title, "BOTTOM", 0, 0)
    wayframe.tta:SetPoint("TOP", wayframe.status, "BOTTOM", 0, 0)

    wayframe:SetScript("OnDragStart", self.OnDragStart)
    wayframe:SetScript("OnDragStop", self.OnDragStop)
    wayframe:RegisterForDrag("LeftButton")
    wayframe:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    wayframe:SetScript("OnEvent", self.OnEvent)
    wayframe.arrow = wayframe:CreateTexture("OVERLAY")
    wayframe.arrow:SetTexture("Interface\\AddOns\\TomTom\\Images\\Arrow")
    wayframe.arrow:SetAllPoints()

    wayframe:SetScript("OnUpdate", self.OnUpdate)
    wayframe:RegisterForClicks("RightButtonUp")
    wayframe:SetScript("OnClick", self.WayFrame_OnClick)

    -- A ~55-line data-feed block used to sit here, registered on ADDON_LOADED.  It was dead
    -- code: this SetScript("OnEvent", ...) overwrote the handler installed a few lines above,
    -- which silently killed the ZONE_CHANGED_NEW_AREA handler that wayframe was registered
    -- for -- and the feed it built drove two frames that nothing ever registered or showed,
    -- one of them running an OnUpdate every frame to compute values nobody read.
    --
    -- Removed rather than repaired.  LibDataBroker-1.1 exists for this now (it is in
    -- source/Ace3v/), so if a real data feed is ever wanted it should be built on that
    -- deliberately, not resurrected from this.
end

function TomTom:OnDragStart(self, button)
    if not TomTom.profile.arrow.locked then
        this:StartMoving()
        this:SetClampedToScreen(true);
    end
end

local function round(v)
    return math.floor(v + 0.5)
end

-- Which screen edge or corner the arrow is nearest, and its offset from that.
--
-- Saving the position against one fixed anchor turns into a large absolute offset, and a large
-- offset is exactly what a resolution or window-size change distorts: switching between
-- fullscreen and windowed moves UIParent's edges, so an arrow parked far from its anchor lands
-- somewhere else.  A small offset from the edge the arrow already sits closest to survives that
-- much better, and it matches how it was placed to begin with -- "top right", "middle".
--
-- Thirds horizontally, halves vertically.  Measured with GetCenter/GetLeft/GetRight/GetTop/
-- GetBottom rather than GetPoint: those say where the frame IS, whichever anchor the drag
-- happened to leave on it.  Those edges come back in each frame's own coordinate space, so the
-- effective-scale ratio converts UIParent's into the arrow's, which is the space SetPoint's
-- offsets are in.
local function nearestAnchor(frame)
    local cx, cy = frame:GetCenter()
    local left, right = UIParent:GetLeft(), UIParent:GetRight()
    local bottom, top = UIParent:GetBottom(), UIParent:GetTop()
    local frameScale = frame:GetEffectiveScale()
    if not cx or not cy or not left or not right or not bottom or not top then return nil end
    if not frameScale or frameScale == 0 then return nil end

    local ratio = UIParent:GetEffectiveScale() / frameScale
    left, right, bottom, top = left * ratio, right * ratio, bottom * ratio, top * ratio

    local point, x, y
    if cy >= (bottom + top) / 2 then
        point = "TOP"
        y = frame:GetTop() - top
    else
        point = "BOTTOM"
        y = frame:GetBottom() - bottom
    end

    local width = right - left
    if cx >= left + width * 2 / 3 then
        point = point .. "RIGHT"
        x = frame:GetRight() - right
    elseif cx <= left + width / 3 then
        point = point .. "LEFT"
        x = frame:GetLeft() - left
    else
        -- Horizontally centred: SetPoint already lines the two centres up, so the offset is the
        -- deviation from centre rather than from an edge.
        x = cx - (left + right) / 2
    end

    return point, round(x), round(y)
end

function TomTom:OnDragStop(self, button)
    this:StopMovingOrSizing()
    local point, x, y = nearestAnchor(this)
    if point then
        TomTom.profile.arrow.location = {point, "UIParent", point, x, y}
    else
        -- Nothing measurable: store the anchor the drag left, which is what this always did.
        local a, _, c, d, e = this:GetPoint()
        TomTom.profile.arrow.location = {a, "UIParent", c, d, e}
    end
end

-- No parameters.  On both clients an event handler reads the globals: `event` for the name,
-- `arg1`..`arg9` for the payload, `this` for the frame.  That is what TomTom:OnEvents above already
-- does, and what Ace3v's own AceEvent-3.0 does, so it is the form that needs no client knowledge at
-- all.  Taking `event` as a parameter made this test depend on arguments being passed.
function TomTom:OnEvent()
    if event == "ZONE_CHANGED_NEW_AREA" then
        this:Show()
    end
end

function TomTom:SetArrowWaypoint(waypoint)
    self.active_waypoint = waypoint
    self.active_point = {c = waypoint.continent, z = waypoint.zone, x = waypoint.x, y = waypoint.y}
    self.arrive_distance = waypoint.arrivaldistance
    self.clear_distance = waypoint.cleardistance
    self.point_title = waypoint.title
    self.wayframe.title:SetText(self.point_title or "Unknown waypoint")
    self.isHide = false
    if self.active_point and not self.isHide then
        self.wayframe:Show()
    else
        self.wayframe:Hide()
    end
end

function TomTom:SetCrazyArrow(point, dist, title, silent)
    return self:AddMFWaypoint(point.c, point.z, point.x, point.y, {
        title = title,
        crazy = true,
        persistent = false,
        silent = silent,
        cleardistance = dist,
        arrivaldistance = dist + 5
    })
end

function TomTom:ClearCrazyArrow()
    self.active_waypoint = nil
    self.active_point = nil
    self.wayframe:Hide()
end

-------------------------
-- Questie integration --
-------------------------
-- local originalQuestieArrowMethod = SetArrowObjective
-- SetArrowObjective = function(hash)
-- 	local existingWP = nil
-- 	for _, wp in TomTom.waypoints do
-- 		if wp.questieHash == hash then
-- 			existingWP = wp
-- 			break
-- 		end
-- 	end
-- 	if existingWP then
-- 		TomTom:GoToNextWayPoint(existingWP)
-- 		return existingWP
-- 	else
-- 		local objective = QuestieTrackedQuests[hash]["arrowPoint"]
-- 		if not objective then return end
-- 		local waypoint = TomTom:SetCrazyArrow(objective, 15, objective.title)
-- 		waypoint.questieHash = hash
-- 		return waypoint
-- 	end
--
-- end

function TomTom:OnUpdate()
    local self = this
    local elapsed = 1/GetFramerate()

    -- if TomTom.active_waypoint and TomTom.active_waypoint.questieHash then
    -- 	if not QuestieTrackedQuests[TomTom.active_waypoint.questieHash] then
    -- 		TomTom:GoToNextWayPoint(TomTom.active_waypoint)
    -- 	end
    -- end
    if not TomTom.active_point or TomTom.isHide then
        self:Hide()
        return
    end
    local dist,x,y = TomTom:GetDistanceToIcon(TomTom.active_point)
    -- The only time we cannot calculate the distance is when the waypoint
    -- is on another continent, or we are in an instance
    if not dist or IsInInstance() then
        if not TomTom.active_point.x and not TomTom.active_point.y then
            TomTom.active_point = nil
        end
        self:Hide()
        return
    end
    self.status:SetText(string.format("%d yards", dist))
    local cell
    -- got there already?
    if dist <= TomTom.clear_distance and not UnitOnTaxi("player") and TomTom.active_point.normalArrowShown then
        TomTom:GoToNextWayPoint(TomTom.active_waypoint)
        -- Showing the arrival arrow?
    elseif dist <= TomTom.arrive_distance then
        if TomTom.profile.arrow.enablePing and TomTom.active_point.normalArrowShown and not TomTom.active_point.pinged then
            PlaySoundFile("Interface\\AddOns\\TomTom\\Media\\ping.mp3")
            TomTom.active_point.pinged = true
        end
        if not self.showDownArrow then
            self.arrow:SetHeight(70)
            self.arrow:SetWidth(53)
            self.arrow:SetTexture("Interface\\AddOns\\TomTom\\Images\\Arrow-UP")
            self.arrow:SetVertexColor(0, 1, 0)
            self.showDownArrow = true
        end
        self.count = self.count + 1
        if self.count >= 55 then
            self.count = 0
        end
        cell = self.count
        local column = TomTom:Modulo(cell, 9)
        local row = floor(cell / 9)
        local xstart = (column * 53) / 512
        local ystart = (row * 70) / 512
        local xend = ((column + 1) * 53) / 512
        local yend = ((row + 1) * 70) / 512
        self.arrow:SetTexCoord(xstart,xend,ystart,yend)
        -- Still moving there huh
    else
        TomTom.active_point.normalArrowShown = true
        if self.showDownArrow then
            self.arrow:SetHeight(56)
            self.arrow:SetWidth(42)
            self.arrow:SetTexture("Interface\\AddOns\\TomTom\\Images\\Arrow")
            self.showDownArrow = false
        end
        local bearing = TomTom:GetDirectionToIcon(TomTom.active_point)
        if not bearing then return end
        local player = TomTom:GetPlayerFacing()

        -- The arrow sprite sheet runs COUNTER-CLOCKWISE from "up", while the map library returns
        -- a clockwise bearing.  Convert here, at the boundary, rather than bending the library.
        --
        -- Worked out from the cardinals the original code produced (via vanilla's degree-based
        -- global atan2): north 0, east 83, south 56, west 27.  A clockwise sheet would want east
        -- 27 and west 81, so east and west were swapped while north and south were right -- which
        -- is exactly the symptom of feeding it a clockwise angle: a westward target pointed east.
        --
        -- GetPlayerFacing is already counter-clockwise from north (WoW's convention), so it is
        -- subtracted in the same space, as the original did.
        local angle = (twopi - bearing) - player
        local perc = 1-  math.abs(((math.pi - math.abs(angle)) / math.pi))
        local gr,gg,gb = 1, 1, 1
        local mr,mg,mb = 0.75, 0.75, 0.75
        local br,bg,bb = 0.5, 0.5, 0.5
        local tablee = TomTom.arrowTab
        tablee[1] = nil;
        tablee[2] = nil;
        tablee[3] = nil;
        tablee[4] = nil;
        tablee[5] = nil;
        tablee[6] = nil;
        tablee[7] = nil;
        tablee[8] = nil;
        tablee[9] = nil;
        table.setn(tablee,0)
        table.insert(tablee, gr)
        table.insert(tablee, gg)
        table.insert(tablee, gb)
        table.insert(tablee, mr)
        table.insert(tablee, mg)
        table.insert(tablee, mb)
        table.insert(tablee, br)
        table.insert(tablee, bg)
        table.insert(tablee, bb)
        local r,g,b = TomTom:ColorGradient(perc,tablee)
        if not g then
            g = 0;
        end
        self.arrow:SetVertexColor(1-g,-1+g*2,0)
        cell = TomTom:Modulo(floor(angle / twopi * 108 + 0.5), 108);
        local column = TomTom:Modulo(cell, 9)
        local row = floor(cell / 9)
        local xstart = (column * 56) / 512
        local ystart = (row * 42) / 512
        local xend = ((column + 1) * 56) / 512
        local yend = ((row + 1) * 42) / 512
        self.arrow:SetTexCoord(xstart,xend,ystart,yend)
    end
    -- Calculate the TTA every second  (%01d:%02d)
    self.tta_throttle = self.tta_throttle + elapsed
    if self.tta_throttle >= 1.0 then
        -- Calculate the speed in yards per sec at which we're moving
        local current_speed = (self.last_distance - dist) / self.tta_throttle
        if self.last_distance == 0 then
            current_speed = 0
        end
        if self.speed_count < 2 then
            self.speed = (self.speed + current_speed) / 2
            self.speed_count = self.speed_count + 1
        else
            self.speed_count = 0
            self.speed = current_speed
        end
        if self.speed > 0 then
            local eta = math.abs(dist / self.speed)
            local text = string.format("%01d:%02d", eta / 60, TomTom:Modulo(eta, 60))
            self.tta:SetText(text)
        else
            self.tta:SetText("***")
        end
        self.last_distance = dist
        self.tta_throttle = 0
    end
end

function TomTom:ArrowHidden()
    self.isHide = true
end

function TomTom:ArrowShown()
    self.isHide = false
end

function TomTom:getCoords(column, row)
    local xstart = (column * 56) / 512
    local ystart = (row * 42) / 512
    local xend = ((column + 1) * 56) / 512
    local yend = ((row + 1) * 42) / 512
    return xstart, xend, ystart, yend
end

--this is where texcoords are extracted incorrectly (I think), leading the arrow to not point in the correct direction
TomTom.texcoords = setmetatable({}, {__index = function(t, k)
        -- this was k:match("(%d+):(%d+)") - so we need string.match, but that's not in Lua 5.0
        local fIndex, lIndex = string.find(k, "(%d+)")
        local col = string.sub(k, fIndex, lIndex)
        fIndex2, lIndex2 = string.find(k, ":(%d+)")
        local row = string.sub(k, fIndex2+1, lIndex2)
        col,row = tonumber(col), tonumber(row)
        local obj = {TomTom:getCoords(col, row)}
        rawset(t, k, obj)
        return obj
end})

-- calculations have to be redone - we are NOT actually working with Astrolabe "icons" here as TomTom did and want the arrow API
-- to be accessible to everyone
-- RADIANS now, normalised to [0, 2*pi), 0 = north, growing clockwise -- the library's
-- convention.  Astrolabe returned degrees (vanilla's global atan2 is degree-based) and the
-- callers compensated inconsistently: two applied math.rad, one did not, and this function
-- itself mixed the two by subtracting a degree value from 2*pi.  Every consumer is updated.
function TomTom:GetDirectionToIcon(point)
    if not point then return end
    local x, y, mapID = hbd:GetPlayerZonePosition()
    if not mapID then return end
    local target = point.mapID or resolveMapID(point.c or point.continent, point.z or point.zone)
    if not target then return end
    return hbd:GetZoneVector(mapID, nil, x, y, target, nil, point.x, point.y)
end

-- The old "is WorldMapSize populated yet" guard is gone: the zone table is static and ready
-- before PLAYER_LOGIN, so there is no uninitialised window to paper over.
function TomTom:GetDistanceToIcon(point)
    if not point then return end
    local x, y, mapID = hbd:GetPlayerZonePosition()
    if not mapID then return end
    local target = point.mapID or resolveMapID(point.c or point.continent, point.z or point.zone)
    if not target then return end
    return hbd:GetZoneDistance(mapID, nil, x, y, target, nil, point.x, point.y)
end

-- The display name of a zone, from its mapID.
function TomTom:GetZoneName(mapID)
    return (mapID and hbd:GetLocalizedMap(mapID)) or "Unknown"
end

-- The display name of a waypoint's zone.
--
-- Ask the mapID first.  It is the waypoint's real identity, whereas wp.zone is a client-state
-- index the map library learns by observation, so it is nil for any zone whose map the player
-- has not opened -- and a waypoint created from a mapID may never have had one at all.
function TomTom:GetWaypointZoneName(wp)
    if wp.mapID then return self:GetZoneName(wp.mapID) end
    local _, _, byIndex = self:GetZoneInfo(wp.zone, wp.continent)
    return byIndex or "Unknown"
end

function TomTom:GetZoneInfo(zone, cont)
    if zone == nil then
        return
    end
    zone = self.extraZones[zone] or zone

    -- Returns continent, zoneIndex, name, mapID.  The zoneIndex CAN BE NIL: it is client state
    -- the map library learns by observation, so it is unknown for a zone the player has not
    -- visited yet.  Callers must key off the mapID, not the index.
    if type(zone) == "number" then
        -- A (zoneIndex, continent) pair, which is how this is called to turn a waypoint back
        -- into a zone name.
        local mapID = hbd:GetMapIDFromCZ(cont, zone)
        if mapID then
            return cont, zone, hbd:GetLocalizedMap(mapID), mapID
        end
        return nil, nil, nil, nil
    end

    -- Otherwise a name.  The library resolves localized names, English names and mapFiles,
    -- normalising case and punctuation, so the old walk over every zone is unnecessary.
    local mapID = hbd:GetMapIDFromZoneName(zone) or hbd:GetMapIDFromFile(zone)
    if not mapID then return nil, nil, nil, nil end
    local C, Z = hbd:GetCZFromMapID(mapID)
    return C, Z, hbd:GetLocalizedMap(mapID), mapID
end

function TomTom:RoundCoords(x,y,prec)
    local fmt = string.format("%%.%df, %%.%df", prec, prec)
    return string.format(fmt, x * 100, y * 100)
end

-- Code courtesy ckknight
function TomTom:GetCurrentCursorPosition()
    local x, y = GetCursorPosition()
    local left, top = WorldMapDetailFrame:GetLeft(), WorldMapDetailFrame:GetTop()
    local width = WorldMapDetailFrame:GetWidth()
    local height = WorldMapDetailFrame:GetHeight()
    local scale = WorldMapDetailFrame:GetEffectiveScale()
    local cx = (x/scale - left) / width
    local cy = (top - y/scale) / height

    if cx < 0 or cx > 1 or cy < 0 or cy > 1 then
        return nil, nil
    end

    return cx, cy
end

-- Hook the WorldMap OnClick
local world_click_verify = {
    ["A"] = function() return IsAltKeyDown() end,
    ["C"] = function() return IsControlKeyDown() end,
    ["S"] = function() return IsShiftKeyDown() end,
}

local origScript = WorldMapButton_OnClick
WorldMapButton_OnClick = function(arg1, arg2, arg3)
    if WorldMapButton.ignoreClick then
        WorldMapButton.ignoreClick = false;
        return;
    end
    local mouseButton = arg1
    if mouseButton == "RightButton" then
        -- Check for all the modifiers that are currently set
        local notSet = false
        string.gsub(TomTom.db.profile.worldmap.create_modifier, "(%S)", function(mod)
            if not world_click_verify[mod] or not world_click_verify[mod]() then
                notSet = true
            end
        end)
        if notSet then
            return origScript and origScript(arg1, arg2, arg3) or true
        end
        local x, y = TomTom:GetCurrentCursorPosition()
        if not x or not y then
            return origScript and origScript(arg1, arg2, arg3) or true
        end

        -- Which map is on screen?  Not GetCurrentMapContinent/Zone: this whole path used to be
        -- driven by the zone INDEX, and an index is client state the map library only knows once
        -- it has been observed -- so a zone the player has never visited was silently
        -- unclickable.  A mapID is always known, and AddMFWaypoint takes one directly.
        local displayed = hbd:GetCurrentMapID()
        if not displayed then
            return origScript and origScript(arg1, arg2, arg3) or true
        end

        local shown = hbd.mapData[displayed]
        local isContinent = shown and shown.areaID == 0
        local isCosmic = displayed == 0

        local target, tx, ty = displayed, x, y

        if isCosmic or isContinent then
            -- Zoomed out: find which zone the click falls inside.  Translating FROM the cosmic
            -- map needs the destination's instance as the source floor, which is what the second
            -- argument is for; from a continent map no floor is involved.
            local bestD = 1
            target = nil
            local ids = hbd:GetAllMapIDs()
            for i = 1, table.getn(ids) do
                local id = ids[i]
                local d = hbd.mapData[id]
                -- A real zone: continents carry areaID 0, and battlegrounds have no continent.
                if d.areaID ~= 0 and d.C then
                    local floor
                    if isCosmic then floor = d.instance end
                    local nX, nY = hbd:TranslateZoneCoordinates(x, y, displayed, floor, id, nil, false)
                    if nX and nY and 0 < nX and nX <= 1 and 0 < nY and nY <= 1 then
                        -- Was "abs(nX-0.5) + abs(nX-0.5)": nX twice, so the vertical distance
                        -- never counted and the wrong zone could win.
                        local dd = math.abs(nX - 0.5) + math.abs(nY - 0.5)
                        if dd < bestD then
                            target, tx, ty, bestD = id, nX, nY, dd
                        end
                    end
                end
            end
        end

        if not target then
            return origScript and origScript(arg1, arg2, arg3) or true
        end

        local uid = TomTom:AddMFWaypoint(target, nil, tx, ty)
    else
        return origScript and origScript(arg1,arg2,arg3) or true
    end
end

if WorldMapButton:GetScript("OnClick") == origScript then
    WorldMapButton:SetScript("OnClick", WorldMapButton_OnClick)
end

------------- console -----------------
TomTom.options = {
    type = 'group',
    -- The root name used to be absent, and AceConfigRegistry's ValidateOptionsTable filled it in
    -- as "a bit of a hack" on the way past.  LibConfig takes the sidebar label as its own
    -- argument, so it never needed one -- but a table that describes itself does not depend on
    -- either library's tolerance.
    name = 'TomTom',
    args = {
        arrow = {
            type = 'group',
            order = 20,
            name = 'Crazy Arrow',
            desc = 'The on-screen arrow that points at your active waypoint',
            args = {
                autoqueue = {
                    type = 'toggle',
                    order = 30,
                    name = 'Point the arrow at new waypoints',
                    desc = 'Make a newly added waypoint the arrow target straight away',
                    get = function(info) return TomTom.profile.arrow.autoqueue end,
                    set = function(info, value) TomTom.profile.arrow.autoqueue = value end
                },
                locked = {
                    type = 'toggle',
                    order = 20,
                    name = 'Lock the arrow in place',
                    desc = 'Stop the arrow being dragged around the screen',
                    get = function(info) return TomTom.profile.arrow.locked end,
                    set = function(info, value) TomTom.profile.arrow.locked = value end
                },
                arrival = {
                    type = 'range',
                    order = 50,
                    name = 'Arrival distance (yards)',
                    min = -1, max = 100, step = 1,
                    desc = 'How close counts as arriving -- the arrow turns into a downward icon',
                    get = function(info) return TomTom.profile.arrow.arrival end,
                    set = function(info, value) TomTom.profile.arrow.arrival = value end
                },
                continueclosest = {
                    type = 'toggle',
                    order = 40,
                    name = 'Continue to the closest waypoint',
                    desc = 'When the current waypoint is cleared, move to the nearest remaining one rather than the newest',
                    get = function(info) return TomTom.profile.arrow.continueclosest end,
                    set = function(info, value) TomTom.profile.arrow.continueclosest = value end
                },
                enablePing = {
                    type = 'toggle',
                    order = 60,
                    name = 'Play a sound on arrival',
                    desc = 'Play the ping sound when you arrive at a waypoint',
                    get = function(info) return TomTom.profile.arrow.enablePing end,
                    set = function(info, value) TomTom.profile.arrow.enablePing = value end
                },
                menu = {
                    type = 'toggle',
                    order = 70,
                    name = 'Right-click menu on the arrow',
                    desc = 'Enable the right-click context menu on the arrow',
                    get = function(info) return TomTom.profile.arrow.menu end,
                    set = function(info, value) TomTom.profile.arrow.menu = value end
                },
                -- debug stuff --
                resetpos = {
                    type = "execute",
                    order = 80,
                    name = 'Reset the arrow position',
                    desc = 'Move the arrow back to the middle of the screen',
                    func = function()
                        TomTom.wayframe:ClearAllPoints()
                        TomTom.wayframe:SetPoint("CENTER", UIParent, "CENTER")
                        TomTom.profile.arrow.location = nil
                    end
                },
                show = {
                    type = 'toggle',
                    order = 10,
                    name = 'Show the arrow',
                    desc = 'Show the arrow whenever there are waypoints. Resets to on at login.',
                    get = function(info) return not TomTom.isHide end,
                    set = function(info, value)
                        TomTom.isHide = not value
                        if value then TomTom.wayframe:Show() end
                    end
                }
            }
        },
        persistence = {
            type = 'group',
            order = 30,
            name = 'Saving',
            desc = 'What happens to waypoints between sessions',
            args = {
                savewaypoints = {
                    type = 'toggle',
                    order = 10,
                    name = 'Save waypoints between sessions',
                    desc = 'The default for newly created waypoints. A waypoint can still override it individually.',
                    get = function(info) return TomTom.profile.persistence.savewaypoints end,
                    set = function(info, value) TomTom.profile.persistence.savewaypoints = value end
                },
                cleardistance = {
                    type = 'range',
                    order = 20,
                    name = 'Clear distance (yards)',
                    min = -1, max = 100, step = 1,
                    desc = 'How close you must get before a waypoint removes itself',
                    get = function(info) return TomTom.profile.persistence.cleardistance end,
                    set = function(info, value) TomTom.profile.persistence.cleardistance = value end
                },

            }
        },
        general = {
            type = 'group',
            order = 10,
            name = 'General',
            desc = 'General behaviour',
            args = {
                announce = {
                    type = 'toggle',
                    order = 10,
                    name = 'Announce waypoints in chat',
                    desc = 'Print a line in chat when a waypoint is added or removed',
                    get = function(info) return TomTom.profile.general.announce end,
                    set = function(info, value) TomTom.profile.general.announce = value end
                },
                confirmremoveall = {
                    type = 'toggle',
                    order = 20,
                    name = 'Confirm before removing all waypoints',
                    desc = 'Ask for confirmation before clearing every waypoint at once',
                    get = function(info) return TomTom.profile.general.confirmremoveall end,
                    set = function(info, value) TomTom.profile.general.confirmremoveall = value end
                },
                corpsewaypoint = {
                    type = 'toggle',
                    order = 30,
                    name = 'Add a waypoint at your corpse',
                    desc = 'Drop a waypoint where you died',
                    get = function(info) return TomTom.profile.general.corpsewaypoint end,
                    set = function(info, value) TomTom.profile.general.corpsewaypoint = value end
                },
            }
        },
        worldmap = {
            type = 'group',
            order = 40,
            name = 'World Map',
            desc = 'Waypoints on the world map',
            args = {
                enable = {
                    type = 'toggle',
                    order = 10,
                    name = 'Show waypoints on the world map',
                    desc = 'Put new waypoints on the world map',
                    get = function(info) return TomTom.profile.worldmap.enable end,
                    set = function(info, value) TomTom.profile.worldmap.enable = value end
                },
                tooltip = {
                    type = 'toggle',
                    order = 20,
                    name = 'Show a tooltip on mouseover',
                    desc = 'Show a tooltip when the mouse is over a world map pin',
                    get = function(info) return TomTom.profile.worldmap.tooltip end,
                    set = function(info, value) TomTom.profile.worldmap.tooltip = value end
                },
                menu = {
                    type = 'toggle',
                    order = 30,
                    name = 'Right-click menu on pins',
                    desc = 'Enable the right-click context menu on world map pins',
                    get = function(info) return TomTom.profile.worldmap.menu end,
                    set = function(info, value) TomTom.profile.worldmap.menu = value end
                },
                create_modifier = {
                    type = 'select',
                    order = 40,
                    name = 'Modifier for creating a waypoint',
                    values = {
                        S = "Shift", C = "Ctrl", A = "Alt",
                        SC = "Shift+Ctrl", SA = "Shift+Alt", CA = "Ctrl+Alt",
                        SCA = "Shift+Ctrl+Alt",
                    },
                    desc = 'Which keys must be held while right-clicking the world map to create a waypoint',
                    get = function(info) return TomTom.profile.worldmap.create_modifier end,
                    set = function(info, value) TomTom.profile.worldmap.create_modifier = value end
                },

            }
        },
        minimap = {
            type = 'group',
            order = 50,
            name = 'Minimap',
            desc = 'Waypoints on the minimap',
            args = {
                enable = {
                    type = 'toggle',
                    order = 10,
                    name = 'Show waypoints on the minimap',
                    desc = 'Put new waypoints on the minimap',
                    get = function(info) return TomTom.profile.minimap.enable end,
                    set = function(info, value) TomTom.profile.minimap.enable = value end
                },
                tooltip = {
                    type = 'toggle',
                    order = 20,
                    name = 'Show a tooltip on mouseover',
                    desc = 'Show a tooltip when the mouse is over a minimap pin',
                    get = function(info) return TomTom.profile.minimap.tooltip end,
                    set = function(info, value) TomTom.profile.minimap.tooltip = value end
                },
                menu = {
                    type = 'toggle',
                    order = 30,
                    name = 'Right-click menu on pins',
                    desc = 'Enable the right-click context menu on minimap pins',
                    get = function(info) return TomTom.profile.minimap.menu end,
                    set = function(info, value) TomTom.profile.minimap.menu = value end
                },
            }
        },
    }
}

-- Kept returning (continent, zoneIndex, x, y): this is semi-public, and WayHandler and at
-- least one third-party addon read it.  mapID is available as a fifth return for new callers.
function TomTom:GetCurrentPlayerPosition()
    local x, y, mapID = hbd:GetPlayerZonePosition()
    if not mapID then return nil, nil, nil, nil, nil end
    local C, Z = hbd:GetCZFromMapID(mapID)
    return C, Z, x, y, mapID
end

function TomTom:CleanZoneName(s)
    return string.gsub(string.lower(s), "[^%a%d]", "")
end

-- Accepts three shapes, because third-party addons written against the Ace2 version pass the
-- first and must keep working:
--   AddMFWaypoint(continent, zoneIndex, x, y, opts)   -- the historical form
--   AddMFWaypoint(mapID, nil, x, y, opts)             -- a mapID (always >= 4)
--   AddMFWaypoint(nil, "zone name", x, y, opts)       -- resolve the name
-- Continent indices are 0-2 and the lowest mapID is 4, so the first argument alone
-- disambiguates the first two.
function TomTom:AddMFWaypoint(pcont, pzone, x, y, opts)
    opts = opts or {}
    local cont, zone, mapID, name = pcont, pzone, nil, nil

    if not cont then
        cont, zone, name, mapID = self:GetZoneInfo(self:CleanZoneName(zone))
    elseif type(cont) == "number" and cont > 2 then
        -- A mapID was passed directly.
        mapID = cont
        cont, zone = hbd:GetCZFromMapID(mapID)
        if not cont then
            self:Print("Could not find any matches for map id %s", mapID)
            return nil
        end
    else
        mapID = hbd:GetMapIDFromCZ(cont, zone)
    end

    -- The mapID is what matters.  The zone INDEX may legitimately be nil -- it is learned by
    -- observation, so it is unknown for a zone the player has not visited -- and requiring it
    -- here is what made "/way The Barrens ..." fail with "could not find the zone" even though
    -- the zone had resolved perfectly well.
    if not mapID then
        if not pcont and pzone then
            self:Print("Could not find any matches for the zone %s.", pzone)
            local cleanedName = string.lower(self:CleanZoneName(pzone))
            self:Print("If that zone really exists, add '%s' to TomTom.extraZones in TomTom.lua", cleanedName)
        else
            self:Print("Could not find any matches for the continent %s and zone %s", pcont, pzone)
        end
        return nil
    end

    -- Default values
    if opts.persistent == nil then opts.persistent = self.profile.persistence.savewaypoints end
    if opts.minimap == nil then opts.minimap = self.profile.minimap.enable end
    if opts.world == nil then opts.world = self.profile.worldmap.enable end
    if opts.crazy == nil then opts.crazy = self.profile.arrow.autoqueue end
    if opts.cleardistance == nil then opts.cleardistance = self.profile.persistence.cleardistance end
    if opts.arrivaldistance == nil then opts.arrivaldistance = self.profile.arrow.arrival end

    -- uid is the 'new waypoint' called this for historical reasons
    -- continent/zone stay for compatibility: third-party addons and the saved-variable format
    -- read them, and zone may be nil until that index has been observed.  mapID is what
    -- everything internal uses from here on.
    local uid = {continent = cont, zone = zone, mapID = mapID,
        x = x, y = y, title = opts.title}

    -- Copy over any options, so we have em
    for k,v in pairs(opts) do
        if not uid[k] then
            uid[k] = v
        end
    end

    -- If this is a persistent waypoint, then add it to the waypoints table
    -- self.isLoading, not the undefined global `isLoading` this used to read.  Nothing currently
    -- restores waypoints through AddMFWaypoint (OnProfileEnable calls LoadWayPoint directly), so
    -- the broken guard was latent rather than actively duplicating anything -- but a real one costs
    -- nothing and protects the profile if that ever changes.
    if opts.persistent and not self.isLoading then
        table.insert(self.waypointprofile, uid)
    end

    if not opts.silent and self.profile.general.announce then
        local zoneName = hbd:GetLocalizedMap(mapID)
        local ctxt = self:RoundCoords(x, y, 2)
        local desc = opts.title and opts.title or ""
        local sep = opts.title and " - " or ""
        self:Print("Added a waypoint (%s%s%s) in %s", desc, sep, ctxt, zoneName)
    end
    return self:LoadWayPoint(uid)
end

function TomTom:LoadWayPoint(uid)
    table.insert(self.waypoints, uid)
    if uid.crazy then
        self:SetArrowWaypoint(uid)
    end
    if not uid.callbacks then
        uid.callbacks = self:DefaultCallbacks()
    end
    -- No need to convert x and y because they're already 0-1 instead of 0-100
    self:SetWaypoint(uid, uid.callbacks, uid.minimap, uid.world)
    return uid
end
--[[-------------------------------------------------------------------
--  Dropdown menu code
-------------------------------------------------------------------]]--

StaticPopupDialogs["TOMTOM_REMOVE_ALL_CONFIRM"] = {
    preferredIndex = STATICPOPUPS_NUMDIALOGS,
    text = "Are you sure you would like to remove ALL TomTom waypoints?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        TomTom:RemoveAllWaypoints()
    end,
    timeout = 30,
    whileDead = 1,
    hideOnEscape = 1,
}

local dropdown_info = {
    -- Define level one elements here
    [1] = {
        { -- Title
            text = "Waypoint Options",
            isTitle = 1,
        },
        { -- hide crazy arrow
            text = "Hide waypoint arrow",
            visible = function()
                return TomTom.dropdown.isArrow
            end,
            func = function()
                TomTom.isHide = true
            end,
        },
        { -- set as crazy arrow
            text = "Set as waypoint arrow",
            disabled = function()
                return TomTom.dropdown.uid == TomTom.active_waypoint
            end,
            visible = function()
                return not TomTom.dropdown.isArrow
            end,
            func = function()
                local uid = TomTom.dropdown.uid
                local data = uid
                TomTom:SetArrowWaypoint(uid)
            end,
        },
        { -- Remove waypoint
            text = "Remove waypoint",
            func = function()
                local uid = TomTom.dropdown.uid
                local data = uid
                TomTom:GoToNextWayPoint(uid)
                --TomTom:PrintF("Removing waypoint %0.2f, %0.2f in %s", data.x, data.y, data.zone)
            end,
        },
        { -- Remove all waypoints from this zone
            text = "Remove all waypoints from this zone",
            func = function()
                local uid = TomTom.dropdown.uid
                local data = uid
                local continent, zone = data.continent, data.zone

                local zoneName = TomTom:GetWaypointZoneName(data)
                local numRemoved = 0
                local hadArrow = TomTom.active_waypoint ~= nil
                -- Prefer the mapID here too: `zone` is a client-state index and is nil for a
                -- waypoint created from a mapID, which would match no waypoints at all.
                local waypoints
                if data.mapID then
                    waypoints = TomTom:GetWaypoints(data.mapID)
                else
                    waypoints = TomTom:GetWaypoints(continent, zone)
                end
                if waypoints and table.getn(waypoints) > 0 then
                    for _, uid in pairs(waypoints) do
                        TomTom:RemoveWaypoint(uid, true)
                        numRemoved = numRemoved + 1
                    end
                    -- RemoveWaypoint clears the crazy arrow if it took the waypoint the arrow
                    -- was pointing at, and leaves it cleared.  Re-point it at whatever is left,
                    -- the same way removing a single waypoint does -- but only if it was
                    -- actually lost, so resetting some other zone does not steal the arrow and
                    -- a reset with no arrow up does not raise one.
                    if hadArrow and not TomTom.active_waypoint then
                        TomTom:GoToNextWayPoint()
                    end
                    TomTom:Print("Removed %d waypoints from %s", numRemoved, zoneName)
                end
            end,
        },
        { -- Remove ALL waypoints
            text = "Remove all waypoints",
            func = function()
                if TomTom.db.profile.general.confirmremoveall then
                    StaticPopup_Show("TOMTOM_REMOVE_ALL_CONFIRM")
                else
                    StaticPopupDialogs["TOMTOM_REMOVE_ALL_CONFIRM"].OnAccept()
                    return
                end
            end,
        },
        { -- Save this waypoint
            text = "Save this waypoint between sessions",
            checked = function()
                return TomTom.dropdown.uid.persistent
            end,
            func = function()
                -- Add/remove it from the SV file
                local uid = TomTom.dropdown.uid
                uid.persistent = not uid.persistent
                if uid.persistent then
                    table.insert(TomTom.waypointprofile, uid)
                else
                    for k, w in pairs(TomTom.waypointprofile) do
                        if w == uid then
                            table.remove(TomTom.waypointprofile, k)
                            break
                        end
                    end
                end
            end,
        },
    },
}

local function init_dropdown(self, level)
    -- Make sure level is set to 1, if not supplied
    level = level or 1

    -- Get the current level from the info table
    local info = dropdown_info[level]

    -- If a value has been set, try to find it at the current level
    if level > 1 and UIDROPDOWNMENU_MENU_VALUE then
        if info[UIDROPDOWNMENU_MENU_VALUE] then
            info = info[UIDROPDOWNMENU_MENU_VALUE]
        end
    end

    -- Add the buttons to the menu
    for idx,entry in ipairs(info) do
        if type(entry.checked) == "function" then
            -- Make this button dynamic
            local new = {}
            for k,v in pairs(entry) do new[k] = v end
            new.checked = new.checked()
            entry = new
        else
            entry.checked = nil
        end
        if type(entry.visible) == "function" then
            if (not entry.visible()) then
                entry = nil
            end
        end
        if entry ~= nil then
            UIDropDownMenu_AddButton(entry, level)
        end
    end
end

function TomTom:InitializeDropdown(uid, isArrow)
    self.dropdown.uid = uid
    self.dropdown.isArrow = isArrow
    UIDropDownMenu_Initialize(self.dropdown, init_dropdown)
end

--[[-------------------------------------------------------------------
--  Define callback functions
-------------------------------------------------------------------]]--
local function _minimap_onclick(event, uid, self, button)
    if TomTom.db.profile.minimap.menu then
        TomTom:InitializeDropdown(uid, false)
        TomTom.dropdown:SetClampedToScreen(true);
        ToggleDropDownMenu(1, nil, TomTom.dropdown, "cursor", 0, 0)
    end
end

local function _world_onclick(event, uid, self, button)
    if TomTom.db.profile.worldmap.menu then
        TomTom:InitializeDropdown(uid, false)
        ToggleDropDownMenu(1, nil, TomTom.dropdown, "cursor", 0, 0)
    end
end

local function _both_tooltip_show(event, tooltip, uid, dist)
    local data = uid

    tooltip:SetText(data.title or "TomTom waypoint")
    if dist and tonumber(dist) then
        tooltip:AddLine(string.format("%s yards away", math.floor(dist)), 1, 1, 1)
    else
        tooltip:AddLine("Unknown distance")
    end
    local zoneName = TomTom:GetWaypointZoneName(data)
    local x, y = data.x, data.y

    tooltip:AddLine(string.format("%s (%.2f, %.2f)", zoneName, x*100, y*100), 0.7, 0.7, 0.7)
    tooltip:Show()
end

local function _minimap_tooltip_show(event, tooltip, uid, dist)
    if not TomTom.db.profile.minimap.tooltip then
        tooltip:Hide()
        return
    end
    return _both_tooltip_show(event, tooltip, uid, dist)
end

local function _world_tooltip_show(event, tooltip, uid, dist)
    if not TomTom.db.profile.worldmap.tooltip then
        tooltip:Hide()
        return
    end
    return _both_tooltip_show(event, tooltip, uid, dist)
end

local function _both_tooltip_update(event, tooltip, uid, dist)
    if not tooltip or not tooltip.lines then return end
    if dist and tonumber(dist) then
        tooltip.lines[2]:SetFormattedText("%s yards away", math.floor(dist), 1, 1, 1)
    else
        tooltip.lines[2]:SetText("Unknown distance")
    end
end


function TomTom:DefaultCallbacks()
    return {
        minimap = {
            onclick = _minimap_onclick,
            tooltip_show = _minimap_tooltip_show,
            tooltip_update = _both_tooltip_update
        },
        world = {
            onclick = _world_onclick,
            tooltip_show = _world_tooltip_show,
            tooltip_update = _both_tooltip_show
        }
    }
end

-- The addon's own Print is kept rather than AceConsole's, because this one string.formats and
-- AceConsole:Print does not (that is Printf) -- keeping it leaves all nine call sites alone.
-- What it did NOT do was prefix the addon name, so each message carried its own, inconsistently:
-- three said plain "TomTom:", two used |cffffff78TomTom:|r, and four said nothing at all.  Those
-- have been stripped, and the prefix is emitted here in AceConsole-3.0's exact format --
-- "|cff33ff99<name>|r:" -- so TomTom looks like every other Ace3 addon in the chat frame.
-- tostring(self) is "TomTom" via AceAddon-3.0's __tostring.
function TomTom:Print(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)
    a1 = tostring(a1)
    local msg
    if string.find(a1, "%%") then
        msg = string.format(a1, tostring(a2), tostring(a3), tostring(a4), tostring(a5), tostring(a6), tostring(a7), tostring(a8), tostring(a9), tostring(a10), tostring(a11), tostring(a12), tostring(a13), tostring(a14), tostring(a15), tostring(a16), tostring(a17), tostring(a18), tostring(a19), tostring(a20))
    else
        msg = a1
    end
    self:log("|cff33ff99" .. tostring(self) .. "|r: " .. msg)
end

-- Accepts (continent, zoneIndex) or (mapID) -- see resolveMapID.  Filtering on the mapID rather
-- than the index pair means this keeps working for a zone whose index has never been observed.
function TomTom:GetWaypoints(cont, zone)
    local mapID = resolveMapID(cont, zone)
    local ret = {}
    if not mapID then return ret end
    for _, wp in pairs(self.waypoints) do
        local wpID = wp.mapID or resolveMapID(wp.continent, wp.zone)
        if wpID == mapID then
            table.insert(ret, wp)
        end
    end
    return ret
end

function TomTom:DebugListWaypoints(zone)
    local all = zone == "all"
    local singleZone = not all and zone ~= nil and zone or nil
    local cont,zoneid,x,y = self:GetCurrentPlayerPosition()
    local _, _, czone = self:GetZoneInfo(zoneid, cont)
    local ctxt = self:RoundCoords(x, y, 2)
    self:Print("You are at (%s) in '%s' (continent: %d, zone id: %d)", ctxt, czone or "UNKNOWN", cont, zoneid)
    if singleZone ~= nil then
        cont, zoneid, czone = self:GetZoneInfo(singleZone)
    end
    local wps = all and self.waypoints or self:GetWaypoints(cont, zoneid)
    if wps and table.getn(wps) > 0 then
        for key, wp in pairs(wps) do
            local ctxt = self:RoundCoords(wp.x, wp.y, 2)
            local desc = wp.title and wp.title or "Unknown waypoint"
            -- The original used select(), which does not exist in Lua 5.0, so "/way list all"
            -- errored out and never worked at all.
            --
            -- Not `all`: every waypoint listed is in `czone` by construction, so that is its
            -- name.  For `all` the waypoints span zones and each needs its own.  Ask the mapID
            -- first: it is the waypoint's real identity, while wp.zone is a client-state index
            -- that is simply unknown for a zone whose map the player has never opened.
            local wpzone = czone
            if all then wpzone = self:GetWaypointZoneName(wp) end
            local indent = "   "
            self:Print("%s%s - %s (continent: %s, zone id: %s, zone: %s)", indent, desc, ctxt, wp.continent, wp.zone, wpzone)
        end
    else
        local indent = "   "
        self:Print("%sNo waypoints%s", indent, all and "" or " in this zone")
    end
end

function TomTom:InitConsole()
    self.options.name = "TomTom"

    -- AceDBOptions-3.0 gives us profile management, which this addon never had.
    local dbo = LibStub("AceDBOptions-3.0", true)
    if dbo then
        self.options.args.profiles = dbo:GetOptionsTable(self.db)
        self.options.args.profiles.order = 100
    end

    -- The options window.  LibConfig-1.0 consumes an AceConfig-format options table -- the very
    -- shape AceConfigDialog-3.0 takes -- so TomTom.options drives it unchanged: the tree uses
    -- only group, toggle, range and select, and LibConfig renders all four.
    --
    -- AddToBlizOptions is deliberately not called.  It is optional, and the Blizzard Interface
    -- Options frame it hangs the panel on is exactly what is broken on Unreal Azeroth --
    -- replacing it is why this library exists.  OpenToCategory is the call that stands in.
    self.options.args.profiles = self:GetProfileOptions()
    -- LibConfig defaults a missing `order` to 100 and the four real groups are 20..50, so the
    -- profile panel would land last anyway -- but saying so keeps it there if a group is added.
    self.options.args.profiles.order = 100
    LibStub("LibConfig-1.0"):RegisterOptionsTable("TomTom", "TomTom", self.options)

    -- The command goes in WITHOUT a leading slash: AceConsole does
    -- _G["SLASH_"..name.."1"] = "/"..strlower(command) (AceConsole-3.0.lua), so "tomtom"
    -- becomes /tomtom.  Passing "/tomtom" would register //tomtom.
    self:RegisterChatCommand("tomtom", "OpenOptions")

    TomTomWayHandler:Register(self)
end

function TomTom:OpenOptions()
    LibStub("LibConfig-1.0"):OpenToCategory("TomTom")
end

-- The profile panel.
--
-- AceDBOptions-3.0 generates the standard Ace3 profile options -- new / choose / copy / reset /
-- delete -- straight off a real AceDB-3.0 database, which self.db is.  Its table uses only
-- description, execute, group, input and select, every one of which LibConfig renders, so the
-- panel needs no UI code of our own.
--
-- One member does need help.  AceDBOptions marks the delete dropdown `confirm = true`, and
-- LibConfig lists `confirm` among the members it inherits but never resolves or acts on it, so
-- picking a profile there would delete it with no prompt.  Two places could carry the fix and
-- only one of them is safe:
--
--   * `options.args` is AceDBOptions' MODULE-LEVEL table -- every database is handed the same
--     one -- so editing it would change the panel for every other addon in the session.
--   * `options.handler` is per database (AceDBOptions.handlers[db], with the prototype's
--     methods copied in rather than inherited), so overriding one method there reaches nothing
--     but TomTom.
--
-- Hence the wrapper goes on the handler.  LibConfig is upstream and not ours to patch.
function TomTom:GetProfileOptions()
    local options = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
    local handler = options.handler
    if not handler or not handler.DeleteProfile then return options end

    local deleteProfile = handler.DeleteProfile
    local pending
    StaticPopupDialogs["TOMTOM_DELETE_PROFILE_CONFIRM"] = {
        preferredIndex = STATICPOPUPS_NUMDIALOGS,
        text = "Are you sure you would like to delete the profile '%s'?",
        button1 = "Yes",
        button2 = "No",
        -- The name is kept in a closure rather than read back off the dialog: vanilla calls
        -- OnAccept with no arguments, and text_arg1 only ever reaches the message.
        OnAccept = function()
            if pending then deleteProfile(handler, nil, pending) end
            pending = nil
        end,
        OnCancel = function() pending = nil end,
        timeout = 30,
        whileDead = 1,
        hideOnEscape = 1,
    }
    handler.DeleteProfile = function(handlerSelf, info, value)
        pending = value
        StaticPopup_Show("TOMTOM_DELETE_PROFILE_CONFIRM", value)
    end
    return options
end

function TomTom:SetClosestWaypoint()
    local closestW, closestD
    for _, w in pairs(self.waypoints) do
        local dist = self:GetDistanceToIcon(w)
        if not closestW or not closestD or dist and dist < closestD then
            closestW, closestD = w, dist
        end
    end
    if closestW then
        self:SetArrowWaypoint(closestW)
    else
        self:Print("No waypoints on this continent")
    end
end

function TomTom:GoToNextWayPoint(wpToRemove)
    if wpToRemove ~= nil then
        self:RemoveWaypoint(wpToRemove)
    end
    local nWayPoints = table.getn(self.waypoints)
    if nWayPoints < 1 then
        self:ClearCrazyArrow()
    elseif self.profile.arrow.continueclosest then
        self:SetClosestWaypoint()
    else
        self:SetArrowWaypoint(self.waypoints[nWayPoints])
    end
end

function TomTom:RemoveWaypointsOfGroup(group)
    for i = table.getn(self.waypoints), 1, -1 do
        local wp = self.waypoints[i]
        if wp.group == group then
            self:RemoveWaypoint(wp, true)
        end
    end
    self:GoToNextWayPoint()
end

function TomTom:RemoveWaypoint(waypointUid, silent)
    for k, w in pairs(self.waypoints) do
        if w == waypointUid then
            table.remove(self.waypoints, k)
            break
        end
    end
    for k, w in pairs(self.waypointprofile) do
        if w == waypointUid then
            table.remove(self.waypointprofile, k)
            break
        end
    end
    if self.active_waypoint == waypointUid then
        self:ClearCrazyArrow()
    end
    self:ClearWaypoint(waypointUid)
    if not silent and not waypointUid.silent and self.profile.general.announce then
        local zoneName = self:GetWaypointZoneName(waypointUid)
        local ctxt = self:RoundCoords(waypointUid.x, waypointUid.y, 2)
        local desc = waypointUid.title and waypointUid.title or ""
        local sep = waypointUid.title and " - " or ""
        self:Print("Removed a waypoint (%s%s%s) in %s", desc, sep, ctxt, zoneName)
    end
end

function TomTom:RemoveAllWaypoints()
    for i = table.getn(self.waypoints), 1, -1 do
        self:RemoveWaypoint(self.waypoints[i], true)
    end
end

function TomTom:OnProfileEnable()
    -- This handles the reloading of all options
    self.profile = self.db.profile
    if self.profile.arrow.location ~= nil then
        local point, parent, relative, offx, offy = self.profile.arrow.location[1], self.profile.arrow.location[2], self.profile.arrow.location[3], self.profile.arrow.location[4], self.profile.arrow.location[5]
        -- Cleared first: the saved point is whichever screen edge the arrow was nearest when it
        -- was dropped, so it can differ from the CENTER given at creation, and a second SetPoint
        -- with a different point ADDS an anchor instead of replacing it -- which stretches the
        -- frame between the two.  Safe because a full point is set on the next line.
        self.wayframe:ClearAllPoints()
        self.wayframe:SetPoint(point, parent, relative, offx, offy)
    else
        self.wayframe:ClearAllPoints()
        self.wayframe:SetPoint("CENTER", UIParent, "CENTER")
    end
    if self.waypoints then
        for _, w in pairs(self.waypoints) do
            self:ClearWaypoint(w)
        end
        self:ClearCrazyArrow()
    end

    local waypoints = {}
    self.waypoints = waypoints

    if (self.db.profile.waypoints == nil) then
        self.db.profile.waypoints = {}
    end
    self.waypointprofile = self.db.profile.waypoints

    self.isLoading = true
    for _, waypoint in pairs(self.waypointprofile) do
        waypoint.callbacks = nil
        self:LoadWayPoint(waypoint)
    end
    self.isLoading = nil
end

--------------------------------------------------------------------------------------------
-- Zone indices
--
-- The map library learns (continent, zoneIndex) -> mapID by observation, so it only knows the
-- zones the player has actually visited.  Nothing internal needs the index any more -- every
-- path keys off the mapID -- but three things still surface it: the continent/zone fields kept
-- on each waypoint for third-party readers, "/way reset <zone>", and "/way list".  So fill the
-- table in once per session, from a safe moment.
--
-- This costs two SetMapZoom calls, one per continent, and the library restores the user's map
-- view afterwards.  It is NOT Astrolabe's sweep, which called SetMapZoom(C, Z) once per zone --
-- about 46 times -- and is what broke on this client in the first place.
--------------------------------------------------------------------------------------------

do
    local learned
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function()
        if learned then return end
        if WorldMapFrame and WorldMapFrame:IsVisible() then return end
        hbd:LearnZoneIndices(1)
        hbd:LearnZoneIndices(2)
        learned = true
    end)
end
