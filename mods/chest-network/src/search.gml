// Search is independent of the presentation and the real container objects.

function CN_NormalizeName(_text)
{
    var _result = string_lower(string_trim(string(_text)));
    var _upper = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ";
    var _lower = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя";
    for (var _i = 1; _i <= string_length(_upper); _i++)
    {
        _result = string_replace_all(_result, string_char_at(_upper, _i), string_char_at(_lower, _i));
    }
    return _result;
}

function CN_FilterItems(_items, _query, _type)
{
    var _query_normal = CN_NormalizeName(_query);
    var _type_normal = CN_NormalizeName(_type);
    var _result = [];
    for (var _i = 0; _i < array_length(_items); _i++)
    {
        var _entry = _items[_i];
        if (_type_normal != "" && CN_NormalizeName(_entry.type) != _type_normal) continue;
        if (_query_normal != "" && string_pos(_query_normal, CN_NormalizeName(_entry.name)) == 0) continue;
        array_push(_result, _entry);
    }
    return _result;
}
