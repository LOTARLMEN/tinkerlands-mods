// Inspection for the disposable startup probe.
function CN_InspectNativeContainer(_container)
{
    var _report = {};
    var _getters = ["x", "y", "width", "height", "grid_width", "grid_height",
                    "cell_width", "cell_height", "border", "header", "open", "interactable", "depth", "scale"];
    for (var _n = 0; _n < array_length(_getters); _n++)
    {
        var _name = _getters[_n];
        var _value = CN_NativeCall("container_get_" + _name, [_container]);
        variable_struct_set(_report, _name, string(_value));
    }
    // The runtime container uses internal keys. Record their types/primitive
    // values for investigation; never write them based on inferred offsets.
    var _fields = {};
    var _key = ds_map_find_first(_container);
    var _count = 0;
    while (!is_undefined(_key) && _count < 128)
    {
        var _value = ds_map_find_value(_container, _key);
        if (is_numeric(_value) || is_string(_value) || is_bool(_value))
            variable_struct_set(_fields, string(_key), string(_value));
        _count++;
        _key = ds_map_find_next(_container, _key);
    }
    _report.fields = _fields;
    return _report;
}

