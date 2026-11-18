// Read-only compatibility probe: no world, player, inventory or chest mutations.
// The only persistent output is this mod's own diagnostic log.

function CN_ProbeLog(_message)
{
    var _file = file_text_open_append("chest_network_probe.log");
    if (_file < 0) return;
    file_text_write_string(_file, string(_message));
    file_text_writeln(_file);
    file_text_close(_file);
}

function CN_ProbeFunction(_name)
{
    var _result = {
        name: _name,
        global_exists: variable_global_exists(_name),
        asset_index: asset_get_index(_name),
        compiled_index: asset_get_index("gml_Script_" + _name)
    };
    CN_ProbeLog(json_stringify(_result));
}

function CN_ProbePublicAPI()
{
    CN_ProbeLog("Container: " + json_stringify(variable_struct_get_names(Container)));
    CN_ProbeLog("GUI: " + json_stringify(variable_struct_get_names(GUI)));
    CN_ProbeLog("Interactable: " + json_stringify(variable_struct_get_names(Interactable)));
    CN_ProbeLog("Item: " + json_stringify(variable_struct_get_names(Item)));
    CN_ProbeLog("ModInstance: " + json_stringify(variable_struct_get_names(ModInstance)));
}

function CN_ProbeCore()
{
    var _root = { uid: "root", i: 0, j: 0, w: 1, h: 1, scope: "probe", slots: 20 };
    var _nodes = [
        { uid: "a", i: 1, j: 0, w: 1, h: 1, scope: "probe", slots: 20 },
        { uid: "b", i: 1, j: 1, w: 1, h: 1, scope: "probe", slots: 20 },
        { uid: "isolated", i: 3, j: 0, w: 1, h: 1, scope: "probe", slots: 20 }
    ];
    array_push(_nodes, _root);
    var _network = CN_SelectNetwork(_root, _nodes);
    CN_ProbeLog("Core network: " + string(array_length(_network)) + " chests, " + string(CN_NetworkCapacity(_network)) + " slots; expected 3/60");
    var _items = [{ name: "ЖЕЛЕЗНАЯ РУДА", type: "material" }];
    CN_ProbeLog("Core Cyrillic search: " + string(array_length(CN_FilterItems(_items, "желез", "material"))) + "; expected 1");
    var _sort_probe = [{ qty: 1, name: "Яблоко", type: "x", sort_key: "яблоко" }, { qty: 1, name: "Арбуз", type: "x", sort_key: "арбуз" }];
    var _sorted = CN_NativeViewSources(_sort_probe, "", "", "name");
    CN_ProbeLog("Native view Cyrillic sort: " + string(_sorted[0].name) + "; expected Арбуз");
}

