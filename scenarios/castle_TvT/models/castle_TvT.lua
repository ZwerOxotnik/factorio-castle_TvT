config = require("config")
---@type ZOsurface
surface_util = require("zk-static-lib/lualibs/control_stage/surface-util")
---@type ZOplayer_util
player_util  = require("zk-static-lib/lualibs/control_stage/player-util")
---@type ZOdata_util
data_util    = require("zk-static-lib/lualibs/control_stage/data-util")
---@type ZOcoordinates_util
coordinates_util    = require("zk-static-lib/lualibs/coordinates-util")


local _mini_battle_inventory = require("mini_battle_inventory")
local _disabled_recipes = require("disabled_recipes")
local _start_inventory  = require("start_inventory")
local _tank_inventory   = require("tank_inventory")
local _disabled_techs   = require("disabled_techs")
local _default_techs    = require("default_techs")

local _is_mini_battle_inventory_checked = false
local _is_disabled_recipes_checked = false
local _is_start_inventory_checked  = false
local _is_tank_inventory_checked   = false
local _is_disabled_techs_checked   = false
local _is_default_techs_checked    = false


---@class CastleTvTModule : module
local M = {}


--#region Global data
--local _players_data
---@class _teams_data
---@field safe_zone table
---@field force LuaForce
local _teams_data
---@class table[]
local _active_safe_zones
--#endregion


--#region Constants
local abs, min = math.abs, math.min
local DESTROY_PARAM = {raise_destroy = true} --[[@as LuaEntity.destroy_param]]
local _render_text_position = {0, 0} --[[@as MapPosition.1]]
---@type ForceIdentification[]
local _render_target_force = {nil}
local _flying_anti_build_text_param = {
	text = {"protected_teams.warning_not_your_team_build_zone"}, create_at_cursor=true,
	color = {1, 0, 0}, time_to_live = 210,
	speed = 0.1
}
local _render_anti_build_text_param = {
	text = {"protected_teams.warning_not_your_team_build_zone"},
	target = _render_text_position,
	surface = nil,
	forces = _render_target_force,
	scale = 1,
	time_to_live = 210,
	color = {200, 0, 0}
}
--#endregion


