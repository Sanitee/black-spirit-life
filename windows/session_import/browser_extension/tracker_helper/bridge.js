(function installNativeBridge(global) {
  "use strict";

  const api = global.browser || global.chrome;
  const protocol = global.TrackerProtocol;
  const GARMOTH_BASE_URL = "https://garmoth.com/grind-tracker/";
  const GARMOTH_TAB_KEY = "sessionImportGarmothTabId";
  const CONTENT_READY_TIMEOUT_MS = 12_000;
  const statusElement = document.getElementById("status");

  let nativePort = null;
  let nativeActivated = false;
  let messageQueue = Promise.resolve();
  let bridgeTab = null;

  function delay(milliseconds) {
    return new Promise((resolve) => global.setTimeout(resolve, milliseconds));
  }

  function setStatus(state, text) {
    statusElement.textContent = text;
    statusElement.dataset.state = state;
    api.runtime.sendMessage({ type: "bridge_status", state, detail: text }).catch(() => {});
  }

  function postToNative(message) {
    protocol.assertMessageSize(message);
    if (!nativePort) {
      throw new Error("The desktop bridge is not connected.");
    }
    nativePort.postMessage(message);
  }

  function fixedErrorPayload(error) {
    const result = protocol.errorResult(error);
    return { ok: false, code: result.code, message: result.message };
  }

  function connectNative() {
    if (nativePort) {
      setStatus(
        nativeActivated ? "connected" : "connecting",
        nativeActivated ? "Connected to the desktop app." : "Waiting for the desktop app…"
      );
      return;
    }

    setStatus("connecting", "Connecting to the desktop app…");
    let port;
    try {
      port = api.runtime.connectNative(protocol.NATIVE_HOST_NAME);
    } catch (error) {
      setStatus("error", "Desktop bridge is not installed. Click the toolbar button after installing it.");
      return;
    }
    nativePort = port;
    nativeActivated = false;

    port.onMessage.addListener((message) => {
      messageQueue = messageQueue
        .then(() => handleNativeMessage(message))
        .catch((error) => {
          const requestId = message && typeof message.requestId === "string" ? message.requestId : null;
          const responseType = message && message.type === "prepare"
            ? "prepareResult"
            : message && message.type === "review"
              ? "reviewResult"
              : "statusResult";
          try {
            postToNative({
              type: responseType,
              protocolVersion: 1,
              requestId,
              matched: 0,
              skipped: [],
              ...fixedErrorPayload(error)
            });
          } catch (_) {
            setStatus("error", "The desktop bridge returned an invalid request.");
          }
        });
    });

    port.onDisconnect.addListener(() => {
      if (nativePort !== port) {
        return;
      }
      nativePort = null;
      nativeActivated = false;
      const reason = api.runtime.lastError && api.runtime.lastError.message
        ? api.runtime.lastError.message
        : "Desktop bridge disconnected.";
      setStatus("error", reason + " Click the toolbar button to reconnect.");
    });

    postToNative({ type: "activate", protocolVersion: 1 });
    setStatus("connecting", "Waiting for the desktop app…");
  }

  async function currentManagedGarmothTab() {
    const stored = await api.storage.session.get(GARMOTH_TAB_KEY);
    const tabId = stored[GARMOTH_TAB_KEY];
    if (!Number.isInteger(tabId)) {
      return null;
    }
    try {
      const tab = await api.tabs.get(tabId);
      if (tab.url && protocol.isGarmothTrackerUrl(tab.url, true)) {
        return tab;
      }
    } catch (_) {
      // A closed or replaced tab is recreated for the next draft.
    }
    await api.storage.session.remove(GARMOTH_TAB_KEY);
    return null;
  }

  async function existingGarmothTabInNormalWindow() {
    const [tabs, windows] = await Promise.all([
      api.tabs.query({ url: "https://garmoth.com/grind-tracker*" }),
      api.windows.getAll({ windowTypes: ["normal"] })
    ]);
    const normalWindowIds = new Set(windows.map((entry) => entry.id));
    const candidates = tabs.filter((tab) => {
      return normalWindowIds.has(tab.windowId)
        && tab.url
        && protocol.isGarmothTrackerUrl(tab.url, true);
    });
    return candidates.find((tab) => tab.active === false) || candidates[0] || null;
  }

  async function ensureGarmothTab(targetUrl) {
    let tab = await currentManagedGarmothTab();
    if (!tab) {
      tab = await existingGarmothTabInNormalWindow();
      if (tab) {
        await api.storage.session.set({ [GARMOTH_TAB_KEY]: tab.id });
      }
    }
    const requestedUrl = targetUrl || GARMOTH_BASE_URL;
    const hasBareTrackerPath = tab && tab.url
      && new URL(tab.url).pathname === protocol.GARMOTH_PATH_PREFIX;
    if (tab && ((targetUrl && tab.url !== requestedUrl) || hasBareTrackerPath)) {
      tab = await api.tabs.update(tab.id, { url: requestedUrl, active: false });
    }
    if (!tab) {
      bridgeTab = bridgeTab || await api.tabs.getCurrent();
      if (!bridgeTab || !Number.isInteger(bridgeTab.windowId)) {
        throw new protocol.ProtocolError("needs_browser_window", "No normal Firefox window is available.");
      }
      const windows = await api.windows.getAll({ windowTypes: ["normal"] });
      if (!windows.some((entry) => entry.id === bridgeTab.windowId)) {
        throw new protocol.ProtocolError("needs_browser_window", "No normal Firefox window is available.");
      }
      tab = await api.tabs.create({
        windowId: bridgeTab.windowId,
        url: requestedUrl,
        active: false
      });
      await api.storage.session.set({ [GARMOTH_TAB_KEY]: tab.id });
    }
    try {
      tab = await api.tabs.update(tab.id, { autoDiscardable: false, active: false });
    } catch (_) {
      // Firefox supports autoDiscardable; this fallback keeps the tab inactive elsewhere.
      tab = await api.tabs.update(tab.id, { active: false });
    }
    return tab;
  }

  async function sendWhenContentReady(tabId, message) {
    const deadline = Date.now() + CONTENT_READY_TIMEOUT_MS;
    let lastError = null;
    while (Date.now() < deadline) {
      try {
        const ping = await api.tabs.sendMessage(tabId, { type: "tracker_ping" });
        if (ping && ping.ready === true) {
          return await api.tabs.sendMessage(tabId, message);
        }
      } catch (error) {
        lastError = error;
      }
      await delay(250);
    }

    let tab = null;
    try {
      tab = await api.tabs.get(tabId);
    } catch (_) {
      // Report a stable error below.
    }
    const isTracker = tab && tab.url && protocol.isGarmothTrackerUrl(tab.url, false);
    if (!isTracker) {
      throw new protocol.ProtocolError(
        "garmoth_login_or_route_required",
        "Open and sign in to Garmoth's Grind Tracker once, then retry."
      );
    }
    throw new protocol.ProtocolError(
      "garmoth_not_ready",
      lastError && lastError.message ? "Garmoth did not become ready in time." : "Garmoth did not become ready."
    );
  }

  async function prepareDraft(rawDraft) {
    const draft = protocol.normalizeDraft(rawDraft);
    const tab = await ensureGarmothTab(draft.target.url);
    const response = await sendWhenContentReady(tab.id, { type: "prepare_draft", draft });
    if (!response || response.ok !== true) {
      const code = response && response.code ? response.code : "content_script_failed";
      const message = response && response.message ? response.message : "Garmoth could not prepare the draft.";
      throw new protocol.ProtocolError(code, message);
    }
    return response;
  }

  async function reviewDraft(draftId) {
    const tab = await currentManagedGarmothTab() || await existingGarmothTabInNormalWindow();
    if (!tab) {
      throw new protocol.ProtocolError("no_prepared_tab", "No prepared Garmoth draft is open.");
    }
    const status = await sendWhenContentReady(tab.id, { type: "tracker_status" });
    if (!status || !status.draftId) {
      throw new protocol.ProtocolError("no_prepared_draft", "The prepared Garmoth form is no longer open. Prepare the session again.");
    }
    if (!draftId || status.draftId !== draftId) {
      throw new protocol.ProtocolError("draft_mismatch", "The open Garmoth draft does not match this session.");
    }
    await api.tabs.update(tab.id, { active: true });
    await api.windows.update(tab.windowId, { focused: true });
    return { tabId: tab.id };
  }

  async function handleNativeMessage(message) {
    protocol.assertMessageSize(message);
    if (!message || typeof message !== "object") {
      throw new protocol.ProtocolError("invalid_message", "Native message must be an object.");
    }
    const requestId = typeof message.requestId === "string" ? message.requestId.slice(0, 100) : null;

    if (message.type === "activated") {
      if (message.protocolVersion !== 1) {
        throw new protocol.ProtocolError("protocol_mismatch", "The desktop bridge uses a different protocol version.");
      }
      nativeActivated = true;
      setStatus("connected", "Connected to the desktop app.");
      return;
    }
    if (message.type === "status") {
      const tab = await currentManagedGarmothTab();
      postToNative({
        type: "statusResult",
        protocolVersion: 1,
        requestId,
        ok: true,
        state: "connected",
        hasPreparedTab: Boolean(tab),
        matched: 0,
        skipped: []
      });
      return;
    }
    if (message.type === "review") {
      try {
        await reviewDraft(typeof message.draftId === "string" ? message.draftId : null);
        postToNative({
          type: "reviewResult",
          protocolVersion: 1,
          requestId,
          draftId: typeof message.draftId === "string" ? message.draftId : null,
          ok: true,
          matched: 0,
          skipped: []
        });
      } catch (error) {
        postToNative({
          type: "reviewResult",
          protocolVersion: 1,
          requestId,
          draftId: typeof message.draftId === "string" ? message.draftId : null,
          matched: 0,
          skipped: [],
          ...fixedErrorPayload(error)
        });
      }
      return;
    }
    if (message.type !== "prepare") {
      postToNative({
        type: "statusResult",
        protocolVersion: 1,
        requestId,
        matched: 0,
        skipped: [],
        ok: false,
        code: "unsupported_message",
        message: "The native message type is not supported."
      });
      return;
    }

    setStatus("connecting", "Preparing a draft in the background…");
    try {
      const result = await prepareDraft(message.draft);
      postToNative({
        type: "prepareResult",
        protocolVersion: 1,
        requestId,
        draftId: result.draftId,
        ok: true,
        matched: result.matched.length,
        skipped: result.skipped,
        warnings: result.warnings,
        notesVerified: result.notesVerified || [],
        notesStatus: result.notesStatus || "not_needed"
      });
      setStatus("connected", "Draft prepared. Review it in Garmoth before saving.");
    } catch (error) {
      postToNative({
        type: "prepareResult",
        protocolVersion: 1,
        requestId,
        draftId: message.draft && typeof message.draft.draftId === "string"
          ? message.draft.draftId.slice(0, 100)
          : null,
        matched: 0,
        skipped: [],
        ...fixedErrorPayload(error)
      });
      setStatus("error", "Draft could not be prepared. Check the desktop app for details.");
    }
  }

  api.runtime.onMessage.addListener((message) => {
    if (!message || message.type !== "bridge_reconnect") {
      return undefined;
    }
    bridgeTab = null;
    api.tabs.getCurrent().then((tab) => {
      if (!message.bridgeTabId || tab.id === message.bridgeTabId) {
        connectNative();
      }
    });
    return undefined;
  });

  api.tabs.onRemoved.addListener(async (tabId) => {
    const stored = await api.storage.session.get(GARMOTH_TAB_KEY);
    if (stored[GARMOTH_TAB_KEY] === tabId) {
      await api.storage.session.remove(GARMOTH_TAB_KEY);
    }
  });

  api.tabs.getCurrent().then((tab) => {
    bridgeTab = tab;
    connectNative();
  });
})(globalThis);
