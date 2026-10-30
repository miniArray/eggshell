//! Required pickup/health-drop rules. Mutable fields are typed, never codec arrays.
macro_rules! codec_fields {($ty:ident,$($field:ident),*$(,)?)=>{impl $ty{pub fn field(&self,n:&str)->Option<i64>{Some(match n{$(stringify!($field)=>self.$field,)*_=>return None})}pub fn set_field(&mut self,n:&str,value:i64)->bool{match n{$(stringify!($field)=>{self.$field=value;true},)*_=>false}}}};}
use crate::{
    body::{Body, Probe},
    math::{approach, sine},
    polygon, Position, SCALE as S,
};
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum PickupKind {
    Coin,
    RedCoin,
    Flower,
}
#[derive(Clone, Debug)]
pub(crate) struct Pickup {
    pub kind: PickupKind,
    pub dotted: i64,
    pub enabled: i64,
    pub collect_ticks: i64,
    pub collect_y: i64,
    pub phase: i64,
    pub moving: i64,
    pub bounce_done: i64,
    pub pickup_delay: i64,
    pub despawn_ticks: i64,
    pub held: i64,
    pub request_cursor: i64,
    pub origin_token: i64,
}
impl Pickup {
    pub fn new(kind: PickupKind, variant: i64, y: i64) -> Self {
        let dotted = i64::from(kind != PickupKind::Flower && variant == 1);
        Self {
            kind,
            dotted,
            enabled: 1 - dotted,
            collect_ticks: 0,
            collect_y: y,
            phase: 0,
            moving: 0,
            bounce_done: 0,
            pickup_delay: 0,
            despawn_ticks: 0,
            held: 0,
            request_cursor: 0,
            origin_token: 0,
        }
    }
    pub fn bounds(&self) -> [i64; 4] {
        if self.kind == PickupKind::Flower {
            [-32 * S, -32 * S, 32 * S, 32 * S]
        } else {
            let w = [12, 8, 4, 8][(self.phase * 8 / 60 % 4) as usize] * S;
            [-w, -16 * S, w, 16 * S]
        }
    }
    pub fn advance(&mut self, body: &mut Body, status: &mut i64, collected: i64, map: &Probe) {
        self.phase = (self.phase + 1) % 60;
        if self.collect_ticks != 0 {
            self.collect_ticks -= 1;
            body.y = self.collect_y
                - sine(60 - self.collect_ticks, 240, 96 * S).expect("bounded pickup tween");
            if self.collect_ticks == 0 {
                *status = 3;
            }
        } else if self.moving != 0 && collected == 0 {
            self.pickup_delay = (self.pickup_delay - 1).max(0);
            body.vx = approach(body.vx, 0, 128);
            if body.fall_item(map, self.bounds(), 2048, 704 * 60, false) {
                if self.kind == PickupKind::RedCoin {
                    body.vy = -192 * 60;
                } else if self.bounce_done == 0 {
                    body.vy = -384 * 60;
                }
                self.bounce_done = 1;
            }
            if self.despawn_ticks != 0 {
                self.despawn_ticks -= 1;
                if self.despawn_ticks == 0 {
                    *status = 3;
                }
            }
        }
    }
    pub fn touches(&self, body: Body, collected: i64, box_: [i64; 4]) -> bool {
        if collected != 0 || self.enabled == 0 || self.held != 0 || self.pickup_delay != 0 {
            return false;
        }
        let b = self.bounds();
        if body.x + b[2] <= box_[0]
            || body.x + b[0] >= box_[2]
            || body.y + b[3] <= box_[1]
            || body.y + b[1] >= box_[3]
        {
            return false;
        }
        if self.kind != PickupKind::Flower {
            return true;
        }
        let angle = sine(self.phase, 60, 10000).expect("bounded flower sway");
        let sin = sine((angle + 360000) % 360000, 360000, S).expect("bounded flower angle");
        let cos = sine((angle + 450000) % 360000, 360000, S).expect("bounded flower angle");
        let source = [
            [-22, -22],
            [0, -32],
            [21, -22],
            [31, 0],
            [23, 23],
            [0, 31],
            [-22, 21],
            [-32, 0],
        ];
        let points: Vec<_> = source
            .into_iter()
            .map(|[x, y]| Position {
                x: x * cos - y * sin,
                y: x * sin + y * cos,
            })
            .collect();
        polygon::overlaps_box(
            &points,
            [
                box_[0] - body.x,
                box_[1] - body.y,
                box_[2] - body.x,
                box_[3] - body.y,
            ],
        )
    }
    pub fn valid(&self) -> bool {
        [
            self.dotted,
            self.enabled,
            self.moving,
            self.bounce_done,
            self.held,
        ]
        .iter()
        .all(|v| [0, 1].contains(v))
            && (0..=60).contains(&self.collect_ticks)
            && (0..60).contains(&self.phase)
            && self.pickup_delay >= 0
            && self.despawn_ticks >= 0
            && self.request_cursor >= 0
            && self.origin_token >= 0
    }
}
codec_fields!(
    Pickup,
    dotted,
    enabled,
    collect_ticks,
    collect_y,
    phase,
    moving,
    bounce_done,
    pickup_delay,
    despawn_ticks,
    held,
    request_cursor,
    origin_token
);
#[derive(Clone, Debug)]
pub(crate) struct Star {
    pub held: i64,
    pub request_cursor: i64,
    pub pickup_delay: i64,
    pub despawn_ticks: i64,
    pub max_speed: i64,
    pub wait_for_land: i64,
    pub phase: i64,
    pub ignore_terrain: i64,
    pub origin_token: i64,
}
codec_fields!(
    Star,
    held,
    request_cursor,
    pickup_delay,
    despawn_ticks,
    max_speed,
    wait_for_land,
    phase,
    ignore_terrain,
    origin_token
);
impl Default for Star {
    fn default() -> Self {
        Self {
            held: 0,
            request_cursor: 0,
            pickup_delay: 0,
            despawn_ticks: 0,
            max_speed: 64 * 60,
            wait_for_land: 0,
            phase: 0,
            ignore_terrain: 0,
            origin_token: 0,
        }
    }
}
impl Star {
    pub fn bounds(&self) -> [i64; 4] {
        if self.phase >= 10 {
            [-12 * S, -18 * S, 12 * S, 16 * S]
        } else {
            [-12 * S, -20 * S, 12 * S, 14 * S]
        }
    }
    pub fn advance(
        &mut self,
        body: &mut Body,
        facing: &mut i64,
        status: &mut i64,
        player_x: i64,
        map: &Probe,
    ) {
        self.phase = (self.phase + 1).min(15);
        self.pickup_delay = (self.pickup_delay - 1).max(0);
        if self.despawn_ticks != 0 {
            self.despawn_ticks -= 1;
            if self.despawn_ticks == 0 {
                *status = 3;
                return;
            }
        }
        let b = self.bounds();
        if self.wait_for_land == 0 && self.ignore_terrain == 0 {
            if body.wall(map, b, *facing) {
                *facing = -*facing;
            }
            body.vx = approach(body.vx, *facing * self.max_speed, 512);
        }
        if body.fall_item(map, b, 1024, 704 * 60, self.ignore_terrain != 0) {
            body.vy = -288 * 60;
            self.max_speed = 64 * 60;
            self.phase = 0;
            if self.wait_for_land != 0 {
                self.wait_for_land = 0;
                *facing = if player_x < body.x { -1 } else { 1 };
            }
        }
    }
    pub fn valid(&self) -> bool {
        [self.held, self.wait_for_land, self.ignore_terrain]
            .iter()
            .all(|v| [0, 1].contains(v))
            && self.request_cursor >= 0
            && self.pickup_delay >= 0
            && self.despawn_ticks >= 0
            && (0..=128 * 60).contains(&self.max_speed)
            && (0..=15).contains(&self.phase)
            && self.origin_token >= 0
    }
}
