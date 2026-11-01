//! Engine-independent fixed-tick experiment. No engine, I/O, or clock dependencies.
use std::fmt;

mod actors;
mod armored;
mod balloon;
mod blocks;
mod body;
mod bubble;
mod bulk;
mod checkpoint;
mod clouds;
mod collision_grid;
mod consumers;
mod decor;
mod dice;
mod eating;
mod egg;
mod egg_block;
mod elements;
mod entity;
mod fish;
mod flow;
mod flower;
mod food;
mod gate;
mod gust;
mod hang;
mod hound;
mod items;
mod juggler;
mod launcher;
mod ledge;
mod life;
mod lift;
pub mod math;
mod melon;
mod pad;
mod petal;
mod pillar;
mod platform;
mod player;
pub mod polygon;
mod post;
mod pound;
mod presentation;
mod render_index;
mod roller;
mod runtime;
pub mod schema;
mod shell;
mod shooter;
mod solids;
#[cfg(test)]
mod solids_trace_tests;
mod spans;
mod spear;
mod spitter;
mod sprout;
mod state;
mod state_restore;
mod stem;
mod stilt;
mod switch;
mod thief;
mod tongue;
mod turn;
mod water;
mod wing;
pub mod wire;
pub mod world;
mod world_polygon;

pub const SCALE: i64 = 3600;
/// Codes the core can create during play in any level (stilt riders, thrown eggs,
/// loot and cache releases). Drawing binds their art even when no placement uses them.
pub const RUNTIME_CODES: [&str; 6] = ["e1", "o1", "o2", "o3", "o4", "o7"];
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

