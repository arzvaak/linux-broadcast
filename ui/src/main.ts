import { invoke } from "@tauri-apps/api/core";
import "./style.css";

type SystemStatus = {
  gpuName: string;
  computeCapability: string;
  architecture: string;
  modelReady: boolean;
  pluginReady: boolean;
  availableEffects: string[];
};

type Microphone = { id: number; name: string; description: string; isDefault: boolean };
type OutputDevice = { name: string; description: string; isDefault: boolean };
type BackgroundSettings = { runInBackground: boolean; startAtLogin: boolean };
type ProcessingStatus = {
  running: boolean;
  sourceName: string | null;
  intensity: number;
  monitoring: boolean;
  monitorSinkName: string | null;
  effectMode: string;
  vadEnabled: boolean;
  frameMs: number;
};

let processing = false;
let systemReady = false;
let noticeTimer: number | undefined;

const app = document.querySelector<HTMLElement>("#app")!;
app.innerHTML = `
  <header class="topbar">
    <div class="brand"><span class="brand-mark"><i></i><i></i><i></i></span><span>Linux Broadcast</span></div>
    <button id="settingsButton" class="settings-button">Settings</button>
  </header>
  <main id="mainView">
    <section class="hero">
      <p class="eyebrow">NVIDIA AFX · Noise Removal</p>
      <h1>Clean voice.</h1>
      <button id="power" class="power" aria-label="Start voice processing"><span></span><b>Start</b></button>
    </section>
    <section class="controls">
      <div class="control-row source-row">
        <label for="microphone"><span>Microphone</span><small>Input source</small></label>
        <div class="select-wrap"><select id="microphone"><option>Detecting microphones…</option></select><span>⌄</span></div>
      </div>
      <div class="divider"></div>
      <div class="control-row effect-row">
        <label for="effect"><span>Effect</span><small>NVIDIA AFX</small></label>
        <div class="select-wrap"><select id="effect">
          <option value="noise">Noise Removal · calls, fans & clicks</option>
          <option value="bnr2">BNR 2.0 · experimental speech cleanup</option>
          <option value="room_echo">Room Echo · untreated rooms</option>
          <option value="noise_room_echo">Noise + Room Echo · noisy rooms</option>
          <option value="studio_voice">Studio Voice · improve mic quality</option>
        </select><span>⌄</span></div>
      </div>
      <p id="effectGuide" class="effect-guide"></p>
      <div class="divider"></div>
      <div class="control-row strength-row">
        <label for="strength"><span id="strengthLabel">Noise removal</span><small>Intensity</small></label>
        <output id="strengthValue">100%</output>
      </div>
      <input id="strength" type="range" min="0" max="100" value="75" />
      <details class="advanced">
        <summary><span>Advanced</span><small>SDK tuning</small></summary>
        <div class="tuning-row">
          <label id="vadSetting" class="tuning-setting" for="vad"><span>SDK voice gate</span><small>Remove non-speech and low-volume noise</small></label>
          <button id="vad" class="toggle" aria-label="Enable SDK voice gate" aria-pressed="false"><i></i></button>
          <label class="tuning-setting latency-setting" for="frameSize"><span>Processing frame</span><small id="frameHint">Steadier delivery</small></label>
          <div class="frame-select"><select id="frameSize" aria-label="AFX processing frame size">
            <option value="10">Responsive · 10 ms</option>
            <option value="20" selected>Buffered · 20 ms</option>
          </select></div>
        </div>
        <button id="resetTuning" class="reset-tuning">Reset balanced defaults</button>
      </details>
      <div id="virtualOutput" class="virtual-output"><span><i></i>Output</span><strong>Linux Broadcast Microphone</strong></div>
      <div class="monitor-row">
        <label for="monitorOutput"><span>Hear myself</span><small>Final signal · use headphones</small></label>
        <div class="monitor-actions">
          <select id="monitorOutput" aria-label="Monitoring output"><option>Detecting outputs…</option></select>
          <button id="monitor" class="toggle" aria-label="Enable microphone monitoring" aria-pressed="false"><i></i></button>
        </div>
      </div>
    </section>
  </main>
  <section id="settingsView" class="settings-view view-hidden">
    <div class="settings-heading"><button id="settingsBack" aria-label="Back to voice controls">←</button><div><h2>Settings</h2><p>Background behavior</p></div></div>
    <div class="settings-card">
      <div class="settings-row">
        <label for="runInBackground"><span>Run in background</span><small>Closing the window keeps the virtual microphone active in the tray.</small></label>
        <button id="runInBackground" class="toggle" aria-pressed="false"><i></i></button>
      </div>
      <div class="divider"></div>
      <div class="settings-row">
        <label for="startAtLogin"><span>Start at login</span><small>Launch hidden with your saved microphone and NVIDIA AFX settings.</small></label>
        <button id="startAtLogin" class="toggle" aria-pressed="false"><i></i></button>
      </div>
    </div>
    <p class="settings-note">Use the tray menu to reopen Linux Broadcast or quit it completely.</p>
  </section>
  <footer id="hardwareInfo" class="hardware">
    <span class="status-dot"></span><strong id="gpu">Detecting NVIDIA GPU…</strong>
    <span class="separator"></span><span id="architecture">—</span>
    <span class="separator"></span><span id="modelState">Checking model</span>
  </footer>
  <div id="notice" class="notice hidden"></div>
`;

