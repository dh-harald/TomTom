
local tooltip = CreateFrame("GameTooltip", "TomTomTooltip", UIParent, "GameTooltipTemplate")

-- Store a reference to the minimap parent
local minimapParent = Minimap

-- Create a local table used as a frame pool
local pool = {}
local all_points = {}

-- Local declarations
local Minimap_OnEnter,Minimap_OnLeave,Minimap_OnUpdate,Minimap_OnClick,Minimap_OnEvent
local Arrow_OnUpdate
local World_OnEnter,World_OnLeave,World_OnClick

local square_half = math.sqrt(0.5)
local rad_135 = math.rad(135)

local hbd = LibStub("LibHereBeDragons-1.0")
local hbdp = LibStub("LibHereBeDragons-Pins-1.0")

local function rotateArrow(self)
    if self.disabled then return end

    -- Radians now, so no math.rad here.  The old comment asking "why the hell is this in
    -- degrees from atan2" has its answer: vanilla's global atan2 is degree-based.  The library
    -- upvalues math.atan2 instead and returns radians, 0 = north, clockwise.
    local angle = hbdp:GetVectorToIcon(self)
    if not angle then return self:Hide() end
    angle = angle + rad_135

    -- Minimap rotation is the pins library's business now: it rotates the pin positions, and
    -- this arrow only shows the bearing to the pin, so nothing is needed here.

    local sin,cos = math.sin(angle), math.cos(angle) -- math.sin(angle) * square_half, math.cos(angle) * square_half
    self.arrow:SetTexCoord(0.5-sin, 0.5+cos, 0.5+cos, 0.5+sin, 0.5-cos, 0.5-sin, 0.5+sin, 0.5-cos)
end

function TomTom:ReparentMinimap(minimap)
    minimapParent = minimap
    for idx, waypoint in ipairs(all_points) do
        waypoint:SetParent(minimap)
    end
end

local waypointMap = {}

function TomTom:SetWaypoint(waypoint, callbacks, show_minimap, show_world)
    if waypointMap[waypoint] then return end

    -- m/f are the pins library's (mapID, floor) pair, NOT the old continent/zone indices.
    -- AddMinimapIconMF takes a mapID, so passing waypoint.continent here would place every pin
    -- as if it were in map 1 or 2.  Fall back to resolving the pair for a waypoint created
    -- before mapID existed, e.g. one restored from saved variables.
    local m = waypoint.mapID or hbd:GetMapIDFromCZ(waypoint.continent, waypoint.zone)
    local f, x, y = nil, waypoint.x, waypoint.y
    if not m then return end
    -- Try to acquire a waypoint from the frame pool
    local point = table.remove(pool)

    if not point then
        point = {}

        local minimap = CreateFrame("Button", nil, minimapParent)
        minimap:SetHeight(20)
        minimap:SetWidth(20)
        minimap:RegisterForClicks("RightButtonUp")

        -- Add to the "All points" table so we can reparent easily
        table.insert(all_points, minimap)

        minimap.icon = minimap:CreateTexture("BACKGROUND")
        minimap.icon:SetTexture("Interface\\AddOns\\TomTom\\Images\\GoldGreenDot")
        minimap.icon:SetPoint("CENTER", 0, 0)
        minimap.icon:SetHeight(12)
        minimap.icon:SetWidth(12)

        minimap.arrow = minimap:CreateTexture("BACKGROUND")
        minimap.arrow:SetTexture("Interface\\AddOns\\TomTom\\Images\\MinimapArrow-Green")
        minimap.arrow:SetPoint("CENTER", 0 ,0)
        minimap.arrow:SetHeight(40)
        minimap.arrow:SetWidth(40)
        minimap.arrow:Hide()

        -- Add the behavior scripts
        minimap:SetScript("OnEnter", Minimap_OnEnter)
        minimap:SetScript("OnLeave", Minimap_OnLeave)
        minimap:SetScript("OnUpdate", Minimap_OnUpdate)
        minimap:SetScript("OnClick", Minimap_OnClick)
        minimap:RegisterEvent("PLAYER_ENTERING_WORLD")
        minimap:SetScript("OnEvent", Minimap_OnEvent)

        if not TomTomMapOverlay then
            local overlay = CreateFrame("Frame", "TomTomMapOverlay", WorldMapButton)
            overlay:SetAllPoints(true)
            overlay:SetFrameLevel(WorldMapButton:GetFrameLevel() + 1)
        end

        local worldmap = CreateFrame("Button", nil, TomTomMapOverlay)
        worldmap:SetHeight(12)
        worldmap:SetWidth(12)
        worldmap:RegisterForClicks("RightButtonUp")
        worldmap.icon = worldmap:CreateTexture("ARTWORK")
        worldmap.icon:SetAllPoints()
        worldmap.icon:SetTexture("Interface\\AddOns\\TomTom\\Images\\GoldGreenDot")

        worldmap:RegisterEvent("WORLD_MAP_UPDATE")
        worldmap:SetScript("OnEnter", World_OnEnter)
        worldmap:SetScript("OnLeave", World_OnLeave)
        worldmap:SetScript("OnClick", World_OnClick)

        point.worldmap = worldmap
        point.minimap = minimap
    end

    waypointMap[waypoint] = point

    point.m = m
    point.f = f
    point.x = x
    point.y = y
    point.show_world = show_world
    point.show_minimap = show_minimap
    point.callbacks = callbacks
    point.worldmap.callbacks = callbacks and callbacks.world
    point.minimap.callbacks = callbacks and callbacks.minimap

    -- Process the callbacks table to put distances in a consumable format
    if callbacks and callbacks.distance then
        point.dlist = {}

        for k,v in pairs(callbacks.distance) do
            table.insert(point.dlist, k)
        end

        table.sort(point.dlist)
    end

    -- Clear the state for callbacks
    point.state = nil
    point.lastdist = nil

    -- Link the actual frames back to the waypoint object
    point.minimap.point = point
    point.worldmap.point = point
    point.uid = waypoint

    -- Place the waypoint
    hbdp:AddMinimapIconMF(self, point.minimap, m, f, x, y, true)

    if show_world then
        point.worldmap.disabled = false
        -- The library owns visibility from here: it decides which maps this pin belongs on and
        -- shows or hides it, so the manual 0..1 test and Show/Hide are gone.
        hbdp:AddWorldMapIconMF(self, point.worldmap, m, f, x, y, HBD_PINS_WORLDMAP_SHOW_WORLD)
    else
        point.worldmap.disabled = true
    end

    if not show_minimap then
        -- Hide the minimap icon/arrow if minimap is off
        point.minimap:EnableMouse(false)
        point.minimap.icon:Hide()
        point.minimap.arrow:Hide()
        point.minimap.disabled = true
        rotateArrow(point.minimap)
    else
        point.minimap:EnableMouse(true)
        point.minimap.disabled = false
        rotateArrow(point.minimap)
    end
