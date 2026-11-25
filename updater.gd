extends Node
## Otomatik güncelleme: açılışta GitHub'daki son Release'e bakar. Daha yeniyse zip'i indirir,
## exe'nin yanındaki dosyaları değiştirir ve oyunu yeniden başlatır.
## Yalnızca dışa aktarılmış Windows sürümünde çalışır (editörde ve testlerde kapalı).
## Yeni sürüm çıkarmak için: project.godot -> application/config/version artır,
## ya da tek komut: release.ps1 (README).

signal status(msg: String)

const REPO := "Obuto45/bazar"
const API := "https://api.github.com/repos/Obuto45/bazar/releases/latest"
const DOWNLOAD_PREFIX := "https://github.com/Obuto45/bazar/releases/download/"
const ASSET_SUFFIX := "_Windows.zip"


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0"))


## "v0.3" / "0.3.1" karşılaştırması: a, b'den yeniyse true.
static func is_newer(a: String, b: String) -> bool:
	var x := a.trim_prefix("v").split(".")
	var y := b.trim_prefix("v").split(".")
	for i in maxi(x.size(), y.size()):
		var p := x[i].to_int() if i < x.size() else 0
		var q := y[i].to_int() if i < y.size() else 0
		if p != q:
			return p > q
	return false


func _ready() -> void:
	if not OS.has_feature("template") or OS.get_name() != "Windows":
		return
	_cleanup_old()
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_release.bind(req))
	req.request(API, ["User-Agent: Bazar-Updater", "Accept: application/vnd.github+json"])


func _exe_dir() -> String:
	return OS.get_executable_path().get_base_dir()


## Önceki güncellemeden kalan, artık kullanılmayan eski dosyaları sil.
func _cleanup_old() -> void:
	var d := DirAccess.open(_exe_dir())
	if d:
		for f in d.get_files():
			if f.ends_with(".old"):
				d.remove(f)


func _on_release(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return # internet yoksa ya da GitHub yanıt vermezse sessizce oyna
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var tag := str(data.get("tag_name", ""))
	if not is_newer(tag, version()):
		return
	var url := ""
	for a in data.get("assets", []):
		if typeof(a) == TYPE_DICTIONARY and str(a.get("name", "")).ends_with(ASSET_SUFFIX):
			url = str(a.get("browser_download_url", ""))
	if not url.begins_with(DOWNLOAD_PREFIX): # yalnızca kendi depomuzdan indir
		return
	status.emit("Yeni sürüm %s indiriliyor..." % tag)
	var dl := HTTPRequest.new()
	dl.download_file = OS.get_user_data_dir().path_join("update.zip")
	add_child(dl)
	dl.request_completed.connect(_on_download.bind(dl, tag))
	dl.request(url, ["User-Agent: Bazar-Updater"])


func _on_download(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray, dl: HTTPRequest, tag: String) -> void:
	var zip_path := dl.download_file
	dl.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.emit("Güncelleme indirilemedi, eski sürümle devam.")
		return
	var err := _install(zip_path)
	DirAccess.remove_absolute(zip_path)
	if err != "":
		status.emit("Güncelleme kurulamadı (%s), eski sürümle devam." % err)
		return
	status.emit("%s kuruldu, oyun yeniden başlıyor..." % tag)
	await get_tree().create_timer(1.5).timeout
	OS.create_process(OS.get_executable_path(), [])
	get_tree().quit()


## Çalışan exe/dll üzerine yazılamaz ama Windows yeniden adlandırmaya izin verir:
## eskiyi .old yap, yenisini yaz. Hata olursa hepsini geri al. Boş dönüş = başarılı.
func _install(zip_path: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "zip açılamadı"
	var dir := _exe_dir()
	var moved: Array = []
	for f in zip.get_files():
		var fname := f.get_file() # klasör yolunu at: zip dışına yazılamasın
		if fname.is_empty() or fname.begins_with("."):
			continue
		var target := dir.path_join(fname)
		var data := zip.read_file(f)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target + ".old")
			if DirAccess.rename_absolute(target, target + ".old") != OK:
				zip.close()
				_rollback(moved)
				return "%s değiştirilemedi" % fname
			moved.append(target)
		var fa := FileAccess.open(target, FileAccess.WRITE)
		if fa == null:
			zip.close()
			_rollback(moved)
			return "%s yazılamadı" % fname
		fa.store_buffer(data)
		fa.close()
	zip.close()
	return ""


func _rollback(moved: Array) -> void:
	for t in moved:
		DirAccess.remove_absolute(t)
		DirAccess.rename_absolute(t + ".old", t)
