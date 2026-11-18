// Whitelisted test commands, bound to the current world-generation session.
// No code evaluation, live mod reload or save-file editing is supported.

function CN_DevState()
{
    if (!variable_global_exists("__cn_dev"))
    {
        variable_global_set("__cn_dev", { token: "", player: "", region: -1, tick: 0, world_name: "", fixture_given: false, failed: false });
    }
    return variable_global_get("__cn_dev");
}

function CN_DevWriteJSON(_path, _value)
{
    var _file = file_text_open_write(_path);
    if (_file < 0) throw "Cannot write development status";
    var _text = json_stringify(_value);
    file_text_write_string(_file, _text);
    file_text_close(_file);
}

function CN_DevInvalidate()
{
    var _d = CN_DevState();
    _d.token = "";
    _d.tick = 0;
    _d.failed = false;
    if (file_exists("chest_network_dev_ready.json")) file_delete("chest_network_dev_ready.json");
}

function CN_InspectQuantities(_entries)
{
    var _totals = {};
    for (var _n = 0; _n < array_length(_entries); _n++)
    {
        var _key = string(_entries[_n].id);
        var _qty = 0;
        if (variable_struct_exists(_totals, _key)) _qty = variable_struct_get(_totals, _key);
        variable_struct_set(_totals, _key, _qty + _entries[_n].qty);
    }
    return _totals;
}

function CN_DevTick()
{
    var _d = CN_DevState();
    if (_d.failed || !CN_WorldReady()) return;
    _d.tick++;
    if ((_d.tick mod 30) != 0) return;
    var _player = string(MY_PLAYER);
    if (_d.token == "" || _d.player != _player || _d.region != REGION)
    {
        _d.token = CN_NewIdentity("dev");
        _d.player = _player;
        _d.region = REGION;
        _d.world_name = "";
        try
        {
            var _name = CN_NativeCall("get_player_main_island_name", []);
            if (is_string(_name)) _d.world_name = _name;
        }
        catch (_error) { CN_ProbeLog("WORLD NAME LOOKUP: " + string(_error)); }
        var _ready = {
            version: "0.0.38", token: _d.token, player: _d.player,
            region: _d.region, world_name: _d.world_name,
            x: MY_PLAYER.x, y: MY_PLAYER.y,
            authoritative: CN_NativeCall("net_is_host", [])
        };
        CN_DevWriteJSON("chest_network_dev_ready.json", _ready);
        CN_ProbeLog("DEVELOPMENT READY: " + json_stringify(_ready));
    }
    if (!file_exists("chest_network_dev_command.json")) return;
    var _file = file_text_open_read("chest_network_dev_command.json");
    if (_file < 0) return;
    var _text = file_text_read_string(_file);
    file_text_close(_file);
    file_delete("chest_network_dev_command.json");
    var _result = { ok: false, message: "", token: _d.token };
    try
    {
        if (string_length(_text) > 4096) throw "Development request too large";
        var _request = json_parse(_text);
        if (!is_struct(_request)) throw "Invalid development request";
        if (_request.token != _d.token || _request.player != _player || _request.region != REGION) throw "Development request belongs to another session";
        if (_request.confirmed_world != "TEST") throw "Only the explicitly confirmed TEST session is allowed";
        if (!CN_NativeCall("net_is_host", [])) throw "Development writes require the host";
        if (_request.action == "grant_fixture")
        {
            throw "Fixture issuance retired: TEST already received its items; use the existing chests";
        }
        else if (_request.action == "inspect_world")
        {
            CN_ProbeWorldState();
            _result.ok = true;
            _result.message = "World state logged";
        }
        else if (_request.action == "probe_cursor_slot" || _request.action == "probe_storage_draw")
        {
            var _world = variable_global_get("__WORLD_INFORMATION_STRUCT");
            if (!is_struct(_world) || _world.mainIslandName != "TEST" || CN_NativeCall("net_is_connected", []))
                throw "Disposable storage probe requires the local TEST world";
            var _view_state = CN_NativeViewState();
            if (_request.action == "probe_cursor_slot") _view_state.cursor_probe_pending = true;
            else _view_state.draw_probe_pending = true;
            _result.ok = true;
            _result.message = "Disposable storage probe queued for DrawGUIEnd";
        }
        else if (_request.action == "open_storage")
        {
            throw "Native window mode: open a chest normally; the replacement window is disabled";
        }
        else if (_request.action == "inspect_network")
        {
            var _anchor = CN_FindOpenedChest();
            if (is_undefined(_anchor)) throw "Open a chest first; no nearest-chest fallback";
            var _nodes = CN_BuildLoadedNetwork(_anchor, REGION);
            var _items = CN_CollectContainerItems(_nodes);
            _result.ok = true;
            _result.message = "Network inspected";
            _result.chests = array_length(_nodes);
            _result.stacks = array_length(_items);
            _result.capacity = CN_NetworkCapacity(_nodes);
            _result.storage = CN_InspectQuantities(_items);
            var _view_state = CN_NativeViewState();
            _result.view = { mode: _view_state.sort, query: _view_state.query, type: _view_state.type, names: [] };
            for (var _n = 0; _n < min(60, array_length(_view_state.view)); _n++)
                if (_view_state.view[_n].qty > 0) array_push(_result.view.names, _view_state.view[_n].name);
            _result.containers = [];
            for (var _n = 0; _n < min(64, array_length(_nodes)); _n++)
            {
                var _node = _nodes[_n];
                array_push(_result.containers, {
                    uid: _node.uid, i: _node.i, j: _node.j, w: _node.w, h: _node.h,
                    slots: _node.slots, storage: CN_InspectQuantities(CN_CollectContainerItems([_node]))
                });
            }
            var _inventory_items = CN_CollectContainerItems([{ container: INVENTORY }]);
            _result.inventory = CN_InspectQuantities(_inventory_items);
            var _held = CN_NativeCall("container_get_global_picked_item", []);
            _result.held = { quantity: CN_ReadItemQuantity(_held) };
            if (_result.held.quantity > 0) _result.held.id = Item.GetProperty(_held, 0);
        }
        else throw "Unsupported development action";
    }
    catch (_error) { _result.message = string(_error); CN_ProbeLog("DEVELOPMENT ACTION ERROR: " + string(_error)); }
    CN_DevWriteJSON("chest_network_dev_result.json", _result);
    CN_ProbeLog("DEVELOPMENT RESULT: " + json_stringify(_result));
}

OnModLoad(function() { CN_DevInvalidate(); });
OnWorldGenerationStart(function() { CN_DevInvalidate(); });
OnModUpdate(function()
{
    try { CN_DevTick(); }
    catch (_error)
    {
        var _d = CN_DevState();
        if (!_d.failed)
        {
            // Latch before logging/cleanup, so a secondary error cannot cause
            // the same failure to be retried every thirty frames.
            _d.failed = true;
            _d.token = "";
            CN_ProbeLog("DEVELOPMENT DISABLED: " + string(_error));
            if (file_exists("chest_network_dev_ready.json")) file_delete("chest_network_dev_ready.json");
        }
    }
});
