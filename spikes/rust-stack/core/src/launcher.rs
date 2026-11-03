//! shot_launcher.gd (e37): a solid launcher that fires one shot at a time, and its
//! launcher_shot.gd (enemy_shot) shot: straight, bouncing or homing. The launcher is its
//! own `Kind`; the shot is an enemy body in `Actor` (ActorKind::Shot).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::Hold,
    entity::{Entity, Kind},
    math::{angle_delta, angle_to, root, turn_cosine, turn_sine},
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
const CHARGE_TICKS: i64 = 30;
const DELAY_TICKS: i64 = 300;
const SHOT_SPEED: i64 = 296;
pub(crate) const STRAIGHT: i64 = 0;
pub(crate) const BOUNCE: i64 = 1;
pub(crate) const HOMING: i64 = 2;
pub(crate) const SHOT_BOX: [i64; 4] = [-17 * S, -22 * S, 17 * S, 22 * S];
const PAUSE_TICKS: i64 = 15;
const GRAVITY: i64 = 1024;
const FALL_CAP: i64 = 704 * 60;
const PROBE: i64 = S / 2;

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Launcher {
    pub aim: i64,
    pub form: i64,
    pub ready: i64,
    pub delay: i64,
    pub charge: i64,
    pub side: i64,
    pub heading: i64,
    pub shot_token: i64,
    pub frozen: i64,
}

impl Launcher {
    /// shot_launcher.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let invalid = || Error::InvalidInput {
            context: "Invalid launcher mode or form".into(),
        };
        let mode = match p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v) {
            None => "Static",
            Some(PropertyValue::String(s)) => s.as_str(),
            Some(_) => return Err(invalid()),
        };
        if !["Static", "Aim"].contains(&mode) || !(0..=2).contains(&p.variant) || p.mirror != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!("e37 launcher E1={mode} F={}", p.variant)],
            });
        }
        Ok(Self {
            aim: i64::from(mode == "Aim"),
            form: p.variant,
            ready: 1,
            delay: 0,
            charge: 0,
            side: 1,
            heading: 180_000,
            shot_token: 0,
            frozen: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-16 * S, -16 * S, 16 * S, 16 * S]
    }
    /// shot_launcher.gd solid_box
    pub fn solid(&self, e: &Entity) -> Option<[i64; 4]> {
        (e.status == 1 && self.frozen == 0).then(|| world_box(e.body, self.bounds()))
    }
    pub fn valid(&self) -> bool {
        [0, 1].contains(&self.aim)
            && (0..=2).contains(&self.form)
            && [0, 1].contains(&self.ready)
            && (0..=DELAY_TICKS).contains(&self.delay)
            && (0..=CHARGE_TICKS).contains(&self.charge)
            && [1, 2].contains(&self.side)
            && (0..360_000).contains(&self.heading)
            && self.shot_token >= 0
            && [0, 1].contains(&self.frozen)
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "aim" => self.aim,
            "form" => self.form,
            "ready" => self.ready,
            "delay" => self.delay,
            "charge" => self.charge,
            "side" => self.side,
            "heading" => self.heading,
            "shot_token" => self.shot_token,
            "frozen" => self.frozen,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "aim" => self.aim = value,
            "form" => self.form = value,
            "ready" => self.ready = value,
            "delay" => self.delay = value,
            "charge" => self.charge = value,
            "side" => self.side = value,
            "heading" => self.heading = value,
            "shot_token" => self.shot_token = value,
            "frozen" => self.frozen = value,
            _ => return false,
        }
        true
    }
}

impl Actor {
    pub fn shot_valid(&self) -> bool {
        (STRAIGHT..=HOMING).contains(&self.form)
            && (0..360_000).contains(&self.heading)
            && (0..=PAUSE_TICKS).contains(&self.pause)
            && [0, 1].contains(&self.fresh)
            && [0, 1].contains(&self.falling)
    }
    /// launcher_shot.gd view_state: (animation, rotation in degrees).
    pub fn shot_view(&self) -> (String, f64) {
        let animation = if self.pause != 0 {
            "Bounce".into()
        } else {
            self.form.to_string()
        };
        (animation, self.heading as f64 / 1000.0)
    }
    /// launcher_shot.gd home: turn toward a point 32 px above the player.
    fn shot_home(&mut self, body: &mut Body, px: i64, py: i64) {
        let dx = px - body.x;
        let dy = py - 32 * S - body.y;
        let distance = root(dx / S * (dx / S) + dy / S * (dy / S));
        let limit = 100 + distance * 1000 / 140;
        let turn = angle_delta(self.heading, angle_to(dx, dy)).clamp(-limit, limit);
        self.heading = (self.heading + turn).rem_euclid(360_000);
        let throttle = turn.abs() * 1414 / 1000;
        let mut speed = 296 * 60;
        if throttle <= 45_000 {
            speed = (296_000 - 40 * throttle) * 60 / 1000;
        }
        body.vx = speed * turn_cosine(self.heading, S) / S;
        body.vy = speed * turn_sine(self.heading, S) / S;
    }
    /// launcher_shot.gd touching
    fn shot_touching(body: Body, map: &Probe) -> bool {
        [[-PROBE, 0], [PROBE, 0], [0, -PROBE], [0, PROBE]]
            .iter()
            .any(|[dx, dy]| body.overlaps(map, SHOT_BOX, *dx, *dy))
    }
    /// launcher_shot.gd reflect: reflect the component that points into the solid.
    fn shot_reflect(&mut self, body: &mut Body, facing: &mut i64, map: &Probe) {
        let dx = body.vx.signum();
        let dy = body.vy.signum();
        if dx != 0 && body.overlaps(map, SHOT_BOX, dx * PROBE, 0) {
            body.vx = -body.vx;
        }
        if dy != 0 && body.overlaps(map, SHOT_BOX, 0, dy * PROBE) {
            body.vy = -body.vy;
        }
        if body.vx != 0 || body.vy != 0 {
            self.heading = angle_to(body.vx, body.vy);
        }
        *facing = if body.vx >= 0 { 1 } else { -1 };
    }
}

