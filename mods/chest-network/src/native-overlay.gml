// Extend the existing chest frame. No Container.Open/Close, virtual inventory,
// replacement window, physical sorting or copying of item maps is used here.
function CN_NativeViewState()
{
    if (!variable_global_exists("__cn_native_view"))
        variable_global_set("__cn_native_view", {
            anchor: undefined, nodes: [], sources: [], view: [], types: [""],
            query: "", type: "", sort: "source", page: 0, tick: 0, order_log_pending: false,
            dirty: true, view_dirty: true, network_dirty: true, layout: undefined,
            renderer: undefined, old_depth: 0, changed_depth: false,
            saved_input: [], focused: false, search_id: undefined, locked_player: undefined,
            saved_move: true, saved_actions: true, slot_ready: false, controls_ready: false, failed: false,
            input_controller: undefined, input_lease: false, saved_input_mode: 0,
            manual_click: false, wheel_logged: false,
            search_activate: false, scroll_drag: false, scroll_grab: 0, occupied: 0,
            deposit_hit: undefined, pending_deposit: undefined, notice: "", notice_tick: 0,
            client_block_logged: false, drag_armed: false, drop_released: false,
            cursor_probe_pending: false, draw_probe_pending: false,
            profile_refresh_us: 0, profile_draw_us: 0
        });
    return variable_global_get("__cn_native_view");
}

function CN_NativeRestoreGuard()
{
    var _s = CN_NativeViewState();
    CN_RestoreNativeInput(_s.saved_input);
    _s.saved_input = [];
}

function CN_NativeReleaseFocus()
{
    var _s = CN_NativeViewState();
    if (_s.input_lease && instance_exists(_s.input_controller))
    {
        var _mode = variable_instance_get(_s.input_controller, "input_active");
        // Preserve a stronger native lock (lost window focus, chat, etc.).
        if (_mode <= 5) variable_instance_set(_s.input_controller, "input_active", _s.saved_input_mode);
    }
    _s.input_lease = false;
    if (!is_undefined(_s.locked_player) && instance_exists(_s.locked_player))
    {
        variable_instance_set(_s.locked_player, "canMove", _s.saved_move);
        variable_instance_set(_s.locked_player, "canUseActions", _s.saved_actions);
    }
    _s.locked_player = undefined;
    _s.focused = false;
    if (!is_undefined(_s.search_id))
    {
        var _input = static_get(GUI.DrawInput);
        if (is_struct(_input) && variable_struct_exists(_input, "selected"))
            if (_input.selected == _s.search_id) _input.selected = -1;
        _s.search_id = undefined;
    }
}

function CN_NativeFocusSearch()
{
    var _s = CN_NativeViewState();
    if (_s.focused) return;
    var _controller = instance_find(objInputController, 0);
    if (!instance_exists(_controller) || !variable_instance_exists(_controller, "input_active"))
        throw "Native keyboard capture unavailable";
    _s.input_controller = _controller;
    _s.saved_input_mode = variable_instance_get(_controller, "input_active");
    _s.input_lease = true;
    _s.focused = true;
    CN_NativeKeepKeyboardCapture();
    CN_ProbeLog("SEARCH FOCUS: native input_active before=" + string(_s.saved_input_mode) + "; capture=5");
}

function CN_NativeKeepKeyboardCapture()
{
    var _s = CN_NativeViewState();
    if (!_s.focused || !_s.input_lease) return;
    var _mode = variable_instance_get(_s.input_controller, "input_active");
    // This is the same input_active=5 mode used by get_chat_is_writting in
    // objInputController.Step, refreshed while our own text field has focus.
    variable_instance_set(_s.input_controller, "input_active", max(_mode, 5));
}

function CN_NativeReadSearch()
{
    var _s = CN_NativeViewState();
    if (!_s.focused) return;
    CN_NativeKeepKeyboardCapture();
    if (keyboard_check_pressed(vk_escape) || keyboard_check_pressed(vk_enter))
    {
        CN_NativeReleaseFocus();
        return;
    }
}

function CN_NativeApplyQuery(_value)
{
    var _s = CN_NativeViewState();
    var _text = string(_value);
    _text = string_replace_all(_text, chr(10), "");
    _text = string_replace_all(_text, chr(13), "");
    _text = string_copy(_text, 1, 48);
    if (_text != _s.query)
    {
        _s.query = _text;
        _s.view_dirty = true;
        _s.page = 0;
    }
}

function CN_NativeViewCleanup()
{
    CN_NativeResetWindow(false);
}

