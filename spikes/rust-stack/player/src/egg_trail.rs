//! Drawing-only carried eggs. Core inventory, loose-egg physics and throws stay authoritative.
use eggshell_spike_core::{EntityStatus, Presentation, SCALE, Session};
use serde::Deserialize;
use std::collections::{HashMap, VecDeque};

#[derive(Clone, Debug, Deserialize)]
pub struct TrailStep {
    pub tick: i64,
    pub map: usize,
    pub player: [f64; 2],
    pub initial: [f64; 2],
    pub count: usize,
    /// Confirmed loose-egg acquisitions, in inventory order, at their pickup positions.
    pub pickups: Vec<[f64; 2]>,
    pub laid: bool,
    pub facing: i64,
    /// Current pack image point relative to the body. The first grab uses its own first-frame point.
    pub hand: Option<[f64; 2]>,
    pub grab: [f64; 2],
}
struct Egg {
    at: [f64; 2],
    delay: usize,
    laid: Option<(i64, i64)>,
    target: Option<[f64; 2]>,
}
#[derive(Default)]
pub struct EggTrail {
    last: Option<(i64, usize)>,
    path: VecDeque<[f64; 2]>,
    eggs: Vec<Egg>,
    frames: VecDeque<(i64, usize, Vec<[f64; 2]>)>,
    aiming: bool,
    origins: Vec<i64>,
    loose: HashMap<i64, EntityStatus>,
    digest: i64,
}
impl EggTrail {
    pub fn observe(
        &mut self,
        p: &Presentation,
        session: &Session,
        hand: Option<[f64; 2]>,
        grab: [f64; 2],
    ) {
        if self.last == Some((p.tick, p.map_index)) {
            return;
        }
        self.reset_if_discontinuous(p.tick, p.map_index);
        // Narrow read-only bridge: Presentation carries colours but omits inventory
        // origin tokens. These saved fields identify placed pickups even at capacity.
        let origins: Vec<_> = (0..p.player.eggs.len())
            .map(|slot| {
                session
                    .saved_field(&format!("egg_origin_{slot}"))
                    .unwrap_or(0)
            })
            .collect();
        let growing = p.player.eggs.len().saturating_sub(self.eggs.len());
        let pickups = p
            .entities
            .iter()
            .filter(|e| {
                e.code == "o7"
                    && e.status == EntityStatus::Defeated
                    && (self.loose.get(&e.token) == Some(&EntityStatus::Active)
                        || self.last.is_none() && p.tick <= 1)
            })
            .filter(|e| {
                origins.contains(&e.token) && !self.origins.contains(&e.token)
                    || growing > 0 && self.loose.get(&e.token) == Some(&EntityStatus::Active)
            })
            .map(|e| pixels(e.motion.current))
            .collect();
        let digest = session.saved_field("move_digest_ticks").unwrap_or(0);
        let laid = self.digest > 0 && digest == 0;
        self.advance(&TrailStep {
            tick: p.tick,
            map: p.map_index,
            player: pixels(p.player.motion.current),
            initial: pixels(p.player.motion.previous),
            count: p.player.eggs.len(),
            pickups,
            laid,
            facing: p.player.facing,
            hand,
            grab,
        });
        self.origins = origins;
        self.digest = digest;
        self.loose = p
            .entities
            .iter()
            .filter(|e| e.code == "o7")
            .map(|e| (e.token, e.status))
            .collect();
    }
    fn reset_if_discontinuous(&mut self, tick: i64, map: usize) {
        if self
            .last
            .is_some_and(|(last, old)| old != map || tick < last || tick > last + 1)
        {
            *self = Self::default();
        }
    }
    pub fn advance(&mut self, s: &TrailStep) -> Vec<[f64; 2]> {
        if self.last == Some((s.tick, s.map)) {
            return self.eggs.iter().map(|e| e.at).collect();
        }
        self.reset_if_discontinuous(s.tick, s.map);
        if self.path.is_empty() {
            self.path.resize(60, s.initial)
        }
        // Remove consumed/overflowed slots before adding new ones. A throw consumes
        // the front; count alone would miss replacement at six eggs.
        let additions = s.pickups.len() + usize::from(s.laid);
        let keep = s.count.saturating_sub(additions);
        let removed = self.eggs.len().saturating_sub(keep);
        if removed > 0 {
            self.eggs.drain(..removed);
        }
        let held_before = self.aiming && removed == 0;
        for (slot, egg) in self.eggs.iter_mut().enumerate() {
            if held_before && slot == 0 {
                continue;
            }
            // Advance the tween already scheduled on the previous saved step.
            if let Some(goal) = egg.target {
                for (at, target) in egg.at.iter_mut().zip(goal) {
                    *at += (target - *at) / 6.0;
                }
            }
        }
        if s.hand.is_some() && !held_before {
            let count = s.count;
            for (slot, egg) in self.eggs.iter_mut().enumerate() {
                egg.delay = if slot == 0 { count } else { slot };
            }
        }
        self.path.push_back(s.player);
        while self.path.len() > 60 {
            self.path.pop_front();
        }
        // Follow targets are scheduled before loose pickups join/reindex the line.
        // A new acquisition therefore holds for one extra step before catching up.
        for (slot, egg) in self.eggs.iter_mut().enumerate() {
            if s.hand.is_some() && slot == 0 {
                egg.target = None;
                continue;
            }
            egg.target = target(&self.path, egg, s.tick);
        }
        for at in &s.pickups {
            if self.eggs.len() == s.count {
                break;
            }
            self.eggs.push(Egg {
                at: *at,
                delay: self.eggs.len() + 1,
                laid: None,
                target: None,
            });
        }
        while self.eggs.len() < s.count {
            self.eggs.push(Egg {
                at: [s.player[0], s.player[1] - 16.0],
                delay: self.eggs.len() + 1,
                laid: s.laid.then_some((s.tick, s.facing)),
                target: None,
            });
        }
        if removed > 0 {
            for (slot, egg) in self.eggs.iter_mut().enumerate() {
                egg.delay = slot + 1;
            }
        }
        if let Some(now) = s.hand
            && let Some(egg) = self.eggs.first_mut()
        {
            let offset = if held_before { now } else { s.grab };
            egg.at = [s.player[0] + offset[0], s.player[1] + offset[1]];
        }
        self.aiming = s.hand.is_some();
        if self.last.is_none() {
            for egg in &mut self.eggs {
                if egg.laid.is_none() {
                    egg.target = target(&self.path, egg, s.tick);
                }
            }
        }
        self.last = Some((s.tick, s.map));
        let positions = self.eggs.iter().map(|e| e.at).collect::<Vec<_>>();
        self.frames.push_back((s.tick, s.map, positions.clone()));
        positions
    }
    pub fn positions(
        &mut self,
        tick: i64,
        map: usize,
        at: [f64; 2],
        count: usize,
    ) -> Vec<[f64; 2]> {
        if let Some(index) = self
            .frames
            .iter()
            .position(|(t, m, e)| *t == tick && *m == map && e.len() == count)
        {
            self.frames.drain(..index);
            self.frames[0].2.clone()
        } else {
            vec![[at[0], at[1] - 16.0]; count]
        }
    }
}
fn target(path: &VecDeque<[f64; 2]>, egg: &Egg, tick: i64) -> Option<[f64; 2]> {
    let back = (egg.delay * 10).min(60);
    let at = path.get(path.len().checked_sub(back)?)?;
    let mut goal = [at[0], at[1] - 16.0];
    if let Some((born, facing)) = egg.laid {
        goal[0] -= facing as f64 * 32.0 * (1.0 - (tick - born) as f64 / 9.0).clamp(0.0, 1.0);
    }
    Some(goal)
}
fn pixels(p: eggshell_spike_core::Position) -> [f64; 2] {
    [p.x as f64 / SCALE as f64, p.y as f64 / SCALE as f64]
}

