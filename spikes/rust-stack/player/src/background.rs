//! Read-only reproduction of pack_background.gd's image-layer policy.
use crate::{
    binding::{Catalog, Visual, point},
    geometry::{Transform, sprite_quad, visible},
    gles::Quad,
    screen::{Plan, godot_round},
};
use serde_json::Value;

#[derive(Clone, Debug, PartialEq)]
pub struct Layer {
    visual: Visual,
    frame: i64,
    scale: [f64; 2],
    offset: [f64; 2],
    anchor: Option<[f64; 2]>,
    scroll: [f64; 2],
    reference: [f64; 2],
    period: [f64; 2],
    repeat: [bool; 2],
    min_repeat: i64,
}
#[derive(Clone, Debug)]
pub struct Group {
    pub id: String,
    pub variant: i64,
    layers: Vec<Layer>,
}
#[derive(Clone, Debug)]
pub struct Background {
    groups: Vec<Group>,
    density: u32,
}
impl Background {
    pub fn prepare(
        manifest: &Value,
        catalog: &mut Catalog,
        choices: &[String; 3],
        map_height: i64,
        density: u32,
    ) -> Result<Self, String> {
        let mut groups = Vec::new();
        let d = density as f64;
        for (slot, choice) in ["bg1", "bg2", "bg3"].iter().zip(choices) {
            let mut parts = choice.split(',');
            let id = parts.next().unwrap_or("0");
            let variant = parts
                .next()
                .and_then(|s| s.parse::<i64>().ok())
                .unwrap_or(0);
            if id == "0" || id.is_empty() {
                continue;
            }
            let mut entry = manifest
                .get("backgrounds")
                .and_then(|b| b.get(id))
                .ok_or_else(|| format!("required background absent: {id}"))?
                .clone();
            let selected = entry
                .get("variants")
                .and_then(|v| v.get(variant.to_string()))
                .cloned();
            if let Some(Value::Object(selected)) = selected {
                let base = entry.as_object_mut().ok_or("background not object")?;
                for (key, value) in selected {
                    base.insert(key, value);
                }
            }
            let mut layers = Vec::new();
            for layer in entry
                .get("layers")
                .and_then(Value::as_array)
                .ok_or("background layers missing")?
            {
                let (visual, frame) = if let Some(animation) = layer.get("animation") {
                    (
                        catalog.visual(
                            &serde_json::json!({"animations":{"default":animation}}),
                            0,
                            1,
                            false,
                        )?,
                        layer.get("frame").and_then(Value::as_i64).unwrap_or(0),
                    )
                } else {
                    let selected = layer.get("frames").and_then(Value::as_array).and_then(|f| {
                        if f.is_empty() {
                            None
                        } else {
                            Some(&f[variant.clamp(0, f.len() as i64 - 1) as usize])
                        }
                    });
                    let source = match selected {
                        Some(Value::String(file)) => serde_json::json!({"file":file}),
                        Some(value) => value.clone(),
                        None => {
                            serde_json::json!({"file":layer.get("file").ok_or("background image missing")?})
                        }
                    };
                    (catalog.visual(&source, 0, 1, false)?, 0)
                };
                let overrides = entry.get("slots").and_then(|s| s.get(*slot));
                let scroll = point(
                    overrides
                        .and_then(|s| s.get("scroll"))
                        .or_else(|| layer.get("scroll")),
                    [1.0, 1.0],
                )?;
                let extra = point(
                    overrides
                        .and_then(|s| s.get("offset_by_height"))
                        .and_then(|s| s.get(map_height.to_string())),
                    [0.0, 0.0],
                )?;
                let scale = point(layer.get("scale"), [1.0, 1.0])?;
                if scale.iter().any(|v| *v <= 0.0) {
                    return Err("nonpositive background scale".into());
                }
                let anchor = layer
                    .get("anchor")
                    .map(|a| point(Some(a), [0.0, 0.0]))
                    .transpose()?;
                let mut offset = point(layer.get("offset"), [0.0, 0.0])?;
                if let Some(a) = anchor {
                    let origin = visual.sample(0, "", frame, None).origin;
                    offset = [a[0] - origin[0] * scale[0], a[1] - origin[1] * scale[1]];
                }
                let reference = point(layer.get("reference"), [0.0, 0.0])?;
                let period = point(layer.get("repeat_size"), [0.0, 0.0])?;
                layers.push(Layer {
                    visual,
                    frame,
                    scale: scale.map(|v| v / d),
                    offset: std::array::from_fn(|i| (offset[i] + extra[i]) / d),
                    anchor: anchor.map(|a| std::array::from_fn(|i| (a[i] + extra[i]) / d)),
                    scroll,
                    reference: reference.map(|v| v / d),
                    period: period.map(|v| v / d),
                    repeat: [
                        layer
                            .get("repeat_x")
                            .and_then(Value::as_bool)
                            .unwrap_or(true),
                        layer
                            .get("repeat_y")
                            .and_then(Value::as_bool)
                            .unwrap_or(false),
                    ],
                    min_repeat: layer
                        .get("min_repeat")
                        .and_then(Value::as_i64)
                        .unwrap_or(-4096),
                });
            }
            if layers.is_empty() {
                return Err(format!("required background group empty: {id}"));
            }
            groups.push(Group {
                id: id.into(),
                variant,
                layers,
            });
        }
        Ok(Self { groups, density })
    }
    pub fn emit(
        &self,
        tick: i64,
        plan: &Plan,
        container: [f64; 2],
        sizes: &[[f64; 2]],
        binary_alpha: &[bool],
        out: &mut Vec<Quad>,
    ) -> Result<(), String> {
        let mut previous: Option<&Group> = None;
        for group in &self.groups {
            // Target's three groups are distinct. Preserve source idempotence for
            // consecutive identical binary-alpha groups, including every frame.
            let binary = group.layers.iter().all(|l| {
                l.visual
                    .animations
                    .iter()
                    .all(|(_, a)| a.frames.iter().all(|f| binary_alpha[f.image]))
            });
            if previous.is_some_and(|p| {
                p.id == group.id && p.variant == group.variant && p.layers == group.layers
            }) && binary
            {
                continue;
            }
            previous = Some(group);
            for layer in &group.layers {
                let f = layer.visual.sample(tick, "", layer.frame, None);
                let mut scale = layer.scale;
                let mut offset = layer.offset;
                if self.density > 1 {
                    for s in &mut scale {
                        *s = godot_round(*s * plan.scale).max(1.0) / plan.scale;
                    }
                }
                if let Some(a) = layer.anchor {
                    offset = [a[0] - f.origin[0] * scale[0], a[1] - f.origin[1] * scale[1]];
                }
                let size = [sizes[f.image][0] * scale[0], sizes[f.image][1] * scale[1]];
                let mut origin = std::array::from_fn::<_, 2, _>(|i| {
                    offset[i] + (plan.center[i] - layer.reference[i]) * (1.0 - layer.scroll[i])
                });
                if self.density > 1 {
                    for (i, value) in origin.iter_mut().enumerate() {
                        *value = (godot_round(*value * plan.scale + godot_round(plan.offset[i]))
                            - godot_round(plan.offset[i]))
                            / plan.scale;
                    }
                }
                let mut period = std::array::from_fn::<_, 2, _>(|i| {
                    if layer.period[i] > 0.0 {
                        layer.period[i]
                    } else {
                        size[i]
                    }
                });
                if self.density > 1 {
                    period = period.map(|v| godot_round(v * plan.scale).max(1.0) / plan.scale);
                }
                let explicit = period != size;
                let visible_start = [
                    plan.center[0] - plan.visible[0] / 2.0,
                    plan.center[1] - plan.visible[1] / 2.0,
                ];
                let visible_end = [
                    visible_start[0] + plan.visible[0],
                    visible_start[1] + plan.visible[1],
                ];
                let first = std::array::from_fn::<_, 2, _>(|i| {
                    if layer.repeat[i] {
                        let v =
                            ((visible_start[i] - origin[i] - if explicit { size[i] } else { 0.0 })
                                / period[i])
                                .floor() as i64;
                        if explicit && i == 0 {
                            v.max(layer.min_repeat)
                        } else {
                            v
                        }
                    } else {
                        0
                    }
                });
                let last = std::array::from_fn::<_, 2, _>(|i| {
                    if layer.repeat[i] {
                        ((visible_end[i] - origin[i]) / period[i]).ceil() as i64
                    } else {
                        0
                    }
                });
                if (last[0] - first[0] + 1).max(0) > 4096 || (last[1] - first[1] + 1).max(0) > 4096
                {
                    return Err("background repeat admission limit exceeded".into());
                }
                for y in first[1]..=last[1] {
                    for x in first[0]..=last[0] {
                        let t = Transform {
                            position: [
                                origin[0] + x as f64 * period[0],
                                origin[1] + y as f64 * period[1],
                            ],
                            scale,
                            ..Transform::default()
                        };
                        let q = sprite_quad(f.image, sizes[f.image], t, plan, [1.0; 4], &[]);
                        if visible(&q, container) {
                            out.push(q);
                        }
                    }
                }
            }
        }
        Ok(())
    }
}
