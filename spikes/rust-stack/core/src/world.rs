//! Immutable level compilation. JSON is confined to this load boundary.
//! Compilation is NOT gameplay admission; Session still refuses unsupported rules.
use crate::{
    math::{floor_div, round_integer, round_units},
    polygon,
    schema::{hash, invalid},
    BridgeGeometry, DrawSlot, Error, Map, Placement, Position, PreparedPlacement, PropertyValue,
    TerrainHazard, TileCollision, TileLayer, World, SCALE,
};
use serde_json::{Map as JsonObject, Value};
use std::collections::BTreeSet;
const MAX_CELLS: usize = 4_000_000;
const MAX_LEVEL_CELLS: usize = 16_000_000;
const MASK: u32 = 0x1fff_ffff;
const H: u32 = 0x8000_0000;
const V: u32 = 0x4000_0000;
const D: u32 = 0x2000_0000;

impl World {
    /// Compile immutable terrain/placements only. Does not run starts or admit simulation.
    pub fn compile(level_json: &str, collision_json: &str) -> Result<Self, Error> {
        Self::compile_configured(level_json, collision_json, false)
    }
    /// Explicit benchmark drawing omission; source properties/identity stay intact.
    pub fn compile_benchmark_real_screen(
        level_json: &str,
        collision_json: &str,
    ) -> Result<Self, Error> {
        Self::compile_configured(level_json, collision_json, true)
    }
    fn compile_configured(
        level_json: &str,
        collision_json: &str,
        _benchmark_real_screen: bool,
    ) -> Result<Self, Error> {
        if level_json.len() > 16_777_216 || collision_json.len() > 16_777_216 {
            return Err(invalid("level/collision exceeds 16 MiB"));
        }
        let outer: Value =
            serde_json::from_str(level_json).map_err(|e| invalid(&format!("level JSON: {e}")))?;
        let (code, value) = match outer {
            Value::String(code) => {
                let value = serde_json::from_str(&code)
                    .map_err(|e| invalid(&format!("encoded level JSON: {e}")))?;
                (code, value)
            }
            value => (level_json.to_string(), value),
        };
        let level = object(&value, "Level")?;
        for field in ["version", "name", "desc"] {
            text(level.get(field), field)?;
        }
        let legacy_writer = text(level.get("version"), "version")? < "s3.8";
        if !level
            .get("author")
            .is_some_and(|v| v.is_string() || v.is_number())
        {
            return Err(invalid("Level.author"));
        }
        for field in ["flowers", "redcoins"] {
            let number = number(level.get(field).unwrap_or(&Value::from(0)), field)?;
            if number.fract() != 0.0 || number < i32::MIN as f64 || number > i32::MAX as f64 {
                return Err(invalid("collectible target"));
            }
        }
        let collision: Value = serde_json::from_str(collision_json)
            .map_err(|e| invalid(&format!("collision JSON: {e}")))?;
        let collision = object(&collision, "Collision")?;
        if collision.get("version").and_then(Value::as_i64) != Some(2) {
            return Err(invalid("collision version"));
        }
        let facts = object(
            collision
                .get("tilemaps")
                .ok_or_else(|| invalid("collision.tilemaps"))?,
            "tilemaps",
        )?;
        let sources = object(
            level.get("maps").ok_or_else(|| invalid("Level.maps"))?,
            "maps",
        )?;
        if sources.is_empty() {
            return Err(invalid("empty maps"));
        }
        let mut names = sources
            .keys()
            .map(|key| {
                let number = key
                    .strip_prefix("map")
                    .and_then(|n| n.parse::<u32>().ok())
                    .filter(|n| *n > 0 && format!("map{n}") == *key)
                    .ok_or_else(|| invalid("map name"))?;
                Ok((number, key))
            })
            .collect::<Result<Vec<_>, Error>>()?;
        names.sort_by_key(|(number, _)| *number);
        let start = object(
            level
                .get("startpoint")
                .ok_or_else(|| invalid("startpoint"))?,
            "startpoint",
        )?;
        let selected = positive(start.get("map"), "startpoint.map")?;
        let initial_map = names
            .iter()
            .position(|(number, _)| *number as usize == selected)
            .ok_or_else(|| invalid("missing initial map"))?
            + 1;
        let spawn = Position {
            x: round_units(number_required(start, "X")?)?,
            y: round_units(number_required(start, "Y")?)?,
        };
        let spawn_facing = if optional_number(start, "M", 0.0)? as i64 == 1 {
            -1
        } else {
            1
        };
        let player_palette = start
            .get("palette")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(|s| s.split('_').map(rgb).collect())
            .unwrap_or_default();
        let mut maps = Vec::new();
        let mut total_cells = 0;
        for (_, name) in names {
            let source = object(&sources[name], name)?;
            let width = positive(source.get("width"), "map.width")?;
            let height = positive(source.get("height"), "map.height")?;
            let objects = object(
                source
                    .get("objects")
                    .ok_or_else(|| invalid("map.objects"))?,
                "objects",
            )?;
            let mut placements = Vec::new();
            let mut bridges = Vec::new();
            for (id, raw) in source_ids(objects) {
                let raw = object(raw, "placement")?;
                let code = text(raw.get("A"), "placement.A")?.to_string();
                // level_code.gd _normalize_objects: before writer s3.8 (a string compare),
                // a repeating switch was o14 with E1 "1"; it becomes F 1 without E1.
                let legacy_switch = legacy_writer
                    && code == "o14"
                    && raw.get("E1").and_then(Value::as_str) == Some("1");
                let mut variant = optional_number(raw, "F", 0.0)? as i64;
                if legacy_switch {
                    variant = 1;
                }
                let mirror = optional_number(raw, "M", 0.0)? as i64;
                let rotation = optional_number(raw, "R", 0.0)? as i64;
                let mut position = Position {
                    x: round_units(number_required(raw, "X")?)?,
                    y: round_units(number_required(raw, "Y")?)?,
                };
                // slime_drop.gd prepare: the dripping form starts 16 px higher.
                if code == "e15" && variant == 1 {
                    position.y = position
                        .y
                        .checked_sub(16 * SCALE)
                        .ok_or_else(|| invalid("slime position"))?;
                }
                // soft_giant.gd prepare: the body stands on the placement's lower edge.
                if code == "e24" {
                    position.y = position
                        .y
                        .checked_add(32 * SCALE)
                        .ok_or_else(|| invalid("soft giant position"))?;
                }
                // Original stilt preparation anchors feet at placement's lower edge.
                if code == "e35" {
                    position.y = position
                        .y
                        .checked_add(16 * SCALE)
                        .ok_or_else(|| invalid("stilt position"))?;
                }
                let prepared = match code.as_str() {
                    "p1" => {
                        let width = numeric_option(raw.get("E1"), "bridge width")?;
                        if width < 0.0 {
                            return Err(invalid("negative bridge width"));
                        }
                        let size = round_units(width)?;
                        let left = position
                            .x
                            .checked_sub(size / 2)
                            .ok_or_else(|| invalid("bridge left overflow"))?;
                        let right = position
                            .x
                            .checked_add(size / 2)
                            .ok_or_else(|| invalid("bridge right overflow"))?;
                        let top = position
                            .y
                            .checked_sub(16 * SCALE)
                            .ok_or_else(|| invalid("bridge top overflow"))?;
                        let geometry_index = bridges.len();
                        bridges.push(BridgeGeometry { left, right, top });
                        PreparedPlacement::Bridge { geometry_index }
                    }
                    "o11" => {
                        let form = optional_number(raw, "F", 0.0)?;
                        if form < 0.0 || form.fract() != 0.0 {
                            return Err(invalid("pad variant must be a nonnegative integer"));
                        }
                        if form > 3.0 {
                            return Err(Error::Unsupported {
                                requirements: vec!["pad variant F exceeds 3".into()],
                            });
                        }
                        position.y = position
                            .y
                            .checked_add(16 * SCALE)
                            .ok_or_else(|| invalid("pad position overflow"))?;
                        PreparedPlacement::Pad {
                            large: variant % 2 != 0,
                            single_use: variant >= 2,
                        }
                    }
                    _ => PreparedPlacement::None,
                };
                let layer = match code.as_str() {
                    // decor.gd prepare_options (also run by decor_platform.gd and lamp.gd).
                    _ if crate::decor::is_decor(&code)
                        || crate::platform::CODES.contains(&code.as_str())
                        || ["d25", "d26"].contains(&code.as_str()) =>
                    {
                        crate::decor::layer_for(&code)
                    }
                    _ if code.starts_with('e') => 8,
                    _ => 7,
                };
                placements.push(Placement {
                    id: id.clone(),
                    code,
                    position,
                    variant,
                    mirror,
                    rotation,
                    layer,
                    properties: {
                        let mut list = properties(raw);
                        if legacy_switch {
                            list.retain(|(k, _)| k != "E1");
                        }
                        list
                    },
                    prepared,
                });
            }
            let mut layers = Vec::new();
            for source_layer in ["layer2", "layer1", "layer3"] {
                let Some(raw) = source.get(source_layer) else {
                    continue;
                };
                for (tilemap, grid) in object(raw, source_layer)? {
                    let fact = facts.get(tilemap).ok_or_else(|| Error::Unsupported {
                        requirements: vec![format!("tilemap {tilemap}")],
                    })?;
                    let fact = object(fact, "tile facts")?;
                    let tile_size = fact
                        .get("tile_size")
                        .and_then(Value::as_array)
                        .filter(|v| v.len() == 2)
                        .ok_or_else(|| invalid("tile size"))?;
                    let size = number(&tile_size[0], "tile width")?;
                    if size != number(&tile_size[1], "tile height")?
                        || !(1.0..=4096.0).contains(&size)
                        || size.fract() != 0.0
                    {
                        return Err(invalid("unsupported tile shape/size"));
                    }
                    let grid = text(Some(grid), "tilemap string")?;
                    let (grid_width, grid_height, cells) =
                        decode_tilemap(grid, MAX_LEVEL_CELLS - total_cells)?;
                    total_cells += cells.len();
                    let solid = fact
                        .get("solid_family")
                        .and_then(Value::as_bool)
                        .ok_or_else(|| invalid("solid_family"))?;
                    let water = fact
                        .get("water_family")
                        .and_then(Value::as_bool)
                        .ok_or_else(|| invalid("water_family"))?;
                    let hazard = if source_layer == "layer3" {
                        TerrainHazard::None
                    } else {
                        match tilemap.as_str() {
                            "lava" | "lava_1" | "lava_2" | "lava_3" | "lava_4" => {
                                TerrainHazard::Lava
                            }
                            "ySSpikes" => TerrainHazard::Spikes,
                            _ => TerrainHazard::None,
                        }
                    };
                    let mut contact = Vec::new();
                    if solid || water || hazard != TerrainHazard::None {
                        let unique: BTreeSet<_> =
                            cells.iter().copied().filter(|cell| *cell != -1).collect();
                        for cell in unique {
                            contact.push(TileCollision {
                                cell,
                                polygon: tile_polygon(cell, size as i64, fact)?,
                            });
                        }
                    }
                    // CollisionTable.read supplies diagnostic slots when private art
                    // instances are absent. An explicit instance overrides those slots.
                    let fact_order = facts
                        .keys()
                        .position(|key| key == tilemap)
                        .ok_or_else(|| invalid("tilemap order"))?;
                    let mut slot = DrawSlot {
                        layer_index: if source_layer == "layer2" { 0 } else { 1 },
                        z_order: fact_order as i64,
                    };
                    if let Some(instances) = fact.get("instances").and_then(Value::as_array) {
                        for instance in instances {
                            let instance = object(instance, "tile instance")?;
                            let layer = text(instance.get("layer"), "instance.layer")?;
                            if source_layer == "layer1" && layer.ends_with("L1")
                                || source_layer == "layer2" && layer.ends_with("L2")
                            {
                                slot = DrawSlot {
                                    layer_index: number_required(instance, "layer_index")? as i64,
                                    z_order: number_required(instance, "z_order")? as i64,
                                };
                            }
                        }
                    }
                    if source_layer == "layer3" {
                        slot = DrawSlot {
                            layer_index: 16,
                            z_order: 0,
                        };
                    }
                    layers.push(TileLayer {
                        source_layer: source_layer.into(),
                        tilemap: tilemap.clone(),
                        tile_size_pixels: size as i64,
                        draw_slot: slot,
                        solid: solid && source_layer != "layer3",
                        water: water && source_layer != "layer3",
                        hazard,
                        collision_index: contact
                            .iter()
                            .enumerate()
                            .map(|(i, c)| (c.cell, i))
                            .collect(),
                        collision: contact,
                        width: grid_width,
                        height: grid_height,
                        cells,
                    });
                }
            }
            layers.sort_by_key(|layer| (layer.draw_slot.layer_index, layer.draw_slot.z_order));
            let backgrounds = ["bg1", "bg2", "bg3"]
                .map(|key| source.get(key).map(stringify_scalar).unwrap_or_default());
            let background_color = rgb(source
                .get("bgcolor")
                .and_then(Value::as_str)
                .unwrap_or("132,222,255"));
            let darkness_percent = source
                .get("darkness")
                .map(loose_number)
                .unwrap_or(0.0)
                .clamp(0.0, 100.0) as i64;
            let tint = source
                .get("tint")
                .map(stringify_scalar)
                .unwrap_or_else(|| "0_255,255,255".into());
            let cave_shimmer = source.get("caveShimmer").map(loose_number).unwrap_or(0.0) == 1.0;
            // world.gd dice_colours: the per-group tint of o33/o34 (map_effects.gd).
            let dice_colours = dice_colours(source.get("diceBlockColours"));
            maps.push(Map {
                name: name.clone(),
                width_pixels: width as i64,
                height_pixels: height as i64,
                backgrounds,
                background_color,
                darkness_percent,
                tint,
                cave_shimmer,
                dice_colours,
                source_properties: properties(source),
                collision_grid: crate::collision_grid::Grid::build(&layers),
                layers,
                placements,
                bridges,
            });
        }
        Ok(Self {
            identity: hash(code.as_bytes()),
            maps,
            initial_map,
            spawn,
            spawn_facing,
            player_palette,
            flowers_target: optional_number(level, "flowers", 0.0)?.max(0.0) as i64,
            redcoins_target: optional_number(level, "redcoins", 0.0)?.max(0.0) as i64,
        })
    }
}

