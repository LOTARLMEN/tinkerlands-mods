//! Host-side routing for one already-authorized inventory slot.
use crate::Slot;
use std::collections::HashSet;

pub(super) const SOURCE_CHANGED: f64 = -13.0;

pub(super) struct DepositRoute {
    token: u32,
    source: Slot,
    destinations: Vec<String>,
    visited: HashSet<String>,
    next: usize,
    moved: i64,
    awaiting_result: bool,
    stopped: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source(qty: i64) -> Slot {
        Slot {
            container: "inventory".into(), x: 1, y: 2, item: "stack".into(),
            qty, id: 42, favorite: false,
        }
    }

    #[test]
    fn uses_each_physical_destination_once_and_accounts_for_partial_movements() {
        let destinations = ["full", "partial", "partial", "locked", "free"].map(String::from).to_vec();
        let mut route = DepositRoute::new(1, source(12), destinations).unwrap();
        assert_eq!(route.offer("full", true, &source(12)), Ok(12.0));
        route.record(0).unwrap();
        assert_eq!(route.offer("partial", true, &source(12)), Ok(12.0));
        route.record(3).unwrap();
        assert_eq!(route.offer("partial", true, &source(9)), Ok(0.0));
        assert_eq!(route.offer("locked", false, &source(9)), Ok(0.0));
        assert_eq!(route.offer("free", true, &source(9)), Ok(9.0));
        route.record(4).unwrap();
        assert_eq!(route.finish(), Ok(7));
    }

    #[test]
    fn blocks_reordered_steps_duplicate_results_and_a_changed_source() {
        let destinations = ["one", "two", "three"].map(String::from).to_vec();
        let mut route = DepositRoute::new(1, source(12), destinations).unwrap();
        assert!(route.offer("two", true, &source(12)).is_err());
        assert_eq!(route.offer("one", true, &source(12)), Ok(12.0));
        assert!(route.finish().is_err());
        assert!(route.record(13).is_err());
        assert!(route.offer("two", true, &source(12)).is_err());
        route.record(4).unwrap();
        assert!(route.record(4).is_err());
        let replaced = Slot { item: "different".into(), ..source(8) };
        assert_eq!(route.offer("two", true, &replaced), Ok(SOURCE_CHANGED));
        assert!(route.offer("three", true, &source(8)).is_err());
        assert_eq!(route.finish(), Ok(4));
    }
}

impl DepositRoute {
    pub(super) fn new(token: u32, source: Slot, destinations: Vec<String>) -> Result<Self, &'static str> {
        if source.qty <= 0 || source.x < 0 || source.y < 0 || source.favorite {
            return Err("invalid_deposit_source");
        }
        Ok(Self {
            token, source, destinations, visited: HashSet::new(), next: 0, moved: 0,
            awaiting_result: false, stopped: false,
        })
    }

    pub(super) fn matches(&self, token: u32) -> bool {
        self.token == token
    }

    pub(super) fn offer(&mut self, destination: &str, available: bool, live: &Slot) -> Result<f64, &'static str> {
        if self.stopped || self.awaiting_result ||
            self.destinations.get(self.next).map(String::as_str) != Some(destination) {
            return Err("unexpected_deposit_destination");
        }
        self.next += 1;
        if !self.visited.insert(destination.to_owned()) || !available || destination == self.source.container {
            return Ok(0.0);
        }
        let remaining = self.source.qty - self.moved;
        if remaining == 0 || live.qty != remaining || live.favorite || !self.source.same_item(live) {
            self.stopped = true;
            return Ok(SOURCE_CHANGED);
        }
        self.awaiting_result = true;
        Ok(remaining as f64)
    }

    pub(super) fn record(&mut self, moved: i64) -> Result<(), &'static str> {
        if !self.awaiting_result || !(0..=self.source.qty - self.moved).contains(&moved) {
            return Err("unexpected_deposit_result");
        }
        self.awaiting_result = false;
        self.moved += moved;
        Ok(())
    }

    pub(super) fn finish(&self) -> Result<i64, &'static str> {
        if self.awaiting_result {
            return Err("unfinished_deposit_step");
        }
        Ok(self.moved)
    }
}
