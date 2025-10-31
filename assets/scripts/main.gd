extends Node2D

@onready var gesture_recognizer = GestureRecognizer.new()
@onready var draw_line = Line2D.new()

var is_drawing = false
var current_stroke = []

func _ready():
	add_child(gesture_recognizer)
	
	# Setup visual feedback line
	add_child(draw_line)
	draw_line.width = 5
	draw_line.default_color = Color.WHITE
	draw_line.joint_mode = Line2D.LINE_JOINT_ROUND
	draw_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	draw_line.end_cap_mode = Line2D.LINE_CAP_ROUND

func _input(event):
	# Handle touch input
	if event is InputEventScreenTouch:
		if event.pressed:
			start_drawing(event.position)
		else:
			finish_drawing()
	
	elif event is InputEventScreenDrag:
		if is_drawing:
			add_point(event.position)
	
	# Handle mouse input
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				start_drawing(event.position)
			else:
				finish_drawing()
	
	elif event is InputEventMouseMotion:
		if is_drawing:
			add_point(event.position)

func start_drawing(pos: Vector2):
	is_drawing = true
	current_stroke.clear()
	draw_line.clear_points()
	add_point(pos)

func add_point(pos: Vector2):
	current_stroke.append(pos)
	draw_line.add_point(pos)

func finish_drawing():
	if not is_drawing:
		return
	
	is_drawing = false
	
	if current_stroke.size() < 5:
		clear_drawing()
		return
	
	# Recognize the gesture
	var result = gesture_recognizer.recognize(current_stroke)
	
	print("Recognized: %s (score: %.2f)" % [result.name, result.score])
	
	if result.name != "unknown":
		on_gesture_recognized(result.name, result.score)
	else:
		on_gesture_failed()
	
	# Clear after a short delay for feedback
	await get_tree().create_timer(0.3).timeout
	clear_drawing()

func clear_drawing():
	current_stroke.clear()
	draw_line.clear_points()

# Game-specific callbacks
func on_gesture_recognized(gesture_name: String, score: float):
	print("Success! Drew a %s with %.0f%% accuracy" % [gesture_name, score * 100])
	# Add your rhythm game logic here:
	# - Check if it matches the required pattern
	# - Check if timing is correct
	# - Award points based on accuracy
	# - Play success feedback

func on_gesture_failed():
	print("Pattern not recognized!")
	# Add failure feedback here
