// Native snapshot ownership must also be respected by host-side network moves.
function CN_HostChestWritable(_node)
{
    if (!CN_NativeCall("net_is_host", [])) return false;
    if (!CN_NativeCall("net_is_connected", [])) return true;
    if (!instance_exists(_node.instance) || !variable_instance_exists(_node.instance, "persistentData")) return false;
    var _pd = variable_instance_get(_node.instance, "persistentData");
    if (!is_struct(_pd) || !variable_struct_exists(_pd, "open") || !variable_struct_exists(_pd, "netID")) return false;
    if (!_pd.open) return true;
    if (!variable_global_exists("__NET_MY_ID")) return false;
    return _pd.netID == variable_global_get("__NET_MY_ID");
}

function CN_NativeContainerWritable(_nodes, _container)
{
    for (var _n = 0; _n < array_length(_nodes); _n++)
        if (_nodes[_n].container == _container) return CN_HostChestWritable(_nodes[_n]);
    return false;
}

// Route client input only to the locally opened and assigned chest.
function CN_ClientAnchorInputAllowed(_host, _anchor, _container)
{
    if (!variable_global_exists("__NET_MY_ID") ||
        !variable_instance_exists(_anchor.instance, "persistentData")) return false;
    var _pd = variable_instance_get(_anchor.instance, "persistentData");
    if (!is_struct(_pd) || !variable_struct_exists(_pd, "open") ||
        !variable_struct_exists(_pd, "netID")) return false;
    var _connected = CN_NativeCall("net_is_connected", []);
    var _stock_open = CN_NativeCall("container_get_open", [_anchor.container]);
    var _local = variable_global_get("__NET_MY_ID");
    var _status = CN_DLLCommand({
        op: "client_slot", host: _host == true, connected: _connected == true,
        stock_open: _stock_open == true, server_open: _pd.open == true,
        anchor: string(_anchor.container), selected: string(_container),
        owner: string(_pd.netID), local: string(_local)
    });
    return _status == 1;
}

function CN_ClientQuickMove(_s, _entry, _deposit)
{
    var _anchor = _s.anchor;
    var _chest = _deposit ? _anchor.container : _entry.container;
    if (!CN_ChestStillExists(_anchor) || !CN_ClientAnchorInputAllowed(false, _anchor, _chest)) return;
    if (_deposit && _entry.container != INVENTORY) return;
    var _picked = CN_NativeCall("container_get_global_picked_item", []);
    if (CN_ReadItemQuantity(_picked) > 0 || _entry.qty <= 0 || !CN_NativeEntryMatches(_entry)) return;
    if (ds_map_exists(_entry.item, 115) && Item.GetProperty(_entry.item, 115) == true) return;

    var _destination = _deposit ? _anchor.container : INVENTORY;
    var _started = get_timer();
    var _result = CN_MoveContainerSlot(_entry.container, _entry.x, _entry.y, _destination,
                                      _entry.item, _entry.qty, _entry.id);
    var _elapsed = get_timer() - _started;
    // The game syncs the assigned chest through the same path as a stock click.
    CN_ProbeLog("CLIENT QUICK MOVE: deposit=" + string(_deposit) + "; move_us=" + string(_elapsed) + "; result=" + json_stringify(_result));
    if (_result.moved > 0) _s.notice = "Синхронизация при закрытии сундука";
    else _s.notice = _deposit ? "Нет места в открытом сундуке" : "Нет места в инвентаре";
    _s.notice_tick = _s.tick + 180;
    if (_result.moved > 0) _s.dirty = true;
}

function CN_SyncHostChest(_node)
{
    if (!CN_NativeCall("net_is_connected", [])) return;
    if (!CN_HostChestWritable(_node)) throw "Chest ownership changed before native sync";
    if (!variable_instance_exists(_node.instance, "sync_content")) throw "Native chest sync unavailable";
    var _sync = variable_instance_get(_node.instance, "sync_content");
    if (!is_method(_sync)) throw "Native chest sync is not a bound method";
    method_call(_sync, []);
}

// The DLL sees the real inventory slots rendered by the game and owns only
// the shifted click on that exact slot. Ordinary native clicks remain intact.
function CN_NativeBeginDeposit()
{
    var _s = CN_NativeViewState();
    if (!is_undefined(_s.deposit_hit)) CN_TakeInventoryHit();
    _s.deposit_hit = undefined;
    if (_s.focused || _s.scroll_drag || !is_undefined(_s.pending_deposit) || !keyboard_check(vk_shift)) return;
    var _left = variable_global_get("__K_MENU_LEFT_CLICK_PRESSED") || variable_global_get("__K_INVENTORY_PICKUP_ITEM_PRESSED");
    var _right = variable_global_get("__K_MENU_RIGHT_CLICK_PRESSED") || variable_global_get("__K_INVENTORY_DROP_ITEM_PRESSED");
    if (!_left && !_right) return;
    var _client = !CN_NativeCall("net_is_host", []);
    if (_client && (!_left || _right || !CN_ClientAnchorInputAllowed(false, _s.anchor, _s.anchor.container))) return;
    var _picked = CN_NativeCall("container_get_global_picked_item", []);
    if (CN_ReadItemQuantity(_picked) > 0) return;
    var _entries = CN_SnapshotSlots([{ container: INVENTORY }], false);
    var _snapshot = CN_DLLCaptureSlots(_entries);
    if (!CN_ArmInventoryHit(INVENTORY, MOUSE_WINDOW_X, MOUSE_WINDOW_Y, GUI_SCALE)) return;
    _snapshot.client = _client;
    _snapshot.gesture = _right ? "shift_right" : "shift_left";
    _s.deposit_hit = _snapshot;
}

