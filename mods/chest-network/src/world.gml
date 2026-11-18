function CN_WorldReady()
{
    if (!instance_exists(objPlayer) || is_undefined(MY_PLAYER)) return false;
    if (!instance_exists(objGUIIngameController) || instance_exists(objGUIMenuController)) return false;
    if (variable_global_exists("WORLD_GENERATED") && !variable_global_get("WORLD_GENERATED")) return false;
    if (variable_global_exists("guiEnabled") && !variable_global_get("guiEnabled")) return false;
    return true;
}

// Adapter for loaded, real chest instances. Cross-island persistence is a
// separate pending capability; do not treat this list as a remote-world cache.

function CN_DescribeLoadedChest(_instance, _scope, _region)
{
    var _required = ["i", "j", "container"];
    for (var _n = 0; _n < array_length(_required); _n++)
    {
        if (!variable_instance_exists(_instance, _required[_n])) throw "Unsupported chest instance field: " + _required[_n];
    }
    var _container = variable_instance_get(_instance, "container");
    if (!Container.Exists(_container)) return undefined;
    if (variable_instance_exists(_instance, "region"))
    {
        if (variable_instance_get(_instance, "region") != _region) return undefined;
    }
    var _i = variable_instance_get(_instance, "i");
    var _j = variable_instance_get(_instance, "j");
    var _px = (_i + 0.5) * TILE_SIZE;
    var _py = (_j + 0.5) * TILE_SIZE;
    var _interactable = World.GetInteractableID(_px, _py, _region);
    var _width = Database.GetInteractableData(_interactable, 35);
    var _height = Database.GetInteractableData(_interactable, 36);
    if (!is_numeric(_width) || !is_numeric(_height) || _width < 1 || _height < 1) throw "Unsupported chest footprint";
    return {
        uid: string(_container), i: _i, j: _j, w: _width, h: _height,
        scope: _scope, container: _container, instance: _instance,
        slots: Container.GetWidth(_container) * Container.GetHeight(_container)
    };
}

function CN_BuildLoadedNetwork(_anchor, _region)
{
    var _nodes = [];
    var _count = instance_number(objInteractableChest);
    for (var _n = 0; _n < _count; _n++)
    {
        var _instance = instance_find(objInteractableChest, _n);
        var _node = CN_DescribeLoadedChest(_instance, _anchor.scope, _region);
        if (!is_undefined(_node)) array_push(_nodes, _node);
    }
    return CN_SelectNetwork(_anchor, _nodes);
}

function CN_CollectContainerItems(_nodes)
{
    var _items = [];
    var _seen = {};
    for (var _n = 0; _n < array_length(_nodes); _n++)
    {
        var _container = _nodes[_n].container;
        if (!Container.Exists(_container)) continue;
        var _width = Container.GetWidth(_container);
        var _height = Container.GetHeight(_container);
        for (var _y = 0; _y < _height; _y++)
        {
            for (var _x = 0; _x < _width; _x++)
            {
                var _item = Container.GetItem(_container, _x, _y);
                var _quantity = CN_ReadItemQuantity(_item);
                if (_quantity <= 0) continue;
                var _identity = string(_item);
                if (variable_struct_exists(_seen, _identity)) continue;
                variable_struct_set(_seen, _identity, true);
                // Preserve individual physical stacks. Rendering a combined
                // count must never merge incompatible item metadata.
                array_push(_items, {
                    container: _container, x: _x, y: _y, item: _item,
                    id: Item.GetProperty(_item, 0), key: Item.GetProperty(_item, 1),
                    name: Item.GetProperty(_item, 2), type: Item.GetProperty(_item, 7),
                    sprite: Item.GetProperty(_item, 5), affix: Item.GetProperty(_item, 59),
                    qty: _quantity
                });
            }
        }
    }
    return _items;
}

function CN_NetworkHasContainer(_nodes, _container)
{
    for (var _n = 0; _n < array_length(_nodes); _n++)
    {
        if (_nodes[_n].container == _container) return true;
    }
    return false;
}