function CN_ProbeContainers()
{
    var _container = undefined;
    var _destination = undefined;
    var _item = undefined;
    try
    {
        _container = Container.Create(2, 2);
        CN_ProbeLog("TEMP CREATE: " + string(Container.Exists(_container)) + "; size=" + string(Container.GetWidth(_container)) + "x" + string(Container.GetHeight(_container)));
        CN_ProbeLog("TEMP EXPORT EMPTY: " + string(Container.Export(_container)));
        CN_ProbeLog("TEMP NATIVE WIDTH: " + string(CN_NativeCall("container_get_grid_width", [_container])));
        var _closed = CN_NativeCall("container_get_open", [_container]);
        var _picked = CN_NativeCall("container_get_global_picked_item", []);
        CN_ProbeLog("CHEST ACCESS GETTERS: temp_open=" + string(_closed) + "; held_quantity=" + string(CN_ReadItemQuantity(_picked)));
        try { CN_ProbeLog("NATIVE TEMP CONTAINER: " + json_stringify(CN_InspectNativeContainer(_container))); }
        catch (_native_error) { CN_ProbeLog("NATIVE TEMP INSPECTION ERROR: " + string(_native_error)); }
        _item = CN_NativeCall("container_item_generate_map", [E_ITEMS.wood, E_ITEM_AFFIX.normal]);
        Item.SetProperty(_item, 114, 7);
        CN_ProbeLog("TEMP GENERATED ITEM: id=" + string(Item.GetProperty(_item, 0)) + "; quantity=" + string(CN_ReadItemQuantity(_item)));
        var _properties = {};
        var _key = ds_map_find_first(_item);
        while (!is_undefined(_key))
        {
            var _value = Item.GetProperty(_item, _key);
            if (is_numeric(_value) || is_string(_value) || is_bool(_value)) variable_struct_set(_properties, string(_key), _value);
            _key = ds_map_find_next(_item, _key);
        }
        CN_ProbeLog("TEMP GENERATED PROPERTIES: " + json_stringify(_properties));
        CN_NativeCall("container_item_map_add_position", [0, 0, _item, _container]);
        var _attached = Container.GetItem(_container, 0, 0);
        CN_ProbeLog("TEMP ATTACH: " + string(_attached == _item) + "; quantity=" + string(CN_ReadItemQuantity(_attached)));
        if (_attached != _item) throw "Generated item was not attached to our temporary container";
        _item = undefined; // The temporary container now owns this item map.
        CN_ProbeLog("TEMP EXPORT SEEDED: " + string(Container.Export(_container)));
        _destination = Container.Create(2, 2);
        CN_NativeCall("container_item_move", [_attached, _destination]);
        CN_ProbeLog("TEMP MOVE FORWARD: source=" + string(CN_ReadItemQuantity(Container.GetItem(_container, 0, 0))) + "; destination=" + string(CN_ReadItemQuantity(Container.GetItem(_destination, 0, 0))));
        var _back = Container.GetItem(_destination, 0, 0);
        if (is_undefined(_back)) throw "Move into temporary destination failed";
        CN_NativeCall("container_item_move", [_back, _container]);
        CN_ProbeLog("TEMP MOVE BACK: source=" + string(CN_ReadItemQuantity(Container.GetItem(_container, 0, 0))) + "; destination=" + string(CN_ReadItemQuantity(Container.GetItem(_destination, 0, 0))));
        CN_ProbeLog("TEMP CONTAINS: " + string(CN_NativeCall("container_contains_item", [E_ITEMS.wood, _container])));
    }
    catch (_error) { CN_ProbeLog("TEMP CONTAINER ERROR: " + string(_error)); }
    // These objects were created here and never attached to player/world state.
    if (!is_undefined(_item) && is_numeric(_item) && ds_exists(_item, ds_type_map))
    {
        if (is_undefined(_container) || !Container.Exists(_container) || Container.GetItem(_container, 0, 0) != _item) ds_map_destroy(_item);
    }
    if (!is_undefined(_destination) && Container.Exists(_destination)) Container.Destroy(_destination, false, 0, 0);
    if (!is_undefined(_container) && Container.Exists(_container)) Container.Destroy(_container, false, 0, 0);
}

function CN_ProbeSeed(_container, _quantity)
{
    var _item = CN_NativeCall("container_item_generate_map", [E_ITEMS.wood, E_ITEM_AFFIX.normal]);
    Item.SetProperty(_item, 114, _quantity);
    CN_NativeCall("container_item_map_add_position", [0, 0, _item, _container]);
    if (Container.GetItem(_container, 0, 0) != _item) throw "Probe could not seed its disposable container";
    return _item;
}

function CN_ProbeFullGrid()
{
    var _first = Container.Create(5, 6);
    var _second = Container.Create(5, 6);
    try
    {
        for (var _y = 0; _y < 6; _y++)
            for (var _x = 0; _x < 5; _x++)
            {
                var _item = CN_NativeCall("container_item_generate_map", [E_ITEMS.wood, E_ITEM_AFFIX.normal]);
                Item.SetProperty(_item, 114, 999);
                CN_NativeCall("container_item_map_add_position", [_x, _y, _item, _first]);
            }
        var _slots = CN_SnapshotSlots([{ container: _first }, { container: _second }]);
        var _view = CN_NativeViewSources(_slots, "", "", "source");
        if (array_length(_view) != 35 || _view[30].container != _second || _view[30].qty != 0)
            throw "Full first chest did not expose a real empty slot from the second";
        CN_ProbeLog("NETWORK GRID READY: 30 occupied, 30 free, first free slot from second chest at index 30");
    }
    catch (_error) { CN_ProbeLog("NETWORK GRID ERROR: " + string(_error)); }
    Container.Destroy(_second, false, 0, 0);
    Container.Destroy(_first, false, 0, 0);
}