function CN_NativeResetWindow(_keep_depth)
{
    var _s = CN_NativeViewState();
    CN_NativeRestoreGuard();
    CN_NativeReleaseFocus();
    if (!is_undefined(_s.deposit_hit)) CN_TakeInventoryHit();
    if (!_keep_depth && _s.changed_depth && instance_exists(_s.renderer))
        variable_instance_set(_s.renderer, "depth", _s.old_depth);
    if (!_keep_depth) _s.changed_depth = false;
    _s.anchor = undefined;
    _s.layout = undefined;
    _s.scroll_drag = false;
    _s.drag_armed = false;
    _s.drop_released = false;
    _s.deposit_hit = undefined;
    _s.pending_deposit = undefined;
    _s.search_activate = false;
}

function CN_NativeViewFail(_error)
{
    var _s = CN_NativeViewState();
    CN_NativeViewCleanup();
    if (!_s.failed) CN_ProbeLog("NATIVE VIEW DISABLED: " + string(_error));
    _s.failed = true;
}

function CN_NativeRefreshView()
{
    var _s = CN_NativeViewState();
    if (_s.network_dirty || (_s.tick mod 30) == 0)
    {
        _s.nodes = CN_BuildLoadedNetwork(_s.anchor, REGION);
        _s.network_dirty = false;
    }
    _s.sources = CN_SnapshotSlots(_s.nodes);
    CN_RefreshLanguage();
    _s.occupied = CN_NativeOccupiedCount(_s.sources);
    var _types = [""];
    var _seen = {};
    for (var _n = 0; _n < array_length(_s.sources); _n++)
    {
        var _type = string(_s.sources[_n].type);
        if (_type == "" || variable_struct_exists(_seen, _type)) continue;
        variable_struct_set(_seen, _type, true);
        array_push(_types, _type);
    }
    _s.types = _types;
    for (var _n = 1; _n < array_length(_types); _n++) CN_LocalizedType(_types[_n]);
    _s.dirty = false;
    _s.view_dirty = true;
}

function CN_NativeViewUpdate()
{
    var _s = CN_NativeViewState();
    // This also recovers input if a previous draw was interrupted externally.
    CN_NativeRestoreGuard();
    if (_s.failed || !_s.slot_ready || !CN_WorldReady()) { CN_NativeViewCleanup(); return; }
    _s.tick++;
    // Keep the renderer ordered before the stock GUI throughout this world,
    // including the frame in which player_input opens the first chest.
    if (!_s.changed_depth)
    {
        var _controller = instance_find(objGUIIngameController, 0);
        _s.old_depth = variable_instance_get(_s.renderer, "depth");
        var _depth = variable_instance_get(_controller, "depth");
        variable_instance_set(_s.renderer, "depth", max(_s.old_depth, _depth) + 100);
        _s.changed_depth = true;
    }
    var _anchor = _s.anchor;
    if (is_undefined(_anchor) || !CN_ChestStillExists(_anchor) || !CN_NativeCall("container_get_open", [_anchor.container]))
    {
        _anchor = CN_FindNativeOpenedChest();
    }
    if (is_undefined(_anchor)) { CN_NativeResetWindow(true); return; }
    var _window = variable_global_get("__WINDOW");
    var _layout = CN_NativeLayout(_window.height, GUI_SCALE,
        Container.GetWidth(_anchor.container), Container.GetHeight(_anchor.container));
    if (is_undefined(_layout)) { CN_NativeResetWindow(true); return; }
    if (is_undefined(_s.anchor) || _anchor.uid != _s.anchor.uid)
    {
        CN_NativeReleaseFocus();
        _s.drag_armed = false;
        _s.drop_released = false;
        _s.query = ""; _s.type = ""; _s.page = 0;
        _s.dirty = true; _s.network_dirty = true;
        _s.client_block_logged = false;
        CN_ProbeLog("NATIVE VIEW ATTACHED: chest=" + _anchor.uid);
    }
    _anchor.region = REGION;
    _s.anchor = _anchor;
    _s.layout = _layout;
    CN_NativeConsumeItemUse();
    CN_NativeRunDeposit();
    // Run before player_input rather than first seeing the gesture in Draw.
    if (CN_NativeConsumeWheel(_layout, mouse_wheel_up(), mouse_wheel_down()) && !_s.wheel_logged)
    {
        CN_ProbeLog("NATIVE WHEEL CAPTURE: hotbar selection pulses consumed in Update");
        _s.wheel_logged = true;
    }
    CN_NativeReadSearch();
    var _refresh_started = get_timer();
    if (_s.dirty || _s.network_dirty || (_s.tick mod 15) == 0) CN_NativeRefreshView();
    if (_s.view_dirty)
    {
        _s.view = CN_NativeViewSources(_s.sources, _s.query, _s.type, _s.sort);
        _s.view_dirty = false;
        if (_s.order_log_pending)
        {
            var _names = [];
            for (var _n = 0; _n < min(30, array_length(_s.view)); _n++)
                if (_s.view[_n].qty > 0) array_push(_names, _s.view[_n].name);
            CN_ProbeLog("NATIVE VIEW ORDER: " + json_stringify({ mode: _s.sort, names: _names }));
            _s.order_log_pending = false;
        }
    }
    _s.profile_refresh_us = max(_s.profile_refresh_us, get_timer() - _refresh_started);
    if (_s.focused && is_undefined(_s.locked_player))
    {
        _s.saved_move = variable_instance_get(MY_PLAYER, "canMove");
        _s.saved_actions = variable_instance_get(MY_PLAYER, "canUseActions");
        _s.locked_player = MY_PLAYER;
        variable_instance_set(MY_PLAYER, "canMove", false);
        variable_instance_set(MY_PLAYER, "canUseActions", false);
    }
    else if (!_s.focused && !is_undefined(_s.locked_player)) CN_NativeReleaseFocus();
}

