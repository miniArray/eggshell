//! Renderer preparation and terrain/entity binding. No Session state is copied or changed.
use crate::{
    background::Background,
    binding::{Anchor, Catalog, Visual},
    geometry::{Transform, rect_quad, slices, slices_uniform, sprite_quad, tile_uv, visible},
    gles::{Gles, Quad},
    gradient::{CustomGradient, StripGradient},
    hud::{Hud, Layout},
    pack::{Image, Pack},
    screen::{self, Plan},
};
use eggshell_spike_core::{
    EntityAuxiliaryKind, EntityAuxiliaryPicture, EntityPicture, EntityStatus, Map, PaletteSwap,
    Placement, Presentation, PropertyValue, SCALE, VisualState, World,
};
use serde_json::Value;
use std::{collections::HashMap, path::Path};

/// Runtime codes the pinned pack has no object art for. runtime_objects.gd make_node
/// then draws Dressing.placeholder: a square of the code's hue over the body box.
/// Object-table key of the pack's ShyGuyRollSprite visual.
const ROLL_SPRITE: &str = "#visual:ShyGuyRollSprite";
/// Original art for runtime codes the pack has no object entry for: the pack visual
/// (by source type) or object entry the original game draws for them. Godot drew
/// placeholders for all of these. enemy_overlap has no art (it is never drawn).
const PACKLESS_ART: [(&str, &str); 10] = [
    ("enemy_pellet", "SnifitBullet"),
    ("enemy_shot", "BulletBill"),
    ("enemy_petal", "EggoDilPetal"),
    ("enemy_mace", "Spikeball"),
    // A Koopa knocked out of its shell (YFS Enemies: KoopaTroopa spawns BeachKoopa):
    // the e7 BeachKoopa object art.
    ("enemy_runner", "object:e7"),
    // The Ptooie Plant (e41) spits a Needlenose: the e40 object art.
    ("enemy_spike", "object:e40"),
    ("enemy_disc", "RotoDisc"),
    ("seed_shot", "MelonSeed"),
    ("fire_shot", "YoshiFireProjectile"),
    ("ice_shot", "YoshiIceProjectile"),
];
pub const PACKLESS_RUNTIME_CODES: [&str; 11] = [
    "enemy_disc",
    "enemy_mace",
    "enemy_overlap",
    "enemy_pellet",
    "enemy_petal",
    "enemy_runner",
    "enemy_shot",
    "enemy_spike",
    "fire_shot",
    "ice_shot",
    "seed_shot",
];

/// pack_dressing.gd placeholder colour: Color.from_hsv(abs(name.hash()) % 360 / 360,
/// 0.55, 0.65), with Godot's String.hash (djb2 over code points, 32 bits).
fn placeholder_rgba(name: &str) -> [f32; 4] {
    let hash = name
        .chars()
        .fold(5381u32, |h, c| h.wrapping_mul(33).wrapping_add(c as u32));
    let h = (hash % 360) as f64 / 360.0 * 6.0;
    let (s, v) = (0.55, 0.65);
    let i = h.floor();
    let f = h - i;
    let (p, q, t) = (v * (1.0 - s), v * (1.0 - s * f), v * (1.0 - s * (1.0 - f)));
    let (r, g, b) = match i as i64 % 6 {
        0 => (v, t, p),
        1 => (q, v, p),
        2 => (p, v, t),
        3 => (p, q, v),
        4 => (t, p, v),
        _ => (v, p, q),
    };
    [r as f32, g as f32, b as f32, 1.0]
}