/// Keep the pack's per-frame hand anchors; no invented pose-dependent offsets.
#[derive(Default)]
pub struct HandPoints(HashMap<usize, [f64; 2]>);
impl HandPoints {
    pub fn prepare(manifest: &serde_json::Value, catalog: &crate::binding::Catalog) -> Self {
        Self::prepare_named(manifest, catalog, "Egg")
    }
    pub fn prepare_named(
        manifest: &serde_json::Value,
        catalog: &crate::binding::Catalog,
        name: &str,
    ) -> Self {
        let mut points = HashMap::new();
        if let Some(animations) = manifest
            .get("player")
            .and_then(serde_json::Value::as_object)
        {
            for animation in animations.values() {
                for frame in animation
                    .get("frames")
                    .and_then(serde_json::Value::as_array)
                    .into_iter()
                    .flatten()
                {
                    let Some(point) = frame
                        .get("image_points")
                        .and_then(serde_json::Value::as_array)
                        .and_then(|ps| ps.iter().find(|p| p[0].as_str() == Some(name)))
                    else {
                        continue;
                    };
                    let Some(image) = frame["file"]
                        .as_str()
                        .and_then(|f| catalog.files.iter().position(|s| s == f))
                    else {
                        continue;
                    };
                    let axis = |a: usize| {
                        point[a + 1].as_f64().unwrap_or(0.0)
                            * frame["size"][a].as_f64().unwrap_or(0.0)
                            - frame["origin"][a].as_f64().unwrap_or(0.0)
                    };
                    points.insert(image, [axis(0), axis(1)]);
                }
            }
        }
        Self(points)
    }
    pub fn at(&self, image: usize, body: [f64; 2], facing: i64, density: u32) -> Option<[f64; 2]> {
        let offset = self.0.get(&image)?;
        Some([
            body[0] + offset[0] * facing as f64 / density as f64,
            body[1] + offset[1] / density as f64,
        ])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn step(tick: i64, count: usize) -> TrailStep {
        TrailStep {
            tick,
            map: 1,
            player: [tick as f64 * 4.0, 100.0],
            initial: [0.0, 100.0],
            count,
            pickups: vec![],
            laid: false,
            facing: 1,
            hand: None,
            grab: [0.0, 0.0],
        }
    }
    #[test]
    fn held_anchor_uses_pack_size_origin_facing_and_density() {
        let manifest = serde_json::json!({"player":{"GrabEgg0":{"fps":24,"frames":[{
            "file":"hand.png","size":[42,60],"origin":[20,60],"image_points":[["Egg",12.0/42.0,34.0/60.0]]
        }]}}});
        let mut catalog = crate::binding::Catalog::default();
        let art = catalog
            .visual(
                &serde_json::json!({"animations":manifest["player"]}),
                0,
                2,
                false,
            )
            .unwrap();
        let points = HandPoints::prepare(&manifest, &catalog);
        let image = art.sample(0, "GrabEgg0", 0, Some(0)).image;
        assert_eq!(points.at(image, [100.0, 400.0], 1, 2), Some([96.0, 387.0]));
        assert_eq!(
            points.at(image, [100.0, 400.0], -1, 2),
            Some([104.0, 387.0])
        );
        assert_eq!(points.at(99, [0.0; 2], 1, 1), None);
    }
    #[test]
    fn all_six_follow_ten_step_delays_then_settle_without_a_bounce() {
        let mut trail = EggTrail::default();
        for t in 0..180 {
            trail.advance(&step(t, 6));
        }
        let eggs = trail.positions(179, 1, [716.0, 100.0], 6);
        for (k, e) in eggs.iter().enumerate() {
            assert!(
                (e[0] - (716.0 - 4.0 * (15 + 10 * k) as f64)).abs() < 0.001,
                "{eggs:?}"
            );
        }
        for t in 180..360 {
            let mut s = step(t, 6);
            s.player = [716.0, 100.0];
            trail.advance(&s);
        }
        for e in trail.positions(359, 1, [716.0, 100.0], 6) {
            assert!((e[0] - 716.0).abs() < 0.001);
            assert_eq!(e[1], 84.0);
        }
    }
    #[test]
    fn pickup_origin_is_preserved_and_aim_holds_one_egg_and_closes_the_line() {
        let mut trail = EggTrail::default();
        let mut s = step(0, 2);
        s.pickups = vec![[10.0, 80.0], [20.0, 70.0]];
        assert_eq!(trail.advance(&s), s.pickups);
        let mut s = step(1, 2);
        s.hand = Some([3.0, 60.0]);
        s.grab = [4.0, 62.0];
        assert_eq!(
            trail.advance(&s)[0],
            [s.player[0] + s.grab[0], s.player[1] + s.grab[1]]
        );
        assert_eq!(trail.eggs[1].delay, 1);
        let mut s = step(2, 2);
        s.hand = Some([7.0, 58.0]);
        assert_eq!(trail.advance(&s)[0], [15.0, 158.0]);
        let s = step(3, 1);
        trail.advance(&s);
        assert_eq!(trail.eggs[0].delay, 1);
    }
    #[test]
    fn laid_egg_has_two_step_hold_then_a_nine_step_rear_offset_not_random_wobble() {
        let mut trail = EggTrail::default();
        let mut s = step(0, 1);
        s.player = [100.0, 100.0];
        s.initial = s.player;
        s.laid = true;
        assert_eq!(trail.advance(&s), vec![[100.0, 84.0]]);
        s.laid = false;
        s.tick = 1;
        assert_eq!(trail.advance(&s), vec![[100.0, 84.0]]);
        s.tick = 2;
        let at = trail.advance(&s)[0];
        assert!((at[0] - (100.0 - 32.0 * 8.0 / 9.0 / 6.0)).abs() < 1e-9);
        for t in 3..120 {
            s.tick = t;
            trail.advance(&s);
        }
        assert!((trail.eggs[0].at[0] - 100.0).abs() < 0.001);
    }
    #[test]
    fn joining_holds_one_extra_step_and_overflow_reindexes_after_scheduling() {
        let mut trail = EggTrail::default();
        for t in 0..100 {
            trail.advance(&step(t, 6));
        }
        let mut s = step(100, 6);
        s.pickups = vec![[450.0, 70.0]];
        let first = trail.advance(&s);
        assert_eq!(first[5], [450.0, 70.0]);
        assert_eq!(trail.eggs[0].delay, 1);
        s.tick = 101;
        s.pickups.clear();
        assert_eq!(trail.advance(&s)[5], [450.0, 70.0]);
        s.tick = 102;
        assert_ne!(trail.advance(&s)[5], [450.0, 70.0]);
    }
    #[test]
    fn cancelled_aim_returns_held_picture_to_its_tail_delay() {
        let mut trail = EggTrail::default();
        for t in 0..100 {
            trail.advance(&step(t, 3));
        }
        let mut s = step(100, 3);
        s.hand = Some([-4.0, -24.0]);
        s.grab = [-4.0, -24.0];
        let held = trail.advance(&s)[0];
        assert_eq!(trail.eggs[0].delay, 3);
        s.tick = 101;
        s.hand = None;
        assert_eq!(trail.advance(&s)[0], held);
        s.tick = 102;
        assert_ne!(trail.advance(&s)[0], held);
        assert_eq!(
            trail.eggs.iter().map(|e| e.delay).collect::<Vec<_>>(),
            [3, 1, 2]
        );
    }
    #[test]
    fn draw_cadence_map_change_and_restore_do_not_invent_steps() {
        let mut trail = EggTrail::default();
        let first = trail.advance(&step(0, 6));
        for t in 1..100 {
            trail.advance(&step(t, 6));
        }
        assert_eq!(trail.positions(0, 1, [0.0, 100.0], 6), first);
        let latest = trail.positions(99, 1, [396.0, 100.0], 6);
        assert_eq!(trail.positions(99, 1, [396.0, 100.0], 6), latest);
        assert_eq!(trail.frames.len(), 1);
        assert_eq!(trail.advance(&step(1, 1)), vec![[4.0, 84.0]]);
        let mut s = step(2, 1);
        s.map = 2;
        assert_eq!(trail.advance(&s), vec![[8.0, 84.0]]);
    }
}
