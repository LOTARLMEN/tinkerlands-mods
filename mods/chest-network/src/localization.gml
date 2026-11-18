// Native category and language keys verified in build 22762534's lang scripts.
// Category identifiers remain unchanged: translated labels are presentation only.
function CN_LocalizationState()
{
    if (!variable_global_exists("__cn_locale"))
        variable_global_set("__cn_locale", { signature: "", labels: {}, types: {} });
    return variable_global_get("__cn_locale");
}

function CN_RefreshLanguage()
{
    var _s = CN_LocalizationState();
    // A translated language label plus Etc distinguishes all ten shipped locales,
    // including Spanish/Portuguese (both use "Idioma"). No guessed enum numbers.
    var _language = CN_NativeCall("lang", [E_LANG_KEY.K_MENU_OPTIONS_LANGUAGE]);
    var _etc = CN_NativeCall("lang_item_type", ["Etc"]);
    var _signature = string(_language) + "|" + string(_etc);
    if (_s.signature == _signature) return false;
    _s.signature = _signature;
    _s.types = {};
    var _labels = ["All", "Search", "Slots", "A–Z", "Network", "View"];
    if (_language == "Язык") _labels = ["Все", "Поиск", "Слоты", "А–Я", "Сеть", "Просмотр"];
    else if (_language == "Sprache") _labels = ["Alle", "Suchen", "Plätze", "A–Z", "Netz", "Ansicht"];
    else if (_language == "Langue") _labels = ["Tous", "Recherche", "Cases", "A–Z", "Réseau", "Lecture"];
    else if (_language == "Idioma" && _etc == "Etc.") _labels = ["Todos", "Buscar", "Espaços", "A–Z", "Rede", "Ver"];
    else if (_language == "Idioma") _labels = ["Todos", "Buscar", "Casillas", "A–Z", "Red", "Ver"];
    else if (_language == "语言") _labels = ["全部", "搜索", "格位", "名称", "网络", "查看"];
    else if (_language == "語言") _labels = ["全部", "搜尋", "欄位", "名稱", "網路", "檢視"];
    else if (_language == "言語") _labels = ["すべて", "検索", "スロット", "名前順", "接続", "閲覧"];
    else if (_language == "언어") _labels = ["전체", "검색", "슬롯", "이름순", "연결", "보기"];
    // `all` is a built-in numeric constant in GML, not a legal bare field key.
    _s.labels = { label_all: _labels[0], label_search: _labels[1], label_source: _labels[2],
                  label_name: _labels[3], label_network: _labels[4], label_view: _labels[5] };
    CN_ProbeLog("NATIVE LANGUAGE: " + _signature);
    return true;
}

function CN_UIText(_key)
{
    // Keep the function result in a local: ModExt's VM does not reliably resolve
    // a member access directly on the result of an interpreted function call.
    var _s = CN_LocalizationState();
    return variable_struct_get(_s.labels, "label_" + _key);
}

function CN_LocalizedType(_type)
{
    if (_type == "") return CN_UIText("all");
    var _s = CN_LocalizationState();
    if (!variable_struct_exists(_s.types, _type))
    {
        var _label = CN_NativeCall("lang_item_type", [_type]);
        if (!is_string(_label) || _label == "") _label = _type;
        variable_struct_set(_s.types, _type, _label);
    }
    return variable_struct_get(_s.types, _type);
}

function CN_NameSortKey(_name)
{
    // Russian dictionaries collate Е/Ё together. Unicode puts ё after я.
    return string_replace_all(CN_NormalizeName(_name), "ё", "е");
}
