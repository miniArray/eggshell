//! Integer terrain and immutable legacy bridge motion. Entity solids remain a separate gate.
use crate::{math::floor_div, Map, SCALE as S};
use std::cell::Cell;
pub(crate) struct Probe<'a> {
    map: &'a Map,
    pub terrain_queries: Cell<u64>,
    polygon: Option<&'a [crate::Position]>,
    parent_counter: Option<&'a Cell<u64>>,
}
impl<'a> Probe<'a> {
    pub fn new(map: &'a Map) -> Self {
        Self {
            map,
            terrain_queries: Cell::new(0),
            polygon: None,
            parent_counter: None,
        }
    }
    pub fn with_polygon<'b>(&'b self, points: &'b [crate::Position]) -> Probe<'b> {
        Probe {
            map: self.map,
            terrain_queries: Cell::new(0),
            polygon: Some(points),
            parent_counter: Some(&self.terrain_queries),
        }
    }
    pub(crate) fn support_in_box(&self, bounds: [i64; 4]) -> bool {
        self.terrain_overlaps(bounds)
            || self.border_overlaps(bounds)
            || self.bridges.iter().any(|b| {
                bounds[1] <= b.top
                    && bounds[3] >= b.top
                    && bounds[2] >= b.left
                    && bounds[0] <= b.right
            })
    }
    pub fn terrain_overlaps(&self, bounds: [i64; 4]) -> bool {
        self.terrain_queries.set(self.terrain_queries.get() + 1);
        self.map.terrain_overlaps(bounds)
    }
}
impl Drop for Probe<'_> {
    fn drop(&mut self) {
        if let Some(parent) = self.parent_counter {
            parent.set(parent.get() + self.terrain_queries.get());
        }
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
        let border = map.border_overlaps(q);
        if !border && !map.terrain_overlaps(q) {
            return false;
        }
        if let Some(polygon) = map.polygon {
            if border {
                return true;
            }
            let points: Vec<_> = polygon
                .iter()
                .map(|p| crate::Position {
                    x: p.x + self.x + dx,
                    y: p.y + self.y + dy,
                })
                .collect();
            map.terrain_queries.set(map.terrain_queries.get() + 1);
            map.map.terrain_polygon_overlaps(&points, q)
        } else {
            true
        }
    }
    fn bridge_overlap(
        &self,
        bridge: &crate::BridgeGeometry,
        b: [i64; 4],
        dx: i64,
        dy: i64,
    ) -> bool {
        self.x + b[2] + dx >= bridge.left
            && self.x + b[0] + dx <= bridge.right
            && self.y + b[3] + dy >= bridge.top
            && self.y + b[1] + dy <= bridge.top + 2 * S
    }
    fn bridges_at(&self, map: &Probe, b: [i64; 4]) -> Vec<i64> {
        map.bridges
            .iter()
            .enumerate()
            .filter_map(|(index, bridge)| {
                self.bridge_overlap(bridge, b, 0, 0)
                    .then_some(index as i64 + 1)
            })
            .collect()
    }
    fn overlaps_support(&self, map: &Probe, b: [i64; 4], support: i64) -> bool {
        self.overlaps(map, b, 0, 0)
            || support > 0 && self.bridge_overlap(&map.bridges[support as usize - 1], b, 0, 0)
    }
    pub fn floor(&self, map: &Probe, b: [i64; 4]) -> i64 {
        if self.overlaps(map, b, 0, 0) {
            return 0;
        }
        if self.overlaps(map, b, 0, S) {
            return -1;
        }
        for (index, bridge) in map.bridges.iter().enumerate() {
            if self.y + b[3] <= bridge.top && self.bridge_overlap(bridge, b, 0, S) {
                return index as i64 + 1;
            }
        }
        0
    }
    pub fn track(&mut self, map: &Probe, b: [i64; 4], settle: bool) -> i64 {
        let support = self.floor(map, b);
        if support > 0 && self.y + b[3] == map.bridges[support as usize - 1].top {
            self.push_support(map, b, 0, -1, 2 * S, support);
        }
        if settle {
            self.settle(map, b, support);
        }
        support
    }
    pub fn wall(&self, map: &Probe, b: [i64; 4], direction: i64) -> bool {
        self.wall_probe(map, b, direction, 1, 1)
    }
    pub fn wall_probe(
        &self,
        map: &Probe,
        b: [i64; 4],
        direction: i64,
        reach: i64,
        lift: i64,
    ) -> bool {
        self.overlaps(map, b, direction * reach * S, 0)
            && self.overlaps(map, b, direction * reach * S, -lift * S)
    }
    pub fn refine(&mut self, map: &Probe, b: [i64; 4], dx: i64, dy: i64) {
        self.refine_support(map, b, dx, dy, 0);
    }
    fn refine_support(&mut self, map: &Probe, b: [i64; 4], dx: i64, dy: i64, support: i64) {
        let (mut sx, mut sy) = (self.x, self.y);
        let mut blocked = false;
        for divisor in [2, 4, 8, 16] {
            let offset = S / divisor * if blocked { 1 } else { -1 };
            self.x += dx * offset;
            self.y += dy * offset;
            blocked = self.overlaps_support(map, b, support);
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
        self.push_support(map, b, dx, dy, limit, 0)
    }
    fn push_support(
        &mut self,
        map: &Probe,
        b: [i64; 4],
        dx: i64,
        dy: i64,
        limit: i64,
        support: i64,
    ) -> bool {
        let (sx, sy) = (self.x, self.y);
        let mut touched = false;
        let mut offset = 0;
        while offset < limit {
            self.x = sx + dx * offset;
            self.y = sy + dy * offset;
            if !self.overlaps_support(map, b, support) {
                if touched {
                    self.refine_support(map, b, dx, dy, support);
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
            self.refine_support(map, b, 0, -1, support.max(0));
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
        let old_bridges = self.bridges_at(map, b);
        let wall = self.overlaps(map, b, direction * S, -S);
        self.x += distance;
        let obstacle = self.overlaps(map, b, 0, 0);
        let bridge = if !obstacle && support > 0 {
            self.bridges_at(map, b)
                .into_iter()
                .find(|index| !old_bridges.contains(index))
                .unwrap_or(0)
        } else {
            0
        };
        if obstacle || bridge != 0 {
            let climb = distance.abs() + 2 * S;
            if !wall && self.push_support(map, b, 0, -1, climb, bridge) {
                if !jumping && self.vy.abs() < (jump_speed / 4).abs() {
                    self.vy = 0;
                }
            } else {
                let retreat = (distance.abs() * 5 / 2).max(b[2] - b[0]);
                if self.push(map, b, -direction, 0, retreat) {
                    if support < 0 && bridge == 0 {
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
                if bridge == 0 {
                    self.vx = 0;
                }
            }
        } else {
            let floor = self.floor(map, b);
            if support != 0 && floor == 0 {
                let drop = ((distance.abs() + S - 1) / S + 2) * S;
                let y = self.y;
                self.y += drop;
                let mut snapped = false;
                for index in self.bridges_at(map, b) {
                    if !old_bridges.contains(&index)
                        && self.push_support(map, b, 0, -1, drop + 2 * S, index)
                    {
                        snapped = true;
                        break;
                    }
                }
                if !snapped
                    && (!self.overlaps(map, b, 0, 0) || !self.push(map, b, 0, -1, drop + 2 * S))
                {
                    self.y = y;
                }
            } else if floor != 0 && self.vy == 0 {
                self.refine_support(map, b, 0, -1, floor.max(0));
            }
        }
        if touch_stops && self.vx != 0 && self.wall(map, b, self.vx.signum()) {
            self.vx = 0;
        }
        self.x - sx
    }
    pub fn vertical(&mut self, map: &Probe, b: [i64; 4], distance: i64) -> i64 {
        self.vertical_support(map, b, distance, 0)
    }
    pub fn vertical_support(
        &mut self,
        map: &Probe,
        b: [i64; 4],
        distance: i64,
        support: i64,
    ) -> i64 {
        if distance == 0 {
            return 0;
        }
        let sy = self.y;
        let old_bridges = self.bridges_at(map, b);
        self.y += distance;
        let obstacle = self.overlaps(map, b, 0, 0);
        let bridge = if !obstacle && distance > 0 && support == 0 {
            self.bridges_at(map, b)
                .into_iter()
                .find(|index| !old_bridges.contains(index))
                .unwrap_or(0)
        } else {
            0
        };
        if obstacle || bridge != 0 {
            let limit = (distance.abs() * if bridge != 0 { 20 } else { 11 } / 10).max(2 * S);
            if !self.push_support(map, b, 0, if distance < 0 { 1 } else { -1 }, limit, bridge) {
                self.y = sy;
            }
            self.vy = 0;
        }
        self.y - sy
    }
    pub fn fall_item(
        &mut self,
        map: &Probe,
        b: [i64; 4],
        gravity: i64,
        max_fall: i64,
        ignore_terrain: bool,
    ) -> bool {
        if ignore_terrain {
            self.vy = (self.vy + gravity).min(max_fall);
            self.x += self.vx;
            self.y += self.vy;
            return false;
        }
        if !self.prepare(map, b) {
            self.vx = 0;
            self.vy = 0;
            return false;
        }
        let support = self.track(map, b, true);
        let grounded = support != 0 && self.vy >= 0;
        if grounded {
            self.vy = 0;
        } else {
            self.vy = (self.vy + gravity).min(max_fall);
        }
        self.horizontal(map, b, self.vx, support, HorizontalMove::Actor);
        let desired = self.vy;
        let actual = self.vertical_support(map, b, desired, support);
        let landed = desired >= 0 && (actual != desired || self.floor(map, b) != 0);
        if actual != desired || landed {
            self.vy = 0;
        }
        grounded || landed
    }
    pub fn gravity(&mut self, map: &Probe, b: [i64; 4], started_on_floor: bool) -> bool {
        if !self.prepare(map, b) {
            self.vy = 0;
            return false;
        }
        let support = self.track(map, b, true);
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
        let actual = self.vertical_support(map, b, distance, support);
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
