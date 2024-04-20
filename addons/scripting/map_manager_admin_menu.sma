#include <amxmodx>
#include <map_manager>
#include <map_manager_scheduler>

#pragma semicolon 1

const ACCESS_CHANGEMAP          = ADMIN_MAP;        // Flag for access to map change commands
const ACCESS_VOTEMAP            = ADMIN_VOTE;       // Flag for access to commands for creating a vote for a map change

const CHANGE_NEXT_ROUND         = 1;
const FREEZE_TIME_ENABLED       = 1;
const VOTE_BY_ADMIN_MENU        = 4;
const MAX_ITEMS_MENU            = 6;

enum {
    MENU_KEY_CONFIRM = 6, 
    MENU_KEY_BACK,
    MENU_KEY_NEXT,
    MENU_KEY_EXIT
};

enum {
    CHANGEMAP, 
    VOTEMAP
};

enum { 
    STATE_NONE,
    STATE_SELECT
};

enum Data {
    TYPE,
    POS,
    INDEX,
    USER,
    STATE
};

enum Cvars {
    NEXTMAP,
    FREEZETIME,
    VOTE_IN_NEW_ROUND,
    LAST_ROUND,
    PREPARE_TIME,
    VOTE_TIME,
    FREEZE_IN_VOTE,
    CHATTIME,
    MAPLIST,
    DELAY,
};

new Pcvar[Cvars];

new Array:MapList;
new Array:VoteList;
new Array:MainMapList;

new LoadedMaps, VoteItems;

new Menu[Data];

new EventNewRound;

new CurrentMap[MAPNAME_LENGTH];
new NextMap[MAPNAME_LENGTH];
new Prefix[48];

new MapStartTime;

#if !defined is_last_round
    #define is_last_round()     get_last_round_state() == LRS_Last
#endif

#define get_num(%0)             get_pcvar_num(Pcvar[%0])
#define get_float(%0)           get_pcvar_float(Pcvar[%0])
#define set_float(%0,%1)        set_pcvar_float(Pcvar[%0],%1)
#define get_string(%0,%1,%2)    get_pcvar_string(Pcvar[%0],%1,%2)
#define set_string(%0,%1)       set_pcvar_string(Pcvar[%0],%1)

public plugin_init()
{
    register_plugin("Map Manager: Admin menu", "0.6.3", "d3m37r4");

    registerCommands();
    registerCommandsForBlocking();
    registerDictionaryFiles();
    registerCvars();

    register_menucmd(Menu[INDEX] = register_menuid("AdminMapMenu"), 1023, "handleAdminMapMenu");
    disable_event(EventNewRound = register_event("HLTV", "eventNewRound", "a", "1=0", "2=0"));

    MapStartTime = get_systime();
}

public plugin_cfg()
{
    MapList = ArrayCreate(MAPNAME_LENGTH);
    VoteList = ArrayCreate(MAPNAME_LENGTH);

    new file[32];
    get_string(MAPLIST, file, charsmax(file));

    if(!file[0]) {
        loadMapsFromDir("maps", MapList);
    } else {
        loadMapsFromFile(file, MapList);
    }

    if(MapList) {
        LoadedMaps = ArraySize(MapList);
    }

    Pcvar[NEXTMAP] = get_cvar_pointer("amx_nextmap");
    Pcvar[FREEZETIME] = get_cvar_pointer("mp_freezetime");
    Pcvar[VOTE_IN_NEW_ROUND] = get_cvar_pointer("mapm_vote_in_new_round");
    Pcvar[LAST_ROUND] = get_cvar_pointer("mapm_last_round");
    Pcvar[PREPARE_TIME] = get_cvar_pointer("mapm_prepare_time");
    Pcvar[VOTE_TIME] = get_cvar_pointer("mapm_vote_time");
    Pcvar[FREEZE_IN_VOTE] = get_cvar_pointer("mapm_freeze_in_vote");
    Pcvar[CHATTIME] = get_cvar_pointer("mp_chattime");

    get_mapname(CurrentMap, charsmax(CurrentMap));
    mapm_get_prefix(Prefix, charsmax(Prefix));
}

