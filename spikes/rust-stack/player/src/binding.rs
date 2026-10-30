//! Pack frame binding, not gameplay pose selection. All metadata work precedes frames.
use serde_json::Value;
use std::collections::HashMap;

pub type ImageId = usize;
#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    pub image: ImageId,
    pub origin: [f64; 2],
    pub duration: f64,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Animation {
    pub frames: Vec<Frame>,
    pub duration: f64,
    pub fps: f64,
    pub looping: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Anchor {
    Position,
    Box,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fill {
    Tile,
    Stretch,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Slices {
    pub left: f64,
    pub right: f64,
    pub top: f64,
    pub bottom: f64,
    pub fill: Fill,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Visual {
    pub animations: Vec<(String, Animation)>,
    pub states: HashMap<String, String>,
    pub default: usize,
    pub anchor: Anchor,
    pub facing: i64,
    pub density: u32,
    pub slices: Option<Slices>,
}
#[derive(Default)]
pub struct Catalog {
    pub files: Vec<String>,
    index: HashMap<String, ImageId>,
}
impl Catalog {
    pub fn image(&mut self, file: &str) -> Result<ImageId, String> {
        if !file.ends_with(".png")
            || file.starts_with('/')
            || file.contains([':', '\\'])
            || file.split('/').any(|s| s == ".." || s.is_empty())
        {
            return Err(format!("unsupported/unsafe private image: {file}"));
        }
        if let Some(&id) = self.index.get(file) {
            return Ok(id);
        }
        let id = self.files.len();
        self.files.push(file.to_owned());
        self.index.insert(file.to_owned(), id);
        Ok(id)
    }
    pub fn visual(
        &mut self,
        entry: &Value,
        variant: i64,
        density: u32,
        decor_ping_pong: bool,
    ) -> Result<Visual, String> {
        let entry = entry
            .get("variants")
            .and_then(|v| v.get(variant.to_string()))
            .unwrap_or(entry);
        let sources: Vec<(String, Value)> =
            if let Some(animations) = entry.get("animations").and_then(Value::as_object) {
                animations
                    .iter()
                    .map(|(k, v)| (k.clone(), v.clone()))
                    .collect()
            } else if entry.get("file").is_some() {
                vec![(
                    "default".into(),
                    serde_json::json!({"frames":[entry],"fps":0,"loop":false}),
                )]
            } else {
                return Err("required visual missing animations/file".into());
            };
        let mut animations = Vec::new();
        for (name, source) in sources {
            let mut frames = Vec::new();
            for f in source
                .get("frames")
                .and_then(Value::as_array)
                .ok_or("required animation frames missing")?
            {
                let file = f
                    .get("file")
                    .and_then(Value::as_str)
                    .ok_or("frame file missing")?;
                let origin = point(f.get("origin").or_else(|| source.get("origin")), [0.0, 0.0])?;
                let duration = f.get("duration").and_then(Value::as_f64).unwrap_or(1.0);
                if !duration.is_finite() || duration <= 0.0 {
                    return Err("invalid frame duration".into());
                }
                frames.push(Frame {
                    image: self.image(file)?,
                    origin,
                    duration,
                });
            }
            if frames.is_empty() {
                return Err("required animation empty".into());
            }
            if decor_ping_pong
                && source.get("ping_pong").and_then(Value::as_bool) == Some(true)
                && frames.len() > 2
            {
                for i in (1..frames.len() - 1).rev() {
                    frames.push(frames[i].clone());
                }
            }
            let duration = frames.iter().map(|f| f.duration).sum();
            let fps = source
                .get("fps")
                .or_else(|| source.get("speed"))
                .and_then(Value::as_f64)
                .unwrap_or(0.0);
            if !fps.is_finite() {
                return Err("invalid animation fps".into());
            }
            animations.push((
                name,
                Animation {
                    frames,
                    duration,
                    fps,
                    looping: source.get("loop").and_then(Value::as_bool).unwrap_or(true),
                },
            ));
        }
        if animations.is_empty() {
            return Err("required visual empty".into());
        }
        let default = animations
            .iter()
            .position(|(name, _)| {
                Some(name.as_str()) == entry.get("default_animation").and_then(Value::as_str)
            })
            .unwrap_or(0);
        let mut states = HashMap::new();
        if let Some(source) = entry.get("states").and_then(Value::as_object) {
            for (key, value) in source {
                states.insert(
                    key.to_owned(),
                    value
                        .as_str()
                        .ok_or("state animation name not string")?
                        .to_owned(),
                );
            }
        }
        let slices = entry
            .get("slices")
            .map(|s| -> Result<Slices, String> {
                let number = |k: &str| s.get(k).and_then(Value::as_f64).unwrap_or(0.0);
                let result = Slices {
                    left: number("left"),
                    right: number("right"),
                    top: number("top"),
                    bottom: number("bottom"),
                    fill: match s.get("fill").and_then(Value::as_str).unwrap_or("tile") {
                        "tile" => Fill::Tile,
                        "stretch" => Fill::Stretch,
                        _ => return Err("unsupported slice fill".into()),
                    },
                };
                if [result.left, result.right, result.top, result.bottom]
                    .iter()
                    .any(|v| !v.is_finite() || *v < 0.0)
                {
                    return Err("invalid slice margins".into());
                }
                Ok(result)
            })
            .transpose()?;
        Ok(Visual {
            animations,
            states,
            default,
            anchor: if entry.get("anchor").and_then(Value::as_str) == Some("position") {
                Anchor::Position
            } else {
                Anchor::Box
            },
            facing: if entry.get("facing").and_then(Value::as_i64) == Some(-1) {
                -1
            } else {
                1
            },
            density,
            slices,
        })
    }
}
pub fn point(value: Option<&Value>, default: [f64; 2]) -> Result<[f64; 2], String> {
    let Some(value) = value else {
        return Ok(default);
    };
    let a = value.as_array().ok_or("point not array")?;
    if a.len() != 2 {
        return Err("point size not two".into());
    }
    let p = [
        a[0].as_f64().ok_or("point x not number")?,
        a[1].as_f64().ok_or("point y not number")?,
    ];
    if p.iter().any(|v| !v.is_finite()) {
        return Err("nonfinite point".into());
    }
    Ok(p)
}
impl Visual {
    /// A semantic player pose must resolve; never conceal an unknown wet/action
    /// pose by sampling the default idle animation.
    pub fn sample_required(
        &self,
        tick: i64,
        state: &str,
        variant: i64,
        literal_frame: Option<i64>,
    ) -> Result<&Frame, String> {
        let alias = self
            .states
            .get(&format!("{state}:{variant}"))
            .or_else(|| self.states.get(state));
        if !self
            .animations
            .iter()
            .any(|(name, _)| name == state || alias == Some(name))
        {
            return Err(format!(
                "required semantic pose not bound: {state}:{variant}"
            ));
        }
        Ok(self.sample(tick, state, variant, literal_frame))
    }
    pub fn sample(
        &self,
        tick: i64,
        state: &str,
        variant: i64,
        literal_frame: Option<i64>,
    ) -> &Frame {
        // view_sample/Runtime.apply_frame: literal animation names override aliases.
        let named = self.animations.iter().position(|(name, _)| name == state);
        let alias = self
            .states
            .get(&format!("{state}:{variant}"))
            .or_else(|| self.states.get(state));
        let index = named
            .or_else(|| alias.and_then(|a| self.animations.iter().position(|(n, _)| n == a)))
            .unwrap_or(self.default);
        let a = &self.animations[index].1;
        if let Some(frame) = literal_frame {
            return &a.frames[frame.clamp(0, a.frames.len() as i64 - 1) as usize];
        }
        if a.fps == 0.0 {
            return &a.frames[variant.clamp(0, a.frames.len() as i64 - 1) as usize];
        }
        let mut position = (tick as f64 * a.fps / 60.0).max(0.0);
        if a.looping {
            position %= a.duration;
        } else {
            position = position.min(a.duration);
        }
        let mut end = 0.0;
        for frame in &a.frames {
            end += frame.duration;
            if position < end {
                return frame;
            }
        }
        a.frames.last().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn entry() -> Value {
        serde_json::json!({"default_animation":"walk","anchor":"position","facing":-1,"animations":{"walk":{"fps":60,"loop":false,"origin":[4,9],"frames":[{"file":"a.png","duration":2},{"file":"b.png","origin":[3,8]}]},"idle":{"fps":0,"frames":[{"file":"c.png"},{"file":"d.png"}]}},"states":{"still":"idle","still:2":"walk"}})
    }
    #[test]
    fn timing_origin_and_hold() {
        let mut c = Catalog::default();
        let v = c.visual(&entry(), 0, 1, false).unwrap();
        assert_eq!(v.sample(1, "walk", 0, None).origin, [4.0, 9.0]);
        assert_eq!(v.sample(2, "walk", 0, None).origin, [3.0, 8.0]);
        assert_eq!(v.sample(999, "walk", 0, None).origin, [3.0, 8.0]);
        assert_eq!(v.sample(999, "walk", 0, Some(0)).origin, [4.0, 9.0]);
    }
    #[test]
    fn aliases_and_fixed_variants() {
        let mut c = Catalog::default();
        let v = c.visual(&entry(), 0, 1, false).unwrap();
        assert_eq!(c.files[v.sample(0, "still", 1, None).image], "d.png");
        assert_eq!(c.files[v.sample(0, "still", 2, None).image], "a.png");
    }
    #[test]
    fn required_pose_accepts_named_and_alias_but_rejects_unknown() {
        let mut c = Catalog::default();
        let v = c.visual(&entry(), 0, 1, false).unwrap();
        assert_eq!(
            v.sample_required(1, "walk", 0, None).unwrap(),
            v.sample(1, "walk", 0, None)
        );
        assert!(v.sample_required(0, "still", 2, None).is_ok());
        assert!(v.sample_required(0, "unknown-wet-pose", 0, None).is_err());
    }
    #[test]
    fn metadata_work_shares_images() {
        let mut c = Catalog::default();
        c.visual(&entry(), 0, 1, false).unwrap();
        c.visual(&entry(), 0, 1, false).unwrap();
        assert_eq!(c.files.len(), 4);
    }
}
