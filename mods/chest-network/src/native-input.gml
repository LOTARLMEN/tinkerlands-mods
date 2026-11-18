// Reversible per-draw input guard. The stock frame stays open and visible.
function CN_CaptureNativeInput()
{
    var _keys = ["__MOUSE_WINDOW_X__", "__MOUSE_WINDOW_Y__",
                 "__K_MENU_LEFT_CLICK_PRESSED", "__K_MENU_RIGHT_CLICK_PRESSED",
                 "__K_CONTEXT_ACTION_1", "__K_CONTEXT_ACTION_2", "__K_CONTEXT_ACTION_3"];
    var _saved = [];
    for (var _n = 0; _n < array_length(_keys); _n++)
    {
        if (!variable_global_exists(_keys[_n])) throw "Native input unavailable: " + _keys[_n];
        array_push(_saved, { key: _keys[_n], value: variable_global_get(_keys[_n]) });
    }
    return _saved;
}

function CN_RestoreNativeInput(_saved)
{
    for (var _n = 0; _n < array_length(_saved); _n++)
        variable_global_set(_saved[_n].key, _saved[_n].value);
}

function CN_MaskNativeInput()
{
    variable_global_set("__MOUSE_WINDOW_X__", -100000);
    variable_global_set("__MOUSE_WINDOW_Y__", -100000);
    CN_MaskNativeActions();
}

function CN_MaskNativeActions()
{
    variable_global_set("__K_MENU_LEFT_CLICK_PRESSED", false);
    variable_global_set("__K_MENU_RIGHT_CLICK_PRESSED", false);
    variable_global_set("__K_CONTEXT_ACTION_1", false);
    variable_global_set("__K_CONTEXT_ACTION_2", false);
    variable_global_set("__K_CONTEXT_ACTION_3", false);
}

function CN_NativePointIn(_x, _y, _rect)
{
    return _x >= _rect.x && _y >= _rect.y && _x < _rect.x + _rect.w && _y < _rect.y + _rect.h;
}

// The player and the GUI have separate input signals. Consume the world
// press/hold for this step and leave the GUI and release signals available.
function CN_NativeConsumeItemUse()
{
    var _keys = ["__K_USE_ITEM", "__K_USE_ITEM_PRESSED", "__K_USE_ITEM_ALT", "__K_USE_ITEM_ALT_PRESSED"];
    for (var _n = 0; _n < array_length(_keys); _n++)
        if (variable_global_exists(_keys[_n])) variable_global_set(_keys[_n], false);
}

// Consume only the hotbar pulses produced by a wheel gesture owned by the
// chest. InputController refreshes these globals every Step. Do not restore
// the consumed pulse in Draw, where the stock hotbar could see it again.
function CN_NativeConsumeWheel(_layout, _up, _down)
{
    if ((!_up && !_down) || is_undefined(_layout)) return false;
    var _inside = MOUSE_WINDOW_X >= 10 * _layout.scale && MOUSE_WINDOW_X < 145 * _layout.scale &&
        MOUSE_WINDOW_Y >= _layout.top && MOUSE_WINDOW_Y < _layout.footer.y + _layout.footer.h;
    if (!_inside) return false;
    var _keys = ["__K_SELECT_ITEM_LEFT_PRESSED", "__K_SELECT_ITEM_RIGHT_PRESSED"];
    // Validate both before consuming either; these are the exact signals read
    // by player_input, not guessed key codes or persistent user bindings.
    for (var _n = 0; _n < array_length(_keys); _n++)
        if (!variable_global_exists(_keys[_n])) throw "Native wheel input unavailable: " + _keys[_n];
    for (var _n = 0; _n < array_length(_keys); _n++) variable_global_set(_keys[_n], false);
    return true;
}

function CN_DrawPhysicalSlot(_entry, _cx, _cy, _allow_input, _allow_hover, _stylesheet)
{
    var _saved = CN_CaptureNativeInput();
    if (!_allow_hover) CN_MaskNativeInput();
    else if (!_allow_input) CN_MaskNativeActions();
    try { CN_RenderPhysicalSlot(_entry, _cx, _cy, _stylesheet); }
    catch (_error) { CN_RestoreNativeInput(_saved); throw _error; }
    CN_RestoreNativeInput(_saved);
}

function CN_RenderPhysicalSlot(_entry, _cx, _cy, _stylesheet)
{
    var _old_style = undefined;
    var _changed_style = false;
    try
    {
        if (!is_undefined(_stylesheet))
        {
            _old_style = CN_NativeCall("container_get_stylesheet", [_entry.container]);
            _changed_style = _old_style != _stylesheet;
            if (_changed_style) CN_NativeCall("container_set_stylesheet", [_stylesheet, _entry.container]);
        }
        // Same native function as the original chest GUI. The first six
        // arguments are container, physical i/j, filter, screen centre x/y.
        CN_NativeCall("container_slot", [_entry.container, _entry.x, _entry.y, "", _cx, _cy]);
    }
    catch (_error)
    {
        if (_changed_style) CN_NativeCall("container_set_stylesheet", [_old_style, _entry.container]);
        throw _error;
    }
    if (_changed_style) CN_NativeCall("container_set_stylesheet", [_old_style, _entry.container]);
}
