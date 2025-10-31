extends Node

class_name GestureRecognizer

# Configuration
const NUM_POINTS = 64
const SQUARE_SIZE = 250.0
const RECOGNITION_THRESHOLD = 0.6  # Lower = more strict (0-1)

var templates = {}

func _ready():
	# Define your gesture templates here
	# Each template is an array of Vector2 points
	# Templates are now directional - orientation matters!
	add_template("circle_cw", create_circle_template(true))
	add_template("circle_ccw", create_circle_template(false))
	add_template("line_right", create_line_template(Vector2.RIGHT))
	add_template("line_left", create_line_template(Vector2.LEFT))
	add_template("line_down", create_line_template(Vector2.DOWN))
	add_template("line_up", create_line_template(Vector2.UP))
	add_template("triangle", create_triangle_template())
	add_template("square", create_square_template())
	add_template("zigzag_right", create_zigzag_template(1))
	add_template("zigzag_left", create_zigzag_template(-1))
	# Add more patterns as needed

func add_template(name: String, points: Array):
	templates[name] = process_points(points)

func recognize(points: Array) -> Dictionary:
	if points.size() < 5:
		return {"name": "unknown", "score": 0.0}
	
	var processed = process_points(points)
	var best_match = ""
	var best_score = INF
	var all_scores = {}  # Debug: track all scores
	
	for template_name in templates:
		var score = distance_at_best_angle(
			processed, 
			templates[template_name],
			-15.0,  # Reduced rotation range for directional gestures
			15.0, 
			2.0
		)
		
		all_scores[template_name] = score  # Debug: store score
		
		if score < best_score:
			best_score = score
			best_match = template_name
	
	# Debug output
	print("\n=== Recognition Results ===")
	for template_name in all_scores:
		var norm_score = 1.0 - (all_scores[template_name] / (0.5 * sqrt(SQUARE_SIZE * SQUARE_SIZE + SQUARE_SIZE * SQUARE_SIZE)))
		print("%s: %.3f (raw: %.2f)" % [template_name, norm_score, all_scores[template_name]])
	
	# Normalize score to 0-1 range (1 = perfect match)
	var normalized_score = 1.0 - (best_score / (0.5 * sqrt(SQUARE_SIZE * SQUARE_SIZE + SQUARE_SIZE * SQUARE_SIZE)))
	
	print("Best match: %s (%.3f)" % [best_match, normalized_score])
	print("Threshold: %.3f" % RECOGNITION_THRESHOLD)
	
	if normalized_score >= RECOGNITION_THRESHOLD:
		return {"name": best_match, "score": normalized_score}
	else:
		return {"name": "unknown", "score": normalized_score}

# Core $1 algorithm functions
func process_points(points: Array) -> Array:
	var resampled = resample(points, NUM_POINTS)
	# Skip rotation to preserve directional information
	var scaled = scale_to_square(resampled, SQUARE_SIZE)
	var translated = translate_to_origin(scaled)
	return translated

func resample(points: Array, n: int) -> Array:
	var interval = path_length(points) / (n - 1)
	var distance = 0.0
	var new_points = [points[0]]
	
	var i = 1
	while i < points.size():
		var d = points[i - 1].distance_to(points[i])
		
		if distance + d >= interval:
			var qx = points[i - 1].x + ((interval - distance) / d) * (points[i].x - points[i - 1].x)
			var qy = points[i - 1].y + ((interval - distance) / d) * (points[i].y - points[i - 1].y)
			var q = Vector2(qx, qy)
			new_points.append(q)
			points.insert(i, q)
			distance = 0.0
		else:
			distance += d
		i += 1
	
	if new_points.size() == n - 1:
		new_points.append(points[-1])
	
	return new_points

func rotate_to_zero(points: Array) -> Array:
	var centroid = get_centroid(points)
	var angle = atan2(centroid.y - points[0].y, centroid.x - points[0].x)
	return rotate_by(points, -angle)

