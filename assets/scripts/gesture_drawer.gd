extends Node2D

# UI elements
var draw_line: Line2D
var label: Label
var name_input: LineEdit
var save_button: Button
var clear_button: Button
var status_label: Label

var is_drawing = false
var current_stroke = []

func _ready():
	# Setup drawing line
	draw_line = Line2D.new()
	add_child(draw_line)
	draw_line.width = 5
	draw_line.default_color = Color.CYAN
	draw_line.joint_mode = Line2D.LINE_JOINT_ROUND
	draw_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	draw_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	# Setup UI panel
	var panel = Panel.new()
	add_child(panel)
	panel.position = Vector2(10, 10)
	panel.size = Vector2(400, 200)
	
	# Title label
	label = Label.new()
	panel.add_child(label)
	label.position = Vector2(10, 10)
	label.add_theme_font_size_override("font_size", 20)
	label.text = "TEMPLATE EDITOR"
	
	# Instructions
	var instructions = Label.new()
	panel.add_child(instructions)
	instructions.position = Vector2(10, 40)
	instructions.text = "Draw your gesture, then name it and save"
	
	# Name input field
	var name_label = Label.new()
	panel.add_child(name_label)
	name_label.position = Vector2(10, 70)
	name_label.text = "Template name:"
	
	name_input = LineEdit.new()
	panel.add_child(name_input)
	name_input.position = Vector2(10, 95)
	name_input.size = Vector2(380, 30)
	name_input.placeholder_text = "e.g., line_right, circle_cw, heart"
	name_input.text_submitted.connect(_on_name_submitted)
	
	# Save button
	save_button = Button.new()
	panel.add_child(save_button)
	save_button.position = Vector2(10, 135)
	save_button.size = Vector2(180, 40)
	save_button.text = "Save Template"
	save_button.pressed.connect(_on_save_pressed)
	save_button.disabled = true
	
	# Clear button
	clear_button = Button.new()
	panel.add_child(clear_button)
	clear_button.position = Vector2(200, 135)
	clear_button.size = Vector2(180, 40)
	clear_button.text = "Clear Drawing"
	clear_button.pressed.connect(clear_drawing)
	
	# Status label
	status_label = Label.new()
	panel.add_child(status_label)
	status_label.position = Vector2(10, 180)
	status_label.add_theme_color_override("font_color", Color.GREEN)

func _input(event):
	# Mouse input
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				start_drawing(event.position)
			else:
				finish_drawing()
	
	elif event is InputEventMouseMotion:
		if is_drawing:
			add_point(event.position)
	
	# Touch input
	elif event is InputEventScreenTouch:
		if event.pressed:
			start_drawing(event.position)
		else:
			finish_drawing()
	
	elif event is InputEventScreenDrag:
		if is_drawing:
			add_point(event.position)

func start_drawing(pos: Vector2):
	is_drawing = true
	current_stroke.clear()
	draw_line.clear_points()
	add_point(pos)
	status_label.text = ""

func add_point(pos: Vector2):
	current_stroke.append(pos)
	draw_line.add_point(pos)

func finish_drawing():
	if not is_drawing:
		return
	
	is_drawing = false
	
	if current_stroke.size() < 5:
		status_label.text = "Gesture too short, draw again"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		clear_drawing()
		return
	
	status_label.text = "Gesture captured! Enter name and save"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	save_button.disabled = false
	name_input.grab_focus()

func clear_drawing():
	current_stroke.clear()
	draw_line.clear_points()
	save_button.disabled = true
	status_label.text = ""

func _on_name_submitted(text: String):
	if text != "" and current_stroke.size() >= 5:
		save_template()

func _on_save_pressed():
	if name_input.text == "":
		status_label.text = "Please enter a template name!"
		status_label.add_theme_color_override("font_color", Color.RED)
		name_input.grab_focus()
		return
	
	save_template()

