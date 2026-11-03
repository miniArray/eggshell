//! Drawing-only parts of placed objects, from span_dressing.gd and pack_dressing.gd:
//! - span parts: the `<code>_stem` stalk under p6..p8 (E2 = its height) and the
//!   `<code>_spikes` strip on the turning p11/p12 (E2 = strip 0 or 1);
//! - extendable scenery (decor.gd resized codes): pack_dressing.gd decoration_plan, a
//!   body grown to the E1 height plus stems, lanterns, caps and pillars.
//!
//! Parts have no collision and change no state.
use crate::{
    binding::{Fill, Slices, Visual},
    geometry::{Transform, rect_quad, slices, sprite_quad},
    gles::Quad,
    screen::Plan,
};
use eggshell_spike_core::{PaletteSwap, PropertyValue};
use serde_json::Value;

/// span_dressing.gd constants.
const STEM_WIDTH: f64 = 32.0;
const STEM_TOP: f64 = 16.0;
const MAX_STEM: i64 = 100_000;
const SPIKE_HEIGHT: f64 = 10.0;
const SPIKE_BOTTOM: f64 = -8.0;
const SPIKE_MARGIN: f64 = 36.0;

/// decor.gd resized: extendable scenery with an E1 height, drawn by `decoration_plan`.
/// d22 (snow tree) and d23 (mountain ledge) are solids of other kinds; scene.rs draws
/// them with their own paths.
pub fn resized_decor(code: &str) -> bool {
    resized_code(code) && code != "d22" && code != "d23"
}
fn resized_code(code: &str) -> bool {
    let Some(i) = code.strip_prefix('d').and_then(|n| n.parse::<i64>().ok()) else {
        return false;
    };
    (14..=23).contains(&i)
        || [27, 28, 75].contains(&i)
        || (31..=54).contains(&i)
        || (56..=67).contains(&i)
}

/// span_dressing.gd leading_integer: the whole-number prefix of a text or number option;
/// -1 when there is none or it is negative.
pub fn leading_integer(value: Option<&PropertyValue>) -> i64 {
    match value {
        Some(PropertyValue::Number(v)) => {
            if v.is_finite() && *v >= 0.0 {
                *v as i64
            } else {
                -1
            }
        }
        Some(PropertyValue::String(s)) => {
            let digits: String = s.trim().chars().take_while(char::is_ascii_digit).collect();
            if digits.is_empty() || digits.len() > 12 {
                -1
            } else {
                digits.parse().unwrap_or(-1)
            }
        }
        _ => -1,
    }
}

/// decor.gd size_option, as kept: `float(int(value))`; 0 when absent or unusable (the
/// core refuses an unusable height before drawing).
pub fn decor_height(value: Option<&PropertyValue>) -> f64 {
    let v = match value {
        Some(PropertyValue::Number(v)) => *v,
        Some(PropertyValue::String(s)) => s.trim().parse::<f64>().unwrap_or(0.0),
        _ => 0.0,
    };
    if v.is_finite() && v >= 0.0 {
        v.trunc()
    } else {
        0.0
    }
}

