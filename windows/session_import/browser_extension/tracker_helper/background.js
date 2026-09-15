(function installToolbarActivation(global) {
  "use strict";

  const api = global.browser || global.chrome;
  const BRIDGE_PAGE = "bridge.html";
  const BRIDGE_TAB_KEY = "sessionImportBridgeTabId";
  const BRIDGE_AUTO_TAB_KEY = "sessionImportAutoConnectedTabId";
  const BRIDGE_CLOSED_KEY = "sessionImportBridgeClosed";
  let operations = Promise.resolve();

  // Event pages can wake for several events at once. Tab creation, remembering
  // a user close, and explicit reconnect must share the same ordered lifecycle.
  function enqueue(operation) {
    operations = operations.then(operation).catch((error) =>
      setActionState("error", error.message || String(error)).catch(() => {})
    );
    return operations;
  }

  function isBridgeTab(tab, windows) {
    return tab && !tab.incognito &&
      tab.url === api.runtime.getURL(BRIDGE_PAGE) &&
      windows.some((entry) => entry.id === tab.windowId);
  }

  async function setActionState(state, detail) {
    const states = {
      idle: { badge: "", color: "#60756b", title: "Connect Session Import Helper" },
      connecting: { badge: "…", color: "#b69239", title: "Connecting Session Import Helper" },
      connected: { badge: "ON", color: "#397c59", title: "Session Import Helper is connected" },
      error: { badge: "!", color: "#a84d4d", title: "Session Import Helper needs attention" }
    };
    const selected = states[state] || states.error;
    const suffix = detail ? ": " + detail : "";
    await Promise.allSettled([
      api.action.setBadgeText({ text: selected.badge }),
      api.action.setBadgeBackgroundColor({ color: selected.color }),
      api.action.setTitle({ title: selected.title + suffix })
    ]);
  }

  async function storedBridgeTab(windows) {
    const stored = await api.storage.session.get(BRIDGE_TAB_KEY);
    const tabId = stored[BRIDGE_TAB_KEY];
    if (!Number.isInteger(tabId)) {
      // Session restore or an add-on reload can leave the extension tab alive
      // without its remembered ID. Inspect only our exact extension URL.
      const tabs = await api.tabs.query({ windowType: "normal" });
      const existing = tabs.find((tab) => isBridgeTab(tab, windows));
      if (existing) {
        await api.storage.session.set({ [BRIDGE_TAB_KEY]: existing.id });
      }
      return existing || null;
    }
    try {
      const tab = await api.tabs.get(tabId);
      if (isBridgeTab(tab, windows)) {
        return tab;
      }
    } catch (_) {
      // The saved tab was closed while the event page was asleep.
    }
    // If the event page missed a close, do not immediately undo the user's
    // choice. session storage is memory-only and clears on browser restart.
    await api.storage.session.set({ [BRIDGE_CLOSED_KEY]: true });
    await api.storage.session.remove([BRIDGE_TAB_KEY, BRIDGE_AUTO_TAB_KEY]);
    return null;
  }

  async function createBridgeTab(windowId) {
    const tab = await api.tabs.create({
      windowId,
      url: api.runtime.getURL(BRIDGE_PAGE),
      active: false,
      pinned: true,
      index: 0
    });
    await api.storage.session.set({
      [BRIDGE_TAB_KEY]: tab.id,
      [BRIDGE_AUTO_TAB_KEY]: tab.id
    });
    try {
      await api.tabs.update(tab.id, { autoDiscardable: false, active: false, pinned: true });
    } catch (_) {
      // autoDiscardable is Firefox-specific. The pinned extension tab still works without it.
    }
    return tab;
  }

  async function activate(sourceTab, manual = false) {
    const stored = await api.storage.session.get(BRIDGE_CLOSED_KEY);
    if (!manual && stored[BRIDGE_CLOSED_KEY]) {
      return;
    }
    const windows = (await api.windows.getAll({ windowTypes: ["normal"] }))
      .filter((entry) => entry.type === "normal" && !entry.incognito);
    const targetWindow = manual
      ? windows.find((entry) => sourceTab && !sourceTab.incognito && entry.id === sourceTab.windowId)
      : windows.find((entry) => entry.focused) || windows[0];
    if (!targetWindow) {
      if (manual) {
        throw new Error("Open a normal, non-private Firefox window before connecting the helper.");
      }
      return; // onCreated will try again when a normal window becomes available.
    }
    const hasGarmothAccess = await api.permissions.contains({
      origins: ["https://garmoth.com/grind-tracker/*"]
    });
    if (!hasGarmothAccess) {
      throw new Error("Allow access to garmoth.com in the extension settings.");
    }

    const bridgeTab = await storedBridgeTab(windows);
    if (manual) {
      await api.storage.session.remove(BRIDGE_CLOSED_KEY);
    } else {
      const state = await api.storage.session.get([BRIDGE_CLOSED_KEY, BRIDGE_AUTO_TAB_KEY]);
      if (state[BRIDGE_CLOSED_KEY] || (bridgeTab && state[BRIDGE_AUTO_TAB_KEY] === bridgeTab.id)) {
        return;
      }
    }
    await setActionState("connecting");
    if (!bridgeTab) {
      await createBridgeTab(targetWindow.id);
      return;
    }

    await api.storage.session.set({ [BRIDGE_AUTO_TAB_KEY]: bridgeTab.id });
    try {
      await api.tabs.update(bridgeTab.id, { autoDiscardable: false, active: false, pinned: true });
    } catch (_) {
      // Keeping the existing tab inactive is enough on browsers without autoDiscardable.
    }
    // A loading/restored extension page connects itself when ready. Do not
    // race its listener or turn a normal load into a false connection error.
    if (bridgeTab.status !== "loading") {
      await api.runtime.sendMessage({ type: "bridge_reconnect", bridgeTabId: bridgeTab.id });
    }
  }

  api.action.onClicked.addListener((tab) => {
    return enqueue(() => activate(tab, true));
  });

  api.runtime.onInstalled.addListener(() => enqueue(() => activate()));
  api.runtime.onStartup.addListener(() => enqueue(() => activate()));
  api.windows.onCreated.addListener((window) => {
    if (window.type === "normal" && !window.incognito) {
      return enqueue(() => activate());
    }
    return undefined;
  });
  api.permissions.onAdded.addListener(() => enqueue(() => activate()));

  api.runtime.onMessage.addListener((message) => {
    if (!message || message.type !== "bridge_status") {
      return undefined;
    }
    setActionState(message.state, message.detail || "");
    return undefined;
  });

  api.tabs.onRemoved.addListener((tabId, removeInfo) => enqueue(async () => {
    const stored = await api.storage.session.get(BRIDGE_TAB_KEY);
    if (stored[BRIDGE_TAB_KEY] === tabId) {
      if (!removeInfo || !removeInfo.isWindowClosing) {
        await api.storage.session.set({ [BRIDGE_CLOSED_KEY]: true });
      }
      await api.storage.session.remove([BRIDGE_TAB_KEY, BRIDGE_AUTO_TAB_KEY]);
      await setActionState("idle");
    }
  }));

  // Also covers a temporary add-on reload in an already open browser. The
  // session keys prevent event-page wakes from reconnecting or reopening it.
  enqueue(() => activate());
})(globalThis);
