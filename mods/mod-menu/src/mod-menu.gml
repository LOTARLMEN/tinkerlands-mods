// Catalog adapters only read collections; compatibility policy is in its own module.
function MM_Field(_value, _key)
{
    if (is_struct(_value))
    {
        if (variable_struct_exists(_value, _key)) return variable_struct_get(_value, _key);
    }
    else if (is_numeric(_value) && ds_exists(_value, ds_type_map))
    {
        if (ds_map_exists(_value, _key)) return ds_map_find_value(_value, _key);
    }
    return undefined;
}

function MM_Text(_value, _fallback)
{
    if (is_string(_value) && _value != "") return _value;
    if (is_numeric(_value)) return string(_value);
    return _fallback;
}

function MM_SequenceSize(_value)
{
    if (is_array(_value)) return array_length(_value);
    if (is_numeric(_value) && ds_exists(_value, ds_type_list)) return ds_list_size(_value);
    throw "Unsupported loader/menu collection";
}

function MM_SequenceAt(_value, _index)
{
    if (is_array(_value)) return _value[_index];
    return ds_list_find_value(_value, _index);
}

function MM_Normalize(_record, _fallback_name)
{
    var _info = MM_Field(_record, "info");
    if (is_undefined(_info)) _info = _record;
    return {
        name: MM_Text(MM_Field(_info, "name"), _fallback_name),
        version: MM_Text(MM_Field(_info, "version"), "Не указана"),
        author: MM_Text(MM_Field(_info, "author"), "Не указан"),
        description: MM_Text(MM_Field(_info, "description"), "Описание отсутствует.")
    };
}

function MM_ReadCatalog()
{
    if (!variable_global_exists("__MOD_LIST__")) throw "Loader list __MOD_LIST__ unavailable";
    var _list = variable_global_get("__MOD_LIST__");
    var _s = MM_State();
    if (is_array(_s.loaded_files)) _list = _s.loaded_files;
    var _count = MM_SequenceSize(_list);
    if (_count > 4096) throw "Unexpectedly large loader list";
    var _map = undefined;
    if (variable_global_exists("__MOD_MAP__")) _map = variable_global_get("__MOD_MAP__");
    var _items = [];
    for (var _n = 0; _n < _count; _n++)
    {
        var _record = MM_SequenceAt(_list, _n);
        var _fallback = "Без названия";
        if (is_string(_record))
        {
            _fallback = _record;
            var _details = MM_ArchiveInfo(_record);
            if (is_undefined(_details)) _details = MM_Field(_map, _record);
            if (!is_undefined(_details)) _record = _details;
        }
        if (!is_struct(_record) && !is_string(_record) && !(is_numeric(_record) && ds_exists(_record, ds_type_map))) throw "Unsupported mod record";
        array_push(_items, MM_Normalize(_record, _fallback));
    }
    return _items;
}

function MM_ArchiveInfo(_filename)
{
    var _s = MM_State();
    if (!variable_struct_exists(_s.metadata, _filename)) return undefined;
    var _entry = variable_struct_get(_s.metadata, _filename);
    if (!is_struct(_entry) || !is_string(MM_Field(_entry, "path")) || !is_string(MM_Field(_entry, "sha1"))) return undefined;
    if (!file_exists(_entry.path)) return undefined;
    // Reject metadata for an archive that has changed since the launch index.
    if (sha1_file(_entry.path) != _entry.sha1) return undefined;
    return MM_Field(_entry, "info");
}

// Word wrapping also breaks unspaced long names/URLs. A newline is always preserved.
function MM_Wrap(_text, _columns)
{
    var _lines = [];
    var _line = "";
    var _word = "";
    _columns = max(1, floor(_columns));
    var _clean = string_replace_all(string(_text), "\r", "");
    for (var _i = 1; _i <= string_length(_clean) + 1; _i++)
    {
        var _char = "\n";
        if (_i <= string_length(_clean)) _char = string_char_at(_clean, _i);
        if (_char == " " || _char == "\n" || _char == "\t")
        {
            if (_word != "")
            {
                if (_line != "" && string_length(_line) + 1 + string_length(_word) > _columns)
                {
                    array_push(_lines, _line);
                    _line = "";
                }
                if (_line != "") _line += " ";
                _line += _word;
                _word = "";
            }
            if (_char == "\n") { array_push(_lines, _line); _line = ""; }
        }
        else
        {
            _word += _char;
            if (string_length(_word) >= _columns)
            {
                if (_line != "") { array_push(_lines, _line); _line = ""; }
                array_push(_lines, _word);
                _word = "";
            }
        }
    }
    return _lines;
}


