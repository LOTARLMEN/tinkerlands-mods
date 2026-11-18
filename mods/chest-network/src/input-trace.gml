// Read engine signals at the end of GUI drawing. The DLL samples Windows input
// and decides when to write a record. No game input or container is modified.
function CN_TraceCall(_name)
{
    if (!variable_global_exists(_name)) return undefined;
    var _fn = variable_global_get(_name);
    if (!is_callable(_fn)) return undefined;
    try
    {
        if (is_method(_fn)) return method_call(_fn, []);
        return script_execute_ext(_fn, []);
    }
    catch (_error) { return undefined; }
}

function CN_TraceFlag(_name)
{
    if (!variable_global_exists(_name)) return undefined;
    return variable_global_get(_name);
}

function CN_TraceField(_instance, _name)
{
    if (!instance_exists(_instance) || !variable_instance_exists(_instance, _name)) return undefined;
    return variable_instance_get(_instance, _name);
}

function CN_TraceState()
{
    if (!variable_global_exists("__cn_input_trace"))
        variable_global_set("__cn_input_trace", { fn: -1, failed: false, ready: false });
    return variable_global_get("__cn_input_trace");
}

function CN_TraceLog(_message)
{
    var _file = file_text_open_append("chest_network_input_trace.log");
    if (_file < 0) return;
    file_text_write_string(_file, _message);
    file_text_writeln(_file);
    file_text_close(_file);
}

function CN_TraceObserve(_state)
{
    var _world = instance_exists(objGUIIngameController);
    if (!_state.ready && !_world && !instance_exists(objMenuMain)) return;
    if (_state.fn == -1)
    {
        var _dll = "mods/native/chest-network/tinkerlands_storage.dll";
        _state.fn = external_define(_dll, "TCS_ObserveInput", dll_cdecl, ty_real, 4, ty_real, ty_real, ty_real, ty_real);
    }
    var _controller = instance_find(objInputController, 0);
    var _input_mode = CN_TraceField(_controller, "input_active");
    if (!is_numeric(_input_mode)) _input_mode = -1000;
    var _player = noone;
    if (_world && instance_exists(objPlayer) && !is_undefined(MY_PLAYER)) _player = MY_PLAYER;
    var _storage = CN_TraceFlag("__cn_native_view");
    var _search = false;
    var _lease = false;
    var _storage_window = false;
    var _draw_guard = false;
    if (is_struct(_storage))
    {
        _search = _storage.focused;
        _lease = _storage.input_lease;
        _storage_window = !is_undefined(_storage.layout);
        _draw_guard = array_length(_storage.saved_input) > 0;
    }
    var _gm_rmb = mouse_check_button(mb_right);
    var _gm_rmb_pressed = mouse_check_button_pressed(mb_right);
    var _gm_rmb_released = mouse_check_button_released(mb_right);
    var _values = [
        _world, undefined, CN_TraceCall("net_is_connected"), CN_TraceCall("net_is_host"),
        _gm_rmb, _gm_rmb_pressed, _gm_rmb_released, CN_TraceFlag("__K_USE_ITEM_ALT"),
        CN_TraceFlag("__K_INTERACT_PRESSED"), CN_TraceFlag("__K_MENU_RIGHT_CLICK_PRESSED"),
        CN_TraceField(_player, "canUseActions"), _search, _lease, _storage_window,
        CN_TraceField(_player, "canMove"), _draw_guard, CN_TraceFlag("__K_MENU_RIGHT_CLICK")
    ];
    var _known = 0;
    var _signals = 0;
    var _flag = 1;
    for (var _i = 0; _i < array_length(_values); _i++)
    {
        var _value = _values[_i];
        if (is_bool(_value) || is_numeric(_value))
        {
            _known += _flag;
            if (_value) _signals += _flag;
        }
        _flag *= 2;
    }
    var _players = instance_number(objPlayer);
    var _result = external_call(_state.fn, _known, _signals, _input_mode, _players);
    if (_result != 1) throw "Input trace DLL refused sample " + string(_result);
    if (!_state.ready)
    {
        _state.ready = true;
        CN_TraceLog("Input trace ready 0.0.1");
    }
}

OnModDrawGUIEnd(function()
{
    var _state = CN_TraceState();
    if (_state.failed) return;
    try { CN_TraceObserve(_state); }
    catch (_error) { _state.failed = true; CN_TraceLog("Input trace disabled: " + string(_error)); }
});
