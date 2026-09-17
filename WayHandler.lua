
TomTomWayHandler = {}

TomTomWayHandler.tomtom = nil

function TomTomWayHandler:Register(tomtom)
    self.tomtom = tomtom

    SLASH_TOMTOM_WAY1 = "/way"
    SLASH_TOMTOM_WAY2 = "/tway"
    SLASH_TOMTOM_WAY3 = "/tomtomway"
    SlashCmdList["TOMTOM_WAY"] = function(msg) self:ChatHandler(msg) end

    SLASH_TOMTOM_CLOSEST_WAYPOINT1 = "/cway"
    SLASH_TOMTOM_CLOSEST_WAYPOINT2 = "/closestway"
    SlashCmdList["TOMTOM_CLOSEST_WAYPOINT"] = function(msg) self.tomtom:SetClosestWaypoint() end

    SLASH_TOMTOM_WAYBACK1 = "/wayb"
    SLASH_TOMTOM_WAYBACK2 = "/wayback"
    SlashCmdList["TOMTOM_WAYBACK"] = function(msg) self:AddWayBack() end
end

--[[
/way <x> <y> [desc] - Adds a waypoint at x,y with description desc
/way <zone> <x> <y> [desc] - Adds a waypoint at x,y in zone with descript desc
/way reset all - Resets all waypoints
/way reset <zone> - Resets all waypoints in zone
/way list - Lists active waypoints
]]

function TomTomWayHandler:Usage()
    local out = self.tomtom
    out:Print("|cffffff78/way|r usage:")
    out:Print("|cffffff78/way <x> <y> [desc]|r - Adds a waypoint at x,y with description desc")
    out:Print("|cffffff78/way <zone> <x> <y> [desc]|r - Adds a waypoint at x,y in zone with description desc")
    out:Print("|cffffff78/way reset|r - Resets waypoints in current zone")
    out:Print("|cffffff78/way reset all|r - Resets all waypoints")
    out:Print("|cffffff78/way reset <zone>|r - Resets all waypoints in zone")
    out:Print("|cffffff78/way list|r - Lists active waypoints in current zone")
    out:Print("|cffffff78/way list all|r - Lists all active waypoints")
    out:Print("|cffffff78/way list <zone>|r - Lists active waypoints in zone")
end

function TomTomWayHandler:AddWayBack()
    local backc, backz, backx, backy = self.tomtom:GetCurrentPlayerPosition()
    if not backc then return end
    self.tomtom:AddMFWaypoint(backc, backz, backx, backy, {
        title = "Wayback",
    })
end

