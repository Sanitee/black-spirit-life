"use strict";

// Offline WebExtension lifecycle tests. No Firefox, profile, native process,
// HTTP client, or external test dependencies are used.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const extensionRoot = path.resolve(__dirname, "../../windows/session_import/browser_extension/tracker_helper");
const background = fs.readFileSync(path.join(extensionRoot, "background.js"), "utf8");
const bridgeUrl = "moz-extension://offline-test/bridge.html";
const tabKey = "sessionImportBridgeTabId";
const autoKey = "sessionImportAutoConnectedTabId";
const closedKey = "sessionImportBridgeClosed";

function event() {
  const listeners = [];
  return {
    addListener(listener) { listeners.push(listener); },
    async emit(...args) {
      await Promise.all(listeners.map((listener) => listener(...args)));
    }
  };
}

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

async function settle() {
  for (let turn = 0; turn < 4; turn += 1) {
    await new Promise(setImmediate);
  }
}

function fixture(options = {}) {
  const state = {
    windows: options.windows || [{ id: 1, type: "normal", incognito: false, focused: true }],
    tabs: new Map((options.tabs || []).map((tab) => [tab.id, { ...tab }])),
    session: { ...options.session },
    permission: options.permission !== false,
    createGate: null,
    createError: null,
    messageError: null,
    updateError: null,
    windowsError: null,
    storageError: null,
    nextId: 100,
    calls: { create: [], update: [], messages: [], permissions: [], badge: [], title: [], writes: [] },
    events: null
  };
  function load() {
    const events = Object.fromEntries([
      "click", "installed", "startup", "windowCreated", "permissionAdded", "message", "removed"
    ].map((name) => [name, event()]));
    state.events = events;
    const api = {
      action: {
        onClicked: events.click,
        async setBadgeText(value) { state.calls.badge.push(value.text); },
        async setBadgeBackgroundColor() {},
        async setTitle(value) { state.calls.title.push(value.title); }
      },
      runtime: {
        getURL(file) { return "moz-extension://offline-test/" + file; },
        onInstalled: events.installed,
        onStartup: events.startup,
        onMessage: events.message,
        async sendMessage(message) {
          state.calls.messages.push(JSON.parse(JSON.stringify(message)));
          if (state.messageError) throw state.messageError;
        }
      },
      storage: {
        session: {
          async get(keys) {
            if (state.storageError) throw state.storageError;
            return Object.fromEntries((Array.isArray(keys) ? keys : [keys])
              .map((key) => [key, state.session[key]]));
          },
          async set(values) {
            state.calls.writes.push(JSON.parse(JSON.stringify(values)));
            Object.assign(state.session, values);
          },
          async remove(keys) {
            for (const key of Array.isArray(keys) ? keys : [keys]) delete state.session[key];
          }
        }
      },
      permissions: {
        onAdded: events.permissionAdded,
        async contains(request) {
          state.calls.permissions.push(JSON.parse(JSON.stringify(request)));
          return state.permission;
        }
      },
      windows: {
        onCreated: events.windowCreated,
        async getAll(request) {
          assert.deepEqual(Array.from(request.windowTypes), ["normal"]);
          if (state.windowsError) throw state.windowsError;
          return state.windows.map((window) => ({ ...window }));
        }
      },
      tabs: {
        onRemoved: events.removed,
        async get(id) {
          if (!state.tabs.has(id)) throw new Error("Invalid tab ID");
          return { ...state.tabs.get(id) };
        },
        async query(request) {
          assert.equal(request.windowType, "normal");
          return Array.from(state.tabs.values(), (tab) => ({ ...tab }));
        },
        async create(request) {
          state.calls.create.push(JSON.parse(JSON.stringify(request)));
          if (state.createGate) await state.createGate.promise;
          if (state.createError) throw state.createError;
          const tab = { id: state.nextId++, incognito: false, status: "complete", ...request };
          state.tabs.set(tab.id, tab);
          return { ...tab };
        },
        async update(id, updates) {
          state.calls.update.push({ id, ...JSON.parse(JSON.stringify(updates)) });
          if (state.updateError) throw state.updateError;
          if (!state.tabs.has(id)) throw new Error("Invalid tab ID");
          Object.assign(state.tabs.get(id), updates);
        }
      }
    };
    vm.runInNewContext(background, { browser: api }, { filename: "background.js" });
    return api;
  }
  state.load = load;
  state.load();
  state.close = async (id, isWindowClosing = false) => {
    state.tabs.delete(id);
    await state.events.removed.emit(id, { isWindowClosing });
  };
  return state;
}

