class_name Bag
extends RefCounted

const RESOURCE_KEYS: Array[String] = [
	"plank",
	"scrap",
	"arrow",
	"trap_spike",
	"trap_snare",
	"trap_lure",
]

var capacity: int = -1  # -1 = unlimited (stockpile)
var stacks: Dictionary = {}


func _init(cap: int = -1) -> void:
	capacity = cap
	clear()


func clear() -> void:
	stacks.clear()
	for key in RESOURCE_KEYS:
		stacks[key] = 0


func count(item_id: String) -> int:
	return int(stacks.get(item_id, 0))


# only planks and scrap eat up bag space, arrows/traps are free
func used_capacity() -> int:
	return count("plank") + count("scrap")


func remaining_capacity() -> int:
	if capacity < 0:
		return 999999
	return maxi(0, capacity - used_capacity())


func add(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0

	var to_add := amount
	if capacity >= 0 and (item_id == "plank" or item_id == "scrap"):
		to_add = mini(amount, remaining_capacity())

	if to_add <= 0:
		return 0

	stacks[item_id] = count(item_id) + to_add
	return to_add


func remove(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0

	var have := count(item_id)
	var taken := mini(have, amount)
	stacks[item_id] = have - taken
	return taken


func can_afford(cost: Dictionary, extra: Bag = null) -> bool:
	for key in cost.keys():
		var item_id := String(key)
		var need := int(cost[key])
		var have := count(item_id) + (extra.count(item_id) if extra != null else 0)
		if have < need:
			return false
	return true


func spend(cost: Dictionary, extra: Bag = null) -> bool:
	if not can_afford(cost, extra):
		return false

	for key in cost.keys():
		var item_id := String(key)
		var need := int(cost[key])
		var from_self := remove(item_id, need)
		var rem := need - from_self
		if rem > 0 and extra != null:
			extra.remove(item_id, rem)
	return true


func transfer_resources_to(target: Bag) -> Dictionary:
	var moved = {"plank": 0, "scrap": 0}
	for res_id in ["plank", "scrap"]:
		var amt := count(res_id)
		if amt > 0:
			var added := target.add(res_id, amt)
			remove(res_id, added)
			moved[res_id] = added
	return moved


func to_dict() -> Dictionary:
	return stacks.duplicate(true)


func from_dict(data: Dictionary) -> void:
	clear()
	for key in data.keys():
		stacks[String(key)] = maxi(0, int(data[key]))


static func format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	if int(cost.get("plank", 0)) > 0:
		var n := int(cost["plank"])
		parts.append("%d plank%s" % [n, "" if n == 1 else "s"])
	if int(cost.get("scrap", 0)) > 0:
		parts.append("%d scrap" % int(cost["scrap"]))
	return " + ".join(parts)
