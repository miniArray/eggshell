//! spine_walker.gd (e25): a fast walker that raises a spiked shell when the player comes
//! near. The body lives in `Actor` (ActorKind::Spine).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::{After, HitKind, Hold},
    entity::Kind,
    state::Run,
    Error, Placement, SCALE as S,
};
pub(crate) const WALK: i64 = 0;
pub(crate) const SPIKE: i64 = 1;
pub(crate) const SHRINK: i64 = 2;
const TWEEN: i64 = 20;
const SPIKE_TICKS: i64 = 60;
const COOLDOWN: i64 = 60;
const REACH: i64 = 96 * S;
const SMALL: [i64; 2] = [32, 28];
const LARGE: [i64; 2] = [64, 62];
/// The raise and fold tweens (easeoutback / easeinback, 0.33 s): progress per tick in
/// millionths, so the spines overshoot.
const EASE_ONE: i64 = 1_000_000;
const RAISE_EASE: [i64; 21] = [
    0, 219874, 411136, 575029, 712976, 826562, 917532, 987775, 1039303, 1074234, 1094765, 1103152,
    1101682, 1092645, 1078311, 1060908, 1042596, 1025449, 1011443, 1002436, 1000000,
];
const FOLD_EASE: [i64; 21] = [
    0, -3753, -13902, -28689, -46230, -64529, -81494, -94948, -102654, -102337, -91703, -68471,
    -30395, 24710, 98941, 194288, 312612, 455626, 624885, 821775, 1000000,
];
/// Largest size in whole pixels the tweens reach, with the overshoot. spine_walker.gd
/// MOST is [68, 66], but its own play goes further: a raise cut short near its peak
/// (from 67 x 65) folding through the easeinback undershoot reaches 70 x 68 (Godot
/// 4.7.2 on corpus level 654d070c, idle route, ticks 540-545). Godot never validates
/// during play, only when it encodes or restores a snapshot, so its saves fail for
/// those ticks while the walker plays on. Rust validates every step, so it bounds the
/// reachable sizes instead of refusing the level.
const MOST: [i64; 2] = [70, 68];
/// Spine hull at full size, relative to the bottom centre, facing left.
const HULL: [[i64; 2]; 5] = [[-32, -18], [0, -62], [32, -46], [32, 0], [-32, 0]];
pub(crate) const BOX: [i64; 4] = [-14 * S, -10 * S, 14 * S, 16 * S];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

/// spine_walker.gd bounds
pub(crate) fn bounds(a: &Actor) -> [i64; 4] {
    if a.mode == WALK {
        return BOX;
    }
    let [w, h] = a.spine_size();
    [-w / 2, 16 * S - h, w / 2, 16 * S]
}

impl Actor {
    /// spine_walker.gd prepare + create.
    pub fn spine(p: &Placement) -> Result<Self, Error> {
        if !(0..=1).contains(&p.variant) || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e25 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::Spine, p.variant, p.mirror, p.position);
        a.colour = p.variant;
        Ok(a)
    }
    pub fn spine_valid(&self) -> bool {
        (0..=1).contains(&self.variant)
            && [0, 1].contains(&self.colour)
            && (WALK..=SHRINK).contains(&self.mode)
            && (0..=SPIKE_TICKS).contains(&self.timer)
            && (0..=COOLDOWN).contains(&self.cooldown)
            && (SMALL[0]..=MOST[0]).contains(&self.spine_w)
            && (SMALL[1]..=MOST[1]).contains(&self.spine_h)
            && (SMALL[0]..=MOST[0]).contains(&self.from_w)
            && (SMALL[1]..=MOST[1]).contains(&self.from_h)
    }
    /// spine_walker.gd spine_size: width and height in 1/S px from the tween tick.
    fn spine_size(&self) -> [i64; 2] {
        let tick = self.timer.clamp(0, TWEEN) as usize;
        if self.mode == SPIKE {
            let raise = RAISE_EASE[tick];
            return [
                SMALL[0] * S + (LARGE[0] - SMALL[0]) * S * raise / EASE_ONE,
                SMALL[1] * S + (LARGE[1] - SMALL[1]) * S * raise / EASE_ONE,
            ];
        }
        if self.mode == SHRINK {
            let fold = FOLD_EASE[tick];
            return [
                self.from_w * S + (SMALL[0] - self.from_w) * S * fold / EASE_ONE,
                self.from_h * S + (SMALL[1] - self.from_h) * S * fold / EASE_ONE,
            ];
        }
        [SMALL[0] * S, SMALL[1] * S]
    }
    /// spine_walker.gd spine_hull
    fn spine_hull(&self, body: Body, facing: i64) -> [[i64; 2]; 5] {
        let [w, h] = self.spine_size();
        HULL.map(|[px, py]| {
            let mut x = px * w / 64;
            if facing > 0 {
                x = -x;
            }
            [body.x + x, body.y + 16 * S + py * h / 62]
        })
    }
    /// spine_walker.gd shrink
    pub(crate) fn spine_shrink(&mut self) {
        if self.mode != SPIKE {
            return;
        }
        self.mode = SHRINK;
        self.timer = 0;
        self.from_w = self.spine_w;
        self.from_h = self.spine_h;
    }
    /// spine_walker.gd _reset
    fn spine_reset(&mut self) {
        self.mode = WALK;
        self.timer = 0;
        self.spine_w = SMALL[0];
        self.spine_h = SMALL[1];
    }
    /// spine_walker.gd view_state animation.
    pub fn spine_animation(&self) -> String {
        format!("{}Walk", self.colour)
    }
}

