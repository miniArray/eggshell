//! gust_flyer.gd (e33): a flyer that speeds up along a free-form placement angle and
//! flies straight on through terrain. It is not in the enemy family (no family index):
//! placements use free-form angles. The body lives in `Actor` (ActorKind::Gust).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::Hold,
    entity::Kind,
    math::{turn_cosine, turn_sine},
    state::Run,
    Error, Placement, Position, PropertyValue, SCALE as S,
};
const TURN: i64 = 360_000;
const TOP_SPEED: i64 = 312;
const RAMP_TICKS: i64 = 60;
const UPRIGHT: [i64; 4] = [-12, -28, 12, 24];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

/// gust_flyer.gd bounds: the axis-aligned box around the body turned to its sprite angle.
pub(crate) fn bounds(heading: i64) -> [i64; 4] {
    let sprite = heading + 90_000;
    let cosine = turn_cosine(sprite, S);
    let sine = turn_sine(sprite, S);
    let (mut left, mut top, mut right, mut bottom) =
        (1_i64 << 40, 1_i64 << 40, -(1_i64 << 40), -(1_i64 << 40));
    for [cx, cy] in [
        [UPRIGHT[0], UPRIGHT[1]],
        [UPRIGHT[2], UPRIGHT[1]],
        [UPRIGHT[2], UPRIGHT[3]],
        [UPRIGHT[0], UPRIGHT[3]],
    ] {
        let x = cx * cosine - cy * sine;
        let y = cx * sine + cy * cosine;
        left = left.min(x);
        right = right.max(x);
        top = top.min(y);
        bottom = bottom.max(y);
    }
    [left, top, right, bottom]
}

impl Actor {
    /// gust_flyer.gd prepare + create: R is a free-form angle, M > 0 turns toward the
    /// player on activation; the mirror itself is cleared.
    pub fn gust(p: &Placement) -> Result<Self, Error> {
        let invalid = || Error::InvalidInput {
            context: "Invalid flyer angle or mirror".into(),
        };
        let angle = match p.properties.iter().find(|(k, _)| k == "R").map(|(_, v)| v) {
            None => 0.0,
            Some(PropertyValue::Number(v)) => *v,
            Some(PropertyValue::String(s)) => s.trim().parse::<f64>().map_err(|_| invalid())?,
            Some(_) => return Err(invalid()),
        };
        if !angle.is_finite() || angle.abs() > (i64::MAX / S - 1) as f64 {
            return Err(invalid());
        }
        if !(0..=2).contains(&p.mirror) || !(0..=4).contains(&p.variant) {
            return Err(Error::Unsupported {
                requirements: vec![format!("e33 form F={} M={}", p.variant, p.mirror)],
            });
        }
        let mut a = Actor::new(ActorKind::Gust, p.variant, 0, p.position);
        a.heading = (((angle - 90.0) * 1000.0).round() as i64).rem_euclid(TURN);
        a.toward = i64::from(p.mirror > 0);
        Ok(a)
    }
    pub fn gust_valid(&self) -> bool {
        (0..TURN).contains(&self.heading)
            && [0, 1].contains(&self.toward)
            && (0..=RAMP_TICKS).contains(&self.ramp)
    }
    /// gust_flyer.gd activate: turn round when the player is nearer the back.
    pub(crate) fn gust_activate(&mut self, body: Body, player: Position) {
        if self.toward == 0 {
            return;
        }
        let dx = player.x - body.x;
        let dy = player.y - body.y;
        let along = dx / S * turn_cosine(self.heading, S) + dy / S * turn_sine(self.heading, S);
        if along < 0 {
            self.heading = (self.heading + 180_000).rem_euclid(TURN);
        }
    }
    /// gust_flyer.gd view_state: (rotation in degrees, mirrored).
    pub fn gust_view(&self) -> (f64, bool) {
        let sprite = (self.heading + 90_000).rem_euclid(TURN);
        (sprite as f64 / 1000.0, !(1000..=180_000).contains(&sprite))
    }
}

impl Run {
    /// gust_flyer.gd step.
    pub(crate) fn gust_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let token = self.entities[index].origin.token();
        let Run {
            entities,
            player,
            rng,
            ..
        } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if w.started == 0 {
            // enemy_body.gd process: the first step's initialisation (mirror is 0).
            w.started = 1;
            w.impact_cursor = player.impact;
        }
        let step = ActorStep { map, player, rng };
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
                requirements: vec!["frozen e33 flyer (ice shots are not ported)".into()],
            });
        }
        let body = &mut e.body;
        if action == Hold::Released {
            w.on_spit_release(body, &mut e.facing, 0, 0);
        }
        w.ramp = (w.ramp + 1).min(RAMP_TICKS);
        let speed = TOP_SPEED * 60 * w.ramp / RAMP_TICKS;
        body.vx = speed * turn_cosine(w.heading, S) / S;
        body.vy = speed * turn_sine(w.heading, S) / S;
        body.x += body.vx;
        body.y += body.vy;
        e.facing = if body.vx > 0 { 1 } else { -1 };
        Ok(())
    }
    /// gust_flyer.gd contact.
    pub(crate) fn gust_contact(&mut self, index: usize, input: u8) {
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
            && strict(world_box(e.body, bounds(w.heading)), world_box(p, pb));
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