func save_template():
	var template_name = name_input.text.strip_edges()
	
	if template_name == "":
		status_label.text = "Please enter a template name!"
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	
	if current_stroke.size() < 5:
		status_label.text = "No gesture to save!"
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	
	# Normalize the stroke before saving
	var normalized_stroke = normalize_stroke(current_stroke)
	
	# Convert to code format
	var code = "func create_%s_template() -> Array:\n\treturn [\n" % template_name.to_lower()
	
	for i in range(normalized_stroke.size()):
		var p = normalized_stroke[i]
		code += "\t\tVector2(%.1f, %.1f)" % [p.x, p.y]
		if i < normalized_stroke.size() - 1:
			code += ",\n"
		else:
			code += "\n"
	
	code += "\t]"
	
	print("\n========================================")
	print("=== TEMPLATE CODE FOR: %s ===" % template_name)
	print("========================================")
	print(code)
	print("\n=== ADD TO gesture_recognizer.gd ===")
	print("In _ready():")
	print('add_template("%s", create_%s_template())' % [template_name, template_name.to_lower()])
	print("========================================\n")
	
	# Save to file
	var file_path = "res://templates/template_%s.txt" % template_name.to_lower()
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(code)
		file.close()
		status_label.text = "Saved to: templates/template_%s.txt" % template_name.to_lower()
		status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		status_label.text = "Saved! (Check console for code)"
		status_label.add_theme_color_override("font_color", Color.GREEN)
	
	# Clear for next template
	await get_tree().create_timer(2.0).timeout
	clear_drawing()
	name_input.text = ""
	status_label.text = "Ready for next template"

func normalize_stroke(points: Array) -> Array:
	if points.size() < 2:
		return points
	
	var normalized = []
	
	# Step 1: Snap near-horizontal and near-vertical lines
	var snapped = snap_to_axes(points)
	
	# Step 2: Simplify by removing redundant points
	var simplified = simplify_points(snapped)
	
	# Step 3: Smooth out small jitters
	var smoothed = smooth_points(simplified)
	
	return smoothed

func snap_to_axes(points: Array) -> Array:
	# Calculate overall direction to determine if this is a line
	var start = points[0]
	var end = points[-1]
	var delta = end - start
	var length = delta.length()
	
	if length < 10:  # Too short to normalize
		return points
	
	var angle = abs(rad_to_deg(delta.angle()))
	var snapped = []
	
	# Check if this is roughly horizontal or vertical
	var is_horizontal = (angle < 15 or angle > 165) or (angle > 75 and angle < 105)
	var is_vertical = (angle > 75 and angle < 105) or (angle > 255 and angle < 285)
	
	for i in range(points.size()):
		var p = points[i]
		var new_p = p
		
		# Snap Y coordinate if horizontal line
		if angle < 15 or angle > 165:
			var avg_y = 0.0
			for point in points:
				avg_y += point.y
			avg_y /= points.size()
			new_p.y = avg_y
		
		# Snap X coordinate if vertical line
		elif angle > 80 and angle < 100:
			var avg_x = 0.0
			for point in points:
				avg_x += point.x
			avg_x /= points.size()
			new_p.x = avg_x
		
		snapped.append(new_p)
	
	return snapped

func simplify_points(points: Array, tolerance: float = 5.0) -> Array:
	# Douglas-Peucker algorithm for line simplification
	if points.size() < 3:
		return points
	
	var dmax = 0.0
	var index = 0
	var end = points.size() - 1
	
	for i in range(1, end):
		var d = perpendicular_distance(points[i], points[0], points[end])
		if d > dmax:
			index = i
			dmax = d
	
	if dmax > tolerance:
		var rec1 = simplify_points(points.slice(0, index + 1), tolerance)
		var rec2 = simplify_points(points.slice(index, end + 1), tolerance)
		
		var result = rec1.slice(0, rec1.size() - 1)
		result.append_array(rec2)
		return result
	else:
		return [points[0], points[end]]

func perpendicular_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var dx = line_end.x - line_start.x
	var dy = line_end.y - line_start.y
	
	if dx == 0 and dy == 0:
		return point.distance_to(line_start)
	
	var t = ((point.x - line_start.x) * dx + (point.y - line_start.y) * dy) / (dx * dx + dy * dy)
	t = clamp(t, 0.0, 1.0)
	
	var projection = Vector2(line_start.x + t * dx, line_start.y + t * dy)
	return point.distance_to(projection)

func smooth_points(points: Array, window: int = 3) -> Array:
	if points.size() < window:
		return points
	
	var smoothed = []
	
	for i in range(points.size()):
		var sum = Vector2.ZERO
		var count = 0
		
		for j in range(-window, window + 1):
			var idx = i + j
			if idx >= 0 and idx < points.size():
				sum += points[idx]
				count += 1
		
		smoothed.append(sum / count)
	
	return smoothed