impl Run {
    /// spine_walker.gd step.
    pub(crate) fn spine_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let token = self.entities[index].origin.token();
        let Run {
            entities,
            player,
            rng,
            frame,
            camera,
            ..
        } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if w.started == 0 {
            // enemy_body.gd process: the first step's initialisation.
            w.started = 1;
            w.impact_cursor = player.impact;
            if w.mirror == 2 {
                e.facing = if player.body.x > e.body.x { 1 } else { -1 };
            }
        }
        let px = player.body.x;
        let mut step = ActorStep {
            map,
            frame: *frame,
            camera: *camera,
            player,
            rng,
        };
        let action = w.process(
            token,
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &step,
        );
        if [Hold::Held, Hold::Gone].contains(&action) {
            return Ok(());
        }
        if w.frozen != 0 {
            return Err(Error::Unsupported {
                requirements: vec!["frozen e25 spine walker (its reactions are not ported)".into()],
            });
        }
        if action == Hold::Released {
            w.spine_reset();
        }
        if let Some(after) = w.spit_step(
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &mut step,
        ) {
            if let After::HitOthers(hb) = after {
                self.hit_others(index, hb, HitKind::Spit, true)?;
            }
            return Ok(());
        }
        // enemy_body.gd hazards
        if map.lava_overlaps(world_box(e.body, BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let body = &mut e.body;
        w.cooldown = (w.cooldown - 1).max(0);
        let mut started = false;
        if w.mode == WALK {
            // spine_walker.gd _walk
            let wet = i64::from(map.water_overlaps(world_box(*body, BOX)));
            let speed = if w.colour != 0 { 128 } else { 192 };
            body.vx = e.facing * speed * 60 / (wet + 1);
            let distance = body.vx;
            let (actual, on_floor) = w.movement_box(body, BOX, map, distance);
            started = on_floor;
            if actual != distance {
                e.facing = -e.facing;
            } else if body.floor(map, BOX) != 0 {
                // enemy_motion.gd edge
                let left = if e.facing > 0 {
                    body.x
                } else {
                    body.x - 12 * S
                };
                let bottom = body.y + BOX[3];
                if !map.support_in_box([left, bottom, left + 12 * S, bottom + 28 * S]) {
                    e.facing = -e.facing;
                }
            }
        } else {
            body.vx = 0;
            w.timer += 1;
            // spine_walker.gd face_player
            if body.x != px {
                e.facing = if body.x > px { -1 } else { 1 };
            }
            let [sw, sh] = w.spine_size();
            w.spine_w = sw / S;
            w.spine_h = sh / S;
            if w.mode == SPIKE {
                if w.timer >= SPIKE_TICKS {
                    w.spine_shrink();
                }
            } else if w.timer >= TWEEN {
                w.spine_reset();
                w.cooldown = COOLDOWN;
            }
        }
        body.gravity(map, BOX, started);
        Ok(())
    }
    /// spine_walker.gd contact, with _attack after the player has moved.
    pub(crate) fn spine_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return;
        };
        let player = world_box(p, pb);
        // enemy_body.gd player_overlap with the walking box.
        let body_touch = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && strict(world_box(e.body, BOX), player);
        let spine_touch = !body_touch
            && w.mode != WALK
            && w.held == 0
            && e.status == 1
            && !captured
            && crate::wing::polygon_overlap(&w.spine_hull(e.body, e.facing), player);
        if body_touch || spine_touch {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        // spine_walker.gd _attack
        let (px, py) = (self.player.body.x, self.player.body.y);
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        if w.mode == WALK
            && w.cooldown == 0
            && w.held == 0
            && !captured
            && (e.body.x - px).abs() < REACH
            && (e.body.y - py).abs() < REACH
        {
            w.mode = SPIKE;
            w.timer = 0;
            e.body.vx = 0;
            w.spine_w = SMALL[0];
            w.spine_h = SMALL[1];
            if e.body.x != px {
                e.facing = if e.body.x > px { -1 } else { 1 };
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    /// Every size the raise and fold tweens can reach stays inside MOST, and the
    /// corpus case (fold from 67 x 65) reaches it exactly as Godot did.
    #[test]
    fn spine_sizes_reachable_in_play_are_valid() {
        let mut a = Actor::new(ActorKind::Spine, 0, 0, crate::Position::default());
        let (mut most_w, mut most_h, mut from) = (0, 0, Vec::new());
        a.mode = SPIKE;
        for tick in 0..=SPIKE_TICKS {
            a.timer = tick;
            let [w, h] = a.spine_size();
            from.push([w / S, h / S]);
        }
        a.mode = SHRINK;
        for [fw, fh] in from {
            (a.from_w, a.from_h) = (fw, fh);
            for tick in 0..=TWEEN {
                a.timer = tick;
                let [w, h] = a.spine_size();
                most_w = most_w.max(w / S);
                most_h = most_h.max(h / S);
            }
        }
        assert_eq!([most_w, most_h], MOST);
        (a.from_w, a.from_h, a.timer) = (67, 65, 7);
        let [w, h] = a.spine_size();
        assert_eq!([w / S, h / S], [70, 68]);
        (a.spine_w, a.spine_h) = (70, 68);
        assert!(a.spine_valid());
    }
}