public plugin_end()
{
    restoreFreezeTime();
}

public clcmdSay(const id)
{
    if(!is_vote_started() && !is_vote_finished() && !is_vote_will_in_next_round()) {
        return PLUGIN_CONTINUE;
    }

    new mapname[MAPNAME_LENGTH]; read_args(mapname, charsmax(mapname));
    remove_quotes(mapname); trim(mapname); strtolower(mapname);
    
    if(is_string_with_space(mapname)) {
        return PLUGIN_CONTINUE;
    }

    if(mapCanBeNominated(mapname)) {
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

public cmdBlocked(const id)
{
    return bool:(is_vote_started() || is_vote_finished() || is_vote_will_in_next_round()) ? PLUGIN_HANDLED : PLUGIN_CONTINUE;
}

public concmdChangeMap(const id, const flags)
{
    if(!commandAvailable(id, flags, true)) {
        return PLUGIN_HANDLED; 
    }

    if(read_argc() != 2) {
        console_print(id, "%l", "MAPM_ADM_CMD_INVALID_SYNTAX");
        console_print(id, "%l: amx_changemap <map>", "MAPM_ADM_USAGE_EXAMPLE");

        return PLUGIN_HANDLED;
    }

    new mapname[MAPNAME_LENGTH];
    read_argv(1, mapname, charsmax(mapname));

    if(equali(mapname, CurrentMap)) {
        console_print(id, "%l", "MAPM_ADM_CANT_BE_CHANGET_TO_THE_CURRENT_MAP");

        return PLUGIN_HANDLED;
    }

    if(!arrayContainsMap(MainMapList, mapname) && !arrayContainsMap(MapList, mapname)) {
        console_print(id, "%l", "MAPM_ADM_MAP_NOT_IN_MAPLIST", mapname);

        return PLUGIN_HANDLED;
    }

    changeMap(id, mapname);

    return PLUGIN_HANDLED;  
}

public concmdVoteMap(const id, const flags)
{
    if(!commandAvailable(id, flags, true)) {
        return PLUGIN_HANDLED; 
    }

    new argc = read_argc();
    new max_items = mapm_get_votelist_size();

    if(argc < 2 || max_items + 1 < argc) {
        console_print(id, "%l", "MAPM_ADM_CMD_INVALID_SYNTAX");
        console_print(id, "%l: %d", "MAPM_ADM_MAX_ITEMS_IN_VOTE", max_items);
        console_print(id, "%l: amx_votemap <map1> <map2> ...", "MAPM_ADM_USAGE_EXAMPLE");

        return PLUGIN_HANDLED;
    }

    VoteItems = 0;
    max_items = (argc - 1);

    for(new i, mapname[MAPNAME_LENGTH]; i < max_items; i++) {
        read_argv(i + 1, mapname, charsmax(mapname));

        if(mapname[0] == EOS) {
            continue;
        }

        if(equali(mapname, CurrentMap)) {
            console_print(id, "%l (arg #%d)", "MAPM_ADM_CANT_BE_CHANGET_TO_THE_CURRENT_MAP", i + 1);

            continue;
        }

        if(!arrayContainsMap(MainMapList, mapname) && !arrayContainsMap(MapList, mapname)) {
            console_print(id, "%l (arg #%d)", "MAPM_ADM_MAP_NOT_IN_MAPLIST", mapname, i + 1);

            continue;
        }
        
        if(arrayContainsMap(VoteList,  mapname)) {
            console_print(id, "%l (arg #%d)", "MAPM_ADM_MAP_ALREADY_IN_VOTELIST", mapname, i + 1);

            continue;
        }

        ArrayPushString(VoteList, mapname);
        VoteItems++;
    }

    VoteItems ? createVoteMap(id) : console_print(id, "%l", "MAPM_ADM_ERR_VOTE_FAILED");

    return PLUGIN_HANDLED;  
}

public clcmdChangeMapMenu(const id, const flags)
{
    if(!commandAvailable(id, flags)) {
        return PLUGIN_HANDLED; 
    }

    showAdminMapMenu(id, CHANGEMAP);

    return PLUGIN_HANDLED;     
}

public clcmdVoteMapMenu(const id, const flags)
{
    if(!commandAvailable(id, flags)) {
        return PLUGIN_HANDLED; 
    }

    showAdminMapMenu(id, VOTEMAP);

    return PLUGIN_HANDLED;   
}

showAdminMapMenu(const id, const menuid)
{
    if(Menu[STATE] == STATE_SELECT) {
        new bool:menu_open, menu_index, dummy;

        for(new player = 1; player <= MaxClients; player++) {
            if(!is_user_connected(player)) {
                continue;
            }

            player_menu_info(player, menu_index, dummy);

            if(Menu[INDEX] != menu_index) {
                continue;
            }

            menu_open = true;

            break;
        }

        if(!menu_open) {
            resetData();
        }
    }

    if(Menu[STATE] == STATE_NONE) {
        Menu[POS] = 0;
        Menu[TYPE] = menuid;
        Menu[USER] = id;
        Menu[STATE] = STATE_SELECT;
        renderAdminMapMenu(id);
    }
}

renderAdminMapMenu(const id, const page = 0)
{
    new start, end;
    new current = getCurrentMenuPage(page, LoadedMaps, MAX_ITEMS_MENU, start, end);
    new pages = getLastMenuPage(LoadedMaps, MAX_ITEMS_MENU);
    new max_items = (Menu[TYPE] == VOTEMAP) ? mapm_get_votelist_size() : 1;

    SetGlobalTransTarget(id);

    new menu[MAX_MENU_LENGTH];
    new len = formatex(menu, charsmax(menu), "%l", Menu[TYPE] == VOTEMAP ? "MAPM_ADM_MENU_TITLE_VOTEMAP" : "MAPM_ADM_MENU_TITLE_CHANGEMAP");

    len += formatex(menu[len], charsmax(menu) - len, " \y%d/%d^n", current + 1, pages + 1);
    len += formatex(menu[len], charsmax(menu) - len, "%l \y%d/%d^n^n", "MAPM_ADM_MENU_SELECTED_MAPS", VoteItems, max_items);

    new keys = MENU_KEY_0;

    for(new i = start, item, mapname[MAPNAME_LENGTH]; i < end; i++) {
        ArrayGetString(MapList, i, mapname, charsmax(mapname));

        keys |= (1 << item);
        len += formatex(menu[len], charsmax(menu) - len, arrayContainsMap(VoteList, mapname) ?
        "\d%d. %s \y[\r*\y]^n" : "\r%d. \w%s^n", ++item, mapname);
    }

    new tmp[15];
    setc(tmp, MAX_ITEMS_MENU - (end - start) + 1, '^n');
    len += copy(menu[len], charsmax(menu) - len, tmp);

    if(VoteItems) {
        keys |= MENU_KEY_7;
        len += formatex(menu[len], charsmax(menu) - len, "\r7. \w%l^n", Menu[TYPE] == VOTEMAP ? 
        "MAPM_ADM_MENU_CREATE_VOTE" : "MAPM_ADM_MENU_CONFIRM_SELECTION");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "\d7. %l^n", Menu[TYPE] == VOTEMAP ?
        "MAPM_ADM_MENU_CREATE_VOTE" : "MAPM_ADM_MENU_CONFIRM_SELECTION");
    }

    if(Menu[POS] != 0) {
        keys |= MENU_KEY_8;
        len += formatex(menu[len], charsmax(menu) - len, "^n\r8. \w%l", "MAPM_MENU_BACK");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "^n\d8. %l", "MAPM_MENU_BACK");
    }

    if(end < LoadedMaps) {
        keys |= MENU_KEY_9;
        len += formatex(menu[len], charsmax(menu) - len, "^n\r9. \w%l", "MAPM_MENU_NEXT");
    } else {
        len += formatex(menu[len], charsmax(menu) - len, "^n\d9. %l", "MAPM_MENU_NEXT");
    }

    formatex(menu[len], charsmax(menu) - len, "^n\r0. \w%l", "MAPM_MENU_EXIT");
    show_menu(id, keys, menu, -1, "AdminMapMenu");
}

