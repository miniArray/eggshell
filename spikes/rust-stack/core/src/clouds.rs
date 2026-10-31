//! o8 release caches (release_cloud.gd) and o19 egg redirectors (redirect_cloud.gd,
//! oriented_box.gd).
use crate::{
    entity::Kind,
    items::{Pickup, PickupKind, Star},
    math::{root, sine},
    Error, Placement, Position, PropertyValue, SCALE as S,
};

macro_rules! cloud_fields {($ty:ident,$($field:ident),*$(,)?)=>{impl $ty{pub fn field(&self,n:&str)->Option<i64>{Some(match n{$(stringify!($field)=>self.$field,)*_=>return None})}pub fn set_field(&mut self,n:&str,value:i64)->bool{match n{$(stringify!($field)=>{self.$field=value;true},)*_=>false}}}};}

pub(crate) const HIDDEN: i64 = 0;
pub(crate) const VISIBLE: i64 = 1;
pub(crate) const REVEALED: i64 = 2;
pub(crate) const OPENING: i64 = 3;
const MAX_RELEASE: i64 = 1024;
const FLAP: [usize; 6] = [0, 1, 2, 3, 2, 1];
/// enemy_motion.gd LEVEL_INTRO_TICKS - 2
const INTRO_PHASE: i64 = 150;
const TURN: i64 = 360_000;
const RECT: [i64; 4] = [-12 * S, -14 * S, 12 * S, 14 * S];

