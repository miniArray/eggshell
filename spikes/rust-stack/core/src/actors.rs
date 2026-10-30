//! Required actor-family state and integer AI; fish-only declarations stay codec defaults.
use crate::{
    body::{Body, HorizontalMove, Probe},
    math::{root, sine, Rng},
    player::Player,
    Error, Position, SCALE as S,
};
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ActorKind {
    Walker,
    Flyer,
    Flower,
    Plant,
    Stilt,
}
#[derive(Clone, Debug)]
pub(crate) struct Actor {
    pub kind: ActorKind,
    pub variant: i64,
    pub mirror: i64,
    pub spawn_x: i64,
    pub spawn_y: i64,
    pub hidden: i64,
    pub held: i64,
    pub request_cursor: i64,
    pub spat: i64,
    pub spit_age: i64,
    pub spit_speed: i64,
    pub spit_wall: i64,
    pub impact_cursor: i64,
    pub started: i64,
    pub frozen: i64,
    pub thaw_ticks: i64,
    pub roll: i64,
    pub roll_ticks: i64,
    pub roll_up: i64,
    pub roll_grace: i64,
    pub roll_bounce: i64,
    pub ground_form: i64,
    pub phase: i64,
    pub timer: i64,
    pub cycles: i64,
    pub mode: i64,
    pub water: i64,
    pub contact: i64,
    pub head_dx: i64,
    pub head_dy: i64,
    pub head_size: i64,
    pub rise_ticks: i64,
    pub rise_velocity: i64,
    pub pin_size: i64,
    pub height: i64,
    pub stride: i64,
}
pub(crate) struct ActorStep<'a, 'w> {
    pub map: &'a Probe<'w>,
    pub frame: i64,
    pub camera: Position,
    pub player: &'a mut Player,
    pub rng: &'a mut Rng,
}
impl Actor {
    pub fn new(kind: ActorKind, variant: i64, mirror: i64, spawn: Position) -> Self {
        Self {
            kind,
            variant,
            mirror,
            spawn_x: spawn.x,
            spawn_y: spawn.y,
            hidden: 0,
            held: 0,
            request_cursor: 0,
            spat: 0,
            spit_age: 0,
            spit_speed: 0,
            spit_wall: 0,
            impact_cursor: 0,
            started: 0,
            frozen: 0,
            thaw_ticks: 0,
            roll: 0,
            roll_ticks: 0,
            roll_up: 0,
            roll_grace: 0,
            roll_bounce: 0,
            ground_form: 0,
            phase: 0,
            timer: 0,
            cycles: 0,
            mode: 0,
            water: 0,
            contact: 0,
            head_dx: 0,
            head_dy: 0,
            head_size: 0,
            rise_ticks: 0,
            rise_velocity: 0,
            pin_size: 0,
            height: 68 * S,
            stride: 0,
        }
    }
    pub fn valid(&self) -> bool {
        let limit = i64::MAX / 16384;
        let last = if [ActorKind::Walker, ActorKind::Flyer, ActorKind::Stilt].contains(&self.kind) {
            4
        } else {
            1
        };
        (0..=last).contains(&self.variant)
            && (self.kind != ActorKind::Stilt
                || ((1..=100_018 * S).contains(&self.height)
                    && (0..72).contains(&self.stride)
                    && (0..=1).contains(&self.phase)
                    && (0..=36).contains(&self.timer)))
            && (0..=2).contains(&self.mirror)
            && [self.spawn_x, self.spawn_y]
                .iter()
                .all(|v| (-limit..=limit).contains(v))
            && [
                self.hidden,
                self.held,
                self.spat,
                self.spit_wall,
                self.started,
                self.frozen,
                self.roll,
                self.roll_up,
                self.roll_bounce,
                self.ground_form,
                self.water,
                self.contact,
            ]
            .iter()
            .all(|v| [0, 1].contains(v))
            && (0..=90).contains(&self.roll_ticks)
            && (0..=15).contains(&self.roll_grace)
            && (-S..=S).contains(&self.head_dx)
            && (-S..=S).contains(&self.head_dy)
            && (0..=15).contains(&self.head_size)
            && (0..=15).contains(&self.pin_size)
            && (self.mode != 4 || self.pin_size <= self.head_size)
            && (0..=60).contains(&self.rise_ticks)
            && (0..=704 * 60).contains(&self.rise_velocity)
            && (0..=1_000_000).contains(&self.spit_age)
            && (0..=1000 * 60).contains(&self.spit_speed)
            && self.request_cursor >= 0
            && self.impact_cursor >= 0
            && (0..=480 * self.frozen).contains(&self.thaw_ticks)
    }
    pub fn activate(&mut self, facing: i64, rng: &mut Rng) {
        match self.kind {
            ActorKind::Walker => {
                self.timer = rng.ticks(60, 150);
                self.cycles = rng.cycles();
            }
            ActorKind::Flyer => self.cycles = if facing < 0 { 1 } else { -1 },
            _ => {}
        }
    }
    pub fn body_bounds(&self, facing: i64) -> [i64; 4] {
        if self.roll != 0 && [ActorKind::Walker, ActorKind::Flyer].contains(&self.kind) {
            return [-12 * S, -12 * S, 12 * S, 16 * S];
        }
        match self.kind {
            ActorKind::Walker => [-10 * S, -18 * S, 10 * S, 16 * S],
            ActorKind::Flyer if self.ground_form != 0 => [-10 * S, -18 * S, 10 * S, 16 * S],
            ActorKind::Flyer => {
                if facing < 0 {
                    [-12 * S, -16 * S, 8 * S, 22 * S]
                } else {
                    [-8 * S, -16 * S, 12 * S, 22 * S]
                }
            }
            ActorKind::Flower => [-14 * S, -34 * S, 14 * S, 16 * S],
            ActorKind::Stilt => [-8 * S, -self.height, 8 * S, 0],
            ActorKind::Plant => {
                let top = if self.mode == 0 { -14 * S } else { -10 * S };
                if self.variant == 1 {
                    [-14 * S, -16 * S, 14 * S, -top]
                } else {
                    [-14 * S, top, 14 * S, 16 * S]
                }
            }
        }
    }
    pub fn bounds(&self, body: Body, facing: i64) -> [i64; 4] {
        let b = self.body_bounds(facing);
        if self.kind == ActorKind::Plant && self.head_size != 0 {
            let h = self.head_box(body, facing);
            [
                b[0].min(h[0] - body.x),
                b[1].min(h[1] - body.y),
                b[2].max(h[2] - body.x),
                b[3].max(h[3] - body.y),
            ]
        } else {
            b
        }
    }
    pub(crate) fn movement(
        &self,
        body: &mut Body,
        facing: i64,
        map: &Probe,
        distance: i64,
    ) -> (i64, bool) {
        let b = self.body_bounds(facing);
        if !body.prepare(map, b) {
            return (0, false);
        }
        let support = body.floor(map, b);
        let grounded = support != 0 && body.vy >= 0;
        let actual = body.horizontal(map, b, distance, support, HorizontalMove::Actor);
        (actual, grounded)
    }
    fn edge(&self, body: Body, facing: i64, map: &Probe) -> bool {
        let left = if facing > 0 { body.x } else { body.x - 12 * S };
        let bottom = body.y + self.body_bounds(facing)[3];
        !(map.terrain_overlaps([left, bottom, left + 12 * S, bottom + 28 * S])
            || map.border_overlaps([left, bottom, left + 12 * S, bottom + 28 * S]))
    }
    pub fn advance(
        &mut self,
        body: &mut Body,
        facing: &mut i64,
        step: &mut ActorStep,
    ) -> Result<(), Error> {
        let fresh = self.started == 0;
        if fresh {
            self.started = 1;
            if self.mirror == 2 {
                *facing = if step.player.body.x > body.x { 1 } else { -1 };
            }
        }
        if fresh
            && self.kind == ActorKind::Plant
            && self.variant == 1
            && !body.overlaps(step.map, self.body_bounds(*facing), 0, -4 * S)
        {
            self.variant = 0;
        }
        match self.kind {
            ActorKind::Walker => self.walker(body, facing, step),
            ActorKind::Flyer if self.ground_form != 0 => {
                if self.timer == 0 && self.mode == 0 {
                    self.timer = step.rng.ticks(60, 150);
                    self.cycles = step.rng.cycles();
                }
                self.walker(body, facing, step);
            }
            ActorKind::Flyer => {
                if self.cycles == 0 {
                    self.activate(*facing, step.rng);
                }
                if self.phase == 0 {
                    self.phase = 360;
                } else {
                    self.phase = self.phase % 360 + 1;
                    let leg = if self.phase <= 180 {
                        self.phase
                    } else {
                        360 - self.phase
                    };
                    body.vx =
                        ((-128 * 60 + 256 * 60 * leg / 180) * self.cycles).clamp(-48 * 60, 48 * 60);
                    self.movement(body, *facing, step.map, body.vx);
                    if body.vx != 0 {
                        *facing = body.vx.signum();
                    }
                }
                let clock = step
                    .frame
                    .checked_add(152)
                    .ok_or_else(|| Error::Unsupported {
                        requirements: vec![
                            "flyer intro clock exceeds admitted integer range".into()
                        ],
                    })?;
                body.y = self.spawn_y + sine(clock % 180, 180, 12 * S)?;
            }
            ActorKind::Flower => {
                if self.mode == 1 {
                    self.timer -= 1;
                    if [72, 54, 36].contains(&self.timer) {
                        *facing = -*facing;
                    }
                    if self.timer == 0 {
                        self.mode = 0;
                    }
                }
                body.vx = 0;
                let mut grounded = false;
                if self.mode == 0 {
                    let speed = if step.map.water_at(body.x, body.y) {
                        24
                    } else {
                        48
                    };
                    body.vx = *facing * speed * 60;
                    let distance = body.vx;
                    let (actual, started) = self.movement(body, *facing, step.map, distance);
                    grounded = started;
                    if actual != distance || body.vx == 0 {
                        self.mode = 1;
                        self.timer = 108;
                        body.vx = 0;
                    }
                }
                if body.gravity(step.map, self.body_bounds(*facing), grounded)
                    && self.mode == 0
                    && self.edge(*body, *facing, step.map)
                {
                    self.mode = 1;
                    self.timer = 108;
                    body.vx = 0;
                }
            }
            ActorKind::Plant => self.plant(body, facing, step),
            ActorKind::Stilt => self.stilt_advance(body, facing, step.map),
        }
        Ok(())
    }
    fn walker(&mut self, body: &mut Body, facing: &mut i64, step: &mut ActorStep) {
        if self.timer == 0 && self.mode == 0 {
            self.timer = step.rng.ticks(60, 150);
            self.cycles = step.rng.cycles();
        }
        self.timer -= 1;
        if self.mode == 0 {
            self.phase += 1;
            if self.phase % 30 == 0 {
                *facing = -*facing;
            }
            if self.timer == 0 {
                self.mode = 1;
                self.timer = 15;
            }
        } else if self.timer == 0 {
            if self.cycles != 0 {
                self.cycles -= 1;
                self.timer = 15;
            } else {
                self.mode = 0;
                self.phase = 0;
                self.timer = step.rng.ticks(60, 150);
                self.cycles = step.rng.cycles();
            }
        }
        body.vx = if self.mode == 1 { *facing * 48 * 60 } else { 0 };
        let (_, grounded) = self.movement(body, *facing, step.map, body.vx);
        if body.gravity(step.map, [-10 * S, -18 * S, 10 * S, 16 * S], grounded)
            && self.mode == 1
            && self.edge(*body, *facing, step.map)
        {
            *facing = -*facing;
        }
    }
    pub fn head_box(&self, body: Body, facing: i64) -> [i64; 4] {
        let width = 16 * S + 48 * S * self.head_size / 15;
        let height = 16 * S + 38 * S * self.head_size / 15;
        let points = [
            [50, 22],
            [30, 34],
            [8, 26],
            [-2, 8],
            [8, -10],
            [30, -20],
            [50, -8],
            [62, 8],
        ];
        let (mut left, mut right, mut top, mut bottom) =
            (1_000_000_000, -1_000_000_000, 1_000_000_000, -1_000_000_000);
        for [x, y] in points {
            let x = x * width / 64;
            let mut y = y * height / 54;
            if facing > 0 {
                y = -y;
            }
            let rx = (x * self.head_dx - y * self.head_dy) / S;
            let ry = (x * self.head_dy + y * self.head_dx) / S;
            left = left.min(rx);
            right = right.max(rx);
            top = top.min(ry);
            bottom = bottom.max(ry);
        }
        let px = body.x + facing * 2 * S;
        let py = self.pivot(body);
        [px + left, py + top, px + right, py + bottom]
    }
    fn pivot(&self, body: Body) -> i64 {
        body.y + if self.variant == 1 { 10 * S } else { -10 * S }
    }
    fn pin(&self, body: Body, facing: i64, player: &mut Player) {
        let width = 16 * S + 48 * S * self.pin_size / 15;
        let reach = 44 * width / 64;
        player.body.x = body.x + facing * 2 * S + reach * self.head_dx / S;
        player.body.y = self.pivot(body) + reach * self.head_dy / S;
    }
    pub fn capture(&mut self, body: Body, facing: i64, family_index: i64, player: &mut Player) {
        if player.life.invulnerable != 0 || player.captured_by != 0 || ![1, 2].contains(&self.mode)
        {
            return;
        }
        let b = self.head_box(body, facing);
        if player.body.x + 12 * S > b[0]
            && player.body.x - 12 * S < b[2]
            && player.body.y > b[1]
            && player.body.y - 56 * S < b[3]
        {
            self.mode = 4;
            self.pin_size = self.head_size;
            self.timer = 210;
            self.phase = 0;
            player.captured_by = family_index + 1;
            player.body.vx = 0;
            player.body.vy = 0;
            player.flutter_remaining = 0;
            player.jump_buffer = 0;
            player.on_floor = 0;
            self.pin(body, facing, player);
        }
    }
    fn plant(&mut self, body: &mut Body, facing: &mut i64, step: &mut ActorStep) {
        if self.variant == 1 {
            body.vy = 0;
        } else {
            body.gravity(step.map, self.body_bounds(*facing), false);
        }
        if self.mode == 4 {
            self.head_size = (self.head_size + 1).min(15);
            self.phase += 1;
            self.timer -= 1;
            if self.phase == 30 {
                step.player
                    .separate_in_world(-*facing * 400 * 60, true, step.map, step.camera);
            }
            if self.phase > 60 && step.player.pressed_input & 4 != 0 {
                self.timer = (self.timer - 30).max(0);
            }
            if self.timer == 0 {
                self.mode = 5;
                self.timer = 30;
                step.player.captured_by = 0;
                step.player.life.invulnerable = 121;
                step.player.life.hurt = 38;
                step.player.life.hurt_phase = 1;
                step.player.life.hurt_deceleration = 648;
                step.player.body.vx = *facing * 400 * 60;
                step.player.body.vy = -384 * 60;
                step.player.on_floor = 0;
            } else {
                self.pin(*body, *facing, step.player);
            }
            return;
        }
        if self.mode == 5 {
            self.timer -= 1;
            if self.timer == 0 {
                self.mode = 2;
            }
            return;
        }
        let near = (step.player.body.x - body.x).abs() < 256 * S
            && (step.player.body.y - body.y).abs() < 256 * S;
        if near {
            if [0, 3].contains(&self.mode) {
                self.mode = 1;
                self.head_size = 0;
            }
            if self.mode == 1 {
                self.head_size = (self.head_size + 1).min(15);
                if self.head_size == 15 {
                    self.mode = 2;
                }
            }
            *facing = if step.player.body.x > body.x { 1 } else { -1 };
            let dx = step.player.body.x - body.x;
            let mut dy = step.player.body.y - self.pivot(*body);
            dy = if self.variant == 1 {
                dy.max(0)
            } else {
                dy.min(0)
            };
            if dx == 0 && dy == 0 {
                self.head_dx = S;
                self.head_dy = 0;
            } else {
                let len = root(dx * dx + dy * dy);
                self.head_dx = dx * S / len;
                self.head_dy = dy * S / len;
            }
        } else if self.mode != 0 {
            self.mode = 3;
            self.head_size = (self.head_size - 1).max(0);
            if self.head_size == 0 {
                self.mode = 0;
            }
        }
    }
}
macro_rules! fields{($($f:ident),*$(,)?)=>{impl Actor{pub fn field(&self,n:&str)->Option<i64>{Some(match n{$(stringify!($f)=>self.$f,)*_=>return None})}pub fn set_field(&mut self,n:&str,v:i64)->bool{match n{$(stringify!($f)=>{self.$f=v;true},)*_=>false}}}};}
fields!(
    variant,
    mirror,
    spawn_x,
    spawn_y,
    hidden,
    held,
    request_cursor,
    spat,
    spit_age,
    spit_speed,
    spit_wall,
    impact_cursor,
    started,
    frozen,
    thaw_ticks,
    roll,
    roll_ticks,
    roll_up,
    roll_grace,
    roll_bounce,
    ground_form,
    phase,
    timer,
    cycles,
    mode,
    water,
    contact,
    head_dx,
    head_dy,
    head_size,
    rise_ticks,
    rise_velocity,
    pin_size,
    height,
    stride
);
