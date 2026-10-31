//! Integer terrain, legacy bridges and the admitted entity-solid projection.
use crate::{math::floor_div, Map, SCALE as S};
use std::cell::{Cell, RefCell};
pub(crate) struct Probe<'a> {
    map: &'a Map,
    pub terrain_queries: Cell<u64>,
    polygon: Option<&'a [crate::Position]>,
    solids: Option<&'a RefCell<crate::solids::SolidFrame>>,
    parent_counter: Option<&'a Cell<u64>>,
}
impl<'a> Probe<'a> {
    pub fn new(map: &'a Map) -> Self {
        Self {
            map,
            terrain_queries: Cell::new(0),
            polygon: None,
            solids: None,
            parent_counter: None,
        }
    }
    pub fn with_solids(map: &'a Map, solids: &'a RefCell<crate::solids::SolidFrame>) -> Self {
        let mut probe = Self::new(map);
        probe.solids = Some(solids);
        probe
    }
    pub fn bump_blocks(&self, body: &Body, bounds: [i64; 4], previous_edge: i64) {
        if let Some(frame) = self.solids {
            frame.borrow_mut().bump_below(body, bounds, previous_edge);
        }
    }
    pub fn head_bumps(&self) -> Vec<i64> {
        self.solids
            .map(|f| f.borrow_mut().take_head_bumps())
            .unwrap_or_default()
    }
    pub fn refresh_solid(
        &self,
        token: i64,
        position: crate::Position,
        live_box: Option<[i64; 4]>,
        region: [i64; 4],
    ) {
        if let Some(frame) = self.solids {
            frame
                .borrow_mut()
                .refresh(token, position, live_box, region);
        }
    }
    pub fn pound_posts(&self, body: &mut Body, bounds: [i64; 4], previous_edge: i64) {
        if let Some(frame) = self.solids {
            frame.borrow_mut().pound(self, body, bounds, previous_edge);
        }
    }
    #[cfg(test)]
    pub fn solid_trace(
        &self,
        saved_frame: i64,
        body: Body,
        bounds: [i64; 4],
    ) -> crate::solids::SolidTrace {
        let floor = body.floor(self, bounds);
        self.solids
            .map(|f| {
                let positions = f.borrow().probe_positions();
                let points = [
                    [-22, -52],
                    [0, -60],
                    [22, -52],
                    [30, -30],
                    [22, -8],
                    [0, 0],
                    [-22, -8],
                    [-30, -30],
                ]
                .map(|p| crate::Position {
                    x: p[0] * S,
                    y: p[1] * S,
                });
                let probe = self.with_polygon(&points);
                let hits = positions
                    .into_iter()
                    .map(|p| {
                        Body {
                            x: p.x,
                            y: p.y,
                            ..Body::default()
                        }
                        .overlaps(
                            &probe,
                            [-30 * S, -60 * S, 30 * S, 0],
                            0,
                            0,
                        )
                    })
                    .collect();
                f.borrow().trace(saved_frame, floor, hits)
            })
            .unwrap_or_default()
    }
    pub fn post_updates(&self) -> Vec<crate::solids::PostUpdate> {
        self.solids
            .map(|f| f.borrow_mut().take_updates())
            .unwrap_or_default()
    }
    /// collision.gd _selected.
    pub fn selected(&self, handle: i64) -> Option<crate::solids::Shape> {
        self.solids.and_then(|s| s.borrow().selected(handle))
    }
    /// collision.gd _one_way: a map bridge, or a top-only entity shape.
    pub fn one_way(&self, support: i64) -> bool {
        support > 0 || self.selected(support).is_some_and(|s| s.mode == 2)
    }
    pub fn solid_shapes(&self, probe: [i64; 4]) -> Vec<crate::solids::Shape> {
        self.solids
            .map(|s| s.borrow_mut().shapes(probe))
            .unwrap_or_default()
    }
    pub fn carry_player(&self, body: &mut Body, bounds: [i64; 4], on_floor: i64) {
        let Some(frame) = self.solids else {
            return;
        };
        let carried = frame.borrow_mut().carry(body, bounds, on_floor);
        if let Some((dx, dy)) = carried {
            if (dx != 0 || dy != 0) && body.overlaps(self, bounds, 0, 0) {
                self.carry_retreat(body, bounds, dx, dy);
            }
        }
    }
    /// collision.gd _carry_retreat: back along the carry until the body is free, then
    /// refine to a sixteenth of a pixel; a body never freed returns to where it was.
    fn carry_retreat(&self, body: &mut Body, bounds: [i64; 4], dx: i64, dy: i64) {
        let length = crate::math::root(dx * dx + dy * dy);
        let (start_x, start_y) = (body.x, body.y);
        let mut last_blocked = 0;
        let mut distance = 0;
        while distance < length * 5 / 2 {
            body.x = start_x - dx * distance / length;
            body.y = start_y - dy * distance / length;
            if !body.overlaps(self, bounds, 0, 0) {
                let mut safe = distance;
                let mut blocked = false;
                let mut position = distance;
                for divisor in [2, 4, 8, 16] {
                    position += S / divisor * if blocked { 1 } else { -1 };
                    position = position.max(last_blocked);
                    body.x = start_x - dx * position / length;
                    body.y = start_y - dy * position / length;
                    blocked = body.overlaps(self, bounds, 0, 0);
                    if !blocked {
                        safe = position;
                    }
                }
                body.x = start_x - dx * safe / length;
                body.y = start_y - dy * safe / length;
                return;
            }
            last_blocked = distance;
            distance += S;
        }
        body.x = start_x;
        body.y = start_y;
    }
    pub fn with_polygon<'b>(&'b self, points: &'b [crate::Position]) -> Probe<'b> {
        Probe {
            map: self.map,
            terrain_queries: Cell::new(0),
            polygon: Some(points),
            solids: self.solids,
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
            || self.solids.is_some_and(|s| s.borrow_mut().touches(bounds))
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
    Item,
}
impl Body {
    fn shape_overlap(&self, b: [i64; 4], shape: &crate::solids::Shape, dx: i64, dy: i64) -> bool {
        // The optional body polygon restricts terrain only; original _box_overlap is AABB,
        // then a turned solid's own narrow phase (solid_touches).
        shape.touches([
            self.x + b[0] + dx,
            self.y + b[1] + dy,
            self.x + b[2] + dx,
            self.y + b[3] + dy,
        ])
    }
    pub fn overlaps(&self, map: &Probe, b: [i64; 4], dx: i64, dy: i64) -> bool {
        if self.terrain_at(map, b, dx, dy) {
            return true;
        }
        let q = [
            self.x + b[0] + dx,
            self.y + b[1] + dy,
            self.x + b[2] + dx,
            self.y + b[3] + dy,
        ];
        map.solid_shapes(q)
            .into_iter()
            .any(|s| s.mode == 1 && self.shape_overlap(b, &s, dx, dy))
    }
    fn terrain_at(&self, map: &Probe, b: [i64; 4], dx: i64, dy: i64) -> bool {
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
        let mut found: Vec<i64> = map
            .bridges
            .iter()
            .enumerate()
            .filter_map(|(index, bridge)| {
                self.bridge_overlap(bridge, b, 0, 0)
                    .then_some(index as i64 + 1)
            })
            .collect();
        let q = [self.x + b[0], self.y + b[1], self.x + b[2], self.y + b[3]];
        for shape in map.solid_shapes(q) {
            if shape.mode == 2 && self.shape_overlap(b, &shape, 0, 0) {
                found.push(shape.handle);
            }
        }
        found
    }
    fn overlaps_support(&self, map: &Probe, b: [i64; 4], support: i64) -> bool {
        self.overlaps(map, b, 0, 0)
            || support > 0 && self.bridge_overlap(&map.bridges[support as usize - 1], b, 0, 0)
            || support <= -2
                && map
                    .selected(support)
                    .is_some_and(|s| self.shape_overlap(b, &s, 0, 0))
    }
    pub fn floor(&self, map: &Probe, b: [i64; 4]) -> i64 {
        if self.overlaps(map, b, 0, 0) {
            return 0;
        }
        if self.terrain_at(map, b, 0, S) {
            return -1;
        }
        let below = [
            self.x + b[0],
            self.y + b[1] + S,
            self.x + b[2],
            self.y + b[3] + S,
        ];
        let shapes = map.solid_shapes(below);
        for shape in &shapes {
            if shape.mode == 1 && self.shape_overlap(b, shape, 0, S) {
                return shape.handle;
            }
        }
        for (index, bridge) in map.bridges.iter().enumerate() {
            if self.y + b[3] <= bridge.top && self.bridge_overlap(bridge, b, 0, S) {
                return index as i64 + 1;
            }
        }
        for shape in &shapes {
            if shape.mode == 2
                && self.y + b[3] <= shape.box_[1]
                && self.shape_overlap(b, shape, 0, S)
            {
                return shape.handle;
            }
        }
        0
    }
    pub fn track(&mut self, map: &Probe, b: [i64; 4], settle: bool) -> i64 {
        let support = self.floor(map, b);
        let top = if support > 0 {
            map.bridges[support as usize - 1].top
        } else {
            map.selected(support).map_or(0, |s| s.box_[1])
        };
        if map.one_way(support) && self.y + b[3] == top {
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
            let one_way = if map.one_way(support) { support } else { 0 };
            self.refine_support(map, b, 0, -1, one_way);
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
            // collision.gd horizontal defaults (thrown and skipping eggs).
            HorizontalMove::Item => (false, 776 * 60, true),
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
        let bridge = if !obstacle && map.one_way(support) {
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
                    if support < 0 && !map.one_way(support) && bridge == 0 {
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
                let one_way = if map.one_way(floor) { floor } else { 0 };
                self.refine_support(map, b, 0, -1, one_way);
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
        self.vertical_move(map, b, distance, support, false, false)
    }
    pub fn vertical_player(
        &mut self,
        map: &Probe,
        b: [i64; 4],
        distance: i64,
        support: i64,
        pounding: bool,
    ) -> i64 {
        self.vertical_move(map, b, distance, support, pounding, true)
    }
    fn vertical_move(
        &mut self,
        map: &Probe,
        b: [i64; 4],
        distance: i64,
        support: i64,
        pounding: bool,
        player: bool,
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
        // collision.gd vertical: _bump side 0 on the way up (the player only).
        if player && distance < 0 {
            map.bump_blocks(self, b, sy + b[1]);
        }
        if pounding && distance > 0 {
            map.pound_posts(self, b, sy + b[3]);
        }
        // collision.gd vertical: a top-only shape gone since it was found is no support.
        let bridge = if bridge < 0 && map.selected(bridge).is_none() {
            0
        } else {
            bridge
        };
        let obstacle = if pounding && distance > 0 {
            self.overlaps(map, b, 0, 0)
        } else {
            obstacle
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
        self.gravity_box(map, b, started_on_floor, 2048, 704 * 60)
    }
    /// enemy_motion.gd gravity_box: water quarters the acceleration and the cap.
    pub fn gravity_box(
        &mut self,
        map: &Probe,
        b: [i64; 4],
        started_on_floor: bool,
        acceleration: i64,
        cap: i64,
    ) -> bool {
        if !self.prepare(map, b) {
            self.vy = 0;
            return false;
        }
        let (acceleration, cap) =
            if map.water_overlaps([self.x + b[0], self.y + b[1], self.x + b[2], self.y + b[3]]) {
                (acceleration / 4, cap / 4)
            } else {
                (acceleration, cap)
            };
        let support = self.track(map, b, true);
        if support != 0 && self.vy >= 0 {
            self.vy = 0;
            return true;
        }
        if self.vy == 0 && started_on_floor {
            return false;
        }
        let distance = if self.vy != 0 {
            (self.vy + acceleration / 2).min(cap)
        } else {
            0
        };
        let actual = self.vertical_support(map, b, distance, support);
        let landed = distance >= 0 && (actual != distance || self.floor(map, b) != 0);
        if landed || actual != distance {
            self.vy = 0;
        }
        if !landed && support == 0 {
            self.vy = (self.vy + acceleration).min(cap);
        }
        landed
    }
}
