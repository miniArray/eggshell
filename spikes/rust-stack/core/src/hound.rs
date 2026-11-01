//! ride_hound.gd (o16): a friendly runner with a top-only back. It follows the player,
//! runs where its rider faces, jumps at walls, plays with resting eggs and destroys
//! enemies in its path.
use crate::{
    body::{Body, HorizontalMove, Probe},
    egg::STATIONARY,
    entity::Kind,
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
const IDLE: i64 = 0;
const WALK: i64 = 1;
const TURN: i64 = 2;
const LOOK: i64 = 3;
const PREPARE: i64 = 4;
const JUMP: i64 = 5;
const FALL: i64 = 6;
const WAGGLE: i64 = 7;
const PLAY: i64 = 8;
const NAMES: [&str; 9] = [
    "Idle",
    "Walk",
    "Turn",
    "Look",
    "PrepareJump",
    "Jump",
    "Fall",
    "Waggle",
    "Play",
];
const MAX_SPEED: i64 = 400 * 60;
const ACCELERATION: i64 = 256;
const JUMP_SPEED: i64 = 768 * 60;
const NEAR: i64 = 48 * S;
const FAR: i64 = 128 * S;
const QUEUE_TICKS: i64 = 20;
const STROKE_TICKS: i64 = 24;
const SWIM_SPEED: i64 = 200 * 60;
const LIQUID_FALL: i64 = 704 * 60 / 4;
/// Body facing left, in pixels around the origin. The back is a 60 x 16 top-only strip.
const BODY: [i64; 4] = [-34, -6, 20, 16];
/// Standing picture facing left, in pixels around the origin.
const IMAGE: [i64; 4] = [-54, -38, 24, 16];

/// ride_hound.gd POSE_TICKS
fn pose_ticks(mode: i64) -> i64 {
    match mode {
        TURN => 7,
        LOOK => 73,
        PREPARE => 8,
        WAGGLE => 63,
        PLAY => 23,
        _ => 0,
    }
}
fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Hound {
    pub request_cursor: i64,
    pub impact_cursor: i64,
    pub started: i64,
    pub spawn_x: i64,
    pub spawn_y: i64,
    pub mode: i64,
    pub timer: i64,
    pub decel: i64,
    pub ridden: i64,
    pub playing: i64,
    pub egg_token: i64,
    pub queue_turn: i64,
    pub grounded: i64,
    pub swimming: i64,
    pub stroke: i64,
    pub stroke_dir: i64,
    /// E1 "1": it never despawns (create's can_despawn 0).
    pub stays: bool,
}

impl Hound {
    /// ride_hound.gd prepare + create. `ordinal` counts this runner among the map's
    /// o16 placements so far (1 for the first): each lowers the shared deceleration.
    pub fn new(p: &Placement, ordinal: i64) -> Result<Self, Error> {
        let stays = match p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v) {
            None => false,
            Some(PropertyValue::String(s)) => s == "1",
            Some(_) => {
                return Err(Error::Unsupported {
                    requirements: vec!["o16 option E1".into()],
                })
            }
        };
        if p.variant != 0 || p.mirror != 0 || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec!["o16 option F/M/R".into()],
            });
        }
        Ok(Self {
            request_cursor: 0,
            impact_cursor: 0,
            started: 0,
            spawn_x: p.position.x,
            spawn_y: p.position.y,
            mode: IDLE,
            timer: 0,
            decel: if ordinal > 5 {
                192
            } else {
                512 - 64 * (ordinal - 1)
            },
            ridden: 0,
            playing: 0,
            egg_token: 0,
            queue_turn: 0,
            grounded: 0,
            swimming: 0,
            stroke: 0,
            stroke_dir: 1,
            stays,
        })
    }
    pub fn bounds(&self, facing: i64) -> [i64; 4] {
        if facing < 0 {
            BODY.map(|v| v * S)
        } else {
            [-BODY[2] * S, BODY[1] * S, -BODY[0] * S, BODY[3] * S]
        }
    }
    /// ride_hound.gd activation_bounds (relative): the whole standing picture.
    pub fn activation_bounds(&self, facing: i64) -> [i64; 4] {
        let b = if facing < 0 {
            IMAGE
        } else {
            [-IMAGE[2], IMAGE[1], -IMAGE[0], IMAGE[3]]
        };
        b.map(|v| v * S)
    }
    /// ride_hound.gd solid_box: the top-only back.
    pub fn solid_at(body: Body, status: i64) -> Option<[i64; 4]> {
        (status == 1).then_some([
            body.x - 30 * S,
            body.y - 32 * S,
            body.x + 30 * S,
            body.y - 16 * S,
        ])
    }
    pub fn animation(&self) -> &'static str {
        NAMES[self.mode.clamp(0, 8) as usize]
    }
    fn pose(&mut self, mode: i64) {
        self.mode = mode;
        self.timer = pose_ticks(mode);
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "hidden" | "held" | "spat" | "spit_age" | "spit_speed" | "spit_wall" | "variant"
            | "mirror" | "frozen" | "thaw_ticks" => 0,
            "request_cursor" => self.request_cursor,
            "impact_cursor" => self.impact_cursor,
            "started" => self.started,
            "spawn_x" => self.spawn_x,
            "spawn_y" => self.spawn_y,
            "mode" => self.mode,
            "timer" => self.timer,
            "decel" => self.decel,
            "ridden" => self.ridden,
            "playing" => self.playing,
            "egg_token" => self.egg_token,
            "queue_turn" => self.queue_turn,
            "grounded" => self.grounded,
            "swimming" => self.swimming,
            "stroke" => self.stroke,
            "stroke_dir" => self.stroke_dir,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "hidden" | "held" | "spat" | "spit_age" | "spit_speed" | "spit_wall" | "variant"
            | "mirror" | "frozen" | "thaw_ticks" => return value == 0,
            "request_cursor" => self.request_cursor = value,
            "impact_cursor" => self.impact_cursor = value,
            "started" => self.started = value,
            "spawn_x" => self.spawn_x = value,
            "spawn_y" => self.spawn_y = value,
            "mode" => self.mode = value,
            "timer" => self.timer = value,
            "decel" => self.decel = value,
            "ridden" => self.ridden = value,
            "playing" => self.playing = value,
            "egg_token" => self.egg_token = value,
            "queue_turn" => self.queue_turn = value,
            "grounded" => self.grounded = value,
            "swimming" => self.swimming = value,
            "stroke" => self.stroke = value,
            "stroke_dir" => self.stroke_dir = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self, body: Body) -> bool {
        (IDLE..=PLAY).contains(&self.mode)
            && (0..=73).contains(&self.timer)
            && [512, 448, 384, 320, 256, 192].contains(&self.decel)
            && [0, 1].contains(&self.ridden)
            && [0, 1].contains(&self.playing)
            && self.egg_token >= 0
            && (0..=QUEUE_TICKS).contains(&self.queue_turn)
            && [0, 1].contains(&self.grounded)
            && [0, 1].contains(&self.swimming)
            && (0..=STROKE_TICKS).contains(&self.stroke)
            && [-1, 1].contains(&self.stroke_dir)
            && body.vx.abs() <= MAX_SPEED
            && [0, 1].contains(&self.started)
            && self.request_cursor >= 0
            && self.impact_cursor >= 0
    }
}

