//! e35's integer strides, knocks and rider-release geometry.
use crate::{
    actors::Actor,
    body::{Body, Probe},
    Error, Placement, PropertyValue, SCALE as S,
};
pub(crate) fn height(source: &Placement) -> Result<i64, Error> {
    let raw = source
        .properties
        .iter()
        .find(|(k, _)| k == "E1")
        .map(|(_, v)| v);
    let value = match raw {
        None => Some(50.0),
        Some(PropertyValue::Number(v)) => Some(*v),
        Some(PropertyValue::String(v)) => v.trim().parse::<f64>().ok(),
        _ => None,
    }
    .filter(|v| v.is_finite() && *v >= 0.0 && *v <= 100_000.0)
    .ok_or_else(|| Error::Unsupported {
        requirements: vec!["invalid/out-of-range stilt height E1".into()],
    })?;
    Ok((value as i64 + 18) * S)
}
impl Actor {
    pub(crate) fn stilt_advance(&mut self, body: &mut Body, facing: &mut i64, map: &Probe) {
        let bounds = self.body_bounds(*facing);
        let grounded = body.floor(map, bounds) != 0;
        let mut started = false;
        if self.phase == 1 {
            self.timer = (self.timer - 1).max(0);
            if self.timer > 0 {
                let distance = body.vx;
                let (_, on_floor) = self.movement(body, *facing, map, distance);
                started = on_floor;
                if grounded && body.vy >= 0 {
                    body.vy = -192 * 60;
                }
            } else if grounded {
                self.phase = 0;
                body.vx = 0;
                *facing = -*facing;
                self.stride = 0;
            }
        } else {
            body.vx = 0;
            let wet = i64::from(map.water_overlaps([
                body.x + bounds[0],
                body.y + bounds[1],
                body.x + bounds[2],
                body.y + bounds[3],
            ]));
            self.stride += 1;
            if self.stride >= 36 * (wet + 1) {
                self.stride = 0;
                let ahead = *facing * 24 * S;
                let blocked = body.overlaps(map, bounds, ahead, -S);
                let x = body.x + ahead;
                let floor =
                    map.support_in_box([x + bounds[0], body.y, x + bounds[2], body.y + 32 * S]);
                if blocked || !floor {
                    *facing = -*facing;
                } else {
                    body.x = x;
                }
            }
        }
        body.gravity(map, bounds, started);
    }
    pub(crate) fn stilt_knock(&mut self, body: &mut Body, facing: &mut i64, from_x: i64) {
        let away = if body.x >= from_x { 1 } else { -1 };
        self.phase = 1;
        self.timer = 36;
        *facing = away;
        body.vx = away * 48 * 60;
    }
}
