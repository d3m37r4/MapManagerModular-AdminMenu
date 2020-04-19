#include <amxmodx>
#include <map_manager>
#include <map_manager_scheduler>

new const ADMIN_MAPLIST[]   = "admin_maps.ini";       // Map list for menu formation (only map name is indicated in line, without indicating online)
const FLAG_ACCESS_CHANGEMAP = ADMIN_MAP;              // Flag for access to map change commands
const FLAG_ACCESS_VOTEMAP   = ADMIN_VOTE;             // Flag for access to commands for creating a vote for a map change

const VOTE_BY_ADMIN_MENU    = 4;
const MAX_ITEMS_MENU        = 6;

enum {
    MenuKeyConfirm = 6, 
    MenuKeyBack,
    MenuKeyNext,
    MenuKeyExit
};

enum {
    ChangeMapMenu, 
    VoteMapMenu
};

enum InfoList {
    MenuType,
    MenuPos,
    MenuId,
    MenuUserId
};

enum StateType { 
    StateNone = -1,
    StateSelect
};

enum CvarList {
    Delay,
}

new Array:g_MapList, Array:g_VoteList, Array:g_MainMapList;
new g_LoadedMaps, g_VoteItems;

new g_MenuInfo[InfoList];
new StateType:g_State = StateNone;
new g_EventNewRound;

new g_LastRound;
new g_NextMap[MAPNAME_LENGTH];
new g_Prefix[48];

new g_Cvar[CvarList];
new g_MapStartTime;

#if AMXX_VERSION_NUM < 200
    new MapName[MAPNAME_LENGTH];
#endif

public plugin_init() {
    register_plugin("Admin Mapmenu", "0.5.2", "d3m37r4");

    RegisterCmd();
    RegisterBlockCmd();

    bind_pcvar_num(create_cvar(
        .name = "mapm_mapmenu_delay", 
        .string = "0",
        .flags = FCVAR_SERVER,
        .has_min = true,
        .min_val = 0.0)
    , g_Cvar[Delay]);

    register_dictionary("admin_mapmenu.txt");
    if(register_dictionary("mapmanager.txt") != -1) {
        set_fail_state("failed to open dictionary file 'mapmanager.txt', check its availability");
    }

    register_menucmd(g_MenuInfo[MenuId] = register_menuid("MapMenu"), 1023, "HandleMapMenu");
    disable_event(g_EventNewRound = register_event("HLTV", "EventNewRound", "a", "1=0", "2=0"));

#if AMXX_VERSION_NUM < 200
    get_mapname(MapName, charsmax(MapName));
#endif

    g_MapStartTime = get_systime();
}

public plugin_cfg() {
    g_MapList = ArrayCreate(MAPNAME_LENGTH);
    g_VoteList = ArrayCreate(MAPNAME_LENGTH);

    new filename[32];
    copy(filename, charsmax(filename), ADMIN_MAPLIST);

    if(!mapm_load_maplist_to_array(g_MapList, filename)) {
        ArrayDestroy(g_MapList);
        ArrayDestroy(g_VoteList);
        set_fail_state("nothing loaded from '%s'", filename);
    }

    if(g_MapList) {
        g_LoadedMaps = ArraySize(g_MapList);
    }

    bind_pcvar_num(get_cvar_pointer("mapm_last_round"), g_LastRound);
    mapm_get_prefix(g_Prefix, charsmax(g_Prefix));
}

