"use strict";

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const API_TOKEN_HEADER = "X-BSL-API-Token";
const API_TOKEN = new URLSearchParams(window.location.hash.replace(/^#/, "")).get("apiToken") || "";

const state = {
  data: null,
  zones: [],
  nodes: [],
  fish: [],
  zoneByRgb: new Map(),
  fishById: new Map(),
  method: { map: "rod", capture: "rod", stats: "rod" },
  captureEquipment: { rod: "Balenos Rod", harpoon: "Thin Harpoon" },
  fishingProfiles: [],
  legacyMigration: null,
  activeProfileId: "",
  profileEditingId: "",
  profileEditorBaseline: null,
  captureProfileId: "",
  captureAutoFishingReductionPercent: 0,
  captureTimeMode: "duration",
  timePicker: { target: "", stage: "hour", hour: 0, minute: 0, pendingDate: null, pointerId: null, frame: 0, pendingPoint: null },
  editingSessionId: "",
  editingProfileDetached: false,
  captureLocation: null,
  captureLastValidLocation: null,
  captureSuggestions: [],
  captureSuggestionIndex: -1,
  pendingMapLocation: null,
  locationResolveRequestId: 0,
  files: [],
  review: null,
  sessions: [],
  journalFilters: { mode: "catches", from: "", to: "", status: "all" },
  salePlanner: { sessionId: "", offers: [], selected: 0 },
  statsSelected: null,
  statsLocation: null,
  statsSuggestions: [],
  statsSuggestionIndex: -1,
  statsLocationResolveRequestId: 0,
  selectedZone: null,
  selectedPoint: null,
  filteredZones: [],
  hoveredZone: null,
  spotRequestId: 0,
  regionVisible: false,
  regionOpacityPercent: 35,
  uiOpacityPercent: 60,
  settlementVisible: true,
  map: {
    width: 11560,
    height: 10540,
    tileSize: 512,
    scale: .1,
    minScale: .06,
    maxScale: 3.2,
    offsetX: 0,
    offsetY: 0,
    drag: null,
    tileLevel: null,
    displayedLevel: null,
    overviewReady: false,
    detailBaseReady: false,
    overviewExpected: 0,
    overviewTiles: new Map(),
    fallbackTiles: new Map(),
    tiles: new Map(),
    regionTiles: new Map(),
    highlightTiles: new Map(),
    worldTransform: null,
    visibleFrame: null,
  },
};

const TOOL_ITEMS = Object.freeze({
  "Balenos Rod": { icon: 16162, shortLabel: "Balenos", gradeClass: "grade-high-quality" },
  "Triple-Float Rod": { icon: 16153, shortLabel: "Triple-Float", gradeClass: "grade-rare" },
  "Thin Harpoon": { icon: 16154, shortLabel: "Thin", gradeClass: "grade-general" },
  "Thick Harpoon": { icon: 16155, shortLabel: "Thick", gradeClass: "grade-high-quality" },
  "Manos Harpoon": { icon: 16478, shortLabel: "Manos", gradeClass: "grade-high-quality" },
});
const MAX_SESSION_MINUTES = 7 * 24 * 60;
const TRADE_WAYPOINT_IDS = Object.freeze([1, 61, 301, 601, 604, 608, 1101, 1301, 1380, 1623, 1649, 1691, 1750, 1785, 1834, 1852, 1853, 1858, 2001, 2052]);
const SETTLEMENT_PRIORITY = new Map(Object.freeze([
  "Velia", "Heidel", "Calpheon City", "Altinova", "Valencia City", "Seoul", "Grána", "Duvencrune", "O'draxxia", "Eilton", "Asparkan", "Hakinza Sanctuary", "Oquilla's Eye",
  "Bukpo", "Nampo's Moodle Village", "Nopsae's Byeot County", "Olvia", "Port Epheria", "Shakatu", "Arehaza", "Tarif", "Old Wisdom Tree", "Velandir", "Yukjo Street", "Iliya Island",
].map((name, index) => [name, 1000 - index])));
const WORLD_UNITS_PER_DISTANCE_PERCENT = 14705;

const els = {};
let toastTimer = 0;
let locationResolveTimer = 0;
let statsLocationResolveTimer = 0;
let mapRenderFrame = 0;
let mapPanFrame = 0;
let mapWheelFrame = 0;
let pendingMapWheel = null;
let captureDragDepth = 0;

const DESKTOP_CONTENT_WIDTH = 1440;
const UI_OPACITY_STORAGE_KEY = "fish-companion-ui-opacity";
const UI_OPACITY_STORAGE_VERSION_KEY = "fish-companion-ui-opacity-version";
const UI_OPACITY_STORAGE_VERSION = "1";
const UI_TRANSPARENCY_STORAGE_KEY = "fish-companion-ui-transparency";
const UI_TRANSPARENCY_STORAGE_VERSION_KEY = "fish-companion-ui-transparency-version";
const UI_TRANSPARENCY_STORAGE_VERSION = "2";
const UI_TRANSPARENCY_LEGACY_MAX = 40;
const UI_OPACITY_MIN = 0;
const UI_OPACITY_MAX = 100;
const UI_OPACITY_DEFAULT = 60;
const UI_MATERIAL_OPACITY_FLOOR = .02;
let desktopScalingInitialized = false;
let desktopScalingObserver = null;
let desktopScalingFrame = 0;

function desktopLayoutMetrics(width, height) {
  const viewWidth = Number(width);
  const viewHeight = Number(height);
  if (!Number.isFinite(viewWidth) || !Number.isFinite(viewHeight) || viewWidth <= 0 || viewHeight <= 0) return null;
  const scale = Math.min(1, viewWidth / DESKTOP_CONTENT_WIDTH);
  return { scale, logicalWidth: Math.max(DESKTOP_CONTENT_WIDTH, viewWidth), logicalHeight: viewHeight / scale };
}

function desktopContentPages() {
  return typeof els.app?.querySelectorAll === "function" ? [...els.app.querySelectorAll(".content-page")] : [];
}

function setDesktopLayoutProperty(node, property, value) {
  if (typeof node?.style?.setProperty !== "function") return;
  if (node.style.getPropertyValue?.(property) !== value) node.style.setProperty(property, value);
}

function updateDesktopScaling() {
  const app = els.app;
  if (!app) return;
  const header = app.querySelector?.(".app-header");
  const headerMetrics = desktopLayoutMetrics(app.clientWidth, 68);
  if (header && headerMetrics) {
    setDesktopLayoutProperty(header, "--header-scale", String(headerMetrics.scale));
    setDesktopLayoutProperty(header, "--header-width", `${headerMetrics.logicalWidth}px`);
  }
  // Read page height after the header's zoom is applied. Hidden pages report
  // zero dimensions and retain their draft/UI state until they are shown.
  for (const page of desktopContentPages()) {
    const metrics = desktopLayoutMetrics(page.clientWidth, page.clientHeight);
    if (!metrics) continue;
    setDesktopLayoutProperty(page, "--content-scale", String(metrics.scale));
    setDesktopLayoutProperty(page, "--content-view-height", `${metrics.logicalHeight}px`);
  }
}

function scheduleDesktopScaling() {
  if (desktopScalingFrame) return;
  if (typeof window.requestAnimationFrame !== "function") {
    updateDesktopScaling();
    return;
  }
  desktopScalingFrame = window.requestAnimationFrame(() => {
    desktopScalingFrame = 0;
    updateDesktopScaling();
  });
}

function initializeDesktopScaling() {
  if (!els.app) return;
  updateDesktopScaling();
  if (desktopScalingInitialized) return;
  desktopScalingInitialized = true;
  if (typeof ResizeObserver === "function") {
    desktopScalingObserver = new ResizeObserver(scheduleDesktopScaling);
    desktopScalingObserver.observe(els.app);
    desktopContentPages().forEach(page => desktopScalingObserver.observe(page));
  }
  window.addEventListener?.("resize", scheduleDesktopScaling);
}

function cacheElements() {
  [
    "app", "boot", "bootText", "sourceState", "profileButton", "profileButtonTool", "profileButtonName", "profileModal", "profileClose", "profileNew", "profileList", "profileMigrationNotice", "profileMigrationTitle", "profileMigrationSummary", "profileMigrationPath", "profileMigrationCopy", "profileForm", "profileName", "profileActiveBadge", "profileMethod", "profileEquipment", "profileEquipmentText", "profileEquipmentOptions", "profileMastery", "profileFishingRank", "profileFishingLevel", "profileAutoDelayField", "profileAutoReductionPercent", "profileAutoDelay", "profileTradingRank", "profileTradingLevel", "profileBargainPreview", "profileNotes", "profileDelete", "profileCancel", "profileSave", "mapTools", "mapViewport", "mapVisibleFrame", "mapWorld", "overviewLayer", "fallbackLayer", "tileLayer", "regionLayer", "zoneHighlightLayer", "spotPointLayer", "settlementLayer", "mapPin", "captureMapPrompt", "captureMapPromptText", "cancelCaptureMap",
    "page-map", "mapSearch", "mapFishSuggestions", "mapRank", "mapRankExperimental", "mapMoneyExplainer", "mapDepth", "mapNoRelic", "mapResultCount", "mapAccuracyNote", "mapResults", "mapResetFilters", "uiOpacity", "uiOpacityValue", "regionToggle", "regionOpacity", "regionOpacityValue", "regionOpacityControl", "mapExpand", "settlementToggle",
    "spotDrawer", "zoomIn", "zoomOut", "zoomHome", "haulPageTitle", "haulPageDescription", "cancelHaulEdit", "haulForm", "haulSpot", "haulLocationCombobox", "haulLocationSuggestions", "haulMapButton", "haulLocationMessage", "haulStyle", "haulMastery", "haulKeep",
    "haulProfileSelect", "haulProfilePreview", "haulProfileManage", "fishingMetrics", "haulResourceLevel", "haulAutoDelayField", "haulAutoDelay", "haulAutoReductionLabel",
    "haulTimeMode", "haulDurationPanel", "haulRangePanel", "haulHours", "haulMinutes", "haulDurationCalculated", "haulStartDate", "haulStartTime", "haulStartTimeButton", "haulStartTimeLabel", "haulEndDate", "haulEndTime", "haulEndTimeButton", "haulEndTimeLabel", "haulExcludedHours", "haulExcludedMinutes", "haulRangeCalculated", "timePickerBackdrop", "timePicker", "timePickerTitle", "timePickerClose", "timePickerHour", "timePickerMinute", "timePickerDial", "timePickerNumbers", "timePickerCancel", "timePickerNow", "timePickerDone", "rodGear", "harpoonGear", "tankFiles", "dropZone", "fileList", "scanButton",
    "reviewEmpty", "reviewContent", "reviewCount", "reviewValue", "reviewCoverage", "reviewConfidence", "recognizedFish", "manualFish",
    "manualAddButton", "haulSaleField", "haulSoldAmount", "saveHaulButton", "saveHaulLabel", "journalSummary", "journalList", "journalDateFrom", "journalDateTo", "journalStatusField", "journalStatus", "journalClearFilters", "statsProfile", "statsStyle", "statsEquipment", "statsEquipmentLabel", "statsEquipmentOptions", "statsMastery",
    "statsLocation", "statsLocationCombobox", "statsLocationClear", "statsLocationSuggestions", "statsLocationMap", "statsLocationMessage", "statsResource", "statsList", "statsDetail", "saleBackdrop", "saleModal", "saleTitle", "saleClose", "saleOrigin", "saleTankValue", "saleBargain", "saleOffers", "saleSoldAt", "saleFinalAmount", "saleChosenSummary", "saleDelete", "saleCancel", "saleSave", "toast", "fishOptions"
  ].forEach(id => { els[id] = document.getElementById(id); });
}

function normalizeUiOpacity(value) {
  if (value == null || String(value).trim() === "") return UI_OPACITY_DEFAULT;
  const parsed = Number(value);
  return Number.isFinite(parsed)
    ? Math.max(UI_OPACITY_MIN, Math.min(UI_OPACITY_MAX, Math.round(parsed)))
    : UI_OPACITY_DEFAULT;
}

function applyUiOpacity(value, persist = false) {
  const percent = normalizeUiOpacity(value);
  const materialOpacity = Math.max(UI_MATERIAL_OPACITY_FLOOR, percent / 100);
  const softOpacity = Math.min(1, materialOpacity * (.82 / .76));
  const controlOpacity = Math.min(1, materialOpacity * (.86 / .76));
  const solidOpacity = Math.min(1, materialOpacity * (.90 / .76));
  const effectStrength = Math.min(1, materialOpacity / .76);
  const hoverOpacity = Math.max(.16, controlOpacity);
  const hoverStrongOpacity = Math.max(.20, solidOpacity);
  const selectedOpacity = Math.max(.24, controlOpacity);
  const selectedStrongOpacity = Math.max(.30, solidOpacity);
  state.uiOpacityPercent = percent;
  if (els.uiOpacity) {
    els.uiOpacity.value = String(percent);
    const progress = (percent - UI_OPACITY_MIN) / (UI_OPACITY_MAX - UI_OPACITY_MIN) * 100;
    els.uiOpacity.style?.setProperty?.("--range-progress", `${progress.toFixed(1)}%`);
    const valueText = percent === 0 ? "0% setting; panels barely visible" : `${percent}% opacity`;
    els.uiOpacity.setAttribute?.("aria-valuetext", valueText);
  }
  if (els.uiOpacityValue) els.uiOpacityValue.textContent = `${percent}%`;
  const rootStyle = document.documentElement?.style;
  rootStyle?.setProperty?.("--ui-surface-opacity", materialOpacity.toFixed(2));
  rootStyle?.setProperty?.("--ui-soft-opacity", softOpacity.toFixed(2));
  rootStyle?.setProperty?.("--ui-control-opacity", controlOpacity.toFixed(2));
  rootStyle?.setProperty?.("--ui-solid-opacity", solidOpacity.toFixed(2));
  rootStyle?.setProperty?.("--ui-hover-opacity", hoverOpacity.toFixed(2));
  rootStyle?.setProperty?.("--ui-hover-strong-opacity", hoverStrongOpacity.toFixed(2));
  rootStyle?.setProperty?.("--ui-selected-opacity", selectedOpacity.toFixed(2));
  rootStyle?.setProperty?.("--ui-selected-strong-opacity", selectedStrongOpacity.toFixed(2));
  rootStyle?.setProperty?.("--ui-border-opacity", (.18 * effectStrength).toFixed(3));
  rootStyle?.setProperty?.("--ui-border-strong-opacity", (.34 * effectStrength).toFixed(3));
  rootStyle?.setProperty?.("--ui-shadow-opacity", (.42 * effectStrength).toFixed(3));
  rootStyle?.setProperty?.("--ui-shadow-soft-opacity", (.24 * effectStrength).toFixed(3));
  rootStyle?.setProperty?.("--ui-shadow-deep-opacity", (.68 * effectStrength).toFixed(3));
  rootStyle?.setProperty?.("--ui-highlight-opacity", (.055 * effectStrength).toFixed(4));
  rootStyle?.setProperty?.("--ui-backdrop-opacity", (.8 * effectStrength).toFixed(3));
  rootStyle?.setProperty?.("--ui-tint-opacity", (.12 * effectStrength).toFixed(3));
  // A nearly clear fill still needs refraction to read as glass rather than a
  // transparent sheet. Keep the blur meaningful across the whole slider.
  rootStyle?.setProperty?.("--ui-header-blur", "8.0px");
  rootStyle?.setProperty?.("--ui-panel-blur", "8.0px");
  if (persist) {
    try {
      window.localStorage?.setItem(UI_OPACITY_STORAGE_KEY, String(percent));
      window.localStorage?.setItem(UI_OPACITY_STORAGE_VERSION_KEY, UI_OPACITY_STORAGE_VERSION);
    } catch {}
  }
  return percent;
}

function migrateUiTransparencyToOpacity(value, version) {
  if (value == null || String(value).trim() === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  let transparency = Math.max(0, Math.min(90, Math.round(parsed)));
  const savedVersion = String(version ?? "").trim();
  if (!savedVersion && transparency === UI_TRANSPARENCY_LEGACY_MAX) transparency = 90;
  // The reported v2 preference is already displayed as 0; keep that visible
  // setting while correcting what the endpoint means in the new opacity UI.
  if (savedVersion === UI_TRANSPARENCY_STORAGE_VERSION && transparency === 0) return 0;
  return normalizeUiOpacity(100 - transparency);
}

function restoreUiOpacity() {
  let saved = UI_OPACITY_DEFAULT;
  try {
    const storage = window.localStorage;
    const storedOpacity = storage?.getItem(UI_OPACITY_STORAGE_KEY);
    if (storedOpacity != null && String(storedOpacity).trim() !== "" && Number.isFinite(Number(storedOpacity))) {
      saved = normalizeUiOpacity(storedOpacity);
      if (storage?.getItem(UI_OPACITY_STORAGE_VERSION_KEY) !== UI_OPACITY_STORAGE_VERSION) {
        storage?.setItem(UI_OPACITY_STORAGE_KEY, String(saved));
        storage?.setItem(UI_OPACITY_STORAGE_VERSION_KEY, UI_OPACITY_STORAGE_VERSION);
      }
    } else {
      const migrated = migrateUiTransparencyToOpacity(
        storage?.getItem(UI_TRANSPARENCY_STORAGE_KEY),
        storage?.getItem(UI_TRANSPARENCY_STORAGE_VERSION_KEY),
      );
      saved = migrated ?? UI_OPACITY_DEFAULT;
      storage?.setItem(UI_OPACITY_STORAGE_KEY, String(saved));
      storage?.setItem(UI_OPACITY_STORAGE_VERSION_KEY, UI_OPACITY_STORAGE_VERSION);
    }
  } catch {}
  return applyUiOpacity(saved, false);
}

function bindUiOpacity() {
  if (!els.uiOpacity) return;
  els.uiOpacity.addEventListener("input", event => applyUiOpacity(event.target.value, false));
  els.uiOpacity.addEventListener("change", event => applyUiOpacity(event.target.value, true));
}

async function request(url, options = {}) {
  if (!API_TOKEN) throw new Error("The secure local fishing session is unavailable. Reopen the Fish tab.");
  const headers = new Headers(options.headers || {});
  headers.set(API_TOKEN_HEADER, API_TOKEN);
  const response = await fetch(url, { ...options, headers });
  const contentType = response.headers.get("content-type") || "";
  const payload = contentType.includes("application/json") ? await response.json() : await response.text();
  if (!response.ok) {
    const message = payload?.message || payload?.error || (typeof payload === "string" ? payload : `Request failed (${response.status})`);
    throw new Error(message);
  }
  return payload;
}

function showToast(message, error = false) {
  window.clearTimeout(toastTimer);
  els.toast.textContent = message;
  els.toast.classList.toggle("is-error", error);
  els.toast.classList.add("is-visible");
  toastTimer = window.setTimeout(() => els.toast.classList.remove("is-visible"), 3200);
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
}

function number(value, maximumFractionDigits = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return "—";
  return new Intl.NumberFormat("en-US", { maximumFractionDigits }).format(n);
}

const LIFE_SKILL_RANK_OFFSETS = Object.freeze({ Beginner: 0, Apprentice: 10, Skilled: 20, Professional: 30, Artisan: 40, Master: 50, Guru: 80 });

function autoFishingDelaySeconds(reductionPercent) {
  const reduction = Math.max(0, Math.min(66.67, Number(reductionPercent) || 0));
  return Math.max(60, Math.round(180 * (1 - reduction / 100) * 10) / 10);
}

function lifeSkillAbsoluteLevel(rank, level) {
  const offset = LIFE_SKILL_RANK_OFFSETS[String(rank)] ?? null;
  const value = Number(level);
  return offset == null || !Number.isFinite(value) ? null : offset + value;
}

function bargainBonusFromTradingLevel(rank, level) {
  const absolute = lifeSkillAbsoluteLevel(rank, level);
  return absolute == null ? 0 : Math.round((5 + absolute * .5) * 10) / 10;
}

function resourceLabel(value) {
  return ({ abundant: "Abundant", average: "Average", "not-enough": "Not Enough", exhausted: "Exhausted" })[String(value || "")] || "Not recorded";
}

function silver(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return "Unknown";
  if (Math.abs(n) >= 1e9) return `${(n / 1e9).toFixed(n >= 1e10 ? 1 : 2)}B`;
  if (Math.abs(n) >= 1e6) return `${(n / 1e6).toFixed(n >= 1e8 ? 0 : 1)}M`;
  if (Math.abs(n) >= 1e3) return `${(n / 1e3).toFixed(n >= 1e5 ? 0 : 1)}K`;
  return number(n);
}

function finiteNumberOrNull(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function setupToolMeta(equipment, method = "rod") {
  return TOOL_ITEMS[equipment] || {
    icon: method === "harpoon" ? 16154 : 16141,
    shortLabel: method === "harpoon" ? "Harpoon" : "Fishing",
    gradeClass: "grade-general",
  };
}

function updateCaptureSetupPreview() {
  const method = state.method.capture;
  const setup = state.fishingSetups.find(item => item.id === state.captureSetupId);
  const equipment = setup?.equipment || state.captureEquipment[method];
  const meta = setupToolMeta(equipment, method);
  els.haulSetupPreview.className = `setup-tool-preview grade-frame ${meta.gradeClass}`;
  const image = $("img", els.haulSetupPreview);
  image.src = `/icon/${meta.icon}.webp`;
  els.haulSetupPreview.title = equipment || meta.shortLabel;
}

function captureSetupLabel(setup) {
  const details = [`${number(setup.mastery)} mastery`];
  if (setup.method === "rod") {
    if (setup.fishingSpeed != null && setup.fishingSpeed !== "") details.push(`Fishing ${setup.fishingSpeed}/5`);
    if (setup.autoFishingDelaySeconds) details.push(`${setup.autoFishingDelaySeconds}s`);
  }
  return `${setup.name} \u00b7 ${details.join(" \u00b7 ")}`;
}

function renderCaptureSetupOptions() {
  const method = state.method.capture;
  const setups = state.fishingSetups.filter(setup => setup.method === method);
  if (!setups.some(setup => setup.id === state.captureSetupId)) state.captureSetupId = "";
  els.haulSetupSelect.innerHTML = `<option value="">Custom settings</option>${setups.map(setup => `<option value="${escapeHtml(setup.id)}">${escapeHtml(captureSetupLabel(setup))}</option>`).join("")}`;
  els.haulSetupSelect.value = state.captureSetupId;
  els.haulSetupDelete.classList.toggle("is-hidden", !state.captureSetupId);
  els.haulSetupSelect.closest(".saved-setup-control").classList.toggle("has-delete", Boolean(state.captureSetupId));
  updateCaptureSetupPreview();
}

function refreshSetupOptions() {
  const method = state.method.stats;
  const available = new Map();
  state.fishingSetups.filter(setup => setup.method === method).forEach(setup => available.set(setup.id, setup));
  state.sessions.filter(session => session.method === method).forEach(session => {
    const id = String(session.setupId || session.setup_id || "").trim();
    if (!id || available.has(id)) return;
    available.set(id, {
      id,
      name: session.setupName || session.setup_name || "Saved setup",
      method,
      equipment: session.equipment || "",
      mastery: session.mastery,
      fishingSpeed: session.fishingSpeed ?? session.fishing_speed,
      autoFishingDelaySeconds: session.autoFishingDelaySeconds ?? session.auto_fishing_delay_seconds,
    });
  });
  const current = available.has(els.statsSetup.value) ? els.statsSetup.value : "all";
  const options = [...available.values()].sort((a,b) => String(a.name).localeCompare(String(b.name)));
  els.statsSetup.innerHTML = `<option value="all">All setups</option>${options.map(setup => `<option value="${escapeHtml(setup.id)}">${escapeHtml(captureSetupLabel(setup))}</option>`).join("")}`;
  els.statsSetup.value = current;
}

async function loadFishingSetups() {
  const result = await request("/api/fishing-setups");
  state.fishingSetups = Array.isArray(result) ? result : Array.isArray(result?.setups) ? result.setups : [];
  renderCaptureSetupOptions();
  refreshSetupOptions();
  return state.fishingSetups;
}

function markCaptureSetupCustom() {
  if (state.captureSetupId) {
    state.captureSetupId = "";
    renderCaptureSetupOptions();
  } else {
    updateCaptureSetupPreview();
  }
}

function updateFishingMetrics() {
  const rod = state.method.capture === "rod";
  const afk = els.haulStyle.value === "afk";
  els.fishingMetrics.classList.toggle("is-hidden", !rod);
  els.fishingMetrics.classList.toggle("single", rod && !afk);
  els.haulAutoDelayField.classList.toggle("is-hidden", !afk);
  const reduction = Math.max(0, Math.min(66.67, Number(state.captureAutoFishingReductionPercent) || 0));
  const delay = autoFishingDelaySeconds(reduction);
  els.haulAutoDelay.textContent = `${number(delay, 1)} sec`;
  els.haulAutoReductionLabel.textContent = `${number(reduction, 1)}% reduction · after bite`;
}

function applyCaptureSetup(id) {
  const setup = state.fishingSetups.find(item => item.id === id && item.method === state.method.capture);
  state.captureSetupId = setup?.id || "";
  if (!setup) {
    renderCaptureSetupOptions();
    return;
  }
  state.captureEquipment[setup.method] = setup.equipment;
  const gear = $(`.gear-option[data-equipment="${CSS.escape(setup.equipment)}"]`, setup.method === "rod" ? els.rodGear : els.harpoonGear);
  if (gear) {
    $$(".gear-option", gear.closest(".gear-options")).forEach(button => {
      const active = button === gear;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });
  }
  els.haulMastery.value = setup.mastery;
  if (setup.method === "rod") {
    els.haulFishingSpeed.value = setup.fishingSpeed ?? "";
    els.haulAutoDelay.value = setup.autoFishingDelaySeconds ?? "";
  }
  renderCaptureSetupOptions();
  updateFishingMetrics();
}

function openCaptureSetupEditor() {
  const method = state.method.capture;
  const equipment = state.captureEquipment[method];
  const meta = setupToolMeta(equipment, method);
  const existing = state.fishingSetups.find(setup => setup.id === state.captureSetupId);
  els.haulSetupName.value = existing ? `${existing.name} copy` : `${meta.shortLabel} ${method === "rod" ? "Fishing" : "Harpoon"}`;
  els.haulSetupEditor.classList.remove("is-hidden");
  els.haulSetupName.focus();
  els.haulSetupName.select();
}

function closeCaptureSetupEditor() {
  els.haulSetupEditor.classList.add("is-hidden");
  els.haulSetupName.value = "";
}

function currentCaptureSetupValues() {
  const method = state.method.capture;
  const mastery = Number(els.haulMastery.value);
  if (!Number.isFinite(mastery) || mastery < 0 || mastery > 5000) throw new Error("Enter the exact fishing mastery for this setup.");
  let fishingSpeed = null;
  let autoFishingDelaySeconds = null;
  if (method === "rod") {
    fishingSpeed = Number(els.haulFishingSpeed.value);
    if (!Number.isInteger(fishingSpeed) || fishingSpeed < 0 || fishingSpeed > 5) throw new Error("Choose the Fishing Speed level used with this setup.");
    if (els.haulAutoDelay.value !== "") {
      autoFishingDelaySeconds = Number(els.haulAutoDelay.value);
      if (!Number.isInteger(autoFishingDelaySeconds) || autoFishingDelaySeconds < 60 || autoFishingDelaySeconds > 180) throw new Error("Auto-fishing must be between 60 and 180 seconds.");
    }
    if (els.haulStyle.value === "afk" && autoFishingDelaySeconds == null) throw new Error("Enter the effective AFK timer, or choose Max for 60 seconds.");
  }
  return {
    method,
    equipment: state.captureEquipment[method],
    mastery,
    fishingSpeed,
    autoFishingDelaySeconds,
  };
}

function newSetupId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `setup-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

async function saveCaptureSetup() {
  const name = els.haulSetupName.value.trim();
  if (!name) { showToast("Give this setup a short name.", true); els.haulSetupName.focus(); return; }
  let values;
  try { values = currentCaptureSetupValues(); }
  catch (error) { showToast(error.message, true); return; }
  if (state.fishingSetups.some(setup => setup.method === values.method && setup.name.toLowerCase() === name.toLowerCase())) {
    showToast("A setup with that name already exists.", true);
    els.haulSetupName.focus();
    return;
  }
  const setup = { id: newSetupId(), name, ...values };
  const original = els.haulSetupConfirm.textContent;
  els.haulSetupConfirm.disabled = true;
  els.haulSetupConfirm.textContent = "Saving";
  try {
    const result = await request("/api/fishing-setups", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ setups: [...state.fishingSetups, setup] }),
    });
    state.fishingSetups = result.setups || [];
    state.captureSetupId = setup.id;
    closeCaptureSetupEditor();
    renderCaptureSetupOptions();
    refreshSetupOptions();
    showToast("Fishing setup saved.");
  } catch (error) {
    showToast(error.message, true);
  } finally {
    els.haulSetupConfirm.disabled = false;
    els.haulSetupConfirm.textContent = original;
  }
}

async function deleteCaptureSetup() {
  const setup = state.fishingSetups.find(item => item.id === state.captureSetupId);
  if (!setup || !window.confirm(`Delete the saved setup \"${setup.name}\"? Existing hauls keep their saved setup details.`)) return;
  try {
    const result = await request("/api/fishing-setups", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ setups: state.fishingSetups.filter(item => item.id !== setup.id) }),
    });
    state.fishingSetups = result.setups || [];
    state.captureSetupId = "";
    renderCaptureSetupOptions();
    refreshSetupOptions();
    showToast("Fishing setup deleted.");
  } catch (error) {
    showToast(error.message, true);
  }
}

function activeProfile() {
  return state.fishingProfiles.find(profile => profile.id === state.activeProfileId) || null;
}

function profileDisplayLabels(profiles) {
  const counts = new Map();
  profiles.forEach(profile => {
    const key = String(profile.name ?? "").toLocaleLowerCase();
    counts.set(key, (counts.get(key) || 0) + 1);
  });
  const occurrences = new Map();
  return new Map(profiles.map(profile => {
    const name = String(profile.name ?? "");
    const key = name.toLocaleLowerCase();
    const count = counts.get(key) || 1;
    const occurrence = (occurrences.get(key) || 0) + 1;
    occurrences.set(key, occurrence);
    const method = profile.method === "harpoon" ? "Harpooning" : "Fishing";
    const label = count > 1
      ? `${name} · ${method} · ${number(profile.mastery)} mastery · ${occurrence}/${count}`
      : name;
    return [profile.id, label];
  }));
}

function profileLabel(profile) {
  const details = [`${number(profile.mastery)} mastery`];
  if (profile.fishingRank && profile.fishingLevel) details.push(`${profile.fishingRank} ${profile.fishingLevel}`);
  if (profile.method === "rod" && profile.autoFishingReductionPercent != null) details.push(`${number(autoFishingDelaySeconds(profile.autoFishingReductionPercent), 1)}s auto`);
  return `${profile.name} · ${details.join(" · ")}`;
}

function updateProfileButton() {
  const profile = activeProfile();
  const method = profile?.method || "rod";
  const equipment = profile ? profile.equipment : "Balenos Rod";
  const meta = setupToolMeta(equipment, method);
  const displayName = profile
    ? profileDisplayLabels(state.fishingProfiles).get(profile.id) || profile.name
    : "Create profile";
  els.profileButtonName.textContent = displayName;
  els.profileButton.setAttribute("aria-label", profile ? `Fishing profile: ${profile.name}` : "Create a fishing profile");
  els.profileButtonTool.className = `profile-button-tool grade-frame ${meta.gradeClass}`;
  $("img", els.profileButtonTool).src = `/icon/${meta.icon}.webp`;
  els.profileButton.removeAttribute("title");
}

function updateCaptureProfilePreview() {
  const method = state.method.capture;
  const profile = state.fishingProfiles.find(item => item.id === state.captureProfileId);
  const equipment = profile ? profile.equipment : state.captureEquipment[method];
  const meta = setupToolMeta(equipment, method);
  els.haulProfilePreview.className = `setup-tool-preview grade-frame ${meta.gradeClass}`;
  const image = $("img", els.haulProfilePreview);
  image.src = `/icon/${meta.icon}.webp`;
  els.haulProfilePreview.title = equipment || meta.shortLabel;
}

function renderCaptureProfileOptions() {
  const method = state.method.capture;
  const profiles = state.fishingProfiles.filter(profile => profile.method === method);
  const labels = profileDisplayLabels(profiles);
  if (!profiles.some(profile => profile.id === state.captureProfileId)) state.captureProfileId = "";
  els.haulProfileSelect.innerHTML = `<option value="">Custom settings</option>${profiles.map(profile => `<option value="${escapeHtml(profile.id)}">${escapeHtml(labels.get(profile.id) || profile.name)}</option>`).join("")}`;
  els.haulProfileSelect.value = state.captureProfileId;
  updateCaptureProfilePreview();
}

