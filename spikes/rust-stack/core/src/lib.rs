//! Engine-independent fixed-tick experiment. No engine, I/O, or clock dependencies.
use std::fmt;

pub const SCALE: i64 = 3600;
pub const TICKS_PER_SECOND: u32 = 60;
pub const SNAPSHOT_VERSION: u32 = 10;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Error {
    NotImplemented { operation: &'static str },
    InvalidInput { context: String },
    Unsupported { requirements: Vec<String> },
    Snapshot { reason: String },
}
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{self:?}")
    }
}
impl std::error::Error for Error {}

/// All coordinates are saved integer simulation units, not pixels.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Position {
    pub x: i64,
    pub y: i64,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Motion {
    pub previous: Position,
    pub current: Position,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EntityStatus {
    Waiting,
    Active,
    Queued,
    Defeated,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Lifetime {
    Active,
    Hurt,
    Separated,
    Rescuing,
    Dying,
    Respawning,
    Goal,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PlayerPicture {
    pub motion: Motion,
    pub velocity: Position,
    pub facing: i64,
    pub movement: i64,
    pub action: i64,
    pub posture: i64,
    pub pose: i64,
    pub pose_ticks: i64,
    pub lifetime: Lifetime,
    pub life_phase: i64,
    pub on_floor: bool,
    pub swimming: bool,
    pub visible: bool,
    pub companion: Motion,
    pub companion_phase: i64,
    pub health: i64,
    pub coins: i64,
    pub red_coins: i64,
    pub flowers: i64,
}
/// Core samples semantic type view_state. Renderer binds animations/frames to art.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct VisualState {
    pub animation: Option<String>,
    pub frame: Option<i64>,
    pub offset_pixels: [f64; 2],
    pub size_pixels: [Option<f64>; 2],
    pub rotation_degrees: f64,
    pub flip_h: bool,
    pub alpha: f64,
    pub head_box: Option<[i64; 4]>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct EntityPicture {
    pub token: i64,
    pub code: String,
    pub placement_id: Option<String>,
    pub motion: Motion,
    pub facing: i64,
    pub layer: i64,
    pub variant: i64,
    pub status: EntityStatus,
    pub visible: bool,
    pub held: bool,
    pub hidden: bool,
    pub visual: VisualState,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SoundEvent {
    pub serial: i64,
    pub kind: i64,
    pub position: Position,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Presentation {
    pub tick: i64,
    pub map_index: usize,
    pub interpolate: bool,
    pub follow: Motion,
    pub player: PlayerPicture,
    /// Saved entity table order, including runtime suffix. Never type-grouped.
    pub entities: Vec<EntityPicture>,
    pub sound: SoundEvent,
}
#[derive(Clone, Debug, PartialEq)]
pub enum PropertyValue {
    String(String),
    Number(f64),
    Bool(bool),
    Null,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Placement {
    pub id: String,
    pub code: String,
    pub position: Position,
    pub variant: i64,
    pub mirror: i64,
    pub rotation: i64,
    pub layer: i64,
    pub properties: Vec<(String, PropertyValue)>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TileLayer {
    pub name: String,
    pub tilemap: String,
    pub width: usize,
    pub height: usize,
    /// Signed int32 Tiled identifiers, -1 empty, high bits h/v/d.
    pub cells: Vec<i32>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Map {
    pub name: String,
    pub width_pixels: i64,
    pub height_pixels: i64,
    pub backgrounds: [String; 3],
    pub background_color: [u8; 3],
    pub darkness_percent: i64,
    pub tint: String,
    pub layers: Vec<TileLayer>,
    pub placements: Vec<Placement>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct World {
    pub identity: [u8; 32],
    pub maps: Vec<Map>,
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct AdmissionReport {
    pub admitted_codes: Vec<String>,
    pub unsupported_requirements: Vec<String>,
    pub schema_digest: [u8; 32],
    pub placed_rows: usize,
}
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Stats {
    pub tick: i64,
    pub completed_ticks: u64,
    pub entity_steps: u64,
    pub contacts: u64,
    pub nearby_queries: u64,
    pub nearby_candidates: u64,
    pub solid_queries: u64,
    pub terrain_queries: u64,
    pub runtime_spawns: u64,
    pub collections: u64,
    pub damage_events: u64,
    pub restore_count: u64,
}

#[derive(Debug)]
pub struct Session {
    world: World,
    admission: AdmissionReport,
    stats: Stats,
}
impl Session {
    pub fn load(
        _level_json: &str,
        _collision_json: &str,
        _schema_json: &str,
    ) -> Result<Self, Error> {
        Err(Error::NotImplemented {
            operation: "load: world compilation and two start ticks",
        })
    }
    pub fn advance(&mut self, _input_mask: u8) -> Result<(), Error> {
        Err(Error::NotImplemented {
            operation: "advance",
        })
    }
    pub fn snapshot(&self) -> Result<Vec<u8>, Error> {
        Err(Error::NotImplemented {
            operation: "v10 snapshot",
        })
    }
    pub fn restore(&mut self, _bytes: &[u8]) -> Result<(), Error> {
        Err(Error::NotImplemented {
            operation: "v10 restore",
        })
    }
    pub fn presentation(&self) -> Presentation {
        // A Session cannot be constructed before the authoritative load exists.
        unreachable!("load never returns a partially implemented session")
    }
    pub fn world(&self) -> &World {
        &self.world
    }
    pub fn admission_report(&self) -> &AdmissionReport {
        &self.admission
    }
    pub fn stats(&self) -> &Stats {
        &self.stats
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unfinished_loader_does_not_admit_gameplay() {
        assert!(matches!(
            Session::load("{}", "{}", "{}"),
            Err(Error::NotImplemented { .. })
        ));
    }
}
