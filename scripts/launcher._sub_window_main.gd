extends Window

var Main : Control
var Graphics : Control
var Controls : Control
var Sound : Control


func _init() -> void:
	pass

func _ready() -> void:
	Main = $Tab_Container/Main
	Graphics = $Tab_Container/Graphics
	Controls = $Tab_Container/Controls
	Sound = $Tab_Container/Sound

func _process(_delta) -> void:
	pass


func _on_close_requested() -> void:
	self.queue_free()