public handleAdminMapMenu(const id, const key)
{
    new max_items = (Menu[TYPE] == VOTEMAP) ? mapm_get_votelist_size() : 1;

    switch(key) {
        case MENU_KEY_CONFIRM: {
            if(Menu[TYPE] == VOTEMAP) {
                createVoteMap(id);             
            } else {
                ArrayGetString(VoteList, 0, NextMap, charsmax(NextMap));
                changeMap(id, NextMap);
            }
        }
        case MENU_KEY_BACK: {
            renderAdminMapMenu(id, --Menu[POS]);
        }
        case MENU_KEY_NEXT: {
            renderAdminMapMenu(id, ++Menu[POS]);
        }
        case MENU_KEY_EXIT: {
            resetData();
        }
        default: {
            new mapname[MAPNAME_LENGTH];
            ArrayGetString(MapList, Menu[POS] * MAX_ITEMS_MENU + key, mapname, charsmax(mapname));

            new map_index = getMapFromArray(VoteList, mapname);

            if(map_index == INVALID_MAP_INDEX) {
                if(VoteItems != max_items) {
                    ArrayPushString(VoteList, mapname);
                    VoteItems++;
                }
            } else {
                ArrayDeleteItem(VoteList, map_index);
                VoteItems--;
            }
           
            renderAdminMapMenu(id, Menu[POS]);
        }
    }
}

