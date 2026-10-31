//! Renderer preparation and terrain/entity binding. No Session state is copied or changed.
use crate::{
    background::Background,
    binding::{Anchor, Catalog, Visual},
    geometry::{Transform, rect_quad, slices, slices_uniform, sprite_quad, tile_uv, visible},
    gles::{Gles, Quad},
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

struct Terrain {
    image: usize,
    layer: usize,
    slot: [i64; 2],
}
struct PreparedMap {
    map: Map,
    background: Background,
    terrain: Vec<Terrain>,
    gradient_stand_ins: Vec<i64>,
    terrain_chunks: HashMap<(i64, i64), Vec<usize>>,
    max_tile_size: f64,
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
    /// The original's aim cursor (hud EggTarget), when the pack has it.
    egg_target: Option<Visual>,
    /// Drawing-only trail of Yoshi positions for carried eggs (never saved, never sim).
    trail: std::sync::Mutex<Trail>,
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
            if !visual.states.contains_key(&key) && visual.animations.iter().any(|(n, _)| *n == name)
            {
                visual.states.insert(key, name);
            }
        }
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
/// Yoshi's recent positions (one per step that moved him) and the drawn carried eggs.
/// YFS Yoshi sheet: egg slot k tweens (0.1 s) to YoshiPos[latest - 10k] - 16 px.
#[derive(Default)]
struct Trail {
    last_tick: i64,
    path: std::collections::VecDeque<[f64; 2]>,
    eggs: Vec<[f64; 2]>,
}
impl Trail {
    const KEEP: usize = 64;
    fn update(&mut self, tick: i64, at: [f64; 2], count: usize) -> Vec<[f64; 2]> {
        if tick != self.last_tick {
            self.last_tick = tick;
            if self.path.back() != Some(&at) {
                self.path.push_back(at);
                if self.path.len() > Self::KEEP {
                    self.path.pop_front();
                }
            }
            self.eggs.truncate(count);
            while self.eggs.len() < count {
                self.eggs.push([at[0], at[1] - 16.0]);
            }
            for (k, egg) in self.eggs.iter_mut().enumerate() {
                let back = 10 * (k + 1);
                let target = self
                    .path
                    .len()
                    .checked_sub(1 + back)
                    .and_then(|i| self.path.get(i))
                    .or(self.path.front())
                    .copied()
                    .unwrap_or(at);
                for i in 0..2 {
                    let goal = target[i] - if i == 1 { 16.0 } else { 0.0 };
                    egg[i] += (goal - egg[i]) / 6.0;
                }
            }
        }
        self.eggs.clone()
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
            let mut gradient_stand_ins = Vec::new();
            // The selected target has no generated gradient or terrain strip entries.
            // Do not silently discard required visual work if input scope changes.
            for (key, value) in &map.source_properties {
                if ["gradient", "customGradientGenerator"].contains(&key.as_str())
                    && matches!(value,PropertyValue::String(v) if !v.is_empty())
                {
                    if !benchmark_real_screen {
                        return Err(format!("required {key} renderer not admitted"));
                    }
                    let layer = if key == "gradient" { -30 } else { -39 };
                    gradient_stand_ins.push(layer);
                    visual_omissions.push(format!(
                        "map={} field={key} stand_in=gradient layer={layer} opaque_fullscreen=true",
                        map.name
                    ));
                }
            }
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
                gradient_stand_ins,
                terrain_chunks,
                max_tile_size,
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
            .chain(["e5_head", "e1"])
        {
            if objects.contains_key(code) {
                continue;
            }
            let entry = object_entries
                .get(code)
                .ok_or_else(|| format!("required admitted object asset absent: {code}"))?;
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
            egg_target,
            trail: std::sync::Mutex::new(Trail::default()),
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
    #[cfg(feature = "benchmark-work-counters")]
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
        self.prepare_art_cull_margin();
        Ok(())
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
    fn picture_configured(
        &self,
        p: &Presentation,
        container: [f64; 2],
        zoom: i32,
        cull_art: bool,
        chunk_layers: bool,
    ) -> Result<Picture, String> {
        if self.sizes.len() != self.catalog.files.len() + 2 {
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
        let plan = screen::plan(
            container,
            [map.width_pixels as f64, map.height_pixels as f64],
            focus,
            self.density,
            zoom,
        )?;
        #[cfg(feature = "benchmark-work-counters")]
        let mut work = crate::diagnosis::SceneWork {
            art_cull_margin: self.art_cull_margin,
            ..Default::default()
        };
        let mut entity_bounds_in_view = 0_u64; // measurement only, inside existing entity traversal
        let mut commands: Vec<(i64, u64, Quad)> = Vec::new();
        let mut order = 0u64;
        for layer in &prepared.gradient_stand_ins {
            commands.push((
                *layer,
                order,
                fullscreen_quad(
                    self.solid,
                    container,
                    [
                        map.background_color[0] as f32 / 255.0,
                        map.background_color[1] as f32 / 255.0,
                        map.background_color[2] as f32 / 255.0,
                        1.0,
                    ],
                ),
            ));
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
            let texture = self.sizes[t.image];
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
                        t.image,
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
                if !entity.visible || entity.held || entity.hidden {
                    continue;
                }
                // seed_shot.gd has no pack art (the original view draws a diagnostic
                // square for it): draw the seed's 8 px body as a small seed-coloured quad.
                if entity.code == "seed_shot" {
                    let t = Transform {
                        position: pixel(entity.motion.current),
                        scale: [8.0, 8.0],
                        origin: [0.5, 0.5],
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
                            [0.24, 0.16, 0.08, 1.0],
                            &[],
                        ),
                    ));
                    order += 1;
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
                    self.object(&entity.code, entity.variant)?;
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
                    entity.visual.asset_key.as_deref().unwrap_or(&entity.code),
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
                if entity.code == "p1" {
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
                    // decorative stalks (p5/p6..p8 E2) and the spans' repeat fallback.
                    let unit = 1.0 / self.density as f64;
                    let target = [width / unit, height / unit];
                    let at = Transform {
                        position: pixel(entity.motion.current),
                        scale: [unit, unit],
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
                } else if let ("e35" | "o23", Some(cuts), Some(height)) =
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
            let f = self
                .player
                .sample_required(pose.tick, &pose.name, pose.frame, None)?;
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
            let trail = self
                .trail
                .lock()
                .map_err(|_| "egg trail lock poisoned")?
                .update(p.tick, body, p.player.eggs.len());
            if let Ok(egg_art) = self.object("o7", 0) {
                for (colour, at) in p.player.eggs.iter().zip(&trail) {
                    let name = ["Green", "Yellow", "Red", "Purple"][(*colour).clamp(0, 3) as usize];
                    let ef = egg_art.sample(p.tick, name, 0, None);
                    commands.push((
                        11,
                        order,
                        sprite_quad(
                            ef.image,
                            self.sizes[ef.image],
                            Transform {
                                position: *at,
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
        if map.tint != "0_255,255,255" && !map.tint.starts_with("0_") {
            if !self.benchmark_real_screen {
                return Err("nonzero tint overlay not admitted".into());
            }
            let (strength, colour) = map.tint.split_once('_').unwrap_or((&map.tint, "0,0,0"));
            let alpha = strength.parse::<f32>().unwrap_or(0.0).clamp(0.0, 50.0) / 100.0;
            let mut rgba = [0.0, 0.0, 0.0, alpha];
            for (i, c) in colour.split(',').take(3).enumerate() {
                rgba[i] = c.parse::<f32>().unwrap_or(0.0).clamp(0.0, 255.0) / 255.0;
            }
            if alpha >= 0.01 {
                tint.push(fullscreen_quad(self.solid, container, rgba));
            }
        }
        Ok(Picture {
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
}
