// Read-only evidence for an ordinary client inventory, using only wood counts.
function CN_CoopTraceState()
{
    if (!variable_global_exists("__cn_coop_trace"))
        variable_global_set("__cn_coop_trace", {tick: 0, watch: undefined, active: false, failed: false});
    return variable_global_get("__cn_coop_trace");
}

function CN_CoopTraceWrite(_row)
{
    var _file = file_text_open_append("chest_network_coop_trace.jsonl");
    if (_file < 0) throw "Coop trace log unavailable";
    file_text_write_string(_file, json_stringify(_row));
    file_text_writeln(_file);
    file_text_close(_file);
}

function CN_CoopInventoryField(_name)
{
    var _lower = string_lower(_name);
    return string_pos("inventor", _lower) > 0 || string_pos("container", _lower) > 0;
}

function CN_CoopReadInventoryField(_scope, _name, _value)
{
    var _row = {scope: _scope, field: _name, container_valid: false, same_as_local: false,
                width: -1, height: -1, wood: -1};
    if (!is_numeric(_value) || !Container.Exists(_value)) return _row;
    _row.container_valid = true;
    _row.same_as_local = _value == INVENTORY;
    _row.width = Container.GetWidth(_value);
    _row.height = Container.GetHeight(_value);
    _row.wood = CN_ContainerQuantity(_value, E_ITEMS.wood);
    return _row;
}

function CN_CoopLookup(_name, _actor)
{
    if (!variable_global_exists(_name)) return undefined;
    try { return CN_NativeCall(_name, [_actor]); }
    catch (_error) { return undefined; }
}

function CN_CoopReadPeer(_actor, _host)
{
    var _rows = [];
    var _instance = MY_PLAYER;
    if (_host) _instance = CN_CoopLookup("find_player_instance_by_netid", _actor);
    var _found_instance = !is_undefined(_instance) && instance_exists(_instance);
    if (_found_instance)
    {
        var _names = variable_instance_get_names(_instance);
        for (var _n = 0; _n < array_length(_names); _n++)
        {
            var _name = _names[_n];
            if (!CN_CoopInventoryField(_name)) continue;
            var _value = variable_instance_get(_instance, _name);
            var _field = CN_CoopReadInventoryField("instance", _name, _value);
            array_push(_rows, _field);
        }
    }
    var _record = CN_CoopLookup("find_player_by_netid", _actor);
    var _found_record = is_struct(_record);
    if (_found_record)
    {
        var _record_names = variable_struct_get_names(_record);
        for (var _n = 0; _n < array_length(_record_names); _n++)
        {
            var _name = _record_names[_n];
            if (!CN_CoopInventoryField(_name)) continue;
            var _value = variable_struct_get(_record, _name);
            var _field = CN_CoopReadInventoryField("player_record", _name, _value);
            array_push(_rows, _field);
        }
    }
    return {peer_instance: _found_instance, peer_record: _found_record, candidates: _rows};
}

function CN_CoopReadChest(_instance, _actor)
{
    if (!instance_exists(_instance)) return undefined;
    var _region = CN_TraceField(_instance, "region");
    if (!is_undefined(_region) && _region != REGION) return undefined;
    var _container = CN_TraceField(_instance, "container");
    var _i = CN_TraceField(_instance, "i");
    var _j = CN_TraceField(_instance, "j");
    if (is_undefined(_container) || !Container.Exists(_container) || !is_numeric(_i) || !is_numeric(_j))
        return undefined;
    var _pd = CN_TraceField(_instance, "persistentData");
    if (!is_struct(_pd) || !variable_struct_exists(_pd, "open") || !variable_struct_exists(_pd, "netID"))
        return undefined;
    return {instance: _instance, container: _container, region: REGION, i: _i, j: _j,
            actor: _actor, claimed: (_pd.open == true && _pd.netID == _actor)};
}

function CN_CoopFindRemoteChest(_local)
{
    var _count = instance_number(objInteractableChest);
    for (var _n = 0; _n < _count; _n++)
    {
        var _instance = instance_find(objInteractableChest, _n);
        var _pd = CN_TraceField(_instance, "persistentData");
        if (!is_struct(_pd) || !variable_struct_exists(_pd, "open") || !variable_struct_exists(_pd, "netID"))
            continue;
        if (!_pd.open || !is_numeric(_pd.netID) || _pd.netID < 0 || _pd.netID == _local) continue;
        var _watch = CN_CoopReadChest(_instance, _pd.netID);
        if (is_struct(_watch)) return _watch;
    }
    return undefined;
}