function assertOnlyBridgeWork(state) {
  for (const created of state.calls.create) {
    assert.deepEqual(created, {
      windowId: created.windowId, url: bridgeUrl, active: false, pinned: true, index: 0
    });
  }
  for (const message of state.calls.messages) {
    assert.equal(message.type, "bridge_reconnect");
    assert.deepEqual(Object.keys(message).sort(), ["bridgeTabId", "type"]);
  }
  for (const update of state.calls.update) {
    assert.equal(update.active, false);
    assert.equal(update.pinned, true);
    assert.equal(update.url, undefined);
  }
  for (const requested of state.calls.permissions) {
    assert.deepEqual(requested, { origins: ["https://garmoth.com/grind-tracker/*"] });
  }
  for (const write of state.calls.writes) {
    assert.ok(Object.keys(write).every((key) => [tabKey, autoKey, closedKey].includes(key)));
  }
}

test("initial add-on load automatically creates one inactive pinned bridge, never Garmoth", async () => {
  const state = fixture();
  await settle();
  assert.equal(state.calls.create.length, 1);
  assert.equal(state.session[tabKey], 100);
  assert.equal(state.calls.messages.length, 0); // bridge.html starts its own native connection.
  assertOnlyBridgeWork(state);
});

test("simultaneous load, install, startup, window and toolbar activations cannot duplicate tabs", async () => {
  const state = fixture();
  state.createGate = deferred();
  await settle();
  const jobs = [
    state.events.installed.emit({ reason: "install", temporary: true }),
    state.events.startup.emit(),
    state.events.windowCreated.emit(state.windows[0]),
    state.events.click.emit({ id: 7, windowId: 1, incognito: false })
  ];
  state.createGate.resolve();
  await Promise.all(jobs);
  assert.equal(state.calls.create.length, 1);
  assert.equal(state.calls.messages.length, 1); // Explicit toolbar reconnect only.
  assertOnlyBridgeWork(state);
});

test("load without a normal window waits and connects when a normal window appears", async () => {
  const state = fixture({ windows: [] });
  await settle();
  assert.equal(state.calls.create.length, 0);
  assert.equal(state.calls.badge.length, 0);
  state.windows.push({ id: 2, type: "normal", incognito: false });
  await state.events.windowCreated.emit(state.windows[0]);
  assert.equal(state.calls.create[0].windowId, 2);
  assertOnlyBridgeWork(state);
});

test("automatic startup ignores private and popup windows and prefers a focused normal window", async () => {
  const state = fixture({ windows: [
    { id: 2, type: "normal", incognito: true, focused: true },
    { id: 3, type: "popup", incognito: false, focused: true }
  ] });
  await settle();
  await Promise.all(state.windows.map((window) => state.events.windowCreated.emit(window)));
  assert.equal(state.calls.create.length, 0);
  state.windows.push({ id: 4, type: "normal", incognito: false, focused: false });
  state.windows.push({ id: 5, type: "normal", incognito: false, focused: true });
  await state.events.windowCreated.emit(state.windows[3]);
  assert.equal(state.calls.create[0].windowId, 5);
  assertOnlyBridgeWork(state);
});

test("toolbar cannot activate from a private, popup or nonexistent window", async () => {
  const state = fixture({ windows: [{ id: 1, type: "normal", incognito: false }], session: { [closedKey]: true } });
  await settle();
  for (const tab of [{ windowId: 1, incognito: true }, { windowId: 2 }, null]) {
    await state.events.click.emit(tab);
  }
  assert.equal(state.calls.create.length, 0);
  assert.equal(state.session[closedKey], true);
  assert.ok(state.calls.title.at(-1).includes("non-private Firefox window"));
});

test("missing host access never creates a bridge or requests broader permission", async () => {
  const state = fixture({ permission: false });
  await settle();
  assert.equal(state.calls.create.length, 0);
  assert.ok(state.calls.title.at(-1).includes("Allow access to garmoth.com"));
  state.permission = true;
  await state.events.permissionAdded.emit({ origins: ["https://garmoth.com/*"] });
  assert.equal(state.calls.create.length, 1);
  assertOnlyBridgeWork(state);
});

