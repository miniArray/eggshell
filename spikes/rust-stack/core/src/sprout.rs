//! hop_sprout.gd (e12): a small biting sprout that hops along the ground, turning at
//! walls. The body lives in `Actor` (ActorKind::Sprout).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::{After, HitKind, Hold},
    entity::Kind,
    state::Run,
    Error, Placement, SCALE as S,
};
pub(crate) const HOP: i64 = 0;
pub(crate) const WAKE: i64 = 1;
const WAKE_TICKS: i64 = 15;
const HOP_DELAY: i64 = 3;
pub(crate) const BOX: [i64; 4] = [-12 * S, -14 * S, 12 * S, 16 * S];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Actor {
    /// hop_sprout.gd prepare + create.
    pub fn sprout(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e12 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        Ok(Actor::new(ActorKind::Sprout, 0, p.mirror, p.position))
    }
    pub fn sprout_valid(&self) -> bool {
        self.variant == 0 && [HOP, WAKE].contains(&self.mode) && (0..=WAKE_TICKS).contains(&self.timer)
    }
    /// hop_sprout.gd view_state: (animation, frame).
    pub fn sprout_view(&self, body: Body) -> (&'static str, Option<i64>) {
        if self.mode == WAKE {
            ("Wake", None)
        } else {
            (
                "Hop",
                Some(match body.vy {
                    0 => 0,
                    v if v < 0 => 1,
                    _ => 2,
                }),
            )
        }
    }
}

impl Run {
    /// hop_sprout.gd step.
    pub(crate) fn sprout_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
                requirements: vec!["frozen e12 sprout (ice shots are not ported)".into()],
            });
        }
        if let Some(after) = w.spit_step(
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &mut step,
        ) {
            if let After::HitOthers(b) = after {
                self.hit_others(index, b, HitKind::Spit, true)?;
            }
            return Ok(());
        }
        // enemy_body.gd hazards
        if map.lava_overlaps(world_box(e.body, BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let body = &mut e.body;
        if w.mode == WAKE {
            w.timer -= 1;
            if w.timer <= 0 {
                w.mode = HOP;
                w.timer = 0;
                e.facing = if px > body.x { 1 } else { -1 };
            }
            body.gravity(map, BOX, false);
            return Ok(());
        }
        let grounded = body.floor(map, BOX) != 0 && body.vy >= 0;
        if grounded {
            body.vx = 0;
            if w.timer == 0 {
                w.timer = HOP_DELAY;
            } else {
                w.timer -= 1;
                if w.timer == 0 {
                    body.vy = -256 * 60;
                    body.vx = e.facing * 64 * 60;
                }
            }
        }
        let distance = body.vx;
        let mut started = false;
        if distance != 0 {
            let (actual, on_floor) = w.movement_box(body, BOX, map, distance);
            started = on_floor;
            if actual != distance {
                e.facing = -e.facing;
                body.vx = -body.vx;
            }
        }
        if body.gravity(map, BOX, started) {
            body.vx = 0;
        }
        Ok(())
    }
    /// hop_sprout.gd contact.
    pub(crate) fn sprout_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let pounding = [2, 3].contains(&self.player.action);
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        // enemy_body.gd player_overlap
        let touching = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && strict(world_box(e.body, BOX), world_box(p, pb));
        if touching && w.contact == 0 && e.body.y > p.y - 8 * S {
            let vy = e.body.vy;
            w.remove(&mut e.status, &mut e.can_respawn);
            if !pounding {
                self.player.stomp(vy, input, &mut self.sound);
            }
        } else if touching && e.body.y < p.y - 8 * S {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        if let Kind::Walker(w) = &mut self.entities[index].kind {
            w.contact = i64::from(touching);
        }
    }
}
