local LFL = RegisterMod('Looking for Ludovico', 1)

LFL.found_item = false
LFL.initial_room_idx = nil
LFL.scanning = false


--- Returns true if the current level can have a treasure room.
--- In Hard mode, there are treasure rooms in all levels up to
--- the level with Mom's fight.
---@param level Level
local function IsTreasureRoomInLevel(level)
	return level:GetStage() <= LevelStage.STAGE3_2
end


--- Saves the map state (display flags and visit count) of every room
--- in the level, indexed by the room's SafeGridIndex.
---
--- Instead of trying to guess which rooms the game reveals when we
--- teleport to the treasure room (the room itself, its neighbours, secret
--- rooms, etc.), we remember the state of ALL rooms and put it back later.
--- @param level Level
--- @return table
local function SnapshotMap(level)
	local snapshot = {}
	local rooms = level:GetRooms()

	for i = 0, #rooms - 1 do
		local desc = rooms:Get(i)
		snapshot[desc.SafeGridIndex] = {
			DisplayFlags = desc.DisplayFlags,
			VisitedCount = desc.VisitedCount,
		}
	end
	return snapshot
end


--- Restores a map state previously saved with SnapshotMap.
--- @param level Level
--- @param snapshot table
local function RestoreMap(level, snapshot)
	for idx, state in pairs(snapshot) do
		-- Descriptors from GetRoomByIdx are writable (the ones from
		-- GetRooms are read-only).
		local desc = level:GetRoomByIdx(idx)
		desc.DisplayFlags = state.DisplayFlags
		desc.VisitedCount = state.VisitedCount
	end

	-- Make the minimap pick up the restored flags.
	level:UpdateVisibility()
end


LFL:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
	local game = Game()
	local level = game:GetLevel()

	-- Never carry state over from the previous level.
	LFL.found_item = false
	LFL.initial_room_idx = nil

	if game:IsGreedMode() or (not IsTreasureRoomInLevel(level)) then
		-- Greed mode not supported and we can skip levels after
		-- Mom's fight (Womb, Utero, etc).
		return
	end

	local levelRoomsList = level:GetRooms()
	local player = Isaac.GetPlayer(0)
	local iPosition = player.Position
	local iRoomIdx  = level:GetCurrentRoomIndex()

	-- Remember how the map looks BEFORE we start jumping around.
	local mapSnapshot = SnapshotMap(level)

	-- Ignore MC_POST_NEW_ROOM while we are teleporting.
	LFL.scanning = true

	for i = 0, #levelRoomsList - 1 do
		local room = levelRoomsList:Get(i)

		if room.Data.Type == RoomType.ROOM_TREASURE then

			-- Change room to force item load/generation
			player.Position = Vector(350,0)
			game:ChangeRoom(room.GridIndex)

			local pickups = Isaac.FindByType(
				EntityType.ENTITY_PICKUP,
				PickupVariant.PICKUP_COLLECTIBLE,
				-1, false, false
			)

			for _, pickup in ipairs(pickups) do
				if pickup.SubType == CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE then
					game:GetPlayer(0):AnimateHappy()
					LFL.found_item = true
					break
				end
			end

			game:GetRoom():Update()

			-- Come back to the initial room
			game:ChangeRoom(iRoomIdx)
			-- (the position must be set AFTER the room change, otherwise
			-- the game overrides it)
			Isaac.GetPlayer(0).Position = iPosition

			if LFL.found_item then
				break
			end
		end
	end

	-- Put the map back exactly as it was: treasure room unvisited and no
	-- room revealed by the trip.
	RestoreMap(level, mapSnapshot)

	LFL.scanning = false
	LFL.initial_room_idx = iRoomIdx
end)


LFL:AddCallback(ModCallbacks.MC_POST_RENDER, function()
	if LFL.found_item then
		local position = Isaac.GetPlayer(0).Position

		position.X = position.X - 150
		position.Y = position.Y - 80
		local renderpos = Isaac.WorldToScreen(position)
		Isaac.RenderText("I can feel Ludovico's", renderpos.X, renderpos.Y, 1,1,1,1)

		position.X = position.X + 30
		position.Y = position.Y + 20
		renderpos = Isaac.WorldToScreen(position)
		Isaac.RenderText("presence...", renderpos.X, renderpos.Y, 1,1,1,1)
	end
end)


LFL:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
	if LFL.scanning or not LFL.initial_room_idx then
		return
	end

	-- Compare room indexes (plain numbers) instead of Room userdata objects.
	if Game():GetLevel():GetCurrentRoomIndex() ~= LFL.initial_room_idx then
		LFL.initial_room_idx = nil
		LFL.found_item = false
	end
end)