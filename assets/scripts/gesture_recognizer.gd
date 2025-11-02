extends Node
class_name GestureRecognizer

# --- Configuration ---
const NUM_POINTS: int = 64
const SQUARE_SIZE: float = 250.0
const RECOGNITION_THRESHOLD: float = 0.65
const SEARCH_ANGLE_RANGE: float = 25.0
const SEARCH_PRECISION: float = 2.0
const MIN_POINT_DISTANCE: float = 2.0  # Filter duplicate points

var templates: Dictionary = {}
var _half_diagonal: float

func _ready() -> void:
	_half_diagonal = 0.5 * sqrt(SQUARE_SIZE * SQUARE_SIZE * 2.0)
	load_templates_from_folder("res://templates/")
	print("Loaded %d gesture templates" % templates.size())


# --- Public API ---
func recognize(points: Array) -> Dictionary:
	"""
	Recognize a gesture from an array of Vector2 points.
	Returns: {name: String, score: float, template: Array (optional)}
	"""
	if points.size() < 5:
		return _create_result("unknown", 0.0)

	var filtered_points: Array = _filter_duplicate_points(points)
	if filtered_points.size() < 5:
		return _create_result("unknown", 0.0)

	var processed: Array = _process_points(filtered_points)
	return _find_best_match(processed)


# --- Template Management ---
func load_templates_from_folder(folder_path: String) -> void:
	var dir: DirAccess = DirAccess.open(folder_path)
	if not dir:
		push_warning("Could not open templates folder: %s" % folder_path)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".txt"):
			var full_path: String = folder_path.path_join(file_name)
			_load_template_from_file(full_path)
		file_name = dir.get_next()
	
	dir.list_dir_end()


func add_template(name: String, points: Array) -> bool:
	"""Programmatically add a template at runtime"""
	if points.size() < 5:
		push_warning("Template '%s' has too few points" % name)
		return false
	
	templates[name] = _process_points(points)
	return true


func remove_template(name: String) -> bool:
	return templates.erase(name)


func clear_templates() -> void:
	templates.clear()