// Only our canonical, content-free archive is exempt. Never infer exemptions
// from a filename pattern, metadata supplied by another mod, or a missing API.
function MM_IsFileList(_value)
{
    if (!is_array(_value)) return false;
    if (array_length(_value) > 4096) return false;
    for (var _n = 0; _n < array_length(_value); _n++)
    {
        if (!is_string(_value[_n])) return false;
    }
    return true;
}

function MM_CopyFileList(_value)
{
    if (!MM_IsFileList(_value)) throw "Unsupported compatibility list";
    var _copy = [];
    for (var _n = 0; _n < array_length(_value); _n++) array_push(_copy, _value[_n]);
    return _copy;
}

function MM_WithoutMenu(_value)
{
    if (!MM_IsFileList(_value)) throw "Unsupported compatibility list";
    var _filtered = [];
    for (var _n = 0; _n < array_length(_value); _n++)
    {
        if (_value[_n] != "mod_menu.mod") array_push(_filtered, _value[_n]);
    }
    return _filtered;
}

function MM_SameFileList(_left, _right)
{
    if (!MM_IsFileList(_left) || !MM_IsFileList(_right)) return false;
    if (array_length(_left) != array_length(_right)) return false;
    for (var _n = 0; _n < array_length(_left); _n++)
    {
        if (_left[_n] != _right[_n]) return false;
    }
    return true;
}

function MM_PrepareCompatibility()
{
    var _s = MM_State();
    if (!variable_global_exists("__MOD_LIST__")) throw "Native compatibility list unavailable";
    var _native = variable_global_get("__MOD_LIST__");
    // Preserve the actual loaded archives for the browser before changing the
    // separate native list consumed by world comparison and WorldSaver.update.
    var _loaded = MM_CopyFileList(_native);
    var _effective = MM_WithoutMenu(_native);
    _s.loaded_files = _loaded;
    if (array_length(_loaded) == array_length(_effective))
    {
        MM_Log("COMPATIBILITY UNCHANGED: canonical mod_menu.mod not present");
        return;
    }
    variable_global_set("__MOD_LIST__", _effective);
    var _readback = variable_global_get("__MOD_LIST__");
    if (!MM_SameFileList(_readback, _effective))
    {
        variable_global_set("__MOD_LIST__", _native);
        throw "Compatibility list verification failed; restored original";
    }
    _s.compatibility_ready = true;
    MM_Log("COMPATIBILITY: " + json_stringify({ loaded: _loaded, world_dependencies: _readback }));
}

// A new outer array and new supported inner arrays keep native preloaded
// metadata and files unchanged. Unknown entries remain exactly as supplied.
function MM_NormalizeWorldLists(_source)
{
    var _result = { supported: false, lists: _source, changed: 0, unknown: 0, snapshots: [] };
    if (!is_array(_source)) return _result;
    if (array_length(_source) > 256) return _result;
    var _lists = [];
    for (var _slot = 0; _slot < array_length(_source); _slot++)
    {
        var _original = _source[_slot];
        if (MM_IsFileList(_original))
        {
            var _filtered = MM_WithoutMenu(_original);
            if (!MM_SameFileList(_original, _filtered)) _result.changed++;
            array_push(_lists, _filtered);
            if (array_length(_original) > 0 && array_length(_result.snapshots) < 16)
            {
                var _snapshot = { slot: _slot, before: MM_CopyFileList(_original), after: MM_CopyFileList(_filtered) };
                array_push(_result.snapshots, _snapshot);
            }
        }
        else
        {
            array_push(_lists, _original);
            _result.unknown++;
        }
    }
    _result.supported = true;
    _result.lists = _lists;
    return _result;
}