const strength = document.querySelector<HTMLInputElement>("#strength")!;
const strengthValue = document.querySelector<HTMLOutputElement>("#strengthValue")!;
strength.addEventListener("input", () => {
  strengthValue.value = `${strength.value}%`;
});

const effectNames: Record<string, string> = {
  noise: "Noise Removal",
  bnr2: "BNR 2.0",
  room_echo: "Room Echo Removal",
  noise_room_echo: "Noise + Room Echo",
  studio_voice: "Studio Voice",
};

const effectLabels: Record<string, string> = {
  noise: "Noise Removal · calls, fans & clicks",
  bnr2: "BNR 2.0 · experimental speech cleanup",
  room_echo: "Room Echo · untreated rooms",
  noise_room_echo: "Noise + Room Echo · noisy rooms",
  studio_voice: "Studio Voice · improve mic quality",
};

const effectGuides: Record<string, string> = {
  noise: "Best default for calls — removes fans, keyboard clicks and everyday background noise.",
  bnr2: "Experimental cleanup for ASR and recorded speech — quiet noises overlapping speech may get through.",
  room_echo: "For untreated or reverberant rooms — reduces room echo, but does not target background sounds.",
  noise_room_echo: "For rooms that are both noisy and echoey — NVIDIA's combined one-pass cleanup model.",
  studio_voice: "For weak or distant microphones — restores voice quality automatically and does not combine with Noise Removal.",
};

const vadEffects = new Set(["noise", "bnr2", "noise_room_echo"]);

const tuningDefaults: Record<string, { intensity: number; vad: boolean; frameMs: number }> = {
  noise: { intensity: 75, vad: false, frameMs: 20 },
  bnr2: { intensity: 75, vad: true, frameMs: 20 },
  room_echo: { intensity: 65, vad: false, frameMs: 20 },
  noise_room_echo: { intensity: 70, vad: false, frameMs: 20 },
  studio_voice: { intensity: 100, vad: false, frameMs: 10 },
};

function selectedEffect() {
  return document.querySelector<HTMLSelectElement>("#effect")!.value;
}

function selectedVad() {
  return document.querySelector<HTMLButtonElement>("#vad")!.classList.contains("active");
}

function selectedFrameMs() {
  return Number(document.querySelector<HTMLSelectElement>("#frameSize")!.value);
}

function rememberedVad(mode: string) {
  const remembered = window.localStorage.getItem(`linux-broadcast.vad.${mode}`);
  return remembered === null ? tuningDefaults[mode]?.vad ?? false : remembered === "true";
}

function loadRememberedTuning(mode: string) {
  const defaults = tuningDefaults[mode] ?? tuningDefaults.noise;
  const rememberedIntensity = Number(window.localStorage.getItem(`linux-broadcast.intensity.${mode}`));
  strength.value = String(
    Number.isFinite(rememberedIntensity) && rememberedIntensity >= 0 && rememberedIntensity <= 100
      ? rememberedIntensity
      : defaults.intensity,
  );
  setVad(rememberedVad(mode));
  const rememberedFrame = Number(window.localStorage.getItem(`linux-broadcast.frame.${mode}`));
  document.querySelector<HTMLSelectElement>("#frameSize")!.value = String(
    rememberedFrame === 10 || (rememberedFrame === 20 && mode !== "studio_voice")
      ? rememberedFrame
      : defaults.frameMs,
  );
}