public eventNewRound()
{
    client_print_color(0, print_team_default, "%s ^1%l %s^1.", Prefix, "MAPM_NEXTMAP", NextMap);
    intermission();
}

public mapm_maplist_loaded(Array:maplist)
{
    MainMapList = ArrayClone(maplist);
}

public mapm_prepare_votelist(type)
{ 
    if(type != VOTE_BY_ADMIN_MENU) {
        return;
    }

    changeFreezeTime();

    for(new i, mapname[MAPNAME_LENGTH]; i < VoteItems; i++) {
        ArrayGetString(VoteList, i, mapname, charsmax(mapname));
        mapm_push_map_to_votelist(mapname, PUSH_BY_NATIVE, CHECK_IGNORE_MAP_ALLOWED);
    }

    mapm_set_votelist_max_items(VoteItems);
    resetData();
}

public mapm_vote_finished(const map[], type, total_votes)
{
    if(type != VOTE_BY_ADMIN_MENU) {
        return;
    }

    restoreFreezeTime();
}

public mapm_vote_canceled(type)
{
    if(type != VOTE_BY_ADMIN_MENU) {
        return;
    }

    restoreFreezeTime();
    resetData();
}

bool:commandAvailable(const index, const flags, bool:console = false) {
    if(~get_user_flags(index) & flags) {
        console_print(index, "%l", "MAPM_ADM_ACCESS_DENIED");

        return false;
    }

    static message[190];

    new delay = get_num(DELAY) * 60 - (get_systime() - MapStartTime);
    if(delay > 0) {
        console ? consolePrintEx(index, "* %l", "MAPM_ADM_CMD_DELAY", delay / 60, delay % 60) : 
        client_print_color(index, print_team_default, "%s ^1%l", Prefix, "MAPM_ADM_CMD_DELAY", delay / 60, delay % 60);

        return false;
    }

    if(is_vote_started()) {
        console ? consolePrintEx(index, "* %l", "MAPM_ADM_VOTE_STARTED") : 
        client_print_color(index, print_team_default, "%s ^1%l", Prefix, "MAPM_ADM_VOTE_STARTED");

        return false;
    }

    if(is_vote_will_in_next_round()) {
        console ? consolePrintEx(index, "* %l", "MAPM_ADM_VOTE_IN_NEXT_ROUND") : 
        client_print_color(index, print_team_default, "%s ^1%l", Prefix, "MAPM_ADM_VOTE_IN_NEXT_ROUND");

        return false;
    }

    if(is_last_round()) {
        get_string(NEXTMAP, NextMap, charsmax(NextMap));

        console ? consolePrintEx(index, "* %l", "MAPM_ADM_MAP_DEFINED", NextMap) : 
        client_print_color(index, print_team_default, "%s ^1%l", Prefix, "MAPM_ADM_MAP_DEFINED", NextMap);

        return false;        
    }

    if(Menu[STATE] == STATE_SELECT && Menu[USER] != index) {
        new name[MAX_NAME_LENGTH];
        get_user_name(Menu[USER], name, charsmax(name));

        formatex(message, charsmax(message), "%l", "MAPM_ADM_MENU_STATE_SELECT",  
        Menu[USER] ? name : "Server", Menu[TYPE] == VOTEMAP ? "MAPM_ADM_MAPS" : "MAPM_ADM_MAP");

        console ? consolePrintEx(index, "* %s", message) : 
        client_print_color(index, print_team_default, "%s ^1%s", Prefix, message);

        return false;
    }

    return true;
}