function CN_NativeViewBegin()
{
    var _s = CN_NativeViewState();
    CN_NativeRestoreGuard();
    // Native player_input may have opened the chest after our Step callback.
    // Attach before the first stock GUI draw, without waiting several frames.
    if (_s.slot_ready && !_s.failed && CN_WorldReady())
        if (is_undefined(_s.anchor) || !CN_ChestStillExists(_s.anchor) ||
            !CN_NativeCall("container_get_open", [_s.anchor.container])) CN_NativeViewUpdate();
    if (_s.failed || is_undefined(_s.layout) || !CN_WorldReady()) return;
    var _mx = MOUSE_WINDOW_X;
    var _my = MOUSE_WINDOW_Y;
    var _click = mouse_check_button_pressed(mb_left);
    var _scroll = CN_NativeScrollGeometry(_s.layout, array_length(_s.view), _s.page);
    var _over_grid = CN_NativePointIn(_mx, _my, _s.layout.grid);
    var _over_storage = _over_grid || CN_NativePointIn(_mx, _my, _s.layout.search) ||
        CN_NativePointIn(_mx, _my, _s.layout.footer) || CN_NativePointIn(_mx, _my, _scroll.track);
    _s.manual_click = false;
    _s.drop_released = false;
    if (_click)
    {
        var _picked = CN_NativeCall("container_get_global_picked_item", []);
        _s.drag_armed = !_over_storage && !_s.focused && CN_ReadItemQuantity(_picked) <= 0;
    }
    if (mouse_check_button_released(mb_left))
    {
        if (_s.drag_armed && _over_grid && !_s.focused)
        {
            var _held = CN_NativeCall("container_get_global_picked_item", []);
            _s.drop_released = CN_ReadItemQuantity(_held) > 0;
        }
        _s.drag_armed = false;
    }
    if (_s.scroll_drag && !mouse_check_button(mb_left)) _s.scroll_drag = false;
    if (_click)
    {
        if (CN_NativePointIn(_mx, _my, _scroll.track) && _scroll.max_row > 0)
        {
            CN_NativeReleaseFocus();
            _s.scroll_grab = CN_NativePointIn(_mx, _my, _scroll.thumb) ? _my - _scroll.thumb.y : _scroll.thumb.h * 0.5;
            _s.scroll_drag = true;
        }
        else if (CN_NativePointIn(_mx, _my, _s.layout.search))
        {
            if (_mx >= _s.layout.search.x + _s.layout.search.w - 10 * _s.layout.scale)
            {
                CN_NativeReleaseFocus();
                _s.query = ""; _s.view_dirty = true; _s.page = 0;
            }
            else { CN_NativeFocusSearch(); _s.search_activate = true; }
        }
        else if (_s.focused) { _s.manual_click = true; CN_NativeReleaseFocus(); }
    }
    if (_s.scroll_drag) _s.page = CN_NativeScrollPage(_scroll, _my, _s.scroll_grab);
    if (_over_storage || _s.focused || _s.scroll_drag)
    {
        // Complete validation precedes the first mutation of native input.
        _s.saved_input = CN_CaptureNativeInput();
        CN_MaskNativeInput();
    }
    else CN_NativeBeginDeposit();
}