end

-- TomTom:RedrawWorldMapIcons is gone.  It existed because WORLD_MAP_UPDATE is not reliably
-- fired on this client, so TomTom re-placed every world map icon from an OnUpdate.  The pins
-- library now does that centrally: WORLD_MAP_UPDATE plus a throttled refresh while the map is
-- open, and it also decides which maps each pin belongs on.

function TomTom:HideWaypoint(uid, minimap, worldmap)
    local point = waypointMap[uid]
    if point then
        if minimap then
            point.minimap.disabled = true
            point.minimap:Hide()
        end

        if worldmap then
            point.worldmap.disabled = true
            point.worldmap:Hide()
        end
    end
end

function TomTom:ShowWaypoint(uid)
    local point = waypointMap[uid]
    if point then
        -- Was point.data.show_minimap / point.data.show_worldmap.  SetWaypoint never sets a
        -- `data` field -- it writes point.show_minimap and point.show_world (note: world, not
        -- worldmap) -- so this errored on a nil index for anyone who called it.  Nothing in the
        -- addon does, which is why it went unnoticed.
        point.minimap.disabled = not point.show_minimap
        point.minimap:Show()

        point.worldmap.disabled = not point.show_world
        point.worldmap:Show()
    end
end

-- This function removes the waypoint from the active set
function TomTom:ClearWaypoint(uid)
    local point = waypointMap[uid]
    if point then
        hbdp:RemoveMinimapIcon(self, point.minimap)
        hbdp:RemoveWorldMapIcon(self, point.worldmap)
        point.minimap:Hide()
        point.worldmap:Hide()

        -- Clear our handles to the callback tables
        point.callbacks = nil
        point.minimap.callbacks = nil
        point.worldmap.callbacks = nil

        -- Clear disabled flags
        point.minimap.disabled = nil
        point.worldmap.disabled = nil

        point.dlist = nil
        point.uid = nil
        table.insert(pool, point)
        waypointMap[uid] = nil
    end
end

function TomTom:GetDistanceToWaypoint(uid)
    local point = waypointMap[uid]
    if not point then return end
    local _, dist = hbdp:GetVectorToIcon(point.minimap)
    return dist
end

function TomTom:GetDirectionToWaypoint(uid)
    local point = waypointMap[uid]
    if not point then return end
    return hbdp:GetVectorToIcon(point.minimap)
end


