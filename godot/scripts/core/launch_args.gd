class_name LaunchArgs
extends RefCounted
## User launch arguments ("key=value" after `--`). On Android there is no command line, so tools
## (tools/profile_device.ps1) push them in a file in the app's external files folder, which adb can
## write and the app can read without permissions:
##   /sdcard/Android/data/com.neontouge.rp4/files/launch_args.txt   (whitespace-separated)
## The file is consumed (deleted) on first read, so a normal launch afterwards is unaffected.

const ANDROID_FILE := "/sdcard/Android/data/com.neontouge.rp4/files/launch_args.txt"

static var _args: PackedStringArray
static var _read := false

static func user_args() -> PackedStringArray:
	if _read:
		return _args
	_read = true
	_args = OS.get_cmdline_user_args()
	if OS.get_name() == "Android" and FileAccess.file_exists(ANDROID_FILE):
		var f := FileAccess.open(ANDROID_FILE, FileAccess.READ)
		if f:
			for a in f.get_as_text().split(" ", false):
				for b in a.split("\n", false):
					if b.strip_edges() != "":
						_args.append(b.strip_edges())
			f.close()
		DirAccess.remove_absolute(ANDROID_FILE)
		print("LaunchArgs from file: ", _args)
	return _args