public CmdSay(const id) {
    if(!is_vote_started() && !is_vote_finished() && !is_vote_will_in_next_round()) {
        return PLUGIN_CONTINUE;
    }

    new text[MAPNAME_LENGTH]; read_args(text, charsmax(text));
    remove_quotes(text); trim(text); strtolower(text);
    
    if(is_string_with_space(text)) {
        return PLUGIN_CONTINUE;
    }

    new bool:nomination = false;
    new map_index = mapm_get_map_index(text);
    if(map_index != INVALID_MAP_INDEX) {
        nomination = true;
    } else if(strlen(text) >= 4) {
        map_index = __FindSimilarMapByString(text, g_MainMapList);
        if(map_index != INVALID_MAP_INDEX ) {
            nomination = true;
        }
    }

    if(nomination) {
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public CmdBlock(const id) {
    if(is_vote_started() || is_vote_finished() || is_vote_will_in_next_round()) {
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public CmdChangeMap(const id, const flags) {
    if(!CmdEnabled(id, flags, true)) {
        return PLUGIN_HANDLED; 
    }

    if(read_argc() != 2) {
        console_print(id, "%l", "INVALID_CMD_SYNTAX");
        console_print(id, "%l: amx_changemap <map>", "USAGE_EXAMPLE");
        return PLUGIN_HANDLED;
    }

    new map[MAPNAME_LENGTH];
    read_argv(1, map, charsmax(map));

    if(equali(map, MapName)) {
        console_print(id, "%l!", "ERR_THIS_CURR_MAP");
        return PLUGIN_HANDLED;
    }

    if(!MapInArray(map, g_MainMapList) && !MapInArray(map, g_MapList)) {
        console_print(id, "%l", "ERR_NO_IN_MAPLIST", map);
        return PLUGIN_HANDLED;
    }

    ChangeMap(id, map);
    return PLUGIN_HANDLED;  
}

public CmdVoteMap(const id, const flags) {
    if(!CmdEnabled(id, flags, true)) {
        return PLUGIN_HANDLED; 
    }

    new argc = read_argc();
    new max_items = mapm_get_votelist_size();

    if(argc < 2 || max_items + 1 < argc) {
        console_print(id, "%l", "INVALID_CMD_SYNTAX");
        console_print(id, "%l: %d", "MAX_ITEMS_IN_VOTE", max_items);
        console_print(id, "%l: amx_votemap <map1> <map2> ...", "USAGE_EXAMPLE");
        return PLUGIN_HANDLED;
    }

    g_VoteItems = 0;
    max_items = (argc - 1);

    for(new i, map[MAPNAME_LENGTH]; i < max_items; i++) {
        read_argv(i + 1, map, charsmax(map));
        if(map[0] == EOS) {
            continue;
        }

        if(equali(map, MapName)) {
            console_print(id, "%l (arg #%d)!", "ERR_THIS_CURR_MAP", i + 1);
            continue;
        }

        if(!MapInArray(map, g_MainMapList) && !MapInArray(map, g_MapList)) {
            console_print(id, "%l (arg #%d)!", "ERR_NO_IN_MAPLIST", map, i + 1);
            continue;
        }
        
        if(MapInArray(map, g_VoteList)) {
            console_print(id, "%l (arg #%d)!", "ERR_MAP_DUPLICATED", map, i + 1);
            continue;   
        }

        ArrayPushString(g_VoteList, map);
        g_VoteItems++;
    }

    if(g_VoteItems) {
        StartVote(id);
    } else {
        console_print(id, "%l", "ERR_VOTE_FAILED");
    }

    return PLUGIN_HANDLED;  
}

public CmdChangeMapMenu(const id, const flags) {
    if(!CmdEnabled(id, flags)) {
        return PLUGIN_HANDLED; 
    }

    OpenMapMenu(id, ChangeMapMenu);
    return PLUGIN_HANDLED;     
}

public CmdVoteMapMenu(const id, const flags) {
    if(!CmdEnabled(id, flags)) {
        return PLUGIN_HANDLED; 
    }

    OpenMapMenu(id, VoteMapMenu);
    return PLUGIN_HANDLED;   
}

OpenMapMenu(const id, const menuid) {
    if(g_State == StateNone) {
        g_MenuInfo[MenuPos] = 0;
        g_MenuInfo[MenuType] = menuid;
        g_MenuInfo[MenuUserId] = id;
        g_State = StateSelect;
        ShowMapMenu(id);
    }

    if(g_State == StateSelect) {
        new bool:menu_open, menu_index, dummy;
        for(new player = 1; player <= MaxClients; player++) {
            if(!is_user_connected(player)) {
                continue;
            }

            player_menu_info(player, menu_index, dummy);
            if(g_MenuInfo[MenuId] != menu_index) {
                continue;
            }

            menu_open = true;
            break;
        }

        if(!menu_open) {
            ClearData();
        }
    }
}

ShowMapMenu(const id, const page = 0) {
    new start, end;
    new current = GetMenuPage(page, g_LoadedMaps, MAX_ITEMS_MENU, start, end);
    new pages = GetMenuPagesNum(g_LoadedMaps, MAX_ITEMS_MENU);
    new max_items = g_MenuInfo[MenuType] == VoteMapMenu ? mapm_get_votelist_size() : 1;

    SetGlobalTransTarget(id);

    new menu[MAX_MENU_LENGTH];
    new len = formatex(menu, charsmax(menu), "%l", g_MenuInfo[MenuType] == VoteMapMenu ? "VOTEMAP_MENU_TITLE" : "CHANGEMAP_MENU_TITLE");

    len += formatex(menu[len], charsmax(menu) - len, " \y%d/%d^n", current + 1, pages + 1);
    len += formatex(menu[len], charsmax(menu) - len, "%l \y%d/%d^n^n", "SELECTED_MAPS", g_VoteItems, max_items);

    new keys = MENU_KEY_0;
    for(new i = start, item, map_name[MAPNAME_LENGTH]; i < end; i++) {
        ArrayGetString(g_MapList, i, map_name, charsmax(map_name));

        keys |= (1 << item);
        len += formatex(menu[len], charsmax(menu) - len, MapInArray(map_name, g_VoteList) ?
        "\d%d. %s \y[\r*\y]^n" : "\r%d. \w%s^n", ++item, map_name);
    }

    new tmp[15];
    setc(tmp, MAX_ITEMS_MENU - (end - start) + 1, '^n');
    len += copy(menu[len], charsmax(menu) - len, tmp);

    if(g_VoteItems) {
        keys |= MENU_KEY_7;
        len += formatex(menu[len], charsmax(menu) - len, "\r7. \w%l^n", g_MenuInfo[MenuType] == VoteMapMenu ? 
        "MENUKEY_CREATE_VOTE" : "MENUKEY_CONFIRM_SELECTION");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "\d7. %l^n", g_MenuInfo[MenuType] == VoteMapMenu ?
        "MENUKEY_CREATE_VOTE" : "MENUKEY_CONFIRM_SELECTION");
    }

    if(g_MenuInfo[MenuPos] != 0) {
        keys |= MENU_KEY_8;
        len += formatex(menu[len], charsmax(menu) - len, "^n\r8. \w%l", "MAPM_MENU_BACK");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "^n\d8. %l", "MAPM_MENU_BACK");
    }

    if(end < g_LoadedMaps) {
        keys |= MENU_KEY_9;
        len += formatex(menu[len], charsmax(menu) - len, "^n\r9. \w%l", "MAPM_MENU_NEXT");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "^n\d9. %l", "MAPM_MENU_NEXT");
    }

    formatex(menu[len], charsmax(menu) - len, "^n\r0. \w%l", "MAPM_MENU_EXIT");
    show_menu(id, keys, menu, -1, "MapMenu");
}

public HandleMapMenu(const id, const key) {
    new max_items = g_MenuInfo[MenuType] == VoteMapMenu ? mapm_get_votelist_size() : 1;
    switch(key) {
        case MenuKeyConfirm: {
            if(g_MenuInfo[MenuType] == VoteMapMenu) {
                StartVote(id);             
            } else {
                ArrayGetString(g_VoteList, 0, g_NextMap, charsmax(g_NextMap));
                ChangeMap(id, g_NextMap);
            }
        }
        case MenuKeyBack: {
            ShowMapMenu(id, --g_MenuInfo[MenuPos]);
        }
        case MenuKeyNext: {
            ShowMapMenu(id, ++g_MenuInfo[MenuPos]);
        }
        case MenuKeyExit: {
            ClearData();
        }
        default: {
            new map_name[MAPNAME_LENGTH];
            ArrayGetString(g_MapList, g_MenuInfo[MenuPos] * MAX_ITEMS_MENU + key, map_name, charsmax(map_name));

            new map_index = ArrayFindString(g_VoteList, map_name);
            if(map_index == INVALID_MAP_INDEX) {
                if(g_VoteItems != max_items) {
                    ArrayPushString(g_VoteList, map_name);
                    g_VoteItems++;
                }
            } else {
                ArrayDeleteItem(g_VoteList, map_index);
                g_VoteItems--;
            }
           
            ShowMapMenu(id, g_MenuInfo[MenuPos]);
        }
    }
}

public EventNewRound() {
    client_print_color(0, print_team_default, "%s %l ^4%s^1.", g_Prefix, "MAPM_NEXTMAP", g_NextMap);
    intermission();
}

public mapm_maplist_loaded(Array:maplist) {
    g_MainMapList = ArrayClone(maplist);
}

public mapm_prepare_votelist(type) { 
    if(type != VOTE_BY_ADMIN_MENU) {
        return;
    }

    for(new i, map_name[MAPNAME_LENGTH]; i < g_VoteItems; i++) {
        ArrayGetString(g_VoteList, i, map_name, charsmax(map_name));
        mapm_push_map_to_votelist(map_name, PUSH_BY_NATIVE, CHECK_IGNORE_MAP_ALLOWED);
    }

    mapm_set_votelist_max_items(g_VoteItems);
    ClearData();
}

bool:CmdEnabled(const index, const flags, bool:console = false) {
    if(~get_user_flags(index) & flags) {
        console_print(index, "%l", "ERR_ACCESS_DENIED");
        return false;
    }

    static message[190];

    new delay = g_Cvar[Delay] * 60 - (get_systime() - g_MapStartTime);
    if(delay > 0) {
        console ? __ConsolePrintEx(index, "* %l", "DELAY_CMD", delay / 60, delay % 60) : 
        client_print_color(index, print_team_default, "%s %l", g_Prefix, "DELAY_CMD", delay / 60, delay % 60);
        return false;
    }

    if(is_vote_started()) {
        console ? __ConsolePrintEx(index, "* %l", "VOTE_STARTED") : client_print_color(index, print_team_default, "%s %l", g_Prefix, "VOTE_STARTED");
        return false;
    }

    if(is_vote_will_in_next_round()) {
        console ? __ConsolePrintEx(index, "* %l", "VOTE_IN_NEXT_ROUND") : client_print_color(index, print_team_default, "%s %l", g_Prefix, "VOTE_IN_NEXT_ROUND");
        return false;
    }

    if(is_last_round()) {
        get_cvar_string("amx_nextmap", g_NextMap, charsmax(g_NextMap));
        console ? __ConsolePrintEx(index, "* %l", "MAP_DEFINED", g_NextMap) : 
        client_print_color(index, print_team_default, "%s %l", g_Prefix, "MAP_DEFINED", g_NextMap);
        return false;        
    }

    if(g_State == StateSelect && g_MenuInfo[MenuUserId] != index) {
        new name[MAX_NAME_LENGTH];
        get_user_name(g_MenuInfo[MenuUserId], name, charsmax(name));

        formatex(message, charsmax(message), "%l", "MENU_STATE_SELECT",  
        g_MenuInfo[MenuUserId] ? name : "Server", g_MenuInfo[MenuType] == VoteMapMenu ? "MAPS" : "MAP");

        console ? __ConsolePrintEx(index, "* %s", message) : client_print_color(index, print_team_default, "%s %s", g_Prefix, message);
        return false;
    }

    return true;
}

ChangeMap(const index, map[]) {
    new name[MAX_NAME_LENGTH];
    get_user_name(index, name, charsmax(name));

    copy(g_NextMap, charsmax(g_NextMap), map);
    set_cvar_string("amx_nextmap", g_NextMap);

    client_print_color(0, print_team_default, "%s %l", g_Prefix, "STATE_CHANGELEVEL", index ? name : "Server", g_NextMap);
    if(g_LastRound) {
        enable_event(g_EventNewRound);
        client_print_color(0, print_team_default, "%s %l", g_Prefix, "MAPM_CHANGELEVEL_NEXTROUND");
    } else {
        intermission();
    }

    log_amx("Map change was started by %n", index);
}

StartVote(const index) {
    new name[MAX_NAME_LENGTH];
    get_user_name(index, name, charsmax(name));

    client_print_color(0, print_team_default, "%s %l", g_Prefix, "STATE_CREATE_VOTE", index ? name : "Server");
    map_scheduler_start_vote(VOTE_BY_ADMIN_MENU);

    log_amx("Map change vote was created by %n", index);
}

RegisterCmd() {
    register_concmd("amx_changemap", "CmdChangeMap", FLAG_ACCESS_CHANGEMAP);
    register_clcmd("amx_changemap_menu", "CmdChangeMapMenu", FLAG_ACCESS_CHANGEMAP);

    register_concmd("amx_votemap", "CmdVoteMap", FLAG_ACCESS_VOTEMAP);
    register_clcmd("amx_votemap_menu", "CmdVoteMapMenu", FLAG_ACCESS_VOTEMAP);
}

RegisterBlockCmd() {
    register_clcmd("say", "CmdSay");
    register_clcmd("say_team", "CmdSay");

    register_clcmd("say rtv", "CmdBlock");
    register_clcmd("say /rtv", "CmdBlock");
    register_clcmd("say maps", "CmdBlock");
    register_clcmd("say /maps", "CmdBlock");
}

GetMenuPage(cur_page, elements_num, per_page, &start, &end) {
    new max = min(cur_page * per_page, elements_num);
    start = max - (max % MAX_ITEMS_MENU);
    end = min(start + per_page, elements_num);
    return start / per_page;
}

GetMenuPagesNum(elements_num, per_page) {
    return (elements_num - 1) / per_page;
}

ClearData() {
    g_State = StateNone;
    g_VoteItems = 0;
    g_NextMap[0] = EOS;
    g_MenuInfo[MenuUserId] = 0;
    ArrayClear(g_VoteList);
}

__FindSimilarMapByString(string[MAPNAME_LENGTH], Array:maplist) {
    if(maplist == Invalid_Array) {
        return INVALID_MAP_INDEX;
    }

    new map_info[MapStruct], end = ArraySize(maplist);
    for(new i; i < end; i++) {
        ArrayGetArray(maplist, i, map_info);
        if(containi(map_info[Map], string) != -1) {
            return i;
        }
    }

    return INVALID_MAP_INDEX;
}

bool:MapInArray(map[], Array:arr) {
    return bool:(ArrayFindString(arr, map) != INVALID_MAP_INDEX);
}

stock __ConsolePrintEx(const index, const message[], any:...) {
    static _string[126];
    vformat(_string, charsmax(_string), message, 3);

    static const color_tags[][] = { "^1", "^3", "^4" };
    for(new i; i < sizeof color_tags; i++) {
        replace_string(_string, charsmax(_string), color_tags[i], "", false);
    }

    console_print(index, _string);
}