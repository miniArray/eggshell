//! Map gradients, read-only. Two sources, as in the original presentation:
//! - the map `gradient` field (pack_background.gd): named pack strips or encoded
//!   `height,r,g,b` strips, drawn in level space at the background layer;
//! - the map `customGradientGenerator` field (map_effects.gd): generated bands in screen
//!   space just above the clear colour, which then becomes the last band colour.
use crate::{
    geometry::{Transform, rect_quad, visible},
    gles::Quad,
    screen::Plan,
};
use serde_json::Value;

/// map_effects.gd GRADIENT_FOLLOW: the generated bands keep nine tenths of the camera.
const GRADIENT_FOLLOW: f64 = 0.9;
/// map_effects.gd MAX_GRADIENT_LINES.
const MAX_GRADIENT_LINES: f64 = 4096.0;

#[derive(Clone, Debug, PartialEq)]
pub struct Band {
    pub y: f64,
    pub height: f64,
    pub color: [f32; 4],
}

/// pack_background.gd strips of the map `gradient` field.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct StripGradient {
    pub strips: Vec<Band>,
    scroll: [f64; 2],
    reference: [f64; 2],
}

/// map_effects.gd custom_gradient: bands in 448-pixel reference rows, and the fill colour.
#[derive(Clone, Debug, PartialEq)]
pub struct CustomGradient {
    pub bands: Vec<Band>,
    pub fill: [u8; 3],
}

fn rgb_color(rgb: [f64; 3]) -> [f32; 4] {
    [
        (rgb[0].clamp(0.0, 255.0) / 255.0) as f32,
        (rgb[1].clamp(0.0, 255.0) / 255.0) as f32,
        (rgb[2].clamp(0.0, 255.0) / 255.0) as f32,
        1.0,
    ]
}

/// Godot String.is_valid_float: the whole text is one decimal number.
fn valid_float(text: &str) -> Option<f64> {
    let t = text;
    if t.is_empty() || t.contains(char::is_whitespace) {
        return None;
    }
    let body = t.strip_prefix(['+', '-']).unwrap_or(t);
    if body.is_empty() || !body.starts_with(|c: char| c.is_ascii_digit() || c == '.') {
        return None;
    }
    // Rust's parser also accepts "inf"/"nan"; the body check above refuses them.
    t.parse::<f64>().ok()
}

/// Godot String.to_float: the leading decimal number, 0 when there is none.
pub(crate) fn leading_float(text: &str) -> f64 {
    let bytes = text.as_bytes();
    let mut end = 0;
    if end < bytes.len() && (bytes[end] == b'+' || bytes[end] == b'-') {
        end += 1;
    }
    let digits_start = end;
    while end < bytes.len() && bytes[end].is_ascii_digit() {
        end += 1;
    }
    if end < bytes.len() && bytes[end] == b'.' {
        end += 1;
        while end < bytes.len() && bytes[end].is_ascii_digit() {
            end += 1;
        }
    }
    if end == digits_start || &text[digits_start..end] == "." {
        return 0.0;
    }
    let mantissa = end;
    if end < bytes.len() && (bytes[end] == b'e' || bytes[end] == b'E') {
        let mut e = end + 1;
        if e < bytes.len() && (bytes[e] == b'+' || bytes[e] == b'-') {
            e += 1;
        }
        let exponent_digits = e;
        while e < bytes.len() && bytes[e].is_ascii_digit() {
            e += 1;
        }
        if e > exponent_digits {
            end = e;
        }
    }
    text[..end]
        .parse::<f64>()
        .or_else(|_| text[..mantissa].parse::<f64>())
        .unwrap_or(0.0)
}

/// map_effects.gd _number.
fn number(text: &str) -> f64 {
    let v = leading_float(text.trim());
    if v.is_finite() { v } else { 0.0 }
}

/// map_effects.gd _whole: leading integer digits (one leading sign allowed), else 0.
fn whole(text: &str) -> f64 {
    let trimmed = text.trim();
    let mut digits = String::new();
    for (index, c) in trimmed.chars().enumerate() {
        if c.is_ascii_digit() || (index == 0 && (c == '-' || c == '+')) {
            digits.push(c);
        } else {
            break;
        }
    }
    digits.parse::<i64>().map(|v| v as f64).unwrap_or(0.0)
}

/// pack_background.gd decode_strips: `height,r,g,b` groups, all or nothing.
fn decode_strips(value: &str) -> Vec<(f64, [f64; 3])> {
    let tokens: Vec<&str> = value.split(',').collect();
    if !tokens.len().is_multiple_of(4) {
        return Vec::new();
    }
    let mut strips = Vec::new();
    for group in tokens.chunks(4) {
        let mut numbers = [0.0; 4];
        for (slot, token) in numbers.iter_mut().zip(group) {
            match valid_float(token) {
                Some(v) if v.is_finite() => *slot = v,
                _ => return Vec::new(),
            }
        }
        strips.push((numbers[0], [numbers[1], numbers[2], numbers[3]]));
    }
    strips
}

