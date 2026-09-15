"use strict";
// Test-only DOM/clock fixture; shipped scripts execute in an isolated VM.
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const extensionRoot = path.resolve(__dirname, "../../windows/session_import/browser_extension/tracker_helper");
const writtenAttribute = "data-bsl-session-import-written";

function fixture({ initialSpot = "77", open = true, tooltipOnly = false, previouslyWritten = false } = {}) {
  const writes = [];
  const observers = new Set();
  let recording = false;
  let now = 0;
  let sequence = 0;
  const timers = [];
  const record = (target, kind, name, value) => {
    if (recording) writes.push({ target: target.id || target.tagName, kind, name, value });
  };
  const notify = () => {
    for (const observer of observers) {
      queueMicrotask(() => { if (observer.active) observer.callback([]); });
    }
  };
  class Element {
    constructor(tag, attributes = {}, text = "") {
      this.tagName = tag.toUpperCase();
      this.attributes = new Map(Object.entries(attributes));
      this.children = [];
      this.parentElement = null;
      this.ownerDocument = null;
      this.listeners = new Map();
      this.hidden = false;
      this.disabled = false;
      this._text = text;
    }
    get id() { return this.getAttribute("id"); }
    get textContent() { return this._text + this.children.map((child) => child.textContent).join(""); }
    set textContent(value) { record(this, "text", "textContent", String(value)); this._text = String(value); notify(); }
    get isContentEditable() { return this.getAttribute("contenteditable") === "true"; }
    get isConnected() { return this === document.documentElement || Boolean(this.parentElement?.isConnected); }
    getAttribute(name) { return this.attributes.has(name) ? this.attributes.get(name) : null; }
    setAttribute(name, value) { record(this, "attribute", name, String(value)); this.attributes.set(name, String(value)); notify(); }
    removeAttribute(name) { record(this, "removeAttribute", name, undefined); this.attributes.delete(name); notify(); }
    appendChild(child) {
      child.parentElement = this;
      const assignDocument = (node) => { node.ownerDocument = this.ownerDocument; node.children.forEach(assignDocument); };
      assignDocument(child);
      this.children.push(child);
      notify();
      return child;
    }
    getClientRects() { return this.isConnected ? [{}] : []; }
    getBoundingClientRect() { return {left:0,top:0,width:100,height:30}; }
    contains(element) { for (let node = element; node; node = node.parentElement) if (node === this) return true; return false; }
    matches(selector) {
      return selector.split(",").some((part) => {
        let simple = part.trim();
        const exclusions = Array.from(simple.matchAll(/:not\(([^)]+)\)/g), (match) => match[1]);
        simple = simple.replace(/:not\([^)]+\)/g, "");
        if (exclusions.some((excluded) => this.matches(excluded))) return false;
        const tag = simple.match(/^[a-z][a-z0-9-]*/i)?.[0];
        if (tag && tag.toUpperCase() !== this.tagName) return false;
        if (simple.startsWith(".")) return (this.getAttribute("class") || "").split(/\s+/).includes(simple.slice(1));
        return Array.from(simple.matchAll(/\[([^=\]]+)(?:=['"]([^'"]*)['"])?\]/g)).every((match) => {
          return match[2] === undefined ? this.getAttribute(match[1]) !== null : this.getAttribute(match[1]) === match[2];
        });
      });
    }
    querySelectorAll(selector) {
      const result = [];
      const visit = (node) => { for (const child of node.children) { if (child.matches(selector)) result.push(child); visit(child); } };
      visit(this);
      return result;
    }
    closest(selector) { for (let node = this; node; node = node.parentElement) if (node.matches(selector)) return node; return null; }
    addEventListener(name, listener) { if (!this.listeners.has(name)) this.listeners.set(name, []); this.listeners.get(name).push(listener); }
    dispatchEvent(event) {
      record(this, "event", event.type, undefined);
      for (const listener of this.listeners.get(event.type) || []) listener(event);
      return true;
    }
    click() { record(this, "click", "click", undefined); for (const listener of this.listeners.get("click") || []) listener({ type: "click" }); }
    get src() { return this.getAttribute("src") || ""; }
  }
  class HTMLInputElement extends Element {
    constructor(attributes) { super("input", attributes); this._value = ""; }
    get value() { return this._value; }
    set value(value) { record(this, "value", "value", String(value)); this._value = String(value); }
    get type() { return this.getAttribute("type") || "text"; }
    get labels() { return []; }
  }
  class HTMLTextAreaElement extends HTMLInputElement {}
  class HTMLSelectElement extends Element {
    constructor(attributes) { super("select", attributes); this._value = ""; }
    get options() { return this.children; }
    get value() { return this._value || this.options[0]?.value || ""; }
    set value(value) { record(this, "value", "value", String(value)); this._value = String(value); }
    get selectedIndex() { return this.options.findIndex((option) => option.value === this.value); }
    get labels() { return []; }
  }
  class HTMLButtonElement extends Element {
    constructor(attributes, text) { super("button", attributes, text); }
    get form() { return this.parentElement?.closest("form") || null; }
    get type() { return this.getAttribute("type") || "submit"; }
  }
  class MutationObserver {
    constructor(callback) { this.callback = callback; this.active = false; }
    observe() { this.active = true; observers.add(this); }
    disconnect() { this.active = false; observers.delete(this); }
  }
  class Event { constructor(type, options) { this.type = type; Object.assign(this, options); } }
  const document = {
    documentElement: null, body: null,
    querySelectorAll(selector) { return this.documentElement.querySelectorAll(selector); },
    getElementById(id) { return this.querySelectorAll("[id]").find((node) => node.id === id) || null; },
    elementFromPoint() { return this.hitElement || null; },
    createTreeWalker(root) { const nodes = root.querySelectorAll("*"); let index = 0; return { nextNode() { return nodes[index++] || null; } }; }
  };
  document.documentElement = new Element("html");
  document.documentElement.ownerDocument = document;
  document.body = document.documentElement.appendChild(new Element("body"));
  document.body.appendChild(new Element("h1", {}, "GRIND TRACKER"));
  const opener = document.body.appendChild(new HTMLButtonElement({ id: "add", type: "button" }, "Add session"));
  const editor = new Element("div", { id: "editor", role: "dialog", "aria-label": "Add session" });
  editor.ownerDocument = document;
  const form = editor.appendChild(new Element("form"));
  const select = form.appendChild(new HTMLSelectElement({ id: "spot", name: "spot" }));
  for (const [value, label] of [["1", "Wolves"], ["77", "Rusalka's Coral"]]) {
    const option = select.appendChild(new Element("option", { value }, label));
    Object.defineProperty(option, "value", { get() { return this.getAttribute("value"); } });
  }
  select.value = initialSpot;
  const fields = {};
  for (const name of ["duration-minutes", "mastery", "energy-spent"]) {
    fields[name] = form.appendChild(new HTMLInputElement({ id: name, name, type: "number" }));
  }
  const loot = form.appendChild(new Element("div", tooltipOnly ? {} : { "data-item-id": "coral-01" }));
  const marker = loot.appendChild(new Element("img", tooltipOnly ? { id: "marker" } : { id: "marker", alt: "Rusalka's Coral" }));
  fields.loot = loot.appendChild(new HTMLInputElement({ id: "loot", type: "number", "aria-label": tooltipOnly ? "Quantity" : "Rusalka's Coral amount" }));
  fields.loot.value = "7";
  const save = form.appendChild(new HTMLButtonElement({ id: "save", type: "submit" }, "Save"));
  if (previouslyWritten) {
    select.setAttribute(writtenAttribute, "true");
    fields.loot.setAttribute(writtenAttribute, "true");
  }
  if (open) document.body.appendChild(editor);
  const listeners = [];
  const context = {
    Element, HTMLInputElement, HTMLTextAreaElement, HTMLSelectElement, HTMLButtonElement,
    MutationObserver, Event, MouseEvent: Event, NodeFilter: { SHOW_ELEMENT: 1 },
    URL, TextEncoder, document,
    location: new URL("https://garmoth.com/grind-tracker/example"),
    getComputedStyle() { return { display: "block", visibility: "visible", opacity: "1" }; },
    setTimeout(callback, milliseconds) { timers.push({ id: ++sequence, at: now + milliseconds, callback }); return sequence; },
    browser: { runtime: { onMessage: { addListener(listener) { listeners.push(listener); } } } }
  };
  vm.createContext(context);
  for (const file of ["protocol.js", "content.js"]) vm.runInContext(fs.readFileSync(path.join(extensionRoot, file), "utf8"), context, { filename: file });
  recording = true;
  const state = {
    context, document, editor, opener, select, fields, marker, save, writes, listeners,
    Element, HTMLInputElement, HTMLButtonElement,
    discover(draft) { return context.TrackerContentTest.discoverPreparation(document, draft || this.draft()); },
    get now() { return now; },
    get observerCount() { return observers.size; },
    fixtureWrite(callback) { recording = false; try { callback(); } finally { recording = true; } },
    async advance(milliseconds) {
      await settle();
      const target = now + milliseconds;
      while (true) {
        timers.sort((left, right) => left.at - right.at || left.id - right.id);
        const next = timers[0];
        if (!next || next.at > target) break;
        timers.shift(); now = next.at; next.callback(); await settle();
      }
      now = target; await settle();
    },
    draft(patch = {}) {
      const value = {
        schemaVersion: 1, draftId: "fixture-cancellation", createdAtUtc: "2026-09-14T08:00:00Z", expiresAtUtc: "2099-01-01T00:00:00Z",
        target: { provider: "garmoth", activity: "gathering", spotId: "77", spotName: "Rusalka's Coral", url: "https://garmoth.com/grind-tracker/example/spot/77" },
        session: { durationSeconds: 3600, mastery: 2000, energySpent: 321, agrisUsed: null, items: [{ itemId: tooltipOnly ? "dust-01" : "coral-01", subKey: 0, name: tooltipOnly ? "Ancient Spirit Dust" : "Rusalka's Coral", quantity: 59 }] },
        behavior: { skipUnsupported: true, submit: false }, ...patch
      };
      // The real protocol intentionally rejects foreign/prototyped objects.
      // Decode wire JSON in its own realm instead of weakening that check.
      context.draftJson = JSON.stringify(value);
      return vm.runInContext("JSON.parse(draftJson)", context);
    },
    prepare(options, draft) { return context.TrackerContentTest.prepareDraftIn(document, draft || this.draft(), options); },
    cancelError() { return new context.TrackerProtocol.ProtocolError("preparation_cancelled", "Preparation cancelled."); }
  };
  return state;
}

async function settle() { await new Promise(setImmediate); }
module.exports = { fixture, settle, writtenAttribute };
