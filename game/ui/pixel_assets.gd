extends RefCounted
## A01 owns the files and metadata; UI only reads the published asset interface.
const ROOT = "res://assets/pixel/"
static var metadata: Dictionary = {}
static var textures: Dictionary = {}

static func manifest() -> Dictionary:
	if metadata.is_empty() and FileAccess.file_exists(ROOT+"manifest.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"manifest.json"))
		if parsed is Dictionary: metadata = parsed
	return metadata

static func entry(id: String) -> Dictionary:
	var data = manifest()
	id = str(data.get("aliases",{}).get(id,id))
	return data.get("sprites",{}).get(id,{})

static func sprite(id: String) -> Texture2D:
	var info = entry(id)
	return texture(str(info.get("file","")))

static func background(id: String) -> Texture2D:
	return texture(str(manifest().get("backgrounds",{}).get(id,{}).get("file","")))

static func texture(relative_path: String) -> Texture2D:
	if relative_path.is_empty(): return null
	if not textures.has(relative_path):
		var path = ROOT+relative_path
		if not ResourceLoader.exists(path): return null
		textures[relative_path] = load(path) as Texture2D
	return textures[relative_path]

static func skin(id: String) -> StyleBox:
	var image = sprite(id)
	if image == null: return null
	var info = entry(id)
	var style = StyleBoxTexture.new()
	style.texture = image
	var margins = info.get("nine_slice_margins",[12,12,12,12])
	var content = info.get("content_margins",[14,10,14,10])
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,margins[side])
		style.set_content_margin(side,content[side])
	return style