fn unsupported(reason: &str) -> Error {
    Error::Unsupported {
        requirements: vec![reason.into()],
    }
}
/// registry.gd numeric_option over a raw property (missing and "" read as "0").
fn option(p: &Placement, key: &str) -> Result<f64, Error> {
    let value = match p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v) {
        None => 0.0,
        Some(PropertyValue::Number(v)) => *v,
        Some(PropertyValue::String(s)) if s.is_empty() => 0.0,
        Some(PropertyValue::String(s)) => s
            .trim()
            .parse::<f64>()
            .map_err(|_| unsupported(&format!("{} option {key}", p.code)))?,
        Some(_) => return Err(unsupported(&format!("{} option {key}", p.code))),
    };
    if !value.is_finite() || value.abs() > (i64::MAX / S - 1) as f64 {
        return Err(unsupported(&format!("{} option {key}", p.code)));
    }
    Ok(value)
}
/// The E3 flag: a string, "1" set.
fn flag(p: &Placement) -> Result<bool, Error> {
    match p.properties.iter().find(|(k, _)| k == "E3").map(|(_, v)| v) {
        None => Ok(false),
        Some(PropertyValue::String(s)) => Ok(s == "1"),
        Some(_) => Err(unsupported(&format!("{} E3 flag", p.code))),
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Cache {
    pub content: i64,
    pub count: i64,
    pub phase: i64,
    pub age: i64,
    pub home_y: i64,
    pub release_failures: i64,
}
cloud_fields!(Cache, content, count, phase, age, home_y, release_failures);

impl Cache {
    /// release_cloud.gd prepare + create
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let content = option(p, "E1")?.trunc() as i64;
        let count = option(p, "E2")?.trunc() as i64;
        let hidden = flag(p)?;
        if content < 0 {
            return Err(unsupported("o8 contents"));
        }
        if content > 4 || count > MAX_RELEASE {
            return Err(unsupported("o8 degraded contents/count"));
        }
        Ok(Self {
            content,
            count: count.max(0),
            phase: if hidden { HIDDEN } else { VISIBLE },
            age: INTRO_PHASE,
            home_y: p.position.y,
            release_failures: 0,
        })
    }
    fn frame(&self) -> usize {
        FLAP[(self.age * 16 / 60 % 6) as usize]
    }
    pub fn bounds(&self) -> [i64; 4] {
        if self.phase == OPENING {
            return [-16 * S, -16 * S, 16 * S, 16 * S];
        }
        let f = self.frame();
        [
            -16 * S,
            [-18 * S, -57257, -14 * S, -12 * S][f],
            16 * S,
            [14, 16, 18, 20][f] * S,
        ]
    }
    pub fn valid(&self) -> bool {
        (0..=4).contains(&self.content)
            && (0..=MAX_RELEASE).contains(&self.count)
            && (HIDDEN..=OPENING).contains(&self.phase)
            && (0..=if self.phase == OPENING { 30 } else { 179 }).contains(&self.age)
            && (0..=MAX_RELEASE).contains(&self.release_failures)
    }
    /// release_cloud.gd _on_screen against the screen area around `centre`.
    fn on_screen(&self, body_x: i64, body_y: i64, centre: Position) -> bool {
        let f = self.frame();
        let half = [30, 36, 42, 34][f] * S;
        let top = [28, 18, 14, 12][f] * S;
        let bottom = [14, 16, 18, 26][f] * S;
        let screen = [
            centre.x - 416 * S,
            centre.y - 224 * S,
            centre.x + 416 * S,
            centre.y + 224 * S,
        ];
        body_x + half >= screen[0]
            && body_x - half <= screen[2]
            && body_y + bottom >= screen[1]
            && body_y - top <= screen[3]
    }
    /// release_cloud.gd hit (kinds EGG, SHELL, SPIT; fire and ice are not ported).
    pub fn hit(&mut self, status: i64, collected: i64) {
        if status != 1 || collected != 0 || self.phase == OPENING {
            return;
        }
        if self.phase == HIDDEN {
            self.phase = REVEALED;
        } else {
            self.phase = OPENING;
            self.age = 0;
        }
    }
    /// release_cloud.gd contact: the player touching a hidden cache reveals it.
    pub fn contact(&mut self, body_x: i64, body_y: i64, collected: i64, player: [i64; 4]) {
        if self.phase != HIDDEN || collected != 0 {
            return;
        }
        let b = self.bounds();
        if player[2] >= body_x + b[0]
            && player[0] <= body_x + b[2]
            && player[3] >= body_y + b[1]
            && player[1] <= body_y + b[3]
        {
            self.phase = REVEALED;
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Redirect {
    pub base_angle: i64,
    pub angle: i64,
    pub rotation_step: i64,
    pub rotation_period: i64,
    pub age: i64,
    pub infinite: i64,
    pub last_egg: i64,
    pub colour: i64,
}
cloud_fields!(
    Redirect,
    base_angle,
    angle,
    rotation_step,
    rotation_period,
    age,
    infinite,
    last_egg,
    colour
);

/// oriented_box.gd angle_wrap
fn wrap(angle: i64) -> i64 {
    (angle % TURN + TURN) % TURN
}
/// oriented_box.gd vector
pub(crate) fn vector(angle: i64, length: i64) -> (i64, i64) {
    let x = sine(wrap(angle + 90_000), TURN, 1_000_000).expect("fixed period");
    let y = sine(wrap(angle), TURN, 1_000_000).expect("fixed period");
    let magnitude = root(x * x + y * y);
    (length * x / magnitude, length * y / magnitude)
}
/// oriented_box.gd points: the rectangle turned by `angle`.
fn points(angle: i64) -> Vec<Position> {
    let (bx, by) = vector(angle, S);
    [
        [RECT[0], RECT[1]],
        [RECT[2], RECT[1]],
        [RECT[2], RECT[3]],
        [RECT[0], RECT[3]],
    ]
    .iter()
    .map(|c| Position {
        x: (c[0] * bx - c[1] * by) / S,
        y: (c[0] * by + c[1] * bx) / S,
    })
    .collect()
}

impl Redirect {
    /// redirect_cloud.gd prepare + create
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let rotation = option(p, "R")?;
        let step = option(p, "E1")?;
        let period = option(p, "E2")?;
        let infinite = flag(p)?;
        let base_angle = wrap((rotation.rem_euclid(360.0) * 1000.0).round() as i64);
        Ok(Self {
            base_angle,
            angle: base_angle,
            rotation_step: wrap(step.trunc() as i64 % 360 * 1000),
            rotation_period: ((period * 60.0).ceil() as i64).max(1),
            age: 0,
            infinite: i64::from(infinite),
            last_egg: 0,
            colour: -1,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        let pts = points(self.base_angle);
        let mut b = [pts[0].x, pts[0].y, pts[0].x, pts[0].y];
        for p in &pts[1..] {
            b = [b[0].min(p.x), b[1].min(p.y), b[2].max(p.x), b[3].max(p.y)];
        }
        b
    }
    /// redirect_cloud.gd touches: the turned rectangle against the probe.
    pub fn touches(&self, body_x: i64, body_y: i64, probe: [i64; 4]) -> bool {
        crate::polygon::overlaps_box(
            &points(self.base_angle),
            [
                probe[0] - body_x,
                probe[1] - body_y,
                probe[2] - body_x,
                probe[3] - body_y,
            ],
        )
    }
    /// redirect_cloud.gd step
    pub fn step(&mut self, rng: &mut crate::math::Rng) {
        if self.colour < 0 {
            self.colour = rng.ticks(0, 3);
        }
        self.age = if self.age == i64::MAX {
            0
        } else {
            self.age + 1
        };
        if self.age % self.rotation_period == 0 {
            self.angle = wrap(self.angle + self.rotation_step);
        }
    }
    pub fn valid(&self) -> bool {
        (0..TURN).contains(&self.base_angle)
            && (0..TURN).contains(&self.angle)
            && (0..TURN).contains(&self.rotation_step)
            && self.rotation_period >= 1
            && self.age >= 0
            && [0, 1].contains(&self.infinite)
            && self.last_egg >= 0
            && (-1..=3).contains(&self.colour)
    }
}

impl crate::state::Run {
    /// release_cloud.gd step (phase 0).
    pub(crate) fn cache_step(&mut self, index: usize, centre: Position) -> Result<(), Error> {
        let e = &mut self.entities[index];
        if e.status != 1 {
            return Ok(());
        }
        if e.collected != 0 {
            e.status = 3;
            return Ok(());
        }
        let Kind::Cache(c) = &mut e.kind else {
            return Ok(());
        };
        if c.phase == OPENING {
            c.age = (c.age + 1).min(30);
            if c.age == 30 {
                return self.release(index);
            }
            return Ok(());
        }
        c.age = (c.age + 1) % 180;
        e.body.y = c.home_y + sine(c.age, 180, 16 * S)?;
        if c.phase == REVEALED && !c.on_screen(e.body.x, e.body.y, centre) {
            c.phase = HIDDEN;
        }
        Ok(())
    }
    /// release_cloud.gd _release
    fn release(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        let Kind::Cache(c) = &e.kind else {
            return Ok(());
        };
        let (content, total, layer, token) = (c.content, c.count, e.layer, e.origin.token());
        let (x, y) = (e.body.x, e.body.y);
        let count = if [1, 2].contains(&content) {
            total
        } else {
            i64::from([3, 4].contains(&content))
        };
        for n in 0..count {
            if content == 1 || content == 2 && self.player.life.health + n + 1 > 30 {
                let vx = self.rng.ticks(-192 * 60, 192 * 60);
                let vy = self.rng.ticks(-768 * 60, -512 * 60);
                let mut pickup = Pickup::new(PickupKind::Coin, 0, y);
                pickup.moving = 1;
                pickup.despawn_ticks = 480;
                self.push_dynamic(Kind::Pickup(pickup), x, y, vx, vy, -1, layer, 0)?;
            } else if content == 2 {
                let vy = self.rng.ticks(-512 * 60, -256 * 60);
                let facing = if self.rng.ticks(-1_000_000, 1_000_000) > 0 {
                    1
                } else {
                    -1
                };
                let max_speed = self.rng.ticks(64 * 60, 128 * 60);
                let star = Star {
                    phase: 10,
                    despawn_ticks: 480,
                    max_speed,
                    ..Star::default()
                };
                self.push_dynamic(Kind::Star(star), x, y, 0, vy, facing, layer, 0)?;
            } else if content == 3 {
                let mut pickup = Pickup::new(PickupKind::Flower, 0, y);
                pickup.origin_token = token;
                self.push_dynamic(Kind::Pickup(pickup), x, y, 0, 0, -1, layer, 0)?;
            } else {
                return Err(unsupported("o8 content 4 releases o14, not ported yet"));
            }
        }
        let e = &mut self.entities[index];
        e.status = 3;
        if let Kind::Cache(c) = &mut e.kind {
            c.release_failures = 0;
        }
        if content != 3 {
            e.collected = 1;
        }
        Ok(())
    }
    /// registry.gd spawn_dynamic for a non-enemy item with explicit common fields.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn push_dynamic(
        &mut self,
        kind: Kind,
        x: i64,
        y: i64,
        vx: i64,
        vy: i64,
        facing: i64,
        layer: i64,
        can_despawn: i64,
    ) -> Result<(), Error> {
        let serial = self.dynamic_serial;
        if !(1..=i64::MAX - crate::entity::TOKEN_BASE).contains(&serial) {
            return Err(unsupported("runtime creation serial"));
        }
        let mut row = crate::entity::Entity::dynamic(
            serial,
            kind,
            crate::body::Body { x, y, vx, vy },
            facing,
            layer,
        );
        row.can_despawn = can_despawn;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
}