function refreshProfileOptions() {
  const method = state.method.stats;
  const available = new Map();
  state.fishingProfiles.filter(profile => profile.method === method).forEach(profile => available.set(profile.id, profile));
  state.sessions.filter(session => session.method === method).forEach(session => {
    const rawId = session.profileId ?? session.profile_id ?? session.setupId ?? session.setup_id;
    const id = rawId == null ? "" : String(rawId);
    if (!id.trim() || available.has(id)) return;
    available.set(id, {
      id,
      name: session.profileName || session.profile_name || session.setupName || session.setup_name || "Saved profile",
      method,
      equipment: session.equipment || "",
      mastery: session.mastery,
      fishingRank: session.fishingRank,
      fishingLevel: session.fishingLevel,
      autoFishingReductionPercent: session.autoFishingReductionPercent ?? session.auto_fishing_reduction_percent ?? (session.autoFishingDelaySeconds ? (1 - Number(session.autoFishingDelaySeconds) / 180) * 100 : 0),
      autoFishingDelaySeconds: session.autoFishingDelaySeconds ?? session.auto_fishing_delay_seconds,
    });
  });
  const current = available.has(els.statsProfile.value) ? els.statsProfile.value : "all";
  const options = [...available.values()].sort((a,b) => String(a.name).localeCompare(String(b.name)));
  const labels = profileDisplayLabels(options);
  els.statsProfile.innerHTML = `<option value="all">All profiles</option>${options.map(profile => `<option value="${escapeHtml(profile.id)}">${escapeHtml(labels.get(profile.id) || profile.name || "Saved profile")}</option>`).join("")}`;
  els.statsProfile.value = current;
}

function renderProfileViews() {
  updateProfileButton();
  renderCaptureProfileOptions();
  refreshProfileOptions();
  if (!els.profileModal.classList.contains("is-hidden")) renderProfileList();
}

async function loadFishingProfiles() {
  const result = await request("/api/profiles");
  state.fishingProfiles = Array.isArray(result?.profiles) ? result.profiles : [];
  state.activeProfileId = String(result?.activeProfileId || "");
  const profile = activeProfile();
  state.captureProfileId = profile?.id || "";
  if (profile) applyProfileToCapture(profile, false);
  renderProfileViews();
  return state.fishingProfiles;
}

function legacyMigrationCount(value) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : 0;
}

function renderProfileMigrationNotice() {
  if (!els.profileMigrationNotice) return;
  const migration = state.legacyMigration;
  const loadoutCount = legacyMigrationCount(migration?.loadoutCount);
  if (!migration || loadoutCount === 0) {
    els.profileMigrationNotice.classList.add("is-hidden");
    return;
  }

  const importedCount = Math.min(loadoutCount, legacyMigrationCount(migration.importedProfileCount));
  const preservedDeletedCount = Math.min(loadoutCount, legacyMigrationCount(migration.preservedDeletedProfileCount));
  const archiveOnlyCount = Math.min(loadoutCount, legacyMigrationCount(migration.archiveOnlyLoadoutCount));
  const backupPath = String(migration.backupRelativePath || "").trim();
  els.profileMigrationTitle.textContent = archiveOnlyCount
    ? "Profile migration needs repair"
    : preservedDeletedCount
      ? "v0.1.7 profiles updated"
      : "v0.1.7 profiles imported";
  els.profileMigrationSummary.textContent = archiveOnlyCount
    ? `${number(archiveOnlyCount)} ${archiveOnlyCount === 1 ? "profile is" : "profiles are"} missing from an earlier preview migration. Restore the exact backup as fishing/fishing-journal.json in this personal data folder, then restart to load every profile.`
    : preservedDeletedCount
      ? `${number(importedCount)} source ${importedCount === 1 ? "profile is" : "profiles are"} available. ${number(preservedDeletedCount)} ${preservedDeletedCount === 1 ? "profile you previously deleted stays" : "profiles you previously deleted stay"} deleted. The exact v0.1.7 source remains in your local backup.`
      : `All ${number(importedCount)} ${importedCount === 1 ? "profile was" : "profiles were"} imported. The exact v0.1.7 source remains in your local backup.`;
  els.profileMigrationPath.textContent = backupPath
    ? `Personal data folder › ${backupPath}`
    : "Exact backup retained in your personal data folder";
  els.profileMigrationCopy.classList.toggle("is-hidden", !backupPath);
  els.profileMigrationNotice.classList.remove("is-hidden");
}

async function loadLegacyMigrationStatus() {
  const result = await request("/api/migration-status");
  state.legacyMigration = result?.legacyV017 && typeof result.legacyV017 === "object"
    ? result.legacyV017
    : null;
  renderProfileMigrationNotice();
  return state.legacyMigration;
}

async function copyLegacyMigrationBackupPath() {
  const backupPath = String(state.legacyMigration?.backupRelativePath || "").trim();
  if (!backupPath) return;
  try {
    if (typeof navigator.clipboard?.writeText === "function") {
      await navigator.clipboard.writeText(backupPath);
    } else {
      const field = document.createElement("textarea");
      field.value = backupPath;
      field.setAttribute("readonly", "");
      field.style.position = "fixed";
      field.style.opacity = "0";
      document.body.appendChild(field);
      field.select();
      const copied = document.execCommand?.("copy");
      field.remove();
      if (!copied) throw new Error("Copy is unavailable");
    }
    showToast("Exact local backup path copied.");
  } catch {
    showToast("Could not copy the backup path. It remains shown in the profile notice.", true);
  }
}

async function persistFishingProfiles(profiles, activeProfileId) {
  const result = await request("/api/profiles", {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ profiles, activeProfileId: activeProfileId || null }),
  });
  state.fishingProfiles = Array.isArray(result?.profiles) ? result.profiles : [];
  state.activeProfileId = String(result?.activeProfileId || "");
  renderProfileViews();
  return result;
}

function markCaptureProfileCustom() {
  if (state.editingSessionId) state.editingProfileDetached = true;
  if (state.captureProfileId) {
    state.captureProfileId = "";
    renderCaptureProfileOptions();
  } else {
    updateCaptureProfilePreview();
  }
}

function syncCaptureMethod(method) {
  state.method.capture = method;
  $$('[data-method-switch="capture"] [data-method]').forEach(button => button.classList.toggle("is-active", button.dataset.method === method));
  els.rodGear.classList.toggle("is-hidden", method !== "rod");
  els.harpoonGear.classList.toggle("is-hidden", method !== "harpoon");
}

function applyProfileToCapture(profile, render = true) {
  if (!profile) {
    state.captureProfileId = "";
    if (render) renderCaptureProfileOptions();
    return;
  }
  syncCaptureMethod(profile.method);
  state.captureProfileId = profile.id;
  state.captureEquipment[profile.method] = profile.equipment;
  const gearContainer = profile.method === "rod" ? els.rodGear : els.harpoonGear;
  const gear = $(`.gear-option[data-equipment="${CSS.escape(profile.equipment)}"]`, profile.method === "rod" ? els.rodGear : els.harpoonGear);
  $$(".gear-option", gearContainer).forEach(button => {
    const active = button === gear;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });
  els.haulMastery.value = profile.mastery;
  if (profile.method === "rod") {
    state.captureAutoFishingReductionPercent = Number(profile.autoFishingReductionPercent) || 0;
  }
  if (render) renderCaptureProfileOptions();
  updateFishingMetrics();
}

async function selectCaptureProfile(id) {
  const profile = state.fishingProfiles.find(item => item.id === id) || null;
  if (!profile) {
    if (state.editingSessionId) state.editingProfileDetached = true;
    state.captureProfileId = "";
    renderCaptureProfileOptions();
    return;
  }
  const previousActive = state.activeProfileId;
  state.editingProfileDetached = false;
  applyProfileToCapture(profile);
  state.activeProfileId = profile.id;
  updateProfileButton();
  try {
    await persistFishingProfiles(state.fishingProfiles, profile.id);
  } catch (error) {
    state.activeProfileId = previousActive;
    updateProfileButton();
    showToast(error.message, true);
  }
}

function newProfileId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `profile-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function defaultProfile(method = "rod") {
  return {
    id: "",
    name: "",
    method,
    equipment: method === "harpoon" ? "Thin Harpoon" : "Balenos Rod",
    mastery: 0,
    fishingRank: "Beginner",
    fishingLevel: 1,
    autoFishingReductionPercent: method === "rod" ? 0 : null,
    tradingRank: "Beginner",
    tradingLevel: 1,
    notes: "",
    createdAtUtc: null,
    updatedAtUtc: null,
  };
}

function updateProfileDerivedValues() {
  [[els.profileFishingRank, els.profileFishingLevel], [els.profileTradingRank, els.profileTradingLevel]].forEach(([rank, level]) => {
    const selected = Boolean(rank.value);
    level.disabled = !selected;
    level.required = selected;
    if (!selected) {
      level.value = "";
      return;
    }
    const maximum = rank.value === "Guru" ? 100 : rank.value === "Master" ? 30 : 10;
    level.max = String(maximum);
    if (Number(level.value) > maximum) level.value = String(maximum);
  });
  const reductionSet = els.profileAutoReductionPercent.value !== "";
  const reduction = reductionSet
    ? Math.max(0, Math.min(66.67, Number(els.profileAutoReductionPercent.value) || 0))
    : null;
  const autoLabel = reductionSet
    ? `${number(autoFishingDelaySeconds(reduction), 1)} sec after bite`
    : "Not set · 180 sec neutral";
  els.profileAutoDelay.value = autoLabel;
  els.profileAutoDelay.textContent = autoLabel;
  const bargain = bargainBonusFromTradingLevel(els.profileTradingRank.value, els.profileTradingLevel.value);
  els.profileBargainPreview.textContent = `${number(bargain, 1)}%`;
}

function renderProfileEquipmentOptions() {
  const method = els.profileMethod.value;
  const values = method === "rod" ? ["Balenos Rod", "Triple-Float Rod"] : ["Thin Harpoon", "Thick Harpoon", "Manos Harpoon"];
  els.profileEquipmentOptions.innerHTML = values.map(value => {
    const meta = setupToolMeta(value, method);
    const active = els.profileEquipment.value === value;
    return `<button type="button" class="profile-equipment-option ${active ? "is-active" : ""}" data-profile-equipment="${escapeHtml(value)}" aria-pressed="${active}"><span class="grade-frame ${meta.gradeClass}"><img src="/icon/${meta.icon}.webp" alt=""></span><strong>${escapeHtml(meta.shortLabel)}</strong></button>`;
  }).join("");
  $$('[data-profile-equipment]', els.profileEquipmentOptions).forEach(button => button.addEventListener("click", () => {
    els.profileEquipment.value = button.dataset.profileEquipment;
    els.profileEquipmentText.value = button.dataset.profileEquipment;
    renderProfileEquipmentOptions();
  }));
}

function setProfileMethod(method) {
  els.profileMethod.value = method;
  $$('[data-profile-method]').forEach(button => {
    const active = button.dataset.profileMethod === method;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });
  const rod = method === "rod";
  els.profileAutoDelayField.classList.toggle("is-hidden", !rod);
  renderProfileEquipmentOptions();
  updateProfileDerivedValues();
}

function renderProfileList() {
  if (!state.fishingProfiles.length) {
    els.profileList.innerHTML = `<div class="profile-list-empty"><strong>No profiles yet</strong><span>Create one profile for quick haul entry.</span></div>`;
    return;
  }
  const labels = profileDisplayLabels(state.fishingProfiles);
  els.profileList.innerHTML = state.fishingProfiles.map(profile => {
    const meta = setupToolMeta(profile.equipment, profile.method);
    const active = profile.id === state.activeProfileId;
    const selected = profile.id === state.profileEditingId;
    return `<button type="button" class="profile-list-item ${active ? "is-active" : ""} ${selected ? "is-selected" : ""}" data-profile-edit="${escapeHtml(profile.id)}"><span class="profile-list-icon grade-frame ${meta.gradeClass}"><img src="/icon/${meta.icon}.webp" alt=""></span><span><strong>${escapeHtml(labels.get(profile.id) || profile.name)}</strong><small>${number(profile.mastery)} mastery${profile.method === "rod" && profile.autoFishingDelaySeconds ? ` · ${profile.autoFishingDelaySeconds}s` : ""}</small></span>${active ? `<em>Active</em>` : ""}</button>`;
  }).join("");
  $$('[data-profile-edit]', els.profileList).forEach(button => button.addEventListener("click", () => editProfile(button.dataset.profileEdit)));
}

function editProfile(id, rerenderList = true) {
  const profile = state.fishingProfiles.find(item => item.id === id) || defaultProfile(state.method.capture);
  state.profileEditingId = profile.id || "";
  els.profileName.value = profile.name ?? "";
  els.profileEquipment.value = profile.equipment ?? "";
  els.profileEquipmentText.value = profile.equipment ?? "";
  els.profileMastery.value = String(profile.mastery ?? 0);
  els.profileFishingRank.value = profile.fishingRank || "";
  els.profileFishingLevel.value = profile.fishingLevel == null ? "" : String(profile.fishingLevel);
  els.profileAutoReductionPercent.value = profile.autoFishingReductionPercent == null ? "" : String(profile.autoFishingReductionPercent);
  els.profileTradingRank.value = profile.tradingRank || "";
  els.profileTradingLevel.value = profile.tradingLevel == null ? "" : String(profile.tradingLevel);
  els.profileNotes.value = profile.notes ?? "";
  state.profileEditorBaseline = profile.id ? {
    id: profile.id,
    name: els.profileName.value,
    equipment: els.profileEquipmentText.value,
    notes: els.profileNotes.value,
  } : null;
  els.profileDelete.classList.toggle("is-hidden", !profile.id);
  els.profileActiveBadge.classList.toggle("is-hidden", !profile.id || profile.id !== state.activeProfileId);
  setProfileMethod(profile.method || "rod");
  updateProfileDerivedValues();
  if (rerenderList) renderProfileList();
}

function openProfileModal(id = state.activeProfileId) {
  els.profileModal.classList.remove("is-hidden");
  els.profileModal.setAttribute("aria-hidden", "false");
  renderProfileMigrationNotice();
  editProfile(id || state.fishingProfiles[0]?.id || "");
  window.setTimeout(() => els.profileName.focus(), 0);
}

function closeProfileModal() {
  els.profileModal.classList.add("is-hidden");
  els.profileModal.setAttribute("aria-hidden", "true");
  state.profileEditingId = "";
  state.profileEditorBaseline = null;
}

function profileFormValues() {
  if (!els.profileForm.reportValidity()) return null;
  const method = els.profileMethod.value;
  const existing = state.fishingProfiles.find(item => item.id === state.profileEditingId) || null;
  const baseline = existing && state.profileEditorBaseline?.id === existing.id
    ? state.profileEditorBaseline
    : null;
  const now = new Date().toISOString();
  return {
    id: state.profileEditingId || newProfileId(),
    legacySourceId: existing?.legacySourceId ?? null,
    name: baseline && els.profileName.value === baseline.name ? existing.name : els.profileName.value,
    method,
    equipment: baseline && els.profileEquipmentText.value === baseline.equipment ? existing.equipment : els.profileEquipmentText.value,
    mastery: Number(els.profileMastery.value),
    fishingRank: els.profileFishingRank.value || null,
    fishingLevel: els.profileFishingRank.value ? Number(els.profileFishingLevel.value) : null,
    autoFishingReductionPercent: method === "rod" && els.profileAutoReductionPercent.value !== "" ? Number(els.profileAutoReductionPercent.value) : null,
    tradingRank: els.profileTradingRank.value || null,
    tradingLevel: els.profileTradingRank.value ? Number(els.profileTradingLevel.value) : null,
    notes: baseline && els.profileNotes.value === baseline.notes ? existing.notes : els.profileNotes.value,
    createdAtUtc: existing?.createdAtUtc ?? now,
    updatedAtUtc: existing?.updatedAtUtc ?? now,
  };
}

async function saveProfile(event) {
  event.preventDefault();
  const profile = profileFormValues();
  if (!profile) return;
  const profiles = state.fishingProfiles.some(item => item.id === profile.id)
    ? state.fishingProfiles.map(item => item.id === profile.id ? profile : item)
    : [...state.fishingProfiles, profile];
  const original = els.profileSave.textContent;
  els.profileSave.disabled = true;
  els.profileSave.textContent = "Saving…";
  try {
    await persistFishingProfiles(profiles, profile.id);
    state.captureProfileId = profile.id;
    applyProfileToCapture(state.fishingProfiles.find(item => item.id === profile.id));
    closeProfileModal();
    showToast("Fishing profile saved and selected.");
  } catch (error) {
    showToast(error.message, true);
  } finally {
    els.profileSave.disabled = false;
    els.profileSave.textContent = original;
  }
}

async function deleteProfile() {
  const profile = state.fishingProfiles.find(item => item.id === state.profileEditingId);
  if (!profile || !window.confirm(`Delete the profile \"${profile.name}\"? Saved hauls keep their profile details.`)) return;
  const profiles = state.fishingProfiles.filter(item => item.id !== profile.id);
  const nextActive = state.activeProfileId === profile.id ? (profiles[0]?.id || null) : state.activeProfileId;
  try {
    await persistFishingProfiles(profiles, nextActive);
    const next = state.fishingProfiles.find(item => item.id === nextActive) || null;
    state.captureProfileId = next?.id || "";
    if (next) applyProfileToCapture(next);
    else renderCaptureProfileOptions();
    editProfile(next?.id || "");
    showToast("Fishing profile deleted.");
  } catch (error) {
    showToast(error.message, true);
  }
}

function normalizeRgb(value) {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    if (/^0x/i.test(value)) return Number.parseInt(value.slice(2), 16);
    if (value.includes(",")) {
      const [r, g, b] = value.split(",").map(Number);
      return (r << 16) | (g << 8) | b;
    }
    return Number(value);
  }
  return Number(value?.rgb ?? value?.rgb_u32 ?? value?.zoneRgb);
}

function depthKey(zone) {
  const given = String(zone?.depth || zone?.waterType || "").trim().toLowerCase().replace(/\s+/g, "-");
  if (given) return given === "unspecified" ? "open-sea" : given;
  const name = String(zone?.name || "").toLowerCase();
  const depth = name.match(/depth\s*([1-5])/);
  if (depth) return `depth-${depth[1]}`;
  if (/(river|lake|pond|swamp|inland|waterfall|hot spring|pavilion|oasis|terrain|warehouse|monastery|forest|cave)/.test(name)) return "inland";
  if (/(coast|beach|dock|wharf|offshore|island|archipelago)/.test(name)) return "coast";
  return "open-sea";
}

function inferZoneRole(zone) {
  const explicit = String(zone?.zoneRole || zone?.zone_role || "").trim();
  if (explicit) return explicit;
  const name = String(zone?.name || zone?.label || "").toLowerCase();
  if (name === "out-of-bounds" || name === "out of bounds") return "out-of-bounds";
  if (name === "unknown") return "unknown";
  if (/\b(default|terrain default)\b/.test(name)) return "broad-default";
  return "named-table";
}

function normalizeBootstrap(raw) {
  const map = raw.map || raw.meta || {};
  state.map.width = Number(map.width || map.image_size_x || 11560);
  state.map.height = Number(map.height || map.image_size_y || 10540);
  state.map.tileSize = Number(map.tileSize || map.tile_size_px || 512);
  const worldTransform = map.worldTransform || map.world_transform || null;
  state.map.worldTransform = worldTransform && [worldTransform.left, worldTransform.top, worldTransform.sectorPerPixel, worldTransform.positionFactor].every(value => Number.isFinite(Number(value)))
    ? {
        left: Number(worldTransform.left),
        top: Number(worldTransform.top),
        sectorPerPixel: Number(worldTransform.sectorPerPixel),
        positionFactor: Number(worldTransform.positionFactor),
      }
    : null;

  const zones = Array.isArray(raw.zones) ? raw.zones : [];
  state.zones = zones.map(zone => {
    const rgb = normalizeRgb(zone);
    const center = zone.center || (Number.isFinite(zone.x) ? { x: zone.x, y: zone.y } : null);
    const rawEvidencePoint = zone.evidencePoint || zone.evidence_point || null;
    const rawEvidenceClusters = Array.isArray(zone.evidenceClusters)
      ? zone.evidenceClusters
      : rawEvidencePoint ? [rawEvidencePoint] : [];
    const evidenceClusters = rawEvidenceClusters
      .filter(point => Number.isFinite(Number(point?.x)) && Number.isFinite(Number(point?.y)))
      .map(point => ({ ...point, x: Number(point.x), y: Number(point.y) }));
    const items = Array.isArray(zone.items) ? zone.items : [];
    return {
      ...zone,
      rgb,
      name: zone.name || zone.label || rgbToText(rgb),
      zoneRole: inferZoneRole(zone),
      active: zone.active !== false,
      exact: zone.exact ?? zone.exactRgbConfirmed ?? zone.exact_rgb_confirmed,
      center: center && Number.isFinite(Number(center.x)) && Number.isFinite(Number(center.y)) ? { x: Number(center.x), y: Number(center.y) } : null,
      evidencePoint: evidenceClusters[0] || null,
      evidenceClusters,
      items,
      methods: Array.isArray(zone.methods) ? zone.methods : [...new Set(items.map(item => item.method || item.catchMethod).filter(Boolean))],
      depth: depthKey(zone),
      dataKnown: Boolean(zone.dataKnown ?? zone.data_known ?? items.length),
      hasRelic: zone.hasRelic ?? zone.has_relic ?? (items.length ? items.some(item => Number(item.itemId) === 40218) : null),
      redSpeciesCount: finiteNumberOrNull(zone.redSpeciesCount ?? zone.red_species_count ?? (items.length ? items.filter(item => item.isFish !== false && String(item.grade).toLowerCase() === "prize").length : null)),
      estimatedValue: finiteNumberOrNull(zone.estimatedValue ?? zone.estimated_value),
      searchTerms: String(zone.searchTerms || items.map(item => item.name || item.label).join(" ")).toLowerCase(),
    };
  }).filter(zone => Number.isFinite(zone.rgb));
  state.zoneByRgb = new Map(state.zones.map(zone => [zone.rgb, zone]));

  const nodes = Array.isArray(raw.locationNodes) ? raw.locationNodes : Array.isArray(raw.nodes) ? raw.nodes : [];
  state.nodes = nodes.map(node => {
    const rawZoneRgb = node.zoneRgb ?? node.zone_rgb;
    const pixel = node.pixel || {};
    const name = String(node.name || node.label || "").trim();
    const label = String(node.label || node.name || "").trim();
    return {
      ...node,
      name,
      label,
      displayName: label || name,
      kind: String(node.nodeTypeLabel || node.kind || node.type || "Node").trim(),
      zoneRgb: rawZoneRgb == null || rawZoneRgb === "" ? Number.NaN : normalizeRgb(rawZoneRgb),
      zoneName: String(node.zoneName || node.zone_name || "").trim(),
      x: Number(node.x ?? pixel.x),
      y: Number(node.y ?? pixel.y),
    };
  }).filter(node => node.name);

  const fish = Array.isArray(raw.fish) ? raw.fish : Array.isArray(raw.catalog) ? raw.catalog : [];
  state.fish = fish.map(item => ({
    ...item,
    itemId: Number(item.itemId ?? item.id),
    name: item.name || item.label || String(item.itemId ?? item.id),
    price: Number(item.price ?? item.priceRaw ?? item.vendorPrice ?? item.buyPrice ?? 0),
  })).filter(item => Number.isFinite(item.itemId));
  state.fishById = new Map(state.fish.map(item => [item.itemId, item]));
  const fishNames = [...state.fish]
    .filter(item => item.name && item.itemId)
    .sort((a, b) => a.name.localeCompare(b.name) || a.itemId - b.itemId);
  if (els.mapFishSuggestions) {
    els.mapFishSuggestions.innerHTML = fishNames.map(item => `<option value="${escapeHtml(item.name)}" label="${escapeHtml(`${item.name} · item ${item.itemId}`)}"></option>`).join("");
  }
  state.data = raw;
}

function rgbToText(rgb) {
  const n = Number(rgb) >>> 0;
  return `${(n >>> 16) & 255},${(n >>> 8) & 255},${n & 255}`;
}

function setSourceState(source = {}) {
  const status = String(source.status || source.mode || "").toLowerCase();
  const refreshing = source.refreshInProgress === true;
  const tables = source.tableRefresh || {};
  const live = status === "live" && !refreshing && !tables.errors?.length;
  els.sourceState.classList.toggle("is-live", live);
  els.sourceState.classList.toggle("is-cache", !live);
  const label = refreshing ? `Checking tables${tables.total ? ` · ${tables.checked || 0}/${tables.total}` : "…"}`
    : live ? "Source checked · coverage incomplete" : status === "live-partial" ? "Partially refreshed tables" : "Saved fishing tables";
  $("span:last-child", els.sourceState).textContent = label;
  const revision = source.revision || source.dataRevision || "";
  els.sourceState.title = [label, source.fetchedAt ? `Checked: ${source.fetchedAt}` : "Check date unavailable", revision,
    source.message, "Community-source freshness does not certify complete current-game coverage."].filter(Boolean).join(" · ");
  if (els.mapAccuracyNote) {
    const gaps = state.data?.accuracyAudit?.unmappedFish || [];
    els.mapAccuracyNote.textContent = gaps.length
      ? `${gaps.length} known fish still lack verified map assignments. Exact boundaries and catch rates are not guaranteed.`
      : "Community tables may be incomplete. Ranking areas are not exact catch positions.";
    els.mapAccuracyNote.title = gaps.map(item => item.name).join(" · ");
  }
}

function populateOptions() {
  els.fishOptions.innerHTML = state.fish.filter(item => item.name).sort((a,b) => a.name.localeCompare(b.name)).map(item => `<option value="${escapeHtml(item.name)}"></option>`).join("");
  if (document.activeElement === els.haulSpot) renderCaptureLocationSuggestions(els.haulSpot.value, true);
  renderCaptureLocationResolution();
}

function navigate(page) {
  if (page !== "map" && state.pendingMapLocation) {
    state.pendingMapLocation = null;
    els.captureMapPrompt.classList.add("is-hidden");
  }
  $$(".page").forEach(node => node.classList.toggle("is-active", node.id === `page-${page}`));
  $$(".nav-button").forEach(node => node.classList.toggle("is-active", node.dataset.page === page));
  updateDesktopScaling();
  if (page === "map") {
    window.requestAnimationFrame(() => {
      if (!state.map.initialized) homeMap();
      else { const frame = renderMapVisibleFrame(); clampMap(frame); applyMapTransform(); renderTiles(); }
    });
  }
  if (page === "journal") loadJournal().catch(error => showToast(error.message, true));
  if (page === "stats") Promise.all([loadSessions(), loadFishingProfiles()]).then(() => { refreshProfileOptions(); refreshEquipmentOptions(); renderStats(); }).catch(error => showToast(error.message, true));
}

function setCaptureStyle(style) {
  const value = style === "active" ? "active" : "afk";
  els.haulStyle.value = value;
  $$(".style-option").forEach(button => {
    const active = button.dataset.style === value;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });
  updateFishingMetrics();
}

function setCaptureEquipment(method, equipment) {
  const container = method === "harpoon" ? els.harpoonGear : els.rodGear;
  state.captureEquipment[method] = equipment;
  $$(".gear-option", container).forEach(button => {
    const active = button.dataset.equipment === equipment;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });
  updateCaptureProfilePreview();
}

function padTimePart(value) {
  return String(Math.trunc(Number(value) || 0)).padStart(2, "0");
}

function localDateTimeParts(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return { date: "", time: "" };
  return {
    date: `${date.getFullYear()}-${padTimePart(date.getMonth() + 1)}-${padTimePart(date.getDate())}`,
    time: `${padTimePart(date.getHours())}:${padTimePart(date.getMinutes())}`,
  };
}

function setCaptureClockValue(target, value = "") {
  const normalized = /^([01]\d|2[0-3]):[0-5]\d$/.test(String(value)) ? String(value) : "";
  const input = target === "end" ? els.haulEndTime : els.haulStartTime;
  const label = target === "end" ? els.haulEndTimeLabel : els.haulStartTimeLabel;
  const button = target === "end" ? els.haulEndTimeButton : els.haulStartTimeButton;
  input.value = normalized;
  label.textContent = normalized || "--:--";
  button.classList.toggle("has-value", Boolean(normalized));
}

function setCaptureTimeMode(mode) {
  const normalized = mode === "range" ? "range" : "duration";
  state.captureTimeMode = normalized;
  els.haulTimeMode.value = normalized;
  $$('[data-time-mode]').forEach(button => {
    const active = button.dataset.timeMode === normalized;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });
  els.haulDurationPanel.classList.toggle("is-hidden", normalized !== "duration");
  els.haulRangePanel.classList.toggle("is-hidden", normalized !== "range");
  updateCaptureTimeDisplays();
}

function resetCaptureTimeFields() {
  els.haulHours.value = "";
  els.haulMinutes.value = "";
  els.haulStartDate.value = "";
  els.haulEndDate.value = "";
  els.haulExcludedHours.value = "";
  els.haulExcludedMinutes.value = "";
  setCaptureClockValue("start", "");
  setCaptureClockValue("end", "");
  setCaptureTimeMode("duration");
}

function localDateTime(dateValue, timeValue) {
  const dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateValue || ""));
  const timeMatch = /^(\d{2}):(\d{2})$/.exec(String(timeValue || ""));
  if (!dateMatch || !timeMatch) return null;
  const value = new Date(
    Number(dateMatch[1]),
    Number(dateMatch[2]) - 1,
    Number(dateMatch[3]),
    Number(timeMatch[1]),
    Number(timeMatch[2]),
    0,
    0,
  );
  return Number.isNaN(value.getTime()) ? null : value;
}

function captureTimeDetails() {
  if (state.captureTimeMode !== "range") {
    const rawHours = String(els.haulHours.value || "").trim();
    const rawMinutes = String(els.haulMinutes.value || "").trim();
    if (!rawHours && !rawMinutes) return { durationMinutes: null, excludedMinutes: 0, startedAt: null, endedAt: null };
    const hours = Number(rawHours || 0);
    const minutes = Number(rawMinutes || 0);
    if (!Number.isInteger(hours) || !Number.isInteger(minutes) || hours < 0 || minutes < 0 || minutes > 59) {
      return { error: "Enter a valid duration in whole hours and minutes.", focus: els.haulHours };
    }
    const durationMinutes = hours * 60 + minutes;
    if (durationMinutes > MAX_SESSION_MINUTES) return { error: "A fishing session can be at most 7 days.", focus: els.haulHours };
    return { durationMinutes: durationMinutes || null, excludedMinutes: 0, startedAt: null, endedAt: null };
  }

  const values = [els.haulStartDate.value, els.haulStartTime.value, els.haulEndDate.value, els.haulEndTime.value];
  const rawExcludedHours = String(els.haulExcludedHours.value || "").trim();
  const rawExcludedMinutes = String(els.haulExcludedMinutes.value || "").trim();
  const hasAny = values.some(Boolean) || Boolean(rawExcludedHours || rawExcludedMinutes);
  if (!hasAny) return { durationMinutes: null, excludedMinutes: 0, startedAt: null, endedAt: null };
  if (!values.every(Boolean)) {
    const missingControl = !els.haulStartDate.value ? els.haulStartDate
      : !els.haulStartTime.value ? els.haulStartTimeButton
      : !els.haulEndDate.value ? els.haulEndDate
      : els.haulEndTimeButton;
    return { incomplete: true, error: "Choose both the start and end date and time.", focus: missingControl };
  }
  const started = localDateTime(els.haulStartDate.value, els.haulStartTime.value);
  const ended = localDateTime(els.haulEndDate.value, els.haulEndTime.value);
  if (!started || !ended) return { error: "Choose valid start and end times.", focus: els.haulStartDate };
  const grossMinutes = Math.round((ended.getTime() - started.getTime()) / 60000);
  if (grossMinutes <= 0) return { error: "The end time must be later than the start time.", focus: els.haulEndDate };
  if (grossMinutes > MAX_SESSION_MINUTES) return { error: "A fishing session can be at most 7 days.", focus: els.haulEndDate };
  const excludedHours = Number(rawExcludedHours || 0);
  const excludedMinutePart = Number(rawExcludedMinutes || 0);
  if (!Number.isInteger(excludedHours) || !Number.isInteger(excludedMinutePart) || excludedHours < 0 || excludedMinutePart < 0 || excludedMinutePart > 59) {
    return { error: "Enter valid whole hours and minutes to subtract.", focus: els.haulExcludedHours };
  }
  const excludedMinutes = excludedHours * 60 + excludedMinutePart;
  if (excludedMinutes >= grossMinutes) {
    return { error: "Time away must be shorter than the full start-to-end period.", focus: els.haulExcludedHours };
  }
  const durationMinutes = grossMinutes - excludedMinutes;
  return {
    durationMinutes,
    excludedMinutes,
    startedAt: started.toISOString(),
    endedAt: ended.toISOString(),
    caughtAt: ended.toISOString(),
  };
}

function updateCaptureTimeDisplays() {
  const directHours = Math.max(0, Number(els.haulHours.value || 0));
  const directMinutes = Math.max(0, Number(els.haulMinutes.value || 0));
  const directTotal = Number.isFinite(directHours + directMinutes) ? directHours * 60 + directMinutes : 0;
  els.haulDurationCalculated.textContent = directTotal > 0 && directMinutes <= 59 ? formatDuration(directTotal) : "—";

  const range = state.captureTimeMode === "range" ? captureTimeDetails() : null;
  els.haulRangePanel.classList.toggle("has-error", Boolean(range?.error && !range?.incomplete));
  els.haulRangeCalculated.textContent = range?.durationMinutes ? formatDuration(range.durationMinutes) : range?.error && !range?.incomplete ? "Check times" : "—";
}

