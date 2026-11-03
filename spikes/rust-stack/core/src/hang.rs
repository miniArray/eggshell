//! hang_flyer.gd (e14): hangs from a ceiling until the player passes below, then dives,
//! swoops through a loop and flies on; F1 flies from the start. Released from the mouth
//! it flees and never hurts again. The body lives in `Actor` (ActorKind::Hang).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::Hold,
    entity::Kind,
    state::Run,
    Error, Placement, SCALE as S,
};
pub(crate) const HANG: i64 = 0;
pub(crate) const DIVE: i64 = 1;
pub(crate) const SWOOP: i64 = 2;
pub(crate) const FORWARD: i64 = 3;
pub(crate) const FLEE: i64 = 4;
const FLAP_WIDTHS: [i64; 6] = [44, 56, 56, 48, 56, 56];
const SWOOP_TICKS: i64 = 150;

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

/// hang_flyer.gd bounds
pub(crate) fn bounds(mode: i64) -> [i64; 4] {
    if mode == HANG {
        [-10 * S, -16 * S, 10 * S, 14 * S]
    } else {
        [-12 * S, -10 * S, 12 * S, 14 * S]
    }
}

/// hang_flyer.gd _out_quad
fn out_quad(distance: i64, tick: i64, ticks: i64) -> i64 {
    let left = ticks - tick;
    distance * (ticks * ticks - left * left) / (ticks * ticks)
}

/// hang_flyer.gd _ping_pong: out and back over 2 * ticks; the return replays the ease.
fn ping_pong(distance: i64, tick: i64, ticks: i64, in_out: bool) -> i64 {
    let phase = tick.min(2 * ticks);
    let along = if phase <= ticks {
        phase
    } else {
        2 * ticks - phase
    };
    if !in_out {
        return out_quad(distance, along, ticks);
    }
    let span = ticks * ticks;
    let part = if 2 * along < ticks {
        2 * along * along
    } else {
        span - 2 * (ticks - along) * (ticks - along)
    };
    distance * part / span
}

impl Actor {
    /// hang_flyer.gd prepare + create.
    pub fn hang(p: &Placement) -> Result<Self, Error> {
        if !(0..=1).contains(&p.variant) || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e14 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::Hang, p.variant, p.mirror, p.position);
        a.mode = if p.variant == 1 { FORWARD } else { HANG };
        Ok(a)
    }
    pub fn hang_valid(&self) -> bool {
        (0..=1).contains(&self.variant)
            && (HANG..=FLEE).contains(&self.mode)
            && (0..=SWOOP_TICKS).contains(&self.timer)
            && (0..20).contains(&self.flap)
    }
    /// hang_flyer.gd view_state animation.
    pub fn hang_animation(&self) -> &'static str {
        if self.mode == HANG {
            "Idle"
        } else {
            "Fly"
        }
    }
    /// hang_flyer.gd _swoop: drop to the player's height (0.3 s), slide 64 px on (0.5 s),
    /// then loop 80 px up and back over 2 s while swinging 40 px forward and back, then
    /// 40 px behind and back.
    fn hang_swoop(&mut self, body: &mut Body, facing: i64) {
        self.timer += 1;
        let t = self.timer;
        let mut x = self.from_x + facing * 64 * S * t.min(30) / 30;
        let mut y = self.from_y + out_quad(self.target_y - self.from_y, t.min(18), 18);
        if t > 30 {
            let lap = t - 30;
            y = self.target_y - ping_pong(80 * S, lap, 60, true);
            let swing = if lap <= 60 { lap } else { lap - 60 };
            let side = if lap <= 60 { facing } else { -facing };
            x += side * ping_pong(40 * S, swing, 30, false);
        }
        body.x = x;
        body.y = y;
        if t >= SWOOP_TICKS {
            self.mode = FORWARD;
            self.timer = 0;
        }
    }
}

impl Run {
    /// hang_flyer.gd step.
    pub(crate) fn hang_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
        let fresh = w.started == 0;
        if fresh {
            // enemy_body.gd process: the first step's initialisation.
            w.started = 1;
            w.impact_cursor = player.impact;
            if w.mirror == 2 {
                e.facing = if player.body.x > e.body.x { 1 } else { -1 };
            }
        }
        let (px, py, player_facing) = (player.body.x, player.body.y, player.facing);
        let captured = player.captured_by != 0;
        let step = ActorStep {
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
                requirements: vec!["frozen e14 flyer (ice shots are not ported)".into()],
            });
        }
        let body = &mut e.body;
        if fresh && w.mode == HANG {
            // Without a ceiling within 4 px it starts flying straight away (enemy_motion.gd
            // overlaps: terrain and map borders only).
            let b = bounds(w.mode);
            let q = [
                body.x + b[0],
                body.y + b[1] - 4 * S,
                body.x + b[2],
                body.y + b[3] - 4 * S,
            ];
            if !(map.border_overlaps(q) || map.terrain_overlaps(q)) {
                w.mode = FORWARD;
            }
        }
        if action == Hold::Released {
            w.on_spit_release(body, &mut e.facing, player_facing, 0);
        }
        if w.mode != HANG {
            w.flap = (w.flap + 1) % 20;
        }
        match w.mode {
            HANG => {
                if (body.x - px).abs() < 248 * S && py > body.y + 12 * S && !captured {
                    w.mode = DIVE;
                    if body.x != px {
                        e.facing = if px > body.x { 1 } else { -1 };
                    }
                }
            }
            DIVE => {
                body.y += 128 * 60;
                body.x += e.facing * FLAP_WIDTHS[(w.flap * 18 / 60 % 6) as usize] * 60;
                if body.y > py - 64 * S {
                    w.mode = SWOOP;
                    w.timer = 0;
                    w.from_x = body.x;
                    w.from_y = body.y;
                    w.target_y = py - 32 * S;
                }
            }
            SWOOP => w.hang_swoop(body, e.facing),
            FORWARD => body.x += e.facing * 128 * 60,
            _ => {
                body.y -= 96 * 60;
                body.x += e.facing * 224 * 60;
            }
        }
        // enemy_body.gd hazards
        if map.lava_overlaps(world_box(*body, bounds(w.mode))) {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        Ok(())
    }
    /// hang_flyer.gd contact.
    pub(crate) fn hang_contact(&mut self, index: usize, input: u8) {
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
            && strict(world_box(e.body, bounds(w.mode)), world_box(p, pb));
        if touching && e.body.y > p.y - 8 * S {
            if w.contact == 0 {
                let vy = e.body.vy;
                w.remove(&mut e.status, &mut e.can_respawn);
                if !pounding {
                    self.player.enemy_bounce(
                        vy,
                        input,
                        self.message.modal_token != 0,
                        &mut self.sound,
                    );
                }
            }
        } else if touching && w.mode != FLEE {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        if let Kind::Walker(w) = &mut self.entities[index].kind {
            w.contact = i64::from(touching);
        }
    }
}
