// Incremental bridge: existing UI/network stay intact; new transfer decisions
// run in our DLL. Handles are opaque strings, never pointers passed as doubles.
function CN_DLLCommand(_request)
{
    if (!variable_global_exists("__cn_dll_command"))
    {
        var _dll = "mods/native/chest-network/tinkerlands_storage.dll";
        var _abi_fn = external_define(_dll, "TCS_ABI", dll_cdecl, ty_real, 0);
        var _abi = external_call(_abi_fn);
        if (_abi != 65536) throw "Unsupported storage DLL ABI";
        var _command_fn = external_define(_dll, "TCS_Command", dll_cdecl, ty_real, 1, ty_string);
        variable_global_set("__cn_dll_command", _command_fn);
        CN_ProbeLog("STORAGE DLL LOADED ABI65536");
    }
    var _fn = variable_global_get("__cn_dll_command");
    var _json = json_stringify(_request);
    var _result = external_call(_fn, _json);
    if (_result <= -100 || (_result < 0 && _result > -10))
    {
        CN_ProbeLog("STORAGE DLL REQUEST REFUSED: " + string_copy(_json, 1, 8192));
        throw "Storage DLL refusal " + string(_result) + "; op=" + _request.op;
    }
    return _result;
}

function CN_DLLSlot(_container, _x, _y, _item, _qty, _id, _favorite)
{
    return { container: string(_container), x: _x, y: _y, item: string(_item),
             qty: _qty, id: _id, favorite: _favorite };
}

function CN_DLLObserveSlot(_entry)
{
    var _item = Container.GetItem(_entry.container, _entry.x, _entry.y);
    var _qty = CN_ReadItemQuantity(_item);
    var _id = -1;
    var _favorite = false;
    if (_qty > 0)
    {
        _id = Item.GetProperty(_item, 0);
        _favorite = ds_map_exists(_item, 115) && Item.GetProperty(_item, 115) == true;
    }
    return CN_DLLSlot(_entry.container, _entry.x, _entry.y, _item, _qty, _id, _favorite);
}

function CN_DLLCaptureSlots(_entries)
{
    var _rows = [];
    for (var _n = 0; _n < array_length(_entries); _n++)
        array_push(_rows, CN_DLLObserveSlot(_entries[_n]));
    var _token = CN_DLLCommand({ op: "capture", slots: _rows });
    return { entries: _entries, token: _token, captured: _rows };
}

function CN_DLLSelectRemainder(_snapshot, _hover_item)
{
    var _live = [];
    for (var _n = 0; _n < array_length(_snapshot.entries); _n++)
        array_push(_live, CN_DLLObserveSlot(_snapshot.entries[_n]));
    var _selected = CN_DLLCommand({ op: "select", token: _snapshot.token,
                                   hover: string(_hover_item), live: _live });
    // Retain observations for the disposable startup probe without logging
    // every ordinary rejected/full inventory gesture.
    _snapshot.live = _live;
    if (_selected <= 0) return undefined;
    var _entry = _snapshot.entries[_selected - 1];
    var _row = _live[_selected - 1];
    return { container: _entry.container, x: _entry.x, y: _entry.y, item: _entry.item,
             qty: _row.qty, id: _row.id, name: _entry.name, type: _entry.type,
             sort_key: _entry.sort_key };
}

function CN_InitInventoryHit()
{
    var _dll = "mods/native/chest-network/tinkerlands_storage.dll";
    var _init = external_define(_dll, "TCS_InitInventoryHit", dll_cdecl, ty_real, 0);
    if (external_call(_init) != 1) return false;
    variable_global_set("__cn_arm_inventory_hit", external_define(_dll, "TCS_ArmInventoryHit", dll_cdecl, ty_real, 4, ty_string, ty_real, ty_real, ty_real));
    variable_global_set("__cn_take_inventory_hit", external_define(_dll, "TCS_TakeInventoryHit", dll_cdecl, ty_real, 0));
    return true;
}

function CN_ArmInventoryHit(_container, _x, _y, _scale)
{
    if (!variable_global_exists("__cn_arm_inventory_hit")) return false;
    var _arm = variable_global_get("__cn_arm_inventory_hit");
    var _handle = string(_container);
    return external_call(_arm, _handle, _x, _y, _scale) == 1;
}

function CN_TakeInventoryHit()
{
    if (!variable_global_exists("__cn_take_inventory_hit")) return 0;
    var _take = variable_global_get("__cn_take_inventory_hit");
    return external_call(_take);
}