test("a restored bridge is discovered without stored ID and reconnected only once", async () => {
  const state = fixture({ tabs: [{ id: 22, windowId: 1, url: bridgeUrl, incognito: false, status: "complete" }] });
  await settle();
  await state.events.installed.emit({ reason: "update" });
  await state.events.startup.emit();
  assert.equal(state.calls.create.length, 0);
  assert.equal(state.session[tabKey], 22);
  assert.deepEqual(state.calls.messages, [{ type: "bridge_reconnect", bridgeTabId: 22 }]);
  assertOnlyBridgeWork(state);
});

test("an existing loading bridge connects itself without racing its not-yet-ready listener", async () => {
  const state = fixture({ tabs: [{ id: 22, windowId: 1, url: bridgeUrl, incognito: false, status: "loading" }] });
  await settle();
  assert.equal(state.calls.create.length, 0);
  assert.equal(state.calls.messages.length, 0);
  assert.equal(state.session[tabKey], 22);
});

test("background event-page reload does not reconnect, reopen or reset the connected badge", async () => {
  const state = fixture();
  await settle();
  await state.events.message.emit({ type: "bridge_status", state: "connected" });
  await settle();
  const badges = state.calls.badge.length;
  state.load();
  await settle();
  assert.equal(state.calls.create.length, 1);
  assert.equal(state.calls.messages.length, 0);
  assert.equal(state.calls.badge.length, badges);
  assert.equal(state.calls.badge.at(-1), "ON");
});

test("manual bridge close remains paused across window creation, permission events and event-page reload", async () => {
  const state = fixture();
  await settle();
  await state.close(100);
  assert.equal(state.session[closedKey], true);
  state.load();
  await state.events.windowCreated.emit(state.windows[0]);
  await state.events.installed.emit({ reason: "update" });
  await state.events.permissionAdded.emit({});
  await settle();
  assert.equal(state.calls.create.length, 1);
  assert.equal(state.calls.messages.length, 0);
  await state.events.click.emit({ id: 7, windowId: 1, incognito: false });
  assert.equal(state.calls.create.length, 2);
  assert.equal(state.session[closedKey], undefined);
  assertOnlyBridgeWork(state);
});

test("a browser restart clears session-only manual-close suppression", async () => {
  const state = fixture();
  await settle();
  await state.close(100);
  state.session = {}; // The storage.session contract, not persistent profile storage.
  state.load();
  await state.events.startup.emit();
  assert.equal(state.calls.create.length, 2);
});

test("closing an entire window does not permanently suppress the next normal window", async () => {
  const state = fixture();
  await settle();
  state.windows = [];
  await state.close(100, true);
  state.windows.push({ id: 2, type: "normal", incognito: false });
  await state.events.windowCreated.emit(state.windows[0]);
  assert.equal(state.calls.create.length, 2);
  assert.equal(state.calls.create[1].windowId, 2);
});

test("close racing the completion of tab creation is recorded before queued automatic activation", async () => {
  const state = fixture();
  state.createGate = deferred();
  await settle();
  const removed = state.events.removed.emit(100, { isWindowClosing: false });
  const installed = state.events.installed.emit({ reason: "install" });
  state.createGate.resolve();
  await Promise.all([removed, installed]);
  state.tabs.delete(100);
  assert.equal(state.session[closedKey], true);
  assert.equal(state.calls.create.length, 1);
});

test("a missed close or replaced saved bridge is not automatically recreated", async () => {
  for (const tabs of [[], [{ id: 22, windowId: 1, url: bridgeUrl + ".not-the-bridge", incognito: false }]]) {
    const state = fixture({ tabs, session: { [tabKey]: 22 } });
    await settle();
    assert.equal(state.calls.create.length, 0);
    assert.equal(state.session[closedKey], true);
    await state.events.click.emit({ windowId: 1, incognito: false });
    assert.equal(state.calls.create.length, 1);
  }
});

test("discovery never adopts a private or lookalike extension tab", async () => {
  const state = fixture({ tabs: [
    { id: 21, windowId: 1, url: bridgeUrl + "/other", incognito: false },
    { id: 22, windowId: 1, url: bridgeUrl, incognito: true },
    { id: 23, windowId: 9, url: bridgeUrl, incognito: false },
    { id: 24, windowId: 1 } // Other sites need not expose URLs to this extension.
  ] });
  await settle();
  assert.equal(state.calls.create.length, 1);
  assert.equal(state.session[tabKey], 100);
});

