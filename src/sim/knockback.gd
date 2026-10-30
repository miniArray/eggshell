extends RefCounted
## The ordered knockBackTimer value tweens owned by armor and soft walkers.
## Eligibility (Global99/102) is independent of the lifetimes of these value tweens.
const SCHEDULED := 0
const PLAYING := 1
const WAITING_RELEASE := 2
const FINISHED_WAITING := 3
const ROW_FIELDS := [["from_vx", 0], ["remaining", 0], ["total", 0], ["phase", SCHEDULED]]
const COLLECTION_FIELDS := [["knock_tweens", ROW_FIELDS]]
const CODES := ["e11", "e23"]
const MAX_SPEED := 1024 * 60
const MAX_TICKS := 600  # Existing soft-walker timer validation limit.


static func start(entity: Dictionary, from_vx: int, ticks: int) -> void:
	assert(from_vx >= -MAX_SPEED and from_vx <= MAX_SPEED and ticks > 0 and ticks <= MAX_TICKS)
	# Value tweens permit repeated tags. Global98 does not Stop an existing tween.
	entity.knock_tweens.append(
		{"from_vx": from_vx, "remaining": ticks, "total": ticks, "phase": SCHEDULED}
	)
	entity.knock_active = 1


## A regular-event Stop releases every matching value tween before global tick2.
## Stop alone does not change beingKnockedBack. The wall events immediately restart.
static func stop(entity: Dictionary) -> void:
	var waiting := []
	var stopped := []
	for tween: Dictionary in entity.knock_tweens:
		if _waiting(tween):
			waiting.append(tween)
		else:
			tween.phase = WAITING_RELEASE
			stopped.append(tween)
	# Waiting order is release order, which need not be registration order.
	entity.knock_tweens = waiting + stopped


static func clear(entity: Dictionary) -> void:
	entity.knock_tweens.clear()
	entity.knock_active = 0


## TimelineManager ticks even the surviving value tweens of an ineligible owner.
## One pretick per simulation step, not one tick per mutable actor-table dispatch.
static func advance(state: Dictionary) -> void:
	for entity: Dictionary in state.entities:
		if entity.code not in CODES:
			continue
		if entity.status != 1:
			clear(entity)
			continue
		for tween: Dictionary in entity.knock_tweens:
			if not _waiting(tween):
				tween.phase = PLAYING
				tween.remaining = maxi(0, tween.remaining - 1)


## GetTweenValue checks active registration order, then waiting release order.
## A terminal zero remains active until its late finish queues that row's release.
static func value(entity: Dictionary) -> int:
	# PropertyTweens(value,true) concatenates active rows before waiting releases.
	for waiting in [false, true]:
		for tween: Dictionary in entity.knock_tweens:
			if _waiting(tween) == waiting:
				return tween.from_vx * tween.remaining / tween.total
	return 0


## A new regular-event start must not replace the same step's ordinary body motion.
## Stop alone can leave eligibility true with no active rows; that is not a new start.
static func deferred(entity: Dictionary) -> bool:
	var scheduled := false
	for tween: Dictionary in entity.knock_tweens:
		if tween.phase == PLAYING:
			return false
		if tween.phase == SCHEDULED:
			scheduled = true
	return scheduled


static func pending(entity: Dictionary) -> bool:
	return entity.knock_tweens.any(
		func(tween: Dictionary) -> bool: return not _waiting(tween) and tween.remaining == 0
	)


## Behavior tick2 releases old waiting rows before TimelineManager's callbacks.
## A natural callback clears eligibility and moves only its argument to waiting;
## that new waiting zero survives until the following behavior tick2 release.
static func finish(entity: Dictionary) -> void:
	if entity.status != 1:
		clear(entity)
		return
	var changed := false
	for tween: Dictionary in entity.knock_tweens:
		if _waiting(tween) or tween.remaining == 0:
			changed = true
	if not changed:
		return
	var active := []
	var completed := []
	for tween: Dictionary in entity.knock_tweens:
		if _waiting(tween):
			continue
		if tween.remaining == 0:
			entity.knock_active = 0
			tween.phase = FINISHED_WAITING
			completed.append(tween)
		else:
			active.append(tween)
	entity.knock_tweens = active + completed


static func _waiting(tween: Dictionary) -> bool:
	return tween.phase in [WAITING_RELEASE, FINISHED_WAITING]


static func valid(entity: Dictionary) -> bool:
	if entity.knock_active not in [0, 1]:
		return false
	for tween: Dictionary in entity.knock_tweens:
		if (
			tween.from_vx < -MAX_SPEED
			or tween.from_vx > MAX_SPEED
			or tween.total < 1
			or tween.total > MAX_TICKS
			or tween.remaining < 0
			or tween.remaining > tween.total
			or tween.phase not in [SCHEDULED, PLAYING, WAITING_RELEASE, FINISHED_WAITING]
			or (tween.phase == SCHEDULED and tween.remaining != tween.total)
			or (tween.phase == FINISHED_WAITING and tween.remaining != 0)
		):
			return false
	return true