function MM_NormalizeMenuCompatibility(_owner)
{
    var _s = MM_State();
    if (!_s.compatibility_ready) return;
    if (!variable_instance_exists(_owner, "savegamesModList")) throw "World-list preview table unavailable";
    var _original = variable_instance_get(_owner, "savegamesModList");
    var _result = MM_NormalizeWorldLists(_original);
    if (!_result.supported) throw "Unsupported world-list preview table";
    if (_result.changed > 0) variable_instance_set(_owner, "savegamesModList", _result.lists);
    MM_Log("WORLD COMPATIBILITY PREVIEW: " + json_stringify({ changed: _result.changed, unknown: _result.unknown, worlds: _result.snapshots }));
}


function MM_State()
{
    return variable_global_get("__mm_browser");
}

function MM_Log(_text)
{
    var _file = file_text_open_append("mod_menu.log");
    if (_file < 0) return;
    file_text_write_string(_file, _text);
    file_text_writeln(_file);
    file_text_close(_file);
}

function MM_Call(_owner, _key, _args)
{
    var _fn = MM_Field(_owner, _key);
    if (!is_callable(_fn)) throw "Menu method unavailable: " + _key;
    return method_call(method(_owner, _fn), _args);
}

function MM_Refresh()
{
    var _s = MM_State();
    _s.items = [];
    _s.error = "";
    _s.selected = 0;
    _s.scroll = 0;
    _s.description_scroll = 0;
    _s.lines = [];
    try
    {
        _s.items = MM_ReadCatalog();
        MM_Log("CATALOG: " + json_stringify(_s.items));
    }
    catch (_error)
    {
        _s.error = "Не удалось прочитать список модов.";
        MM_Log("CATALOG ERROR: " + string(_error));
    }
    _s.text_dirty = true;
}

function MM_Open()
{
    var _s = MM_State();
    if (!_s.hooked || _s.loading || !instance_exists(objMenuMain)) return;
    MM_Refresh();
    MM_Call(_s.controller, "goto", [_s.page]);
    Input.DisableMenuInputs(0.15);
    MM_Log("OPEN");
}

function MM_Close()
{
    var _s = MM_State();
    if (_s.hooked && !_s.loading && instance_exists(objMenuMain)) MM_Call(_s.controller, "goto", [_s.main]);
    Input.DisableMenuInputs(0.15);
    MM_Log("CLOSE");
}

function MM_MenuField(_instance, _name)
{
    if (variable_instance_exists(_instance, _name)) return variable_instance_get(_instance, _name);
    if (variable_global_exists(_name)) return variable_global_get(_name);
    return undefined;
}

function MM_HookMenu(_owner)
{
    var _s = MM_State();
    try { MM_NormalizeMenuCompatibility(_owner); }
    catch (_error) { MM_Log("WORLD COMPATIBILITY PREVIEW ERROR: " + string(_error)); }
    var _controller = MM_MenuField(_owner, "menuController");
    var _main = MM_MenuField(_owner, "menuMain");
    if (!is_struct(_controller) || !is_struct(_main)) throw "Main menu structures unavailable";
    var _menu_depth = variable_instance_get(_owner, "depth");
    var _old_depth = variable_instance_get(_s.renderer, "depth");
    MM_Log("RENDERER: " + json_stringify({ id: string(_s.renderer), visible: variable_instance_get(_s.renderer, "visible"), menu_depth: _menu_depth, depth_before: _old_depth }));
    // Main-menu Draw GUI End paints its background in the same event as objMod.
    // Lower depth draws our page after that background, including GUI End.
    variable_instance_set(_s.renderer, "depth", _menu_depth - 100);
    variable_instance_set(_s.renderer, "visible", true);
    var _components = MM_Field(_main, "components");
    var _count = MM_SequenceSize(_components);
    if (_count < 2) throw "Main menu button prototypes unavailable";
    var _last = MM_SequenceAt(_components, _count - 1);
    var _before = MM_SequenceAt(_components, _count - 2);
    var _first = MM_SequenceAt(_components, 0);
    var _gap = abs(_last.y - _before.y);
    if (_gap < 8) throw "Unsupported main menu layout";
    // A separate native page keeps underlying main-menu components inactive.
    MM_Log("CONTROLLER: " + json_stringify({ fields: variable_struct_get_names(_controller), menus_array: is_array(_controller.menus), method: is_method(_controller.add_menu), components_array: is_array(_components) }));
    var _page = MM_Call(_controller, "add_menu", []);
    if (!is_struct(_page) || is_undefined(MM_Field(_page, "index"))) throw "Native menu page unavailable";
    var _data = {};
    var _names = variable_struct_get_names(_last.data);
    for (var _n = 0; _n < array_length(_names); _n++) variable_struct_set(_data, _names[_n], variable_struct_get(_last.data, _names[_n]));
    _data.text = "Моды";
    _s.controller = _controller;
    _s.main = _main;
    _s.page = _page;
    // Native MenuComponent executes a native GML callback, not a ModExt VM value.
    // Rebind the game's existing single-player navigation to our isolated page.
    // It only calls menuController.goto(menuCharacters) and sets joiningOnlineGame.
    var _navigation = { menuController: _controller, menuCharacters: _page, joiningOnlineGame: false };
    var _callback = method(_navigation, _first.callback);
    if (!is_method(_callback)) throw "Native navigation callback unavailable";
    _s.button = MM_Call(_main, "add_component", [_last.x, _last.y - _gap, _last.type, _data, _callback]);
    // Preserve the bottom Exit button and make room above it.
    for (var _c = 0; _c < _count - 1; _c++)
    {
        var _component = MM_SequenceAt(_components, _c);
        _component.y -= _gap;
    }
    _s.hooked = true;
    MM_Log("MENU HOOKED: " + json_stringify({ owner: string(_owner), count_before: _count, page: _page.index, data_fields: _names, x: _last.x, y: _last.y - _gap, type: string(_last.type) }));
}

