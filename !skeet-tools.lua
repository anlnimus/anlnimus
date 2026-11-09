-- Shared scope-overlay ownership.
local scope_overlay_ref = ui.reference("VISUALS", "Effects", "Remove scope overlay")
local scope_overlay_requests = {}
local saved_scope_overlay = nil
local function request_scope_overlay(owner, active)
    scope_overlay_requests[owner] = active or nil
    if next(scope_overlay_requests) ~= nil then
        if saved_scope_overlay == nil then
            saved_scope_overlay = ui.get(scope_overlay_ref)
        end
        ui.set(scope_overlay_ref, true)
    elseif saved_scope_overlay ~= nil then
        ui.set(scope_overlay_ref, saved_scope_overlay)
        saved_scope_overlay = nil
    end
end
client.set_event_callback("shutdown", function()
    if saved_scope_overlay ~= nil then ui.set(scope_overlay_ref, saved_scope_overlay) end
end)

-- skeet-tools
-- GameSense / Skeet, legacy CS:GO.
-- Custom controls: LUA > B (model and skybox changers: LUA > A,
-- arms changer: SKINS > Model Options).
-- Disable the standalone versions (incl. killsay, model changer, skybox
-- changer, arms changer, molniya hit effect) before loading this combined file.
-- Thirdperson checkbox enables the distance override, not the built-in camera.

ui.new_label("LUA", "B", "----- skeet-tools -----")

-- Sniper camera and scope overlay.
do
local enabled = ui.new_checkbox(
    "LUA", "B", "Sniper no zoom"
)

local fov = ui.new_slider(
    "LUA", "B", "Scoped camera FOV",
    60, 140, 90, true, "°"
)

local sniper_weapons = {
    CWeaponAWP = true,
    CWeaponSSG08 = true,
    CWeaponSCAR20 = true,
    CWeaponG3SG1 = true
}

client.set_event_callback("override_view", function(view)
    if not ui.get(enabled) then
        return
    end

    local player = entity.get_local_player()
    if not player or not entity.is_alive(player) then
        return
    end

    local weapon = entity.get_player_weapon(player)
    if not weapon then
        return
    end

    local classname = entity.get_classname(weapon)
    if not sniper_weapons[classname] then
        return
    end

    if entity.get_prop(player, "m_bIsScoped") ~= 1 then
        return
    end

    view.fov = ui.get(fov)
end)

local function update_scope_overlay()
    request_scope_overlay("no_zoom", ui.get(enabled))
end
ui.set_callback(enabled, update_scope_overlay)
update_scope_overlay()

end

-- Optional thirdperson distance override.
do
local enabled = ui.new_checkbox("LUA", "B", "Thirdperson distance")
local distance = ui.new_slider("LUA", "B", "Thirdperson distance value", 30, 200, 150)
local previous_distance = nil

local function update_distance()
    local active = ui.get(enabled)
    ui.set_visible(distance, active)
    if active then
        if previous_distance == nil then
            previous_distance = cvar.cam_idealdist:get_float()
        end
        cvar.cam_idealdist:set_float(ui.get(distance))
    elseif previous_distance ~= nil then
        cvar.cam_idealdist:set_float(previous_distance)
        previous_distance = nil
    end
end

ui.set_callback(enabled, update_distance)
ui.set_callback(distance, update_distance)
client.set_event_callback("paint", function()
    if ui.get(enabled) then
        cvar.cam_idealdist:set_float(ui.get(distance))
    end
end)
client.set_event_callback("shutdown", function()
    if previous_distance ~= nil then
        cvar.cam_idealdist:set_float(previous_distance)
    end
end)
update_distance()

end

-- Isolate Tesla initialization so an unsupported signature does not
-- prevent the camera tools from loading. Requires permission for FFI.
local function setup_tesla()
local ffi = require("ffi")

pcall(ffi.cdef, [[
    typedef struct {
        float x,y,z;
    } skeet_tools_vec3_t;

    struct skeet_tools_tesla_info_t {
        skeet_tools_vec3_t  m_pos;
        skeet_tools_vec3_t  m_ang;
        int m_entindex;
        const char *m_spritename;
        float m_flbeamwidth;
        int m_nbeams;
        skeet_tools_vec3_t m_color;
        float m_fltimevis;
        float m_flradius;
    };

    typedef void(__thiscall* skeet_tools_tesla_fn)(struct skeet_tools_tesla_info_t&);
]])

local match = client.find_signature("client_panorama.dll", "\x55\x8B\xEC\x81\xEC\xCC\xCC\xCC\xCC\x56\x57\x8B\xF9\x8B\x47\x18")
if match == nil then
    error("Tesla signature not found; this game build is unsupported")
end
local fs_tesla = ffi.cast("skeet_tools_tesla_fn", match)

local hitbox_pos = entity.hitbox_position
local uidtoentindex = client.userid_to_entindex
local get_local_player = entity.get_local_player


local tesla = ui.new_checkbox("LUA", "B", "Tesla on hit")
local color = ui.new_color_picker("LUA", "B", "color", 255,255,255,255)
local beam_width = ui.new_slider("LUA", "B", "Tesla width", 0, 30, 10)
local beam_radius = ui.new_slider("LUA", "B", "Tesla radius", 0, 1000, 500)
local beams = ui.new_slider("LUA", "B", "Beams", 0, 100, 12)

client.set_event_callback("player_hurt", function(event)
    if ui.get(tesla) then 
        local me = get_local_player()
        local attacker = uidtoentindex(event.attacker)
        if me ~= nil and attacker == me then 
            local hurt = uidtoentindex(event.userid)
            if not hurt then return end
            local hx, hy, hz = hitbox_pos(hurt, 6)
            if hx == nil or hy == nil or hz == nil then return end
            local r,g,b,a = ui.get(color)
            local x = client.random_float(-1000, 1000)
            local y = client.random_float(-1000, 1000)
            local z = client.random_float(-1000, 1000)

            local tesla_info = ffi.new("struct skeet_tools_tesla_info_t")
            tesla_info.m_flbeamwidth = ui.get(beam_width)
            tesla_info.m_flradius = ui.get(beam_radius)
            tesla_info.m_entindex = attacker
            tesla_info.m_color = {r/255, g/255, b/255}
            tesla_info.m_pos = { hx, hy, hz }
            tesla_info.m_ang = {x,y,z}
            tesla_info.m_fltimevis = 0.75
            tesla_info.m_nbeams = ui.get(beams)
            tesla_info.m_spritename = "sprites/physbeam.vmt"
            fs_tesla(tesla_info)
        end
    end
end) 
end

local tesla_ok, tesla_error = pcall(setup_tesla)
if not tesla_ok then
    client.log("[skeet-tools] Tesla unavailable: ", tostring(tesla_error))
end

-- Music kit changer.
do
local kits_by_id = {
	"Default",
	nil,
	"Crimson Assault",
	"Sharpened",
	"Insurgency",
	"A*D*8",
	"High Noon",
	"Death's Head Demolition",
	"Desert Fire",
	"LNOE",
	"Metal",
	"All I Want for Christmas",
	"IsoRhythm",
	"For No Mankind",
	"Hotline Miami",
	"Total Domination",
	"The Talos Principle",
	"Battlepack",
	"MOLOTOV",
	"Uber Blasto Phone",
	"Hazardous Environments",
	"Headshot",
	"The 8-Bit Kit",
	"I Am",
	"Diamonds",
	"Invasion!",
	"Lion's Mouth",
	"Sponge Fingerz",
	"Disgusting",
	"Java Havana Funkaloo",
	"Moments CSGO",
	"Aggressive",
	"The Good Youth",
	"FREE",
	"Life's Not Out To Get You",
	"Backbone",
	"GLA",
	"III-Arena",
	"EZ4ENCE",
	"The Master Chief Collection",
	"Scar",
	"Anti Citizen",
	"Bachram",
	"Gunman Taco Truck",
	"Eye of the Dragon",
	"M.U.D.D. FORCE",
	"Neo Noir",
	"Bodacious",
	"Drifter",
	"All for Dust",
	"Hades Music Kit",
	"The Lowlife Pack",
	"CHAIN$AW.LXADXUT.",
	"Mocha Petal",
	"~Yellow Magic~",
	"Vici",
	"Astro Bellum",
	"Work Hard, Play Hard",
	"KOLIBRI",
	"u mad!",
	"Flashbang Dance",
	"Heading for the Source",
	"Void",
	"Shooters",
	"dashstar*",
	"Gothic Luxury",
	"Lock Me Up",
	"花脸 Hua Lian (Painted Face)",
	"ULTIMATE"
}


-- The original table has an unused ID at index 2. Build a dense UI list
-- and retain the original music IDs explicitly.
local labels, kit_ids = {}, {}
local max_id = 0
for id in pairs(kits_by_id) do
    if id > max_id then max_id = id end