function setVad(enabled: boolean) {
  const button = document.querySelector<HTMLButtonElement>("#vad")!;
  button.classList.toggle("active", enabled);
  button.setAttribute("aria-pressed", String(enabled));
  button.setAttribute("aria-label", `${enabled ? "Disable" : "Enable"} SDK voice gate`);
}

function showEffect(mode: string) {
  const studioVoice = mode === "studio_voice";
  const vadSupported = vadEffects.has(mode);
  const frameSize = document.querySelector<HTMLSelectElement>("#frameSize")!;
  document.querySelector(".eyebrow")!.textContent = `NVIDIA AFX · ${effectNames[mode] ?? "Voice Effect"}`;
  document.querySelector("#strengthLabel")!.textContent = effectNames[mode] ?? "Effect";
  document.querySelector("#effectGuide")!.textContent = effectGuides[mode] ?? "";
  strength.disabled = studioVoice;
  strengthValue.value = studioVoice ? "Auto" : `${strength.value}%`;
  document.querySelector<HTMLElement>("#vadSetting")!.classList.toggle("unsupported", !vadSupported);
  document.querySelector<HTMLButtonElement>("#vad")!.disabled = !vadSupported;
  frameSize.disabled = studioVoice;
  if (studioVoice) frameSize.value = "10";
  document.querySelector("#frameHint")!.textContent = studioVoice ? "Fixed by Studio Voice" : frameSize.value === "20" ? "Steadier delivery" : "Lower latency";
}

function showStatus(status: SystemStatus) {
  document.querySelector("#gpu")!.textContent = status.gpuName;
  document.querySelector("#architecture")!.textContent = `${status.architecture} · CC ${status.computeCapability}`;
  const model = document.querySelector("#modelState")!;
  const effectSelect = document.querySelector<HTMLSelectElement>("#effect")!;
  effectSelect.replaceChildren(
    ...status.availableEffects.map((mode) => new Option(effectLabels[mode] ?? mode, mode)),
  );
  effectSelect.disabled = status.availableEffects.length === 0;
  systemReady = status.modelReady && status.pluginReady && status.availableEffects.length > 0;
  model.textContent = !status.modelReady
    ? "NVIDIA AFX package required"
    : status.pluginReady
      ? `${status.availableEffects.length} AFX ${status.availableEffects.length === 1 ? "effect" : "effects"} ready`
      : "Native plugin requires build";
  model.className = systemReady ? "ready" : "warning";
  const power = document.querySelector<HTMLButtonElement>("#power")!;
  power.disabled = !systemReady;
  power.title = systemReady ? "Start voice processing" : "The AFX model and native plugin must both be ready";
}

function showProcessing(status: ProcessingStatus) {
  processing = status.running;
  const power = document.querySelector<HTMLButtonElement>("#power")!;
  power.classList.toggle("active", processing);
  power.querySelector("b")!.textContent = processing ? "Stop" : "Start";
  power.setAttribute("aria-label", processing ? "Stop voice processing" : "Start voice processing");
  document.querySelector("#virtualOutput")!.classList.toggle("live", processing);
  const monitor = document.querySelector<HTMLButtonElement>("#monitor")!;
  monitor.classList.toggle("active", status.monitoring);
  monitor.setAttribute("aria-pressed", String(status.monitoring));
  monitor.setAttribute("aria-label", status.monitoring ? "Disable microphone monitoring" : "Enable microphone monitoring");
  if (status.monitorSinkName) {
    document.querySelector<HTMLSelectElement>("#monitorOutput")!.value = status.monitorSinkName;
  }
  if (status.sourceName) {
    document.querySelector<HTMLSelectElement>("#microphone")!.value = status.sourceName;
  }
  if (status.running) {
    document.querySelector<HTMLSelectElement>("#effect")!.value = status.effectMode;
    strength.value = String(Math.round(status.intensity * 100));
    setVad(status.vadEnabled);
    document.querySelector<HTMLSelectElement>("#frameSize")!.value = String(status.frameMs);
    showEffect(status.effectMode);
  }
}

