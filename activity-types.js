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
// Default colours: bright Material 600-ish shades, see docs/brand-colors.md —
// the original ten were tested on real outdoors + satellite tiles; users can
// recolour any type (relic_colors_v1 overrides these).
const TYPE_CONFIG = {
  Run: { label:'Run', color:'#E53935', types:['Run','TrailRun','VirtualRun'] },
  Ride: { label:'Road Bike', color:'#1E88E5', speed:true, cycling:true, types:['Ride','EBikeRide','VirtualRide','Velomobile','Handcycle'] },
  MountainBike: { label:'Mountain Bike', color:'#7CB342', speed:true, cycling:true, types:['MountainBikeRide','EMountainBikeRide'] },
  Gravel: { label:'Gravel', color:'#C0CA33', speed:true, cycling:true, types:['GravelRide'] },
  Hike: { label:'Hike', color:'#43A047', types:['Hike','Snowshoe'] },
  Walk: { label:'Walk', color:'#8E24AA', types:['Walk'] },
  Wheelchair: { label:'Wheelchair', color:'#5E35B1', types:['Wheelchair'] },
  Alpine: { label:'Alpine Ski', color:'#D81B60', types:['AlpineSki'] },
  Snowboard: { label:'Snowboard', color:'#EC407A', types:['Snowboard'] },
  Nordic: { label:'Nordic Ski', color:'#00ACC1', types:['NordicSki','RollerSki'] },
  Backcountry: { label:'Backcountry', color:'#3949AB', types:['BackcountrySki'] },
  Swim: { label:'Swim', color:'#039BE5', types:['Swim'] },
  Paddling: { label:'Paddling', color:'#00897B', speed:true, types:['Paddling','Canoeing','Kayaking','StandUpPaddling','Rowing'] },
  Watersport: { label:'Surf & Sail', color:'#4DD0E1', speed:true, types:['Watersport','Surfing','Kitesurf','Windsurf','Sail'] },
  Skate: { label:'Skate', color:'#FDD835', speed:true, types:['Skate','IceSkate','InlineSkate','Skateboard'] },
  Flight: { label:'Flight', color:'#FB8C00', kind:'travel', speed:true, types:['Flight'] },
  Drive: { label:'Drive', color:'#546E7A', kind:'travel', speed:true, types:['Drive','Car'] },
  Rail: { label:'Rail', color:'#6D4C41', kind:'travel', speed:true, types:['Rail','Train'] },
  Boat: { label:'Boat', color:'#283593', kind:'travel', speed:true, types:['Boat','Ferry'] },
  Motorbike: { label:'Motorbike', color:'#F4511E', kind:'travel', speed:true, types:['Motorbike','Motorcycle'] },
  Other: { label:'Other', color:'#8D6E63', types:['Other'] },
};

// Reverse lookup: Strava type string → TYPE_CONFIG key, built once at startup
const TYPE_GROUP_MAP = {};
Object.entries(TYPE_CONFIG).forEach(([k,cfg]) => cfg.types.forEach(t => { TYPE_GROUP_MAP[t] = k; }));
function getGroup(type) { return TYPE_GROUP_MAP[type] || 'Other'; }
function getColor(type) { return TYPE_CONFIG[getGroup(type)]?.color || '#8D6E63'; }
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