function CN_ProbeTransferCases()
{
    var _source = Container.Create(1, 1);
    var _destination = Container.Create(1, 1);
    try
    {
        var _item = CN_ProbeSeed(_source, 7);
        var _other = CN_ProbeSeed(_destination, 995);
        var _move = CN_MoveContainerSlot(_source, 0, 0, _destination, _item, 7, E_ITEMS.wood);
        CN_ProbeLog("CASE PARTIAL: " + json_stringify(_move) + "; source=" + string(CN_ContainerQuantity(_source, E_ITEMS.wood)) + "; destination=" + string(CN_ContainerQuantity(_destination, E_ITEMS.wood)));
        _item = Container.GetItem(_source, 0, 0);
        _move = CN_MoveContainerSlot(_source, 0, 0, _destination, _item, 3, E_ITEMS.wood);
        CN_ProbeLog("CASE FULL: " + json_stringify(_move));
        _move = CN_MoveContainerSlot(_source, 0, 0, _destination, _item, 7, E_ITEMS.wood);
        CN_ProbeLog("CASE STALE: " + json_stringify(_move));
        try
        {
            var _wrong = CN_NativeCall("container_contains_item", [_source, _item]);
            CN_ProbeLog("CASE OLD CONTAINS ORDER: unexpected success " + string(_wrong));
        }
        catch (_expected) { CN_ProbeLog("CASE OLD CONTAINS ORDER ERROR: " + string(_expected)); }
        CN_ProbeLog("CASE CORRECT CONTAINS ORDER: " + string(CN_NativeCall("container_contains_item", [E_ITEMS.wood, _source])));
        Container.Clear(_source);
        Container.Clear(_destination);
        _item = CN_ProbeSeed(_source, 7);
        Item.SetData(_item, "cn_probe_custom", "retained");
        CN_NativeCall("container_set_open", [_destination, false]);
        CN_NativeCall("container_set_interactable", [_destination, false]);
        _move = CN_MoveContainerSlot(_source, 0, 0, _destination, _item, 7, E_ITEMS.wood);
        CN_ProbeLog("CASE CLOSED NONINTERACTABLE: " + json_stringify(_move));
        var _received = Container.GetItem(_destination, 0, 0);
        if (CN_ReadItemQuantity(_received) > 0) CN_ProbeLog("CASE CUSTOM DATA: " + string(Item.GetData(_received, "cn_probe_custom")));
        var _exported = Container.Export(_destination);
        CN_ProbeLog("CASE EXPORT: " + string(_exported));
        Container.Clear(_source);
        Container.Import(_source, _exported);
        var _imported_item = Container.GetItem(_source, 0, 0);
        var _imported_custom = Item.GetData(_imported_item, "cn_probe_custom");
        var _imported_quantity = CN_ContainerQuantity(_source, E_ITEMS.wood);
        CN_ProbeLog("CASE IMPORT: quantity=" + string(_imported_quantity) + "; custom=" + string(_imported_custom));
        Container.Clear(_source);
        Container.Clear(_destination);
        _item = CN_ProbeSeed(_source, 1);
        _move = CN_MoveContainerSlot(_source, 0, 0, _destination, _item, 1, E_ITEMS.wood);
        CN_ProbeLog("CASE SINGLE ITEM: " + json_stringify(_move));
    }
    catch (_error) { CN_ProbeLog("TRANSFER CASE ERROR: " + string(_error)); }
    Container.Destroy(_destination, false, 0, 0);
    Container.Destroy(_source, false, 0, 0);
}