function CN_NativeDrawSearch()
{
    var _s = CN_NativeViewState();
    var _l = _s.layout;
    var _saved_click = variable_global_get("__K_MENU_LEFT_CLICK_PRESSED");
    // input_active blocks gameplay and native click pulses; replay our exact
    // physical field click once so DrawInput can establish its own text focus.
    if (_s.search_activate) variable_global_set("__K_MENU_LEFT_CLICK_PRESSED", true);
    var _query = _s.query;
    try { _query = GUI.DrawInput(_l.search.x, _l.search.y, _l.search.w - 10 * _l.scale, _l.search.h, _s.query, 48); }
    catch (_error) { variable_global_set("__K_MENU_LEFT_CLICK_PRESSED", _saved_click); throw _error; }
    variable_global_set("__K_MENU_LEFT_CLICK_PRESSED", _saved_click);
    CN_NativeApplyQuery(_query);
    var _input = static_get(GUI.DrawInput);
    if (_s.focused)
    {
        var _selected = -1;
        if (is_struct(_input) && variable_struct_exists(_input, "selected")) _selected = _input.selected;
        if (_selected == -1 || (!_s.search_activate && _selected != _s.search_id))
        {
            CN_NativeReleaseFocus();
        }
        else if (_s.search_activate)
        {
            _s.search_id = _selected;
            CN_ProbeLog("SEARCH NATIVE SELECTED: " + string(_s.search_id));
        }
    }
    _s.search_activate = false;
}

function CN_NativeButton(_x, _y, _w, _h, _text)
{
    GUI.DrawContainer(_x, _y, _w, _h);
    var _cx = _x + _w * 0.5;
    var _cy = _y + _h * 0.5;
    var _text_scale = _h / 14 * 0.7;
    // Keep complete translated category labels inside the small native button.
    _text_scale *= min(1, 10 / max(1, string_length(_text)));
    GUI.DrawText(_cx, _cy, _text, 5, c_white, 1, _text_scale);
    var _s = CN_NativeViewState();
    return (variable_global_get("__K_MENU_LEFT_CLICK_PRESSED") || _s.manual_click) &&
        MOUSE_WINDOW_X >= _x && MOUSE_WINDOW_X < _x + _w && MOUSE_WINDOW_Y >= _y && MOUSE_WINDOW_Y < _y + _h;
}

function CN_NativeViewDraw()
{
    var _s = CN_NativeViewState();
    CN_NativeRestoreGuard();
    if (_s.failed || is_undefined(_s.layout) || !CN_WorldReady()) return;
    if (!CN_ChestStillExists(_s.anchor) || !CN_NativeCall("container_get_open", [_s.anchor.container])) return;
    var _started = get_timer();
    var _l = _s.layout;
    var _scale = _l.scale;
    var _scroll = CN_NativeScrollGeometry(_l, array_length(_s.view), _s.page);
    _s.page = max(0, min(_s.page, _scroll.max_row));
    var _over_chest = MOUSE_WINDOW_X >= 10 * _scale && MOUSE_WINDOW_X < 145 * _scale &&
        MOUSE_WINDOW_Y >= _l.top && MOUSE_WINDOW_Y < _l.footer.y + _l.footer.h;
    if (_over_chest)
    {
        if (mouse_wheel_up()) _s.page = max(0, _s.page - 1);
        if (mouse_wheel_down()) _s.page = min(_scroll.max_row, _s.page + 1);
    }
    var _left_replay = _s.manual_click || _s.drop_released;
    var _click = _left_replay || variable_global_get("__K_MENU_LEFT_CLICK_PRESSED") || variable_global_get("__K_MENU_RIGHT_CLICK_PRESSED");
    var _input_in_grid = CN_NativePointIn(MOUSE_WINDOW_X, MOUSE_WINDOW_Y, _l.grid);
    var _host = CN_NativeCall("net_is_host", []);
    var _stylesheet = CN_NativeCall("container_get_stylesheet", [_s.anchor.container]);
    var _live_nodes = _s.nodes;
    if (_click && _input_in_grid) _live_nodes = CN_BuildLoadedNetwork(_s.anchor, REGION);
    var _mx = MOUSE_WINDOW_X;
    var _my = MOUSE_WINDOW_Y;
    // Stock drawing for all unhovered cells shares one reversible input mask.
    var _input = CN_CaptureNativeInput();
    CN_MaskNativeInput();
    try { CN_NativeDrawGrid(_s, _mx, _my, _click, _left_replay, _host, _live_nodes, _stylesheet, _input); }
    catch (_error) { CN_RestoreNativeInput(_input); throw _error; }
    CN_RestoreNativeInput(_input);
    CN_NativeDrawSearch();
    _scroll = CN_NativeScrollGeometry(_l, array_length(_s.view), _s.page);
    draw_set_color(make_color_rgb(85, 44, 39));
    draw_rectangle(_scroll.track.x, _scroll.track.y, _scroll.track.x + _scroll.track.w, _scroll.track.y + _scroll.track.h, false);
    draw_set_color(make_color_rgb(191, 148, 104));
    draw_rectangle(_scroll.thumb.x, _scroll.thumb.y, _scroll.thumb.x + _scroll.thumb.w, _scroll.thumb.y + _scroll.thumb.h, false);
    draw_set_color(c_white);
    CN_NativeDrawControls(_s, _l, _host, true);
    _s.profile_draw_us = max(_s.profile_draw_us, get_timer() - _started);
}

