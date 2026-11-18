// Passive, bounded diagnostic output. Never changes the saver or world data.
function CN_PerformanceState()
{
    if (!variable_global_exists("__cn_performance"))
        variable_global_set("__cn_performance", { failed: false, tick: 0, sequence: 0, last_heartbeat: 0, saver_key: "" });
    return variable_global_get("__cn_performance");
}

function CN_PerformanceWrite(_kind, _data)
{
    var _s = CN_PerformanceState();
    if (_s.failed) return;
    _s.sequence++;
    var _record = { version: "0.0.40", sequence: _s.sequence, event: _kind,
                    local_datetime_serial: date_current_datetime(), data: _data };
    var _file = file_text_open_append("chest_network_performance.jsonl");
    if (_file < 0) throw "Cannot append performance trace";
    file_text_write_string(_file, json_stringify(_record));
    file_text_writeln(_file);
    file_text_close(_file);
}

function CN_PerformanceObserve()
{
    var _s = CN_PerformanceState();
    if (_s.failed) return;
    _s.tick++;
    var _save = undefined;
    var _key = "";
    if (variable_global_exists("__SAVER"))
    {
        var _saver = variable_global_get("__SAVER");
        if (is_struct(_saver))
        {
            _save = {};
            var _fields = ["stepCurrent", "stepCurrentSub", "stepCurrentSub2", "saveInOneFrame", "networkSave"];
            for (var _n = 0; _n < array_length(_fields); _n++)
            {
                if (!variable_struct_exists(_saver, _fields[_n])) continue;
                var _value = variable_struct_get(_saver, _fields[_n]);
                if (is_numeric(_value) || is_bool(_value)) variable_struct_set(_save, _fields[_n], _value);
            }
            // Log phase changes immediately. Substep counters are included in
            // heartbeats, not written to disk every frame of a large save.
            _key = "saving";
            if (variable_struct_exists(_save, "stepCurrent")) _key += ":" + string(_save.stepCurrent);
            if (variable_struct_exists(_save, "saveInOneFrame")) _key += ":" + string(_save.saveInOneFrame);
        }
    }
    if (_key != _s.saver_key)
    {
        _s.saver_key = _key;
        if (is_undefined(_save)) _save = {};
        CN_PerformanceWrite("saver_state_observed", _save);
    }
    if ((_s.tick mod 30) != 0) return;
    var _now = date_current_datetime();
    var _gap = (_now - _s.last_heartbeat) * 86400;
    if (_gap < 2) return;
    var _status = { world_ready: CN_WorldReady(), saver_observed: _key != "" };
    if (!is_undefined(_save)) _status.saver = _save;
    if (_s.last_heartbeat > 0) _status.gap_seconds = _gap;
    if (_status.world_ready) _status.region = REGION;
    if (variable_global_exists("__cn_native_view"))
    {
        var _view = variable_global_get("__cn_native_view");
        if (_view.profile_refresh_us > 0 || _view.profile_draw_us > 0)
            _status.storage = { open: !is_undefined(_view.anchor), chests: array_length(_view.nodes),
                                refresh_us_max: _view.profile_refresh_us, draw_us_max: _view.profile_draw_us };
        _view.profile_refresh_us = 0;
        _view.profile_draw_us = 0;
    }
    _s.last_heartbeat = _now;
    CN_PerformanceWrite("heartbeat", _status);
}

function CN_PerformanceFail(_error)
{
    var _s = CN_PerformanceState();
    if (!_s.failed) CN_ProbeLog("PERFORMANCE TRACE DISABLED: " + string(_error));
    _s.failed = true;
}

OnModLoad(function() { try { CN_PerformanceWrite("mod_load_callback", {}); } catch (_error) { CN_PerformanceFail(_error); } });
OnWorldGenerationStart(function() { try { CN_PerformanceWrite("world_generation_start_callback", {}); } catch (_error) { CN_PerformanceFail(_error); } });
OnWorldGenerationEnd(function() { try { CN_PerformanceWrite("world_generation_end_callback", {}); } catch (_error) { CN_PerformanceFail(_error); } });
OnIslandArrive(function() { try { CN_PerformanceWrite("island_arrive_callback", {}); } catch (_error) { CN_PerformanceFail(_error); } });
OnModUpdate(function() { try { CN_PerformanceObserve(); } catch (_error) { CN_PerformanceFail(_error); } });