function renderTimePickerFace() {
  const picker = state.timePicker;
  const isHour = picker.stage === "hour";
  const entries = [];
  if (isHour) {
    for (let value = 1; value <= 12; value += 1) entries.push({ value, label: String(value), radius: 105, inner: false });
    for (let value = 13; value <= 23; value += 1) entries.push({ value, label: String(value), radius: 65, inner: true });
    entries.push({ value: 0, label: "00", radius: 65, inner: true });
  } else {
    for (let value = 0; value < 60; value += 5) entries.push({ value, label: padTimePart(value), radius: 105, inner: false });
  }
  const center = 134;
  els.timePickerNumbers.innerHTML = entries.map(entry => {
    const clockStep = isHour ? entry.value % 12 : entry.value / 5;
    const angle = clockStep * 30 * Math.PI / 180;
    const left = center + Math.sin(angle) * entry.radius;
    const top = center - Math.cos(angle) * entry.radius;
    return `<span class="time-picker-number ${entry.inner ? "is-inner" : ""}" data-clock-value="${entry.value}" style="left:${left.toFixed(2)}px;top:${top.toFixed(2)}px">${entry.label}</span>`;
  }).join("");
  els.timePickerDial.dataset.stage = picker.stage;
  updateTimePickerVisual();
}

function updateTimePickerVisual() {
  const picker = state.timePicker;
  els.timePickerHour.textContent = padTimePart(picker.hour);
  els.timePickerMinute.textContent = padTimePart(picker.minute);
  els.timePickerHour.classList.toggle("is-active", picker.stage === "hour");
  els.timePickerMinute.classList.toggle("is-active", picker.stage === "minute");
  els.timePickerHour.setAttribute("aria-pressed", String(picker.stage === "hour"));
  els.timePickerMinute.setAttribute("aria-pressed", String(picker.stage === "minute"));
  const selectedValue = picker.stage === "hour" ? picker.hour : Math.round(picker.minute / 5) * 5 % 60;
  $$('[data-clock-value]', els.timePickerNumbers).forEach(label => label.classList.toggle("is-selected", Number(label.dataset.clockValue) === selectedValue));
  const angle = picker.stage === "hour" ? (picker.hour % 12) * 30 : picker.minute * 6;
  const innerHour = picker.stage === "hour" && (picker.hour === 0 || picker.hour >= 13);
  els.timePickerDial.style.setProperty("--clock-angle", `${angle}deg`);
  els.timePickerDial.style.setProperty("--clock-hand", `${innerHour ? 65 : 105}px`);
}

function selectTimePickerStage(stage) {
  state.timePicker.stage = stage === "minute" ? "minute" : "hour";
  renderTimePickerFace();
}

function openTimePicker(target) {
  const input = target === "end" ? els.haulEndTime : els.haulStartTime;
  const existing = /^(\d{2}):(\d{2})$/.exec(input.value);
  const now = new Date();
  state.timePicker.target = target === "end" ? "end" : "start";
  state.timePicker.hour = existing ? Number(existing[1]) : now.getHours();
  state.timePicker.minute = existing ? Number(existing[2]) : now.getMinutes();
  // Stage the end-date fallback too, so opening/cancelling never edits the form.
  state.timePicker.pendingDate = target === "end" ? els.haulEndDate.value || els.haulStartDate.value || null : null;
  state.timePicker.pointerId = null;
  state.timePicker.pendingPoint = null;
  els.timePickerTitle.textContent = state.timePicker.target === "end" ? "End time" : "Start time";
  els.timePicker.classList.toggle("is-end-time", state.timePicker.target === "end");
  els.timePickerNow.hidden = state.timePicker.target !== "end";
  els.timePickerBackdrop.classList.remove("is-hidden");
  els.timePickerBackdrop.setAttribute("aria-hidden", "false");
  selectTimePickerStage("hour");
  window.requestAnimationFrame(() => els.timePickerDial.focus());
}

function setTimePickerNow() {
  const picker = state.timePicker;
  if (picker.target !== "end") return;
  const now = new Date();
  picker.pendingDate = localDateTimeParts(now).date;
  picker.hour = now.getHours();
  picker.minute = now.getMinutes();
  if (picker.frame) window.cancelAnimationFrame(picker.frame);
  picker.frame = 0;
  picker.pendingPoint = null;
  if (picker.pointerId != null) {
    try { els.timePickerDial.releasePointerCapture(picker.pointerId); } catch {}
  }
  picker.pointerId = null;
  els.timePickerDial.classList.remove("is-dragging");
  selectTimePickerStage("minute");
  els.timePickerDial.focus();
}

function closeTimePicker(commit = false) {
  if (!state.timePicker.target) return;
  const target = state.timePicker.target;
  const restoreButton = target === "end" ? els.haulEndTimeButton : els.haulStartTimeButton;
  if (commit) {
    if (target === "end" && state.timePicker.pendingDate) els.haulEndDate.value = state.timePicker.pendingDate;
    setCaptureClockValue(target, `${padTimePart(state.timePicker.hour)}:${padTimePart(state.timePicker.minute)}`);
  }
  if (state.timePicker.frame) window.cancelAnimationFrame(state.timePicker.frame);
  state.timePicker.frame = 0;
  state.timePicker.pendingPoint = null;
  state.timePicker.pointerId = null;
  state.timePicker.pendingDate = null;
  state.timePicker.target = "";
  els.timePickerDial.classList.remove("is-dragging");
  els.timePickerBackdrop.classList.add("is-hidden");
  els.timePickerBackdrop.setAttribute("aria-hidden", "true");
  updateCaptureTimeDisplays();
  restoreButton.focus();
}

function applyTimePickerPoint(point) {
  if (!state.timePicker.target || !point) return;
  const rect = els.timePickerDial.getBoundingClientRect();
  const dx = point.x - (rect.left + rect.width / 2);
  const dy = point.y - (rect.top + rect.height / 2);
  const distance = Math.hypot(dx, dy);
  const angle = (Math.atan2(dx, -dy) + Math.PI * 2) % (Math.PI * 2);
  if (state.timePicker.stage === "hour") {
    const clockIndex = Math.round(angle / (Math.PI * 2) * 12) % 12;
    const inner = distance < rect.width * .32;
    state.timePicker.hour = inner ? (clockIndex === 0 ? 0 : clockIndex + 12) : (clockIndex === 0 ? 12 : clockIndex);
  } else {
    state.timePicker.minute = Math.round(angle / (Math.PI * 2) * 60) % 60;
  }
  updateTimePickerVisual();
}

function scheduleTimePickerPoint(event) {
  state.timePicker.pendingPoint = { x: event.clientX, y: event.clientY };
  if (state.timePicker.frame) return;
  state.timePicker.frame = window.requestAnimationFrame(() => {
    state.timePicker.frame = 0;
    const point = state.timePicker.pendingPoint;
    state.timePicker.pendingPoint = null;
    applyTimePickerPoint(point);
  });
}

function finishTimePickerPointer(event) {
  if (state.timePicker.pointerId !== event.pointerId) return;
  if (state.timePicker.frame) window.cancelAnimationFrame(state.timePicker.frame);
  state.timePicker.frame = 0;
  applyTimePickerPoint({ x: event.clientX, y: event.clientY });
  state.timePicker.pendingPoint = null;
  state.timePicker.pointerId = null;
  els.timePickerDial.classList.remove("is-dragging");
  try { els.timePickerDial.releasePointerCapture(event.pointerId); } catch {}
  if (state.timePicker.stage === "hour") window.setTimeout(() => {
    if (state.timePicker.target && state.timePicker.stage === "hour") selectTimePickerStage("minute");
  }, 90);
}

function updateHaulEditPresentation() {
  const editing = Boolean(state.editingSessionId);
  els.haulPageTitle.textContent = editing ? "Edit haul" : "Add a haul";
  els.haulPageDescription.textContent = editing
    ? "Correct the saved setup, location, time, or fish counts."
    : "Choose the setup, scan the tank, and check the recognized fish before saving.";
  els.cancelHaulEdit.classList.toggle("is-hidden", !editing);
  els.haulSaleField.classList.toggle("is-hidden", !editing);
  els.saveHaulLabel.textContent = "Save";
}

function clearCaptureReview() {
  state.review = null;
  setFiles([]);
  els.tankFiles.value = "";
  els.manualFish.value = "";
  renderReview();
}

function beginNewHaul() {
  state.editingSessionId = "";
  state.editingProfileDetached = false;
  state.pendingMapLocation = null;
  state.captureLocation = null;
  state.captureLastValidLocation = null;
  els.captureMapPrompt.classList.add("is-hidden");
  els.haulSpot.value = "";
  els.haulSoldAmount.value = "";
  els.haulSoldAmount.dataset.original = "";
  els.haulResourceLevel.value = "";
  els.haulKeep.value = "all";
  resetCaptureTimeFields();
  setCaptureStyle("afk");
  const profile = activeProfile();
  if (profile) applyProfileToCapture(profile);
  else {
    syncCaptureMethod("rod");
    state.captureProfileId = "";
    state.captureAutoFishingReductionPercent = 0;
    els.haulMastery.value = "";
    setCaptureEquipment("rod", state.captureEquipment.rod || "Balenos Rod");
    renderCaptureProfileOptions();
    updateFishingMetrics();
  }
  clearCaptureReview();
  renderCaptureLocationResolution();
  updateHaulEditPresentation();
  navigate("capture");
  $("#page-capture").scrollTop = 0;
}

function cancelHaulEditing() {
  state.editingSessionId = "";
  state.editingProfileDetached = false;
  state.pendingMapLocation = null;
  clearCaptureReview();
  updateHaulEditPresentation();
  navigate("journal");
}

async function editSession(id) {
  let session = state.sessions.find(entry => String(entry.id) === String(id));
  if (!session) {
    try { session = await request(`/api/sessions/${encodeURIComponent(id)}`); }
    catch (error) { showToast(error.message, true); return; }
  }
  if (isLegacyAggregateSession(session)) {
    showToast("Imported v0.1.7 aggregate hauls are preserved read-only.", true);
    return;
  }
  const method = session.method === "harpoon" ? "harpoon" : "rod";
  const equipment = session.equipment || (method === "harpoon" ? "Thin Harpoon" : "Balenos Rod");
  const profileId = String(session.profileId || session.profile_id || session.setupId || session.setup_id || "");
  state.editingSessionId = String(session.id);
  const recordedSale = sessionSale(session);
  const recordedAmount = recordedSale?.finalAmount != null ? String(recordedSale.finalAmount) : "";
  els.haulSoldAmount.value = recordedAmount;
  els.haulSoldAmount.dataset.original = recordedAmount;
  state.editingProfileDetached = false;
  state.pendingMapLocation = null;
  syncCaptureMethod(method);
  state.captureProfileId = state.fishingProfiles.some(profile => profile.id === profileId && profile.method === method) ? profileId : "";
  setCaptureEquipment(method, equipment);
  setCaptureStyle(session.style);
  els.haulMastery.value = session.mastery ?? "";
  const savedReduction = Number(session.autoFishingReductionPercent ?? session.auto_fishing_reduction_percent);
  const savedDelay = Number(session.autoFishingDelaySeconds ?? session.auto_fishing_delay_seconds);
  state.captureAutoFishingReductionPercent = method === "rod"
    ? (Number.isFinite(savedReduction) ? savedReduction : Number.isFinite(savedDelay) ? Math.max(0, Math.min(66.67, (1 - savedDelay / 180) * 100)) : 0)
    : 0;
  els.haulResourceLevel.value = method === "rod" ? String(session.resourceLevel || session.resource_level || "") : "";
  els.haulKeep.value = session.keepFrom || session.keep_from || "all";
  const duration = Math.max(0, Number(session.durationMinutes ?? session.duration_minutes) || 0);
  const excluded = Math.max(0, Number(session.excludedMinutes ?? session.excluded_minutes) || 0);
  const startedAt = session.startedAt || session.started_at || "";
  const endedAt = session.endedAt || session.ended_at || "";
  if (startedAt && endedAt) {
    const startedParts = localDateTimeParts(startedAt);
    const endedParts = localDateTimeParts(endedAt);
    els.haulStartDate.value = startedParts.date;
    els.haulEndDate.value = endedParts.date;
    setCaptureClockValue("start", startedParts.time);
    setCaptureClockValue("end", endedParts.time);
    els.haulHours.value = "";
    els.haulMinutes.value = "";
    els.haulExcludedHours.value = excluded ? String(Math.floor(excluded / 60)) : "";
    els.haulExcludedMinutes.value = excluded % 60 ? String(excluded % 60) : "";
    setCaptureTimeMode("range");
  } else {
    els.haulStartDate.value = "";
    els.haulEndDate.value = "";
    setCaptureClockValue("start", "");
    setCaptureClockValue("end", "");
    els.haulHours.value = duration ? String(Math.floor(duration / 60)) : "";
    els.haulMinutes.value = duration % 60 ? String(duration % 60) : "";
    els.haulExcludedHours.value = "";
    els.haulExcludedMinutes.value = "";
    setCaptureTimeMode("duration");
  }

  const rgb = normalizeRgb(session.zoneRgb ?? session.zone_rgb);
  const zoneName = String(session.zoneName || session.zone_name || "Saved fishing table");
  const locationName = String(session.locationName || session.location_name || zoneName);
  const pointX = finiteNumberOrNull(session.point?.x ?? session.pointX ?? session.point_x);
  const pointY = finiteNumberOrNull(session.point?.y ?? session.pointY ?? session.point_y);
  const point = pointX != null && pointY != null ? { x: pointX, y: pointY } : null;
  const zone = state.zoneByRgb.get(rgb) || {
    rgb,
    name: zoneName,
    depth: session.depth || depthKey({ name: zoneName }),
    center: point,
    active: true,
    dataKnown: true,
  };
  const node = findNodeByInput(locationName);
  const captureLocation = {
    type: node ? "node" : point ? "map" : "zone",
    inputKey: captureInputKey(locationName),
    inputValue: locationName,
    locationName,
    node,
    zone: { ...zone, rgb, name: zoneName, depth: session.depth || zone.depth || depthKey(zone) },
    point,
    requiresExactClick: false,
    source: point ? "map-click" : "saved-session",
  };
  els.haulSpot.value = locationName;
  state.captureLocation = captureLocation;
  state.captureLastValidLocation = captureLocation;

  const verified = String(session.verificationStatus || session.verification_status || "").toLowerCase() === "verified";
  state.review = {
    catches: sessionCatches(session).map(item => ({ ...item, verified: true, source: "saved" })),
    tank: {},
    scan: {},
    review: {},
    recognizerVersion: "",
    contextResolvedSlots: 0,
    manuallyEdited: !verified,
    originalSource: session.source || "manual",
    originalVerificationStatus: session.verificationStatus || session.verification_status || "reviewed",
  };
  setFiles([]);
  els.tankFiles.value = "";
  els.manualFish.value = "";
  renderCaptureProfileOptions();
  updateFishingMetrics();
  renderCaptureLocationResolution();
  renderReview();
  updateHaulEditPresentation();
  navigate("capture");
  $("#page-capture").scrollTop = 0;
}

function bindNavigation() {
  $$(".nav-button").forEach(button => button.addEventListener("click", () => button.dataset.page === "capture" ? beginNewHaul() : navigate(button.dataset.page)));
  $$('[data-go]').forEach(button => button.addEventListener("click", () => button.dataset.go === "capture" ? beginNewHaul() : navigate(button.dataset.go)));
}

function bindJournal() {
  $$('[data-journal-mode]').forEach(button => button.addEventListener("click", () => {
    state.journalFilters.mode = button.dataset.journalMode === "sales" ? "sales" : "catches";
    $$('[data-journal-mode]').forEach(other => {
      const active = other === button;
      other.classList.toggle("is-active", active);
      other.setAttribute("aria-pressed", String(active));
    });
    renderJournal();
  }));
  [els.journalDateFrom, els.journalDateTo].forEach(control => control.addEventListener("change", () => {
    state.journalFilters.from = els.journalDateFrom.value;
    state.journalFilters.to = els.journalDateTo.value;
    renderJournal();
  }));
  els.journalStatus.addEventListener("change", () => {
    state.journalFilters.status = els.journalStatus.value;
    renderJournal();
  });
  els.journalClearFilters.addEventListener("click", () => {
    state.journalFilters.from = "";
    state.journalFilters.to = "";
    state.journalFilters.status = "all";
    els.journalDateFrom.value = "";
    els.journalDateTo.value = "";
    els.journalStatus.value = "all";
    renderJournal();
  });
  els.saleClose.addEventListener("click", closeSalePlanner);
  els.saleCancel.addEventListener("click", closeSalePlanner);
  els.saleBackdrop.addEventListener("pointerdown", event => { if (event.target === els.saleBackdrop) closeSalePlanner(); });
  els.saleFinalAmount.addEventListener("input", renderSaleChosenSummary);
  els.saleSave.addEventListener("click", saveRecordedSale);
  els.saleDelete.addEventListener("click", deleteRecordedSale);
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && !els.saleBackdrop.classList.contains("is-hidden")) closeSalePlanner();
  });
}

function bindProfiles() {
  els.profileButton.addEventListener("click", () => openProfileModal());
  els.haulProfileManage.addEventListener("click", () => openProfileModal(state.captureProfileId || state.activeProfileId));
  els.profileClose.addEventListener("click", closeProfileModal);
  els.profileCancel.addEventListener("click", closeProfileModal);
  els.profileNew.addEventListener("click", () => editProfile(""));
  els.profileMigrationCopy.addEventListener("click", copyLegacyMigrationBackupPath);
  els.profileDelete.addEventListener("click", deleteProfile);
  els.profileForm.addEventListener("submit", saveProfile);
  $$('[data-profile-method]').forEach(button => button.addEventListener("click", () => setProfileMethod(button.dataset.profileMethod)));
  els.profileEquipmentText.addEventListener("input", () => {
    els.profileEquipment.value = els.profileEquipmentText.value;
    renderProfileEquipmentOptions();
  });
  els.profileAutoReductionPercent.addEventListener("input", updateProfileDerivedValues);
  els.profileFishingRank.addEventListener("change", updateProfileDerivedValues);
  els.profileTradingRank.addEventListener("change", updateProfileDerivedValues);
  els.profileTradingLevel.addEventListener("input", updateProfileDerivedValues);
  els.profileModal.addEventListener("pointerdown", event => {
    if (event.target === els.profileModal) closeProfileModal();
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && !els.profileModal.classList.contains("is-hidden")) closeProfileModal();
  });
}

function bindMethodSwitches() {
  $$('[data-method-switch]').forEach(switcher => {
    const scope = switcher.dataset.methodSwitch;
    $$('[data-method]', switcher).forEach(button => button.addEventListener("click", () => {
      const method = button.dataset.method;
      state.method[scope] = method;
      $$('[data-method]', switcher).forEach(other => other.classList.toggle("is-active", other === button));
      if (scope === "map") {
        applyMapFilters();
        if (state.selectedZone) loadSpotDetails(state.selectedZone.rgb);
      }
      if (scope === "capture") {
        els.rodGear.classList.toggle("is-hidden", method !== "rod");
        els.harpoonGear.classList.toggle("is-hidden", method !== "harpoon");
        if (state.editingSessionId) state.editingProfileDetached = true;
        state.captureProfileId = "";
        const matchingProfile = activeProfile()?.method === method ? activeProfile() : null;
        state.captureAutoFishingReductionPercent = method === "rod" ? Number(matchingProfile?.autoFishingReductionPercent || 0) : 0;
        renderCaptureProfileOptions();
        updateFishingMetrics();
      }
      if (scope === "stats") {
        state.statsSelected = null;
        refreshProfileOptions();
        refreshEquipmentOptions();
        renderStats();
      }
    }));
  });
}

function measureMapVisibleFrame() {
  const viewportWidth = Math.max(0, Number(els.mapViewport?.clientWidth) || 0);
  const viewportHeight = Math.max(0, Number(els.mapViewport?.clientHeight) || 0);
  const fullFrame = {
    left: 0, top: 0, right: viewportWidth, bottom: viewportHeight,
    width: viewportWidth, height: viewportHeight,
    centerX: viewportWidth / 2, centerY: viewportHeight / 2,
  };
  if (!viewportWidth || !viewportHeight || typeof els.mapViewport?.getBoundingClientRect !== "function") return fullFrame;

  const viewportRect = els.mapViewport.getBoundingClientRect();
  const viewportLeft = Number(viewportRect.left) || 0;
  const viewportTop = Number(viewportRect.top) || 0;
  const renderedWidth = Number(viewportRect.width) || (Number(viewportRect.right) - viewportLeft) || viewportWidth;
  const renderedHeight = Number(viewportRect.height) || (Number(viewportRect.bottom) - viewportTop) || viewportHeight;
  if (!(renderedWidth > 0) || !(renderedHeight > 0)) return fullFrame;
  const viewportRight = Number(viewportRect.right) || viewportLeft + renderedWidth;
  const viewportBottom = Number(viewportRect.bottom) || viewportTop + renderedHeight;
  const scaleX = viewportWidth / renderedWidth;
  const scaleY = viewportHeight / renderedHeight;
  const frame = { left: 0, top: 0, right: viewportWidth, bottom: viewportHeight };

  const dockedOverlays = [els.mapTools];
  if (!els.spotDrawer?.classList?.contains?.("is-closed")) dockedOverlays.push(els.spotDrawer);
  for (const overlay of dockedOverlays) {
    if (typeof overlay?.getBoundingClientRect !== "function") continue;
    const rect = overlay.getBoundingClientRect();
    const rawLeft = Number(rect.left);
    const rawTop = Number(rect.top);
    const rawRight = Number(rect.right);
    const rawBottom = Number(rect.bottom);
    if (![rawLeft, rawTop, rawRight, rawBottom].every(Number.isFinite)) continue;
    const left = Math.max(0, (Math.max(viewportLeft, rawLeft) - viewportLeft) * scaleX);
    const top = Math.max(0, (Math.max(viewportTop, rawTop) - viewportTop) * scaleY);
    const right = Math.min(viewportWidth, (Math.min(viewportRight, rawRight) - viewportLeft) * scaleX);
    const bottom = Math.min(viewportHeight, (Math.min(viewportBottom, rawBottom) - viewportTop) * scaleY);
    const width = Math.max(0, right - left);
    const height = Math.max(0, bottom - top);
    if (!width || !height) continue;

    // The responsive layout docks panels vertically on desktop/tablet and
    // horizontally on narrow screens. Coverage identifies the rendered dock
    // direction without duplicating CSS breakpoints in map geometry code.
    if (height / viewportHeight >= width / viewportWidth) {
      if (left <= viewportWidth - right) frame.left = Math.max(frame.left, right);
      else frame.right = Math.min(frame.right, left);
    } else if (top <= viewportHeight - bottom) frame.top = Math.max(frame.top, bottom);
    else frame.bottom = Math.min(frame.bottom, top);
  }

  if (frame.right <= frame.left || frame.bottom <= frame.top) return fullFrame;
  return {
    ...frame,
    width: frame.right - frame.left,
    height: frame.bottom - frame.top,
    centerX: (frame.left + frame.right) / 2,
    centerY: (frame.top + frame.bottom) / 2,
  };
}

function renderMapVisibleFrame(frame = measureMapVisibleFrame()) {
  state.map.visibleFrame = { ...frame };
  if (els.mapVisibleFrame?.style) {
    els.mapVisibleFrame.style.left = `${frame.left}px`;
    els.mapVisibleFrame.style.top = `${frame.top}px`;
    els.mapVisibleFrame.style.width = `${frame.width}px`;
    els.mapVisibleFrame.style.height = `${frame.height}px`;
  }
  return frame;
}

function preserveMapVisibleFrame(change) {
  const before = measureMapVisibleFrame();
  const worldCenter = state.map.initialized && state.map.scale > 0 && before.width > 0 && before.height > 0
    ? { x: (before.centerX - state.map.offsetX) / state.map.scale, y: (before.centerY - state.map.offsetY) / state.map.scale }
    : null;
  change();
  const after = renderMapVisibleFrame();
  if (!worldCenter || after.width <= 0 || after.height <= 0) return after;
  state.map.offsetX = after.centerX - worldCenter.x * state.map.scale;
  state.map.offsetY = after.centerY - worldCenter.y * state.map.scale;
  state.map.minScale = Math.max(.01, Math.min(after.width / state.map.width, after.height / state.map.height) * .95);
  clampMap(after);
  applyMapTransform();
  renderTiles(true);
  renderSpotPoints(state.filteredZones);
  renderSettlementMarkers();
  return after;
}

function setSpotDrawerOpen(open) {
  const shouldOpen = Boolean(open);
  const isOpen = !els.spotDrawer.classList.contains("is-closed");
  if (isOpen === shouldOpen) return renderMapVisibleFrame();
  return preserveMapVisibleFrame(() => els.spotDrawer.classList.toggle("is-closed", !shouldOpen));
}

function homeMap() {
  const frame = renderMapVisibleFrame();
  const scale = Math.min(frame.width / state.map.width, frame.height / state.map.height) * .97;
  state.map.minScale = Math.max(.01, scale * .98);
  state.map.scale = scale;
  state.map.offsetX = frame.left + (frame.width - state.map.width * scale) / 2;
  state.map.offsetY = frame.top + (frame.height - state.map.height * scale) / 2;
  state.map.initialized = true;
  applyMapTransform();
  renderTiles(true);
}

function clampMap(frame = measureMapVisibleFrame()) {
  const { width, height } = state.map;
  const scaledW = width * state.map.scale;
  const scaledH = height * state.map.scale;
  const edgeX = Math.min(150, frame.width * .18);
  const edgeY = Math.min(150, frame.height * .18);
  if (scaledW <= frame.width) state.map.offsetX = frame.left + (frame.width - scaledW) / 2;
  else state.map.offsetX = Math.min(frame.left + edgeX, Math.max(frame.right - scaledW - edgeX, state.map.offsetX));
  if (scaledH <= frame.height) state.map.offsetY = frame.top + (frame.height - scaledH) / 2;
  else state.map.offsetY = Math.min(frame.top + edgeY, Math.max(frame.bottom - scaledH - edgeY, state.map.offsetY));
}

function applyMapTransform() {
  const positionTile = image => {
    const worldX = Number(image.dataset.worldX);
    const worldY = Number(image.dataset.worldY);
    const worldSize = Number(image.dataset.worldSize);
    if (![worldX, worldY, worldSize].every(Number.isFinite)) return;
    image.style.left = `${state.map.offsetX + worldX * state.map.scale}px`;
    image.style.top = `${state.map.offsetY + worldY * state.map.scale}px`;
    image.style.width = `${worldSize * state.map.scale + .75}px`;
    image.style.height = `${worldSize * state.map.scale + .75}px`;
  };
  [state.map.overviewTiles, state.map.fallbackTiles, state.map.tiles, state.map.regionTiles, state.map.highlightTiles]
    .forEach(collection => collection.forEach(positionTile));
  $$("[data-map-world-x][data-map-world-y]", els.mapWorld).forEach(node => {
    const worldX = Number(node.dataset.mapWorldX);
    const worldY = Number(node.dataset.mapWorldY);
    if (!Number.isFinite(worldX) || !Number.isFinite(worldY)) return;
    node.style.left = `${state.map.offsetX + worldX * state.map.scale}px`;
    node.style.top = `${state.map.offsetY + worldY * state.map.scale}px`;
  });
}

function zoomMap(factor, anchorX = null, anchorY = null) {
  const frame = measureMapVisibleFrame();
  if (!Number.isFinite(anchorX)) anchorX = frame.centerX;
  if (!Number.isFinite(anchorY)) anchorY = frame.centerY;
  const old = state.map.scale;
  const next = Math.max(state.map.minScale, Math.min(state.map.maxScale, old * factor));
  if (Math.abs(next - old) < .00001) return;
  const worldX = (anchorX - state.map.offsetX) / old;
  const worldY = (anchorY - state.map.offsetY) / old;
  state.map.scale = next;
  state.map.offsetX = anchorX - worldX * next;
  state.map.offsetY = anchorY - worldY * next;
  clampMap();
  applyMapTransform();
  renderTiles();
  renderSpotPoints(state.filteredZones);
  renderSettlementMarkers();
}

function tileLevelForScale(scale) {
  const current = state.map.tileLevel;
  if (current === 0 && scale >= .78) return 0;
  if (current === 1 && scale >= .24 && scale < 1) return 1;
  if (current === 2 && scale >= .09 && scale < .30) return 2;
  if (current === 3 && scale < .13) return 3;
  if (scale < .11) return 3;
  if (scale < .26) return 2;
  if (scale < .90) return 1;
  return 0;
}

function mapLayerTileUrl(template, level, x, y, rgb = null, color = "30ff60") {
  return String(template || "")
    .replace("{z}", String(level))
    .replace("{x}", String(x))
    .replace("{y}", String(y))
    .replace("{rgb}", rgb == null ? "" : encodeURIComponent(rgbToText(rgb)))
    .replace("{color}", encodeURIComponent(color));
}

function tableHighlightColor(zone) {
  const redCount = Number(methodMetric(zone, "redSpeciesCount", state.method.map) || 0);
  if (redCount >= 5) return "ff416d";
  if (redCount === 4) return "f0527b";
  if (redCount === 3) return "e49a3a";
  if (redCount === 2) return "d8b659";
  if (redCount === 1) return "52d6ca";
  return "8a9497";
}

function ensureMapTile(collection, key, container, className, src, x, y, tileWorld, opacity = null, priority = "auto", onReady = null, deferReveal = false) {
  if (collection.has(key)) return;
  const image = new Image();
  image.className = className;
  image.alt = "";
  image.draggable = false;
  image.decoding = "async";
  image.fetchPriority = priority;
  image.dataset.loaded = "false";
  image.dataset.level = String(key).split("/")[0];
  image.dataset.worldX = String(x * tileWorld);
  image.dataset.worldY = String(y * tileWorld);
  image.dataset.worldSize = String(tileWorld);
  image.style.left = `${state.map.offsetX + x * tileWorld * state.map.scale}px`;
  image.style.top = `${state.map.offsetY + y * tileWorld * state.map.scale}px`;
  image.style.width = `${tileWorld * state.map.scale + .75}px`;
  image.style.height = `${tileWorld * state.map.scale + .75}px`;
  const targetOpacity = Number.isFinite(Number(opacity)) ? Number(opacity) : 1;
  image.style.opacity = "0";
  if (deferReveal) {
    image.dataset.targetOpacity = String(targetOpacity);
    image.style.visibility = "hidden";
    image.style.transition = "none";
  }
  const fail = () => {
    if (collection.get(key) !== image) return;
    // Keep a failed pending tile as a marker until the requested coverage changes.
    // This avoids a retry loop and, critically, does not retire the visible fallback.
    if (deferReveal) image.dataset.failed = "true";
    else collection.delete(key);
    image.remove();
    if (onReady) onReady(false);
  };
  image.addEventListener("load", () => {
    const reveal = () => {
      if (collection.get(key) !== image) return;
      image.dataset.loaded = "true";
      if (!deferReveal) image.style.opacity = String(targetOpacity);
      if (onReady) onReady(true);
    };
    if (typeof image.decode === "function") image.decode().then(reveal, deferReveal ? fail : reveal);
    else reveal();
  }, { once: true });
  image.addEventListener("error", fail, { once: true });
  container.appendChild(image);
  collection.set(key, image);
  image.src = src;
}

function pruneMapTiles(collection, wanted) {
  for (const [key, image] of collection) {
    if (!wanted.has(key)) {
      image.remove();
      collection.delete(key);
    }
  }
}

const mapOverlayCoverage = new WeakMap();

function prepareMapOverlayTiles(collection, identity) {
  let coverage = mapOverlayCoverage.get(collection);
  if (!coverage || coverage.identity !== identity) {
    // Different masks, display rules or selected regions must never be fallbacks.
    pruneMapTiles(collection, new Set());
    coverage = { identity, level: null };
    mapOverlayCoverage.set(collection, coverage);
  }
  return coverage;
}

function commitMapOverlayTiles(collection, coverage, level, wanted, required) {
  const ready = [...required].every(key => collection.get(key)?.dataset.loaded === "true");
  if (coverage.level == null || coverage.level === level || ready) coverage.level = level;
  const retained = new Set(wanted);
  for (const [key, image] of collection) {
    const visible = Number(image.dataset.overlayLevel) === coverage.level && image.dataset.loaded === "true";
    // All visibility changes happen together, without opacity transitions. Pending
    // zoom levels never paint over the old level while their neighbours are loading.
    image.style.visibility = visible ? "inherit" : "hidden";
    image.style.opacity = visible ? image.dataset.targetOpacity : "0";
    if (coverage.level !== level && visible) retained.add(key);
  }
  pruneMapTiles(collection, retained);
}

function mapTileIntersectsViewport(x, y, tileWorld) {
  const left = state.map.offsetX + x * tileWorld * state.map.scale;
  const top = state.map.offsetY + y * tileWorld * state.map.scale;
  const size = tileWorld * state.map.scale;
  return left < els.mapViewport.clientWidth && left + size > 0
    && top < els.mapViewport.clientHeight && top + size > 0;
}

function scheduleMapTilesRender() {
  if (mapRenderFrame) return;
  mapRenderFrame = window.requestAnimationFrame(() => {
    mapRenderFrame = 0;
    renderTiles();
  });
}

function overviewLevel() {
  const levels = Array.isArray(state.data?.map?.levels) ? state.data.map.levels : [];
  return levels.reduce((largest, entry) => Math.max(largest, Number(entry.z) || 0), 0);
}

function updateMapOverlayVisibility() {
  // The overview remains a complete base while the next detail level is loading.
  const ready = state.map.overviewReady;
  els.regionLayer.style.visibility = ready ? "visible" : "hidden";
  els.zoneHighlightLayer.style.visibility = ready ? "visible" : "hidden";
}

