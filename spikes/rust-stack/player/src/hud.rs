//! Literal read-only HUD layout and bitmap-glyph binding from hud.gd.
use crate::{
    binding::{Catalog, Visual},
    geometry::{Transform, rect_quad},
    gles::Quad,
    screen::Plan,
};
use eggshell_spike_core::HudPicture;
use serde_json::Value;
use std::path::Path;

#[derive(Clone, Debug)]
pub struct Font {
    image: usize,
    cell: [f64; 2],
    characters: Vec<char>,
    widths: Vec<(f64, String)>,
    space_advance: f64,
}
#[derive(Clone, Debug)]
pub struct Hud {
    font: Font,
    icons: [Visual; 4],
    icon_variants: [i64; 4],
    dense: bool,
    padding: i32,
    backing: Option<[u8; 3]>,
}
#[derive(Clone, Debug)]
pub struct Layout {
    pub scale: f64,
    pub positions: Vec<[f64; 2]>,
    pub size: [f64; 2],
}
impl Font {
    pub fn prepare(
        manifest: &Value,
        catalog: &mut Catalog,
        metrics: &Path,
    ) -> Result<Self, String> {
        let metadata: Value =
            serde_json::from_slice(&std::fs::read(metrics).map_err(|e| e.to_string())?)
                .map_err(|e| e.to_string())?;
        let advance = metadata
            .get("space_advance")
            .and_then(Value::as_f64)
            .ok_or("reference view metrics lack space advance")?;
        if !advance.is_finite()
            || advance <= 0.0
            || metadata.get("font_size").and_then(Value::as_i64) != Some(16)
        {
            return Err("invalid reference font metrics".into());
        }
        println!(
            "RUST_VIEW_METRICS reference_Godot={:?} font_size=16 space_advance={advance}",
            metadata.get("godot")
        );
        let entry = ["hud", "MainFont", "ScoreFont", "LifeCounterFont"]
            .iter()
            .find_map(|k| {
                manifest
                    .get("fonts")
                    .and_then(|v| v.get(k))
                    .filter(|v| v.get("cell_width").is_some())
            })
            .ok_or("required HUD bitmap font missing")?;
        let mut widths = Vec::new();
        if let Some(values) = entry.get("widths").and_then(Value::as_array) {
            for pair in values {
                widths.push((
                    pair[0].as_f64().ok_or("glyph advance not numeric")?,
                    pair[1]
                        .as_str()
                        .ok_or("glyph width group not string")?
                        .to_owned(),
                ));
            }
        }
        Ok(Self {
            image: catalog.image(
                entry
                    .get("file")
                    .and_then(Value::as_str)
                    .ok_or("HUD font image missing")?,
            )?,
            cell: [
                entry["cell_width"]
                    .as_f64()
                    .ok_or("bitmap cell width missing")?,
                entry["cell_height"]
                    .as_f64()
                    .ok_or("bitmap cell height missing")?,
            ],
            characters: entry["characters"]
                .as_str()
                .ok_or("bitmap characters missing")?
                .chars()
                .collect(),
            widths,
            space_advance: advance,
        })
    }
    fn advance(&self, c: char, dense: bool) -> Result<f64, String> {
        let width = if self.characters.contains(&c) {
            self.widths
                .iter()
                .find(|(_, s)| s.contains(c))
                .map(|(w, _)| *w)
                .unwrap_or(self.cell[0])
        } else if c == ' ' {
            self.space_advance
        } else {
            return Err(format!("reference default-font glyph not admitted: {c:?}"));
        };
        Ok(if dense { width.ceil() } else { width })
    }
    fn measure(&self, text: &str, dense: bool) -> Result<f64, String> {
        text.chars()
            .try_fold(0.0, |a, c| Ok(a + self.advance(c, dense)?))
    }
    fn emit(
        &self,
        text: &str,
        mut at: [f64; 2],
        scale: f64,
        size: [f64; 2],
        dense: bool,
        out: &mut Vec<Quad>,
    ) -> Result<(), String> {
        let plan = overlay_plan(scale);
        let columns = (size[0] / self.cell[0]).floor().max(1.0) as usize;
        for c in text.chars() {
            if let Some(index) = self.characters.iter().position(|v| *v == c) {
                out.push(rect_quad(
                    self.image,
                    [
                        (index % columns) as f64 * self.cell[0],
                        (index / columns) as f64 * self.cell[1],
                        self.cell[0],
                        self.cell[1],
                    ],
                    size,
                    [at[0], at[1], self.cell[0], self.cell[1]],
                    Transform::default(),
                    &plan,
                    [1.0; 4],
                    &[],
                ));
            }
            at[0] += self.advance(c, dense)?;
        }
        Ok(())
    }
}
impl Hud {
    pub fn prepare(
        manifest: &Value,
        catalog: &mut Catalog,
        metrics: &Path,
        density: u32,
    ) -> Result<Self, String> {
        let font = Font::prepare(manifest, catalog, metrics)?;
        let hud = manifest.get("hud").ok_or("HUD metadata missing")?;
        let objects = manifest.get("objects").ok_or("object metadata missing")?;
        let countdown = hud
            .get("countdown")
            .or_else(|| hud.get("LifeCounter"))
            .ok_or("countdown icon missing")?;
        let coins = hud
            .get("coins")
            .or_else(|| objects.get("o1"))
            .ok_or("coin icon missing")?;
        let generic = hud.get("HUDIcons").ok_or("HUDIcons metadata missing")?;
        let icons = [
            catalog.visual(countdown, 0, 1, false)?,
            catalog.visual(coins, 0, 1, false)?,
            catalog.visual(hud.get("redcoins").unwrap_or(generic), 0, 1, false)?,
            catalog.visual(hud.get("flowers").unwrap_or(generic), 0, 1, false)?,
        ];
        let backing = hud
            .get("backing")
            .and_then(|v| v.get("color"))
            .and_then(Value::as_array)
            .filter(|a| a.len() == 3)
            .map(|a| {
                [
                    a[0].as_u64().unwrap_or(0) as u8,
                    a[1].as_u64().unwrap_or(0) as u8,
                    a[2].as_u64().unwrap_or(0) as u8,
                ]
            });
        let padding = if backing.is_some() {
            hud["backing"]
                .get("padding")
                .and_then(Value::as_i64)
                .unwrap_or(2) as i32
        } else {
            -1
        };
        let icon_variants = [
            0,
            0,
            if hud.get("redcoins").is_none() { 1 } else { 0 },
            if hud.get("flowers").is_none() { 2 } else { 0 },
        ];
        Ok(Self {
            font,
            icons,
            icon_variants,
            dense: density > 1,
            padding,
            backing,
        })
    }
    #[allow(clippy::too_many_arguments)]
    pub fn emit(
        &self,
        h: &HudPicture,
        tick: i64,
        container: [f64; 2],
        base_scale: f64,
        density: u32,
        sizes: &[[f64; 2]],
        solid_image: usize,
        out: &mut Vec<Quad>,
    ) -> Result<Layout, String> {
        let mut items = vec![
            (format!("Stars {}", h.health), Some(0)),
            (format!("Coins {}", h.coins), Some(1)),
            (format!("Red {}/{}", h.redcoins, h.redcoins_target), Some(2)),
            (
                format!("Flowers {}/{}", h.flowers, h.flowers_target),
                Some(3),
            ),
        ];
        // Read-only UI branch from hud.gd, not a gameplay phase transition.
        if h.life_phase == 8 || (h.life_phase == 7 && h.life_ticks <= 60) {
            items.push((format!("Hurt {}  Deaths {}", h.hits, h.deaths), None));
            items.push((format!("Time {}", clock_text(h.total_play_ticks)), None));
        }
        if !h.status.is_empty() {
            items.push((h.status.clone(), None));
        }
        let text_height = self.font.cell[1].max(16.0);
        let art_scale = (base_scale / density as f64).round().max(1.0);
        let mut widths = Vec::new();
        let mut heights = Vec::new();
        for (text, icon) in &mut items {
            let mut w = self.font.measure(text, self.dense)?;
            let mut height = text_height;
            if let Some(i) = *icon {
                let frame = self.icons[i].sample(tick, "", self.icon_variants[i], None);
                let icon_size = if self.dense {
                    sizes[frame.image]
                } else {
                    [text_height, text_height]
                };
                if self.dense && w + icon_size[0] + 8.0 > container[0] / art_scale {
                    *icon = None;
                } else {
                    w += icon_size[0] + 8.0;
                    height = height.max(icon_size[1]);
                }
            }
            widths.push(w);
            heights.push(height);
        }
        let layout = if self.dense {
            dense_plan(container, &widths, &heights, art_scale, self.padding)
        } else {
            plan(container, &widths, text_height + 8.0, self.padding)
        };
        for (index, (text, icon)) in items.iter().enumerate() {
            let mut at = layout.positions[index];
            if let Some(color) = self.backing {
                let p = self.padding as f64;
                out.push(rect_quad(
                    solid_image,
                    [0.0, 0.0, 1.0, 1.0],
                    [1.0, 1.0],
                    [
                        at[0] - p,
                        at[1] - p,
                        widths[index].ceil() + p * 2.0,
                        heights[index].ceil() + p * 2.0,
                    ],
                    Transform::default(),
                    &overlay_plan(layout.scale),
                    [
                        color[0] as f32 / 255.0,
                        color[1] as f32 / 255.0,
                        color[2] as f32 / 255.0,
                        1.0,
                    ],
                    &[],
                ));
            }
            if let Some(i) = *icon {
                let frame = self.icons[i].sample(tick, "", self.icon_variants[i], None);
                let size = sizes[frame.image];
                let target = if self.dense {
                    size
                } else {
                    [text_height, text_height]
                };
                out.push(rect_quad(
                    frame.image,
                    [0.0, 0.0, size[0], size[1]],
                    size,
                    [at[0], at[1], target[0], target[1]],
                    Transform::default(),
                    &overlay_plan(layout.scale),
                    [1.0; 4],
                    &[],
                ));
                at[0] += target[0] + 8.0;
            }
            self.font.emit(
                text,
                at,
                layout.scale,
                sizes[self.font.image],
                self.dense,
                out,
            )?;
        }
        Ok(layout)
    }
}
pub fn overlay_plan(scale: f64) -> Plan {
    Plan {
        scale,
        center: [0.0; 2],
        visible: [0.0; 2],
        offset: [0.0; 2],
        base_scale: scale,
        zoom: 0,
        zoom_min: 0,
        zoom_max: 0,
    }
}
pub fn clock_text(ticks: i64) -> String {
    let ticks = ticks.max(0);
    let seconds = ticks / 60;
    format!(
        "{:02}:{:02}:{:02}.{:02}",
        seconds / 3600,
        seconds / 60 % 60,
        seconds % 60,
        ticks % 60 * 100 / 60
    )
}
pub fn plan(container: [f64; 2], widths: &[f64], mut row_height: f64, padding: i32) -> Layout {
    if container.iter().any(|v| !v.is_finite() || *v <= 0.0) {
        return Layout {
            scale: 1.0,
            positions: Vec::new(),
            size: [0.0; 2],
        };
    }
    let widths: Vec<f64> = widths
        .iter()
        .map(|w| if padding >= 0 { w.ceil() } else { *w })
        .collect();
    if padding >= 0 {
        row_height = (row_height - 8.0).ceil() + (8.max(2 * padding)) as f64;
    }
    let maximum = ((container[0] / 832.0).min(container[1] / 448.0))
        .floor()
        .max(1.0) as i32;
    let mut choices: Vec<f64> = (1..=maximum.min(4)).rev().map(|v| v as f64).collect();
    let widest = widths.iter().copied().fold(0.0, f64::max);
    let limit = (((widest + 16.0) / container[0].max(1.0))
        .max((widths.len() as f64 * row_height + 16.0) / (container[1] * 0.4)))
    .ceil()
        * 2.0;
    let mut divisor = 2.0;
    while divisor <= limit.max(2.0) {
        choices.push(1.0 / divisor);
        divisor *= 2.0;
    }
    let mut result = Layout {
        scale: 1.0,
        positions: Vec::new(),
        size: [0.0; 2],
    };
    for factor in choices {
        let available = (container[0] / factor).max(1.0);
        let mut margin = 8.0_f64.min(available / 16.0);
        if padding >= 0 {
            margin = margin.max(padding as f64).ceil();
        }
        let mut x = margin;
        let mut y = margin;
        let mut right = margin;
        let mut fits = true;
        let mut positions = Vec::new();
        for &width in &widths {
            if x > margin && x + width + margin > available {
                x = margin;
                y += row_height;
            }
            if width + 2.0 * margin > available {
                fits = false;
            }
            positions.push([x, y]);
            right = right.max(x + width + margin);
            x += width
                + if padding >= 0 {
                    8.max(2 * padding) as f64
                } else {
                    8.0
                };
        }
        let height = y + row_height + margin;
        result = Layout {
            scale: factor,
            positions,
            size: [right * factor, height * factor],
        };
        if fits && height * factor <= container[1] * 0.4 {
            break;
        }
    }
    result
}
pub fn dense_plan(
    container: [f64; 2],
    widths: &[f64],
    heights: &[f64],
    art_scale: f64,
    padding: i32,
) -> Layout {
    let available = container[0] / art_scale;
    let mut margin = 8.0_f64.min(available / 16.0).floor();
    if padding >= 0 {
        margin = margin.max(padding as f64);
    }
    let gap = if padding >= 0 {
        8.max(2 * padding) as f64
    } else {
        8.0
    };
    let mut at = [margin, margin];
    let mut row_height = 0.0_f64;
    let mut positions = Vec::new();
    for (i, width) in widths.iter().enumerate() {
        if at[0] > margin && at[0] + width + margin > available {
            at[0] = margin;
            at[1] += row_height + gap;
            row_height = 0.0;
        }
        positions.push(at);
        at[0] += width.ceil() + gap;
        row_height = row_height.max(heights[i].ceil());
    }
    Layout {
        scale: art_scale,
        positions,
        size: [container[0], (at[1] + row_height + margin) * art_scale],
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_clock_rounding() {
        assert_eq!(clock_text(3599), "00:00:59.98");
        assert_eq!(clock_text(-1), "00:00:00.00");
    }
    #[test]
    fn hud_wraps_without_reordering() {
        let p = plan([320.0, 300.0], &[140.0, 130.0, 125.0, 190.0], 28.0, -1);
        assert_eq!(p.scale, 1.0);
        assert_eq!(p.positions[0], [8.0, 8.0]);
        assert!(p.positions[2][1] > p.positions[0][1]);
    }
    #[test]
    fn dense_readouts_do_not_shrink() {
        let p = dense_plan([200.0, 900.0], &[140.0, 130.0], &[20.0, 20.0], 2.0, -1);
        assert_eq!(p.scale, 2.0);
        assert!(p.positions[1][1] > p.positions[0][1]);
    }
}
