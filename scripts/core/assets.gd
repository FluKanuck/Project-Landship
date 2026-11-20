class_name Assets
## Loads the scripted .glb assets and gives them the shared materials.

static var _scenes := {}


static func spawn(asset: String, context := "exterior") -> Node3D:
	if not _scenes.has(asset):
		_scenes[asset] = load("res://assets/models/%s.glb" % asset)
	var ps: PackedScene = _scenes[asset]
	var n: Node3D = ps.instantiate()
	Mats.apply(n, context)
	return n


## Find a node by exact name anywhere below `root` (sockets, moving parts).
static func find(root: Node, name: String) -> Node:
	if root.name == name:
		return root
	for c in root.get_children():
		var r := find(c, name)
		if r:
			return r
	return null


## Attach module `asset` to socket `socket` on `host`.
static func attach(host: Node3D, socket: String, asset: String, context := "exterior") -> Node3D:
	var s := find(host, socket) as Node3D
	var m := spawn(asset, context)
	if s:
		s.add_child(m)
	else:
		push_warning("socket %s missing on %s" % [socket, host.name])
		host.add_child(m)
	return m


static func set_layer(node: Node, layer_mask: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layer_mask
	for c in node.get_children():
		set_layer(c, layer_mask)


static func set_shadows(node: Node, on: bool) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in node.get_children():
		set_shadows(c, on)