function MM_Visible()
{
    var _s = MM_State();
    return _s.hooked && !_s.loading && instance_exists(objMenuMain) && _s.controller.currentMenuIndex == _s.page.index;
}

// Diagnostic status contains observations only; no command file executes game code.
function MM_Status()
{
    var _s = MM_State();
    var _file = file_text_open_write("mod_menu_status.json");
    if (_file < 0) return;
    var _status = { version: "0.1.6", hooked: _s.hooked, loading: _s.loading, visible: MM_Visible(), error: _s.error, mods: _s.items, draw_calls: _s.draw_calls, visible_draws: _s.visible_draws, compatibility_ready: _s.compatibility_ready };
    if (_s.hooked) { _status.current_page = _s.controller.currentMenuIndex; _status.mods_page = _s.page.index; }
    file_text_write_string(_file, json_stringify(_status));
    file_text_close(_file);
}

OnModLoad(function()
{
    variable_global_set("__mm_browser", {
        owner: undefined, hooked: false, hook_failed: false, loading: false,
        controller: undefined, main: undefined, page: undefined, button: undefined,
        items: [], error: "", selected: 0, scroll: 0, description_scroll: 0,
        text_dirty: true, lines: [], columns: 0, status_ticks: 0, draw_failed: false,
        metadata: {}, was_visible: false, pending: "", renderer: id,
        draw_calls: 0, visible_draws: 0, draw_stage: "",
        loaded_files: undefined, compatibility_ready: false
    });
    var _file = file_text_open_write("mod_menu.log");
    if (_file >= 0) { file_text_write_string(_file, "Mod Menu 0.1.6"); file_text_writeln(_file); file_text_close(_file); }
    try { MM_PrepareCompatibility(); }
    catch (_error) { MM_Log("COMPATIBILITY ERROR: " + string(_error)); }
    try
    {
        if (file_exists("mod_menu_catalog.json"))
        {
            var _index_file = file_text_open_read("mod_menu_catalog.json");
            if (_index_file >= 0)
            {
                var _index_text = "";
                while (!file_text_eof(_index_file)) { _index_text += file_text_read_string(_index_file); file_text_readln(_index_file); }
                file_text_close(_index_file);
                var _index = json_parse(_index_text);
                if (is_struct(_index) && is_struct(MM_Field(_index, "archives"))) MM_State().metadata = _index.archives;
            }
        }
    }
    catch (_error) { MM_Log("METADATA INDEX ERROR: " + string(_error)); }
    MM_Refresh();
});

OnWorldGenerationStart(function()
{
    var _s = MM_State();
    _s.loading = true;
});

