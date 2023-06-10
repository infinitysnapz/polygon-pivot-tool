@tool
extends EditorPlugin

# TODO:
# add snapping to vertexes, handle the case where intersection point a or b is a vertex of the polygon
# handle self intersecting cuts / holes
# handle lines and paths


signal cut_completed;

const POLYGON_EDITOR_CLASSES = [
"Polygon2DEditor",
"CollisionPolygon2DEditor",
"NavigationPolygonEditor",
#"Line2DEditor",
#"Path2DEditor"
];

const POLYPIVOT_TOOL_BUTTON_SCENE = preload("res://addons/polygon-pivot-tool/polypivot_tool_button.tscn");

const POINT_SIZE = 7;
const LINE_WIDTH = 3;

const CONSUME = true;
const DONT_CONSUME = false;

# used when comparing floats
const THRESHOLD = 1;

enum States {
	WAIT,
	READY,
	SLICE
}

var polypivot_tool_button = null;

var current_state;
var polygon = null
var selected_polygon = null;
var points = [];
var mouse_position = Vector2.ZERO;
var pivot = Vector2.ZERO;


func _enter_tree():
	
	get_editor_interface().get_selection().selection_changed.connect(self.on_editor_selection_changed)
	
	polypivot_tool_button = POLYPIVOT_TOOL_BUTTON_SCENE.instantiate();
	polypivot_tool_button.toggled.connect(on_polypivot_button_toggled);
	cut_completed.connect(polypivot_tool_button.set_pressed.bind(false));
	
	add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, polypivot_tool_button);
	polypivot_tool_button.hide();
	
	var editors = get_polygon_editors();
	for e in editors:
		for c in e.get_children():
			if c is Button:
				c.pressed.connect(user_changed_tool);
				polypivot_tool_button.pressed.connect(c.set_pressed_no_signal.bind(false));


func _exit_tree():
	get_editor_interface().get_selection().selection_changed.disconnect(on_editor_selection_changed);
	remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU, polypivot_tool_button);


func user_changed_tool():
	polypivot_tool_button.set_pressed_no_signal(false);
	current_state = States.WAIT;
	points.clear();


func get_polygon_editors():
	var parent = polypivot_tool_button.get_parent();
	var editors = [];
		
	for c in parent.get_children():
		if is_node_class_one_of(c, POLYGON_EDITOR_CLASSES):
			editors.push_back(c);

	return editors;


func on_polypivot_button_toggled(new_state):

	if current_state == States.SLICE:
		confirm_slice();

	if new_state:
		current_state = States.READY;
	else:
		current_state = States.WAIT;


func on_editor_selection_changed():

	var nodes = get_editor_interface().get_selection().get_selected_nodes();
	polypivot_tool_button.button_pressed = false;

	if nodes.size() == 1 and _handles(nodes.front()):
		selected_polygon = nodes.front();
		polygon = get_polygon_data(selected_polygon);
		for i in polygon.size():
			polygon[i] = selected_polygon.get_global_transform() * polygon[i]
	else:
		selected_polygon = null;
		polygon = null
		current_state = States.WAIT;
		

func _make_visible(visible):
	print("calling make visible")
	if visible:
		polypivot_tool_button.show();
	else:
		polypivot_tool_button.hide();


func is_valid_node_for_polypivot_tool(n):
	return (n is Polygon2D) or (n is NavigationRegion2D) or (n is CollisionPolygon2D);


func _handles(object):
	if is_valid_node_for_polypivot_tool(object):
		selected_polygon = object;
		polygon = get_polygon_data(selected_polygon);
		for i in polygon.size():
			polygon[i] = selected_polygon.get_global_transform() * polygon[i]
		return true;
#	elif object.get_class() == "MultiNodeEdit":
#		var can_handle = true;
#		for node in get_editor_interface().get_selection().get_selected_nodes():
#			if not is_valid_node_for_polypivot_tool(node):
#				can_handle = false;
#				break;
#		return can_handle;
	else:
		selected_polygon = null;
		polygon = null
		current_state = States.WAIT;
		return false;


func from_editor_to_2d_scene_coordinates( position ):
	return selected_polygon.get_viewport_transform().affine_inverse() * position;

func from_2d_scene_to_editor_coordinates( position ):
	return selected_polygon.get_viewport_transform() * position;

func average(vecarray) -> Vector2:
	var count = Vector2.ZERO
	for i in vecarray:
		count+=i
	return count/len(vecarray)