function showNotice(message: string, error = false) {
  const notice = document.querySelector<HTMLElement>("#notice")!;
  notice.textContent = message;
  notice.classList.toggle("error", error);
  notice.classList.remove("hidden");
  if (noticeTimer !== undefined) window.clearTimeout(noticeTimer);
  noticeTimer = window.setTimeout(() => notice.classList.add("hidden"), 3600);
}

function showInitializationFailure(error: unknown) {
  systemReady = false;
  document.querySelector("#gpu")!.textContent = "NVIDIA AFX unavailable";
  document.querySelector("#architecture")!.textContent = "—";
  const model = document.querySelector("#modelState")!;
  model.textContent = "Initialization failed";
  model.className = "warning";
  const microphone = document.querySelector<HTMLSelectElement>("#microphone")!;
  microphone.replaceChildren(new Option("No microphone available", ""));
  microphone.disabled = true;
  const output = document.querySelector<HTMLSelectElement>("#monitorOutput")!;
  output.replaceChildren(new Option("No output available", ""));
  output.disabled = true;
  document.querySelector<HTMLButtonElement>("#power")!.disabled = true;
  showNotice(String(error), true);
}

function showBackgroundSettings(settings: BackgroundSettings) {
  const background = document.querySelector<HTMLButtonElement>("#runInBackground")!;
  const login = document.querySelector<HTMLButtonElement>("#startAtLogin")!;
  background.classList.toggle("active", settings.runInBackground);
  background.setAttribute("aria-pressed", String(settings.runInBackground));
  background.setAttribute("aria-label", `${settings.runInBackground ? "Disable" : "Enable"} background mode`);
  background.disabled = settings.startAtLogin;
  background.title = settings.startAtLogin ? "Turn off Start at login first" : "";
  login.classList.toggle("active", settings.startAtLogin);
  login.setAttribute("aria-pressed", String(settings.startAtLogin));
  login.setAttribute("aria-label", `${settings.startAtLogin ? "Disable" : "Enable"} start at login`);
}

async function load() {
  try {
    const [status, microphones, outputs, service, background] = await Promise.all([
      invoke<SystemStatus>("system_status"),
      invoke<Microphone[]>("list_microphones"),
      invoke<OutputDevice[]>("list_outputs"),
      invoke<ProcessingStatus>("processing_status"),
      invoke<BackgroundSettings>("background_settings"),
    ]);
    showBackgroundSettings(background);
    showStatus(status);
    const select = document.querySelector<HTMLSelectElement>("#microphone")!;
    select.replaceChildren(...microphones.map((mic) => new Option(mic.description, mic.name)));
    const remembered = window.localStorage.getItem("linux-broadcast.microphone");
    const selected = service.sourceName
      ?? microphones.find((microphone) => microphone.name === remembered)?.name
      ?? microphones.find((microphone) => microphone.isDefault)?.name
      ?? microphones[0]?.name;
    if (selected) select.value = selected;
    const outputSelect = document.querySelector<HTMLSelectElement>("#monitorOutput")!;
    outputSelect.replaceChildren(...outputs.map((output) => new Option(output.description, output.name)));
    const monitorOutput = service.monitorSinkName
      ?? outputs.find((output) => output.isDefault)?.name
      ?? outputs[0]?.name;
    if (monitorOutput) outputSelect.value = monitorOutput;
    const effectSelect = document.querySelector<HTMLSelectElement>("#effect")!;
    const rememberedEffect = window.localStorage.getItem("linux-broadcast.effect") ?? "noise_room_echo";
    const fallbackEffect = status.availableEffects[0] ?? "noise_room_echo";
    effectSelect.value = service.running
      ? service.effectMode
      : status.availableEffects.includes(rememberedEffect) ? rememberedEffect : fallbackEffect;
    const effect = effectSelect.value;
    loadRememberedTuning(effect);
    if (service.running) {
      strength.value = String(Math.round(service.intensity * 100));
      setVad(service.vadEnabled);
      document.querySelector<HTMLSelectElement>("#frameSize")!.value = String(service.frameMs);
    }
    showEffect(effectSelect.value);
    showProcessing(service);
    if (!service.running && systemReady && selected) {
      const started = await invoke<ProcessingStatus>("start_processing", {
        sourceName: selected,
        intensity: Number(strength.value) / 100,
        effectMode: selectedEffect(),
        vadEnabled: selectedVad(),
        frameMs: selectedFrameMs(),
      });
      showProcessing(started);
    }
  } catch (error) {
    showInitializationFailure(error);
  }
}