pub fn decode_tilemap(json: &str, remaining: usize) -> Result<(usize, usize, Vec<i32>), Error> {
    let value: Value =
        serde_json::from_str(json).map_err(|e| invalid(&format!("tilemap JSON: {e}")))?;
    let grid = object(&value, "tilemap")?;
    if grid.get("c2tilemap").and_then(Value::as_bool) != Some(true) || grid.contains_key("cells") {
        return Err(invalid("tilemap marker/reserved cells"));
    }
    let width = positive(grid.get("width"), "tilemap.width")?;
    let height = positive(grid.get("height"), "tilemap.height")?;
    let count = width
        .checked_mul(height)
        .filter(|count| *count <= MAX_CELLS.min(remaining))
        .ok_or_else(|| invalid("tilemap cell limit"))?;
    let data = text(grid.get("data"), "tilemap.data")?;
    let mut cells = Vec::with_capacity(count);
    for token in data.split(',') {
        let (repeat, tile) = if let Some((r, t)) = token.split_once('x') {
            if r.starts_with('0') || !r.bytes().all(|b| b.is_ascii_digit()) {
                return Err(invalid("tile repeat grammar"));
            }
            let repeat = r
                .parse::<usize>()
                .map_err(|_| invalid("tile repeat overflow"))?;
            (repeat, t)
        } else {
            (1, token)
        };
        if repeat > count - cells.len() {
            return Err(invalid("tile run exceeds count"));
        }
        let flag_at = tile.find(['h', 'v', 'd']).unwrap_or(tile.len());
        let digits = &tile[..flag_at];
        let flags = &tile[flag_at..];
        if digits != "-1" && (digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit())) {
            return Err(invalid("tile id grammar"));
        }
        let id = digits
            .parse::<i64>()
            .map_err(|_| invalid("tile id overflow"))?;
        if id < -1 || id > MASK as i64 || id == -1 && !flags.is_empty() {
            return Err(invalid("tile id/flags"));
        }
        let mut bits = 0u32;
        for flag in flags.bytes() {
            let bit = match flag {
                b'h' => H,
                b'v' => V,
                b'd' => D,
                _ => return Err(invalid("tile flag grammar")),
            };
            if bits & bit != 0 {
                return Err(invalid("duplicate tile flag"));
            }
            bits |= bit;
        }
        let cell = if id == -1 {
            -1
        } else {
            (id as u32 | bits) as i32
        };
        cells.resize(cells.len() + repeat, cell);
    }
    if cells.len() != count {
        return Err(invalid("tile run short count"));
    }
    Ok((width, height, cells))
}
fn tile_polygon(
    cell: i32,
    size: i64,
    fact: &JsonObject<String, Value>,
) -> Result<Vec<Position>, Error> {
    let id = cell as u32 & MASK;
    let disabled = fact
        .get("collision_disabled")
        .and_then(Value::as_array)
        .ok_or_else(|| invalid("collision_disabled"))?;
    if disabled.iter().any(|n| n.as_f64() == Some(id as f64)) {
        return Ok(Vec::new());
    }
    let default = serde_json::json!([0, 0, 1, 0, 1, 1, 0, 1]);
    let polygon = fact
        .get("collision_polygons")
        .and_then(Value::as_object)
        .and_then(|p| p.get(&id.to_string()))
        .unwrap_or(&default);
    let polygon = polygon
        .as_array()
        .filter(|p| p.len() % 2 == 0)
        .ok_or_else(|| invalid("tile polygon"))?;
    let mut points = Vec::new();
    for pair in polygon.as_chunks::<2>().0.iter() {
        let mut x = round_integer(number(&pair[0], "polygon x")? * (size * SCALE) as f64)?;
        let mut y = round_integer(number(&pair[1], "polygon y")? * (size * SCALE) as f64)?;
        if cell as u32 & D != 0 {
            std::mem::swap(&mut x, &mut y);
        }
        if cell as u32 & H != 0 {
            x = size * SCALE - x;
        }
        if cell as u32 & V != 0 {
            y = size * SCALE - y;
        }
        points.push(Position { x, y });
    }
    Ok(points)
}
impl TileLayer {
    pub(crate) fn contact(&self, cell: i32) -> Option<&TileCollision> {
        if cell == -1 {
            return None;
        }
        self.collision_index.get(&cell).map(|i| &self.collision[*i])
    }
    pub fn overlaps_box(&self, bounds: [i64; 4]) -> bool {
        let [left, top, right, bottom] = bounds;
        let size = self.tile_size_pixels * SCALE;
        let x0 = floor_div(left.wrapping_sub(1), size).unwrap_or(0).max(0);
        let y0 = floor_div(top.wrapping_sub(1), size).unwrap_or(0).max(0);
        let x1 = floor_div(right, size)
            .unwrap_or(-1)
            .min(self.width as i64 - 1);
        let y1 = floor_div(bottom, size)
            .unwrap_or(-1)
            .min(self.height as i64 - 1);
        for row in y0..=y1 {
            for col in x0..=x1 {
                let cell = self.cells[row as usize * self.width + col as usize];
                if let Some(contact) = self.contact(cell) {
                    if polygon::overlaps_box(
                        &contact.polygon,
                        [
                            left - col * size,
                            top - row * size,
                            right - col * size,
                            bottom - row * size,
                        ],
                    ) {
                        return true;
                    }
                }
            }
        }
        false
    }
}
impl Map {
    pub fn terrain_overlaps(&self, bounds: [i64; 4]) -> bool {
        self.collision_grid
            .overlaps(self, bounds, crate::collision_grid::SOLID)
    }
    pub(crate) fn water_overlaps(&self, bounds: [i64; 4]) -> bool {
        self.collision_grid
            .overlaps(self, bounds, crate::collision_grid::WATER)
    }
    pub fn collision_grid_metrics(&self) -> (usize, usize, usize) {
        self.collision_grid.metrics()
    }
    /// world.gd lava_overlaps: the lava tilemaps only (spikes hurt the player, not bodies).
    pub(crate) fn lava_overlaps(&self, b: [i64; 4]) -> bool {
        self.collision_grid
            .overlaps(self, b, crate::collision_grid::LAVA)
    }
    pub(crate) fn hazard_overlaps(&self, b: [i64; 4]) -> bool {
        self.collision_grid.overlaps(
            self,
            b,
            crate::collision_grid::LAVA | crate::collision_grid::SPIKES,
        )
    }
    pub(crate) fn water_at(&self, x: i64, y: i64) -> bool {
        self.water_overlaps([x, y, x, y])
    }
    pub fn border_overlaps(&self, [left, top, right, bottom]: [i64; 4]) -> bool {
        top < self.height_pixels * SCALE
            && bottom > -480 * SCALE
            && (left < 0 && right > -32 * SCALE
                || right > self.width_pixels * SCALE && left < (self.width_pixels + 32) * SCALE)
    }
}
/// registry.gd source_ids (Godot 1e51f18): native Object.entries lists canonical uint32
/// index keys first, in numeric order, then every other key in source order.
fn source_ids(objects: &JsonObject<String, Value>) -> Vec<(&String, &Value)> {
    let index = |key: &str| -> Option<u64> {
        let canonical = !key.is_empty()
            && key.len() <= 10
            && key.bytes().all(|b| b.is_ascii_digit())
            && (key == "0" || !key.starts_with('0'));
        canonical
            .then(|| key.parse::<u64>().ok())
            .flatten()
            .filter(|v| *v < 4_294_967_295)
    };
    let mut indexed: Vec<(u64, (&String, &Value))> = Vec::new();
    let mut others = Vec::new();
    for entry in objects {
        match index(entry.0) {
            Some(value) => indexed.push((value, entry)),
            None => others.push(entry),
        }
    }
    indexed.sort_by_key(|(value, _)| *value);
    indexed
        .into_iter()
        .map(|(_, entry)| entry)
        .chain(others)
        .collect()
}
fn object<'a>(value: &'a Value, label: &str) -> Result<&'a JsonObject<String, Value>, Error> {
    value
        .as_object()
        .ok_or_else(|| invalid(&format!("{label} must be an object")))
}
fn text<'a>(value: Option<&'a Value>, label: &str) -> Result<&'a str, Error> {
    value
        .and_then(Value::as_str)
        .ok_or_else(|| invalid(&format!("{label} must be a string")))
}
fn number(value: &Value, label: &str) -> Result<f64, Error> {
    value
        .as_f64()
        .filter(|n| n.is_finite())
        .ok_or_else(|| invalid(&format!("{label} must be finite")))
}
fn number_required(object: &JsonObject<String, Value>, key: &str) -> Result<f64, Error> {
    number(object.get(key).ok_or_else(|| invalid(key))?, key)
}
fn numeric_option(value: Option<&Value>, label: &str) -> Result<f64, Error> {
    let value = value.ok_or_else(|| invalid(label))?;
    let n = if let Some(text) = value.as_str() {
        text.trim().parse::<f64>().map_err(|_| invalid(label))?
    } else {
        number(value, label)?
    };
    if !n.is_finite() || n.abs() > (i64::MAX / SCALE - 1) as f64 {
        return Err(invalid(label));
    }
    Ok(n)
}
fn optional_number(
    object: &JsonObject<String, Value>,
    key: &str,
    default: f64,
) -> Result<f64, Error> {
    object
        .get(key)
        .map(|v| number(v, key))
        .unwrap_or(Ok(default))
}
fn positive(value: Option<&Value>, label: &str) -> Result<usize, Error> {
    let n = number(value.ok_or_else(|| invalid(label))?, label)?;
    if n >= 1.0 && n <= i32::MAX as f64 && n.fract() == 0.0 {
        Ok(n as usize)
    } else {
        Err(invalid(label))
    }
}
fn loose_number(v: &Value) -> f64 {
    let n = v
        .as_f64()
        .or_else(|| v.as_str().and_then(|s| s.trim().parse::<f64>().ok()))
        .unwrap_or(0.0);
    if n.is_finite() {
        n
    } else {
        0.0
    }
}
fn rgb(s: &str) -> [u8; 3] {
    let mut result = [0; 3];
    for (i, s) in s.split(',').take(3).enumerate() {
        result[i] = s.trim().parse::<f64>().unwrap_or(0.0).clamp(0.0, 255.0) as u8;
    }
    result
}
/// world.gd dice_colours: a c2array JSON string whose rows each start with "r,g,b".
fn dice_colours(value: Option<&Value>) -> Vec<[u8; 3]> {
    let Some(Value::String(text)) = value else {
        return Vec::new();
    };
    let Ok(decoded) = serde_json::from_str::<Value>(text) else {
        return Vec::new();
    };
    if decoded.get("c2array") != Some(&Value::Bool(true)) {
        return Vec::new();
    }
    let Some(Value::Array(rows)) = decoded.get("data") else {
        return Vec::new();
    };
    rows.iter()
        .map(|item| match item.get(0).and_then(|first| first.get(0)) {
            Some(Value::String(s)) => rgb(s),
            // str() of a number is a single channel; any other value reads as 0.
            Some(Value::Number(n)) => [n.as_f64().unwrap_or(0.0).clamp(0.0, 255.0) as u8, 0, 0],
            Some(_) => [0, 0, 0],
            None => [0, 0, 0],
        })
        .collect()
}
fn stringify_scalar(v: &Value) -> String {
    v.as_str()
        .map(str::to_string)
        .unwrap_or_else(|| v.to_string())
}
fn properties(o: &JsonObject<String, Value>) -> Vec<(String, PropertyValue)> {
    o.iter().map(|(k, v)| (k.clone(), property(v))).collect()
}
#[cfg(test)]
pub(crate) fn property_for_tests(v: &Value) -> PropertyValue {
    property(v)
}
fn property(v: &Value) -> PropertyValue {
    match v {
        Value::Null => PropertyValue::Null,
        Value::Bool(v) => PropertyValue::Bool(*v),
        Value::Number(v) => PropertyValue::Number(v.as_f64().unwrap_or(0.0)),
        Value::String(v) => PropertyValue::String(v.clone()),
        Value::Array(v) => PropertyValue::Array(v.iter().map(property).collect()),
        Value::Object(v) => PropertyValue::Object(properties(v)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[allow(clippy::collapsible_if)]
    fn old_overlaps_box(layer: &TileLayer, bounds: [i64; 4]) -> bool {
        let [left, top, right, bottom] = bounds;
        let size = layer.tile_size_pixels * SCALE;
        let x0 = floor_div(left.wrapping_sub(1), size).unwrap_or(0).max(0);
        let y0 = floor_div(top.wrapping_sub(1), size).unwrap_or(0).max(0);
        let x1 = floor_div(right, size)
            .unwrap_or(-1)
            .min(layer.width as i64 - 1);
        let y1 = floor_div(bottom, size)
            .unwrap_or(-1)
            .min(layer.height as i64 - 1);
        for row in y0..=y1 {
            for col in x0..=x1 {
                let cell = layer.cells[row as usize * layer.width + col as usize];
                if let Some(contact) = layer.collision.iter().find(|p| p.cell == cell) {
                    if polygon::overlaps_box(
                        &contact.polygon,
                        [
                            left - col * size,
                            top - row * size,
                            right - col * size,
                            bottom - row * size,
                        ],
                    ) {
                        return true;
                    }
                }
            }
        }
        false
    }
    fn check_indexed_level(path: &std::path::Path, boxes: usize) -> usize {
        let collision = include_str!("../../../../data/collision_table.json");
        let raw = std::fs::read_to_string(path).unwrap();
        let world = World::compile_benchmark_real_screen(&raw, collision).unwrap();
        let mut checks = 0;
        let mut seed = 0x6a09e667f3bcc909_u64;
        let mut random = || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        for map in &world.maps {
            for layer in &map.layers {
                assert_eq!(layer.collision_index.len(), layer.collision.len());
                for cell in layer.cells.iter().copied().collect::<BTreeSet<_>>() {
                    assert_eq!(
                        layer.contact(cell),
                        layer.collision.iter().find(|p| p.cell == cell)
                    );
                }
            }
            for index in 0..boxes {
                let x = (random() % ((map.width_pixels + 128) * SCALE) as u64) as i64 - 64 * SCALE;
                let y = (random() % ((map.height_pixels + 128) * SCALE) as u64) as i64 - 64 * SCALE;
                let dx = (random() % (128 * SCALE) as u64) as i64;
                let dy = (random() % (128 * SCALE) as u64) as i64;
                let bounds = match index % 16 {
                    0 => [x, y, x, y],
                    1 => [x, y, x - dx, y - dy],
                    2 => [-SCALE, -SCALE, 0, 0],
                    3 => [0, 0, 32 * SCALE, 32 * SCALE],
                    _ => [x, y, x + dx, y + dy],
                };
                for class in [1_u8, 2, 4, 8, 12] {
                    let old = map.layers.iter().any(|l| {
                        crate::collision_grid::classes(l) & class != 0
                            && old_overlaps_box(l, bounds)
                    });
                    assert_eq!(
                        old,
                        map.collision_grid.overlaps(map, bounds, class),
                        "combined class={class} {} {bounds:?}",
                        path.display()
                    );
                }
                if bounds[0] <= bounds[2] && bounds[1] <= bounds[3] {
                    let points = [
                        Position {
                            x: bounds[0],
                            y: bounds[1],
                        },
                        Position {
                            x: bounds[2],
                            y: bounds[1],
                        },
                        Position {
                            x: bounds[0] + (bounds[2] - bounds[0]) / 2,
                            y: bounds[3],
                        },
                    ];
                    assert_eq!(
                        map.legacy_terrain_polygon_overlaps(&points, bounds),
                        map.terrain_polygon_overlaps(&points, bounds),
                        "combined polygon {} {bounds:?}",
                        path.display()
                    );
                }
                for layer in &map.layers {
                    assert_eq!(
                        old_overlaps_box(layer, bounds),
                        layer.overlaps_box(bounds),
                        "{} {} {:?}",
                        path.display(),
                        layer.tilemap,
                        bounds
                    );
                    checks += 1;
                }
            }
        }
        println!(
            "TERRAIN_INDEX_EQUAL path={} random_boxes_per_map={boxes} layer_queries={checks}",
            path.display()
        );
        checks
    }
    #[test]
    fn indexed_collision_matches_linear_on_all_public_level_fixtures() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
        let mut paths = std::fs::read_dir(root)
            .unwrap()
            .map(|p| p.unwrap().path())
            .filter(|p| p.to_string_lossy().ends_with(".level.json"))
            .collect::<Vec<_>>();
        paths.sort();
        assert!(!paths.is_empty());
        for path in paths {
            check_indexed_level(&path, 2000);
        }
    }
    #[test]
    #[ignore = "requires private AKA real-screen inputs; set TERRAIN_EQ_LEVELS"]
    fn indexed_collision_matches_linear_on_private_real_maps() {
        let paths = std::env::var_os("TERRAIN_EQ_LEVELS").expect("TERRAIN_EQ_LEVELS required");
        let paths = std::env::split_paths(&paths).collect::<Vec<_>>();
        assert!(!paths.is_empty());
        for path in paths {
            check_indexed_level(&path, 20000);
        }
    }
    #[test]
    fn dice_colours_read_the_first_cell_of_each_row() {
        let table = r#"{"c2array":true,"size":[3,1,1],"data":[[["10,20,30"]],[[]],[[7]]]}"#;
        assert_eq!(
            dice_colours(Some(&Value::String(table.into()))),
            vec![[10, 20, 30], [0, 0, 0], [7, 0, 0]]
        );
        assert!(dice_colours(Some(&Value::String("retained-source".into()))).is_empty());
        assert!(dice_colours(None).is_empty());
    }
    #[test]
    fn registry_source_ids_list_canonical_indices_first_in_numeric_order() {
        let objects: Value = serde_json::from_str(
            r#"{"b":0,"10":0,"+3":0,"2":0,"07":0,"4294967295":0,"a":0,"4294967294":0,"0":0}"#,
        )
        .unwrap();
        let order: Vec<&str> = source_ids(objects.as_object().unwrap())
            .into_iter()
            .map(|(key, _)| key.as_str())
            .collect();
        assert_eq!(
            order,
            [
                "0",
                "2",
                "10",
                "4294967294",
                "b",
                "+3",
                "07",
                "4294967295",
                "a"
            ]
        );
    }
    #[test]
    fn dice_colours_keep_source_and_do_not_block_levels_without_dice() {
        let level = r#"{"version":"1","name":"test","desc":"","author":"test","startpoint":{"map":1,"X":32,"Y":32},"maps":{"map1":{"width":640,"height":480,"objects":{},"diceBlockColours":"retained-source"}}}"#;
        let collision = r#"{"version":2,"tilemaps":{}}"#;
        assert!(World::compile(level, collision).is_ok());
        let world = World::compile_benchmark_real_screen(level, collision).unwrap();
        assert!(world.maps[0]
            .source_properties
            .iter()
            .any(|(k, v)| k == "diceBlockColours"
                && matches!(v,PropertyValue::String(s) if s=="retained-source")));
    }
    #[test]
    fn tile_runs_preserve_transforms_and_refuse_malformed_expansion() {
        let (_, _, cells) = decode_tilemap(
            r#"{"c2tilemap":true,"width":3,"height":1,"data":"1hv,2x-1"}"#,
            3,
        )
        .unwrap();
        assert_eq!(cells, vec![(H | V | 1) as i32, -1, -1]);
        for data in [
            "4x1",
            "01x1",
            "0x1",
            "1hh",
            "-1h",
            "536870912",
            "1x1",
            "1,1",
        ] {
            let json = format!(r#"{{"c2tilemap":true,"width":3,"height":1,"data":"{data}"}}"#);
            assert!(decode_tilemap(&json, 3).is_err(), "{data}");
        }
    }
}