/// Where a part's art comes from.
#[derive(Clone, Debug, PartialEq)]
pub enum Art {
    /// The placement's own object entry (its variant chooses the frame).
    Body,
    /// pack_dressing.gd _part_entry: `parts[source_types[index]]` of the object entry.
    Part(usize),
    /// pack_dressing.gd _visual_animation: the first `visuals` entry with this animation.
    Animation(String),
    /// Another object entry (the d29 lantern).
    Object(&'static str),
}
/// pack_dressing.gd _part.
#[derive(Clone, Debug, PartialEq)]
pub struct Part {
    pub art: Art,
    pub animation: Option<&'static str>,
    pub position: [f64; 2],
    pub resize: bool,
    pub height: f64,
    pub bottom: bool,
    /// left, right, top, bottom, in world pixels.
    pub margins: [f64; 4],
    pub tile: bool,
    pub variant: i64,
}
fn part(art: Art) -> Part {
    Part {
        art,
        animation: None,
        position: [0.0; 2],
        resize: false,
        height: 0.0,
        bottom: false,
        margins: [0.0; 4],
        tile: false,
        variant: 0,
    }
}

/// pack_dressing.gd decoration_plan for a resized code. `cap` is the object entry's
/// `source_type` (the d28 cap animation). Parts are in drawing order.
pub fn decoration_plan(code: &str, variant: i64, height: f64, cap: Option<&str>) -> Vec<Part> {
    let index: i64 = code[1..].parse().unwrap_or(0);
    // decor_entry: d22 draws its other trunk part as the body.
    let mut body = part(if index == 22 {
        Art::Part(if variant == 0 { 1 } else { 0 })
    } else {
        Art::Body
    });
    body.variant = variant;
    body.height = height;
    body.resize = true;
    body.bottom = true;
    let mut result = Vec::new();
    let mut after = Vec::new();
    if (14..=21).contains(&index) {
        body.margins = [16.0, 16.0, 64.0, 0.0];
        after.push(part(Art::Animation(format!("Stem{}", index - 13))));
    } else if (31..=54).contains(&index) {
        let top = if (39..=46).contains(&index) {
            32.0
        } else {
            64.0
        };
        body.margins = [0.0, 0.0, top, 0.0];
        after.push(part(Art::Animation(format!(
            "CurlyStem{}",
            (index - 30) % 8
        ))));
    } else if index == 22 {
        if variant == 0 {
            body.margins = [0.0, 96.0, 160.0, 0.0];
            body.height = height.max(160.0);
            body.position[1] = if height < 160.0 { 16.0 } else { 0.0 };
        } else {
            body.margins = [0.0, 160.0, 256.0, 32.0];
            body.height = height.max(290.0);
            body.position[1] = 1264.0 / 71.0;
        }
    } else if index == 23 {
        body.resize = false;
        let mut pillar = part(Art::Part(1));
        pillar.resize = true;
        pillar.height = height;
        pillar.bottom = false;
        pillar.position[1] = if variant == 0 { 32.0 } else { 64.0 };
        pillar.tile = true;
        result.push(pillar);
    } else if index == 27 || index == 28 {
        let hanging = index == 27;
        body.margins = if hanging {
            [16.0, 16.0, 0.0, 32.0]
        } else {
            [16.0, 16.0, 32.0, 0.0]
        };
        body.bottom = !hanging;
        body.position[1] = if hanging { -16.0 } else { 16.0 };
        let mut lantern = part(Art::Object("d29"));
        lantern.animation = Some(if hanging { "Hanging" } else { "Standing" });
        lantern.position[1] = body.position[1] + height * if hanging { 1.0 } else { -1.0 };
        after.push(lantern);
        if !hanging && let Some(cap) = cap.filter(|c| !c.is_empty()) {
            let mut cap = part(Art::Animation(cap.to_owned()));
            cap.position = [0.0, 16.0];
            after.push(cap);
        }
    } else if (56..=67).contains(&index) {
        body.position[1] = 16.0;
        body.margins = if index <= 60 {
            [0.0, 112.0, 66.0, 30.0]
        } else {
            [0.0, 80.0, 64.0, 0.0]
        };
    } else if index == 75 {
        body.margins = [0.0, 0.0, 16.0, 16.0];
    }
    result.push(body);
    result.extend(after);
    result
}

/// The pack entry a part's art binds to, with its default animation set as the source
/// sets it. None when the pack lacks it.
pub fn part_entry(manifest: &Value, code: &str, art: &Art) -> Option<Value> {
    let objects = manifest.get("objects")?;
    match art {
        Art::Body => objects.get(code).cloned(),
        Art::Part(index) => {
            let entry = objects.get(code)?;
            let id = entry
                .get("source_types")?
                .as_array()?
                .get(*index)?
                .as_f64()?;
            entry
                .get("parts")?
                .get((id as i64).to_string())
                .filter(|v| v.is_object())
                .cloned()
        }
        Art::Animation(name) => {
            let found = manifest
                .get("visuals")?
                .as_object()?
                .values()
                .find(|v| v.get("animations").and_then(|a| a.get(name)).is_some())?;
            let mut entry = found.clone();
            entry["default_animation"] = Value::String(name.clone());
            Some(entry)
        }
        Art::Object(name) => objects.get(*name).cloned(),
    }
}
/// A stable key for a part's bound visual in the scene's object table.
pub fn part_key(code: &str, art: &Art) -> String {
    match art {
        Art::Body => code.to_owned(),
        Art::Part(index) => format!("{code}#part{index}"),
        Art::Animation(name) => format!("#visual:{name}"),
        Art::Object(name) => (*name).to_owned(),
    }
}

/// What drawing needs: one placement's world position, the scale unit and the plan.
pub struct Draw<'a> {
    pub at: [f64; 2],
    pub rotation: f64,
    pub density: f64,
    pub plan: &'a Plan,
    pub color: [f32; 4],
    pub palette: &'a [PaletteSwap],
}
impl Draw<'_> {
    fn unit(&self) -> f64 {
        1.0 / self.density
    }
    fn transform(&self, offset: [f64; 2]) -> Transform {
        let unit = self.unit();
        let (s, c) = self.rotation.to_radians().sin_cos();
        Transform {
            position: [
                self.at[0] + c * offset[0] - s * offset[1],
                self.at[1] + s * offset[0] + c * offset[1],
            ],
            scale: [unit, unit],
            rotation: self.rotation,
            ..Transform::default()
        }
    }
    /// Image `image` (pixel `size`) in slices over the world rectangle `rect`.
    fn sliced(
        &self,
        image: usize,
        size: [f64; 2],
        rect: [f64; 4],
        cuts: Slices,
        out: &mut Vec<Quad>,
    ) -> Result<(), String> {
        if rect[2] <= 0.0 || rect[3] <= 0.0 {
            return Ok(());
        }
        let d = self.density;
        let t = self.transform([rect[0], rect[1]]);
        for p in slices(size, [rect[2] * d, rect[3] * d], cuts)? {
            out.push(rect_quad(
                image,
                p.source,
                size,
                p.destination,
                t,
                self.plan,
                self.color,
                self.palette,
            ));
        }
        Ok(())
    }
    /// pack_dressing.gd _draw_part for every part of a decoration plan.
    pub fn decoration(
        &self,
        parts: &[(Part, &Visual)],
        tick: i64,
        sizes: &[[f64; 2]],
        out: &mut Vec<Quad>,
    ) -> Result<(), String> {
        let d = self.density;
        for (part, visual) in parts {
            let animation = part.animation.unwrap_or("");
            // Grown parts keep the first frame (the source removes their frame updates).
            let frame = visual.sample(
                if part.resize { 0 } else { tick },
                animation,
                part.variant,
                None,
            );
            let size = sizes[frame.image];
            let native = [size[0] / d, size[1] / d];
            if !part.resize {
                let mut t = self.transform(part.position);
                t.origin = frame.origin;
                out.push(sprite_quad(
                    frame.image,
                    size,
                    t,
                    self.plan,
                    self.color,
                    self.palette,
                ));
                continue;
            }
            let origin = [native[0] / 2.0, if part.bottom { part.height } else { 0.0 }];
            let rect = [
                part.position[0] - origin[0],
                part.position[1] - origin[1],
                native[0],
                part.height,
            ];
            let m = if part.tile { [0.0; 4] } else { part.margins };
            let cuts = Slices {
                left: m[0] * d,
                right: m[1] * d,
                top: m[2] * d,
                bottom: m[3] * d,
                fill: Fill::Tile,
            };
            self.sliced(frame.image, size, rect, cuts, out)?;
        }
        Ok(())
    }
    /// span_dressing.gd parts: the stalk (p6..p8, tiled from its top-left) and the spike
    /// strip (p11/p12, end caps kept, middle tiled across, stretched to 10 px tall).
    pub fn span_part(
        &self,
        code: &str,
        e2: i64,
        span_width: f64,
        visual: &Visual,
        sizes: &[[f64; 2]],
        out: &mut Vec<Quad>,
    ) -> Result<(), String> {
        let frame = visual.sample(0, "", 0, None);
        let size = sizes[frame.image];
        let d = self.density;
        if ["p6", "p7", "p8"].contains(&code) {
            let height = e2.min(MAX_STEM) as f64;
            let rect = [-STEM_WIDTH / 2.0, STEM_TOP, STEM_WIDTH, height];
            let cuts = Slices {
                left: 0.0,
                right: 0.0,
                top: 0.0,
                bottom: 0.0,
                fill: Fill::Tile,
            };
            return self.sliced(frame.image, size, rect, cuts, out);
        }
        // NinePatchRect: margins min(36 * density, width / 2), horizontal tile, vertical
        // stretch: tile at the image's own height, then scale it to the strip height.
        let margin = (SPIKE_MARGIN * d).min((size[0] / 2.0).floor());
        let cuts = Slices {
            left: margin,
            right: margin,
            top: 0.0,
            bottom: 0.0,
            fill: Fill::Tile,
        };
        let mut t = self.transform([-span_width / 2.0, SPIKE_BOTTOM - SPIKE_HEIGHT]);
        t.scale[1] = SPIKE_HEIGHT / size[1];
        for p in slices(size, [span_width * d, size[1]], cuts)? {
            out.push(rect_quad(
                frame.image,
                p.source,
                size,
                p.destination,
                t,
                self.plan,
                self.color,
                self.palette,
            ));
        }
        Ok(())
    }
}