document.querySelector("#microphone")!.addEventListener("change", async () => {
  const select = document.querySelector<HTMLSelectElement>("#microphone")!;
  window.localStorage.setItem("linux-broadcast.microphone", select.value);
  if (!systemReady) return;
  try {
    const status = await invoke<ProcessingStatus>("start_processing", {
      sourceName: select.value,
      intensity: Number(strength.value) / 100,
      effectMode: selectedEffect(),
      vadEnabled: selectedVad(),
      frameMs: selectedFrameMs(),
    });
    showProcessing(status);
    showNotice(`${select.selectedOptions[0]?.text ?? "Microphone"} is now routed through Linux Broadcast`);
  } catch (error) {
    showNotice(String(error), true);
  }
});

document.querySelector("#effect")!.addEventListener("change", async () => {
  const effect = selectedEffect();
  window.localStorage.setItem("linux-broadcast.effect", effect);
  loadRememberedTuning(effect);
  showEffect(effect);
  if (!processing) return;
  try {
    const status = await invoke<ProcessingStatus>("start_processing", {
      sourceName: document.querySelector<HTMLSelectElement>("#microphone")!.value,
      intensity: Number(strength.value) / 100,
      effectMode: effect,
      vadEnabled: selectedVad(),
      frameMs: selectedFrameMs(),
    });
    showProcessing(status);
    showNotice(`${effectNames[effect]} is live`);
  } catch (error) {
    showNotice(String(error), true);
  }
});

document.querySelector("#monitor")!.addEventListener("click", async () => {
  if (!processing) {
    showNotice("Start Linux Broadcast before monitoring", true);
    return;
  }
  const button = document.querySelector<HTMLButtonElement>("#monitor")!;
  const enabled = !button.classList.contains("active");
  button.disabled = true;
  try {
    const status = await invoke<ProcessingStatus>("set_monitoring", {
      enabled,
      sinkName: document.querySelector<HTMLSelectElement>("#monitorOutput")!.value,
    });
    showProcessing(status);
    showNotice(enabled ? "Processed microphone monitoring is on" : "Microphone monitoring is off");
  } catch (error) {
    showNotice(String(error), true);
  } finally {
    button.disabled = false;
  }
});

document.querySelector("#monitorOutput")!.addEventListener("change", async () => {
  const button = document.querySelector<HTMLButtonElement>("#monitor")!;
  if (!processing || !button.classList.contains("active")) return;
  try {
    const status = await invoke<ProcessingStatus>("set_monitoring", {
      enabled: true,
      sinkName: document.querySelector<HTMLSelectElement>("#monitorOutput")!.value,
    });
    showProcessing(status);
  } catch (error) {
    showNotice(String(error), true);
  }
});

document.querySelector("#power")!.addEventListener("click", async () => {
  const power = document.querySelector<HTMLButtonElement>("#power")!;
  if (!systemReady || power.disabled) return;
  power.disabled = true;
  try {
    const status = processing
      ? await invoke<ProcessingStatus>("stop_processing")
      : await invoke<ProcessingStatus>("start_processing", {
          sourceName: document.querySelector<HTMLSelectElement>("#microphone")!.value,
          intensity: Number(strength.value) / 100,
          effectMode: selectedEffect(),
          vadEnabled: selectedVad(),
          frameMs: selectedFrameMs(),
        });
    showProcessing(status);
    showNotice(status.running ? "Linux Broadcast microphone is live" : "Voice processing stopped");
  } catch (error) {
    showNotice(String(error), true);
  } finally {
    power.disabled = !systemReady;
  }
});

strength.addEventListener("change", async () => {
  window.localStorage.setItem(`linux-broadcast.intensity.${selectedEffect()}`, strength.value);
  if (!processing) return;
  try {
    const status = await invoke<ProcessingStatus>("start_processing", {
      sourceName: document.querySelector<HTMLSelectElement>("#microphone")!.value,
      intensity: Number(strength.value) / 100,
      effectMode: selectedEffect(),
      vadEnabled: selectedVad(),
      frameMs: selectedFrameMs(),
    });
    showProcessing(status);
    showNotice(`${effectNames[selectedEffect()]} intensity set to ${strength.value}%`);
  } catch (error) {
    showNotice(String(error), true);
  }
});