func rotate_by(points: Array, angle: float) -> Array:
	var centroid = get_centroid(points)
	var cos_angle = cos(angle)
	var sin_angle = sin(angle)
	var new_points = []
	
	for p in points:
		var qx = (p.x - centroid.x) * cos_angle - (p.y - centroid.y) * sin_angle + centroid.x
		var qy = (p.x - centroid.x) * sin_angle + (p.y - centroid.y) * cos_angle + centroid.y
		new_points.append(Vector2(qx, qy))
	
	return new_points

func scale_to_square(points: Array, size: float) -> Array:
	var bounds = get_bounding_box(points)
	var new_points = []
	
	for p in points:
		var qx = p.x * (size / bounds.x)
		var qy = p.y * (size / bounds.y)
		new_points.append(Vector2(qx, qy))
	
	return new_points

func translate_to_origin(points: Array) -> Array:
	var centroid = get_centroid(points)
	var new_points = []
	
	for p in points:
		new_points.append(Vector2(p.x - centroid.x, p.y - centroid.y))
	
	return new_points

func distance_at_best_angle(points: Array, template: Array, angle_a: float, angle_b: float, threshold: float) -> float:
	var phi = 0.5 * (-1.0 + sqrt(5.0))  # Golden ratio
	var x1 = phi * angle_a + (1.0 - phi) * angle_b
	var f1 = distance_at_angle(points, template, deg_to_rad(x1))
	var x2 = (1.0 - phi) * angle_a + phi * angle_b
	var f2 = distance_at_angle(points, template, deg_to_rad(x2))
	
	while abs(angle_b - angle_a) > threshold:
		if f1 < f2:
			angle_b = x2
			x2 = x1
			f2 = f1
			x1 = phi * angle_a + (1.0 - phi) * angle_b
			f1 = distance_at_angle(points, template, deg_to_rad(x1))
		else:
			angle_a = x1
			x1 = x2
			f1 = f2
			x2 = (1.0 - phi) * angle_a + phi * angle_b
			f2 = distance_at_angle(points, template, deg_to_rad(x2))
	
	return min(f1, f2)

func distance_at_angle(points: Array, template: Array, angle: float) -> float:
	var rotated = rotate_by(points, angle)
	return path_distance(rotated, template)

func path_distance(points1: Array, points2: Array) -> float:
	var distance = 0.0
	for i in range(points1.size()):
		distance += points1[i].distance_to(points2[i])
	return distance / points1.size()

# Helper functions
func path_length(points: Array) -> float:
	var length = 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length

func get_centroid(points: Array) -> Vector2:
	var sum = Vector2.ZERO
	for p in points:
		sum += p
	return sum / points.size()

func get_bounding_box(points: Array) -> Vector2:
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for p in points:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)
	
	return Vector2(max_x - min_x, max_y - min_y)

# Template creation helpers
func create_circle_template(clockwise: bool = true) -> Array:
	var points = []
	var num_points = 64  # More points for smoother circle
	for i in range(num_points):
		var angle = (i / float(num_points)) * TAU
		if not clockwise:
			angle = -angle
		points.append(Vector2(cos(angle) * 120, sin(angle) * 120))  # Bigger circle
	return points

func create_line_template(direction: Vector2) -> Array:
	var points = []
	var num_points = 64  # Use full resolution for lines
	for i in range(num_points):
		var t = i / float(num_points - 1)
		points.append(direction * t * 150)  # Longer line
	return points

func create_triangle_template() -> Array:
	var points = []
	var p1 = Vector2(0, -100)
	var p2 = Vector2(87, 50)
	var p3 = Vector2(-87, 50)
	
	# Create line from p1 to p2
	for i in range(43):
		var t = i / 42.0
		points.append(p1.lerp(p2, t))
	# Create line from p2 to p3
	for i in range(43):
		var t = i / 42.0
		points.append(p2.lerp(p3, t))
	# Create line from p3 back to p1
	for i in range(43):
		var t = i / 42.0
		points.append(p3.lerp(p1, t))
	
	return points

func create_square_template() -> Array:
	return [
		Vector2(-50, -50),
		Vector2(50, -50),
		Vector2(50, 50),
		Vector2(-50, 50),
		Vector2(-50, -50)
	]

func create_zigzag_template(direction: int = 1) -> Array:
	return [
		Vector2(-100 * direction, -50),
		Vector2(0, 50),
		Vector2(100 * direction, -50)
	]