fn point(value: Option<&Value>) -> Option<[f64; 2]> {
    let a = value?.as_array()?;
    if a.len() != 2 {
        return None;
    }
    Some([a[0].as_f64()?, a[1].as_f64()?])
}

impl StripGradient {
    /// pack_background.gd setup, gradient part. `value` is the map `gradient` text:
    /// `NAME_OFFSET_SCALE`, where NAME is a pack gradient or encoded strips.
    pub fn prepare(manifest: &Value, value: &str, density: u32) -> Self {
        let parts: Vec<&str> = value.split('_').collect();
        let pack = manifest
            .get("gradients")
            .and_then(|g| g.get(parts[0]))
            .and_then(Value::as_object)
            .filter(|g| !g.is_empty());
        let d = density as f64;
        let mut gradient = Self::default();
        let mut sources: Vec<(Option<f64>, Option<[f64; 3]>)> = Vec::new();
        if let Some(pack) = pack {
            match pack.get("strips").map(|s| s.as_array()) {
                Some(Some(strips)) => {
                    for strip in strips {
                        let height = strip.get("height").and_then(Value::as_f64);
                        let color = strip
                            .get("color")
                            .and_then(Value::as_array)
                            .filter(|c| c.len() == 3)
                            .and_then(|c| Some([c[0].as_f64()?, c[1].as_f64()?, c[2].as_f64()?]));
                        sources.push((height.filter(|h| h.is_finite()), color));
                    }
                }
                Some(None) => return gradient,
                None => {}
            }
            if let Some(scroll) = point(pack.get("scroll")) {
                gradient.scroll = scroll;
            }
            if let Some(reference) = point(pack.get("reference")) {
                gradient.reference = reference.map(|v| v / d);
            }
        } else {
            sources = decode_strips(parts[0])
                .into_iter()
                .map(|(h, c)| (Some(h), Some(c)))
                .collect();
        }
        let scale = parts.get(2).and_then(|s| valid_float(s)).unwrap_or(1.0);
        let offset = parts.get(1).and_then(|s| valid_float(s)).unwrap_or(0.0);
        if !scale.is_finite() || scale <= 0.0 || !offset.is_finite() {
            return gradient;
        }
        let mut y = 0.0;
        for (index, (height, color)) in sources.into_iter().enumerate() {
            let (Some(height), Some(color)) = (height, color) else {
                continue;
            };
            let strip_height = height / if pack.is_some() { d } else { 1.0 };
            let height = (if index == 0 { offset } else { strip_height }).max(0.0) * scale;
            gradient.strips.push(Band {
                y,
                height,
                color: rgb_color(color),
            });
            y += height;
        }
        gradient
    }
    /// pack_background.gd _draw strips: level-space rectangles across the visible width.
    pub fn emit(&self, plan: &Plan, container: [f64; 2], solid: usize, out: &mut Vec<Quad>) {
        let shift = (plan.center[1] - self.reference[1]) * (1.0 - self.scroll[1]);
        let left = plan.center[0] - plan.visible[0] / 2.0;
        for strip in &self.strips {
            let q = rect_quad(
                solid,
                [0.0, 0.0, 1.0, 1.0],
                [1.0, 1.0],
                [left, strip.y + shift, plan.visible[0], strip.height],
                Transform::default(),
                plan,
                strip.color,
                &[],
            );
            if strip.height > 0.0 && visible(&q, container) {
                out.push(q);
            }
        }
    }
}

