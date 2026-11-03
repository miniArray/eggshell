//! Captor art and its spawn-relative animation clock. Simulation owns all motion.
use eggshell_spike_core::Presentation;
use serde_json::Value;

/// Numeric visual entry in the pinned pack. Captors are companion auxiliaries,
/// not runtime entity codes, so the ordinary object-code table cannot bind them.
pub fn art(manifest: &Value) -> Option<&Value> {
    manifest
        .get("hud")
        .and_then(|hud| hud.get("captor"))
        .or_else(|| manifest.get("visuals")?.get("486"))
}

#[derive(Default)]
pub struct Captors {
    last: Option<(i64, usize)>,
    start: Option<i64>,
    finished: Option<(i64, i64)>,
}
impl Captors {
    pub fn observe(&mut self, p: &Presentation) {
        self.step(
            p.tick,
            p.map_index,
            p.companions.rescuers.iter().any(|a| a.visible),
        );
    }
    fn step(&mut self, tick: i64, map: usize, active: bool) {
        if self
            .last
            .is_some_and(|(last, old_map)| tick < last || map != old_map)
        {
            *self = Self::default();
        }
        if active {
            self.start.get_or_insert(tick);
        } else if let Some(start) = self.start.take() {
            // The drawing thread may still consume the preceding active picture.
            self.finished = Some((start, tick));
        }
        self.last = Some((tick, map));
    }
    pub fn age(&self, tick: i64) -> i64 {
        self.start
            .filter(|start| *start <= tick)
            .or_else(|| {
                self.finished
                    .filter(|(start, end)| (*start..*end).contains(&tick))
                    .map(|(start, _)| start)
            })
            .map_or(0, |start| tick - start)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::binding::Catalog;
    #[test]
    fn binds_visual_and_starts_four_frame_flight_at_spawn() {
        let manifest = serde_json::json!({"visuals":{"486":{"default_animation":"Fly","animations":{"Fly":{
            "fps":36,"loop":true,"frames":[{"file":"a.png"},{"file":"b.png"},{"file":"c.png"},{"file":"d.png"}]
        }}}}});
        let visual = Catalog::default()
            .visual(art(&manifest).unwrap(), 0, 1, false)
            .unwrap();
        let mut clock = Captors::default();
        clock.step(485, 1, true);
        let first = visual.sample(0, "Fly", 0, None).image;
        for (age, expected) in [
            (0, 0),
            (1, 0),
            (2, 1),
            (3, 1),
            (4, 2),
            (5, 3),
            (6, 3),
            (7, 0),
        ] {
            clock.step(485 + age, 1, true);
            assert_eq!(
                visual.sample(clock.age(485 + age), "", 0, None).image,
                first + expected
            );
        }
        clock.step(500, 1, false);
        assert_eq!(clock.age(490), 5);
        clock.step(510, 1, true);
        assert_eq!(clock.age(510), 0);
        clock.step(3, 1, true);
        assert_eq!(clock.age(3), 0);
        clock.step(4, 2, true);
        assert_eq!(clock.age(4), 0);
    }
}