-- Was a near-verbatim copy of Astrolabe's private placeIconOnMinimap edge math, reading
-- Astrolabe.MinimapIcons and Astrolabe.minimapOutside plus the MinimapSize global, and carrying
-- its own Squeenix / simpleMinimap square-minimap test.  The pins library owns all of that now,
-- including the shape detection, so this is a straight delegation.
function TomTom:IsMinimapIconOnEdge(icon)
    return hbdp:IsMinimapIconOnEdge(icon) or false
end



do
    local tooltip_uid,tooltip_callbacks

    local function tooltip_onupdate(self, elapsed)
        if tooltip_callbacks and tooltip_callbacks.tooltip_update then
            local dist = TomTom:GetDistanceToWaypoint(tooltip_uid)
            tooltip_callbacks.tooltip_update("tooltip_update", tooltip, tooltip_uid, dist)
        end
    end

    function Minimap_OnClick(self, button)
        local self = this
        local data = self.callbacks

        if data and data.onclick then
            data.onclick("onclick", self.point.uid, self, button)
        end
    end

    function Minimap_OnEnter()
        local self = this
        local data = self.callbacks

        if data and data.tooltip_show then
            local uid = self.point.uid
            local dist = TomTom:GetDistanceToWaypoint(uid)

            tooltip_uid = uid
            tooltip_callbacks = data

            -- Parent to UIParent, unless it's hidden
            if UIParent:IsVisible() then
                tooltip:SetParent(UIParent)
            else
                tooltip:SetParent(self)
            end

            tooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")

            data.tooltip_show("tooltip_show", tooltip, uid, dist)
            tooltip:Show()

            -- Set the update script if there is one
            if data.tooltip_update then
                tooltip:SetScript("OnUpdate", tooltip_onupdate)
            else
                tooltip:SetScript("OnUpdate", nil)
            end
        end
    end

    function Minimap_OnLeave(self, motion)
        tooltip_uid,tooltip_callbacks = nil,nil
        tooltip:Hide()
    end

    World_OnEnter = Minimap_OnEnter
    World_OnLeave = Minimap_OnLeave
    World_OnClick = Minimap_OnClick

    local minimap_count = 0

    function Minimap_OnUpdate()
        local self = this
        local elapsed = 1/GetFramerate()
        local angle, dist = hbdp:GetVectorToIcon(self)
        local disabled = self.disabled
        if not dist then
            self:Hide()
            return
        end

        minimap_count = minimap_count + elapsed

        if minimap_count < 0.1 then return end

        -- Reset the counter
        minimap_count = 0

        local edge = TomTom:IsMinimapIconOnEdge(self)
        local data = self.point
        local callbacks = data.callbacks

        if edge then
            -- Check to see if this is a transition
            if not disabled then
                self.icon:Hide()
                self.arrow:Show()

                -- Rotate the icon, as required
                angle = math.rad(angle) + rad_135
                -- why the hell is this in degrees from atan2 method?

                --                if GetCVar("rotateMinimap") == "1" then
                --                    --local cring = MiniMapCompassRing:GetFacing()
                --                    local cring = GetPlayerFacing()
                --                    angle = angle - cring
                --                end
                local sin,cos = math.sin(angle) * square_half, math.cos(angle) * square_half
                self.arrow:SetTexCoord(0.5-sin, 0.5+cos, 0.5+cos, 0.5+sin, 0.5-cos, 0.5-sin, 0.5+sin, 0.5-cos)
            end
        else
            if not disabled then
                self.icon:Show()
                self.arrow:Hide()
            end
        end

        if callbacks and callbacks.distance then
            local list = data.dlist

            local state = data.state
            local newstate

            -- Calculate the initial state
            if not state then
                for i=1,table.getn(list) do
                    if dist <= list[i] then
                        state = i
                        break
                    end
                end

                -- Handle the case where we're outside the largest circle
                if not state then state = -1 end

                data.state = state
            else
                -- Calculate the new state
                for i=1,table.getn(list) do
                    if dist <= list[i] then
                        newstate = i
                        break
                    end
                end

                -- Handle the case where we're outside the largest circle
                if not newstate then newstate = -1 end
            end

            -- If newstate is set, then this is a transition
            -- If only state is set, this is the initial state

            if state ~= newstate then
                -- Handle the initial state
                newstate = newstate or state
                local distance = list[newstate]
                local callback = callbacks.distance[distance]
                if callback then
                    callback("distance", data.uid, distance, dist, data.lastdist)
                end
                data.state = newstate
            end

            -- Update the last distance with the current distance
            data.lastdist = dist
        end
    end

    function Minimap_OnEvent(self, event, ...)
        local self = this
        if event == "PLAYER_ENTERING_WORLD" then
            local data = self.point
            if data and data.uid and waypointMap[data.uid] then
                hbdp:AddMinimapIconMF(TomTom, self, data.m, data.f, data.x, data.y, true)
            end
        end
    end
end