document.querySelector("#vad")!.addEventListener("click", async () => {
  if (!vadEffects.has(selectedEffect())) return;
  setVad(!selectedVad());
  window.localStorage.setItem(`linux-broadcast.vad.${selectedEffect()}`, String(selectedVad()));
  if (!processing) return;
  try {
    const status = await invoke<ProcessingStatus>("start_processing", {
      sourceName: document.querySelector<HTMLSelectElement>("#microphone")!.value,
      intensity: Number(strength.value) / 100,
      effectMode: selectedEffect(),
      vadEnabled: selectedVad(),
      frameMs: selectedFrameMs(),
    });
    showProcessing(status);
    showNotice(`SDK voice gate ${status.vadEnabled ? "enabled" : "disabled"}`);
  } catch (error) {
    showNotice(String(error), true);
  }
});

document.querySelector("#frameSize")!.addEventListener("change", async () => {
  const frame = document.querySelector<HTMLSelectElement>("#frameSize")!;
  window.localStorage.setItem(`linux-broadcast.frame.${selectedEffect()}`, frame.value);
  showEffect(selectedEffect());
  if (!processing) return;
  try {
    const status = await invoke<ProcessingStatus>("start_processing", {
      sourceName: document.querySelector<HTMLSelectElement>("#microphone")!.value,
      intensity: Number(strength.value) / 100,
      effectMode: selectedEffect(),
      vadEnabled: selectedVad(),
      frameMs: selectedFrameMs(),
    });
    showProcessing(status);
    showNotice(`${status.frameMs} ms NVIDIA AFX frames are live`);
  } catch (error) {
    showNotice(String(error), true);
  }
});

document.querySelector("#resetTuning")!.addEventListener("click", async () => {
  const effect = selectedEffect();
  for (const setting of ["intensity", "vad", "frame"]) {
    window.localStorage.removeItem(`linux-broadcast.${setting}.${effect}`);
  }
  loadRememberedTuning(effect);
  showEffect(effect);
  if (!processing) {
    showNotice(`${effectNames[effect]} balanced defaults restored`);
    return;
  }
  try {
    const status = await invoke<ProcessingStatus>("start_processing", {
      sourceName: document.querySelector<HTMLSelectElement>("#microphone")!.value,
      intensity: Number(strength.value) / 100,
      effectMode: effect,
      vadEnabled: selectedVad(),
      frameMs: selectedFrameMs(),
    });
    showProcessing(status);
    showNotice(`${effectNames[effect]} balanced defaults restored`);
  } catch (error) {
    showNotice(String(error), true);
  }
});

document.querySelector("#settingsButton")!.addEventListener("click", () => {
  document.querySelector("#mainView")!.classList.add("view-hidden");
  document.querySelector("#hardwareInfo")!.classList.add("view-hidden");
  document.querySelector("#settingsView")!.classList.remove("view-hidden");
});

document.querySelector("#settingsBack")!.addEventListener("click", () => {
  document.querySelector("#settingsView")!.classList.add("view-hidden");
  document.querySelector("#mainView")!.classList.remove("view-hidden");
  document.querySelector("#hardwareInfo")!.classList.remove("view-hidden");
});

document.querySelector("#runInBackground")!.addEventListener("click", async () => {
  const button = document.querySelector<HTMLButtonElement>("#runInBackground")!;
  if (button.disabled) return;
  button.disabled = true;
  try {
    const settings = await invoke<BackgroundSettings>("set_run_in_background", {
      enabled: !button.classList.contains("active"),
    });
    showBackgroundSettings(settings);
    showNotice(settings.runInBackground ? "Linux Broadcast will stay in the tray" : "Closing the window will quit Linux Broadcast");
  } catch (error) {
    showNotice(String(error), true);
    button.disabled = false;
  }
});

document.querySelector("#startAtLogin")!.addEventListener("click", async () => {
  const button = document.querySelector<HTMLButtonElement>("#startAtLogin")!;
  button.disabled = true;
  try {
    const settings = await invoke<BackgroundSettings>("set_start_at_login", {
      enabled: !button.classList.contains("active"),
    });
    showBackgroundSettings(settings);
    showNotice(settings.startAtLogin ? "Linux Broadcast will start hidden at login" : "Start at login disabled");
  } catch (error) {
    showNotice(String(error), true);
    button.disabled = false;
  }
});

void load();