function CN_ProbeRemainderCases()
{
    var _source = Container.Create(1, 1);
    var _first = Container.Create(1, 1);
    var _second = Container.Create(1, 1);
    var _route = undefined;
    try
    {
        for (var _case = 0; _case < 4; _case++)
        {
            Container.Clear(_source); Container.Clear(_first); Container.Clear(_second);
            var _item = CN_ProbeSeed(_source, 7);
            if (_case >= 2) Item.SetData(_item, "cn_probe_remainder", "retained");
            var _first_qty = (_case == 0) ? 999 : 995;
            var _first_item = CN_ProbeSeed(_first, _first_qty);
            // Observed engine behavior: independently allocated custom data
            // does not stack even when its marker text is equal. Test plain
            // partial stacks separately; never erase data to force a merge.
            if (_case == 3) Item.SetData(_first_item, "cn_probe_remainder", "retained");
            var _entries = CN_SnapshotSlots([{ container: _source }]);
            var _before = CN_DLLCaptureSlots(_entries);
            var _initial = _before.captured[0];
            var _first_key = string(_first);
            var _second_key = string(_second);
            _route = CN_DLLCommand({ op: "begin_deposit_route", source: _initial,
                destinations: [_first_key, _second_key] });
            var _first_qty_allowed = CN_DLLCommand({ op: "offer_deposit_slot", token: _route,
                destination: _first_key, available: true, live: _initial });
            if (_first_qty_allowed != 7) throw "Deposit route rejected a fresh source";
            var _stock = CN_MoveContainerSlot(_source, 0, 0, _first, _item, _first_qty_allowed, E_ITEMS.wood);
            CN_DLLCommand({ op: "record_deposit_move", token: _route, moved: _stock.moved });
            var _remainder = CN_NativeInventoryRemainder(_before, _item);
            var _expected = (_case == 1) ? 3 : 7;
            CN_ProbeLog("DLL REMAINDER CASE: " + json_stringify({ case_id: _case, first: _first_qty, source_custom: _case >= 2, destination_custom: _case == 3, stock: _stock, before: _before.captured, live: _before.live, source_now: CN_ContainerQuantity(_source, E_ITEMS.wood), remainder: _remainder }));
            if (is_undefined(_remainder) || _remainder.qty != _expected) throw "Native remainder selection failed";
            var _observed = CN_DLLObserveSlot(_remainder);
            var _next_qty = CN_DLLCommand({ op: "offer_deposit_slot", token: _route,
                destination: _second_key, available: true, live: _observed });
            if (_next_qty != _expected) throw "Deposit route lost the remainder";
            var _routed = CN_MoveContainerSlot(_source, 0, 0, _second, _remainder.item, _next_qty, _remainder.id);
            CN_DLLCommand({ op: "record_deposit_move", token: _route, moved: _routed.moved });
            var _route_moved = CN_DLLCommand({ op: "finish_deposit_route", token: _route });
            _route = undefined;
            var _total = CN_ContainerQuantity(_source, E_ITEMS.wood) + CN_ContainerQuantity(_first, E_ITEMS.wood) + CN_ContainerQuantity(_second, E_ITEMS.wood);
            var _received = Container.GetItem(_second, 0, 0);
            if (_routed.moved != _expected || _route_moved != 7 || _total != _first_qty + 7)
                throw "Native remainder transfer did not preserve quantity/data";
            if (_case >= 2 && Item.GetData(_received, "cn_probe_remainder") != "retained")
                throw "Native remainder transfer lost custom data";
            CN_ProbeLog("CASE NETWORK REMAINDER: " + json_stringify({ first_before: _first_qty, stock_moved: _stock.moved, routed: _routed.moved, total: _total }));
        }
        CN_ProbeLog("NATIVE DEPOSIT ROUTE READY: four disposable cases preserved quantity and custom data");
        CN_ProbeLog("NATIVE REMAINDER READY: full/partial disposable destinations preserve totals and custom data");
    }
    catch (_error)
    {
        if (!is_undefined(_route))
        {
            try { CN_DLLCommand({ op: "abort_deposit_route", token: _route }); }
            catch (_abort_error) { CN_ProbeLog("DEPOSIT ROUTE PROBE ABORT: " + string(_abort_error)); }
        }
        Container.Destroy(_second, false, 0, 0); Container.Destroy(_first, false, 0, 0); Container.Destroy(_source, false, 0, 0);
        throw _error;
    }
    Container.Destroy(_second, false, 0, 0); Container.Destroy(_first, false, 0, 0); Container.Destroy(_source, false, 0, 0);
}

