extends RefCounted

static func _read(path: String, validator: Callable) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"code":"missing_save","message":"未找到存档："+path}
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null: return {"ok":false,"code":"read_failed","message":"无法读取存档"}
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK: return {"ok":false,"code":"invalid_json","message":"存档JSON损坏"}
	var error: String = validator.call(parser.data)
	if not error.is_empty(): return {"ok":false,"code":"invalid_state","message":error}
	return {"ok":true,"code":"loaded","message":"存档已恢复","state":parser.data}

static func _write(path: String, text: String) -> bool:
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.flush()
	return file.get_error() == OK

static func save_state(path: String, state: Dictionary, validator: Callable) -> Dictionary:
	var error: String = validator.call(state)
	if not error.is_empty(): return {"ok":false,"code":"invalid_state","message":error}
	var temp = path+".tmp"
	if not _write(temp,JSON.stringify(state,"\t",true,true)): return {"ok":false,"code":"write_failed","message":"无法写入临时存档"}
	if not _read(temp,validator).ok: return {"ok":false,"code":"verify_failed","message":"临时存档校验失败，原档未变"}
	# Rotate only a validated primary; a damaged primary can never replace a valid backup.
	if _read(path,validator).ok:
		if not _write(path+".bak.tmp",FileAccess.get_file_as_string(path)) or not _read(path+".bak.tmp",validator).ok:
			return {"ok":false,"code":"backup_failed","message":"备份失败，原档未变"}
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".bak.tmp"),ProjectSettings.globalize_path(path+".bak")) != OK:
			return {"ok":false,"code":"backup_failed","message":"备份提交失败，原档未变"}
	# First save also leaves one validated backup.
	elif not _read(path+".bak",validator).ok:
		if not _write(path+".bak",FileAccess.get_file_as_string(temp)):
			return {"ok":false,"code":"backup_failed","message":"无法建立首份有效备份"}
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path)) != OK:
		return {"ok":false,"code":"commit_failed","message":"存档提交失败，有效备份保留"}
	return {"ok":true,"code":"saved","message":"已保存","events":[]}

static func load_state(path: String, validator: Callable) -> Dictionary:
	var main = _read(path,validator)
	if main.ok: return main
	# Unsupported versions do not silently roll back across a potentially newer game.
	if main.code == "invalid_state" and main.message in ["不支持的存档版本","不支持的存档规则"]: return main
	var backup = _read(path+".bak",validator)
	if backup.ok:
		backup.code = "recovered_backup"
		backup.message = "主档无效，已恢复有效备份；原始坏档保留"
		return backup
	return {"ok":false,"code":main.code,"message":main.message+"；没有有效备份，当前进度未变"}