OnModUpdate(function()
{
    var _s = MM_State();
    if (!instance_exists(objMenuMain))
    {
        _s.owner = undefined;
        _s.hooked = false;
        return;
    }
    var _owner = instance_find(objMenuMain, 0);
    if (_s.owner != _owner)
    {
        _s.owner = _owner;
        _s.hooked = false;
        _s.hook_failed = false;
        _s.loading = false;
        _s.draw_failed = false;
    }
    if (_s.loading) return;
    if (!_s.hooked && !_s.hook_failed)
    {
        try { MM_HookMenu(_owner); }
        catch (_error) { _s.hook_failed = true; MM_Log("MENU HOOK ERROR: " + string(_error)); }
        MM_Status();
    }
    // One-shot local preview of our own UI, only in the main menu.
    // The exact version prevents a request from a previous build being reused.
    if (_s.hooked && file_exists("mod_menu_preview.request"))
    {
        var _preview_file = file_text_open_read("mod_menu_preview.request");
        var _preview_version = "";
        if (_preview_file >= 0) { _preview_version = file_text_read_string(_preview_file); file_text_close(_preview_file); }
        file_delete("mod_menu_preview.request");
        if (_preview_version == "0.1.6") MM_Open();
    }
    var _visible = MM_Visible();
    if (_visible && !_s.was_visible) { MM_Refresh(); MM_Log("OPEN"); }
    _s.was_visible = _visible;
    if (_visible && (_s.pending == "close" || keyboard_check_pressed(vk_escape)))
    {
        MM_Close();
        keyboard_clear(vk_escape);
    }
    else if (_visible && _s.pending == "refresh") MM_Refresh();
    _s.pending = "";
    _s.status_ticks++;
    if (_s.status_ticks >= 120) { _s.status_ticks = 0; MM_Status(); }
});


function MM_FitLabel(_text, _width, _scale)
{
    var _limit = max(3, floor(_width / (7 * _scale)));
    if (string_length(_text) <= _limit) return _text;
    return string_copy(_text, 1, _limit - 1) + "…";
}

function MM_DrawAction(_cx, _cy, _width, _height, _label, _action)
{
    var _left = _cx - _width * 0.5;
    var _top = _cy - _height * 0.5;
    GUI.DrawContainer(_left, _top, _width, _height);
    GUI.DrawText(_cx, _cy, _label, 5);
    if (mouse_check_button_pressed(mb_left) && point_in_rectangle(MOUSE_WINDOW_X, MOUSE_WINDOW_Y, _left, _top, _left + _width, _top + _height))
    {
        MM_State().pending = _action;
        mouse_clear(mb_left);
    }
}

