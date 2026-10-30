//! Deliberate presentation-policy boundaries, not legal-course gameplay evidence.
use super::{actor_visible, plant_head};
use crate::{
    actors::{Actor, ActorKind},
    body::Body,
    entity::{Entity, Kind, Origin},
    Position,
};
#[test]
#[ignore = "requires independent original inactive visibility policy cases on aka"]
fn original_inactive_visibility_policy() {
    let path = std::env::var("CORE_INACTIVE_POLICY").unwrap();
    let cases: Vec<serde_json::Value> =
        serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    assert_eq!(cases.len(), 320);
    for case in &cases {
        let code = case["code"].as_str().unwrap();
        let kind = match code {
            "e1" => ActorKind::Walker,
            "e2" => ActorKind::Flyer,
            "e3" => ActorKind::Flower,
            "e5" => ActorKind::Plant,
            "e35" => ActorKind::Stilt,
            _ => panic!("unexpected oracle case"),
        };
        let mut actor = Actor::new(kind, 0, 0, Position::default());
        actor.held = case["held"].as_i64().unwrap();
        actor.hidden = case["hidden"].as_i64().unwrap();
        if kind == ActorKind::Plant {
            actor.head_dx = 3600;
            actor.head_size = 10;
            actor.mode = 2;
        }
        let mut entity = Entity::dynamic(1, Kind::Walker(actor), Body::default(), -1, 8);
        entity.origin = if case["source_index"].as_i64().unwrap() >= 0 {
            Origin::Placed(0)
        } else {
            Origin::Runtime(1)
        };
        entity.status = case["status"].as_i64().unwrap();
        entity.can_respawn = case["can_respawn"].as_i64().unwrap();
        assert_eq!(
            actor_visible(&entity),
            case["visible"].as_bool().unwrap(),
            "case={case}"
        );
        if case["inactive"].as_bool().unwrap() || !case["visible"].as_bool().unwrap() {
            assert!(plant_head(&entity, None, 0)
                .iter()
                .all(|head| !head.picture.visible));
        }
    }
    println!("INACTIVE_POLICY_DONE cases={} original_static_policy=true session_states_edited=false boundary_only=true inactive_heads_hidden=true",cases.len());
}
