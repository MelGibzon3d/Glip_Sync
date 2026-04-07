@tool
extends Node
## Rhubarb Lip Sync Baker — parses a Rhubarb TSV file and bakes a
## blend-shape animation with smooth cross-fade transitions.
##
## USAGE:
##   1. Attach this script to a Node that is a sibling or ancestor of
##      both the MeshInstance3D (with blend shapes) and an AnimationPlayer.
##   2. In the Inspector, set [rhubarb_file] to your .txt TSV file.
##   3. Set [mesh_node] to point at the MeshInstance3D with the shapes.
##   4. Set [animation_player_node] to your AnimationPlayer.
##   5. Toggle [bake_now] to true — the animation is generated instantly.
##
## The script auto-detects blend-shape names from the mesh, so your
## Rhubarb visemes (A-H, X) must match the shape-key names on the mesh.
## Missing visemes are auto-remapped to the closest available shape.

# ── Exported configuration ──────────────────────────────────────────────

## Path to the Rhubarb .txt or .json file
@export_file("*.txt", "*.json") var rhubarb_file: String = ""

@export_group("Rhubarb Auto-Generation")
enum RhubarbRecognizer {POCKET_SPHINX, PHONETIC}
## Optional: The path to rhubarb.exe on your machine. If set, you don't need a text file.
@export_global_file("*.exe", "*.app", "*.exe") var rhubarb_executable_path: String = ""
## How Rhubarb analyzes sound. Use POCKET_SPHINX for English, or PHONETIC for sounds/non-English.
@export var recognizer: RhubarbRecognizer = RhubarbRecognizer.POCKET_SPHINX
## Optional: If you want to physically save the JSON that Rhubarb generates, specify an output folder.
@export_global_dir var rhubarb_save_directory: String = ""
@export_group("")

## The MeshInstance3D that contains the lip-sync blend shapes
@export var mesh_node: NodePath = NodePath("")

@export_group("Viseme Mapping")
## Closed mouth (M, B, P consonants)
@export var map_A: String = "X"
## Slightly open mouth (K, S, T consonants)
@export var map_B: String = "C"
## Open mouth (Aa, Eh vowels)
@export var map_C: String = "C"
## Wide open mouth (Ah vowels)
@export var map_D: String = "D"
## Slightly rounded mouth (O, Oo vowels)
@export var map_E: String = "E"
## Puckered lips (W, Q, R consonants)
@export var map_F: String = "F"
## Upper teeth visible (F, V consonants)
@export var map_G: String = "E"
## Very wide open mouth (L, Th consonants - optional)
@export var map_H: String = "C"
## Silence / Idle (Mouth closed completely)
@export var map_X: String = "X"
@export_group("")

## (Optional) The AudioStreamPlayer you want to bind the audio cue to
@export var audio_player_node: NodePath = NodePath("")

## (Optional) The audio file to play during the animation
@export var audio_stream: AudioStream = null

## The AnimationPlayer that will receive the baked animation
@export var animation_player_node: NodePath = NodePath("")

enum BlendMode {BY_RATIO, FIXED_TIME}

## Blending mode for crossfades.
## 'BY_RATIO' mimics Blender Rhubarb "In Out Blend Type: By ratio".
@export var blend_mode: BlendMode = BlendMode.BY_RATIO

## Ratio for BY_RATIO mode. 0.50 means the crossfade takes 50% of the duration
## of the preceding viseme. This acts proportionally and keeps mouth movement smooth.
@export_range(0.01, 1.0, 0.01) var blend_ratio: float = 0.50

## Duration (seconds) for FIXED_TIME mode.
## Larger = smoother / mushier; smaller = snappier.
@export_range(0.01, 0.3, 0.01) var fixed_blend_time: float = 0.07

## Name for the generated animation inside the AnimationPlayer library
@export var animation_name: String = "lip_sync"

## Toggle this ON in the Inspector to run the bake (auto-resets to false)
@export var bake_now: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_bake_animation()
		bake_now = false # always reset so you can click again


# ── Internal types ──────────────────────────────────────────────────────

