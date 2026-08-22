use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use tauri::{menu::MenuBuilder, tray::TrayIconBuilder, Manager, WindowEvent};
use std::{
    env,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::Mutex,
    thread,
    time::{Duration, Instant},
};

const VIRTUAL_SOURCE_NAME: &str = "linux_broadcast.source";

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SystemStatus {
    gpu_name: String,
    compute_capability: String,
    architecture: String,
    model_ready: bool,
    plugin_ready: bool,
}

#[derive(Clone)]
struct GpuTarget {
    index: u32,
    name: String,
    compute_capability: String,
    architecture: &'static str,
    model_ready: bool,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Microphone {
    id: u64,
    name: String,
    description: String,
    is_default: bool,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct OutputDevice {
    name: String,
    description: String,
    is_default: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ProcessingStatus {
    running: bool,
    source_name: Option<String>,
    intensity: f32,
    monitoring: bool,
    monitor_sink_name: Option<String>,
    effect_mode: String,
    vad_enabled: bool,
    frame_ms: u32,
}

struct ServiceProcess {
    child: Child,
    source_name: String,
    intensity: f32,
    monitor: Option<Child>,
    monitor_sink_name: Option<String>,
    effect_mode: String,
    vad_enabled: bool,
    frame_ms: u32,
}

#[derive(Default)]
struct ServiceState {
    process: Mutex<Option<ServiceProcess>>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct BackgroundSettings {
    run_in_background: bool,
    start_at_login: bool,
}

impl Default for BackgroundSettings {
    fn default() -> Self {
        Self { run_in_background: true, start_at_login: false }
    }
}

struct PreferencesState {
    settings: Mutex<BackgroundSettings>,
}

impl Default for PreferencesState {
    fn default() -> Self {
        Self { settings: Mutex::new(load_background_settings()) }
    }
}

impl Drop for ServiceState {
    fn drop(&mut self) {
        if let Ok(process) = self.process.get_mut() {
            if let Some(service) = process.as_mut() {
                let source_name = service.source_name.clone();
                stop_monitor(&mut service.monitor);
                stop_child(&mut service.child);
                restore_physical_default(&source_name);
            }
        }
    }
}

fn command_output(program: &str, arguments: &[&str]) -> Result<String, String> {
    let output = Command::new(program)
        .args(arguments)
        .output()
        .map_err(|error| format!("Could not run {program}: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_owned());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

fn preferences_path() -> Option<PathBuf> {
    env::var_os("HOME")
        .map(PathBuf::from)
        .map(|home| home.join(".config/linux-broadcast/preferences.json"))
}

fn load_background_settings() -> BackgroundSettings {
    preferences_path()
        .and_then(|path| fs::read_to_string(path).ok())
        .and_then(|contents| serde_json::from_str(&contents).ok())
        .unwrap_or_default()
}

fn write_file_atomically(destination: &Path, contents: &[u8], mode: u32) -> Result<(), String> {
    let parent = destination
        .parent()
        .ok_or_else(|| format!("Invalid file path: {}", destination.display()))?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let temporary = destination.with_extension(format!("installing-{}", std::process::id()));
    let result = (|| {
        fs::write(&temporary, contents).map_err(|error| error.to_string())?;
        fs::set_permissions(&temporary, fs::Permissions::from_mode(mode))
            .map_err(|error| error.to_string())?;
        fs::rename(&temporary, destination).map_err(|error| error.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn save_background_settings(settings: &BackgroundSettings) -> Result<(), String> {
    let path = preferences_path().ok_or_else(|| "Could not locate the user configuration directory".to_owned())?;
    let contents = serde_json::to_string_pretty(settings).map_err(|error| error.to_string())?;
    write_file_atomically(&path, contents.as_bytes(), 0o600)
}

fn install_file(source: &Path, destination: &Path, mode: u32) -> Result<(), String> {
    let parent = destination
        .parent()
        .ok_or_else(|| format!("Invalid installation path: {}", destination.display()))?;
    fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    let temporary = destination.with_extension(format!("installing-{}", std::process::id()));
    let result = (|| {
        fs::copy(source, &temporary).map_err(|error| error.to_string())?;
        fs::set_permissions(&temporary, fs::Permissions::from_mode(mode))
            .map_err(|error| error.to_string())?;
        fs::rename(&temporary, destination).map_err(|error| error.to_string())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn install_login_service() -> Result<(), String> {
    let home = env::var_os("HOME").map(PathBuf::from).ok_or_else(|| "Could not locate HOME".to_owned())?;
    let executable = env::current_exe().map_err(|error| error.to_string())?;
    let installed_executable = home.join(".local/bin/linux-broadcast");
    let installed_plugin = home.join(".local/lib/linux-broadcast/liblinux_broadcast_afx_ladspa.so");
    let unit = home.join(".config/systemd/user/linux-broadcast.service");
    for path in [&installed_executable, &installed_plugin, &unit] {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
    }
    if executable.canonicalize().ok() != installed_executable.canonicalize().ok() {
        install_file(&executable, &installed_executable, 0o755)?;
    }
    let plugin = installation_plugin_path()?;
    if plugin.canonicalize().ok() != installed_plugin.canonicalize().ok() {
        install_file(&plugin, &installed_plugin, 0o755)?;
    }
    write_file_atomically(
        &unit,
        include_str!("../../../systemd/linux-broadcast.service").as_bytes(),
        0o644,
    )?;
    command_output("systemctl", &["--user", "daemon-reload"])?;
    command_output("systemctl", &["--user", "reenable", "linux-broadcast.service"])?;
    Ok(())
}

fn architecture_for(capability: &str) -> Result<&'static str, String> {
    match capability {
        "7.5" => Ok("sm_75"),
        "8.6" => Ok("sm_86"),
        "8.9" => Ok("sm_89"),
        "12.0" => Ok("sm_120"),
        value => Err(format!("No BNR 2.0 model mapping for compute capability {value}")),
    }
}

fn model_path(sdk: &Path, architecture: &str) -> PathBuf {
    sdk.join("features/denoiser/models")
        .join(architecture)
        .join("denoiser_v2_48k.trtpkg")
}

fn parse_gpu_targets(raw: &str, sdk: Option<&Path>) -> Vec<GpuTarget> {
    raw.lines()
        .filter_map(|line| {
            let mut fields = line.splitn(3, ',').map(str::trim);
            let index = fields.next()?.parse().ok()?;
            let name = fields.next()?.to_owned();
            if !name.to_ascii_uppercase().contains("RTX") {
                return None;
            }
            let compute_capability = fields.next()?.to_owned();
            let architecture = architecture_for(&compute_capability).ok()?;
            let model_ready = sdk.is_some_and(|root| model_path(root, architecture).exists());
            Some(GpuTarget {
                index,
                name,
                compute_capability,
                architecture,
                model_ready,
            })
        })
        .collect()
}

fn choose_gpu(mut targets: Vec<GpuTarget>) -> Result<GpuTarget, String> {
    targets.sort_by_key(|target| (!target.model_ready, target.index));
    targets.into_iter().next().ok_or_else(|| {
        "No supported RTX GPU was found. Linux Broadcast requires compute capability 7.5, 8.6, 8.9, or 12.0"
            .to_owned()
    })
}

fn selected_gpu() -> Result<GpuTarget, String> {
    let raw = command_output(
        "nvidia-smi",
        &[
            "--query-gpu=index,name,compute_cap",
            "--format=csv,noheader,nounits",
        ],
    )?;
    let sdk = sdk_root().ok();
    let targets = parse_gpu_targets(&raw, sdk.as_deref());
    if let Some(configured) = env::var_os("LINUX_BROADCAST_GPU_INDEX") {
        let index = configured
            .to_string_lossy()
            .parse::<u32>()
            .map_err(|_| "LINUX_BROADCAST_GPU_INDEX must be a non-negative integer".to_owned())?;
        return targets
            .into_iter()
            .find(|target| target.index == index)
            .ok_or_else(|| format!("GPU {index} is not a supported RTX GPU"));
    }
    choose_gpu(targets)
}

fn validate_effect_mode(mode: &str) -> Result<(), String> {
    match mode {
        "noise" | "bnr2" | "room_echo" | "noise_room_echo" | "studio_voice" => Ok(()),
        _ => Err(format!("Unsupported NVIDIA AFX effect mode: {mode}")),
    }
}

fn validate_frame_ms(effect_mode: &str, frame_ms: u32) -> Result<(), String> {
    match (effect_mode, frame_ms) {
        ("studio_voice", 10) | ("noise" | "bnr2" | "room_echo" | "noise_room_echo", 10 | 20) => Ok(()),
        ("studio_voice", _) => Err("Studio Voice Low Latency requires 10 ms SDK frames".to_owned()),
        (_, _) => Err("NVIDIA AFX frame size must be 10 or 20 ms".to_owned()),
    }
}

fn sdk_root() -> Result<PathBuf, String> {
    if let Some(configured) = env::var_os("AFX_SDK_ROOT") {
        return Ok(PathBuf::from(configured));
    }
    env::var_os("HOME")
        .map(PathBuf::from)
        .map(|home| home.join(".local/share/linux-broadcast/nvidia/current"))
        .ok_or_else(|| "Could not locate the user-local AFX SDK".to_owned())
}

fn plugin_path() -> Result<PathBuf, String> {
    if let Some(configured) = env::var_os("LINUX_BROADCAST_PLUGIN") {
        let path = PathBuf::from(configured);
        if path.is_file() {
            return Ok(path);
        }
    }
    if let Some(home) = env::var_os("HOME") {
        let installed = PathBuf::from(home)
            .join(".local/lib/linux-broadcast/liblinux_broadcast_afx_ladspa.so");
        if installed.is_file() {
            return installed.canonicalize().map_err(|error| error.to_string());
        }
    }
    if let Some(bundled) = env::var_os("LINUX_BROADCAST_BUNDLED_PLUGIN") {
        let path = PathBuf::from(bundled);
        if path.is_file() {
            return path.canonicalize().map_err(|error| error.to_string());
        }
    }
    let development = development_plugin_path()?;
    development
        .canonicalize()
        .map_err(|_| format!("Native AFX plugin not found: {}", development.display()))
}

fn development_plugin_path() -> Result<PathBuf, String> {
    let executable = env::current_exe().map_err(|error| error.to_string())?;
    let directory = executable
        .parent()
        .ok_or_else(|| "Could not locate the application directory".to_owned())?;
    Ok(directory.join("../../../../build/native-cmake/liblinux_broadcast_afx_ladspa.so"))
}

fn installation_plugin_path() -> Result<PathBuf, String> {
    if let Some(configured) = env::var_os("LINUX_BROADCAST_PLUGIN") {
        let path = PathBuf::from(configured);
        if path.is_file() {
            return path.canonicalize().map_err(|error| error.to_string());
        }
    }
    let development = development_plugin_path()?;
    if development.is_file() {
        return development.canonicalize().map_err(|error| error.to_string());
    }
    plugin_path()
}

fn list_physical_microphones() -> Result<Vec<Microphone>, String> {
    let default_source = command_output(
        "wpctl",
        &["inspect", "@DEFAULT_AUDIO_SOURCE@"],
    )
        .ok()
        .and_then(|output| {
            output.lines().find_map(|line| {
                let value = line.trim().trim_start_matches("* ");
                value
                    .strip_prefix("node.name = \"")
                    .and_then(|name| name.strip_suffix('"'))
                    .map(str::to_owned)
            })
        });
    let raw = command_output("pw-dump", &[])?;
    let objects: Vec<Value> = serde_json::from_str(&raw).map_err(|error| error.to_string())?;
    let mut microphones = objects
        .into_iter()
        .filter_map(|object| {
            let id = object.get("id")?.as_u64()?;
            let props = object.get("info")?.get("props")?;
            if props.get("media.class")?.as_str()? != "Audio/Source" {
                return None;
            }
            let name = props.get("node.name")?.as_str()?.to_owned();
            if name == VIRTUAL_SOURCE_NAME || props.get("node.virtual").and_then(Value::as_bool) == Some(true) {
                return None;
            }
            let description = props
                .get("node.description")
                .or_else(|| props.get("node.nick"))?
                .as_str()?
                .to_owned();
            let is_default = default_source.as_deref() == Some(&name);
            Some(Microphone { id, name, description, is_default })
        })
        .collect::<Vec<_>>();
    microphones.sort_by(|left, right| left.description.cmp(&right.description));
    Ok(microphones)
}

fn list_output_devices() -> Result<Vec<OutputDevice>, String> {
    let default_sink = command_output(
        "wpctl",
        &["inspect", "@DEFAULT_AUDIO_SINK@"],
    )
        .ok()
        .and_then(|output| {
            output.lines().find_map(|line| {
                let value = line.trim().trim_start_matches("* ");
                value
                    .strip_prefix("node.name = \"")
                    .and_then(|name| name.strip_suffix('"'))
                    .map(str::to_owned)
            })
        });
    let raw = command_output("pw-dump", &[])?;
    let objects: Vec<Value> = serde_json::from_str(&raw).map_err(|error| error.to_string())?;
    let mut outputs = objects
        .into_iter()
        .filter_map(|object| {
            let props = object.get("info")?.get("props")?;
            if props.get("media.class")?.as_str()? != "Audio/Sink" {
                return None;
            }
            let name = props.get("node.name")?.as_str()?.to_owned();
            let description = props
                .get("node.description")
                .or_else(|| props.get("node.nick"))?
                .as_str()?
                .to_owned();
            let is_default = default_sink.as_deref() == Some(&name);
            Some(OutputDevice { name, description, is_default })
        })
        .collect::<Vec<_>>();
    outputs.sort_by(|left, right| left.description.cmp(&right.description));
    Ok(outputs)
}

fn virtual_source_exists() -> bool {
    virtual_source_id().is_some()
}

fn virtual_source_id() -> Option<u64> {
    node_id(VIRTUAL_SOURCE_NAME)
}

fn node_id(node_name: &str) -> Option<u64> {
    command_output("pw-dump", &[])
        .ok()
        .and_then(|raw| serde_json::from_str::<Vec<Value>>(&raw).ok())
        .and_then(|objects| {
            objects.into_iter().find_map(|object| {
                let is_virtual_source = object
                    .get("info")
                    .and_then(|info| info.get("props"))
                    .and_then(|props| props.get("node.name"))
                    .and_then(Value::as_str)
                    == Some(node_name);
                is_virtual_source.then(|| object.get("id")?.as_u64()).flatten()
            })
        })
}

fn monitor_source_name() -> &'static str {
    if node_id("easyeffects_source").is_some() {
        "easyeffects_source"
    } else {
        VIRTUAL_SOURCE_NAME
    }
}

fn set_default_source(id: u64) -> Result<(), String> {
    command_output("wpctl", &["set-default", &id.to_string()]).map(|_| ())
}

fn restore_physical_default(source_name: &str) {
    if let Ok(microphones) = list_physical_microphones() {
        if let Some(microphone) = microphones.iter().find(|microphone| microphone.name == source_name) {
            let _ = set_default_source(microphone.id);
        }
    }
}

fn spa_quote(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn module_command(intensity: f32, plugin: &Path) -> String {
    format!(
        "load-module libpipewire-module-filter-chain {{ node.description = \"Linux Broadcast Microphone\" media.name = \"Linux Broadcast Microphone\" filter.graph = {{ nodes = [ {{ type = ladspa name = \"NVIDIA AFX\" plugin = \"{}\" label = \"linux_broadcast_bnr2\" control = {{ \"Intensity\" = {:.4} }} }} ] }} audio.rate = 48000 audio.position = [ MONO ] capture.props = {{ node.name = \"linux_broadcast.capture\" node.passive = true node.autoconnect = false node.dont-reconnect = true stream.dont-remix = true audio.position = [ MONO ] }} playback.props = {{ node.name = \"{}\" node.description = \"Linux Broadcast Microphone\" media.class = Audio/Source node.virtual = true }} }}\n",
        spa_quote(&plugin.display().to_string()),
        intensity,
        VIRTUAL_SOURCE_NAME,
    )
}

fn runtime_library_path(sdk: &Path) -> String {
    let mut paths = vec![
        sdk.join("nvafx/lib"),
        sdk.join("features/denoiser/lib"),
        sdk.join("features/dereverb/lib"),
        sdk.join("features/dereverb_denoiser/lib"),
        sdk.join("features/studio_voice/lib"),
        sdk.join("external/cuda/lib"),
    ];
    if let Some(existing) = env::var_os("LD_LIBRARY_PATH") {
        paths.extend(env::split_paths(&existing));
    }
    env::join_paths(paths)
        .unwrap_or_default()
        .to_string_lossy()
        .into_owned()
}

fn spawn_service(intensity: f32, effect_mode: &str, vad_enabled: bool, frame_ms: u32) -> Result<Child, String> {
    let sdk = sdk_root()?;
    let plugin = plugin_path()?;
    let gpu = selected_gpu()?;
    let gpu_index = gpu.index.to_string();
    let mut child = Command::new("pw-cli")
        .env("AFX_SDK_ROOT", &sdk)
        .env("CUDA_VISIBLE_DEVICES", &gpu_index)
        .env("LINUX_BROADCAST_GPU_INDEX", &gpu_index)
        .env("LINUX_BROADCAST_EFFECT", effect_mode)
        .env("LINUX_BROADCAST_VAD", if vad_enabled { "1" } else { "0" })
        .env("LINUX_BROADCAST_FRAME_MS", frame_ms.to_string())
        .env("LD_LIBRARY_PATH", runtime_library_path(&sdk))
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("Could not start PipeWire controller: {error}"))?;
    let module = module_command(intensity, &plugin);
    let write_result = child
        .stdin
        .as_mut()
        .ok_or_else(|| "PipeWire controller stdin is unavailable".to_owned())
        .and_then(|stdin| {
            stdin
                .write_all(module.as_bytes())
                .map_err(|error| format!("Could not load the NVIDIA AFX module: {error}"))
        });
    if let Err(error) = write_result {
        let _ = child.kill();
        let _ = child.wait();
        return Err(error);
    }
    Ok(child)
}

fn ports_for(direction: &str, node_name: &str) -> Vec<String> {
    command_output("pw-link", &[direction])
        .unwrap_or_default()
        .lines()
        .map(str::trim)
        .filter(|port| port.starts_with(&format!("{node_name}:")))
        .map(str::to_owned)
        .collect()
}

fn link_nodes(source_name: &str, target_name: &str) -> Result<(), String> {
    let deadline = Instant::now() + Duration::from_secs(4);
    while Instant::now() < deadline {
        let source_ports = ports_for("-o", source_name);
        let target_ports = ports_for("-i", target_name);
        if !source_ports.is_empty() && !target_ports.is_empty() {
            for (index, target) in target_ports.iter().enumerate() {
                let source = source_ports.get(index).unwrap_or(&source_ports[0]);
                command_output("pw-link", &[source, target])?;
            }
            return Ok(());
        }
        thread::sleep(Duration::from_millis(80));
    }
    Err(format!("Could not connect {source_name} to {target_name}"))
}

fn link_microphone(source_name: &str) -> Result<(), String> {
    link_nodes(source_name, "linux_broadcast.capture")
}

fn stop_child(child: &mut Child) {
    if let Some(stdin) = child.stdin.as_mut() {
        let _ = stdin.write_all(b"quit\n");
        let _ = stdin.flush();
    }
    let deadline = Instant::now() + Duration::from_secs(2);
    while Instant::now() < deadline {
        if child.try_wait().ok().flatten().is_some() {
            return;
        }
        thread::sleep(Duration::from_millis(40));
    }
    let _ = child.kill();
    let _ = child.wait();
}

fn stop_monitor(monitor: &mut Option<Child>) {
    if let Some(mut child) = monitor.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
}

fn spawn_monitor(sink_name: &str) -> Result<Child, String> {
    let mut child = Command::new("pw-loopback")
        .args([
            "--name",
            "linux-broadcast-monitor",
            "--latency",
            "30",
            "--capture-props",
            "{ node.autoconnect = false }",
            "--playback-props",
            "{ node.autoconnect = false }",
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("Could not start microphone monitoring: {error}"))?;
    let connected = link_nodes(monitor_source_name(), "input.linux-broadcast-monitor")
        .and_then(|_| link_nodes("output.linux-broadcast-monitor", sink_name));
    if let Err(error) = connected {
        let _ = child.kill();
        let _ = child.wait();
        return Err(error);
    }
    Ok(child)
}

fn stop_locked(process: &mut Option<ServiceProcess>) {
    if let Some(mut service) = process.take() {
        stop_monitor(&mut service.monitor);
        stop_child(&mut service.child);
    }
}

#[tauri::command]
fn system_status() -> Result<SystemStatus, String> {
    let gpu = selected_gpu()?;
    Ok(SystemStatus {
        gpu_name: gpu.name,
        compute_capability: gpu.compute_capability,
        architecture: gpu.architecture.to_owned(),
        model_ready: gpu.model_ready,
        plugin_ready: plugin_path().is_ok(),
    })
}

#[tauri::command]
fn list_microphones() -> Result<Vec<Microphone>, String> {
    list_physical_microphones()
}

#[tauri::command]
fn list_outputs() -> Result<Vec<OutputDevice>, String> {
    list_output_devices()
}

#[tauri::command]
fn processing_status(state: tauri::State<'_, ServiceState>) -> Result<ProcessingStatus, String> {
    let mut process = state.process.lock().map_err(|_| "Service state lock failed")?;
    if process.as_mut().is_some_and(|service| service.child.try_wait().ok().flatten().is_some()) {
        let source_name = process.as_ref().map(|service| service.source_name.clone());
        stop_locked(&mut process);
        if let Some(source_name) = source_name {
            restore_physical_default(&source_name);
        }
    }
    if let Some(service) = process.as_mut() {
        if service.monitor.as_mut().is_some_and(|monitor| monitor.try_wait().ok().flatten().is_some()) {
            service.monitor = None;
            service.monitor_sink_name = None;
        }
    }
    Ok(ProcessingStatus {
        running: process.is_some() && virtual_source_exists(),
        source_name: process.as_ref().map(|service| service.source_name.clone()),
        intensity: process.as_ref().map_or(1.0, |service| service.intensity),
        monitoring: process.as_ref().is_some_and(|service| service.monitor.is_some()),
        monitor_sink_name: process.as_ref().and_then(|service| service.monitor_sink_name.clone()),
        effect_mode: process.as_ref().map_or_else(|| "noise".to_owned(), |service| service.effect_mode.clone()),
        vad_enabled: process.as_ref().is_none_or(|service| service.vad_enabled),
        frame_ms: process.as_ref().map_or(10, |service| service.frame_ms),
    })
}

#[tauri::command]
fn start_processing(
    source_name: String,
    intensity: f32,
    effect_mode: String,
    vad_enabled: bool,
    frame_ms: u32,
    state: tauri::State<'_, ServiceState>,
) -> Result<ProcessingStatus, String> {
    if !(0.0..=1.0).contains(&intensity) {
        return Err("Intensity must be between 0 and 1".to_owned());
    }
    validate_effect_mode(&effect_mode)?;
    validate_frame_ms(&effect_mode, frame_ms)?;
    let microphone = list_physical_microphones()?
        .into_iter()
        .find(|microphone| microphone.name == source_name)
        .ok_or_else(|| "The selected physical microphone is no longer available".to_owned())?;
    let mut process = state.process.lock().map_err(|_| "Service state lock failed")?;
    let monitor_sink_name = process.as_ref().and_then(|service| {
        service.monitor.as_ref()?;
        service.monitor_sink_name.clone()
    });
    stop_locked(&mut process);
    let mut child = spawn_service(intensity, &effect_mode, vad_enabled, frame_ms)?;
    if let Err(error) = link_microphone(&microphone.name) {
        stop_child(&mut child);
        return Err(error);
    }
    *process = Some(ServiceProcess {
        child,
        source_name: source_name.clone(),
        intensity,
        monitor: None,
        monitor_sink_name: None,
        effect_mode: effect_mode.clone(),
        vad_enabled,
        frame_ms,
    });

    let deadline = Instant::now() + Duration::from_secs(8);
    while Instant::now() < deadline {
        if virtual_source_exists() {
            if let Some(id) = virtual_source_id() {
                if let Err(error) = set_default_source(id) {
                    stop_locked(&mut process);
                    restore_physical_default(&source_name);
                    return Err(error);
                }
            }
            if let Some(sink_name) = monitor_sink_name {
                let output = list_output_devices()?
                    .into_iter()
                    .find(|output| output.name == sink_name);
                if let (Some(output), Some(service)) = (output, process.as_mut()) {
                    let monitor = match spawn_monitor(&output.name) {
                        Ok(monitor) => monitor,
                        Err(error) => {
                            stop_locked(&mut process);
                            restore_physical_default(&source_name);
                            return Err(error);
                        }
                    };
                    service.monitor = Some(monitor);
                    service.monitor_sink_name = Some(sink_name);
                }
            }
            let monitoring = process.as_ref().is_some_and(|service| service.monitor.is_some());
            let monitor_sink_name = process.as_ref().and_then(|service| service.monitor_sink_name.clone());
            return Ok(ProcessingStatus {
                running: true,
                source_name: Some(source_name),
                intensity,
                monitoring,
                monitor_sink_name,
                effect_mode,
                vad_enabled,
                frame_ms,
            });
        }
        if process.as_mut().and_then(|service| service.child.try_wait().ok().flatten()).is_some() {
            *process = None;
            return Err(format!("AFX/PipeWire service exited while loading {effect_mode}"));
        }
        thread::sleep(Duration::from_millis(100));
    }
    stop_locked(&mut process);
    Err("Linux Broadcast virtual microphone did not appear".to_owned())
}

#[tauri::command]
fn stop_processing(state: tauri::State<'_, ServiceState>) -> Result<ProcessingStatus, String> {
    let mut process = state.process.lock().map_err(|_| "Service state lock failed")?;
    let source_name = process.as_ref().map(|service| service.source_name.clone());
    stop_locked(&mut process);
    if let Some(source_name) = source_name {
        restore_physical_default(&source_name);
    }
    Ok(ProcessingStatus {
        running: false,
        source_name: None,
        intensity: 1.0,
        monitoring: false,
        monitor_sink_name: None,
        effect_mode: "noise".to_owned(),
        vad_enabled: true,
        frame_ms: 10,
    })
}

#[tauri::command]
fn set_monitoring(
    enabled: bool,
    sink_name: Option<String>,
    state: tauri::State<'_, ServiceState>,
) -> Result<ProcessingStatus, String> {
    let mut process = state.process.lock().map_err(|_| "Service state lock failed")?;
    let service = process.as_mut().ok_or_else(|| "Start voice processing before monitoring".to_owned())?;
    stop_monitor(&mut service.monitor);
    service.monitor_sink_name = None;

    if enabled {
        let sink_name = sink_name.ok_or_else(|| "Choose an output device".to_owned())?;
        let output = list_output_devices()?
            .into_iter()
            .find(|output| output.name == sink_name)
            .ok_or_else(|| "The selected output device is no longer available".to_owned())?;
        service.monitor = Some(spawn_monitor(&output.name)?);
        service.monitor_sink_name = Some(output.name);
    }

    Ok(ProcessingStatus {
        running: true,
        source_name: Some(service.source_name.clone()),
        intensity: service.intensity,
        monitoring: service.monitor.is_some(),
        monitor_sink_name: service.monitor_sink_name.clone(),
        effect_mode: service.effect_mode.clone(),
        vad_enabled: service.vad_enabled,
        frame_ms: service.frame_ms,
    })
}

#[tauri::command]
fn background_settings(state: tauri::State<'_, PreferencesState>) -> Result<BackgroundSettings, String> {
    let mut settings = state.settings.lock().map_err(|_| "Preferences state lock failed")?;
    settings.start_at_login = command_output("systemctl", &["--user", "is-enabled", "linux-broadcast.service"]).is_ok();
    Ok(settings.clone())
}

#[tauri::command]
fn set_run_in_background(
    enabled: bool,
    state: tauri::State<'_, PreferencesState>,
) -> Result<BackgroundSettings, String> {
    let mut settings = state.settings.lock().map_err(|_| "Preferences state lock failed")?;
    if !enabled && settings.start_at_login {
        return Err("Turn off Start at login before disabling background mode".to_owned());
    }
    settings.run_in_background = enabled;
    save_background_settings(&settings)?;
    Ok(settings.clone())
}

#[tauri::command]
fn set_start_at_login(
    enabled: bool,
    state: tauri::State<'_, PreferencesState>,
) -> Result<BackgroundSettings, String> {
    if enabled {
        install_login_service()?;
    } else {
        let _ = command_output("systemctl", &["--user", "disable", "linux-broadcast.service"]);
    }
    let mut settings = state.settings.lock().map_err(|_| "Preferences state lock failed")?;
    settings.start_at_login = enabled;
    if enabled {
        settings.run_in_background = true;
    }
    save_background_settings(&settings)?;
    Ok(settings.clone())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // WebKitGTK's DMA-BUF renderer can produce blank windows with NVIDIA's driver.
    if env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
    let start_hidden = env::args_os().any(|argument| argument == "--background");
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, arguments, _| {
            if arguments.iter().any(|argument| argument == "--background") {
                return;
            }
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .manage(ServiceState::default())
        .manage(PreferencesState::default())
        .setup(move |app| {
            if let Ok(resource_dir) = app.path().resource_dir() {
                let bundled_plugin = resource_dir
                    .join("lib/linux-broadcast/liblinux_broadcast_afx_ladspa.so");
                if bundled_plugin.is_file() {
                    env::set_var("LINUX_BROADCAST_BUNDLED_PLUGIN", bundled_plugin);
                }
            }
            let menu = MenuBuilder::new(app)
                .text("open", "Open Linux Broadcast")
                .text("quit", "Quit Linux Broadcast")
                .build()?;
            let mut tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("Linux Broadcast")
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "open" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.unminimize();
                            let _ = window.set_focus();
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                });
            if let Some(icon) = app.default_window_icon().cloned() {
                tray = tray.icon(icon);
            }
            tray.build(app)?;
            if start_hidden {
                if let Some(window) = app.get_webview_window("main") {
                    window.hide()?;
                }
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                let keep_running = window
                    .state::<PreferencesState>()
                    .settings
                    .lock()
                    .map(|settings| settings.run_in_background)
                    .unwrap_or(true);
                if keep_running {
                    api.prevent_close();
                    let _ = window.hide();
                } else {
                    api.prevent_close();
                    window.app_handle().exit(0);
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            system_status,
            list_microphones,
            list_outputs,
            processing_status,
            start_processing,
            stop_processing,
            set_monitoring,
            background_settings,
            set_run_in_background,
            set_start_at_login
        ])
        .run(tauri::generate_context!())
        .expect("Linux Broadcast Tauri runtime failed");
}

#[cfg(test)]
mod tests {
    use super::{
        architecture_for, choose_gpu, parse_gpu_targets, spa_quote, validate_frame_ms, GpuTarget,
    };

    #[test]
    fn maps_all_rtx_generations() {
        assert_eq!(architecture_for("7.5").unwrap(), "sm_75");
        assert_eq!(architecture_for("8.6").unwrap(), "sm_86");
        assert_eq!(architecture_for("8.9").unwrap(), "sm_89");
        assert_eq!(architecture_for("12.0").unwrap(), "sm_120");
        assert!(architecture_for("8.0").is_err());
    }

    #[test]
    fn quotes_pipewire_values() {
        assert_eq!(spa_quote("mic\\\"one"), "mic\\\\\\\"one");
    }

    #[test]
    fn validates_effect_frame_sizes() {
        assert!(validate_frame_ms("noise", 10).is_ok());
        assert!(validate_frame_ms("noise", 20).is_ok());
        assert!(validate_frame_ms("studio_voice", 10).is_ok());
        assert!(validate_frame_ms("studio_voice", 20).is_err());
        assert!(validate_frame_ms("noise", 40).is_err());
    }

    #[test]
    fn parses_every_rtx_architecture() {
        let targets = parse_gpu_targets(
            "0, Quadro RTX 8000, 7.5\n1, GeForce RTX 3060 Laptop GPU, 8.6\n2, NVIDIA RTX 6000 Ada Generation, 8.9\n3, NVIDIA RTX PRO 6000 Blackwell, 12.0\n4, GeForce GTX 1650 Ti, 7.5",
            None,
        );
        assert_eq!(targets.len(), 4);
        assert_eq!(targets[0].architecture, "sm_75");
        assert_eq!(targets[1].architecture, "sm_86");
        assert_eq!(targets[2].architecture, "sm_89");
        assert_eq!(targets[3].architecture, "sm_120");
    }

    #[test]
    fn prefers_an_rtx_gpu_with_an_installed_model() {
        let targets = vec![
            GpuTarget {
                index: 0,
                name: "NVIDIA GeForce RTX 2080".to_owned(),
                compute_capability: "7.5".to_owned(),
                architecture: "sm_75",
                model_ready: false,
            },
            GpuTarget {
                index: 1,
                name: "NVIDIA GeForce RTX 4080".to_owned(),
                compute_capability: "8.9".to_owned(),
                architecture: "sm_89",
                model_ready: true,
            },
            GpuTarget {
                index: 2,
                name: "NVIDIA GeForce RTX 5090".to_owned(),
                compute_capability: "12.0".to_owned(),
                architecture: "sm_120",
                model_ready: false,
            },
        ];
        assert_eq!(choose_gpu(targets).unwrap().index, 1);
    }
}
