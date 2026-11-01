//! The level list menu: menu_model.gd state (start and levels pages) and menu_view.gd
//! layout and look (white text on a black panel with a white border, the focused row
//! filled white with black text, muted grey for unavailable rows, the scene dimmed).
//! Text uses the pack's HUD bitmap font, like the rest of the Rust HUD.
use crate::{
    geometry::{Transform, rect_quad},
    gles::Quad,
    hud::{Font, overlay_plan},
    level_list::Entry,
};

/// menu_view.gd constants, in unscaled pixels.
pub const GAP: f64 = 8.0;
pub const REFERENCE: [f64; 2] = [832.0, 448.0];
pub const MAX_SCALE: f64 = 4.0;
pub const MAX_WIDTH: f64 = 480.0;
pub const MIN_LIST_ROWS: f64 = 4.0;
pub const DIM: [f32; 4] = [0.0, 0.0, 0.0, 0.6];
pub const WHITE: [f32; 4] = [1.0; 4];
pub const BLACK: [f32; 4] = [0.0, 0.0, 0.0, 1.0];
pub const MUTED: [f32; 4] = [0.65, 0.65, 0.65, 1.0];
/// Width of the scroll position bar at the right of an overflowing list.
pub const SCROLLBAR: f64 = 4.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Page {
    Start,
    Levels,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Request {
    None,
    Open(usize),
    Quit,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Item {
    pub label: String,
    pub detail: String,
    pub enabled: bool,
    kind: ItemKind,
}
#[derive(Clone, Copy, Debug, PartialEq)]
enum ItemKind {
    Levels,
    Quit,
    Level(usize),
}

/// menu_model.gd without an open level. Settings are not part of the Rust player yet.
pub struct Model {
    pub levels: Vec<Entry>,
    pages: Vec<Page>,
    focus: [usize; 2],
    pub status: String,
}
impl Model {
    /// Opens on the level list (above the start page) when there are levels, with the
    /// focus on `focus_file` when it is listed.
    pub fn open(levels: Vec<Entry>, focus_file: Option<&str>) -> Self {
        let focus = focus_file
            .and_then(|f| levels.iter().position(|e| e.file == f))
            .unwrap_or(0);
        let pages = if levels.is_empty() {
            vec![Page::Start]
        } else {
            vec![Page::Start, Page::Levels]
        };
        Self {
            levels,
            pages,
            focus: [0, focus],
            status: String::new(),
        }
    }
    pub fn page(&self) -> Page {
        *self.pages.last().unwrap_or(&Page::Start)
    }
    fn slot(&self) -> usize {
        match self.page() {
            Page::Start => 0,
            Page::Levels => 1,
        }
    }
    pub fn title(&self) -> &'static str {
        match self.page() {
            Page::Start => "Eggshell",
            Page::Levels => "Levels",
        }
    }
    pub fn playable(&self) -> usize {
        self.levels.iter().filter(|e| e.ok).count()
    }
    pub fn info(&self) -> String {
        match self.page() {
            Page::Start => "No level is open.".into(),
            Page::Levels => {
                let count = self.levels.len();
                format!(
                    "{count} {}, {} playable",
                    if count == 1 { "level" } else { "levels" },
                    self.playable()
                )
            }
        }
    }
    /// Controls of the current page, named by the device buttons.
    pub fn hint(&self) -> &'static str {
        match self.page() {
            Page::Start => "A: select. Select+Start: quit.",
            Page::Levels => "A: play. L1/R1: page. B: back. Select+Start: quit.",
        }
    }
    pub fn items(&self) -> Vec<Item> {
        match self.page() {
            Page::Start => {
                let mut items = Vec::new();
                if !self.levels.is_empty() {
                    items.push(item("Levels", ItemKind::Levels));
                }
                items.push(item("Quit", ItemKind::Quit));
                items
            }
            Page::Levels => self
                .levels
                .iter()
                .enumerate()
                .map(|(index, level)| Item {
                    label: level.name.clone(),
                    detail: if level.ok {
                        if level.author.is_empty() {
                            String::new()
                        } else {
                            format!("by {}", level.author)
                        }
                    } else {
                        level.error.clone()
                    },
                    enabled: level.ok,
                    kind: ItemKind::Level(index),
                })
                .collect(),
        }
    }
    fn count(&self) -> usize {
        match self.page() {
            Page::Start => 1 + usize::from(!self.levels.is_empty()),
            Page::Levels => self.levels.len(),
        }
    }
    pub fn focused(&self) -> usize {
        self.focus[self.slot()].min(self.count().saturating_sub(1))
    }
    /// Move the focus by `delta` items, wrapping at either end.
    pub fn step(&mut self, delta: i64) {
        let count = self.count() as i64;
        if count > 0 {
            let slot = self.slot();
            self.focus[slot] = (self.focused() as i64 + delta).rem_euclid(count) as usize;
        }
    }
    /// Move the focus by whole pages of `rows` items, stopping at either end.
    pub fn page_step(&mut self, delta: i64, rows: usize) {
        let count = self.count() as i64;
        if count > 0 {
            let slot = self.slot();
            self.focus[slot] =
                (self.focused() as i64 + delta * rows.max(1) as i64).clamp(0, count - 1) as usize;
        }
    }
    pub fn confirm(&mut self) -> Request {
        let items = self.items();
        let Some(item) = items.get(self.focused()) else {
            return Request::None;
        };
        match item.kind {
            ItemKind::Levels => {
                self.pages.push(Page::Levels);
                self.status.clear();
                Request::None
            }
            ItemKind::Quit => Request::Quit,
            ItemKind::Level(index) => {
                if item.enabled {
                    Request::Open(index)
                } else {
                    self.status = format!("Cannot open {}: {}", item.label, item.detail);
                    Request::None
                }
            }
        }
    }
    /// Go back one page. Without an open level there is nothing to resume at the root.
    pub fn back(&mut self) {
        if self.pages.len() > 1 {
            self.pages.pop();
            self.status.clear();
        }
    }
}
fn item(label: &str, kind: ItemKind) -> Item {
    Item {
        label: label.into(),
        detail: String::new(),
        enabled: true,
        kind,
    }
}