class VisemeKey:
	var time: float
	var viseme: String
	func _init(t: float, v: String):
		time = t
		viseme = v


# ── Bake entry-point ────────────────────────────────────────────────────

func _bake_animation() -> void:
	# --- validate mesh and anim player inputs ---------------------------
	var mesh: MeshInstance3D = get_node_or_null(mesh_node) as MeshInstance3D
	if mesh == null:
		push_error("RhubarbBaker: mesh_node does not point to a valid MeshInstance3D.")
		return

	var anim_player: AnimationPlayer = get_node_or_null(animation_player_node) as AnimationPlayer
	if anim_player == null:
		push_error("RhubarbBaker: animation_player_node does not point to a valid AnimationPlayer.")
		return

	# --- parse or generate data -----------------------------------------
	var keys: Array[VisemeKey] = []
	if rhubarb_file == "" and rhubarb_executable_path != "" and audio_stream != null:
		var os_audio_path = ProjectSettings.globalize_path(audio_stream.resource_path)
		var os_exe_path = ProjectSettings.globalize_path(rhubarb_executable_path)
		
		if not FileAccess.file_exists(os_audio_path):
			push_error("RhubarbBaker: Audio file not found on disk at: " + os_audio_path)
			return
		# Define output file path
		var save_path: String = ""
		var is_temp: bool = false
		if rhubarb_save_directory != "":
			save_path = ProjectSettings.globalize_path(rhubarb_save_directory).path_join(audio_stream.resource_path.get_file().get_basename() + ".json")
		else:
			save_path = ProjectSettings.globalize_path("user://temp_rhubarb_sync.json")
			is_temp = true
			
		var rhubarb_dir = os_exe_path.get_base_dir()
		var output: Array = []
		var err: int = -1
		
		# Rhubarb requires its working directory to access /res/sphinx. 
		# We must use a shell to switch directory before executing.
		var rec_str = "pocketSphinx" if recognizer == RhubarbRecognizer.POCKET_SPHINX else "phonetic"
		print("RhubarbBaker: Executing Rhubarb securely (using %s recognizer)..." % rec_str)
		if OS.get_name() == "Windows":
			var cmd_str = "cd /d \"%s\" && \"%s\" -q -r %s -f json -o \"%s\" \"%s\"" % [rhubarb_dir, os_exe_path, rec_str, save_path, os_audio_path]
			err = OS.execute("cmd.exe", ["/c", cmd_str], output, true)
		else:
			var cmd_str = "cd \"%s\" && \"%s\" -q -r %s -f json -o \"%s\" \"%s\"" % [rhubarb_dir, os_exe_path, rec_str, save_path, os_audio_path]
			err = OS.execute("sh", ["-c", cmd_str], output, true)
			
		if err != OK:
			push_error("RhubarbBaker: Failed to run Rhubarb. Error code: ", err, " Output: ", output)
			return
			
		if not FileAccess.file_exists(save_path):
			push_error("RhubarbBaker: Rhubarb completed but no output file was created at: ", save_path)
			return

		var f = FileAccess.open(save_path, FileAccess.READ)
		var json_str = f.get_as_text()
		f.close()
		
		if is_temp:
			DirAccess.remove_absolute(save_path)
		else:
			print("RhubarbBaker: Saved generated JSON purely for backup to ", save_path)

		var json = JSON.new()
		if json.parse(json_str) != OK:
			push_error("RhubarbBaker: Failed to parse generated Rhubarb JSON output.")
			return
		
		var parsed_data = json.data
		if not (parsed_data is Dictionary) or not parsed_data.has("mouthCues"):
			push_error("RhubarbBaker: Invalid generated JSON structure returned.")
			return
			
		for q in parsed_data["mouthCues"]:
			keys.append(VisemeKey.new(float(q["start"]), str(q["value"])))
		print("RhubarbBaker: Successfully generated %d viseme entries directly from Rhubarb." % keys.size())
		
	else:
		if rhubarb_file == "":
			push_error("RhubarbBaker: No rhubarb_file set and Auto-Generation variables are not configured!")
			return

		keys = _parse_rhubarb_file(rhubarb_file)
		if keys.is_empty():
			push_error("RhubarbBaker: Parsed 0 entries from manual file.")
			return
		print("RhubarbBaker: Parsed %d viseme entries from file." % keys.size())

	# --- discover available blend shapes on the mesh --------------------
	var mesh_resource: Mesh = mesh.mesh
	if mesh_resource == null:
		push_error("RhubarbBaker: MeshInstance3D has no mesh resource.")
		return

	var available_shapes: PackedStringArray = PackedStringArray()
	var shape_count: int = mesh_resource.get_blend_shape_count()
	for i in shape_count:
		available_shapes.append(mesh_resource.get_blend_shape_name(i))
	print("RhubarbBaker: Found %d blend shapes on mesh: %s" % [shape_count, str(available_shapes)])

	# --- Rhubarb viseme → mesh shape key mapping -------------------------
	var rhubarb_to_shape: Dictionary = {
		"A": map_A,
		"B": map_B,
		"C": map_C,
		"D": map_D,
		"E": map_E,
		"F": map_F,
		"G": map_G,
		"H": map_H,
		"X": map_X,
	}

	# Remap all visemes in the parsed data through the mapping
	for k in keys:
		if rhubarb_to_shape.has(k.viseme):
			var mapped: String = rhubarb_to_shape[k.viseme]
			if k.viseme != mapped and mapped != "":
				print("RhubarbBaker: Mapping Rhubarb '%s' → shape key '%s'" % [k.viseme, mapped])
			k.viseme = mapped
		else:
			push_warning("RhubarbBaker: Unknown Rhubarb viseme '%s', keeping as-is." % k.viseme)

	# Collect unique shape keys actually referenced (excluding "" for silence)
	var used_shapes: Dictionary = {} # String -> true
	for k in keys:
		if k.viseme != "":
			used_shapes[k.viseme] = true

	# Warn about shape keys that don't exist on the mesh
	for v in used_shapes.keys():
		if not available_shapes.has(v):
			push_warning("RhubarbBaker: Shape key '%s' not found on mesh. Skipping." % v)

	# We only create tracks for visemes that are BOTH in the TSV and on the mesh
	var active_visemes: Array[String] = []
	for v in used_shapes.keys():
		if available_shapes.has(v):
			active_visemes.append(v)
	active_visemes.sort()

	if active_visemes.is_empty():
		push_error("RhubarbBaker: No matching blend shapes found between TSV and mesh.")
		return

	# --- build the Animation resource -----------------------------------
	var anim := Animation.new()
	var last_time: float = keys[keys.size() - 1].time
	anim.length = last_time + 0.5 # small padding after last viseme

	# Relative path from the AnimationPlayer's ROOT NODE to the MeshInstance3D.
	# Godot resolves animation track paths relative to root_node.
	var anim_root: Node = anim_player.get_node(anim_player.root_node)
	if anim_root == null:
		anim_root = anim_player # fallback
	
	var rel_path: String = str(anim_root.get_path_to(mesh))
	
	print("RhubarbBaker: AnimationPlayer root_node is: ", anim_player.root_node)
	print("RhubarbBaker: Resolved anim_root to: ", anim_root.name)
	print("RhubarbBaker: Computed rel_path to mesh: ", rel_path)
	
	# If the computed path starts with "../", it often fails to resolve in Godot 4
	# when using inherited/imported scenes. A safe fix is to just use the path
	# relative to the scene's actual root node instead.
	if rel_path.begins_with("../"):
		print("RhubarbBaker: Computed path has '../', attempting to fix by stripping it. (This happens when AnimationPlayer root is itself)")
		# Usually this means anim_root == anim_player, so evaluating from its parent is what Godot actually wants for bone/blend paths in GLBs
		var owner_root = anim_player.get_parent()
		if owner_root:
			rel_path = str(owner_root.get_path_to(mesh))
			print("RhubarbBaker: Fixed rel_path: ", rel_path)

	# Create one TYPE_BLEND_SHAPE track per active viseme
	var track_map: Dictionary = {} # viseme_name -> track_index
	for v_name in active_visemes:
		var idx: int = anim.add_track(Animation.TYPE_BLEND_SHAPE)
		anim.track_set_path(idx, NodePath(rel_path +":"+ v_name))
		anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
		track_map[v_name] = idx

	# --- insert keyframes with envelope logic (Blender NLA analog) ---
	# First, collapse adjacent identical shape keys (crucial for envelope logic)
	var merged_keys: Array[VisemeKey] = []
	for k in keys:
		var vis: String = k.viseme
		if merged_keys.size() > 0 and merged_keys.back().viseme == vis:
			continue
		merged_keys.append(VisemeKey.new(k.time, vis))

	# Initialise all active tracks with value 0.0 at time 0
	for v_name in active_visemes:
		anim.track_insert_key(track_map[v_name], 0.0, 0.0)

	for i in merged_keys.size():
		var entry: VisemeKey = merged_keys[i]
		var t_i: float = entry.time
		var v: String = entry.viseme
		var sil_curr: bool = (v == "" or v == "X")

		var t_next: float = merged_keys[i + 1].time if i + 1 < merged_keys.size() else t_i + 0.5

		var A: float
		var M_start: float
		var M_end: float
		var D: float

		if blend_mode == BlendMode.BY_RATIO:
			# Shape peaks at exactly the midpoint of the syllable
			var M_curr: float = t_i + (t_next - t_i) * blend_ratio
			if sil_curr:
				# Silence acts as a flat rest phase (no peak)
				M_start = t_i
				M_end = t_next
			else:
				M_start = M_curr
				M_end = M_curr

			# Determine fade-in start (A)
			if i == 0 or (merged_keys[i - 1].viseme == "" or merged_keys[i - 1].viseme == "X"):
				A = t_i
			else:
				var prev_t = merged_keys[i - 1].time
				A = prev_t + (t_i - prev_t) * blend_ratio

			# Determine fade-out end (D)
			if i == merged_keys.size() - 1 or (merged_keys[i + 1].viseme == "" or merged_keys[i + 1].viseme == "X"):
				D = t_next
			else:
				var t_next_next = merged_keys[i + 2].time if i + 2 < merged_keys.size() else t_next + 0.5
				D = t_next + (t_next_next - t_next) * blend_ratio
		else:
			# FIXED_TIME Mode: legacy fixed crossfade
			var fade = fixed_blend_time
			if i == 0 or (merged_keys[i - 1].viseme == "" or merged_keys[i - 1].viseme == "X"):
				A = t_i
			else:
				A = max(t_i - fade, merged_keys[i - 1].time)
			M_start = t_i
			
			if i == merged_keys.size() - 1 or (merged_keys[i + 1].viseme == "" or merged_keys[i + 1].viseme == "X"):
				M_end = t_next
				D = t_next + 0.15
			else:
				M_end = max(t_next - fade, t_i)
				D = t_next

		# Skip shape keys not on mesh
		if v == "" or not track_map.has(v):
			continue

		var idx = track_map[v]
		# Ensure we don't accidentally insert out of order keys due to floating point error
		if A < M_start and not is_equal_approx(A, M_start):
			anim.track_insert_key(idx, A, 0.0)
		anim.track_insert_key(idx, M_start, 1.0)
		if M_end > M_start and not is_equal_approx(M_start, M_end):
			anim.track_insert_key(idx, M_end, 1.0)
		if D > M_end and not is_equal_approx(M_end, D):
			anim.track_insert_key(idx, D, 0.0)

	# --- optional audio track -------------------------------------------
	if not audio_player_node.is_empty() and audio_stream != null:
		var audio_player: Node = get_node_or_null(audio_player_node)
		if audio_player != null:
			var audio_rel_path: String = str(anim_root.get_path_to(audio_player))
			if audio_rel_path.begins_with("../"):
				var owner_root = anim_player.get_parent()
				if owner_root:
					audio_rel_path = str(owner_root.get_path_to(audio_player))

			var audio_idx: int = anim.add_track(Animation.TYPE_AUDIO)
			anim.track_set_path(audio_idx, NodePath(audio_rel_path))
			anim.audio_track_insert_key(audio_idx, 0.0, audio_stream)
			print("RhubarbBaker: 🎵 Audio track perfectly mapped to: %s" % audio_rel_path)
		else:
			push_warning("RhubarbBaker: audio_stream provided but audio_player_node is invalid!")

	# --- also build a RESET animation (all shapes at 0) -----------------
	var reset_anim := Animation.new()
	reset_anim.length = 0.001
	for v_name in active_visemes:
		var idx: int = reset_anim.add_track(Animation.TYPE_BLEND_SHAPE)
		reset_anim.track_set_path(idx, NodePath(rel_path +":"+ v_name))
		reset_anim.track_insert_key(idx, 0.0, 0.0)

	# --- add to AnimationPlayer library ---------------------------------
	var lib: AnimationLibrary = null
	if anim_player.has_animation_library(&""):
		lib = anim_player.get_animation_library(&"")
	else:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library(&"", lib)

	# Remove old versions if they exist
	if lib.has_animation(animation_name):
		lib.remove_animation(animation_name)
	if lib.has_animation(&"RESET"):
		lib.remove_animation(&"RESET")

	lib.add_animation(animation_name, anim)
	lib.add_animation(&"RESET", reset_anim)

	print("RhubarbBaker: ✅ Baked animation '%s' with %d tracks, length %.2fs" % [
		animation_name, active_visemes.size(), anim.length
	])
	print("RhubarbBaker: Active visemes: %s" % str(active_visemes))
	print("RhubarbBaker: Don't forget to save the scene (Ctrl+S) to persist the animation!")


