(function installGarmothDraftFiller(global) {
  "use strict";

  const api = global.browser || global.chrome;
  const protocol = global.TrackerProtocol;
  let preparationActive = false;
  let assertPreparationActive = () => {};
  const WRITTEN_ATTRIBUTE = "data-bsl-session-import-written";
  const OPTIONAL_ATTRIBUTE = "data-bsl-session-import-optional";
  const OPTIONAL_FIELDS = new Set(["mastery", "energySpent", "agrisUsed", "additionalDropRate", "additionalDropAmount"]);
  const NOTES_START = "[BS Life: not included in Garmoth totals]";
  const NOTES_END = "[/BS Life]";
  const FORBIDDEN_ACTION = /\b(save|submit|confirm|finish|create\s+session)\b/i;
  const EDITABLE_SELECTOR = [
    "input:not([type='hidden']):not([type='submit']):not([type='button'])",
    "textarea",
    "select",
    "[role='spinbutton']",
    "[contenteditable='true']"
  ].join(",");

  function delay(milliseconds) {
    return new Promise((resolve) => global.setTimeout(resolve, milliseconds));
  }

  function normalizedText(value) {
    return String(value || "")
      .normalize("NFKC")
      .replace(/[’`]/g, "'")
      .replace(/\s+/g, " ")
      .trim()
      .toLocaleLowerCase("en-US");
  }

  function isVisible(element) {
    if (!(element instanceof Element) || element.hidden) {
      return false;
    }
    const style = global.getComputedStyle(element);
    return style.display !== "none"
      && style.visibility !== "hidden"
      && style.opacity !== "0"
      && element.getClientRects().length > 0;
  }

  function all(scope, selector) {
    return Array.from(scope.querySelectorAll(selector));
  }

  function accessibleText(element) {
    const pieces = [
      element.getAttribute("aria-label"),
      element.getAttribute("title"),
      element.getAttribute("alt"),
      element.getAttribute("data-name"),
      element.textContent
    ];
    return normalizedText(pieces.filter(Boolean).join(" "));
  }

  function individualNames(element) {
    return [
      element.getAttribute("aria-label"),
      element.getAttribute("title"),
      element.getAttribute("alt"),
      element.getAttribute("data-name"),
      element.textContent
    ].filter(Boolean).map(normalizedText).filter(Boolean);
  }

  function labelledText(control) {
    const pieces = [
      control.getAttribute("aria-label"),
      control.getAttribute("title"),
      control.getAttribute("placeholder"),
      control.getAttribute("name"),
      control.getAttribute("id"),
      control.getAttribute("data-field"),
      control.getAttribute("data-testid")
    ];
    if (control.labels) {
      for (const label of control.labels) {
        pieces.push(label.textContent);
      }
    }
    const labelledBy = control.getAttribute("aria-labelledby");
    if (labelledBy) {
      for (const id of labelledBy.split(/\s+/)) {
        const label = control.ownerDocument.getElementById(id);
        if (label) {
          pieces.push(label.textContent);
        }
      }
    }
    const enclosingLabel = control.closest("label");
    if (enclosingLabel) {
      pieces.push(enclosingLabel.textContent);
    }
    const parent = control.parentElement;
    if (parent && parent.textContent.length < 180) {
      pieces.push(parent.textContent);
    }
    return normalizedText(pieces.filter(Boolean).join(" "));
  }

  function safeClick(element, purpose, expectedText) {
    assertPreparationActive();
    if (!(element instanceof Element) || !isVisible(element)) {
      throw new protocol.ProtocolError("unsafe_click", "The requested Garmoth control is unavailable.");
    }
    const name = accessibleText(element);
    const inputType = normalizedText(element.getAttribute("type"));
    const implicitSubmit = element instanceof HTMLButtonElement
      && element.form !== null
      && element.type === "submit";
    if (inputType === "submit" || implicitSubmit || FORBIDDEN_ACTION.test(name)) {
      throw new protocol.ProtocolError("submission_forbidden", "The helper refused a submit control.");
    }
    if (purpose === "open_editor"
        && !individualNames(element).some((entry) => /^(\+\s*)?add( (new )?session)?$/.test(entry))) {
      throw new protocol.ProtocolError("unsafe_click", "The Add session control changed unexpectedly.");
    }
    if (purpose === "select_spot" && expectedText && !name.includes(normalizedText(expectedText))) {
      throw new protocol.ProtocolError("unsafe_click", "The requested spot option was not an exact match.");
    }
    assertPreparationActive();
    element.click();
  }

  function assertTrackerPage() {
    const current = new URL(global.location.href);
    if (!protocol.isGarmothTrackerUrl(current.href, false) || current.username || current.password) {
      throw new protocol.ProtocolError("wrong_page", "Open a Garmoth Grind Tracker page before importing.");
    }
  }

  function editorScore(element) {
    if (!isVisible(element)) {
      return -1;
    }
    const controls = all(element, EDITABLE_SELECTOR).filter(isVisible);
    if (controls.length === 0) {
      return -1;
    }
    const descriptor = normalizedText([
      element.getAttribute("aria-label"),
      element.getAttribute("class"),
      element.getAttribute("data-testid"),
      element.textContent.slice(0, 1200)
    ].filter(Boolean).join(" "));
    const dialogLike = element.matches("[role='dialog'],[aria-modal='true'],dialog[open]");
    if (!dialogLike && (!descriptor.includes("session") || controls.length < 2)) {
      return -1;
    }
    let score = Math.min(controls.length, 20);
    if (dialogLike) {
      score += 40;
    }
    if (descriptor.includes("session")) {
      score += 30;
    }
    if (descriptor.includes("loot") || descriptor.includes("time") || descriptor.includes("duration")) {
      score += 10;
    }
    return score;
  }

  function numericItemIdentity(value) {
    const text = String(value || "");
    return /^\d+$/.test(text) && /[1-9]/.test(text) ? text.replace(/^0+/, "") : null;
  }

  function tableImageIdentity(image) {
    try {
      const url = new URL(image.currentSrc || image.src, global.location.href);
      if (url.origin !== "https://assets.garmoth.com") return null;
      const filename = decodeURIComponent(url.pathname.split("/").pop());
      const match = filename.match(/^(\d+)\.(?:webp|png|jpe?g)$/i);
      return match ? numericItemIdentity(match[1]) : null;
    } catch (_) { return null; }
  }

  function ownTableRows(table) {
    return all(table, "tr").filter(row => row.closest("table") === table);
  }

  function sessionTableShape(table) {
    if (!isVisible(table)) return false;
    const headers = all(table, "th").filter(header => header.closest("table") === table);
    const labels = headers.map(header => normalizedText(header.textContent));
    return labels.some(label => /^(?:hours?|hours\s*:\s*mins|duration)$/.test(label))
      && (labels.some(label => /^(?:mins?|minutes?)$/.test(label)) || labels.includes("hours:mins") || labels.includes("duration"))
      && headers.some(header => all(header, "img[src]").some(image => tableImageIdentity(image)))
      && all(table, "input").some(control => actionable(control) && !control.readOnly);
  }

  // Resolve the HTML table's logical grid, including header colSpan/rowSpan.
  // Header artwork and input cells need not share an ancestor below TABLE.
  function sessionTableLayout(scope) {
    const tables = (scope.matches?.("table") ? [scope] : all(scope, "table")).filter(sessionTableShape);
    if (tables.length !== 1) return null;
    const table = tables[0];
    const rows = ownTableRows(table);
    const grid = [];
    const positions = new Map();
    for (let rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
      grid[rowIndex] ||= [];
      let column = 0;
      const cells = Array.from(rows[rowIndex].children).filter(cell => cell.matches("th,td"));
      for (const cell of cells) {
        while (grid[rowIndex][column]) column += 1;
        const colSpan = Number(cell.getAttribute("colspan") || 1);
        const rowSpan = Number(cell.getAttribute("rowspan") || 1);
        if (!Number.isInteger(colSpan) || !Number.isInteger(rowSpan) || colSpan < 1 || rowSpan < 1
            || colSpan > 200 || rowSpan > rows.length || column + colSpan > 200) return null;
        positions.set(cell, {row:rowIndex,column,colSpan,rowSpan});
        for (let r = rowIndex; r < rowIndex + rowSpan; r += 1) {
          grid[r] ||= [];
          for (let c = column; c < column + colSpan; c += 1) {
            if (grid[r][c]) return null;
            grid[r][c] = cell;
          }
        }
        column += colSpan;
      }
    }
    const editableRows = rows.filter(row => all(row, "input,select,textarea,[contenteditable='true']")
      .some(control => control.closest("table") === table && actionable(control) && !control.readOnly));
    if (editableRows.length !== 1) return null;
    const editableRow = editableRows[0];
    const rowIndex = rows.indexOf(editableRow);
    const fields = [];
    const items = [];
    for (const cell of Array.from(editableRow.children).filter(cell => cell.matches("td"))) {
      const controls = all(cell, EDITABLE_SELECTOR).filter(control => actionable(control) && !control.readOnly);
      if (!controls.length) continue;
      const position = positions.get(cell);
      if (controls.length !== 1 || position.colSpan !== 1 || position.rowSpan !== 1) return null;
      const headers = [];
      for (let row = 0; row < rowIndex; row += 1) {
        const header = grid[row]?.[position.column];
        if (header?.tagName === "TH" && positions.get(header)?.colSpan === 1 && !headers.includes(header)) headers.push(header);
      }
      if (!headers.length) return null;
      const header = headers[headers.length - 1];
      const control = controls[0];
      const images = all(header, "img[src]");
      if (images.length) {
        if (!isQuantityControl(control)) return null;
        const identityMarkers = [header, ...all(header, "[data-item-id],[data-item-key]")];
        const dataIds = [...new Set(identityMarkers.flatMap(marker => [marker.getAttribute("data-item-id"), marker.getAttribute("data-item-key")])
          .map(value => numericItemIdentity(String(value || "").replace(/:0$/, ""))).filter(Boolean))];
        const names = [...new Set([...individualNames(header), ...images.flatMap(individualNames)].filter(name => /[a-z]/i.test(name)))];
        items.push({header,control,images,dataIds,names,ids:[...new Set(images.map(tableImageIdentity).filter(Boolean))]});
      } else {
        const label = normalizedText(header.textContent).replace(/^mins?$/, "minutes").replace(/^hours:mins$/, "duration");
        fields.push({header,control,label});
      }
    }
    const one = aliases => fields.filter(field => aliases.includes(field.label));
    const hours = one(["hour", "hours"]);
    const minutes = one(["minute", "minutes"]);
    const clock = one(["hours:mins", "duration"]);
    if (!items.length || !(hours.length === 1 && minutes.length === 1 || clock.length === 1)) return null;
    return {table,editableRow,fields,items};
  }

  function tableSessionContainers(root) {
    const containers = new Set();
    for (const table of all(root, "table").filter(sessionTableShape)) {
      let container = table.parentElement;
      for (let depth = 0; container && container !== root.body && depth < 6; depth += 1, container = container.parentElement) {
        if (!isVisible(container)) continue;
        const saves = all(container, "button,input[type='submit']").filter(button => isVisible(button)
          && individualNames(button).some(name => /^(?:save|save session)$/.test(name)));
        if (saves.length === 1) { containers.add(container); break; }
      }
    }
    return [...containers];
  }

  function findEditor(root) {
    const candidates = all(
      root,
      "[role='dialog'],[aria-modal='true'],dialog[open],[data-state='open'],form"
    );
    const tableContainers = tableSessionContainers(root);
    return candidates.concat(tableContainers)
      .map((element) => ({ element, score: Math.max(editorScore(element), tableContainers.includes(element) ? 25 : -1) }))
      .filter((entry) => entry.score >= 25)
      .sort((left, right) => right.score - left.score)[0]?.element || null;
  }

  function sessionLabels(element) {
    return [element.getAttribute("aria-label"),
      ...(element.getAttribute("aria-labelledby") || "").split(/\s+/)
        .map((id) => element.ownerDocument.getElementById(id)?.textContent),
      ...all(element, "h1,h2,h3,h4,h5,h6,[role='heading']").map((heading) => heading.textContent)
    ].map(normalizedText);
  }

  function isSessionEditor(element) {
    if (!element || !isVisible(element)) return false;
    const controls = all(element, EDITABLE_SELECTOR).filter(isVisible);
    if (!controls.length || controls.some((control) => control.matches("input[type='password'],input[type='email']"))) return false;
    if (sessionTableLayout(element) && all(element, "button,input[type='submit']").filter(button => isVisible(button)
      && individualNames(button).some(name => /^(?:save|save session)$/.test(name))).length === 1) return true;
    if (sessionLabels(element).some((label) => /^(?:(?:add(?: new)?|edit|new) )?session(?: details)?$/.test(label))) return true;
    // Some tracker layouts use a normal section instead of an ARIA dialog.
    // Require the complete session structure, not a generic panel with Save.
    const hasDuration = !!findField(element, ["duration", "session time", "hours", "minutes"]);
    const hasLootHeading = all(element, "h1,h2,h3,h4,h5,h6,label,[role='heading']")
      .some((heading) => /^(?:session )?loot(?: items)?$/.test(normalizedText(heading.textContent)));
    const hasItem = all(element, "[data-item-id],img[src],[data-item-key]")
      .some((marker) => isVisible(marker) && hasNearbyQuantityControl(marker, element));
    const hasSave = all(element, "button,[role='button'],input[type='submit']")
      .some((button) => isVisible(button) && individualNames(button).some((name) => /^(?:save|save session)$/.test(name)));
    return hasDuration && hasLootHeading && hasItem && hasSave;
  }

  function findSessionEditor(root) {
    const candidates = all(root, "[role='dialog'],[aria-modal='true'],dialog[open],[data-state='open'],form,section")
      .concat(tableSessionContainers(root));
    for (const heading of all(root, "h1,h2,h3,h4,h5,h6,[role='heading']")) {
      if (!/^(?:(?:add(?: new)?|edit|new) )?session(?: details)?$/.test(normalizedText(heading.textContent))) continue;
      let ancestor = heading.parentElement;
      for (let depth = 0; ancestor && ancestor !== root.body && depth < 4; depth += 1, ancestor = ancestor.parentElement) candidates.push(ancestor);
    }
    return [...new Set(candidates)].filter(isSessionEditor)
      .sort((left, right) => all(left, EDITABLE_SELECTOR).length - all(right, EDITABLE_SELECTOR).length)[0] || null;
  }

  function actionable(element) {
    return !!element && isVisible(element) && !element.disabled && element.getAttribute("aria-disabled") !== "true";
  }

  function visibleLogin(root) {
    return all(root, "button,a,[role='button'],h1,h2,[role='heading']")
      .some((element) => actionable(element) && individualNames(element)
        .some((name) => /^(?:log\s?in|sign\s?in)(?: to garmoth| with discord)?$/.test(name)));
  }

  function canPrepareCurrentPage(root, target) {
    const editor = findSessionEditor(root);
    if (editor) {
      if (verifySelectedSpot(editor, root, target)) return true;
      const select = findField(editor, ["spot", "monster zone", "gathering spot", "zone"], "select");
      if (select) return Array.from(select.options).some((option) => optionMatches(option, target));
      return all(editor, "[role='combobox'],button[aria-haspopup='listbox']")
        .some((control) => actionable(control) && phraseScore(labelledText(control), ["spot", "monster zone", "gathering spot", "zone"]) > 0);
    }
    return !findEditor(root) && actionable(findOpenEditorButton(root));
  }

  function renderedTrackerHref(link, allowCurrent = false, requireVisible = true) {
    if (!link || (requireVisible ? !actionable(link) : link.disabled || link.getAttribute("aria-disabled") === "true")
        || link.getAttribute("download") !== null) return null;
    try {
      const url = new URL(link.getAttribute("href"), global.location.href);
      if (url.username || url.password || !protocol.isGarmothTrackerUrl(url.href, false)
          || /\/(?:logout|signout|delete|remove|api|oauth)(?:\/|$)/i.test(url.pathname)) return null;
      url.hash = "";
      const current = new URL(global.location.href);
      current.hash = "";
      return !allowCurrent && url.href === current.href ? null : url.href;
    } catch (_) { return null; }
  }

  function isHitTarget(element) {
    if (!actionable(element)) return false;
    const bounds = element.getBoundingClientRect();
    const hit = element.ownerDocument.elementFromPoint(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2);
    return !!hit && (hit === element || element.contains(hit));
  }

  function trackerSidebarStep(root, draft) {
    const menu = root.getElementById("grind-menu");
    if (!menu || !menu.closest("main") || !protocol.isGarmothTrackerUrl(global.location.href, false)) return null;
    const asides = all(menu, "aside");
    if (asides.length !== 1) return null;
    const aside = asides[0];
    const category = draft.target.activity === "grinding" ? "grinding" : "lifeskill";
    const categories = all(aside, "a[href]").filter((anchor) => {
      try {
        const url = new URL(anchor.getAttribute("href"), global.location.href);
        return protocol.isGarmothTrackerUrl(url.href, false) && !url.username && !url.password && /\/summary\/?$/.test(url.pathname)
          && ["grinding", "lifeskill", "scrolls", "dungeon"].every((name) => all(anchor, "button")
            .some((button) => individualNames(button).some((label) => label === name)));
      } catch (_) { return false; }
    }).flatMap((anchor) => all(anchor, "button").filter((button) => isHitTarget(button)
      && individualNames(button).some((name) => name === category)));
    const previous = global.__bslSessionNavigationStep;
    const currentStep = previous && previous.root === root && previous.draftId === draft.draftId
      && previous.deadline > Date.now() ? previous : null;
    if (categories.length === 1) {
      const control = categories[0];
      const selected = control.getAttribute("aria-pressed") ?? control.getAttribute("aria-selected");
      if (selected === "true") return null;
      if (["select_activity", "expand_spot_group"].includes(currentStep?.action) && currentStep.category === category) {
        if (currentStep.action === "select_activity" && Date.now() - currentStep.at < 250) return {state:"loading",message:"Loading the selected activity."};
        // Where the site exposes no selected attribute, remember only our own
        // explicit click within this draft/document/deadline; never infer colour.
        if (selected === null) return null;
      }
      return {state:"act",action:"select_activity",element:control,category,
        expectedUrl:renderedTrackerHref(control.closest("a[href]"), true),
        message:category === "lifeskill" ? "Opening Lifeskill spots." : "Opening Grinding spots."};
    }
    if (categories.length > 1) return {state:"blocked",message:"More than one activity control is visible. Open your tracker sidebar first."};
    const back = all(aside, "button,a,[role='button'],div,span").filter((element) => isHitTarget(element)
      && individualNames(element).some((name) => name === "back")
      && !all(element, "button,a,[role='button'],div,span").some((child) => individualNames(child).some((name) => name === "back")));
    if (back.length !== 1) {
      // Garmoth's desktop rail exposes its categories on pointer entry. This
      // event stays inside the app-owned browser; it never moves the OS cursor.
      const bounds = aside.getBoundingClientRect();
      const summary = all(aside, "a[href]").some(anchor =>
        renderedTrackerHref(anchor, true) && /\/summary\/?$/.test(new URL(anchor.href || anchor.getAttribute("href"), global.location.href).pathname)
        && individualNames(anchor).some(name => name === "summary"));
      if (bounds.width > 0 && bounds.width < 160 && summary) {
        if (currentStep?.action === "expand_tracker") return Date.now() - currentStep.at < 2000
          ? {state:"loading",message:"Opening the tracker sidebar."}
          : null;
        return {state:"act",action:"expand_tracker",element:aside,hover:true,expectedUrl:null,message:"Opening the tracker sidebar."};
      }
      return null;
    }
    if (currentStep?.action === "expand_tracker") return Date.now() - currentStep.at < 2000
      ? {state:"loading",message:"Opening the tracker sidebar."}
      : {state:"blocked",message:"The tracker sidebar did not expand. Open it in Garmoth and try again."};
    return {state:"act",action:"expand_tracker",element:back[0],expectedUrl:renderedTrackerHref(back[0].closest("a[href]"), true),message:"Opening the tracker sidebar."};
  }

  function trackerSpotGroupStep(root, draft) {
    // Observed Garmoth accordion: labelled cursor-pointer DIV followed by an
    // overflow-hidden DIV whose inline max-height is zero while closed. The
    // hidden anchor is used only to prove which sibling header may be opened;
    // navigation still requires the normal visible-link path afterward.
    const menu = root.getElementById("grind-menu");
    if (!draft.target.spotId || !menu || !menu.closest("main") || !protocol.isGarmothTrackerUrl(global.location.href, false)) return null;
    const asides = all(menu,"aside");
    if (asides.length !== 1) return null;
    const aside = asides[0];
    const wanted = normalizedText(draft.target.spotName);
    const matches = all(aside,"a[href]").map(link=>({link,url:renderedTrackerHref(link,false,false)}))
      .filter(({link,url})=>url && new URL(url).pathname.split("/").filter(Boolean).slice(-2).join("/") === "spot/" + String(draft.target.spotId)
        && [...individualNames(link),...all(link,"span,[data-spot-name]").flatMap(individualNames)].some(name=>name===wanted));
    if (new Set(matches.map(entry=>entry.url)).size !== 1) return null;
    const groups = [];
    for (const {link} of matches) {
      let panel = link.parentElement;
      for (let depth=0;panel && panel!==aside && depth<7;depth+=1,panel=panel.parentElement) {
        if (!panel.matches(".overflow-hidden") || panel.tagName!=="DIV") continue;
        const siblings = Array.from(panel.parentElement?.children || []);
        const header = siblings[siblings.indexOf(panel)-1];
        if (!header || header.tagName!=="DIV" || !header.matches(".cursor-pointer") || !actionable(header)
            || all(header,".uppercase").length!==1 || all(header,"a,button,input,[role='button']").length) break;
        const label = normalizedText(all(header,".uppercase")[0].textContent);
        if (!label || FORBIDDEN_ACTION.test(label)) break;
        groups.push({header,panel});
        break;
      }
    }
    const headers = [...new Set(groups.map(group=>group.header))];
    if (headers.length!==1) return null;
    const {header,panel} = groups[0];
    const previous = global.__bslSessionNavigationStep;
    const sameStep = previous?.root===root && previous.draftId===draft.draftId && previous.deadline>Date.now()
      && previous.action==="expand_spot_group" && previous.groupControl===header;
    const closed = /(?:^|;)\s*max-height\s*:\s*0(?:px)?\s*(?:;|$)/i.test(panel.getAttribute("style") || "");
    if (sameStep) {
      if (Date.now()-previous.at<500) return {state:"loading",message:"Opening the selected spot group."};
      return closed ? {state:"blocked",message:"The selected spot group did not expand. Open it in Garmoth and try again."} : null;
    }
    return closed ? {state:"act",action:"expand_spot_group",element:header,expectedUrl:null,message:"Opening the selected spot group."} : null;
  }

  function trackerNavigationStep(root,draft) {
    return trackerSidebarStep(root,draft) || trackerSpotGroupStep(root,draft);
  }

  function executeNavigationStep(root, rawDraft, action, options) {
    const assertActive = typeof options?.assertActive === "function" ? options.assertActive : () => {};
    assertActive();
    const draft = protocol.normalizeDraft(rawDraft);
    const decision = discoverPreparation(root, draft);
    const step = trackerNavigationStep(root, draft);
    if (decision.state !== "act" || decision.action !== action || step?.action !== action || !step.element)
      return {acted:false,message:"The tracker controls changed. Review the page and try again."};
    if ((step.expectedUrl ?? null) !== (options?.expectedUrl ?? null))
      return {acted:false,message:"The tracker destination changed. Review the page and try again."};
    const deadline = options?.deadline;
    if (!Number.isFinite(deadline) || deadline <= Date.now() || preparationActive)
      return {acted:false,message:"The navigation request expired or another preparation is running."};
    const previousGuard = assertPreparationActive;
    assertPreparationActive = assertActive;
    try {
      if (step.hover) {
        if (step.action !== "expand_tracker" || step.element.tagName !== "ASIDE" || !isVisible(step.element))
          return {acted:false,message:"The tracker sidebar changed. Try preparing again."};
        assertActive();
        step.element.dispatchEvent(new MouseEvent("mouseenter", {bubbles:false,view:global}));
        assertActive();
        step.element.dispatchEvent(new MouseEvent("mouseover", {bubbles:true,view:global}));
      } else safeClick(step.element, "tracker_navigation");
      assertActive();
      const previous = global.__bslSessionNavigationStep;
      const priorCategory = previous?.root===root && previous.draftId===draft.draftId && previous.deadline>Date.now() ? previous.category : undefined;
      global.__bslSessionNavigationStep = {root,draftId:draft.draftId,action,category:step.category ?? priorCategory,
        groupControl:action==="expand_spot_group"?step.element:undefined,at:Date.now(),deadline};
      return {acted:true,action,expectedUrl:step.expectedUrl};
    } finally { assertPreparationActive = previousGuard; }
  }

  function discoverPreparation(root, rawDraft) {
    const current = new URL(global.location.href);
    if (current.origin !== protocol.GARMOTH_ORIGIN || current.username || current.password) return { state: "blocked", message: "Open Garmoth before preparing." };
    const draft = protocol.normalizeDraft(rawDraft);
    if (root.readyState === "loading") return { state: "loading", message: "Garmoth is loading." };
    const editor = findSessionEditor(root);
    const existing = findEditor(root);
    if (editor || existing) {
      if (editor && protocol.isGarmothTrackerUrl(current.href, false) && canPrepareCurrentPage(root, draft.target)) return { state: "ready", message: "The session form is available." };
      return { state: visibleLogin(root) ? "login_required" : "blocked", message: "Review or close the current form before preparing this spot." };
    }
    if (visibleLogin(root)) return { state: "login_required", message: "Sign in to Garmoth first." };
    if (protocol.isGarmothTrackerUrl(current.href, false) &&
        (pageNamesExactSpot(root, draft.target) || routeNamesExactSpot(draft.target)) && canPrepareCurrentPage(root, draft.target)) return { state: "ready", message: "The selected spot is available." };
    // A full document can finish navigation before Vue has hydrated its spot
    // controls. Do not send a just-opened spot back to Summary in that gap.
    if (/\/spot\/[^/]+\/?$/.test(current.pathname) &&
        (!all(root, "h1").some(isVisible) || pageNamesExactSpot(root, draft.target) || routeNamesExactSpot(draft.target)))
      return {state:"loading",message:"Loading the selected spot's session controls."};
    const sidebarStep = trackerNavigationStep(root, draft);
    if (sidebarStep) {
      const {element,category,...decision} = sidebarStep;
      return decision;
    }
    const links = all(root, "a[href]").map((link) => ({link, url: renderedTrackerHref(link)})).filter((entry) => entry.url);
    const wanted = normalizedText(draft.target.spotName);
    const exact = links.filter(({link,url}) => [...individualNames(link), ...all(link, "h1,h2,h3,h4,span,[data-spot-name],img[alt]").flatMap(individualNames)]
      .some((name) => name === wanted) && (!draft.target.spotId ||
        new URL(url).pathname.split("/").filter(Boolean).slice(-2).join("/") === "spot/" + String(draft.target.spotId)));
    const exactUrls = [...new Set(exact.map((entry) => entry.url))];
    if (exactUrls.length === 1) return { state: "navigate", url: exactUrls[0], message: "Opening the selected spot." };
    if (exactUrls.length > 1) return { state: "blocked", message: "More than one tracker link matches this spot. Choose it in Garmoth first." };
    if (protocol.isGarmothTrackerUrl(current.href, false) && canPrepareCurrentPage(root, draft.target)) return { state: "ready", message: "The session form is available." };
    const personal = links.map((entry) => ({...entry, rank:Math.max(0, ...individualNames(entry.link).map((name) =>
      /^(?:my|personal) (?:grind )?tracker$/.test(name) ? 3 : /^(?:my |personal )?summary$/.test(name) ? 2 : name === "grind tracker" ? 1 : 0))}))
      .filter((entry) => entry.rank > 0 && new URL(entry.url).pathname.replace(/\/$/, "") !== protocol.GARMOTH_PATH_PREFIX);
    const highestRank = Math.max(0, ...personal.map((entry) => entry.rank));
    const personalUrls = [...new Set(personal.filter((entry) => entry.rank === highestRank).map((entry) => entry.url))];
    if (personalUrls.length === 1) return { state: "navigate", url: personalUrls[0], message: "Opening your tracker." };
    if (all(root, "[aria-busy='true'],[role='progressbar'],[data-loading='true'],.skeleton,.animate-pulse")
      .some(isVisible)) return { state: "loading", message: "Garmoth is loading its tracker." };
    // Garmoth can complete the document while its app shell is still empty.
    // No visible content is evidence only of loading, never of login or readiness.
    // The host's existing preparation deadline still bounds this read-only wait.
    if (protocol.isGarmothTrackerUrl(current.href, false) && root.readyState === "complete" && root.body
        && !normalizedText(root.body.innerText ?? root.body.textContent)
        && !all(root.body, "h1,h2,h3,h4,h5,h6,[role='heading'],a,button,input,select,textarea,form,table,"
          + "[role='button'],[role='checkbox'],[role='switch'],[role='combobox'],[role='alert'],[role='dialog'],"
          + "[aria-modal='true'],img,svg,canvas,video,iframe").some(isVisible))
      return {state:"loading",message:"Garmoth is loading its tracker."};
    return { state: "blocked", code: "no_matching_link", message: "Choose your tracker and the exact spot in Garmoth. No matching rendered link was found." };
  }

  function findOpenEditorButton(root) {
    if (!protocol.isGarmothTrackerUrl(global.location.href, false)) return null;
    const candidates = all(root, "button,a,[role='button']")
      .filter((element) => actionable(element) && !element.closest("[role='dialog'],[aria-modal='true']"))
      .map((element) => ({ element, names: individualNames(element) }))
      .filter((entry) => entry.names.some((name) => /^(\+\s*)?add( (new )?session)?$/.test(name)));
    const explicit = candidates.filter((entry) => entry.names.some((name) => /^(\+\s*)?add (new )?session$/.test(name)));
    if (explicit.length) return explicit.length === 1 ? explicit[0].element : null;
    const contextual = candidates.filter(({element}) => {
      if (element.getAttribute("aria-haspopup") === "dialog") return true;
      let group = element.parentElement;
      for (let depth = 0; group && group !== root.body && depth < 3; depth += 1, group = group.parentElement) {
        if (all(group, "h1,h2,h3,h4,h5,h6,[role='heading']")
          .some((heading) => /^(?:(?:my|grind) )?sessions$/.test(normalizedText(heading.textContent)))) return true;
      }
      return false;
    });
    if (contextual.length === 1) return contextual[0].element;
    // The live spot page uses its item heading and session-history table,
    // rather than a literal "Sessions" heading, beside its single Add button.
    if (contextual.length === 0 && candidates.length === 1 && /\/spot\/[^/]+\/?$/.test(global.location.pathname)
        && all(root, "h1").some(isVisible)) {
      const history = all(root, "table").filter(isVisible).some(table => {
        const headers = all(table, "thead th,thead td").map(cell => normalizedText(cell.textContent));
        return headers.includes("time ago") && headers.includes("agris") && headers.some(name => name === "silver/hr");
      });
      if (history) return candidates[0].element;
    }
    return null;
  }

  function waitFor(root, finder, timeoutMilliseconds) {
    const immediate = finder();
    if (immediate) {
      return Promise.resolve(immediate);
    }
    return new Promise((resolve, reject) => {
      let settled = false;
      const observer = new MutationObserver(() => {
        const result = finder();
        if (result && !settled) {
          settled = true;
          observer.disconnect();
          resolve(result);
        }
      });
      const observed = root.documentElement || root;
      observer.observe(observed, { childList: true, subtree: true, attributes: true });
      global.setTimeout(() => {
        if (!settled) {
          settled = true;
          observer.disconnect();
          reject(new protocol.ProtocolError("editor_not_found", "Garmoth's Add session panel did not open."));
        }
      }, timeoutMilliseconds);
    });
  }

  async function ensureEditor(root) {
    const existing = findSessionEditor(root);
    if (existing) {
      return existing;
    }
    if (findEditor(root)) throw new protocol.ProtocolError("session_not_ready", "Review or close the current form before preparing.");
    const opener = findOpenEditorButton(root);
    if (!opener) {
      throw new protocol.ProtocolError(
        "editor_not_found",
        "Garmoth's Add session control was not found. The page may have changed."
      );
    }
    safeClick(opener, "open_editor");
    return waitFor(root, () => findSessionEditor(root), 6_000);
  }

  function nativeValueSetter(control) {
    if (control instanceof HTMLInputElement) {
      return Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
    }
    if (control instanceof HTMLTextAreaElement) {
      return Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set;
    }
    if (control instanceof HTMLSelectElement) {
      return Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, "value")?.set;
    }
    return null;
  }

  function writeControl(control, value, optionalField, trackWholeField = true) {
    assertPreparationActive();
    if (!(control instanceof Element) || !actionable(control) || control.readOnly
        || control.matches("[type='submit'],[type='checkbox'],[type='radio'],[type='password'],[type='email'],button")) {
      throw new protocol.ProtocolError("unsafe_field", "The helper refused to write a non-field control.");
    }
    const textValue = String(value);
    if (control.isContentEditable) {
      control.textContent = textValue;
    } else {
      const setter = nativeValueSetter(control);
      if (setter) {
        setter.call(control, textValue);
      } else {
        control.value = textValue;
      }
    }
    assertPreparationActive();
    if (trackWholeField) {
      control.setAttribute(WRITTEN_ATTRIBUTE, "true");
      if (OPTIONAL_FIELDS.has(optionalField)) control.setAttribute(OPTIONAL_ATTRIBUTE, optionalField);
      else control.removeAttribute(OPTIONAL_ATTRIBUTE);
    }
    for (const eventName of ["input", "change", "blur"]) {
      assertPreparationActive();
      control.dispatchEvent(new Event(eventName, { bubbles: true }));
    }
    return String(control.isContentEditable ? control.textContent : control.value) === textValue
      && !control.validity?.badInput && !control.validity?.rangeOverflow
      && !control.validity?.rangeUnderflow && !control.validity?.stepMismatch;
  }

  function clearPreviouslyWritten(editor, session) {
    assertPreparationActive();
    for (const control of all(editor, "[" + WRITTEN_ATTRIBUTE + "='true']")) {
      assertPreparationActive();
      const optionalField = control.getAttribute(OPTIONAL_ATTRIBUTE);
      // Omission means leave the site's current choice alone, including a user
      // correction since our previous draft. Retain ownership for a later
      // explicit value; removed loot still follows the normal clearing path.
      if (OPTIONAL_FIELDS.has(optionalField) && session[optionalField] == null) continue;
      const descriptor = labelledText(control);
      if (control.matches("select,[role='combobox']") || /spot|monster zone|gathering spot/.test(descriptor)) {
        control.removeAttribute(WRITTEN_ATTRIBUTE);
        control.removeAttribute(OPTIONAL_ATTRIBUTE);
        continue;
      }
      try {
        writeControl(control, "");
      } catch (_) {
        assertPreparationActive();
        // A field removed by a live rerender does not block the next draft.
      }
      assertPreparationActive();
      control.removeAttribute(WRITTEN_ATTRIBUTE);
      control.removeAttribute(OPTIONAL_ATTRIBUTE);
    }
  }

  function phraseScore(text, aliases) {
    let best = 0;
    for (const alias of aliases.map(normalizedText)) {
      if (text === alias) {
        best = Math.max(best, 100);
      } else if (text.startsWith(alias + " ") || text.endsWith(" " + alias)) {
        best = Math.max(best, 80);
      } else if (text.includes(alias)) {
        best = Math.max(best, 50);
      }
    }
    return best;
  }

  function findField(scope, aliases, extraSelector) {
    if (!extraSelector) {
      const layout = sessionTableLayout(scope);
      const matches = layout?.fields.filter(field => phraseScore(field.label, aliases) > 0) || [];
      if (matches.length === 1) return matches[0].control;
    }
    const selector = extraSelector || EDITABLE_SELECTOR;
    return all(scope, selector)
      .filter((control) => isVisible(control) && !control.disabled)
      .map((control) => ({ control, score: phraseScore(labelledText(control), aliases) }))
      .filter((entry) => entry.score > 0)
      .sort((left, right) => right.score - left.score)[0]?.control || null;
  }

  function formatClock(totalSeconds) {
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    const base = String(hours).padStart(2, "0") + ":" + String(minutes).padStart(2, "0");
    return seconds ? base + ":" + String(seconds).padStart(2, "0") : base;
  }

  function fillDuration(editor, totalSeconds, warnings) {
    let displayedSeconds = totalSeconds;
    const result = accepted => ({accepted, seconds:displayedSeconds});
    const useWholeMinutes = () => {
      if (displayedSeconds % 60) {
        displayedSeconds = Math.floor(displayedSeconds / 60) * 60;
        warnings.push("duration_rounded_to_minutes");
      }
    };
    const fractionalMinutes = control => control.getAttribute("step") === "any"
      || Number(control.getAttribute("step")) > 0 && Number(control.getAttribute("step")) < 1;
    const hoursField = findField(editor, ["hours", "hour", "duration hours", "time hours"]);
    const minutesField = findField(editor, ["minutes", "minute", "duration minutes", "time minutes"]);
    const secondsField = findField(editor, ["seconds", "second", "duration seconds", "time seconds"]);
    if (hoursField && minutesField && hoursField !== minutesField) {
      const separateSeconds = secondsField && secondsField !== hoursField && secondsField !== minutesField;
      if (!separateSeconds && !fractionalMinutes(minutesField)) useWholeMinutes();
      if (!displayedSeconds) return result(false);
      const hours = Math.floor(displayedSeconds / 3600);
      const minutes = separateSeconds ? Math.floor((displayedSeconds % 3600) / 60) : (displayedSeconds % 3600) / 60;
      return result(writeControl(hoursField, hours) && writeControl(minutesField, minutes)
        && (!separateSeconds || writeControl(secondsField, displayedSeconds % 60)));
    }
    if (secondsField && !hoursField && !minutesField) return result(writeControl(secondsField, displayedSeconds));
    const durationField = findField(editor, ["duration", "session time", "time"]) || minutesField;
    if (!durationField) {
      warnings.push("duration_field_not_found");
      return result(false);
    }
    const description = labelledText(durationField);
    if (durationField.getAttribute("type") === "time") {
      const step = durationField.getAttribute("step");
      if (step !== "any" && (step === null || Number(step) >= 60)) useWholeMinutes();
      return result(displayedSeconds > 0 && writeControl(durationField, formatClock(displayedSeconds)));
    } else if (description.includes("second")) {
      return result(writeControl(durationField, displayedSeconds));
    } else if (description.includes("hour") && !description.includes("minute")) {
      return result(writeControl(durationField, displayedSeconds / 3600));
    } else if (durationField === minutesField || durationField instanceof HTMLInputElement && durationField.type === "number") {
      if (!fractionalMinutes(durationField)) useWholeMinutes();
      return result(displayedSeconds > 0 && writeControl(durationField, displayedSeconds / 60));
    } else {
      if (/^h{1,2}:m{2}$/i.test((durationField.getAttribute("placeholder") || "").trim())) useWholeMinutes();
      return result(displayedSeconds > 0 && writeControl(durationField, formatClock(displayedSeconds)));
    }
  }

  function fillOptionalNumber(editor, value, aliases, warning, warnings, optionalField) {
    if (value === null || value === undefined) {
      return;
    }
    const control = findField(editor, aliases);
    if (!control) {
      warnings.push(warning);
      return;
    }
    writeControl(control, value, optionalField);
  }

  function durationMatches(editor, totalSeconds) {
    const hours = findField(editor, ["hours", "hour", "duration hours", "time hours"]);
    const minutes = findField(editor, ["minutes", "minute", "duration minutes", "time minutes"]);
    const seconds = findField(editor, ["seconds", "second", "duration seconds", "time seconds"]);
    const number = control => {
      const value = String(control?.value ?? control?.textContent ?? "").trim();
      return value ? Number(value) : NaN;
    };
    if (hours && minutes && hours !== minutes) return Math.abs(number(hours) * 3600 + number(minutes) * 60
      + (seconds && seconds !== hours && seconds !== minutes ? number(seconds) : 0) - totalSeconds) < 0.001;
    if (seconds && !hours && !minutes) return number(seconds) === totalSeconds;
    const field = findField(editor, ["duration", "session time", "time"]) || minutes;
    if (!field) return false;
    const label = labelledText(field);
    if (field.getAttribute("type") === "time" || field !== minutes && !(field instanceof HTMLInputElement && field.type === "number") && !/second|hour/.test(label)) {
      const clock = String(field.value ?? field.textContent ?? "").trim().match(/^(\d+):(\d{2})(?::(\d{2}))?$/);
      return !!clock && Number(clock[1]) * 3600 + Number(clock[2]) * 60 + Number(clock[3] || 0) === totalSeconds;
    }
    const factor = label.includes("second") ? 1 : label.includes("hour") && !label.includes("minute") ? 3600 : 60;
    return Math.abs(number(field) * factor - totalSeconds) < 0.001;
  }

  function explicitFieldLabels(control) {
    return [control.getAttribute("aria-label"), control.getAttribute("title"),
      control.getAttribute("placeholder"), control.getAttribute("name"), control.getAttribute("data-field"),
      ...(control.labels ? Array.from(control.labels, (label) => label.textContent) : []),
      ...(control.getAttribute("aria-labelledby") || "").split(/\s+/)
        .map((id) => control.ownerDocument.getElementById(id)?.textContent),
      control.closest("label")?.textContent,
      control.parentElement?.textContent.length < 100 ? control.parentElement.textContent : null
    ].map((value) => normalizedText(value).replace(/[_-]+/g, " ").replace(/\s*\(?%\)?\s*$/, "").replace(/\s*:\s*$/, "").trim());
  }

  function explicitNumberControl(editor, aliases) {
    const matches = all(editor, "input:not([type='hidden']),[role='spinbutton']")
      .filter((control) => actionable(control) && !control.readOnly &&
        (!control.getAttribute("type") || /^(?:number|text|tel)$/.test(control.getAttribute("type"))) &&
        explicitFieldLabels(control).some((label) => aliases.includes(label)));
    if (!matches.length && sessionTableLayout(editor)) {
      // The live form labels these two inputs with a P above nested field
      // wrappers, not a linked LABEL. Never inspect the surrounding buff grid.
      for (const label of all(editor, "p")) {
        if (!aliases.includes(normalizedText(label.textContent))) continue;
        const container = label.parentElement;
        const controls = all(container, "input").filter(control => actionable(control) && !control.readOnly
          && /^(?:number|text|tel)$/.test(control.getAttribute("type") || "text"));
        if (controls.length === 1 && !matches.includes(controls[0])) matches.push(controls[0]);
      }
    }
    return matches.length === 1 ? matches[0] : null;
  }

  function fillExplicitNumber(editor, value, aliases, warning, warnings, optionalField) {
    if (value === null || value === undefined) return;
    const control = explicitNumberControl(editor, aliases);
    if (!control) { warnings.push(warning); return; }
    if (!writeControl(control, value, optionalField)) warnings.push(warning.replace("_not_found", "_not_accepted"));
  }

  function verifySessionDetails(editor, session, warnings) {
    const warn = field => {
      if (!warnings.includes(field + "_not_found") && !warnings.includes(field + "_not_accepted"))
        warnings.push(field + "_not_accepted");
    };
    if (session.agrisActive != null && toggleState(agrisToggle(editor)) !== session.agrisActive) warn("agris_toggle");
    for (const [field, aliases, warning] of [
      ["additionalDropRate", ["additional drop rate", "additional item drop rate"], "additional_drop_rate_field"],
      ["additionalDropAmount", ["additional drop amount", "additional item drop amount"], "additional_drop_amount_field"]
    ]) {
      if (session[field] == null) continue;
      const control = explicitNumberControl(editor, aliases);
      const value = String(control?.value ?? control?.textContent ?? "").trim();
      if (!value || !Number.isFinite(Number(value)) || Number(value) !== session[field]
          || control?.validity?.badInput || control?.validity?.rangeOverflow
          || control?.validity?.rangeUnderflow || control?.validity?.stepMismatch) warn(warning);
    }
  }

  function agrisToggle(editor) {
    const matches = all(editor, "input[type='checkbox'],[role='checkbox'],[role='switch'],button[aria-pressed]")
      .filter((control) => actionable(control) && explicitFieldLabels(control)
        .some((label) => label === "agris" || label === "agris fever"));
    if (matches.length) return matches.length === 1 ? matches[0] : null;
    const headers = sessionTableLayout(editor)?.fields.filter(field => field.label === "agris"
      && field.header.matches(".cursor-pointer") && field.header.matches(".v-popper--has-tooltip")) || [];
    return headers.length === 1 ? headers[0].header : null;
  }

  function tableAgrisState(header) {
    if (header?.tagName !== "TH" || normalizedText(header.textContent) !== "agris") return null;
    const icons = all(header, "svg");
    if (icons.length !== 1) return null;
    const paths = all(icons[0], "path");
    if (paths.length !== 1) return null;
    const path = paths[0].getAttribute("d");
    const viewBox = icons[0].getAttribute("viewBox");
    // Observed before/after toggling Garmoth's Used Agris row. These two
    // shapes identify state; colour and the numeric points input do not.
    if (viewBox === "0 0 384 512" && path === "M342.6 150.6c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0L192 210.7L86.6 105.4c-12.5-12.5-32.8-12.5-45.3 0s-12.5 32.8 0 45.3L146.7 256L41.4 361.4c-12.5 12.5-12.5 32.8 0 45.3s32.8 12.5 45.3 0L192 301.3l105.4 105.3c12.5 12.5 32.8 12.5 45.3 0s12.5-32.8 0-45.3L237.3 256z") return false;
    if (viewBox === "0 0 448 512" && path === "M438.6 105.4c12.5 12.5 12.5 32.8 0 45.3l-256 256c-12.5 12.5-32.8 12.5-45.3 0l-128-128c-12.5-12.5-12.5-32.8 0-45.3s32.8-12.5 45.3 0L160 338.7l233.4-233.3c12.5-12.5 32.8-12.5 45.3 0z") return true;
    return null;
  }

  function toggleState(control) {
    if (!control) return null;
    if (control.tagName === "TH") return tableAgrisState(control);
    if (control instanceof HTMLInputElement && control.type === "checkbox")
      return control.indeterminate ? null : control.checked === true;
    const state = control.getAttribute(control.getAttribute("aria-pressed") !== null ? "aria-pressed" : "aria-checked");
    return state === "true" ? true : state === "false" ? false : null;
  }

  async function fillAgrisToggle(editor, root, value, warnings, target) {
    if (value === null || value === undefined) return;
    let control = agrisToggle(editor);
    let current = toggleState(control);
    // The table can mount before Iconify supplies this header's state glyph.
    // Wait only for an already identified Agris header, never infer its value.
    for (let attempt = 0; current === null && control?.tagName === "TH" && attempt < 30; attempt += 1) {
      await delay(50);
      assertPreparationActive();
      const refreshed = findSessionEditor(root);
      if (!refreshed || !verifySelectedSpot(refreshed, root, target))
        throw new protocol.ProtocolError("spot_not_selected", "The session spot changed. Review the form before preparing again.");
      control = agrisToggle(refreshed);
      current = toggleState(control);
    }
    if (current === null) { warnings.push("agris_toggle_not_found"); return; }
    if (current === value) return;
    safeClick(control, "set_agris");
    await delay(45);
    assertPreparationActive();
    const refreshed = findSessionEditor(root);
    if (!refreshed || toggleState(agrisToggle(refreshed)) !== value) warnings.push("agris_toggle_not_accepted");
  }

  function optionMatches(option, target) {
    const text = normalizedText(option.textContent || option.label);
    const requestedName = normalizedText(target.spotName);
    return (target.spotId && String(option.value) === String(target.spotId))
      || text === requestedName;
  }

  function urlContainsDelimitedIdentifier(urlValue, identifier) {
    try {
      const decoded = decodeURIComponent(new URL(urlValue, global.location.href).href);
      const escaped = String(identifier).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp("(^|[^a-z0-9])" + escaped + "([^a-z0-9]|$)", "i").test(decoded);
    } catch (_) {
      return false;
    }
  }

  function pageNamesExactSpot(root, target) {
    const requestedName = normalizedText(target.spotName);
    return all(root, "h1,[data-spot-name]")
      .some((element) => normalizedText(element.textContent) === requestedName);
  }

  function routeNamesExactSpot(target) {
    if (!target.spotId) {
      return false;
    }
    const segments = global.location.pathname.split("/").filter(Boolean);
    const spotIndex = segments.lastIndexOf("spot");
    return spotIndex >= 0 && segments[spotIndex + 1] === String(target.spotId);
  }

  function customControlNamesExactSpot(control, target) {
    const requestedName = normalizedText(target.spotName);
    return individualNames(control).some((name) => {
      return name === requestedName
        || name === "spot " + requestedName
        || name === "zone " + requestedName
        || name === "monster zone " + requestedName
        || name === "gathering spot " + requestedName;
    });
  }

  function verifySelectedSpot(editor, root, target) {
    const select = findField(editor, ["spot", "monster zone", "gathering spot", "zone"], "select");
    if (select) {
      return select.selectedIndex >= 0 && optionMatches(select.options[select.selectedIndex], target);
    }
    const customControls = all(editor, "[role='combobox'],button[aria-haspopup='listbox']")
      .filter((element) => isVisible(element) && !element.disabled)
      .map((control) => ({
        control,
        score: phraseScore(labelledText(control), ["spot", "monster zone", "gathering spot", "zone"])
      }))
      .filter((entry) => entry.score > 0);
    if (customControls.length > 0) {
      return customControls.some((entry) => customControlNamesExactSpot(entry.control, target));
    }
    return pageNamesExactSpot(root, target) || routeNamesExactSpot(target);
  }

  async function selectSpot(editor, root, target) {
    if (verifySelectedSpot(editor, root, target)) {
      return false;
    }
    const select = findField(editor, ["spot", "monster zone", "gathering spot", "zone"], "select");
    if (select) {
      const option = Array.from(select.options).find((entry) => optionMatches(entry, target));
      if (option) {
        if (select.value === option.value) {
          return false;
        }
        writeControl(select, option.value);
        assertPreparationActive();
        select.removeAttribute(WRITTEN_ATTRIBUTE);
        return true;
      }
    }

    const customControls = all(editor, "[role='combobox'],button[aria-haspopup='listbox']")
      .filter((element) => isVisible(element) && !element.disabled);
    const custom = customControls
      .map((control) => ({
        control,
        score: phraseScore(labelledText(control), ["spot", "monster zone", "gathering spot", "zone"])
      }))
      .sort((left, right) => right.score - left.score)[0];
    if (custom && custom.score > 0) {
      if (customControlNamesExactSpot(custom.control, target)) {
        return false;
      }
      safeClick(custom.control, "open_spot_picker");
      try {
        const option = await waitFor(root, () => all(root, "[role='option'],[data-option]")
          .filter(isVisible)
          .find((entry) => optionMatches(entry, target)), 3_000);
        safeClick(option, "select_spot", target.spotName);
        return true;
      } catch (_) {
        // The exact spot stays unchanged and is reported below.
      }
    }
    return false;

  }

  function isQuantityControl(control) {
    if (!isVisible(control) || control.disabled) {
      return false;
    }
    if (control.matches("select,textarea") || control.isContentEditable) {
      return false;
    }
    const type = normalizedText(control.getAttribute("type"));
    if (type && !["number", "text", "tel"].includes(type)) {
      return false;
    }
    const descriptor = labelledText(control);
    return !/duration|time|hour|minute|mastery|energy|agris|drop rate|drop amount|search|filter/.test(descriptor);
  }

  function directItemMarkers(editor, item) {
    const layout = sessionTableLayout(editor);
    if (layout) {
      const id = numericItemIdentity(item.itemId);
      const name = normalizedText(item.name);
      return layout.items.filter(entry => {
        const dataMatch = id && entry.dataIds.includes(id);
        const nameMatch = entry.names.includes(name);
        if (entry.dataIds.some(value => value !== id) || entry.names.some(value => value !== name)) return false;
        if (dataMatch || nameMatch) return true;
        // An icon filename identifies artwork, not necessarily the item. The
        // live table has shared artwork; its tooltip is authoritative instead.
        return !entry.header.matches(".v-popper--has-tooltip") && id && entry.ids.includes(id);
      })
        .map(entry => entry.header);
    }
    const markers = new Set();
    if (item.itemId) {
      for (const element of all(editor, "[data-item-id],[data-id],[data-item-key],[data-item]")) {
        const values = ["data-item-id", "data-id", "data-item-key", "data-item"]
          .map((name) => element.getAttribute(name));
        if (values.some((value) => value === item.itemId || value === item.itemId + ":" + item.subKey)) {
          markers.add(element);
        }
      }
      for (const image of all(editor, "img[src]")) {
        if (urlContainsDelimitedIdentifier(image.src, item.itemId)) {
          markers.add(image);
        }
      }
    }

    const wantedName = normalizedText(item.name);
    for (const element of all(editor, "[alt],[title],[aria-label],[data-name]")) {
      if (individualNames(element).some((name) => name === wantedName)) {
        markers.add(element);
      }
    }
    const walker = editor.ownerDocument.createTreeWalker(editor, NodeFilter.SHOW_ELEMENT);
    let node = walker.nextNode();
    while (node) {
      if (node.children.length === 0 && normalizedText(node.textContent) === wantedName) {
        markers.add(node);
      }
      node = walker.nextNode();
    }
    return Array.from(markers).filter(isVisible);
  }

  function nearestQuantityControl(marker, editor, item, verifiedTooltip = false) {
    const layout = sessionTableLayout(editor);
    if (layout) {
      const matching = layout.items.filter(entry => entry.header === marker || entry.header.contains(marker));
      if (matching.length !== 1) return null;
      const id = numericItemIdentity(item.itemId);
      if (!verifiedTooltip && id && matching[0].ids.includes(id) && layout.items.filter(entry => entry.ids.includes(id)).length !== 1) return null;
      return matching[0].control;
    }
    let current = marker;
    const wantedName = normalizedText(item.name);
    for (let depth = 0; current && current !== editor && depth < 8; depth += 1) {
      const controls = all(current, EDITABLE_SELECTOR).filter(isQuantityControl);
      if (controls.length === 1) {
        return controls[0];
      }
      if (controls.length > 1 && controls.length <= 8) {
        const ranked = controls
          .map((control) => {
            const descriptor = labelledText(control);
            let score = phraseScore(descriptor, ["quantity", "count", "amount", "total"]);
            if (descriptor.includes(wantedName)) {
              score += 100;
            }
            if (item.itemId && descriptor.includes(item.itemId)) {
              score += 100;
            }
            return { control, score };
          })
          .sort((left, right) => right.score - left.score);
        if (ranked[0].score > 0) {
          return ranked[0].control;
        }
      }
      current = current.parentElement;
    }
    return null;
  }

  function visibleTooltips(documentRoot) {
    return all(documentRoot, "[role='tooltip'],.tooltip,.tippy-box,[data-tooltip-content],.v-popper__popper")
      .filter(element => isVisible(element) && element.getAttribute("aria-hidden") !== "true");
  }

  function visibleTooltipTexts(documentRoot) {
    return visibleTooltips(documentRoot).map(element => normalizedText(element.textContent))
      .filter(Boolean);
  }

  function hasNearbyQuantityControl(marker, editor) {
    const layout = sessionTableLayout(editor);
    if (layout) return layout.items.some(entry => entry.header === marker || entry.header.contains(marker));
    let current = marker;
    for (let depth = 0; current && current !== editor && depth < 7; depth += 1) {
      const controls = all(current, EDITABLE_SELECTOR).filter(isQuantityControl);
      if (controls.length > 0 && controls.length <= 8) {
        return true;
      }
      current = current.parentElement;
    }
    return false;
  }

  async function readTooltipAfterHover(candidate, documentRoot) {
    assertPreparationActive();
    const before = new Map(visibleTooltips(documentRoot).map(element => [element,normalizedText(element.textContent)]));
    const changedTexts = () => visibleTooltips(documentRoot)
      .filter(element => before.get(element) !== normalizedText(element.textContent))
      .map(element => normalizedText(element.textContent)).filter(Boolean);
    let observer = null;
    const mutation = new Promise((resolve) => {
      observer = new MutationObserver(() => {
        const current = changedTexts();
        if (current.length > 0) {
          resolve(current);
        }
      });
      observer.observe(documentRoot.body || documentRoot.documentElement, {
        childList: true,
        subtree: true,
        attributes: true
      });
    });
    try {
      candidate.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
      assertPreparationActive();
      candidate.dispatchEvent(new MouseEvent("mouseenter", { bubbles: false }));
      const tooltipText = await Promise.race([
        mutation,
        delay(candidate.matches(".v-popper--has-tooltip") ? 300 : 45).then(changedTexts)
      ]);
      assertPreparationActive();
      candidate.dispatchEvent(new MouseEvent("mouseout", { bubbles: true }));
      assertPreparationActive();
      candidate.dispatchEvent(new MouseEvent("mouseleave", { bubbles: false }));
      return tooltipText;
    } finally {
      observer.disconnect();
    }
  }

  async function tooltipMarkers(editor, wantedItems) {
    const found = new Map();
    const ambiguous = new Set();
    const layout = sessionTableLayout(editor);
    const candidates = (layout ? layout.items.map(entry => entry.header) : all(editor, "img,[role='img'],[data-tooltip],[aria-describedby]"))
      .filter((element) => isVisible(element) && hasNearbyQuantityControl(element, editor))
      .slice(0, 96);
    for (const candidate of candidates) {
      const tooltipTexts = await readTooltipAfterHover(candidate, editor.ownerDocument);
      for (const entry of wantedItems) {
        const wantedName = normalizedText(entry.item.name);
        const tableEntry = layout?.items.find(item => item.header === candidate);
        if (tableEntry && (tableEntry.dataIds.some(id => id !== numericItemIdentity(entry.item.itemId))
            || tableEntry.names.some(name => name !== wantedName))) continue;
        const exactTooltip = tooltipTexts.some(text => text === wantedName || !layout && text.startsWith(wantedName + " "));
        if (exactTooltip) {
          if (layout && found.has(entry.index) && found.get(entry.index) !== candidate) {
            found.delete(entry.index);
            ambiguous.add(entry.index);
          } else if (!ambiguous.has(entry.index)) found.set(entry.index, candidate);
        }
      }
      if (!layout && found.size === wantedItems.length) {
        break;
      }
    }
    return found;
  }

  async function fillItems(editor, root, items, skipUnsupported) {
    const matched = [];
    const skipped = [];
    const unresolved = [];
    const controlsByIndex = new Map();
    const tableBindings = new Map();
    const usedControls = new Set();

    items.forEach((item, index) => {
      const markers = directItemMarkers(editor, item);
      const marker = markers.find(candidate => {
        const control = nearestQuantityControl(candidate,editor,item);
        return control && !usedControls.has(control);
      });
      const control = marker ? nearestQuantityControl(marker,editor,item) : null;
      if (control) {
        controlsByIndex.set(index, control);
        const binding = tableItemBinding(editor,marker,control);
        if (binding) tableBindings.set(index,binding);
        usedControls.add(control);
      } else {
        unresolved.push({ item, index });
      }
    });

    if (unresolved.length > 0) {
      const tooltipMatches = await tooltipMarkers(editor, unresolved);
      for (const entry of unresolved) {
        const marker = tooltipMatches.get(entry.index);
        const control = marker ? nearestQuantityControl(marker, editor, entry.item, true) : null;
        if (control && !usedControls.has(control)) {
          controlsByIndex.set(entry.index, control);
          const binding = tableItemBinding(editor,marker,control);
          if (binding) tableBindings.set(entry.index,binding);
          usedControls.add(control);
        }
      }
    }

    const written = [];
    items.forEach((item, index) => {
      const identity = { index, itemId: item.itemId, subKey: item.subKey };
      const control = controlsByIndex.get(index);
      if (!control) {
        skipped.push({ ...identity, reason: "item_not_found" });
        return;
      }
      writeControl(control, item.quantity);
      written.push({ item, identity, control });
    });

    if (written.length > 0) {
      await delay(45);
    }
    const readbackEditor = findSessionEditor(root) || editor;
    for (const entry of written) {
      let control = entry.control;
      if (!control.isConnected) {
        const markers = directItemMarkers(readbackEditor, entry.item);
        control = markers
          .map((marker) => nearestQuantityControl(marker, readbackEditor, entry.item))
          .find(Boolean);
      }
      const compactValue = control
        ? String(control.value ?? control.textContent ?? "").replace(/[\s,._]/g, "")
        : "";
      if (compactValue === String(entry.item.quantity)) {
        matched.push(entry.identity);
      } else {
        skipped.push({ ...entry.identity, reason: "value_not_accepted" });
      }
    }

    if (!skipUnsupported && skipped.length > 0) {
      throw new protocol.ProtocolError("unsupported_items", "One or more items are not available for this Garmoth spot.");
    }
    return { matched, skipped, tableBindings };
  }

  function tableItemBinding(editor, marker, control) {
    const layout = sessionTableLayout(editor);
    const entries = layout?.items.filter(entry => entry.header === marker || entry.header.contains(marker)) || [];
    if (entries.length !== 1 || entries[0].control !== control) return null;
    const entry = entries[0];
    const fingerprint = JSON.stringify([entry.dataIds,entry.names,entry.ids,entry.header.textContent,
      entry.images.map(image => [image.src,image.currentSrc,image.getAttribute("alt"),image.getAttribute("title"),image.getAttribute("aria-label")])]);
    return {header:entry.header,control,fingerprint};
  }

  async function prepareDraftIn(root, rawDraft, options) {
    if (preparationActive) {
      throw new protocol.ProtocolError("preparation_busy", "A session is already being prepared.");
    }
    preparationActive = true;
    assertPreparationActive = typeof options?.assertActive === "function"
      ? options.assertActive : () => {};
    try {
      assertPreparationActive();
      return await prepareActiveDraft(root, rawDraft, options);
    } finally {
      preparationActive = false;
      assertPreparationActive = () => {};
    }
  }

  function notesPanel(editor) {
    const panels = all(editor, "span").filter(span => normalizedText(span.textContent) === "notes")
      .map(span => ({header:span.parentElement,panel:span.parentElement?.parentElement}))
      .filter(({header,panel}) => header?.tagName === "DIV" && header.matches(".cursor-pointer")
        && normalizedText(header.textContent) === "notes" && panel?.tagName === "DIV"
        && panel.matches(".overflow-hidden") && panel.children[0] === header
        && !panel.closest("table") && !all(header,"a,button,input,textarea,[contenteditable='true']").length);
    return panels.length === 1 ? panels[0] : null;
  }

  function notesControl(panel) {
    if (!panel) return null;
    const controls = all(panel, EDITABLE_SELECTOR);
    return controls.length === 1 && controls[0].tagName === "TEXTAREA"
      && controls[0].getAttribute("placeholder") === "Notes" && actionable(controls[0]) && !controls[0].readOnly
      ? controls[0] : null;
  }

  async function fillUnsupportedNotes(root, editor, draft, itemResult, warnings) {
    const empty = {notesVerified:[],notesStatus:"not_needed"};
    const fail = code => { if (!warnings.includes(code)) warnings.push(code); return {...empty,notesStatus:"failed"}; };
    const entries = itemResult.skipped.filter(item => item.reason === "item_not_found").map(item => {
      const source = draft.session.items[item.index];
      return {index:item.index,itemId:source.itemId,subKey:source.subKey,name:source.name,quantity:source.quantity};
    });
    // Ownership is session-editor-local and contains only our generated block.
    // A persisted or copied marker is never sufficient permission to replace it.
    if (!(global.__bslSessionNotesOwners instanceof WeakMap)) global.__bslSessionNotesOwners = new WeakMap();
    const owners = global.__bslSessionNotesOwners;
    const key = String(draft.target.spotId || "") + "\n" + normalizedText(draft.target.spotName);
    const previous = owners.get(editor);
    const owner = previous?.key === key ? previous : null;
    if (!entries.length && !owner) return empty;
    if (entries.some(item => item.name.includes(NOTES_START) || item.name.includes(NOTES_END))) return fail("unsupported_notes_conflict");
    try {
      protocol.assertMessageSize({draftId:draft.draftId,matched:itemResult.matched,skipped:itemResult.skipped,
        notesVerified:entries,notesStatus:"verified",warnings});
    } catch (_) { return fail("unsupported_notes_too_long"); }

    let currentEditor = editor;
    let found = notesPanel(currentEditor);
    if (!found) return fail("unsupported_notes_not_found");
    let control = notesControl(found.panel);
    if (!control && found.panel.children.length === 1 && !all(found.panel,EDITABLE_SELECTOR).length)
      safeClick(found.header,"open_notes");
    for (let attempt=0; !control && attempt<30; attempt+=1) {
      await delay(50);
      assertPreparationActive();
      currentEditor = findSessionEditor(root);
      if (!currentEditor || !verifySelectedSpot(currentEditor,root,draft.target))
        throw new protocol.ProtocolError("spot_not_selected","The session spot changed. Review the form before preparing again.");
      found = notesPanel(currentEditor);
      if (!found) return fail("unsupported_notes_not_found");
      control = notesControl(found.panel);
    }
    if (!control) return fail("unsupported_notes_not_found");
    const current = String(control.value);
    const occurrences = (text,part) => text.split(part).length - 1;
    let before = current, after = "", leading = current ? current.endsWith("\n") ? "\n" : "\n\n" : "";
    if (owner) {
      if (occurrences(current,owner.block) !== 1 || occurrences(current,NOTES_START) !== 1 || occurrences(current,NOTES_END) !== 1)
        return fail("unsupported_notes_conflict");
      const index = current.indexOf(owner.block);
      before = current.slice(0,index); after = current.slice(index+owner.block.length); leading = owner.leading;
    } else if (current.includes(NOTES_START) || current.includes(NOTES_END)) return fail("unsupported_notes_conflict");
    const block = entries.length ? leading + NOTES_START + "\n"
      + entries.map(item => item.name.replace(/\s+/g," ").trim() + " × " + String(item.quantity)).join("\n")
      + "\n" + NOTES_END + "\n" : "";
    const next = before + block + after;
    const maximum = Number(control.getAttribute("maxlength") ?? -1);
    if (next.length > 65536 || maximum >= 0 && next.length > maximum) return fail("unsupported_notes_too_long");
    if (next !== current) {
      // Do not mark the whole Notes field for the next prepare's generic cleanup.
      if (!writeControl(control,next,undefined,false)) return fail("unsupported_notes_not_accepted");
      await delay(45);
      assertPreparationActive();
      currentEditor = findSessionEditor(root);
      if (!currentEditor || !verifySelectedSpot(currentEditor,root,draft.target))
        throw new protocol.ProtocolError("spot_not_selected","The session spot changed. Review the form before preparing again.");
      control = notesControl(notesPanel(currentEditor)?.panel);
      if (!control || String(control.value) !== next) return fail("unsupported_notes_not_accepted");
    }
    if (block) owners.set(currentEditor,{key,block,leading});
    else owners.delete(currentEditor);
    return {notesVerified:entries,notesStatus:"verified"};
  }

  async function verifyMatchedItemsAfterNotes(root, editor, items, itemResult, warnings) {
    const controls = new Map(), used = new Set(), unresolved = [];
    for (const identity of itemResult.matched) {
      assertPreparationActive();
      const item = items[identity.index];
      let control = directItemMarkers(editor,item)
        .filter(marker => !marker.closest("select,[role='combobox'],[role='listbox']"))
        .map(marker => nearestQuantityControl(marker,editor,item))
        .find(candidate => candidate && !used.has(candidate));
      if (!control) {
        // Reuse this operation's already-proven tooltip identity only while its
        // exact table nodes, logical mapping and artwork/labels remain intact.
        // A remount or changed identity must resolve afresh, never be guessed.
        const previous = itemResult.tableBindings.get(identity.index);
        const current = previous?.header.isConnected && previous.control.isConnected
          ? tableItemBinding(editor,previous.header,previous.control) : null;
        if (current && current.fingerprint === previous.fingerprint && !used.has(current.control)) control = current.control;
      }
      if (control) { controls.set(identity.index,control); used.add(control); }
      else unresolved.push({index:identity.index,item});
    }
    if (unresolved.length) {
      const markers = await tooltipMarkers(editor,unresolved);
      for (const entry of unresolved) {
        const marker = markers.get(entry.index);
        const control = marker ? nearestQuantityControl(marker,editor,entry.item,true) : null;
        if (control && !used.has(control)) { controls.set(entry.index,control); used.add(control); }
      }
    }
    assertPreparationActive();
    const currentEditor = findSessionEditor(root);
    const matched = [];
    for (const identity of itemResult.matched) {
      const control = controls.get(identity.index);
      const value = control?.isConnected && currentEditor?.contains(control)
        ? String(control.value ?? control.textContent ?? "").replace(/[\s,._]/g,"") : "";
      if (value === String(items[identity.index].quantity)) matched.push(identity);
      else itemResult.skipped.push({...identity,reason:"value_not_accepted"});
    }
    if (matched.length !== itemResult.matched.length) warnings.push("item_values_not_accepted");
    itemResult.matched = matched;
    itemResult.skipped.sort((left,right) => left.index-right.index);
  }

  async function prepareActiveDraft(root, rawDraft, options) {
    const settings = options || {};
    if (!settings.skipPageGuard) {
      assertTrackerPage();
    }
    const draft = protocol.normalizeDraft(rawDraft);
    let editor = await ensureEditor(root);

    const warnings = [];
    const spotChanged = await selectSpot(editor, root, draft.target);
    if (spotChanged) {
      await delay(60);
    } else {
      await Promise.resolve();
    }
    editor = findSessionEditor(root)
      || (editor.isConnected && isSessionEditor(editor) ? editor : await waitFor(root, () => findSessionEditor(root), 2_000));
    if (!verifySelectedSpot(editor, root, draft.target)) {
      throw new protocol.ProtocolError(
        "spot_not_selected",
        "The exact Garmoth spot could not be selected. No session fields were changed."
      );
    }
    clearPreviouslyWritten(editor, draft.session);
    const durationResult = fillDuration(editor, draft.session.durationSeconds, warnings);
    if (!durationResult.accepted) {
      if (!warnings.length) warnings.push("duration_value_not_accepted");
      return { ok: false, code: "duration_not_prepared", message: "The session duration could not be entered. Review the form before saving.",
        draftId: draft.draftId, matched: [], skipped: draft.session.items.map((item, index) => ({index, itemId:item.itemId, subKey:item.subKey, reason:"duration_not_prepared"})), warnings };
    }
    fillOptionalNumber(editor, draft.session.mastery, ["mastery", "gathering mastery"], "mastery_field_not_found", warnings, "mastery");
    fillOptionalNumber(editor, draft.session.energySpent, ["energy", "energy spent"], "energy_field_not_found", warnings, "energySpent");
    fillExplicitNumber(editor, draft.session.agrisUsed, ["agris used", "agris consumed", "agris points", "agris points used", "agris fever used"], "agris_field_not_found", warnings, "agrisUsed");
    await fillAgrisToggle(editor, root, draft.session.agrisActive, warnings, draft.target);
    editor = findSessionEditor(root) || editor;
    if (!isSessionEditor(editor) || !verifySelectedSpot(editor, root, draft.target))
      throw new protocol.ProtocolError("spot_not_selected", "The session spot changed. Review the form before preparing again.");
    fillExplicitNumber(editor, draft.session.additionalDropRate, ["additional drop rate", "additional item drop rate"], "additional_drop_rate_field_not_found", warnings, "additionalDropRate");
    fillExplicitNumber(editor, draft.session.additionalDropAmount, ["additional drop amount", "additional item drop amount"], "additional_drop_amount_field_not_found", warnings, "additionalDropAmount");
    const itemResult = await fillItems(editor, root, draft.session.items, draft.behavior.skipUnsupported);

    assertPreparationActive();
    let finalEditor = findSessionEditor(root);
    if (!finalEditor || !verifySelectedSpot(finalEditor, root, draft.target) || !durationMatches(finalEditor, durationResult.seconds)) {
      warnings.push("duration_or_spot_not_accepted");
      return {ok:false, code:"session_not_prepared", message:"The spot or duration changed while entering items. Review the form before saving.",
        draftId:draft.draftId, matched:itemResult.matched, skipped:itemResult.skipped, warnings};
    }
    if (!itemResult.matched.length) return { ok:false, code:"no_items_prepared", message:"No item quantities were entered. All items remain in Session Import for review.",
      draftId:draft.draftId, matched:itemResult.matched, skipped:itemResult.skipped, warnings };
    let notes = await fillUnsupportedNotes(root,finalEditor,draft,itemResult,warnings);
    if (notes.notesStatus !== "not_needed")
      await verifyMatchedItemsAfterNotes(root,findSessionEditor(root) || finalEditor,draft.session.items,itemResult,warnings);
    assertPreparationActive();
    finalEditor = findSessionEditor(root);
    if (!finalEditor || !verifySelectedSpot(finalEditor,root,draft.target) || !durationMatches(finalEditor,durationResult.seconds))
      return {ok:false,code:"session_not_prepared",message:"The spot or duration changed. Review the form before saving.",
        draftId:draft.draftId,matched:itemResult.matched,skipped:itemResult.skipped,warnings,...notes};
    if (notes.notesVerified.length) {
      const owner = global.__bslSessionNotesOwners?.get(finalEditor);
      const control = notesControl(notesPanel(finalEditor)?.panel);
      const value = String(control?.value ?? "");
      if (!owner || value.split(owner.block).length !== 2 || value.split(NOTES_START).length !== 2 || value.split(NOTES_END).length !== 2) {
        if (!warnings.includes("unsupported_notes_not_accepted")) warnings.push("unsupported_notes_not_accepted");
        notes = {notesVerified:[],notesStatus:"failed"};
      }
    }
    if (!itemResult.matched.length) return {ok:false,code:"no_items_prepared",message:"The entered item quantities changed. Review the form before saving.",
      draftId:draft.draftId,matched:itemResult.matched,skipped:itemResult.skipped,warnings,...notes};
    // Item input handlers may remount or reset other form controls. Report a
    // changed explicit option without rewriting it or changing omitted values.
    verifySessionDetails(finalEditor, draft.session, warnings);
    finalEditor.setAttribute("data-bsl-session-import-draft", draft.draftId);
    return {
      ok: true,
      draftId: draft.draftId,
      matched: itemResult.matched,
      skipped: itemResult.skipped,
      warnings,
      ...notes
    };
  }

  if (api && api.runtime && api.runtime.onMessage) {
    api.runtime.onMessage.addListener((message) => {
      if (message && message.type === "tracker_ping") {
        try {
          assertTrackerPage();
          return Promise.resolve({ ready: true });
        } catch (_) {
          return Promise.resolve({ ready: false });
        }
      }
      if (message && message.type === "tracker_status") {
        const editor = findSessionEditor(document) || findEditor(document);
        return Promise.resolve({
          ready: true,
          draftId: editor ? editor.getAttribute("data-bsl-session-import-draft") : null
        });
      }
      if (!message || message.type !== "prepare_draft") {
        return undefined;
      }
      return prepareDraftIn(document, message.draft)
        .catch((error) => protocol.errorResult(error));
    });
  }

  global.TrackerContentTest = Object.freeze({
    normalizedText,
    urlContainsDelimitedIdentifier,
    safeClick,
    writeControl,
    findEditor,
    findSessionEditor,
    isSessionEditor,
    canPrepareCurrentPage,
    discoverPreparation,
    executeNavigationStep,
    findOpenEditorButton,
    prepareDraftIn
  });
})(globalThis);
