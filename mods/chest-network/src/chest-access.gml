// Observe the exact chest opened by the native game. No nearest-chest fallback,
// new content, persistent-data writes or simulated interaction is needed.
function CN_FindOpenedChest()
{
    // Do not close native containers while an item is held by native drag/drop.
    var _picked = CN_NativeCall("container_get_global_picked_item", []);
    if (CN_ReadItemQuantity(_picked) > 0) return undefined;
    return CN_FindNativeOpenedChest();
}

// A live native view must stay attached while the player holds a stack.
function CN_FindNativeOpenedChest()
{
    var _count = instance_number(objInteractableChest);
    for (var _n = 0; _n < _count; _n++)
    {
        var _instance = instance_find(objInteractableChest, _n);
        if (!variable_instance_exists(_instance, "container")) continue;
        var _container = variable_instance_get(_instance, "container");
        if (!Container.Exists(_container)) continue;
        if (!CN_NativeCall("container_get_open", [_container])) continue;
        var _node = CN_DescribeLoadedChest(_instance, "region:" + string(REGION), REGION);
        if (!is_undefined(_node)) return _node;
    }
    return undefined;
}

function CN_ChestStillExists(_anchor)
{
    if (is_undefined(_anchor) || REGION != _anchor.region) return false;
    var _instance = _anchor.instance;
    if (!instance_exists(_instance) || !Container.Exists(_anchor.container)) return false;
    if (!variable_instance_exists(_instance, "container") || !variable_instance_exists(_instance, "i") ||
        !variable_instance_exists(_instance, "j")) return false;
    if (variable_instance_exists(_instance, "region") && variable_instance_get(_instance, "region") != _anchor.region) return false;
    if (variable_instance_get(_instance, "container") != _anchor.container ||
        variable_instance_get(_instance, "i") != _anchor.i || variable_instance_get(_instance, "j") != _anchor.j) return false;
    // The local window must stop granting access when its chest is out of reach.
    var _px = (_anchor.i + _anchor.w * 0.5) * TILE_SIZE;
    var _py = (_anchor.j + _anchor.h * 0.5) * TILE_SIZE;
    return point_distance(_px, _py, MY_PLAYER.x, MY_PLAYER.y) <= TILE_SIZE * 5;
}