function CN_NativeDrawGrid(_s, _mx, _my, _click, _left_replay, _host, _live_nodes, _stylesheet, _input)
{
    var _l = _s.layout;
    var _scale = _l.scale;
    for (var _n = 0; _n < 30; _n++)
    {
        var _cx = _l.cx + (_n mod 5) * _l.dx;
        var _cy = _l.cy + floor(_n / 5) * _l.dy;
        // Erase only the original slot contents, retaining the actual frame.
        var _bg_x = _cx - sprite_get_width(sprGUIIngameChestSlot) * _scale * 0.5;
        var _bg_y = _cy - sprite_get_height(sprGUIIngameChestSlot) * _scale * 0.5;
        _bg_x += sprite_get_xoffset(sprGUIIngameChestSlot) * _scale;
        _bg_y += sprite_get_yoffset(sprGUIIngameChestSlot) * _scale;
        draw_sprite_ext(sprGUIIngameChestSlot, 0, _bg_x, _bg_y, _scale, _scale, 0, c_white, 1);
        var _index = _s.page * 5 + _n;
        if (_index >= array_length(_s.view)) continue;
        var _entry = _s.view[_index];
        var _hover = abs(_mx - _cx) < 11 * _scale && abs(_my - _cy) < 10 * _scale;
        if (_click && _hover)
        {
            var _live_entry = CN_NativeLiveEntry(_entry);
            if (!is_undefined(_live_entry)) _entry = _live_entry;
        }
        var _current = CN_NativeEntryMatches(_entry);
        if (_hover && _click) _current = _current && CN_NetworkHasContainer(_live_nodes, _entry.container);
        if (!_current) { _s.dirty = true; continue; }
        if (!_hover)
        {
            CN_RenderPhysicalSlot(_entry, _cx, _cy, _stylesheet);
            continue;
        }
        CN_RestoreNativeInput(_input);
        var _native_click = variable_global_get("__K_MENU_LEFT_CLICK_PRESSED") ||
            variable_global_get("__K_MENU_RIGHT_CLICK_PRESSED");
        if (_host && _left_replay) variable_global_set("__K_MENU_LEFT_CLICK_PRESSED", true);
        var _writable = false;
        if (_host && !_s.focused) _writable = CN_NativeContainerWritable(_live_nodes, _entry.container);
        else if (!_host && _native_click && !_s.focused && !_s.scroll_drag && !keyboard_check(vk_shift))
            _writable = CN_ClientAnchorInputAllowed(_host, _s.anchor, _entry.container);
        var _before_item = _entry.item;
        var _before_qty = _entry.qty;
        if (!_writable) CN_MaskNativeActions();
        CN_RenderPhysicalSlot(_entry, _cx, _cy, _stylesheet);
        if (_host && _writable && _click &&
            (Container.GetItem(_entry.container, _entry.x, _entry.y) != _before_item || CN_ReadItemQuantity(_before_item) != _before_qty))
        {
            for (var _node_i = 0; _node_i < array_length(_live_nodes); _node_i++)
                if (_live_nodes[_node_i].container == _entry.container) CN_SyncHostChest(_live_nodes[_node_i]);
        }
        if (_native_click && !_host && _writable)
        {
            var _after = Container.GetItem(_entry.container, _entry.x, _entry.y);
            var _after_qty = CN_ReadItemQuantity(_after);
            CN_ProbeLog("CLIENT STOCK SLOT: anchor=" + _s.anchor.uid + "; x=" + string(_entry.x) +
                "; y=" + string(_entry.y) + "; before=" + string(_before_qty) + "; after=" + string(_after_qty));
        }
        else if (_click && !_host)
        {
            if (_entry.container != _s.anchor.container) _s.notice = "Соседний сундук: просмотр";
            else if (!_native_click || keyboard_check(vk_shift)) _s.notice = "Используйте обычный клик";
            else _s.notice = "Сундук пока недоступен";
            _s.notice_tick = _s.tick + 180;
            if (!_s.client_block_logged)
            {
                CN_ProbeLog("CLIENT STOCK SLOT BLOCKED: anchor=" + _s.anchor.uid +
                    "; selected_anchor=" + string(_entry.container == _s.anchor.container) +
                    "; native_click=" + string(_native_click));
                _s.client_block_logged = true;
            }
        }
        if (_click) _s.dirty = true;
        CN_MaskNativeInput();
    }
}