impl Run {
    fn launcher(&mut self, index: usize) -> &mut Launcher {
        match &mut self.entities[index].kind {
            Kind::Launcher(l) => l,
            _ => unreachable!("launcher index"),
        }
    }
    /// shot_launcher.gd step.
    pub(crate) fn launcher_step(&mut self, index: usize) -> Result<(), Error> {
        let (px, py) = (self.player.body.x, self.player.body.y);
        let body = self.entities[index].body;
        let l = self.launcher(index);
        if l.frozen != 0 {
            return Ok(());
        }
        if l.charge != 0 {
            l.charge -= 1;
            if l.charge == 0 {
                self.launcher_fire(index)?;
            }
            return Ok(());
        }
        l.side = if px < body.x { 1 } else { 2 };
        l.heading = angle_to(px - body.x, py - 32 * S - body.y);
        if l.delay != 0 {
            l.delay -= 1;
        }
        if l.ready == 0 && l.shot_token != 0 {
            let token = l.shot_token;
            let gone = self
                .entities
                .iter()
                .find(|e| e.origin.token() == token)
                .is_none_or(|e| e.status == 3);
            if gone {
                let l = self.launcher(index);
                l.ready = 1;
                l.shot_token = 0;
            }
        }
        let l = self.launcher(index);
        if l.ready != 0 && l.delay == 0 {
            l.ready = 0;
            l.charge = CHARGE_TICKS;
        }
        Ok(())
    }
    /// shot_launcher.gd fire: registry.gd spawn_dynamic of an enemy_shot.
    fn launcher_fire(&mut self, index: usize) -> Result<(), Error> {
        let body = self.entities[index].body;
        let l = self.launcher(index);
        let heading = if l.aim != 0 {
            l.heading
        } else if l.side == 1 {
            180_000
        } else {
            0
        };
        let facing = if l.side == 1 { -1 } else { 1 };
        let form = l.form;
        let speed = SHOT_SPEED * 60;
        let token = match self.next_serial() {
            Ok(serial) => {
                let position = crate::Position {
                    x: body.x,
                    y: body.y,
                };
                let mut shot = Actor::new(ActorKind::Shot, 0, 0, position);
                shot.form = form;
                shot.heading = heading;
                let family = self.entities.iter().filter(|e| e.is_enemy()).count() as i64;
                let mut row = Entity::dynamic(
                    serial,
                    Kind::Walker(Box::new(shot)),
                    Body {
                        x: body.x,
                        y: body.y,
                        vx: speed * turn_cosine(heading, S) / S,
                        vy: speed * turn_sine(heading, S) / S,
                    },
                    facing,
                    8,
                );
                row.family_index = family;
                self.dynamic_serial = serial + 1;
                let token = row.origin.token();
                self.entities.push(row);
                token
            }
            Err(_) => 0,
        };
        let l = self.launcher(index);
        l.shot_token = token;
        l.ready = i64::from(token == 0);
        l.delay = DELAY_TICKS;
        Ok(())
    }
    /// launcher_shot.gd step.
    pub(crate) fn shot_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
        let (px, py) = (player.body.x, player.body.y);
        let step = ActorStep {
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
                requirements: vec!["frozen enemy_shot (ice shots are not ported)".into()],
            });
        }
        let body = &mut e.body;
        if action == Hold::Released {
            w.on_spit_release(body, &mut e.facing, 0, 0);
        }
        if w.falling != 0 {
            body.vy = (body.vy + GRAVITY).min(FALL_CAP);
            body.y += body.vy;
            return Ok(());
        }
        if w.form == BOUNCE {
            if w.fresh != 0 && body.overlaps(map, SHOT_BOX, 0, 0) {
                w.remove(&mut e.status, &mut e.can_respawn);
                return Ok(());
            }
            w.fresh = 0;
            if w.pause != 0 {
                w.pause -= 1;
                if w.pause == 0 {
                    w.shot_reflect(body, &mut e.facing, map);
                } else {
                    return Ok(());
                }
            } else if Actor::shot_touching(*body, map) {
                w.pause = PAUSE_TICKS;
                return Ok(());
            }
        }
        w.fresh = 0;
        if w.form == HOMING {
            w.shot_home(body, px, py);
        }
        body.x += body.vx;
        body.y += body.vy;
        Ok(())
    }
    /// launcher_shot.gd contact.
    pub(crate) fn shot_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        if w.falling != 0 {
            w.contact = 0;
            return;
        }
        // enemy_body.gd player_overlap
        let touching = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && strict(world_box(e.body, SHOT_BOX), world_box(p, pb));
        if touching && w.contact == 0 && e.body.y > p.y - 8 * S {
            w.falling = 1;
            e.body.vx = 0;
            e.body.vy = 0;
            self.player.stomp(0, input, &mut self.sound);
        } else if touching && e.body.y < p.y - 8 * S {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        if let Kind::Walker(w) = &mut self.entities[index].kind {
            w.contact = i64::from(touching);
        }
    }
}
