extends Camera3D

@export var target_path: NodePath
@export var follow_offset: Vector3 = Vector3(0.0, 3.6, -7.8)
@export var look_offset: Vector3 = Vector3(0.0, 1.5, 1.0)
@export var position_smooth: float = 6.0

var _target: Node3D


func _ready() -> void:
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node3D


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var desired_pos: Vector3 = _target.global_transform * follow_offset
	global_position = global_position.lerp(desired_pos, 1.0 - exp(-position_smooth * delta))
	var look_pos: Vector3 = _target.global_transform * look_offset
	if global_position.distance_squared_to(look_pos) > 0.01:
		look_at(look_pos, Vector3.UP)