function CN_NativeDrawControls(_s, _l, _host, _interactive)
{
    var _scale = _l.scale;
    var _text_scale = _scale * 0.7;
    var _text_y = _l.search.y + _l.search.h * 0.5;
    if (!_s.focused && _s.query == "")
    {
        var _hint_x = _l.search.x + 3 * _scale;
        // Resolve interpreted calls before passing values to a native GUI alias.
        var _hint_text = CN_UIText("search");
        GUI.DrawText(_hint_x, _text_y, _hint_text, 4, c_white, 1, _text_scale);
    }
    var _clear_x = _l.search.x + _l.search.w - 5 * _scale;
    GUI.DrawText(_clear_x, _text_y, "x", 5, c_white, 1, _text_scale);
    // Replace the stock per-chest action row with controls for the network view.
    draw_set_color(make_color_rgb(168, 116, 83));
    draw_rectangle(_l.footer.x, _l.footer.y, _l.footer.x + _l.footer.w, _l.footer.y + _l.footer.h, false);
    draw_set_color(c_white);
    var _fy = _l.footer.y + 4 * _scale;
    var _type_label = CN_LocalizedType(_s.type);
    var _filter_clicked = CN_NativeButton(25 * _scale, _fy, 39 * _scale, 14 * _scale, _type_label);
    if (_interactive && _filter_clicked)
    {
        var _ti = 0;
        for (var _n = 0; _n < array_length(_s.types); _n++) if (_s.types[_n] == _s.type) _ti = _n;
        _s.type = _s.types[(_ti + 1) mod array_length(_s.types)];
        _s.view_dirty = true; _s.page = 0;
    }
    var _sort_label = CN_UIText(_s.sort);
    var _sort_clicked = CN_NativeButton(65 * _scale, _fy, 29 * _scale, 14 * _scale, _sort_label);
    if (_interactive && _sort_clicked)
    {
        _s.sort = (_s.sort == "source") ? "name" : "source";
        _s.order_log_pending = true;
        _s.view_dirty = true; _s.page = 0;
    }
    var _capacity = CN_NetworkCapacity(_s.nodes);
    var _summary = CN_UIText("network") + ": " + string(array_length(_s.nodes));
    if (!_host) _summary += "   " + CN_UIText("anchor");
    var _summary_scale = _scale * 0.65;
    GUI.DrawText(118 * _scale, _l.footer.y + 7 * _scale, _summary, 5, c_white, 1, _summary_scale);
    var _occupied_text = string(_s.occupied) + "/" + string(_capacity);
    GUI.DrawText(118 * _scale, _l.footer.y + 17 * _scale, _occupied_text, 5, c_white, 1, _summary_scale);
    if (_s.notice != "" && _s.tick < _s.notice_tick)
        GUI.DrawText(10 * _scale, _l.top - 21 * _scale, _s.notice, 7, c_white, 1, _summary_scale);
}

function CN_ProbeNativeControls()
{
    // Exercise the actual production controls in DrawGUI, off screen. No chest,
    // item, focus, query or filter belonging to the player is changed here.
    var _layout = { scale: 1, top: -3000,
                    search: { x: -3000, y: -3000, w: 112, h: 16 },
                    footer: { x: -3000, y: -3000, w: 123, h: 23 } };
    var _view = { focused: false, query: "", type: "", types: ["", "Material"],
                  sort: "source", nodes: [], occupied: 0, notice: "", tick: 0, notice_tick: 0 };
    CN_NativeDrawControls(_view, _layout, true, false);
    _view.type = "Material";
    _view.sort = "name";
    CN_NativeDrawControls(_view, _layout, false, false);
    var _s = CN_NativeViewState();
    _s.controls_ready = true;
    CN_ProbeLog("NATIVE CONTROLS READY: production localized controls drawn off screen in both sort modes");
}