function CN_NativeFinishDepositHit()
{
    var _s = CN_NativeViewState();
    if (is_undefined(_s.deposit_hit)) return;
    var _before = _s.deposit_hit;
    _s.deposit_hit = undefined;
    var _hit = CN_TakeInventoryHit();
    if (_hit <= 0)
    {
        CN_ProbeLog("NETWORK QUICK DEPOSIT: " + _before.gesture + " no native inventory slot");
        return;
    }
    var _x = (_hit - 1) mod 256;
    var _y = floor((_hit - 1) / 256);
    var _item = undefined;
    for (var _n = 0; _n < array_length(_before.entries); _n++)
    {
        var _candidate = _before.entries[_n];
        if (_candidate.x != _x || _candidate.y != _y) continue;
        _item = _candidate.item;
        break;
    }
    if (is_undefined(_item)) return;
    // A half pickup or an item already on the cursor belongs to native drag/drop.
    var _picked = CN_NativeCall("container_get_global_picked_item", []);
    if (CN_ReadItemQuantity(_picked) > 0)
    {
        CN_ProbeLog("NETWORK QUICK DEPOSIT: " + _before.gesture + " stock cursor item");
        return;
    }
    var _entry = CN_NativeInventoryRemainder(_before, _item);
    if (is_undefined(_entry))
    {
        CN_ProbeLog("NETWORK QUICK DEPOSIT: " + _before.gesture + " no eligible inventory remainder");
        return;
    }
    CN_ProbeLog("NETWORK QUICK DEPOSIT: " + _before.gesture + " slot=" + string(_x) + "," + string(_y) + " quantity=" + string(_entry.qty));
    _s.pending_deposit = { anchor: _s.anchor.uid, entry: _entry, client: _before.client };
}

function CN_NativeInventoryRemainder(_before, _hover_item)
{
    return CN_DLLSelectRemainder(_before, _hover_item);
}

function CN_DepositInventoryAcrossNetwork(_anchor, _entry)
{
    var _result = { ok: false, moved: 0, remaining: _entry.qty, reason: "source_changed" };
    if (!CN_NativeCall("net_is_host", [])) { _result.reason = "host_required"; return _result; }
    if (_entry.container != INVENTORY || !CN_NativeEntryMatches(_entry)) return _result;
    if (ds_map_exists(_entry.item, 115) && Item.GetProperty(_entry.item, 115) == true)
    { _result.reason = "favorite_item"; return _result; }
    if (!CN_ChestStillExists(_anchor) || !CN_NativeCall("container_get_open", [_anchor.container]))
    { _result.reason = "network_unavailable"; return _result; }
    var _nodes = CN_BuildLoadedNetwork(_anchor, REGION);
    var _source = CN_DLLSlot(_entry.container, _entry.x, _entry.y, _entry.item, _entry.qty, _entry.id, false);
    var _destinations = [];
    for (var _n = 0; _n < array_length(_nodes); _n++)
        array_push(_destinations, string(_nodes[_n].container));
    var _token = CN_DLLCommand({ op: "begin_deposit_route", source: _source, destinations: _destinations });
    _result.reason = "destination_full_or_restricted";
    try
    {
        for (var _n = 0; _n < array_length(_nodes); _n++)
        {
            // Observe membership and ownership separately from the DLL's route.
            if (!CN_ChestStillExists(_anchor)) { _result.reason = "network_unavailable"; break; }
            var _live = CN_BuildLoadedNetwork(_anchor, REGION);
            var _node = _nodes[_n];
            var _available = CN_NetworkHasContainer(_live, _node.container) && CN_HostChestWritable(_node);
            var _slot = _source;
            if (_available) _slot = CN_DLLObserveSlot(_entry);
            var _quantity = CN_DLLCommand({ op: "offer_deposit_slot", token: _token,
                destination: _destinations[_n], available: _available, live: _slot });
            if (_quantity == -13) { _result.reason = "source_changed"; break; }
            if (_quantity <= 0) continue;
            var _moved = CN_MoveContainerSlot(_entry.container, _entry.x, _entry.y, _node.container,
                                            _entry.item, _quantity, _entry.id);
            CN_DLLCommand({ op: "record_deposit_move", token: _token, moved: _moved.moved });
            if (_moved.reason == "source_changed") { _result.reason = "source_changed"; break; }
            if (_moved.moved > 0) CN_SyncHostChest(_node);
            if (_moved.moved == _quantity) break;
        }
        _result.moved = CN_DLLCommand({ op: "finish_deposit_route", token: _token });
    }
    catch (_error)
    {
        try { CN_DLLCommand({ op: "abort_deposit_route", token: _token }); }
        catch (_abort_error) { CN_ProbeLog("DEPOSIT ROUTE ABORT: " + string(_abort_error)); }
        throw _error;
    }
    _result.remaining -= _result.moved;
    _result.ok = _result.moved > 0;
    if (_result.remaining <= 0) _result.reason = "";
    return _result;
}

function CN_NativeRunDeposit()
{
    var _s = CN_NativeViewState();
    if (is_undefined(_s.pending_deposit)) return;
    var _request = _s.pending_deposit;
    _s.pending_deposit = undefined;
    if (is_undefined(_s.anchor) || _s.anchor.uid != _request.anchor) return;
    if (_request.client)
    {
        if (!CN_NativeCall("net_is_host", [])) CN_ClientQuickMove(_s, _request.entry, true);
        return;
    }
    var _result = CN_DepositInventoryAcrossNetwork(_s.anchor, _request.entry);
    CN_ProbeLog("NETWORK DEPOSIT RESULT: " + json_stringify(_result));
    _s.notice = (_result.moved > 0) ? "Перенесено: " + string(_result.moved) : "Нет места или перенос недоступен";
    _s.notice_tick = _s.tick + 180;
    _s.dirty = true;
}
