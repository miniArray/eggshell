//! Typed player motion for admitted Stride/Bounce/Lagoon slices.
//! Tongue, water and lifetime rules share this authoritative Player.
use crate::{body::Body, math::approach, SCALE as S};
pub(crate) const NORMAL: [i64; 4] = [-12 * S, -56 * S, 12 * S, 0];
#[derive(Clone, Debug, Default)]
pub(crate) struct Sound {
    pub serial: i64,
    pub kind: i64,
    pub x: i64,
    pub y: i64,
}
impl Sound {
    pub fn player(&mut self, b: Body) {
        self.emit(1, b.x, b.y - 28 * S);
    }
    pub fn emit(&mut self, kind: i64, x: i64, y: i64) {
        self.serial = if self.serial == i64::MAX {
            1
        } else {
            self.serial + 1
        };
        self.kind = kind;
        self.x = x;
        self.y = y;
    }
}
#[derive(Clone, Debug)]
pub(crate) struct Player {
    pub body: Body,
    pub life: crate::life::Life,
    pub tongue: crate::tongue::Tongue,
    pub water: crate::water::Water,
    pub food: crate::food::Food,
    pub action_wet: i64,
    pub facing: i64,
    pub movement: i64,
    pub on_floor: i64,
    pub support_bridge: i64,
    pub captured_by: i64,
    pub previous_input: i64,
    pub pressed_input: i64,
    pub jump_buffer: i64,
    pub flutter_remaining: i64,
    pub flutter_cooldown: i64,
    pub flutter_ready: i64,
    pub boosted_flutter: i64,
    pub action: i64,
    pub action_tick: i64,
    pub duck: i64,
    pub look: i64,
    pub posture_tick: i64,
    pub impact: i64,
    pub impact_x: i64,
    pub impact_y: i64,
    pub turn: i64,
    pub turn_ticks: i64,
    pub push: i64,
    pub pound_delay: i64,
    pub gravity_tick: i64,
    pub bounce: i64,
    pub brake_vx: i64,
    /// moves.gd move_snow: standing on snow64 terrain.
    pub snow: i64,
    pub jump_carry: i64,
    pub life_phase: i64,
    pub life_ticks: i64,
    pub recovery_x: i64,
    pub recovery_y: i64,
    pub goal_from_x: i64,
    pub goal_from_y: i64,
    pub goal_x: i64,
    pub goal_y: i64,
}
impl Player {
    pub fn new(body: Body, facing: i64) -> Self {
        Self {
            body,
            life: crate::life::Life::default(),
            tongue: crate::tongue::Tongue::default(),
            water: crate::water::Water::default(),
            food: crate::food::Food::default(),
            action_wet: 0,
            facing,
            movement: 0,
            on_floor: 0,
            support_bridge: 0,
            captured_by: 0,
            previous_input: 0,
            pressed_input: 0,
            jump_buffer: 0,
            flutter_remaining: 0,
            flutter_cooldown: 0,
            flutter_ready: 0,
            boosted_flutter: 0,
            action: 0,
            action_tick: 0,
            duck: 0,
            look: 0,
            posture_tick: 0,
            impact: 0,
            impact_x: 0,
            impact_y: 0,
            turn: 0,
            turn_ticks: 0,
            push: 0,
            pound_delay: 0,
            gravity_tick: 0,
            bounce: 0,
            brake_vx: 0,
            snow: 0,
            jump_carry: 0,
            life_phase: 0,
            life_ticks: 0,
            recovery_x: body.x - facing * 10 * S,
            recovery_y: body.y - 24 * S,
            goal_from_x: 0,
            goal_from_y: 0,
            goal_x: 0,
            goal_y: 0,
        }
    }
    /// moves.gd player_box: pose heights, empty or full mouth.
    pub fn bounds(&self) -> [i64; 4] {
        let full = self.food.full();
        let tick = self.action_tick;
        let mut height = 56;
        let mut bottom = 0;
        if self.duck != 0 {
            let heights = if full { [56, 56, 32] } else { [52, 48, 32] };
            height = heights[(self.posture_tick * 24 / 60).min(2) as usize];
        } else if [1, 2].contains(&self.action) {
            let frame = if self.action == 2 {
                6
            } else {
                (tick * 36 / 60).min(6)
            } as usize;
            height = if full {
                [52, 52, 56, 50, 48, 58, 54][frame]
            } else {
                [52, 52, 56, 50, 48, 54, 50][frame]
            };
            bottom = if full {
                [0, 4, 2, 0, 0, 2, 0][frame]
            } else {
                0
            };
        } else if self.action == 3 {
            height = if full {
                [44, 38, 40][(tick * 16 / 60).min(2) as usize]
            } else if tick < 4 {
                40
            } else {
                36
            };
        } else if self.action == 4 {
            height = if self.tongue.axis != 0 { 60 } else { 50 };
        } else if self.action == 5 {
            height = if self.tongue.axis != 0 {
                if self.action_wet != 0 {
                    54
                } else {
                    56
                }
            } else {
                50
            };
        } else if self.action == 7 {
            height = if self.tongue.axis != 0 {
                56
            } else if self.water.swimming != 0 {
                50
            } else {
                54
            };
        } else if self.action == 9 && (3..=5).contains(&tick) {
            return [-14 * S, -56 * S, 10 * S, 0];
        } else if self.action == 0 && self.water.swimming != 0 {
            if self.water.transition != 0 {
                height = [54, 50, 54][(2).min((9 - self.water.transition) * 20 / 60) as usize];
            } else if self.water.dive != 0 {
                height = if self.body.vx != 0 { 42 } else { 54 };
                bottom = if self.body.vx != 0 { 14 } else { 0 };
            }
        }
        [-12 * S, -height * S, 12 * S, bottom * S]
    }
    pub fn attach(&mut self) {
        self.recovery_x = self.body.x - self.facing * 10 * S;
        self.recovery_y = self.body.y - 24 * S;
    }
    pub(crate) fn set_action(&mut self, action: i64, sound: &mut Sound) {
        // moves.gd SOUNDING_ACTIONS: pound start, pound land, tongue, toss, head bump.
        if action != self.action && [1, 3, 4, 8, 9].contains(&action) {
            sound.player(self.body);
        }
        if self.action == 4 && action != 4 {
            self.tongue.phase = 0;
        }
        self.action = action;
        self.action_tick = 0;
        self.action_wet = self.water.swimming;
    }
    /// moves.gd interrupt(): held food and eggs stay.
    pub(crate) fn interrupt(&mut self) {
        self.action = 0;
        self.action_tick = 0;
        self.food.aim = 0;
        self.duck = 0;
        self.look = 0;
        self.turn = 0;
        self.turn_ticks = 0;
        self.tongue.length = 16 * S;
        self.tongue.phase = 0;
        self.food.swallow_queue = 0;
        self.gravity_tick = 0;
        self.jump_buffer = 0;
        self.cancel_flutter();
    }
    pub(crate) fn cancel_flutter(&mut self) {
        if self.flutter_remaining != 0 {
            self.flutter_cooldown = 17;
        }
        self.flutter_remaining = 0;
        self.bounce = 0;
    }
    fn jump(&mut self, sound: &mut Sound) {
        sound.player(self.body);
        self.body.vy = -776 * 60;
        self.on_floor = 0;
        self.jump_buffer = 0;
        self.flutter_ready = 1;
        self.pound_delay = 6;
        self.gravity_tick = 0;
        if self.action == 10 || self.action == 9 {
            self.set_action(0, sound);
        }
    }
    fn flutter(&mut self, input: u8, sound: &mut Sound) -> bool {
        if self.water.swimming != 0 || [1, 2, 3].contains(&self.action) {
            return false;
        }
        if self.flutter_remaining != 0 && self.on_floor != 0 {
            self.body.vx = self.body.vx.clamp(-256 * 60, 256 * 60);
            self.cancel_flutter();
            return true;
        }
        if self.on_floor == 0
            && self.flutter_remaining == 0
            && self.flutter_ready != 0
            && self.flutter_cooldown == 0
            && input & 4 != 0
            && self.body.vy > 192 * 60
        {
            self.flutter_remaining = if self.boosted_flutter != 0 { 51 } else { 41 };
            self.flutter_ready = 0;
            sound.player(self.body);
            self.body.vy = self.body.vy.min(392 * 60);
            self.gravity_tick = 0;
            if self.action == 9 {
                self.set_action(0, sound);
            }
        }
        if self.flutter_remaining == 0 {
            return false;
        }
        self.body.vy += ((if self.boosted_flutter != 0 {
            -424
        } else {
            -264
        }) * 60
            - self.body.vy)
            * 37649
            / 1_000_000;
        self.body.vx = self.body.vx.clamp(-256 * 60, 256 * 60);
        self.flutter_remaining -= 1;
        if self.flutter_remaining == 0 {
            self.flutter_cooldown = 17;
            self.gravity_tick = 1;
        }
        false
    }
    pub fn stomp(&mut self, enemy_vy: i64, input: u8, sound: &mut Sound) {
        self.bounce(-(enemy_vy / 2).abs() - 320 * 60, input, sound);
    }
    /// moves.gd bounce with a negative launch `velocity` (before the jump bonus).
    pub fn bounce(&mut self, velocity: i64, input: u8, sound: &mut Sound) {
        let pounding = [1, 2, 3].contains(&self.action);
        if pounding {
            self.pound_delay = 6;
        }
        if self.action != 4 {
            self.set_action(0, sound);
            if self.on_floor == 0 && self.water.swimming == 0 && !pounding {
                if self.flutter_cooldown == 1 {
                    self.flutter_cooldown = 0;
                }
                self.flutter(input, sound);
            }
            if self.flutter_remaining != 0 {
                self.bounce = 2;
            } else {
                self.cancel_flutter();
            }
        }
        self.support_bridge = 0;
        self.body.vy = velocity - if input & 4 != 0 { 384 * 60 } else { 0 };
        self.on_floor = 0;
        self.jump_buffer = 0;
        self.flutter_ready = 1;
        self.boosted_flutter = 1;
        self.gravity_tick = 0;
    }
    #[allow(clippy::too_many_arguments)]
    pub fn advance(
        &mut self,
        map: &crate::body::Probe,
        input: u8,
        pressed: u8,
        released: u8,
        frame: i64,
        rng: &mut crate::math::Rng,
        sound: &mut Sound,
    ) {
        self.pound_delay = (self.pound_delay - 1).max(0);
        self.flutter_cooldown = (self.flutter_cooldown - 1).max(0);
        self.tick_action(input, rng, sound);
        self.turn_ticks = (self.turn_ticks - 1).max(0);
        if self.turn_ticks == 0 {
            self.turn = 0;
        }
        self.tick_pound(input, sound);
        if self.life.hurt != 0 {
            self.interrupt();
        }
        let bounds = self.bounds();
        map.carry_player(&mut self.body, bounds, self.on_floor);
        let can_move = self.body.prepare(map, bounds);
        let mut support = self.body.track(map, bounds, false);
        self.on_floor = i64::from(support != 0 && self.body.vy == 0);
        let was_grounded = self.on_floor != 0;
        let carried = self.jump_carry != 0;
        self.jump_carry = 0;
        // moves.gd _snow, then water_flow.gd apply (before the player's own move).
        let snow_box = [
            self.body.x + bounds[0],
            self.body.y + bounds[1],
            self.body.x + bounds[2],
            self.body.y + bounds[3],
        ];
        self.snow = i64::from(
            crate::flow::on_snow(map, snow_box, self.snow != 0) && self.water.swimming == 0,
        );
        let flow_x = self.body.x;
        let pounding = [1, 2].contains(&self.action);
        let flow = self.flow(map, bounds, pressed, pounding);
        if self.body.x != flow_x {
            // The move starts from where the flow pushed the body.
            support = self.body.floor(map, bounds);
            self.on_floor = i64::from(support != 0 && self.body.vy == 0);
        }
        if flow != 0 {
            self.jump(sound);
            self.body.vx = flow * 400 * 60;
        }
        self.jump_buffer = if pressed & 4 != 0 {
            6
        } else {
            (self.jump_buffer - 1).max(0)
        };
        if frame <= 1 {
            self.flutter_ready = 1;
        }
        let mut release_flutter = false;
        if released & 4 != 0 {
            if self.flutter_remaining != 0 {
                release_flutter = true;
            } else if self.flutter_ready == 0 {
                self.boosted_flutter = 0;
            }
            self.flutter_ready = 1;
        } else if input & 4 == 0 && self.flutter_remaining == 0 && self.flutter_ready == 0 {
            self.flutter_ready = 1;
            self.boosted_flutter = 0;
        }
        let (bob, water_jump) = self.prepare_water(map, input, pressed);
        if released & 4 != 0 && self.body.vy < 0 {
            self.body.vy /= 4;
        }
        if water_jump {
            self.jump(sound);
        }
        if self.water.swimming != 0 {
            self.cancel_flutter();
            self.food.aim = 0;
            if [1, 2, 3].contains(&self.action) {
                self.set_action(0, sound);
            }
        }
        // move_facing.gd update: holding one direction faces it at once in the air or on
        // snow.
        let right = input & 2 != 0;
        let left = input & 1 != 0;
        let free = self.on_floor == 0 || self.snow != 0;
        let face_locked = [1, 2, 3, 4, 5, 6, 7].contains(&self.action)
            || self.food.aim != 0
            || self.water.swimming != 0
            || self.duck != 0;
        if !face_locked && right && (free && !left || self.on_floor != 0 && self.body.vx > 0) {
            self.facing = 1;
        }
        if !face_locked && left && (free && !right || self.on_floor != 0 && self.body.vx < 0) {
            self.facing = -1;
        }
        if self.life.hurt == 0 {
            self.actions(map, input, pressed, false, rng, sound);
        }
        self.update_posture(map, input, sound);
        let mut bounds = self.bounds();
        let mut jumping = carried;
        if self.water.swimming == 0
            && self.on_floor != 0
            && self.jump_buffer != 0
            && input & 4 != 0
            && !self.body.overlaps(map, NORMAL, 0, -S)
            && ![1, 2, 3].contains(&self.action)
        {
            self.jump(sound);
            jumping = true;
            bounds = self.bounds();
        }
        let lift = if self.bounce == 2 {
            self.bounce = 1;
            false
        } else {
            let lift = self.flutter(input, sound);
            if self.bounce == 1 {
                self.cancel_flutter();
                self.bounce = 0;
            }
            lift
        };
        if jumping {
            self.cancel_flutter();
            if support != 0 {
                self.body.vy = -776 * 60;
            }
        }
        if release_flutter {
            self.flutter_remaining = 0;
            self.flutter_cooldown = 17;
            self.gravity_tick = 0;
            self.boosted_flutter = 0;
        }
        let direction = if self.duck != 0 || [1, 2, 3].contains(&self.action) {
            0
        } else {
            i64::from(right) - i64::from(left)
        };
        if self.action == 1 {
            self.body.vx = 0;
            self.body.vy = 0;
        }
        let liquid = self.water.swimming != 0 || self.liquid_body(map, bounds);
        let speed = if liquid {
            200 * 60
        } else if self.snow != 0 {
            336 * 60
        } else {
            400 * 60
        };
        let deceleration = if self.life.hurt != 0 || self.water.swimming != 0 {
            self.life.hurt_deceleration
        } else if liquid {
            128
        } else if self.on_floor == 0 {
            if input & 3 != 0 {
                1296
            } else {
                0
            }
        } else if self.snow != 0 && self.facing * self.brake_vx < 0 {
            // Snow brakes lightly while the body slides against its facing; the brake is
            // chosen from the speed before the last object contact.
            256
        } else {
            1296
        };
        if [4, 5, 7, 6].contains(&self.action) {
            self.body.vx = self.body.vx.clamp(-200 * 60, 200 * 60);
        }
        let acceleration = if direction != 0 {
            (if liquid {
                256
            } else if self.snow != 0 {
                192
            } else {
                512
            }) * direction
                + if self.body.vx * direction < 0 {
                    direction * deceleration
                } else {
                    0
                }
        } else {
            0
        };
        if was_grounded
            && self.snow == 0
            && self.food.aim == 0
            && self.action == 0
            && direction * self.body.vx < -320 * 60
        {
            self.turn = direction;
            self.turn_ticks = 30;
        }
        if lift && !self.body.overlaps(map, bounds, 0, -2 * S) {
            self.body.y -= 2 * S;
            support = self.body.floor(map, bounds);
        }
        self.body.settle(map, bounds, support);
        let dx = if self.action == 1 {
            0
        } else if self.body.vx != 0 {
            (self.body.vx + acceleration / 2).clamp(-speed, speed)
        } else {
            0
        };
        let gravity = if self.water.swimming != 0
            || self.action == 1
            || self.flutter_remaining != 0 && self.bounce == 0
        {
            0
        } else {
            if self.action == 2 {
                4096
            } else {
                if self.gravity_tick != 0 && (self.action != 0 || self.food.aim != 0) {
                    self.gravity_tick = 0;
                }
                if self.gravity_tick != 0 {
                    const RECOVERY: [i64; 24] = [
                        2048, 1080, 1149, 1219, 1287, 1353, 1417, 1478, 1537, 1594, 1647, 1698,
                        1746, 1791, 1833, 1871, 1906, 1938, 1966, 1990, 2010, 2026, 2038, 2046,
                    ];
                    let index = (self.gravity_tick - 1) as usize;
                    self.gravity_tick = if index < 23 { index as i64 + 2 } else { 0 };
                    RECOVERY[index]
                } else {
                    2048
                }
            }
        };
        let cap = if self.action == 2 {
            1408 * 60
        } else {
            704 * 60
        };
        let dy = if self.action == 1 {
            0
        } else if self.body.vy != 0 {
            (self.body.vy + gravity / 2).min(cap)
        } else {
            0
        };
        if can_move {
            self.body.horizontal(
                map,
                bounds,
                dx,
                support,
                crate::body::HorizontalMove::Player { jumping },
            );
        }
        let vertical = dy + bob;
        let moved = if can_move {
            self.body
                .vertical_player(map, bounds, vertical, support, self.action == 2)
        } else {
            0
        };
        let floor = self.body.floor(map, bounds);
        self.on_floor = i64::from(
            can_move && (vertical > 0 && moved != vertical || vertical == 0 && floor != 0),
        );
        self.support_bridge = if self.on_floor != 0 { floor.max(0) } else { 0 };
        if moved != vertical && vertical < 0 && self.action == 0 && self.flutter_remaining == 0 {
            self.set_action(9, sound);
        }
        if self.on_floor != 0 {
            self.body.vy = 0;
            self.boosted_flutter = 0;
            self.gravity_tick = 0;
            if self.action == 2 {
                self.set_action(3, sound);
                self.impact += 1;
                self.impact_x = self.body.x;
                self.impact_y = self.body.y;
            } else if !was_grounded && self.action == 0 {
                self.set_action(10, sound);
            }
        } else if self.action != 1 && (support == 0 || jumping) {
            self.body.vy = (self.body.vy + gravity).min(cap);
        }
        if direction == 0 {
            self.body.vx = approach(self.body.vx, 0, deceleration);
        }
        self.body.vx = (self.body.vx + acceleration).clamp(-speed, speed);
        if self.body.vx != 0 && self.body.wall(map, bounds, self.body.vx.signum()) {
            self.body.vx = 0;
        }
        if self.turn != 0 && 0 < self.body.vx * self.turn && self.body.vx * self.turn < 64 * 60 {
            self.body.vx = self.turn * 96 * 60;
            self.turn = 0;
            self.turn_ticks = 0;
        }
        if self.water.swimming != 0 && self.food.aim == 0 && ![4, 5, 7].contains(&self.action) {
            self.facing = if self.body.vx > 0 {
                1
            } else if self.body.vx < 0 {
                -1
            } else {
                self.facing
            };
        }
        if self.water.swimming == 0
            && self.on_floor != 0
            && self.jump_buffer != 0
            && input & 4 != 0
            && !self.body.overlaps(map, NORMAL, 0, -S)
            && ![1, 2, 3].contains(&self.action)
        {
            self.jump(sound);
            self.jump_carry = 1;
        }
        self.brake_vx = self.body.vx;
        self.finish_water(map);
        self.advance_tongue(map);
    }
    pub fn finish(&mut self, map: &crate::body::Probe, input: u8) {
        let direction = i64::from(input & 2 != 0) - i64::from(input & 1 != 0);
        self.push = i64::from(
            self.on_floor != 0
                && direction != 0
                && self.body.vx == 0
                && self.body.wall(map, self.bounds(), direction),
        );
        self.movement = if self.body.vx == 0 {
            0
        } else if self.body.vx.abs() >= 320 * 60 {
            2
        } else {
            1
        };
        if self.on_floor == 0 {
            self.movement = if self.body.vy < 0 { 3 } else { 4 };
            if self.flutter_remaining != 0 {
                self.movement = 6;
            }
        }
    }
}