function CN_ProbeEnums()
{
    var _names = ["E_ITEM_DATA", "E_INTERACTABLE_DATA", "E_SCRIPT_DATA", "E_DATABASES"];
    for (var _i = 0; _i < array_length(_names); _i++)
    {
        if (variable_global_exists(_names[_i])) CN_ProbeLog("ENUM " + _names[_i] + ": " + json_stringify(variable_global_get(_names[_i])));
    }
    CN_ProbeLog("CHEST TEMPLATE: object=" + string(Database.GetInteractableData(E_INTERACTABLES.chest_wood, 10)) + "; width=" + string(Database.GetInteractableData(E_INTERACTABLES.chest_wood, 35)) + "; height=" + string(Database.GetInteractableData(E_INTERACTABLES.chest_wood, 36)));
    try
    {
        var _terminal_key = "id16052_cn_terminal";
        var _object = Database.GetInteractableData(_terminal_key, 10);
        var _width = Database.GetInteractableData(_terminal_key, 35);
        var _hook = Database.GetInteractableData(_terminal_key, 56);
        CN_ProbeLog("PROTOTYPE TERMINAL: object=" + string(_object) + "; width=" + string(_width) + "; hook=" + string(_hook));
        CN_ProbeLog("PROTOTYPE ITEM: " + string(CN_NativeCall("db_item", ["id16053_cn_terminal", 2])));
        // SDK column22 is Build Block;0/6/59 match already verified runtime
        // ID/max-stack/affix indices. This is a read-only diagnostic, not a write
        // based on an assumed property ID. Validate the effective link in-game.
        var _terminal_id = Database.GetInteractableData(_terminal_key, 0);
        var _item_id = CN_NativeCall("db_item", ["id16053_cn_terminal", 0]);
        var _build_ref = CN_NativeCall("db_item", ["id16053_cn_terminal", 22]);
        var _wood_ref = CN_NativeCall("db_item", [E_ITEMS.chest_wood, 22]);
        CN_ProbeLog("BUILD LINK CANDIDATE: " + json_stringify({ terminal_id: _terminal_id, item_id: _item_id, property_index: 22, terminal_build: string(_build_ref), wood_build: string(_wood_ref), expected_wood: E_INTERACTABLES.chest_wood }));
    }
    catch (_error) { CN_ProbeLog("PROTOTYPE CONTENT ERROR: " + string(_error)); }
}

function CN_ProbeWorldState()
{
    var _world = { region: REGION, player_x: MY_PLAYER.x, player_y: MY_PLAYER.y };
    var _names = variable_instance_get_names(global);
    for (var _n = 0; _n < array_length(_names); _n++)
    {
        var _name = _names[_n];
        if (string_pos("world", string_lower(_name)) == 0 && string_pos("island", string_lower(_name)) == 0) continue;
        var _value = variable_global_get(_name);
        if (is_string(_value) || is_numeric(_value) || is_bool(_value)) variable_struct_set(_world, _name, _value);
    }
    CN_ProbeLog("WORLD STATE: " + json_stringify(_world));
    var _player_fields = variable_instance_get_names(MY_PLAYER);
    var _inventory_fields = {};
    for (var _p = 0; _p < array_length(_player_fields); _p++)
    {
        var _field = _player_fields[_p];
        if (string_pos("inventory", string_lower(_field)) == 0 && string_pos("container", string_lower(_field)) == 0) continue;
        var _field_value = variable_instance_get(MY_PLAYER, _field);
        variable_struct_set(_inventory_fields, _field, string(_field_value));
    }
    CN_ProbeLog("PLAYER INVENTORY FIELDS: " + json_stringify(_inventory_fields));
    try
    {
        var _inventory = INVENTORY;
        var _inventory_exists = Container.Exists(_inventory);
        var _inventory_info = { value: string(_inventory), exists: _inventory_exists };
        if (_inventory_exists) { _inventory_info.width = Container.GetWidth(_inventory); _inventory_info.height = Container.GetHeight(_inventory); }
        CN_ProbeLog("INVENTORY MACRO: " + json_stringify(_inventory_info));
    }
    catch (_error) { CN_ProbeLog("INVENTORY MACRO UNAVAILABLE: " + string(_error)); }
    if (instance_exists(objInteractableChest))
    {
        var _chest = instance_find(objInteractableChest, 0);
        var _fields = variable_instance_get_names(_chest);
        var _data = {};
        for (var _i = 0; _i < array_length(_fields); _i++)
        {
            var _value = variable_instance_get(_chest, _fields[_i]);
            if (is_string(_value) || is_numeric(_value) || is_bool(_value)) variable_struct_set(_data, _fields[_i], _value);
        }
        CN_ProbeLog("REAL CHEST: " + json_stringify(_data));
    }
}

