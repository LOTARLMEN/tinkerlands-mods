//! Deduplication of read-only multiplayer inventory observations.
use crate::{binary, whole};
use serde::Deserialize;

#[derive(Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub(super) struct CoopObservation {
    #[serde(deserialize_with = "binary")]
    host: bool,
    #[serde(deserialize_with = "whole")]
    region: i32,
    local: String,
    #[serde(deserialize_with = "whole")]
    inventory_wood: i64,
    #[serde(deserialize_with = "whole")]
    cursor_wood: i64,
    chest: Option<ChestObservation>,
}

#[derive(Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct ChestObservation {
    #[serde(deserialize_with = "whole")]
    i: i32,
    #[serde(deserialize_with = "whole")]
    j: i32,
    actor: String,
    #[serde(deserialize_with = "binary")]
    native_open: bool,
    #[serde(deserialize_with = "binary")]
    claimed: bool,
    #[serde(deserialize_with = "whole")]
    wood: i64,
    #[serde(deserialize_with = "binary")]
    peer_instance: bool,
    #[serde(deserialize_with = "binary")]
    peer_record: bool,
    candidates: Vec<InventoryField>,
}

#[derive(Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct InventoryField {
    scope: String,
    field: String,
    #[serde(deserialize_with = "binary")]
    container_valid: bool,
    #[serde(deserialize_with = "binary")]
    same_as_local: bool,
    #[serde(deserialize_with = "whole")]
    width: i32,
    #[serde(deserialize_with = "whole")]
    height: i32,
    #[serde(deserialize_with = "whole")]
    wood: i64,
}

pub(super) struct CoopTrace {
    previous: Option<CoopObservation>,
}

impl CoopTrace {
    pub(super) const fn new() -> Self {
        Self { previous: None }
    }

    pub(super) fn observe(&mut self, observation: CoopObservation) -> f64 {
        if self.previous.as_ref() == Some(&observation) {
            return 0.0;
        }
        self.previous = Some(observation);
        1.0
    }

    pub(super) fn reset(&mut self) {
        self.previous = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn sample(chest_wood: u32, chest_open: bool) -> CoopObservation {
        serde_json::from_value(json!({
            "host": 1.0, "region": 0.0, "local": "1", "inventory_wood": 10.0, "cursor_wood": 0,
            "chest": { "i": 2.0, "j": 3, "actor": "2", "native_open": false, "claimed": chest_open,
                "wood": chest_wood, "peer_instance": true, "peer_record": true, "candidates": [] }
        })).unwrap()
    }

    #[test]
    fn emits_only_changes_and_reports_close_even_with_the_same_contents() {
        let mut trace = CoopTrace::new();
        assert_eq!(trace.observe(sample(0, true)), 1.0);
        assert_eq!(trace.observe(sample(0, true)), 0.0);
        assert_eq!(trace.observe(sample(1, true)), 1.0);
        assert_eq!(trace.observe(sample(1, false)), 1.0);
        trace.reset();
        assert_eq!(trace.observe(sample(1, false)), 1.0);
    }
}
