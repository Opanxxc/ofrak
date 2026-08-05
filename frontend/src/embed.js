// A small control surface for a host page that embeds the OFRAK GUI in a
// same-origin iframe. The host calls these directly via
// `iframe.contentWindow.ofrakEmbed.*` — no postMessage, because the embed is
// deliberately same-origin, so a direct method call is simpler than a message
// protocol (real return values, no correlation ids, no handshake).
//
// Every command is a DISPLAY operation: it moves the selection, expands or
// scrolls the tree, or re-syncs a resource's client-side cache. None of them
// POST a mutation to the OFRAK backend, so the surface cannot change binary
// state. Installed from App.svelte, which is the one place that holds both the
// component-local id->RemoteResource map and the module-level stores; every
// handle is passed in, so this module imports nothing OFRAK-specific.

import { get } from "svelte/store";

/**
 * Build the embed control surface.
 *
 * @param {object} h handles supplied by App.svelte
 * @param {(id:string)=>any} h.resourceFor look up a RemoteResource by id (App's `resources`)
 * @param {import('svelte/store').Writable<string|undefined>} h.selected the `selected` store
 * @param {import('svelte/store').Writable<Record<string,any>>} h.resourceNodeDataMap tree-node store
 * @param {import('svelte/store').Writable<number>} h.currentPosition hex-view byte offset store
 * @returns {object} the ofrakEmbed API
 */
export function installEmbed(h) {
  // Select/open a resource. App.svelte's `$: if ($selected ...)` block does the
  // rest (sets selectedResource, updates the #hash, etc.). A resource not yet
  // loaded into the tree (a deep node no ancestor has expanded) is reported so
  // the host can fall back to a #hash load (OFRAK's ancestry loader).
  function select(resource_id) {
    if (!h.resourceFor(resource_id)) {
      return { ok: false, error: "resource not loaded", needsHashLoad: true };
    }
    h.selected.set(resource_id);
    return { ok: true, selected: resource_id };
  }

  // Expand/collapse a tree node = flip its `.collapsed` flag in the store the
  // node reads. Create the entry if the node hasn't mounted yet, so a
  // pre-emptive expand sticks (ResourceTreeNode's reactive block won't
  // overwrite a defined value).
  function setCollapsed(resource_id, collapsed) {
    h.resourceNodeDataMap.update((m) => {
      if (!m[resource_id]) m[resource_id] = {};
      m[resource_id].collapsed = collapsed;
      return m;
    });
    return { ok: true };
  }

  // Scroll the resource's tree row into view. The tree button carries
  // id={selfId}, so a plain DOM lookup finds it.
  function scrollTo(resource_id) {
    const el = document.getElementById(resource_id);
    if (el) el.scrollIntoView({ block: "nearest", inline: "nearest" });
    return { ok: true, scrolled: !!el };
  }

  // Re-sync a resource the host changed out-of-band (an agent driving the same
  // OFRAK backend over MCP) AND every already-expanded descendant, so the whole
  // VISIBLE subtree updates in place — never a reload. Uses OFRAK's own
  // primitives, the same ones the toolbar runs after an unpack:
  //   1. get_latest_model() refetches tags/caption/attributes
  //   2. flush_cache() drops the stale get_children()/get_data caches
  //   3. reassign the node's childrenPromise (what ResourceTreeNode awaits) so
  //      the {#await} re-runs and refreshed children render
  // Collapsed nodes are skipped: they have no rendered children and fetch fresh
  // when first expanded, so they can't be stale — bounding the walk to what is
  // actually on screen.
  async function refresh(resource_id) {
    if (!h.resourceFor(resource_id)) {
      return { ok: false, error: "resource not loaded" };
    }
    const queue = [resource_id];
    const seen = new Set();
    let count = 0;
    while (queue.length) {
      const id = queue.shift();
      if (seen.has(id)) continue;
      seen.add(id);
      const res = h.resourceFor(id);
      if (!res) continue;
      try {
        await res.get_latest_model();
        await res.flush_cache();
      } catch (e) {
        continue; // node gone / refetch failed — skip it, keep walking the rest
      }
      let children = [];
      try {
        children = await res.get_children();
      } catch (e) {
        children = [];
      }
      // Resolve to the fetched array so the {#await} renders without a gap.
      const childrenPromise = Promise.resolve(children);
      h.resourceNodeDataMap.update((m) => {
        if (m[id]) {
          m[id].childrenPromise = childrenPromise;
          m[id].lastModified = true; // OFRAK's "just changed" underline
        }
        return m;
      });
      count += 1;
      // Recurse into children that are currently expanded (visible subtree).
      const map = get(h.resourceNodeDataMap);
      for (const child of children) {
        const cid = child.get_id(); // the tree-node key (ResourceTreeNode selfId)
        const node = map[cid];
        if (node && node.collapsed === false) queue.push(cid);
      }
    }
    return { ok: true, refreshed: resource_id, nodes: count };
  }

  // Scroll the hex view to a byte offset within the currently-displayed
  // resource. Drives the same `currentPosition` store the JumpToOffset box
  // sets, aligned down to the 16-byte row the hex view renders on. Pair with
  // select() to point the hex view at a resource first.
  function scrollToOffset(offset) {
    const n = Number(offset);
    if (!Number.isFinite(n) || n < 0) {
      return { ok: false, error: "invalid offset" };
    }
    const aligned = Math.floor(n / 16) * 16;
    h.currentPosition.set(aligned);
    return { ok: true, offset: aligned };
  }

  // Read the current selection so the host can orient before acting.
  function getState() {
    const id = get(h.selected) ?? null;
    const res = id ? h.resourceFor(id) : undefined;
    return {
      ok: true,
      selected_resource_id: id,
      caption: res?.get_caption?.() ?? null,
    };
  }

  return {
    select,
    expand: (resource_id) => setCollapsed(resource_id, false),
    collapse: (resource_id) => setCollapsed(resource_id, true),
    scrollTo,
    scrollToOffset,
    refresh,
    getState,
  };
}
