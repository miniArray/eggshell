//! wing_drifter.gd (e30): a bobbing flyer. A stomp or strike knocks it aside; it then
//! turns to the player and charges in a straight line. The body lives in `Actor`
//! (ActorKind::Wing).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::{After, HitKind, Hold},
    entity::Kind,
    math::{angle_to, sine, turn_cosine, turn_sine},
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
pub(crate) const FLY: i64 = 0;
pub(crate) const STOMPED: i64 = 1;
pub(crate) const ANGRY: i64 = 2;
pub(crate) const CHARGE: i64 = 3;
const BOB_PERIOD: i64 = 180;
const BOB: i64 = 64 * S;
const DRIFT: i64 = 64 * 60;
const CHARGE_SPEED: i64 = 256 * 60;
const KNOCK_TICKS: i64 = 6;
const STOMP_TICKS: i64 = 13;
const AIM_TICKS: i64 = 60;
// Body hulls facing left, in pixels around the origin.
const FLY_HULL: [[i64; 2]; 6] = [[-24, -14], [2, -14], [16, 12], [16, 30], [-2, 30], [-24, 2]];
const ANGRY_HULL: [[i64; 2]; 6] = [[-28, -8], [-2, -8], [16, 12], [16, 30], [-2, 30], [-28, 8]];

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}

/// wing_drifter.gd bounds
pub(crate) fn bounds(mode: i64, facing: i64) -> [i64; 4] {
    let left = if [FLY, STOMPED].contains(&mode) {
        -24
    } else {
        -28
    };
    if facing < 0 {
        [left * S, -14 * S, 16 * S, 30 * S]
    } else {
        [-16 * S, -14 * S, -left * S, 30 * S]
    }
}

/// wing_drifter.gd hull
fn hull(mode: i64, body: Body, facing: i64) -> [[i64; 2]; 6] {
    let points = if [FLY, STOMPED].contains(&mode) {
        FLY_HULL
    } else {
        ANGRY_HULL
    };
    points.map(|[px, py]| {
        let x = px * S;
        [body.x + if facing > 0 { -x } else { x }, body.y + py * S]
    })
}

/// enemy_body.gd polygon_overlap: separating axes of the hull and the box, open edges.
pub(crate) fn polygon_overlap(hull: &[[i64; 2]], b: [i64; 4]) -> bool {
    let mut axes = vec![[1, 0], [0, 1]];
    for index in 0..hull.len() {
        let a = hull[index];
        let c = hull[(index + 1) % hull.len()];
        axes.push([a[1] - c[1], c[0] - a[0]]);
    }
    for axis in axes {
        let mut minimum = hull[0][0] * axis[0] + hull[0][1] * axis[1];
        let mut maximum = minimum;
        for point in hull {
            let dot = point[0] * axis[0] + point[1] * axis[1];
            minimum = minimum.min(dot);
            maximum = maximum.max(dot);
        }
        let rectangle_min = b[if axis[0] >= 0 { 0 } else { 2 }] * axis[0]
            + b[if axis[1] >= 0 { 1 } else { 3 }] * axis[1];
        let rectangle_max = b[if axis[0] >= 0 { 2 } else { 0 }] * axis[0]
            + b[if axis[1] >= 0 { 3 } else { 1 }] * axis[1];
        if maximum <= rectangle_min || rectangle_max <= minimum {
            return false;
        }
    }
    true
}

