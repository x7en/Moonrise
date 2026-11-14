class_name Inventory
extends RefCounted
## Stack-based resource inventory used for both the player's bag (capped) and house stockpile.

const RESOURCE_KEYS: Array[String] = [
	"plank",
	"scrap",
	"arrow",
	"trap_spike",
	"trap_snare",
	"trap_lure",
]

var capacity: int = -1  # -1 means unlimited (stockpile)
var stacks: Dictionary = {}


func _init(p_capacity: int = -1) -> void:
	capacity = p_capacity
	clear()


func clear() -> void:
	stacks.clear()
	for key in RESOURCE_KEYS:
		stacks[key] = 0


func count(item_id: String) -> int:
	return int(stacks.get(item_id, 0))


## Returns total resource weight currently carried (planks + scrap count toward bag capacity).
func used_capacity() -> int:
	return count("plank") + count("scrap")


func remaining_capacity() -> int:
	if capacity < 0:
		return 999999
	return maxi(0, capacity - used_capacity())


## Adds up to amount units (respecting capacity for resource items) and returns amount added.
func add(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var to_add: int = amount
	if capacity >= 0 and (item_id == "plank" or item_id == "scrap"):
		to_add = mini(amount, remaining_capacity())
	if to_add <= 0:
		return 0
	stacks[item_id] = count(item_id) + to_add
	return to_add


func remove(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var have: int = count(item_id)
	var taken: int = mini(have, amount)
	stacks[item_id] = have - taken
	return taken


func can_afford(cost: Dictionary, extra: Inventory = null) -> bool:
	for key in cost.keys():
		var item_id: String = String(key)
		var need: int = int(cost[key])
		var have: int = count(item_id) + (extra.count(item_id) if extra != null else 0)
		if have < need:
			return false
	return true


func missing_for(cost: Dictionary, extra: Inventory = null) -> Dictionary:
	var missing: Dictionary = {}
	for key in cost.keys():
		var item_id: String = String(key)
		var need: int = int(cost[key])
		var have: int = count(item_id) + (extra.count(item_id) if extra != null else 0)
		if have < need:
			missing[item_id] = need - have
	return missing


func spend(cost: Dictionary, extra: Inventory = null) -> bool:
	if not can_afford(cost, extra):
		return false
	for key in cost.keys():
		var item_id: String = String(key)
		var need: int = int(cost[key])
		var from_self: int = remove(item_id, need)
		var rem: int = need - from_self
		if rem > 0 and extra != null:
			extra.remove(item_id, rem)
	return true


## Transfers planks and scrap into another Inventory and returns a summary dictionary.
func transfer_resources_to(target: Inventory) -> Dictionary:
	var moved: Dictionary = {"plank": 0, "scrap": 0}
	for res_id in ["plank", "scrap"]:
		var amt: int = count(res_id)
		if amt > 0:
			var added: int = target.add(res_id, amt)
			remove(res_id, added)
			moved[res_id] = added
	return moved


func total_resources() -> int:
	return count("plank") + count("scrap")


func to_dict() -> Dictionary:
	return stacks.duplicate(true)


func from_dict(data: Dictionary) -> void:
	clear()
	for key in data.keys():
		stacks[String(key)] = maxi(0, int(data[key]))


static func format_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	if int(cost.get("plank", 0)) > 0:
		var n: int = int(cost["plank"])
		parts.append("%d plank%s" % [n, "" if n == 1 else "s"])
	if int(cost.get("scrap", 0)) > 0:
		parts.append("%d scrap" % int(cost["scrap"]))
	return " + ".join(parts)