changeMap(const index, mapname[]) {
    new name[MAX_NAME_LENGTH];
    get_user_name(index, name, charsmax(name));

    copy(NextMap, charsmax(NextMap), mapname);
    set_string(NEXTMAP, NextMap);

    client_print_color(0, print_team_default, "%s ^1%l", Prefix, "MAPM_ADM_CHANGELEVEL", index ? name : "Server", NextMap);

    if(get_num(LAST_ROUND)) {
        enable_event(EventNewRound);
        client_print_color(0, print_team_default, "%s ^1%l", Prefix, "MAPM_CHANGELEVEL_NEXTROUND");
    } else {
        client_print_color(0, print_team_default, "%s ^1%l %l.", Prefix, "MAPM_MAP_CHANGE", get_num(CHATTIME), "MAPM_SECONDS");
        intermission();
    }

    log_amx("Map change was started by %n", index);
}

createVoteMap(const index) {
    new name[MAX_NAME_LENGTH];
    get_user_name(index, name, charsmax(name));

    client_print_color(0, print_team_default, "%s ^1%l", Prefix, "MAPM_ADM_CREATE_VOTE", index ? name : "Server");
    map_scheduler_start_vote(VOTE_BY_ADMIN_MENU);

    log_amx("Map change vote was created by %n", index);
}

registerCommands()
{
    register_concmd("amx_changemap", "concmdChangeMap", ACCESS_CHANGEMAP);
    register_clcmd("amx_changemap_menu", "clcmdChangeMapMenu", ACCESS_CHANGEMAP);

    register_concmd("amx_votemap", "concmdVoteMap", ACCESS_VOTEMAP);
    register_clcmd("amx_votemap_menu", "clcmdVoteMapMenu", ACCESS_VOTEMAP);
}

registerCommandsForBlocking()
{
    register_clcmd("say", "clcmdSay");
    register_clcmd("say_team", "clcmdSay");

    register_clcmd("say rtv", "cmdBlocked");
    register_clcmd("say /rtv", "cmdBlocked");
    register_clcmd("say maps", "cmdBlocked");
    register_clcmd("say /maps", "cmdBlocked");
}

registerDictionaryFiles()
{
    if(register_dictionary("mapmanager.txt") != -1) {
        set_fail_state("Failed to open dictionary file 'mapmanager.txt', check its availability");
    }

    register_dictionary("mapmanager_admin_menu.txt");
}

