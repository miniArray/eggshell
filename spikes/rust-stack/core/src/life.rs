//! Typed damage, companion and lifetime rules. No engine callbacks or clocks.
use crate::{
    body::{Body, HorizontalMove, Probe},
    math::{approach, root, screen_centre},
    player::{Player, Sound},
    polygon, Position, SCALE as S,
};
const BUBBLE_BOX: [i64; 4] = [-30 * S, -60 * S, 30 * S, 0];
/// life.gd HURT_RECOVERED: the knocked pose has cleared; one input-lock tick remains.
pub(crate) const HURT_RECOVERED: i64 = 3;
/// companion_bubble.gd PHYSICAL_WIDTH / PHYSICAL_HEIGHT: terrain recovery extents.
const BUBBLE_PHYSICAL: i64 = 64 * S;
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
            && (0..=HURT_RECOVERED).contains(&self.hurt_phase)
            && (self.hurt_phase == 0 || self.hurt > 0)
            && (self.hurt_phase != HURT_RECOVERED || self.hurt == 1)
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
                let Position { x: ax, y: ay } = self.companion_anchor();
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
        // life.gd _hurt_step: the knocked pose clears one step before its input lock ends,
        // and that last lock tick stays distinct from Spin's.
        if self.life.hurt == 0 {
            self.life.hurt_phase = 0;
        } else if self.life.hurt == 1 && self.life.hurt_phase == 1 {
            self.life.hurt_phase = HURT_RECOVERED;
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
        body.prepare_recovering(&probe, BUBBLE_BOX, BUBBLE_PHYSICAL, BUBBLE_PHYSICAL);
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
        // companion_bubble.gd advance: the platform keeps the pre-recovery floor for ramp
        // following, even while rising, and settles its sway on that floor.
        let support = body.floor(&probe, BUBBLE_BOX);
        if body.prepare_recovering(&probe, BUBBLE_BOX, BUBBLE_PHYSICAL, BUBBLE_PHYSICAL) {
            body.settle(&probe, BUBBLE_BOX, support);
            let previous = body.vx;
            let accelerated = previous + control * 512;
            let next = accelerated.clamp(-48 * 60, 48 * 60);
            // The displacement integrates the acceleration first, then takes its own cap.
            let distance = if previous != 0 {
                ((previous + accelerated) / 2).clamp(-48 * 60, 48 * 60)
            } else {
                0
            };
            body.horizontal(&probe, BUBBLE_BOX, distance, support, HorizontalMove::Actor);
            let vy = body.vy;
            body.vertical_support(&probe, BUBBLE_BOX, vy, support);
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

#[cfg(test)]
mod companion_anchor_tests {
    use super::*;

    fn swimmer() -> Player {
        let mut player = Player::new(
            Body {
                x: 100 * S,
                y: 200 * S,
                ..Body::default()
            },
            1,
        );
        player.water.swimming = 1;
        player
    }

    #[test]
    fn move_pose_companion_anchor_uses_steady_water_and_pre_contact_speed() {
        for facing in [-1, 1] {
            let mut player = swimmer();
            player.facing = facing;
            player.body.vx = 128 * 60;
            assert_eq!(
                player.companion_anchor(),
                Position {
                    x: (100 - facing * 10) * S,
                    y: 168 * S
                }
            );
            player.brake_vx = -128 * 60;
            player.body.vx = 0;
            assert_eq!(
                player.companion_anchor(),
                Position {
                    x: (100 - facing * 12) * S,
                    y: 170 * S
                }
            );
        }
    }

    #[test]
    fn move_pose_companion_anchor_falls_back_for_every_nonsteady_pose() {
        for condition in [
            "land",
            "action",
            "hurt",
            "transition",
            "jump",
            "dive",
            "aim",
            "duck",
            "look",
        ] {
            let mut player = swimmer();
            player.brake_vx = 128 * 60;
            match condition {
                "land" => player.water.swimming = 0,
                "action" => player.action = 10,
                "hurt" => player.life.hurt = 1,
                "transition" => player.water.transition = 1,
                "jump" => player.water.jump = 1,
                "dive" => player.water.dive = 1,
                "aim" => player.food.aim = 1,
                "duck" => player.duck = 1,
                "look" => player.look = 1,
                _ => unreachable!(),
            }
            assert_eq!(
                player.companion_anchor(),
                Position {
                    x: 90 * S,
                    y: 176 * S
                },
                "{condition}"
            );
        }
    }

    #[test]
    fn life_separation_starts_at_the_water_pose_anchor() {
        let mut player = swimmer();
        player.brake_vx = 128 * 60;
        let expected = player.companion_anchor();
        player.separate(0, true);
        assert_eq!(
            Position {
                x: player.recovery_x,
                y: player.recovery_y
            },
            expected
        );
        assert_eq!(
            Position {
                x: player.life.companion_from_x,
                y: player.life.companion_from_y
            },
            expected
        );
    }

    #[test]
    fn life_rejoin_finishes_at_the_water_pose_anchor() {
        let mut player = swimmer();
        player.brake_vx = 128 * 60;
        player.life_phase = 1;
        player.life_ticks = 3;
        player.life.companion_mode = 3;
        player.life.separated = 1;
        player.life.companion_from_x = 0;
        player.life.companion_from_y = 0;
        let expected = player.companion_anchor();
        let mut sound = Sound::default();
        for _ in 0..3 {
            assert!(!player.phase_tick(&mut sound));
            assert_eq!(
                Position {
                    x: player.recovery_x,
                    y: player.recovery_y
                },
                expected
            );
        }
        assert_eq!(player.life_phase, 0);
        assert_eq!(player.life.companion_mode, 0);
        assert_eq!(player.life.separation_grace, 30);
    }
}

#[cfg(test)]
mod bubble_physics_tests {
    use super::*;

    #[test]
    fn companion_bubble_integrates_acceleration_before_capping_the_displacement() {
        let level = serde_json::json!({
            "version":"s3.8", "name":"bubble", "desc":"", "author":"test",
            "startpoint":{"map":1, "X":128, "Y":128},
            "maps":{"map1":{"width":4096, "height":2048, "objects":{}}}
        })
        .to_string();
        let world = crate::World::compile(
            &level,
            include_str!("../../../../data/collision_table.json"),
        )
        .unwrap();
        let map = Probe::new(&world.maps[0]);
        // (previous speed, expected displacement): only a speed near the cap differs from
        // the old capped-mean rule, which gave 2720 and 2830.
        for (previous, distance) in [(2560, 2816), (2780, 2880), (512, 768)] {
            let mut player = Player::new(
                Body {
                    x: 400 * S,
                    y: 1000 * S,
                    ..Body::default()
                },
                1,
            );
            player.life.companion_mode = 2;
            player.life.companion_age = 100;
            player.life.companion_direction = 1;
            player.life.companion_vx = previous;
            player.recovery_x = 1000 * S;
            player.recovery_y = 600 * S;
            player.bubble_step(&map);
            assert_eq!(player.recovery_x - 1000 * S, distance, "{previous}");
            assert_eq!(player.life.companion_vx, (previous + 512).min(48 * 60));
        }
    }
}

#[cfg(test)]
mod knock_recovery_tests {
    use super::*;

    fn knocked(hurt: i64, hurt_phase: i64) -> Player {
        let mut player = Player::new(
            Body {
                x: 400 * S,
                y: 400 * S,
                ..Body::default()
            },
            1,
        );
        player.life.hurt = hurt;
        player.life.hurt_phase = hurt_phase;
        player
    }

    #[test]
    fn life_hurt_step_marks_the_cleared_knock_pose_on_its_last_lock_tick() {
        let mut player = knocked(2, 1);
        let mut sound = Sound::default();
        player.before_play_life(
            &Probe::new(
                &crate::World::compile(
                    &serde_json::json!({
                        "version":"s3.8", "name":"knock", "desc":"", "author":"test",
                        "startpoint":{"map":1, "X":400, "Y":400},
                        "maps":{"map1":{"width":4096, "height":2048, "objects":{}}}
                    })
                    .to_string(),
                    include_str!("../../../../data/collision_table.json"),
                )
                .unwrap()
                .maps[0],
            ),
            Position::default(),
            &mut sound,
        );
        assert_eq!(
            (player.life.hurt, player.life.hurt_phase),
            (1, HURT_RECOVERED)
        );
        assert!(player.life.valid(player.life_phase, player.life_ticks));
    }

    #[test]
    fn enemy_body_bounce_runs_only_after_the_knocked_pose_clears() {
        let mut sound = Sound::default();
        // A cleared knock pose bounces, with the held jump read from the raw input.
        let mut recovered = knocked(1, HURT_RECOVERED);
        recovered.previous_input = 4;
        recovered.enemy_bounce(0, 0, false, &mut sound);
        assert_eq!(recovered.body.vy, (-320 - 384) * 60);
        // Spin's last lock tick, a running knock pose and an open message block it.
        for (hurt, phase, modal) in [(1, 0, false), (5, 1, false), (0, 0, true)] {
            let mut player = knocked(hurt, phase);
            player.enemy_bounce(0, 4, modal, &mut sound);
            assert_eq!(player.body.vy, 0, "{hurt} {phase} {modal}");
        }
        let mut free = knocked(0, 0);
        free.enemy_bounce(0, 0, false, &mut sound);
        assert_eq!(free.body.vy, -320 * 60);
    }
}