function CN_ProbeNativeSlot()
{
    var _s = CN_NativeViewState();
    var _temporary = Container.Create(1, 1);
    try
    {
        // Verify the reversible display-only setter away from real chests.
        var _old_style = CN_NativeCall("container_get_stylesheet", [_temporary]);
        CN_NativeCall("container_set_stylesheet", [sprGUIIngameChestSlot, _temporary]);
        var _changed_style = CN_NativeCall("container_get_stylesheet", [_temporary]);
        if (_changed_style != sprGUIIngameChestSlot) throw "Native stylesheet setter did not round-trip";
        CN_NativeCall("container_set_stylesheet", [_old_style, _temporary]);
        var _mouse_probe = CN_NativeCall("container_mouse_in_container", [_temporary]);
        var _mouse_x_probe = CN_NativeCall("container_get_mouse_x", [_temporary]);
        var _mouse_y_probe = CN_NativeCall("container_get_mouse_y", [_temporary]);
        var _button_probe = mouse_check_button(mb_left);
        CN_ProbeLog("NATIVE INVENTORY API READY: native hit-test and relative mouse coordinates callable");
        CN_NativeCall("container_slot", [_temporary, 0, 0, "", -3000, -3000]);
        if (CN_InitInventoryHit())
        {
            var _scale = GUI_SCALE;
            if (!CN_ArmInventoryHit(_temporary, -3000, -3000, _scale)) throw "Native inventory hit could not arm";
            CN_NativeCall("container_slot", [_temporary, 0, 0, "", -3000, -3000, undefined, undefined, false, undefined, undefined, undefined, undefined, undefined]);
            var _hit = CN_TakeInventoryHit();
            if (_hit != 1) throw "Native inventory hit did not observe the rendered slot";
            CN_ProbeLog("NATIVE INVENTORY HIT READY: observed stock slot arguments");
        }
        else CN_ProbeLog("NATIVE INVENTORY HIT UNAVAILABLE");
        Container.Destroy(_temporary, false, 0, 0);
        _s.slot_ready = true;
        CN_ProbeLog("NATIVE SLOT READY: six-argument draw verified on a disposable empty container");
    }
    catch (_error)
    {
        CN_TakeInventoryHit();
        if (Container.Exists(_temporary)) Container.Destroy(_temporary, false, 0, 0);
        throw _error;
    }
}

function CN_ProbeCursorSlot()
{
    var _cursor = "__CONTAINER__PICKED_ITEM_MAP";
    if (!variable_global_exists(_cursor)) throw "Native cursor unavailable";
    var _previous = variable_global_get(_cursor);
    if (CN_ReadItemQuantity(_previous) > 0) throw "Disposable cursor probe requires an empty cursor";
    var _saved = CN_CaptureNativeInput();
    var _source = Container.Create(1, 1);
    var _target = Container.Create(1, 1);
    var _item = undefined;
    var _held = undefined;
    var _picked = 0;
    var _quantity = 0;
    var _remaining = 0;
    try
    {
        _item = CN_ProbeSeed(_source, 7);
        CN_NativeCall("container_item_pickup", [0, 0, _source, true]);
        _held = CN_NativeCall("container_get_global_picked_item", []);
        _picked = CN_ReadItemQuantity(_held);
        variable_global_set("__MOUSE_WINDOW_X__", -3000);
        variable_global_set("__MOUSE_WINDOW_Y__", -3000);
        CN_MaskNativeActions();
        variable_global_set("__K_MENU_LEFT_CLICK_PRESSED", true);
        var _entry = { container: _target, x: 0, y: 0 };
        CN_DrawPhysicalSlot(_entry, -3000, -3000, true, true, sprGUIIngameChestSlot);
        _quantity = CN_ContainerQuantity(_target, E_ITEMS.wood);
        var _cursor_after = CN_NativeCall("container_get_global_picked_item", []);
        _remaining = CN_ReadItemQuantity(_cursor_after);
    }
    catch (_error) { CN_ProbeLog("NATIVE CURSOR SLOT ERROR: " + string(_error)); }
    variable_global_set(_cursor, _previous);
    CN_RestoreNativeInput(_saved);
    var _placed = Container.GetItem(_target, 0, 0);
    var _source_left = Container.GetItem(_source, 0, 0);
    if (!is_undefined(_held) && _held != _placed && _held != _source_left && ds_exists(_held, ds_type_map)) ds_map_destroy(_held);
    if (!is_undefined(_item) && _item != _held && _item != _placed && _item != _source_left && ds_exists(_item, ds_type_map)) ds_map_destroy(_item);
    Container.Destroy(_target, false, 0, 0);
    Container.Destroy(_source, false, 0, 0);
    CN_ProbeLog("NATIVE CURSOR SLOT: picked=" + string(_picked) + "; received=" + string(_quantity) + "; held=" + string(_remaining));
}

