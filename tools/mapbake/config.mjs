// Map area and design data for the Riviera map (Monaco, Cap d'Ail, La Turbie, Roquebrune).
// Coordinates are WGS84 (lat, lon). The world frame is metres: +X east, +Z south, origin at CENTER.

export const CENTER = { lat: 43.742, lon: 7.418 };
export const SIZE_X = 9000; // metres east-west
export const SIZE_Z = 6200; // metres north-south
export const DEM_ZOOM = 14; // AWS Terrarium tiles (~6.9 m/px here)
export const GRID = 8; // metres per baked height / land cell

// Drivable OSM highway classes -> game road kind (see RoadKind in native world_types.h).
export const HIGHWAYS = {
	motorway: 'expressway', motorway_link: 'ramp', trunk: 'avenue', trunk_link: 'ramp',
	primary: 'avenue', primary_link: 'ramp', secondary: 'avenue', secondary_link: 'ramp',
	tertiary: 'street', tertiary_link: 'street', unclassified: 'street', residential: 'street',
	living_street: 'street',
};
// Named service roads that are part of the Monaco GP circuit or a famous route.
export const NAMED_SERVICE = /Piscine|Rascasse|Noghès|Nogues|Albert 1er|Louis II|Portier|Sainte-D/i;

// Districts: nearest seed wins (Voronoi), distances in metres. Names shown in the HUD / map.
export const DISTRICTS = [
	{ id: 'monte_carlo', name: 'Monte-Carlo', lat: 43.7395, lon: 7.4270 },
	{ id: 'condamine', name: 'La Condamine', lat: 43.7355, lon: 7.4195 },
	{ id: 'fontvieille', name: 'Fontvieille', lat: 43.7290, lon: 7.4165 },
	{ id: 'monaco_ville', name: 'Monaco-Ville', lat: 43.7310, lon: 7.4230 },
	{ id: 'larvotto', name: 'Larvotto', lat: 43.7455, lon: 7.4335 },
	{ id: 'beausoleil', name: 'Beausoleil', lat: 43.7440, lon: 7.4220 },
	{ id: 'cap_dail', name: "Cap d'Ail", lat: 43.7225, lon: 7.4000 },
	{ id: 'eze', name: 'Èze-sur-Mer', lat: 43.7250, lon: 7.3750 },
	{ id: 'la_turbie', name: 'La Turbie', lat: 43.7460, lon: 7.4000 },
	{ id: 'grande_corniche', name: 'Grande Corniche', lat: 43.7400, lon: 7.3830 },
	{ id: 'mont_agel', name: 'Mont Agel', lat: 43.7630, lon: 7.4250 },
	{ id: 'roquebrune', name: 'Roquebrune-Cap-Martin', lat: 43.7600, lon: 7.4600 },
	{ id: 'cap_martin', name: 'Cap Martin', lat: 43.7520, lon: 7.4700 },
	{ id: 'a8', name: 'Autoroute A8', lat: 43.7560, lon: 7.4000 },
];

// Points of interest in the game (festival hub, garages, fast travel, landmarks).
export const POIS = [
	{ type: 'festival', id: 'festival', lat: 43.7353, lon: 7.4210, data: 'Port Hercule' },
	{ type: 'spawn', id: 'spawn_festival', lat: 43.7367, lon: 7.4228 },
	{ type: 'garage', id: 'garage_port', lat: 43.7349, lon: 7.4199 },
	{ type: 'garage', id: 'garage_turbie', lat: 43.7447, lon: 7.4012 },
	{ type: 'garage', id: 'garage_roquebrune', lat: 43.7585, lon: 7.4610 },
	{ type: 'fast_travel', id: 'ft_casino', lat: 43.7394, lon: 7.4276 },
	{ type: 'fast_travel', id: 'ft_turbie', lat: 43.7450, lon: 7.4003 },
	{ type: 'fast_travel', id: 'ft_cap_dail', lat: 43.7218, lon: 7.4035 },
	{ type: 'fast_travel', id: 'ft_roquebrune', lat: 43.7590, lon: 7.4585 },
	{ type: 'landmark', id: 'casino', lat: 43.7396, lon: 7.4281, data: 'casino' },
	{ type: 'landmark', id: 'palace', lat: 43.7314, lon: 7.4198, data: 'palace' },
	{ type: 'landmark', id: 'trophy', lat: 43.7447, lon: 7.4046, data: 'trophee_augustes' },
	{ type: 'landmark', id: 'museum', lat: 43.7307, lon: 7.4254, data: 'oceanographic_museum' },
];

// Event routes. `prefer` (regex on "name|ref") makes the router hug the real road: matching roads
// cost 0.25x, others 5x. Without `via`, a sprint runs between the two ends of the longest connected
// stretch of preferred road inside the map; `via` waypoints (lat, lon) force the order (circuits).
export const ROUTES = [
	{
		id: 'monaco_gp', name: 'Circuit de Monaco', closed: true,
		// The ways of OSM relation 148194 (the real circuit); street-name waypoints in race order:
		// Sainte-Dévote, Beau Rivage (Ostende), Casino, Mirabeau/hairpin (Spélugues), Portier + tunnel
		// (Louis II), chicane/Tabac (Quai des États-Unis), Piscine, then Rascasse and the pit straight.
		circuit: true,
		via: [[43.7373, 7.4212], "Avenue d'Ostende", 'Place du Casino', 'Avenue des Spélugues', 'Boulevard Louis II', 'Quai des États-Unis', 'Route de la Piscine'],
	},
	{ id: 'grande_corniche', name: 'Grande Corniche Hillclimb', closed: false, prefer: /Grande Corniche|\|[DM] 2564$/ },
	{ id: 'moyenne_corniche', name: 'Moyenne Corniche', closed: false, prefer: /Moyenne Corniche|\|[DM] 6007$/ },
	{ id: 'basse_corniche', name: 'Basse Corniche Coast Run', closed: false, prefer: /Basse Corniche|\|[DM] 6098$/ },
	{ id: 'a8_sprint', name: 'Autoroute A8 Sprint', closed: false, prefer: /\|A 8$/ },
	{ id: 'col_mont_agel', name: 'Col du Mont Agel', closed: false, prefer: /Mont Agel|\|[DM] 53$/ },
	{ id: 'route_turbie', name: 'Route de La Turbie Descent', closed: false, prefer: /Route de la Turbie|Boulevard de la Turbie|\|[DM] 37$/i },
];