impl CustomGradient {
    /// map_effects.gd custom_gradient: `lines|start|end|r,g,b_r,g,b...`. None when unusable.
    pub fn prepare(value: &str) -> Option<Self> {
        let parts: Vec<&str> = value.split('|').collect();
        if parts.len() < 4 {
            return None;
        }
        let lines = number(parts[0]);
        let start = number(parts[1]);
        let end = number(parts[2]);
        let colours: Vec<[f64; 3]> = if parts[3].is_empty() {
            Vec::new()
        } else {
            parts[3]
                .split('_')
                .map(|token| {
                    let channels: Vec<&str> = token.split(',').collect();
                    std::array::from_fn(|i| channels.get(i).map_or(0.0, |c| whole(c)))
                })
                .collect()
        };
        let last = *colours.last()?;
        let mut bands = Vec::new();
        if start > 0.0 {
            bands.push(Band {
                y: 0.0,
                height: start + 1.0,
                color: rgb_color(colours[0]),
            });
        }
        let segments = colours.len() - 1;
        if segments > 0 && lines > 0.0 && lines.is_finite() {
            let step = (end - start) / lines;
            let height = (step + 0.5).floor() + 1.0;
            let per = lines / segments as f64;
            let mut count = 0.0;
            for segment in 0..segments {
                let low = colours[segment];
                let high = colours[segment + 1];
                for line in 0..per.min(MAX_GRADIENT_LINES).ceil() as i64 {
                    let rgb = std::array::from_fn(|c| {
                        let value_at = (high[c] - low[c]) / per * line as f64 + low[c];
                        8.0 * (value_at / 8.0 + 0.5).floor()
                    });
                    bands.push(Band {
                        y: start + step * count,
                        height,
                        color: rgb_color(rgb),
                    });
                    count += 1.0;
                }
            }
        }
        Some(Self {
            bands,
            fill: last.map(|v| v.clamp(0.0, 255.0) as u8),
        })
    }
    /// map_effects.gd _place_gradient: screen-space bands across the container width.
    pub fn emit(&self, plan: &Plan, container: [f64; 2], solid: usize, out: &mut Vec<Quad>) {
        let top = plan.center[1] - 224.0;
        let screen = Plan {
            scale: 1.0,
            offset: [0.0; 2],
            ..*plan
        };
        for band in &self.bands {
            let y = plan.offset[1] + (band.y + GRADIENT_FOLLOW * top) * plan.scale;
            let q = rect_quad(
                solid,
                [0.0, 0.0, 1.0, 1.0],
                [1.0, 1.0],
                [0.0, y, container[0], band.height * plan.scale],
                Transform::default(),
                &screen,
                band.color,
                &[],
            );
            if band.height > 0.0 && visible(&q, container) {
                out.push(q);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn plan(center: [f64; 2], scale: f64) -> Plan {
        let container = [640.0, 480.0];
        Plan {
            scale,
            center,
            visible: [container[0] / scale, container[1] / scale],
            offset: std::array::from_fn(|i| container[i] / 2.0 - center[i] * scale),
            base_scale: scale,
            zoom: 0.0,
            zoom_min: 0.0,
            zoom_max: 0.0,
        }
    }
    #[test]
    fn fractional_plans_keep_gradient_bands_full_width() {
        let g = CustomGradient::prepare("4|0|448|0,0,0_255,255,255").unwrap();
        for scale in [1.25, 1.5] {
            let p = crate::screen::plan(
                [640.0, 480.0],
                [2048.0, 448.0],
                [800.0, 224.0],
                1,
                scale - 1.0,
            )
            .unwrap();
            let mut quads = Vec::new();
            g.emit(&p, [640.0, 480.0], 0, &mut quads);
            assert!(!quads.is_empty());
            for q in quads {
                assert_eq!(q.corners[0][0], 0.0);
                assert_eq!(q.corners[2][0], 640.0);
                assert!(q.corners.iter().flatten().all(|v| v.is_finite()));
            }
        }
    }
    #[test]
    fn custom_gradient_matches_map_effects_bands() {
        let g = CustomGradient::prepare("4|10|50|0,0,0_16,32,255").unwrap();
        assert_eq!(g.fill, [16, 32, 255]);
        // start band, then 4 lines of one segment: step 10, height 11.
        assert_eq!(g.bands.len(), 5);
        assert_eq!((g.bands[0].y, g.bands[0].height), (0.0, 11.0));
        assert_eq!((g.bands[1].y, g.bands[1].height), (10.0, 11.0));
        assert_eq!((g.bands[4].y, g.bands[4].height), (40.0, 11.0));
        // value at line 2: 8*floor((16/4*2)/8+0.5)=8, 8*floor(16/8+.5)=16, 8*floor(127.5/8+.5)=128.
        assert_eq!(g.bands[3].color, rgb_color([8.0, 16.0, 128.0]));
        // Spaces and trailing text in channels, as in the corpus.
        let g = CustomGradient::prepare("64|440|600|0,0,50_255,255,255 500").unwrap();
        assert_eq!(g.fill, [255, 255, 255]);
        let g = CustomGradient::prepare("32|0|448|230, 94, 197_184, 73, 157").unwrap();
        assert_eq!(g.fill, [184, 73, 157]);
        assert_eq!(g.bands.len(), 32);
        // Rounded channel 256 clamps like Color.
        let g = CustomGradient::prepare("2|0|10|250,0,0_255,0,0").unwrap();
        assert_eq!(g.bands[1].color[0], 1.0);
        assert!(CustomGradient::prepare("1|2|3").is_none());
        assert!(CustomGradient::prepare("1|2|3|").is_none());
        // One colour: no lines, only the fill (and a start band).
        let g = CustomGradient::prepare("8|-5|9|7,8,9").unwrap();
        assert!(g.bands.is_empty());
        assert_eq!(g.fill, [7, 8, 9]);
    }
    #[test]
    fn custom_bands_follow_nine_tenths_in_screen_space() {
        let g = CustomGradient::prepare("2|0|100|0,0,0_255,255,255").unwrap();
        // step 50: bands at y 0 and 50, height floor(50.5) + 1 = 51.
        assert_eq!(
            g.bands.iter().map(|b| (b.y, b.height)).collect::<Vec<_>>(),
            vec![(0.0, 51.0), (50.0, 51.0)]
        );
        let p = plan([500.0, 300.0], 1.0);
        let mut out = Vec::new();
        g.emit(&p, [640.0, 480.0], 0, &mut out);
        // top = 76; band y = offset.y + (y + 0.9 * 76), offset.y = 240 - 300.
        let at = |y: f64| p.offset[1] + (y + 0.9 * 76.0);
        assert!(at(0.0) > 0.0);
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].corners[0], [0.0, at(0.0) as f32]);
        assert_eq!(out[1].corners[2], [640.0, (at(50.0) + 51.0) as f32]);
        // Far below, the bands are above the screen and not emitted.
        let mut out = Vec::new();
        g.emit(&plan([600.0, 5000.0], 1.0), [640.0, 480.0], 0, &mut out);
        assert!(out.is_empty());
    }
    #[test]
    fn strip_gradient_uses_offset_for_the_first_strip_and_scrolls() {
        let manifest = serde_json::json!({"gradients":{"sky":{"reference":[416,224],"scroll":[0,0.1],
            "strips":[{"color":[1,2,3],"height":0},{"color":[4,5,6],"height":5},{"color":"bad","height":5},{"color":[7,8,9],"height":8}]}}});
        let g = StripGradient::prepare(&manifest, "sky_20_2", 1);
        assert_eq!(
            g.strips.iter().map(|s| (s.y, s.height)).collect::<Vec<_>>(),
            vec![(0.0, 40.0), (40.0, 10.0), (50.0, 16.0)]
        );
        let p = plan([416.0, 324.0], 1.0);
        let mut out = Vec::new();
        g.emit(&p, [640.0, 480.0], 0, &mut out);
        // shift = (324 - 224) * 0.9 = 90; screen y = world y + offset.y (240 - 324 = -84).
        assert_eq!(out.len(), 3);
        assert_eq!(out[0].corners[0][1], (90.0 - 84.0) as f32);
        assert_eq!(out[0].corners[1][0], 640.0);
        // Unknown names decode `height,r,g,b` groups; bad groups give nothing.
        let g = StripGradient::prepare(&manifest, "3,1,2,3,4,5,6,7", 1);
        assert_eq!(g.strips.len(), 2);
        assert_eq!((g.strips[0].height, g.strips[1].height), (0.0, 4.0));
        assert!(
            StripGradient::prepare(&manifest, "3,1,x,3", 1)
                .strips
                .is_empty()
        );
        assert!(
            StripGradient::prepare(&manifest, "night1_0_1", 1)
                .strips
                .is_empty()
        );
        assert!(
            StripGradient::prepare(&manifest, "sky_0_0", 1)
                .strips
                .is_empty()
        );
    }
    #[test]
    fn gradients_use_new_default_plan_with_centered_short_axis() {
        let container = [640.0, 480.0];
        let p = crate::screen::plan(container, [15040.0, 448.0], [416.0, 224.0], 1, 0).unwrap();
        let custom = CustomGradient::prepare("2|0|448|0,0,0_255,255,255").unwrap();
        let mut out = Vec::new();
        custom.emit(&p, container, 0, &mut out);
        assert_eq!(out[0].corners[0], [0.0, 16.0]);
        assert_eq!(out[1].corners[2], [640.0, 465.0]);
        out.clear();
        let manifest = serde_json::json!({"gradients":{"sky":{"reference":[416,224],"scroll":[1,1],
            "strips":[{"color":[0,0,0],"height":0},{"color":[255,255,255],"height":448}]}}});
        let strips = StripGradient::prepare(&manifest, "sky", 1);
        strips.emit(&p, container, 0, &mut out);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].corners[0], [0.0, 16.0]);
        assert_eq!(out[0].corners[2], [640.0, 464.0]);
    }
    #[test]
    fn godot_number_parsers() {
        assert_eq!(leading_float("12xy3"), 12.0);
        assert_eq!(leading_float("-1.5e2z"), -150.0);
        assert_eq!(leading_float("abc"), 0.0);
        assert_eq!(whole(" 255 500"), 255.0);
        assert_eq!(whole("x"), 0.0);
        assert_eq!(valid_float("1.5"), Some(1.5));
        assert_eq!(valid_float("inf"), None);
        assert_eq!(valid_float(""), None);
    }
}
