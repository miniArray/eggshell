//! Drawing-only carried eggs. Core inventory, loose-egg physics and throws stay authoritative.
//!
//! Follow rule (original Egg Following group): a history of at most 60 Yoshi positions;
//! one-based egg order k tweens over 0.1 s (a sixth per step) toward history entry
//! `len - 1 - 10*k`, 16 px up. The original pushes every tick, so eggs close up on a
//! standing Yoshi. The Rust line's chosen rule (user's play of the original) differs:
//! a position is recorded only when Yoshi moved, and after six still steps the eggs
//! drop to his feet level and keep their spacing. Overflow: when a full queue pushes
//! an egg out (core `PlayerPicture::egg_pops`), the front egg falls off screen with
//! the egg platform's gravity (1600 px/s², cap 576 px/s).
use eggshell_spike_core::{EntityStatus, Presentation, SCALE, Session};
use serde::Deserialize;
use std::collections::{HashMap, VecDeque};

#[derive(Clone, Debug, Deserialize)]
pub struct TrailStep {
    pub tick: i64,
    pub map: usize,
    pub player: [f64; 2],
    pub count: usize,
    /// Confirmed loose-egg acquisitions, in inventory order, at their pickup positions.
    pub pickups: Vec<[f64; 2]>,
    pub laid: bool,
    pub facing: i64,
    /// Current pack image point relative to the body. The first grab uses its own first-frame point.
    pub hand: Option<[f64; 2]>,
    pub grab: [f64; 2],
    /// Front eggs pushed out of a full queue on this step (rise of `egg_pops`).
    #[serde(default)]
    pub popped: usize,
    /// Carried egg colours this step, front first (the colour of a later dropped egg).
    #[serde(default)]
    pub colours: Vec<i64>,
}
struct Egg {
    at: [f64; 2],
    delay: usize,
    laid: Option<(i64, i64)>,
    /// Delay captured when the tween target was scheduled; applied on the next step.
    scheduled: Option<usize>,
}
/// A front egg pushed out of a full queue, falling off screen.
#[derive(Clone)]
struct FallingEgg {
    at: [f64; 2],
    vy: f64,
    fallen: f64,
    colour: i64,
}
/// Positions to draw for one observed step.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct TrailFrame {
    pub carried: Vec<[f64; 2]>,
    /// Colour and position of each dropped egg still falling.
    pub falling: Vec<(i64, [f64; 2])>,
}
#[derive(Default)]
pub struct EggTrail {
    last: Option<(i64, usize)>,
    path: VecDeque<[f64; 2]>,
    /// Steps since Yoshi last moved.
    still: i64,
    eggs: Vec<Egg>,
    falling: Vec<FallingEgg>,
    colours: Vec<i64>,
    frames: VecDeque<(i64, usize, TrailFrame)>,
    aiming: bool,
    /// Last observed `egg_pops`; None until the first observation (a restore resets it).
    pops: Option<u64>,
    loose: HashMap<i64, EntityStatus>,
    digest: i64,
}
impl EggTrail {
    const KEEP: usize = 60;
    const SPACING: usize = 10;
    const LIFT: f64 = 16.0;
    /// Steps without movement before the eggs drop to Yoshi's feet level.
    const STILL_TICKS: i64 = 6;
    /// Egg platform gravity and fall cap in px per step (1600 px/s², 576 px/s at 60 Hz).
    const GRAVITY: f64 = 1600.0 / 3600.0;
    const MAX_FALL: f64 = 576.0 / 60.0;
    /// Taller than any view, so a dropped egg is off screen before it is forgotten.
    const FORGET: f64 = 1024.0;
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
        let popped = self
            .pops
            .map_or(0, |last| p.player.egg_pops.saturating_sub(last) as usize);
        // New inventory this step: growth plus replacements of popped front eggs.
        let added = p.player.eggs.len().saturating_sub(self.eggs.len()) + popped;
        let digest = session.saved_field("move_digest_ticks").unwrap_or(0);
        let laid = self.digest > 0 && digest == 0;
        let pickups = p
            .entities
            .iter()
            .filter(|e| {
                e.code == "o7"
                    && e.status == EntityStatus::Defeated
                    && (self.loose.get(&e.token) == Some(&EntityStatus::Active)
                        || self.last.is_none() && p.tick <= 1)
            })
            .take(added.saturating_sub(usize::from(laid)))
            .map(|e| pixels(e.motion.current))
            .collect();
        self.advance(&TrailStep {
            tick: p.tick,
            map: p.map_index,
            player: pixels(p.player.motion.current),
            count: p.player.eggs.len(),
            pickups,
            laid,
            facing: p.player.facing,
            hand,
            grab,
            popped,
            colours: p.player.eggs.clone(),
        });
        self.pops = Some(p.player.egg_pops);
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
        let first = self.last.is_none();
        // A full queue pushes its front eggs out: they fall off screen.
        let popped = s.popped.min(self.eggs.len());
        for (k, egg) in self.eggs.drain(..popped).enumerate() {
            self.falling.push(FallingEgg {
                at: egg.at,
                vy: 0.0,
                fallen: 0.0,
                colour: self.colours.get(k).copied().unwrap_or(0),
            });
        }
        // A throw consumes the front slot; count alone would miss which end.
        let additions = s.pickups.len() + usize::from(s.laid);
        let keep = s.count.saturating_sub(additions);
        let thrown = self.eggs.len().saturating_sub(keep);
        self.eggs.drain(..thrown);
        let removed = popped + thrown;
        let held_before = self.aiming && removed == 0;
        if self.path.back() == Some(&s.player) {
            self.still += 1;
        } else {
            self.still = 0;
            self.path.push_back(s.player);
            while self.path.len() > Self::KEEP {
                self.path.pop_front();
            }
        }
        for f in &mut self.falling {
            f.vy = (f.vy + Self::GRAVITY).min(Self::MAX_FALL);
            f.at[1] += f.vy;
            f.fallen += f.vy;
        }
        self.falling.retain(|f| f.fallen < Self::FORGET);
        // Advance the tween scheduled on the previous saved step.
        for slot in 0..self.eggs.len() {
            if held_before && slot == 0 {
                continue;
            }
            let egg = &self.eggs[slot];
            if let Some(delay) = egg.scheduled {
                let goal = self.goal(delay, egg.laid, s.tick - 1, s.player);
                let egg = &mut self.eggs[slot];
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
        // Targets are scheduled before loose pickups join/reindex the line.
        // A new acquisition therefore holds for one extra step before catching up.
        for (slot, egg) in self.eggs.iter_mut().enumerate() {
            egg.scheduled = (s.hand.is_none() || slot != 0).then_some(egg.delay);
        }
        for at in &s.pickups {
            if self.eggs.len() == s.count {
                break;
            }
            let delay = self.eggs.len() + 1;
            self.eggs.push(Egg {
                at: *at,
                delay,
                laid: None,
                scheduled: first.then_some(delay),
            });
        }
        while self.eggs.len() < s.count {
            let delay = self.eggs.len() + 1;
            self.eggs.push(Egg {
                at: [s.player[0], s.player[1] - Self::LIFT],
                delay,
                laid: s.laid.then_some((s.tick, s.facing)),
                scheduled: (first && !s.laid).then_some(delay),
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
        self.colours = s.colours.clone();
        self.last = Some((s.tick, s.map));
        let frame = TrailFrame {
            carried: self.eggs.iter().map(|e| e.at).collect(),
            falling: self.falling.iter().map(|f| (f.colour, f.at)).collect(),
        };
        let positions = frame.carried.clone();
        self.frames.push_back((s.tick, s.map, frame));
        positions
    }
    /// Target of a following egg: history entry `len - 1 - 10*delay` (the oldest entry
    /// while the history is short), 16 px up; at Yoshi's feet level once he stands.
    fn goal(&self, delay: usize, laid: Option<(i64, i64)>, tick: i64, now: [f64; 2]) -> [f64; 2] {
        let at = self
            .path
            .len()
            .checked_sub(1 + Self::SPACING * delay)
            .and_then(|i| self.path.get(i))
            .or(self.path.front())
            .copied()
            .unwrap_or(now);
        let mut goal = [at[0], at[1] - Self::LIFT];
        if self.still >= Self::STILL_TICKS {
            goal[1] = now[1] - Self::LIFT;
        }
        if let Some((born, facing)) = laid {
            goal[0] -= facing as f64 * 32.0 * (1.0 - (tick - born) as f64 / 9.0).clamp(0.0, 1.0);
        }
        goal
    }
    /// The observed step's positions. A worker can process an entire catch-up batch
    /// while the prepared frame is still drawing: samples stay until that frame
    /// consumes them.
    pub fn positions(&mut self, tick: i64, map: usize, at: [f64; 2], count: usize) -> TrailFrame {
        if let Some(index) = self
            .frames
            .iter()
            .position(|(t, m, f)| *t == tick && *m == map && f.carried.len() == count)
        {
            self.frames.drain(..index);
            self.frames[0].2.clone()
        } else {
            TrailFrame {
                carried: vec![[at[0], at[1] - Self::LIFT]; count],
                falling: Vec::new(),
            }
        }
    }
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
            count,
            pickups: vec![],
            laid: false,
            facing: 1,
            hand: None,
            grab: [0.0, 0.0],
            popped: 0,
            colours: vec![0; count],
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
    fn all_six_follow_ten_step_delays_then_stand_spaced_without_a_bounce() {
        let mut trail = EggTrail::default();
        for t in 0..180 {
            trail.advance(&step(t, 6));
        }
        // Ten steps of delay per egg plus five steps of tween lag. The sixth egg reads
        // the oldest of 60 entries, one step newer than ten times its order.
        let eggs = trail.positions(179, 1, [716.0, 100.0], 6).carried;
        let lags = [15, 25, 35, 45, 55, 64];
        for (e, lag) in eggs.iter().zip(lags) {
            assert!(
                (e[0] - (716.0 - 4.0 * lag as f64)).abs() < 0.001,
                "{eggs:?}"
            );
        }
        for t in 180..360 {
            let mut s = step(t, 6);
            s.player = [716.0, 100.0];
            trail.advance(&s);
        }
        // Standing keeps ten recorded positions per egg (the sixth: the oldest entry).
        let eggs = trail.positions(359, 1, [716.0, 100.0], 6).carried;
        let xs = [676.0, 636.0, 596.0, 556.0, 516.0, 480.0];
        for (e, x) in eggs.iter().zip(xs) {
            assert!((e[0] - x).abs() < 0.001, "{eggs:?}");
            assert!((e[1] - 84.0).abs() < 1e-9);
        }
    }
    #[test]
    fn standing_eggs_stay_spaced_and_drop_to_yoshi_level() {
        let mut t = EggTrail::default();
        // Walk right 2 px a step on y 100, jump the last 20 steps (y 80), then land.
        for tick in 0..60 {
            let mut s = step(tick, 3);
            s.player = [tick as f64 * 2.0, if tick >= 40 { 80.0 } else { 100.0 }];
            t.advance(&s);
        }
        let mut eggs = Vec::new();
        for tick in 60..200 {
            let mut s = step(tick, 3);
            s.player = [118.0, 100.0];
            eggs = t.advance(&s);
        }
        // Spaced by 10 recorded positions (20 px) behind Yoshi (the landing adds one
        // record at x 118), all at his feet level - 16.
        for (k, egg) in eggs.iter().enumerate() {
            let x = 120.0 - 20.0 * (k + 1) as f64;
            assert!(
                (egg[0] - x).abs() < 0.5 && (egg[1] - 84.0).abs() < 0.5,
                "{k} {egg:?}"
            );
        }
    }
    #[test]
    fn a_seventh_egg_drops_the_front_egg() {
        let mut t = EggTrail::default();
        let mut s = step(0, 6);
        s.player = [100.0, 50.0];
        s.colours = vec![1, 0, 0, 0, 0, 2];
        let before = t.advance(&s);
        // Made at six: the front (yellow) egg falls, the rest move up one place and
        // the new egg appears at Yoshi.
        s.tick = 1;
        s.popped = 1;
        s.colours = vec![0, 0, 0, 0, 2, 0];
        let after = t.advance(&s);
        assert_eq!(after[..5], before[1..]);
        assert_eq!(after[5], [100.0, 34.0]);
        let falling = t.positions(1, 1, [100.0, 50.0], 6).falling;
        assert_eq!(falling.len(), 1);
        assert_eq!(falling[0].0, 1);
        assert!(falling[0].1[1] > before[0][1]);
        // It keeps falling at most 9.6 px per step, then is forgotten.
        let mut last = falling[0].1[1];
        s.popped = 0;
        for tick in 2..200 {
            s.tick = tick;
            t.advance(&s);
            if let Some((_, at)) = t.positions(tick, 1, [100.0, 50.0], 6).falling.first() {
                assert!(at[1] - last <= 9.6 + 1e-9);
                last = at[1];
            }
        }
        assert!(t.positions(199, 1, [100.0, 50.0], 6).falling.is_empty());
    }
    #[test]
    fn a_restore_resets_the_pop_baseline_without_dropping() {
        let mut t = EggTrail {
            pops: Some(3),
            ..EggTrail::default()
        };
        t.advance(&step(0, 6));
        // A rewind (restore) starts again; the next observation only sets a baseline.
        t.reset_if_discontinuous(0, 2);
        assert_eq!(t.pops, None);
        assert!(t.falling.is_empty());
    }
    #[test]
    fn short_history_leaves_eggs_where_they_appeared() {
        let mut t = EggTrail::default();
        let mut s = step(0, 1);
        s.player = [10.0, 50.0];
        assert_eq!(t.advance(&s), vec![[10.0, 34.0]]);
        for tick in 1..=5 {
            s.tick = tick;
            s.player = [10.0 + 4.0 * tick as f64, 50.0];
            assert_eq!(t.advance(&s), vec![[10.0, 34.0]]);
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
        let front = trail.eggs[0].at;
        let mut s = step(100, 6);
        s.pickups = vec![[450.0, 70.0]];
        s.popped = 1;
        let first = trail.advance(&s);
        assert_eq!(first[5], [450.0, 70.0]);
        assert_eq!(trail.eggs[0].delay, 1);
        let falling = trail.positions(100, 1, [400.0, 100.0], 6).falling;
        assert_eq!(falling.len(), 1);
        assert_eq!(falling[0].1[0], front[0]);
        s.tick = 101;
        s.pickups.clear();
        s.popped = 0;
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
        assert_eq!(trail.positions(0, 1, [0.0, 100.0], 6).carried, first);
        let latest = trail.positions(99, 1, [396.0, 100.0], 6);
        assert_eq!(trail.positions(99, 1, [396.0, 100.0], 6), latest);
        assert_eq!(trail.frames.len(), 1);
        assert_eq!(trail.advance(&step(1, 1)), vec![[4.0, 84.0]]);
        let mut s = step(2, 1);
        s.map = 2;
        assert_eq!(trail.advance(&s), vec![[8.0, 84.0]]);
    }
}