OnModLoad(function()
{
    variable_global_set("__cn_probe_world_inspected", false);
    variable_global_set("__cn_probe_ready_ticks", 0);
    var _file = file_text_open_write("chest_network_probe.log");
    if (_file >= 0)
    {
        file_text_write_string(_file, "Chest Network compatibility probe 0.0.40");
        file_text_writeln(_file);
        file_text_close(_file);
    }
    try
    {
        CN_InitIdentity();
        var _first_identity = CN_NewIdentity("probe");
        var _second_identity = CN_NewIdentity("probe");
        if (_first_identity == _second_identity) throw "Identity probe returned the same ID twice";
        CN_ProbeLog("IDENTITY READY: clock and random verified; two distinct IDs");
    }
    catch (_error)
    {
        if (variable_global_exists("__cn_identity"))
        {
            var _identity_state = variable_global_get("__cn_identity");
            _identity_state.ready = false;
        }
        CN_ProbeLog("IDENTITY ERROR: " + string(_error));
    }
    try { CN_ProbeCore(); } catch (_error) { CN_ProbeLog("CORE ERROR: " + string(_error)); }
    try
    {
        CN_RefreshLanguage();
        var _ui_examples = [];
        var _ui_keys = ["all", "search", "source", "name", "network", "view"];
        for (var _n = 0; _n < array_length(_ui_keys); _n++)
        {
            var _ui_label = CN_UIText(_ui_keys[_n]);
            if (!is_string(_ui_label) || _ui_label == "") throw "Missing UI translation: " + _ui_keys[_n];
            array_push(_ui_examples, _ui_label);
        }
        var _type_examples = [];
        var _type_keys = ["Etc", "Material", "Weapon", "Storage"];
        for (var _n = 0; _n < array_length(_type_keys); _n++)
            array_push(_type_examples, { key: _type_keys[_n], label: CN_LocalizedType(_type_keys[_n]) });
        var _localized_sort = [];
        var _localized_names = ["Яблоко", "Ёж", "Ель", "Арбуз", "Берёза"];
        for (var _n = 0; _n < array_length(_localized_names); _n++)
            array_push(_localized_sort, { name: _localized_names[_n], sort_key: CN_NameSortKey(_localized_names[_n]) });
        _localized_sort = CN_SortNativeSources(_localized_sort, "name");
        CN_ProbeLog("LOCALIZATION READY: " + json_stringify({ ui: _ui_examples, types: _type_examples, sort: _localized_sort }));
    }
    catch (_error) { CN_ProbeLog("LOCALIZATION ERROR: " + string(_error)); }
    try { CN_ProbePublicAPI(); } catch (_error) { CN_ProbeLog("API ERROR: " + string(_error)); }
    try { CN_ProbeContainers(); } catch (_error) { CN_ProbeLog("TEMP CLEANUP ERROR: " + string(_error)); }
    try { CN_ProbeTransferCases(); } catch (_error) { CN_ProbeLog("TRANSFER CLEANUP ERROR: " + string(_error)); }
    try { CN_ProbeRemainderCases(); } catch (_error) { CN_ProbeLog("NATIVE REMAINDER ERROR: " + string(_error)); }
    CN_ProbeFullGrid();
    try { CN_ProbeEnums(); } catch (_error) { CN_ProbeLog("ENUM ERROR: " + string(_error)); }
    var _names = [
        "container_item_move", "container_contains_item", "container_get_item_list",
        "container_item_add", "container_item_generate_map", "net_is_host",
        "net_remote_call_host", "net_remote_call_socket", "net_packet_remote_call",
        "world_get_interactable_persistent_data_struct_ij"
    ];
    for (var _i = 0; _i < array_length(_names); _i++)
    {
        try { CN_ProbeFunction(_names[_i]); }
        catch (_error) { CN_ProbeLog("LOOKUP ERROR " + _names[_i] + ": " + string(_error)); }
    }
    CN_ProbeLog("PROBE FINISHED; no game containers were changed");
});

// Read-only world observation after a short stable period. Live reload was
// disabled for world testing: changing event tables during world entry is unsafe.
OnModUpdate(function()
{
    if (instance_exists(objPlayer) && !is_undefined(MY_PLAYER) && instance_exists(objGUIIngameController) && !instance_exists(objGUIMenuController))
    {
        if (variable_global_exists("guiEnabled") && !variable_global_get("guiEnabled")) return;
        var _ticks = variable_global_get("__cn_probe_ready_ticks") + 1;
        variable_global_set("__cn_probe_ready_ticks", min(_ticks, 120));
        if (_ticks < 120) return;
        if (!variable_global_exists("__cn_probe_world_inspected") || !variable_global_get("__cn_probe_world_inspected"))
        {
            variable_global_set("__cn_probe_world_inspected", true);
            try { CN_ProbeWorldState(); } catch (_error) { CN_ProbeLog("WORLD INSPECTION ERROR: " + string(_error)); }
        }
    }
});
