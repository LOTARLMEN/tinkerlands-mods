// Pure network logic. Coordinates and sizes are in occupied world cells.
// The same source runs in the game and in the Node test harness.

function CN_CellKey(_scope, _i, _j)
{
    return _scope + ":" + string(_i) + ":" + string(_j);
}

function CN_VisitCell(_state, _scope, _i, _j)
{
    var _cell = CN_CellKey(_scope, _i, _j);
    if (!variable_struct_exists(_state.cells, _cell)) return;
    var _node = variable_struct_get(_state.cells, _cell);
    if (variable_struct_exists(_state.seen, _node.uid)) return;
    variable_struct_set(_state.seen, _node.uid, true);
    array_push(_state.queue, _node);
}

function CN_VisitSides(_state, _rect)
{
    for (var _x = _rect.i; _x < _rect.i + _rect.w; _x++)
    {
        CN_VisitCell(_state, _rect.scope, _x, _rect.j - 1);
        CN_VisitCell(_state, _rect.scope, _x, _rect.j + _rect.h);
    }
    for (var _y = _rect.j; _y < _rect.j + _rect.h; _y++)
    {
        CN_VisitCell(_state, _rect.scope, _rect.i - 1, _y);
        CN_VisitCell(_state, _rect.scope, _rect.i + _rect.w, _y);
    }
}

function CN_SelectNetwork(_anchor, _nodes)
{
    var _state = { cells: {}, seen: {}, queue: [] };
    var _root = undefined;
    for (var _n = 0; _n < array_length(_nodes); _n++)
    {
        var _node = _nodes[_n];
        if (_node.scope != _anchor.scope) continue;
        if (_node.uid == _anchor.uid && _node.i == _anchor.i && _node.j == _anchor.j && _node.w == _anchor.w && _node.h == _anchor.h) _root = _node;
        for (var _x = _node.i; _x < _node.i + _node.w; _x++)
        {
            for (var _y = _node.j; _y < _node.j + _node.h; _y++)
            {
                variable_struct_set(_state.cells, CN_CellKey(_node.scope, _x, _y), _node);
            }
        }
    }
    // The opened chest is a real member, including an isolated single chest.
    // A stale/missing anchor must not grant access through its former neighbours.
    if (is_undefined(_root)) return [];
    variable_struct_set(_state.seen, _root.uid, true);
    array_push(_state.queue, _root);
    var _cursor = 0;
    while (_cursor < array_length(_state.queue))
    {
        CN_VisitSides(_state, _state.queue[_cursor]);
        _cursor++;
    }
    return _state.queue;
}

function CN_NetworkCapacity(_nodes)
{
    var _total = 0;
    for (var _n = 0; _n < array_length(_nodes); _n++)
    {
        _total += _nodes[_n].slots;
    }
    return _total;
}
