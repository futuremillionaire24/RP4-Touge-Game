class_name ThinFilmLUT
extends RefCounted
## Generates a 256×6 ImageTexture encoding spectral thin-film interference colors for
## pearlescent / chameleon paint finishes. Each row represents a different film thickness
## (warm pearl, cool pearl, chameleon, candy flip, chrome flip, iridescent). Indexed by
## cos(theta) = dot(N, V) along the X axis (0 = grazing, 255 = face-on).

const ROWS := 6
const WIDTH := 256

## Film thickness presets in nanometres (determines the interference spectrum).
const PRESETS := {
	0: {"name": "warm_pearl", "thickness_nm": 380.0, "strength": 0.7},
	1: {"name": "cool_pearl", "thickness_nm": 480.0, "strength": 0.65},
	2: {"name": "chameleon", "thickness_nm": 550.0, "strength": 0.9},
	3: {"name": "candy_flip", "thickness_nm": 420.0, "strength": 0.8},
	4: {"name": "chrome_flip", "thickness_nm": 320.0, "strength": 0.5},
	5: {"name": "iridescent", "thickness_nm": 650.0, "strength": 0.85},
}

static var _texture: ImageTexture = null

## Returns a cached 256×6 RGBA8 ImageTexture.
static func generate() -> ImageTexture:
	return get_lut()

static func get_lut() -> ImageTexture:
	if _texture != null:
		return _texture
	var img := Image.create(WIDTH, ROWS, false, Image.FORMAT_RGBA8)
	for row in range(ROWS):
		var preset: Dictionary = PRESETS[row]
		var d_nm: float = preset.thickness_nm
		var strength: float = preset.strength
		for x in range(WIDTH):
			var cos_theta := float(x) / float(WIDTH - 1) # 0 = grazing, 1 = face-on
			# Thin-film interference: path difference = 2 * n * d * cos(theta_refracted)
			# For mica flakes (n ≈ 1.58) coated with metal oxide.
			var n_film := 1.58
			# Snell's law: sin(theta_i) = n * sin(theta_r) → cos(theta_r)
			var sin_i := sqrt(1.0 - cos_theta * cos_theta)
			var sin_r := sin_i / n_film
			var cos_r := sqrt(maxf(0.0, 1.0 - sin_r * sin_r))
			# Optical path difference (nm).
			var opd := 2.0 * n_film * d_nm * cos_r
			# Compute reflected color from interference at R, G, B wavelengths.
			var r := _interference(opd, 630.0) * strength
			var g := _interference(opd, 532.0) * strength
			var b := _interference(opd, 465.0) * strength
			# Blend with white at face-on (interference disappears at normal incidence
			# on real pearls — the base coat dominates).
			var face := cos_theta * cos_theta
			r = lerpf(r, 0.5, face * 0.6)
			g = lerpf(g, 0.5, face * 0.6)
			b = lerpf(b, 0.5, face * 0.6)
			img.set_pixel(x, row, Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0), 1.0))
	_texture = ImageTexture.create_from_image(img)
	return _texture

## Thin-film reflectance at a single wavelength: interference fringes from the path difference.
static func _interference(opd_nm: float, wavelength_nm: float) -> float:
	# Constructive when opd = m * wavelength; destructive at half-wavelength offsets.
	var phase := opd_nm / wavelength_nm * TAU
	# Reflectance envelope: Airy function approximation (simplified for paint, not Fabry-Pérot).
	return 0.5 + 0.5 * cos(phase)

## Row index for a named preset.
static func row_for(name: String) -> int:
	for i in range(ROWS):
		if PRESETS[i].name == name:
			return i
	return 0