func _forward_canvas_gui_input(event) -> bool: #NOTE - the important bit
	var newposition = null
	if current_state == States.WAIT: 
		return DONT_CONSUME;
	
	if event is InputEventMouse:
		mouse_position = event.position;
		newposition = from_editor_to_2d_scene_coordinates(mouse_position)
		#newposition = from_editor_to_2d_scene_coordinates(event.position)
		

	if current_state == States.SLICE:
		update_overlays();
		pass;
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			current_state = States.SLICE;

			var mouse_pos_in_scene = selected_polygon.get_global_mouse_position();
			points = []
			points.append(newposition);
			pivot = average(points)
			return CONSUME;
			
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var nearestpt = INF
			var nearestvec = null
			for i in polygon:
				var tmp = newposition.distance_squared_to(i)
				if tmp < nearestpt:
					nearestpt = tmp
					nearestvec = i
			if nearestpt < 500 :
				if nearestvec in points:
					points.erase(nearestvec)
				else:
					points.append(nearestvec)
			else:
				nearestpt = INF
				nearestvec = null
				for i in points: # toggle point
					var tmp = newposition.distance_squared_to(i)
					if tmp < nearestpt:
						nearestpt = tmp
						nearestvec = i
				if nearestpt < 100:
					points.erase(nearestvec)
				else:
					points.append(newposition)
					
			pivot = average(points)
			return CONSUME;
		

	if current_state == States.SLICE:

		if event is InputEventKey:
			
			if event.physical_keycode == KEY_ENTER and event.pressed:
				pivot = average(points)
				confirm_slice();
				return CONSUME;
			
			if event.physical_keycode == KEY_ESCAPE and event.pressed:
				return CONSUME;
				
	return DONT_CONSUME;


func _forward_canvas_draw_over_viewport(overlay):

	if not points.is_empty():
		for i in points.size():
			overlay.draw_circle(from_2d_scene_to_editor_coordinates(points[i]), POINT_SIZE, Color.RED);
			#overlay.draw_line(points[i], points[i+1], Color.RED, LINE_WIDTH);
		overlay.draw_circle(from_2d_scene_to_editor_coordinates(pivot), POINT_SIZE, Color.BLUE);
		
		#overlay.draw_circle(points.back(), POINT_SIZE, Color.RED);
		#overlay.draw_line(points.back(), mouse_position, Color.RED, LINE_WIDTH);


func confirm_slice():
	
	if not is_instance_valid(selected_polygon):
		abort_slice("Selected polygon instance is invalid")
		return;

	var scene_points = points.duplicate();
	for i in scene_points.size():
		scene_points[i] = from_editor_to_2d_scene_coordinates(scene_points[i]);

	for i in len(selected_polygon.polygon):
		print(i)
		selected_polygon.polygon[i] -= pivot - selected_polygon.global_position;
	selected_polygon.global_position = pivot
	
	var new_poly = selected_polygon
	var undo_redo = get_undo_redo();
	var parent = selected_polygon.get_parent();

	undo_redo.create_action("Sliced Polygon");
	
	undo_redo.add_undo_reference(selected_polygon);
	
	undo_redo.add_do_method(self, "do_split_polygon", selected_polygon, parent, new_poly);
	undo_redo.add_undo_method(self, "undo_split_polygon", selected_polygon, parent, new_poly);
	undo_redo.commit_action();


	update_overlays();
	
	points.clear();
	current_state = States.READY;

	emit_signal("cut_completed");
	

func do_split_polygon(former, parent, slices):
	pass


func undo_split_polygon(former, parent, slices):
	pass


func create_new_polygon(current_polygon, new_polygon_data):
	var centroid = origin_to_geometry(new_polygon_data);
	var parent = current_polygon.get_parent();
	var new_polygon;
	
	var is_scene_instance = not current_polygon.scene_file_path.is_empty();
	if is_scene_instance:
		new_polygon = load( current_polygon.scene_file_path ).instantiate();
		new_polygon.global_position = current_polygon.global_position;
	else:
		new_polygon = current_polygon.duplicate(true);

	set_polygon_data(new_polygon, new_polygon_data);

	parent.add_child(new_polygon);
	new_polygon.global_position += centroid;

	# this way we can successfully duplicate children nodes;
	if is_scene_instance:
		new_polygon.owner = get_editor_interface().get_edited_scene_root();
	else:
		set_node_owner_recursively(new_polygon, get_editor_interface().get_edited_scene_root());

	return new_polygon;


func abort_slice(error = ""):
	if not error.is_empty():
		printerr(error);
	cancel_slice();

func cancel_slice():
	points.clear();
	current_state = States.READY;


###########################################################################
############################### UTILS #####################################
###########################################################################

static func is_node_class_one_of(node, classes):
	for c in classes:
		if node.is_class(c):
			return true;
	return false;


static func set_polygon_data(node, polygon_data):
	if node is NavigationRegion2D:
		var navigation_polygon = NavigationPolygon.new();
		navigation_polygon.add_outline(polygon_data);
		navigation_polygon.make_polygons_from_outlines();
		node.navigation_polygon = navigation_polygon;
	else:
		node.polygon = polygon_data;


static func get_polygon_data(node):
	if node is NavigationRegion2D:
		assert(node.navigation_polygon.get_outline_count() == 1, "we can only handle connected navigation polygon instances");
		return node.navigation_polygon.get_outline(0);
	
	return node.polygon;


static func get_polygon_orientation(polygon):
	return 1 if Geometry2D.is_polygon_clockwise(polygon) else -1;


static func origin_to_geometry(polygon_data):
	# centering resulting polygons origin to their geometry
	var centroid = Vector2.ZERO;
	for i in polygon_data.size():
		centroid += polygon_data[i];

	centroid /= polygon_data.size();

	for i in polygon_data.size():
		polygon_data[i] -= centroid;
	
	return centroid;
	

static func set_node_owner_recursively(node, o):
	node.owner = o;
	for c in node.get_children():
		set_node_owner_recursively(c, o);

###########################################################################
###########################################################################
###########################################################################
