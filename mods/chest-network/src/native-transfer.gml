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
    if ((!_left && !_right) || !CN_NativeCall("net_is_host", [])) return;
    var _picked = CN_NativeCall("container_get_global_picked_item", []);
    if (CN_ReadItemQuantity(_picked) > 0) return;
    var _entries = CN_SnapshotSlots([{ container: INVENTORY }]);
    var _snapshot = CN_DLLCaptureSlots(_entries);
    if (!CN_ArmInventoryHit(INVENTORY, MOUSE_WINDOW_X, MOUSE_WINDOW_Y, GUI_SCALE)) return;
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
    _s.pending_deposit = { anchor: _s.anchor.uid, entry: _entry };
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
    _result.reason = "destination_full_or_restricted";
    for (var _n = 0; _n < array_length(_nodes); _n++)
    {
        // Recheck connectivity and identity immediately before each native write.
        if (!CN_ChestStillExists(_anchor)) { _result.reason = "network_unavailable"; break; }
        var _live = CN_BuildLoadedNetwork(_anchor, REGION);
        if (!CN_NetworkHasContainer(_live, _nodes[_n].container)) continue;
        if (!CN_HostChestWritable(_nodes[_n])) continue;
        var _current = Container.GetItem(INVENTORY, _entry.x, _entry.y);
        if (_current != _entry.item || CN_ReadItemQuantity(_current) != _result.remaining ||
            Item.GetProperty(_current, 0) != _entry.id)
        { _result.reason = "source_changed"; break; }
        var _moved = CN_MoveContainerSlot(INVENTORY, _entry.x, _entry.y, _nodes[_n].container,
                                        _current, _result.remaining, _entry.id);
        _result.moved += _moved.moved;
        _result.remaining -= _moved.moved;
        if (_moved.moved > 0) CN_SyncHostChest(_nodes[_n]);
        if (_result.remaining <= 0) break;
    }
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
    var _result = CN_DepositInventoryAcrossNetwork(_s.anchor, _request.entry);
    CN_ProbeLog("NETWORK DEPOSIT RESULT: " + json_stringify(_result));
    _s.notice = (_result.moved > 0) ? "Перенесено: " + string(_result.moved) : "Нет места или перенос недоступен";
    _s.notice_tick = _s.tick + 180;
    _s.dirty = true;
}
