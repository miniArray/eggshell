//! Music and effect playback derived from saved state. A port of src/view/audio_player.gd
//! (derivation and playback rules) and src/view/pack_audio.gd (the pack audio map).
//!
//! `Observer` compares a small summary of the previous observed state with the current
//! one after each simulation step and never writes state. A restored state, a frame that
//! does not advance or a gap of more than four frames resynchronizes without cues, so a
//! restore never replays old sounds. `Mixer` plays the cues in SDL's audio thread: eight
//! effect voices and one music voice. Effects are decoded once on a loader thread; music
//! is decoded while it plays and kept, so loops and restarts are exact.
use crate::pack::Pack;
use eggshell_spike_core::{PropertyValue, Session, World};
use serde_json::Value;
use std::{
    collections::HashMap,
    io::Cursor,
    sync::{
        Arc, OnceLock,
        atomic::{AtomicU64, Ordering},
        mpsc,
    },
};

// life.gd
const PLAY: i64 = 0;
const REJOIN: i64 = 1;
const DEAD: i64 = 2;
const FADE_OUT: i64 = 3;
const RESPAWN: i64 = 4;
const FADE_IN: i64 = 5;
const CHECKPOINT: i64 = 6;
const GOAL: i64 = 7;
const COMPLETE: i64 = 8;
const ATTACHED: i64 = 0;
const BUBBLE: i64 = 2;
// moves.gd
const NORMAL: i64 = 0;
const POUND_START: i64 = 1;
const POUND_FALL: i64 = 2;
const POUND_LAND: i64 = 3;
const TONGUE: i64 = 4;
const TOSS: i64 = 8;
const HEAD_BUMP: i64 = 9;
// move_requests.gd
const CAPACITY: i64 = 4;
const REQUEST_EVENTS: [(i64, &str); 5] = [
    (2, "spit"),
    (3, "spit_seed"),
    (4, "spit_fire"),
    (5, "spit_ice"),
    (STORED_EGG, "egg_made"),
];
const STORED_EGG: i64 = 7;
// audio_player.gd
pub const VOICES: usize = 8;
const MAX_STEP_GAP: i64 = 4;
const SWITCH_TICKS: i64 = 630;
const AIM_TICK_FRAMES: i64 = 4;
const SNOW_STEP_FRAMES: i64 = 18;
const HELD_EVENTS: [&str; 1] = ["switch_timer"];
const QUIET_PHASES: [i64; 5] = [DEAD, FADE_OUT, RESPAWN, GOAL, COMPLETE];
const OBJECT_EVENTS: [&str; 7] = [
    "egg_bounce",
    "cloud_reveal",
    "cloud_hit",
    "cloud_release",
    "egg_block",
    "spring",
    "gate_open",
];
const EGG_THROWN: i64 = 1;
const CACHE_HIDDEN: i64 = 0;
const CACHE_REVEALED: i64 = 2;
const CACHE_OPENING: i64 = 3;
/// settings.gd defaults; the Rust player has no settings file yet.
const MUSIC_VOLUME: i64 = 80;
const EFFECTS_VOLUME: i64 = 80;
/// Every pack Ogg file is 48 kHz; the device plays at this rate.
pub const RATE: u32 = 48_000;

macro_rules! watched {
    ($($name:ident = $default:expr),* $(,)?) => {
        /// Saved scalar fields that derivation reads (audio_player.gd WATCHED), plus
        /// `goal_reached`, which game.gd reads to stop stepping and pausing sounds.
        #[allow(non_camel_case_types)]
        #[derive(Clone, Copy, Debug)]
        pub enum W { $($name),* }
        const WATCHED: &[(&str, i64)] = &[$((stringify!($name), $default)),*];
    };
}
watched!(
    frame = 0,
    map_index = 1,
    life_phase = PLAY,
    life_ticks = 0,
    health = 10,
    health_wait = 0,
    separated = 0,
    checkpoint_awards = 0,
    companion_mode = ATTACHED,
    coins = 0,
    redcoins = 0,
    flowers = 0,
    invulnerable = 0,
    vx = 0,
    vy = 0,
    on_floor = 0,
    swimming = 0,
    boosted_flutter = 0,
    flutter_remaining = 0,
    move_pound_delay = 0,
    move_action = NORMAL,
    move_impact = 0,
    move_eggs = 0,
    move_aim = 0,
    move_snow = 0,
    move_emit_serial = 0,
    move_emit_kind = 0,
    move_emit_1_kind = 0,
    move_emit_2_kind = 0,
    move_emit_3_kind = 0,
    switch_ticks = 0,
    switch_sound_serial = 0,
    switch_sound_kind = 0,
    message_stage = 0,
    message_section = 0,
    goal_reached = 0,
);

/// Object codes that derivation reads, with their fields (audio_player.gd ENTITY_FIELDS).
const ENTITY_FIELDS: [(&str, &[&str]); 5] = [
    ("o7", &["mode", "bounces"]),
    ("o8", &["phase", "status", "content"]),
    ("o9", &["busy"]),
    ("o11", &["squash"]),
    ("o31", &["opened"]),
];

/// Receives one entity row: its code and a reader of its saved fields by name.
pub type RowVisitor<'a> = dyn FnMut(&str, &dyn Fn(&str) -> Option<i64>) + 'a;
/// The saved state as derivation sees it: flat level and player fields, and entity rows.
pub trait SavedState {
    fn field(&self, name: &str) -> Option<i64>;
    fn rows(&self, visit: &mut RowVisitor);
}
impl SavedState for Session {
    fn field(&self, name: &str) -> Option<i64> {
        self.saved_field(name)
    }
    fn rows(&self, visit: &mut RowVisitor) {
        self.visit_saved_rows(visit)
    }
}

/// One watched object row: its code (index into ENTITY_FIELDS) and field values.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Row {
    pub token: i64,
    pub code: usize,
    pub values: [i64; 3],
}