function updateOverviewReadiness() {
  const expected = state.map.overviewExpected;
  const ready = expected > 0
    && state.map.overviewTiles.size === expected
    && [...state.map.overviewTiles.values()].every(image => image.dataset.loaded === "true");
  if (ready === state.map.overviewReady) return;
  state.map.overviewReady = ready;
  els.mapViewport.classList.toggle("has-map-coverage", ready);
  updateMapOverlayVisibility();
  if (ready) scheduleMapTilesRender();
}

function renderOverviewTiles() {
  if (!state.data?.map) return;
  const level = overviewLevel();
  const levelMeta = (state.data.map.levels || []).find(entry => Number(entry.z) === level);
  const width = Number(levelMeta?.width || Math.ceil(state.map.width / (state.map.tileSize * 2 ** level)));
  const height = Number(levelMeta?.height || Math.ceil(state.map.height / (state.map.tileSize * 2 ** level)));
  const tileWorld = state.map.tileSize * 2 ** level;
  state.map.overviewExpected = width * height;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const key = `${level}/${x}_${y}`;
      ensureMapTile(
        state.map.overviewTiles,
        key,
        els.overviewLayer,
        "map-tile map-overview-tile",
        `/tile/${level}/${x}_${y}.webp`,
        x,
        y,
        tileWorld,
        1,
        "high",
        updateOverviewReadiness,
      );
    }
  }
  updateOverviewReadiness();
}

function zoneIntersectsTile(zone, x, y, tileWorld) {
  const bounds = zone?.bounds;
  if (!bounds) return true;
  const left = Number(bounds.left);
  const top = Number(bounds.top);
  const right = Number(bounds.right);
  const bottom = Number(bounds.bottom);
  if (![left, top, right, bottom].every(Number.isFinite)) return true;
  const tileLeft = x * tileWorld;
  const tileTop = y * tileWorld;
  return tileLeft < right && tileLeft + tileWorld > left && tileTop < bottom && tileTop + tileWorld > top;
}

function renderTiles(force = false) {
  if (!state.map.initialized) return;
  const regionLayer = state.data?.fishingRegionLayer || {};
  const highlightConfig = regionLayer.highlight || {};
  const highlightedZone = state.selectedZone;
  const highlightedRgb = highlightedZone && highlightedZone.zoneRole !== "out-of-bounds" ? Number(highlightedZone.rgb) : null;
  const highlightedColor = highlightedZone ? tableHighlightColor(highlightedZone) : "30ff60";
  const regionsEnabled = Boolean(state.regionVisible && regionLayer.tileUrlTemplate);
  const highlightEnabled = Boolean(!state.selectedPoint && Number.isFinite(highlightedRgb) && highlightConfig.tileUrlTemplate);
  const geometry = [state.map.width, state.map.height, state.map.tileSize];
  const regionCoverage = prepareMapOverlayTiles(state.map.regionTiles, regionsEnabled
    ? JSON.stringify([regionLayer.revision, regionLayer.displayRevision, regionLayer.tileUrlTemplate, geometry]) : null);
  const highlightCoverage = prepareMapOverlayTiles(state.map.highlightTiles, highlightEnabled
    ? JSON.stringify([regionLayer.revision, highlightConfig.tileUrlTemplate, highlightedRgb, highlightedColor, highlightConfig.defaultOpacity, geometry]) : null);
  if (els.mapViewport.clientWidth <= 0 || els.mapViewport.clientHeight <= 0) return;
  renderOverviewTiles();
  const level = tileLevelForScale(state.map.scale);
  const overview = overviewLevel();
  els.mapViewport.classList.toggle("is-overview-scale", level === overview);
  const factor = 2 ** level;
  const tileWorld = state.map.tileSize * factor;
  const margin = tileWorld * (level === 0 ? .18 : level === 1 ? .42 : .72);
  const left = Math.max(0, -state.map.offsetX / state.map.scale - margin);
  const top = Math.max(0, -state.map.offsetY / state.map.scale - margin);
  const right = Math.min(state.map.width, (els.mapViewport.clientWidth - state.map.offsetX) / state.map.scale + margin);
  const bottom = Math.min(state.map.height, (els.mapViewport.clientHeight - state.map.offsetY) / state.map.scale + margin);
  const minX = Math.max(0, Math.floor(left / tileWorld));
  const minY = Math.max(0, Math.floor(top / tileWorld));
  const maxX = Math.min(Math.ceil(state.map.width / tileWorld) - 1, Math.floor(right / tileWorld));
  const maxY = Math.min(Math.ceil(state.map.height / tileWorld) - 1, Math.floor(bottom / tileWorld));
  const wanted = new Set();
  const wantedRegions = new Set();
  const wantedHighlights = new Set();
  const requiredRegions = new Set();
  const requiredHighlights = new Set();
  const visibleFrame = measureMapVisibleFrame();
  const viewportCenterX = (-state.map.offsetX + visibleFrame.centerX) / state.map.scale;
  const viewportCenterY = (-state.map.offsetY + visibleFrame.centerY) / state.map.scale;
  const coordinates = [];
  for (let x = minX; x <= maxX; x++) {
    for (let y = minY; y <= maxY; y++) coordinates.push({ x, y });
  }
  coordinates.sort((a, b) => {
    const aDistance = (a.x * tileWorld + tileWorld / 2 - viewportCenterX) ** 2 + (a.y * tileWorld + tileWorld / 2 - viewportCenterY) ** 2;
    const bDistance = (b.x * tileWorld + tileWorld / 2 - viewportCenterX) ** 2 + (b.y * tileWorld + tileWorld / 2 - viewportCenterY) ** 2;
    return aDistance - bDistance;
  });

  pruneMapTiles(state.map.fallbackTiles, new Set());
  state.map.tileLevel = level;
  if (level !== overview) {
    coordinates.forEach(({ x, y }, index) => {
      const key = `${level}/${x}_${y}`;
      wanted.add(key);
      ensureMapTile(
        state.map.tiles,
        key,
        els.tileLayer,
        "map-tile map-detail-tile",
        `/tile/${level}/${x}_${y}.webp`,
        x,
        y,
        tileWorld,
        1,
        index < 4 ? "high" : "auto",
        scheduleMapTilesRender,
      );
      const image = state.map.tiles.get(key);
      if (image) image.style.zIndex = "2";
    });
  }
  for (const image of state.map.tiles.values()) {
    image.style.zIndex = Number(image.dataset.level) === level ? "2" : "1";
  }
  const baseReady = level === overview
    ? state.map.overviewReady
    : wanted.size > 0 && [...wanted].every(key => state.map.tiles.get(key)?.dataset.loaded === "true");
  state.map.detailBaseReady = baseReady;
  if (baseReady) {
    pruneMapTiles(state.map.tiles, wanted);
    state.map.displayedLevel = level;
  }

  if (regionsEnabled) {
    for (const { x, y } of coordinates) {
      const key = `${regionLayer.displayRevision || regionLayer.revision || "unversioned"}/${level}/${x}_${y}`;
      wantedRegions.add(key);
      if (mapTileIntersectsViewport(x, y, tileWorld)) requiredRegions.add(key);
      ensureMapTile(
        state.map.regionTiles,
        key,
        els.regionLayer,
        "map-overlay-tile fishing-region-tile",
        mapLayerTileUrl(regionLayer.tileUrlTemplate, level, x, y),
        x,
        y,
        tileWorld,
        1,
        "low",
        ready => { if (ready) scheduleMapTilesRender(); },
        true,
      );
      const image = state.map.regionTiles.get(key);
      if (image) image.dataset.overlayLevel = String(level);
    }
  }
  if (highlightEnabled) {
    for (const { x, y } of coordinates) {
      if (!zoneIntersectsTile(highlightedZone, x, y, tileWorld)) continue;
      const key = `${level}/${x}_${y}`;
      const highlightKey = `${regionLayer.revision || "unversioned"}/${highlightedRgb}/${highlightedColor}/${key}`;
      wantedHighlights.add(highlightKey);
      if (mapTileIntersectsViewport(x, y, tileWorld)) requiredHighlights.add(highlightKey);
      ensureMapTile(
        state.map.highlightTiles,
        highlightKey,
        els.zoneHighlightLayer,
        "map-overlay-tile fishing-region-highlight-tile",
        mapLayerTileUrl(highlightConfig.tileUrlTemplate, level, x, y, highlightedRgb, highlightedColor),
        x,
        y,
        tileWorld,
        Math.min(finiteNumberOrNull(highlightConfig.defaultOpacity) ?? .38, .38),
        "low",
        ready => { if (ready) scheduleMapTilesRender(); },
        true,
      );
      const image = state.map.highlightTiles.get(highlightKey);
      if (image) image.dataset.overlayLevel = String(level);
    }
  }
  commitMapOverlayTiles(state.map.regionTiles, regionCoverage, level, wantedRegions, requiredRegions);
  commitMapOverlayTiles(state.map.highlightTiles, highlightCoverage, level, wantedHighlights, requiredHighlights);
  state.map.tileLevel = level;
  updateMapOverlayVisibility();
  if (force) {
    renderSpotPoints(state.filteredZones);
    renderSettlementMarkers();
  }
}

function handleMapLootIconError(event) {
  const image = event.target;
  if (image?.tagName !== "IMG" || !image.matches(".loot-icon img")) return;
  const holder = image.closest(".loot-icon");
  if (!holder || !els.spotDrawer.contains(holder)) return;
  image.classList.add("is-hidden");
  holder.classList.add("is-missing");
  holder.setAttribute("role", "img");
  holder.setAttribute("aria-label", "Icon unavailable");
}

function bindMap() {
  els.spotDrawer.addEventListener("error", handleMapLootIconError, true);
  const applyPendingMapDrag = () => {
    mapPanFrame = 0;
    const drag = state.map.drag;
    if (!drag || drag.lastX == null || drag.lastY == null) return;
    state.map.offsetX = drag.offsetX + drag.lastX - drag.startX;
    state.map.offsetY = drag.offsetY + drag.lastY - drag.startY;
    clampMap();
    applyMapTransform();
    scheduleMapTilesRender();
  };
  els.mapViewport.addEventListener("wheel", event => {
    event.preventDefault();
    const rect = els.mapViewport.getBoundingClientRect();
    const factor = Math.exp(Math.max(-180, Math.min(180, -event.deltaY)) * .0018);
    if (!pendingMapWheel) pendingMapWheel = { factor: 1, anchorX: 0, anchorY: 0 };
    pendingMapWheel.factor *= factor;
    pendingMapWheel.anchorX = event.clientX - rect.left;
    pendingMapWheel.anchorY = event.clientY - rect.top;
    if (!mapWheelFrame) mapWheelFrame = window.requestAnimationFrame(() => {
      mapWheelFrame = 0;
      const pending = pendingMapWheel;
      pendingMapWheel = null;
      if (pending) zoomMap(pending.factor, pending.anchorX, pending.anchorY);
    });
  }, { passive: false });

  els.mapViewport.addEventListener("pointerdown", event => {
    if (event.button !== 0) return;
    els.mapViewport.setPointerCapture(event.pointerId);
    state.map.drag = { id: event.pointerId, startX: event.clientX, startY: event.clientY, lastX: event.clientX, lastY: event.clientY, offsetX: state.map.offsetX, offsetY: state.map.offsetY, moved: false };
    els.mapViewport.classList.add("is-dragging");
  });
  els.mapViewport.addEventListener("pointermove", event => {
    const drag = state.map.drag;
    if (!drag || drag.id !== event.pointerId) return;
    const dx = event.clientX - drag.startX;
    const dy = event.clientY - drag.startY;
    if (Math.hypot(dx,dy) > 4) drag.moved = true;
    drag.lastX = event.clientX;
    drag.lastY = event.clientY;
    if (!mapPanFrame) mapPanFrame = window.requestAnimationFrame(applyPendingMapDrag);
  });
  const endPointer = event => {
    const drag = state.map.drag;
    if (!drag || drag.id !== event.pointerId) return;
    drag.lastX = event.clientX;
    drag.lastY = event.clientY;
    if (mapPanFrame) window.cancelAnimationFrame(mapPanFrame);
    applyPendingMapDrag();
    state.map.drag = null;
    els.mapViewport.classList.remove("is-dragging");
    if (!drag.moved) inspectMapPoint(event.clientX, event.clientY);
    else renderTiles(true);
  };
  els.mapViewport.addEventListener("pointerup", endPointer);
  els.mapViewport.addEventListener("pointercancel", event => { if (state.map.drag?.id === event.pointerId) { if (mapPanFrame) window.cancelAnimationFrame(mapPanFrame); mapPanFrame = 0; state.map.drag = null; els.mapViewport.classList.remove("is-dragging"); } });
  els.mapViewport.addEventListener("keydown", event => {
    const step = event.shiftKey ? 180 : 70;
    if (["ArrowLeft","ArrowRight","ArrowUp","ArrowDown"].includes(event.key)) {
      event.preventDefault();
      if (event.key === "ArrowLeft") state.map.offsetX += step;
      if (event.key === "ArrowRight") state.map.offsetX -= step;
      if (event.key === "ArrowUp") state.map.offsetY += step;
      if (event.key === "ArrowDown") state.map.offsetY -= step;
      clampMap(); applyMapTransform(); renderTiles();
    }
    if (event.key === "+" || event.key === "=") zoomMap(1.24);
    if (event.key === "-") zoomMap(1 / 1.24);
  });
  els.zoomIn.addEventListener("click", () => zoomMap(1.3));
  els.zoomOut.addEventListener("click", () => zoomMap(1 / 1.3));
  els.zoomHome.addEventListener("click", homeMap);
  renderMapVisibleFrame();
  let resizeFrame = 0;
  const resizeMap = () => {
    resizeFrame = 0;
    const previousFrame = state.map.visibleFrame || measureMapVisibleFrame();
    const nextFrame = renderMapVisibleFrame();
    if (!nextFrame.width || !nextFrame.height) return;
    if (state.map.initialized) {
      state.map.offsetX += nextFrame.centerX - previousFrame.centerX;
      state.map.offsetY += nextFrame.centerY - previousFrame.centerY;
      state.map.minScale = Math.max(.01, Math.min(nextFrame.width / state.map.width, nextFrame.height / state.map.height) * .95);
      clampMap(nextFrame); applyMapTransform(); renderTiles(true);
      renderSpotPoints(state.filteredZones);
      renderSettlementMarkers();
    }
  };
  const scheduleResize = () => { if (!resizeFrame) resizeFrame = window.requestAnimationFrame(resizeMap); };
  if (typeof ResizeObserver === "function") {
    const observer = new ResizeObserver(scheduleResize);
    observer.observe(els.mapViewport);
    if (els.mapTools) observer.observe(els.mapTools);
    if (els.spotDrawer) observer.observe(els.spotDrawer);
  }
  window.addEventListener("resize", scheduleResize);
}

function selectZone(zone, point = undefined) {
  state.hoveredZone = null;
  state.selectedZone = zone || null;
  state.selectedPoint = zone
    ? (point && Number.isFinite(Number(point.x)) && Number.isFinite(Number(point.y))
      ? { ...point, x: Number(point.x), y: Number(point.y) }
      : null)
    : null;
  if (state.selectedPoint) showPin(state.selectedPoint.x, state.selectedPoint.y, state.selectedPoint.sourceKind === "ranking");
  else els.mapPin.classList.add("is-hidden");
  updateMapResultSelection();
  renderTiles(true);
}

function renderEmptySpotDrawer() {
  els.spotDrawer.innerHTML = `<div class="drawer-empty"><strong>Choose a fishing spot</strong></div>`;
}

function closeSpotDrawer() {
  setSpotDrawerOpen(false);
  state.spotRequestId += 1;
  state.selectedZone = null;
  state.selectedPoint = null;
  state.hoveredZone = null;
  els.mapPin.classList.add("is-hidden");
  renderEmptySpotDrawer();
  updateMapResultSelection();
  renderTiles(true);
}

async function inspectMapPoint(clientX, clientY) {
  const rect = els.mapViewport.getBoundingClientRect();
  const x = Math.floor((clientX - rect.left - state.map.offsetX) / state.map.scale);
  const y = Math.floor((clientY - rect.top - state.map.offsetY) / state.map.scale);
  if (x < 0 || y < 0 || x >= state.map.width || y >= state.map.height) return;
  const choosingLocation = Boolean(state.pendingMapLocation);
  showPin(x, y);
  if (!choosingLocation) {
    setSpotDrawerOpen(true);
    els.spotDrawer.innerHTML = `<div class="loot-loading"><span class="spinner"></span><span>Resolving exact fishing table…</span></div>`;
  }
  try {
    const result = await request(`/api/zone-at?x=${x}&y=${y}`);
    const rgb = normalizeRgb(result.rgb ?? result.zone?.rgb ?? result.zoneRgb);
    const knownZone = state.zoneByRgb.get(rgb) || result.zone || null;
    const zone = knownZone || { rgb, name: result.name || rgbToText(rgb), center: { x, y }, active: true, dataKnown: false };
    if (state.pendingMapLocation) {
      if (!Number.isFinite(rgb) || !knownZone?.name || knownZone.zoneRole === "out-of-bounds") {
        showToast("Choose a point inside a mapped fishing table.", true);
        return;
      }
      const pending = state.pendingMapLocation;
      state.pendingMapLocation = null;
      els.captureMapPrompt.classList.add("is-hidden");
      const hasNode = Boolean(pending.node);
      const inferredLocationName = String(result.location?.name || "").trim();
      const inputValue = hasNode ? pending.inputValue : (inferredLocationName || zone.name);
      const locationName = hasNode ? pending.locationName : (inferredLocationName || zone.name);
      const selectedLocation = {
        type: hasNode ? "node" : "map",
        inputKey: hasNode ? pending.inputKey : captureInputKey(inputValue),
        inputValue,
        locationName,
        node: pending.node || null,
        zone: { ...zone, rgb, depth: zone.depth || depthKey(zone) },
        point: { x, y },
        requiresExactClick: false,
        anchor: pending.anchor,
        inferredLocation: hasNode ? null : (result.location || null),
        source: "map-click",
      };
      if (pending.scope === "stats") {
        els.statsLocation.value = inputValue;
        state.statsLocation = selectedLocation;
        renderStatsLocationSelection();
        showToast(`${locationName} selected`);
        navigate("stats");
        return;
      }
      els.haulSpot.value = inputValue;
      commitCaptureLocation(selectedLocation);
      showToast(`${locationName} selected`);
      navigate("capture");
      return;
    }
    selectZone(zone, { x, y });
    await loadSpotDetails(rgb);
  } catch (error) {
    if (state.pendingMapLocation) showToast(error.message, true);
    else renderDrawerError(error.message);
  }
}

function showPin(x, y, approximate = false) {
  els.mapPin.dataset.mapWorldX = String(x);
  els.mapPin.dataset.mapWorldY = String(y);
  els.mapPin.style.left = `${state.map.offsetX + x * state.map.scale}px`;
  els.mapPin.style.top = `${state.map.offsetY + y * state.map.scale}px`;
  els.mapPin.classList.toggle("is-approximate", approximate);
  els.mapPin.classList.remove("is-hidden");
}

function focusZone(zone) {
  const focusPoint = zone?.center;
  if (!focusPoint) { showToast("This table has no mapped area yet.", true); return; }
  const frame = measureMapVisibleFrame();
  const targetScale = Math.max(state.map.scale, .50);
  state.map.scale = Math.min(targetScale, state.map.maxScale);
  state.map.offsetX = frame.centerX - focusPoint.x * state.map.scale;
  state.map.offsetY = frame.centerY - focusPoint.y * state.map.scale;
  clampMap(); applyMapTransform();
  selectZone(zone, null);
  setSpotDrawerOpen(true);
  loadSpotDetails(zone.rgb);
}

function focusEvidenceCluster(zone, point) {
  if (!zone || !point) return;
  const frame = measureMapVisibleFrame();
  state.map.scale = Math.min(Math.max(state.map.scale, .50), state.map.maxScale);
  state.map.offsetX = frame.centerX - Number(point.x) * state.map.scale;
  state.map.offsetY = frame.centerY - Number(point.y) * state.map.scale;
  clampMap();
  applyMapTransform();
  selectZone(zone, point);
  setSpotDrawerOpen(true);
  loadSpotDetails(zone.rgb);
}

async function loadSpotDetails(rgb) {
  const requestId = ++state.spotRequestId;
  const zone = state.zoneByRgb.get(Number(rgb)) || state.selectedZone || { rgb: Number(rgb), name: rgbToText(rgb) };
  if (state.selectedZone?.rgb !== zone.rgb) selectZone(zone);
  setSpotDrawerOpen(true);
  els.spotDrawer.innerHTML = `<div class="loot-loading"><span class="spinner"></span><span>Loading ${escapeHtml(zone.name)}…</span></div>`;
  try {
    const detail = await request(`/api/zone/${Number(rgb)}?method=${encodeURIComponent(state.method.map)}`);
    if (requestId !== state.spotRequestId) return;
    renderSpotDrawer(zone, detail);
  } catch (error) {
    if (requestId !== state.spotRequestId) return;
    renderDrawerError(error.message, zone);
  }
}

function renderDrawerError(message, zone = state.selectedZone) {
  els.spotDrawer.innerHTML = `<button type="button" class="drawer-close" aria-label="Close fishing table" style="position:absolute;right:14px;top:14px;z-index:3">×</button><div class="drawer-empty"><div class="empty-pin"><span></span></div><strong>${escapeHtml(zone?.name || "Fishing table unavailable")}</strong><p>${escapeHtml(message || "No verified loot table is available for this point.")}</p></div>`;
  $(".drawer-close", els.spotDrawer).addEventListener("click", closeSpotDrawer);
}

function knownRate(row) {
  const normalized = row.normalizedDropRateText ?? row.normalized_rate_text ?? row.rateText;
  const stateName = String(row.normalizedDropRateState ?? row.rateState ?? "").toLowerCase();
  if (stateName && stateName !== "known") return null;
  if (normalized == null || normalized === "" || /^(?:\?|unknown|unavailable)$/i.test(String(normalized).trim())) return null;
  return String(normalized).includes("%") ? String(normalized) : `${normalized}%`;
}

function renderSpotDrawer(zone, detail) {
  const method = state.method.map;
  const methodLabel = method === "rod" ? "Fishing" : "Harpooning";
  const methodIcon = method === "rod" ? 16141 : 16154;
  if (detail.available === false) {
    renderDrawerError(detail.note || detail.dataQualityNote || "This point is mapped, but its loot table is not known yet.", zone);
    return;
  }
  const allRows = Array.isArray(detail.speciesRows) ? detail.speciesRows : Array.isArray(detail.items) ? detail.items : [];
  const rows = allRows.filter(row => {
    const methods = row.catchMethods || row.methods || (row.catchMethod ? [row.catchMethod] : []);
    const pool = String(row.groupLabel || row.group || "").trim().toLowerCase();
    const assignedToTable = pool && pool !== "unassigned";
    return assignedToTable && (!methods.length || methods.includes(method));
  });
  const uniqueRows = deduplicateTableRows(rows);
  const gradeSections = groupTableRowsByGrade(uniqueRows);
  const selectedEvidence = state.selectedPoint?.sourceKind === "ranking" ? state.selectedPoint : null;
  const observedRows = Array.isArray(selectedEvidence?.observedFish) ? selectedEvidence.observedFish : [];

  const title = detail.zoneName || zone.name;
  els.spotDrawer.innerHTML = `
    <div class="drawer-header">
      <div class="drawer-title-row">
        <h2>${escapeHtml(title)}</h2>
        <div class="drawer-method" title="${methodLabel}"><img src="/icon/${methodIcon}.webp" alt="${methodLabel}"></div>
        <button type="button" class="drawer-close" aria-label="Close fishing table">×</button>
      </div>
    </div>
    <div class="loot-content">
      ${observedRows.length ? `<details class="evidence-section drawer-leaderboard-details">
        <summary>Leaderboard records</summary>
        <div class="loot-grid observed-grid">${observedRows.map(row => {
          const itemId = Number(row.itemId ?? row.id);
          const priceRaw = Number(row.priceRaw ?? row.price ?? 0);
          return `<div class="loot-item observed-item">
            <div class="loot-icon grade-frame ${itemGradeClass(row.grade || row.iconGradeTone)}"><img src="/icon/${itemId}.webp" alt=""></div>
            <div class="loot-meta"><strong>${escapeHtml(row.label || row.name || itemId)}</strong><small class="loot-value">${priceRaw > 0 ? `${silver(priceRaw)} silver` : "Value unknown"}</small></div>
            <span class="observation-count" aria-label="${number(row.observations || 0)} leaderboard records">×${number(row.observations || 0)}</span>
          </div>`;
        }).join("")}</div>
      </details>` : ""}
      ${gradeSections.length ? gradeSections.map(renderTableLootSection).join("") : `<div class="empty-state compact"><strong>No verified ${methodLabel.toLowerCase()} items</strong></div>`}
    </div>`;
  els.spotDrawer.scrollTop = 0;
  const closeButton = $(".drawer-close", els.spotDrawer);
  if (closeButton) closeButton.addEventListener("click", closeSpotDrawer);
}

function gradeClass(label) {
  return String(label || "").toLowerCase().replace(/[^a-z]+/g, "-").replace(/^-|-$/g, "");
}

