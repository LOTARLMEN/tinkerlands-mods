// The menu probe verifies these documented functions in this ModExt runtime
// before either development tokens or persistent terminal IDs can be generated.
// Never re-seed the game's shared RNG for mod identifiers.
function CN_InitIdentity()
{
    var _state = { ready: false, sequence: 0, clock_verified: false, random_verified: false };
    variable_global_set("__cn_identity", _state);
    var _clock = date_current_datetime();
    if (!is_numeric(_clock) || !(_clock > 0 && _clock < 1000000000)) throw "Unsupported identity clock result";
    _state.clock_verified = true;
    var _sample = random(1);
    if (!is_numeric(_sample) || !(_sample >= 0 && _sample <= 1)) throw "Unsupported identity random result";
    _state.random_verified = true;
    _state.ready = true;
}

function CN_NewIdentity(_prefix)
{
    if (!variable_global_exists("__cn_identity")) throw "Identity capability probe has not run";
    var _state = variable_global_get("__cn_identity");
    if (!_state.ready || !_state.clock_verified || !_state.random_verified) throw "Identity capability probe did not pass";
    var _clock = date_current_datetime();
    if (!is_numeric(_clock) || !(_clock > 0 && _clock < 1000000000)) throw "Identity clock changed after probe";
    var _millis = floor(_clock * 86400000);
    var _first_sample = random(1073741823);
    var _second_sample = random(1073741823);
    if (!is_numeric(_first_sample) || !(_first_sample >= 0 && _first_sample <= 1073741823)) throw "Identity random changed after probe";
    if (!is_numeric(_second_sample) || !(_second_sample >= 0 && _second_sample <= 1073741823)) throw "Identity random changed after probe";
    var _first = floor(_first_sample);
    var _second = floor(_second_sample);
    _state.sequence++;
    return _prefix + ":" + string(_millis) + ":" + string(_state.sequence) + ":" + string(_first) + ":" + string(_second);
}