/// audio_player.gd `summarize`: watched fields, watched object rows by token, egg count.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Summary {
    pub values: Vec<i64>,
    /// Sorted by token; a later row with the same token replaces an earlier one.
    pub objects: Vec<Row>,
    pub eggs: i64,
}
impl Default for Summary {
    fn default() -> Self {
        Self {
            values: WATCHED.iter().map(|(_, d)| *d).collect(),
            objects: Vec::new(),
            eggs: 0,
        }
    }
}
impl std::ops::Index<W> for Summary {
    type Output = i64;
    fn index(&self, w: W) -> &i64 {
        &self.values[w as usize]
    }
}
impl std::ops::IndexMut<W> for Summary {
    fn index_mut(&mut self, w: W) -> &mut i64 {
        &mut self.values[w as usize]
    }
}
impl Summary {
    /// Missing fields read as their defaults.
    pub fn read(&mut self, state: &dyn SavedState) {
        for (value, (name, default)) in self.values.iter_mut().zip(WATCHED) {
            *value = state.field(name).unwrap_or(*default);
        }
        self.objects.clear();
        self.eggs = 0;
        let (objects, eggs) = (&mut self.objects, &mut self.eggs);
        state.rows(&mut |code, field| {
            let Some(index) = ENTITY_FIELDS.iter().position(|(c, _)| *c == code) else {
                return;
            };
            let mut values = [0; 3];
            for (value, name) in values.iter_mut().zip(ENTITY_FIELDS[index].1) {
                *value = field(name).unwrap_or(0);
            }
            objects.push(Row {
                token: field("token").unwrap_or(0),
                code: index,
                values,
            });
            *eggs += i64::from(index == 0);
        });
        // Stable sort, then keep the last row of each token, as a Dictionary would.
        self.objects.sort_by_key(|r| r.token);
        let mut kept = 0;
        for i in 0..self.objects.len() {
            if i + 1 < self.objects.len() && self.objects[i + 1].token == self.objects[i].token {
                continue;
            }
            self.objects[kept] = self.objects[i];
            kept += 1;
        }
        self.objects.truncate(kept);
    }
    fn object(&self, token: i64) -> Option<&Row> {
        self.objects
            .binary_search_by_key(&token, |r| r.token)
            .ok()
            .map(|i| &self.objects[i])
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cue {
    Effect(&'static str),
    StopEffect(&'static str),
    Role(&'static str),
    StopMusic,
    StopAll,
}
impl Cue {
    /// The test name of a cue: its event, its role or the cue kind.
    pub fn name(&self) -> &'static str {
        match self {
            Cue::Effect(e) | Cue::StopEffect(e) => e,
            Cue::Role(r) => r,
            Cue::StopMusic => "stop_music",
            Cue::StopAll => "stop_all",
        }
    }
}

/// World goals that turn the last red coin or flower into its own cue.
#[derive(Clone, Copy, Debug, Default)]
pub struct Targets {
    pub redcoins: i64,
    pub flowers: i64,
}

/// Cues for one observed change (audio_player.gd `derive`).
pub fn derive(p: &Summary, c: &Summary, targets: Targets, cues: &mut Vec<Cue>) {
    use W::*;
    let respawned = c[life_phase] == FADE_IN && p[life_phase] != FADE_IN;
    if c[life_phase] != p[life_phase] {
        match c[life_phase] {
            DEAD => {
                cues.push(Cue::StopAll);
                cues.push(Cue::Role("death"));
            }
            FADE_OUT if p[life_phase] != DEAD => {
                cues.push(Cue::StopAll);
                cues.push(Cue::Effect("quick_death"));
            }
            GOAL => {
                cues.push(Cue::StopMusic);
                cues.push(Cue::Role("goal"));
            }
            REJOIN => cues.push(Cue::Effect("rescue")),
            PLAY if p[life_phase] == REJOIN => cues.push(Cue::Effect("rejoin")),
            _ => {}
        }
    }
    if respawned || [DEAD, FADE_OUT, RESPAWN].contains(&c[life_phase]) {
        return;
    }
    if c[life_phase] == CHECKPOINT
        && c[life_ticks] == 45
        && (p[life_phase] != CHECKPOINT || p[life_ticks] != 45)
    {
        cues.push(Cue::Effect("checkpoint"));
    }
    counter_cues(p, c, targets, cues);
    health_cues(p, c, cues);
    move_cues(p, c, cues);
    level_cues(p, c, cues);
    object_cues(p, c, cues);
}

fn counter_cues(p: &Summary, c: &Summary, targets: Targets, cues: &mut Vec<Cue>) {
    use W::*;
    if c[coins] > p[coins] {
        cues.push(Cue::Effect("coin"));
    }
    if c[redcoins] > p[redcoins] {
        let all_red = c[redcoins] >= targets.redcoins;
        cues.push(Cue::Effect(if all_red {
            "all_red_coins"
        } else {
            "red_coin"
        }));
    }
    if c[flowers] > p[flowers] {
        cues.push(Cue::Effect("flower"));
        if c[flowers] >= targets.flowers {
            cues.push(Cue::Effect("all_flowers"));
        }
    }
}

fn health_cues(p: &Summary, c: &Summary, cues: &mut Vec<Cue>) {
    use W::*;
    if c[invulnerable] > p[invulnerable] {
        cues.push(Cue::Effect("hit"));
    }
    if c[companion_mode] == BUBBLE && p[companion_mode] != BUBBLE {
        cues.push(Cue::Effect("companion_cry"));
    }
    if c[health] < p[health] && c[separated] != 0 && p[separated] != 0 {
        cues.push(Cue::Effect(if c[health] >= 10 {
            "countdown_high"
        } else {
            "countdown_low"
        }));
    }
    if c[health] <= p[health] {
        return;
    }
    if c[life_phase] == CHECKPOINT || p[life_phase] == CHECKPOINT {
        if c[checkpoint_awards] > 0 {
            cues.push(Cue::Effect("star"));
        }
    } else if p[separated] == 0 && p[health] < 10 && p[health_wait] == 1 {
        if c[health] == 10 {
            cues.push(Cue::Effect("countdown_full"));
        }
    } else {
        cues.push(Cue::Effect("star"));
    }
}

fn move_cues(p: &Summary, c: &Summary, cues: &mut Vec<Cue>) {
    use W::*;
    let switched = c[switch_sound_serial] != p[switch_sound_serial];
    let launched = switched || c[invulnerable] > p[invulnerable] || sprung(p, c);
    let rising = c[vy] < 0 && p[vy] >= 0 && !launched;
    let pounding = [POUND_START, POUND_FALL, POUND_LAND].contains(&c[move_action]);
    if rising && c[boosted_flutter] != 0 {
        cues.push(Cue::Effect("stomp"));
    } else if rising && c[move_pound_delay] == 6 && !pounding {
        cues.push(Cue::Effect("jump"));
    }
    if c[flutter_remaining] > 0 && p[flutter_remaining] == 0 {
        cues.push(Cue::Effect("flutter"));
    }
    if c[move_action] != p[move_action] {
        match c[move_action] {
            POUND_START => cues.push(Cue::Effect("pound_start")),
            TONGUE => cues.push(Cue::Effect("tongue")),
            TOSS => cues.push(Cue::Effect("egg_throw")),
            HEAD_BUMP => cues.push(Cue::Effect("head_bump")),
            _ => {}
        }
    }
    if c[move_impact] != p[move_impact] {
        cues.push(Cue::Effect("pound_land"));
    }
    let mut made_egg = false;
    let fresh = c[move_emit_serial].wrapping_sub(p[move_emit_serial]);
    if fresh > 0 {
        let kinds = [
            c[move_emit_kind],
            c[move_emit_1_kind],
            c[move_emit_2_kind],
            c[move_emit_3_kind],
        ];
        for kind in &kinds[..fresh.min(CAPACITY) as usize] {
            made_egg = made_egg || *kind == STORED_EGG;
            if let Some((_, event)) = REQUEST_EVENTS.iter().find(|(k, _)| k == kind) {
                cues.push(Cue::Effect(event));
            }
        }
    }
    if c[move_eggs] > p[move_eggs] && !made_egg {
        cues.push(Cue::Effect("egg_pickup"));
    }
    if c[swimming] != p[swimming] {
        cues.push(Cue::Effect("splash"));
    }
    if c[move_aim] != 0 && crossed(p[frame], c[frame], AIM_TICK_FRAMES) {
        cues.push(Cue::Effect("aim_tick"));
    }
    if c[move_snow] != 0
        && c[on_floor] != 0
        && c[vx] != 0
        && crossed(p[frame], c[frame], SNOW_STEP_FRAMES)
    {
        cues.push(Cue::Effect("snow_step"));
    }
}

fn level_cues(p: &Summary, c: &Summary, cues: &mut Vec<Cue>) {
    use W::*;
    if c[switch_sound_serial] > p[switch_sound_serial] {
        match c[switch_sound_kind] {
            1 => cues.push(Cue::Effect("switch_press")),
            2 => cues.push(Cue::Effect("switch_timer")),
            3 => cues.push(Cue::StopEffect("switch_timer")),
            _ => {}
        }
    }
    if c[message_stage] != p[message_stage] {
        match (p[message_stage], c[message_stage]) {
            (0, 1) => cues.push(Cue::Effect("message_hit")),
            (1, 2) => cues.push(Cue::Effect("message_open")),
            (2, 3) => cues.push(Cue::Effect("message_close")),
            _ => {}
        }
    } else if c[message_stage] == 2 && c[message_section] != p[message_section] {
        cues.push(Cue::Effect("message_scroll"));
    }
}

const O7: usize = 0;
const O8: usize = 1;
const O9: usize = 2;
const O11: usize = 3;
const O31: usize = 4;

fn sprung(p: &Summary, c: &Summary) -> bool {
    c.objects.iter().any(|now| {
        now.code == O11
            && p.object(now.token)
                .is_some_and(|was| was.code == O11 && now.values[0] > was.values[0])
    })
}

fn object_cues(p: &Summary, c: &Summary, cues: &mut Vec<Cue>) {
    let mut found = [false; OBJECT_EVENTS.len()];
    for now in &c.objects {
        let Some(was) = p.object(now.token) else {
            continue;
        };
        if was.code != now.code {
            continue;
        }
        let (n, w) = (now.values, was.values);
        match now.code {
            O7 if n[0] == EGG_THROWN && n[1] < w[1] => found[0] = true,
            O8 if w[0] == CACHE_HIDDEN && n[0] == CACHE_REVEALED => found[1] = true,
            O8 if w[0] != CACHE_OPENING && n[0] == CACHE_OPENING => found[2] = true,
            O8 if w[0] == CACHE_OPENING && w[1] != 3 && n[1] == 3 && [1, 2].contains(&n[2]) => {
                found[3] = true
            }
            O9 if w[0] == 7 && n[0] == 6 && c.eggs > p.eggs => found[4] = true,
            O11 if n[0] > w[0] => found[5] = true,
            O31 if n[0] != 0 && w[0] == 0 => found[6] = true,
            _ => {}
        }
    }
    for (event, found) in OBJECT_EVENTS.iter().zip(found) {
        if found {
            cues.push(Cue::Effect(event));
            if *event == "egg_bounce" {
                cues.push(Cue::Effect("egg_ricochet"));
            }
        }
    }
}

fn crossed(from_frame: i64, to_frame: i64, period: i64) -> bool {
    to_frame.div_euclid(period) > from_frame.div_euclid(period)
}

/// pack_audio.gd: track keys and effect keys to pack files, track settings, neutral event
/// names to effect keys (or lists that take turns) and music roles to track keys.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct AudioMap {
    pub music: HashMap<String, String>,
    pub effects: HashMap<String, String>,
    pub music_settings: HashMap<String, TrackSettings>,
    pub events: HashMap<String, Vec<String>>,
    pub tracks: HashMap<String, String>,
    /// Remote level music (a map's `{src, dat}`), keyed by the exact `src` URL: the
    /// private copy fetched once beside the pack and its SHA-256 (add_custom_music).
    pub custom: HashMap<String, (std::path::PathBuf, String)>,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TrackSettings {
    pub loop_start: f64,
    pub volume_db: f64,
}
impl Default for TrackSettings {
    fn default() -> Self {
        Self {
            loop_start: 0.0,
            volume_db: 0.0,
        }
    }
}
fn safe_file(value: &Value) -> Option<&str> {
    let file = value.as_str()?;
    (!file.is_empty()
        && !file.starts_with('/')
        && !file.contains([':', '\\'])
        && !file.split('/').any(|part| part == ".."))
    .then_some(file)
}
fn ogg(value: &Value) -> Option<&str> {
    safe_file(value).filter(|f| {
        std::path::Path::new(f)
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("ogg"))
    })
}
fn number(value: Option<&Value>) -> Option<f64> {
    value
        .filter(|v| v.is_number())
        .and_then(Value::as_f64)
        .filter(|v| v.is_finite())
}
impl AudioMap {
    pub fn parse(manifest: &Value) -> Self {
        let mut map = Self::default();
        let Some(audio) = manifest.get("audio").and_then(Value::as_object) else {
            return map;
        };
        for (key, entry) in audio
            .get("music")
            .and_then(Value::as_object)
            .into_iter()
            .flatten()
        {
            let file = entry.get("file").unwrap_or(entry);
            let Some(file) = ogg(file) else { continue };
            map.music.insert(key.clone(), file.to_owned());
            let mut settings = TrackSettings::default();
            if entry.is_object() {
                if let Some(loop_start) = number(entry.get("loop_start")).filter(|v| *v >= 0.0) {
                    settings.loop_start = loop_start;
                }
                if let Some(volume) = number(entry.get("volume_db")) {
                    settings.volume_db = volume.clamp(-60.0, 24.0);
                }
            }
            map.music_settings.insert(key.clone(), settings);
        }
        for (key, entry) in audio
            .get("effects")
            .and_then(Value::as_object)
            .into_iter()
            .flatten()
        {
            if let Some(file) = ogg(entry) {
                map.effects.insert(key.clone(), file.to_owned());
            }
        }
        for (key, entry) in audio
            .get("events")
            .and_then(Value::as_object)
            .into_iter()
            .flatten()
        {
            let values = entry
                .as_array()
                .map_or(std::slice::from_ref(entry), Vec::as_slice);
            let keys: Option<Vec<String>> = values
                .iter()
                .map(|v| v.as_str().filter(|s| !s.is_empty()).map(str::to_owned))
                .collect();
            if let Some(keys) = keys.filter(|k| !k.is_empty()) {
                map.events.insert(key.clone(), keys);
            }
        }
        for (key, entry) in audio
            .get("tracks")
            .and_then(Value::as_object)
            .into_iter()
            .flatten()
        {
            if let Some(track) = entry.as_str().filter(|s| !s.is_empty()) {
                map.tracks.insert(key.clone(), track.to_owned());
            }
        }
        map
    }
    pub fn is_empty(&self) -> bool {
        self.music.is_empty() && self.effects.is_empty()
    }
    /// The effect key for a neutral event; a key list selects one by `pick`.
    pub fn effect_key<'a>(&'a self, event: &'a str, pick: i64) -> &'a str {
        match self.events.get(event) {
            Some(keys) => &keys[pick.rem_euclid(keys.len() as i64) as usize],
            None => event,
        }
    }
    pub fn track_key<'a>(&'a self, role: &'a str) -> &'a str {
        self.tracks.get(role).map_or(role, String::as_str)
    }
    pub fn settings_for(&self, track: &str) -> TrackSettings {
        self.music_settings.get(track).copied().unwrap_or_default()
    }
    /// The original plays a map's remote music link as CustomMusic (Audio events 2-4).
    /// Eggshell plays a private copy of it: `dir/index.json` maps each URL to an Ogg
    /// file under `dir` and its SHA-256 (fetch-custom-music.py). A level whose URL
    /// has no copy stays silent, as before. Returns the number of tracks added.
    pub fn add_custom_music(&mut self, dir: &std::path::Path) -> Result<usize, String> {
        let text = std::fs::read_to_string(dir.join("index.json"))
            .map_err(|e| format!("custom music index: {e}"))?;
        let index: Value =
            serde_json::from_str(&text).map_err(|e| format!("custom music index: {e}"))?;
        let mut added = 0;
        for (url, entry) in index
            .get("tracks")
            .and_then(Value::as_object)
            .into_iter()
            .flatten()
        {
            let (Some(file), Some(digest)) = (
                entry.get("file").and_then(safe_file).and_then(ogg_name),
                entry.get("sha256").and_then(Value::as_str),
            ) else {
                continue;
            };
            if !url.starts_with("https://") || self.music.contains_key(url) {
                continue;
            }
            self.music.insert(url.clone(), file.to_owned());
            self.custom
                .insert(url.clone(), (dir.join(file), digest.to_owned()));
            added += 1;
        }
        Ok(added)
    }
    /// A track's bytes: a custom copy checked against its index digest, else the
    /// verified pack file.
    fn track_bytes(&self, key: &str, file: &str, pack: &Pack) -> Result<Vec<u8>, String> {
        match self.custom.get(key) {
            Some((path, digest)) => {
                let bytes = std::fs::read(path).map_err(|e| format!("{path:?}: {e}"))?;
                if crate::pack::hash(&bytes) != *digest {
                    return Err(format!("custom music hash mismatch: {path:?}"));
                }
                Ok(bytes)
            }
            None => pack.verified_bytes(file),
        }
    }
}
fn ogg_name(file: &str) -> Option<&str> {
    std::path::Path::new(file)
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("ogg"))
        .then_some(file)
}

/// The looping level track of one map.
#[derive(Clone, Debug, PartialEq)]
pub struct LevelTrack {
    pub key: String,
    pub loop_start: f64,
    pub volume_db: f64,
}

/// world.gd `music`: the level-code music value as {id, settings, custom}.
fn map_music(value: Option<&PropertyValue>) -> (String, String, bool) {
    match value {
        Some(PropertyValue::Object(fields)) => {
            let text = |name: &str, default: &str| {
                fields
                    .iter()
                    .find(|(k, _)| k == name)
                    .map_or(default.to_owned(), |(_, v)| property_text(v))
            };
            (text("src", ""), text("dat", "0,0"), true)
        }
        Some(PropertyValue::Number(n)) => (number_text(*n), "0,0".into(), false),
        Some(value) => (property_text(value), "0,0".into(), false),
        None => ("0".into(), "0,0".into(), false),
    }
}
fn number_text(n: f64) -> String {
    let text = format!("{n}");
    text.strip_suffix(".0").map_or(text.clone(), str::to_owned)
}
fn property_text(value: &PropertyValue) -> String {
    match value {
        PropertyValue::String(s) => s.clone(),
        PropertyValue::Number(n) => number_text(*n),
        PropertyValue::Bool(b) => b.to_string(),
        PropertyValue::Null => "<null>".into(),
        _ => String::new(),
    }
}
fn settings_number(text: &str) -> f64 {
    text.trim()
        .parse::<f64>()
        .ok()
        .filter(|v| v.is_finite())
        .unwrap_or(0.0)
}

/// audio_player.gd `level_track`: None when the map asks for silence, for an unknown
/// track or for remote music.
pub fn level_track(world: &World, map_index: i64, audio: &AudioMap) -> Option<LevelTrack> {
    let map = usize::try_from(map_index - 1)
        .ok()
        .and_then(|i| world.maps.get(i))?;
    let music = map
        .source_properties
        .iter()
        .find(|(k, _)| k == "music")
        .map(|(_, v)| v);
    let (key, settings, custom) = map_music(music);
    if key.is_empty() || !audio.music.contains_key(&key) {
        return None;
    }
    let pack = audio.settings_for(&key);
    let mut track = LevelTrack {
        key,
        loop_start: pack.loop_start,
        volume_db: pack.volume_db,
    };
    if custom {
        // Custom selections carry "loop_start_seconds,volume_db" from the level code.
        let mut parts = settings.split(',');
        track.loop_start = settings_number(parts.next().unwrap_or("")).max(0.0);
        track.volume_db = settings_number(parts.next().unwrap_or("")).clamp(-60.0, 24.0);
    }
    Some(track)
}

fn volume_gain(volume: i64) -> Option<f32> {
    (volume > 0).then_some(volume as f32 / 100.0)
}
fn db_gain(db: f64) -> f32 {
    10f64.powf(db / 20.0) as f32
}

/// Decoded interleaved 16-bit samples at RATE.
#[derive(Debug)]
pub struct Pcm {
    pub channels: usize,
    pub samples: Vec<i16>,
}
impl Pcm {
    fn frames(&self) -> usize {
        self.samples.len() / self.channels
    }
}

fn reader(bytes: Arc<[u8]>) -> Result<Reader, String> {
    let reader = lewton::inside_ogg::OggStreamReader::new(Cursor::new(bytes))
        .map_err(|e| format!("Ogg Vorbis header: {e:?}"))?;
    let channels = usize::from(reader.ident_hdr.audio_channels);
    if reader.ident_hdr.audio_sample_rate != RATE || !(1..=2).contains(&channels) {
        return Err(format!(
            "unsupported Ogg Vorbis stream: {} Hz, {channels} channels",
            reader.ident_hdr.audio_sample_rate
        ));
    }
    Ok(reader)
}
type Reader = lewton::inside_ogg::OggStreamReader<Cursor<Arc<[u8]>>>;

/// Decodes a whole effect file.
pub fn decode(bytes: Arc<[u8]>) -> Result<Pcm, String> {
    let mut reader = reader(bytes)?;
    let channels = usize::from(reader.ident_hdr.audio_channels);
    let mut samples = Vec::new();
    while let Some(packet) = reader
        .read_dec_packet_itl()
        .map_err(|e| format!("Ogg Vorbis packet: {e:?}"))?
    {
        samples.extend_from_slice(&packet);
    }
    Ok(Pcm { channels, samples })
}

/// Decodes every pack track and effect and reports frames and decode time per file.
pub fn decode_check(pack: &Pack) -> Result<(), String> {
    let map = AudioMap::parse(&pack.manifest);
    let mut files: Vec<_> = map.music.values().chain(map.effects.values()).collect();
    files.sort();
    files.dedup();
    let (mut seconds, mut decode_ms) = (0.0, 0.0);
    for file in &files {
        let bytes = Arc::from(pack.verified_bytes(file)?);
        let start = std::time::Instant::now();
        let pcm = decode(bytes).map_err(|e| format!("{file}: {e}"))?;
        let ms = start.elapsed().as_secs_f64() * 1000.0;
        let length = pcm.frames() as f64 / f64::from(RATE);
        println!(
            "RUST_AUDIO_DECODED file={file} channels={} seconds={length:.3} decode_ms={ms:.1}",
            pcm.channels
        );
        seconds += length;
        decode_ms += ms;
    }
    println!(
        "RUST_AUDIO_DECODE_CHECK_DONE files={} seconds={seconds:.1} decode_ms={decode_ms:.0} realtime_factor={:.1}",
        files.len(),
        seconds * 1000.0 / decode_ms.max(1e-9)
    );
    Ok(())
}

/// Requests from the observer to the mixer.
pub enum Command {
    Effect {
        event: &'static str,
        clip: Arc<Pcm>,
        from_frame: usize,
        gain: f32,
    },
    StopEvent(&'static str),
    StopVoices,
    PauseEvent(&'static str, bool),
    /// A track that streams from its decoder thread (MusicStream::start).
    Music {
        stream: MusicStream,
        gain: f32,
    },
    StopMusic,
}

/// Counters the mixer publishes for the run summary.
#[derive(Debug, Default)]
pub struct MixerStats {
    pub callbacks: AtomicU64,
    pub callback_ns_max: AtomicU64,
    pub effects_started: AtomicU64,
    pub music_started: AtomicU64,
    pub decode_errors: AtomicU64,
}

#[derive(Default)]
struct Voice {
    event: &'static str,
    clip: Option<Arc<Pcm>>,
    position: usize,
    paused: bool,
    gain: f32,
    order: u64,
}

/// One decoded music packet, or what ended the stream.
enum Packet {
    Samples {
        channels: usize,
        samples: Vec<i16>,
    },
    /// A decode error; the stream continues as if the file ended there.
    Error,
    End,
}
/// Decoded packets a music source yields from its start.
trait Packets: Send {
    fn channels(&self) -> usize;
    fn next(&mut self) -> Result<Option<Vec<i16>>, String>;
}
impl Packets for Reader {
    fn channels(&self) -> usize {
        usize::from(self.ident_hdr.audio_channels)
    }
    fn next(&mut self) -> Result<Option<Vec<i16>>, String> {
        self.read_dec_packet_itl()
            .map_err(|e| format!("Ogg Vorbis packet: {e:?}"))
    }
}
type Opener = Box<dyn Fn() -> Result<Box<dyn Packets>, String> + Send>;
/// About 1.4 s of decoded music at most between the decoder thread and the mixer
/// (64 packets of up to 1,024 frames). Memory stays flat whatever the track length.
const STREAM_PACKETS: usize = 64;

/// A music track that streams: a decoder thread reads the Ogg file packet by packet into
/// a short bounded queue, and the mixer plays from it. Only the compressed file stays in
/// memory. At the end of a looping track the thread continues from a second reader that
/// it has already advanced to the loop start, decoding from the file start and counting
/// frames, so the loop point is the same frame as before. It advances that reader while
/// the queue is full, so a loop never waits.
pub struct MusicStream {
    packets: mpsc::Receiver<Packet>,
    current: Vec<i16>,
    channels: usize,
    offset: usize,
}
impl MusicStream {
    pub fn start(bytes: Arc<[u8]>, looping: bool, loop_start: usize) -> Result<Self, String> {
        let first = reader(bytes.clone())?;
        let open: Opener =
            Box::new(move || reader(bytes.clone()).map(|r| Box::new(r) as Box<dyn Packets>));
        Self::spawn(Box::new(first), open, looping, loop_start)
    }
    fn spawn(
        first: Box<dyn Packets>,
        open: Opener,
        looping: bool,
        loop_start: usize,
    ) -> Result<Self, String> {
        let (sender, packets) = mpsc::sync_channel(STREAM_PACKETS);
        std::thread::Builder::new()
            .name("music-decoder".into())
            .spawn(move || decode_stream(first, open, looping, loop_start, sender))
            .map_err(|e| e.to_string())?;
        Ok(Self {
            packets,
            current: Vec::new(),
            channels: 2,
            offset: 0,
        })
    }
}
/// A second reader on its way to the loop start: frames decoded so far, and the samples
/// from the loop start on once it got there.
struct Spare {
    source: Option<Box<dyn Packets>>,
    decoded: usize,
    head: Option<Vec<i16>>,
    failed: bool,
}
impl Spare {
    fn new() -> Self {
        Self {
            source: None,
            decoded: 0,
            head: None,
            failed: false,
        }
    }
    /// One packet of work toward the loop start; false when there is nothing left to do.
    fn advance(&mut self, open: &Opener, target: usize) -> bool {
        if self.head.is_some() || self.failed {
            return false;
        }
        if self.source.is_none() {
            match open() {
                Ok(source) => self.source = Some(source),
                Err(_) => {
                    self.failed = true;
                    return true;
                }
            }
        }
        let Some(source) = self.source.as_mut() else {
            return false;
        };
        let channels = source.channels();
        match source.next() {
            Ok(Some(packet)) => {
                let frames = packet.len() / channels;
                if self.decoded + frames > target {
                    self.head = Some(packet[(target - self.decoded) * channels..].to_vec());
                }
                self.decoded += frames;
            }
            // The loop start is at or past the end (or unreadable): the track ends.
            _ => self.failed = true,
        }
        true
    }
}
fn decode_stream(
    mut source: Box<dyn Packets>,
    open: Opener,
    looping: bool,
    loop_start: usize,
    out: mpsc::SyncSender<Packet>,
) {
    let mut spare = Spare::new();
    // Sends one packet; while the queue is full, prepares the loop instead of waiting.
    let send = |packet: Packet, spare: &mut Spare| -> bool {
        let mut packet = packet;
        loop {
            match out.try_send(packet) {
                Ok(()) => return true,
                Err(mpsc::TrySendError::Disconnected(_)) => return false,
                Err(mpsc::TrySendError::Full(p)) => {
                    packet = p;
                    if !(looping && spare.advance(&open, loop_start)) {
                        return out.send(packet).is_ok();
                    }
                }
            }
        }
    };
    loop {
        let channels = source.channels();
        let ended = match source.next() {
            Ok(Some(samples)) => {
                if !samples.is_empty() && !send(Packet::Samples { channels, samples }, &mut spare) {
                    return;
                }
                false
            }
            Ok(None) => true,
            Err(_) => {
                if !send(Packet::Error, &mut spare) {
                    return;
                }
                true
            }
        };
        if !ended {
            continue;
        }
        if looping {
            while spare.advance(&open, loop_start) {}
        }
        match (looping, spare.head.take(), spare.source.take()) {
            (true, Some(head), Some(next)) => {
                let channels = next.channels();
                source = next;
                spare = Spare::new();
                if !head.is_empty()
                    && !send(
                        Packet::Samples {
                            channels,
                            samples: head,
                        },
                        &mut spare,
                    )
                {
                    return;
                }
            }
            _ => {
                // A one-shot role ends; the observer keeps its role until it changes.
                let _ = out.send(Packet::End);
                return;
            }
        }
    }
}
struct MusicVoice {
    stream: MusicStream,
    gain: f32,
}

/// The SDL audio callback: mixes eight effect voices and one music voice.
pub struct Mixer {
    commands: mpsc::Receiver<Command>,
    voices: [Voice; VOICES],
    order: u64,
    music: Option<MusicVoice>,
    stats: Arc<MixerStats>,
}
impl Mixer {
    pub fn new(commands: mpsc::Receiver<Command>, stats: Arc<MixerStats>) -> Self {
        Self {
            commands,
            voices: Default::default(),
            order: 0,
            music: None,
            stats,
        }
    }
    fn apply(&mut self, command: Command) {
        match command {
            Command::Effect {
                event,
                clip,
                from_frame,
                gain,
            } => {
                // audio_player.gd _play_effect: the event's own voice, else a free voice,
                // else the oldest voice that does not hold the switch timer.
                let chosen = self
                    .voices
                    .iter()
                    .position(|v| v.event == event)
                    .or_else(|| self.voices.iter().position(|v| v.clip.is_none()))
                    .or_else(|| {
                        (0..VOICES)
                            .filter(|&i| !HELD_EVENTS.contains(&self.voices[i].event))
                            .min_by_key(|&i| self.voices[i].order)
                    });
                let Some(chosen) = chosen else { return };
                self.order += 1;
                self.voices[chosen] = Voice {
                    event,
                    clip: Some(clip),
                    position: from_frame,
                    paused: false,
                    gain,
                    order: self.order,
                };
                self.stats.effects_started.fetch_add(1, Ordering::Relaxed);
            }
            Command::StopEvent(event) => {
                for voice in self.voices.iter_mut().filter(|v| v.event == event) {
                    voice.clip = None;
                    voice.event = "";
                }
            }
            Command::StopVoices => {
                for voice in &mut self.voices {
                    voice.clip = None;
                    voice.event = "";
                }
            }
            Command::PauseEvent(event, paused) => {
                for voice in self.voices.iter_mut().filter(|v| v.event == event) {
                    voice.paused = paused;
                }
            }
            Command::Music { stream, gain } => {
                self.music = Some(MusicVoice { stream, gain });
                self.stats.music_started.fetch_add(1, Ordering::Relaxed);
            }
            Command::StopMusic => self.music = None,
        }
    }
    /// Mixes interleaved stereo frames into `out`.
    pub fn mix(&mut self, out: &mut [f32]) {
        while let Ok(command) = self.commands.try_recv() {
            self.apply(command);
        }
        out.fill(0.0);
        let frames = out.len() / 2;
        for voice in &mut self.voices {
            let Some(clip) = &voice.clip else { continue };
            if voice.paused {
                continue;
            }
            let end = clip.frames();
            let count = end.saturating_sub(voice.position).min(frames);
            add(
                out,
                &clip.samples,
                clip.channels,
                voice.position,
                count,
                voice.gain,
            );
            voice.position += count;
            if voice.position >= end {
                // Finished: the voice is free, but keeps its event for its next sound.
                voice.clip = None;
            }
        }
        self.mix_music(out, frames);
    }
    fn mix_music(&mut self, out: &mut [f32], frames: usize) {
        let mut written = 0;
        while written < frames {
            let Some(music) = &mut self.music else { return };
            let stream = &mut music.stream;
            if stream.offset >= stream.current.len() {
                match stream.packets.try_recv() {
                    Ok(Packet::Samples { channels, samples }) => {
                        stream.channels = channels;
                        stream.current = samples;
                        stream.offset = 0;
                    }
                    Ok(Packet::Error) => {
                        self.stats.decode_errors.fetch_add(1, Ordering::Relaxed);
                    }
                    Ok(Packet::End) | Err(mpsc::TryRecvError::Disconnected) => {
                        self.music = None;
                        return;
                    }
                    // The decoder is behind (only at a track start): silence for now.
                    Err(mpsc::TryRecvError::Empty) => return,
                }
                continue;
            }
            let channels = stream.channels;
            let available = (stream.current.len() - stream.offset) / channels;
            let count = available.min(frames - written);
            add(
                &mut out[written * 2..],
                &stream.current,
                channels,
                stream.offset / channels,
                count,
                music.gain,
            );
            stream.offset += count * channels;
            written += count;
        }
    }
}
fn add(out: &mut [f32], samples: &[i16], channels: usize, from: usize, count: usize, gain: f32) {
    let scale = gain / 32768.0;
    for (i, frame) in out.chunks_exact_mut(2).take(count).enumerate() {
        let at = (from + i) * channels;
        let left = f32::from(samples[at]) * scale;
        let right = f32::from(samples[at + channels - 1]) * scale;
        frame[0] += left;
        frame[1] += right;
    }
}
fn clamp(out: &mut [f32]) {
    for sample in out {
        *sample = sample.clamp(-1.0, 1.0);
    }
}

struct Callback {
    mixer: Mixer,
    stats: Arc<MixerStats>,
}
impl sdl2::audio::AudioCallback for Callback {
    type Channel = f32;
    fn callback(&mut self, out: &mut [f32]) {
        let start = std::time::Instant::now();
        self.mixer.mix(out);
        clamp(out);
        self.stats.callbacks.fetch_add(1, Ordering::Relaxed);
        self.stats
            .callback_ns_max
            .fetch_max(start.elapsed().as_nanos() as u64, Ordering::Relaxed);
    }
}

/// Effect files decoded once on a loader thread, by effect key.
struct Effects {
    index: HashMap<String, usize>,
    decoded: Arc<Vec<OnceLock<Arc<Pcm>>>>,
}

/// audio_player.gd playback state on the simulation side: the summary of the previous
/// observed state, the music role and track, and the command channel to the mixer.
pub struct Observer {
    map: AudioMap,
    targets: Targets,
    /// The level track of each map, by zero-based map index.
    level_tracks: Vec<Option<LevelTrack>>,
    music_bytes: HashMap<String, Arc<[u8]>>,
    effects: Effects,
    previous: Summary,
    current: Summary,
    observed: bool,
    replaced: bool,
    cues: Vec<Cue>,
    music_role: String,
    music_track: String,
    music_gain: Option<f32>,
    effects_gain: Option<f32>,
    out: Option<mpsc::Sender<Command>>,
    timer_paused: bool,
    /// How many states this observer has derived from; one per simulation step.
    pub observations: u64,
    /// Derived effect cues by event, for the run summary.
    pub heard: std::collections::BTreeMap<&'static str, u64>,
    pub missing_clips: u64,
}
impl Observer {
    /// Without pack audio or a mixer, cues are still derived and nothing plays.
    pub fn new(
        map: AudioMap,
        world: &World,
        pack: Option<&Pack>,
        out: Option<mpsc::Sender<Command>>,
    ) -> Result<Self, String> {
        let level_tracks: Vec<_> = (1..=world.maps.len() as i64)
            .map(|index| level_track(world, index, &map))
            .collect();
        let mut music_bytes = HashMap::new();
        let mut effects = Effects {
            index: HashMap::new(),
            decoded: Arc::new(Vec::new()),
        };
        let out = out.filter(|_| !map.is_empty());
        if let (Some(pack), Some(_)) = (pack, &out) {
            // Only the tracks this level can play: its map tracks and the music roles.
            let keys = level_tracks
                .iter()
                .flatten()
                .map(|t| t.key.clone())
                .chain(["death", "goal"].map(|role| map.track_key(role).to_owned()));
            for key in keys {
                if let (Some(file), std::collections::hash_map::Entry::Vacant(slot)) =
                    (map.music.get(&key), music_bytes.entry(key.clone()))
                {
                    match map.track_bytes(&key, file, pack) {
                        Ok(bytes) => {
                            slot.insert(Arc::from(bytes));
                        }
                        // A broken custom copy leaves the level silent, never unplayable.
                        Err(e) if map.custom.contains_key(&key) => {
                            eprintln!("RUST_AUDIO_ERROR custom_music {e}");
                        }
                        Err(e) => return Err(e),
                    }
                }
            }
            let mut files: Vec<_> = map.effects.iter().collect();
            files.sort();
            let mut bytes = Vec::with_capacity(files.len());
            for (i, (key, file)) in files.iter().enumerate() {
                effects.index.insert((*key).clone(), i);
                bytes.push(Arc::<[u8]>::from(pack.verified_bytes(file)?));
            }
            let decoded: Arc<Vec<OnceLock<Arc<Pcm>>>> =
                Arc::new((0..files.len()).map(|_| OnceLock::new()).collect());
            effects.decoded = decoded.clone();
            let names: Vec<String> = files.iter().map(|(k, _)| (*k).clone()).collect();
            std::thread::Builder::new()
                .name("effect-decoder".into())
                .spawn(move || {
                    for (i, bytes) in bytes.into_iter().enumerate() {
                        match decode(bytes) {
                            Ok(pcm) => {
                                let _ = decoded[i].set(Arc::new(pcm));
                            }
                            Err(e) => eprintln!("RUST_AUDIO_ERROR effect={} {e}", names[i]),
                        }
                    }
                })
                .map_err(|e| e.to_string())?;
        }
        Ok(Self {
            map,
            targets: Targets {
                redcoins: world.redcoins_target,
                flowers: world.flowers_target,
            },
            level_tracks,
            music_bytes,
            effects,
            previous: Summary::default(),
            current: Summary::default(),
            observed: false,
            replaced: false,
            cues: Vec::new(),
            music_role: String::new(),
            music_track: String::new(),
            music_gain: volume_gain(MUSIC_VOLUME),
            effects_gain: volume_gain(EFFECTS_VOLUME),
            out,
            timer_paused: false,
            observations: 0,
            heard: Default::default(),
            missing_clips: 0,
        })
    }
    pub fn muted(&self) -> bool {
        self.out.is_none()
    }
    /// The state was replaced, for example by a restore: the next observation
    /// resynchronizes without cues.
    pub fn replaced(&mut self) {
        self.replaced = true;
    }
    /// True after the goal: game.gd stops stepping, so nothing more is observed.
    pub fn goal_reached(&self) -> bool {
        self.observed && self.previous[W::goal_reached] != 0
    }
    /// Cues derived by the last observation; empty after a resynchronization.
    pub fn last_cues(&self) -> &[Cue] {
        &self.cues
    }
    /// Feed the state once per simulation step (audio_player.gd `observe`).
    pub fn observe(&mut self, state: &dyn SavedState) {
        if self.goal_reached() && !self.replaced {
            return;
        }
        self.observations += 1;
        self.current.read(state);
        let (p, c) = (&self.previous, &self.current);
        let continuous = self.observed
            && !self.replaced
            && c[W::frame] > p[W::frame]
            && c[W::frame] - p[W::frame] <= MAX_STEP_GAP;
        self.cues.clear();
        if continuous {
            derive(p, c, self.targets, &mut self.cues);
        }
        std::mem::swap(&mut self.previous, &mut self.current);
        self.observed = true;
        self.replaced = false;
        for cue in &self.cues {
            if let Cue::Effect(event) = cue {
                *self.heard.entry(*event).or_default() += 1;
            }
        }
        if self.out.is_none() {
            return;
        }
        let mut timer_started = false;
        if !continuous {
            timer_started = self.resync();
        } else {
            let cues = std::mem::take(&mut self.cues);
            for cue in &cues {
                timer_started |= self.apply(*cue);
            }
            self.cues = cues;
            self.update_music();
        }
        let paused = self.previous[W::message_stage] != 0;
        if paused != self.timer_paused || (paused && timer_started) {
            self.send(Command::PauseEvent("switch_timer", paused));
            self.timer_paused = paused;
        }
    }
    /// Starts a track's decoder thread here (not in the audio callback) and hands the
    /// stream to the mixer. A file whose header does not decode plays nothing.
    fn start_music(&self, bytes: Arc<[u8]>, looping: bool, loop_start: usize, gain: f32) {
        if self.out.is_none() {
            return;
        }
        match MusicStream::start(bytes, looping, loop_start) {
            Ok(stream) => self.send(Command::Music { stream, gain }),
            Err(e) => eprintln!("RUST_AUDIO_ERROR music {e}"),
        }
    }
    fn send(&self, command: Command) {
        if let Some(out) = &self.out {
            // A closed device only means no more sound.
            let _ = out.send(command);
        }
    }
    fn resync(&mut self) -> bool {
        self.send(Command::StopVoices);
        // A one-shot role belongs to the old timeline. The same level track keeps playing.
        if !self.music_role.is_empty() {
            self.send(Command::StopMusic);
            self.music_role.clear();
            self.music_track.clear();
        }
        self.update_music();
        let c = &self.previous;
        if c[W::switch_ticks] > 0 && !QUIET_PHASES.contains(&c[W::life_phase]) {
            let seconds = (SWITCH_TICKS - c[W::switch_ticks]) as f64 / 60.0;
            return self.play_effect("switch_timer", seconds);
        }
        false
    }
    fn update_music(&mut self) {
        let current = &self.previous;
        if QUIET_PHASES.contains(&current[W::life_phase]) {
            if !self.music_role.is_empty() || self.music_track.is_empty() {
                return;
            }
            self.send(Command::StopMusic);
            self.music_track.clear();
            return;
        }
        let track = usize::try_from(current[W::map_index] - 1)
            .ok()
            .and_then(|i| self.level_tracks.get(i))
            .cloned()
            .flatten();
        let key = track.as_ref().map_or("", |t| t.key.as_str());
        if key == self.music_track && self.music_role.is_empty() {
            return;
        }
        self.send(Command::StopMusic);
        self.music_role.clear();
        self.music_track = key.to_owned();
        let (Some(track), Some(gain)) = (track, self.music_gain) else {
            return;
        };
        let Some(bytes) = self.music_bytes.get(&track.key).cloned() else {
            return;
        };
        self.start_music(
            bytes,
            true,
            (track.loop_start * f64::from(RATE)).round() as usize,
            gain * db_gain(track.volume_db),
        );
        println!("EGGSHELL_MUSIC {}", track.key);
    }
    /// True when it started the switch timer.
    fn apply(&mut self, cue: Cue) -> bool {
        match cue {
            Cue::Effect(event) => return self.play_effect(event, 0.0),
            Cue::StopEffect(event) => self.send(Command::StopEvent(event)),
            Cue::StopAll => {
                self.send(Command::StopVoices);
                self.send(Command::StopMusic);
                self.music_track.clear();
                self.music_role.clear();
            }
            Cue::StopMusic => {
                self.send(Command::StopMusic);
                self.music_track.clear();
                self.music_role.clear();
            }
            Cue::Role(role) => self.play_role(role),
        }
        false
    }
    fn play_role(&mut self, role: &str) {
        self.send(Command::StopMusic);
        self.music_track.clear();
        self.music_role = role.to_owned();
        let key = self.map.track_key(role).to_owned();
        let (Some(bytes), Some(gain)) = (self.music_bytes.get(&key).cloned(), self.music_gain)
        else {
            return;
        };
        self.start_music(
            bytes,
            false,
            0,
            gain * db_gain(self.map.settings_for(&key).volume_db),
        );
        println!("EGGSHELL_MUSIC {key}");
    }
    fn play_effect(&mut self, event: &'static str, from_seconds: f64) -> bool {
        let Some(gain) = self.effects_gain else {
            return false;
        };
        let key = self.map.effect_key(event, self.previous[W::frame]);
        let Some(&index) = self.effects.index.get(key) else {
            return false;
        };
        let Some(clip) = self.effects.decoded[index].get().cloned() else {
            // Still decoding at startup.
            self.missing_clips += 1;
            return false;
        };
        self.send(Command::Effect {
            event,
            clip,
            from_frame: (from_seconds * f64::from(RATE)).round() as usize,
            gain,
        });
        event == "switch_timer"
    }
}

/// The open SDL playback device. Dropping it closes the device.
pub struct Device {
    device: sdl2::audio::AudioDevice<Callback>,
    pub driver: String,
    pub stats: Arc<MixerStats>,
    paused: bool,
}
impl Device {
    /// Opens 48 kHz stereo playback. SDL converts for the actual device.
    pub fn open(sdl: &sdl2::Sdl) -> Result<(Self, mpsc::Sender<Command>), String> {
        let audio = sdl.audio()?;
        let (sender, receiver) = mpsc::channel();
        let stats = Arc::new(MixerStats::default());
        let desired = sdl2::audio::AudioSpecDesired {
            freq: Some(RATE as i32),
            channels: Some(2),
            samples: Some(1024),
        };
        let mixer = Mixer::new(receiver, stats.clone());
        let device = audio.open_playback(None, &desired, |_| Callback {
            mixer,
            stats: stats.clone(),
        })?;
        device.resume();
        let driver = audio.current_audio_driver().to_owned();
        Ok((
            Self {
                device,
                driver,
                stats,
                paused: false,
            },
            sender,
        ))
    }
    /// Sounds wait while the game is paused (game.gd open_menu).
    pub fn set_paused(&mut self, paused: bool) {
        if paused != self.paused {
            if paused {
                self.device.pause();
            } else {
                self.device.resume();
            }
            self.paused = paused;
        }
    }
    pub fn summary(&self) -> Value {
        let spec = self.device.spec();
        serde_json::json!({
            "driver": self.driver,
            "freq": spec.freq,
            "channels": spec.channels,
            "samples": spec.samples,
            "callbacks": self.stats.callbacks.load(Ordering::Relaxed),
            "callback_ns_max": self.stats.callback_ns_max.load(Ordering::Relaxed),
            "effects_started": self.stats.effects_started.load(Ordering::Relaxed),
            "music_started": self.stats.music_started.load(Ordering::Relaxed),
            "decode_errors": self.stats.decode_errors.load(Ordering::Relaxed),
        })
    }
}

#[cfg(test)]
mod tests {
    //! Ported from tests/audio.gd: derivation from synthetic state pairs.
    use super::*;

    struct State {
        fields: HashMap<&'static str, i64>,
        rows: Vec<(&'static str, Vec<(&'static str, i64)>)>,
    }
    impl SavedState for State {
        fn field(&self, name: &str) -> Option<i64> {
            self.fields.get(name).copied()
        }
        fn rows(&self, visit: &mut RowVisitor) {
            for (code, fields) in &self.rows {
                visit(code, &|n| {
                    fields.iter().find(|(k, _)| *k == n).map(|(_, v)| *v)
                });
            }
        }
    }
    fn summarize(fields: &[(&'static str, i64)]) -> Summary {
        let mut s = Summary::default();
        s.read(&State {
            fields: fields.iter().copied().collect(),
            rows: Vec::new(),
        });
        s
    }
    fn base() -> Summary {
        summarize(&[("frame", 100)])
    }
    fn set(s: &mut Summary, name: &str, value: i64) {
        let i = WATCHED.iter().position(|(n, _)| *n == name).unwrap();
        s.values[i] = value;
    }
    fn after(previous: &Summary, changes: &[(&str, i64)]) -> Summary {
        let mut current = previous.clone();
        current[W::frame] = previous[W::frame] + 1;
        for (k, v) in changes {
            set(&mut current, k, *v);
        }
        current
    }
    fn names(p: &Summary, c: &Summary, targets: Targets) -> Vec<&'static str> {
        let mut cues = Vec::new();
        derive(p, c, targets, &mut cues);
        cues.iter().map(Cue::name).collect()
    }
    fn expect(changes: &[(&str, i64)], expected: &[&str], start: &[(&str, i64)]) {
        let mut previous = base();
        for (k, v) in start {
            set(&mut previous, k, *v);
        }
        let got = names(
            &previous,
            &after(&previous, changes),
            Targets {
                redcoins: 5,
                flowers: 5,
            },
        );
        assert_eq!(got, expected, "changes {changes:?} from {start:?}");
    }

    #[test]
    fn derivation_checks() {
        let idle = base();
        assert!(names(&idle, &after(&idle, &[]), Targets::default()).is_empty());
        assert!(idle[W::health] == 10 && idle[W::map_index] == 1);
        expect(
            &[("vy", -46000), ("move_pound_delay", 6)],
            &["jump"],
            &[("on_floor", 1)],
        );
        expect(
            &[
                ("vy", -40000),
                ("boosted_flutter", 1),
                ("move_pound_delay", 6),
            ],
            &["stomp"],
            &[("vy", 3000)],
        );
        expect(
            &[
                ("vy", -60480),
                ("boosted_flutter", 1),
                ("switch_sound_serial", 2),
                ("switch_sound_kind", 2),
            ],
            &["switch_timer"],
            &[("switch_sound_serial", 1)],
        );
        expect(
            &[
                ("vy", -23040),
                ("invulnerable", 120),
                ("move_pound_delay", 6),
            ],
            &["hit"],
            &[],
        );
        expect(&[("flutter_remaining", 40)], &["flutter"], &[]);
        expect(
            &[("flutter_remaining", 39)],
            &[],
            &[("flutter_remaining", 40)],
        );
        expect(&[("move_action", POUND_START)], &["pound_start"], &[]);
        expect(&[("move_impact", 1)], &["pound_land"], &[]);
        expect(&[("move_action", TONGUE)], &["tongue"], &[]);
        expect(&[("move_action", TOSS)], &["egg_throw"], &[]);
        expect(&[("move_action", HEAD_BUMP)], &["head_bump"], &[]);
        expect(&[("swimming", 1)], &["splash"], &[]);
        expect(&[("swimming", 0)], &["splash"], &[("swimming", 1)]);
        expect(&[("move_eggs", 2)], &["egg_pickup"], &[("move_eggs", 1)]);
        expect(
            &[
                ("move_eggs", 2),
                ("move_emit_serial", 1),
                ("move_emit_kind", STORED_EGG),
            ],
            &["egg_made"],
            &[("move_eggs", 1)],
        );
        expect(
            &[
                ("move_emit_serial", 3),
                ("move_emit_kind", 5),
                ("move_emit_1_kind", 4),
                ("move_emit_2_kind", 2),
            ],
            &["spit_ice", "spit_fire"],
            &[("move_emit_serial", 1), ("move_emit_kind", 2)],
        );
        expect(
            &[("move_emit_serial", 2), ("move_emit_kind", 3)],
            &["spit_seed"],
            &[("move_emit_serial", 1)],
        );
        expect(
            &[("move_emit_serial", 0), ("move_emit_kind", 0)],
            &[],
            &[("move_emit_serial", 4), ("move_emit_kind", 2)],
        );
        let mut aiming = base();
        set(&mut aiming, "move_aim", 1);
        set(&mut aiming, "frame", 102);
        let mut ticks = 0;
        for _ in 0..8 {
            let next = after(&aiming, &[]);
            ticks += names(&aiming, &next, Targets::default())
                .iter()
                .filter(|e| **e == "aim_tick")
                .count();
            aiming = next;
        }
        assert_eq!(ticks, 2, "aim ticks every four frames");
        expect(&[("coins", 1)], &["coin"], &[]);
        expect(&[("redcoins", 3)], &["red_coin"], &[("redcoins", 2)]);
        expect(&[("redcoins", 5)], &["all_red_coins"], &[("redcoins", 4)]);
        expect(&[("flowers", 2)], &["flower"], &[("flowers", 1)]);
        expect(
            &[("flowers", 5)],
            &["flower", "all_flowers"],
            &[("flowers", 4)],
        );
        expect(
            &[("switch_sound_serial", 4), ("switch_sound_kind", 1)],
            &["switch_press"],
            &[("switch_sound_serial", 3)],
        );
        let mut cues = Vec::new();
        derive(
            &base(),
            &after(
                &base(),
                &[("switch_sound_serial", 1), ("switch_sound_kind", 3)],
            ),
            Targets::default(),
            &mut cues,
        );
        assert_eq!(cues, [Cue::StopEffect("switch_timer")]);
        expect(&[("message_stage", 1)], &["message_hit"], &[]);
        expect(
            &[("message_stage", 2)],
            &["message_open"],
            &[("message_stage", 1)],
        );
        expect(
            &[("message_section", 1)],
            &["message_scroll"],
            &[("message_stage", 2)],
        );
        expect(
            &[("message_stage", 3)],
            &["message_close"],
            &[("message_stage", 2)],
        );
        expect(
            &[
                ("move_snow", 1),
                ("on_floor", 1),
                ("vx", 3000),
                ("frame", 108),
            ],
            &["snow_step"],
            &[("frame", 107)],
        );
    }

    #[test]
    fn pad_launch_after_an_enemy_bounce_is_not_a_stomp() {
        let mut pad = base();
        set(&mut pad, "vy", 3000);
        set(&mut pad, "boosted_flutter", 1);
        pad.objects = vec![Row {
            token: 5,
            code: O11,
            values: [0; 3],
        }];
        let mut sprung = after(&pad, &[("vy", -23040)]);
        sprung.objects[0].values[0] = 12;
        assert_eq!(names(&pad, &sprung, Targets::default()), ["spring"]);
    }

    fn rows_state(frame: i64, rows: &[(&'static str, &[(&'static str, i64)])]) -> Summary {
        let mut s = Summary::default();
        s.read(&State {
            fields: [("frame", frame)].into_iter().collect(),
            rows: rows.iter().map(|(c, f)| (*c, f.to_vec())).collect(),
        });
        s
    }

    #[test]
    fn object_checks() {
        let before = rows_state(
            50,
            &[
                ("o7", &[("token", 1000001), ("mode", 1), ("bounces", 4)]),
                (
                    "o8",
                    &[("token", 2), ("phase", 0), ("status", 1), ("content", 2)],
                ),
                (
                    "o8",
                    &[("token", 3), ("phase", 1), ("status", 1), ("content", 1)],
                ),
                ("o9", &[("token", 4), ("busy", 7)]),
                ("o11", &[("token", 5), ("squash", 0)]),
                ("o31", &[("token", 6), ("opened", 0)]),
                ("e4", &[("token", 7), ("status", 1)]),
            ],
        );
        assert!(before.objects.len() == 6 && before.eggs == 1);
        let state = [
            ("o7", &[("token", 1000001), ("mode", 1), ("bounces", 3)][..]),
            (
                "o8",
                &[("token", 2), ("phase", 2), ("status", 1), ("content", 2)],
            ),
            (
                "o8",
                &[("token", 3), ("phase", 3), ("status", 1), ("content", 1)],
            ),
            ("o9", &[("token", 4), ("busy", 6)]),
            ("o11", &[("token", 5), ("squash", 12)]),
            ("o31", &[("token", 6), ("opened", 1)]),
            ("e4", &[("token", 7), ("status", 1)]),
            ("o7", &[("token", 1000002), ("mode", 1), ("bounces", 4)]),
        ];
        let now = rows_state(51, &state);
        assert_eq!(
            names(&before, &now, Targets::default()),
            [
                "egg_bounce",
                "egg_ricochet",
                "cloud_reveal",
                "cloud_hit",
                "egg_block",
                "spring",
                "gate_open"
            ]
        );
        let mut later = state;
        later[2] = (
            "o8",
            &[("token", 3), ("phase", 3), ("status", 3), ("content", 1)],
        );
        later[4] = ("o11", &[("token", 5), ("squash", 11)]);
        let next = rows_state(52, &later);
        assert_eq!(names(&now, &next, Targets::default()), ["cloud_release"]);
        let mut replaced = later;
        replaced[0] = ("o9", &[("token", 1000001), ("busy", 0)]);
        assert!(names(&next, &rows_state(53, &replaced), Targets::default()).is_empty());
    }

    #[test]
    fn life_checks() {
        expect(&[("life_phase", DEAD)], &["stop_all", "death"], &[]);
        expect(
            &[("life_phase", FADE_OUT)],
            &["stop_all", "quick_death"],
            &[],
        );
        expect(&[("life_phase", FADE_OUT)], &[], &[("life_phase", DEAD)]);
        expect(&[("life_phase", GOAL)], &["stop_music", "goal"], &[]);
        expect(&[("life_phase", REJOIN)], &["rescue"], &[]);
        expect(
            &[("life_phase", PLAY)],
            &["rejoin"],
            &[("life_phase", REJOIN)],
        );
        expect(
            &[
                ("life_phase", FADE_IN),
                ("redcoins", 0),
                ("flowers", 0),
                ("health", 10),
                ("swimming", 0),
            ],
            &[],
            &[
                ("life_phase", FADE_OUT),
                ("redcoins", 3),
                ("flowers", 2),
                ("health", 4),
                ("swimming", 1),
            ],
        );
        expect(
            &[("health", 9), ("health_wait", 45)],
            &["countdown_low"],
            &[("separated", 1), ("health", 10), ("health_wait", 1)],
        );
        expect(
            &[("health", 11), ("health_wait", 45)],
            &["countdown_high"],
            &[("separated", 1), ("health", 12), ("health_wait", 1)],
        );
        expect(
            &[("health", 10), ("health_wait", 0)],
            &["countdown_full"],
            &[("health", 9), ("health_wait", 1)],
        );
        expect(
            &[("health", 9), ("health_wait", 119)],
            &[],
            &[("health", 8), ("health_wait", 1)],
        );
        expect(&[("health", 11)], &["star"], &[]);
        expect(
            &[("health", 12)],
            &["star"],
            &[("health", 11), ("separated", 1)],
        );
        expect(
            &[
                ("life_phase", CHECKPOINT),
                ("health", 11),
                ("checkpoint_awards", 9),
                ("life_ticks", 6),
            ],
            &["star"],
            &[
                ("life_phase", CHECKPOINT),
                ("health", 10),
                ("checkpoint_awards", 10),
                ("life_ticks", 0),
            ],
        );
        expect(
            &[
                ("life_phase", CHECKPOINT),
                ("health", 20),
                ("checkpoint_awards", 0),
                ("life_ticks", 45),
            ],
            &["checkpoint"],
            &[
                ("life_phase", CHECKPOINT),
                ("health", 19),
                ("checkpoint_awards", 1),
                ("life_ticks", 0),
            ],
        );
        expect(
            &[("companion_mode", BUBBLE)],
            &["companion_cry"],
            &[("companion_mode", 1)],
        );
    }

    fn manifest(audio: Value) -> AudioMap {
        AudioMap::parse(&serde_json::json!({ "audio": audio }))
    }

    #[test]
    fn map_checks() {
        assert!(AudioMap::default().is_empty());
        let audio = manifest(serde_json::json!({
            "music": {
                "1": {"file": "audio/a.ogg", "loop_start": -1, "volume_db": "loud"},
                "2": {"file": "../escape.ogg"},
                "3": "audio/c.wav",
                "4": {"loop_start": 3}
            },
            "effects": {"hop": "audio/hop.ogg", "bad": 7},
            "events": {
                "jump": "hop",
                "turns": ["a", "b", "c"],
                "empty": "",
                "number": 3,
                "mixed": ["a", 4]
            },
            "tracks": {"goal": "4"}
        }));
        assert_eq!(audio.music.keys().collect::<Vec<_>>(), ["1"]);
        assert_eq!(audio.settings_for("1"), TrackSettings::default());
        assert_eq!(audio.effects.keys().collect::<Vec<_>>(), ["hop"]);
        assert_eq!(audio.effect_key("jump", 0), "hop");
        assert_eq!(audio.effect_key("coin", 0), "coin");
        assert_eq!(audio.effect_key("empty", 0), "empty");
        assert_eq!(audio.effect_key("mixed", 0), "mixed");
        let turns: Vec<_> = [0, 1, 2, 3, -1]
            .iter()
            .map(|p| audio.effect_key("turns", *p))
            .collect();
        assert_eq!(turns, ["a", "b", "c", "a", "c"]);
        assert!(audio.track_key("goal") == "4" && audio.track_key("death") == "death");
        let bad = AudioMap::parse(&serde_json::json!({"audio": ["wrong"]}));
        assert!(bad.is_empty() && bad.events.is_empty());
    }

    #[test]
    fn level_checks() {
        let audio = manifest(serde_json::json!({
            "music": {
                "1": {"file": "audio/one.ogg", "loop_start": 1.5, "volume_db": -2},
                "named": "audio/named.ogg"
            }
        }));
        let level = |music: &str| {
            format!(
                r#"{{"version":"1","name":"t","desc":"","author":"t","startpoint":{{"map":1,"X":32,"Y":32}},"maps":{{"map1":{{"width":640,"height":480,"objects":{{}}{music}}}}}}}"#
            )
        };
        let collision = r#"{"version":2,"tilemaps":{}}"#;
        let track = |music: &str| {
            let world = World::compile(&level(music), collision).unwrap();
            level_track(&world, 1, &audio)
        };
        assert_eq!(
            track(r#","music":1"#),
            Some(LevelTrack {
                key: "1".into(),
                loop_start: 1.5,
                volume_db: -2.0
            })
        );
        assert_eq!(track(r#","music":0"#), None);
        assert_eq!(
            track(r#","music":{"src":"https://example.invalid/a.ogg","dat":"2,-5"}"#),
            None
        );
        assert_eq!(
            track(r#","music":{"src":"named","dat":"2.5,-5"}"#),
            Some(LevelTrack {
                key: "named".into(),
                loop_start: 2.5,
                volume_db: -5.0
            })
        );
        assert_eq!(track(""), None);
    }

    #[test]
    fn custom_music_plays_the_private_copy_with_the_level_settings() {
        let dir = std::env::temp_dir().join(format!("custom-music-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("tracks")).unwrap();
        std::fs::write(dir.join("tracks/a.ogg"), b"not really ogg").unwrap();
        let digest = crate::pack::hash(b"not really ogg");
        std::fs::write(
            dir.join("index.json"),
            serde_json::json!({"tracks": {
                "https://example.invalid/a.mp3": {"file": "tracks/a.ogg", "sha256": digest},
                "https://example.invalid/escape": {"file": "../x.ogg", "sha256": digest},
                "http://example.invalid/plain": {"file": "tracks/a.ogg", "sha256": digest}
            }})
            .to_string(),
        )
        .unwrap();
        let mut audio = manifest(serde_json::json!({"music": {"1": "audio/one.ogg"}}));
        assert_eq!(audio.add_custom_music(&dir).unwrap(), 1);
        let level = r#"{"version":"1","name":"t","desc":"","author":"t","startpoint":{"map":1,"X":32,"Y":32},"maps":{"map1":{"width":640,"height":480,"objects":{},"music":{"src":"https://example.invalid/a.mp3","dat":"2.5,-5"}}}}"#;
        let world = World::compile(level, r#"{"version":2,"tilemaps":{}}"#).unwrap();
        assert_eq!(
            level_track(&world, 1, &audio),
            Some(LevelTrack {
                key: "https://example.invalid/a.mp3".into(),
                loop_start: 2.5,
                volume_db: -5.0
            })
        );
        let (path, want) = audio.custom["https://example.invalid/a.mp3"].clone();
        assert_eq!(crate::pack::hash(&std::fs::read(&path).unwrap()), want);
        // A changed copy is refused by its digest.
        std::fs::write(dir.join("tracks/a.ogg"), b"changed").unwrap();
        let pack_less = audio.custom.get("https://example.invalid/a.mp3").unwrap();
        assert_ne!(
            crate::pack::hash(&std::fs::read(&pack_less.0).unwrap()),
            pack_less.1
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    struct Fields(HashMap<&'static str, i64>);
    impl SavedState for Fields {
        fn field(&self, name: &str) -> Option<i64> {
            self.0.get(name).copied()
        }
        fn rows(&self, _: &mut RowVisitor) {}
    }

    #[test]
    fn observer_checks() {
        let world = World::compile(
            r#"{"version":"1","name":"t","desc":"","author":"t","redcoins":2,"startpoint":{"map":1,"X":32,"Y":32},"maps":{"map1":{"width":640,"height":480,"objects":{}}}}"#,
            r#"{"version":2,"tilemaps":{}}"#,
        )
        .unwrap();
        let mut player = Observer::new(AudioMap::default(), &world, None, None).unwrap();
        let mut state = Fields([("frame", 10), ("coins", 0)].into_iter().collect());
        player.observe(&state);
        assert!(
            player.last_cues().is_empty(),
            "the first observation only synchronizes"
        );
        state.0.insert("frame", 11);
        state.0.insert("coins", 1);
        player.observe(&state);
        assert_eq!(player.last_cues(), [Cue::Effect("coin")]);
        let mut restored = Fields(
            [("frame", 12), ("coins", 5), ("redcoins", 2)]
                .into_iter()
                .collect(),
        );
        player.replaced();
        player.observe(&restored);
        assert!(
            player.last_cues().is_empty(),
            "a replaced state never replays sounds"
        );
        restored.0.insert("frame", 13);
        restored.0.insert("redcoins", 3);
        player.observe(&restored);
        assert_eq!(player.last_cues(), [Cue::Effect("all_red_coins")]);
        restored.0.insert("frame", 40);
        restored.0.insert("coins", 6);
        player.observe(&restored);
        assert!(
            player.last_cues().is_empty(),
            "a jump in time resynchronizes"
        );
        restored.0.insert("frame", 30);
        restored.0.insert("coins", 7);
        player.observe(&restored);
        assert!(
            player.last_cues().is_empty(),
            "time going back resynchronizes"
        );
        restored.0.insert("frame", 31);
        restored.0.insert("goal_reached", 1);
        player.observe(&restored);
        restored.0.insert("frame", 32);
        restored.0.insert("coins", 8);
        let seen = player.observations;
        player.observe(&restored);
        assert_eq!(
            player.observations, seen,
            "nothing is observed after the goal"
        );
    }

    #[test]
    fn mixer_reuses_the_events_voice_and_keeps_the_switch_timer() {
        let (send, receive) = mpsc::channel();
        let mut mixer = Mixer::new(receive, Arc::default());
        let clip = Arc::new(Pcm {
            channels: 1,
            samples: vec![1000; 48_000],
        });
        let effect = |event| Command::Effect {
            event,
            clip: clip.clone(),
            from_frame: 0,
            gain: 1.0,
        };
        send.send(effect("switch_timer")).unwrap();
        for event in ["a", "b", "c", "d", "e", "f", "g"] {
            send.send(effect(event)).unwrap();
        }
        send.send(effect("a")).unwrap();
        send.send(effect("h")).unwrap();
        let mut out = vec![0.0; 256];
        mixer.mix(&mut out);
        let events: Vec<_> = mixer.voices.iter().map(|v| v.event).collect();
        // "a" restarted its own voice; "h" took the oldest voice that is not the timer.
        assert_eq!(events, ["switch_timer", "a", "h", "c", "d", "e", "f", "g"]);
        assert!((out[0] - 8.0 * 1000.0 / 32768.0).abs() < 1e-6);
    }

    /// A fake source: `packets` packets of `size` stereo frames whose left sample is the
    /// frame number (mod 32768) from the file start.
    struct Counting {
        packets: usize,
        size: usize,
        sent: usize,
    }
    impl Packets for Counting {
        fn channels(&self) -> usize {
            2
        }
        fn next(&mut self) -> Result<Option<Vec<i16>>, String> {
            if self.sent == self.packets {
                return Ok(None);
            }
            let first = self.sent * self.size;
            self.sent += 1;
            Ok(Some(
                (first..first + self.size)
                    .flat_map(|f| [(f % 32768) as i16, 0])
                    .collect(),
            ))
        }
    }
    fn counting_stream(
        packets: usize,
        size: usize,
        looping: bool,
        loop_start: usize,
    ) -> MusicStream {
        let source = move || Counting {
            packets,
            size,
            sent: 0,
        };
        let open: Opener = Box::new(move || Ok(Box::new(source()) as Box<dyn Packets>));
        MusicStream::spawn(Box::new(source()), open, looping, loop_start).unwrap()
    }
    /// The left samples the stream delivers, in order, until it ends or `frames` arrived.
    fn left_samples(stream: &MusicStream, frames: usize) -> (Vec<i64>, bool) {
        let mut left = Vec::new();
        while left.len() < frames {
            match stream.packets.recv() {
                Ok(Packet::Samples { samples, .. }) => {
                    left.extend(samples.iter().step_by(2).map(|v| i64::from(*v)))
                }
                Ok(Packet::Error) => {}
                Ok(Packet::End) | Err(_) => return (left, true),
            }
        }
        (left, false)
    }

    #[test]
    fn music_loops_back_to_its_loop_start() {
        // 20 frames in packets of 4, looping from frame 6 (inside the second packet).
        let (left, ended) = left_samples(&counting_stream(5, 4, true, 6), 48);
        let mut want: Vec<i64> = (0..20).collect();
        want.extend(6..20);
        want.extend(6..20);
        assert!(!ended);
        assert_eq!(left[..48], want[..48]);
    }

    #[test]
    fn the_mixer_plays_the_stream_at_its_gain() {
        let mut mixer = Mixer::new(mpsc::channel().1, Arc::default());
        mixer.music = Some(MusicVoice {
            stream: counting_stream(5, 4, true, 6),
            gain: 32768.0,
        });
        let mut left = Vec::new();
        for _ in 0..2000 {
            let mut out = vec![0.0; 2 * 3];
            mixer.mix(&mut out);
            left.extend(out.iter().step_by(2).map(|v| *v as i64));
            if left.iter().filter(|v| **v == 19).count() == 2 {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        // Silence while the decoder starts, then frames 1..19, then the loop from 6.
        let heard: Vec<i64> = left.into_iter().skip_while(|v| *v == 0).collect();
        let mut want: Vec<i64> = (1..20).collect();
        want.extend(6..20);
        assert_eq!(heard[..want.len()], want[..]);
    }

    #[test]
    fn a_one_shot_track_ends_and_a_loop_start_past_the_end_stops() {
        let (left, ended) = left_samples(&counting_stream(3, 4, false, 0), 100);
        assert!(ended && left == (0..12).collect::<Vec<_>>());
        let (left, ended) = left_samples(&counting_stream(3, 4, true, 12), 100);
        assert!(ended && left.len() == 12);
    }

    #[test]
    fn a_long_track_loops_exactly_with_a_short_queue() {
        // A 21-minute track (60,000 packets of 1,024 frames) looping from packet 59,990
        // plus 100 frames. Nothing holds more than one packet outside the bounded queue.
        let size = 1024;
        let total = 60_000 * size;
        let start = size * 59_990 + 100;
        let stream = counting_stream(60_000, size, true, start);
        let wrap = |f: usize| (f % 32768) as i64;
        let (mut frame, mut around) = (0usize, Vec::new());
        while frame < total + 3 {
            match stream.packets.recv().unwrap() {
                Packet::Samples { samples, .. } => {
                    assert!(samples.len() <= 2 * size);
                    for v in samples.iter().step_by(2) {
                        if frame + 3 >= total && frame < total + 3 {
                            around.push(i64::from(*v));
                        }
                        frame += 1;
                    }
                }
                _ => panic!("the looping stream ended"),
            }
        }
        assert_eq!(
            around,
            [
                wrap(total - 3),
                wrap(total - 2),
                wrap(total - 1),
                wrap(start),
                wrap(start + 1),
                wrap(start + 2)
            ]
        );
    }
}