function CN_CoopObservedChest(_previous, _host, _local)
{
    var _current = undefined;
    if (is_struct(_previous) && _previous.region == REGION)
    {
        var _fresh = CN_CoopReadChest(_previous.instance, _previous.actor);
        if (is_struct(_fresh) && _fresh.container == _previous.container && _fresh.i == _previous.i && _fresh.j == _previous.j)
            _current = _fresh;
    }
    if (_host)
    {
        if (is_struct(_current) && _current.claimed) return _current;
        var _remote = CN_CoopFindRemoteChest(_local);
        if (is_struct(_remote)) return _remote;
    }
    else
    {
        var _view = CN_NativeViewState();
        if (is_struct(_view.anchor))
        {
            var _owned = CN_CoopReadChest(_view.anchor.instance, _local);
            if (is_struct(_owned)) return _owned;
        }
    }
    // Continue observing this physical chest after the stock close.
    return _current;
}

function CN_CoopTraceUpdate(_s)
{
    _s.tick++;
    if ((_s.tick mod 12) != 0) return;
    var _connected = CN_TraceCall("net_is_connected");
    if (_connected != true || !instance_exists(objPlayer))
    {
        if (_s.active)
        {
            CN_DLLCommand({op: "reset_coop_trace"});
            CN_CoopTraceWrite({event: "session_end", at_ms: floor(get_timer() / 1000)});
            _s.active = false;
            _s.watch = undefined;
        }
        return;
    }
    if (!CN_WorldReady() || !variable_global_exists("__NET_MY_ID")) return;
    var _host = CN_NativeCall("net_is_host", []);
    var _local = variable_global_get("__NET_MY_ID");
    _s.watch = CN_CoopObservedChest(_s.watch, _host, _local);
    var _held = CN_NativeCall("container_get_global_picked_item", []);
    var _held_wood = 0;
    var _held_qty = CN_ReadItemQuantity(_held);
    if (_held_qty > 0 && Item.GetProperty(_held, 0) == E_ITEMS.wood) _held_wood = _held_qty;
    var _wood = CN_ContainerQuantity(INVENTORY, E_ITEMS.wood);
    var _sample = {host: _host == true, region: REGION, local: string(_local), inventory_wood: _wood, cursor_wood: _held_wood};
    if (is_struct(_s.watch))
    {
        var _watch = _s.watch;
        var _peer = CN_CoopReadPeer(_watch.actor, _host);
        var _open = CN_NativeCall("container_get_open", [_watch.container]);
        var _chest_wood = CN_ContainerQuantity(_watch.container, E_ITEMS.wood);
        _sample.chest = {i: _watch.i, j: _watch.j, actor: string(_watch.actor),
                         native_open: _open == true, claimed: _watch.claimed, wood: _chest_wood,
                         peer_instance: _peer.peer_instance, peer_record: _peer.peer_record, candidates: _peer.candidates};
    }
    _s.active = true;
    var _changed = CN_DLLCommand({op: "observe_coop", sample: _sample});
    if (_changed == 1)
        CN_CoopTraceWrite({event: "sample", at_ms: floor(get_timer() / 1000), sample: _sample});
}

OnModLoad(function()
{
    var _s = CN_CoopTraceState();
    try
    {
        var _fixture = {host: false, region: 0, local: "probe", inventory_wood: 0, cursor_wood: 0};
        var _first = CN_DLLCommand({op: "observe_coop", sample: _fixture});
        var _second = CN_DLLCommand({op: "observe_coop", sample: _fixture});
        CN_DLLCommand({op: "reset_coop_trace"});
        if (_first != 1 || _second != 0) throw "Coop observation self-check failed";
        var _ready = {event: "ready", version: "0.0.42",
                      instance_lookup: variable_global_exists("find_player_instance_by_netid"),
                      record_lookup: variable_global_exists("find_player_by_netid")};
        var _line = json_stringify(_ready);
        var _file = file_text_open_write("chest_network_coop_trace.jsonl");
        if (_file < 0) throw "Coop trace log unavailable";
        file_text_write_string(_file, _line);
        file_text_writeln(_file);
        file_text_close(_file);
        CN_ProbeLog("COOP TRACE READY");
    }
    catch (_error) { _s.failed = true; CN_ProbeLog("COOP TRACE ERROR: " + string(_error)); }
});

OnModUpdate(function()
{
    var _s = CN_CoopTraceState();
    if (_s.failed) return;
    try { CN_CoopTraceUpdate(_s); }
    catch (_error) { _s.failed = true; CN_ProbeLog("COOP TRACE ERROR: " + string(_error)); }
});
