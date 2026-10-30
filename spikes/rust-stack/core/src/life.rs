//! Typed damage, companion and lifetime rules. No engine callbacks or clocks.
use crate::{
    body::{Body, HorizontalMove, Probe},
    math::{approach, root, screen_centre},
    player::{Player, Sound},
    polygon, Position, SCALE as S,
};
const BUBBLE_BOX: [i64; 4] = [-30 * S, -60 * S, 30 * S, 0];
const BUBBLE: [Position; 8] = [
    Position {
        x: -22 * S,
        y: -52 * S,
    },
    Position { x: 0, y: -60 * S },
    Position {
        x: 22 * S,
        y: -52 * S,
    },
    Position {
        x: 30 * S,
        y: -30 * S,
    },
    Position {
        x: 22 * S,
        y: -8 * S,
    },
    Position { x: 0, y: 0 },
    Position {
        x: -22 * S,
        y: -8 * S,
    },
    Position {
        x: -30 * S,
        y: -30 * S,
    },
];
fn rescuer_overlaps(delta: Position) -> bool {
    if delta.x < -43 * S || delta.x > 42 * S || delta.y < -83 * S || delta.y > 24 * S {
        return false;
    }
    let shifted = RESCUER.map(|p| Position {
        x: p.x + delta.x,
        y: p.y + delta.y,
    });
    polygon::overlaps_polygon(&BUBBLE, &shifted)
}
const RESCUER: [Position; 8] = [
    Position {
        x: -4 * S,
        y: -12 * S,
    },
    Position { x: 0, y: -24 * S },
    Position {
        x: 3 * S,
        y: -12 * S,
    },
    Position { x: 13 * S, y: 0 },
    Position {
        x: 11 * S,
        y: 19 * S,
    },
    Position { x: 0, y: 23 * S },
    Position {
        x: -10 * S,
        y: 17 * S,
    },
    Position { x: -12 * S, y: 0 },
];
macro_rules! life_fields {($($name:ident:$default:expr),*$(,)?)=>{
#[derive(Clone,Debug)]
pub(crate) struct Life {$(pub $name:i64,)*pub rescuers:[Position;4]}
impl Default for Life {fn default()->Self{Self{$($name:$default,)*rescuers:[Position::default();4]}}}
impl Life {
 pub fn field(&self,n:&str)->Option<i64>{Some(match n{$(stringify!($name)=>self.$name,)*
 "rescue_1_x"=>self.rescuers[0].x,"rescue_1_y"=>self.rescuers[0].y,"rescue_2_x"=>self.rescuers[1].x,"rescue_2_y"=>self.rescuers[1].y,
 "rescue_3_x"=>self.rescuers[2].x,"rescue_3_y"=>self.rescuers[2].y,"rescue_4_x"=>self.rescuers[3].x,"rescue_4_y"=>self.rescuers[3].y,_=>return None})}
 pub fn set_field(&mut self,n:&str,v:i64)->bool{match n{$(stringify!($name)=>{self.$name=v;true},)*
 "rescue_1_x"=>{self.rescuers[0].x=v;true},"rescue_1_y"=>{self.rescuers[0].y=v;true},"rescue_2_x"=>{self.rescuers[1].x=v;true},"rescue_2_y"=>{self.rescuers[1].y=v;true},
 "rescue_3_x"=>{self.rescuers[2].x=v;true},"rescue_3_y"=>{self.rescuers[2].y=v;true},"rescue_4_x"=>{self.rescuers[3].x=v;true},"rescue_4_y"=>{self.rescuers[3].y=v;true},_=>false}}
}};}
life_fields! {
 hurt:0,hurt_phase:0,invulnerable:0,health:10,health_wait:0,separated:0,recovery_delay:0,hits:0,hurt_deceleration:0,
 death_cause:0,quick_death:0,companion_mode:0,companion_age:0,companion_vx:0,companion_vy:0,companion_direction:1,
 companion_from_x:0,companion_from_y:0,companion_dx:0,bubble_bound_ticks:0,bubble_bound_from_x:0,bubble_bound_to_x:0,
 separation_grace:0,rescue_active:0,rescue_mask:0,rescue_ticks:0,checkpoint_awards:0,
}
impl Life {
    pub fn valid(&self, phase: i64, ticks: i64) -> bool {
        let limit = i64::MAX / 16384;
        (0..=8).contains(&phase)
            && (0..=240).contains(&ticks)
            && (0..=4).contains(&self.companion_mode)
            && (0..=30).contains(&self.health)
            && (0..=120).contains(&self.health_wait)
            && (0..=63).contains(&self.hurt)
            && (0..=121).contains(&self.invulnerable)
            && (0..=2).contains(&self.hurt_phase)
            && (self.hurt_phase == 0 || self.hurt > 0)
            && [0, 128, 648, 1296].contains(&self.hurt_deceleration)
            && (0..=6).contains(&self.bubble_bound_ticks)
            && (0..=36).contains(&self.recovery_delay)
            && (0..=30).contains(&self.separation_grace)
            && (0..=15).contains(&self.rescue_mask)
            && (0..=90).contains(&self.rescue_ticks)
            && (0..=30).contains(&self.checkpoint_awards)
            && (0..=5).contains(&self.death_cause)
            && [-1, 1].contains(&self.companion_direction)
            && [self.separated, self.quick_death, self.rescue_active]
                .iter()
                .all(|v| [0, 1].contains(v))
            && self.hits >= 0
            && (0..=300).contains(&self.companion_age)
            && (-48 * 60..=48 * 60).contains(&self.companion_vx)
            && (-192 * 60..=192 * 60).contains(&self.companion_vy)
            && ((self.companion_mode == 0) == (self.separated == 0))
            && ((phase == 1) == (self.companion_mode == 3))
            && (phase != 0 || ticks == 0)
            && (self.companion_mode != 4 || self.rescue_active == 1 && self.rescue_mask == 15)
            && [
                self.companion_from_x,
                self.companion_from_y,
                self.companion_dx,
                self.bubble_bound_from_x,
                self.bubble_bound_to_x,
            ]
            .iter()
            .chain(self.rescuers.iter().flat_map(|p| [&p.x, &p.y]))
            .all(|v| (-limit..=limit).contains(v))
    }
}
impl Player {
    pub fn hurt(&mut self, damager_x: i64, sound: &mut Sound) -> bool {
        if self.life.invulnerable != 0 || self.captured_by != 0 || self.life_phase != 0 {
            return false;
        }
        let separated = self.life.separated == 1;
        self.life.invulnerable = 121;
        sound.player(self.body);
        self.life.hurt = if separated {
            63
        } else if self.water.swimming != 0 {
            0
        } else {
            38
        };
        self.life.hurt_phase = if separated || self.life.hurt == 0 {
            0
        } else {
            1
        };
        self.life.hurt_deceleration = if self.water.swimming != 0 { 128 } else { 1296 };
        if self.water.swimming != 0 {
            self.body.vx = -self.facing * 200 * 60;
        } else if self.body.x < damager_x {
            self.body.vx = -self.body.vx - 256 * 60;
        } else if self.body.x > damager_x {
            self.body.vx = -self.body.vx + 256 * 60;
        }
        self.body.vy = -384 * 60;
        self.separate(self.body.vx, false);
        self.on_floor = 0;
        self.jump_buffer = 0;
        self.flutter_remaining = 0;
        true
    }
    pub fn separate(&mut self, velocity: i64, instant: bool) {
        if self.life.separated != 0 || self.life_phase != 0 {
            return;
        }
        self.attach();
        let l = &mut self.life;
        l.separated = 1;
        l.hits = l.hits.saturating_add(1);
        l.health_wait = 46;
        l.companion_mode = if instant { 2 } else { 1 };
        l.companion_age = 0;
        l.recovery_delay = if instant { 0 } else { 36 };
        l.companion_from_x = self.recovery_x;
        l.companion_from_y = self.recovery_y;
        let displacement = -velocity * 15;
        l.companion_dx = if displacement >= 0 {
            displacement.max(112 * S)
        } else {
            displacement.min(-112 * S)
        };
        l.companion_direction = if l.companion_dx >= 0 { 1 } else { -1 };
        l.companion_vx = 0;
        l.companion_vy = 0;
        if instant {
            l.companion_direction = if self.recovery_x >= self.body.x {
                1
            } else {
                -1
            };
        }
    }
    pub fn separate_in_world(
        &mut self,
        velocity: i64,
        instant: bool,
        map: &Probe,
        camera: Position,
    ) {
        let eligible = self.life.separated == 0 && self.life_phase == 0;
        self.separate(velocity, instant);
        if eligible && self.life.health == 0 && instant {
            self.start_rescue(map, camera);
        }
    }
    pub fn catch_companion(&mut self, box_: [i64; 4]) -> bool {
        if self.life_phase != 0
            || self.captured_by != 0
            || self.life.companion_mode != 2
            || self.life.bubble_bound_ticks != 0
        {
            return false;
        }
        let [left, top, right, bottom] = box_;
        if left > right || top > bottom {
            return false;
        }
        let b = [
            self.recovery_x - 30 * S,
            self.recovery_y - 60 * S,
            self.recovery_x + 30 * S,
            self.recovery_y,
        ];
        if right < b[0]
            || left > b[2]
            || bottom < b[1]
            || top > b[3]
            || !polygon::overlaps_box(
                &BUBBLE,
                [
                    left.max(b[0]) - self.recovery_x,
                    top.max(b[1]) - self.recovery_y,
                    right.min(b[2]) - self.recovery_x,
                    bottom.min(b[3]) - self.recovery_y,
                ],
            )
        {
            return false;
        }
        self.life_phase = 1;
        self.life_ticks = 51;
        let l = &mut self.life;
        l.companion_mode = 3;
        l.companion_from_x = self.recovery_x;
        l.companion_from_y = self.recovery_y;
        l.companion_age = 0;
        l.companion_vx = 0;
        l.companion_vy = 0;
        l.rescue_active = 0;
        l.rescue_mask = 0;
        l.rescue_ticks = 0;
        l.health_wait = if l.health < 10 { 120 } else { 0 };
        true
    }
    pub fn kill(&mut self, cause: i64, fast: bool, sound: &mut Sound) -> bool {
        if self.life_phase != 0 || !(1..=5).contains(&cause) {
            return false;
        }
        let quick = fast || self.life.quick_death != 0;
        self.life.death_cause = cause;
        self.life_phase = if quick { 3 } else { 2 };
        self.life_ticks = if quick { 32 } else { 240 };
        if cause == 3 {
            self.body.vx = 0;
            self.body.vy = 0;
        }
        self.life.hurt = 0;
        self.life.hurt_phase = 0;
        self.life.invulnerable = 0;
        self.captured_by = 0;
        if self.life_phase == 2 {
            sound.player(self.body);
        }
        true
    }
    pub fn blocks_step(&self) -> bool {
        self.life_phase != 0 && !(self.life_phase == 5 && self.life_ticks == 1)
    }
    pub fn locks_input(&self) -> bool {
        self.life.hurt != 0 || self.life_phase == 5
    }
    pub fn locked_action(&self, input: u8) -> u8 {
        if self.life.invulnerable == 120 && [37, 62].contains(&self.life.hurt) {
            input & 3
        } else {
            0
        }
    }
    /// Advance a non-play phase. Respawn is executed immediately by Run, never stored as a callback.
    pub fn phase_tick(&mut self, sound: &mut Sound) -> bool {
        if self.life_phase == 4 {
            return true;
        }
        if self.life_phase == 8 {
            return false;
        }
        self.life_ticks = (self.life_ticks - 1).max(0);
        match self.life_phase {
            1 => {
                let age = 51 - self.life_ticks;
                let across = age.min(48);
                let ax = self.body.x - self.facing * 10 * S;
                let ay = self.body.y - 24 * S;
                self.recovery_x =
                    self.life.companion_from_x + (ax - self.life.companion_from_x) * across / 48;
                self.recovery_y = if age <= 24 {
                    self.life.companion_from_y - 96 * S * age * (48 - age) / 576
                } else {
                    let leg = (age - 25).clamp(0, 24);
                    self.life.companion_from_y - 96 * S
                        + (ay - self.life.companion_from_y + 96 * S) * leg * leg / 576
                };
                if self.life_ticks == 0 {
                    self.life.separated = 0;
                    self.life.companion_mode = 0;
                    self.life.separation_grace = 30;
                    self.life_phase = 0;
                    self.attach();
                    sound.player(self.body);
                }
            }
            2 => {
                if self.life_ticks == 0 {
                    self.life_phase = 3;
                    self.life_ticks = 61;
                }
            }
            3 => {
                if self.life_ticks == 0 {
                    self.life_phase = 4;
                    return true;
                }
            }
            5 => {
                if self.life_ticks == 0 {
                    self.life_phase = 0;
                }
            }
            7 => {
                let age = (180 - self.life_ticks).min(60);
                let blend = age * (120 - age);
                self.body.x = self.goal_from_x + (self.goal_x - self.goal_from_x) * blend / 3600;
                self.body.y = self.goal_from_y + (self.goal_y - self.goal_from_y) * blend / 3600;
                self.attach();
                if self.life_ticks == 0 {
                    self.life_phase = 8;
                }
            }
            _ => {}
        }
        false
    }
    /// Returns true only when a new death starts.
    pub fn before_play_life(&mut self, map: &Probe, camera: Position, sound: &mut Sound) -> bool {
        self.life.invulnerable = (self.life.invulnerable - 1).max(0);
        self.life.hurt = (self.life.hurt - 1).max(0);
        if self.life.hurt == 0 || self.life.hurt == 1 && self.life.hurt_phase == 1 {
            self.life.hurt_phase = 0;
        }
        self.life.separation_grace = (self.life.separation_grace - 1).max(0);
        let died = self.companion_step(map, camera, sound);
        if self.life.separated != 0 && self.life.health > 0 {
            if self.life.health_wait <= 0 {
                self.life.health_wait = 46;
            }
            self.life.health_wait -= 1;
            if self.life.health_wait <= 0 {
                self.life.health -= 1;
                self.life.health_wait = if self.life.health != 0 { 46 } else { 0 };
                if self.life.health == 0 && self.life.companion_mode == 2 {
                    self.start_rescue(map, camera);
                }
            }
        } else if self.life.separated == 0 && self.life.health < 10 {
            if self.life.health_wait <= 0 {
                self.life.health_wait = 120;
            }
            self.life.health_wait -= 1;
            if self.life.health_wait == 0 {
                self.life.health += 1;
                self.life.health_wait = if self.life.health < 10 { 120 } else { 0 };
            }
        }
        died
    }
    fn companion_step(&mut self, map: &Probe, camera: Position, sound: &mut Sound) -> bool {
        match self.life.companion_mode {
            1 => {
                self.life.companion_age += 1;
                let age = self.life.companion_age.min(36);
                let leg = age.min(36 - age);
                self.recovery_x = self.life.companion_from_x + self.life.companion_dx * age / 36;
                self.recovery_y = self.life.companion_from_y - 56 * S * leg * (36 - leg) / 324;
                self.life.recovery_delay = 36 - age;
                if self.life.companion_age >= 38 {
                    self.life.companion_mode = 2;
                    self.life.companion_age = 0;
                    self.bubble_settle(map);
                    if self.life.health == 0 {
                        self.start_rescue(map, camera);
                    }
                }
            }
            2 => {
                if self.life.health == 0 && self.life.rescue_active == 0 {
                    self.start_rescue(map, camera);
                }
                if self.life.rescue_active != 0 {
                    if !self.catch_companion([
                        self.body.x - 12 * S,
                        self.body.y - 56 * S,
                        self.body.x + 12 * S,
                        self.body.y,
                    ]) {
                        self.rescue_step();
                    }
                } else {
                    self.bubble_step(map);
                }
            }
            4 => {
                self.recovery_y -= 256 * 60;
                for p in &mut self.life.rescuers {
                    p.y -= 256 * 60;
                }
                self.life.rescue_ticks -= 1;
                if self.life.rescue_ticks <= 0 {
                    return self.kill(2, false, sound);
                }
            }
            _ => {}
        }
        false
    }
    fn bubble_settle(&mut self, map: &Probe) {
        let probe = map.with_polygon(&BUBBLE);
        let mut body = Body {
            x: self.recovery_x,
            y: self.recovery_y,
            ..Body::default()
        };
        body.prepare(&probe, BUBBLE_BOX);
        if body.overlaps(&probe, BUBBLE_BOX, 0, 0) {
            body.x += (self.body.x - body.x).signum() * 96 * 60;
            body.y += (self.body.y - body.y).signum() * 96 * 60;
        }
        self.recovery_x = body.x;
        self.recovery_y = body.y;
    }
    fn bubble_step(&mut self, map: &Probe) {
        self.life.companion_age = if self.life.companion_age >= 300 {
            61
        } else {
            self.life.companion_age + 1
        };
        let age = self.life.companion_age;
        self.life.companion_vy = if age <= 60 {
            -192 * 60 * age / 60
        } else {
            let leg = (age - 61) % 240;
            -192 * 60 + 384 * 60 * leg.min(240 - leg) / 120
        };
        if self.life.bubble_bound_ticks != 0 {
            self.life.bubble_bound_ticks -= 1;
            let span = self.life.bubble_bound_to_x - self.life.bubble_bound_from_x;
            self.recovery_x =
                self.life.bubble_bound_from_x + span * (6 - self.life.bubble_bound_ticks) / 6;
            self.recovery_y += self.life.companion_vy;
            return;
        }
        let probe = map.with_polygon(&BUBBLE);
        let here = Body {
            x: self.recovery_x,
            y: self.recovery_y,
            ..Body::default()
        };
        let control = self.life.companion_direction;
        if self.life.companion_direction < 0 && here.wall_probe(&probe, BUBBLE_BOX, -1, 2, 3) {
            self.life.companion_direction = 1;
        }
        if self.life.companion_direction > 0 && here.wall_probe(&probe, BUBBLE_BOX, 1, 2, 3) {
            self.life.companion_direction = -1;
        }
        if here.overlaps(&probe, BUBBLE_BOX, 0, 0) {
            self.recovery_x += (self.body.x - self.recovery_x).signum() * 96 * 60;
            self.recovery_y += (self.body.y - self.recovery_y).signum() * 96 * 60;
        }
        let mut body = Body {
            x: self.recovery_x,
            y: self.recovery_y,
            vx: self.life.companion_vx,
            vy: self.life.companion_vy,
        };
        if body.prepare(&probe, BUBBLE_BOX) {
            let previous = body.vx;
            let next = (previous + control * 512).clamp(-48 * 60, 48 * 60);
            let distance = if previous != 0 {
                (previous + next) / 2
            } else {
                0
            };
            body.horizontal(&probe, BUBBLE_BOX, distance, 0, HorizontalMove::Actor);
            let vy = body.vy;
            body.vertical(&probe, BUBBLE_BOX, vy);
            body.vx = if body.vx != previous {
                (body.vx + control * 512).clamp(-48 * 60, 48 * 60)
            } else {
                next
            };
            if body.vx != 0 && body.wall(&probe, BUBBLE_BOX, body.vx.signum()) {
                body.vx = 0;
            }
        }
        self.recovery_x = body.x;
        self.recovery_y = body.y;
        self.life.companion_vx = body.vx;
        self.life.companion_vy = body.vy;
        let left = 32 * S;
        let right = left.max(map.width_pixels * S - 32 * S);
        if self.recovery_x < left || self.recovery_x > right {
            self.life.bubble_bound_ticks = 6;
            self.life.bubble_bound_from_x = self.recovery_x;
            self.life.bubble_bound_to_x = self.recovery_x.clamp(left, right);
            self.life.companion_direction = if self.recovery_x < left { 1 } else { -1 };
            self.life.companion_vx = 0;
        }
    }
    fn start_rescue(&mut self, map: &Probe, camera: Position) {
        if self.life.rescue_active != 0 || self.life.companion_mode != 2 {
            return;
        }
        self.life.rescue_active = 1;
        self.life.rescue_mask = 0;
        self.life.health_wait = 0;
        self.life.bubble_bound_ticks = 0;
        self.life.companion_vx = 0;
        self.life.companion_vy = 0;
        let centre = screen_centre(camera, map.width_pixels * S, map.height_pixels * S);
        for (index, offset) in [-120, -24, 24, 120].iter().enumerate() {
            self.life.rescuers[index] = Position {
                x: centre.x + offset * S,
                y: centre.y - 304 * S,
            };
        }
    }
    fn rescue_step(&mut self) {
        for (index, offset) in [[-32, -22], [-16, -14], [32, -22], [16, -14]]
            .iter()
            .enumerate()
        {
            if self.life.rescue_mask & (1 << index) != 0 {
                continue;
            }
            let target = Position {
                x: self.recovery_x + offset[0] * S,
                y: self.recovery_y + offset[1] * S,
            };
            let p = &mut self.life.rescuers[index];
            let dx = target.x - p.x;
            let dy = target.y - p.y;
            let divisor = 1.max(dx.abs().max(dy.abs()) / 1_000_000 + 1);
            let nx = dx / divisor;
            let ny = dy / divisor;
            let distance = 1.max(root(nx * nx + ny * ny));
            if divisor == 1 && distance <= 1024 * 60 {
                *p = target;
            } else {
                p.x += nx * 1024 * 60 / distance;
                p.y += ny * 1024 * 60 / distance;
            }
            let delta = Position {
                x: p.x - self.recovery_x,
                y: p.y - self.recovery_y,
            };
            if rescuer_overlaps(delta) {
                *p = target;
                self.life.rescue_mask |= 1 << index;
            }
        }
        if self.life.rescue_mask == 15 {
            self.life.companion_mode = 4;
            self.life.rescue_ticks = 90;
        }
    }
    pub fn after_life(&mut self, map: &Probe, sound: &mut Sound) -> bool {
        if self.life_phase != 0 {
            return false;
        }
        // move_pose.gd pit_height: the airborne pose heights, empty or full mouth.
        let full = self.food.full();
        let pit_height =
            if self.on_floor != 0 || self.water.swimming != 0 || ![0, 10].contains(&self.action) {
                62 * S
            } else if self.life.hurt != 0 {
                64 * S
            } else if self.flutter_remaining != 0 {
                if full {
                    70 * S
                } else {
                    68 * S
                }
            } else if self.body.vy < 0 {
                if full {
                    72 * S
                } else {
                    66 * S
                }
            } else if full {
                64 * S
            } else {
                66 * S
            };
        if self.body.y > map.height_pixels * S + pit_height {
            return self.kill(1, false, sound);
        }
        let rect = [
            self.body.x - 12 * S,
            self.body.y - 56 * S,
            self.body.x + 12 * S,
            self.body.y,
        ];
        if map.hazard_overlaps(rect) {
            return self.kill(3, false, sound);
        }
        if self.life.hurt_phase == 1 && self.on_floor != 0 {
            self.life.hurt_phase = 2;
            self.life.hurt = 43;
        }
        if self.life.companion_mode == 2 {
            self.catch_companion(rect);
        } else if self.life.companion_mode == 0 {
            self.attach();
        }
        false
    }
    pub fn dead_body(
        &mut self,
        map: &Probe,
        input: u8,
        frame: i64,
        rng: &mut crate::math::Rng,
        sound: &mut Sound,
    ) {
        if ![2, 3].contains(&self.life_phase) || ![1, 2, 5].contains(&self.life.death_cause) {
            return;
        }
        let quick = self.life.death_cause == 5 || self.life.quick_death != 0;
        let first = if self.life_phase == 2 {
            self.life_ticks == 239
        } else {
            quick && self.life_ticks == 31
        };
        let steer = if first {
            self.previous_input = input as i64;
            input & 3
        } else {
            0
        };
        self.advance(map, steer, 0, 0, frame, rng, sound);
        if steer == 0 && self.on_floor == 0 && self.previous_input & 3 != 0 {
            self.body.vx = approach(self.body.vx, 0, 1296);
        }
    }
}