/// enemy_motion.gd overlaps: terrain and side borders only.
fn terrain(map: &Probe, b: [i64; 4]) -> bool {
    map.border_overlaps(b) || map.terrain_overlaps(b)
}
/// ride_hound.gd _wet: water and lava are both liquids it swims in.
fn wet(map: &Probe, area: [i64; 4]) -> bool {
    map.water_overlaps(area) || map.lava_overlaps(area)
}
/// enemy_motion.gd move: (actual distance, started on a floor).
fn motion(
    body: &mut Body,
    map: &Probe,
    b: [i64; 4],
    distance: i64,
    horizontal: bool,
) -> (i64, bool) {
    if !body.prepare(map, b) {
        return (0, false);
    }
    let support = body.floor(map, b);
    if horizontal {
        let started = support != 0 && body.vy >= 0;
        (
            body.horizontal(map, b, distance, support, HorizontalMove::Actor),
            started,
        )
    } else {
        (body.vertical_support(map, b, distance, support), false)
    }
}

impl Run {
    fn hound(&mut self, index: usize) -> &mut Hound {
        match &mut self.entities[index].kind {
            Kind::Hound(h) => h,
            _ => unreachable!("hound index"),
        }
    }
    /// ride_hound.gd rider_on
    fn hound_rider_on(&self, index: usize) -> bool {
        let e = &self.entities[index];
        let Some(back) = Hound::solid_at(e.body, e.status) else {
            return false;
        };
        if self.player.captured_by != 0 || self.player.on_floor == 0 {
            return false;
        }
        let b = self.player.bounds();
        let p = self.player.body;
        p.x + b[2] > back[0]
            && p.x + b[0] < back[2]
            && p.y + b[3] + 4 * S >= back[1]
            && p.y < back[1] + 2 * S
    }
    /// ride_hound.gd _egg: the egg it plays with, while it rests.
    fn hound_egg(&self, index: usize) -> Option<usize> {
        let Kind::Hound(h) = &self.entities[index].kind else {
            return None;
        };
        if h.egg_token == 0 {
            return None;
        }
        self.find_token(h.egg_token).filter(|&i| {
            let o = &self.entities[i];
            matches!(&o.kind, Kind::Egg(g) if g.mode == STATIONARY)
                && o.status == 1
                && o.collected == 0
        })
    }
    fn egg_box(&self, egg: usize) -> [i64; 4] {
        let b = self.entities[egg].body;
        [b.x - 12 * S, b.y - 12 * S, b.x + 12 * S, b.y + 16 * S]
    }
    fn hound_egg_adjacent(&self, index: usize, egg: usize, reach: i64) -> bool {
        let e = &self.entities[index];
        let Kind::Hound(h) = &e.kind else {
            return false;
        };
        let mut body = world_box(e.body, h.bounds(e.facing));
        body[0] += e.facing * reach * S;
        body[2] += e.facing * reach * S;
        strict(body, self.egg_box(egg))
    }
    /// ride_hound.gd step.
    pub(crate) fn hound_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        // enemy_body.gd process: never held, so only the cursors move.
        let impact = self.player.impact;
        let serial = self.player.food.requests.serial();
        let status = self.entities[index].status;
        let h = self.hound(index);
        if h.started == 0 {
            h.started = 1;
            h.impact_cursor = impact;
        }
        h.request_cursor = serial;
        if status == 3 {
            return Ok(());
        }
        // ride_hound.gd step: the move uses the box of the facing before _decide (a TURN
        // that ends this step flips facing but still moves with the old box).
        let box_facing = self.entities[index].facing;
        let riding = self.hound_rider_on(index);
        let h = self.hound(index);
        if riding {
            h.ridden = 1;
            h.playing = 0;
            h.egg_token = 0;
        } else if h.ridden != 0 {
            h.ridden = 0;
        }
        let egg = self.hound_egg(index);
        let h = self.hound(index);
        if h.playing != 0 && egg.is_none() {
            h.playing = 0;
            h.egg_token = 0;
            if [WAGGLE, PLAY].contains(&h.mode) {
                h.mode = IDLE;
            }
        }
        let control = self.hound_decide(index, map, egg);
        let h = self.hound(index);
        if h.queue_turn != 0 {
            h.queue_turn -= 1;
            if h.queue_turn == 0 {
                h.pose(TURN);
            }
        }
        let riders = self.hound_riders(index);
        let start = self.entities[index].body;
        self.hound_move(index, map, control, box_facing);
        let moved = self.entities[index].body;
        if !riders.is_empty() && (moved.x != start.x || moved.y != start.y) {
            self.refresh_block_solid(index, map);
            let (dx, dy) = (moved.x - start.x, moved.y - start.y);
            for rider in riders {
                let o = &mut self.entities[rider];
                let Kind::Walker(w) = &o.kind else { continue };
                let b = w.body_bounds(o.facing);
                if dy != 0 {
                    motion(&mut o.body, map, b, dy, false);
                }
                if dx != 0 {
                    motion(&mut o.body, map, b, dx, true);
                }
                self.refresh_block_solid(rider, map);
            }
        }
        let e = &self.entities[index];
        if e.body.vx != 0 || e.body.vy != 0 {
            self.hound_destroy(index)?;
        }
        let e = &self.entities[index];
        let Kind::Hound(h) = &e.kind else {
            unreachable!()
        };
        if h.ridden == 0 && h.playing == 0 {
            self.hound_kick_eggs(index);
        }
        if self.entities[index].body.y > map.height_pixels * S + 1664 * S {
            let e = &mut self.entities[index];
            e.status = 3;
            e.can_respawn = 0;
        }
        Ok(())
    }
    /// ride_hound.gd _decide: the control direction (-1, 0, 1) for this step.
    fn hound_decide(&mut self, index: usize, map: &Probe, egg: Option<usize>) -> i64 {
        let player = self.player.body;
        let player_facing = self.player.facing;
        let e = &self.entities[index];
        let (body, facing) = (e.body, e.facing);
        let Kind::Hound(h) = &e.kind else {
            unreachable!()
        };
        let b = h.bounds(facing);
        let behind = (player.x - body.x) * facing < 0;
        let wall_ahead = terrain(
            map,
            [
                body.x + b[0] + facing * S,
                body.y + b[1] - S,
                body.x + b[2] + facing * S,
                body.y + b[3] - S,
            ],
        );
        let adjacent = |reach: i64| egg.is_some_and(|g| self.hound_egg_adjacent(index, g, reach));
        let (adjacent12, adjacent8) = (adjacent(12), adjacent(8));
        let egg_ahead = egg.map(|g| (self.entities[g].body.x - body.x) * facing);
        let egg_resting = egg.is_some_and(|g| self.entities[g].body.vy == 0);
        let mut egg_hop = false;
        let e = &mut self.entities[index];
        let Kind::Hound(h) = &mut e.kind else {
            unreachable!()
        };
        let control = match h.mode {
            TURN | LOOK | PREPARE | WAGGLE | PLAY => {
                h.timer -= 1;
                if h.timer > 0 {
                    return 0;
                }
                match h.mode {
                    TURN => {
                        e.facing = -e.facing;
                        h.pose(IDLE);
                    }
                    LOOK => {
                        e.facing = -e.facing;
                        // _player_behind with the turned facing.
                        let behind_now = (player.x - body.x) * e.facing < 0;
                        h.pose(if behind_now { LOOK } else { IDLE });
                    }
                    PREPARE => {
                        h.pose(JUMP);
                        if h.swimming != 0 {
                            e.body.vy = -JUMP_SPEED;
                        }
                    }
                    WAGGLE => {
                        if egg.is_some() && adjacent12 {
                            h.pose(PLAY);
                        } else {
                            h.playing = 0;
                            h.egg_token = 0;
                            h.pose(IDLE);
                        }
                    }
                    _ => {
                        if egg.is_some() && adjacent12 {
                            egg_hop = true;
                        }
                        h.pose(WAGGLE);
                    }
                }
                0
            }
            JUMP => {
                if h.grounded != 0 && wall_ahead {
                    e.body.vy = -JUMP_SPEED;
                    h.grounded = 0;
                } else if e.body.vy > 0 {
                    h.pose(FALL);
                }
                facing
            }
            FALL => {
                if h.grounded != 0 {
                    let look = h.ridden == 0 && behind;
                    h.pose(if look { LOOK } else { IDLE });
                    0
                } else if h.ridden != 0 {
                    facing
                } else {
                    0
                }
            }
            // Standing or walking.
            _ => {
                if (h.grounded != 0 || h.swimming != 0) && wall_ahead {
                    h.pose(PREPARE);
                    0
                } else if h.ridden != 0 {
                    if player_facing != facing {
                        if h.queue_turn == 0 {
                            h.queue_turn = QUEUE_TICKS;
                            e.body.vx /= 2;
                        }
                        0
                    } else {
                        h.mode = if h.grounded != 0 { WALK } else { FALL };
                        facing
                    }
                } else if h.playing != 0 {
                    if egg_ahead.unwrap_or(0) < 0 {
                        h.pose(TURN);
                        0
                    } else if adjacent8 && egg_resting {
                        e.body.vx = 0;
                        h.pose(WAGGLE);
                        0
                    } else {
                        h.mode = WALK;
                        facing
                    }
                } else {
                    let gap = body.x - player.x;
                    let mut result = None;
                    if gap.abs() > NEAR {
                        let toward = if gap > 0 { -1 } else { 1 };
                        if facing == toward {
                            if gap.abs() > FAR {
                                h.mode = WALK;
                                result = Some(toward);
                            }
                        } else if e.body.vx * toward >= 0 {
                            h.pose(TURN);
                            result = Some(0);
                        }
                    }
                    match result {
                        Some(control) => control,
                        None => {
                            if h.mode == WALK && e.body.vx == 0 {
                                h.pose(if behind { LOOK } else { IDLE });
                            }
                            0
                        }
                    }
                }
            }
        };
        if egg_hop {
            if let Some(g) = egg {
                let o = &mut self.entities[g];
                o.body.vy = -256 * 60;
                if let Kind::Egg(egg) = &mut o.kind {
                    egg.floating = 0;
                }
            }
        }
        control
    }
    /// ride_hound.gd _move (_run or _swim, then the liquid transition).
    fn hound_move(&mut self, index: usize, map: &Probe, control: i64, box_facing: i64) {
        let e = &mut self.entities[index];
        let Kind::Hound(h) = &mut e.kind else {
            unreachable!()
        };
        let b = h.bounds(box_facing);
        let body = &mut e.body;
        if h.swimming != 0 {
            // In liquid a pressed direction becomes a 0.4 s paddle stroke.
            if control != 0 && h.stroke == 0 {
                h.stroke = STROKE_TICKS;
                h.stroke_dir = control;
            }
            if h.stroke != 0 {
                h.stroke -= 1;
                let done = STROKE_TICKS - h.stroke;
                let span = STROKE_TICKS * STROKE_TICKS;
                let left = STROKE_TICKS - done;
                let part = if 2 * done < STROKE_TICKS {
                    2 * done * done
                } else {
                    span - 2 * left * left
                };
                body.vx = h.stroke_dir * 400 * 60 * (span - part) / span;
            } else if body.vx > 0 {
                body.vx = (body.vx - h.decel).max(0);
            } else if body.vx < 0 {
                body.vx = (body.vx + h.decel).min(0);
            }
            body.vx = body.vx.clamp(-SWIM_SPEED, SWIM_SPEED);
            let back = [
                body.x - 30 * S,
                body.y - 32 * S,
                body.x + 30 * S,
                body.y - 16 * S,
            ];
            if wet(map, back) {
                body.vy -= 256;
            } else if body.vy > 0 {
                body.vy -= 384;
            } else if ![PREPARE, JUMP].contains(&h.mode) {
                body.vy = 0;
            }
            if !wet(map, [back[0], back[1] + 6 * S, back[2], back[3] + 6 * S]) {
                body.y += 16 * 60;
            }
            // Every body in a liquid falls at most a quarter of its normal fall speed.
            body.vy = body.vy.min(LIQUID_FALL);
            let distance = body.vx;
            if distance != 0 && motion(body, map, b, distance, true).0 != distance {
                body.vx = 0;
            }
            let distance = body.vy;
            if distance != 0 && motion(body, map, b, distance, false).0 != distance {
                body.vy = 0;
            }
            h.grounded = i64::from(body.floor(map, b) != 0);
        } else {
            if control != 0 {
                body.vx = (body.vx + control * ACCELERATION).clamp(-MAX_SPEED, MAX_SPEED);
            } else if body.vx > 0 {
                body.vx = (body.vx - h.decel).max(0);
            } else if body.vx < 0 {
                body.vx = (body.vx + h.decel).min(0);
            }
            let distance = body.vx;
            let mut started = false;
            if distance != 0 {
                let (actual, s) = motion(body, map, b, distance, true);
                started = s;
                if actual != distance {
                    body.vx = 0;
                }
            }
            h.grounded = i64::from(body.gravity_box(map, b, started, 2048, 704 * 60));
        }
        // Entering or leaving a liquid is seen after the move and rules the next step.
        let area = world_box(*body, b);
        if h.swimming == 0 && wet(map, area) {
            h.swimming = 1;
            h.playing = 0;
            h.egg_token = 0;
        } else if h.swimming != 0 && !wet(map, area) {
            h.swimming = 0;
            h.stroke = 0;
        }
    }
    /// ride_hound.gd _enemy_riders: enemies standing on the back move with it.
    fn hound_riders(&self, index: usize) -> Vec<usize> {
        let e = &self.entities[index];
        let Some(back) = Hound::solid_at(e.body, e.status) else {
            return Vec::new();
        };
        self.entities
            .iter()
            .enumerate()
            .filter(|(_, o)| {
                let Kind::Walker(w) = &o.kind else {
                    return false;
                };
                // ride_hound.gd riders: registry.gd is_enemy bodies only (not e33).
                if o.status != 1 || w.held != 0 || w.hidden != 0 || o.body.vy < 0 || !o.is_enemy() {
                    return false;
                }
                let b = world_box(o.body, w.body_bounds(o.facing));
                b[3] <= back[1] && b[3] >= back[1] - S && b[0] < back[2] && b[2] > back[0]
            })
            .map(|(i, _)| i)
            .collect()
    }
    /// ride_hound.gd _destroy_enemies: a moving runner removes every active enemy it
    /// touches.
    fn hound_destroy(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        let Kind::Hound(h) = &e.kind else {
            return Ok(());
        };
        let body = world_box(e.body, h.bounds(e.facing));
        let targets: Vec<usize> = self
            .entities
            .iter()
            .enumerate()
            .filter(|(_, o)| {
                let Kind::Walker(w) = &o.kind else {
                    return false;
                };
                // ride_hound.gd _destroy_enemies: registry.gd is_enemy bodies only (a
                // gust_flyer.gd e33 is not an enemy).
                o.status == 1
                    && o.is_enemy()
                    && w.held == 0
                    && w.hidden == 0
                    && strict(body, world_box(o.body, w.bounds(o.body, o.facing)))
            })
            .map(|(i, _)| i)
            .collect();
        for target in targets {
            // Body.remove runs actor.gd on_remove (the capturing e5 lets go).
            self.shell_remove(target);
        }
        Ok(())
    }
    /// ride_hound.gd _kick_eggs: a free runner kicks the first resting egg it touches.
    fn hound_kick_eggs(&mut self, index: usize) {
        let e = &self.entities[index];
        let Kind::Hound(h) = &e.kind else { return };
        let body = world_box(e.body, h.bounds(e.facing));
        let x = e.body.x;
        let found = (0..self.entities.len()).find(|&i| {
            let o = &self.entities[i];
            matches!(&o.kind, Kind::Egg(g) if g.mode == STATIONARY)
                && o.status == 1
                && o.collected == 0
                && strict(body, self.egg_box(i))
        });
        let Some(egg) = found else { return };
        let o = &mut self.entities[egg];
        o.body.vy = -448 * 60;
        o.body.vx = if o.body.x < x { -384 } else { 384 } * 60;
        if let Kind::Egg(g) = &mut o.kind {
            g.floating = 0;
        }
        let token = o.origin.token();
        let h = self.hound(index);
        h.playing = 1;
        h.egg_token = token;
    }
}