/// menu_view.gd plan: whole-number scale, the unscaled space, and the largest panel.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Plan {
    pub scale: f64,
    pub space: [f64; 2],
    pub size: [f64; 2],
}
pub fn plan(container: [f64; 2]) -> Option<Plan> {
    if container[0] <= 0.0 || container[1] <= 0.0 {
        return None;
    }
    let scale = (container[0] / REFERENCE[0])
        .min(container[1] / REFERENCE[1])
        .floor()
        .clamp(1.0, MAX_SCALE);
    let space = [container[0] / scale, container[1] / scale];
    let margin = (2.0 * GAP).min(space[0].min(space[1]) / 16.0).floor();
    let size = [
        MAX_WIDTH.min(space[0] - 2.0 * margin).max(1.0),
        (space[1] - 2.0 * margin).max(1.0),
    ];
    Some(Plan { scale, space, size })
}
/// menu_view.gd compact: fewer than MIN_LIST_ROWS rows would remain after the header.
pub fn compact(height: f64, header: f64, row: f64) -> bool {
    height - header < MIN_LIST_ROWS * row
}
/// menu_view.gd scroll_for: the offset that shows a row, moving as little as possible.
pub fn scroll_for(top: f64, height: f64, current: f64, area: f64) -> f64 {
    if top < current || height >= area {
        return top;
    }
    if top + height > current + area {
        return top + height - area;
    }
    current
}

/// Word-smart wrapping: break at spaces; a word wider than the line breaks by character.
pub fn wrap(text: &str, width: f64, measure: &dyn Fn(&str) -> f64) -> Vec<String> {
    let mut lines = Vec::new();
    let mut line = String::new();
    for word in text.split(' ').filter(|w| !w.is_empty()) {
        let candidate = if line.is_empty() {
            word.to_owned()
        } else {
            format!("{line} {word}")
        };
        if measure(&candidate) <= width {
            line = candidate;
            continue;
        }
        if !line.is_empty() {
            lines.push(std::mem::take(&mut line));
        }
        if measure(word) <= width {
            line = word.to_owned();
            continue;
        }
        for c in word.chars() {
            let mut next = line.clone();
            next.push(c);
            if !line.is_empty() && measure(&next) > width {
                lines.push(std::mem::take(&mut line));
                line.push(c);
            } else {
                line = next;
            }
        }
    }
    if !line.is_empty() || lines.is_empty() {
        lines.push(line);
    }
    lines
}