# --- Private: Template Loading ---
func _load_template_from_file(file_path: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_warning("Failed to open template file: %s" % file_path)
		return

	var content: String = file.get_as_text()
	file.close()

	var points: Array = _parse_template_points(content)
	
	if points.size() >= 2:
		var processed = _process_points(points)
		var template_name: String = file_path.get_file().get_basename()
		templates[template_name] = processed
		print("  ✓ Loaded '%s' (%d points)" % [template_name, points.size()])
	else:
		push_warning("Template '%s' has insufficient points" % file_path.get_file())


func _parse_template_points(content: String) -> Array:
	var points: Array = []
	var regex: RegEx = RegEx.new()
	regex.compile(r"Vector2\s*\(\s*(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)\s*\)")
	
	for match in regex.search_all(content):
		var x: float = match.get_string(1).to_float()
		var y: float = match.get_string(2).to_float()
		points.append(Vector2(x, y))
	
	return points


# --- Private: Recognition ---
func _find_best_match(processed: Array) -> Dictionary:
	var best_name: String = "unknown"
	var best_score: float = -INF

	for template_name in templates.keys():
		var template: Array = templates[template_name]
		var score: float = _calculate_template_score(processed, template)
		
		if score > best_score:
			best_score = score
			best_name = template_name

	if best_score >= RECOGNITION_THRESHOLD:
		return _create_result(best_name, best_score)
	else:
		return _create_result("unknown", best_score)


func _calculate_template_score(points: Array, template: Array) -> float:
	# Check normal orientation
	var normal_distance: float = _distance_at_best_angle(
		points, template, 
		-SEARCH_ANGLE_RANGE, SEARCH_ANGLE_RANGE
	)
	var normal_score: float = 1.0 - (normal_distance / _half_diagonal)
	
	# Check flipped orientation (180°)
	var flipped_distance: float = _distance_at_best_angle(
		points, template,
		180.0 - SEARCH_ANGLE_RANGE, 180.0 + SEARCH_ANGLE_RANGE
	)
	var flipped_score: float = 1.0 - (flipped_distance / _half_diagonal)
	
	return max(normal_score, flipped_score)


# --- Private: Point Processing Pipeline ---
func _process_points(points: Array) -> Array:
	# Templates already have enough points, so just do standard processing
	var resampled: Array = _resample(points, NUM_POINTS)
	var scaled: Array = _scale_to_square(resampled, SQUARE_SIZE)
	var centered: Array = _translate_to_origin(scaled)
	return centered


func _interpolate_points(points: Array, target_count: int) -> Array:
	"""Interpolate sparse points to create a denser path with better shape preservation"""
	if points.size() < 2:
		var result: Array = []
		var point: Vector2 = points[0] if points.size() > 0 else Vector2.ZERO
		for i in range(target_count):
			result.append(point)
		return result
	
	if points.size() >= target_count:
		return points
	
	# For closed shapes (first and last point are close), ensure we close the loop properly
	var is_closed: bool = points[0].distance_to(points[-1]) < 10.0
	var working_points: Array = points.duplicate()
	
	# Calculate how many points to add between each segment proportionally
	var total_length: float = _path_length(working_points)
	if total_length < 0.001:
		return points
	
	var result: Array = []
	var points_to_add: int = target_count - working_points.size()
	
	# Distribute new points proportionally to segment lengths
	var segment_lengths: Array = []
	for i in range(working_points.size() - 1):
		segment_lengths.append(working_points[i].distance_to(working_points[i + 1]))
	
	for i in range(working_points.size() - 1):
		result.append(working_points[i])
		
		# Calculate how many points this segment should get
		var segment_ratio: float = segment_lengths[i] / total_length
		var points_for_segment: int = int(round(float(points_to_add) * segment_ratio))
		
		# Add interpolated points along this segment
		for j in range(points_for_segment):
			var t: float = float(j + 1) / float(points_for_segment + 1)
			result.append(working_points[i].lerp(working_points[i + 1], t))
	
	# Add the last point
	result.append(working_points[-1])
	
	# Trim or pad to exact target count
	if result.size() > target_count:
		return result.slice(0, target_count)
	else:
		while result.size() < target_count:
			result.append(working_points[-1])
		return result


func _filter_duplicate_points(points: Array) -> Array:
	if points.size() <= 1:
		return points
	
	var filtered: Array = [points[0]]
	for i in range(1, points.size()):
		if points[i].distance_to(filtered[-1]) >= MIN_POINT_DISTANCE:
			filtered.append(points[i])
	
	return filtered


func _resample(points: Array, n: int) -> Array:
	if points.size() < 2:
		# Handle degenerate case
		var result: Array = []
		var point: Vector2 = points[0] if points.size() > 0 else Vector2.ZERO
		for i in range(n):
			result.append(point)
		return result

	var total_length: float = _path_length(points)
	if total_length < 0.001:
		var result: Array = []
		for i in range(n):
			result.append(points[0])
		return result
	
	var interval: float = total_length / float(n - 1)
	var accumulated_dist: float = 0.0
	var new_points: Array = [points[0]]

	for i in range(1, points.size()):
		var segment_length: float = points[i - 1].distance_to(points[i])
		
		if (accumulated_dist + segment_length) >= interval:
			var ratio: float = (interval - accumulated_dist) / segment_length
			var interpolated: Vector2 = points[i - 1].lerp(points[i], ratio)
			new_points.append(interpolated)
			points.insert(i, interpolated)
			accumulated_dist = 0.0
		else:
			accumulated_dist += segment_length

	# Pad with final point if needed
	while new_points.size() < n:
		new_points.append(points[-1])
	
	return new_points.slice(0, n)


func _scale_to_square(points: Array, size: float) -> Array:
	var bounds: Vector2 = _get_bounding_box_size(points)
	if bounds.x < 0.001 or bounds.y < 0.001:
		return points
	
	var scale_factor: float = size / max(bounds.x, bounds.y)
	
	var result: Array = []
	for p in points:
		result.append(p * scale_factor)
	
	return result


func _translate_to_origin(points: Array) -> Array:
	var centroid: Vector2 = _get_centroid(points)
	
	var result: Array = []
	for p in points:
		result.append(p - centroid)
	
	return result


# --- Private: Distance Calculations ---
func _distance_at_best_angle(points: Array, template: Array, angle_a: float, angle_b: float) -> float:
	"""Golden section search to find optimal rotation angle"""
	var phi: float = 0.5 * (-1.0 + sqrt(5.0))  # Golden ratio conjugate
	
	var x1: float = phi * angle_a + (1.0 - phi) * angle_b
	var f1: float = _distance_at_angle(points, template, deg_to_rad(x1))
	
	var x2: float = (1.0 - phi) * angle_a + phi * angle_b
	var f2: float = _distance_at_angle(points, template, deg_to_rad(x2))

	while abs(angle_b - angle_a) > SEARCH_PRECISION:
		if f1 < f2:
			angle_b = x2
			x2 = x1
			f2 = f1
			x1 = phi * angle_a + (1.0 - phi) * angle_b
			f1 = _distance_at_angle(points, template, deg_to_rad(x1))
		else:
			angle_a = x1
			x1 = x2
			f1 = f2
			x2 = (1.0 - phi) * angle_a + phi * angle_b
			f2 = _distance_at_angle(points, template, deg_to_rad(x2))
	
	return min(f1, f2)


func _distance_at_angle(points: Array, template: Array, angle_rad: float) -> float:
	var rotated: Array = _rotate_points(points, angle_rad)
	return _path_distance(rotated, template)


func _rotate_points(points: Array, angle_rad: float) -> Array:
	var cos_angle: float = cos(angle_rad)
	var sin_angle: float = sin(angle_rad)
	
	var result: Array = []
	for p in points:
		var rotated: Vector2 = Vector2(
			p.x * cos_angle - p.y * sin_angle,
			p.x * sin_angle + p.y * cos_angle
		)
		result.append(rotated)
	
	return result


func _path_distance(points_a: Array, points_b: Array) -> float:
	"""Average point-to-point distance between two paths"""
	var n: int = min(points_a.size(), points_b.size())
	if n == 0:
		return INF
	
	var total_distance: float = 0.0
	for i in range(n):
		total_distance += points_a[i].distance_to(points_b[i])
	
	return total_distance / float(n)


# --- Private: Geometric Utilities ---
func _path_length(points: Array) -> float:
	var length: float = 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length


func _get_centroid(points: Array) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())


func _get_bounding_box_size(points: Array) -> Vector2:
	var min_point: Vector2 = Vector2(INF, INF)
	var max_point: Vector2 = Vector2(-INF, -INF)
	
	for p in points:
		min_point.x = min(min_point.x, p.x)
		min_point.y = min(min_point.y, p.y)
		max_point.x = max(max_point.x, p.x)
		max_point.y = max(max_point.y, p.y)
	
	return max_point - min_point


func _create_result(name: String, score: float) -> Dictionary:
	return {
		"name": name,
		"score": score
	}