function TomTomWayHandler:ChatHandler(msg)
    msg = msg or ""
    local wrongseparator = "(%d)" .. (tonumber("1.1") and "," or ".") .. "(%d)"
    local rightseparator = "%1" .. (tonumber("1.1") and "." or ",") .. "%2"

    msg = string.gsub(string.gsub(msg, "(%d)[%.,] (%d)", "%1 %2"), wrongseparator, rightseparator)
    local tokens = {}
    string.gsub(msg, "(%S+)", function(c) table.insert(tokens, c) end)

    -- Lower the first token
    local ltoken = tokens[1] and string.lower(tokens[1])

    if ltoken == "list" then
        local ltoken2 = tokens[2] and string.lower(tokens[2])
        if ltoken2 ~= nil and ltoken2 ~= "all" then
            ltoken2 = TomTom:CleanZoneName(table.concat(tokens, " ", 2))
        end
        TomTom:DebugListWaypoints(ltoken2)
        return
    elseif ltoken == "reset" or ltoken == "remove" or ltoken == "clear" or ltoken == "clean" or ltoken == "del" or ltoken == "delete" then
        local ltoken2 = tokens[2] and string.lower(tokens[2])
        if ltoken2 == "all" then
            if TomTom.db.profile.general.confirmremoveall then
                StaticPopup_Show("TOMTOM_REMOVE_ALL_CONFIRM")
            else
                StaticPopupDialogs["TOMTOM_REMOVE_ALL_CONFIRM"].OnAccept()
                return
            end
        else
            -- `zone` must live out here: the failure message below names it, and when it was
            -- scoped to the else branch that message formatted a nil.
            local cont, zoneid, mapID, zone
            if not ltoken2 then
                local _
                cont, zoneid, _, _, mapID = TomTom:GetCurrentPlayerPosition()
            else
                zone = table.concat(tokens, " ", 2)
                local _
                cont, zoneid, _, mapID = TomTom:GetZoneInfo(TomTom:CleanZoneName(zone))
            end
            if cont == nil and not mapID then
                self.tomtom:Print("Could not find any matches for zone %s.", zone or "")
                return
            end
            -- Work from the mapID, not the zone index.  The index is client state the map
            -- library learns by observation, so it is nil for a zone whose map the player has
            -- never opened -- and then both the name and the match below came out empty.
            local zoneName = mapID and TomTom:GetZoneName(mapID)
            local numRemoved = 0
            local hadArrow = TomTom.active_waypoint ~= nil
            local waypoints
            if mapID then
                waypoints = TomTom:GetWaypoints(mapID)
            else
                waypoints = TomTom:GetWaypoints(cont, zoneid)
            end
            if waypoints and table.getn(waypoints) > 0 then
                for key, uid in pairs(waypoints) do
                    TomTom:RemoveWaypoint(uid, true)
                    numRemoved = numRemoved + 1
                end
                -- As above: RemoveWaypoint leaves the crazy arrow cleared if it took the
                -- waypoint the arrow was on.  Send it to the next one instead of nowhere.
                if hadArrow and not TomTom.active_waypoint then
                    TomTom:GoToNextWayPoint()
                end
                self.tomtom:Print("Removed %d waypoints from %s", numRemoved, zoneName)
            else
                self.tomtom:Print("There were no waypoints to remove in %s", zoneName)
            end
        end
    elseif tokens[1] and not tonumber(tokens[1]) then
        -- Example: /way Elwynn Forest 34.2 50.7 Party in the forest!
        -- tokens[1] = Elwynn
        -- tokens[2] = Forest
        -- tokens[3] = 34.2
        -- tokens[4] = 50.7
        -- tokens[5] = Party
        -- ...
        --
        -- Find the first numeric token
        local zoneEnd
        for idx = 1, table.getn(tokens) do
            local token = tokens[idx]
            if tonumber(token) then
                -- We've encountered a number, so the zone name must have
                -- ended at the prior token
                zoneEnd = idx - 1
                break
            end
        end

        if not zoneEnd then
            self:Usage()
            return
        end

        -- This is a waypoint set, with a zone before the coords
        local zone = table.concat(tokens, " ", 1, zoneEnd)
        local x, y, desc = tokens[zoneEnd + 1], tokens[zoneEnd + 2], tokens[zoneEnd + 3]
        if desc then desc = table.concat(tokens, " ", zoneEnd + 3) end
        local cont, zoneid = TomTom:GetZoneInfo(TomTom:CleanZoneName(zone))

        if cont == nil then
            self.tomtom:Print("Could not find any matches for zone %s.", zone)
            return
        end

        x = x and tonumber(x)
        y = y and tonumber(y)

        if not x or not y then
            return self:Usage()
        end
        if x < 0 or x > 100 or y < 0 or y > 100 then
            self.tomtom:Print("Coordinates must be between 0 and 100 (got %s, %s)", x, y)
            return self:Usage()
        end
        self.tomtom:AddMFWaypoint(cont, zoneid, x/100, y/100, {
            title = desc,
        })
    elseif tonumber(tokens[1]) then
        -- A vanilla set command
        local x,y,desc = unpack(tokens)
        if not x or not tonumber(x) then
            return self:Usage()
        elseif not y or not tonumber(y) then
            return self:Usage()
        end
        if desc then
            desc = table.concat(tokens, " ", 3)
        end
        x = tonumber(x)
        y = tonumber(y)

        -- A map coordinate is a percentage, so anything outside 0-100 is a typo, not a position.
        -- Without this, "/way 1440 62.4 34.1 <name>" -- a Wowhead TomTom link with the leading #
        -- dropped -- was read as x = 1440, i.e. fourteen zone widths east, and silently placed a
        -- waypoint about 140,000 yards away instead of reporting the mistake.
        if x < 0 or x > 100 or y < 0 or y > 100 then
            self.tomtom:Print("Coordinates must be between 0 and 100 (got %s, %s)", x, y)
            return self:Usage()
        end

        local cont, zone = TomTom:GetCurrentPlayerPosition()
        if cont and zone and x and y then
            self.tomtom:AddMFWaypoint(cont, zone, x/100, y/100, {
                title = desc
            })
        end
    else
        return self:Usage()
    end
end