struct Row {
    label: Vec<String>,
    detail: Vec<String>,
    height: f64,
    enabled: bool,
}
/// Wrapped rows of one page at one width. Wrapping all levels takes about 50 ms on the
/// Pro, so every layout is kept: the overflow pass uses a second, narrower width.
type RowsKey = (Page, u64, usize);
/// Drawing of the menu model. Keeps the list scroll offset and the wrapped rows.
pub struct View {
    font: Font,
    font_size: [f64; 2],
    dense: bool,
    line: f64,
    scroll: f64,
    layouts: Vec<(RowsKey, Vec<Row>)>,
    rows: Vec<Row>,
    rows_key: Option<RowsKey>,
    /// Rows that fit in the list area at the last layout, for paging.
    pub visible_rows: usize,
}
impl View {
    pub fn new(font: Font, font_size: [f64; 2], dense: bool) -> Self {
        let line = font.cell()[1] + 2.0;
        Self {
            font,
            font_size,
            dense,
            line,
            scroll: 0.0,
            layouts: Vec::new(),
            rows: Vec::new(),
            rows_key: None,
            visible_rows: 1,
        }
    }
    fn measure(&self, text: &str) -> f64 {
        self.font.width(text, self.dense).unwrap_or(f64::INFINITY)
    }
    fn lines(&self, text: &str, width: f64) -> Vec<String> {
        if text.is_empty() {
            return Vec::new();
        }
        let shown = self.font.displayable(text);
        wrap(&shown, width, &|t| self.measure(t))
    }
    fn layout_rows(&mut self, model: &Model, width: f64) {
        let key = (model.page(), width.to_bits(), model.levels.len());
        if self.rows_key == Some(key) {
            return;
        }
        if let Some(previous) = self.rows_key.take() {
            let rows = std::mem::take(&mut self.rows);
            self.layouts.push((previous, rows));
        }
        if let Some(at) = self.layouts.iter().position(|(k, _)| *k == key) {
            self.rows = self.layouts.swap_remove(at).1;
            self.rows_key = Some(key);
            return;
        }
        let inner = width - GAP;
        self.rows = model
            .items()
            .iter()
            .map(|item| {
                let label = self.lines(&item.label, inner);
                let detail = self.lines(&item.detail, inner);
                let height = GAP + (label.len() + detail.len()) as f64 * self.line;
                Row {
                    label,
                    detail,
                    height,
                    enabled: item.enabled,
                }
            })
            .collect();
        self.rows_key = Some(key);
    }
    /// The menu over `container`: dim, panel, readouts, the scrolled list and its bar.
    pub fn emit(
        &mut self,
        model: &Model,
        container: [f64; 2],
        solid: usize,
        out: &mut Vec<Quad>,
    ) -> Result<(), String> {
        let Some(plan) = plan(container) else {
            return Ok(());
        };
        let s = plan.scale;
        let overlay = overlay_plan(s);
        let rect = |out: &mut Vec<Quad>, r: [f64; 4], color: [f32; 4]| {
            out.push(rect_quad(
                solid,
                [0.0, 0.0, 1.0, 1.0],
                [1.0, 1.0],
                r,
                Transform::default(),
                &overlay,
                color,
                &[],
            ));
        };
        rect(out, [0.0, 0.0, plan.space[0], plan.space[1]], DIM);
        let content_width = plan.size[0] - 2.0 * GAP;
        let title = self.lines(model.title(), content_width);
        let info = self.lines(&model.info(), content_width);
        let status = self.lines(&model.status, content_width);
        let hint = self.lines(model.hint(), content_width);
        let line = self.line;
        let block = |lines: &Vec<String>| lines.len() as f64 * line;
        let header = 2.0 * GAP
            + 2.0
            + [&title, &info, &status, &hint]
                .iter()
                .filter(|l| !l.is_empty())
                .map(|l| block(l) + GAP / 2.0)
                .sum::<f64>();
        // Rows at full width first; an overflowing list gives up the bar's width.
        self.layout_rows(model, content_width);
        let first_row = self.rows.first().map_or(2.0 * GAP + line, |r| r.height);
        let is_compact = compact(plan.size[1], header, first_row);
        // Column children outside the list: title, status, and (unless compact) info, hint.
        let column: Vec<&Vec<String>> = if is_compact {
            vec![&title, &status]
        } else {
            vec![&title, &info, &status, &hint]
        };
        let shown: Vec<&Vec<String>> = column.into_iter().filter(|l| !l.is_empty()).collect();
        let fixed = shown.iter().map(|l| block(l)).sum::<f64>() + GAP / 2.0 * shown.len() as f64;
        let rows_height = |rows: &[Row]| -> f64 { rows.iter().map(|r| r.height).sum() };
        let extra = |list_rows: f64| -> f64 {
            if is_compact {
                let mut h = list_rows;
                for l in [&info, &hint] {
                    if !l.is_empty() {
                        h += block(l) + GAP / 2.0;
                    }
                }
                h
            } else {
                list_rows
            }
        };
        let mut content = extra(rows_height(&self.rows));
        let mut height = plan.size[1].min(2.0 * GAP + fixed + content);
        let mut area = height - 2.0 * GAP - fixed;
        let mut list_width = content_width;
        if content > area + 0.5 {
            list_width = content_width - SCROLLBAR - GAP / 2.0;
            self.layout_rows(model, list_width);
            content = extra(rows_height(&self.rows));
            height = plan.size[1].min(2.0 * GAP + fixed + content);
            area = height - 2.0 * GAP - fixed;
        }
        let left = ((plan.space[0] - plan.size[0]) / 2.0).floor();
        let top = ((plan.space[1] - height) / 2.0).floor();
        // Panel: black fill, one-pixel white border inside the panel rectangle.
        rect(out, [left, top, plan.size[0], height], BLACK);
        let border = 1.0 / s;
        for r in [
            [left, top, plan.size[0], border],
            [left, top + height - border, plan.size[0], border],
            [left, top, border, height],
            [left + plan.size[0] - border, top, border, height],
        ] {
            rect(out, r, WHITE);
        }
        let x = left + GAP;
        let mut y = top + GAP;
        let font = &self.font;
        let line_height = self.line;
        let (font_size, dense) = (self.font_size, self.dense);
        let text = |out: &mut Vec<Quad>,
                    lines: &[String],
                    at: [f64; 2],
                    color: [f32; 4],
                    clip: Option<[f64; 2]>|
         -> Result<(), String> {
            for (i, line) in lines.iter().enumerate() {
                let line_top = at[1] + i as f64 * line_height;
                let mut glyphs = Vec::new();
                font.emit_colored(
                    line,
                    [at[0], line_top + 1.0],
                    s,
                    font_size,
                    dense,
                    color,
                    &mut glyphs,
                )?;
                for q in glyphs {
                    match clip {
                        Some([low, high]) => {
                            if let Some(q) = clip_y(q, low * s, high * s) {
                                out.push(q);
                            }
                        }
                        None => out.push(q),
                    }
                }
            }
            Ok(())
        };
        for (lines, color, in_column) in [
            (&title, WHITE, true),
            (&info, MUTED, !is_compact),
            (&status, WHITE, true),
        ] {
            if lines.is_empty() || !in_column {
                continue;
            }
            text(out, lines, [x, y], color, None)?;
            y += block(lines) + GAP / 2.0;
        }
        let list_top = y;
        let list_bottom = list_top + area.max(0.0);
        // Content positions (relative to the list top), including compact readouts.
        let mut cursor = 0.0;
        let info_at = if is_compact && !info.is_empty() {
            let at = cursor;
            cursor += block(&info) + GAP / 2.0;
            Some(at)
        } else {
            None
        };
        let mut row_tops = Vec::with_capacity(self.rows.len());
        for row in &self.rows {
            row_tops.push(cursor);
            cursor += row.height;
        }
        let hint_at = if is_compact && !hint.is_empty() {
            cursor += GAP / 2.0;
            Some(cursor)
        } else {
            None
        };
        let focused = model.focused();
        if let (Some(&row_top), Some(row)) = (row_tops.get(focused), self.rows.get(focused)) {
            // The first row also shows the compact info line above it.
            let shown_top = if focused == 0 { 0.0 } else { row_top };
            let bottom = row_top + row.height;
            self.scroll = scroll_for(shown_top, bottom - shown_top, self.scroll, area);
        }
        self.scroll = self.scroll.clamp(0.0, (content - area).max(0.0));
        let base = list_top - self.scroll;
        let clip = Some([list_top, list_bottom]);
        if let Some(at) = info_at {
            text(out, &info, [x, base + at], MUTED, clip)?;
        }
        let mut visible = 0usize;
        for (index, (row, row_top)) in self.rows.iter().zip(&row_tops).enumerate() {
            let y0 = base + row_top;
            let y1 = y0 + row.height;
            if y1 <= list_top || y0 >= list_bottom {
                continue;
            }
            if y0 >= list_top && y1 <= list_bottom {
                visible += 1;
            }
            let on = index == focused;
            if on {
                let quad = rect_quad(
                    solid,
                    [0.0, 0.0, 1.0, 1.0],
                    [1.0, 1.0],
                    [x, y0, list_width, row.height],
                    Transform::default(),
                    &overlay,
                    WHITE,
                    &[],
                );
                if let Some(q) = clip_y(quad, list_top * s, list_bottom * s) {
                    out.push(q);
                }
            }
            let enabled = row.enabled;
            let color = if on {
                BLACK
            } else if enabled {
                WHITE
            } else {
                MUTED
            };
            text(
                out,
                &row.label,
                [x + GAP / 2.0, y0 + GAP / 2.0],
                color,
                clip,
            )?;
            let detail_top = y0 + GAP / 2.0 + block(&row.label);
            text(out, &row.detail, [x + GAP / 2.0, detail_top], color, clip)?;
        }
        if let Some(at) = hint_at {
            text(out, &hint, [x, base + at], MUTED, clip)?;
        }
        self.visible_rows = visible.max(1);
        if content > area + 0.5 && area > 0.0 {
            // Scroll position bar: the list shows that more exists above or below.
            let bar = (area * area / content).max(GAP);
            let at = list_top + (area - bar) * (self.scroll / (content - area));
            rect(
                out,
                [x + content_width - SCROLLBAR, at, SCROLLBAR, bar],
                MUTED,
            );
        }
        if !is_compact && !hint.is_empty() {
            text(out, &hint, [x, list_bottom + GAP / 2.0], MUTED, None)?;
        }
        Ok(())
    }
}
/// Clip an axis-aligned quad (corners TL, TR, BR, BL) to screen rows `top..bottom`.
pub fn clip_y(mut q: Quad, top: f64, bottom: f64) -> Option<Quad> {
    let (y0, y1) = (q.corners[0][1] as f64, q.corners[2][1] as f64);
    if y1 <= top || y0 >= bottom || y1 <= y0 {
        return None;
    }
    let (v0, v1) = (q.uv[0][1] as f64, q.uv[2][1] as f64);
    let v_at = |y: f64| v0 + (v1 - v0) * (y - y0) / (y1 - y0);
    if y0 < top {
        let v = v_at(top) as f32;
        q.corners[0][1] = top as f32;
        q.corners[1][1] = top as f32;
        q.uv[0][1] = v;
        q.uv[1][1] = v;
    }
    if y1 > bottom {
        let v = v_at(bottom) as f32;
        q.corners[2][1] = bottom as f32;
        q.corners[3][1] = bottom as f32;
        q.uv[2][1] = v;
        q.uv[3][1] = v;
    }
    Some(q)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn entry(file: &str, ok: bool) -> Entry {
        Entry {
            file: file.into(),
            name: format!("Name {file}"),
            author: if ok { "Ann".into() } else { String::new() },
            ok,
            error: if ok {
                String::new()
            } else {
                "Not supported yet: e16".into()
            },
        }
    }
    #[test]
    fn plan_matches_menu_view_at_each_boundary() {
        let p = plan([640.0, 480.0]).unwrap();
        assert_eq!(
            p,
            Plan {
                scale: 1.0,
                space: [640.0, 480.0],
                size: [480.0, 448.0]
            }
        );
        // Scale 2 needs both axes at twice the reference; one pixel short stays at 1.
        assert_eq!(plan([1664.0, 896.0]).unwrap().scale, 2.0);
        assert_eq!(plan([1663.0, 896.0]).unwrap().scale, 1.0);
        assert_eq!(plan([1664.0, 895.0]).unwrap().scale, 1.0);
        assert_eq!(plan([100000.0, 100000.0]).unwrap().scale, MAX_SCALE);
        // Margins shrink before the panel: 160 px tall keeps 10 px margins.
        assert_eq!(plan([160.0, 160.0]).unwrap().size, [140.0, 140.0]);
        assert_eq!(plan([1.0, 1.0]).unwrap().size, [1.0, 1.0]);
        assert!(plan([0.0, 480.0]).is_none());
    }
    #[test]
    fn compact_and_scroll_rules() {
        assert!(!compact(200.0, 100.0, 25.0));
        assert!(compact(199.0, 100.0, 25.0));
        assert_eq!(scroll_for(10.0, 20.0, 50.0, 100.0), 10.0);
        assert_eq!(scroll_for(140.0, 20.0, 50.0, 100.0), 60.0);
        assert_eq!(scroll_for(60.0, 20.0, 50.0, 100.0), 50.0);
        assert_eq!(scroll_for(60.0, 200.0, 50.0, 100.0), 60.0);
    }
    #[test]
    fn model_pages_focus_and_refusals() {
        let mut m = Model::open(
            vec![entry("a", true), entry("b", false), entry("c", true)],
            Some("c"),
        );
        assert_eq!(m.page(), Page::Levels);
        assert_eq!(m.focused(), 2);
        m.step(1);
        assert_eq!(m.focused(), 0);
        m.step(-1);
        assert_eq!(m.focused(), 2);
        m.page_step(-1, 5);
        assert_eq!(m.focused(), 0);
        m.step(1);
        assert_eq!(m.confirm(), Request::None);
        assert_eq!(m.status, "Cannot open Name b: Not supported yet: e16");
        m.step(1);
        assert_eq!(m.confirm(), Request::Open(2));
        assert_eq!(m.info(), "3 levels, 2 playable");
        assert_eq!(m.items()[0].detail, "by Ann");
        m.back();
        assert_eq!(m.page(), Page::Start);
        assert!(m.status.is_empty());
        m.back();
        assert_eq!(m.page(), Page::Start);
        assert_eq!(m.confirm(), Request::None);
        assert_eq!(m.page(), Page::Levels);
        m.back();
        m.step(1);
        assert_eq!(m.confirm(), Request::Quit);
        let mut empty = Model::open(Vec::new(), None);
        assert_eq!(empty.page(), Page::Start);
        assert_eq!(empty.items().len(), 1);
        assert_eq!(empty.confirm(), Request::Quit);
    }
    #[test]
    fn wrap_breaks_words_and_long_words() {
        let measure = |t: &str| t.chars().count() as f64 * 10.0;
        assert_eq!(wrap("one two three", 70.0, &measure), ["one two", "three"]);
        assert_eq!(wrap("abcdefghij", 40.0, &measure), ["abcd", "efgh", "ij"]);
        assert_eq!(wrap("", 40.0, &measure), [""]);
        assert_eq!(wrap("a  b", 40.0, &measure), ["a b"]);
    }
    #[test]
    fn clip_keeps_texture_proportion() {
        let q = Quad {
            image: 0,
            corners: [[0.0, 0.0], [10.0, 0.0], [10.0, 20.0], [0.0, 20.0]],
            uv: [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]],
            color: [1.0; 4],
            palette: Vec::new(),
        };
        let c = clip_y(q.clone(), 5.0, 15.0).unwrap();
        assert_eq!(c.corners[0][1], 5.0);
        assert_eq!(c.uv[0][1], 0.25);
        assert_eq!(c.corners[2][1], 15.0);
        assert_eq!(c.uv[2][1], 0.75);
        assert!(clip_y(q.clone(), 20.0, 30.0).is_none());
        assert!(clip_y(q, -10.0, 0.0).is_none());
    }
}
