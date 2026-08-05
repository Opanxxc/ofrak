import { animals, otherColors } from "./animals.js";

import { writable, derived } from "svelte/store";

// Currently selected resource ID
export const selected = writable(undefined);

// Currently selected resource object
export const selectedResource = writable(undefined);

// Currently selected project ID
export const selectedProject = writable(undefined);

// User-generated OFRAK script (array of lines)
export const script = writable([]);

export function loadSettings(forceReset) {
  const defaultSettings = {
    background: "#000000",
    foreground: "#ffffff",
    selected: otherColors[0],
    highlight: otherColors[1],
    comment: "#eb8e5b",
    lastModified: "#dc4e47",
    allModified: "#fdb44e",
    accentText: animals[1].color,
    colors: otherColors, // animals.map(a => a.color).concat(otherColors),

    experimentalFeatures: false,

    showDevSettings: false,
    // Points the OFRAK frontend to a seperate backend server. When empty, uses
    // the same host and port as the frontend.
    backendUrl: "",
  };

  if (forceReset) {
    return defaultSettings;
  }
  try {
    const prevSettings =
      JSON.parse(window.localStorage.getItem("settings")) || defaultSettings;
    // allows fields in defaultSettings which don't exist in prevSettings (i.e. a new setting has
    // been introduced since user saved their own settings) to still be populated, with default.
    return { ...defaultSettings, ...prevSettings };
  } catch {
    return defaultSettings;
  }
}

export let settings = writable(loadSettings());

// The base URL every backend request is built on. An explicit `backendUrl`
// setting (a separate host/port) wins; otherwise it is derived from the path
// the GUI is served under, so requests reach the backend whether the app is at
// the origin root (`""`) or reverse-proxied under a subpath
// (`/some/prefix`). Deriving here — rather than defaulting the persisted
// setting — keeps a per-deployment subpath out of saved settings, so it can
// never leak between contexts that share an origin.
function servedBasePath() {
  if (typeof window === "undefined") {
    return "";
  }
  // Directory the current document was served from (strip the file segment),
  // then drop the trailing slash so callers append `/<route>`.
  const dir = window.location.pathname.replace(/[^/]*$/, "");
  return dir.replace(/\/$/, "");
}

export const backendUrl = derived(
  settings,
  ($settings) => $settings.backendUrl || servedBasePath()
);

export let resourceNodeDataMap = writable({});

export let dataLength = writable(undefined);
