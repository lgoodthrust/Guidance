extends Node

var launcher = Node # FOR DATA SHARE

func _ready() -> void:
	launcher = get_node(".").get_parent() # FOR DATA SHARE


func LAUCNHER_CHILD_SHARE_SET(key, data): # FOR DATA SHARE
	if launcher:
		launcher.LAUCNHER_CHILD_SHARED_DATA[key] = [data]
		launcher.LAUCNHER_CHILD_SHARED_DATA_CALL()

func LAUCNHER_CHILD_SHARE_GET(key): # FOR DATA SHARE
	if launcher:
		var data = launcher.LAUCNHER_CHILD_SHARED_DATA[key]
		return data