function itemGradeClass(grade) {
  const key = String(grade || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
  if (["prize", "red", "orange", "grade4", "4"].includes(key)) return "grade-prize";
  if (["rare", "yellow", "grade3", "3"].includes(key)) return "grade-rare";
  if (["highquality", "blue", "grade2", "2"].includes(key)) return "grade-high-quality";
  if (["general", "green", "grade1", "1"].includes(key)) return "grade-general";
  return "grade-unknown";
}

function deduplicateTableRows(rows) {
  const byItem = new Map();
  rows.forEach(row => {
    const itemId = Number(row.itemId ?? row.id);
    if (!Number.isFinite(itemId)) return;
    const pool = String(row.groupLabel || row.group || "Unassigned").trim() || "Unassigned";
    const condition = String(row.conditionText || "").trim();
    const conditional = Boolean(row.hasConditions || row.conditionId || condition);
    const sourceEntry = {
      pool,
      rate: knownRate(row),
      state: conditional ? "conditional" : String(row.normalizedDropRateState || row.rateState || (knownRate(row) ? "known" : "unknown")).toLowerCase(),
      condition,
      conditionId: row.conditionId ?? null,
    };
    const existing = byItem.get(itemId);
    if (!existing) {
      byItem.set(itemId, {
        ...row,
        itemId,
        sourcePools: [pool],
        sourceRates: knownRate(row) ? [knownRate(row)] : [],
        sourceConditions: row.conditionText ? [row.conditionText] : [],
        sourceEntries: [sourceEntry],
      });
      return;
    }
    if (!existing.sourcePools.includes(pool)) existing.sourcePools.push(pool);
    const rate = knownRate(row);
    if (rate && !existing.sourceRates.includes(rate)) existing.sourceRates.push(rate);
    if (row.conditionText && !existing.sourceConditions.includes(row.conditionText)) existing.sourceConditions.push(row.conditionText);
    if (!existing.sourceEntries.some(entry => entry.pool === sourceEntry.pool && entry.rate === sourceEntry.rate && entry.state === sourceEntry.state && entry.condition === sourceEntry.condition && entry.conditionId === sourceEntry.conditionId)) existing.sourceEntries.push(sourceEntry);
    if (!existing.grade && row.grade) existing.grade = row.grade;
    if (!existing.iconGradeTone && row.iconGradeTone) existing.iconGradeTone = row.iconGradeTone;
  });
  return [...byItem.values()];
}

function gradeSectionForRow(row) {
  if (row.isFish === false) return { key: "other", label: "Other loot", order: 5, badge: "other" };
  const frame = itemGradeClass(row.grade || row.iconGradeTone || row.icon_grade_tone);
  if (frame === "grade-prize") return { key: "prize", label: "Red fish", order: 0, badge: "prize" };
  if (frame === "grade-rare") return { key: "rare", label: "Yellow fish", order: 1, badge: "rare" };
  if (frame === "grade-high-quality") return { key: "high-quality", label: "Blue fish", order: 2, badge: "high-quality" };
  if (frame === "grade-general") return { key: "general", label: "Green fish", order: 3, badge: "general" };
  return { key: "unknown", label: "Other fish", order: 4, badge: "other" };
}

function groupTableRowsByGrade(rows) {
  const sections = new Map();
  rows.forEach(row => {
    const definition = gradeSectionForRow(row);
    if (!sections.has(definition.key)) sections.set(definition.key, { ...definition, rows: [] });
    sections.get(definition.key).rows.push(row);
  });
  return [...sections.values()]
    .sort((a,b) => a.order - b.order)
    .map(section => ({ ...section, rows: section.rows.sort((a,b) => String(a.label || a.name).localeCompare(String(b.label || b.name))) }));
}

function renderObservedEvidence(point) {
  const rows = Array.isArray(point.observedFish) ? point.observedFish : [];
  const observations = Number(point.observations || 0);
  const radius = Number(point.uncertaintyGameUnits || 500);
  return `<section class="evidence-section">
    <div class="evidence-heading"><div><h3>Evidence near this position</h3><p>Grouped nearby rankings · each position has ${number(radius)}-unit uncertainty · capture method is not recorded · not a catch rate</p></div><span>${number(observations)} observations</span></div>
    <div class="loot-grid observed-grid">${rows.map(row => {
      const itemId = Number(row.itemId ?? row.id);
      const priceRaw = Number(row.priceRaw ?? row.price ?? 0);
      return `<div class="loot-item observed-item">
        <div class="loot-icon grade-frame ${itemGradeClass(row.grade || row.iconGradeTone)}"><img src="/icon/${itemId}.webp" alt=""></div>
        <div class="loot-meta"><strong>${escapeHtml(row.label || row.name || itemId)}</strong><small class="loot-value">${priceRaw > 0 ? `${silver(priceRaw)} silver` : "Value unknown"}</small></div>
        <span class="observation-count">×${number(row.observations || 0)}</span>
      </div>`;
    }).join("")}</div>
  </section>`;
}

function renderTableLootSection(section) {
  return `<section class="loot-section">
    <div class="loot-heading"><span class="grade-badge ${section.badge}">${escapeHtml(section.label)}</span><small>${section.rows.length}</small></div>
    <div class="loot-grid">${section.rows.map(row => {
      const itemId = Number(row.itemId ?? row.id);
      const priceRaw = Number(row.priceRaw ?? row.price ?? 0);
      return `<div class="loot-item">
        <div class="loot-icon grade-frame ${itemGradeClass(row.grade || row.iconGradeTone || row.icon_grade_tone)}"><img src="/icon/${itemId}.webp" alt=""></div>
        <div class="loot-meta"><strong>${escapeHtml(row.label || row.name || itemId)}</strong><div class="loot-facts"><small class="loot-value">${priceRaw > 0 ? `${silver(priceRaw)} silver` : "Value unknown"}</small>${renderTableRowRate(row)}</div></div>
      </div>`;
    }).join("")}</div>
  </section>`;
}

function renderTableRowRate(row) {
  const entries = row.sourceEntries || [{
    pool: String(row.groupLabel || row.group || "Unknown"),
    rate: knownRate(row),
    state: row.hasConditions || row.conditionId || row.conditionText ? "conditional" : "unknown",
    condition: String(row.conditionText || ""),
  }];
  const conditional = entries.some(entry => entry.state === "conditional");
  const single = entries.length === 1 && !conditional;
  const label = single ? entries[0].rate || "Unknown" : conditional ? "Conditional" : "Rates";
  const itemName = String(row.label || row.name || row.itemId);
  return `<details class="loot-rate-details${single && entries[0].rate ? " has-rate" : ""}">
    <summary class="${single && entries[0].rate ? "item-rate" : "pool-count"}" aria-label="${escapeHtml(`${itemName}: ${label}. Source percentages`)}">${escapeHtml(label)}</summary>
    <div class="loot-rate-options">${entries.map(entry => `<div class="loot-rate-option"><strong>${escapeHtml(entry.pool)}</strong><span>${escapeHtml(entry.rate || "Unknown")}</span>${entry.condition ? `<small>${escapeHtml(entry.condition)}</small>` : entry.state === "conditional" ? `<small>Source condition is not specified.</small>` : ""}</div>`).join("")}
      <small>Within each source pool, not per-cast odds.</small>
    </div>
  </details>`;
}

function renderPoolSummary(groups, profileLabel = "") {
  if (String(profileLabel).startsWith("calculator-")) {
    return `<section class="pool-summary"><strong>Personal catch chances not calculated</strong><p class="table-accuracy-note">The source's pool percentages use a calculator profile whose inputs are not supplied here. They are not verified for your mastery or equipment. Fish-row percentages are source-model/community estimates within their pool, not verified per-cast probabilities.</p></section>`;
  }
  const poolPresentation = label => {
    const rawLabel = String(label || "Other").trim();
    const key = rawLabel.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    const knownPools = {
      prize: { label: "Prize pool", className: "prize" },
      rare: { label: "Rare pool", className: "rare" },
      "high-quality": { label: "High Quality pool", className: "high-quality" },
      highquality: { label: "High Quality pool", className: "high-quality" },
      general: { label: "General pool", className: "general" },
      trash: { label: "Other loot", className: "trash" },
      harpoon: { label: "Harpoon pool", className: "harpoon" },
    };
    return knownPools[key] || { label: `${rawLabel} pool`, className: "other" };
  };
  const known = groups.map(group => {
    const presentation = poolPresentation(group.label || group.groupLabel || "Other");
    return { ...presentation, rate: knownRate(group) };
  }).filter(entry => entry.rate);
  if (!known.length) return "";
  return `<section class="pool-summary">
    <div class="pool-summary-heading"><strong>Source loot-pool rates</strong></div><p class="table-accuracy-note">Pools are separate from icon grades. Rates depend on conditions and are not individual fish catch chances.</p>
    ${known.map(entry => {
      const numericRate = Number.parseFloat(entry.rate);
      const width = Number.isFinite(numericRate) ? Math.max(0, Math.min(100,numericRate)) : 0;
      return `<div class="pool-summary-row ${escapeHtml(entry.className)}"><span>${escapeHtml(entry.label)}</span><div class="rate-track"><i style="width:${width}%"></i></div><strong>${escapeHtml(entry.rate)}</strong></div>`;
    }).join("")}
  </section>`;
}

function resultPoolRate(zone, method, label) {
  const byMethod = zone?.groupRatesByMethod || zone?.group_rates_by_method || {};
  const methodRates = byMethod?.[method] || {};
  const wanted = String(label).toLowerCase();
  const entry = Object.entries(methodRates).find(([key]) => String(key).toLowerCase() === wanted);
  if (!entry) return null;
  const value = typeof entry[1] === "object"
    ? entry[1]?.ratePercent ?? entry[1]?.rate ?? entry[1]?.value
    : entry[1];
  return finiteNumberOrNull(value);
}

function renderResultPoolRates(zone, method) {
  if (String(zone?.rateProfileLabel || "").startsWith("calculator-")) return "";
  const labels = method === "harpoon" ? ["Harpoon"] : ["Prize", "Rare"];
  const rates = labels
    .map(label => ({ label, rate: resultPoolRate(zone, method, label) }))
    .filter(entry => entry.rate != null);
  if (!rates.length) return "";
  return `<span class="result-pool-rates" title="Loot-pool chance; this is separate from the fish icon grade">
    ${rates.map(entry => `<span class="result-pool-rate ${entry.label.toLowerCase()}"><span>${escapeHtml(entry.label)}</span><i><b style="width:${Math.max(1, Math.min(100, entry.rate))}%"></b></i><strong>${number(entry.rate, 2)}%</strong></span>`).join("")}
  </span>`;
}

function depthLabel(value) {
  const key = String(value || "open-sea");
  if (key === "inland") return "Inland fishing";
  if (key === "coast") return "Coastal fishing";
  if (key === "open-sea") return "Open sea";
  if (key.startsWith("depth-")) return `Depth ${key.slice(-1)}`;
  return key.replace(/-/g," ");
}

function zoneMatchesMethod(zone, method) {
  if (!zone.dataKnown) return true;
  return !zone.methods?.length || zone.methods.includes(method);
}

function itemMatchesMethod(item, method) {
  const methods = item.catchMethods || item.methods || (item.catchMethod ? [item.catchMethod] : item.method ? [item.method] : []);
  return !methods.length || methods.map(value => String(value).toLowerCase()).includes(method);
}

function zoneItemsForMethod(zone, method) {
  return (zone.items || []).filter(item => itemMatchesMethod(item, method));
}

function highestListedFishValue(zone, method) {
  let highest = null;
  for (const item of zoneItemsForMethod(zone, method)) {
    const isFish = item.isFish === true || (item.isFish !== false
      && state.fish.some(fish => Number(fish.itemId ?? fish.id) === Number(item.itemId ?? item.id)));
    if (!isFish) continue;
    const price = finiteNumberOrNull(item.priceRaw ?? item.price);
    if (price != null && price > 0) highest = highest == null ? price : Math.max(highest, price);
  }
  return highest;
}

function compareListedFishValue(a, b, method) {
  const aValue = highestListedFishValue(a, method);
  const bValue = highestListedFishValue(b, method);
  if (aValue == null && bValue == null) return 0;
  if (aValue == null) return 1;
  if (bValue == null) return -1;
  return bValue - aValue;
}

function experimentalMoneyMetric(zone, method) {
  const byMethod = zone?.experimentalMoneyByMethod;
  const source = byMethod?.[method];
  if (!source || String(source.status || "").toLowerCase() !== "modeled") return null;
  const consistentBaseFishValuePer100 = finiteNumberOrNull(source.consistentBaseFishValuePer100);
  if (consistentBaseFishValuePer100 == null) return null;
  return {
    consistentBaseFishValuePer100,
    expectedBaseFishValuePer100: finiteNumberOrNull(source.expectedBaseFishValuePer100),
    redFishChancePercent: finiteNumberOrNull(source.redFishChancePercent),
    consistencyPercentile: finiteNumberOrNull(source.consistencyPercentile),
    approximationErrorSilver: finiteNumberOrNull(source.approximationErrorSilver),
    quantileMethod: String(source.quantileMethod || "").trim(),
    rateProfileLabel: String(source.rateProfileLabel || "").trim(),
    sourceProfileConditions: Array.isArray(source.sourceProfileConditions)
      ? source.sourceProfileConditions.map(value => String(value || "").trim()).filter(Boolean)
      : [],
    sourceDataMayBeIncomplete: source.sourceDataMayBeIncomplete === true,
    sourceDataQualityNote: String(source.sourceDataQualityNote || "").trim(),
  };
}

function compareExperimentalMoney(a, b, method) {
  const aMetric = experimentalMoneyMetric(a, method);
  const bMetric = experimentalMoneyMetric(b, method);
  if (!aMetric && !bMetric) return 0;
  if (!aMetric) return 1;
  if (!bMetric) return -1;
  return bMetric.consistentBaseFishValuePer100 - aMetric.consistentBaseFishValuePer100
    || (bMetric.expectedBaseFishValuePer100 ?? -Infinity) - (aMetric.expectedBaseFishValuePer100 ?? -Infinity)
    || (bMetric.redFishChancePercent ?? -Infinity) - (aMetric.redFishChancePercent ?? -Infinity);
}

function methodMetric(zone, field, method) {
  const byMethod = zone?.[`${field}ByMethod`] || zone?.[`${field}_by_method`];
  if (byMethod && Object.prototype.hasOwnProperty.call(byMethod, method)) {
    const value = byMethod[method];
    if (field === "hasRelic") return value == null ? null : Boolean(value);
    return finiteNumberOrNull(value);
  }
  const fallback = zone?.[field];
  if (field === "hasRelic") return fallback == null ? null : Boolean(fallback);
  return finiteNumberOrNull(fallback);
}

function compareMethodMetricDescending(a, b, field, method) {
  const aValue = methodMetric(a, field, method);
  const bValue = methodMetric(b, field, method);
  if (aValue == null && bValue == null) return 0;
  if (aValue == null) return 1;
  if (bValue == null) return -1;
  return bValue - aValue;
}

function evidenceMetric(zone, field) {
  return finiteNumberOrNull(zone?.evidencePoint?.[field]);
}

function compareEvidenceMetricDescending(a, b, field) {
  const aValue = evidenceMetric(a, field);
  const bValue = evidenceMetric(b, field);
  if (aValue == null && bValue == null) return 0;
  if (aValue == null) return 1;
  if (bValue == null) return -1;
  return bValue - aValue;
}

function evidencePointMetric(point, field) {
  return finiteNumberOrNull(point?.[field]);
}

function compareEvidencePoints(a, b, field) {
  const aValue = evidencePointMetric(a.point, field);
  const bValue = evidencePointMetric(b.point, field);
  if (aValue == null && bValue == null) return 0;
  if (aValue == null) return 1;
  if (bValue == null) return -1;
  return bValue - aValue;
}

function evidenceSupport(point) {
  const observations = Number(point?.observations || 0);
  if (observations >= 10) return 3;
  if (observations >= 5) return 2;
  if (observations >= 2) return 1;
  return 0;
}

function canonicalMapFish() {
  const query = normalizeSearchText(els.mapSearch?.value || "");
  const matches = query ? state.fish.filter(item => normalizeSearchText(item.name) === query || String(item.itemId) === query) : [];
  return matches.length === 1 ? matches[0] : null;
}

function zoneEvidenceEntries(zones) {
  const selectedFish = canonicalMapFish();
  // Ranking observations do not establish a capture method. Do not show a
  // rod-only fish as harpoon evidence simply because its zone has both methods.
  if (selectedFish && !(selectedFish.methods || []).includes(state.method.map)) return [];
  return zones.flatMap(zone => zone.zoneRole === "named-table"
    ? (zone.evidenceClusters || []).map((point, clusterIndex) => ({ zone, point, clusterIndex }))
      .filter(({ point }) => !selectedFish || (point.observedFish || []).some(item => Number(item.itemId ?? item.id) === selectedFish.itemId))
    : []);
}

function zoneRoleLabel(zone) {
  if (zone.zoneRole === "broad-default") return "Broad fishing table";
  if (zone.zoneRole === "unknown") return "Unknown fishing table";
  return "Mapped fishing table";
}

function normalizeSearchText(value) {
  return String(value ?? "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

function settlementType(node) {
  const type = String(node?.nodeTypeLabel || node?.kind || node?.type || "").trim().toLowerCase();
  return type === "city" || type === "village" || type === "trade" ? type : "";
}

function settlementPriority(node) {
  const type = settlementType(node);
  const typePriority = type === "city" ? 300 : type === "village" ? 200 : 100;
  return Number(SETTLEMENT_PRIORITY.get(node.name) || 0) + typePriority;
}

function settlementLabelBox(x, y, width, height, placement) {
  // Match the existing one-pixel marker's CSS anchors, including its height.
  if (placement === "left") return { left: x + 1 - width - 24, top: y - 17, right: x + 1 - 24, bottom: y - 17 + height };
  if (placement === "above") return { left: x - width / 2, top: y + 1 - height - 38, right: x + width / 2, bottom: y + 1 - 38 };
  if (placement === "below") return { left: x - width / 2, top: y + 7, right: x + width / 2, bottom: y + height + 7 };
  return { left: x + 24, top: y - 17, right: x + width + 24, bottom: y - 17 + height };
}

function settlementBoxesOverlap(a, b, padding = 5) {
  return a.left < b.right + padding && a.right + padding > b.left && a.top < b.bottom + padding && a.bottom + padding > b.top;
}

function settlementIconBox(x, y, type) {
  const size = type === "city" ? 36 : type === "trade" ? 30 : 32;
  // The CSS icon is centred on x and has bottom:-1px inside a 1px marker.
  return { left: x - size / 2, top: y + 2 - size, right: x + size / 2, bottom: y + 2 };
}

let settlementLayoutCache = null;

function settlementLayout(nodes, scale, minScale) {
  const showFeaturedVillages = scale >= minScale * 1.45;
  const showAllVillages = scale >= minScale * 2.6;
  const showTradeHubs = scale >= minScale * 2.35;
  const candidates = nodes.filter(node => {
    const type = settlementType(node);
    if (!Number.isFinite(node.x) || !Number.isFinite(node.y)) return false;
    if (/^(?:undiscovered|unknown)(?:\s+area)?$/i.test(node.name)) return false;
    if (type === "city") return true;
    if (type === "village") return showAllVillages || (showFeaturedVillages && SETTLEMENT_PRIORITY.has(node.name));
    return type === "trade" && showTradeHubs;
  }).sort((a, b) => settlementPriority(b) - settlementPriority(a)
    || a.name.localeCompare(b.name) || a.x - b.x || a.y - b.y
    || String(a.id ?? a.waypointId ?? "").localeCompare(String(b.id ?? b.waypointId ?? "")));
  const fontFamily = typeof getComputedStyle === "function" && els.settlementLayer
    ? getComputedStyle(els.settlementLayer).fontFamily
    : '"Segoe UI", sans-serif';
  const signature = JSON.stringify([scale, fontFamily, candidates.map(node => [
    node.id ?? node.waypointId ?? null, node.name, node.x, node.y, settlementType(node),
  ])]);
  if (settlementLayoutCache?.signature === signature) return settlementLayoutCache.layout;

  let measure = null;
  try { measure = document.createElement("canvas").getContext("2d"); } catch { /* Conservative text-width fallback. */ }
  // Reserve all eligible icons before placing any labels. A later node's icon
  // must not paint over a higher-priority label, even if that node is offscreen.
  const iconBoxes = candidates.map(node => ({ node, box: settlementIconBox(node.x * scale, node.y * scale, settlementType(node)) }));
  const occupied = [];
  const layout = [];
  for (const node of candidates) {
    const type = settlementType(node);
    const fontSize = type === "city" ? 13 : 12;
    const name = String(node.name);
    if (measure) measure.font = `800 ${fontSize}px ${fontFamily}`;
    const textWidth = measure ? measure.measureText(name).width : name.length * fontSize * .7;
    // Include padding, borders, letter spacing and a small rounding allowance.
    // No maximum width: long place names must retain their complete label.
    const width = Math.max(72, Math.ceil(textWidth + (type === "city" ? 22 : 20) + Math.max(0, name.length - 1) * fontSize * .005 + 2));
    const height = type === "city" ? 29 : 26;
    const x = node.x * scale;
    const y = node.y * scale;
    for (const placement of ["right", "left", "above", "below"]) {
      const box = settlementLabelBox(x, y, width, height, placement);
      if (iconBoxes.some(icon => icon.node !== node && settlementBoxesOverlap(box, icon.box))) continue;
      if (occupied.some(existing => settlementBoxesOverlap(box, existing))) continue;
      occupied.push(box);
      layout.push({ node, type, x, y, placement, box });
      break;
    }
  }
  // A single scale's deterministic layout is enough. Panning never repacks it.
  settlementLayoutCache = { signature, layout };
  return layout;
}

function renderSettlementMarkers() {
  if (!els.settlementLayer) return;
  if (!state.settlementVisible || !state.map.initialized) {
    els.settlementLayer.replaceChildren();
    return;
  }
  const scale = state.map.scale;
  const visibleFrame = measureMapVisibleFrame();
  const viewportRect = els.mapViewport.getBoundingClientRect();
  const stage = els.mapViewport.closest(".map-stage");
  const blocked = stage ? $$(".map-toolbar, .zoom-controls, .fishystuff-credit, .map-towns-toggle, .capture-map-prompt:not(.is-hidden)", stage).map(control => {
    const rect = control.getBoundingClientRect();
    if (!rect.width || !rect.height) return null;
    return { left: rect.left - viewportRect.left - 7, top: rect.top - viewportRect.top - 7, right: rect.right - viewportRect.left + 7, bottom: rect.bottom - viewportRect.top + 7 };
  }).filter(Boolean) : [];
  const edgeMargin = 115;
  const markers = [];
  settlementLayout(state.nodes, scale, state.map.minScale).forEach(({ node, type, placement, x: mapX, y: mapY, box: mapBox }) => {
    const x = mapX + state.map.offsetX;
    const y = mapY + state.map.offsetY;
    if (x < visibleFrame.left - edgeMargin || y < visibleFrame.top - edgeMargin || x > visibleFrame.right + edgeMargin || y > visibleFrame.bottom + edgeMargin) return;
    const box = { left: mapBox.left + state.map.offsetX, right: mapBox.right + state.map.offsetX,
      top: mapBox.top + state.map.offsetY, bottom: mapBox.bottom + state.map.offsetY };
    // Screen edges and controls can hide a label, but never change its side.
    if (box.left < visibleFrame.left + 7 || box.top < visibleFrame.top + 7 || box.right > visibleFrame.right - 7 || box.bottom > visibleFrame.bottom - 7) return;
    if (blocked.some(blocker => settlementBoxesOverlap(box, blocker, 0))) return;
    const icon = type === "city" ? 2 : type === "trade" ? 5 : 1;
    markers.push(`<span class="settlement-marker is-${type} place-${placement}" data-map-world-x="${node.x}" data-map-world-y="${node.y}" style="left:${x}px;top:${y}px"><i aria-hidden="true"><img src="/node-icons/${icon}.png" alt=""></i><strong>${escapeHtml(node.name)}</strong></span>`);
  });
  els.settlementLayer.innerHTML = markers.join("");
}

function renderSpotPoints(zones = state.filteredZones) {
  if (!els.spotPointLayer) return;
  if (state.selectedZone || els.mapRank?.value !== "evidence") {
    els.spotPointLayer.replaceChildren();
    return;
  }
  const threshold = state.map.scale < .18 ? 5 : state.map.scale < .55 ? 2 : 1;
  const margin = 70 / state.map.scale;
  const visibleFrame = measureMapVisibleFrame();
  const left = (visibleFrame.left - state.map.offsetX) / state.map.scale - margin;
  const top = (visibleFrame.top - state.map.offsetY) / state.map.scale - margin;
  const right = (visibleFrame.right - state.map.offsetX) / state.map.scale + margin;
  const bottom = (visibleFrame.bottom - state.map.offsetY) / state.map.scale + margin;
  const mapped = zoneEvidenceEntries(zones).filter(({ point }) => {
    const observations = Number(point.observations || 0);
    return observations >= threshold && point.x >= left && point.x <= right && point.y >= top && point.y <= bottom;
  });
  els.spotPointLayer.innerHTML = mapped.map(({ zone, point, clusterIndex }, index) => {
    const redCount = Number(point.observedRedSpeciesCount || 0);
    const observations = Number(point.observations || 0);
    const redClass = redCount > 0 ? " has-red-fish" : "";
    const supportClass = observations >= 10 ? " is-strong" : observations >= 5 ? " is-supported" : " is-weak";
    const label = `${zone.name} · ${number(redCount)} red-grade ${redCount === 1 ? "fish" : "fish"} evidenced nearby · ${number(observations)} ranking observations · 500-unit uncertainty`;
    const screenX = state.map.offsetX + Number(point.x) * state.map.scale;
    const screenY = state.map.offsetY + Number(point.y) * state.map.scale;
    return `<button type="button" class="fishing-spot-point${redClass}${supportClass}" data-rgb="${zone.rgb}" data-cluster-index="${clusterIndex}" data-map-world-x="${Number(point.x)}" data-map-world-y="${Number(point.y)}" style="left:${screenX}px;top:${screenY}px;--spot-delay:-${((index % 19) * .11).toFixed(2)}s" aria-label="${escapeHtml(label)}" title="${escapeHtml(label)}"></button>`;
  }).join("");
  $$(".fishing-spot-point", els.spotPointLayer).forEach(button => {
    const zone = state.zoneByRgb.get(Number(button.dataset.rgb));
    const point = zone?.evidenceClusters?.[Number(button.dataset.clusterIndex)];
    button.addEventListener("pointerdown", event => event.stopPropagation());
    button.addEventListener("click", event => {
      event.stopPropagation();
      focusEvidenceCluster(zone, point);
    });
  });
}

function applyMapFilters() {
  const query = els.mapSearch.value.trim().toLowerCase();
  const compactQuery = normalizeSearchText(query);
  const canonicalFish = canonicalMapFish();
  const canonicalItemId = canonicalFish?.itemId ?? null;
  const rank = els.mapRank.value;
  const moneyRanking = rank === "consistent";
  if (els.mapRankExperimental) els.mapRankExperimental.hidden = !moneyRanking;
  if (els.mapMoneyExplainer) els.mapMoneyExplainer.hidden = !moneyRanking;
  const depth = els.mapDepth.value;
  const noRelic = els.mapNoRelic.checked;
  const method = state.method.map;
  let zones = state.zones.filter(zone => zone.active && zone.name && zone.zoneRole !== "out-of-bounds");
  const assignedZones = canonicalFish ? zones.filter(zone => zoneItemsForMethod(zone, method).some(item => Number(item.itemId ?? item.id) === canonicalItemId)) : [];
  zones = zones.filter(zone => zoneMatchesMethod(zone, method));
  if (depth !== "all") zones = zones.filter(zone => zone.depth === depth);
  if (noRelic) zones = zones.filter(zone => zone.dataKnown && methodMetric(zone, "hasRelic", method) === false);
  if (query) {
    zones = zones.filter(zone => {
      const methodItems = zoneItemsForMethod(zone, method);
      if (canonicalItemId != null) {
        const hasCanonicalItem = methodItems.some(item => Number(item.itemId ?? item.id) === canonicalItemId);
        return hasCanonicalItem;
      }
      const itemTerms = methodItems.map(item => `${item.name || item.label || ""} ${item.itemId || item.id || ""}`).join(" ");
      const haystack = `${zone.name} ${itemTerms || (!zone.items?.length ? zone.searchTerms || "" : "")}`.toLowerCase();
      const has = haystack.includes(query) || Boolean(compactQuery && normalizeSearchText(haystack).includes(compactQuery));
      return has;
    });
  }
  if (rank === "red") zones.sort((a,b) => compareMethodMetricDescending(a, b, "redSpeciesCount", method) || a.name.localeCompare(b.name));
  if (rank === "value") zones.sort((a,b) => compareListedFishValue(a, b, method) || compareMethodMetricDescending(a, b, "redSpeciesCount", method) || a.name.localeCompare(b.name));
  if (moneyRanking) zones.sort((a,b) => compareExperimentalMoney(a, b, method) || a.name.localeCompare(b.name));
  if (rank === "name") zones.sort((a,b) => a.name.localeCompare(b.name));
  state.filteredZones = zones;
  const tableRanking = moneyRanking || (["red", "value"].includes(rank) && !canonicalFish);
  const tableEntries = tableRanking ? zones.filter(zone => zone.tableRecommendationEligible !== false && zone.zoneRole === "named-table" && zone.dataKnown) : zones;
  els.mapResultCount.textContent = `${tableEntries.length} areas`;
  els.mapResults.classList.toggle("has-results", true);
  const resultEntries = tableEntries;
  const conflictBanner = canonicalFish?.sourceConflictNotes?.length
    ? `<details class="map-search-empty map-search-source"><summary>Source conflict <span aria-hidden="true">ⓘ</span></summary><small>${escapeHtml(canonicalFish.sourceConflictNotes.map(note => typeof note === "string" ? note : note.message || note.note || "Source disagreement; check audit report.").join(" "))}</small></details>` : "";
  const emptyCanonicalFish = Boolean(canonicalFish && resultEntries.length === 0);
  const emptyReason = assignedZones.length
    ? `${assignedZones.length} source-table assignments exist for this method, but none match these filters.`
    : `No verified ${method === "harpoon" ? "harpooning" : "fishing"}-table assignment is available in the loaded source. This is a data gap, not proof the fish cannot be caught.`;
  els.mapResults.innerHTML = conflictBanner + (emptyCanonicalFish
    ? `<div class="map-search-empty"><strong>${escapeHtml(canonicalFish.name)}</strong><span>${escapeHtml(emptyReason)}</span><small>${escapeHtml(canonicalFish.locationNote || "Try another method or clear filters. No unrelated table is substituted.")}</small></div>`
    : resultEntries.length ? resultEntries.map(entry => {
    const zone = entry;
    const resultKind = zoneRoleLabel(zone);
    if (moneyRanking) {
      const metric = experimentalMoneyMetric(zone, method);
      const iconId = method === "harpoon" ? 16154 : 16141;
      const methodLabel = method === "harpoon" ? "Harpooning" : "Fishing";
      const resultContext = `${methodLabel} table · ${depthLabel(zone.depth)}`;
      const profileContext = metric
        ? `Source profile: ${metric.rateProfileLabel || "source-selected calculator profile"}${metric.sourceProfileConditions.length ? ` (${metric.sourceProfileConditions.join("; ")})` : ""}`
        : "";
      const sourceCaveat = metric?.sourceDataMayBeIncomplete
        ? ` · Source warning: ${metric.sourceDataQualityNote || "this table may be incomplete"}`
        : "";
      const modelTitle = metric
        ? `${resultContext} · Experimental modeled P${number(metric.consistencyPercentile ?? 25)}: ${number(metric.consistentBaseFishValuePer100)} silver per 100 catches${metric.expectedBaseFishValuePer100 == null ? "" : ` · Expected average: ${number(metric.expectedBaseFishValuePer100)} silver per 100 catches`}${metric.redFishChancePercent == null ? "" : ` · Red fish chance: ${number(metric.redFishChancePercent, 2)}%`} · Deterministic binned distribution${metric.approximationErrorSilver == null ? "" : ` · Approximation within ±${number(metric.approximationErrorSilver)} silver`} · ${profileContext} · Base fish value only${sourceCaveat}`
        : `${resultContext} · Not enough rate data · This table is not scored as zero`;
      return `<button type="button" class="map-result is-money-model" data-rgb="${zone.rgb}" title="${escapeHtml(modelTitle)}" aria-label="${escapeHtml(`${zone.name} · ${modelTitle}`)}" aria-pressed="false"><span class="result-fish-icon result-method-icon" title="${methodLabel}"><img src="/icon/${iconId}.webp" alt=""></span><strong>${escapeHtml(zone.name)}</strong>${metric ? `<span class="result-money-primary">${silver(metric.consistentBaseFishValuePer100)} / 100 catches</span><span class="result-money-secondary">${metric.redFishChancePercent == null ? "Red chance unavailable" : `${number(metric.redFishChancePercent, 2)}% red fish`}</span>` : `<span class="result-money-primary is-unavailable">Not enough rate data</span>`}</button>`;
    }
    const redFishSource = zoneItemsForMethod(zone, method);
    const allRedFish = [...new Map(redFishSource.filter(item => item.isFish !== false && item.grade === "Prize").map(item => [Number(item.itemId ?? item.id), item])).values()];
    const resultFish = canonicalFish
      ? [...new Map(redFishSource.filter(item => Number(item.itemId ?? item.id) === canonicalItemId).map(item => [Number(item.itemId ?? item.id), item])).values()]
      : allRedFish;
    const iconItem = resultFish[0] || redFishSource.find(item => item.isFish !== false) || null;
    const iconId = iconItem ? Number(iconItem.itemId ?? iconItem.id) : method === "harpoon" ? 16154 : 16141;
    const resultContext = `${resultKind} · ${depthLabel(zone.depth)}${zone.dataKnown ? "" : " · loot unknown"}`;
    const itemTitle = iconItem ? String(iconItem.name || iconItem.label || iconId) : method === "harpoon" ? "Harpooning" : "Fishing";
    return `<button type="button" class="map-result ${zone.zoneRole === "named-table" ? "" : "is-broad"}" data-rgb="${zone.rgb}" title="${escapeHtml(resultContext)}" aria-pressed="false"><span class="result-fish-icon grade-frame ${itemGradeClass(iconItem?.grade)}" title="${escapeHtml(itemTitle)}"><img src="/icon/${iconId}.webp" alt=""></span><strong>${escapeHtml(zone.name)}</strong></button>`;
  }).join("") : `<div class="map-search-empty"><strong>No matching areas</strong><small>Try another search or reset filters.</small></div>`);
  $$(".map-result", els.mapResults).forEach(button => {
    const zone = state.zoneByRgb.get(Number(button.dataset.rgb));
    button.addEventListener("click", () => focusZone(zone));
  });
  updateMapResultSelection();
  renderSpotPoints(zones);
}

function updateMapResultSelection() {
  if (!els.mapResults) return;
  $$(".map-result", els.mapResults).forEach(button => {
    const rgb = Number(button.dataset.rgb);
    const point = button.dataset.clusterIndex == null ? null : state.zoneByRgb.get(rgb)?.evidenceClusters?.[Number(button.dataset.clusterIndex)];
    const active = rgb === state.selectedZone?.rgb && (!point || (state.selectedPoint?.sourceKind === "ranking" && state.selectedPoint.x === Number(point.x) && state.selectedPoint.y === Number(point.y)));
    button.classList.toggle("is-selected", active);
    button.setAttribute("aria-pressed", String(active));
  });
}

function updateRegionOpacity(value = state.regionOpacityPercent) {
  const parsed = Number(value);
  const percent = Number.isFinite(parsed) ? Math.max(0, Math.min(100, Math.round(parsed))) : state.regionOpacityPercent;
  state.regionOpacityPercent = percent;
  if (els.regionOpacity) els.regionOpacity.value = String(percent);
  if (els.regionOpacityValue) els.regionOpacityValue.textContent = `${percent}%`;
  if (els.regionLayer) els.regionLayer.style.opacity = String(percent / 100);
}

function bindMapFilters() {
  [els.mapSearch, els.mapRank, els.mapDepth, els.mapNoRelic].forEach(control => control.addEventListener(control.tagName === "INPUT" && control.type !== "checkbox" ? "input" : "change", applyMapFilters));
  els.mapResetFilters.addEventListener("click", () => {
    els.mapSearch.value = "";
    els.mapRank.value = "red";
    els.mapDepth.value = "all";
    els.mapNoRelic.checked = false;
    applyMapFilters();
  });
  els.regionOpacity.addEventListener("input", event => updateRegionOpacity(event.target.value));
  els.mapExpand.addEventListener("click", () => {
    let expanded = false;
    preserveMapVisibleFrame(() => { expanded = els["page-map"].classList.toggle("map-expanded"); });
    els.mapExpand.setAttribute("aria-pressed", String(expanded));
    els.mapExpand.textContent = expanded ? "Less map" : "More map";
  });
  els.regionToggle.addEventListener("click", () => {
    state.regionVisible = !state.regionVisible;
    renderRegions();
  });
  els.settlementToggle.addEventListener("click", () => {
    state.settlementVisible = !state.settlementVisible;
    els.settlementToggle.setAttribute("aria-pressed", String(state.settlementVisible));
    els.settlementToggle.setAttribute("aria-label", state.settlementVisible ? "Hide towns and cities" : "Show towns and cities");
    renderSettlementMarkers();
  });
}

function renderRegions() {
  const available = Boolean(state.data?.fishingRegionLayer?.tileUrlTemplate);
  els.regionToggle.disabled = !available;
  els.regionToggle.setAttribute("aria-pressed", String(available && state.regionVisible));
  els.regionToggle.setAttribute("aria-label", available ? (state.regionVisible ? "Hide FishyStuff zone-assignment colours" : "Show FishyStuff zone-assignment colours (not a fishable-water mask)") : "Fishing-region colours are unavailable");
  els.regionLayer.style.display = available && state.regionVisible ? "block" : "none";
  if (els.regionOpacityControl) els.regionOpacityControl.hidden = !available || !state.regionVisible;
  updateRegionOpacity();
  updateMapOverlayVisibility();
  if (state.map.initialized) renderTiles(true);
}

function bindCapture() {
  els.cancelHaulEdit.addEventListener("click", cancelHaulEditing);
  els.haulProfileSelect.addEventListener("change", () => selectCaptureProfile(els.haulProfileSelect.value));
  els.haulSpot.addEventListener("input", onCaptureLocationInput);
  els.haulSpot.addEventListener("focus", () => renderCaptureLocationSuggestions(els.haulSpot.value, true));
  els.haulSpot.addEventListener("keydown", onCaptureLocationKeydown);
  els.haulSpot.addEventListener("blur", () => window.setTimeout(restoreLastValidCaptureLocation, 120));
  els.haulMapButton.addEventListener("click", beginCaptureMapSelection);
  els.cancelCaptureMap.addEventListener("click", cancelCaptureMapSelection);
  document.addEventListener("pointerdown", event => {
    if (!els.haulLocationCombobox.contains(event.target)) closeCaptureLocationSuggestions();
  });
  $$(".style-option").forEach(button => button.addEventListener("click", () => {
    setCaptureStyle(button.dataset.style);
  }));
  $$(".gear-option").forEach(button => button.addEventListener("click", () => {
    const container = button.closest(".gear-options");
    $$(".gear-option", container).forEach(other => {
      const active = other === button;
      other.classList.toggle("is-active", active);
      other.setAttribute("aria-pressed", String(active));
    });
    const method = container.closest("#harpoonGear") ? "harpoon" : "rod";
    state.captureEquipment[method] = button.dataset.equipment;
    markCaptureProfileCustom();
  }));
  els.haulMastery.addEventListener("input", markCaptureProfileCustom);
  $$('[data-time-mode]').forEach(button => button.addEventListener("click", () => setCaptureTimeMode(button.dataset.timeMode)));
  [els.haulHours, els.haulMinutes, els.haulExcludedHours, els.haulExcludedMinutes].forEach(input => input.addEventListener("input", updateCaptureTimeDisplays));
  els.haulStartDate.addEventListener("input", () => {
    if (els.haulStartDate.value && !els.haulEndDate.value) els.haulEndDate.value = els.haulStartDate.value;
    updateCaptureTimeDisplays();
  });
  els.haulEndDate.addEventListener("input", updateCaptureTimeDisplays);
  els.haulStartTimeButton.addEventListener("click", () => openTimePicker("start"));
  els.haulEndTimeButton.addEventListener("click", () => openTimePicker("end"));
  els.timePickerClose.addEventListener("click", () => closeTimePicker(false));
  els.timePickerCancel.addEventListener("click", () => closeTimePicker(false));
  els.timePickerDone.addEventListener("click", () => closeTimePicker(true));
  els.timePickerNow.addEventListener("click", setTimePickerNow);
  els.timePickerHour.addEventListener("click", () => selectTimePickerStage("hour"));
  els.timePickerMinute.addEventListener("click", () => selectTimePickerStage("minute"));
  els.timePickerBackdrop.addEventListener("pointerdown", event => {
    if (event.target === els.timePickerBackdrop) closeTimePicker(false);
  });
  els.timePickerBackdrop.addEventListener("keydown", event => {
    if (event.key === "Escape") { event.preventDefault(); closeTimePicker(false); }
  });
  els.timePickerDial.addEventListener("pointerdown", event => {
    if (event.button !== 0 || !state.timePicker.target) return;
    event.preventDefault();
    state.timePicker.pointerId = event.pointerId;
    els.timePickerDial.classList.add("is-dragging");
    try { els.timePickerDial.setPointerCapture(event.pointerId); } catch {}
    applyTimePickerPoint({ x: event.clientX, y: event.clientY });
  });
  els.timePickerDial.addEventListener("pointermove", event => {
    if (state.timePicker.pointerId !== event.pointerId) return;
    event.preventDefault();
    scheduleTimePickerPoint(event);
  });
  els.timePickerDial.addEventListener("pointerup", finishTimePickerPointer);
  els.timePickerDial.addEventListener("pointercancel", event => {
    if (state.timePicker.pointerId !== event.pointerId) return;
    state.timePicker.pointerId = null;
    state.timePicker.pendingPoint = null;
    if (state.timePicker.frame) window.cancelAnimationFrame(state.timePicker.frame);
    state.timePicker.frame = 0;
    els.timePickerDial.classList.remove("is-dragging");
  });
  els.timePickerDial.addEventListener("keydown", event => {
    const direction = event.key === "ArrowUp" || event.key === "ArrowRight" ? 1 : event.key === "ArrowDown" || event.key === "ArrowLeft" ? -1 : 0;
    if (direction) {
      event.preventDefault();
      if (state.timePicker.stage === "hour") state.timePicker.hour = (state.timePicker.hour + direction + 24) % 24;
      else state.timePicker.minute = (state.timePicker.minute + direction + 60) % 60;
      updateTimePickerVisual();
    } else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      if (state.timePicker.stage === "hour") selectTimePickerStage("minute");
      else closeTimePicker(true);
    }
  });
  els.tankFiles.addEventListener("change", () => setFiles([...els.tankFiles.files].filter(isScreenshotFile)));
  const capturePage = $("#page-capture");
  capturePage.addEventListener("dragenter", event => {
    if (![...(event.dataTransfer?.types || [])].includes("Files")) return;
    event.preventDefault();
    captureDragDepth += 1;
    els.dropZone.classList.add("is-over");
  });
  capturePage.addEventListener("dragover", event => {
    if (![...(event.dataTransfer?.types || [])].includes("Files")) return;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = "copy";
    els.dropZone.classList.add("is-over");
  });
  capturePage.addEventListener("dragleave", event => {
    if (![...(event.dataTransfer?.types || [])].includes("Files")) return;
    captureDragDepth = Math.max(0, captureDragDepth - 1);
    if (!captureDragDepth) els.dropZone.classList.remove("is-over");
  });
  capturePage.addEventListener("drop", event => {
    event.preventDefault();
    captureDragDepth = 0;
    els.dropZone.classList.remove("is-over");
    addScreenshotFiles([...(event.dataTransfer?.files || [])], "drop");
  });
  document.addEventListener("paste", event => {
    if (!capturePage.classList.contains("is-active")) return;
    const images = [...(event.clipboardData?.items || [])]
      .filter(item => item.kind === "file" && item.type.startsWith("image/"))
      .map(item => item.getAsFile())
      .filter(Boolean);
    if (!images.length) return;
    event.preventDefault();
    addScreenshotFiles(images, "clipboard");
  });
  els.scanButton.addEventListener("click", scanScreenshots);
  els.manualAddButton.addEventListener("click", addManualFish);
  els.saveHaulButton.addEventListener("click", saveHaul);
}

function setFiles(files) {
  state.files = files;
  els.fileList.innerHTML = files.length ? files.map((file,index) => `<span class="file-pill">${index + 1}. ${escapeHtml(file.name)} · ${(file.size/1024).toFixed(0)} KB</span>`).join("") : "<span>No screenshots selected</span>";
  els.scanButton.disabled = files.length === 0;
}

function isScreenshotFile(file) {
  if (!file) return false;
  if (String(file.type || "").startsWith("image/")) return true;
  return /\.(png|jpe?g|webp)$/i.test(String(file.name || ""));
}

function addScreenshotFiles(files, source) {
  const accepted = files.filter(isScreenshotFile);
  if (!accepted.length) {
    showToast("Drop or paste a PNG, JPG, or WebP screenshot.", true);
    return;
  }
  const identities = new Set(state.files.map(file => `${file.name}|${file.size}|${file.lastModified}|${file.type}`));
  const additions = accepted.filter(file => {
    const identity = `${file.name}|${file.size}|${file.lastModified}|${file.type}`;
    if (identities.has(identity)) return false;
    identities.add(identity);
    return true;
  });
  setFiles([...state.files, ...additions]);
  if (!additions.length) {
    showToast("That screenshot is already in this haul.");
    return;
  }
  const origin = source === "clipboard" ? "pasted" : "dropped";
  showToast(`${additions.length} screenshot${additions.length === 1 ? "" : "s"} ${origin}.`);
}

async function resolveCatchIdentities(payload) {
  const rawCatches = Array.isArray(payload.catches)
    ? payload.catches
    : Array.isArray(payload.items)
      ? payload.items
      : [];
  const hasAmbiguity = rawCatches.some(item => Array.isArray(item.candidateItems) && item.candidateItems.length > 1);
  const zone = findZoneByInput(els.haulSpot.value);
  if (!hasAmbiguity || !zone) return { catches: rawCatches, contextResolvedSlots: 0 };

  try {
    const method = state.method.capture;
    const detail = await request(`/api/zone/${Number(zone.rgb)}?method=${encodeURIComponent(method)}`);
    if (detail.available === false) return { catches: rawCatches, contextResolvedSlots: 0 };
    const rows = Array.isArray(detail.speciesRows)
      ? detail.speciesRows
      : Array.isArray(detail.items)
        ? detail.items
        : [];
    const availableIds = new Set(rows.filter(row => {
      const methods = row.catchMethods || row.methods || (row.catchMethod ? [row.catchMethod] : []);
      return !methods.length || methods.includes(method);
    }).map(row => Number(row.itemId ?? row.id)).filter(Number.isFinite));

    let contextResolvedSlots = 0;
    const catches = rawCatches.map(item => {
      const candidates = Array.isArray(item.candidateItems) ? item.candidateItems : [];
      if (candidates.length <= 1) return item;
      const possibleHere = candidates.filter(candidate => availableIds.has(Number(candidate.itemId)));
      if (possibleHere.length !== 1) return item;
      const chosen = possibleHere[0];
      const visualVerified = item.visualTemplateVerified === true && Number(item.conflictingSlotCount || 0) === 0;
      if (visualVerified) contextResolvedSlots += Number(item.count || 0);
      return {
        ...item,
        itemId: Number(chosen.itemId),
        name: chosen.name,
        grade: chosen.grade,
        price: chosen.price,
        iconUrl: chosen.iconUrl,
        identityStatus: "identified",
        resolvedItemId: Number(chosen.itemId),
        resolvedName: chosen.name,
        contextResolved: true,
        allSlotsVerified: visualVerified,
      };
    });
    return { catches, contextResolvedSlots };
  } catch {
    // Recognition remains usable offline; shared artwork simply stays marked
    // for review when its exact table cannot be loaded.
    return { catches: rawCatches, contextResolvedSlots: 0 };
  }
}

async function scanScreenshots() {
  if (!state.files.length) return;
  let captureLocation = resolveCaptureLocation();
  if (captureLocation?.type === "node" && !captureLocation.zone && captureLocation.source !== "map-click") captureLocation = await resolveNodeLocation();
  if (captureLocation?.type === "node" && !captureLocation.zone) {
    renderCaptureLocationResolution();
    showToast("Choose the node's exact fishing point on the Map before scanning.", true);
    els.haulSpot.focus();
    return;
  }
  const original = els.scanButton.innerHTML;
  els.scanButton.disabled = true;
  els.scanButton.innerHTML = `<span class="spinner" style="width:18px;height:18px;border-width:2px"></span>Recognizing locally…`;
  const form = new FormData();
  // Send only generic in-memory part names to the localhost recognizer.  The
  // user's original filename and path are never included in the request.
  state.files.forEach((file, index) => form.append("screenshots", file, `tank-frame-${index + 1}.img`));
  try {
    const result = await request("/api/recognize", { method: "POST", body: form });
    const payload = result.result || result;
    if (payload.status === "error") throw new Error(payload.message || "Recognition failed");
    const resolved = await resolveCatchIdentities(payload);
    const catches = resolved.catches;
    state.review = {
      catches: catches.map(item => {
        const itemId = Number(item.resolvedItemId ?? item.itemId);
        const catalog = state.fishById.get(itemId) || {};
        const ambiguousCandidates = Array.isArray(item.candidateItems) ? item.candidateItems : [];
        const unresolvedIdentity = item.identityStatus === "ambiguous" && item.resolvedItemId == null;
        return {
          itemId,
          name: item.name || catalog.name || String(item.itemId),
          count: Number(item.count || 0),
          price: unresolvedIdentity ? 0 : Number(item.price ?? catalog.price ?? 0),
          grade: unresolvedIdentity ? "" : item.grade || catalog.grade || "",
          verified: item.allSlotsVerified === true,
          ambiguousCandidates,
          contextResolved: item.contextResolved === true,
          source: "recognizer",
        };
      }).filter(item => item.count > 0),
      tank: payload.tank || {},
      scan: payload.scan || {},
      review: payload.review || {},
      recognizerVersion: payload.recognizerVersion || "",
      contextResolvedSlots: resolved.contextResolvedSlots,
      manuallyEdited: false,
    };
    renderReview();
    showToast(`Recognized ${number(totalReviewFish())} retained fish.`);
  } catch (error) {
    showToast(error.message, true);
  } finally {
    els.scanButton.disabled = false;
    els.scanButton.innerHTML = original;
  }
}

function totalReviewFish() {
  return state.review?.catches.reduce((sum,item) => sum + Number(item.count || 0), 0) || 0;
}

function totalReviewValue() {
  return state.review?.catches.reduce((sum,item) => sum + Number(item.count || 0) * Number(item.price || 0), 0) || 0;
}

function reviewState() {
  if (!state.review) return { label: "Not scanned", unresolved: 0, verified: false };
  const recognizerUncertain = Math.max(
    0,
    Number(state.review.review?.uncertainCatchSlots || 0) - Number(state.review.contextResolvedSlots || 0),
  );
  const conflicting = Number(state.review.scan?.conflictingSlotObservations || 0);
  const catchUncertain = state.review.catches.reduce(
    (sum, item) => sum + (item.verified ? 0 : Number(item.count || 0)),
    0,
  );
  const unresolved = Math.max(recognizerUncertain, conflicting, catchUncertain);
  const verified = !state.review.manuallyEdited && unresolved === 0 && state.review.catches.length > 0;
  if (unresolved > 0) return { label: `${number(unresolved)} to check`, unresolved, verified: false };
  if (state.review.manuallyEdited) return { label: "Reviewed", unresolved: 0, verified: false };
  return { label: verified ? "Verified" : "Reviewed", unresolved: 0, verified };
}

function renderReview() {
  if (!state.review) {
    els.reviewEmpty.classList.remove("is-hidden");
    els.reviewContent.classList.add("is-hidden");
    return;
  }
  els.reviewEmpty.classList.add("is-hidden");
  els.reviewContent.classList.remove("is-hidden");
  els.reviewCount.textContent = number(totalReviewFish());
  els.reviewValue.textContent = silver(totalReviewValue());
  els.reviewValue.title = `${number(totalReviewValue())} silver`;
  const coverage = state.review.scan?.completeTankCoverage;
  const unique = state.review.scan?.uniqueSlotsObserved;
  els.reviewCoverage.textContent = coverage === true ? "Complete" : Number.isFinite(Number(unique)) ? `${number(unique)}/100` : "Reviewed";
  const currentReview = reviewState();
  els.reviewConfidence.textContent = currentReview.label;
  els.recognizedFish.innerHTML = state.review.catches.length ? state.review.catches.map((item,index) => `<div class="recognized-row" data-index="${index}">
    <span class="recognized-icon grade-frame ${itemGradeClass(item.grade)}" title="${escapeHtml(item.name)}${item.price ? ` · ${silver(item.price)} each` : ""}"><img src="/icon/${item.itemId}.webp" alt=""></span>
    <div><strong title="${escapeHtml(item.name)}">${escapeHtml(item.name)}</strong></div>
    <div class="count-control"><button type="button" data-delta="-1" aria-label="Decrease">−</button><span>${number(item.count)}</span><button type="button" data-delta="1" aria-label="Increase">+</button></div>
    <button type="button" class="remove-fish" aria-label="Remove fish">×</button>
  </div>`).join("") : `<div class="empty-state compact"><strong>No retained fish</strong><p>Add a fish manually if the tank was not recognized correctly.</p></div>`;
  $$(".recognized-row", els.recognizedFish).forEach(row => {
    const index = Number(row.dataset.index);
    $$('[data-delta]', row).forEach(button => button.addEventListener("click", () => {
      state.review.manuallyEdited = true;
      state.review.catches[index].count = Math.max(0, state.review.catches[index].count + Number(button.dataset.delta));
      if (state.review.catches[index].count === 0) state.review.catches.splice(index,1);
      renderReview();
    }));
    $(".remove-fish", row).addEventListener("click", () => { state.review.manuallyEdited = true; state.review.catches.splice(index,1); renderReview(); });
  });
}

function addManualFish() {
  const name = els.manualFish.value.trim();
  const fish = state.fish.find(item => item.name.toLowerCase() === name.toLowerCase());
  if (!fish) { showToast("Choose a fish from the list.", true); return; }
  if (!state.review) state.review = { catches: [], tank: {}, scan: {}, review: {}, manuallyEdited: true };
  state.review.manuallyEdited = true;
  const existing = state.review.catches.find(item => item.itemId === fish.itemId);
  if (existing) existing.count += 1;
  else state.review.catches.push({ itemId: fish.itemId, name: fish.name, count: 1, price: fish.price, grade: fish.grade || "", verified: true, source: "manual" });
  els.manualFish.value = "";
  renderReview();
}

function locationSuggestionScore(label, meta, query) {
  const normalized = String(query || "").trim().toLowerCase();
  if (!normalized) return 0;
  const text = String(label || "").toLowerCase();
  const details = String(meta || "").toLowerCase();
  const tokens = normalized.split(/\s+/).filter(Boolean);
  if (!tokens.every(token => text.includes(token) || details.includes(token))) return null;
  if (text === normalized) return 0;
  if (text.startsWith(normalized)) return 1;
  if (text.split(/[^a-z0-9]+/).some(word => word.startsWith(normalized))) return 2;
  if (text.includes(normalized)) return 3;
  return 4;
}

function captureLocationSuggestionGroups(query = "") {
  const nodes = state.nodes.map(node => {
    const label = node.duplicateName ? (node.displayName || node.name) : node.name;
    const meta = `${node.kind || "Node"} · Map node`;
    return { type: "node", label, meta, value: node, score: locationSuggestionScore(label, meta, query) };
  }).filter(item => item.score != null).sort((a,b) => a.score - b.score || a.label.localeCompare(b.label));
  const zones = state.zones.filter(zone => zone.active && zone.name && zone.zoneRole !== "out-of-bounds").map(zone => {
    const meta = `Fishing spot · ${depthLabel(zone.depth)}`;
    return { type: "zone", label: zone.name, meta, value: zone, score: locationSuggestionScore(zone.name, meta, query) };
  }).filter(item => item.score != null).sort((a,b) => a.score - b.score || a.label.localeCompare(b.label));
  return { nodes, zones };
}

function locationSuggestionIcon(type) {
  return type === "node"
    ? `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a7 7 0 0 1 7 7c0 5.2-7 13-7 13S5 14.2 5 9a7 7 0 0 1 7-7Zm0 4a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z"/></svg>`
    : `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m3 5 6-3 6 3 6-3v17l-6 3-6-3-6 3V5Zm7-.5v12.8l4 2V6.5l-4-2Zm6 2v12.8l3-1.5V5l-3 1.5ZM5 6.2v12.6l3-1.5V4.7L5 6.2Z"/></svg>`;
}

function renderCaptureLocationSuggestions(query = els.haulSpot.value, forceOpen = false) {
  const groups = captureLocationSuggestionGroups(query);
  state.captureSuggestions = [...groups.nodes, ...groups.zones];
  state.captureSuggestionIndex = -1;
  const sections = [];
  let index = 0;
  for (const [heading, items] of [["Nodes", groups.nodes], ["Fishing spots", groups.zones]]) {
    if (!items.length) continue;
    sections.push(`<div class="location-suggestion-group">${heading}</div>`);
    sections.push(items.map(item => {
      const optionIndex = index++;
      return `<button id="haul-location-option-${optionIndex}" type="button" class="location-suggestion" role="option" aria-selected="false" data-suggestion-index="${optionIndex}" data-type="${item.type}"><span class="location-suggestion-icon">${locationSuggestionIcon(item.type)}</span><span class="location-suggestion-copy"><strong>${escapeHtml(item.label)}</strong><small>${escapeHtml(item.meta)}</small></span></button>`;
    }).join(""));
  }
  els.haulLocationSuggestions.innerHTML = sections.join("");
  const shouldOpen = forceOpen && state.captureSuggestions.length > 0;
  els.haulLocationSuggestions.classList.toggle("is-hidden", !shouldOpen);
  els.haulSpot.setAttribute("aria-expanded", String(shouldOpen));
  els.haulSpot.removeAttribute("aria-activedescendant");
  $$(".location-suggestion", els.haulLocationSuggestions).forEach(option => {
    option.addEventListener("pointerdown", event => {
      event.preventDefault();
      selectCaptureLocationSuggestion(Number(option.dataset.suggestionIndex));
    });
    option.addEventListener("pointerenter", () => setActiveCaptureLocationSuggestion(Number(option.dataset.suggestionIndex)));
  });
}

function closeCaptureLocationSuggestions() {
  state.captureSuggestionIndex = -1;
  els.haulLocationSuggestions.classList.add("is-hidden");
  els.haulSpot.setAttribute("aria-expanded", "false");
  els.haulSpot.removeAttribute("aria-activedescendant");
}

function setActiveCaptureLocationSuggestion(index) {
  const count = state.captureSuggestions.length;
  if (!count) return;
  const normalized = ((index % count) + count) % count;
  state.captureSuggestionIndex = normalized;
  $$(".location-suggestion", els.haulLocationSuggestions).forEach((option, optionIndex) => {
    const active = optionIndex === normalized;
    option.classList.toggle("is-active", active);
    option.setAttribute("aria-selected", String(active));
    if (active) {
      els.haulSpot.setAttribute("aria-activedescendant", option.id);
      option.scrollIntoView({ block: "nearest" });
    }
  });
}

function commitCaptureLocation(location) {
  state.captureLocation = location || null;
  if (location && !location.resolving) state.captureLastValidLocation = location;
  renderCaptureLocationResolution();
  return state.captureLocation;
}

function selectCaptureLocationSuggestion(index) {
  const suggestion = state.captureSuggestions[index];
  if (!suggestion) return;
  els.haulSpot.value = suggestion.label;
  closeCaptureLocationSuggestions();
  if (suggestion.type === "zone") {
    const zone = suggestion.value;
    commitCaptureLocation({ type: "zone", inputKey: captureInputKey(suggestion.label), inputValue: suggestion.label, locationName: zone.name, node: null, zone, requiresExactClick: false, source: "fishing-region" });
    return;
  }
  const node = suggestion.value;
  state.captureLocation = { type: "node", inputKey: captureInputKey(suggestion.label), inputValue: suggestion.label, locationName: node.name, node, zone: null, requiresExactClick: false, resolving: true, source: "node-resolver" };
  renderCaptureLocationResolution();
  resolveNodeLocation(suggestion.label);
}

function onCaptureLocationKeydown(event) {
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    if (els.haulLocationSuggestions.classList.contains("is-hidden")) renderCaptureLocationSuggestions(els.haulSpot.value, true);
    const delta = event.key === "ArrowDown" ? 1 : -1;
    const start = state.captureSuggestionIndex < 0 ? (delta > 0 ? 0 : state.captureSuggestions.length - 1) : state.captureSuggestionIndex + delta;
    setActiveCaptureLocationSuggestion(start);
    return;
  }
  if (event.key === "Enter") {
    const exactIndex = state.captureSuggestions.findIndex(item => item.label.toLowerCase() === els.haulSpot.value.trim().toLowerCase());
    const choice = state.captureSuggestionIndex >= 0 ? state.captureSuggestionIndex : exactIndex;
    if (choice >= 0) {
      event.preventDefault();
      selectCaptureLocationSuggestion(choice);
    }
    return;
  }
  if (event.key === "Escape") {
    event.preventDefault();
    closeCaptureLocationSuggestions();
  }
}

function restoreLastValidCaptureLocation() {
  closeCaptureLocationSuggestions();
  if (state.pendingMapLocation) return;
  const value = els.haulSpot.value.trim();
  if (!value) {
    state.captureLocation = null;
    state.captureLastValidLocation = null;
    renderCaptureLocationResolution();
    return;
  }
  if (state.captureLocation?.inputKey === captureInputKey(value) || findNodeByInput(value) || directZoneByInput(value)) return;
  const last = state.captureLastValidLocation;
  if (last) {
    els.haulSpot.value = last.inputValue || last.locationName || last.zone?.name || "";
    state.captureLocation = last;
  } else {
    els.haulSpot.value = "";
    state.captureLocation = null;
  }
  renderCaptureLocationResolution();
}

function findNodeByInput(name) {
  const normalized = String(name || "").trim().toLowerCase();
  return state.nodes.find(node => node.displayName.toLowerCase() === normalized || node.name.toLowerCase() === normalized) || null;
}

function directZoneByInput(name) {
  const normalized = String(name || "").trim().toLowerCase();
  return state.zones.find(candidate => candidate.name.toLowerCase() === normalized) || null;
}

function zoneFromLocationData(rawRgb, rawName) {
  if (rawRgb == null || rawRgb === "") return null;
  const rgb = normalizeRgb(rawRgb);
  if (!Number.isFinite(rgb)) return null;
  const matchedZone = state.zoneByRgb.get(rgb) || null;
  const zoneName = String(rawName || matchedZone?.name || "").trim();
  if (!zoneName) return null;
  return {
    ...(matchedZone || {}),
    rgb,
    name: zoneName,
    depth: matchedZone?.depth || depthKey({ name: zoneName }),
  };
}

function captureInputKey(value = els.haulSpot?.value) {
  return String(value || "").trim().toLowerCase();
}

function resolveCaptureLocation(name = els.haulSpot?.value) {
  const inputKey = captureInputKey(name);
  if (!inputKey) return null;
  if (state.captureLocation?.inputKey === inputKey) return state.captureLocation;
  const zone = directZoneByInput(name);
  if (zone) return { type: "zone", inputKey, inputValue: String(name || "").trim(), locationName: zone.name, node: null, zone, requiresExactClick: false, source: "fishing-region" };
  const node = findNodeByInput(name);
  return node ? { type: "node", inputKey, inputValue: String(name || "").trim(), locationName: node.name, node, zone: null, requiresExactClick: false, resolving: true } : null;
}

function resolutionAnchor(result, fallbackNode) {
  const candidates = [result?.location, ...(Array.isArray(result?.matches) ? result.matches : []), fallbackNode].filter(Boolean);
  const points = candidates.map(item => ({
    x: Number(item.x ?? item.pixel?.x),
    y: Number(item.y ?? item.pixel?.y),
  })).filter(point => Number.isFinite(point.x) && Number.isFinite(point.y));
  if (!points.length) return null;
  return {
    x: points.reduce((sum, point) => sum + point.x, 0) / points.length,
    y: points.reduce((sum, point) => sum + point.y, 0) / points.length,
  };
}

async function resolveNodeLocation(name = els.haulSpot.value) {
  const inputValue = String(name || "").trim();
  const inputKey = captureInputKey(inputValue);
  const node = findNodeByInput(inputValue);
  if (!node) return resolveCaptureLocation(inputValue);
  if (state.captureLocation?.inputKey === inputKey && (state.captureLocation.source === "map-click" || state.captureLocation.zone)) return state.captureLocation;
  const requestId = ++state.locationResolveRequestId;
  try {
    const result = await request(`/api/location-resolve?q=${encodeURIComponent(inputValue)}`);
    if (requestId !== state.locationResolveRequestId || captureInputKey() !== inputKey) return null;
    const location = result.location || (Array.isArray(result.matches) && result.matches.length === 1 ? result.matches[0] : null) || node;
    const aggregation = result.aggregation || {};
    const ambiguousZones = result.ambiguousZones || aggregation.ambiguousZones || result.candidateZones || aggregation.candidateZones || [];
    const requiresExactClick = result.requiresExactClick === true
      || aggregation.requiresExactClick === true
      || location.requiresExactClick === true
      || location.zoneBoundaryAmbiguous === true
      || result.ambiguous === true
      || aggregation.ambiguous === true
      || location.ambiguous === true
      || ambiguousZones.length > 1
      || (result.status && result.status !== "resolved");
    const zone = requiresExactClick ? null : zoneFromLocationData(
      aggregation.zoneRgb ?? location.zoneRgb,
      aggregation.zoneName ?? location.zoneName,
    );
    commitCaptureLocation({
      type: "node",
      inputKey,
      inputValue,
      locationName: String(aggregation.displayLocationName || location.name || node.name || inputValue),
      node: { ...node, ...location },
      zone,
      requiresExactClick: requiresExactClick || !zone,
      anchor: resolutionAnchor(result, node),
      candidateZones: ambiguousZones,
      source: zone ? "node-resolver" : "exact-click-required",
    });
  } catch {
    if (requestId !== state.locationResolveRequestId || captureInputKey() !== inputKey) return null;
    commitCaptureLocation({
      type: "node",
      inputKey,
      inputValue,
      locationName: node.name,
      node,
      zone: null,
      requiresExactClick: true,
      anchor: resolutionAnchor(null, node),
      source: "exact-click-required",
    });
  }
  return state.captureLocation;
}

function onCaptureLocationInput() {
  window.clearTimeout(locationResolveTimer);
  state.locationResolveRequestId += 1;
  const inputValue = els.haulSpot.value;
  const inputKey = captureInputKey(inputValue);
  if (!inputKey) {
    state.captureLocation = null;
    state.captureLastValidLocation = null;
    renderCaptureLocationResolution();
    renderCaptureLocationSuggestions(inputValue, true);
    return;
  }
  if (state.captureLocation?.inputKey !== inputKey) state.captureLocation = null;
  const zone = directZoneByInput(inputValue);
  const node = findNodeByInput(inputValue);
  if (zone) commitCaptureLocation({ type: "zone", inputKey, inputValue, locationName: zone.name, node: null, zone, requiresExactClick: false, source: "fishing-region" });
  else if (node) {
    state.captureLocation = { type: "node", inputKey, inputValue, locationName: node.name, node, zone: null, requiresExactClick: false, resolving: true, source: "node-resolver" };
  }
  renderCaptureLocationResolution();
  renderCaptureLocationSuggestions(inputValue, true);
  if (node) locationResolveTimer = window.setTimeout(() => resolveNodeLocation(inputValue), 160);
}

function renderCaptureLocationResolution() {
  if (!els.haulLocationMessage) return;
  const location = resolveCaptureLocation();
  els.haulLocationMessage.classList.add("is-hidden");
  els.haulLocationMessage.classList.remove("needs-map", "is-pending");
  els.haulLocationMessage.textContent = "";
  if (!location) return;
  els.haulLocationMessage.classList.remove("is-hidden");
  if (location.resolving) {
    els.haulLocationMessage.classList.add("is-pending");
    els.haulLocationMessage.innerHTML = `<span class="location-resolution-copy"><strong>Node · ${escapeHtml(location.locationName || location.inputValue)}</strong><small>Checking its fishing table…</small></span>`;
    return;
  }
  if (location.type === "node") {
    const nodeName = location.locationName || location.node?.name || location.inputValue;
    if (location.zone) {
      els.haulLocationMessage.innerHTML = `<span class="location-resolution-copy"><strong>Node · ${escapeHtml(nodeName)}</strong><small>Fishing table · ${escapeHtml(location.zone.name)}</small></span>`;
      return;
    }
    els.haulLocationMessage.classList.add("needs-map");
    els.haulLocationMessage.innerHTML = `<span class="location-resolution-copy"><strong>Node · ${escapeHtml(nodeName)}</strong><small>Choose the exact water point to identify its table</small></span><button type="button" class="location-map-action">Choose on map</button>`;
    const action = $(".location-map-action", els.haulLocationMessage);
    if (action) action.addEventListener("click", () => chooseCapturePointOnMap(location));
    return;
  }
  const primary = location.type === "map"
    ? `Map · ${escapeHtml(location.locationName || location.inputValue || "Point selected")}`
    : "Fishing spot selected";
  els.haulLocationMessage.innerHTML = `<span class="location-resolution-copy"><strong>${primary}</strong><small>Fishing table · ${escapeHtml(location.zone?.name || location.locationName)}</small></span>`;
}

async function beginCaptureMapSelection() {
  closeCaptureLocationSuggestions();
  let location = resolveCaptureLocation();
  if (location?.type === "node" && location.resolving) location = await resolveNodeLocation(location.inputValue);
  if (location?.type === "node") {
    chooseCapturePointOnMap(location);
    return;
  }
  chooseCapturePointOnMap(null, location?.point || location?.zone?.center || null);
}

function chooseCapturePointOnMap(location = null, anchorOverride = null) {
  const nodeLocation = location?.type === "node" ? location : null;
  const anchor = anchorOverride || nodeLocation?.point || nodeLocation?.anchor || resolutionAnchor(null, nodeLocation?.node);
  state.pendingMapLocation = {
    scope: "capture",
    inputKey: nodeLocation?.inputKey || "",
    inputValue: nodeLocation?.inputValue || "",
    locationName: nodeLocation?.locationName || "",
    node: nodeLocation?.node || null,
    anchor,
  };
  state.selectedZone = null;
  state.selectedPoint = null;
  renderSpotPoints(state.filteredZones);
  state.spotRequestId += 1;
  renderEmptySpotDrawer();
  updateMapResultSelection();
  els.captureMapPromptText.textContent = nodeLocation?.locationName ? `Choose water near ${nodeLocation.locationName}` : "Choose the exact fishing point";
  els.captureMapPrompt.classList.remove("is-hidden");
  navigate("map");
  setSpotDrawerOpen(false);
  window.requestAnimationFrame(() => {
    if (!state.map.initialized) homeMap();
    if (anchor && Number.isFinite(anchor.x) && Number.isFinite(anchor.y)) {
      const frame = measureMapVisibleFrame();
      state.map.scale = Math.max(state.map.scale, .72);
      state.map.offsetX = frame.centerX - anchor.x * state.map.scale;
      state.map.offsetY = frame.centerY - anchor.y * state.map.scale;
      clampMap();
      applyMapTransform();
      renderTiles(true);
      showPin(anchor.x, anchor.y);
    } else {
      els.mapPin.classList.add("is-hidden");
    }
    showToast(nodeLocation ? "Click the exact water where you fished." : "Click the exact fishing point on the map.");
  });
}

function cancelCaptureMapSelection() {
  const scope = state.pendingMapLocation?.scope || "capture";
  state.pendingMapLocation = null;
  els.captureMapPrompt.classList.add("is-hidden");
  navigate(scope === "stats" ? "stats" : "capture");
  if (scope === "stats") renderStatsLocationSelection();
  else renderCaptureLocationResolution();
}

function findZoneByInput(name) {
  return resolveCaptureLocation(name)?.zone || null;
}

async function saveHaul() {
  let location = resolveCaptureLocation();
  if (location?.type === "node" && !location.zone && location.source !== "map-click") location = await resolveNodeLocation();
  const zone = location?.zone || null;
  const method = state.method.capture;
  const masteryText = els.haulMastery.value.trim();
  const mastery = masteryText === "" ? Number.NaN : Number(masteryText);
  if (!location) { showToast("Choose a suggested node, fishing spot, or map point.", true); els.haulSpot.focus(); return; }
  if (!zone && location.type === "node") { renderCaptureLocationResolution(); showToast("Choose the node's exact fishing point on the Map before saving.", true); els.haulSpot.focus(); return; }
  if (!zone) { showToast("Choose a fishing spot or an exact point on the map.", true); els.haulSpot.focus(); return; }
  if (!Number.isFinite(mastery) || mastery < 0) { showToast("Enter the fishing mastery used for this haul.", true); els.haulMastery.focus(); return; }
  const autoFishingReductionPercent = method === "rod" ? Math.max(0, Math.min(66.67, Number(state.captureAutoFishingReductionPercent) || 0)) : null;
  const autoFishingDelay = method === "rod" && els.haulStyle.value === "afk" ? autoFishingDelaySeconds(autoFishingReductionPercent) : null;
  const resourceLevel = method === "rod" ? (els.haulResourceLevel.value || null) : null;
  if (!state.review || totalReviewFish() <= 0) { showToast("Review at least one recognized fish before saving.", true); return; }
  const timeDetails = captureTimeDetails();
  if (timeDetails.error) { showToast(timeDetails.error, true); timeDetails.focus?.focus(); return; }
  const editingSession = state.editingSessionId
    ? state.sessions.find(session => String(session.id) === String(state.editingSessionId)) || null
    : null;
  const soldAmountText = editingSession ? els.haulSoldAmount.value.trim() : "";
  const soldAmount = soldAmountText ? Number(soldAmountText) : null;
  if (soldAmountText && (!Number.isFinite(soldAmount) || soldAmount <= 0 || soldAmount > 100_000_000_000_000)) {
    showToast("Enter the actual silver received, or leave it blank if this haul was not sold.", true);
    els.haulSoldAmount.focus();
    return;
  }
  const selectedProfile = state.fishingProfiles.find(profile => profile.id === state.captureProfileId) || null;
  const preserveProfileSnapshot = Boolean(editingSession && !state.editingProfileDetached);
  const valuationProfile = selectedProfile || editingSession || (activeProfile()?.method === method ? activeProfile() : null);
  const currentReview = reviewState();
  const pointX = Number(location?.point?.x);
  const pointY = Number(location?.point?.y);
  const exactMapPoint = Number.isFinite(pointX) && Number.isFinite(pointY)
    ? { x: Math.round(pointX), y: Math.round(pointY) }
    : null;
  const preservedProfileId = editingSession?.profileId || editingSession?.profile_id || editingSession?.setupId || editingSession?.setup_id || null;
  const preservedProfileName = editingSession?.profileName || editingSession?.profile_name || editingSession?.setupName || editingSession?.setup_name || null;
  const preserveRecognition = Boolean(editingSession && !state.review.manuallyEdited);
  const payload = {
    ...(timeDetails.caughtAt
      ? { caughtAt: timeDetails.caughtAt }
      : editingSession?.caughtAt || editingSession?.caught_at
        ? { caughtAt: editingSession.caughtAt || editingSession.caught_at }
        : {}),
    method,
    zoneRgb: zone.rgb,
    zoneName: zone.name,
    locationName: location.locationName || zone.name,
    ...(exactMapPoint ? { point: exactMapPoint } : {}),
    depth: zone.depth,
    style: els.haulStyle.value,
    mastery,
    equipment: state.captureEquipment[method],
    profileId: selectedProfile?.id || (preserveProfileSnapshot ? preservedProfileId : null),
    profileName: selectedProfile?.name || (preserveProfileSnapshot ? preservedProfileName : null),
    fishingRank: valuationProfile?.fishingRank || null,
    fishingLevel: valuationProfile?.fishingLevel || null,
    resourceLevel,
    autoFishingReductionPercent,
    autoFishingDelaySeconds: autoFishingDelay,
    tradingRank: valuationProfile?.tradingRank || null,
    tradingLevel: valuationProfile?.tradingLevel || null,
    keepFrom: els.haulKeep.value,
    durationMinutes: timeDetails.durationMinutes,
    excludedMinutes: timeDetails.excludedMinutes,
    startedAt: timeDetails.startedAt,
    endedAt: timeDetails.endedAt,
    catches: state.review.catches.map(item => ({ itemId: item.itemId, name: item.name, count: Number(item.count), price: Number(item.price || 0), grade: item.grade || "" })),
    recognition: {
      recognizerVersion: state.review.recognizerVersion,
      completeTankCoverage: state.review.scan?.completeTankCoverage ?? null,
      uncertainCatchSlots: currentReview.unresolved,
      conflictingSlotObservations: Number(state.review.scan?.conflictingSlotObservations || 0),
      contextResolvedSlots: Number(state.review.contextResolvedSlots || 0),
      manuallyEdited: Boolean(state.review.manuallyEdited),
      frameCount: Number(state.review.scan?.frames?.length || state.files.length || 0),
    },
    source: preserveRecognition ? (state.review.originalSource || editingSession.source || "manual") : currentReview.verified ? "recognizer" : "recognizer-reviewed",
    verificationStatus: preserveRecognition ? (state.review.originalVerificationStatus || editingSession.verificationStatus || editingSession.verification_status || "reviewed") : currentReview.verified ? "verified" : "reviewed",
  };
  els.saveHaulButton.disabled = true;
  els.saveHaulLabel.textContent = "Saving…";
  try {
    const wasEditing = Boolean(editingSession);
    const endpoint = wasEditing ? `/api/sessions/${encodeURIComponent(editingSession.id)}` : "/api/sessions";
    await request(endpoint, { method: wasEditing ? "PUT" : "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload) });
    if (wasEditing) {
      const originalSaleAmount = String(els.haulSoldAmount.dataset.original || "").trim();
      if (soldAmountText !== originalSaleAmount) {
        if (!soldAmountText && originalSaleAmount) {
          await request(`/api/sessions/${encodeURIComponent(editingSession.id)}/sale`, { method: "DELETE" });
        } else if (soldAmountText) {
          const existingSale = sessionSale(editingSession);
          await request(`/api/sessions/${encodeURIComponent(editingSession.id)}/sale`, {
            method: "PUT",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              soldAt: existingSale?.soldAt || new Date().toISOString(),
              destination: existingSale?.destination || "Not recorded",
              currentTankValue: Math.max(0, Math.round(payload.catches.reduce((sum, item) => sum + Number(item.count || 0) * Number(item.price || 0), 0))),
              marketPercent: existingSale?.marketPercent ?? 100,
              distanceBonusPercent: existingSale?.distanceBonusPercent ?? 0,
              bargainBonusPercent: existingSale?.bargainBonusPercent ?? sessionBargainBonus(payload),
              finalAmount: Math.round(soldAmount),
            }),
          });
        }
      }
    }
    state.editingSessionId = "";
    state.editingProfileDetached = false;
    clearCaptureReview();
    updateHaulEditPresentation();
    showToast(wasEditing ? "Haul updated." : "Haul saved to your private journal.");
    navigate("journal");
  } catch (error) {
    showToast(error.message, true);
  } finally {
    els.saveHaulButton.disabled = false;
    updateHaulEditPresentation();
  }
}

async function loadSessions() {
  const result = await request("/api/sessions");
  state.sessions = Array.isArray(result) ? result : Array.isArray(result.sessions) ? result.sessions : [];
  return state.sessions;
}

async function loadJournal() {
  await loadSessions();
  renderJournal();
}

function sessionCatches(session) {
  const catches = Array.isArray(session.catches) ? session.catches : Array.isArray(session.items) ? session.items : Array.isArray(session.fish) ? session.fish : [];
  return catches.map(item => {
    const catalog = state.fishById.get(Number(item.itemId)) || {};
    return { ...item, itemId: Number(item.itemId), name: item.name || catalog.name || String(item.itemId), count: Number(item.count || 0), price: Number(item.price ?? item.unitPrice ?? catalog.price ?? 0), grade: item.grade || catalog.grade || "" };
  });
}

function isLegacyAggregateSession(session) {
  return session?.legacyAggregateOnly === true
    || Number(session?.legacy_aggregate_only) === 1
    || String(session?.verificationStatus || session?.verification_status || "").toLowerCase() === "legacy-aggregate-only"
    || String(session?.source || "").toLowerCase() === "legacy-v017";
}

function legacyReceivedSilver(session) {
  if (!isLegacyAggregateSession(session)) return null;
  const raw = session?.legacyReceivedSilver ?? session?.legacy_received_silver;
  if (raw == null || raw === "") return null;
  const value = Number(raw);
  return Number.isSafeInteger(value) && value >= 0 ? value : null;
}

function sessionTotal(session) {
  const catchTotal = sessionCatches(session).reduce((sum,item) => sum + item.count,0);
  if (catchTotal > 0 || !isLegacyAggregateSession(session)) return catchTotal;
  const aggregate = Number(session?.totalFish ?? session?.total_fish);
  return Number.isSafeInteger(aggregate) && aggregate >= 0 ? aggregate : 0;
}

function sessionValue(session) {
  return sessionCatches(session).reduce((sum,item) => sum + item.count * item.price,0);
}

function sessionBargainBonus(session) {
  return bargainBonusFromTradingLevel(
    session.tradingRank ?? session.trading_rank,
    session.tradingLevel ?? session.trading_level,
  );
}

function sessionSale(session) {
  return session?.sale && typeof session.sale === "object" ? session.sale : null;
}

function saleProjection(tankValue, marketPercent, distanceBonusPercent, bargainBonusPercent) {
  const tank = Math.max(0, Number(tankValue) || 0);
  const market = Math.max(30, Math.min(130, Number(marketPercent) || 100));
  const distance = Math.max(0, Math.min(150, Number(distanceBonusPercent) || 0));
  const bargain = Math.max(0, Number(bargainBonusPercent) || 0);
  return Math.round(tank * (market / 100) * (1 + distance / 100) * (1 + bargain / 100));
}

function saleItemKey(item) {
  return String(item?.itemId ?? item?.item_id ?? item?.id ?? item?.name ?? "");
}

function saleItemBaseValue(item) {
  return Math.max(0, Number(item?.count) || 0) * Math.max(0, Number(item?.price) || 0);
}

function saleQuoteFor(offer, item) {
  const value = Number(offer?.quotes?.[saleItemKey(item)]);
  return Number.isFinite(value) ? Math.max(30, Math.min(130, value)) : 100;
}

function saleOfferTotal(session, offer, bargainBonus = sessionBargainBonus(session)) {
  return sessionCatches(session).reduce((sum, item) => (
    sum + saleProjection(saleItemBaseValue(item), saleQuoteFor(offer, item), offer?.distance, bargainBonus)
  ), 0);
}

function saleOfferEffectiveQuote(session, offer) {
  const items = sessionCatches(session);
  const baseValue = items.reduce((sum, item) => sum + saleItemBaseValue(item), 0);
  if (baseValue <= 0) return 100;
  const quotedValue = items.reduce((sum, item) => sum + saleItemBaseValue(item) * saleQuoteFor(offer, item) / 100, 0);
  return Math.round(quotedValue / baseValue * 1000) / 10;
}

function nodeWorld(node) {
  const world = node?.world || {};
  const x = finiteNumberOrNull(world.x ?? node?.worldX ?? node?.world_x);
  const z = finiteNumberOrNull(world.z ?? node?.worldZ ?? node?.world_z);
  return x != null && z != null ? { x, z } : null;
}

function pointToWorld(point) {
  const transform = state.map.worldTransform;
  const x = finiteNumberOrNull(point?.x);
  const y = finiteNumberOrNull(point?.y);
  if (!transform || x == null || y == null) return null;
  return {
    x: (transform.left + x * transform.sectorPerPixel) * transform.positionFactor,
    z: (transform.top - y * transform.sectorPerPixel) * transform.positionFactor,
  };
}

function sessionOriginWorld(session) {
  const point = {
    x: session?.point?.x ?? session?.pointX ?? session?.point_x,
    y: session?.point?.y ?? session?.pointY ?? session?.point_y,
  };
  const exact = pointToWorld(point);
  if (exact) return { ...exact, exact: true };
  const wanted = normalizeSearchText(session?.locationName || session?.location_name || "");
  if (!wanted) return null;
  const node = state.nodes.find(entry => {
    const name = normalizeSearchText(entry.name || "");
    const label = normalizeSearchText(entry.label || "");
    return name === wanted || label === wanted || name.includes(wanted) || wanted.includes(name);
  });
  const world = nodeWorld(node);
  return world ? { ...world, exact: false } : null;
}

function tradeDestinations() {
  return TRADE_WAYPOINT_IDS.map(id => state.nodes.find(node => Number(node.waypointId ?? node.waypoint_id) === id))
    .filter(Boolean)
    .filter(node => nodeWorld(node))
    .map(node => ({ id: Number(node.waypointId ?? node.waypoint_id), name: node.name || node.displayName || `Trade manager ${node.waypointId}`, world: nodeWorld(node) }));
}

function distanceBonusBetween(origin, destination) {
  if (!origin || !destination?.world) return 0;
  const distance = Math.hypot(destination.world.x - origin.x, destination.world.z - origin.z);
  return Math.round(Math.min(150, distance / WORLD_UNITS_PER_DISTANCE_PERCENT) * 10) / 10;
}

function localDateTimeInput(value = new Date()) {
  const parts = localDateTimeParts(value);
  return parts.date && parts.time ? `${parts.date}T${parts.time}` : "";
}

function offerDestinationOptions(selectedName) {
  return tradeDestinations().map(destination => `<option value="${escapeHtml(destination.name)}"${destination.name === selectedName ? " selected" : ""}>${escapeHtml(destination.name)}</option>`).join("");
}

function openSalePlanner(id) {
  const session = state.sessions.find(entry => String(entry.id) === String(id));
  if (!session) return;
  if (isLegacyAggregateSession(session)) {
    showToast("Imported v0.1.7 aggregate hauls cannot be recalculated or sold again.", true);
    return;
  }
  const existing = sessionSale(session);
  const items = sessionCatches(session);
  const origin = sessionOriginWorld(session);
  const ranked = tradeDestinations().map(destination => ({ ...destination, distance: distanceBonusBetween(origin, destination) })).sort((a,b) => b.distance - a.distance);
  const defaults = ranked.slice(0, 3);
  if (!defaults.length) {
    showToast("Selling-destination map data is unavailable.", true);
    return;
  }
  if (existing) {
    const savedDestination = ranked.find(destination => destination.name === existing.destination) || defaults[0];
    defaults[0] = { ...savedDestination, distance: Number(existing.distanceBonusPercent) || 0 };
  }
  state.salePlanner = {
    sessionId: String(session.id),
    selected: 0,
    offers: defaults.map((destination, index) => ({
      destination: destination.name,
      distance: existing && index === 0 ? Number(existing.distanceBonusPercent) || 0 : destination.distance,
      quotes: Object.fromEntries(items.map(item => [saleItemKey(item), existing && index === 0 ? Number(existing.marketPercent) || 100 : 100])),
    })),
  };
  const locationName = session.locationName || session.location_name || session.zoneName || session.zone_name || "Fishing location";
  els.saleTitle.textContent = existing ? `Recorded sale · ${locationName}` : `Sell ${locationName} haul`;
  els.saleOrigin.textContent = `${locationName}${origin?.exact === false ? " · node position" : ""}`;
  const tankValue = sessionValue(session);
  els.saleTankValue.dataset.value = String(tankValue);
  els.saleTankValue.textContent = `${silver(tankValue)} silver`;
  els.saleTankValue.title = `${number(tankValue)} silver`;
  els.saleBargain.textContent = `${number(existing?.bargainBonusPercent ?? sessionBargainBonus(session), 1)}%`;
  els.saleSoldAt.value = localDateTimeInput(existing?.soldAt || new Date());
  els.saleFinalAmount.value = existing?.finalAmount != null ? String(existing.finalAmount) : "";
  els.saleDelete.classList.toggle("is-hidden", !existing);
  renderSaleOffers();
  els.saleBackdrop.classList.remove("is-hidden");
  els.saleBackdrop.setAttribute("aria-hidden", "false");
}

function closeSalePlanner() {
  els.saleBackdrop.classList.add("is-hidden");
  els.saleBackdrop.setAttribute("aria-hidden", "true");
  state.salePlanner = { sessionId: "", offers: [], selected: 0 };
}

function renderSaleOffers() {
  if (!state.salePlanner.offers.length) return;
  const session = state.sessions.find(entry => String(entry.id) === state.salePlanner.sessionId);
  if (!session) return;
  const origin = sessionOriginWorld(session);
  const items = sessionCatches(session).filter(item => item.count > 0);
  const bargain = sessionSale(session)?.bargainBonusPercent ?? sessionBargainBonus(session);
  els.saleOffers.innerHTML = `<div class="sale-quote-grid">
    <div class="sale-grid-corner"><strong>Fish in this tank</strong><span>${number(items.length)} kinds · ${number(sessionTotal(session))} retained</span></div>
    ${state.salePlanner.offers.map((offer, index) => `<article class="sale-destination-card" data-sale-column="${index}">
      <button type="button" class="sale-offer-select" data-sale-select="${index}" aria-label="Use ${escapeHtml(offer.destination)} for the sale record"><span></span></button>
      <label><span>Destination</span><select data-sale-destination="${index}">${offerDestinationOptions(offer.destination)}</select></label>
      <strong class="sale-distance-badge">${number(offer.distance, 1)}% distance</strong>
    </article>`).join("")}
    ${items.map(item => {
      const key = saleItemKey(item);
      const base = saleItemBaseValue(item);
      return `<div class="sale-fish-cell">
        <span class="sale-fish-icon grade-frame ${itemGradeClass(item.grade)}"><img src="/icon/${item.itemId}.webp" alt=""></span>
        <span><strong>${escapeHtml(item.name)}</strong><small>${number(item.count)} × ${silver(item.price)}</small></span>
        <b>${silver(base)}</b>
      </div>${state.salePlanner.offers.map((offer, index) => `<label class="sale-quote-cell" data-sale-quote-cell="${index}">
        <span class="sale-percent-input"><input data-sale-quote="${index}" data-sale-item="${escapeHtml(key)}" aria-label="${escapeHtml(item.name)} quotation at ${escapeHtml(offer.destination)}" type="number" min="30" max="130" step="0.1" value="${number(saleQuoteFor(offer, item), 1)}"><b>%</b></span>
        <small data-sale-item-total="${index}:${escapeHtml(key)}">${silver(saleProjection(base, saleQuoteFor(offer, item), offer.distance, bargain))}</small>
      </label>`).join("")}`;
    }).join("")}
    <div class="sale-total-label"><strong>Estimated return</strong><span>quotation · distance · bargain</span></div>
    ${state.salePlanner.offers.map((offer, index) => `<button type="button" class="sale-total-cell" data-sale-summary="${index}">
      <span data-sale-rank="${index}">Comparison</span>
      <strong data-sale-total="${index}">${silver(saleOfferTotal(session, offer, bargain))}</strong>
      <small data-sale-delta="${index}"></small>
    </button>`).join("")}
  </div>`;

  $$('[data-sale-select]', els.saleOffers).forEach(button => {
    button.addEventListener("click", () => {
      state.salePlanner.selected = Number(button.dataset.saleSelect);
      updateSaleDecisionTotals();
    });
  });
  $$('[data-sale-summary]', els.saleOffers).forEach(button => {
    button.addEventListener("click", () => {
      state.salePlanner.selected = Number(button.dataset.saleSummary);
      updateSaleDecisionTotals();
    });
  });
  $$('[data-sale-destination]', els.saleOffers).forEach(control => {
    control.addEventListener("change", event => {
      const index = Number(event.target.dataset.saleDestination);
      const destination = tradeDestinations().find(entry => entry.name === event.target.value);
      state.salePlanner.offers[index].destination = event.target.value;
      state.salePlanner.offers[index].distance = distanceBonusBetween(origin, destination);
      renderSaleOffers();
    });
  });
  $$('[data-sale-quote]', els.saleOffers).forEach(control => {
    const syncQuote = event => {
      const index = Number(event.target.dataset.saleQuote);
      const key = String(event.target.dataset.saleItem || "");
      const value = Number(event.target.value);
      if (Number.isFinite(value)) state.salePlanner.offers[index].quotes[key] = Math.max(30, Math.min(130, value));
      updateSaleDecisionTotals();
    };
    control.addEventListener("input", syncQuote);
    control.addEventListener("change", event => {
      syncQuote(event);
      const index = Number(event.target.dataset.saleQuote);
      const key = String(event.target.dataset.saleItem || "");
      event.target.value = number(state.salePlanner.offers[index].quotes[key] ?? 100, 1);
    });
  });
  updateSaleDecisionTotals();
}

function updateSaleDecisionTotals() {
  const session = state.sessions.find(entry => String(entry.id) === state.salePlanner.sessionId);
  if (!session || !state.salePlanner.offers.length) return;
  const bargain = sessionSale(session)?.bargainBonusPercent ?? sessionBargainBonus(session);
  const items = sessionCatches(session).filter(item => item.count > 0);
  const totals = state.salePlanner.offers.map(offer => saleOfferTotal(session, offer, bargain));
  const bestTotal = Math.max(...totals);
  const bestIndex = totals.indexOf(bestTotal);
  state.salePlanner.offers.forEach((offer, index) => {
    const selected = index === state.salePlanner.selected;
    const best = index === bestIndex;
    const column = $(`[data-sale-column="${index}"]`, els.saleOffers);
    const summary = $(`[data-sale-summary="${index}"]`, els.saleOffers);
    column?.classList.toggle("is-selected", selected);
    column?.classList.toggle("is-best", best);
    summary?.classList.toggle("is-selected", selected);
    summary?.classList.toggle("is-best", best);
    $$(`[data-sale-quote-cell="${index}"]`, els.saleOffers).forEach(cell => cell.classList.toggle("is-selected", selected));
    const totalNode = $(`[data-sale-total="${index}"]`, els.saleOffers);
    const rankNode = $(`[data-sale-rank="${index}"]`, els.saleOffers);
    const deltaNode = $(`[data-sale-delta="${index}"]`, els.saleOffers);
    if (totalNode) totalNode.textContent = silver(totals[index]);
    if (rankNode) rankNode.textContent = best ? "Best return" : "Compared with best";
    if (deltaNode) {
      const difference = Math.max(0, bestTotal - totals[index]);
      const percent = bestTotal > 0 ? difference / bestTotal * 100 : 0;
      deltaNode.textContent = best ? "Best place to sell" : `${silver(difference)} less · ${number(percent, 1)}%`;
    }
    items.forEach(item => {
      const itemTotal = saleProjection(saleItemBaseValue(item), saleQuoteFor(offer, item), offer.distance, bargain);
      const node = $(`[data-sale-item-total="${index}:${CSS.escape(saleItemKey(item))}"]`, els.saleOffers);
      if (node) node.textContent = silver(itemTotal);
    });
  });
  renderSaleChosenSummary();
}

function renderSaleChosenSummary() {
  const offer = state.salePlanner.offers[state.salePlanner.selected];
  const session = state.sessions.find(entry => String(entry.id) === state.salePlanner.sessionId);
  if (!offer || !session) return;
  const bargain = sessionSale(session)?.bargainBonusPercent ?? sessionBargainBonus(session);
  const comparison = saleOfferTotal(session, offer, bargain);
  const actual = Number(els.saleFinalAmount.value) || 0;
  els.saleChosenSummary.innerHTML = `<span>${escapeHtml(offer.destination)}</span><strong>${actual > 0 ? silver(actual) : silver(comparison)}</strong><small>${actual > 0 ? "actual silver" : "comparison only"}</small>`;
}

async function saveRecordedSale() {
  const session = state.sessions.find(entry => String(entry.id) === state.salePlanner.sessionId);
  const offer = state.salePlanner.offers[state.salePlanner.selected];
  const soldAt = new Date(els.saleSoldAt.value);
  const finalAmount = Number(els.saleFinalAmount.value);
  if (!session || !offer) return;
  if (Number.isNaN(soldAt.getTime())) { showToast("Choose when the fish were sold.", true); return; }
  if (!Number.isFinite(finalAmount) || finalAmount <= 0) { showToast("Enter the actual silver received in game.", true); els.saleFinalAmount.focus(); return; }
  els.saleSave.disabled = true;
  try {
    await request(`/api/sessions/${encodeURIComponent(session.id)}/sale`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        soldAt: soldAt.toISOString(),
        destination: offer.destination,
        currentTankValue: Math.max(0, Math.round(sessionValue(session))),
        marketPercent: saleOfferEffectiveQuote(session, offer),
        distanceBonusPercent: offer.distance,
        bargainBonusPercent: sessionBargainBonus(session),
        finalAmount: Math.round(finalAmount),
      }),
    });
    await loadSessions();
    closeSalePlanner();
    renderJournal();
    showToast("Actual sale recorded.");
  } catch (error) { showToast(error.message, true); }
  finally { els.saleSave.disabled = false; }
}