/// span_dressing.gd parts selection: Some(variant) of the part to draw, or None.
pub fn span_part_variant(code: &str, e2: i64, span_width: f64) -> Option<i64> {
    if ["p6", "p7", "p8"].contains(&code) && e2 > 0 {
        return Some(0);
    }
    if ["p11", "p12"].contains(&code) && (e2 == 0 || e2 == 1) && span_width > 0.0 {
        return Some(e2);
    }
    None
}
pub fn span_part_key(code: &str) -> Option<String> {
    match code {
        "p6" | "p7" | "p8" => Some(format!("{code}_stem")),
        "p11" | "p12" => Some(format!("{code}_spikes")),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn plans_follow_decoration_plan() {
        let p = decoration_plan("d14", 0, 100.0, None);
        assert_eq!(p.len(), 2);
        assert_eq!(p[0].art, Art::Body);
        assert_eq!((p[0].resize, p[0].bottom, p[0].height), (true, true, 100.0));
        assert_eq!(p[0].margins, [16.0, 16.0, 64.0, 0.0]);
        assert_eq!(p[1].art, Art::Animation("Stem1".into()));
        assert_eq!(
            decoration_plan("d38", 0, 0.0, None)[1].art,
            Art::Animation("CurlyStem0".into())
        );
        assert_eq!(decoration_plan("d39", 0, 0.0, None)[0].margins[2], 32.0);
        let p = decoration_plan("d27", 0, 80.0, Some("ChainedLanternBase"));
        assert_eq!(p.len(), 2);
        assert_eq!((p[0].bottom, p[0].position[1]), (false, -16.0));
        assert_eq!((p[1].animation, p[1].position[1]), (Some("Hanging"), 64.0));
        let p = decoration_plan("d28", 0, 80.0, Some("PoleLanternBase"));
        assert_eq!(p.len(), 3);
        assert_eq!(
            (p[1].animation, p[1].position[1]),
            (Some("Standing"), -64.0)
        );
        assert_eq!(p[2].art, Art::Animation("PoleLanternBase".into()));
        assert_eq!(p[2].position, [0.0, 16.0]);
        let p = decoration_plan("d22", 0, 100.0, None);
        assert_eq!(p[0].art, Art::Part(1));
        assert_eq!((p[0].height, p[0].position[1]), (160.0, 16.0));
        let p = decoration_plan("d22", 1, 300.0, None);
        assert_eq!((p[0].art.clone(), p[0].height), (Art::Part(0), 300.0));
        let p = decoration_plan("d23", 1, 50.0, None);
        assert_eq!(p.len(), 2);
        assert_eq!(
            (p[0].art.clone(), p[0].tile, p[0].position[1]),
            (Art::Part(1), true, 64.0)
        );
        assert!(!p[1].resize);
        assert_eq!(
            decoration_plan("d57", 0, 0.0, None)[0].margins,
            [0.0, 112.0, 66.0, 30.0]
        );
        assert_eq!(
            decoration_plan("d61", 0, 0.0, None)[0].margins,
            [0.0, 80.0, 64.0, 0.0]
        );
        assert_eq!(
            decoration_plan("d75", 3, 0.0, None)[0].margins,
            [0.0, 0.0, 16.0, 16.0]
        );
    }
    #[test]
    fn options_parse_like_the_source() {
        let s = |t: &str| PropertyValue::String(t.into());
        assert_eq!(leading_integer(Some(&s(" 12px"))), 12);
        assert_eq!(leading_integer(Some(&s("x"))), -1);
        assert_eq!(leading_integer(Some(&PropertyValue::Number(-2.0))), -1);
        assert_eq!(leading_integer(None), -1);
        assert_eq!(decor_height(Some(&PropertyValue::Number(96.7))), 96.0);
        assert_eq!(decor_height(Some(&s("40"))), 40.0);
        assert_eq!(span_part_variant("p6", 40, 0.0), Some(0));
        assert_eq!(span_part_variant("p6", 0, 0.0), None);
        assert_eq!(span_part_variant("p11", 1, 64.0), Some(1));
        assert_eq!(span_part_variant("p11", 2, 64.0), None);
        assert_eq!(span_part_variant("p11", 0, 0.0), None);
        assert!(resized_decor("d28") && resized_decor("d75") && !resized_decor("d29"));
        assert!(!resized_decor("d23") && resized_code("d23"));
    }
}