registerCvars()
{
    Pcvar[MAPLIST] = create_cvar(
        .name = "mapm_admin_menu_maplist", 
        .string = "maps.ini",
        .flags = FCVAR_SERVER
    );
    Pcvar[DELAY] = create_cvar(
        .name = "mapm_admin_menu_delay", 
        .string = "1",
        .flags = FCVAR_SERVER,
        .has_min = true,
        .min_val = 0.0
    );
}

getCurrentMenuPage(cur_page, elements_num, per_page, &start, &end)
{
    new max = min(cur_page * per_page, elements_num);
    start = max - (max % MAX_ITEMS_MENU);
    end = min(start + per_page, elements_num);

    return start / per_page;
}

getLastMenuPage(elements_num, per_page)
{
    return (elements_num - 1) / per_page;
}

resetData()
{
    Menu[STATE] = STATE_NONE;
    VoteItems = 0;
    NextMap[0] = EOS;
    Menu[USER] = 0;
    ArrayClear(VoteList);
}

findSimilarMapByString(string[], Array:array)
{
    if(array == Invalid_Array) {
        return INVALID_MAP_INDEX;
    }

    new map_info[MapStruct], end = ArraySize(array);

    for(new i; i < end; i++) {
        ArrayGetArray(array, i, map_info);

        if(containi(map_info[Map], string) != -1) {
            return i;
        }
    }

    return INVALID_MAP_INDEX;
}

bool:mapCanBeNominated(mapname[])
{
    new map_index = mapm_get_map_index(mapname);

    if(map_index != INVALID_MAP_INDEX) {
        return true;
    } else if(strlen(mapname) >= 4) {
        map_index = findSimilarMapByString(mapname, MainMapList);

        if(map_index != INVALID_MAP_INDEX ) {
            return true;
        }
    }

    return false;
}

bool:arrayContainsMap(Array:which, mapname[])
{
    return bool:(getMapFromArray(which, mapname) != INVALID_MAP_INDEX);
}

getMapFromArray(Array:which, mapname[])
{
    static buffer[MAPNAME_LENGTH];

    for(new item, size = ArraySize(which); item < size; item++) {
        ArrayGetString(which, item, buffer, charsmax(buffer));

        if(equali(mapname, buffer)) {
            return item;
        }
    }

    return INVALID_MAP_INDEX;
}

loadMapsFromDir(dirname[], Array:which)
{
    static file[32], dir;

    dir = open_dir(dirname, file, charsmax(file));

    if(dir) {
        do {
            valid_map(file) && ArrayPushArray(which, file);
        } while (next_file(dir, file, charsmax(file)));

        close_dir(dir);
    }

    if(!ArraySize(which)) {
        set_fail_state("Nothing loaded from dir '%s'.", dirname);
    }
}

loadMapsFromFile(filename[], Array:which)
{
    if(!mapm_load_maplist_to_array(which, filename)) {
        set_fail_state("Nothing loaded from file '%s'.", filename);
    }
}

changeFreezeTime()
{
    if(get_num(FREEZE_IN_VOTE) != FREEZE_TIME_ENABLED || !get_num(VOTE_IN_NEW_ROUND)) {
        return;
    }
    
    set_float(FREEZETIME, get_float(FREEZETIME) + get_float(PREPARE_TIME) + get_float(VOTE_TIME) + 1);
}

restoreFreezeTime()
{
    if(get_num(FREEZE_IN_VOTE) != FREEZE_TIME_ENABLED) {
        return;
    }
    
    set_float(FREEZETIME, get_float(FREEZETIME) - get_float(PREPARE_TIME) - get_float(VOTE_TIME) - 1);
}

stock consolePrintEx(index, message[], any:...)
{
    static buffer[126];
    static const color_tags[][] = { "^1", "^3", "^4" };

    vformat(buffer, charsmax(buffer), message, 3);

    for(new i; i < sizeof color_tags; i++) {
        replace_string(buffer, charsmax(buffer), color_tags[i], "", false);
    }

    console_print(index, buffer);
}
