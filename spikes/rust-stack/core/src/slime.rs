//! slime_drop.gd (e15): a slime blob that creeps along, turning at walls. Landing on it
//! squashes it under the player before it bursts. The dripping form (F1) hangs hidden
//! on a ceiling, drops when the player comes near, then stares before it creeps on.
//! The body lives in `Actor` (ActorKind::Slime; `phase` is the slime phase).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::{After, HitKind, Hold},
    entity::Kind,
    player::Player,
    state::Run,
    Error, Placement, SCALE as S,
};
pub(crate) const WALK: i64 = 0;
pub(crate) const SQUASH: i64 = 1;
pub(crate) const HANG: i64 = 2;
pub(crate) const DRIP: i64 = 3;
pub(crate) const DROP: i64 = 4;
pub(crate) const LAND: i64 = 5;
pub(crate) const STARE: i64 = 6;
const SQUASH_TICKS: i64 = 15;
const DRIP_TICKS: i64 = 12;
const LAND_TICKS: i64 = 18;
const STARE_TICKS: i64 = 60;
const WALK_BOX: [i64; 4] = [-10 * S, -8 * S, 10 * S, 16 * S];
const HANG_BOX: [i64; 4] = [-10 * S, 0, 10 * S, 16 * S];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

/// slime_drop.gd bounds
pub(crate) fn bounds(phase: i64) -> [i64; 4] {
    if [HANG, DRIP].contains(&phase) {
        HANG_BOX
    } else {
        WALK_BOX
    }
}

/// slime_drop.gd pin: the squashing slime holds the player on top of it.
fn pin(body: Body, pin_dx: i64, player: &mut Player) {
    player.body.x = body.x + pin_dx;
    player.body.y = body.y;
    player.body.vx = 0;
    player.body.vy = 0;
    player.on_floor = 1;
}

impl Actor {
    /// slime_drop.gd prepare + create (the F1 placement is already 16 px higher: see
    /// world.rs).
    pub fn slime(p: &Placement) -> Result<Self, Error> {
        if !(0..=1).contains(&p.variant) || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e15 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::Slime, p.variant, p.mirror, p.position);
        if p.variant == 1 {
            a.phase = HANG;
            a.hidden = 1;
        }
        Ok(a)
    }
    pub fn slime_valid(&self) -> bool {
        (0..=1).contains(&self.variant)
            && (WALK..=STARE).contains(&self.phase)
            && (0..=60).contains(&self.timer)
            && self.pin_dx.abs() <= 64 * S
    }
    /// slime_drop.gd tongue: only an exposed blob can be caught.
    pub(crate) fn slime_edible(&self) -> bool {
        [WALK, LAND, STARE, DROP].contains(&self.phase)
    }
    /// slime_drop.gd hit / projectile_contact: hanging and squashing blobs are untouched.
    pub(crate) fn slime_struck(&self) -> bool {
        ![HANG, SQUASH].contains(&self.phase)
    }
    /// slime_drop.gd view_state animation.
    pub fn slime_animation(&self) -> &'static str {
        ["Walk", "Squash", "Drip", "Drip", "Fall", "Land", "Stare"][self.phase.clamp(0, 6) as usize]
    }
}

impl Run {
    /// slime_drop.gd step.
    pub(crate) fn slime_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let token = self.entities[index].origin.token();
        let Run {
            entities,
            player,
            rng,
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
        let mut step = ActorStep {
            map,
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
                requirements: vec!["frozen e15 slime (its reactions are not ported)".into()],
            });
        }
        let b = bounds(w.phase);
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
        if map.lava_overlaps(world_box(e.body, b)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let player = step.player;
        let body = &mut e.body;
        match w.phase {
            HANG => {
                if w.timer == 0 {
                    // slime_drop.gd attach: a solid within 2 px above, or it creeps.
                    w.timer = 1;
                    if !body.overlaps(map, WALK_BOX, 0, -2 * S) {
                        w.phase = WALK;
                        w.hidden = 0;
                        w.timer = 0;
                    }
                }
                if w.phase == HANG && (player.body.x - body.x).abs() < 96 * S {
                    w.phase = DRIP;
                    w.hidden = 0;
                    w.timer = DRIP_TICKS;
                    e.facing = if player.body.x > body.x { 1 } else { -1 };
                }
                return Ok(());
            }
            DRIP => {
                w.timer -= 1;
                if w.timer <= 0 {
                    w.phase = DROP;
                    body.y += 8 * S;
                    w.fall_from = body.y;
                    body.vy = 0;
                }
                return Ok(());
            }
            SQUASH => {
                body.vx = 0;
                pin(*body, w.pin_dx, player);
                w.timer -= 1;
                if w.timer <= 0 {
                    w.remove(&mut e.status, &mut e.can_respawn);
                }
                return Ok(());
            }
            LAND | STARE => {
                body.vx = 0;
                w.timer -= 1;
                if w.timer <= 0 {
                    if w.phase == LAND {
                        w.phase = STARE;
                        w.timer = STARE_TICKS;
                        e.facing = if player.body.x > body.x { 1 } else { -1 };
                    } else {
                        w.phase = WALK;
                    }
                }
            }
            WALK => {
                let wet = i64::from(map.water_overlaps(world_box(*body, b)));
                body.vx = e.facing * 48 * 60 / (wet + 1);
            }
            _ => body.vx = 0,
        }
        let distance = body.vx;
        let mut started = false;
        if distance != 0 {
            let (actual, on_floor) = w.movement_box(body, b, map, distance);
            started = on_floor;
            if actual != distance {
                e.facing = -e.facing;
            }
        }
        if body.gravity(map, b, started) && w.phase == DROP {
            let far = body.y > w.fall_from + 112 * S;
            w.phase = if far { LAND } else { WALK };
            w.timer = if far { LAND_TICKS } else { 0 };
        }
        Ok(())
    }
    /// slime_drop.gd contact.
    pub(crate) fn slime_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        if [HANG, SQUASH].contains(&w.phase) {
            w.contact = 0;
            return;
        }
        // enemy_body.gd player_overlap
        let touching = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && strict(world_box(e.body, bounds(w.phase)), world_box(p, pb));
        if touching && w.contact == 0 && e.body.y > p.y - 8 * S {
            w.phase = SQUASH;
            w.timer = SQUASH_TICKS;
            e.body.vx = 0;
            w.pin_dx = (p.x - e.body.x).clamp(-64 * S, 64 * S);
            pin(e.body, w.pin_dx, &mut self.player);
        } else if touching && e.body.y < p.y - 8 * S {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        if let Kind::Walker(w) = &mut self.entities[index].kind {
            w.contact = i64::from(touching);
        }
    }
}
