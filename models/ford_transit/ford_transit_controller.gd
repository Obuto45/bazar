extends VehicleBody3D

@export var max_engine_force: float = 3400.0
@export var max_brake_force: float = 90.0
@export var max_steer_angle: float = 0.52
@export var steer_speed: float = 3.2
@export var max_speed_kmh: float = 110.0

@onready var headlight_left: SpotLight3D = $HeadlightLeft
@onready var headlight_right: SpotLight3D = $HeadlightRight

var _lights_on: bool = true


func _ready() -> void:
	_update_lights()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_lights"):
		_lights_on = not _lights_on
		_update_lights()


func _physics_process(delta: float) -> void:
	var steer_input: float = Input.get_axis("steer_right", "steer_left")
	steering = move_toward(steering, steer_input * max_steer_angle, steer_speed * delta)

	var throttle_input: float = Input.get_axis("move_back", "move_forward")
	var speed_kmh: float = linear_velocity.length() * 3.6

	if Input.is_action_pressed("handbrake"):
		engine_force = 0.0
		brake = max_brake_force * 1.4
	elif absf(throttle_input) > 0.01:
		var forward_speed: float = linear_velocity.dot(global_transform.basis.z)
		var reversing_against_motion: bool = (throttle_input > 0.0 and forward_speed < -0.5) or (throttle_input < 0.0 and forward_speed > 0.5)
		if reversing_against_motion:
			engine_force = 0.0
			brake = max_brake_force
		elif speed_kmh < max_speed_kmh:
			brake = 0.0
			engine_force = throttle_input * max_engine_force
		else:
			engine_force = 0.0
			brake = 0.0
	else:
		engine_force = 0.0
		brake = 6.0


func _update_lights() -> void:
	if headlight_left:
		headlight_left.visible = _lights_on
	if headlight_right:
		headlight_right.visible = _lights_on
