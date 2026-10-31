//! Level-wide request consumers (registry.gd consume_requests, before entity consumers):
//! item_egg.gd egg inventory and throws, seed_shot.gd seeds, element_shot.gd fire/ice.
use crate::{
    food::{Since, COLD, EGG, HEAT, STORED_EGG},
    math::sine,
    Error,
};

/// What the run must do after the level consumers, in order.
pub(crate) enum Action {
    Spawn(crate::egg::Spawn),
    MarkOrigin(i64),
    /// seed_shot.gd: a runtime seed at x, y heading along the request angle.
    Seed(i64, i64, i64),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Consumers {
    pub egg_cursor: i64,
    pub colour: [i64; 6],
    pub origin: [i64; 6],
    pub ghost: [i64; 6],
    pub seed_cursor: i64,
    pub element_cursor: i64,
}

impl Default for Consumers {
    fn default() -> Self {
        Self {
            egg_cursor: 0,
            colour: [-1; 6],
            origin: [0; 6],
            ghost: [0; 6],
            seed_cursor: 0,
            element_cursor: 0,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Egg {
    colour: i64,
    origin: i64,
    ghost: i64,
}

fn unsupported(reason: &str) -> Error {
    Error::Unsupported {
        requirements: vec![reason.into()],
    }
}

impl Consumers {
    fn inventory(&self) -> Vec<Egg> {
        (0..6)
            .filter(|&slot| self.colour[slot] >= 0)
            .map(|slot| Egg {
                colour: self.colour[slot],
                origin: self.origin[slot],
                ghost: self.ghost[slot],
            })
            .collect()
    }
    fn write(&mut self, queue: &[Egg]) {
        for slot in 0..6 {
            let egg = queue.get(slot);
            self.colour[slot] = egg.map_or(-1, |e| e.colour);
            self.origin[slot] = egg.map_or(0, |e| e.origin);
            self.ghost[slot] = egg.map_or(0, |e| e.ghost);
        }
    }
    fn normalize(&mut self, count: i64) {
        let mut queue = self.inventory();
        let target = count.clamp(0, 6) as usize;
        queue.truncate(target);
        while queue.len() < target {
            queue.push(Egg {
                colour: 0,
                origin: 0,
                ghost: 0,
            });
        }
        self.write(&queue);
    }
    /// item_egg.gd / seed_shot.gd / element_shot.gd reset_map, on a map (re)start.
    pub fn reset_map(&mut self, serial: i64) {
        self.egg_cursor = serial;
        self.origin = [0; 6];
        self.seed_cursor = serial;
        self.element_cursor = serial;
    }
    /// The three consume_level_requests in registry TYPES order. Spawns and origin marks
    /// are returned in order for the run to apply.
    pub fn run(
        &mut self,
        requests: &crate::food::Requests,
        eggs: i64,
    ) -> Result<Vec<Action>, Error> {
        let mut actions = self.run_eggs(requests, eggs)?;
        // seed_shot.gd consume_level_requests
        let seeds = requests.since(self.seed_cursor);
        self.seed_cursor = requests.serial();
        if let Since::Requests(list) = seeds {
            for (x, y, angle) in crate::melon::seed_requests(&list) {
                actions.push(Action::Seed(x, y, angle));
            }
        }
        // element_shot.gd consume_level_requests
        let elements = requests.since(self.element_cursor);
        self.element_cursor = requests.serial();
        if let Since::Requests(list) = elements {
            if list.iter().any(|r| [HEAT, COLD].contains(&r.kind)) {
                return Err(unsupported("fire and ice shots are not ported yet"));
            }
        }
        Ok(actions)
    }
    /// item_egg.gd consume_level_requests (also run first by an egg's grant).
    pub fn run_eggs(
        &mut self,
        requests: &crate::food::Requests,
        eggs: i64,
    ) -> Result<Vec<Action>, Error> {
        let mut actions = Vec::new();
        match requests.since(self.egg_cursor) {
            Since::Error => {
                self.egg_cursor = requests.serial();
                self.normalize(eggs);
            }
            Since::Requests(list) => {
                let mut before = eggs;
                for r in &list {
                    if r.kind == EGG {
                        before += 1;
                    } else if r.kind == STORED_EGG {
                        before -= 1;
                    }
                }
                let size = self.inventory().len() as i64;
                self.normalize(before.max(size));
                for r in &list {
                    let mut queue = self.inventory();
                    if r.kind == EGG {
                        let item = if queue.is_empty() {
                            Egg {
                                colour: 0,
                                origin: 0,
                                ghost: 0,
                            }
                        } else {
                            queue.remove(0)
                        };
                        let (mut vx, mut vy) = (r.vx, r.vy);
                        if vx == 0 && vy == 0 {
                            vx = sine((r.angle + 450_000) % 360_000, 360_000, 1024 * 60)?;
                            vy = sine((r.angle + 360_000) % 360_000, 360_000, 1024 * 60)?;
                        }
                        actions.push(Action::Spawn(crate::egg::Spawn::Egg {
                            x: r.x,
                            y: r.y,
                            colour: item.colour,
                            origin: item.origin,
                            ghost: item.ghost,
                            vx,
                            vy,
                        }));
                    } else if r.kind == STORED_EGG {
                        if queue.len() == 6 {
                            actions.push(Action::MarkOrigin(queue.remove(0).origin));
                        }
                        queue.push(Egg {
                            colour: 0,
                            origin: 0,
                            ghost: 0,
                        });
                    }
                    self.write(&queue);
                }
                self.egg_cursor = requests.serial();
                self.normalize(eggs);
            }
        }
        Ok(actions)
    }
    /// item_egg.gd grant's queue step; returns the origin pushed out of a full queue.
    pub fn push_egg(&mut self, colour: i64, origin: i64, ghost: i64) -> Option<i64> {
        let mut queue = self.inventory();
        let popped = (queue.len() == 6).then(|| queue.remove(0).origin);
        queue.push(Egg {
            colour,
            origin,
            ghost,
        });
        self.write(&queue);
        popped
    }
    pub fn valid(&self) -> bool {
        let present = self.colour.iter().take_while(|c| **c >= 0).count();
        self.egg_cursor >= 0
            && self.seed_cursor >= 0
            && self.element_cursor >= 0
            && self.colour[present..].iter().all(|c| *c == -1)
            && self.colour.iter().all(|c| (-1..=3).contains(c))
            && (0..6).all(|slot| {
                [0, 1].contains(&self.ghost[slot])
                    && self.origin[slot] >= 0
                    && (slot < present || (self.origin[slot] == 0 && self.ghost[slot] == 0))
            })
    }
    pub fn field(&self, name: &str) -> Option<i64> {
        Some(match name {
            "egg_request_cursor" => self.egg_cursor,
            "seed_request_cursor" => self.seed_cursor,
            "element_request_cursor" => self.element_cursor,
            _ => {
                let (array, slot) = slot(name)?;
                match array {
                    "colour" => self.colour[slot],
                    "origin" => self.origin[slot],
                    _ => self.ghost[slot],
                }
            }
        })
    }
    pub fn set_field(&mut self, name: &str, value: i64) -> bool {
        let target = match name {
            "egg_request_cursor" => &mut self.egg_cursor,
            "seed_request_cursor" => &mut self.seed_cursor,
            "element_request_cursor" => &mut self.element_cursor,
            _ => {
                let Some((array, slot)) = slot(name) else {
                    return false;
                };
                match array {
                    "colour" => &mut self.colour[slot],
                    "origin" => &mut self.origin[slot],
                    _ => &mut self.ghost[slot],
                }
            }
        };
        *target = value;
        true
    }
}

fn slot(name: &str) -> Option<(&'static str, usize)> {
    for array in ["colour", "origin", "ghost"] {
        if let Some(rest) = name
            .strip_prefix("egg_")
            .and_then(|r| r.strip_prefix(array))
        {
            let index: usize = rest.strip_prefix('_')?.parse().ok()?;
            if index < 6 {
                return Some((array, index));
            }
        }
    }
    None
}
