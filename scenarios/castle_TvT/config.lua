local territory_in_chunks = 30

local config = {
	force_team_color   = true, -- Perhaps will be deleted beacause of EasyAPI
	is_biters_disabled = true,
	center_size = territory_in_chunks, -- territory in chunks in all directions
	top_size    = territory_in_chunks, -- territory in chunks in all directions
	left_size   = territory_in_chunks, -- territory in chunks in all directions
	right_size  = territory_in_chunks, -- territory in chunks in all directions
	down_size   = territory_in_chunks, -- territory in chunks in all directions
	grace_period_ticks = 60 * 60 * 40, -- 40 mins
	center_resource_radius = 30,
    teams = {},
}


---@param team_name string
---@param color rgb
---@param chat_color rgb
local function create_team_data(team_name, color, chat_color)
    local team_data = {
		chat_color = chat_color,
		color = color,
		minimum_players = 0,
    }

    config.teams[team_name] = team_data
end


local team_name = "A"
create_team_data(team_name)
local team_data = config.teams[team_name]
team_data.is_top      = true
team_data.spawn_point = {0, (-config.center_size - config.top_size) * 32}
team_data.safe_zone   = {
	{-config.top_size * 32 - 8, -config.center_size * 32 - config.top_size * 2 * 32 - 8}, -- left_top
	{ config.top_size * 32 + 8, -config.center_size * 32 + 8}, -- right_bottom
	width  = config.left_size * 2 * 32 + 16,
	height = config.left_size * 2 * 32 + 16,
}

team_name = "B"
create_team_data(team_name)
team_data = config.teams[team_name]
team_data.is_right    = true
team_data.spawn_point = {(config.center_size + config.right_size) * 32, 0}
team_data.safe_zone   = {
	{config.center_size * 32 - 8, -config.center_size * 32 - 8}, -- left_top
	{config.center_size * 32 + config.down_size * 2 * 32 + 8, config.center_size * 32 + 8}, -- right_bottom
	width  = config.left_size * 2 * 32 + 16,
	height = config.left_size * 2 * 32 + 16,
}

team_name = "C"
create_team_data(team_name)
team_data = config.teams[team_name]
team_data.is_down     = true
team_data.spawn_point = {0, (config.center_size + config.down_size) * 32}
team_data.safe_zone   = {
	{-config.down_size * 32 - 8, config.center_size * 32 - 8}, -- left_top
	{ config.down_size * 32 + 8, config.center_size * 32 + config.down_size * 2 * 32 + 8}, -- right_bottom
	width  = config.left_size * 2 * 32 + 16,
	height = config.left_size * 2 * 32 + 16,
}

team_name = "D"
create_team_data(team_name)
team_data = config.teams[team_name]
team_data.is_left     = true
team_data.spawn_point = {(-config.center_size - config.left_size) * 32, 0}
team_data.safe_zone   = {
	{-config.center_size * 32 - config.left_size * 2 * 32 - 8, -config.center_size * 32 - 8}, -- left_top
	{-config.center_size * 32 + 8, config.center_size * 32 + 8}, -- right_bottom
	width  = config.left_size * 2 * 32 + 16,
	height = config.left_size * 2 * 32 + 16,
}

team_name = "Pirates"
create_team_data(team_name)
team_data = config.teams[team_name]
team_data.is_center   = true
team_data.spawn_point = {22, -22}


return config
