extends RefCounted
## Shared packaged font. This module never asks the OS for a font.
static var _primary: FontFile=preload("res://assets/fonts/noto-sans-sc/NotoSansSC-Regular.otf")

static func get_font() -> Font:
	_primary.allow_system_fallback=false
	_primary.fallbacks=[]
	return _primary
