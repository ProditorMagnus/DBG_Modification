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
function wesnoth.wml_actions.query_location3(cfg)
   local helper = wesnoth.require "lua/helper.lua"
   local T = helper.set_wml_tag_metatable {}
   local location_set = wesnoth.require "lua/location_set.lua"
   -- local overlay_choosable = cfg.overlay_selectable or "terrain/alphamask.png~O(0.2)~CS(255,255,0)"
   local overlay_choosable = cfg.overlay_selectable or "misc/hover-hex.png"
   -- local overlay_chosen = cfg.overlay_selected or "terrain/alphamask.png~O(0.2)~CS(0,255,0)"
   local overlay_chosen = cfg.overlay_selected or "misc/blank-hex.png~BLIT(misc/hover-hex-enemy-bottom.png)~BLIT(misc/hover-hex-enemy-top.png)"
   local overlay_unselectable = cfg.overlay_unselectable or "terrain/alphamask.png~O(0.4)~CS(127,127,127)"
   local variable = cfg.variable or "location"
   local allow_fog = cfg.allow_fog or false
   local allow_shroud = cfg.allow_shroud or false
   local max_count = cfg.max_count or 1
   local min_count = cfg.min_count or 1
   local confirm_message = cfg.confirm_message
   local overlay_message = cfg.overlay_message or "Click on location to choose."
   local filter = helper.literal(helper.get_child(cfg, "filter_location")) or {}
   
   filter.include_borders = false -- prevent getting stuck when only way to get required amount of locations would be with borders, which are not selectable
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
   
   local res = wesnoth.synchronize_choice("location", function()
      
      
      local disabled_locations = location_set.create()
      if overlay_unselectable then
         for _, loc in ipairs(wesnoth.get_locations({{[1]="not",[2]=filter}})) do
            x = loc[1]
            y = loc[2]
            disabled_locations:insert(x, y)
            wesnoth.add_tile_overlay(x, y, { image = overlay_unselectable })
         end
      end
      
      wesnoth.wml_actions.disallow_end_turn()
      
      local old_callback = wesnoth.game_events.on_mouse_action
      local finished = false
      local adding = true
      
      local candidates = location_set.create()
      local chosen_locations = location_set.create()
      for _, loc in ipairs(allowed_locations) do
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
         wesnoth.print{text=overlay_message .. " Selected "..chosen_locations:size().."/ ("..min_count..".."..max_count..")",size=24}
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
      
      while not finished do
         while not finished do
                print_current_count()
                wesnoth.delay(10)
         end
         
         print_current_count()
         
         if confirm_message then
                local options = {"Finish", "Choose again", "Quit"}
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
   end)
   
   local normal_object = {}
   for i=1,#res do
      normal_object[i] = res[i][2]
   end
   wesnoth.wml_actions.allow_end_turn()
   helper.set_variable_array(variable, normal_object)
   return normal_object
end

wesnoth.random()
wesnoth.wml_actions.query_location3({})
wesnoth.wml_actions.query_location3({})