test("tab-creation failure reports attention and explicit reconnect can recover", async () => {
  const state = fixture();
  state.createError = new Error("Window closed before tab creation");
  await settle();
  assert.equal(state.session[tabKey], undefined);
  assert.ok(state.calls.title.at(-1).includes("Window closed before tab creation"));
  state.createError = null;
  await state.events.click.emit({ windowId: 1 });
  assert.equal(state.session[tabKey], 100);
  assertOnlyBridgeWork(state);
});

test("unsupported autoDiscardable remains nonfatal and does not create another tab", async () => {
  const state = fixture();
  state.updateError = new Error("Unsupported property autoDiscardable");
  await settle();
  await state.events.installed.emit({ reason: "install" });
  assert.equal(state.calls.create.length, 1);
  assert.equal(state.session[tabKey], 100);
  assert.equal(state.calls.badge.includes("!"), false);
});

test("a failed reconnect is not automatically retried on unrelated window events", async () => {
  const state = fixture({ tabs: [{ id: 22, windowId: 1, url: bridgeUrl, status: "complete" }] });
  state.messageError = new Error("Receiving end does not exist");
  await settle();
  await state.events.windowCreated.emit(state.windows[0]);
  state.load();
  await settle();
  assert.equal(state.calls.create.length, 0);
  assert.equal(state.calls.messages.length, 1);
  state.messageError = null;
  await state.events.click.emit({ windowId: 1 });
  assert.equal(state.calls.messages.length, 2);
  assertOnlyBridgeWork(state);
});

test("storage or window failures fail closed without an unhandled rejection", async () => {
  for (const property of ["storageError", "windowsError"]) {
    const state = fixture();
    state[property] = new Error("Offline API failure");
    await settle();
    assert.equal(state.calls.create.length, 0);
    assert.equal(state.calls.badge.at(-1), "!");
    state[property] = null;
    await state.events.click.emit({ windowId: 1 });
    assert.equal(state.calls.create.length, 1);
  }
});

test("unrelated tab removal and messages leave bridge lifecycle intact", async () => {
  const state = fixture();
  await settle();
  await state.events.removed.emit(8, { isWindowClosing: false });
  await state.events.message.emit({ type: "prepare", draft: { shouldNeverBeSent: true } });
  assert.equal(state.session[tabKey], 100);
  assert.equal(state.session[closedKey], undefined);
  assertOnlyBridgeWork(state);
});

test("manifest update preserves exact narrow permissions and disallows private browsing", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(extensionRoot, "manifest.json"), "utf8"));
  assert.equal(manifest.version, "0.1.1");
  assert.deepEqual(manifest.permissions, ["nativeMessaging", "storage"]);
  assert.deepEqual(manifest.host_permissions, ["https://garmoth.com/grind-tracker/*"]);
  assert.equal(manifest.incognito, "not_allowed");
});

test("the actual bridge page startup sends only its activation handshake, not a draft or save", async () => {
  const nativeMessages = [];
  let nativeConnections = 0;
  const context = {
    TextEncoder,
    document: { getElementById() { return { textContent: "", dataset: {} }; } },
    browser: {
      runtime: {
        onMessage: event(),
        async sendMessage(message) { assert.equal(message.type, "bridge_status"); },
        connectNative(name) {
          nativeConnections += 1;
          assert.equal(name, "com.blackspiritlife.session_import.trial");
          return {
            onMessage: event(), onDisconnect: event(),
            postMessage(message) { nativeMessages.push(JSON.parse(JSON.stringify(message))); }
          };
        }
      },
      tabs: { onRemoved: event(), async getCurrent() { return { id: 100, windowId: 1, url: bridgeUrl }; } }
    }
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(extensionRoot, "protocol.js"), "utf8"), context);
  vm.runInContext(fs.readFileSync(path.join(extensionRoot, "bridge.js"), "utf8"), context);
  await settle();
  assert.equal(nativeConnections, 1);
  assert.deepEqual(nativeMessages, [{ type: "activate", protocolVersion: 1 }]);
});
