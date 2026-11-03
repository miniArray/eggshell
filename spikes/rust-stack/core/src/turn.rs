//! oriented_box.gd: integer oriented rectangles. Angles are clockwise thousandths of a
//! degree.
use crate::{
    math::{root, sine},
    Position, SCALE as S,
};
pub(crate) const TURN: i64 = 360_000;

/// oriented_box.gd angle_wrap
pub(crate) fn wrap(angle: i64) -> i64 {
    (angle % TURN + TURN) % TURN
}
/// oriented_box.gd vector
pub(crate) fn vector(angle: i64, length: i64) -> (i64, i64) {
    let (x, y, magnitude) = unit(wrap(angle));
    (length * x / magnitude, length * y / magnitude)
}
/// The integer sine pair of a wrapped angle and its magnitude, remembered for the last
/// angle asked: turned solids test the same few angles many times per step.
type Unit = (i64, i64, i64);
fn unit(angle: i64) -> Unit {
    thread_local! {
        static LAST: std::cell::Cell<Option<(i64, Unit)>> = const { std::cell::Cell::new(None) };
    }
    if let Some((cached, value)) = LAST.get() {
        if cached == angle {
            return value;
        }
    }
    let x = sine(wrap(angle + 90_000), TURN, 1_000_000).expect("fixed period");
    let y = sine(angle, TURN, 1_000_000).expect("fixed period");
    let value = (x, y, root(x * x + y * y));
    LAST.set(Some((angle, value)));
    value
}
/// oriented_box.gd points: `rect` turned by `angle` about the origin.
pub(crate) fn points(angle: i64, rect: [i64; 4]) -> [Position; 4] {
    let (bx, by) = vector(angle, S);
    [
        [rect[0], rect[1]],
        [rect[2], rect[1]],
        [rect[2], rect[3]],
        [rect[0], rect[3]],
    ]
    .map(|c| Position {
        x: (c[0] * bx - c[1] * by) / S,
        y: (c[0] * by + c[1] * bx) / S,
    })
}
/// oriented_box.gd bounds (World.polygon_bounds of the points).
pub(crate) fn bounds(angle: i64, rect: [i64; 4]) -> [i64; 4] {
    let pts = points(angle, rect);
    let mut b = [pts[0].x, pts[0].y, pts[0].x, pts[0].y];
    for p in &pts[1..] {
        b = [b[0].min(p.x), b[1].min(p.y), b[2].max(p.x), b[3].max(p.y)];
    }
    b
}
/// oriented_box.gd overlaps: the turned rectangle at (x, y) against a world box.
pub(crate) fn overlaps(angle: i64, rect: [i64; 4], probe: [i64; 4], x: i64, y: i64) -> bool {
    crate::polygon::overlaps_box(
        &points(angle, rect),
        [probe[0] - x, probe[1] - y, probe[2] - x, probe[3] - y],
    )
}
