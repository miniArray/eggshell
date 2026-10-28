extends RefCounted
## Fire and ice: the element kinds, the player's element ammunition and the
## reaction flags that object types declare. This file loads nothing else.

const NONE := 0
const FIRE := 1
const ICE := 2

## Ammunition kinds saved in `move_ammo`. They equal the movement module's
## SEED, HEAT and COLD values; the element tests check that they stay equal.
const AMMO_SEED := 1
const AMMO_FIRE := 2
const AMMO_ICE := 3

## Shots loaded by the three sizes of an element melon, in form order.
const MELON_SHOTS := [3, 1, 9]
const FIRST_FIRE_MELON := 3
const FIRST_ICE_MELON := 6
const LAST_MELON := 8
## Shots loaded by swallowing a burning or a cold bubble.
const BUBBLE_SHOTS := 3

## Reaction flags in a type's `ELEMENT_REACTIONS` constant. Fire and ice shots
## only strike types that declare a nonzero value.
const BURNS := 1  ## Fire defeats it.
const FREEZES := 2  ## Ice freezes it.
const THAWS := 4  ## A frozen body thaws by itself.
const ANCHORED := 8  ## A frozen body keeps its place instead of falling.
const LIGHTS := 16  ## Fire and ice light or put it out (no defeat, no freeze).
const OPENS := 32  ## Fire and ice open it at once.

## A thawing body shakes for its last second of ice.
const THAW_TICKS := 480
const SHAKE_TICKS := 60


## The element that one ammunition kind fires, or NONE.
static func of_ammo(ammo: int) -> int:
	if ammo == AMMO_FIRE:
		return FIRE
	if ammo == AMMO_ICE:
		return ICE
	return NONE


## The ammunition kind that fires one element, or 0.
static func ammo_of(element: int) -> int:
	if element == FIRE:
		return AMMO_FIRE
	if element == ICE:
		return AMMO_ICE
	return 0


## The element of a melon form, or NONE for the plain seed forms.
static func melon_element(form: int) -> int:
	if form >= FIRST_ICE_MELON and form <= LAST_MELON:
		return ICE
	if form >= FIRST_FIRE_MELON and form < FIRST_ICE_MELON:
		return FIRE
	return NONE


## `[ammunition kind, shots]` loaded by an element melon form, or [] for other forms.
static func melon_ammo(form: int) -> Array:
	var element := melon_element(form)
	if element == NONE:
		return []
	var first := FIRST_FIRE_MELON if element == FIRE else FIRST_ICE_MELON
	return [ammo_of(element), MELON_SHOTS[form - first]]


## `[ammunition kind, shots]` loaded by swallowing a bubble of one element.
static func bubble_ammo(element: int) -> Array:
	return [ammo_of(element), BUBBLE_SHOTS] if element in [FIRE, ICE] else []


## The element that puts out a lamp lit by the other one.
static func opposite(element: int) -> int:
	return ICE if element == FIRE else (FIRE if element == ICE else NONE)