local function clamp(x, lower, upper)
	if upper < x then
		if lower > upper then
			return lower
		else
			return upper
		end
	else
		if lower > x then
			return lower
		else
			return x
		end
	end
	-- return max(lower, min(upper, x)
end

local __new_point = {0, 0} -- it's safe as long as we don't store it somewhere...
local function getNearestPosInPerimeter(l,t,w,h, p)
	local x = p.x
	local y = p.y
	local r, b = l+w, t+h

	x, y = clamp(x, l, r), clamp(y, t, b)

	local dl, dr, dt, db = abs(x-l), abs(x-r), abs(y-t), abs(y-b)
	local m = min(dl, dr, dt, db)

	if m == dt then
		__new_point[1] = x
		__new_point[2] = t
		return __new_point
	end
	if m == db then
		__new_point[1] = x
		__new_point[2] = b
		return __new_point
	end
	if m == dl then
		__new_point[1] = l
		__new_point[2] = y
		return __new_point
	end
	__new_point[1] = r
	__new_point[2] = y
	return __new_point
end


local function is_in_zone(position, zone)
	local p1  = zone[1]
	local p1X = p1[1]
	local p1Y = p1[2]
	local p2  = zone[2]
	local p2X = p2[1]
	local p2Y = p2[2]
	local tX  = position.x
	local tY  = position.y

	if (p1X > p2X) then
		if (p1Y > p2Y) then
			return (p1X > tX and p2X < tX and p1Y > tY and p2Y < tY);
		else
			return (p1X > tX and p2X < tX and p1Y < tY and p2Y > tY);
		end
	else
		if (p1Y > p2Y) then
			return (p1X < tX and p2X > tX and p1Y > tY and p2Y < tY);
		else
			return (p1X < tX and p2X > tX and p1Y < tY and p2Y > tY);
		end
	end
end

---@param player LuaPlayer
---@return boolean
function M.is_in_team(player)
	for _, team_data in pairs(_teams_data) do
		if team_data.force == player.force then
			return true
		end
	end

	return false
end

---@param player LuaPlayer
---@return boolean
function M.is_player_in_pirate_team(player)
	for _, team_data in pairs(_teams_data) do
		if team_data.force == player.force and team_data.is_pirates then
			return true
		end
	end

	return false
end

function M.teleport_pirate_on_random_position(player)
	local surface = game.get_surface(1)
	local pos = {x = 0, y = 0}
	for _=1, 10 do
		pos.x = math.random(-config.center_size * 32 + 16, config.center_size * 32 - 16)
		pos.y = math.random(-config.center_size * 32 + 16, config.center_size * 32 - 16)
		local enemy_units = surface.find_enemy_units(pos, 30, player.force)
		if #enemy_units <= 0 then
			if player_util.teleport_safely(player, surface, pos) then
				break
			end
		end
	end

	M.give_start_inventory(player)
end

function M.destroy_borders(team_data)
	local borders = team_data.safe_zone.borders
	for k, entity in pairs(borders) do
		borders[k] = nil
		if entity.valid then
			entity.destroy()
		end
	end
end

function M.give_start_inventory(player)
	if not _is_start_inventory_checked then
		data_util.remove_invalid_prototypes(game.item_prototypes, _start_inventory)
		_is_start_inventory_checked = true
	end

	local stack = {name = "", count = 0}
	for name, count in pairs(_start_inventory) do
		stack.name  = name
		stack.count = count
		player.insert(stack)
	end
end

function M.create_borders(team_data)
	M.destroy_borders(team_data)

	local safe_zone = team_data.safe_zone.safe_zone
	local left   = safe_zone[1][1]
	local top    = safe_zone[1][2]
	local right  = safe_zone[2][1]
	local bottom = safe_zone[2][2]

	local beam_type = 'electric-beam-no-sound'
	local surface = game.get_surface(1)
	local borders = team_data.safe_zone.borders
	borders[1] = surface.create_entity({
		name = beam_type, position = {right, top},
		source = {right, top}, target = {right, bottom + 0.5}
	}) -- intentional offset here to correct visual appearance
	borders[2] = surface.create_entity({
		name = beam_type, position = {right, bottom},
		source = {right, bottom}, target = {left, bottom + 0.5}
	})
	borders[3] = surface.create_entity({
		name = beam_type, position = {left, bottom},
		source = {left, bottom}, target = {left, top}
	})
	borders[4] = surface.create_entity({
		name = beam_type, position = {left, top - 0.5},
		source = {left, top - 0.5}, target = {right, top}
	})
end

function M.remove_safe_zone(force)
	for _, team_data in pairs(_teams_data) do
		if team_data.safe_zone and team_data.force == force then
			M.destroy_borders(team_data)

			for k, v in pairs(_active_safe_zones) do
				if v == team_data.safe_zone then
					table.remove(_active_safe_zones, k)
				end
			end

			team_data.safe_zone = nil
		end
	end
end

local _render_tick = -1
---@param entity LuaEntity
---@param player LuaPlayer?
local function destroy_entity(entity, player)
	if player and player.valid then
		if _render_tick ~= game.tick then
			player.create_local_flying_text(_flying_anti_build_text_param)
			_render_tick = game.tick
		end
		player.mine_entity(entity, true) -- forced mining
		return
	end

	-- Show warning text
	_render_target_force[1] = entity.force
	_render_anti_build_text_param.surface = entity.surface
	local ent_pos = entity.position
	_render_text_position[1] = ent_pos.x
	_render_text_position[2] = ent_pos.y
	rendering.draw_text(_render_anti_build_text_param)

	entity.destroy(DESTROY_PARAM)
end
M.destroy_entity = destroy_entity


---@param player LuaPlayer
function M.teleport_to_battle_zone(player)
	player.force = "player" -- should I change this?
	player.ticks_to_respawn = nil
	if player.controller_type == defines.controllers.editor then
		player.toggle_map_editor()
	end
	if not (player.character and player.character.valid) then
		player_util.create_new_character(player)
	end

	local battle_surface
	-- if global.is_round_start then
		battle_surface = global.mini_battle_zone_surface
	-- else
	-- 	battle_surface = game.get_surface(1)
	-- end

	player.teleport({0, 0}, battle_surface)

	local vehicle = battle_surface.create_entity({
		name = "tank",
		force = player.force,
		surface = battle_surface,
		position = {0, 0}
	})
	vehicle.set_driver(player)

	if not player_util.teleport_safely(
			player, battle_surface,
			{math.random(-230, 230), math.random(-230, 230)}
		)
	then
		vehicle.teleport({math.random(-230, 230), math.random(-230, 230)}, battle_surface)
	end

	if not _is_tank_inventory_checked then
		data_util.remove_invalid_prototypes(game.item_prototypes, _tank_inventory)
		_is_tank_inventory_checked = true
	end

	local stack = {name = "", count = 0}
	for name, count in pairs(_tank_inventory) do
		stack.name  = name
		stack.count = count
		vehicle.insert(stack)
	end

	if not _is_mini_battle_inventory_checked then
		data_util.remove_invalid_prototypes(game.item_prototypes, _mini_battle_inventory)
		_is_mini_battle_inventory_checked = true
	end

	for name, count in pairs(_mini_battle_inventory) do
		stack.name  = name
		stack.count = count
		player.insert(stack)
	end
end


--#region Function of events

---@param event on_robot_built_entity
function M.on_robot_built_entity(event)
	local entity = event.created_entity
	if not entity.valid then return end

	local force = entity.force
	local ent_pos = entity.position
	for _, zone_data in pairs(global._active_safe_zones) do
		if zone_data.force ~= force and
		   is_in_zone(ent_pos, zone_data.safe_zone)
		then
			destroy_entity(entity)
			break
		end
	end
end

---@param event EventData.on_player_joined_game
function M.on_player_joined_game(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end

	player.print("WARNING: this is a test version. Some features are missing, not balanced. There are various issues and game crashes.", {1, 1, 0})

	if not global.is_round_start then
		M.teleport_to_battle_zone(player)
		return
	end

	if not M.is_in_team(player) then
		M.teleport_to_battle_zone(player)
	end
end

---@param player LuaPlayer
function M.on_player_respawned(event)
	local player = game.get_player(event.player_index)
	if not (player and player.valid) then return end

	if not M.is_in_team(player) then
		M.teleport_to_battle_zone(player)
		return
	end

	if M.is_player_in_pirate_team(player) then
		M.teleport_pirate_on_random_position(player)
	end
end

---@param event EventData.on_built_entity
function M.on_built_entity(event)
	local entity = event.created_entity
	if not entity.valid then return end

	local force = entity.force
	for _, zone_data in pairs(global._active_safe_zones) do
		if zone_data.force ~= force and
		   is_in_zone(entity.position, zone_data.safe_zone)
		then
			destroy_entity(entity, game.get_player(event.player_index))
			return
		end
	end
end

---@param event EventData.on_entity_destroyed
function M.on_entity_destroyed(event)
	local id = event.registration_number
	for team_name, team_data in pairs(_teams_data) do
		if team_data.base_id == id then
			local force = team_data.force
			remote.call("EasyAPI", "remove_team", force.index, true)

			local active_teams = 0
			for _, team_data2 in pairs(_teams_data) do
				if #team_data2.force.connected_players > 0 and not team_data2.is_pirates then
					active_teams = active_teams + 1
				end
			end
			if active_teams <= 1 then
				local event_id
				for _, team_data2 in pairs(_teams_data) do
					if not team_data2.is_pirates then
						event_id = remote.call("EasyAPI", "get_event_name", "on_team_won")
						script.raise_event(event_id, {force = team_data2.force})
						break
					end
				end

				for team_name, team_data2 in pairs(_teams_data) do
					local force = team_data2.force
					remote.call("EasyAPI", "remove_team", force.index, true)
				end

				for _, player in pairs(game.players) do
					M.teleport_to_battle_zone(player)
				end

				event_id = remote.call("EasyAPI", "get_event_name", "on_round_end")
				script.raise_event(event_id, {source = "scenario"})
			end
			return
		end
	end
end

---@param event EventData.on_research_finished
function M.on_research_finished(event)
	local research = event.research
	if not research.valid then return end
	if table_size(_teams_data) == 0 then return end

	local source_force = research.force

	if not _is_disabled_recipes_checked then
		data_util.remove_invalid_prototypes(game.technology_prototypes, _disabled_recipes)
		_is_disabled_recipes_checked = true
	end

	local recipes = source_force.recipes
	for name in pairs(_disabled_recipes) do
		recipes[name].enabled = false
	end

	local is_tracked_team = false
	local is_all_tracked_teams_has_the_research = true
	local pirate_force
	for _, team_data in pairs(_teams_data) do
		if team_data.safe_zone then
			local team_force = team_data.force
			if #team_force.players > 0 then
				if team_force == source_force then
					is_tracked_team = true
					break
				elseif not team_force.technologies[research.name].researched then
					is_all_tracked_teams_has_the_research = false
					break
				end
			end
		else
			pirate_force = team_data.force
		end
	end

	if not is_tracked_team then return end
	if not is_all_tracked_teams_has_the_research then return end

	if not pirate_force then
		for _, team_data in pairs(_teams_data) do
			if not team_data.safe_zone then
				pirate_force = team_data.force
				break
			end
		end
	end

	pirate_force.technologies[research.name].researched = true
end

function M.set_config_data()
	local radius = config.center_size + 1 +
		math.max(config.top_size, config.left_size, config.right_size, config.down_size)
	global.radius = radius
	global.end_preparation_tick = game.tick + 100
end


---@param event EventData.on_game_created_from_scenario
function M.on_game_created_from_scenario(event)
	M.set_config_data()
	local setting_names = {
		"bt_allow_bandits", "bt_show_all_forces", "bt_allow_rename_teams",
		"bt_allow_join_player_force", "bt_allow_abandon_teams",
		"bt_allow_join_enemy_force",  "bt_allow_rename_teams",
		"bt_show_all_forces", "bt_auto_create_teams_gui_for_new_players"
	}
	for _, name in pairs(setting_names) do
		remote.call("BTeams", "change_setting", "global", name, false)
	end
	local setting_names = {
		"bt_teleport_in_void_when_player_abandon_team"
	}
	for _, name in pairs(setting_names) do
		remote.call("BTeams", "change_setting", "global", name, true)
	end

	---@diagnostic disable-next-line: missing-fields
	local mini_battle_zone = game.create_surface("mini_battle_zone", {
		width  = 1,
		height = 1,
	})
	global.mini_battle_zone_surface = mini_battle_zone
	surface_util.fill_box_with_tiles(mini_battle_zone, -250, 250, 500, "refined-concrete")

	local reserve_base_surface = game.get_surface("reserve_base_surface")

	local pos = {x = 0, y = 0}
	---@type LuaSurface.create_entity_param
	local entity_param = {
		type = "ammo-turret",
		name = "gun-turret",
		move_stuck_players = true,
		raise_built = false,
		position = pos,
		force = nil,
	}
	pos.x = -8
	pos.y = -8
	local turret = reserve_base_surface.create_entity(entity_param)
	turret.rotatable = false
	turret.operable  = false
	turret.minable   = false
	turret.insert({name = "uranium-rounds-magazine", count = 200})
	pos.x =  8
	pos.y = -8
	turret = reserve_base_surface.create_entity(entity_param)
	turret.rotatable = false
	turret.operable  = false
	turret.minable   = false
	turret.insert({name = "uranium-rounds-magazine", count = 200})
	pos.x = -8
	pos.y =  8
	turret = reserve_base_surface.create_entity(entity_param)
	turret.rotatable = false
	turret.operable  = false
	turret.minable   = false
	turret.insert({name = "uranium-rounds-magazine", count = 200})
	pos.x =  8
	pos.y =  8
	turret = reserve_base_surface.create_entity(entity_param)
	turret.rotatable = false
	turret.operable  = false
	turret.minable   = false
	turret.insert({name = "uranium-rounds-magazine", count = 200})

	surface_util.fill_box_with_resources_safely(
		reserve_base_surface, 28, 4, 8, "coal", 2000
	)
	surface_util.fill_box_with_resources_safely(
		reserve_base_surface, -28 - 8, 4, 8, "stone", 2000
	)
	surface_util.fill_box_with_resources_safely(
		reserve_base_surface, -4, -28, 8, "iron-ore", 2000
	)
	surface_util.fill_box_with_resources_safely(
		reserve_base_surface, -4, 28 + 8, 8, "copper-ore", 1000
	)
end

---@param event EventData.on_chunk_generated
function M.on_chunk_generated(event)
	local surface = event.surface
	if not (surface and surface.valid) then return end
	if surface.index ~= 1 then return end

	local chunk_x = event.position.x
	local chunk_y = event.position.y
	local center_size = config.center_size
	if center_size >  chunk_x and
	   center_size >  chunk_y and
	  -center_size <= chunk_x and
	  -center_size <= chunk_y
	then
		return
	end
	local size = config.top_size
	if size >  chunk_x and
	  -size <= chunk_x and
	  -center_size > chunk_y and
	 -(center_size + size * 2) <= chunk_y
	then
		return
	end
	size = config.down_size
	if size >  chunk_x and
	  -size <= chunk_x and
	   center_size <= chunk_y and
	  (center_size + size * 2) > chunk_y
	then
		return
	end
	size = config.right_size
	if size >  chunk_y and
	  -size <= chunk_y and
	   center_size <= chunk_x and
	  (center_size + size * 2) > chunk_x
	then
		return
	end
	size = config.left_size
	if size >  chunk_y and
	  -size <= chunk_y and
	  -center_size > chunk_x and
	 -(center_size + size * 2) <= chunk_x
	then
		return
	end

	surface_util.fill_chunk_with_tiles(
		surface, chunk_x, chunk_y, "out-of-map"
	) -- a bit buggy

	-- if math.max(math.abs(chunk_x), math.abs(chunk_x)) > global.radius then return end
	-- game.print(chunk_x .. ", " .. chunk_y)
end


function M.generate_surface()
	if global.is_round_start then return end

	if not global.chunk_y then
		global.chunk_x = -global.radius - 1
		global.chunk_y = -global.radius - 1
	end

	local surface = game.get_surface(1)
	local pos = {0, 0}
	while true do
		if global.chunk_y > global.radius then
			return
		else
			global.chunk_x = global.chunk_x + 1
			if global.chunk_x > global.radius then
				global.chunk_y = global.chunk_y + 1
				global.chunk_x = -global.radius - 1
			end
		end

		if not surface.is_chunk_generated(pos) then
			pos[1] = global.chunk_x * 32 + 15
			pos[2] = global.chunk_y * 32 + 15
			surface.request_to_generate_chunks(pos, 1)
			surface.force_generate_chunk_requests() -- good luck with making it work as you wish
			global.end_preparation_tick = global.end_preparation_tick + 10
			break
		end
	end
end

function M.check_active_safe_zones()
	local target_surface = game.get_surface(1)
	for _, player in pairs(game.connected_players) do
		if player.surface == target_surface then
			local target = player.vehicle or player
			local player_force = player.force
			for _, zone_data in pairs(global._active_safe_zones) do
				if zone_data.force ~= player_force and
				   is_in_zone(target.position, zone_data.safe_zone)
				then
					local zone = zone_data.safe_zone
					target.teleport(
						getNearestPosInPerimeter(
							zone[1][1],zone[1][2],
							zone.width,zone.height,
							target.position
						)
					)

					-- TODO: change speed for transport
					-- TODO: apply slowness
					break
				end
			end
		end
	end
end

function M.check_time_safe_zones()
	for _, team_data in pairs(_teams_data) do
		if team_data.safe_zone then
			local force = team_data.force
			if #force.players > 0 then
				team_data.active_safe_zone_ticks = team_data.active_safe_zone_ticks + 119
				if team_data.active_safe_zone_ticks > config.grace_period_ticks then
					M.remove_safe_zone(team_data.force)
				end
			end
		end
	end
end

function M.check_surface()
	if global.is_round_start then return end
	if game.tick < global.end_preparation_tick then return end

	global.is_round_start = true
	global.round_start_tick = game.tick

	if not _is_default_techs_checked then
		data_util.remove_invalid_prototypes(game.technology_prototypes, _default_techs)
		_is_default_techs_checked = true
	end

	if not _is_disabled_techs_checked then
		data_util.remove_invalid_prototypes(game.technology_prototypes, _disabled_techs)
		_is_disabled_techs_checked = true
	end

	local surface = game.get_surface(1)
	for team_name, team_data in pairs(config.teams) do
		local force = game.create_force(team_name)

		force.friendly_fire = team_data.friendly_fire or false
		force.set_spawn_position(team_data.spawn_point, surface)

		local techs = force.technologies
		for _, tech_name in pairs(_default_techs) do
			techs[tech_name].researched = true
		end
		for tech_name, _ in pairs(_disabled_techs) do
			techs[tech_name].enabled = false
		end

		local save_zone_data
		if team_data.safe_zone then
			save_zone_data = {
				safe_zone = team_data.safe_zone,
				force = force,
				borders = {nil,nil,nil,nil}
			}
			_active_safe_zones[#_active_safe_zones+1] = save_zone_data
		end
		_teams_data[team_name] = {
			force = force,
			safe_zone  = save_zone_data,
			is_pirates = (save_zone_data == nil),
			is_stuck   = (save_zone_data ~= nil) or nil,
			active_safe_zone_ticks = 0,
		}
		if save_zone_data then
			M.create_borders(_teams_data[team_name])
		end
	end

	for team_name, team_data in pairs(_teams_data) do
		local force = team_data.force
		remote.call("EasyAPI", "add_team", force, true)
		if team_data.safe_zone then
			---@type LuaSurface.create_entity_param
			local entity_param = {
				type = "rocket-silo",
				name = "rocket-silo",
				move_stuck_players = true,
				raise_built = false,
				position = nil,
				force = nil,
			}
			entity_param.position = force.get_spawn_position(surface)
			entity_param.force = force
			local base_entity = surface.create_entity(entity_param)
			base_entity.minable   = false
			base_entity.rotatable = false
			local base_pos = base_entity.position
			local id = script.register_on_entity_destroyed(base_entity)
			team_data.base_id = id

			remote.call("EasyAPI", "change_team_base", force, surface, base_pos)
		end
	end

	local entity_pos = {x = 0, y = 0}
	local entity_param = {
		type = "resource",
		name = "",
		position = entity_pos,
		surface = surface,
		snap_to_tile_center=true,
		amount = 4294967295
	}
	local center_pos = {x = 0, y = 0}
	local ores = {}
	for _, prototype in pairs(game.entity_prototypes) do
		if prototype.type == "resource" and prototype.mineable_properties.products[1].type ~= "fluid" then
			ores[#ores+1] = prototype.name
		end
	end
	local fluid_sources = {}
	for _, prototype in pairs(game.entity_prototypes) do
		if prototype.type == "resource" and prototype.mineable_properties.products[1].type == "fluid" then
			fluid_sources[#fluid_sources+1] = prototype.name
		end
	end

	local radius = config.center_resource_radius
	-- Creates ores in the center
	for x = -radius, radius do
		for y = -radius, radius do
			entity_pos.x = x
			entity_pos.y = y
			if radius >= coordinates_util.get_distance(center_pos, entity_pos) then
				entity_param.name = ores[math.random(1, #ores)]
				surface.create_entity(entity_param)
			end
		end
	end

	entity_param.amount = 20000
	-- Creates fluid resources arond created ores
	for x = -radius - 8, radius + 8, 14 do
		for y = -radius - 8, radius + 8, 14 do
			entity_pos.x = x
			entity_pos.y = y
			if radius + 6 < coordinates_util.get_distance(center_pos, entity_pos) then
				entity_param.name = fluid_sources[math.random(1, #fluid_sources)]
				surface.create_entity(entity_param)
			end
		end
	end

	script.raise_event(remote.call("EasyAPI", "get_event_name", "on_round_start"), {source = "scenario"})
end

function M.unstuck_players()
	-- if global.round_start_tick > game.tick + 2400 then return end

	local target_surface = game.get_surface(1)
	for team_name, team_data in pairs(_teams_data) do
		if #team_data.force.connected_players > 0 then
			if team_data.is_stuck then
				local pos = config.teams[team_name].spawn_point
				local stuck_entities = target_surface.find_entities_filtered{
					type     = "character",
					position = pos,
					radius   = 2,
				}
				for _, entity in pairs(stuck_entities) do
					player_util.teleport_safely(entity.player, target_surface, pos)
				end
				if #stuck_entities > 0 then
					surface_util.fill_box_with_tiles(
						target_surface,
						pos[1] - 6, pos[2] + 6,
						13, "refined-concrete"
					)

					team_data.is_stuck = false
				end
			-- elseif team_data.is_pirates then
				-- TODO: IMPROVE!!!
				-- for _, player in pairs(team_data.force.connected_players) do
				-- 	local surface = player.surface
				-- 	if surface.index == 1 then
				-- 		player_util.teleport_safely(player, surface, player.position)
				-- 	end
				-- end
			end
		end
	end
end

--#endregion


--#region Pre-game stage

function M.link_data()
	_teams_data = global._teams_data
	_active_safe_zones = global._active_safe_zones
end

local function update_global_data()
	global.round_start_tick = global.round_start_tick or 0
	global.is_round_start = global.is_round_start or false
	global._active_safe_zones = global._active_safe_zones or {}
	global._teams_data = global._teams_data or {}
	if game then
		global.end_preparation_tick = global.end_preparation_tick or game.tick + 400
	else
		global.end_preparation_tick = global.end_preparation_tick + 400
	end
	--

	M.link_data()

	local id = remote.call("EasyAPI", "get_event_name", "on_round_end")
	script.on_event(id, function(event)
		if event.source ~= "scenario" then return end

		M.set_config_data()

		for _, team_data in pairs(_teams_data) do
			game.merge_forces(team_data.force, game.forces.neutral)
		end

		local surface = game.get_surface(1)
		surface.clear(true)

		global.is_round_start = false
		global.end_preparation_tick = game.tick + 400
	end)

	id = remote.call("EasyAPI", "get_event_name", "on_player_joined_team")
	script.on_event(id, function(event)
		local player = game.get_player(event.player_index)
		if not (player and player.valid) then return end

		player_util.create_new_character(player)

		local surface = game.get_surface(1)

		if M.is_player_in_pirate_team(player) then
			M.teleport_pirate_on_random_position(player)
		else
			local pos = player.force.get_spawn_position(surface)
			if not player_util.teleport_safely(player, surface, pos) then
				player.teleport(pos, surface)
			end
		end

		M.give_start_inventory(player)
	end)

	id = remote.call("EasyAPI", "get_event_name", "on_pre_deleted_team")
	script.on_event(id, function(event)
		local force = event.force
		if not force.valid then return end
		if force.index <= 3 then return end

		M.remove_safe_zone(force)

		for k, team_data in pairs(_teams_data) do
			if team_data.force == force then
				_teams_data[k] = nil
			end
		end

		game.merge_forces(force, game.forces.neutral)
		for _, player in pairs(force.connected_players) do
			if player.character then
				player.character.die()
			end
		end

		for _, player in pairs(force.players) do
			player.character = nil
			player.force = "player"
			remote.call("EasyAPI", "set_tick_player_joining_team", player.index, nil)
			M.teleport_to_battle_zone(player)
			remote.call("BTeams", "show_teams_gui", player)
		end
	end)

	--for player_index, player in pairs(game.players) do
	--	-- delete UIs
	--end
end


M.on_init = update_global_data
M.on_configuration_changed = update_global_data
M.on_load = M.link_data
M.update_global_data_on_disabling = update_global_data -- for safe disabling of this mod

--#endregion


M.events = {
	[defines.events.on_game_created_from_scenario] = M.on_game_created_from_scenario,
	[defines.events.on_chunk_generated]    = M.on_chunk_generated,
	[defines.events.on_player_joined_game] = M.on_player_joined_game,
	[defines.events.on_player_respawned]   = M.on_player_respawned,
	[defines.events.on_robot_built_entity] = M.on_robot_built_entity,
	[defines.events.on_built_entity]       = M.on_built_entity,
	[defines.events.on_research_finished]  = M.on_research_finished,
	[defines.events.on_entity_destroyed]   = M.on_entity_destroyed,
}


M.on_nth_tick = {
	-- [3]   = M.generate_surface,
	[10]  = M.check_active_safe_zones,
	[119] = M.check_time_safe_zones,
	[120] = M.check_surface,
	[600] = M.unstuck_players, -- cursed
}


M.commands = {
	-- set_spawn = set_spawn_command, -- Delete this example
}


return M