impl Actor {
    /// wing_drifter.gd prepare + create.
    pub fn wing(p: &Placement) -> Result<Self, Error> {
        let drift = match p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v) {
            None => "",
            Some(PropertyValue::String(s)) => s.as_str(),
            Some(_) => {
                return Err(Error::InvalidInput {
                    context: "Invalid flyer option: E1".into(),
                })
            }
        };
        if !(0..=1).contains(&p.variant) || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e30 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        let mut a = Actor::new(ActorKind::Wing, p.variant, p.mirror, p.position);
        a.bob_sign = if p.variant == 1 { 1 } else { -1 };
        a.drifts = i64::from(drift != "1");
        Ok(a)
    }
    pub fn wing_valid(&self) -> bool {
        (0..=1).contains(&self.variant)
            && (FLY..=CHARGE).contains(&self.mode)
            && (0..=AIM_TICKS).contains(&self.timer)
            && (0..BOB_PERIOD).contains(&self.bob)
            && [-1, 1].contains(&self.bob_sign)
            && [0, 1].contains(&self.drifts)
            && self.knock_dx.abs() <= 48 * S
            && self.knock_dy.abs() <= 48 * S
    }
    /// wing_drifter.gd knock: (dx, dy) is any direction; the knock covers `distance`
    /// pixels along it. Only a calm flyer is knocked.
    pub(crate) fn wing_knock(&mut self, body: Body, distance: i64, dx: i64, dy: i64) {
        if self.mode != FLY {
            return;
        }
        let angle = angle_to(dx, dy);
        self.mode = STOMPED;
        self.timer = 0;
        self.knock_x = body.x;
        self.knock_y = body.y;
        self.knock_dx = turn_cosine(angle, distance * S);
        self.knock_dy = turn_sine(angle, distance * S);
        // Axis strikes stay exact; the integer angle search is only approximate.
        if dx == 0 {
            self.knock_dx = 0;
            self.knock_dy = dy.signum() * distance * S;
        } else if dy == 0 {
            self.knock_dx = dx.signum() * distance * S;
            self.knock_dy = 0;
        }
    }
    /// wing_drifter.gd projectile_contact: every strike is absorbed (1); a calm flyer
    /// is knocked along the strike.
    pub(crate) fn wing_struck(&mut self, body: Body, projectile: Body) -> i64 {
        let (mut dx, dy) = (projectile.vx, projectile.vy);
        if dx == 0 && dy == 0 {
            dx = body.x - projectile.x;
        }
        self.wing_knock(body, 48, dx, dy);
        1
    }
    /// wing_drifter.gd view_state animation.
    pub fn wing_animation(&self) -> &'static str {
        ["Fly", "Stomped", "Angry", "Angry"][self.mode.clamp(FLY, CHARGE) as usize]
    }
}

impl Run {
    /// wing_drifter.gd step.
    pub(crate) fn wing_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
            // enemy_body.gd process: the first step's initialisation.
            w.started = 1;
            w.impact_cursor = player.impact;
            if w.mirror == 2 {
                e.facing = if player.body.x > e.body.x { 1 } else { -1 };
            }
        }
        let mut step = ActorStep { map, player, rng };
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
                requirements: vec!["frozen e30 flyer (ice shots are not ported)".into()],
            });
        }
        if action == Hold::Released {
            w.on_spit_release(&mut e.body, &mut e.facing, 0, 0);
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
        let (px, py) = (step.player.body.x, step.player.body.y);
        let body = &mut e.body;
        match w.mode {
            FLY => {
                w.bob = (w.bob + 1) % BOB_PERIOD;
                body.y = w.home_y + sine(w.bob, BOB_PERIOD, w.bob_sign * BOB)?;
                if w.drifts != 0 {
                    body.x += e.facing * DRIFT;
                }
            }
            STOMPED => {
                w.timer += 1;
                if w.timer <= KNOCK_TICKS {
                    let span = KNOCK_TICKS * KNOCK_TICKS;
                    let left = KNOCK_TICKS - w.timer;
                    let part = span - left * left;
                    body.x = w.knock_x + w.knock_dx * part / span;
                    body.y = w.knock_y + w.knock_dy * part / span;
                }
                if w.timer >= STOMP_TICKS {
                    w.mode = ANGRY;
                    w.timer = 0;
                }
            }
            ANGRY => {
                w.timer += 1;
                if body.x != px {
                    e.facing = if body.x > px { -1 } else { 1 };
                }
                if w.timer >= AIM_TICKS {
                    let angle = angle_to(px - body.x, py - 32 * S - body.y);
                    body.vx = turn_cosine(angle, CHARGE_SPEED);
                    body.vy = turn_sine(angle, CHARGE_SPEED);
                    w.mode = CHARGE;
                    w.timer = 0;
                }
            }
            _ => {
                body.x += body.vx;
                body.y += body.vy;
            }
        }
        // enemy_body.gd hazards
        if map.lava_overlaps(world_box(e.body, bounds(w.mode, e.facing))) {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        Ok(())
    }
    /// wing_drifter.gd contact.
    pub(crate) fn wing_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let pounding = [2, 3].contains(&self.player.action);
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        let touching = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && polygon_overlap(&hull(w.mode, e.body, e.facing), world_box(p, pb));
        if touching && e.body.y > p.y - 16 * S {
            if w.contact == 0 {
                if pounding {
                    w.remove(&mut e.status, &mut e.can_respawn);
                } else {
                    let vy = e.body.vy;
                    w.wing_knock(e.body, 12, 0, 1);
                    self.player.enemy_bounce(
                        vy,
                        input,
                        self.message.modal_token != 0,
                        &mut self.sound,
                    );
                }
            }
        } else if touching {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        if let Kind::Walker(w) = &mut self.entities[index].kind {
            w.contact = i64::from(touching);
        }
    }
}
