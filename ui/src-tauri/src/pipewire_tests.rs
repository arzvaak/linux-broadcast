//! Live routing test: no NVIDIA plugin or physical-device changes required.
use super::*;

struct Controller(Child);

impl Controller {
    fn load(command: &str) -> Self {
        let mut child = Command::new("pw-cli")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("pw-cli is required");
        child.stdin.as_mut().unwrap().write_all(command.as_bytes()).unwrap();
        child.stdin.as_mut().unwrap().flush().unwrap();
        Self(child)
    }
}

impl Drop for Controller {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn snapshot() -> Vec<Value> {
    serde_json::from_str(&command_output("pw-dump", &[]).unwrap()).unwrap()
}

fn named_node(objects: &[Value], name: &str) -> Option<u64> {
    objects.iter().find_map(|object| {
        (object["type"] == "PipeWire:Interface:Node"
            && object["info"]["props"]["node.name"] == name)
            .then(|| object["id"].as_u64())
            .flatten()
    })
}

fn incoming_sources(objects: &[Value], capture: &str) -> Vec<u64> {
    let Some(id) = named_node(objects, capture) else { return vec![] };
    objects.iter().filter_map(|object| {
        (object["type"] == "PipeWire:Interface:Link"
            && object["info"]["input-node-id"].as_u64() == Some(id))
            .then(|| object["info"]["output-node-id"].as_u64())
            .flatten()
    }).collect()
}

fn wait_for(description: &str, condition: impl Fn(&[Value]) -> bool) {
    let deadline = Instant::now() + Duration::from_secs(6);
    while Instant::now() < deadline {
        if condition(&snapshot()) { return; }
        thread::sleep(Duration::from_millis(50));
    }
    panic!("Timed out waiting for {description}");
}

fn source(name: &str) -> Controller {
    Controller::load(&format!(
        "load-module libpipewire-module-loopback {{ audio.position = [ MONO ] capture.props = {{ node.name = \"{}.input\" node.autoconnect = false }} playback.props = {{ node.name = \"{}\" media.class = Audio/Source node.virtual = true node.autoconnect = false priority.session = 0 }} }}\n",
        spa_quote(name), spa_quote(name),
    ))
}

#[test]
#[ignore = "Requires a running PipeWire/WirePlumber session and pw-cli/pw-dump"]
fn reconnects_selected_source_without_restarting_filter() {
    let prefix = format!("linux_broadcast_test_{}", std::process::id());
    let source_name = format!("{prefix}.source");
    let capture_name = format!("{prefix}.capture");
    let output_name = format!("{prefix}.output");
    let _other = source(&format!("{prefix}.other"));
    let mut microphone = Some(source(&source_name));
    wait_for("synthetic microphone", |objects| named_node(objects, &source_name).is_some());

    // Use the production routing config, replacing only the GPU-dependent DSP
    // graph with a built-in copy filter and giving all test nodes unique names.
    let mut command = module_command(0.7, Path::new("/unused-test-plugin.so"), &source_name);
    let graph_start = command.find("filter.graph =").unwrap();
    let graph_end = command.find(" audio.rate").unwrap();
    command.replace_range(graph_start..graph_end,
        "filter.graph = { nodes = [ { type = builtin name = copy label = copy } ] }");
    command = command.replace("linux_broadcast.capture", &capture_name)
        .replace(VIRTUAL_SOURCE_NAME, &output_name);
    let filter = Controller::load(&command);
    wait_for_microphone_link(&source_name, &capture_name).unwrap();
    wait_for("initial connection", |objects| {
        incoming_sources(objects, &capture_name) == [named_node(objects, &source_name).unwrap_or(0)]
    });
    let filter_id = named_node(&snapshot(), &capture_name).unwrap();

    for _ in 0..2 {
        drop(microphone.take());
        wait_for("source removal", |objects| named_node(objects, &source_name).is_none());
        // A missing selected input must not capture another mic or the virtual output.
        let deadline = Instant::now() + Duration::from_millis(500);
        while Instant::now() < deadline {
            let objects = snapshot();
            assert_eq!(named_node(&objects, &capture_name), Some(filter_id));
            assert!(incoming_sources(&objects, &capture_name).is_empty());
            thread::sleep(Duration::from_millis(50));
        }
        microphone = Some(source(&source_name));
        wait_for("automatic reconnection", |objects| {
            incoming_sources(objects, &capture_name) == [named_node(objects, &source_name).unwrap_or(0)]
        });
        assert_eq!(named_node(&snapshot(), &capture_name), Some(filter_id));
    }

    drop(filter);
    wait_for("filter removal after Stop", |objects| named_node(objects, &capture_name).is_none());
    drop(microphone.take());
    wait_for("stopped source removal", |objects| named_node(objects, &source_name).is_none());
    microphone = Some(source(&source_name));
    wait_for("source returning after Stop", |objects| named_node(objects, &source_name).is_some());
    assert!(named_node(&snapshot(), &capture_name).is_none());
    drop(microphone);
}
