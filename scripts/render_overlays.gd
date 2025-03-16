class_name render_overlay

extends RefCounted

var tpos: Vector2 = Vector2(0, 0)
var FOV = 45

var w_size = DisplayServer.window_get_size()
var w_center = w_size/2.0

var radius = 45.0
var filled = false
var thickness = 2.0
var color = Color8(0, 255, 0, 255)
var aa = true

var wd_pos = w_center*( tpos/FOV + Vector2(1,1))
var r_size = Vector2(radius, radius)
var r_shape = Rect2(wd_pos-(r_size / 2.0), r_size)

func draw_target_redic(node: Node, tpos, FOV, radius, distance, color):
	node.queue_redraw()
	node.draw_rect(r_shape, color, filled, thickness, aa)