/// Exactly PlayerPose.select's name/tick/frame, before pack frame binding.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PoseSelection {
    pub name: String,
    pub tick: i64,
    pub frame: i64,
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
    pub selected_pose: PoseSelection,
    pub body_bounds: [i64; 4],
    pub visual: VisualState,
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
    /// The extended tongue while it is out or blocked (moves.gd TONGUE_OUT/BLOCKED).
    pub tongue: Option<TonguePicture>,
    /// Carried egg colours, first slot first (0 green, 1 yellow, 2 red, 3 purple). The
    /// original draws them trailing Yoshi; the Godot port drew none.
    pub eggs: Vec<i64>,
    /// Throw direction in degrees (0 right, -90 up) while aiming (moves.gd _emit angle).
    pub aim_degrees: Option<f64>,
}
/// Where the tongue leaves the mouth, relative to the player body position, and how far
/// it reaches. The Godot port never drew it; the pack has YoshiTongueL/R/U nine-patches.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TonguePicture {
    pub up: bool,
    pub mouth: [i64; 2],
    pub length: i64,
}
/// Core samples semantic type view_state. Renderer binds animations/frames to art.
#[derive(Clone, PartialEq)]
pub struct VisualState {
    pub animation: Option<String>,
    pub frame: Option<i64>,
    pub offset_pixels: [f64; 2],
    pub size_pixels: [Option<f64>; 2],
    /// Multiplicative local ratio after frame/size selection, before placement/camera.
    pub scale: Option<[f64; 2]>,
    pub rotation_degrees: Option<f64>,
    /// None preserves the pack/source setting; Some(false) overrides it.
    pub flip_h: Option<bool>,
    pub flip_v: Option<bool>,
    pub alpha: f64,
    /// World-space integer head hull, separate from the body hull.
    pub head_box: Option<[i64; 4]>,
    /// Semantic override only. Pack frame/origin/slices remain renderer-owned.
    pub asset_key: Option<String>,
    pub origin_pixels: Option<[f64; 2]>,
    pub slice: Option<PictureSlice>,
    pub palette: Vec<PaletteSwap>,
    /// Multiplicative colour (Godot self_modulate), e.g. map_effects.gd dice colours.
    pub tint: Option<[u8; 3]>,
}
/// The derived field list; `tint` appears only when set, so pictures without a tint
/// print (and hash in diagnosis traces) exactly as before the field existed.
impl std::fmt::Debug for VisualState {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut s = f.debug_struct("VisualState");
        s.field("animation", &self.animation)
            .field("frame", &self.frame)
            .field("offset_pixels", &self.offset_pixels)
            .field("size_pixels", &self.size_pixels)
            .field("scale", &self.scale)
            .field("rotation_degrees", &self.rotation_degrees)
            .field("flip_h", &self.flip_h)
            .field("flip_v", &self.flip_v)
            .field("alpha", &self.alpha)
            .field("head_box", &self.head_box)
            .field("asset_key", &self.asset_key)
            .field("origin_pixels", &self.origin_pixels)
            .field("slice", &self.slice)
            .field("palette", &self.palette);
        if let Some(tint) = &self.tint {
            s.field("tint", tint);
        }
        s.finish()
    }
}
impl Default for VisualState {
    fn default() -> Self {
        Self {
            animation: None,
            frame: None,
            offset_pixels: [0.0; 2],
            size_pixels: [None; 2],
            scale: None,
            rotation_degrees: None,
            flip_h: None,
            flip_v: None,
            alpha: 1.0,
            head_box: None,
            asset_key: None,
            origin_pixels: None,
            slice: None,
            palette: Vec::new(),
            tint: None,
        }
    }
}
#[derive(Clone, Debug, PartialEq)]
pub struct PictureSlice {
    pub start_pixels: f64,
    pub end_pixels: f64,
    pub axis: SliceAxis,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SliceAxis {
    Horizontal,
    Vertical,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PaletteSwap {
    pub from: [u8; 3],
    pub to: [u8; 3],
}
#[derive(Clone, Debug, PartialEq)]
pub struct EntityPicture {
    pub token: i64,
    pub code: String,
    pub placement_id: Option<String>,
    /// Index in the current immutable Map.placements; None is runtime-created.
    pub source_index: Option<usize>,
    /// Relative integer body bounds, distinct from activation/picture/head hulls.
    pub body_bounds: [i64; 4],
    pub motion: Motion,
    pub facing: i64,
    pub layer: i64,
    pub variant: i64,
    pub status: EntityStatus,
    pub visible: bool,
    pub held: bool,
    pub hidden: bool,
    pub visual: VisualState,
    pub auxiliary: Vec<EntityAuxiliaryPicture>,
}
/// Separate type-owned pictures, not inferred from contact hulls.
#[derive(Clone, Debug, PartialEq)]
pub struct EntityAuxiliaryPicture {
    pub kind: EntityAuxiliaryKind,
    pub picture: AuxiliaryPicture,
    pub scale: [f64; 2],
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EntityAuxiliaryKind {
    PlantHead,
    /// The original's stilt walker parts (Enemies sheet): feet, pole strip, body.
    StiltFeet,
    StiltPoles,
    StiltTop,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SoundEvent {
    pub serial: i64,
    pub kind: i64,
    pub position: Position,
}
#[derive(Clone, Debug, PartialEq)]
pub struct AuxiliaryPicture {
    pub motion: Motion,
    pub visible: bool,
    pub layer: i64,
    pub facing: i64,
    pub animation: String,
    pub tick: i64,
    pub visual: VisualState,
}
#[derive(Clone, Debug, PartialEq)]
pub struct CompanionPictures {
    pub mode: i64,
    pub companion: AuxiliaryPicture,
    pub bubble: AuxiliaryPicture,
    pub rescuers: [AuxiliaryPicture; 4],
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HudPicture {
    pub health: i64,
    pub coins: i64,
    pub redcoins: i64,
    pub redcoins_target: i64,
    pub flowers: i64,
    pub flowers_target: i64,
    pub hits: i64,
    pub deaths: i64,
    pub total_play_ticks: i64,
    pub life_phase: i64,
    pub life_ticks: i64,
    pub separated: bool,
    pub score: i64,
    pub status: String,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MessagePicture {
    pub holder_token: i64,
    pub text: String,
    pub section: i64,
    pub sections: i64,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Presentation {
    pub tick: i64,
    pub map_index: usize,
    pub interpolate: bool,
    pub follow: Motion,
    pub player: PlayerPicture,
    pub companions: CompanionPictures,
    pub hud: HudPicture,
    pub message: Option<MessagePicture>,
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
    Array(Vec<PropertyValue>),
    Object(Vec<(String, PropertyValue)>),
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
    pub prepared: PreparedPlacement,
}
/// Immutable source facts. None does not mean that gameplay admission is granted.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PreparedPlacement {
    None,
    /// Zero-based index into this map's bridges, in registry placement order.
    Bridge {
        geometry_index: usize,
    },
    /// o11 is a verification-only dependency of the Bounce fixture.
    Pad {
        large: bool,
        single_use: bool,
    },
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BridgeGeometry {
    pub left: i64,
    pub right: i64,
    pub top: i64,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DrawSlot {
    pub layer_index: i64,
    pub z_order: i64,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TerrainHazard {
    None,
    Lava,
    Spikes,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TileCollision {
    pub cell: i32,
    pub polygon: Vec<Position>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TileLayer {
    /// Original layer1/layer2/layer3 key, not the tilemap family.
    pub source_layer: String,
    pub tilemap: String,
    pub tile_size_pixels: i64,
    pub draw_slot: DrawSlot,
    pub solid: bool,
    pub water: bool,
    pub hazard: TerrainHazard,
    /// Transformed contact polygons for every distinct nonempty cell identifier.
    pub collision: Vec<TileCollision>,
    /// Derived once at compilation. Keys include all h/v/d transform bits.
    /// Immutable with `collision`; never part of saved gameplay state.
    pub(crate) collision_index: std::collections::HashMap<i32, usize>,
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
    pub cave_shimmer: bool,
    pub dice_colours: Vec<[u8; 3]>,
    pub source_properties: Vec<(String, PropertyValue)>,
    pub layers: Vec<TileLayer>,
    pub(crate) collision_grid: collision_grid::Grid,
    pub placements: Vec<Placement>,
    /// One immutable geometry owner. Saved support_bridge uses index + 1.
    pub bridges: Vec<BridgeGeometry>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct World {
    pub identity: [u8; 32],
    pub maps: Vec<Map>,
    pub initial_map: usize,
    pub spawn: Position,
    pub spawn_facing: i64,
    pub player_palette: Vec<[u8; 3]>,
    /// Source goals after original bounded-integer validation and max(0, value).
    pub flowers_target: i64,
    pub redcoins_target: i64,
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
    #[cfg(feature = "benchmark-work-counters")]
    pub benchmark_stepped_source_rows: Vec<Option<usize>>,
    /// Debug-host-only actual dispatch counters; absent from optimized Pro builds.
    #[cfg(debug_assertions)]
    pub benchmark_actor_steps: [u64; 5],
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
    schema: schema::Schema,
    state: state::Run,
    previous: presentation::Previous,
    render_index: render_index::Index,
    interpolate: bool,
    /// Reused storage for the next step's entity rows. Contents are never read.
    spare_entities: Vec<entity::Entity>,
}
impl Session {
    pub fn load(level_json: &str, collision_json: &str, schema_json: &str) -> Result<Self, Error> {
        let schema = schema::Schema::parse(schema_json)?;
        if schema::hash(collision_json.as_bytes())
            != schema::decode_hash(
                "a143014159ced2f04f82386471c7fbf6e628f4760c4085655b7e9392b0dde6d6",
            )?
        {
            return Err(Error::Unsupported {
                requirements: vec!["collision table differs from pinned reference".into()],
            });
        }
        let world = World::compile(level_json, collision_json)?;
        let mut stats = Stats::default();
        let state = state::Run::create(&world, &mut stats)?;
        state.validate(&world)?;
        let mut render_index = render_index::Index::default();
        render_index.update(&state, &world);
        let previous = presentation::Previous::of(&state, world.maps[0].placements.len());
        let admission = AdmissionReport {
            admitted_codes: world.maps[0]
                .placements
                .iter()
                .map(|p| p.code.clone())
                .chain(RUNTIME_CODES.iter().map(|c| c.to_string()))
                .collect::<std::collections::BTreeSet<_>>()
                .into_iter()
                .collect(),
            unsupported_requirements: Vec::new(),
            schema_digest: schema.digest(),
            placed_rows: world.maps[0].placements.len(),
        };
        Ok(Self {
            world,
            admission,
            stats,
            schema,
            state,
            previous,
            render_index,
            interpolate: false,
            spare_entities: Vec::new(),
        })
    }
    /// Benchmark-only entry; normal load remains strict and all other checks run.
    pub fn load_benchmark_unverified(
        level_json: &str,
        collision_json: &str,
        schema_json: &str,
    ) -> Result<Self, Error> {
        Self::load_benchmark_configured(level_json, collision_json, schema_json, false)
    }
    pub fn load_benchmark_real_screen(
        level_json: &str,
        collision_json: &str,
        schema_json: &str,
    ) -> Result<Self, Error> {
        Self::load_benchmark_configured(level_json, collision_json, schema_json, true)
    }
    fn load_benchmark_configured(
        level_json: &str,
        collision_json: &str,
        schema_json: &str,
        omit_dice_colours: bool,
    ) -> Result<Self, Error> {
        let schema = schema::Schema::parse(schema_json)?;
        if schema::hash(collision_json.as_bytes())
            != schema::decode_hash(
                "a143014159ced2f04f82386471c7fbf6e628f4760c4085655b7e9392b0dde6d6",
            )?
        {
            return Err(Error::Unsupported {
                requirements: vec!["collision table differs from pinned reference".into()],
            });
        }
        let world = if omit_dice_colours {
            World::compile_benchmark_real_screen(level_json, collision_json)?
        } else {
            World::compile(level_json, collision_json)?
        };
        let mut stats = Stats::default();
        let state = state::Run::create_benchmark_unverified(&world, &mut stats)?;
        state.validate(&world)?;
        let mut render_index = render_index::Index::default();
        render_index.update(&state, &world);
        let previous = presentation::Previous::of(&state, world.maps[0].placements.len());
        let admission = AdmissionReport {
            admitted_codes: world.maps[0]
                .placements
                .iter()
                .map(|p| p.code.clone())
                .chain(RUNTIME_CODES.iter().map(|c| c.to_string()))
                .collect::<std::collections::BTreeSet<_>>()
                .into_iter()
                .collect(),
            unsupported_requirements: Vec::new(),
            schema_digest: schema.digest(),
            placed_rows: world.maps[0].placements.len(),
        };
        Ok(Self {
            world,
            admission,
            stats,
            schema,
            state,
            previous,
            render_index,
            interpolate: false,
            spare_entities: Vec::new(),
        })
    }
    pub fn benchmark_actor_steps(&self) -> Option<[u64; 5]> {
        #[cfg(debug_assertions)]
        {
            Some(self.stats.benchmark_actor_steps)
        }
        #[cfg(not(debug_assertions))]
        {
            None
        }
    }
    pub fn advance(&mut self, input_mask: u8) -> Result<(), Error> {
        // Transactional refusal while this narrow vertical slice still has unsupported
        // contacts. This is a typed-state copy, never snapshot encoding or JSON.
        // Remove the rollback copy only when the admitted closure cannot fail mid-step.
        // The entity rows are copied into a recycled buffer (the rows of the state
        // before last), so a step makes no large allocation.
        let rows = std::mem::take(&mut self.state.entities);
        let mut next = self.state.clone();
        self.state.entities = rows;
        let mut buffer = std::mem::take(&mut self.spare_entities);
        buffer.clone_from(&self.state.entities);
        next.entities = buffer;
        let mut stats = self.stats.clone();
        #[cfg(feature = "benchmark-work-counters")]
        stats.benchmark_stepped_source_rows.clear();
        next.advance(input_mask, &self.world, &mut stats)?;
        next.validate(&self.world)?;
        stats.completed_ticks += 1;
        stats.tick = next.frame;
        self.stats = stats;
        self.render_index.update(&next, &self.world);
        let finished = std::mem::replace(&mut self.state, next);
        let older = std::mem::replace(
            &mut self.previous,
            presentation::Previous::from_run(finished, self.world.maps[0].placements.len()),
        );
        self.spare_entities = older.into_entities();
        self.interpolate = true;
        Ok(())
    }
    pub fn snapshot(&self) -> Result<Vec<u8>, Error> {
        self.state.validate(&self.world)?;
        self.state
            .wire(&self.world, &self.schema)
            .encode(&self.schema)
    }
    pub fn restore(&mut self, bytes: &[u8]) -> Result<(), Error> {
        let wire = wire::WireSnapshot::decode(bytes, self.world.identity, &self.schema)?;
        let state = state::Run::restored(&wire, &self.world, &self.schema)?;
        self.previous = presentation::Previous::of(&state, self.world.maps[0].placements.len());
        self.render_index.update(&state, &self.world);
        self.state = state;
        self.stats.tick = self.state.frame;
        self.stats.restore_count += 1;
        self.interpolate = false;
        Ok(())
    }
    /// Visual-only query; never used by activation or simulation dispatch.
    pub fn presentation_region(&self, bounds: [i64; 4]) -> Presentation {
        let rows = self.render_index.query(bounds);
        presentation::sample_rows(
            &self.state,
            &self.world,
            &self.previous,
            self.interpolate,
            Some(&rows),
        )
    }
    pub fn configure_presentation_index(&mut self, absolute_origin_guard: i64) {
        self.render_index.configure(absolute_origin_guard.max(1));
        self.render_index.update(&self.state, &self.world);
    }
    pub fn presentation_view(&self) -> (usize, Position) {
        (1, self.state.camera)
    }
    pub fn render_index_metrics(&self) -> (usize, usize, usize, usize) {
        self.render_index.metrics()
    }
    pub fn presentation(&self) -> Presentation {
        presentation::sample(&self.state, &self.world, &self.previous, self.interpolate)
    }
    pub fn world(&self) -> &World {
        &self.world
    }
    /// Read-only saved fields for views that derive cues from saved state, such as
    /// audio_player.gd `summarize`. A level or player field by its saved name.
    pub fn saved_field(&self, name: &str) -> Option<i64> {
        self.state.saved_field(name, &self.world)
    }
    /// Visits every saved entity row in table order with its code and a reader of its
    /// saved fields by name. Read-only; never used by simulation.
    pub fn visit_saved_rows(&self, mut visit: impl FnMut(&str, &dyn Fn(&str) -> Option<i64>)) {
        for e in &self.state.entities {
            visit(e.code(&self.world), &|name| {
                self.state.saved_entity_field(e, name, &self.world)
            });
        }
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
    fn visual_defaults_do_not_hide_or_override_pack_flips() {
        let visual = VisualState::default();
        assert_eq!(visual.alpha, 1.0);
        assert_eq!(visual.scale, None);
        assert_eq!(visual.flip_h, None);
        assert_eq!(visual.flip_v, None);
        assert_eq!(visual.rotation_degrees, None);
    }
    #[test]
    fn malformed_loader_does_not_admit_gameplay() {
        assert!(matches!(
            Session::load("{}", "{}", "{}"),
            Err(Error::InvalidInput { .. })
        ));
    }
}
