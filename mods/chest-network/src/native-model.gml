// Physical source addresses only: this is a view, never a second container.
function CN_SnapshotSlots(_nodes)
{
    var _result = [];
    var _seen = {};
    for (var _n = 0; _n < array_length(_nodes); _n++)
    {
        var _c = _nodes[_n].container;
        if (!Container.Exists(_c)) continue;
        for (var _y = 0; _y < Container.GetHeight(_c); _y++)
        {
            for (var _x = 0; _x < Container.GetWidth(_c); _x++)
            {
                var _item = Container.GetItem(_c, _x, _y);
                var _qty = CN_ReadItemQuantity(_item);
                var _entry = { container: _c, x: _x, y: _y, item: _item, qty: _qty,
                               name: "", type: "", id: undefined, sort_key: "", favorite: false };
                if (_qty > 0)
                {
                    var _key = string(_item);
                    if (variable_struct_exists(_seen, _key)) continue;
                    variable_struct_set(_seen, _key, true);
                    _entry.name = Item.GetProperty(_item, 2);
                    _entry.type = Item.GetProperty(_item, 7);
                    _entry.id = Item.GetProperty(_item, 0);
                    _entry.sort_key = CN_NameSortKey(_entry.name);
                    // Native container_item_favorite toggles runtime key115.
                    _entry.favorite = ds_map_exists(_item, 115) && Item.GetProperty(_item, 115) == true;
                }
                array_push(_result, _entry);
            }
        }
    }
    return _result;
}

function CN_SortNativeSources(_sources, _mode)
{
    var _a = [];
    for (var _n = 0; _n < array_length(_sources); _n++) array_push(_a, _sources[_n]);
    if (_mode == "source") return _a;
    // Stable merge sort avoids a VM callback being passed into native array_sort.
    var _length = array_length(_a);
    for (var _width = 1; _width < _length; _width *= 2)
    {
        var _b = [];
        for (var _start = 0; _start < _length; _start += 2 * _width)
        {
            var _mid = min(_start + _width, _length);
            var _end = min(_start + 2 * _width, _length);
            var _left = _start;
            var _right = _mid;
            while (_left < _mid || _right < _end)
            {
                var _take_left = _right >= _end;
                if (_left >= _mid) _take_left = false;
                else if (_right < _end) _take_left = _a[_left].sort_key <= _a[_right].sort_key;
                if (_take_left) { array_push(_b, _a[_left]); _left++; }
                else { array_push(_b, _a[_right]); _right++; }
            }
        }
        _a = _b;
    }
    return _a;
}

function CN_NativeViewSources(_sources, _query, _type, _mode)
{
    var _occupied = [];
    var _empty = [];
    for (var _n = 0; _n < array_length(_sources); _n++)
    {
        if (_sources[_n].qty > 0) array_push(_occupied, _sources[_n]);
        else array_push(_empty, _sources[_n]);
    }
    _occupied = CN_FilterItems(_occupied, _query, _type);
    _occupied = CN_SortNativeSources(_occupied, _mode);
    var _padding = CN_DLLCommand({ op: "visible_empty_slots", occupied: array_length(_occupied), available: array_length(_empty) });
    for (var _n = 0; _n < _padding; _n++) array_push(_occupied, _empty[_n]);
    return _occupied;
}

function CN_NativeEntryMatches(_entry)
{
    if (!Container.Exists(_entry.container)) return false;
    var _item = Container.GetItem(_entry.container, _entry.x, _entry.y);
    if (_item != _entry.item || CN_ReadItemQuantity(_item) != _entry.qty) return false;
    if (_entry.qty > 0 && Item.GetProperty(_item, 0) != _entry.id) return false;
    return true;
}

// Refresh only the quantity of the same physical item. Never retarget a click
// to a replacement item or a different slot after a background/native transfer.
function CN_NativeLiveEntry(_entry)
{
    if (!Container.Exists(_entry.container)) return undefined;
    var _item = Container.GetItem(_entry.container, _entry.x, _entry.y);
    if (_item != _entry.item) return undefined;
    var _qty = CN_ReadItemQuantity(_item);
    if (_entry.qty <= 0) return (_qty <= 0) ? _entry : undefined;
    if (_qty <= 0 || Item.GetProperty(_item, 0) != _entry.id) return undefined;
    return { container: _entry.container, x: _entry.x, y: _entry.y, item: _item,
             qty: _qty, id: _entry.id, name: _entry.name, type: _entry.type,
             sort_key: _entry.sort_key };
}

function CN_NativeLayout(_height, _scale, _columns, _rows)
{
    // Exact 5x6 branch of objGUIIngameController.Draw_64, verified against 0.0.12.
    // Other layouts keep their ordinary window until separately mapped.
    if (_columns != 5 || _rows != 6 || _height < 185 * _scale) return undefined;
    var _top = _height - 170 * _scale;
    return {
        scale: _scale, top: _top, cx: 36 * _scale, cy: _height - 145 * _scale,
        dx: 23 * _scale, dy: 22 * _scale,
        grid: { x: 25 * _scale, y: _height - 155 * _scale, w: 114 * _scale, h: 130 * _scale },
        search: { x: 26 * _scale, y: _top - 6 * _scale, w: 112 * _scale, h: 16 * _scale },
        footer: { x: 20 * _scale, y: _height - 24 * _scale, w: 123 * _scale, h: 23 * _scale }
    };
}

function CN_NativeScrollGeometry(_layout, _slot_count, _page)
{
    var _rows = max(6, ceil(_slot_count / 5));
    var _max_row = _rows - 6;
    var _track = { x: 17 * _layout.scale, y: _layout.grid.y,
                   w: 5 * _layout.scale, h: _layout.grid.h };
    var _height = min(_track.h, max(12 * _layout.scale, _track.h * 6 / _rows));
    var _position = (_max_row <= 0) ? 0 : max(0, min(_page, _max_row)) / _max_row;
    return { track: _track, thumb: { x: _track.x, y: _track.y + (_track.h - _height) * _position,
                                    w: _track.w, h: _height }, max_row: _max_row };
}

function CN_NativeScrollPage(_scroll, _mouse_y, _grab)
{
    var _travel = _scroll.track.h - _scroll.thumb.h;
    if (_scroll.max_row <= 0 || _travel <= 0) return 0;
    var _position = max(0, min(1, (_mouse_y - _scroll.track.y - _grab) / _travel));
    return floor(_position * _scroll.max_row + 0.5);
}

function CN_NativeOccupiedCount(_entries)
{
    var _count = 0;
    for (var _n = 0; _n < array_length(_entries); _n++) if (_entries[_n].qty > 0) _count++;
    return _count;
}