function CN_ProbeStorageDraw()
{
    var _input = CN_CaptureNativeInput();
    var _temp = Container.Create(5, 6);
    var _style = sprGUIIngameChestSlot;
    var _individual = [];
    var _batched = [];
    try
    {
        CN_ProbeSeed(_temp, 1);
        var _slots = CN_SnapshotSlots([{ container: _temp }]);
        if (array_length(_slots) != 30) throw "Disposable draw probe expects 30 real slots";
        for (var _n = 0; _n < 6; _n++)
        {
            for (var _pass = 0; _pass < 2; _pass++)
            {
                var _shared = ((_n + _pass) mod 2) == 0;
                var _started = get_timer();
                if (_shared) CN_MaskNativeInput();
                for (var _i = 0; _i < 30; _i++)
                {
                    var _entry = _slots[_i];
                    var _x = -3000 + _entry.x * 23;
                    var _y = -3000 + _entry.y * 22;
                    if (_shared) CN_RenderPhysicalSlot(_entry, _x, _y, _style);
                    else CN_DrawPhysicalSlot(_entry, _x, _y, false, false, _style);
                }
                if (_shared) CN_RestoreNativeInput(_input);
                var _elapsed = get_timer() - _started;
                if (_shared) array_push(_batched, _elapsed);
                else array_push(_individual, _elapsed);
            }
        }
        var _layout = { scale: 1, cx: -3000, cy: -3000, dx: 23, dy: 22 };
        var _test_view = { layout: _layout, page: 0, view: _slots, dirty: false };
        CN_MaskNativeInput();
        CN_NativeDrawGrid(_test_view, -9000, -9000, false, false, true, [], _style, _input);
    }
    catch (_error)
    {
        CN_RestoreNativeInput(_input);
        Container.Destroy(_temp, false, 0, 0);
        throw _error;
    }
    CN_RestoreNativeInput(_input);
    Container.Destroy(_temp, false, 0, 0);
    CN_ProbeLog("NATIVE STORAGE DRAW PROBE: " + json_stringify({ slots: 30, individual_us: _individual, batch_us: _batched }));
}

OnModLoad(function() { var _s = CN_NativeViewState(); _s.renderer = id; });
OnWorldGenerationStart(function() { CN_NativeViewCleanup(); var _s = CN_NativeViewState(); _s.failed = false; _s.dirty = true; _s.network_dirty = true; });
OnInteractableCreate(function(_id, _i, _j) { var _s = CN_NativeViewState(); _s.network_dirty = true; });
OnInteractableDestroy(function(_id, _i, _j) { var _s = CN_NativeViewState(); _s.network_dirty = true; });
OnModUpdate(function() { try { CN_NativeViewUpdate(); } catch (_error) { CN_NativeViewFail(_error); } });
OnModDrawGUI(function() { try { CN_NativeViewBegin(); } catch (_error) { CN_NativeViewFail(_error); } });
OnModDrawGUIEnd(function()
{
    var _s = CN_NativeViewState();
    try
    {
        CN_NativeRestoreGuard();
        if (_s.failed) return;
        if (!_s.slot_ready) CN_ProbeNativeSlot();
        if (!_s.controls_ready) CN_ProbeNativeControls();
        CN_NativeFinishDepositHit();
        if (_s.cursor_probe_pending)
        {
            _s.cursor_probe_pending = false;
            try { CN_ProbeCursorSlot(); }
            catch (_probe_error) { CN_ProbeLog("NATIVE CURSOR SLOT ERROR: " + string(_probe_error)); }
        }
        if (_s.draw_probe_pending)
        {
            _s.draw_probe_pending = false;
            try { CN_ProbeStorageDraw(); }
            catch (_probe_error) { CN_ProbeLog("NATIVE STORAGE DRAW ERROR: " + string(_probe_error)); }
        }
        CN_NativeViewDraw();
    }
    catch (_error) { CN_NativeViewFail(_error); }
});