# ── File parser ─────────────────────────────────────────────────────────

func _parse_rhubarb_file(path: String) -> Array[VisemeKey]:
	var result: Array[VisemeKey] = []
	var ext: String = path.get_extension().to_lower()

	if ext == "json":
		return _parse_json_file(path)
	elif ext == "txt" or ext == "tsv":
		return _parse_tsv_file(path)
	else:
		push_error("RhubarbBaker: Unsupported file extension '%s'" % ext)
		return result


func _parse_json_file(path: String) -> Array[VisemeKey]:
	var result: Array[VisemeKey] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("RhubarbBaker: Cannot open JSON file '%s' — error %s" % [path, str(FileAccess.get_open_error())])
		return result

	var content := file.get_as_text()
	var json_data: Variant = JSON.parse_string(content)
	
	if typeof(json_data) != TYPE_DICTIONARY:
		push_error("RhubarbBaker: Invalid JSON format in '%s'. Expected a dictionary." % path)
		return result
		
	var dict_data: Dictionary = json_data as Dictionary
	if not dict_data.has("mouthCues"):
		push_error("RhubarbBaker: Invalid JSON format. Missing 'mouthCues' array.")
		return result
		
	var mouth_cues: Array = dict_data["mouthCues"]
	for cue in mouth_cues:
		var cue_dict: Dictionary = cue as Dictionary
		if not cue_dict.has("start") or not cue_dict.has("value"):
			continue
			
		var time_val: float = str(cue_dict["start"]).to_float()
		var viseme_str: String = str(cue_dict["value"]).strip_edges()
		result.append(VisemeKey.new(time_val, viseme_str))
		
	return result


func _parse_tsv_file(path: String) -> Array[VisemeKey]:
	var result: Array[VisemeKey] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("RhubarbBaker: Cannot open text file '%s' — error %s" % [path, str(FileAccess.get_open_error())])
		return result

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue

		# Split by tab
		var parts := line.split("\t", false)
		if parts.size() < 2:
			# Try space as fallback separator
			parts = line.split(" ", false)
		if parts.size() < 2:
			push_warning("RhubarbBaker: Skipping malformed line: '%s'" % line)
			continue

		var time_str := parts[0].strip_edges()
		var viseme_str := parts[1].strip_edges()

		if not time_str.is_valid_float():
			push_warning("RhubarbBaker: Non-numeric time '%s', skipping." % time_str)
			continue

		result.append(VisemeKey.new(time_str.to_float(), viseme_str))

	return result