async function deleteRecordedSale() {
  const id = state.salePlanner.sessionId;
  if (!id || !window.confirm("Remove this recorded sale? The fishing haul will stay in your journal.")) return;
  try {
    await request(`/api/sessions/${encodeURIComponent(id)}/sale`, { method: "DELETE" });
    await loadSessions();
    closeSalePlanner();
    renderJournal();
    showToast("Recorded sale removed.");
  } catch (error) { showToast(error.message, true); }
}

function formatDate(value) {
  const date = new Date(value || Date.now());
  return new Intl.DateTimeFormat("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }).format(date);
}

function journalDateMatches(value) {
  const timestamp = new Date(value).getTime();
  if (!Number.isFinite(timestamp)) return false;
  const from = state.journalFilters.from ? new Date(`${state.journalFilters.from}T00:00:00`).getTime() : null;
  const to = state.journalFilters.to ? new Date(`${state.journalFilters.to}T23:59:59.999`).getTime() : null;
  return (from == null || timestamp >= from) && (to == null || timestamp <= to);
}

function filteredJournalSessions() {
  const salesMode = state.journalFilters.mode === "sales";
  return state.sessions.filter(session => {
    const sale = sessionSale(session);
    if (salesMode && !sale) return false;
    if (!salesMode && state.journalFilters.status !== "all" && isLegacyAggregateSession(session)) return false;
    if (!salesMode && state.journalFilters.status === "sold" && !sale) return false;
    if (!salesMode && state.journalFilters.status === "unsold" && sale) return false;
    const date = salesMode ? sale?.soldAt : session.caughtAt || session.caught_at || session.createdAt || session.created_at;
    return journalDateMatches(date);
  });
}

function renderJournal() {
  const sessions = filteredJournalSessions();
  const totalFish = sessions.reduce((sum,session) => sum + sessionTotal(session),0);
  const legacyAggregateCount = sessions.filter(isLegacyAggregateSession).length;
  const valueSessions = sessions.filter(session => !isLegacyAggregateSession(session));
  const totalValue = valueSessions.reduce((sum,session) => sum + sessionValue(session),0);
  const totalValueKnown = sessions.length === 0 || valueSessions.length > 0;
  const legacyValueSummary = legacyAggregateCount
    ? `<small class="journal-legacy-value-summary">Excludes ${number(legacyAggregateCount)} aggregate-only ${legacyAggregateCount === 1 ? "import" : "imports"}</small>`
    : "";
  const sales = sessions.map(sessionSale).filter(Boolean);
  const recordedValue = sales.reduce((sum, sale) => sum + Number(sale.finalAmount || 0), 0);
  const legacyReceivedEntries = sessions.map(legacyReceivedSilver).filter(value => value != null);
  const legacyReceivedValue = legacyReceivedEntries.reduce((sum, value) => sum + value, 0);
  const legacyReceivedSummary = legacyReceivedEntries.length
    ? `<small class="journal-legacy-summary" title="${number(legacyReceivedValue)} silver received in v0.1.7">Legacy received: ${silver(legacyReceivedValue)} silver &middot; ${number(legacyReceivedEntries.length)} imported ${legacyReceivedEntries.length === 1 ? "haul" : "hauls"}</small>`
    : "";
  els.journalStatusField.classList.toggle("is-hidden", state.journalFilters.mode === "sales");
  els.journalSummary.innerHTML = `<div class="summary-card"><span>${state.journalFilters.mode === "sales" ? "Sold hauls" : "Catches"}</span><strong>${number(sessions.length)}</strong></div><div class="summary-card"><span>Retained fish</span><strong>${number(totalFish)}</strong></div><div class="summary-card value-summary"><span>Fish tank value</span><strong title="${totalValueKnown ? `${number(totalValue)} silver` : "Not recorded for aggregate-only imports"}">${totalValueKnown ? `${silver(totalValue)} <small>silver</small>` : "—"}</strong>${legacyValueSummary}</div><div class="summary-card value-summary recorded-summary"><span>Recorded sales</span><strong title="${number(recordedValue)} silver">${sales.length ? silver(recordedValue) : "—"} ${sales.length ? "<small>silver</small>" : ""}</strong><small>${number(sales.length)} ${sales.length === 1 ? "sale" : "sales"}</small>${legacyReceivedSummary}</div>`;
  if (!sessions.length) {
    const hasFilters = Boolean(state.journalFilters.from || state.journalFilters.to || state.journalFilters.status !== "all" || state.journalFilters.mode === "sales");
    els.journalList.innerHTML = `<div class="surface empty-state"><div class="empty-stack"><span></span><span></span><span></span></div><strong>${hasFilters ? "No matching journal entries" : "No saved hauls yet"}</strong>${hasFilters ? "" : `<button class="primary-button small" data-empty-add style="margin-top:16px">Add your first haul</button>`}</div>`;
    const add = $("[data-empty-add]", els.journalList);
    if (add) add.addEventListener("click", beginNewHaul);
    return;
  }
  const sorted = [...sessions].sort((a,b) => {
    const aDate = state.journalFilters.mode === "sales" ? sessionSale(a)?.soldAt : a.caughtAt || a.caught_at || a.createdAt || a.created_at;
    const bDate = state.journalFilters.mode === "sales" ? sessionSale(b)?.soldAt : b.caughtAt || b.caught_at || b.createdAt || b.created_at;
    return new Date(bDate) - new Date(aDate);
  });
  els.journalList.innerHTML = sorted.map(session => {
    const catches = sessionCatches(session).sort((a,b) => b.count - a.count);
    const legacyAggregate = isLegacyAggregateSession(session);
    const total = sessionTotal(session);
    const duration = Number((session.durationMinutes ?? session.duration_minutes) || 0);
    const zoneName = String(session.zoneName || session.zone_name || "Fishing table");
    const locationName = String(session.locationName || session.location_name || zoneName);
    const tool = setupToolMeta(session.equipment, session.method);
    const equipmentName = session.equipment || (session.method === "harpoon" ? "Harpoon" : "Fishing rod");
    const rawValue = sessionValue(session);
    const sale = legacyAggregate ? null : sessionSale(session);
    const receivedSilver = legacyReceivedSilver(session);
    const rawNotes = String(session.notes ?? "");
    const notes = rawNotes.trim() ? rawNotes : "";
    const profileName = String(session.profileName || session.profile_name || session.setupName || session.setup_name || "").trim();
    const setup = [
      legacyAggregate && profileName ? profileName : null,
      session.mastery != null && session.mastery !== "" && Number.isFinite(Number(session.mastery)) ? `${number(session.mastery)} mastery` : null,
      duration ? formatDuration(duration) : null,
      legacyAggregate ? "Imported v0.1.7 · read-only" : null,
    ].filter(Boolean);
    const fishDetails = legacyAggregate
      ? `<span class="journal-legacy-explainer"><strong>Aggregate retained count</strong><small>Fish species were not stored in v0.1.7.</small></span>`
      : catches.map(item => `<span class="fish-peek-item grade-frame ${itemGradeClass(item.grade)}" title="${escapeHtml(item.name)} &middot; ${number(item.count)}"><img src="/icon/${item.itemId}.webp" alt=""><b>${number(item.count)}</b></span>`).join("");
    const values = legacyAggregate
      ? `<div class="journal-value is-tank is-empty"><span>Fish tank value</span><strong aria-label="Not recorded">&mdash;</strong><small class="journal-value-note">Species were not stored</small></div><div class="journal-value is-sale${receivedSilver == null ? " is-empty" : ""}"><span>Legacy received</span>${receivedSilver == null ? `<strong aria-label="Not recorded">&mdash;</strong>` : `<strong title="${number(receivedSilver)} silver">${silver(receivedSilver)} <em>silver</em></strong>`}</div>`
      : `<div class="journal-value is-tank"><span>Fish tank value</span><strong title="${number(rawValue)} silver">${silver(rawValue)} <em>silver</em></strong></div><div class="journal-value is-sale${sale ? "" : " is-empty"}"><span>Recorded sale</span>${sale ? `<strong title="${number(sale.finalAmount)} silver">${silver(sale.finalAmount)} <em>silver</em></strong>` : `<strong aria-label="No recorded sale">&mdash;</strong>`}</div>`;
    const actions = legacyAggregate
      ? `<span class="journal-legacy-lock" title="This v0.1.7 entry contains aggregate totals, not editable fish species or a recalculable sale."><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 10V8a5 5 0 0 1 10 0v2h2v12H5V10h2Zm2 0h6V8a3 3 0 0 0-6 0v2Zm3 4a2 2 0 0 0-1 3.73V20h2v-2.27A2 2 0 0 0 12 14Z"/></svg><span>Read-only import</span></span>`
      : `<button type="button" class="journal-sale-button"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v3H4V5Zm1 5h14l-1 9H6l-1-9Zm5 2v5h4v-5h-4Z"/></svg><span>${sale ? "Sale details" : "Where to sell?"}</span></button><button type="button" class="journal-edit-button"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15.7 3.3 5 5L8.9 20.1 3 21l.9-5.9L15.7 3.3Zm0 2.8L5.8 16l-.3 2.5L8 18.2l9.9-9.9-2.2-2.2Z"/></svg><span>Edit</span></button>`;
    return `<article class="journal-row${legacyAggregate ? " is-legacy-aggregate" : ""}" data-id="${escapeHtml(session.id)}">
      <div class="journal-entry-info">
        <div class="journal-entry-heading"><span class="journal-method-icon grade-frame ${tool.gradeClass}" title="${escapeHtml(equipmentName)}"><img src="/icon/${tool.icon}.webp" alt=""></span><div><strong>${escapeHtml(locationName)}</strong><small>${escapeHtml(formatDate(session.caughtAt || session.caught_at || session.createdAt || session.created_at))}</small></div></div>
        <div class="journal-setup">${setup.map(value => `<span>${escapeHtml(value)}</span>`).join("")}</div>
        ${notes ? `<p class="journal-session-note"><strong>Note</strong><span>${escapeHtml(notes)}</span></p>` : ""}
      </div>
      <div class="fish-peek${legacyAggregate ? " is-legacy" : ""}"><span class="fish-peek-count"><strong>${number(total)}</strong><small>fish</small></span><div class="fish-peek-icons">${fishDetails}</div></div>
      <div class="journal-values">${values}</div>
      <div class="journal-actions${legacyAggregate ? " is-legacy" : ""}"><button type="button" class="journal-map-button"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 4 6-2v16l-6 2-6-2-6 2V4l6-2 6 2Zm-5 .2v12l4 1.33v-12L10 4.2ZM5 6v11.23l3-1V5L5 6Zm11-.23v12l3-1V5.1l-3 .67Z"/></svg><span>Location</span></button>${actions}<button type="button" class="delete-session" aria-label="Delete haul"><svg viewBox="0 0 24 24"><path d="M8 4V2h8v2h5v2H3V4h5Zm-3 4h14l-1 14H6L5 8Zm4 3v8h2v-8H9Zm4 0v8h2v-8h-2Z"/></svg></button></div>
    </article>`;
  }).join("");
  $$(".journal-row", els.journalList).forEach(row => {
    $(".journal-map-button", row).addEventListener("click", () => showJournalSessionOnMap(row.dataset.id));
    $(".journal-sale-button", row)?.addEventListener("click", () => openSalePlanner(row.dataset.id));
    $(".journal-edit-button", row)?.addEventListener("click", () => editSession(row.dataset.id));
    $(".delete-session", row).addEventListener("click", () => deleteSession(row.dataset.id));
  });
}

function showJournalSessionOnMap(id) {
  const session = state.sessions.find(entry => String(entry.id) === String(id));
  if (!session) return;
  const rgb = normalizeRgb(session.zoneRgb ?? session.zone_rgb);
  const x = finiteNumberOrNull(session.point?.x ?? session.pointX ?? session.point_x);
  const y = finiteNumberOrNull(session.point?.y ?? session.pointY ?? session.point_y);
  const point = x != null && y != null ? { x, y, sourceKind: "journal" } : null;
  const knownZone = state.zoneByRgb.get(rgb);
  const zone = knownZone || (Number.isFinite(rgb) ? {
    rgb,
    name: session.zoneName || session.zone_name || "Saved fishing table",
    center: point ? { x, y } : null,
    active: true,
    dataKnown: true,
  } : null);
  if (!zone || (!point && !zone.center)) {
    showToast("This haul has no mapped fishing table.", true);
    return;
  }
  const method = session.method === "harpoon" ? "harpoon" : "rod";
  state.method.map = method;
  $$('[data-method-switch="map"] [data-method]').forEach(button => button.classList.toggle("is-active", button.dataset.method === method));
  applyMapFilters();
  navigate("map");
  window.requestAnimationFrame(() => {
    if (point) focusEvidenceCluster(zone, point);
    else {
      focusZone(zone);
      showToast("Showing the saved fishing table.");
    }
  });
}

function formatDuration(minutes) {
  const n = Number(minutes);
  const hours = Math.floor(n / 60);
  const mins = n % 60;
  if (hours && mins) return `${hours}h ${mins}m`;
  if (hours) return `${hours}h`;
  return `${mins}m`;
}

async function deleteSession(id) {
  if (!window.confirm("Delete this haul from the private journal?")) return;
  try {
    await request(`/api/sessions/${encodeURIComponent(id)}`, { method: "DELETE" });
    await loadSessions(); renderJournal(); showToast("Haul deleted.");
  } catch (error) { showToast(error.message, true); }
}

function refreshEquipmentOptions() {
  const method = state.method.stats;
  const defaults = method === "rod" ? ["Balenos Rod","Triple-Float Rod"] : ["Thin Harpoon","Thick Harpoon","Manos Harpoon"];
  const fromData = state.sessions.filter(session => session.method === method).map(session => session.equipment).filter(Boolean);
  const values = [...new Set([...defaults,...fromData])];
  const current = values.includes(els.statsEquipment.value) ? els.statsEquipment.value : "all";
  const toolLabel = method === "rod" ? "Rod" : "Harpoon";
  els.statsEquipment.value = current;
  els.statsEquipmentLabel.textContent = toolLabel;
  els.statsEquipmentOptions.setAttribute("aria-label", `${toolLabel} filter`);
  els.statsEquipmentOptions.innerHTML = `<button type="button" class="stats-choice tool-choice ${current === "all" ? "is-active" : ""}" data-stats-equipment="all" aria-pressed="${current === "all"}"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16v2H4V6Zm0 5h16v2H4v-2Zm0 5h16v2H4v-2Z"/></svg><span>All</span></button>${values.map(value => {
    const meta = TOOL_ITEMS[value];
    const visual = meta
      ? `<span class="stats-tool-icon grade-frame ${meta.gradeClass}"><img src="/icon/${meta.icon}.webp" alt=""></span><span>${escapeHtml(meta.shortLabel)}</span>`
      : `<span>${escapeHtml(value)}</span>`;
    return `<button type="button" class="stats-choice tool-choice ${current === value ? "is-active" : ""}" data-stats-equipment="${escapeHtml(value)}" aria-pressed="${current === value}" title="${escapeHtml(value)}">${visual}</button>`;
  }).join("")}`;
  $$('[data-stats-equipment]', els.statsEquipmentOptions).forEach(button => button.addEventListener("click", () => {
    els.statsEquipment.value = button.dataset.statsEquipment;
    $$('[data-stats-equipment]', els.statsEquipmentOptions).forEach(other => {
      const active = other === button;
      other.classList.toggle("is-active", active);
      other.setAttribute("aria-pressed", String(active));
    });
    state.statsSelected = null;
    renderStats();
  }));
}

function masteryMatches(value, filter) {
  const mastery = Number(value);
  if (filter === "all") return true;
  if (filter === "0-999") return mastery >= 0 && mastery <= 999;
  if (filter === "1000-1499") return mastery >= 1000 && mastery <= 1499;
  if (filter === "1500-1999") return mastery >= 1500 && mastery <= 1999;
  if (filter === "2000-2499") return mastery >= 2000 && mastery <= 2499;
  if (filter === "2500+") return mastery >= 2500;
  return true;
}

function statsGradeKey(grade) {
  const frame = itemGradeClass(grade);
  if (frame === "grade-prize") return "red";
  if (frame === "grade-rare") return "yellow";
  if (frame === "grade-high-quality") return "blue";
  if (frame === "grade-general") return "green";
  return "other";
}

const STATS_GRADE_DEFINITIONS = Object.freeze([
  { key: "red", label: "Red fish" },
  { key: "yellow", label: "Yellow fish" },
  { key: "blue", label: "Blue fish" },
  { key: "green", label: "Green fish" },
  { key: "other", label: "Other" },
]);

function statsLocationInputKey(value = els.statsLocation?.value) {
  return String(value || "").trim().toLowerCase();
}

function closeStatsLocationSuggestions() {
  state.statsSuggestionIndex = -1;
  els.statsLocationSuggestions.classList.add("is-hidden");
  els.statsLocation.setAttribute("aria-expanded", "false");
  els.statsLocation.removeAttribute("aria-activedescendant");
}

function setActiveStatsLocationSuggestion(index) {
  const count = state.statsSuggestions.length;
  if (!count) return;
  const normalized = ((index % count) + count) % count;
  state.statsSuggestionIndex = normalized;
  $$(".location-suggestion", els.statsLocationSuggestions).forEach((option, optionIndex) => {
    const active = optionIndex === normalized;
    option.classList.toggle("is-active", active);
    option.setAttribute("aria-selected", String(active));
    if (active) {
      els.statsLocation.setAttribute("aria-activedescendant", option.id);
      option.scrollIntoView({ block: "nearest" });
    }
  });
}

function renderStatsLocationSuggestions(query = els.statsLocation.value, forceOpen = false) {
  const value = String(query || "").trim();
  if (!value) {
    state.statsSuggestions = [];
    closeStatsLocationSuggestions();
    return;
  }
  const groups = captureLocationSuggestionGroups(value);
  const visibleGroups = [
    ["Nodes", groups.nodes.slice(0, 7)],
    ["Fishing spots", groups.zones.slice(0, 7)],
  ];
  state.statsSuggestions = visibleGroups.flatMap(([, items]) => items);
  state.statsSuggestionIndex = -1;
  let optionIndex = 0;
  els.statsLocationSuggestions.innerHTML = visibleGroups.filter(([, items]) => items.length).map(([heading, items]) => {
    const options = items.map(item => {
      const index = optionIndex++;
      return `<button id="stats-location-option-${index}" type="button" class="location-suggestion" role="option" aria-selected="false" data-suggestion-index="${index}"><span class="location-suggestion-icon">${locationSuggestionIcon(item.type)}</span><span class="location-suggestion-copy"><strong>${escapeHtml(item.label)}</strong><small>${escapeHtml(item.meta)}</small></span></button>`;
    }).join("");
    return `<div class="location-suggestion-group">${heading}</div>${options}`;
  }).join("");
  const shouldOpen = forceOpen && state.statsSuggestions.length > 0;
  els.statsLocationSuggestions.classList.toggle("is-hidden", !shouldOpen);
  els.statsLocation.setAttribute("aria-expanded", String(shouldOpen));
  $$(".location-suggestion", els.statsLocationSuggestions).forEach(option => {
    option.addEventListener("pointerdown", event => {
      event.preventDefault();
      selectStatsLocationSuggestion(Number(option.dataset.suggestionIndex));
    });
    option.addEventListener("pointerenter", () => setActiveStatsLocationSuggestion(Number(option.dataset.suggestionIndex)));
  });
}

function renderStatsLocationSelection() {
  const location = state.statsLocation;
  els.statsLocationClear.classList.toggle("is-hidden", !els.statsLocation.value.trim());
  els.statsLocationMessage.classList.add("is-hidden");
  els.statsLocationMessage.classList.remove("needs-map", "is-pending");
  els.statsLocationMessage.textContent = "";
  if (!location) return;
  els.statsLocationMessage.classList.remove("is-hidden");
  if (location.resolving) {
    els.statsLocationMessage.classList.add("is-pending");
    els.statsLocationMessage.textContent = "Finding its fishing table...";
    return;
  }
  if (location.requiresExactClick || !location.zone) {
    els.statsLocationMessage.classList.add("needs-map");
    els.statsLocationMessage.textContent = "This node crosses tables - mark the exact water on the map.";
    return;
  }
  els.statsLocationMessage.textContent = `Fishing table: ${location.zone.name}`;
}

function commitStatsLocation(location, updateInput = true) {
  state.statsLocation = location || null;
  if (updateInput && location) els.statsLocation.value = location.inputValue || location.locationName || location.zone?.name || "";
  state.statsSelected = null;
  renderStatsLocationSelection();
  renderStats();
  return state.statsLocation;
}

async function resolveStatsNodeLocation(name = els.statsLocation.value) {
  const inputValue = String(name || "").trim();
  const inputKey = statsLocationInputKey(inputValue);
  const node = findNodeByInput(inputValue);
  if (!node) return state.statsLocation;
  if (state.statsLocation?.inputKey === inputKey && (state.statsLocation.source === "map-click" || state.statsLocation.zone)) return state.statsLocation;
  const requestId = ++state.statsLocationResolveRequestId;
  try {
    const result = await request(`/api/location-resolve?q=${encodeURIComponent(inputValue)}`);
    if (requestId !== state.statsLocationResolveRequestId || statsLocationInputKey() !== inputKey) return null;
    const location = result.location || (Array.isArray(result.matches) && result.matches.length === 1 ? result.matches[0] : null) || node;
    const aggregation = result.aggregation || {};
    const ambiguousZones = result.ambiguousZones || aggregation.ambiguousZones || result.candidateZones || aggregation.candidateZones || [];
    const requiresExactClick = result.requiresExactClick === true
      || aggregation.requiresExactClick === true
      || location.requiresExactClick === true
      || location.zoneBoundaryAmbiguous === true
      || result.ambiguous === true
      || aggregation.ambiguous === true
      || location.ambiguous === true
      || ambiguousZones.length > 1
      || (result.status && result.status !== "resolved");
    const zone = requiresExactClick ? null : zoneFromLocationData(
      aggregation.zoneRgb ?? location.zoneRgb,
      aggregation.zoneName ?? location.zoneName,
    );
    return commitStatsLocation({
      type: "node",
      inputKey,
      inputValue,
      locationName: String(aggregation.displayLocationName || location.name || node.name || inputValue),
      node: { ...node, ...location },
      zone,
      requiresExactClick: requiresExactClick || !zone,
      anchor: resolutionAnchor(result, node),
      candidateZones: ambiguousZones,
      source: zone ? "node-resolver" : "exact-click-required",
    }, false);
  } catch {
    if (requestId !== state.statsLocationResolveRequestId || statsLocationInputKey() !== inputKey) return null;
    return commitStatsLocation({
      type: "node",
      inputKey,
      inputValue,
      locationName: node.name,
      node,
      zone: null,
      requiresExactClick: true,
      anchor: resolutionAnchor(null, node),
      source: "exact-click-required",
    }, false);
  }
}

function selectStatsLocationSuggestion(index) {
  const suggestion = state.statsSuggestions[index];
  if (!suggestion) return;
  els.statsLocation.value = suggestion.label;
  closeStatsLocationSuggestions();
  if (suggestion.type === "zone") {
    const zone = suggestion.value;
    commitStatsLocation({ type: "zone", inputKey: statsLocationInputKey(suggestion.label), inputValue: suggestion.label, locationName: zone.name, node: null, zone, requiresExactClick: false, source: "fishing-region" }, false);
    return;
  }
  const node = suggestion.value;
  state.statsLocation = { type: "node", inputKey: statsLocationInputKey(suggestion.label), inputValue: suggestion.label, locationName: node.name, node, zone: null, requiresExactClick: false, resolving: true, source: "node-resolver" };
  renderStatsLocationSelection();
  renderStats();
  resolveStatsNodeLocation(suggestion.label);
}

function onStatsLocationInput() {
  window.clearTimeout(statsLocationResolveTimer);
  state.statsLocationResolveRequestId += 1;
  const inputValue = els.statsLocation.value;
  const inputKey = statsLocationInputKey(inputValue);
  els.statsLocationClear.classList.toggle("is-hidden", !inputKey);
  if (!inputKey) {
    state.statsLocation = null;
    state.statsSelected = null;
    renderStatsLocationSelection();
    closeStatsLocationSuggestions();
    renderStats();
    return;
  }
  if (state.statsLocation?.inputKey !== inputKey) state.statsLocation = null;
  const zone = directZoneByInput(inputValue);
  const node = findNodeByInput(inputValue);
  if (zone) state.statsLocation = { type: "zone", inputKey, inputValue, locationName: zone.name, node: null, zone, requiresExactClick: false, source: "fishing-region" };
  else if (node) state.statsLocation = { type: "node", inputKey, inputValue, locationName: node.name, node, zone: null, requiresExactClick: false, resolving: true, source: "node-resolver" };
  state.statsSelected = null;
  renderStatsLocationSelection();
  renderStatsLocationSuggestions(inputValue, true);
  renderStats();
  if (node) statsLocationResolveTimer = window.setTimeout(() => resolveStatsNodeLocation(inputValue), 160);
}

function onStatsLocationKeydown(event) {
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    if (els.statsLocationSuggestions.classList.contains("is-hidden")) renderStatsLocationSuggestions(els.statsLocation.value, true);
    const delta = event.key === "ArrowDown" ? 1 : -1;
    const start = state.statsSuggestionIndex < 0 ? (delta > 0 ? 0 : state.statsSuggestions.length - 1) : state.statsSuggestionIndex + delta;
    setActiveStatsLocationSuggestion(start);
    return;
  }
  if (event.key === "Enter") {
    const exactIndex = state.statsSuggestions.findIndex(item => item.label.toLowerCase() === els.statsLocation.value.trim().toLowerCase());
    const choice = state.statsSuggestionIndex >= 0 ? state.statsSuggestionIndex : exactIndex;
    if (choice >= 0) {
      event.preventDefault();
      selectStatsLocationSuggestion(choice);
    }
    return;
  }
  if (event.key === "Escape") closeStatsLocationSuggestions();
}