end
for id = 1, max_id do
    if kits_by_id[id] ~= nil then
        labels[#labels + 1] = kits_by_id[id]
        kit_ids[#kit_ids + 1] = id
    end
end

local enabled = ui.new_checkbox("LUA", "B", "Music kit changer")
local selection = ui.new_listbox("LUA", "B", "Music kit", labels)
local saved_resource, saved_player, saved_id

local function restore_music()
    local resource = entity.get_player_resource()
    local player = entity.get_local_player()
    if saved_id ~= nil and resource == saved_resource and player == saved_player then
        entity.set_prop(resource, "m_nMusicID", saved_id, player)
    end
    saved_resource, saved_player, saved_id = nil, nil, nil
end

local function apply_music()
    if not ui.get(enabled) then return end
    local player = entity.get_local_player()
    local resource = entity.get_player_resource()
    if not player or not resource then return end
    local current = entity.get_prop(resource, "m_nMusicID", player)
    if current == nil then return end
    if saved_id == nil or resource ~= saved_resource or player ~= saved_player then
        saved_resource, saved_player, saved_id = resource, player, current
    end
    local selected_id = kit_ids[ui.get(selection) + 1]
    if selected_id ~= nil and current ~= selected_id then
        entity.set_prop(resource, "m_nMusicID", selected_id, player)
    end
end

local function update_music()
    ui.set_visible(selection, ui.get(enabled))
    if ui.get(enabled) then apply_music() else restore_music() end
end
ui.set_callback(enabled, update_music)
ui.set_callback(selection, apply_music)
client.set_event_callback("round_start", apply_music)
client.set_event_callback("net_update_end", apply_music)
client.set_event_callback("level_init", function()
    saved_resource, saved_player, saved_id = nil, nil, nil
end)
client.set_event_callback("shutdown", restore_music)
update_music()
end

-- Aspect ratio override, retaining the original slider's 0..199 mapping.
-- Recalculate from the current resolution without recreating menu controls.
do
local enabled = ui.new_checkbox("LUA", "B", "Force aspect ratio")
local amount = ui.new_slider("LUA", "B", "Aspect ratio amount", 0, 199, 100, true, "%")
local saved_aspect = nil
local last_width, last_height, last_amount

local function restore_aspect()
    if saved_aspect ~= nil then
        cvar.r_aspectratio:set_float(saved_aspect)
        saved_aspect = nil
    end
    last_width, last_height, last_amount = nil, nil, nil
end

local function apply_aspect()
    if not ui.get(enabled) then return end
    local width, height = client.screen_size()
    if not width or not height or width <= 0 or height <= 0 then return end
    local value = ui.get(amount)
    if width == last_width and height == last_height and value == last_amount then return end
    if saved_aspect == nil then
        saved_aspect = cvar.r_aspectratio:get_float()
    end
    local multiplier = 2 - value * 0.01
    local ratio = value == 100 and 0 or width * multiplier / height
    cvar.r_aspectratio:set_float(ratio)
    last_width, last_height, last_amount = width, height, value
end

local function update_aspect()
    ui.set_visible(amount, ui.get(enabled))
    if ui.get(enabled) then apply_aspect() else restore_aspect() end
end
ui.set_callback(enabled, update_aspect)
ui.set_callback(amount, apply_aspect)
client.set_event_callback("paint", apply_aspect)
client.set_event_callback("level_init", function()
    last_width, last_height, last_amount = nil, nil, nil
end)
client.set_event_callback("shutdown", restore_aspect)
update_aspect()
end

-- Integrated autobuy.
do
--autobuy v2
local primary_weapons = {
    "-", 
    "AWP", 
    "SCAR20/G3SG1", 
    "Scout", 
    "M4/AK47", 
    "Famas/Galil", 
    "Aug/SG553", 
    "M249",
    "Negev", 
    "Mag7/SawedOff", 
    "Nova", 
    "XM1014", 
    "MP9/Mac10", 
    "UMP45", 
    "PPBizon", 
    "MP7"
}

local secondary_weapons = {
    "-", 
    "CZ75/Tec9/FiveSeven", 
    "P250", 
    "Deagle/Revolver", 
    "Dualies"
}

local grenades = {
    "HE Grenade", 
    "Molotov", 
    "Smoke", 
    "Flash", 
    "Flash (2)", 
    "Decoy"
}

local utilities = {
    "Armor", 
    "Helmet", 
    "Zeus", 
    "Defuser"
}

local prices = {
	["AWP"] = 4750,
	["SCAR20/G3SG1"] = 5000,
	["Scout"] = 1700,
	["M4/AK47"] = 3100,
	["Famas/Galil"] = 2250,
	["Aug/SG553"] = 3100,
    ["M249"] = 5200,
    ["Negev"] = 1700,
	["Mag7/SawedOff"] = 1300,
	["Nova"] = 1050,
	["XM1014"] = 2000,
	["MP9/Mac10"] = 1250,
	["UMP45"] = 1200,
	["PPBizon"] = 1400,
	["MP7"] = 1500,
	["CZ75/Tec9/FiveSeven"] = 500,
	["P250"] = 300,
	["Deagle/Revolver"] = 700,
	["Dualies"] = 400,
	["HE Grenade"] = 300,
	["Molotov"] = 600,
	["Smoke"] = 300,
	["Flash"] = 200,
    ["Flash (2)"] = 200,
	["Decoy"] = 50,
	["Armor"] = 650,
	["Helmet"] = 1000,
	["Zeus"] = 200,
	["Defuser"] = 400
}

local commands = {
	["AWP"] = "buy awp",
	["SCAR20/G3SG1"] = "buy scar20",
	["Scout"] = "buy ssg08",
	["M4/AK47"] = "buy m4a1",
	["Famas/Galil"] = "buy famas",
	["Aug/SG553"] = "buy aug",
    ["M249"] = "buy m249",
    ["Negev"] = "buy negev",
	["Mag7/SawedOff"] = "buy mag7",
	["Nova"] = "buy nova",
	["XM1014"] = "buy xm1014",
	["MP9/Mac10"] = "buy mp9",
	["UMP45"] = "buy ump45",
	["PPBizon"] = "buy bizon",
	["MP7"] = "buy mp7",
	["CZ75/Tec9/FiveSeven"] = "buy tec9",
	["P250"] = "buy p250",
	["Deagle/Revolver"] = "buy deagle",
	["Dualies"] = "buy elite",
	["HE Grenade"] = "buy hegrenade",
	["Molotov"] = "buy molotov",
	["Smoke"] = "buy smokegrenade",
	["Flash"] = "buy flashbang",
    ["Flash (2)"] = "buy flashbang",
	["Decoy"] = "buy decoy",
	["Armor"] = "buy vest",
	["Helmet"] = "buy vesthelm",
	["Zeus"] = "buy taser 34",
	["Defuser"] = "buy defuser"
}

--new menu
local ui_enabled = ui.new_checkbox("LUA", "B", "Autobuy")
local ui_hide = ui.new_checkbox("LUA", "B", "Hide autobuy")
local ui_primary = ui.new_combobox("LUA", "B", "Primary", primary_weapons)
local ui_secondary = ui.new_combobox("LUA", "B", "Secondary", secondary_weapons)
local ui_grenades = ui.new_multiselect("LUA", "B", "Grenades", grenades)
local ui_utilities = ui.new_multiselect("LUA", "B", "Utilities", utilities)
local ui_cost_based = ui.new_checkbox("LUA", "B", "Cost based")
local ui_threshold = ui.new_slider("LUA", "B", "Balance override", 0, 16000, 0, true, "$", 1, {[0] = "Off"})
local ui_primary_2 = ui.new_combobox("LUA", "B", "Backup primary", primary_weapons)
local ui_secondary_2 = ui.new_combobox("LUA", "B", "Backup secondary", secondary_weapons)
local ui_grenades_2 = ui.new_multiselect("LUA", "B", "Backup grenades", grenades)
local ui_utilities_2 = ui.new_multiselect("LUA", "B", "Backup utilities", utilities)

--visibility
local function handle_vis()
    local state = ui.get(ui_enabled)
    local state2 = (not ui.get(ui_hide))
    local state3 = ui.get(ui_cost_based)

    ui.set_visible(ui_hide, state)

    if state and state2 then
        ui.set_visible(ui_primary, state)
        ui.set_visible(ui_secondary, state)
        ui.set_visible(ui_grenades, state)
        ui.set_visible(ui_utilities, state)
        ui.set_visible(ui_cost_based, state)
        ui.set_visible(ui_threshold, state3)
        ui.set_visible(ui_primary_2, state3)
        ui.set_visible(ui_secondary_2, state3)
        ui.set_visible(ui_grenades_2, state3)
        ui.set_visible(ui_utilities_2, state3)
    elseif not state2 then
        ui.set_visible(ui_primary, state2)
        ui.set_visible(ui_secondary, state2)
        ui.set_visible(ui_grenades, state2)
        ui.set_visible(ui_utilities, state2)
        ui.set_visible(ui_cost_based, state2)
        ui.set_visible(ui_threshold, state2)
        ui.set_visible(ui_primary_2, state2)
        ui.set_visible(ui_secondary_2, state2)
        ui.set_visible(ui_grenades_2, state2)
        ui.set_visible(ui_utilities_2, state2)
    else
        ui.set_visible(ui_primary, state)
        ui.set_visible(ui_secondary, state)
        ui.set_visible(ui_grenades, state)
        ui.set_visible(ui_utilities, state)
        ui.set_visible(ui_cost_based, state)
        ui.set_visible(ui_threshold, state)
        ui.set_visible(ui_primary_2, state)
        ui.set_visible(ui_secondary_2, state)
        ui.set_visible(ui_grenades_2, state)
        ui.set_visible(ui_utilities_2, state)
    end
end
ui.set_callback(ui_enabled, handle_vis)
ui.set_callback(ui_hide, handle_vis)
ui.set_callback(ui_cost_based, handle_vis)
handle_vis()

local function get_weapon_prices()
    local total_price = 0
    --utilities
	local utility_purchase = ui.get(ui_utilities)
	for i = 1, #utility_purchase do
        local n = utility_purchase[i]
        
	    for k, v in pairs(prices) do
		    if k == n then
			    total_price = total_price + v
		    end
	    end
    end

    --secondary
    for k, v in pairs(prices) do
        if k == ui.get(ui_secondary) then
            total_price = total_price + v
        end
    end

    --primary
    for k, v in pairs(prices) do
        if k == ui.get(ui_primary) then
            total_price = total_price + v
        end
    end
    
    --grenades
    local grenade_purchase = ui.get(ui_grenades)
    for i = 1, #grenade_purchase do
        local n = grenade_purchase[i]
        
	    for k, v in pairs(prices) do
		    if k == n then
			    total_price = total_price + v
		    end
	    end
    end
    return total_price
end

-- split into two funcs because otherwise the storing gets fked up
local logged_grenades = {}
local logged_grenades_2 = {}

local function grenade_limit_callback()
	local total_nades = ui.get(ui_grenades)

	if #total_nades > 4 then
		ui.set(ui_grenades, logged_grenades)
		return
	end

	logged_grenades = total_nades
end

local function grenade_limit_callback_2()
	local total_nades = ui.get(ui_grenades_2)

	if #total_nades > 4 then
		ui.set(ui_grenades_2, logged_grenades_2)
		return
	end

	logged_grenades_2 = total_nades
end

ui.set_callback(ui_grenades, grenade_limit_callback)
ui.set_callback(ui_grenades_2, grenade_limit_callback_2)

client.set_event_callback("round_prestart", function(e)
    if not ui.get(ui_enabled) then return end
    local player = entity.get_local_player()
    if not player then return end
    local ui_threshold_value = ui.get(ui_threshold)

    local price_threshold = 0

    if ui.get(ui_cost_based) and (ui_threshold_value == 0) then
        price_threshold = get_weapon_prices()
    elseif ui.get(ui_cost_based) and (ui_threshold_value ~= 0) then
        price_threshold = ui.get(ui_threshold)
    end

    local money = entity.get_prop(player, "m_iAccount")
    if money == nil then return end

    --if money is less than threshold
    if ui.get(ui_cost_based) and money < price_threshold then
        --secondary
        for k, v in pairs(commands) do
            if k == ui.get(ui_secondary_2) then
                client.exec(v)
            end
        end

        --utilities
		local utility_purchase = ui.get(ui_utilities_2)

		for i = 1, #utility_purchase do
            local n = utility_purchase[i]
            
		    for k, v in pairs(commands) do
			    if k == n then
				    client.exec(v)
			    end
		    end
        end

        --primary
        for k, v in pairs(commands) do
            if k == ui.get(ui_primary_2) then
                client.exec(v)
            end
        end

        --grenades
        local grenade_purchase = ui.get(ui_grenades_2)

        for i = 1, #grenade_purchase do
            local n = grenade_purchase[i]
            
		    for k, v in pairs(commands) do
			    if k == n then
				    client.exec(v)
			    end
		    end
        end

    --money is greater than threshold
    else 
        --utilities
		local utility_purchase = ui.get(ui_utilities)

		for i = 1, #utility_purchase do
            local n = utility_purchase[i]
            
		    for k, v in pairs(commands) do
			    if k == n then
				    client.exec(v)
			    end
		    end
        end

        --secondary
        for k, v in pairs(commands) do
            if k == ui.get(ui_secondary) then
                client.exec(v)
            end
        end

        --primary
        for k, v in pairs(commands) do
            if k == ui.get(ui_primary) then
                client.exec(v)
            end
        end

        --grenades
        local grenade_purchase = ui.get(ui_grenades)

        for i = 1, #grenade_purchase do
            local n = grenade_purchase[i]
            
		    for k, v in pairs(commands) do
			    if k == n then
				    client.exec(v)
			    end
		    end
        end
    end
end)
end

-- Integrated clantag.
do
local set_clantag = client.set_clan_tag
local separator = ui.new_label("LUA", "B", "---Clantag---")
local ref_clantag_group = ui.new_checkbox("LUA", "B", "Enable Clantag Changer")
local ref_clantag = ui.new_textbox("LUA", "B", "Enter Clantag")
local ref_animation = ui.new_combobox("LUA", "B", "Animation", { "Static", "Typing", "Blink", "Typing v2", "Custom" })
local ref_interval = ui.new_slider("LUA", "B", "Tag Change Interval", 100, 2000, 500, true, "ms")
local ref_static_on_end = ui.new_checkbox("LUA", "B", "Set static clantag on round end")

local custom_clantag = {"penis", "penis <3"}

local function typing_animation(text)
    local frames = {}
    for i = 1, #text do
        table.insert(frames, text:sub(1, i))
    end
    return frames
end

local function typing_v2_animation(text)
    local frames = {}
    for i = 1, #text do
        table.insert(frames, text:sub(1, #text - i + 1))
    end
    table.insert(frames, "")
    for i = 1, #text do
        table.insert(frames, text:sub(1, i))
    end
    return frames
end

local function get_animation_frames(clantag, anim_type)
    if anim_type == "Static" then
        return { clantag }
    elseif anim_type == "Typing" then
        return typing_animation(clantag)
    elseif anim_type == "Blink" then
        return { clantag, "" }
    elseif anim_type == "Typing v2" then
        return typing_v2_animation(clantag)
    elseif anim_type == "Custom" then
        return custom_clantag
    end
end

local tag_list = { "" }
local index = 1
local last_update_time = 0
local round_ended = false
local tag_owned = false

client.set_event_callback("paint", function()
    if not ui.get(ref_clantag_group) then return end
    if round_ended and ui.get(ref_static_on_end) then return end

    local clantag = ui.get(ref_clantag)
    local anim_type = ui.get(ref_animation)
    local interval = ui.get(ref_interval) / 1000

    if clantag == nil or clantag == "" then return end

    if clantag:match("[^%w%s%p]") then
        return
    end

    if anim_type == "Custom" then
        tag_list = custom_clantag
    else
        tag_list = get_animation_frames(clantag, anim_type)
    end

    if globals.realtime() - last_update_time >= interval then
        set_clantag(tag_list[index] or "")
        tag_owned = true
        index = index % #tag_list + 1
        last_update_time = globals.realtime()
    end
end)
local function update_clantag_controls()
    local active = ui.get(ref_clantag_group)
    for _, control in ipairs({ref_clantag, ref_animation, ref_interval, ref_static_on_end}) do
        ui.set_visible(control, active)
    end
    index, last_update_time = 1, 0
    if not active and tag_owned then
        set_clantag("")
        tag_owned = false
    end
end
ui.set_callback(ref_clantag_group, update_clantag_controls)
ui.set_callback(ref_clantag, function() index, last_update_time = 1, 0 end)
ui.set_callback(ref_animation, function() index, last_update_time = 1, 0 end)
client.set_event_callback("round_end", function()
    round_ended = true
    if ui.get(ref_clantag_group) and ui.get(ref_static_on_end) then
        set_clantag(ui.get(ref_clantag) or "")
        tag_owned = true
    end
end)
client.set_event_callback("round_start", function() round_ended = false end)
client.set_event_callback("level_init", function()
    round_ended, index, last_update_time = false, 1, 0
end)
client.set_event_callback("shutdown", function()
    if tag_owned then set_clantag("") end
end)
update_clantag_controls()

end

-- Integrated custom scope.
do
-- local variables for API functions. any changes to the line below will be lost on re-generation
local client_screen_size, entity_get_local_player, entity_get_player_weapon, entity_get_prop, entity_is_alive, globals_frametime, renderer_gradient, ui_get, ui_new_checkbox, ui_new_color_picker, ui_new_slider, ui_reference, ui_set, ui_set_callback, ui_set_visible = client.screen_size, entity.get_local_player, entity.get_player_weapon, entity.get_prop, entity.is_alive, globals.frametime, renderer.gradient, ui.get, ui.new_checkbox, ui.new_color_picker, ui.new_slider, ui.reference, ui.set, ui.set_callback, ui.set_visible
local clamp = function(v, min, max) local num = v; num = num < min and min or num; num = num > max and max or num; return num end

-- Linear fade needs no external easing library.
local m_alpha = 0

local scope_overlay = scope_overlay_ref
local master_switch = ui_new_checkbox('LUA', 'B', 'Custom scope lines')
local color_picker = ui_new_color_picker('LUA', 'B', 'Scope lines color', 0, 0, 0, 255)
local overlay_position = ui_new_slider('LUA', 'B', 'Scope lines length', 0, 500, 190)
local overlay_offset = ui_new_slider('LUA', 'B', 'Scope lines gap', 0, 500, 15)
local fade_time = ui_new_slider('LUA', 'B', 'Fade animation speed', 3, 20, 12, true, 'fr', 1, { [3] = 'Off' })

local g_paint_ui = function()
    request_scope_overlay("custom_scope", ui_get(master_switch))
end

local g_paint = function()

    local width, height = client_screen_size()
    local offset, initial_position, speed, color =
        ui_get(overlay_offset) * height / 1080, 
        ui_get(overlay_position) * height / 1080, 
        ui_get(fade_time), { ui_get(color_picker) }

    local me = entity_get_local_player()
    if not me or not entity_is_alive(me) then m_alpha = 0; return end
    local wpn = entity_get_player_weapon(me)
    if not wpn then m_alpha = 0; return end
    offset = math.min(offset, initial_position)

    local scope_level = entity_get_prop(wpn, 'm_zoomLevel')
    local scoped = entity_get_prop(me, 'm_bIsScoped') == 1
    local resume_zoom = entity_get_prop(me, 'm_bResumeZoom') == 1

    local is_valid = entity_is_alive(me) and wpn ~= nil and scope_level ~= nil
    local act = is_valid and scope_level > 0 and scoped and not resume_zoom

    local FT = speed > 3 and globals_frametime() * speed or 1
    local alpha = m_alpha

    renderer_gradient(width/2 - initial_position, height / 2, initial_position - offset, 1, color[1], color[2], color[3], 0, color[1], color[2], color[3], alpha*color[4], true)
    renderer_gradient(width/2 + offset, height / 2, initial_position - offset, 1, color[1], color[2], color[3], alpha*color[4], color[1], color[2], color[3], 0, true)

    renderer_gradient(width / 2, height/2 - initial_position, 1, initial_position - offset, color[1], color[2], color[3], 0, color[1], color[2], color[3], alpha*color[4], false)
    renderer_gradient(width / 2, height/2 + offset, 1, initial_position - offset, color[1], color[2], color[3], alpha*color[4], color[1], color[2], color[3], 0, false)
    
    m_alpha = clamp(m_alpha + (act and FT or -FT), 0, 1)
end

local ui_callback = function(c)
    local master_switch, addr = ui_get(c), ''

    if not master_switch then
        m_alpha, addr = 0, 'un'
    end
    
    local _func = client[addr .. 'set_event_callback']

    request_scope_overlay("custom_scope", master_switch)
    ui_set_visible(color_picker, master_switch)
    ui_set_visible(overlay_position, master_switch)
    ui_set_visible(overlay_offset, master_switch)
    ui_set_visible(fade_time, master_switch)

    _func('paint_ui', g_paint_ui)
    _func('paint', g_paint)
end

ui_set_callback(master_switch, ui_callback)
ui_callback(master_switch)
end

-- Integrated microphone killsay (WAV files from csgo/killsays). Controls: LUA > B.
local function setup_killsay()

local ffi = require('ffi');
local fsdll = "filesystem_stdio.dll"
local fs = "VFileSystem017"

local int_ptr = ffi.typeof("int[1]")
local char_buffer = ffi.typeof("char[?]")

local function sig_bind(module, interface, signature, typestring)
	local iface = client.create_interface(module, interface) or error("invalid interface", 2)
	local instance = client.find_signature(module, signature) or error("invalid signature", 2)
	local success, typeof = pcall(ffi.typeof, typestring)
	if not success then
		error(typeof, 2)
	end
	local fnptr = ffi.cast(typeof, instance) or error("invalid typecast", 2)
	return function(...)
		return fnptr(iface, ...)
	end
end

local add_to_searchpath = vtable_bind("filesystem_stdio.dll", "VFileSystem017", 11, "void(__thiscall*)(void*, const char*, const char*, int)");

--[[local remove_search_path = sig_bind(fsdll, fs, "\x55\x8B\xEC\x81\xEC\xCC\xCC\xCC\xCC\x8B\x55\x08\x53\x8B\xD9",
	"void(__thiscall*)(void*, const char*, const char*)")

local remove_file = sig_bind(fsdll, fs,
	"\x55\x8B\xEC\x81\xEC\xCC\xCC\xCC\xCC\x8D\x85\xCC\xCC\xCC\xCC\x56\x50\x8D\x45\x0C",
	"void(__thiscall*)(void*, const char*, const char*)")]]

local find_next = sig_bind(fsdll, fs,
		"\x55\x8B\xEC\x83\xEC\x0C\x53\x8B\xD9\x8B\x0D\xCC\xCC\xCC\xCC",
		"const char*(__thiscall*)(void*, int)")

local find_is_directory = sig_bind(fsdll, fs,
		"\x55\x8B\xEC\x0F\xB7\x45\x08",
		"bool(__thiscall*)(void*, int)")

local find_close = sig_bind(fsdll, fs,
		"\x55\x8B\xEC\x53\x8B\x5D\x08\x85",
		"void(__thiscall*)(void*, int)")

local find_first = sig_bind(fsdll, fs,
		"\x55\x8B\xEC\x6A\x00\xFF\x75\x10\xFF\x75\x0C\xFF\x75\x08\xE8\xCC\xCC\xCC\xCC\x5D",
		"const char*(__thiscall*)(void*, const char*, const char*, int*)")

local get_current_directory = sig_bind(fsdll, fs,
		"\x55\x8B\xEC\x56\x8B\x75\x08\x56\xFF\x75\x0C",
		"bool(__thiscall*)(void*, char*, int)")


-- Add Kill says to search path
local key = "SAM_KILL_SAY";
local path = char_buffer(128)
get_current_directory(path, ffi.sizeof(path))
path = ffi.string(path) .. '\\killsays'
add_to_searchpath(path, key, 0)



-- Find all killsays
local function getKillSays()
	local found_files = { "Off" }
	local fileHandle = int_ptr()
	local fileName = find_first("*", key, fileHandle)
	while fileName ~= nil do
		local conv = ffi.string(fileName)
		if not find_is_directory(fileHandle[0]) and conv:find('.wav') then
			table.insert(found_files, conv)
		end
		fileName = find_next(fileHandle[0])
	end
	find_close(fileHandle[0])
	return found_files
end

local isPlaying = false;

local oldLength = #getKillSays();
local killsay = ui.new_combobox('LUA', 'B', 'Microphone killsay', unpack(getKillSays()));
local kill_say_mode = ui.new_combobox('LUA', 'B', 'Killsay mode', { 'Selected', 'Increasement', 'Random' });
local loopback = ui.new_checkbox('LUA', 'B', 'Sound loop back');
--local no_overlap = ui.new_checkbox('LUA', 'B', 'Do not overlap');

local function recreateElement(old, type, ...)
	ui.set_visible(old, false);
	local old_val = ui.get(old);
	local temp = ui[type](...);
	-- Prevents Combobox Item not found error
	pcall(function()
		ui.set(temp, old_val);
	end)
	return temp;
end

local function updateKilLSays()
	if (oldLength ~= #getKillSays()) then
		killsay = recreateElement(killsay, 'new_combobox', 'LUA', 'B', 'Microphone Kill Say', unpack(getKillSays()));
		kill_say_mode = recreateElement(kill_say_mode, 'new_combobox', 'LUA', 'B', 'Killsay mode', { 'Selected', 'Increasement', 'Random' });
		loopback = recreateElement(loopback, 'new_checkbox', 'LUA', 'B', 'Sound loop back');

		oldLength = #getKillSays();
	end
end

local function binToNumber(string)
	return string.byte(string, 1) + string.byte(string, 2) * 256 + string.byte(string, 3) * 65536 + string.byte(string, 4) * 16777216
end

local increasement = 2;
local function getWavFile()
	local killsays = getKillSays();
	local file = ui.get(killsay);
	local mode = ui.get(kill_say_mode);
	if (mode == 'Increasement') then
		file = killsays[increasement];
		increasement = increasement + 1;
		if (increasement > #killsays) then
			increasement = 2;
		end
	elseif (mode == 'Random') then
		file = killsays[math.random(2, #killsays)];
	end
	return readfile('killsays\\' .. file);
end

local function getWavFileDuration(bytes)
	local size = binToNumber(string.sub(bytes, 4, 8));
	local byterate = binToNumber(string.sub(bytes, 28, 32));
	return (size - 42) / byterate
end

local function toggleMic(on)
	isPlaying = on;
	local loopback = ui.get(loopback) and 1 or 0;
	cvar.voice_loopback:set_int(on and loopback or 0);
	cvar.voice_inputfromfile:set_int(on and 1 or 0);
	client.exec((on and '+' or '-') .. 'voicerecord');
end

client.set_event_callback("player_death", function(event)
	local userid, attacker = event.userid, event.attacker

	if (userid and attacker) then
		local userid_idx, attacker_idx, lp_idx = client.userid_to_entindex(userid), client.userid_to_entindex(attacker), entity.get_local_player();

		if (userid_idx and attacker_idx and attacker_idx == lp_idx and userid_idx ~= lp_idx and ui.get(killsay) ~= 'Off') then
			if (not isPlaying) then
				local bytes = getWavFile();
				writefile('voice_input.wav', bytes);
				local duration = getWavFileDuration(bytes);
				client.delay_call(duration, function()
					toggleMic(false);
				end)
				toggleMic(true);
			end
		end
	end
end);

client.set_event_callback('shutdown', function()
	toggleMic(false)
end)

client.set_event_callback('paint_ui', function()
	updateKilLSays();
end)

end

local killsay_ok, killsay_error = pcall(setup_killsay)
if not killsay_ok then
    client.log("[skeet-tools] killsay unavailable: ", tostring(killsay_error))
end

-- Integrated model changer. Controls: LUA > A.
local function setup_model_changer()
------------------------------------------------------------------
-- UwU model changer (standalone)
-- extracted from uwu_hook.lua
------------------------------------------------------------------

local ffi = require 'ffi'

-- // native filesystem helpers /////////////////////////////////////

local function vmt_entry(instance, index, type)
    return ffi.cast(type, (ffi.cast("void***", instance)[0])[index])
end

local function vmt_bind(module, interface, index, typestring)
    local instance = client.create_interface(module, interface) or error("invalid interface")
    local success, typeof = pcall(ffi.typeof, typestring)
    if not success then
        error(typeof, 2)
    end
    local fnptr = vmt_entry(instance, index, typeof) or error("invalid vtable")
    return function(...)
        return fnptr(instance, ...)
    end
end

local function bind_signature(module, interface, signature, typestring)
    local interface_ptr = client.create_interface(module, interface) or error("invalid interface", 2)
    local instance = client.find_signature(module, signature) or error("invalid signature", 2)
    local success, typeof = pcall(ffi.typeof, typestring)
    if not success then
        error(typeof, 2)
    end
    local fnptr = ffi.cast(typeof, instance) or error("invalid typecast", 2)
    return function(...)
        return fnptr(interface_ptr, ...)
    end
end

local char_buffer, int_ptr, current_directory, add_to_searchpath, find_first, find_next, find_close, find_is_directory
do
    char_buffer = ffi.typeof("char[?]")
    int_ptr = ffi.typeof("int[1]")
    current_directory = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x56\x8B\x75\x08\x56\xFF\x75\x0C", "bool(__thiscall*)(void*, char*, int)")
    add_to_searchpath = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x81\xEC\xCC\xCC\xCC\xCC\x8B\x55\x08\x53\x56\x57", "void(__thiscall*)(void*, const char*, const char*, int)")
    find_first = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x6A\x00\xFF\x75\x10\xFF\x75\x0C\xFF\x75\x08\xE8\xCC\xCC\xCC\xCC\x5D", "const char*(__thiscall*)(void*, const char*, const char*, int*)")
    find_next = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x83\xEC\x0C\x53\x8B\xD9\x8B\x0D\xCC\xCC\xCC\xCC", "const char*(__thiscall*)(void*, int)")
    find_close = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x53\x8B\x5D\x08\x85", "void(__thiscall*)(void*, int)")
    find_is_directory = bind_signature("filesystem_stdio.dll", "VFileSystem017", "\x55\x8B\xEC\x0F\xB7\x45\x08", "bool(__thiscall*)(void*, int)")
end

-- // custom model collection ///////////////////////////////////////

local function collect_custom_models()
    local models = {}
    local file_handle = int_ptr()
    local file = find_first("*", "CUSTOMMODEL", file_handle)
    while file ~= nil do
        local file_name = ffi.string(file)
        if find_is_directory(file_handle[0]) == true and file_name ~= "." and file_name ~= ".." then
            local subfolder_handle = int_ptr()
            local subfolder_file = find_first(file_name .. "/*", "CUSTOMMODEL", subfolder_handle)
            while subfolder_file ~= nil do
                local subfolder_file_name = ffi.string(subfolder_file)
                if find_is_directory(subfolder_handle[0]) == false and subfolder_file_name:find(".mdl") then
                    local lower_name = subfolder_file_name:lower()
                    if not lower_name:find("arms") and not lower_name:find("sleeve") and not lower_name:find("hand") and not lower_name:find("bas%.res") then
                        local model_path = "models/player/custom_player/" .. file_name .. "/" .. subfolder_file_name
                        local display_name = subfolder_file_name:gsub(".mdl", ""):gsub("_", " ")
                        local first_letter = display_name:sub(1, 1)
                        local rest = display_name:sub(2)
                        display_name = first_letter:upper() .. rest
                        models[display_name] = model_path
                    end
                elseif find_is_directory(subfolder_handle[0]) == true and subfolder_file_name ~= "." and subfolder_file_name ~= ".." then
                    local subsubfolder_handle = int_ptr()
                    local subsubfolder_file = find_first(file_name .. "/" .. subfolder_file_name .. "/*", "CUSTOMMODEL", subsubfolder_handle)
                    while subsubfolder_file ~= nil do
                        local subsubfolder_file_name = ffi.string(subsubfolder_file)
                        if find_is_directory(subsubfolder_handle[0]) == false and subsubfolder_file_name:find(".mdl") then
                            local lower_name = subsubfolder_file_name:lower()
                            if not lower_name:find("arms") and not lower_name:find("sleeve") and not lower_name:find("hand") and not lower_name:find("bas%.res") then
                                local model_path = "models/player/custom_player/" .. file_name .. "/" .. subfolder_file_name .. "/" .. subsubfolder_file_name
                                local display_name = subsubfolder_file_name:gsub(".mdl", ""):gsub("_", " ")
                                local first_letter = display_name:sub(1, 1)
                                local rest = display_name:sub(2)
                                display_name = first_letter:upper() .. rest
                                models[display_name] = model_path
                            end
                        end
                        subsubfolder_file = find_next(subsubfolder_handle[0])
                    end
                    find_close(subsubfolder_handle[0])
                end
                subfolder_file = find_next(subfolder_handle[0])
            end
            find_close(subfolder_handle[0])
        elseif find_is_directory(file_handle[0]) == false and file_name:find(".mdl") then
            local lower_name = file_name:lower()
            if not lower_name:find("arms") and not lower_name:find("sleeve") and not lower_name:find("hand") and not lower_name:find("bas%.res") then
                local model_path = "models/player/custom_player/" .. file_name
                local display_name = file_name:gsub(".mdl", ""):gsub("_", " ")
                local first_letter = display_name:sub(1, 1)
                local rest = display_name:sub(2)
                display_name = first_letter:upper() .. rest
                models[display_name] = model_path
            end
        end
        file = find_next(file_handle[0])
    end
    find_close(file_handle[0])
    return models
end

local custom_model_path = char_buffer(192)
current_directory(custom_model_path, ffi.sizeof(custom_model_path))
custom_model_path = string.format("%s\\csgo\\models\\player\\custom_player", ffi.string(custom_model_path))
add_to_searchpath(custom_model_path, "CUSTOMMODEL", 0)

local auto_t_models = collect_custom_models()
local auto_ct_models = collect_custom_models()

auto_t_models["None"] = ""
auto_ct_models["None"] = ""

local t_player_models = {
    ["None"] = "",
    ["mika"] = "models/player/custom_player/nuclearsilo/blue_archive/mika/mika_v2.mdl",
    ["jinx"] = "models/player/custom_player/kolka/Arcane_Jinx/arcane_jinx.mdl",
    ["dva"] = "models/player/custom_player/killzonegaming/dva/dva.mdl",
    ["hatsunenightmare"] = "models/player/custom_player/maoling/vocaloid/hatsune_miku/monsterko/nightmare/miku_nightmare.mdl",
    ["hutao"] = "models/player/custom_player/toppiofficial/genshin/rework/hutao.mdl",
}

local ct_player_models = {
    ["None"] = "",
    ["mika"] = "models/player/custom_player/nuclearsilo/blue_archive/mika/mika_v2.mdl",
    ["jinx"] = "models/player/custom_player/kolka/Arcane_Jinx/arcane_jinx.mdl",
    ["dva"] = "models/player/custom_player/killzonegaming/dva/dva.mdl",
    ["hatsunenightmare"] = "models/player/custom_player/maoling/vocaloid/hatsune_miku/monsterko/nightmare/miku_nightmare.mdl",
    ["hutao"] = "models/player/custom_player/toppiofficial/genshin/rework/hutao.mdl",
}

local function get_model_names(models_table)
    local names = {}
    for k, v in pairs(models_table) do
        table.insert(names, k)
    end
    table.sort(names, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        return a < b
    end)
    return names
end

local model_names_t = get_model_names(t_player_models)
local model_names_ct = get_model_names(ct_player_models)
local auto_model_names_t = get_model_names(auto_t_models)
local auto_model_names_ct = get_model_names(auto_ct_models)

-- // ui ////////////////////////////////////////////////////////////

local UI = {}
UI.enabled = ui.new_checkbox("LUA", "A", "\aFF78DCFFUwU model changer")
UI.mode = ui.new_combobox("LUA", "A", "\aFF78DCFF  Mode", {"Manual", "Auto"})
UI.ct = ui.new_combobox("LUA", "A", "\aFF78DCFF  CT Model", model_names_ct)
UI.t = ui.new_combobox("LUA", "A", "\aFF78DCFF  T Model", model_names_t)
UI.ct_auto = ui.new_combobox("LUA", "A", "\aFF78DCFF  CT Model\nauto", auto_model_names_ct)
UI.t_auto = ui.new_combobox("LUA", "A", "\aFF78DCFF  T Model\nauto", auto_model_names_t)

local function update_visibility()
    local enabled = ui.get(UI.enabled)
    local mode = ui.get(UI.mode)

    ui.set_visible(UI.mode, enabled)
    ui.set_visible(UI.ct, enabled and mode == "Manual")
    ui.set_visible(UI.t, enabled and mode == "Manual")
    ui.set_visible(UI.ct_auto, enabled and mode == "Auto")
    ui.set_visible(UI.t_auto, enabled and mode == "Auto")
end

ui.set_callback(UI.enabled, update_visibility)
ui.set_callback(UI.mode, update_visibility)
update_visibility()

-- // native model changing /////////////////////////////////////////

ffi.cdef[[
    typedef struct
    {
        void*   fnHandle;
        char    szName[260];
        int     nLoadFlags;
        int     nServerCount;
        int     type;
        int     flags;
        float  vecMins[3];
        float  vecMaxs[3];
        float   radius;
        char    pad[0x1C];
    }model_t;

    typedef int(__thiscall* get_model_index_t)(void*, const char*);
    typedef const model_t(__thiscall* find_or_load_model_t)(void*, const char*);
    typedef int(__thiscall* add_string_t)(void*, bool, const char*, int, const void*);
    typedef void*(__thiscall* find_table_t)(void*, const char*);
    typedef void(__thiscall* set_model_index_t)(void*, int);
    typedef int(__thiscall* precache_model_t)(void*, const char*, bool);
    typedef void*(__thiscall* get_client_entity_t)(void*, int);
]]

local class_ptr = ffi.typeof("void***")

local rawientitylist = client.create_interface("client_panorama.dll", "VClientEntityList003")
local ientitylist = rawientitylist and ffi.cast(class_ptr, rawientitylist)
local get_client_entity = ientitylist and ffi.cast("get_client_entity_t", ientitylist[0][3])

local rawivmodelinfo = client.create_interface("engine.dll", "VModelInfoClient004")
local ivmodelinfo = rawivmodelinfo and ffi.cast(class_ptr, rawivmodelinfo)
local get_model_index = ivmodelinfo and ffi.cast("get_model_index_t", ivmodelinfo[0][2])
local find_or_load_model = ivmodelinfo and ffi.cast("find_or_load_model_t", ivmodelinfo[0][39])

local rawnetworkstringtablecontainer = client.create_interface("engine.dll", "VEngineClientStringTable001")
local networkstringtablecontainer = rawnetworkstringtablecontainer and ffi.cast(class_ptr, rawnetworkstringtablecontainer)
local find_table = networkstringtablecontainer and ffi.cast("find_table_t", networkstringtablecontainer[0][3])

local function precache_model(modelname)
    if not find_table or not networkstringtablecontainer then return false end

    local rawprecache_table = find_table(networkstringtablecontainer, "modelprecache")
    if rawprecache_table then
        local precache_table = ffi.cast(class_ptr, rawprecache_table)
        if precache_table then
            local add_string = ffi.cast("add_string_t", precache_table[0][8])
            if add_string and find_or_load_model and ivmodelinfo then
                find_or_load_model(ivmodelinfo, modelname)
                local idx = add_string(precache_table, false, modelname, -1, nil)
                if idx == -1 then
                    return false
                end
            end
        end
    end
    return true
end

local function set_model_index(ent, idx)
    if not get_client_entity or not ientitylist then return end

    local raw_entity = get_client_entity(ientitylist, ent)
    if raw_entity then
        local gce_entity = ffi.cast(class_ptr, raw_entity)
        local a_set_model_index = ffi.cast("set_model_index_t", gce_entity[0][75])
        if a_set_model_index then
            a_set_model_index(gce_entity, idx)
        end
    end
end

local function change_model(ent, model)
    if not model or model == "" or model:len() <= 5 then return end
    if not get_model_index or not ivmodelinfo then return end

    if precache_model(model) == false then
        return
    end
    local idx = get_model_index(ivmodelinfo, model)
    if idx == -1 then
        return
    end
    set_model_index(ent, idx)
end

-- // apply /////////////////////////////////////////////////////////

client.set_event_callback('pre_render', function()
    if not ui.get(UI.enabled) then return end

    local me = entity.get_local_player()
    if not me then return end

    local team = entity.get_prop(me, 'm_iTeamNum')
    if not team then return end

    local model_mode = ui.get(UI.mode)

    if team == 2 then
        local model_name, model_path
        if model_mode == "Auto" then
            model_name = ui.get(UI.t_auto)
            model_path = auto_t_models[model_name]
        else
            model_name = ui.get(UI.t)
            model_path = t_player_models[model_name]
        end
        if model_path and model_path ~= "" then
            change_model(me, model_path)
        end
    elseif team == 3 then
        local model_name, model_path
        if model_mode == "Auto" then
            model_name = ui.get(UI.ct_auto)
            model_path = auto_ct_models[model_name]
        else
            model_name = ui.get(UI.ct)
            model_path = ct_player_models[model_name]
        end
        if model_path and model_path ~= "" then
            change_model(me, model_path)
        end
    end
end)

client.color_log(255, 120, 220, "[gamesense] \0")
client.color_log(255, 255, 255, "UwU model changer loaded! >-< ♡")

end

local model_changer_ok, model_changer_error = pcall(setup_model_changer)
if not model_changer_ok then
    client.log("[skeet-tools] model_changer unavailable: ", tostring(model_changer_error))
end

-- Integrated skybox changer. Controls: LUA > A.
local function setup_skybox()


local ffi = require("ffi")
local type = type
local unpack = unpack
local table_insert = table.insert
local table_concat = table.concat
local client_color_log = client.color_log
local package_searchpath = package.searchpath
local materialsystem_find_materials = materialsystem.find_materials
local client_userid_to_entindex = client.userid_to_entindex
local entity_get_local_player = entity.get_local_player
local client_delay_call = client.delay_call
local client_set_event_callback = client.set_event_callback
local client_unset_event_callback = client.unset_event_callback
local ui_set_callback = ui.set_callback
local ui_get = ui.get
local globals_realtime = globals.realtime
local tSkyboxList = {
  {
    sName = "Tibet",
    sPath = "cs_tibet",
    bThirdparty = false
  },
  {
    sName = "Baggage",
    sPath = "cs_baggage_skybox_",
    bThirdparty = false
  },
  {
    sName = "Monastery",
    sPath = "embassy",
    bThirdparty = false
  },
  {
    sName = "Italy",
    sPath = "italy",
    bThirdparty = false
  },
  {
    sName = "Aztec",
    sPath = "jungle",
    bThirdparty = false
  },
  {
    sName = "Vertigo",
    sPath = "office",
    bThirdparty = false
  },
  {
    sName = "Daylight",
    sPath = "sky_cs15_daylight01_hdr",
    bThirdparty = false
  },
  {
    sName = "Daylight (2)",
    sPath = "vertigoblue_hdr",
    bThirdparty = false
  },
  {
    sName = "Clouds",
    sPath = "sky_cs15_daylight02_hdr",
    bThirdparty = false
  },
  {
    sName = "Clouds (2)",
    sPath = "vertigo",
    bThirdparty = false
  },
  {
    sName = "Gray",
    sPath = "sky_day02_05_hdr",
    bThirdparty = false
  },
  {
    sName = "Clear",
    sPath = "nukeblank",
    bThirdparty = false
  },
  {
    sName = "Canals",
    sPath = "sky_venice",
    bThirdparty = false
  },
  {
    sName = "Cobblestone",
    sPath = "sky_cs15_daylight03_hdr",
    bThirdparty = false
  },
  {
    sName = "Assault",
    sPath = "sky_cs15_daylight04_hdr",
    bThirdparty = false
  },
  {
    sName = "Clouds (Dark)",
    sPath = "sky_csgo_cloudy01",
    bThirdparty = false
  },
  {
    sName = "Night",
    sPath = "sky_csgo_night02",
    bThirdparty = false
  },
  {
    sName = "Night (2)",
    sPath = "sky_csgo_night02b",
    bThirdparty = false
  },
  {
    sName = "Night (Flat)",
    sPath = "sky_csgo_night_flat",
    bThirdparty = false
  },
  {
    sName = "Dusty",
    sPath = "sky_dust",
    bThirdparty = false
  },
  {
    sName = "Rainy",
    sPath = "vietnam",
    bThirdparty = false
  },
  {
    sName = "amethyst",
    sPath = "amethyst",
    bThirdparty = true
  },
  {
    sName = "clear_night_sky",
    sPath = "clear_night_sky",
    bThirdparty = true
  },
  {
    sName = "cloudynight",
    sPath = "cloudynight",
    bThirdparty = true
  },
  {
    sName = "dreamyocean",
    sPath = "dreamyocean",
    bThirdparty = true
  },
  {
    sName = "grimmnight",
    sPath = "grimmnight",
    bThirdparty = true
  },
  {
    sName = "lakesky",
    sPath = "lakesky",
    bThirdparty = true
  },
  {
    sName = "mars",
    sPath = "mars",
    bThirdparty = true
  },
  {
    sName = "mpa119",
    sPath = "mpa119",
    bThirdparty = true
  },
  {
    sName = "mr1",
    sPath = "mr1",
    bThirdparty = true
  },
  {
    sName = "mr_01",
    sPath = "mr_01",
    bThirdparty = true
  },
  {
    sName = "mr_02",
    sPath = "mr_02",
    bThirdparty = true
  },
  {
    sName = "mr_03",
    sPath = "mr_03",
    bThirdparty = true
  },
  {
    sName = "mr_04",
    sPath = "mr_04",
    bThirdparty = true
  },
  {
    sName = "mr_05",
    sPath = "mr_05",
    bThirdparty = true
  },
  {
    sName = "mr_06",
    sPath = "mr_06",
    bThirdparty = true
  },
  {
    sName = "mr_07",
    sPath = "mr_07",
    bThirdparty = true
  },
  {
    sName = "mr_08",
    sPath = "mr_08",
    bThirdparty = true
  },
  {
    sName = "mr_10",
    sPath = "mr_10",
    bThirdparty = true
  },
  {
    sName = "mr_12",
    sPath = "mr_12",
    bThirdparty = true
  },
  {
    sName = "mr_13",
    sPath = "mr_13",
    bThirdparty = true
  },
  {
    sName = "mr_15",
    sPath = "mr_15",
    bThirdparty = true
  },
  {
    sName = "mr_16",
    sPath = "mr_16",
    bThirdparty = true
  },
  {
    sName = "mr_ice",
    sPath = "mr_ice",
    bThirdparty = true
  },
  {
    sName = "mr_moon",
    sPath = "mr_moon",
    bThirdparty = true
  },
  {
    sName = "mr_night_",
    sPath = "mr_night_",
    bThirdparty = true
  },
  {
    sName = "mr_space",
    sPath = "mr_space",
    bThirdparty = true
  },
  {
    sName = "otherworld",
    sPath = "otherworld",
    bThirdparty = true
  },
  {
    sName = "pandora_b",
    sPath = "pandora_b",
    bThirdparty = true
  },
  {
    sName = "pandora_f",
    sPath = "pandora_f",
    bThirdparty = true
  },
  {
    sName = "ptr_amethyst",
    sPath = "ptr_amethyst",
    bThirdparty = true
  },
  {
    sName = "ptr_clear_night_sky",
    sPath = "ptr_clear_night_sky",
    bThirdparty = true
  },
  {
    sName = "ptr_cloudynight",
    sPath = "ptr_cloudynight",
    bThirdparty = true
  },
  {
    sName = "ptr_dreamyocean",
    sPath = "ptr_dreamyocean",
    bThirdparty = true
  },
  {
    sName = "ptr_grimmnight",
    sPath = "ptr_grimmnight",
    bThirdparty = true
  },
  {
    sName = "ptr_otherworld",
    sPath = "ptr_otherworld",
    bThirdparty = true
  },
  {
    sName = "ptr_sky051",
    sPath = "ptr_sky051",
    bThirdparty = true
  },
  {
    sName = "ptr_sky081",
    sPath = "ptr_sky081",
    bThirdparty = true
  },
  {
    sName = "ptr_sky091",
    sPath = "ptr_sky091",
    bThirdparty = true
  },
  {
    sName = "ptr_sky561",
    sPath = "ptr_sky561",
    bThirdparty = true
  },
  {
    sName = "Real_SkySunset",
    sPath = "Real_SkySunset",
    bThirdparty = true
  },
  {
    sName = "red_planet",
    sPath = "red_planet",
    bThirdparty = true
  },
  {
    sName = "retrosun",
    sPath = "retrosun",
    bThirdparty = true
  },
  {
    sName = "sky002",
    sPath = "sky002",
    bThirdparty = true
  },
  {
    sName = "sky003",
    sPath = "sky003",
    bThirdparty = true
  },
  {
    sName = "sky004",
    sPath = "sky004",
    bThirdparty = true
  },
  {
    sName = "sky051",
    sPath = "sky051",
    bThirdparty = true
  },
  {
    sName = "sky081",
    sPath = "sky081",
    bThirdparty = true
  },
  {
    sName = "sky091",
    sPath = "sky091",
    bThirdparty = true
  },
  {
    sName = "sky100",
    sPath = "sky100",
    bThirdparty = true
  },
  {
    sName = "sky101",
    sPath = "sky101",
    bThirdparty = true
  },
  {
    sName = "sky103",
    sPath = "sky103",
    bThirdparty = true
  },
  {
    sName = "sky104",
    sPath = "sky104",
    bThirdparty = true
  },
  {
    sName = "sky105",
    sPath = "sky105",
    bThirdparty = true
  },
  {
    sName = "sky106",
    sPath = "sky106",
    bThirdparty = true
  },
  {
    sName = "sky107",
    sPath = "sky107",
    bThirdparty = true
  },
  {
    sName = "sky108",
    sPath = "sky108",
    bThirdparty = true
  },
  {
    sName = "sky109",
    sPath = "sky109",
    bThirdparty = true
  },
  {
    sName = "sky110",
    sPath = "sky110",
    bThirdparty = true
  },
  {
    sName = "sky111",
    sPath = "sky111",
    bThirdparty = true
  },
  {
    sName = "sky112",
    sPath = "sky112",
    bThirdparty = true
  },
  {
    sName = "sky113",
    sPath = "sky113",
    bThirdparty = true
  },
  {
    sName = "sky114",
    sPath = "sky114",
    bThirdparty = true
  },
  {
    sName = "sky115",
    sPath = "sky115",
    bThirdparty = true
  },
  {
    sName = "sky116",
    sPath = "sky116",
    bThirdparty = true
  },
  {
    sName = "sky117",
    sPath = "sky117",
    bThirdparty = true
  },
  {
    sName = "sky118",
    sPath = "sky118",
    bThirdparty = true
  },
  {
    sName = "sky119",
    sPath = "sky119",
    bThirdparty = true
  },
  {
    sName = "sky121",
    sPath = "sky121",
    bThirdparty = true
  },
  {
    sName = "sky122",
    sPath = "sky122",
    bThirdparty = true
  },
  {
    sName = "sky123",
    sPath = "sky123",
    bThirdparty = true
  },
  {
    sName = "sky124",
    sPath = "sky124",
    bThirdparty = true
  },
  {
    sName = "sky125",
    sPath = "sky125",
    bThirdparty = true
  },
  {
    sName = "sky126",
    sPath = "sky126",
    bThirdparty = true
  },
  {
    sName = "sky127",
    sPath = "sky127",
    bThirdparty = true
  },
  {
    sName = "sky128",
    sPath = "sky128",
    bThirdparty = true
  },
  {
    sName = "sky129c",
    sPath = "sky129c",
    bThirdparty = true
  },
  {
    sName = "sky129",
    sPath = "sky129",
    bThirdparty = true
  },
  {
    sName = "sky130",
    sPath = "sky130",
    bThirdparty = true
  },
  {
    sName = "sky131",
    sPath = "sky131",
    bThirdparty = true
  },
  {
    sName = "sky132",
    sPath = "sky132",
    bThirdparty = true
  },
  {
    sName = "sky133",
    sPath = "sky133",
    bThirdparty = true
  },
  {
    sName = "sky134",
    sPath = "sky134",
    bThirdparty = true
  },
  {
    sName = "sky135",
    sPath = "sky135",
    bThirdparty = true
  },
  {
    sName = "sky136",
    sPath = "sky136",
    bThirdparty = true
  },
  {
    sName = "sky137",
    sPath = "sky137",
    bThirdparty = true
  },
  {
    sName = "sky138a",
    sPath = "sky138a",
    bThirdparty = true
  },
  {
    sName = "sky138",
    sPath = "sky138",
    bThirdparty = true
  },
  {
    sName = "sky139a",
    sPath = "sky139a",
    bThirdparty = true
  },
  {
    sName = "sky139",
    sPath = "sky139",
    bThirdparty = true
  },
  {
    sName = "sky140",
    sPath = "sky140",
    bThirdparty = true
  },
  {
    sName = "sky141",
    sPath = "sky141",
    bThirdparty = true
  },
  {
    sName = "sky142",
    sPath = "sky142",
    bThirdparty = true
  },
  {
    sName = "sky143",
    sPath = "sky143",
    bThirdparty = true
  },
  {
    sName = "sky144",
    sPath = "sky144",
    bThirdparty = true
  },
  {
    sName = "sky145",
    sPath = "sky145",
    bThirdparty = true
  },
  {
    sName = "sky147",
    sPath = "sky147",
    bThirdparty = true
  },
  {
    sName = "sky148",
    sPath = "sky148",
    bThirdparty = true
  },
  {
    sName = "sky149",
    sPath = "sky149",
    bThirdparty = true
  },
  {
    sName = "sky150day",
    sPath = "sky150day",
    bThirdparty = true
  },
  {
    sName = "sky150",
    sPath = "sky150",
    bThirdparty = true
  },
  {
    sName = "sky151",
    sPath = "sky151",
    bThirdparty = true
  },
  {
    sName = "sky152",
    sPath = "sky152",
    bThirdparty = true
  },
  {
    sName = "sky153",
    sPath = "sky153",
    bThirdparty = true
  },
  {
    sName = "sky154",
    sPath = "sky154",
    bThirdparty = true
  },
  {
    sName = "sky155",
    sPath = "sky155",
    bThirdparty = true
  },
  {
    sName = "sky156",
    sPath = "sky156",
    bThirdparty = true
  },
  {
    sName = "sky157",
    sPath = "sky157",
    bThirdparty = true
  },
  {
    sName = "sky158",
    sPath = "sky158",
    bThirdparty = true
  },
  {
    sName = "sky159",
    sPath = "sky159",
    bThirdparty = true
  },
  {
    sName = "sky161s",
    sPath = "sky161s",
    bThirdparty = true
  },
  {
    sName = "sky161",
    sPath = "sky161",
    bThirdparty = true
  },
  {
    sName = "sky162",
    sPath = "sky162",
    bThirdparty = true
  },
  {
    sName = "sky163",
    sPath = "sky163",
    bThirdparty = true
  },
  {
    sName = "sky164",
    sPath = "sky164",
    bThirdparty = true
  },
  {
    sName = "sky165",
    sPath = "sky165",
    bThirdparty = true
  },
  {
    sName = "sky166",
    sPath = "sky166",
    bThirdparty = true
  },
  {
    sName = "sky167",
    sPath = "sky167",
    bThirdparty = true
  },
  {
    sName = "sky168",
    sPath = "sky168",
    bThirdparty = true
  },
  {
    sName = "sky169",
    sPath = "sky169",
    bThirdparty = true
  },
  {
    sName = "sky170",
    sPath = "sky170",
    bThirdparty = true
  },
  {
    sName = "sky171",
    sPath = "sky171",
    bThirdparty = true
  },
  {
    sName = "sky172",
    sPath = "sky172",
    bThirdparty = true
  },
  {
    sName = "sky173",
    sPath = "sky173",
    bThirdparty = true
  },
  {
    sName = "sky174",
    sPath = "sky174",
    bThirdparty = true
  },
  {
    sName = "sky175",
    sPath = "sky175",
    bThirdparty = true
  },
  {
    sName = "sky176",
    sPath = "sky176",
    bThirdparty = true
  },
  {
    sName = "sky177",
    sPath = "sky177",
    bThirdparty = true
  },
  {
    sName = "sky178",
    sPath = "sky178",
    bThirdparty = true
  },
  {
    sName = "sky179",
    sPath = "sky179",
    bThirdparty = true
  },
  {
    sName = "sky180",
    sPath = "sky180",
    bThirdparty = true
  },
  {
    sName = "sky181",
    sPath = "sky181",
    bThirdparty = true
  },
  {
    sName = "sky182",
    sPath = "sky182",
    bThirdparty = true
  },
  {
    sName = "sky183",
    sPath = "sky183",
    bThirdparty = true
  },
  {
    sName = "sky184",
    sPath = "sky184",
    bThirdparty = true
  },
  {
    sName = "sky185",
    sPath = "sky185",
    bThirdparty = true
  },
  {
    sName = "sky186",
    sPath = "sky186",
    bThirdparty = true
  },
  {
    sName = "sky187",
    sPath = "sky187",
    bThirdparty = true
  },
  {
    sName = "sky190",
    sPath = "sky190",
    bThirdparty = true
  },
  {
    sName = "sky191",
    sPath = "sky191",
    bThirdparty = true
  },
  {
    sName = "sky192",
    sPath = "sky192",
    bThirdparty = true
  },
  {
    sName = "sky1",
    sPath = "sky1",
    bThirdparty = true
  },
  {
    sName = "sky200",
    sPath = "sky200",
    bThirdparty = true
  },
  {
    sName = "sky26_HDR",
    sPath = "sky26_HDR",
    bThirdparty = true
  },
  {
    sName = "sky28_HDR",
    sPath = "sky28_HDR",
    bThirdparty = true
  },
  {
    sName = "sky302",
    sPath = "sky302",
    bThirdparty = true
  },
  {
    sName = "sky303",
    sPath = "sky303",
    bThirdparty = true
  },
  {
    sName = "sky561",
    sPath = "sky561",
    bThirdparty = true
  },
  {
    sName = "sky77",
    sPath = "sky77",
    bThirdparty = true
  },
  {
    sName = "sky78",
    sPath = "sky78",
    bThirdparty = true
  },
  {
    sName = "sky_001",
    sPath = "sky_001",
    bThirdparty = true
  },
  {
    sName = "sky_79",
    sPath = "sky_79",
    bThirdparty = true
  },
  {
    sName = "sky_descent",
    sPath = "sky_descent",
    bThirdparty = true
  },
  {
    sName = "sky_l",
    sPath = "sky_l",
    bThirdparty = true
  },
  {
    sName = "sky_moon",
    sPath = "sky_moon",
    bThirdparty = true
  },
  {
    sName = "sky_z",
    sPath = "sky_z",
    bThirdparty = true
  },
  {
    sName = "space_10",
    sPath = "space_10",
    bThirdparty = true
  },
  {
    sName = "space_11",
    sPath = "space_11",
    bThirdparty = true
  },
  {
    sName = "space_12",
    sPath = "space_12",
    bThirdparty = true
  },
  {
    sName = "space_13",
    sPath = "space_13",
    bThirdparty = true
  },
  {
    sName = "space_14",
    sPath = "space_14",
    bThirdparty = true
  },
  {
    sName = "space_15",
    sPath = "space_15",
    bThirdparty = true
  },
  {
    sName = "space_16",
    sPath = "space_16",
    bThirdparty = true
  },
  {
    sName = "space_17",
    sPath = "space_17",
    bThirdparty = true
  },
  {
    sName = "space_18",
    sPath = "space_18",
    bThirdparty = true
  },
  {
    sName = "space_19",
    sPath = "space_19",
    bThirdparty = true
  },
  {
    sName = "space_1",
    sPath = "space_1",
    bThirdparty = true
  },
  {
    sName = "space_20",
    sPath = "space_20",
    bThirdparty = true
  },
  {
    sName = "space_22",
    sPath = "space_22",
    bThirdparty = true
  },
  {
    sName = "space_23",
    sPath = "space_23",
    bThirdparty = true
  },
  {
    sName = "space_2",
    sPath = "space_2",
    bThirdparty = true
  },
  {
    sName = "space_3",
    sPath = "space_3",
    bThirdparty = true
  },
  {
    sName = "space_4",
    sPath = "space_4",
    bThirdparty = true
  },
  {
    sName = "space_5",
    sPath = "space_5",
    bThirdparty = true
  },
  {
    sName = "space_6",
    sPath = "space_6",
    bThirdparty = true
  },
  {
    sName = "space_7",
    sPath = "space_7",
    bThirdparty = true
  },
  {
    sName = "space_8",
    sPath = "space_8",
    bThirdparty = true
  },
  {
    sName = "space_9",
    sPath = "space_9",
    bThirdparty = true
  },
  {
    sName = "stormymountain_hdr",
    sPath = "stormymountain_hdr",
    bThirdparty = true
  },
  {
    sName = "sunsetmountain",
    sPath = "sunsetmountain",
    bThirdparty = true
  },
  {
    sName = "WhiteDwarf",
    sPath = "WhiteDwarf",
    bThirdparty = true
  }
}

local load_name_sky_address = client.find_signature("engine.dll", "\x55\x8B\xEC\x81\xEC\xCC\xCC\xCC\xCC\x56\x57\x8B\xF9\xC7\x45") or error("signature for load_skybox is outdated")
local load_name_sky = ffi.cast(ffi.typeof("void(__fastcall*)(const char*)"), load_name_sky_address)

local multicolor_log
multicolor_log = function(...)
  local args = {
    ...
  }
  local len = #args
  for i = 1, len do
    local arg = args[i]
    local r, g, b = unpack(arg)
    local msg = { }
    if #arg == 3 then
      table_insert(msg, " ")
    else
      for i = 4, #arg do
        table_insert(msg, arg[i])
      end
    end
    msg = table_concat(msg)
    if len > i then
      msg = msg .. "\0"
    end
    client_color_log(r, g, b, msg)
  end
end
do
  local _accum_0 = { }
  local _len_0 = 1
  for _index_0 = 1, #tSkyboxList do
    local tSkyboxData = tSkyboxList[_index_0]
    if (function()
      if tSkyboxData.bThirdparty then
        local sPath = "./csgo/materials/skybox/" .. tostring(tSkyboxData.sPath) .. "up.vmt"
        local bIsFileExists = package_searchpath("", sPath) == sPath
        if bIsFileExists then
          multicolor_log({
            127,
            255,
            0,
            " + "
          }, {
            255,
            255,
            255,
            "Found ["
          }, {
            0,
            255,
            255,
            "materials\\skybox\\" .. tostring(tSkyboxData.sPath) .. "up.vmt"
          }, {
            255,
            255,
            255,
            "]"
          })
        else
          multicolor_log({
            255,
            127,
            0,
            " - "
          }, {
            255,
            255,
            255,
            "Not Found ["
          }, {
            0,
            255,
            255,
            "materials\\skybox\\" .. tostring(tSkyboxData.sPath) .. "up.vmt"
          }, {
            255,
            255,
            255,
            "] ("
          }, {
            0,
            255,
            255,
            "No such file!"
          }, {
            255,
            255,
            255,
            ")"
          })
        end
        return bIsFileExists
      else
        return true
      end
    end)() then
      _accum_0[_len_0] = tSkyboxData
      _len_0 = _len_0 + 1
    end
  end
  tSkyboxList = _accum_0
end
table.sort(tSkyboxList, function(tA, tB)
  return tA.sName < tB.sName
end)
local tScriptData = {
  tMenuReferences = {
    nPadding = ui.new_label("LUA", "A", "\nSet Skybox"),
    nMasterSwitch = ui.new_checkbox("LUA", "A", "Set Skybox"),
    nSkyboxColor = ui.new_color_picker("LUA", "A", "Color\nSet Skybox", 255, 255, 255, 255),
    nSkyboxList = ui.new_listbox("LUA", "A", "List\nSet Skybox", (function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #tSkyboxList do
        local tSkyboxData = tSkyboxList[_index_0]
        _accum_0[_len_0] = tSkyboxData.sName
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)()),
    nSkyboxColorChangeDelay = ui.new_slider("LUA", "A", "Color Change Delay\nSet Skybox", 1, 5, 1, true, "s.", 1),
    nSkyboxCheckInterval = ui.new_slider("LUA", "A", "Check Inteval\nSet Skybox", 1, 5, 1, true, "s.", 1),
    nHide3dSkybox = ui.new_checkbox("LUA", "A", "Hide 3D Skybox\nSet Skybox")
  },
  tSkyboxIndexToPath = (function()
    local _tbl_0 = { }
    for nIterator1, tSkyboxData in ipairs(tSkyboxList) do
      _tbl_0[nIterator1] = tSkyboxData.sPath
    end
    return _tbl_0
  end)(),
  sSkyboxNameCustom = false,
  nSkyboxCheckTimestamp = 0
}
local tGameData = {
  udCvar_sv_skyname = cvar.sv_skyname,
  udCvar_r_3dsky = cvar.r_3dsky,
  sSkyboxNameDefault = false
}
local tScriptFunctions = {
  SetSkyboxName = function(bSetDefaultSkybox)
    if bSetDefaultSkybox and tGameData.sSkyboxNameDefault then
      if tGameData.udCvar_sv_skyname then
        return load_name_sky(tGameData.sSkyboxNameDefault)
      end
    else
      if tGameData.udCvar_sv_skyname then
        tScriptData.sSkyboxNameCustom = tScriptData.tSkyboxIndexToPath[ui_get(tScriptData.tMenuReferences.nSkyboxList) + 1]
        if tScriptData.sSkyboxNameCustom then
          return load_name_sky(tScriptData.sSkyboxNameCustom)
        end
      end
    end
  end,
  SetSkyboxColor = function(nR, nG, nB, nA)
    local tCurrentSkyboxMaterials = materialsystem_find_materials("skybox/" .. tostring(tScriptData.sSkyboxNameCustom))
    if tCurrentSkyboxMaterials then
      return client_delay_call(#tCurrentSkyboxMaterials == 0 and ui_get(tScriptData.tMenuReferences.nSkyboxColorChangeDelay) or 0, (function()
        local tMaterials = materialsystem_find_materials("skybox/")
        if tMaterials then
          for _index_0 = 1, #tMaterials do
            local udMaterial = tMaterials[_index_0]
            udMaterial:color_modulate(nR, nG, nB)
            udMaterial:alpha_modulate(nA)
          end
        end
      end))
    end
  end,
  CheckSkyboxName = function()
    local sSkyboxNameCurrent = tGameData.udCvar_sv_skyname:get_string()
    if tScriptData.sSkyboxNameCustom and sSkyboxNameCurrent ~= tScriptData.sSkyboxNameCustom then
      return load_name_sky(tScriptData.sSkyboxNameCustom)
    end
  end
}
local tScriptEventCallbacks = {
  OnPlayerConnectFull = function(e)
    if client_userid_to_entindex(e.userid) == entity_get_local_player() then
      tGameData.sSkyboxNameDefault = tGameData.udCvar_sv_skyname:get_string()
    end
    if ui_get(tScriptData.tMenuReferences.nMasterSwitch) then
      tScriptFunctions.SetSkyboxName()
      local nR, nG, nB, nA = ui_get(tScriptData.tMenuReferences.nSkyboxColor)
      return tScriptFunctions.SetSkyboxColor(nR, nG, nB, nA)
    end
  end,
  OnPostConfigLoad = function()
    if entity_get_local_player() then
      tScriptFunctions.SetSkyboxName()
      local nR, nG, nB, nA = ui_get(tScriptData.tMenuReferences.nSkyboxColor)
      return tScriptFunctions.SetSkyboxColor(nR, nG, nB, nA)
    end
  end,
  OnPaint = function()
    local nCurrentTimestamp = globals_realtime()
    if nCurrentTimestamp - tScriptData.nSkyboxCheckTimestamp > ui_get(tScriptData.tMenuReferences.nSkyboxCheckInterval) then
      tScriptData.nSkyboxCheckTimestamp = nCurrentTimestamp
      if entity_get_local_player() then
        tScriptFunctions.SetSkyboxName()
        local nR, nG, nB, nA = ui_get(tScriptData.tMenuReferences.nSkyboxColor)
        return tScriptFunctions.SetSkyboxColor(nR, nG, nB, nA)
      end
    end
  end
}
ui_set_callback(tScriptData.tMenuReferences.nMasterSwitch, function(nUiElementReference)
  if ui_get(tScriptData.tMenuReferences.nMasterSwitch) then
    client_set_event_callback("player_connect_full", tScriptEventCallbacks.OnPlayerConnectFull)
    client_set_event_callback("post_config_load", tScriptEventCallbacks.OnPostConfigLoad)
    client_set_event_callback("paint", tScriptEventCallbacks.OnPaint)
    tScriptFunctions.SetSkyboxName()
    local nR, nG, nB, nA = ui_get(tScriptData.tMenuReferences.nSkyboxColor)
    return tScriptFunctions.SetSkyboxColor(nR, nG, nB, nA)
  else
    client_unset_event_callback("player_connect_full", tScriptEventCallbacks.OnPlayerConnectFull)
    client_unset_event_callback("post_config_load", tScriptEventCallbacks.OnPostConfigLoad)
    client_unset_event_callback("paint", tScriptEventCallbacks.OnPaint)
    tScriptFunctions.SetSkyboxName(true)
    return tScriptFunctions.SetSkyboxColor(255, 255, 255, 255)
  end
end)
ui_set_callback(tScriptData.tMenuReferences.nSkyboxColor, function(nUiElementReference)
  if ui_get(tScriptData.tMenuReferences.nMasterSwitch) then
    local nR, nG, nB, nA = ui_get(nUiElementReference)
    return tScriptFunctions.SetSkyboxColor(nR, nG, nB, nA)
  end
end)
ui_set_callback(tScriptData.tMenuReferences.nSkyboxList, function(nUiElementReference)
  tScriptData.sSkyboxNameCustom = tScriptData.tSkyboxIndexToPath[ui_get(tScriptData.tMenuReferences.nSkyboxList) + 1]
  if ui_get(tScriptData.tMenuReferences.nMasterSwitch) then
    tScriptFunctions.SetSkyboxName()
    local nR, nG, nB, nA = ui_get(tScriptData.tMenuReferences.nSkyboxColor)
    return tScriptFunctions.SetSkyboxColor(nR, nG, nB, nA)
  end
end)
ui_set_callback(tScriptData.tMenuReferences.nHide3dSkybox, function(nUiElementReference)
  if ui_get(nUiElementReference) then
    return tGameData.udCvar_r_3dsky:set_raw_int(0)
  else
    return tGameData.udCvar_r_3dsky:set_raw_int(1)
  end
end)
client_set_event_callback("shutdown", function()
  client_unset_event_callback("player_connect_full", tScriptEventCallbacks.OnPlayerConnectFull)
  client_unset_event_callback("post_config_load", tScriptEventCallbacks.OnPostConfigLoad)
  client_unset_event_callback("paint", tScriptEventCallbacks.OnPaint)
  tScriptFunctions.SetSkyboxName(true)
  return tScriptFunctions.SetSkyboxColor(255, 255, 255, 255)
end)
if tGameData.udCvar_sv_skyname then
  tGameData.sSkyboxNameDefault = tGameData.udCvar_sv_skyname:get_string()
  if ui_get(tScriptData.tMenuReferences.nMasterSwitch) then
    client_set_event_callback("player_connect_full", tScriptEventCallbacks.OnPlayerConnectFull)
    client_set_event_callback("post_config_load", tScriptEventCallbacks.OnPostConfigLoad)
    client_set_event_callback("paint", tScriptEventCallbacks.OnPaint)
    tScriptFunctions.SetSkyboxName()
    local nR, nG, nB, nA = ui_get(tScriptData.tMenuReferences.nSkyboxColor)
    return tScriptFunctions.SetSkyboxColor(nR, nG, nB, nA)
  end
end

end

local skybox_ok, skybox_error = pcall(setup_skybox)
if not skybox_ok then
    client.log("[skeet-tools] skybox unavailable: ", tostring(skybox_error))
end

-- Integrated arms changer (no sleeve, r_skin). Controls: SKINS > Model Options.
local function setup_arms_changer()

-- Made By Exodouding for skeet.cc/gamesense.pub

local skin_colors = {
    "White",
    "Black",
    "Brown",
    "Asian",
    "Mexican",
    "Tattoo"
}

local LastSelectedIndex = -1

local no_sleeve = ui.new_checkbox("Skins", "Model Options", "No Sleeve")

local PlayerSkinColor = ui.new_checkbox("Skins", "Model Options", "Player Skin Color")
local Skins = ui.new_combobox("Skins", "Model Options", "\n", skin_colors)
ui.set_visible(Skins, false)

ui.set_callback(PlayerSkinColor, function()

	local Result = ui.get(PlayerSkinColor)
	
	ui.set_visible(Skins, Result)
	
	if not Result then 
		client.set_cvar("r_skin", 0)
		LastSelectedIndex = -1
	end
	
end)

local function NoSleeve()

    local sleeve = materialsystem.find_materials("sleeve")
	
    for i=#sleeve, 1, -1 do
	
        if ui.get(no_sleeve) then
            sleeve[i]:set_material_var_flag(2, true)
        else
            sleeve[i]:set_material_var_flag(2, false)
        end
    end
end

local function SkinColor()

	if not ui.get(PlayerSkinColor) then 
		return
	end
	
	for i, v in pairs(skin_colors) do
		
		local SelectedSkin = ui.get(Skins, skin_colors)
		
		if SelectedSkin == skin_colors[i] and i ~= LastSelectedIndex then
			client.set_cvar("r_skin", i-1)
			-- print("Name : " .. v .. " | Skin ID : " .. i)
			LastSelectedIndex = i
		end
	end
end

local function Main()
	NoSleeve()
	SkinColor()
end

client.set_event_callback("paint", Main)

end

local arms_changer_ok, arms_changer_error = pcall(setup_arms_changer)
if not arms_changer_ok then
    client.log("[skeet-tools] arms_changer unavailable: ", tostring(arms_changer_error))
end
