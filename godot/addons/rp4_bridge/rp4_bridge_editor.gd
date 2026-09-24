@tool
extends EditorPlugin
## Registers the RP4Bridge Android library (v2 plugin) with the Android export.

var _export_plugin: RP4BridgeExport

func _enter_tree() -> void:
	_export_plugin = RP4BridgeExport.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class RP4BridgeExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "RP4Bridge"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["rp4_bridge/bin/rp4bridge-release.aar"])

	func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		# The RP4 Pro is a controller-first handheld: declare gamepad support, don't require touch.
		return """
		<uses-feature android:name="android.hardware.gamepad" android:required="false" />
		<uses-feature android:name="android.hardware.touchscreen" android:required="false" />
		"""
