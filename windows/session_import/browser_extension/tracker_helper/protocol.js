(function installTrackerProtocol(global) {
  "use strict";

  const SCHEMA_VERSION = 1;
  const NATIVE_HOST_NAME = "com.blackspiritlife.session_import.trial";
  const FIREFOX_EXTENSION_ID = "session-import-trial@blackspirit.life";
  const MAX_MESSAGE_BYTES = 64 * 1024;
  const MAX_ITEMS = 160;
  const MAX_DURATION_SECONDS = 14 * 24 * 60 * 60;
  const ALLOWED_ACTIVITIES = new Set(["gathering", "hunting", "grinding"]);
  const GARMOTH_ORIGIN = "https://garmoth.com";
  const GARMOTH_PATH_PREFIX = "/grind-tracker";

  class ProtocolError extends Error {
    constructor(code, message) {
      super(message);
      this.name = "ProtocolError";
      this.code = code;
    }
  }

  function isPlainObject(value) {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      return false;
    }
    const prototype = Object.getPrototypeOf(value);
    return prototype === Object.prototype || prototype === null;
  }

  function requiredText(value, field, maximumLength) {
    if (typeof value !== "string") {
      throw new ProtocolError("invalid_" + field, field + " must be text.");
    }
    const normalized = value.trim();
    if (!normalized || normalized.length > maximumLength) {
      throw new ProtocolError("invalid_" + field, field + " is empty or too long.");
    }
    return normalized;
  }

  function optionalText(value, field, maximumLength) {
    if (value === undefined || value === null || value === "") {
      return null;
    }
    return requiredText(value, field, maximumLength);
  }

  function optionalInteger(value, field, minimum, maximum) {
    if (value === undefined || value === null || value === "") {
      return null;
    }
    const parsed = typeof value === "number" ? value : Number(value);
    if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum) {
      throw new ProtocolError("invalid_" + field, field + " must be a safe integer.");
    }
    return parsed;
  }

  function optionalPercentage(value, field) {
    if (value === undefined || value === null || value === "") return null;
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 10_000
        || Math.abs(value * 100 - Math.round(value * 100)) > 0.000001) {
      throw new ProtocolError("invalid_" + field, field + " must be from 0 to 10000 with at most two decimal places.");
    }
    return value;
  }

  function optionalBoolean(value, field) {
    if (value === undefined || value === null) return null;
    if (typeof value !== "boolean") throw new ProtocolError("invalid_" + field, field + " must be true or false.");
    return value;
  }

  function isGarmothTrackerUrl(value, allowBarePath) {
    try {
      const parsed = new URL(value);
      const validPath = parsed.pathname.startsWith(GARMOTH_PATH_PREFIX + "/")
        || (allowBarePath === true && parsed.pathname === GARMOTH_PATH_PREFIX);
      const placeholder = parsed.pathname.split("/").some((segment) => /^(?:null|undefined)$/i.test(decodeURIComponent(segment)));
      return parsed.origin === GARMOTH_ORIGIN && validPath && !placeholder;
    } catch (_) {
      return false;
    }
  }

  function normalizeGarmothUrl(value) {
    if (value === undefined || value === null || value === "") {
      return null;
    }
    let parsed;
    try {
      parsed = new URL(value);
    } catch (_) {
      throw new ProtocolError("invalid_target_url", "target.url is not a valid URL.");
    }
    if (!isGarmothTrackerUrl(parsed.toString(), true)) {
      throw new ProtocolError("invalid_target_url", "target.url must be a Garmoth grind tracker URL.");
    }
    parsed.username = "";
    parsed.password = "";
    parsed.hash = "";
    return parsed.toString();
  }

  function normalizeItem(rawItem, index) {
    if (!isPlainObject(rawItem)) {
      throw new ProtocolError("invalid_item", "items[" + index + "] must be an object.");
    }
    const itemId = optionalText(rawItem.itemId, "item_id", 80);
    const name = requiredText(rawItem.name, "item_name", 160);
    const subKey = optionalInteger(rawItem.subKey, "sub_key", 0, 1_000_000) ?? 0;
    const quantity = optionalInteger(rawItem.quantity, "quantity", 1, Number.MAX_SAFE_INTEGER);
    if (quantity === null) {
      throw new ProtocolError("invalid_quantity", "Every item needs a positive quantity.");
    }
    return { itemId, subKey, name, quantity };
  }

  function normalizeDraft(rawDraft) {
    if (!isPlainObject(rawDraft)) {
      throw new ProtocolError("invalid_draft", "draft must be an object.");
    }
    if (rawDraft.schemaVersion !== SCHEMA_VERSION) {
      throw new ProtocolError("unsupported_schema", "Only schemaVersion 1 is supported.");
    }

    const draftId = requiredText(rawDraft.draftId, "draft_id", 100);
    if (!isPlainObject(rawDraft.target)) {
      throw new ProtocolError("invalid_target", "target must be an object.");
    }
    const activity = requiredText(rawDraft.target.activity, "activity", 20).toLowerCase();
    if (!ALLOWED_ACTIVITIES.has(activity)) {
      throw new ProtocolError("invalid_activity", "activity is not supported.");
    }
    const target = {
      provider: rawDraft.target.provider === undefined
        ? "garmoth"
        : requiredText(rawDraft.target.provider, "provider", 30).toLowerCase(),
      activity,
      spotId: optionalText(
        rawDraft.target.spotId === undefined || rawDraft.target.spotId === null
          ? null
          : String(rawDraft.target.spotId),
        "spot_id",
        80
      ),
      spotName: requiredText(rawDraft.target.spotName, "spot_name", 160),
      url: normalizeGarmothUrl(rawDraft.target.url)
    };
    if (target.provider !== "garmoth") {
      throw new ProtocolError("invalid_provider", "Only Garmoth is supported by this trial.");
    }

    if (!isPlainObject(rawDraft.session)) {
      throw new ProtocolError("invalid_session", "session must be an object.");
    }
    const rawItems = rawDraft.session.items;
    if (!Array.isArray(rawItems) || rawItems.length === 0 || rawItems.length > MAX_ITEMS) {
      throw new ProtocolError("invalid_items", "session.items must contain 1 to " + MAX_ITEMS + " items.");
    }
    const items = rawItems.map(normalizeItem);
    const identities = new Set();
    for (const item of items) {
      const identity = item.itemId
        ? "id:" + item.itemId + ":" + item.subKey
        : "name:" + item.name.toLocaleLowerCase("en-US") + ":" + item.subKey;
      if (identities.has(identity)) {
        throw new ProtocolError("duplicate_item", "The draft contains the same item more than once.");
      }
      identities.add(identity);
    }

    const durationSeconds = optionalInteger(
      rawDraft.session.durationSeconds,
      "duration_seconds",
      1,
      MAX_DURATION_SECONDS
    );
    if (durationSeconds === null) {
      throw new ProtocolError("invalid_duration_seconds", "session.durationSeconds is required.");
    }

    const behavior = isPlainObject(rawDraft.behavior) ? rawDraft.behavior : {};
    if (behavior.submit === true) {
      throw new ProtocolError("submission_forbidden", "This helper never submits or saves sessions.");
    }

    const createdAtUtc = optionalText(rawDraft.createdAtUtc, "created_at", 50);
    const expiresAtUtc = optionalText(rawDraft.expiresAtUtc, "expires_at", 50);
    if (expiresAtUtc) {
      const expiry = Date.parse(expiresAtUtc);
      if (!Number.isFinite(expiry)) {
        throw new ProtocolError("invalid_expiry", "expiresAtUtc is not a valid date.");
      }
      if (expiry <= Date.now()) {
        throw new ProtocolError("expired_draft", "The import draft has expired.");
      }
    }

    return {
      schemaVersion: SCHEMA_VERSION,
      draftId,
      createdAtUtc,
      expiresAtUtc,
      target,
      session: {
        durationSeconds,
        mastery: optionalInteger(rawDraft.session.mastery, "mastery", 0, 100_000),
        energySpent: optionalInteger(rawDraft.session.energySpent, "energy_spent", 0, 10_000_000),
        agrisUsed: optionalInteger(rawDraft.session.agrisUsed, "agris_used", 0, 10_000_000_000),
        agrisActive: optionalBoolean(rawDraft.session.agrisActive, "agris_active"),
        additionalDropRate: optionalPercentage(rawDraft.session.additionalDropRate, "additional_drop_rate"),
        additionalDropAmount: optionalPercentage(rawDraft.session.additionalDropAmount, "additional_drop_amount"),
        items
      },
      behavior: {
        skipUnsupported: behavior.skipUnsupported !== false,
        submit: false
      }
    };
  }

  function assertMessageSize(value) {
    let json;
    try {
      json = JSON.stringify(value);
    } catch (_) {
      throw new ProtocolError("invalid_message", "The message is not JSON serializable.");
    }
    const byteLength = new TextEncoder().encode(json).byteLength;
    if (byteLength > MAX_MESSAGE_BYTES) {
      throw new ProtocolError("message_too_large", "The message exceeds the 64 KiB trial limit.");
    }
    return byteLength;
  }

  function errorResult(error) {
    if (error instanceof ProtocolError) {
      return { ok: false, code: error.code, message: error.message };
    }
    return {
      ok: false,
      code: "unexpected_error",
      message: error && error.message ? String(error.message) : "Unexpected extension error."
    };
  }

  global.TrackerProtocol = Object.freeze({
    SCHEMA_VERSION,
    NATIVE_HOST_NAME,
    FIREFOX_EXTENSION_ID,
    MAX_MESSAGE_BYTES,
    GARMOTH_ORIGIN,
    GARMOTH_PATH_PREFIX,
    ProtocolError,
    normalizeDraft,
    normalizeGarmothUrl,
    isGarmothTrackerUrl,
    assertMessageSize,
    errorResult
  });
})(globalThis);