function clearStatsLocation() {
  window.clearTimeout(statsLocationResolveTimer);
  state.statsLocationResolveRequestId += 1;
  state.statsLocation = null;
  state.statsSelected = null;
  els.statsLocation.value = "";
  closeStatsLocationSuggestions();
  renderStatsLocationSelection();
  renderStats();
  els.statsLocation.focus();
}

async function beginStatsMapSelection() {
  closeStatsLocationSuggestions();
  let location = state.statsLocation;
  if (location?.type === "node" && location.resolving) location = await resolveStatsNodeLocation(location.inputValue);
  const nodeLocation = location?.type === "node" ? location : null;
  const anchor = nodeLocation?.anchor || nodeLocation?.point || location?.point || location?.zone?.center || resolutionAnchor(null, nodeLocation?.node);
  state.pendingMapLocation = {
    scope: "stats",
    inputKey: nodeLocation?.inputKey || "",
    inputValue: nodeLocation?.inputValue || "",
    locationName: nodeLocation?.locationName || "",
    node: nodeLocation?.node || null,
    anchor,
  };
  state.selectedZone = null;
  state.selectedPoint = null;
  renderSpotPoints(state.filteredZones);
  state.spotRequestId += 1;
  renderEmptySpotDrawer();
  updateMapResultSelection();
  els.captureMapPromptText.textContent = nodeLocation?.locationName ? `Mark water near ${nodeLocation.locationName}` : "Mark the fishing location";
  els.captureMapPrompt.classList.remove("is-hidden");
  navigate("map");
  setSpotDrawerOpen(false);
  window.requestAnimationFrame(() => {
    if (!state.map.initialized) homeMap();
    if (anchor && Number.isFinite(anchor.x) && Number.isFinite(anchor.y)) {
      const frame = measureMapVisibleFrame();
      state.map.scale = Math.max(state.map.scale, .72);
      state.map.offsetX = frame.centerX - anchor.x * state.map.scale;
      state.map.offsetY = frame.centerY - anchor.y * state.map.scale;
      clampMap();
      applyMapTransform();
      renderTiles(true);
      showPin(anchor.x, anchor.y);
    } else {
      els.mapPin.classList.add("is-hidden");
    }
    showToast(nodeLocation ? "Mark the exact water where you fished." : "Mark the fishing location on the map.");
  });
}