function MM_Draw()
{
    if (!MM_Visible()) return;
    var _s = MM_State();
    _s.visible_draws++;
    _s.draw_stage = "dimensions";
    var _scale = GUI_SCALE;
    var _font_scale = _scale * 0.8;
    var _window = variable_global_get("__WINDOW");
    var _gw = _window.width;
    var _gh = _window.height;
    var _width = min(480 * _scale, _gw - 24 * _scale);
    var _height = min(260 * _scale, _gh - 24 * _scale);
    var _x = floor((_gw - _width) * 0.5);
    var _y = floor((_gh - _height) * 0.5);
    var _pad = 10 * _scale;
    var _left_width = floor(_width * 0.37);
    var _right_x = _x + _left_width + 2 * _pad;
    var _right_width = _width - _left_width - 3 * _pad;
    var _body_y = _y + 40 * _scale;
    var _body_h = _height - 64 * _scale;
    var _row_h = 25 * _scale;
    var _rows = max(1, floor(_body_h / _row_h));
    if (_s.visible_draws == 1) MM_Log("LAYOUT: " + json_stringify({ width: _gw, height: _gh, scale: _scale, panel_x: _x, panel_y: _y, panel_w: _width, panel_h: _height }));
    _s.draw_stage = "panel";
    GUI.DrawContainer(_x, _y, _width, _height);
    _s.draw_stage = "title";
    GUI.DrawText(_x + _pad, _y + 8 * _scale, "Моды", 7);
    _s.draw_stage = "count";
    var _count = array_length(_s.items);
    var _caption = "Загружено: " + string(_count);
    GUI.DrawText(_x + _pad, _y + 23 * _scale, _caption, 7, c_white, 1, _font_scale);
    MM_DrawAction(_x + _width - 42 * _scale, _y + 17 * _scale, 62 * _scale, 18 * _scale, "Назад", "close");
    if (_s.error != "")
    {
        GUI.DrawText(_x + _pad, _body_y, _s.error, 7, c_white, 1, _font_scale);
        MM_DrawAction(_x + 55 * _scale, _body_y + 30 * _scale, 90 * _scale, 20 * _scale, "Повторить", "refresh");
        return;
    }
    if (_count == 0) { GUI.DrawText(_x + _pad, _body_y, "Загруженных модов нет.", 7); return; }
    _s.draw_stage = "list input";
    var _mx = MOUSE_WINDOW_X;
    var _my = MOUSE_WINDOW_Y;
    var _left_hover = point_in_rectangle(_mx, _my, _x + _pad, _body_y, _x + _pad + _left_width, _body_y + _body_h);
    if (_left_hover)
    {
        if (mouse_wheel_down()) _s.scroll++;
        if (mouse_wheel_up()) _s.scroll--;
    }
    _s.scroll = clamp(_s.scroll, 0, max(0, _count - _rows));
    var _click = mouse_check_button_pressed(mb_left);
    _s.draw_stage = "list rows";
    for (var _r = 0; _r < _rows; _r++)
    {
        var _index = _s.scroll + _r;
        if (_index >= _count) break;
        var _row_y = _body_y + _r * _row_h;
        var _hover = point_in_rectangle(_mx, _my, _x + _pad, _row_y, _x + _pad + _left_width, _row_y + _row_h - 2 * _scale);
        GUI.DrawContainer(_x + _pad, _row_y, _left_width, _row_h - 2 * _scale);
        var _color = c_white;
        if (_index == _s.selected) _color = c_yellow;
        var _name_label = MM_FitLabel(_s.items[_index].name, _left_width - 10 * _scale, _font_scale);
        var _version_label = MM_FitLabel(_s.items[_index].version, _left_width - 10 * _scale, _font_scale * 0.8);
        GUI.DrawText(_x + _pad + 5 * _scale, _row_y + 3 * _scale, _name_label, 7, _color, 1, _font_scale);
        GUI.DrawText(_x + _pad + 5 * _scale, _row_y + 13 * _scale, _version_label, 7, c_white, 1, _font_scale * 0.8);
        if (_hover && _click)
        {
            _s.selected = _index;
            _s.description_scroll = 0;
            _s.text_dirty = true;
            mouse_clear(mb_left);
        }
    }
    _s.draw_stage = "description";
    var _selected = _s.items[_s.selected];
    var _columns = max(8, floor(_right_width / (7 * _font_scale)));
    if (_s.text_dirty || _s.columns != _columns)
    {
        var _text = _selected.name + "\nВерсия: " + _selected.version + "\nАвтор: " + _selected.author + "\n\n" + _selected.description;
        _s.lines = MM_Wrap(_text, _columns);
        _s.columns = _columns;
        _s.text_dirty = false;
    }
    var _line_h = 12 * _scale;
    var _line_count = max(1, floor(_body_h / _line_h));
    var _right_hover = point_in_rectangle(_mx, _my, _right_x, _body_y, _right_x + _right_width, _body_y + _body_h);
    if (_right_hover)
    {
        if (mouse_wheel_down()) _s.description_scroll += 2;
        if (mouse_wheel_up()) _s.description_scroll -= 2;
    }
    _s.description_scroll = clamp(_s.description_scroll, 0, max(0, array_length(_s.lines) - _line_count));
    for (var _l = 0; _l < _line_count; _l++)
    {
        var _at = _s.description_scroll + _l;
        if (_at >= array_length(_s.lines)) break;
        GUI.DrawText(_right_x, _body_y + _l * _line_h, _s.lines[_at], 7, c_white, 1, _font_scale);
    }
    GUI.DrawText(_x + _pad, _y + _height - 15 * _scale, "Выберите мод | Колесо мыши — прокрутка | Esc — назад", 7, c_white, 1, _font_scale * 0.8);
}

OnModDrawGUIEnd(function()
{
    var _s = MM_State();
    _s.draw_calls++;
    if (_s.draw_failed) return;
    try { MM_Draw(); }
    catch (_error)
    {
        _s.draw_failed = true;
        MM_Log("DRAW ERROR at " + string(_s.draw_stage) + ": " + string(_error));
        MM_Close();
    }
});
