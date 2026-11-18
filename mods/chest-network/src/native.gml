// Calls are resolved from the installed game's actual exported globals.
// Contracts are verified by disposable-container probes before use on real chests.

function CN_NativeCall(_name, _args)
{
    if (!variable_global_exists(_name)) throw "Native function unavailable: " + _name;
    var _function = variable_global_get(_name);
    if (!is_callable(_function)) throw "Native value is not callable: " + _name;
    if (is_method(_function)) return method_call(_function, _args);
    return script_execute_ext(_function, _args);
}

function CN_ReadItemQuantity(_item)
{
    if (is_undefined(_item)) return 0;
    if (!is_numeric(_item) || !ds_exists(_item, ds_type_map)) return 0;
    // Runtime property 114 verified in probe 0.0.4 against the native export
    // and a seven-item transfer in both directions. Maximum stack uses key 6.
    if (!ds_map_exists(_item, 114)) return 0;
    var _quantity = Item.GetProperty(_item, 114);
    if (!is_numeric(_quantity) || _quantity < 0) return 0;
    return _quantity;
}

function CN_ContainerQuantity(_container, _item_id)
{
    if (!Container.Exists(_container)) return 0;
    var _seen = {};
    var _total = 0;
    for (var _y = 0; _y < Container.GetHeight(_container); _y++)
    {
        for (var _x = 0; _x < Container.GetWidth(_container); _x++)
        {
            var _item = Container.GetItem(_container, _x, _y);
            var _quantity = CN_ReadItemQuantity(_item);
            if (_quantity <= 0) continue;
            var _key = string(_item);
            if (variable_struct_exists(_seen, _key)) continue;
            variable_struct_set(_seen, _key, true);
            if (Item.GetProperty(_item, 0) == _item_id) _total += _quantity;
        }
    }
    return _total;
}

function CN_MoveContainerSlot(_source, _x, _y, _destination, _expected_item, _expected_quantity, _expected_id)
{
    var _result = { ok: false, moved: 0, reason: "", remaining: 0 };
    var _source_exists = Container.Exists(_source);
    var _destination_exists = Container.Exists(_destination);
    var _width = 0;
    var _height = 0;
    var _item = undefined;
    if (_source_exists)
    {
        _width = Container.GetWidth(_source);
        _height = Container.GetHeight(_source);
        // Observation must not call the engine with an invalid cell.
        if (_x >= 0 && _y >= 0 && _x < _width && _y < _height)
            _item = Container.GetItem(_source, _x, _y);
    }
    var _quantity = CN_ReadItemQuantity(_item);
    var _id = -1;
    if (_quantity > 0) _id = Item.GetProperty(_item, 0);
    if (is_undefined(_expected_id)) _expected_id = _id;
    var _observed = CN_DLLSlot(_source, _x, _y, _item, _quantity, _id, false);
    var _expected = CN_DLLSlot(_source, _x, _y, _expected_item, _expected_quantity, _expected_id, false);
    var _check = CN_DLLCommand({ op: "check_move", source: _observed, expected: _expected,
                                destination: string(_destination), width: _width, height: _height,
                                source_exists: _source_exists, destination_exists: _destination_exists });
    if (_check < 0)
    {
        _result.reason = "source_changed";
        if (_check == -10) _result.reason = "container_unavailable";
        if (_check == -11) _result.reason = "same_container";
        if (_check == -12) _result.reason = "invalid_slot";
        return _result;
    }
    var _source_before = CN_ContainerQuantity(_source, _id);
    var _destination_before = CN_ContainerQuantity(_destination, _id);
    CN_NativeCall("container_item_move", [_item, _destination]);
    var _source_after = CN_ContainerQuantity(_source, _id);
    var _destination_after = CN_ContainerQuantity(_destination, _id);
    _result.moved = CN_DLLCommand({ op: "verify", quantity: _quantity,
                                   source_before: _source_before, source_after: _source_after,
                                   destination_before: _destination_before, destination_after: _destination_after });
    _result.remaining = _quantity - _result.moved;
    _result.ok = _result.moved > 0;
    if (!_result.ok) _result.reason = "destination_full_or_restricted";
    return _result;
}
