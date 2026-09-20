// Relic activity types: the ONE list, shared by index.html and
// relic-bulk-import.html (plain <script src>, no build step; top-level
// const/functions become globals for the page's own inline script).
//
// Groups, not individual sports: every GPS-shaped Strava SportType (and the
// legacy ActivityType) maps into one group, so the filter drawer stays usable.
// Non-GPS sports (gym, yoga, court/ball sports, climbing, VirtualRow) are
// deliberately left out (user's call, 2026-09-19) and fall through to Other.
// types[0] is the value stored when a group is picked by hand (manual entry,
// GPX/KML import, the type picker) — hence the synthetic 'Paddling'/
// 'Watersport'/'Skate'/etc. leading some lists. kind:'travel' = transport
// rather than sport (Relic's own modes, which Strava doesn't record).
// speed:true = show km/h, not pace. cycling:true = cadence in rpm.
// Keys are persisted (colours, filters, story type pills) — don't rename them
// (which is why road cycling is still keyed 'Ride').
// Default colours: bright, see docs/brand-colors.md. A hue is deliberately
// REUSED (different shade) by two activities that never sit side by side —
// e.g. Road Bike / Swim / Boat all blue, Run / Motorbike both red. Keep that
// rule if you add a type: pick a new shade in an existing family rather than
// squeezing in a 22nd hue. Users can recolour any type (relic_colors_v1 wins).
const TYPE_CONFIG = {
  Run: { label:'Run', color:'#FF3D3D', types:['Run','TrailRun','VirtualRun'] },
  Ride: { label:'Road Bike', color:'#2196F3', speed:true, cycling:true, types:['Ride','EBikeRide','VirtualRide','Velomobile','Handcycle'] },
  MountainBike: { label:'Mountain Bike', color:'#00C853', speed:true, cycling:true, types:['MountainBikeRide','EMountainBikeRide'] },
  Gravel: { label:'Gravel', color:'#C6D22E', speed:true, cycling:true, types:['GravelRide'] },
  Hike: { label:'Hike', color:'#1B8A3F', types:['Hike','Snowshoe'] },
  Walk: { label:'Walk', color:'#AA47BC', types:['Walk'] },
  Wheelchair: { label:'Wheelchair', color:'#6A3FD1', types:['Wheelchair'] },
  Alpine: { label:'Alpine Ski', color:'#FF2D87', types:['AlpineSki'] },
  Snowboard: { label:'Snowboard', color:'#FF80AB', types:['Snowboard'] },
  Nordic: { label:'Nordic Ski', color:'#00BCD4', types:['NordicSki','RollerSki'] },
  Backcountry: { label:'Backcountry', color:'#3F51B5', types:['BackcountrySki'] },
  Swim: { label:'Swim', color:'#00A3FF', types:['Swim'] },
  Paddling: { label:'Paddling', color:'#00BFA5', speed:true, types:['Paddling','Canoeing','Kayaking','StandUpPaddling','Rowing'] },
  Watersport: { label:'Surf & Sail', color:'#26E0D6', speed:true, types:['Watersport','Surfing','Kitesurf','Windsurf','Sail'] },
  Skate: { label:'Skate', color:'#FFD600', speed:true, types:['Skate','IceSkate','InlineSkate','Skateboard'] },
  Flight: { label:'Flight', color:'#FF9100', kind:'travel', speed:true, types:['Flight'] },
  Drive: { label:'Drive', color:'#546E7A', kind:'travel', speed:true, types:['Drive','Car'] },
  Rail: { label:'Rail', color:'#E040FB', kind:'travel', speed:true, types:['Rail','Train'] },
  Boat: { label:'Boat', color:'#0D47A1', kind:'travel', speed:true, types:['Boat','Ferry'] },
  Motorbike: { label:'Motorbike', color:'#D50000', kind:'travel', speed:true, types:['Motorbike','Motorcycle'] },
  Other: { label:'Other', color:'#9E9E9E', types:['Other'] },
};

// Reverse lookup: Strava type string → TYPE_CONFIG key, built once at startup
const TYPE_GROUP_MAP = {};
Object.entries(TYPE_CONFIG).forEach(([k,cfg]) => cfg.types.forEach(t => { TYPE_GROUP_MAP[t] = k; }));
function getGroup(type) { return TYPE_GROUP_MAP[type] || 'Other'; }
function getColor(type) { return TYPE_CONFIG[getGroup(type)]?.color || '#9E9E9E'; }
function usesSpeed(type) { return !!TYPE_CONFIG[getGroup(type)]?.speed; }
function isCycling(type) { return !!TYPE_CONFIG[getGroup(type)]?.cycling; }
// <option>s for a type <select>: sports, travel, then Other. Value = the
// group's types[0]; `selected` may be any raw type string (e.g. 'GravelRide'),
// it's matched by group.
function typeOptionsHtml(selected) {
  const selGroup = selected ? getGroup(selected) : null;
  const opt = ([k, c]) => `<option value="${c.types[0]}"${k === selGroup ? ' selected' : ''}>${c.label}</option>`;
  const all = Object.entries(TYPE_CONFIG).filter(([k]) => k !== 'Other');
  return `<optgroup label="Sport">${all.filter(([, c]) => c.kind !== 'travel').map(opt).join('')}</optgroup>`
       + `<optgroup label="Travel">${all.filter(([, c]) => c.kind === 'travel').map(opt).join('')}</optgroup>`
       + opt(['Other', TYPE_CONFIG.Other]);
}