struct Terrain {
    image: usize,
    layer: usize,
    slot: [i64; 2],
    /// Animated tilesets: the frame images (scene image ids) and their timing.
    animation: Option<TileAnimation>,
}
#[derive(Clone, Debug, PartialEq)]
struct TileAnimation {
    frames: Vec<usize>,
    /// Steps per frame change.
    period: f64,
    ping_pong: bool,
}
impl TileAnimation {
    fn frame(&self, tick: i64) -> usize {
        let n = self.frames.len();
        if n == 0 {
            return 0;
        }
        let step = (tick.max(0) as f64 / self.period).floor() as usize;
        let index = if self.ping_pong && n > 1 {
            let m = step % (2 * n - 2);
            if m < n { m } else { 2 * n - 2 - m }
        } else {
            step % n
        };
        self.frames[index]
    }
}
/// The original's animated tilesets (YFS Global Events "Animated Tilesets"): every
/// period the tilemap loads the next "<prefix><n>.png" image. Tilemap, file prefix,
/// frame count, seconds per frame, ping-pong (regular water steps 0..3..0 every 0.2 s).
const TILE_ANIMATIONS: [(&str, &str, usize, f64, bool); 12] = [
    ("flowWater", "flowwatertm", 4, 0.075, false),
    ("water2", "sewerwatertm", 4, 0.075, false),
    ("water", "regularwatertm", 4, 0.2, true),
    ("water3", "wavywatertm", 12, 0.075, false),
    ("water4", "icywatertm", 4, 0.125, false),
    ("water5", "muddywatertm", 12, 0.075, false),
    ("water6", "transparentwatertm", 4, 0.125, false),
    ("lava", "lavatm", 4, 0.2, false),
    ("lava_1", "lava_1tm", 4, 0.2, false),
    ("lava_2", "lava_2tm", 4, 0.2, false),
    ("lava_3", "lava_3tm", 4, 0.2, false),
    ("lava_4", "lava_4tm", 4, 0.2, false),
];
struct PreparedMap {
    map: Map,
    background: Background,
    terrain: Vec<Terrain>,
    /// pack_background.gd strips of the map `gradient` field (level space, layer -30).
    strip_gradient: StripGradient,
    /// map_effects.gd bands of `customGradientGenerator` (screen space, layer -39).
    custom_gradient: Option<CustomGradient>,
    terrain_chunks: HashMap<(i64, i64), Vec<usize>>,
    max_tile_size: f64,
    water: crate::water_fx::Water,
}
pub struct Scene {
    catalog: Catalog,
    maps: Vec<PreparedMap>,
    objects: HashMap<String, HashMap<i64, Visual>>,
    player: Visual,
    companions: [Option<Visual>; 3],
    /// YoshiTongueL, YoshiTongueR, YoshiTongueU nine-patches, when the pack has all three.
    tongue: Option<[Visual; 3]>,
    /// Stilt walker recolour per variant. The original recolours the parts at run time
    /// (ShyGuy_Colors); the pack's pre-coloured e1 frames give the same colour pairs.
    stilt_palettes: HashMap<i64, Vec<PaletteSwap>>,
    /// pack_dressing.gd decoration_plan: each extendable scenery (code, variant)'s pack
    /// `source_type`, which names the d28 cap animation.
    decor_caps: HashMap<(String, i64), String>,
    /// The original's aim cursor (hud EggTarget), when the pack has it.
    egg_target: Option<Visual>,
    /// Drawing-only trail of Yoshi positions for carried eggs (never saved, never sim).
    trail: std::sync::Mutex<Trail>,
    /// Animated tileset frames from outside the pack (scene ids after the generated
    /// images), loaded by `add_animated_tiles`.
    animated_files: Vec<std::path::PathBuf>,
    /// Walk/Sprint animation phase, advanced at the original's speed-scaled rate.
    run_clock: std::sync::Mutex<RunClock>,
    /// Spike: drawing-only camera shake (never saved, never sim).
    shake: std::sync::Mutex<crate::shake::Shake>,
    pub feel: std::sync::Mutex<crate::feel::FeelSettings>,
    pub paused_offset: [f64; 2],
    dust: std::sync::Mutex<crate::dust::Dust>,
    /// Per sliced image: middle columns / rows all identical (drawn as one stretched band).
    uniform: HashMap<usize, [bool; 2]>,
    hud: Hud,
    density: u32,
    palette: Vec<PaletteSwap>,
    sizes: Vec<[f64; 2]>,
    binary: Vec<bool>,
    pub(crate) solid: usize,
    bubble: usize,
    art_cull_margin: f64,
    absolute_origin_guard: i64,
    benchmark_real_screen: bool,
    pub visual_omissions: Vec<String>,
}
pub struct Picture {
    pub plan: Plan,
    pub world: Vec<Quad>,
    pub water: crate::water_fx::Frame,
    pub water_surface: Vec<Quad>,
    pub hud: Vec<Quad>,
    pub tint: Vec<Quad>,
    #[cfg(feature = "benchmark-work-counters")]
    pub work: crate::diagnosis::SceneWork,
    pub hud_layout: Layout,
    pub light_origin: [f64; 2],
    pub light_radius: f64,
    pub darkness: f64,
    pub entity_bounds_in_view: u64,
}
fn fullscreen_quad(image: usize, container: [f64; 2], color: [f32; 4]) -> Quad {
    let [w, h] = container;
    Quad {
        image,
        corners: [
            [0.0, 0.0],
            [w as f32, 0.0],
            [w as f32, h as f32],
            [0.0, h as f32],
        ],
        uv: crate::geometry::UNIT_UV,
        color,
        palette: Vec::new(),
    }
}
/// map_effects.gd plan tint: `STRENGTH_r,g,b`, strength clamped to 0..50 percent and
/// ignored below 1; channels like World.rgb (leading number, clamped, truncated).
fn map_tint(tint: &str) -> Option<[f32; 4]> {
    let parts: Vec<&str> = tint.split('_').collect();
    let strength = crate::gradient::leading_float(parts[0]).clamp(0.0, 50.0);
    if !strength.is_finite() || strength < 1.0 {
        return None;
    }
    let channels: Vec<&str> = parts
        .get(1)
        .copied()
        .unwrap_or("0,0,0")
        .split(',')
        .collect();
    let mut rgba = [0.0, 0.0, 0.0, (strength / 100.0) as f32];
    for (i, value) in rgba.iter_mut().take(3).enumerate() {
        let v = channels
            .get(i)
            .map_or(0.0, |c| crate::gradient::leading_float(c));
        let v = if v.is_finite() { v } else { 0.0 };
        *value = (v.clamp(0.0, 255.0).trunc() / 255.0) as f32;
    }
    Some(rgba)
}
/// Conservative envelope only: special geometry stays on the exact existing path.
fn art_can_intersect(
    e: &EntityPicture,
    at: [f64; 2],
    body: [f64; 4],
    plan: &Plan,
    container: [f64; 2],
    margin: f64,
    inactive: bool,
) -> bool {
    if ["p1", "o5", "o11"].contains(&e.code.as_str())
        || crate::dressing::resized_decor(&e.code)
        || e.visual.asset_key.is_some()
        || e.auxiliary.iter().any(|a| a.picture.visible)
    {
        return true;
    }
    if !inactive
        && (e.visual.size_pixels.iter().any(Option::is_some)
            || e.visual.origin_pixels.is_some()
            || e.visual.scale.is_some()
            || e.visual.head_box.is_some())
    {
        return true;
    }
    let offset = if inactive {
        [0.0; 2]
    } else {
        e.visual.offset_pixels
    };
    if !margin.is_finite() || offset.iter().any(|v| !v.is_finite()) {
        return true;
    }
    let lo = [
        (at[0] + body[0].min(0.0) - margin - offset[0].abs()) * plan.scale
            + screen::godot_round(plan.offset[0]),
        (at[1] + body[1].min(0.0) - margin - offset[1].abs()) * plan.scale
            + screen::godot_round(plan.offset[1]),
    ];
    let hi = [
        (at[0] + body[2].max(0.0) + margin + offset[0].abs()) * plan.scale
            + screen::godot_round(plan.offset[0]),
        (at[1] + body[3].max(0.0) + margin + offset[1].abs()) * plan.scale
            + screen::godot_round(plan.offset[1]),
    ];
    hi[0] >= 0.0 && hi[1] >= 0.0 && lo[0] <= container[0] && lo[1] <= container[1]
}
/// pack_dressing.gd decor_entry for d25/d26: lamp.gd view states "lit|dim:colour:style"
/// name the candle animations "<colour><base><style>" (styles 2 and 3 are the dim ones).
fn lamp_aliases(visual: &mut Visual) {
    let base = visual.animations[visual.default].0.clone();
    let chars: Vec<char> = base.chars().collect();
    if chars.len() < 3 {
        return;
    }
    let middle: String = chars[1..chars.len() - 1].iter().collect();
    for colour in 0..2 {
        for style in 0..4 {
            let name = format!("{colour}{middle}{style}");
            let key = format!(
                "{}:{colour}:{}",
                if style < 2 { "lit" } else { "dim" },
                style % 2
            );
            if !visual.states.contains_key(&key)
                && visual.animations.iter().any(|(n, _)| *n == name)
            {
                visual.states.insert(key, name);
            }
        }
    }
}
/// decor.gd size_option for an extendable scenery's E1 height, whole pixels.
fn scenery_height(p: &Placement) -> f64 {
    let value = p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v);
    let n = match value {
        Some(PropertyValue::Number(n)) => *n,
        Some(PropertyValue::String(s)) => s.trim().parse().unwrap_or(0.0),
        _ => 0.0,
    };
    if n.is_finite() && n > 0.0 {
        n.trunc()
    } else {
        0.0
    }
}
fn pixel(p: eggshell_spike_core::Position) -> [f64; 2] {
    [p.x as f64 / SCALE as f64, p.y as f64 / SCALE as f64]
}
fn auxiliary_transform(
    auxiliary: &EntityAuxiliaryPicture,
    origin: [f64; 2],
    size: [f64; 2],
    density: u32,
) -> Result<Transform, String> {
    let aux = &auxiliary.picture;
    let mut t = Transform {
        position: pixel(aux.motion.current),
        scale: auxiliary.scale.map(|v| v / density as f64),
        origin: aux.visual.origin_pixels.unwrap_or(origin),
        rotation: aux.visual.rotation_degrees.unwrap_or(0.0),
        flip: [
            aux.visual.flip_h.unwrap_or(false),
            aux.visual.flip_v.unwrap_or(false),
        ],
    };
    for (i, source_size) in size.iter().enumerate() {
        t.position[i] += aux.visual.offset_pixels[i];
        if let Some(value) = aux.visual.size_pixels[i] {
            t.scale[i] = t.scale[i].signum() * value / source_size;
        }
    }
    t.ratio(aux.visual.scale)
}
/// Colour pairs that turn shy-guy variant 0 art into variant `variant`, read from the pack's
/// pre-coloured e1 Walk and Idle frames, most-used first, at most eight.
fn variant_palette(pack: &Pack, variant: i64) -> Result<Vec<PaletteSwap>, String> {
    let animations = pack
        .manifest
        .get("objects")
        .and_then(|o| o.get("e1"))
        .and_then(|e| e.get("animations"))
        .ok_or("pack has no e1 animations for stilt colours")?;
    let files = |name: &str| -> Vec<String> {
        animations
            .get(name)
            .and_then(|a| a.get("frames"))
            .and_then(Value::as_array)
            .map(|f| {
                f.iter()
                    .filter_map(|f| f.get("file").and_then(Value::as_str).map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default()
    };
    let mut pairs: HashMap<([u8; 3], [u8; 3]), u64> = HashMap::new();
    for pose in ["Walk", "Idle"] {
        for (a, b) in files(&format!("0{pose}"))
            .iter()
            .zip(files(&format!("{variant}{pose}")).iter())
        {
            let (a, b) = (pack.png(a)?, pack.png(b)?);
            if (a.width, a.height) != (b.width, b.height) {
                continue;
            }
            for (pa, pb) in a.rgba.chunks_exact(4).zip(b.rgba.chunks_exact(4)) {
                if pa[3] == 255 && pb[3] == 255 && pa[..3] != pb[..3] {
                    *pairs
                        .entry(([pa[0], pa[1], pa[2]], [pb[0], pb[1], pb[2]]))
                        .or_default() += 1;
                }
            }
        }
    }
    if pairs.is_empty() {
        return Err(format!(
            "pack has no e1 colour frames for stilt variant {variant}"
        ));
    }
    // One target per source colour (the most used), then the most used sources first.
    let mut best: HashMap<[u8; 3], ([u8; 3], u64, u64)> = HashMap::new();
    for ((from, to), n) in pairs {
        let e = best.entry(from).or_insert((to, 0, 0));
        e.2 += n;
        if n > e.1 || (n == e.1 && to < e.0) {
            e.0 = to;
            e.1 = n;
        }
    }
    let mut swaps: Vec<_> = best.into_iter().collect();
    swaps.sort_by(|a, b| b.1.2.cmp(&a.1.2).then(a.0.cmp(&b.0)));
    Ok(swaps
        .into_iter()
        .take(8)
        .map(|(from, (to, _, _))| PaletteSwap { from, to })
        .collect())
}
/// Carried eggs (drawing only; Godot drew none). Original (YFS Yoshi sheet, group
/// "Egg Following"): Every tick: YoshiPos.Push(Yoshi.X) / SetXY(last, 1, Yoshi.Y); when
/// YoshiPos.Width > 60: Delete(0); for each "follow" egg: TweenTwoProperties("pos",
/// YoshiPos.At(count - egg.idx10, 0) + offsetX, YoshiPos.At(count - egg.idx10, 1) - 16,
/// 0.1 s) with idx10 = 10 * egg index. That pushes while Yoshi stands too, so the eggs
/// would close up on him; the user's playtest of the original shows standing eggs
/// spaced and countable on the ground. So: a position is pushed only when Yoshi moved
/// (spacing = 10 moved steps per egg, as in the original while walking), and once he
/// has stood still for STILL_TICKS the eggs drop to his feet level, keeping their x.
#[derive(Default)]
struct Trail {
    last_tick: Option<i64>,
    path: std::collections::VecDeque<[f64; 2]>,
    eggs: Vec<[f64; 2]>,
    /// The last seen PlayerPicture::egg_pops and egg colours (front first).
    pops: Option<u64>,
    colours: Vec<i64>,
    /// Front eggs pushed out of a full queue, falling off screen.
    falling: Vec<FallingEgg>,
    /// Steps since Yoshi last moved.
    still: i64,
}
/// YFS Yoshi 487-488 and Objects 185-186: when a seventh egg is made or picked up, the
/// egg with the lowest orderID (the front one, nearest Yoshi) gets mode fallOffScreen:
/// collisions off, its Platform on (gravity 1600 px/s^2, max fall 576 px/s), and it
/// despawns off screen. The rest move up one place.
struct FallingEgg {
    at: [f64; 2],
    vy: f64,
    fallen: f64,
    colour: i64,
}
impl Trail {
    const KEEP: usize = 60;
    const SPACING: usize = 10;
    /// One tween step: a 0.1 s (6-tick) tween restarted every tick moves a sixth.
    const STEP: f64 = 1.0 / 6.0;
    /// Egg Platform gravity and fall cap in px per tick (1600 px/s^2, 576 px/s at 60 Hz).
    const GRAVITY: f64 = 1600.0 / 3600.0;
    const MAX_FALL: f64 = 576.0 / 60.0;
    /// Steps without movement before the eggs drop to Yoshi's feet level.
    const STILL_TICKS: i64 = 6;
    /// Eggs hang 16 px above the recorded position (the original's At(.., 1) - 16).
    const LIFT: f64 = 16.0;
    /// Taller than any view, so a dropped egg is off screen before it is forgotten.
    const FORGET: f64 = 1024.0;
    /// Call before update with this frame's pop count and egg colours. A rise drops that
    /// many front eggs, with the colours they had on the last frame.
    fn pops(&mut self, pops: u64, colours: &[i64]) {
        if let Some(last) = self.pops {
            let n = (pops.saturating_sub(last) as usize).min(self.eggs.len());
            for k in 0..n {
                let at = self.eggs.remove(0);
                self.falling.push(FallingEgg {
                    at,
                    vy: 0.0,
                    fallen: 0.0,
                    colour: self.colours.get(k).copied().unwrap_or(0),
                });
            }
        }
        // A restore starts the count again at 0; that only resets the baseline.
        self.pops = Some(pops);
        self.colours = colours.to_vec();
    }
    /// Colour and position of every dropped egg still falling.
    fn falling(&self) -> Vec<(i64, [f64; 2])> {
        self.falling.iter().map(|f| (f.colour, f.at)).collect()
    }
    fn update(&mut self, tick: i64, at: [f64; 2], count: usize) -> Vec<[f64; 2]> {
        let steps = match self.last_tick {
            None => 1,
            Some(last) => (tick - last).clamp(0, Self::KEEP as i64) as usize,
        };
        self.last_tick = Some(tick);
        self.eggs.truncate(count);
        while self.eggs.len() < count {
            self.eggs.push([at[0], at[1] - Self::LIFT]);
        }
        if steps > 0 {
            if self.path.back() == Some(&at) {
                self.still += steps as i64;
            } else {
                self.still = 0;
                self.path.push_back(at);
                while self.path.len() > Self::KEEP {
                    self.path.pop_front();
                }
            }
        }
        for _ in 0..steps {
            for f in &mut self.falling {
                f.vy = (f.vy + Self::GRAVITY).min(Self::MAX_FALL);
                f.at[1] += f.vy;
                f.fallen += f.vy;
            }
            self.falling.retain(|f| f.fallen < Self::FORGET);
            for (k, egg) in self.eggs.iter_mut().enumerate() {
                let back = Self::SPACING * (k + 1);
                let target = self
                    .path
                    .len()
                    .checked_sub(1 + back)
                    .and_then(|i| self.path.get(i))
                    .or(self.path.front())
                    .copied()
                    .unwrap_or(at);
                let mut goal = [target[0], target[1] - Self::LIFT];
                if self.still >= Self::STILL_TICKS {
                    goal[1] = at[1] - Self::LIFT;
                }
                for i in 0..2 {
                    egg[i] += (goal[i] - egg[i]) * Self::STEP;
                }
            }
        }
        self.eggs.clone()
    }
}
/// The original game's walk and run animation rate (YFS Yoshi sheet): while Yoshi moves
/// on the ground in Walk or Sprint (Sprint from 320 px/s), the animation speed is
/// |vx| / 8 frames per second. Godot used the pack's fixed 8 fps, so a run at speed
/// cycled its two Sprint frames slowly. Drawing only.
#[derive(Default)]
struct RunClock {
    last_tick: Option<i64>,
    phase: f64,
}
impl RunClock {
    /// Advances by the steps since the last drawn tick at `vx` (units per step) and
    /// returns the frame index for an animation of `frames` frames.
    fn frame(&mut self, tick: i64, vx: i64, frames: usize) -> i64 {
        let steps = self.last_tick.map_or(0, |last| (tick - last).clamp(0, 600));
        self.last_tick = Some(tick);
        // px/s = |vx| / SCALE * 60; frames per step = px/s / 8 / 60.
        self.phase += steps as f64 * vx.unsigned_abs() as f64 / (SCALE as f64 * 8.0);
        if frames == 0 {
            return 0;
        }
        self.phase = self.phase.rem_euclid(frames as f64);
        self.phase.floor() as i64
    }
}
#[cfg(test)]
mod trail_tests {
    use super::Trail;
    #[test]
    fn standing_eggs_stay_spaced_and_drop_to_yoshi_level() {
        let mut t = Trail::default();
        // Walk right 2 px a step on y 100, jump the last 20 steps (y 80), then land.
        for tick in 0..60 {
            let y = if tick >= 40 { 80.0 } else { 100.0 };
            t.update(tick, [tick as f64 * 2.0, y], 3);
        }
        let mut eggs = Vec::new();
        for tick in 60..200 {
            eggs = t.update(tick, [118.0, 100.0], 3);
        }
        // Spaced by 10 recorded positions (20 px) behind Yoshi (the landing adds one
        // record at x 118), all at his feet level - 16.
        for (k, egg) in eggs.iter().enumerate() {
            let x = 120.0 - 20.0 * (k + 1) as f64;
            assert!(
                (egg[0] - x).abs() < 0.5 && (egg[1] - 84.0).abs() < 0.5,
                "{k} {egg:?}"
            );
        }
    }
    #[test]
    fn tile_animation_frames_and_ping_pong() {
        let a = super::TileAnimation {
            frames: vec![10, 11, 12, 13],
            period: 4.5,
            ping_pong: false,
        };
        assert_eq!([0, 4, 5, 9, 18].map(|t| a.frame(t)), [10, 10, 11, 12, 10]);
        let b = super::TileAnimation {
            frames: vec![10, 11, 12, 13],
            period: 12.0,
            ping_pong: true,
        };
        let seq: Vec<_> = (0..8).map(|k| b.frame(k * 12)).collect();
        assert_eq!(seq, [10, 11, 12, 13, 12, 11, 10, 11]);
    }
    #[test]
    fn run_frames_follow_speed() {
        use super::{RunClock, SCALE};
        let mut c = RunClock::default();
        assert_eq!(c.frame(0, 0, 10), 0);
        // 240 px/s = 30 frames/s: one frame every 2 steps.
        let vx = 4 * SCALE;
        assert_eq!(c.frame(2, vx, 10), 1);
        assert_eq!(c.frame(20, vx, 10), 0);
        // 480 px/s on a two-frame Sprint: 60 frames/s, one per step.
        let vx = -8 * SCALE;
        assert_eq!(c.frame(21, vx, 2), 1);
        assert_eq!(c.frame(22, vx, 2), 0);
    }
    #[test]
    fn a_seventh_egg_drops_the_front_egg() {
        let mut t = Trail::default();
        let colours = [1, 0, 0, 0, 0, 2];
        t.pops(0, &colours);
        let before = t.update(0, [100.0, 50.0], 6);
        // Made at six: the pop count rises, the front (yellow) egg falls, the rest
        // move up one place and the new egg appears at Yoshi.
        t.pops(1, &[0, 0, 0, 0, 2, 0]);
        let after = t.update(1, [100.0, 50.0], 6);
        assert_eq!(after[..5], before[1..]);
        let falling = t.falling();
        assert_eq!(falling.len(), 1);
        assert_eq!(falling[0].0, 1);
        assert!(falling[0].1[1] > before[0][1]);
        // It keeps falling at most 9.6 px per tick, then is forgotten.
        let mut last = falling[0].1[1];
        for tick in 2..200 {
            t.pops(1, &[0; 6]);
            t.update(tick, [100.0, 50.0], 6);
            if let Some((_, at)) = t.falling().first() {
                assert!(at[1] - last <= 9.6 + 1e-9);
                last = at[1];
            }
        }
        assert!(t.falling().is_empty());
        // A restore resets the count without dropping anything.
        t.pops(0, &[0; 6]);
        t.update(200, [100.0, 50.0], 6);
        assert!(t.falling().is_empty());
    }
    #[test]
    fn short_history_leaves_eggs_where_they_appeared() {
        let mut t = Trail::default();
        let eggs = t.update(0, [10.0, 50.0], 1);
        assert_eq!(eggs, vec![[10.0, 34.0]]);
        let eggs = t.update(5, [30.0, 50.0], 1);
        assert_eq!(eggs, vec![[10.0, 34.0]]);
    }
}
fn fallback_head_box(
    hint: Option<[i64; 4]>,
    auxiliary: &[EntityAuxiliaryPicture],
) -> Option<[i64; 4]> {
    // Current core carries the hull as a body hint AND a complete auxiliary.
    // Draw that auxiliary exactly once, including when it explicitly hides.
    if auxiliary
        .iter()
        .any(|a| a.kind == EntityAuxiliaryKind::PlantHead)
    {
        None
    } else {
        hint
    }
}
impl Scene {
    pub fn prepare(
        world: &World,
        admitted_codes: &[String],
        pack: &Pack,
        metrics: &Path,
    ) -> Result<Self, String> {
        Self::prepare_configured(world, admitted_codes, pack, metrics, false)
    }
    pub fn prepare_benchmark_real_screen(
        world: &World,
        admitted_codes: &[String],
        pack: &Pack,
        metrics: &Path,
    ) -> Result<Self, String> {
        Self::prepare_configured(world, admitted_codes, pack, metrics, true)
    }
    fn prepare_configured(
        world: &World,
        admitted_codes: &[String],
        pack: &Pack,
        metrics: &Path,
        benchmark_real_screen: bool,
    ) -> Result<Self, String> {
        let mut visual_omissions = Vec::new();
        let mut catalog = Catalog::default();
        let density = pack.density;
        let mut maps = Vec::new();
        for map in &world.maps {
            let text = |key: &str| {
                map.source_properties.iter().find_map(|(k, v)| match v {
                    PropertyValue::String(s) if k == key => Some(s.as_str()),
                    _ => None,
                })
            };
            let strip_gradient =
                StripGradient::prepare(&pack.manifest, text("gradient").unwrap_or(""), density);
            let custom_gradient = text("customGradientGenerator").and_then(CustomGradient::prepare);
            if benchmark_real_screen
                && map.source_properties.iter().any(|(k, v)| {
                    k == "diceBlockColours" && matches!(v,PropertyValue::String(s) if !s.is_empty())
                })
            {
                visual_omissions.push(format!(
                    "map={} omission=diceBlockColours stand_in=none",
                    map.name
                ));
            }
            if pack
                .manifest
                .get("terrain")
                .and_then(Value::as_object)
                .is_some_and(|t| !t.is_empty())
            {
                return Err("required terrain edge strips not admitted yet".into());
            }
            let background = Background::prepare(
                &pack.manifest,
                &mut catalog,
                &map.backgrounds,
                map.height_pixels,
                density,
            )?;
            let mut terrain = Vec::new();
            for (index, layer) in map.layers.iter().enumerate() {
                let file = pack
                    .manifest
                    .get("tiles")
                    .and_then(|t| t.get(&layer.tilemap))
                    .and_then(Value::as_str)
                    .ok_or_else(|| format!("required tile PNG absent: {}", layer.tilemap))?;
                let image = catalog.image(file)?;
                let mut slot = [layer.draw_slot.layer_index, layer.draw_slot.z_order];
                if let Some(instances) = pack
                    .drawing
                    .get("tilemaps")
                    .and_then(|t| t.get(&layer.tilemap))
                    .and_then(|t| t.get("instances"))
                    .and_then(Value::as_array)
                {
                    for instance in instances {
                        let name = instance.get("layer").and_then(Value::as_str).unwrap_or("");
                        if (layer.source_layer == "layer1" && name.ends_with("L1"))
                            || (layer.source_layer == "layer2" && name.ends_with("L2"))
                        {
                            slot = [
                                instance["layer_index"]
                                    .as_f64()
                                    .ok_or("drawing slot index missing")?
                                    as i64,
                                instance["z_order"]
                                    .as_f64()
                                    .ok_or("drawing slot z missing")?
                                    as i64,
                            ];
                        }
                    }
                } else {
                    return Err(format!("required drawing slots absent: {}", layer.tilemap));
                }
                if layer.tile_size_pixels <= 0 || layer.cells.len() != layer.width * layer.height {
                    return Err("invalid immutable terrain layer".into());
                }
                terrain.push(Terrain {
                    image,
                    layer: index,
                    slot,
                    animation: None,
                });
            }
            terrain.sort_by_key(|t| t.slot);
            let mut terrain_chunks: HashMap<(i64, i64), Vec<usize>> = HashMap::new();
            let mut max_tile_size = 0.0_f64;
            for (ti, t) in terrain.iter().enumerate() {
                let layer = &map.layers[t.layer];
                let size = layer.tile_size_pixels;
                max_tile_size = max_tile_size.max(size as f64);
                let mut chunks = std::collections::BTreeSet::new();
                for (i, cell) in layer.cells.iter().enumerate() {
                    if *cell == -1 {
                        continue;
                    }
                    let x = (i % layer.width) as i64 * size;
                    let y = (i / layer.width) as i64 * size;
                    for cy in y / 256..=(y + size - 1) / 256 {
                        for cx in x / 256..=(x + size - 1) / 256 {
                            chunks.insert((cx, cy));
                        }
                    }
                }
                for key in chunks {
                    terrain_chunks.entry(key).or_default().push(ti);
                }
            }
            maps.push(PreparedMap {
                map: map.clone(),
                background,
                terrain,
                strip_gradient,
                custom_gradient,
                terrain_chunks,
                max_tile_size,
                water: crate::water_fx::Water::prepare(&map.layers)?,
            });
        }
        let object_entries = pack.manifest.get("objects").ok_or("pack objects missing")?;
        let mut objects = HashMap::new();
        for code in admitted_codes
            .iter()
            .map(String::as_str)
            .chain(
                world
                    .maps
                    .iter()
                    .flat_map(|m| m.placements.iter().map(|p| p.code.as_str())),
            )
            // e16 frames stand in for the fire and ice shots, which have no pack art.
            .chain(["e5_head", "e1", "e16"])
        {
            // editor_blank.gd: never drawn, so it binds no art.
            if objects.contains_key(code) || ["empty", ""].contains(&code) {
                continue;
            }
            let Some(entry) = object_entries.get(code) else {
                if PACKLESS_RUNTIME_CODES.contains(&code) {
                    let source = PACKLESS_ART
                        .iter()
                        .find(|(c, _)| *c == code)
                        .map(|(_, s)| *s);
                    let entry = source.and_then(|s| match s.strip_prefix("object:") {
                        Some(object) => object_entries.get(object),
                        None => pack
                            .manifest
                            .get("visuals")
                            .and_then(Value::as_object)
                            .and_then(|v| {
                                v.values().find(|e| {
                                    e.get("source_type").and_then(Value::as_str) == Some(s)
                                })
                            }),
                    });
                    if let Some(entry) = entry {
                        let mut bound = HashMap::new();
                        bound.insert(0, catalog.visual(entry, 0, density, false)?);
                        objects.insert(code.to_owned(), bound);
                    }
                    continue;
                }
                return Err(format!("required admitted object asset absent: {code}"));
            };
            let mut variants = vec![0];
            if code == "e1" {
                variants.extend(0..=4);
            } // e35 runtime rider colours
            variants.extend(
                world
                    .maps
                    .iter()
                    .flat_map(|m| m.placements.iter())
                    .filter(|p| p.code == code)
                    .map(|p| p.variant),
            );
            if let Some(entries) = entry.get("variants").and_then(Value::as_object) {
                for key in entries.keys() {
                    variants.push(key.parse().map_err(|_| "nonnumeric pack variant")?);
                }
            }
            variants.sort_unstable();
            variants.dedup();
            let mut bound = HashMap::new();
            for variant in variants {
                let mut visual = catalog.visual(entry, variant, density, code.starts_with('d'))?;
                if ["d25", "d26"].contains(&code) {
                    lamp_aliases(&mut visual);
                }
                bound.insert(variant, visual);
            }
            objects.insert(code.to_owned(), bound);
        }
        // pack_dressing.gd decoration_plan d23: the second source type is a tiled pillar.
        if objects.contains_key("d23") {
            let entry = object_entries.get("d23").ok_or("d23 entry")?;
            let part = entry
                .get("source_types")
                .and_then(Value::as_array)
                .and_then(|types| types.get(1))
                .and_then(Value::as_f64)
                .and_then(|t| entry.get("parts")?.get((t as i64).to_string()))
                .ok_or("pack has no d23 pillar part")?;
            let mut bound = HashMap::new();
            bound.insert(0, catalog.visual(part, 0, density, true)?);
            objects.insert("d23_pillar".to_owned(), bound);
        }
        // pack_dressing.gd decor_entry d22: form 0 draws the second tree part, form 1
        // the first.
        if objects.contains_key("d22") {
            let entry = object_entries.get("d22").ok_or("d22 entry")?;
            for (name, slot) in [("d22_small", 1), ("d22_big", 0)] {
                let part = entry
                    .get("source_types")
                    .and_then(Value::as_array)
                    .and_then(|types| types.get(slot))
                    .and_then(Value::as_f64)
                    .and_then(|t| entry.get("parts")?.get((t as i64).to_string()))
                    .ok_or("pack has no d22 tree part")?;
                let mut bound = HashMap::new();
                bound.insert(0, catalog.visual(part, 0, density, true)?);
                objects.insert(name.to_owned(), bound);
            }
        }
        let egg_target = match pack.manifest.get("hud").and_then(|h| h.get("EggTarget")) {
            Some(entry) => Some(catalog.visual(entry, 0, density, false)?),
            None => {
                visual_omissions.push("aim cursor: pack has no hud EggTarget".into());
                None
            }
        };
        let mut stilt_palettes = HashMap::new();
        for variant in world
            .maps
            .iter()
            .flat_map(|m| m.placements.iter())
            .filter(|p| p.code == "e35" && p.variant != 0)
            .map(|p| p.variant)
        {
            if let std::collections::hash_map::Entry::Vacant(slot) = stilt_palettes.entry(variant) {
                slot.insert(variant_palette(pack, variant)?);
            }
        }
        // The original stilt walker's animated parts, by pack source type.
        if world
            .maps
            .iter()
            .flat_map(|m| m.placements.iter())
            .any(|p| p.code == "e35")
        {
            for name in ["StiltGuy_Feet", "StiltGuy_PolesMiddle", "StiltGuy_Top"] {
                let entry = pack
                    .manifest
                    .get("visuals")
                    .and_then(Value::as_object)
                    .and_then(|v| {
                        v.values()
                            .find(|e| e.get("source_type").and_then(Value::as_str) == Some(name))
                    })
                    .ok_or_else(|| format!("pack has no {name} for e35"))?;
                let mut bound = HashMap::new();
                bound.insert(0, catalog.visual(entry, 0, density, false)?);
                objects.insert(name.to_owned(), bound);
            }
        }
        // Visible pound-post art (o23): bind the colours and forms the level places,
        // keyed by pack source type, which the core names in the post's asset_key.
        let visuals = pack.manifest.get("visuals").and_then(Value::as_object);
        for p in world.maps.iter().flat_map(|m| m.placements.iter()) {
            if p.code != "o23" {
                continue;
            }
            let option = |key: &str| {
                p.properties
                    .iter()
                    .find(|(k, _)| k == key)
                    .map(|(_, v)| match v {
                        eggshell_spike_core::PropertyValue::String(s) => {
                            s.trim().parse().unwrap_or(0)
                        }
                        eggshell_spike_core::PropertyValue::Number(n) => *n as i64,
                        _ => 0,
                    })
                    .unwrap_or(0)
            };
            let name = format!(
                "{}Post{}",
                if option("E3") != 0 { "Spiked" } else { "" },
                option("E2")
            );
            if objects.contains_key(&name) {
                continue;
            }
            let entry = visuals
                .and_then(|v| {
                    v.values().find(|e| {
                        e.get("source_type").and_then(Value::as_str) == Some(name.as_str())
                            && e.get("slices").is_some()
                    })
                })
                .ok_or_else(|| format!("pack has no {name} nine-patch for o23"))?;
            let mut bound = HashMap::new();
            bound.insert(0, catalog.visual(entry, 0, density, false)?);
            objects.insert(name, bound);
        }
        // Drawing-only parts: span stalks and spike strips, and extendable scenery parts
        // (span_dressing.gd, pack_dressing.gd decoration_plan).
        // The Shy Guy roll sprite (drawn for a rolling e1/e2; see ROLL_SPRITE).
        let roll_entry = pack
            .manifest
            .get("visuals")
            .and_then(Value::as_object)
            .and_then(|v| {
                v.values().find(|e| {
                    e.get("source_type").and_then(Value::as_str) == Some("ShyGuyRollSprite")
                })
            });
        if let Some(entry) =
            roll_entry.filter(|_| objects.contains_key("e1") || objects.contains_key("e2"))
        {
            let mut bound = HashMap::new();
            bound.insert(0, catalog.visual(entry, 0, density, false)?);
            objects.insert(ROLL_SPRITE.to_owned(), bound);
        }
        let mut decor_caps = HashMap::new();
        for p in world.maps.iter().flat_map(|m| m.placements.iter()) {
            let mut needed: Vec<(String, Option<Value>, i64)> = Vec::new();
            if let Some(key) = crate::dressing::span_part_key(&p.code) {
                let entry = object_entries.get(&key).cloned();
                needed.push((key.clone(), entry.clone(), 0));
                needed.push((key, entry, 1));
            }
            if crate::dressing::resized_decor(&p.code) {
                let entry = object_entries.get(&p.code);
                let selected = entry
                    .and_then(|e| e.get("variants"))
                    .and_then(|v| v.get(p.variant.to_string()))
                    .or(entry);
                let cap = selected
                    .and_then(|e| e.get("source_type"))
                    .and_then(Value::as_str);
                if let Some(cap) = cap {
                    decor_caps.insert((p.code.clone(), p.variant), cap.to_owned());
                }
                for part in crate::dressing::decoration_plan(&p.code, p.variant, 0.0, cap) {
                    if part.art == crate::dressing::Art::Body {
                        continue;
                    }
                    needed.push((
                        crate::dressing::part_key(&p.code, &part.art),
                        crate::dressing::part_entry(&pack.manifest, &p.code, &part.art),
                        part.variant,
                    ));
                }
            }
            for (key, entry, variant) in needed {
                if objects
                    .get(&key)
                    .is_some_and(|v: &HashMap<i64, Visual>| v.contains_key(&variant))
                {
                    continue;
                }
                let entry = entry.ok_or_else(|| format!("pack has no {key} art for {}", p.code))?;
                let visual = catalog.visual(&entry, variant, density, true)?;
                objects.entry(key).or_default().insert(variant, visual);
            }
        }
        let player=catalog.visual(&serde_json::json!({"animations":pack.manifest.get("player").ok_or("player animations missing")?,"default_animation":"Idle0"}),0,density,false)?;
        let hud_entries = pack.manifest.get("hud").ok_or("hud metadata missing")?;
        let companion = hud_entries
            .get("companion")
            .or_else(|| object_entries.get("companion"));
        let bubble = hud_entries
            .get("bubble")
            .filter(|v| v.as_object().is_some_and(|v| !v.is_empty()))
            .or_else(|| {
                object_entries.get("recovery").filter(|v| {
                    v.get("default_animation")
                        .and_then(Value::as_str)
                        .is_some_and(|s| s.eq_ignore_ascii_case("bubble"))
                })
            });
        let companions = [
            companion
                .map(|v| catalog.visual(v, 0, density, false))
                .transpose()?,
            bubble
                .map(|v| catalog.visual(v, 0, density, false))
                .transpose()?,
            hud_entries
                .get("captor")
                .map(|v| catalog.visual(v, 0, density, false))
                .transpose()?,
        ];
        let tongue = {
            let visuals = pack.manifest.get("visuals").and_then(Value::as_object);
            let find = |name: &str| {
                visuals.and_then(|v| {
                    v.values().find(|e| {
                        e.get("source_type").and_then(Value::as_str) == Some(name)
                            && e.get("slices").is_some()
                    })
                })
            };
            match (
                find("YoshiTongueL"),
                find("YoshiTongueR"),
                find("YoshiTongueU"),
            ) {
                (Some(l), Some(r), Some(u)) => Some([
                    catalog.visual(l, 0, density, false)?,
                    catalog.visual(r, 0, density, false)?,
                    catalog.visual(u, 0, density, false)?,
                ]),
                _ => {
                    visual_omissions
                        .push("tongue: pack has no YoshiTongueL/R/U nine-patches".into());
                    None
                }
            }
        };
        let hud = Hud::prepare(&pack.manifest, &mut catalog, metrics, density)?;
        let keys = [[0, 248, 0], [0, 168, 0], [0, 96, 0]];
        let palette = if world.player_palette.is_empty() {
            Vec::new()
        } else {
            keys.into_iter()
                .enumerate()
                .map(|(i, from)| PaletteSwap {
                    from,
                    to: world.player_palette.get(i).copied().unwrap_or([0; 3]),
                })
                .collect()
        };
        Ok(Self {
            catalog,
            maps,
            objects,
            player,
            companions,
            tongue,
            stilt_palettes,
            decor_caps,
            egg_target,
            trail: std::sync::Mutex::new(Trail::default()),
            run_clock: std::sync::Mutex::new(RunClock::default()),
            animated_files: Vec::new(),
            shake: std::sync::Mutex::new(crate::shake::Shake::default()),
            feel: std::sync::Mutex::new(crate::feel::FeelSettings::default()),
            paused_offset: [0.0; 2],
            dust: std::sync::Mutex::new(crate::dust::Dust::default()),
            uniform: HashMap::new(),
            hud,
            density,
            palette,
            sizes: Vec::new(),
            binary: Vec::new(),
            solid: 0,
            bubble: 0,
            benchmark_real_screen,
            art_cull_margin: f64::INFINITY,
            absolute_origin_guard: 1,
            visual_omissions,
        })
    }
    pub fn validate_assets(&self, pack: &Pack) -> Result<serde_json::Value, String> {
        let mut total = 0usize;
        let mut files = Vec::new();
        let mut max = [0u32; 2];
        for file in &self.catalog.files {
            let image = pack.png(file)?;
            total += image.rgba.len();
            max[0] = max[0].max(image.width);
            max[1] = max[1].max(image.height);
            files.push(serde_json::json!({"file":file,"sha256":image.sha256,"width":image.width,"height":image.height}));
        }
        Ok(
            serde_json::json!({"mode":"asset-binding-only-no-gameplay-no-GPU","image_count":files.len(),"rgba_payload_bytes":total,"maximum_dimensions":max,"files":files,"visual_omissions":self.visual_omissions,"benchmark_real_screen":self.benchmark_real_screen,"faithful_real_level":false}),
        )
    }
    pub fn absolute_origin_guard(&self) -> i64 {
        self.absolute_origin_guard
    }
    /// Nine-patch cuts of every bound image that is drawn in slices.
    fn sliced_images(&self) -> HashMap<usize, crate::binding::Slices> {
        let mut result = HashMap::new();
        let visuals = self
            .objects
            .values()
            .flat_map(|variants| variants.values())
            .chain(self.tongue.iter().flatten());
        for v in visuals {
            if let Some(cuts) = v.slices {
                for (_, a) in &v.animations {
                    for f in &a.frames {
                        result.insert(f.image, cuts);
                    }
                }
            }
        }
        result
    }
    /// Whether the tiled middle columns (x) and rows (y) of an image are all identical.
    fn uniform_bands(image: &Image, cuts: crate::binding::Slices) -> [bool; 2] {
        let (w, h) = (image.width as usize, image.height as usize);
        let pixel = |x: usize, y: usize| &image.rgba[(y * w + x) * 4..(y * w + x) * 4 + 4];
        let band = |start: f64, end: f64, length: usize| {
            let a = (start.max(0.0) as usize).min(length);
            let b = ((length as f64 - end).max(0.0) as usize).min(length);
            (a < b).then_some((a, b))
        };
        let columns = band(cuts.left, cuts.right, w)
            .is_some_and(|(a, b)| (0..h).all(|y| (a..b).all(|x| pixel(x, y) == pixel(a, y))));
        let rows = band(cuts.top, cuts.bottom, h)
            .is_some_and(|(a, b)| (a..b).all(|y| (0..w).all(|x| pixel(x, y) == pixel(x, a))));
        [columns, rows]
    }
    fn uniform_for(&self, image: usize) -> [bool; 2] {
        self.uniform.get(&image).copied().unwrap_or([false; 2])
    }
    /// Private pack file of each bound image, by image index.
    pub fn image_files(&self) -> &[String] {
        &self.catalog.files
    }
    fn prepare_art_cull_margin(&mut self) {
        self.absolute_origin_guard = self
            .objects
            .values()
            .flat_map(|variants| variants.values())
            .flat_map(|v| v.animations.iter().flat_map(|(_, a)| &a.frames))
            .map(|f| {
                let s = self.sizes[f.image];
                (1.0 + f.origin[0].abs() / s[0]).max(1.0 + f.origin[1].abs() / s[1])
            })
            .fold(1.0_f64, f64::max)
            .ceil() as i64;
        self.art_cull_margin = 2.0
            + self
                .objects
                .values()
                .flat_map(|variants| variants.values())
                .flat_map(|v| v.animations.iter().flat_map(|(_, a)| &a.frames))
                .map(|f| {
                    let s = self.sizes[f.image];
                    (s[0] + s[1] + f.origin[0].abs() + f.origin[1].abs()) / self.density as f64
                })
                .fold(0.0_f64, f64::max);
    }
    /// Image sizes without a GPU, for host checks (level index, diagnosis).
    pub fn prepare_headless_assets(&mut self, pack: &Pack) -> Result<(), String> {
        if !self.sizes.is_empty() {
            return Err("headless assets already prepared".into());
        }
        let sliced = self.sliced_images();
        for (id, file) in self.catalog.files.iter().enumerate() {
            let image = pack.png(file)?;
            if let Some(cuts) = sliced.get(&id) {
                self.uniform.insert(id, Self::uniform_bands(&image, *cuts));
            }
            self.sizes.push([image.width as f64, image.height as f64]);
            self.binary
                .push(image.rgba.chunks_exact(4).all(|p| p[3] == 0 || p[3] == 255));
        }
        self.solid = self.sizes.len();
        self.sizes.push([1.0, 1.0]);
        self.binary.push(true);
        self.bubble = self.sizes.len();
        self.sizes.push([64.0, 64.0]);
        self.binary.push(true);
        for path in self.animated_files.clone() {
            let image = Image::load(&path)?;
            self.sizes.push([image.width as f64, image.height as f64]);
            self.binary
                .push(image.rgba.chunks_exact(4).all(|p| p[3] == 0 || p[3] == 255));
        }
        self.prepare_art_cull_margin();
        Ok(())
    }
    /// The original's animated tilesets: for every terrain layer whose tilemap animates
    /// and whose frames "<prefix>0.png".. all exist in `dir` at the tile image's size,
    /// the layer draws those frames in turn. Missing frames keep the static image.
    /// Call before upload. Returns the number of animated layers.
    pub fn add_animated_tiles(&mut self, dir: &Path, pack: &Pack) -> Result<usize, String> {
        if !self.sizes.is_empty() {
            return Err("animated tiles must be added before upload".into());
        }
        let base = self.catalog.files.len() + 2;
        let mut animated = 0;
        for prepared in &mut self.maps {
            for t in &mut prepared.terrain {
                let name = &prepared.map.layers[t.layer].tilemap;
                let Some(&(_, prefix, count, seconds, ping_pong)) =
                    TILE_ANIMATIONS.iter().find(|a| a.0 == name)
                else {
                    continue;
                };
                let still = pack.png(&self.catalog.files[t.image])?;
                let mut frames = Vec::new();
                for n in 0..count {
                    let path = dir.join(format!("{prefix}{n}.png"));
                    if !path.is_file() {
                        break;
                    }
                    let image = Image::load(&path)?;
                    if [image.width, image.height] != [still.width, still.height] {
                        return Err(format!(
                            "animated tile frame size differs: {}",
                            path.display()
                        ));
                    }
                    let id = match self.animated_files.iter().position(|p| *p == path) {
                        Some(i) => base + i,
                        None => {
                            self.animated_files.push(path);
                            base + self.animated_files.len() - 1
                        }
                    };
                    frames.push(id);
                }
                if frames.len() == count {
                    t.animation = Some(TileAnimation {
                        frames,
                        period: seconds * 60.0,
                        ping_pong,
                    });
                    animated += 1;
                }
            }
        }
        Ok(animated)
    }
    pub fn upload(&mut self, gpu: &mut Gles, pack: &Pack) -> Result<(), String> {
        if !self.sizes.is_empty() {
            return Err("scene assets already uploaded".into());
        }
        let mut bytes = 0usize;
        let sliced = self.sliced_images();
        for (id, file) in self.catalog.files.iter().enumerate() {
            let image = pack.png(file)?;
            if let Some(cuts) = sliced.get(&id) {
                self.uniform.insert(id, Self::uniform_bands(&image, *cuts));
            }
            self.sizes.push([image.width as f64, image.height as f64]);
            self.binary
                .push(image.rgba.chunks_exact(4).all(|p| p[3] == 0 || p[3] == 255));
            bytes += image.rgba.len();
            if gpu.upload(&image)? != id {
                return Err("GPU image binding identity mismatch".into());
            }
        }
        // Only the reference's authored fallback pictures: flat white and bubble ring.
        self.solid = gpu.upload(&Image {
            width: 1,
            height: 1,
            rgba: vec![255; 4],
            sha256: String::new(),
        })?;
        self.sizes.push([1.0, 1.0]);
        self.binary.push(true);
        let mut ring = vec![0; 64 * 64 * 4];
        for y in 0..64_i32 {
            for x in 0..64_i32 {
                let distance = (x - 32) * (x - 32) + (y - 32) * (y - 32);
                if (28 * 28..=30 * 30).contains(&distance) {
                    let i = (y as usize * 64 + x as usize) * 4;
                    ring[i..i + 4].fill(255);
                }
            }
        }
        self.bubble = gpu.upload(&Image {
            width: 64,
            height: 64,
            rgba: ring,
            sha256: String::new(),
        })?;
        self.sizes.push([64.0, 64.0]);
        self.binary.push(true);
        for path in self.animated_files.clone() {
            let image = Image::load(&path)?;
            self.sizes.push([image.width as f64, image.height as f64]);
            self.binary
                .push(image.rgba.chunks_exact(4).all(|p| p[3] == 0 || p[3] == 255));
            bytes += image.rgba.len();
            if gpu.upload(&image)? != self.sizes.len() - 1 {
                return Err("GPU animated tile binding identity mismatch".into());
            }
        }
        self.prepare_art_cull_margin();
        println!(
            "RUST_SCENE_UPLOAD original_images={} rgba_payload_bytes={bytes} per_frame_asset_reads=0 per_frame_texture_uploads=0 baseline_fallbacks=white-and-bubble-ring",
            self.catalog.files.len()
        );
        Ok(())
    }
    pub fn presentation_region(
        &self,
        map_index: usize,
        focus: eggshell_spike_core::Position,
        container: [f64; 2],
        zoom: i32,
    ) -> Result<[i64; 4], String> {
        let map = &self
            .maps
            .get(map_index.checked_sub(1).ok_or("zero map")?)
            .ok_or("map missing")?
            .map;
        let plan = screen::plan(
            container,
            [map.width_pixels as f64, map.height_pixels as f64],
            pixel(focus),
            self.density,
            zoom,
        )?;
        let pad = self.art_cull_margin;
        Ok([
            ((plan.center[0] - plan.visible[0] / 2.0 - pad) * SCALE as f64).floor() as i64,
            ((plan.center[1] - plan.visible[1] / 2.0 - pad) * SCALE as f64).floor() as i64,
            ((plan.center[0] + plan.visible[0] / 2.0 + pad) * SCALE as f64).ceil() as i64,
            ((plan.center[1] + plan.visible[1] / 2.0 + pad) * SCALE as f64).ceil() as i64,
        ])
    }
    /// The clear colour of a one-based map index: map_effects.gd _base, which takes the
    /// last custom gradient colour when the map has one, else the map `bgcolor`.
    /// A menu drawn with the HUD bitmap font and this scene's uploaded images.
    pub fn menu_view(&self) -> Result<crate::menu::View, String> {
        let font = self.hud.font().clone();
        let size = *self
            .sizes
            .get(font.image())
            .ok_or("scene textures not uploaded")?;
        Ok(crate::menu::View::new(font, size, self.density > 1))
    }
    pub fn solid_image(&self) -> usize {
        self.solid
    }
    pub fn clear_color(&self, map_index: usize) -> Result<[u8; 3], String> {
        let prepared = self
            .maps
            .get(map_index.checked_sub(1).ok_or("zero saved map index")?)
            .ok_or("picture map absent")?;
        Ok(prepared
            .custom_gradient
            .as_ref()
            .map_or(prepared.map.background_color, |g| g.fill))
    }
    pub fn picture(
        &self,
        p: &Presentation,
        container: [f64; 2],
        zoom: i32,
    ) -> Result<Picture, String> {
        self.picture_configured(p, container, zoom, true, true)
    }
    #[cfg(feature = "benchmark-work-counters")]
    pub fn picture_unculled(
        &self,
        p: &Presentation,
        container: [f64; 2],
        zoom: i32,
    ) -> Result<Picture, String> {
        self.picture_configured(p, container, zoom, false, false)
    }
    #[cfg(feature = "benchmark-work-counters")]
    pub fn picture_before_spatial(
        &self,
        p: &Presentation,
        container: [f64; 2],
        zoom: i32,
    ) -> Result<Picture, String> {
        self.picture_configured(p, container, zoom, true, false)
    }
    /// Fed once per successful step even when that step is not drawn. Only DTO reads.
    pub fn observe_feel(&self, p: &Presentation) -> Result<(), String> {
        let settings = *self.feel.lock().map_err(|_| "feel lock poisoned")?;
        self.dust.lock().map_err(|_| "dust lock poisoned")?.observe(
            p,
            settings,
            &self
                .maps
                .get(p.map_index.checked_sub(1).ok_or("zero saved map index")?)
                .ok_or("picture map absent")?
                .map,
        );
        Ok(())
    }
    pub fn feel_view(&self) -> crate::menu::View {
        let font = self.hud.font.clone();
        let size = self.sizes[font.image()];
        crate::menu::View::new(font, size, self.density > 1)
    }
    fn picture_configured(
        &self,
        p: &Presentation,
        container: [f64; 2],
        zoom: i32,
        cull_art: bool,
        chunk_layers: bool,
    ) -> Result<Picture, String> {
        if self.sizes.len() != self.catalog.files.len() + 2 + self.animated_files.len() {
            return Err("scene textures not uploaded".into());
        }
        // Core's current saved map_index is one-based; maps is a zero-based Vec.
        let prepared = self
            .maps
            .get(p.map_index.checked_sub(1).ok_or("zero saved map index")?)
            .ok_or("picture map absent")?;
        let map = &prepared.map;
        // The initial matched 60Hz experiment explicitly pins smoothing off.
        // p.interpolate indicates an eligible previous pair, not a setting.
        let focus = pixel(p.follow.current);
        let mut plan = screen::plan(
            container,
            [map.width_pixels as f64, map.height_pixels as f64],
            focus,
            self.density,
            zoom,
        )?;
        // Spike: shake moves only the drawn camera, in whole framebuffer pixels.
        {
            let mut shake = self.shake.lock().map_err(|_| "shake lock poisoned")?;
            shake.settings = *self.feel.lock().map_err(|_| "feel lock poisoned")?;
            shake.observe(p);
            let off = shake.offset(p.tick);
            for (value, shift) in plan.offset.iter_mut().zip([
                off[0] + self.paused_offset[0],
                off[1] + self.paused_offset[1],
            ]) {
                *value += (shift * plan.scale).round();
            }
        }
        #[cfg(feature = "benchmark-work-counters")]
        let mut work = crate::diagnosis::SceneWork {
            art_cull_margin: self.art_cull_margin,
            ..Default::default()
        };
        let mut entity_bounds_in_view = 0_u64; // measurement only, inside existing entity traversal
        let mut commands: Vec<(i64, u64, Quad)> = Vec::new();
        let mut order = 0u64;
        let mut gradients = Vec::new();
        if let Some(custom) = &prepared.custom_gradient {
            custom.emit(&plan, container, self.solid, &mut gradients);
        }
        for q in gradients.drain(..) {
            commands.push((-39, order, q));
            order += 1;
        }
        // pack_background.gd draws its strips before its image layers, on one z.
        prepared
            .strip_gradient
            .emit(&plan, container, self.solid, &mut gradients);
        for q in gradients {
            commands.push((-30, order, q));
            order += 1;
        }
        let mut backgrounds = Vec::new();
        prepared.background.emit(
            p.tick,
            &plan,
            container,
            &self.sizes,
            &self.binary,
            &mut backgrounds,
        )?;
        for q in backgrounds {
            commands.push((-30, order, q));
            order += 1;
        }
        let terrain_ids: Vec<usize> = if chunk_layers {
            let mut ids = std::collections::BTreeSet::new();
            let min = [
                ((plan.center[0] - plan.visible[0] / 2.0) / 256.0).floor() as i64,
                ((plan.center[1] - plan.visible[1] / 2.0) / 256.0).floor() as i64,
            ];
            let max = [
                ((plan.center[0] + plan.visible[0] / 2.0 + 2.0 * prepared.max_tile_size) / 256.0)
                    .floor() as i64,
                ((plan.center[1] + plan.visible[1] / 2.0 + 2.0 * prepared.max_tile_size) / 256.0)
                    .floor() as i64,
            ];
            for y in min[1]..=max[1] {
                for x in min[0]..=max[0] {
                    if let Some(v) = prepared.terrain_chunks.get(&(x, y)) {
                        ids.extend(v.iter().copied());
                    }
                }
            }
            ids.into_iter().collect()
        } else {
            (0..prepared.terrain.len()).collect()
        };
        #[cfg(feature = "benchmark-work-counters")]
        {
            work.terrain_layers_total = prepared.terrain.len();
            work.terrain_layers_selected = terrain_ids.len();
            work.presentation_entities = p.entities.len();
        }
        for ti in terrain_ids {
            let t = &prepared.terrain[ti];
            let layer = &map.layers[t.layer];
            #[cfg(feature = "benchmark-work-counters")]
            let mut tile_work = crate::diagnosis::TileWork {
                source_layer: layer.source_layer.clone(),
                tilemap: layer.tilemap.clone(),
                z: t.slot[0],
                stored_cells: layer.cells.len(),
                ..Default::default()
            };
            let size = layer.tile_size_pixels as f64;
            // Animated tilesets draw the current frame (same size as the still image).
            let image = t.animation.as_ref().map_or(t.image, |a| a.frame(p.tick));
            let texture = self.sizes[image];
            let art = size * self.density as f64;
            let columns = (texture[0] / art) as u32;
            if columns == 0 {
                return Err("tile atlas narrower than a tile".into());
            }
            let x0 = ((plan.center[0] - plan.visible[0] / 2.0) / size)
                .floor()
                .max(0.0) as usize;
            let x1 = (((plan.center[0] + plan.visible[0] / 2.0) / size).ceil() as usize + 1)
                .min(layer.width);
            let y0 = ((plan.center[1] - plan.visible[1] / 2.0) / size)
                .floor()
                .max(0.0) as usize;
            let y1 = (((plan.center[1] + plan.visible[1] / 2.0) / size).ceil() as usize + 1)
                .min(layer.height);
            for y in y0..y1 {
                for x in x0..x1 {
                    #[cfg(feature = "benchmark-work-counters")]
                    {
                        work.tiles_visited += 1;
                        tile_work.visited += 1;
                    }
                    let cell = layer.cells[y * layer.width + x];
                    if cell == -1 {
                        continue;
                    }
                    let raw = cell as u32;
                    let id = raw & 0x1fff_ffff;
                    let source = [
                        (id % columns) as f64 * art,
                        (id / columns) as f64 * art,
                        art,
                        art,
                    ];
                    if source[1] + art > texture[1] {
                        return Err("tile source rectangle outside original atlas".into());
                    }
                    let palette = if map.cave_shimmer {
                        crate::effects::shimmer(&layer.tilemap, p.tick)
                    } else {
                        Vec::new()
                    };
                    let mut q = rect_quad(
                        image,
                        source,
                        texture,
                        [x as f64 * size, y as f64 * size, size, size],
                        Transform::default(),
                        &plan,
                        [1.0; 4],
                        &palette,
                    );
                    q.uv = tile_uv(source, texture, raw);
                    #[cfg(feature = "benchmark-work-counters")]
                    {
                        work.tiles_emitted += 1;
                        tile_work.emitted += 1;
                    }
                    commands.push((t.slot[0], order, q));
                    order += 1;
                }
            }
            #[cfg(feature = "benchmark-work-counters")]
            work.tile_layers.push(tile_work);
        }
        // The tongue tip, while the tongue is out. A caught enemy rides it back into the
        // mouth (the original pulls it in; Godot hid it at the catch).
        let tongue_tip = p.player.tongue.as_ref().map(|t| {
            let length = t.length;
            let (dx, dy) = if t.up {
                (0, -length)
            } else {
                (p.player.facing * length, 0)
            };
            eggshell_spike_core::Position {
                x: p.player.motion.current.x + t.mouth[0] + dx,
                y: p.player.motion.current.y + t.mouth[1] + dy,
            }
        });
        // Match Godot creation categories only for equal-z painter order. This
        // never groups or changes core dispatch, Session rows or activation.
        for category in 0..4 {
            for entity in &p.entities {
                #[cfg(feature = "benchmark-work-counters")]
                let work_layer = if ["p1", "o5", "o11"].contains(&entity.code.as_str())
                    || (entity.code.starts_with('e') && entity.source_index.is_some())
                {
                    10
                } else {
                    entity.layer
                };
                #[cfg(feature = "benchmark-work-counters")]
                {
                    work.entity_row_visits += 1;
                    work.entity_layers.entry(work_layer).or_default().visited += 1;
                }
                let enemy = entity.code.starts_with('e');
                let selected = if entity.code == "p1" {
                    1
                } else if entity.code == "o5" {
                    3
                } else if enemy {
                    2
                } else {
                    0
                };
                if selected != category {
                    continue;
                }
                #[cfg(feature = "benchmark-work-counters")]
                {
                    work.entities_selected += 1;
                    work.entity_layers.entry(work_layer).or_default().selected += 1;
                }
                let pulled;
                let entity = match tongue_tip {
                    Some(tip) if entity.held && !entity.hidden && entity.code.starts_with('e') => {
                        let b = entity.body_bounds;
                        let at = eggshell_spike_core::Position {
                            x: tip.x - (b[0] + b[2]) / 2,
                            y: tip.y - (b[1] + b[3]) / 2,
                        };
                        pulled = EntityPicture {
                            motion: eggshell_spike_core::Motion {
                                previous: at,
                                current: at,
                            },
                            visible: true,
                            held: false,
                            ..entity.clone()
                        };
                        &pulled
                    }
                    _ => entity,
                };
                if !entity.visible || entity.held || entity.hidden {
                    continue;
                }
                #[cfg(feature = "benchmark-work-counters")]
                let commands_start = commands.len();
                let placement = entity
                    .source_index
                    .map(|i| {
                        map.placements
                            .get(i)
                            .ok_or("entity source binding outside placements")
                    })
                    .transpose()?;
                let bounds_position = if enemy
                    && matches!(entity.status, EntityStatus::Waiting | EntityStatus::Queued)
                {
                    placement
                        .map(|v| v.position)
                        .unwrap_or(entity.motion.current)
                } else {
                    entity.motion.current
                };
                let body = entity.body_bounds.map(|v| v as f64 / SCALE as f64);
                let at = pixel(bounds_position);
                let lo = [
                    (at[0] + body[0]) * plan.scale + screen::godot_round(plan.offset[0]),
                    (at[1] + body[1]) * plan.scale + screen::godot_round(plan.offset[1]),
                ];
                let hi = [
                    (at[0] + body[2]) * plan.scale + screen::godot_round(plan.offset[0]),
                    (at[1] + body[3]) * plan.scale + screen::godot_round(plan.offset[1]),
                ];
                if body[2] > body[0]
                    && body[3] > body[1]
                    && hi[0] > 0.0
                    && hi[1] > 0.0
                    && lo[0] < container[0]
                    && lo[1] < container[1]
                {
                    entity_bounds_in_view += 1;
                }
                if entity.visual.slice.is_some() {
                    return Err("required semantic picture slice override not admitted".into());
                }
                let inactive =
                    enemy && matches!(entity.status, EntityStatus::Waiting | EntityStatus::Queued);
                if cull_art
                    && !art_can_intersect(
                        entity,
                        at,
                        body,
                        &plan,
                        container,
                        self.art_cull_margin,
                        inactive,
                    )
                {
                    if !self.placeholder_drawn(entity) {
                        self.object(self.art_key(entity), entity.variant)?;
                    }
                    continue;
                }
                if self.placeholder_drawn(entity) {
                    let t = Transform {
                        position: [at[0] + body[0], at[1] + body[1]],
                        scale: [body[2] - body[0], body[3] - body[1]],
                        ..Transform::default()
                    };
                    commands.push((
                        entity.layer,
                        order,
                        sprite_quad(
                            self.solid,
                            self.sizes[self.solid],
                            t,
                            &plan,
                            placeholder_rgba(&entity.code),
                            &[],
                        ),
                    ));
                    order += 1;
                    continue;
                }
                #[cfg(feature = "benchmark-work-counters")]
                {
                    work.entities_art_built += 1;
                    work.entity_layers.entry(work_layer).or_default().art_built += 1;
                }
                let pad = placement.and_then(|p| match p.prepared {
                    eggshell_spike_core::PreparedPlacement::Pad { large, single_use } => {
                        Some((large, single_use))
                    }
                    _ => None,
                });
                // Production LevelView binds static bridges/goals with variant0;
                // pad frames use compiler-owned large/single-use facts.
                let binding_variant = if entity.code == "p1" || entity.code == "o5" {
                    0
                } else if let Some((large, single_use)) = pad {
                    i64::from(large) + 2 * i64::from(single_use)
                } else {
                    entity.variant
                };
                let visual = self.object(
                    self.art_key(entity),
                    if pad.is_some() { 0 } else { binding_variant },
                )?;
                let inactive =
                    enemy && matches!(entity.status, EntityStatus::Waiting | EntityStatus::Queued);
                let state = if inactive {
                    VisualState::default()
                } else {
                    entity.visual.clone()
                };
                let frame = visual.sample(
                    if inactive { 0 } else { p.tick },
                    state.animation.as_deref().unwrap_or(""),
                    binding_variant,
                    // A post's frame is its colour (Godot view_state); the colour already
                    // chose the one-frame Post<colour> art.
                    if entity.code == "o23" {
                        None
                    } else {
                        state.frame
                    },
                );
                let size = self.sizes[frame.image];
                let mut transform = self.entity_transform(
                    entity,
                    placement,
                    visual,
                    frame.origin,
                    size,
                    &state,
                    inactive,
                )?;
                if entity.code == "o5" {
                    transform = Transform {
                        position: pixel(placement.ok_or("runtime goal not admitted")?.position),
                        scale: [1.0 / self.density as f64; 2],
                        origin: frame.origin,
                        ..Transform::default()
                    };
                }
                if entity.code != "p1" {
                    transform = transform.ratio(state.scale)?;
                }
                if self.density > 1 {
                    transform = transform.snap_dense(plan.scale);
                }
                let color = if inactive {
                    [0.6, 0.6, 0.6, 0.55]
                } else {
                    // Godot self_modulate multiplies the art (map_effects.gd dice colours).
                    let [r, g, b] = state.tint.unwrap_or([255; 3]).map(|c| c as f32 / 255.0);
                    [r, g, b, state.alpha.clamp(0.0, 1.0) as f32]
                };
                let mut quads = Vec::new();
                let dressing = crate::dressing::Draw {
                    at: pixel(entity.motion.current),
                    rotation: state.rotation_degrees.unwrap_or(0.0),
                    density: self.density as f64,
                    plan: &plan,
                    color,
                    palette: &state.palette,
                };
                let resized_decor = placement
                    .filter(|_| crate::dressing::resized_decor(&entity.code))
                    .filter(|_| entity.visual.asset_key.is_none());
                if let Some(placement) = resized_decor {
                    let option = |key: &str| {
                        placement
                            .properties
                            .iter()
                            .find(|(k, _)| k == key)
                            .map(|(_, v)| v)
                    };
                    let height = crate::dressing::decor_height(option("E1"));
                    let mut parts = Vec::new();
                    for part in crate::dressing::decoration_plan(
                        &entity.code,
                        placement.variant,
                        height,
                        self.decor_caps
                            .get(&(entity.code.clone(), placement.variant))
                            .map(String::as_str),
                    ) {
                        let key = crate::dressing::part_key(&entity.code, &part.art);
                        let v = self.object(&key, part.variant)?;
                        parts.push((part, v));
                    }
                    dressing.decoration(&parts, p.tick, &self.sizes, &mut quads)?;
                } else if entity.code == "p1" {
                    let placement = placement.ok_or("runtime bridge not admitted")?;
                    let geometry_index = match placement.prepared {
                        eggshell_spike_core::PreparedPlacement::Bridge { geometry_index } => {
                            geometry_index
                        }
                        _ => return Err("bridge has no compiler-owned geometry binding".into()),
                    };
                    let geometry = map
                        .bridges
                        .get(geometry_index)
                        .ok_or("prepared bridge index outside immutable map geometry")?;
                    let left = geometry.left as f64 / SCALE as f64;
                    let top = geometry.top as f64 / SCALE as f64;
                    let width = (geometry.right - geometry.left) as f64 / SCALE as f64;
                    if width == 0.0 {
                        continue;
                    }
                    transform = Transform {
                        position: [left, top],
                        scale: [width / size[0], 1.0 / self.density as f64],
                        origin: if self.density > 1 {
                            frame.origin
                        } else {
                            [0.0; 2]
                        },
                        ..Transform::default()
                    };
                    let target = [
                        (size[0] * transform.scale[0]).abs() * self.density as f64,
                        (size[1] * transform.scale[1]).abs() * self.density as f64,
                    ];
                    transform = transform.ratio(state.scale)?;
                    if let Some(cuts) = visual.slices {
                        let corner = transform.point([-transform.origin[0], -transform.origin[1]]);
                        for patch in slices(size, target, cuts)? {
                            quads.push(rect_quad(
                                frame.image,
                                patch.source,
                                size,
                                patch.destination,
                                Transform {
                                    position: corner,
                                    scale: state
                                        .scale
                                        .unwrap_or([1.0; 2])
                                        .map(|ratio| ratio / self.density as f64),
                                    ..Transform::default()
                                },
                                &plan,
                                color,
                                &state.palette,
                            ));
                        }
                    } else {
                        quads.push(sprite_quad(
                            frame.image,
                            size,
                            transform,
                            &plan,
                            color,
                            &state.palette,
                        ));
                    }
                } else if let (true, Some(cuts), [Some(width), Some(height)]) = (
                    matches!(
                        entity.code.as_str(),
                        "p2" | "p3"
                            | "p4"
                            | "p5"
                            | "p6"
                            | "p7"
                            | "p8"
                            | "p9"
                            | "p10"
                            | "p11"
                            | "p12"
                            | "p13"
                            | "p14"
                            | "p15"
                            | "p16"
                            | "p17"
                            | "p18"
                            | "p19"
                            | "p20"
                            | "p21"
                    ),
                    visual.slices,
                    state.size_pixels,
                ) {
                    // span_dressing.gd: a span body is its pack nine-slice grown to the
                    // span's width and drawn height, centred on the span. Omitted: the
                    // spans' repeat fallback (every pack span entry has slices).
                    let unit = 1.0 / self.density as f64;
                    let target = [width / unit, height / unit];
                    // p11/p12 turn about their centre (span_dressing.gd: the slices follow
                    // the span node's turn).
                    let at = Transform {
                        position: pixel(entity.motion.current),
                        scale: [unit, unit],
                        rotation: state.rotation_degrees.unwrap_or(0.0),
                        ..Transform::default()
                    };
                    if width > 0.0 && height > 0.0 {
                        for patch in
                            slices_uniform(size, target, cuts, self.uniform_for(frame.image))?
                        {
                            let d = patch.destination;
                            quads.push(rect_quad(
                                frame.image,
                                patch.source,
                                size,
                                [-target[0] / 2.0 + d[0], -target[1] / 2.0 + d[1], d[2], d[3]],
                                at,
                                &plan,
                                color,
                                &state.palette,
                            ));
                        }
                    }
                } else if let ("e35" | "o23" | "d22", Some(cuts), Some(height)) =
                    (entity.code.as_str(), visual.slices, state.size_pixels[1])
                {
                    // Nine-patches grown to the entity's height from its bottom centre.
                    // e35: StiltGuyTop, a fixed 48-pixel head over a tiled pole strip.
                    // o23: Post<colour> / SpikedPost<colour>, a cap over a tiled shaft.
                    // The Godot port stretched e35 and drew o23 with the pack's fully
                    // transparent PostCollision box, so its posts were invisible walls.
                    let unit = transform.scale[0].abs();
                    if unit <= 0.0 || !height.is_finite() || height < 0.0 {
                        return Err("nine-patch needs a non-negative height and a scale".into());
                    }
                    if entity.code == "o23" {
                        transform.position = pixel(entity.motion.current);
                        transform.rotation = 0.0;
                        transform.scale[0] = unit;
                    }
                    let target = [size[0], height / unit];
                    let top = -(target[1] - (size[1] - frame.origin[1]));
                    let upright = Transform {
                        position: transform.position,
                        scale: [transform.scale[0], unit],
                        rotation: transform.rotation,
                        origin: [0.0; 2],
                        flip: [false; 2],
                    };
                    // A post pounded flat (height 0) draws nothing.
                    let patches = if height > 0.0 {
                        slices_uniform(size, target, cuts, self.uniform_for(frame.image))?
                    } else {
                        Vec::new()
                    };
                    for patch in patches {
                        let d = patch.destination;
                        quads.push(rect_quad(
                            frame.image,
                            patch.source,
                            size,
                            [-frame.origin[0] + d[0], top + d[1], d[2], d[3]],
                            upright,
                            &plan,
                            color,
                            &state.palette,
                        ));
                    }
                } else if let (true, Some(roll)) = (
                    ["e1", "e2"].contains(&entity.code.as_str())
                        && state.animation.as_deref() == Some("Roll"),
                    self.objects.get(ROLL_SPRITE),
                ) {
                    // The pack's ShyGuy "Roll" frame is fully transparent: the original
                    // (YFS Enemies sheet) hides the Shy Guy and spawns a ShyGuyRollSprite
                    // child playing "<colour>Roll", turning at 1248 degrees per second
                    // in the roll direction. Godot drew the empty frame (invisible).
                    let art = roll.get(&0).ok_or("roll sprite binding")?;
                    let rf = art.sample(0, &format!("{}Roll", entity.variant), 0, None);
                    let direction = if entity.facing < 0 { -1.0 } else { 1.0 };
                    let mut t = transform;
                    t.origin = rf.origin;
                    t.rotation += direction * (1248.0 / 60.0 * p.tick as f64).rem_euclid(360.0);
                    quads.push(sprite_quad(
                        rf.image,
                        self.sizes[rf.image],
                        t,
                        &plan,
                        color,
                        &state.palette,
                    ));
                } else {
                    quads.push(sprite_quad(
                        frame.image,
                        size,
                        transform,
                        &plan,
                        color,
                        &state.palette,
                    ));
                }
                if entity.code == "d23" {
                    let height = placement.map_or(0.0, scenery_height);
                    let mut pillar = self.d23_pillar(
                        pixel(entity.motion.current),
                        entity.variant,
                        height,
                        &plan,
                        color,
                    )?;
                    pillar.append(&mut quads);
                    quads = pillar;
                }
                // span_dressing.gd parts: p6..p8 stalks, p11/p12 spike strips (E2).
                if let (Some(key), Some(placement)) =
                    (crate::dressing::span_part_key(&entity.code), placement)
                {
                    let e2 = crate::dressing::leading_integer(
                        placement
                            .properties
                            .iter()
                            .find(|(k, _)| k == "E2")
                            .map(|(_, v)| v),
                    );
                    let width = state.size_pixels[0].unwrap_or(0.0);
                    if let Some(variant) =
                        crate::dressing::span_part_variant(&entity.code, e2, width)
                    {
                        let art = self.object(&key, variant)?;
                        dressing.span_part(
                            &entity.code,
                            e2,
                            width,
                            art,
                            &self.sizes,
                            &mut quads,
                        )?;
                    }
                }
                // An active stilt walker is drawn from its animated parts (auxiliaries);
                // the editor image only stands for a waiting one.
                if entity
                    .auxiliary
                    .iter()
                    .any(|a| a.kind == EntityAuxiliaryKind::StiltTop && a.picture.visible)
                {
                    quads.clear();
                }
                for q in quads {
                    if visible(&q, container) {
                        commands.push((
                            if entity.code == "p1"
                                || entity.code == "o5"
                                || (enemy && entity.source_index.is_some())
                                || pad.is_some()
                            {
                                10
                            } else {
                                entity.layer
                            },
                            order,
                            q,
                        ));
                        order += 1;
                    }
                }
                for auxiliary in &entity.auxiliary {
                    let aux = &auxiliary.picture;
                    if !aux.visible {
                        continue;
                    }
                    let key = match auxiliary.kind {
                        EntityAuxiliaryKind::PlantHead => "e5_head",
                        EntityAuxiliaryKind::StiltFeet => "StiltGuy_Feet",
                        EntityAuxiliaryKind::StiltPoles => "StiltGuy_PolesMiddle",
                        EntityAuxiliaryKind::StiltTop => "StiltGuy_Top",
                    };
                    let art = self.object(aux.visual.asset_key.as_deref().unwrap_or(key), 0)?;
                    let frame = art.sample(aux.tick, &aux.animation, 0, aux.visual.frame);
                    let mut t = auxiliary_transform(
                        auxiliary,
                        frame.origin,
                        self.sizes[frame.image],
                        self.density,
                    )?;
                    if self.density > 1 {
                        t = t.snap_dense(plan.scale);
                    }
                    let stilt = matches!(
                        auxiliary.kind,
                        EntityAuxiliaryKind::StiltFeet
                            | EntityAuxiliaryKind::StiltPoles
                            | EntityAuxiliaryKind::StiltTop
                    );
                    let palette = if stilt {
                        self.stilt_palettes
                            .get(&entity.variant)
                            .map_or(&aux.visual.palette, |p| p)
                    } else {
                        &aux.visual.palette
                    };
                    let q = sprite_quad(
                        frame.image,
                        self.sizes[frame.image],
                        t,
                        &plan,
                        [1.0, 1.0, 1.0, aux.visual.alpha as f32],
                        palette,
                    );
                    if visible(&q, container) {
                        commands.push((aux.layer, order, q));
                        order += 1;
                    }
                }
                if let Some(head) = fallback_head_box(state.head_box, &entity.auxiliary) {
                    let art = self.object(&format!("{}_head", entity.code), 0)?;
                    let f = art.sample(p.tick, "", 0, None);
                    let rect = head.map(|v| v as f64 / SCALE as f64);
                    let q = rect_quad(
                        f.image,
                        [0.0, 0.0, self.sizes[f.image][0], self.sizes[f.image][1]],
                        self.sizes[f.image],
                        [rect[0], rect[1], rect[2] - rect[0], rect[3] - rect[1]],
                        Transform::default(),
                        &plan,
                        [1.0; 4],
                        &[],
                    );
                    if visible(&q, container) {
                        commands.push((10, order, q));
                        order += 1;
                    }
                }
                #[cfg(feature = "benchmark-work-counters")]
                if commands.len() > commands_start {
                    work.entities_emitted += 1;
                    let mut layers = std::collections::BTreeSet::new();
                    for (z, _, _) in &commands[commands_start..] {
                        work.entity_layers.entry(*z).or_default().quads_emitted += 1;
                        layers.insert(*z);
                    }
                    for z in layers {
                        work.entity_layers.entry(z).or_default().emitted += 1;
                    }
                }
            }
        }
        // Layer 12: in front of the layer-11 player, so puffs at the feet stay visible.
        let settings = *self.feel.lock().map_err(|_| "feel lock poisoned")?;
        for particle in self
            .dust
            .lock()
            .map_err(|_| "dust lock poisoned")?
            .particles(p.tick, p.map_index, settings)
        {
            commands.push((
                12,
                order,
                rect_quad(
                    self.solid,
                    [0.0, 0.0, 1.0, 1.0],
                    self.sizes[self.solid],
                    particle.rect,
                    Transform::default(),
                    &plan,
                    particle.color,
                    &[],
                ),
            ));
            order += 1;
        }
        if p.player.visible
            && let (Some(tongue), Some(art)) = (p.player.tongue, &self.tongue)
        {
            // Drawn under Yoshi, from the mouth: R/L grow sideways, U grows upward.
            let visual = &art[if tongue.up {
                2
            } else if p.player.facing < 0 {
                0
            } else {
                1
            }];
            let f = visual.sample(0, "", 0, None);
            let size = self.sizes[f.image];
            let cuts = visual.slices.ok_or("tongue art lost its slices")?;
            let unit = 1.0 / self.density as f64;
            let length = tongue.length as f64 / SCALE as f64 / unit;
            let (target, corner) = if tongue.up {
                ([size[0], length], [-f.origin[0], -length])
            } else if p.player.facing < 0 {
                ([length, size[1]], [-length, -f.origin[1]])
            } else {
                ([length, size[1]], [0.0, -f.origin[1]])
            };
            let body = pixel(p.player.motion.current);
            let mouth = Transform {
                position: [
                    body[0] + tongue.mouth[0] as f64 / SCALE as f64,
                    body[1] + tongue.mouth[1] as f64 / SCALE as f64,
                ],
                scale: [unit, unit],
                ..Transform::default()
            };
            let palette = if p.player.visual.palette.is_empty() {
                &self.palette
            } else {
                &p.player.visual.palette
            };
            for patch in slices_uniform(size, target, cuts, self.uniform_for(f.image))? {
                let d = patch.destination;
                commands.push((
                    11,
                    order,
                    rect_quad(
                        f.image,
                        patch.source,
                        size,
                        [corner[0] + d[0], corner[1] + d[1], d[2], d[3]],
                        mouth,
                        &plan,
                        [1.0, 1.0, 1.0, p.player.visual.alpha as f32],
                        palette,
                    ),
                ));
                order += 1;
            }
        }
        if p.player.visible {
            let pose = &p.player.selected_pose;
            let running = ["Walk0", "Walk1", "Sprint0", "Sprint1"].contains(&pose.name.as_str());
            let literal = if running {
                let frames = self
                    .player
                    .animations
                    .iter()
                    .find(|(n, _)| *n == pose.name)
                    .map_or(0, |(_, a)| a.frames.len());
                Some(
                    self.run_clock
                        .lock()
                        .map_err(|_| "run clock lock poisoned")?
                        .frame(p.tick, p.player.velocity.x, frames),
                )
            } else {
                None
            };
            let f = self
                .player
                .sample_required(pose.tick, &pose.name, pose.frame, literal)?;
            let mut t = Transform {
                position: pixel(p.player.motion.current),
                scale: [
                    p.player.facing as f64 / self.density as f64,
                    1.0 / self.density as f64,
                ],
                origin: f.origin,
                ..Transform::default()
            };
            t = t.ratio(p.player.visual.scale)?;
            if self.density > 1 {
                t = t.snap_dense(plan.scale);
            }
            let palette = if p.player.visual.palette.is_empty() {
                &self.palette
            } else {
                &p.player.visual.palette
            };
            // Carried eggs trail behind Yoshi (drawn first, so Yoshi covers them).
            let body = pixel(p.player.motion.current);
            let (trail, falling) = {
                let mut trail = self.trail.lock().map_err(|_| "egg trail lock poisoned")?;
                trail.pops(p.player.egg_pops, &p.player.eggs);
                let eggs = trail.update(p.tick, body, p.player.eggs.len());
                (eggs, trail.falling())
            };
            if let Ok(egg_art) = self.object("o7", 0) {
                let carried = p.player.eggs.iter().copied().zip(trail.iter().copied());
                for (colour, at) in carried.chain(falling) {
                    let name = ["Green", "Yellow", "Red", "Purple"][colour.clamp(0, 3) as usize];
                    let ef = egg_art.sample(p.tick, name, 0, None);
                    commands.push((
                        11,
                        order,
                        sprite_quad(
                            ef.image,
                            self.sizes[ef.image],
                            Transform {
                                position: at,
                                scale: [1.0 / self.density as f64; 2],
                                origin: ef.origin,
                                ..Transform::default()
                            },
                            &plan,
                            [1.0, 1.0, 1.0, 1.0],
                            &[],
                        ),
                    ));
                    order += 1;
                }
            }
            commands.push((
                11,
                order,
                sprite_quad(
                    f.image,
                    self.sizes[f.image],
                    t,
                    &plan,
                    [1.0, 1.0, 1.0, p.player.visual.alpha as f32],
                    palette,
                ),
            ));
            order += 1;
            // The aim cursor: 144 px from the egg's start point (x, y-32) along the throw
            // direction (YFS EggTargetObj: origin 160 px below its 32 px target).
            if let (Some(angle), Some(target)) = (p.player.aim_degrees, &self.egg_target) {
                let tf = target.sample(p.tick, "", 0, None);
                let (s, c) = angle.to_radians().sin_cos();
                commands.push((
                    11,
                    order,
                    sprite_quad(
                        tf.image,
                        self.sizes[tf.image],
                        Transform {
                            position: [body[0] + 144.0 * c, body[1] - 32.0 + 144.0 * s],
                            scale: [1.0 / self.density as f64; 2],
                            origin: tf.origin,
                            ..Transform::default()
                        },
                        &plan,
                        [1.0; 4],
                        &[],
                    ),
                ));
                order += 1;
            }
        }
        for (index, aux) in std::iter::once((0, &p.companions.companion))
            .chain(std::iter::once((1, &p.companions.bubble)))
            .chain(p.companions.rescuers.iter().map(|p| (2, p)))
        {
            if !aux.visible {
                continue;
            }
            let (image, origin, scale) = if let Some(art) = &self.companions[index] {
                let f = art.sample(aux.tick, &aux.animation, 0, aux.visual.frame);
                (
                    f.image,
                    f.origin,
                    [
                        aux.facing as f64 / self.density as f64,
                        1.0 / self.density as f64,
                    ],
                )
            } else {
                match index {
                    0 => (self.solid, [8.0, 24.0], [16.0, 24.0]),
                    1 => (self.bubble, [32.0, 62.0], [1.0, 1.0]),
                    _ => (self.solid, [4.0, 6.0], [8.0, 12.0]),
                }
            };
            let generated = self.companions[index].is_none() && index != 1;
            let t = if generated {
                Transform {
                    position: pixel(aux.motion.current),
                    scale,
                    origin: [origin[0] / scale[0], origin[1] / scale[1]],
                    ..Transform::default()
                }
            } else {
                Transform {
                    position: pixel(aux.motion.current),
                    scale,
                    origin,
                    ..Transform::default()
                }
            };
            let t = t.ratio(aux.visual.scale)?;
            let t = if self.density > 1 && !generated {
                t.snap_dense(plan.scale)
            } else {
                t
            };
            commands.push((
                aux.layer,
                order,
                sprite_quad(image, self.sizes[image], t, &plan, [1.0; 4], &[]),
            ));
            order += 1;
        }
        commands.sort_by_key(|(z, order, _)| (*z, *order));
        let world = commands.into_iter().map(|(_, _, q)| q).collect();
        let mut hud = Vec::new();
        let hud_layout = self.hud.emit(
            &p.hud,
            p.tick,
            container,
            plan.base_scale,
            self.density,
            &self.sizes,
            self.solid,
            &mut hud,
        )?;
        if let Some(message) = &p.message {
            self.hud.emit_message(
                message,
                container,
                hud_layout.size[1],
                &self.sizes,
                self.solid,
                &mut hud,
            )?;
        }
        let player = pixel(p.player.motion.current);
        let light_origin = [
            plan.offset[0] + player[0] * plan.scale,
            plan.offset[1] + (player[1] - 28.0) * plan.scale,
        ];
        let mut tint = Vec::new();
        if let Some(rgba) = map_tint(&map.tint) {
            tint.push(fullscreen_quad(self.solid, container, rgba));
        }
        let water = prepared.water.frame(
            &plan,
            container,
            p.tick,
            if settings.water_fx_enabled {
                settings.water_fx_strength
            } else {
                0
            },
        );
        let mut water_surface = Vec::new();
        water.emit_surface(self.solid, &mut water_surface);
        Ok(Picture {
            water,
            water_surface,
            #[cfg(feature = "benchmark-work-counters")]
            work,
            tint,
            plan,
            entity_bounds_in_view,
            world,
            hud,
            hud_layout,
            light_origin,
            light_radius: 128.0 * plan.scale,
            darkness: map.darkness_percent.clamp(0, 100) as f64 / 100.0,
        })
    }
    /// The object-table key an entity draws with: its semantic asset key, except that the
    /// fire and ice shots use their own original art (PACKLESS_ART) instead of the e16
    /// stand-in when the pack has it.
    fn art_key<'a>(&self, entity: &'a EntityPicture) -> &'a str {
        if ["fire_shot", "ice_shot"].contains(&entity.code.as_str())
            && self.objects.contains_key(&entity.code)
        {
            return &entity.code;
        }
        entity.visual.asset_key.as_deref().unwrap_or(&entity.code)
    }
    /// A packless runtime code with no art key draws as its placeholder square.
    fn placeholder_drawn(&self, entity: &EntityPicture) -> bool {
        entity.visual.asset_key.is_none()
            && PACKLESS_RUNTIME_CODES.contains(&entity.code.as_str())
            && !self.objects.contains_key(&entity.code)
    }
    /// pack_dressing.gd decoration_plan d23 pillar: the MountainPlatformPillar image,
    /// centred and tiled downward to the E1 height, 32 px (form 1: 64 px) below the
    /// placement, drawn behind the ledge.
    fn d23_pillar(
        &self,
        at: [f64; 2],
        variant: i64,
        height: f64,
        plan: &Plan,
        color: [f32; 4],
    ) -> Result<Vec<crate::gles::Quad>, String> {
        let visual = self.object("d23_pillar", 0)?;
        let frame = visual.sample(0, "", 0, None);
        let texels = self.sizes[frame.image];
        let native = texels.map(|v| v / self.density as f64);
        let transform = Transform {
            position: [at[0], at[1] + if variant == 0 { 32.0 } else { 64.0 }],
            ..Transform::default()
        };
        let mut quads = Vec::new();
        let mut top = 0.0;
        while top < height && native[1] > 0.0 {
            let h = native[1].min(height - top);
            quads.push(rect_quad(
                frame.image,
                [0.0, 0.0, texels[0], h * self.density as f64],
                texels,
                [-native[0] / 2.0, top, native[0], h],
                transform,
                plan,
                color,
                &[],
            ));
            top += native[1];
        }
        Ok(quads)
    }
    fn object(&self, code: &str, variant: i64) -> Result<&Visual, String> {
        self.objects
            .get(code)
            .and_then(|v| v.get(&variant).or_else(|| v.get(&0)))
            .ok_or_else(|| format!("unprepared required object binding: {code}:{variant}"))
    }
    #[allow(clippy::too_many_arguments)]
    fn entity_transform(
        &self,
        e: &EntityPicture,
        placement: Option<&Placement>,
        art: &Visual,
        origin: [f64; 2],
        size: [f64; 2],
        state: &VisualState,
        inactive: bool,
    ) -> Result<Transform, String> {
        let actor = e.code.starts_with('e') || e.source_index.is_none();
        let mut t = Transform {
            position: if inactive {
                pixel(
                    placement
                        .ok_or("inactive entity has no placement")?
                        .position,
                )
            } else {
                pixel(e.motion.current)
            },
            scale: [1.0 / self.density as f64; 2],
            origin: state.origin_pixels.unwrap_or(origin),
            rotation: placement
                .filter(|_| !actor)
                .map(|p| p.rotation as f64)
                .unwrap_or(0.0),
            ..Transform::default()
        };
        if actor {
            let facing = if inactive {
                if placement.unwrap().mirror == 1 {
                    1
                } else {
                    -1
                }
            } else {
                e.facing
            };
            if art.anchor == Anchor::Position {
                t.scale[0] *= if facing == art.facing { 1.0 } else { -1.0 };
            } else {
                t.flip[0] = facing < 0;
                let b = e.body_bounds.map(|v| v as f64 / SCALE as f64);
                t.position[0] += (b[0] + b[2]) / 2.0;
                t.position[1] += if origin[1] >= size[1] - 0.5 {
                    b[3]
                } else {
                    (b[1] + b[3]) / 2.0
                };
            }
        } else if placement.is_some_and(|p| p.mirror == 1) {
            if art.anchor == Anchor::Position {
                t.scale[0] *= -1.0;
            } else {
                t.flip[0] = true;
            }
        }
        if let Some(placement) = placement
            && let eggshell_spike_core::PreparedPlacement::Pad { large, single_use } =
                placement.prepared
        {
            let selected = art.sample(0, "", i64::from(large) + 2 * i64::from(single_use), None);
            let base = (if large { 48.0 } else { 32.0 }) / self.sizes[selected.image][1];
            t.scale = [base, base];
            t.rotation = 0.0;
            t.flip = [false; 2];
        }
        for (i, source_size) in size.iter().enumerate() {
            if let Some(width) = state.size_pixels[i] {
                t.scale[i] = t.scale[i].signum() * width / source_size;
            }
            t.position[i] += state.offset_pixels[i];
        }
        for (i, flip) in [state.flip_h, state.flip_v].into_iter().enumerate() {
            if let Some(flip) = flip {
                if art.anchor == Anchor::Position {
                    t.scale[i] = t.scale[i].abs() * if flip { -1.0 } else { 1.0 };
                } else {
                    t.flip[i] = flip;
                }
            }
        }
        if let Some(rotation) = state.rotation_degrees {
            t.rotation = rotation;
        }
        Ok(t)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn head() -> EntityAuxiliaryPicture {
        EntityAuxiliaryPicture {
            kind: EntityAuxiliaryKind::PlantHead,
            scale: [1.0; 2],
            picture: eggshell_spike_core::AuxiliaryPicture {
                motion: eggshell_spike_core::Motion {
                    previous: Default::default(),
                    current: eggshell_spike_core::Position {
                        x: 100 * SCALE,
                        y: 50 * SCALE,
                    },
                },
                visible: true,
                layer: 10,
                facing: -1,
                animation: String::new(),
                tick: 0,
                visual: VisualState {
                    origin_pixels: Some([0.0; 2]),
                    size_pixels: [Some(48.0), Some(24.0)],
                    rotation_degrees: Some(0.0),
                    ..Default::default()
                },
            },
        }
    }
    #[test]
    fn plant_head_uses_axis_aligned_hull_not_facing_rotation_or_pack_origin() {
        for density in [1, 2] {
            let t = auxiliary_transform(&head(), [32.0, 54.0], [64.0, 54.0], density).unwrap();
            assert_eq!(t.position, [100.0, 50.0]);
            assert_eq!(t.origin, [0.0, 0.0]);
            assert_eq!(t.rotation, 0.0);
            assert_eq!(t.flip, [false; 2]);
            assert_eq!(t.point([0.0, 0.0]), [100.0, 50.0]);
            assert_eq!(t.point([64.0, 54.0]), [148.0, 74.0]);
        }
    }
    #[test]
    fn map_tint_follows_map_effects_plan() {
        assert_eq!(map_tint("0_255,255,255"), None);
        assert_eq!(map_tint("0.5_255,0,0"), None);
        assert_eq!(map_tint("junk"), None);
        assert_eq!(map_tint("30_255,0,0"), Some([1.0, 0.0, 0.0, 0.3]));
        assert_eq!(map_tint("80_510,-4,51.9"), Some([1.0, 0.0, 0.2, 0.5]));
        assert_eq!(map_tint("10"), Some([0.0, 0.0, 0.0, 0.1]));
    }
    #[test]
    fn fullscreen_stand_in_covers_actual_container_and_keeps_opaque_alpha() {
        for size in [[640.0, 480.0], [320.0, 240.0]] {
            let q = fullscreen_quad(9, size, [0.25, 0.5, 0.75, 1.0]);
            assert_eq!(q.image, 9);
            assert_eq!(q.corners[2], [size[0] as f32, size[1] as f32]);
            assert_eq!(q.color[3], 1.0);
            assert!(q.palette.is_empty());
        }
    }
    #[test]
    fn auxiliary_is_not_drawn_again_from_body_hull_hint() {
        let hint = Some([1, 2, 3, 4]);
        let mut aux = head();
        assert_eq!(fallback_head_box(hint, &[]), hint);
        assert_eq!(fallback_head_box(hint, &[aux.clone()]), None);
        aux.picture.visible = false;
        assert_eq!(fallback_head_box(hint, &[aux]), None);
    }
    #[test]
    fn packless_runtime_codes_are_runtime_codes_and_take_godot_placeholder_hues() {
        for code in PACKLESS_RUNTIME_CODES {
            assert!(eggshell_spike_core::RUNTIME_CODES.contains(&code), "{code}");
        }
        // djb2 of "enemy_petal" is 447528952, a hue of 352 degrees.
        let rgba = placeholder_rgba("enemy_petal");
        let want = [
            0.65,
            0.2925,
            0.65 * (1.0 - 0.55 * (352.0 / 60.0 - 5.0)),
            1.0,
        ];
        for (got, want) in rgba.iter().zip(want) {
            assert!((f64::from(*got) - want).abs() < 1e-6, "{rgba:?}");
        }
    }
    /// Every code the core can create during play has an object binding in the pinned
    /// pack or draws as its placeholder, and the verification levels that spawn them
    /// draw every tick. aka only: PLAYER_PACK_ROOT, PLAYER_PACK_INVENTORY, PLAYER_SCHEMA
    /// and PLAYER_METRICS name the private inputs.
    #[test]
    #[ignore]
    fn every_runtime_code_has_a_binding() {
        let env = |name: &str| std::env::var(name).unwrap_or_else(|_| panic!("{name} unset"));
        let pack = Pack::open(
            Path::new(&env("PLAYER_PACK_ROOT")),
            Path::new(&env("PLAYER_PACK_INVENTORY")),
        )
        .unwrap();
        let schema = std::fs::read_to_string(env("PLAYER_SCHEMA")).unwrap();
        let collision = include_str!("../../../../data/collision_table.json");
        let fixtures = concat!(env!("CARGO_MANIFEST_DIR"), "/../core/tests/fixtures");
        let mut drawn = std::collections::BTreeSet::new();
        for name in [
            "petals_target",
            "spitters_target",
            "shooters_target",
            "shells_target",
            "launchers_target",
            "elements_target",
            "melons_target",
            "rollers_target",
            "sprouts_target",
            "jugglers_target",
            "stilts_target",
        ] {
            let level = std::fs::read_to_string(format!("{fixtures}/{name}.level.json")).unwrap();
            let mut session =
                eggshell_spike_core::Session::load(&level, collision, &schema).unwrap();
            let codes = session.admission_report().admitted_codes.clone();
            let mut scene = Scene::prepare(
                session.world(),
                &codes,
                &pack,
                Path::new(&env("PLAYER_METRICS")),
            )
            .unwrap();
            scene.prepare_headless_assets(&pack).unwrap();
            for code in eggshell_spike_core::RUNTIME_CODES {
                assert!(
                    scene.objects.contains_key(code) || PACKLESS_RUNTIME_CODES.contains(&code),
                    "{name}: runtime code {code} has no binding (or a binding and a placeholder)"
                );
            }
            session.configure_presentation_index(scene.absolute_origin_guard());
            for step in 0..=900 {
                if step > 0 {
                    session.advance(0).unwrap();
                }
                let (map_index, focus) = session.presentation_view();
                let region = scene
                    .presentation_region(map_index, focus, [640.0, 480.0], 0)
                    .unwrap();
                let picture = session.presentation_region(region);
                drawn.extend(
                    picture
                        .entities
                        .iter()
                        .filter(|e| e.visible && e.source_index.is_none())
                        .map(|e| e.code.clone()),
                );
                scene
                    .picture(&picture, [640.0, 480.0], 0)
                    .unwrap_or_else(|e| panic!("{name} step {step}: {e}"));
            }
        }
        println!("RUNTIME_CODES_DRAWN {drawn:?}");
        for code in ["enemy_petal", "enemy_pellet", "enemy_spike"] {
            assert!(drawn.contains(code), "{code} never drawn");
        }
    }
}