function statsLocationMatchesSession(session) {
  const location = state.statsLocation;
  if (!location || location.resolving || !location.zone) return true;
  const selectedRgb = normalizeRgb(location.zone.rgb);
  const sessionRgb = normalizeRgb(session.zoneRgb ?? session.zone_rgb);
  if (Number.isFinite(selectedRgb) && Number.isFinite(sessionRgb)) return selectedRgb === sessionRgb;
  const selectedName = normalizeSearchText(location.zone.name || location.locationName);
  const sessionName = normalizeSearchText(session.zoneName || session.zone_name || session.locationName || session.location_name);
  return Boolean(selectedName && sessionName && selectedName === sessionName);
}

function buildPersonalStats() {
  const method = state.method.stats;
  const profileId = els.statsProfile.value;
  const style = els.statsStyle.value;
  const equipment = els.statsEquipment.value;
  const mastery = els.statsMastery.value;
  const resource = els.statsResource.value;
  const filtered = state.sessions.filter(session => {
    if (isLegacyAggregateSession(session)) return false;
    if (session.method !== method) return false;
    if (profileId !== "all" && String(session.profileId || session.profile_id || session.setupId || session.setup_id || "") !== profileId) return false;
    if (style !== "all" && session.style !== style) return false;
    if (equipment !== "all" && session.equipment !== equipment) return false;
    if (!masteryMatches(session.mastery, mastery)) return false;
    if (!statsLocationMatchesSession(session)) return false;
    const sessionResource = session.resourceLevel || session.resource_level || "unrecorded";
    if (resource !== "all" && sessionResource !== resource) return false;
    return true;
  });
  const bySpot = new Map();
  for (const session of filtered) {
    const rgb = normalizeRgb(session.zoneRgb ?? session.zone_rgb);
    const zoneName = String(session.zoneName || session.zone_name || "Fishing table");
    const locationName = String(session.locationName || session.location_name || zoneName).trim() || zoneName;
    const tableKey = Number.isFinite(rgb) ? String(rgb) : zoneName.toLowerCase();
    const key = `${tableKey}|${locationName.toLowerCase()}`;
    if (!bySpot.has(key)) bySpot.set(key, { key, rgb, name: locationName, tableName: zoneName, depth: session.depth || depthKey({name:zoneName}), sessions: 0, totalFish: 0, totalValue: 0, totalMinutes: 0, timedFish: 0, timedGradeCounts: new Map(), resourceLevels: new Set(), catches: new Map() });
    const spot = bySpot.get(key);
    spot.sessions += 1;
    const catches = sessionCatches(session);
    const sessionFish = catches.reduce((sum,item) => sum + item.count,0);
    spot.totalFish += sessionFish;
    spot.totalValue += catches.reduce((sum,item) => sum + item.count * item.price,0);
    spot.resourceLevels.add(session.resourceLevel || session.resource_level || "unrecorded");
    const duration = Number((session.durationMinutes ?? session.duration_minutes) || 0);
    if (duration > 0) {
      spot.totalMinutes += duration;
      spot.timedFish += sessionFish;
      catches.forEach(item => {
        const grade = statsGradeKey(item.grade);
        spot.timedGradeCounts.set(grade, (spot.timedGradeCounts.get(grade) || 0) + item.count);
      });
    }
    for (const item of catches) {
      if (!spot.catches.has(item.itemId)) spot.catches.set(item.itemId, { itemId:item.itemId, name:item.name, count:0, price:item.price, grade:item.grade });
      spot.catches.get(item.itemId).count += item.count;
    }
  }
  return [...bySpot.values()].filter(spot => spot.totalFish > 0).map(spot => {
    spot.fish = [...spot.catches.values()].sort((a,b) => b.count - a.count || a.name.localeCompare(b.name)).map(item => ({ ...item, per100: item.count / spot.totalFish * 100, percentage: item.count / spot.totalFish * 100 }));
    spot.valuePer100 = spot.totalValue / spot.totalFish * 100;
    spot.fishPerHour = spot.totalMinutes > 0 ? spot.timedFish / spot.totalMinutes * 60 : null;
    spot.hoursPer100 = spot.totalMinutes > 0 && spot.timedFish > 0 ? (spot.totalMinutes / spot.timedFish * 100) / 60 : null;
    spot.grades = STATS_GRADE_DEFINITIONS.map(definition => {
      const count = spot.fish.filter(item => statsGradeKey(item.grade) === definition.key).reduce((sum, item) => sum + item.count, 0);
      const timedCount = spot.timedGradeCounts.get(definition.key) || 0;
      return {
        ...definition,
        count,
        percentage: count / spot.totalFish * 100,
        perHour: spot.totalMinutes > 0 ? timedCount / spot.totalMinutes * 60 : null,
      };
    });
    spot.resourceSummary = spot.resourceLevels.size === 1 ? resourceLabel([...spot.resourceLevels][0]) : "Mixed resources";
    return spot;
  }).sort((a,b) => b.totalFish - a.totalFish || a.name.localeCompare(b.name));
}

function renderStats() {
  const spots = buildPersonalStats();
  if (!spots.length) {
    els.statsList.innerHTML = `<div class="surface empty-state"><div class="empty-chart"><i></i><i></i><i></i></div><strong>No matching catches yet</strong><p>Every saved tank contributes by fish count, including tanks sold before 100/100.</p><button class="primary-button small" data-stats-add style="margin-top:16px">Add a haul</button></div>`;
    $("[data-stats-add]", els.statsList).addEventListener("click", beginNewHaul);
    els.statsDetail.innerHTML = `<div class="empty-state compact"><div class="empty-chart"><i></i><i></i><i></i></div><strong>Nothing to inspect yet</strong><p>Adjust the filters or add a matching haul.</p></div>`;
    return;
  }
  if (!spots.some(spot => spot.key === state.statsSelected)) state.statsSelected = null;
  els.statsList.innerHTML = spots.map(spot => {
    const waterLabel = depthLabel(spot.depth);
    const info = [
      `${number(spot.totalFish)} fish`,
      `${number(spot.sessions)} ${spot.sessions === 1 ? "haul" : "hauls"}`,
      spot.totalMinutes ? formatDuration(spot.totalMinutes) : null,
      spot.resourceSummary !== "Not recorded" ? spot.resourceSummary : null,
      normalizeSearchText(spot.name).includes(normalizeSearchText(waterLabel)) ? null : waterLabel,
    ].filter(Boolean).join(" &middot; ");
    return `<button class="stats-row ${spot.key === state.statsSelected ? "is-active" : ""}" data-key="${escapeHtml(spot.key)}">
      <span class="stats-spot"><strong>${escapeHtml(spot.name)}</strong><small>${info}</small></span>
      <span class="stats-fishes">${spot.fish.slice(0,5).map(item => `<span class="stats-fish" title="${escapeHtml(item.name)}"><span class="stats-fish-icon grade-frame ${itemGradeClass(item.grade)}"><img src="/icon/${item.itemId}.webp" alt=""><b>${number(item.per100,1)}</b></span></span>`).join("")}</span>
      <span class="stats-value"><span class="stats-value-metric"><strong>${silver(spot.valuePer100)}</strong><small>Tank value / 100</small></span><span class="stats-value-metric is-time"><strong>${spot.hoursPer100 != null ? formatDuration(Math.round(spot.hoursPer100 * 60)) : "&mdash;"}</strong><small>Time for 100 fish</small></span></span>
    </button>`;
  }).join("");
  $$(".stats-row", els.statsList).forEach(row => row.addEventListener("click", () => { state.statsSelected = row.dataset.key; renderStats(); }));
  const selected = spots.find(spot => spot.key === state.statsSelected);
  if (selected) renderStatsDetail(selected);
  else els.statsDetail.innerHTML = `<div class="empty-state compact"><div class="empty-chart"><i></i><i></i><i></i></div><strong>Choose a fishing spot</strong><p>Its grade mix and catch pace will appear here.</p></div>`;
}

function renderStatsDetail(spot) {
  const gradeByKey = new Map((spot.grades || []).map(grade => [grade.key, grade]));
  const focusGrades = [gradeByKey.get("red"), gradeByKey.get("yellow")].filter(Boolean);
  const visibleGrades = (spot.grades || []).filter(grade => grade.count > 0);
  els.statsDetail.innerHTML = `<div class="stats-detail-header">
    <h2>${escapeHtml(spot.name)}</h2><p>${number(spot.totalFish)} fish &middot; ${number(spot.sessions)} ${spot.sessions === 1 ? "haul" : "hauls"}${spot.totalMinutes ? ` &middot; ${formatDuration(spot.totalMinutes)}` : ""}</p>
  </div>
  <div class="grade-insights">
    <div class="grade-focus-grid">${focusGrades.map(grade => `<article class="grade-focus-card ${grade.key}">
      <header><span></span><strong>${escapeHtml(grade.label)}</strong></header>
      <div class="grade-focus-values"><strong>${number(grade.percentage,1)}%</strong><span><b>${grade.perHour != null ? number(grade.perHour,2) : "&mdash;"}</b><small>${grade.perHour != null ? "per hour" : "no time"}</small></span></div>
      <p>${number(grade.count)} of ${number(spot.totalFish)} retained</p>
    </article>`).join("")}</div>
    <section class="grade-composition">
      <div class="grade-composition-heading"><strong>Catch composition</strong><span>${spot.totalMinutes ? `${number(spot.fishPerHour,1)} fish / hour` : "No time recorded"}</span></div>
      <div class="grade-composition-bar" aria-label="Catch composition">${visibleGrades.map(grade => `<i class="${grade.key}" style="width:${grade.percentage}%" title="${escapeHtml(grade.label)} ${number(grade.percentage,1)}%"></i>`).join("")}</div>
      <div class="grade-legend">${visibleGrades.map(grade => `<span class="${grade.key}"><i></i><b>${escapeHtml(grade.label)}</b><strong>${number(grade.percentage,1)}%</strong></span>`).join("")}</div>
    </section>
    <div class="grade-time-summary"><span><small>Timed fishing</small><strong>${spot.totalMinutes ? formatDuration(spot.totalMinutes) : "&mdash;"}</strong></span><span><small>Catch pace</small><strong>${spot.fishPerHour != null ? `${number(spot.fishPerHour,1)} / hour` : "&mdash;"}</strong></span><span><small>Time for 100 fish</small><strong>${spot.hoursPer100 != null ? formatDuration(Math.round(spot.hoursPer100 * 60)) : "&mdash;"}</strong></span></div>
  </div>`;
  return;
  els.statsDetail.innerHTML = `<div class="stats-detail-header">
    <h2>${escapeHtml(spot.name)}</h2><p>${number(spot.totalFish)} fish &middot; ${number(spot.sessions)} ${spot.sessions === 1 ? "haul" : "hauls"}${spot.totalMinutes ? ` &middot; ${formatDuration(spot.totalMinutes)}` : ""}</p>
    <div class="detail-totals"><div class="detail-total"><strong>${silver(spot.valuePer100)}</strong><small>fish tank value / 100</small></div><div class="detail-total"><strong>${spot.fishPerHour ? number(spot.fishPerHour,1) : "—"}</strong><small>${spot.fishPerHour ? "retained fish / hour" : "no time entered"}</small></div></div>
  </div><div class="detail-fish-list">${spot.fish.map(item => `<div class="detail-fish-row"><img class="grade-frame ${itemGradeClass(item.grade)}" src="/icon/${item.itemId}.webp" alt=""><div><strong>${escapeHtml(item.name)}</strong><small>${number(item.count)} caught · ${item.price ? silver(item.price) : "value unknown"}</small></div><div class="detail-fish-rate"><strong>${number(item.per100,1)}</strong><small>per 100 · ${number(item.percentage,1)}%</small></div></div>`).join("")}</div>`;
}

function bindStatsFilters() {
  $$('[data-stats-style]').forEach(button => button.addEventListener("click", () => {
    els.statsStyle.value = button.dataset.statsStyle;
    $$('[data-stats-style]').forEach(other => {
      const active = other === button;
      other.classList.toggle("is-active", active);
      other.setAttribute("aria-pressed", String(active));
    });
    state.statsSelected = null;
    renderStats();
  }));
  [els.statsProfile, els.statsMastery, els.statsResource].forEach(control => control.addEventListener("change", () => { state.statsSelected = null; renderStats(); }));
  els.statsLocation.addEventListener("input", onStatsLocationInput);
  els.statsLocation.addEventListener("focus", () => renderStatsLocationSuggestions(els.statsLocation.value, true));
  els.statsLocation.addEventListener("keydown", onStatsLocationKeydown);
  els.statsLocationClear.addEventListener("click", clearStatsLocation);
  els.statsLocationMap.addEventListener("click", beginStatsMapSelection);
  document.addEventListener("pointerdown", event => {
    if (!els.statsLocationCombobox.contains(event.target)) closeStatsLocationSuggestions();
  });
}

async function initialize() {
  cacheElements();
  restoreUiOpacity();
  bindUiOpacity();
  bindNavigation();
  bindProfiles();
  bindMethodSwitches();
  bindMap();
  bindMapFilters();
  bindCapture();
  bindJournal();
  bindStatsFilters();
  try {
    const bootstrap = await request("/api/bootstrap");
    normalizeBootstrap(bootstrap);
    setSourceState(bootstrap.source || bootstrap.provenance || {});
    populateOptions();
    renderRegions();
    applyMapFilters();
    await loadSessions().catch(() => []);
    await loadFishingProfiles().catch(() => []);
    await loadLegacyMigrationStatus().catch(() => null);
    refreshProfileOptions();
    refreshEquipmentOptions();
    els.boot.classList.add("is-done");
    els.app.classList.remove("is-hidden");
    initializeDesktopScaling();
    window.setTimeout(() => {
      els.boot.remove();
      if (!state.selectedZone) homeMap();
      // Give the visible application two complete paint opportunities before
      // any source refresh can contend with map setup and first interaction.
      window.requestAnimationFrame(() => window.requestAnimationFrame(() => {
        request("/api/background-refresh", { method: "POST" }).catch(() => {});
        window.setTimeout(refreshLiveBootstrap, 1400);
      }));
    }, 280);
  } catch (error) {
    els.bootText.textContent = `Could not open the fishing data: ${error.message}`;
    els.bootText.style.color = "#ff9caf";
  }
}

async function refreshLiveBootstrap(attempt = 0) {
  try {
    const fresh = await request("/api/bootstrap");
    const previousZone = state.selectedZone;
    const previousPoint = state.selectedPoint;
    const maskChanged = state.data?.fishingRegionLayer?.revision !== fresh.fishingRegionLayer?.revision;
    normalizeBootstrap(fresh);
    setSourceState(fresh.source || fresh.provenance || {});
    populateOptions();
    renderRegions();
    applyMapFilters();
    if (previousZone && state.selectedZone?.rgb === previousZone.rgb) {
      let updatedZone = state.zoneByRgb.get(previousZone.rgb);
      if (maskChanged && previousPoint && previousPoint.sourceKind !== "ranking") {
        const resolved = await request(`/api/zone-at?x=${Math.floor(previousPoint.x)}&y=${Math.floor(previousPoint.y)}`);
        updatedZone = state.zoneByRgb.get(normalizeRgb(resolved.rgb ?? resolved.zone?.rgb)) || resolved.zone;
      }
      if (!updatedZone && state.selectedZone?.rgb === previousZone.rgb) closeSpotDrawer();
      else if (updatedZone && state.selectedZone?.rgb === previousZone.rgb) {
        const tableChanged = JSON.stringify(previousZone.tableSource) !== JSON.stringify(updatedZone.tableSource)
          || JSON.stringify(previousZone.accuracyNotes) !== JSON.stringify(updatedZone.accuracyNotes);
        // Old ranking clusters no longer attest to the current boundary revision.
        const updatedPoint = maskChanged && previousPoint?.sourceKind === "ranking" ? null : previousPoint;
        selectZone(updatedZone, updatedPoint);
        if (tableChanged || maskChanged) await loadSpotDetails(updatedZone.rgb);
      }
    }
    // A full source-table sweep takes minutes, not the former five-second window.
    window.setTimeout(() => refreshLiveBootstrap(0), fresh.source?.refreshInProgress ? 5000 : 60000);
  } catch {
    window.setTimeout(() => refreshLiveBootstrap(attempt + 1), Math.min(60000, 5000 * (attempt + 1)));
  }
}

document.addEventListener("DOMContentLoaded", initialize);
