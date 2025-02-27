extends Window

func _init() -> void:
	pass

func _ready() -> void:
	pass

func _process(delta) -> void:
	pass


func _on_close_requested() -> void:
	self.queue_free()
