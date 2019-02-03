--<<
-- Problems arise when there is queued query_location but the one who is supposed to select it leaves

-- Parameters
-- [filter_location] location filter - error if matches no location, if missing matches all locations
-- max_count - optional default 1, how many locations player may select, not allowed to be 0, not allowed to be less than min_count
-- min_count - optional default 1, how many locations player needs to select
-- allow_fog - optional default false
-- allow_shroud - optional default false. If you allow both shroud and fog here, you can include custom vision location filter
-- variable - WML variable for result - optional default location
-- confirm_message - optional, if used then there is dialog to finish selection, with min_count=0 cancel, reseting selection
-- overlay_selected, overlay_selectable, overlay_unselectable - custom overlay - optional, use "" to not display
-- overlay_message - optional printed while selecting
function wesnoth.wml_actions.query_location(cfg)
	local is_choosing_side = wesnoth.sides[wesnoth.current.side].is_local
	wesnoth.message("Im local: "..tostring(is_choosing_side))
	local _ = wesnoth.textdomain "wesnoth"
	local variable = cfg.variable or "location"
	local helper = wesnoth.require "lua/helper.lua"
	local T = helper.set_wml_tag_metatable {}
	local location_set = wesnoth.require "lua/location_set.lua"
	-- local overlay_choosable = cfg.overlay_selectable or "terrain/alphamask.png~O(0.2)~CS(255,255,0)"
	local overlay_choosable = cfg.overlay_selectable or "misc/hover-hex.png"
	-- local overlay_chosen = cfg.overlay_selected or "terrain/alphamask.png~O(0.2)~CS(0,255,0)"
	local overlay_chosen = cfg.overlay_selected or "misc/blank-hex.png~BLIT(misc/hover-hex-enemy-bottom.png)~BLIT(misc/hover-hex-enemy-top.png)"
	local overlay_unselectable = cfg.overlay_unselectable or "terrain/alphamask.png~O(0.4)~CS(127,127,127)"
	local allow_fog = cfg.allow_fog or false
	local allow_shroud = cfg.allow_shroud or false
	local max_count = cfg.max_count or 1
	local min_count = cfg.min_count or 1
	local confirm_message = cfg.confirm_message
	local overlay_message = cfg.overlay_message or _"Click on location to choose."
	local filter = helper.literal(helper.get_child(cfg, "filter_location")) or {}
	filter.include_borders = false -- prevent getting stuck when only way to get required amount of locations would be with borders, which are not selectable
	
	-- TODO testing shows that wesnoth.game_events.on_mouse_action is nil, find out what it is supposed to be
	local old_callback = wesnoth.game_events.on_mouse_action
	
	local res = wesnoth.synchronize_choice(_"selecting location", function()
		if not is_choosing_side then
			wesnoth.message("synchronize_choice function fired for nonlocal side")
			wesnoth.game_events.on_mouse_action = old_callback
			return {}
		end
		if not is_choosing_side then
			wesnoth.message("synchronize_choice function fired again despite return, for nonlocal side")
			wesnoth.game_events.on_mouse_action = old_callback
			return {}
		end
		
		if allow_fog and not allow_shroud then
			table.insert(filter, T.filter_vision{side=wesnoth.current.side,respect_fog=false})
		elseif not allow_fog and not allow_shroud then
			table.insert(filter, T.filter_vision{side=wesnoth.current.side})
		end
		
		local allowed_locations = wesnoth.get_locations(filter)
		if #allowed_locations < min_count then helper.wml_error("query_location matches less locations than min_count "..#allowed_locations.."<"..min_count) end
		if min_count > max_count then helper.wml_error("query_location min_count is higher than max_count "..min_count..">"..max_count) end
		if max_count == 0 then helper.wml_error("query_location called with max_count=0") end
		if #allowed_locations == 0 and min_count == 0 then return end
		
		local disabled_locations = location_set.create()
		if overlay_unselectable then
			for i, loc in ipairs(wesnoth.get_locations({{[1]="not",[2]=filter}})) do
				x = loc[1]
				y = loc[2]
				disabled_locations:insert(x, y)
				if is_choosing_side then
					wesnoth.add_tile_overlay(x, y, { image = overlay_unselectable })
				end
			end
		end
		
		wesnoth.wml_actions.disallow_end_turn()
	
		
		local finished = false
		local adding = true -- not used for now
		
		local candidates = location_set.create()
		local chosen_locations = location_set.create()
		for i, loc in ipairs(allowed_locations) do
			x = loc[1]
			y = loc[2]
			candidates:insert(x, y)
			wesnoth.add_tile_overlay(x, y, { image = overlay_choosable })
		end
		wesnoth.redraw{}
		
		function wesnoth.game_events.on_mouse_action(x,y)			
			if adding and candidates:get(x,y) then
				if chosen_locations:size() < max_count then
					chosen_locations:insert(x,y)
					candidates:remove(x,y)
					wesnoth.remove_tile_overlay(x, y, { image = overlay_choosable })
					wesnoth.add_tile_overlay(x, y, { image = overlay_chosen })
				end
			elseif adding and chosen_locations:get(x,y) then
				if chosen_locations:size() >= min_count then
					finished = true
				end
			elseif not adding and candidates:get(x,y) then
				finished = true
			elseif not adding and chosen_locations:get(x,y) then
				if chosen_locations:size() > min_count then
					candidates:insert(x,y)
					chosen_locations:remove(x,y)
					wesnoth.remove_tile_overlay(x, y, { image = overlay_chosen })
					wesnoth.add_tile_overlay(x, y, { image = overlay_choosable })
				else
					finished=true
				end
			elseif not candidates:get(x,y) and not chosen_locations:get(x,y) then
				if chosen_locations:size() >= min_count then
					finished = true
				end
			end
			
			if chosen_locations:size() == max_count then
				finished = true
			end
		end
		
		local function print_current_count()
			wesnoth.print{text=overlay_message .. _" Selected "..chosen_locations:size().."/ ("..min_count..".."..max_count..")",size=24}
			wesnoth.print{text="Im local: "..tostring(is_choosing_side), size=24}
		end
		
		local function clear_selection()
			chosen_locations:iter(function(x,y,data) 
				wesnoth.remove_tile_overlay(x, y, { image = overlay_chosen })
			end)
			chosen_locations:clear()
		end
		
		local function reset_selection()
			chosen_locations:iter(function(x,y,data) 
				wesnoth.remove_tile_overlay(x, y, { image = overlay_chosen })
				wesnoth.add_tile_overlay(x, y, { image = overlay_choosable })
				candidates:insert(x,y)
			end)
			chosen_locations:clear()
			finished = false
		end
		
		wesnoth.wml_actions.set_menu_item{
			id="Rav_ql",
			synced=false,
			description="ql",
			T.command{
				T.lua{
					code="wesnoth.message(\"Rav_ql\")"
				}
			}
		}

		while not finished do
			while not finished do
				print_current_count()
				wesnoth.delay(10)
				if not is_choosing_side then
					finished = true
					wesnoth.message("I am not choosing side!")
					wesnoth.game_events.on_mouse_action = old_callback
				end
				wesnoth.redraw{}
			end
			
			print_current_count()
			
			if confirm_message then
				local options = {_"Finish", _"Choose again", _"Quit"}
				if min_count ~= 0 then
					table.remove(options, 3)
				end
				local result = helper.get_user_choice({ speaker = "narrator", message = confirm_message }, options)
				if result == 1 then
				elseif result == 2 then
					reset_selection()
				elseif result == 3 then
					clear_selection()
				end
			end
			
			if not is_choosing_side then
				finished = true
				wesnoth.game_events.on_mouse_action = old_callback
			end
		end
		
		wesnoth.game_events.on_mouse_action = old_callback
		
		candidates:iter(function(x,y,data) 
			wesnoth.remove_tile_overlay(x, y, { image = overlay_choosable })
		end)
		chosen_locations:iter(function(x,y,data) 
			wesnoth.remove_tile_overlay(x, y, { image = overlay_chosen })
		end)
		
		disabled_locations:iter(function(x,y,data) 
			wesnoth.remove_tile_overlay(x, y, { image = overlay_unselectable })
		end)
		disabled_locations:clear()
		
		local wml_object = {}
		for i,v in ipairs(chosen_locations:to_pairs()) do
			wml_object[i] = {"value",{x=v[1],y=v[2]}}
		end
		wesnoth.redraw{}
		
		return wml_object
	end, function() 
		return helper.wml_error("query_location used with AI side")
	end)

	local normal_object = {}
	for i=1,#res do 
		normal_object[i] = res[i][2]
	end
	wesnoth.wml_actions.allow_end_turn()
	helper.set_variable_array(variable, normal_object)
	return normal_object
end

function ql()
	return wesnoth.wml_actions.query_location({T.filter_location{terrain="Cud"}})
end
function qi()
	return wesnoth.wml_actions.query_location({T.filter_location{terrain="Cud"}, overlay_selectable=""})
end
function qo()
	return wesnoth.wml_actions.query_location({T.filter_location{T["not"]{terrain="Cud"}}})
end

function qk()
	return wesnoth.wml_actions.query_location({T.filter_location{terrain="Cud"}, confirm_message="qk"})
end

function qj()
	return wesnoth.wml_actions.query_location({T.filter_location{terrain="Cud"}, max_count=3})
end

function qh()
	return wesnoth.wml_actions.query_location({T.filter_location{terrain="Cud"}, max_count=3,allow_fog=true})
end

function qh()
	return wesnoth.wml_actions.query_location({T.filter_location{terrain="Cud"}, max_count=3,allow_fog=true})
end

-->>