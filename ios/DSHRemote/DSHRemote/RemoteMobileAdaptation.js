(() => {
  const VERSION = "4";
  const root = document.documentElement;

  if (window.__dshRemoteMobile?.version === VERSION) {
    window.__dshRemoteMobile.sync();
    return;
  }

  const labels = {
    sidebar: /(侧边栏|sidebar)/i,
    newSession: /(新建会话|新会话|new session|new chat)/i,
    closeDetails: /(关闭详情|close details)/i,
    closeSettings: /^(关闭|close)$/i,
    modelID: /(模型 ID|model id)/i,
  };

  const isVisible = (element) => {
    if (!(element instanceof HTMLElement)) return false;
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };

  const buttons = () => Array.from(document.querySelectorAll("button"));
  const buttonWithLabel = (pattern, scope = document) =>
    Array.from(scope.querySelectorAll("button")).find((button) =>
      pattern.test(button.getAttribute("aria-label") || button.textContent || ""),
    );

  const viewport = document.querySelector('meta[name="viewport"]') || document.createElement("meta");
  viewport.name = "viewport";
  viewport.content = "width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover";
  if (!viewport.isConnected) document.head.append(viewport);

  const style = document.createElement("style");
  style.id = "dsh-remote-mobile-style";
  style.textContent = `
    :root[data-dsh-remote-mobile] {
      color-scheme: light dark;
      --dsh-remote-sheet-width: min(86vw, 340px);
      --dsh-remote-safe-bottom: env(safe-area-inset-bottom, 0px);
    }

    :root[data-dsh-remote-mobile],
    :root[data-dsh-remote-mobile] body {
      width: 100%;
      height: 100%;
      overflow: hidden;
      overscroll-behavior: none;
      -webkit-text-size-adjust: 100%;
    }

    [data-dsh-remote-frame] {
      width: 100vw !important;
      height: 100dvh !important;
      grid-template-columns: 0 minmax(0, 1fr) 0 !important;
      overflow: hidden !important;
    }

    [data-dsh-remote-frame] > [data-side] {
      display: none !important;
    }

    [data-dsh-remote-center] {
      grid-column: 2 !important;
      width: 100vw !important;
      min-width: 0 !important;
    }

    [data-dsh-remote-sidebar] {
      position: fixed !important;
      z-index: 1002 !important;
      inset: 0 auto 0 0 !important;
      width: var(--dsh-remote-sheet-width) !important;
      min-width: var(--dsh-remote-sheet-width) !important;
      border-right: 1px solid var(--dsw-alias-border-l2) !important;
      border-radius: 0 22px 22px 0;
      box-shadow: 14px 0 44px rgb(0 0 0 / 18%);
      overflow: hidden !important;
      transform: translate3d(-104%, 0, 0);
      transition: transform 220ms cubic-bezier(.2, .8, .2, 1);
    }

    :root[data-dsh-remote-drawer="open"] [data-dsh-remote-sidebar] {
      transform: translate3d(0, 0, 0);
    }

    :root[data-dsh-remote-settings-state="open"] [data-dsh-remote-sidebar] {
      width: 100vw !important;
      min-width: 100vw !important;
      border: 0 !important;
      border-radius: 0 !important;
      box-shadow: none !important;
      overflow: visible !important;
      transform: translate3d(0, 0, 0) !important;
    }

    [data-dsh-remote-sidebar-root] {
      box-sizing: border-box !important;
      width: 100% !important;
      padding: 6px 12px calc(10px + var(--dsh-remote-safe-bottom)) !important;
    }

    [data-dsh-remote-sidebar-header] {
      box-sizing: border-box !important;
      height: 54px !important;
      margin: 0 0 6px !important;
      padding: 0 4px !important;
      justify-content: space-between !important;
      overflow: visible !important;
    }

    [data-dsh-remote-sidebar-header]::before {
      content: attr(data-dsh-remote-title);
      color: var(--dsw-alias-label-primary);
      font-size: 20px;
      font-weight: 650;
      letter-spacing: -0.01em;
    }

    [data-dsh-remote-sidebar-header] > :not([data-dsh-remote-sidebar-toggle]) {
      display: none !important;
    }

    [data-dsh-remote-sidebar-toggle],
    [data-slot="sidebar"] button,
    [data-slot="sidebar"] [role="treeitem"] {
      min-height: 44px;
      touch-action: manipulation;
    }

    [data-dsh-remote-sidebar-toggle] {
      width: 44px !important;
      height: 44px !important;
      margin-right: -8px;
    }

    [data-slot="sidebar"] [role="treeitem"] {
      border-radius: 10px;
    }

    #dsh-remote-drawer-scrim,
    #dsh-remote-details-scrim {
      position: fixed;
      z-index: 1001;
      inset: 0;
      border: 0;
      background: rgb(0 0 0 / 32%);
      opacity: 0;
      pointer-events: none;
      transition: opacity 180ms ease;
      -webkit-tap-highlight-color: transparent;
    }

    :root[data-dsh-remote-drawer="open"] #dsh-remote-drawer-scrim,
    :root[data-dsh-remote-details-state="open"] #dsh-remote-details-scrim {
      opacity: 1;
      pointer-events: auto;
    }

    :root[data-dsh-remote-settings-state="open"] #dsh-remote-drawer-scrim {
      opacity: 0;
      pointer-events: none;
    }

    [data-dsh-remote-settings] {
      position: fixed !important;
      z-index: 1010 !important;
      inset: 0 !important;
      box-sizing: border-box !important;
      display: grid !important;
      grid-template-columns: minmax(0, 1fr) 56px !important;
      grid-template-rows: 56px 52px minmax(0, 1fr) !important;
      width: 100vw !important;
      min-width: 100vw !important;
      max-width: none !important;
      height: 100dvh !important;
      min-height: 100dvh !important;
      max-height: none !important;
      border: 0 !important;
      border-radius: 0 !important;
      background: var(--dsw-alias-bg-base) !important;
      box-shadow: none !important;
      overflow: hidden !important;
    }

    [data-dsh-remote-settings-nav],
    [data-dsh-remote-settings-content] {
      display: contents !important;
    }

    [data-dsh-remote-settings-title] {
      grid-column: 1;
      grid-row: 1;
      box-sizing: border-box !important;
      display: flex !important;
      width: 100% !important;
      height: 56px !important;
      margin: 0 !important;
      padding: 0 18px !important;
      align-items: center;
      color: var(--dsw-alias-label-primary);
      font-size: 20px !important;
      font-weight: 650;
      letter-spacing: -0.01em;
    }

    [data-dsh-remote-settings-title] [data-slot="settings.header"] {
      display: block !important;
      width: auto !important;
      height: auto !important;
    }

    [data-dsh-remote-settings-header] {
      grid-column: 2;
      grid-row: 1;
      box-sizing: border-box !important;
      display: flex !important;
      width: 56px !important;
      height: 56px !important;
      padding: 0 6px 0 0 !important;
      align-items: center !important;
      justify-content: flex-end !important;
    }

    [data-dsh-remote-settings-header] [data-slot="settings.action"] {
      display: none !important;
    }

    [data-dsh-remote-settings-close] {
      width: 44px !important;
      min-width: 44px !important;
      height: 44px !important;
      min-height: 44px !important;
      padding: 0 !important;
      touch-action: manipulation;
    }

    [data-dsh-remote-settings-nav-list] {
      grid-column: 1 / -1;
      grid-row: 2;
      box-sizing: border-box !important;
      display: flex !important;
      width: 100% !important;
      height: 52px !important;
      margin: 0 !important;
      padding: 4px 12px !important;
      gap: 4px !important;
      flex-direction: row !important;
      align-items: center !important;
      justify-content: flex-start !important;
      overflow-x: auto !important;
      overflow-y: hidden !important;
      border-top: 1px solid var(--dsw-alias-border-l2);
      border-bottom: 1px solid var(--dsw-alias-border-l2);
      overscroll-behavior-x: contain;
      -webkit-overflow-scrolling: touch;
    }

    [data-dsh-remote-settings-nav-list] > button {
      flex: 0 0 auto !important;
      width: auto !important;
      min-width: 72px !important;
      height: 44px !important;
      min-height: 44px !important;
      margin: 0 !important;
      padding: 0 12px !important;
      border-radius: 10px !important;
      touch-action: manipulation;
    }

    [data-dsh-remote-settings-nav-list] > button > span {
      width: auto !important;
      white-space: nowrap;
    }

    [data-dsh-remote-settings-options] {
      grid-column: 1 / -1;
      grid-row: 3;
      box-sizing: border-box !important;
      width: 100% !important;
      min-width: 0 !important;
      height: 100% !important;
      min-height: 0 !important;
      padding: 0 !important;
      overflow-x: hidden !important;
      overflow-y: auto !important;
      overscroll-behavior-y: contain;
      -webkit-overflow-scrolling: touch;
    }

    [data-dsh-remote-settings-options] [data-slot="settings.section"] > * {
      box-sizing: border-box !important;
      width: min(100%, 680px) !important;
      min-width: 0 !important;
      max-width: 680px !important;
      margin: 0 auto !important;
      padding: 16px 16px calc(32px + var(--dsh-remote-safe-bottom)) !important;
    }

    [data-dsh-remote-settings-options] [data-slot="settings.general.item"] {
      display: block !important;
      width: 100% !important;
      min-width: 0 !important;
    }

    [data-dsh-remote-settings-options] [data-slot="settings.general.item"] > * {
      box-sizing: border-box !important;
      display: grid !important;
      grid-template-columns: minmax(0, 1fr) auto !important;
      width: 100% !important;
      min-width: 0 !important;
      min-height: 72px !important;
      margin: 0 !important;
      padding: 14px 0 !important;
      gap: 12px !important;
      align-items: center !important;
      border-bottom: 1px solid var(--dsw-alias-border-l2);
    }

    [data-dsh-remote-settings-options] [data-slot="settings.general.item"] > * > * {
      min-width: 0 !important;
    }

    [data-dsh-remote-settings-options] [data-dsh-remote-settings-appearance] {
      grid-template-columns: minmax(0, 1fr) !important;
      gap: 10px !important;
    }

    [data-dsh-remote-settings-options] [data-dsh-remote-settings-appearance] > :first-child {
      width: 100% !important;
      height: auto !important;
    }

    [data-dsh-remote-settings-options] [data-dsh-remote-settings-appearance] > :last-child {
      display: grid !important;
      grid-template-columns: repeat(3, minmax(0, 1fr)) !important;
      width: 100% !important;
      height: auto !important;
      gap: 8px !important;
    }

    [data-dsh-remote-settings-options] [data-dsh-remote-settings-appearance] > :last-child > button {
      width: auto !important;
      min-width: 0 !important;
      height: 84px !important;
    }

    [data-dsh-remote-settings-options] button,
    [data-dsh-remote-settings-options] input,
    [data-dsh-remote-settings-options] select,
    [data-dsh-remote-settings-options] textarea {
      max-width: 100%;
      min-height: 44px;
      font-size: 16px;
      touch-action: manipulation;
    }

    [data-dsh-remote-settings-options] pre,
    [data-dsh-remote-settings-options] code,
    [data-dsh-remote-settings-options] table {
      max-width: 100%;
      overflow-x: auto;
    }

    [data-dsh-remote-model-row] {
      display: grid !important;
      grid-template-columns: minmax(0, 1fr) 44px 44px !important;
      width: 100% !important;
      height: auto !important;
      gap: 8px !important;
    }

    [data-dsh-remote-model-row] > input {
      grid-column: 1 / -1;
      width: 100% !important;
      min-width: 0 !important;
    }

    [data-dsh-remote-model-row] > input:first-child {
      grid-row: 1;
    }

    [data-dsh-remote-model-row] > input:nth-child(2) {
      grid-row: 2;
    }

    [data-dsh-remote-model-row] > button:nth-of-type(1) {
      grid-column: 2;
      grid-row: 3;
      width: 44px !important;
      min-width: 44px !important;
    }

    [data-dsh-remote-model-row] > button:nth-of-type(2) {
      grid-column: 3;
      grid-row: 3;
      width: 44px !important;
      min-width: 44px !important;
    }

    [data-dsh-remote-modal-root] {
      z-index: 1020 !important;
      box-sizing: border-box !important;
      padding: 12px !important;
    }

    [data-dsh-remote-modal] {
      box-sizing: border-box !important;
      display: flex !important;
      flex-direction: column !important;
      width: min(100%, 560px) !important;
      min-width: 0 !important;
      max-width: 560px !important;
      max-height: calc(100dvh - 24px) !important;
      border-radius: 18px !important;
    }

    [data-dsh-remote-modal] > :first-child {
      flex: 1 1 auto !important;
      min-height: 0 !important;
      overflow: hidden !important;
    }

    [data-dsh-remote-modal] > :first-child > :last-child {
      flex: 1 1 auto !important;
      min-height: 0 !important;
      overflow: hidden !important;
    }

    [data-dsh-remote-modal] > :first-child > :last-child > pre {
      box-sizing: border-box !important;
      width: 100% !important;
      height: 100% !important;
      max-height: 100% !important;
    }

    [data-dsh-remote-modal] > :last-child:not(:first-child) {
      flex: 0 0 auto !important;
      min-height: 60px !important;
    }

    [data-dsh-remote-modal] > :last-child:not(:first-child) button {
      min-height: 44px !important;
    }

    :root[data-dsh-remote-native][data-dsh-remote-settings-state="open"] [data-dsh-remote-settings] {
      grid-template-rows: 52px minmax(0, 1fr) !important;
    }

    :root[data-dsh-remote-native][data-dsh-remote-settings-state="open"] [data-dsh-remote-settings-title],
    :root[data-dsh-remote-native][data-dsh-remote-settings-state="open"] [data-dsh-remote-settings-header] {
      display: none !important;
    }

    :root[data-dsh-remote-native][data-dsh-remote-settings-state="open"] [data-dsh-remote-settings-nav-list] {
      grid-row: 1;
    }

    :root[data-dsh-remote-native][data-dsh-remote-settings-state="open"] [data-dsh-remote-settings-options] {
      grid-row: 2;
    }

    [data-dsh-remote-conversation] {
      --dsh-chat-content-width: 100%;
      --dsh-composer-card-max-width: 100%;
      --dsh-composer-side-clearance: 10px;
      width: 100% !important;
    }

    [data-dsh-remote-conversation-header] {
      box-sizing: border-box !important;
      height: 45px !important;
      min-height: 45px !important;
      padding: 0 14px !important;
      background: color-mix(in srgb, var(--dsw-alias-bg-base) 94%, transparent);
    }

    [data-dsh-remote-title-row] {
      display: none !important;
    }

    [data-dsh-remote-tabs] {
      box-sizing: border-box !important;
      width: 100% !important;
      height: 44px !important;
      margin: 0 !important;
      padding: 0 !important;
      gap: 4px !important;
      align-items: stretch !important;
    }

    [data-dsh-remote-tabs] > [role="tab"] {
      flex: 1;
      min-width: 76px;
      min-height: 44px;
      padding: 0 8px !important;
      font-size: 14px !important;
      touch-action: manipulation;
    }

    [data-conversation-scroll] {
      scrollbar-gutter: auto !important;
      overscroll-behavior-y: contain;
    }

    [data-dsh-remote-chat-scroll] {
      padding: 14px 16px 20px !important;
    }

    [data-chat-flow] {
      width: 100% !important;
      max-width: none !important;
      gap: 18px !important;
    }

    [data-slot="conversation.chat.assistant-actions"] button,
    [data-slot="conversation.chat.turnTail"] button {
      min-width: 36px !important;
      min-height: 36px !important;
      touch-action: manipulation;
    }

    [data-slot="conversation.chat.node"] pre,
    [data-slot="conversation.chat.node"] code {
      max-width: 100%;
      overflow-wrap: anywhere;
    }

    [data-composer-seat] {
      box-sizing: border-box !important;
      width: 100% !important;
      padding-bottom: var(--dsh-remote-safe-bottom);
    }

    [data-composer-card] {
      max-width: none !important;
      border-radius: 20px !important;
      box-shadow: 0 8px 28px rgb(0 0 0 / 9%) !important;
    }

    [data-input-scroll] textarea {
      min-height: 48px;
      font-size: 16px !important;
    }

    [data-dsh-remote-composer-row] {
      display: grid !important;
      grid-template-columns: minmax(76px, auto) minmax(0, 1fr);
      gap: 6px !important;
      padding: 2px 8px 7px !important;
    }

    [data-dsh-remote-composer-tools],
    [data-dsh-remote-composer-trailing] {
      width: auto !important;
      min-width: 0 !important;
      gap: 5px !important;
    }

    [data-dsh-remote-composer-trailing] {
      justify-content: flex-end;
    }

    [data-dsh-remote-composer-row] button {
      min-width: 36px;
      min-height: 36px;
      touch-action: manipulation;
    }

    [data-slot="conversation.input.model"] {
      min-width: 0;
    }

    [data-slot="conversation.input.model"] button {
      max-width: 138px !important;
      min-width: 0 !important;
      height: 36px !important;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    [data-slot="conversation.input.model"] button > :nth-child(2) {
      display: none !important;
    }

    [data-slot="conversation.composer.dock"] {
      display: none !important;
    }

    [data-dsh-remote-conversation][data-phase="hero"] [data-composer-seat] {
      padding-inline: 8px;
    }

    [data-dsh-remote-conversation][data-phase="hero"] [data-composer-card] {
      width: 100% !important;
    }

    [data-dsh-remote-details] {
      position: fixed !important;
      z-index: 1004 !important;
      inset: auto 0 0 0 !important;
      box-sizing: border-box !important;
      width: 100vw !important;
      min-width: 100vw !important;
      height: min(74dvh, 680px) !important;
      padding-bottom: var(--dsh-remote-safe-bottom);
      border: 0 !important;
      border-radius: 24px 24px 0 0;
      box-shadow: 0 -14px 44px rgb(0 0 0 / 18%);
      overflow: hidden !important;
      transform: translate3d(0, 104%, 0);
      transition: transform 220ms cubic-bezier(.2, .8, .2, 1);
    }

    :root[data-dsh-remote-details-state="open"] [data-dsh-remote-details] {
      transform: translate3d(0, 0, 0);
    }

    [role="menu"], [role="listbox"], [role="dialog"] {
      max-width: calc(100vw - 24px) !important;
      max-height: min(72dvh, 620px) !important;
    }

    @media (max-width: 360px) {
      [data-dsh-remote-chat-scroll] {
        padding-inline: 12px !important;
      }

      [data-dsh-remote-composer-row] {
        grid-template-columns: 72px minmax(0, 1fr);
      }

      [data-slot="conversation.input.model"] button {
        max-width: 104px !important;
      }

      [data-dsh-remote-settings-nav-list] > button {
        min-width: 68px !important;
        padding-inline: 10px !important;
      }

      [data-dsh-remote-settings-options] [data-slot="settings.general.item"] > * {
        grid-template-columns: minmax(0, 1fr) !important;
      }

      [data-dsh-remote-settings-options] [data-slot="settings.general.item"] > * > :last-child {
        width: 100% !important;
        justify-self: stretch !important;
      }

      [data-dsh-remote-settings-options] [data-slot="settings.general.item"] > * > :last-child button {
        width: 100% !important;
      }

      [data-dsh-remote-settings-options] [data-dsh-remote-settings-appearance] > :last-child > button {
        flex-direction: row !important;
        height: 56px !important;
        gap: 6px !important;
        white-space: nowrap !important;
      }
    }

    @media (prefers-reduced-motion: reduce) {
      [data-dsh-remote-sidebar],
      [data-dsh-remote-details],
      #dsh-remote-drawer-scrim,
      #dsh-remote-details-scrim {
        transition: none !important;
      }
    }
  `;
  document.head.append(style);
  root.setAttribute("data-dsh-remote-mobile", VERSION);
  if (window.webkit?.messageHandlers?.dshRemoteState) {
    root.setAttribute("data-dsh-remote-native", "");
  }

  const ensureScrim = (id, onClick) => {
    let scrim = document.getElementById(id);
    if (scrim) return scrim;
    scrim = document.createElement("button");
    scrim.id = id;
    scrim.type = "button";
    scrim.tabIndex = -1;
    scrim.setAttribute("aria-hidden", "true");
    scrim.addEventListener("click", onClick);
    document.body.append(scrim);
    return scrim;
  };

  const sidebarToggle = () => buttonWithLabel(labels.sidebar);

  const closeSidebar = () => {
    if (root.getAttribute("data-dsh-remote-drawer") !== "open") return;
    sidebarToggle()?.click();
  };

  const closeDetails = () => buttonWithLabel(labels.closeDetails)?.click();

  ensureScrim("dsh-remote-drawer-scrim", closeSidebar);
  ensureScrim("dsh-remote-details-scrim", closeDetails);

  let syncFrame = null;
  let activeSettingsPanel = null;
  let syncScheduled = false;
  let lastBridgeState = "";

  const markComposer = () => {
    const card = document.querySelector("[data-composer-card]");
    const row = card?.lastElementChild;
    if (!(row instanceof HTMLElement)) return;
    row.setAttribute("data-dsh-remote-composer-row", "");
    row.children[0]?.setAttribute("data-dsh-remote-composer-tools", "");
    row.children[1]?.setAttribute("data-dsh-remote-composer-trailing", "");
  };

  const titleFromPage = () => {
    const crumb = document.querySelector('[data-slot="conversation.session.header"] nav button:last-of-type');
    const title = crumb?.textContent?.trim();
    if (title) return title;
    const documentTitle = document.title.split(/\s+[—-]\s+/)[0]?.trim();
    if (documentTitle && documentTitle !== "DeepSeek Harness") return documentTitle;
    return null;
  };

  const postState = () => {
    const payload = JSON.stringify({
      title: titleFromPage(),
      ready: Boolean(syncFrame),
      settings: Boolean(activeSettingsPanel),
    });
    if (payload === lastBridgeState) return;
    lastBridgeState = payload;
    try {
      window.webkit?.messageHandlers?.dshRemoteState?.postMessage(JSON.parse(payload));
    } catch (_) {
      // The browser baseline has no native message bridge.
    }
  };

  const markSettings = () => {
    const headerSlot = document.querySelector('[data-slot="settings.header"]');
    const panel = headerSlot?.closest('[role="dialog"]');
    activeSettingsPanel = panel instanceof HTMLElement ? panel : null;
    root.setAttribute("data-dsh-remote-settings-state", activeSettingsPanel ? "open" : "closed");
    if (!activeSettingsPanel) return;

    activeSettingsPanel.setAttribute("data-dsh-remote-settings", "");
    const nav = activeSettingsPanel.querySelector(":scope > nav");
    const content = Array.from(activeSettingsPanel.children).find((child) => child !== nav);
    nav?.setAttribute("data-dsh-remote-settings-nav", "");
    nav?.firstElementChild?.setAttribute("data-dsh-remote-settings-title", "");
    nav?.lastElementChild?.setAttribute("data-dsh-remote-settings-nav-list", "");
    content?.setAttribute("data-dsh-remote-settings-content", "");
    content?.firstElementChild?.setAttribute("data-dsh-remote-settings-header", "");
    content?.lastElementChild?.setAttribute("data-dsh-remote-settings-options", "");
    activeSettingsPanel
      .querySelectorAll('[data-slot="settings.general.item"] > *')
      .forEach((item) => {
        item.setAttribute("data-dsh-remote-settings-item", "");
        const control = item.lastElementChild;
        if (control?.querySelectorAll(":scope > button").length === 3) {
          item.setAttribute("data-dsh-remote-settings-appearance", "");
        }
      });
    document.querySelectorAll('[role="dialog"]').forEach((dialog) => {
      if (dialog === activeSettingsPanel) return;
      dialog.setAttribute("data-dsh-remote-modal", "");
      dialog.parentElement?.setAttribute("data-dsh-remote-modal-root", "");
    });
    activeSettingsPanel.querySelectorAll("input").forEach((input) => {
      if (labels.modelID.test(input.getAttribute("aria-label") || input.placeholder || "")) {
        input.parentElement?.setAttribute("data-dsh-remote-model-row", "");
      }
    });
    buttonWithLabel(labels.closeSettings, activeSettingsPanel)?.setAttribute(
      "data-dsh-remote-settings-close",
      "",
    );
  };

  const sync = () => {
    syncScheduled = false;
    const shellOverlay = document.querySelector("[data-shell-overlay]");
    const frame = shellOverlay?.parentElement;
    if (!(frame instanceof HTMLElement)) {
      syncFrame = null;
      postState();
      return;
    }

    syncFrame = frame;
    frame.setAttribute("data-dsh-remote-frame", "");

    const sidebar = document.querySelector('[data-slot="sidebar"]')?.parentElement;
    const center = document.querySelector('[data-slot="conversation"]')?.parentElement;
    const details = document.querySelector('[data-slot="details"]')?.parentElement;
    sidebar?.setAttribute("data-dsh-remote-sidebar", "");
    center?.setAttribute("data-dsh-remote-center", "");
    details?.setAttribute("data-dsh-remote-details", "");

    const sidebarRoot = document.querySelector('[data-slot="sidebar"]')?.firstElementChild;
    sidebarRoot?.setAttribute("data-dsh-remote-sidebar-root", "");
    const toggle = sidebarToggle();
    toggle?.setAttribute("data-dsh-remote-sidebar-toggle", "");
    const sidebarHeader = toggle?.parentElement;
    if (sidebarHeader instanceof HTMLElement) {
      sidebarHeader.setAttribute("data-dsh-remote-sidebar-header", "");
      sidebarHeader.setAttribute(
        "data-dsh-remote-title",
        document.documentElement.lang.toLowerCase().startsWith("en") ? "Sessions" : "会话",
      );
    }

    const conversation = document.querySelector('[data-slot="conversation"]')?.firstElementChild;
    conversation?.setAttribute("data-dsh-remote-conversation", "");
    const header = document.querySelector('[data-slot="conversation.session.header"]')?.firstElementChild;
    header?.setAttribute("data-dsh-remote-conversation-header", "");
    header?.firstElementChild?.setAttribute("data-dsh-remote-title-row", "");
    header?.querySelector('[role="tablist"]')?.setAttribute("data-dsh-remote-tabs", "");

    const chatFlow = document.querySelector("[data-chat-flow]");
    chatFlow?.parentElement?.setAttribute("data-dsh-remote-chat-scroll", "");
    markComposer();
    markSettings();

    root.setAttribute(
      "data-dsh-remote-drawer",
      frame.hasAttribute("data-sidebar-collapsed") ? "closed" : "open",
    );
    root.setAttribute(
      "data-dsh-remote-details-state",
      frame.hasAttribute("data-details-collapsed") ? "closed" : "open",
    );
    postState();
  };

  const scheduleSync = () => {
    if (syncScheduled) return;
    syncScheduled = true;
    setTimeout(sync, 0);
  };

  const command = (action) => {
    if (action === "toggleSidebar") {
      sidebarToggle()?.click();
      return;
    }

    if (action === "newSession") {
      const activateNewSession = () => {
        const candidates = buttons().filter((button) =>
          labels.newSession.test(button.getAttribute("aria-label") || button.textContent || ""),
        );
        (candidates.find(isVisible) || candidates[0])?.click();
      };

      if (root.getAttribute("data-dsh-remote-drawer") === "open") {
        closeSidebar();
        setTimeout(activateNewSession, 180);
      } else {
        activateNewSession();
      }
      return;
    }

    if (action === "closeSettings") {
      buttonWithLabel(labels.closeSettings, activeSettingsPanel || document)?.click();
      return;
    }

    if (action === "reload") window.location.reload();
  };

  window.__dshRemoteMobile = { version: VERSION, command, sync: scheduleSync };

  document.addEventListener(
    "click",
    (event) => {
      const target = event.target instanceof Element ? event.target.closest('[role="treeitem"]') : null;
      if (target) setTimeout(closeSidebar, 80);
    },
    true,
  );

  new MutationObserver(scheduleSync).observe(document.body, {
    attributes: true,
    childList: true,
    characterData: true,
    subtree: true,
    attributeFilter: [
      "aria-label",
      "class",
      "data-details-collapsed",
      "data-sidebar-collapsed",
      "disabled",
    ],
  });

  scheduleSync();
})();
