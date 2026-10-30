//! Terrain-body motion. Full/top-only entity supports are not admitted yet.
use crate::{math::floor_div, Map, SCALE as S};
use std::cell::Cell;
pub(crate) struct Probe<'a> {
    map: &'a Map,
    pub terrain_queries: Cell<u64>,
}
impl<'a> Probe<'a> {
    pub fn new(map: &'a Map) -> Self {
        Self {
            map,
            terrain_queries: Cell::new(0),
        }
    }
    pub fn terrain_overlaps(&self, bounds: [i64; 4]) -> bool {
        self.terrain_queries.set(self.terrain_queries.get() + 1);
        self.map.terrain_overlaps(bounds)
    }
}
impl std::ops::Deref for Probe<'_> {
    type Target = Map;
    fn deref(&self) -> &Map {
        self.map
    }
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct Body {
    pub x: i64,
    pub y: i64,
    pub vx: i64,
    pub vy: i64,
}
#[derive(Clone, Copy, Debug)]
pub(crate) enum HorizontalMove {
    Player { jumping: bool },
    Actor,
}
impl Body {
    pub fn overlaps(&self, map: &Probe, b: [i64; 4], dx: i64, dy: i64) -> bool {
        let q = [
            self.x + b[0] + dx,
            self.y + b[1] + dy,
            self.x + b[2] + dx,
            self.y + b[3] + dy,
        ];
        map.border_overlaps(q) || map.terrain_overlaps(q)
    }
    pub fn floor(&self, map: &Probe, b: [i64; 4]) -> i64 {
        if !self.overlaps(map, b, 0, 0) && self.overlaps(map, b, 0, S) {
            -1
        } else {
            0
        }
    }
    pub fn wall(&self, map: &Probe, b: [i64; 4], direction: i64) -> bool {
        self.overlaps(map, b, direction * S, 0) && self.overlaps(map, b, direction * S, -S)
    }
    pub fn refine(&mut self, map: &Probe, b: [i64; 4], dx: i64, dy: i64) {
        let (mut sx, mut sy) = (self.x, self.y);
        let mut blocked = false;
        for divisor in [2, 4, 8, 16] {
            let offset = S / divisor * if blocked { 1 } else { -1 };
            self.x += dx * offset;
            self.y += dy * offset;
            blocked = self.overlaps(map, b, 0, 0);
            if !blocked {
                sx = self.x;
                sy = self.y;
            }
        }
        if blocked {
            self.x = sx;
            self.y = sy;
        }
    }
    pub fn push(&mut self, map: &Probe, b: [i64; 4], dx: i64, dy: i64, limit: i64) -> bool {
        let (sx, sy) = (self.x, self.y);
        let mut touched = false;
        let mut offset = 0;
        while offset < limit {
            self.x = sx + dx * offset;
            self.y = sy + dy * offset;
            if !self.overlaps(map, b, 0, 0) {
                if touched {
                    self.refine(map, b, dx, dy);
                }
                return true;
            }
            touched = true;
            offset += S;
        }
        self.x = sx;
        self.y = sy;
        false
    }
    fn push_axis(&mut self, map: &Probe, b: [i64; 4], horizontal: bool, limit: i64) -> bool {
        let (sx, sy) = (self.x, self.y);
        let mut offset = 0;
        while offset < limit {
            for dir in [-1, 1] {
                let (dx, dy) = if horizontal { (dir, 0) } else { (0, dir) };
                self.x = sx + dx * offset;
                self.y = sy + dy * offset;
                if !self.overlaps(map, b, 0, 0) {
                    self.refine(map, b, dx, dy);
                    return true;
                }
            }
            offset += S;
        }
        self.x = sx;
        self.y = sy;
        false
    }
    pub fn prepare(&mut self, map: &Probe, b: [i64; 4]) -> bool {
        if !self.overlaps(map, b, 0, 0) {
            return true;
        }
        let width = b[2] - b[0];
        let height = b[3] - b[1];
        if self.push(map, b, 0, -1, height / 8) {
            self.vy = 0;
            return true;
        }
        if self.push_axis(map, b, true, width / 2) || self.push_axis(map, b, false, height / 2) {
            return true;
        }
        let (sx, sy) = (self.x, self.y);
        let mut offset = 0;
        let mut index = 0;
        let dirs = [
            [0, -1],
            [1, -1],
            [1, 0],
            [1, 1],
            [0, 1],
            [-1, 1],
            [-1, 0],
            [-1, -1],
        ];
        while offset <= width.max(height) / 2 {
            if index == 0 {
                offset += S;
            }
            let [dx, dy] = dirs[index];
            self.x = floor_div(sx, S).unwrap_or(0) * S + dx * offset;
            self.y = floor_div(sy, S).unwrap_or(0) * S + dy * offset;
            if !self.overlaps(map, b, 0, 0) {
                return true;
            }
            index = (index + 1) % 8;
        }
        self.x = sx;
        self.y = sy;
        false
    }
    pub fn settle(&mut self, map: &Probe, b: [i64; 4], support: i64) {
        if support != 0 && self.vy > 0 {
            self.refine(map, b, 0, -1);
            self.vy = 0;
        }
    }
    pub fn horizontal(
        &mut self,
        map: &Probe,
        b: [i64; 4],
        distance: i64,
        support: i64,
        movement: HorizontalMove,
    ) -> i64 {
        let (jumping, jump_speed, touch_stops): (bool, i64, bool) = match movement {
            HorizontalMove::Player { jumping } => (jumping, 776 * 60, false),
            HorizontalMove::Actor => (false, 640 * 60, true),
        };
        if distance == 0 {
            return 0;
        }
        let (sx, sy) = (self.x, self.y);
        let direction = distance.signum();
        let wall = self.overlaps(map, b, direction * S, -S);
        self.x += distance;
        if self.overlaps(map, b, 0, 0) {
            let climb = distance.abs() + 2 * S;
            if !wall && self.push(map, b, 0, -1, climb) {
                if !jumping && self.vy.abs() < (jump_speed / 4).abs() {
                    self.vy = 0;
                }
            } else {
                let retreat = (distance.abs() * 5 / 2).max(b[2] - b[0]);
                if self.push(map, b, -direction, 0, retreat) {
                    if support < 0 {
                        let y = self.y;
                        self.y += S;
                        if !self.overlaps(map, b, 0, 0) || !self.push(map, b, 0, -1, 3 * S) {
                            self.y = y;
                        }
                    }
                } else {
                    self.x = sx;
                    self.y = sy;
                }
                self.vx = 0;
            }
        } else {
            let floor = self.floor(map, b);
            if support != 0 && floor == 0 {
                let drop = ((distance.abs() + S - 1) / S + 2) * S;
                let y = self.y;
                self.y += drop;
                if !self.overlaps(map, b, 0, 0) || !self.push(map, b, 0, -1, drop + 2 * S) {
                    self.y = y;
                }
            } else if floor != 0 && self.vy == 0 {
                self.refine(map, b, 0, -1);
            }
        }
        if touch_stops && self.vx != 0 && self.wall(map, b, self.vx.signum()) {
            self.vx = 0;
        }
        self.x - sx
    }
    pub fn vertical(&mut self, map: &Probe, b: [i64; 4], distance: i64) -> i64 {
        if distance == 0 {
            return 0;
        }
        let sy = self.y;
        self.y += distance;
        if self.overlaps(map, b, 0, 0) {
            let limit = (distance.abs() * 11 / 10).max(2 * S);
            if !self.push(map, b, 0, if distance < 0 { 1 } else { -1 }, limit) {
                self.y = sy;
            }
            self.vy = 0;
        }
        self.y - sy
    }
    pub fn gravity(&mut self, map: &Probe, b: [i64; 4], started_on_floor: bool) -> bool {
        if !self.prepare(map, b) {
            self.vy = 0;
            return false;
        }
        let support = self.floor(map, b);
        self.settle(map, b, support);
        if support != 0 && self.vy >= 0 {
            self.vy = 0;
            return true;
        }
        if self.vy == 0 && started_on_floor {
            return false;
        }
        let distance = if self.vy != 0 {
            (self.vy + 1024).min(704 * 60)
        } else {
            0
        };
        let actual = self.vertical(map, b, distance);
        let landed = distance >= 0 && (actual != distance || self.floor(map, b) != 0);
        if landed || actual != distance {
            self.vy = 0;
        }
        if !landed && support == 0 {
            self.vy = (self.vy + 2048).min(704 * 60);
        }
        landed
    }
}
