use std::{
    collections::HashMap,
    fmt::Write as _,
    fs,
    fs::OpenOptions,
    io::Write,
    path::{Path, PathBuf},
    time::Duration,
};

use anyhow::{Context, Result, anyhow};
use chrono::Local;
use diffy::Patch;
use fs2::FileExt;
use reqwest::blocking::Client as HttpClient;
use serde::{Deserialize, Serialize};
use serde_json::{self, json};
use serde_yaml::Value as YamlValue;
use sha2::{Digest, Sha256};
use tempfile::NamedTempFile;

const ARTIFACTS_DIR: &str = "artifacts";
const DESCRIPTION_FILE: &str = "description.md";
const PHASING_FILE: &str = "phasing.md";
const PHASING_INDEX_FILE: &str = "phasing_index.json";

pub const ARTIFACT_PROMPT_ENV: &str = "WALKCOACH_ARTIFACT_PROMPT_PATH";
const DEFAULT_PROMPT_PATH: &str = "config/artifact_editor_prompt.txt";
const DEFAULT_ARTIFACT_MODEL: &str = "moonshotai/kimi-k2-instruct-0905";
const DEFAULT_ARTIFACT_TEMPERATURE: f32 = 0.0;
const DEFAULT_ARTIFACT_MAX_TOKENS: u32 = 800;

#[derive(Debug, Deserialize)]
pub struct ArtifactEditorResponse {
    pub rationale: String,
    #[serde(default)]
    pub patches: Vec<ArtifactPatch>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ArtifactPatch {
    pub path: String,
    #[serde(rename = "type")]
    pub kind: ArtifactPatchType,
    pub data: String,
}

#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactPatchType {
    UnifiedDiff,
    YamlMerge,
}

pub struct ArtifactStore {
    root: PathBuf,
}

#[derive(Debug, Default, Serialize, Deserialize, Clone)]
pub struct PhasingIndex {
    pub phases: Vec<PhasingEntry>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct PhasingEntry {
    pub number: u32,
    pub title: String,
    pub talk_track: String,
    pub hash: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub audio_path: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AppliedPatchReport {
    pub applied: Vec<PathBuf>,
    pub rejected: Vec<RejectedPatch>,
    pub phasing_changed: bool,
}

#[derive(Debug, Clone)]
pub struct RejectedPatch {
    pub path: PathBuf,
    pub reason: String,
    pub reject_path: PathBuf,
}

pub struct ArtifactEditor {
    http: HttpClient,
    base_url: String,
    api_key: String,
    model: String,
    system_prompt: String,
    temperature: f32,
    max_tokens: u32,
}

pub struct ArtifactEditorInput<'a> {
    pub user_transcript: &'a str,
    pub assistant_reply: &'a str,
    pub description_md: &'a str,
    pub phasing_md: &'a str,
}

pub struct ArtifactManager {
    store: ArtifactStore,
    editor: Option<ArtifactEditor>,
    disabled_reason: Option<String>,
}

pub struct ArtifactUpdateOutcome {
    pub rationale: String,
    pub applied: Vec<PathBuf>,
    pub rejected: Vec<RejectedPatch>,
    pub total_patches: usize,
    pub phasing_updated: bool,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionResponse {
    choices: Vec<ChatChoice>,
}

#[derive(Debug, Deserialize)]
struct ChatChoice {
    message: ChatMessage,
}

#[derive(Debug, Deserialize)]
struct ChatMessage {
    content: Option<String>,
}

impl ArtifactEditor {
    pub fn from_environment(api_key: String) -> Result<Option<Self>> {
        let prompt = match load_editor_prompt()? {
            Some(prompt) => prompt,
            None => return Ok(None),
        };

        let http = HttpClient::builder()
            .timeout(Duration::from_secs(45))
            .build()
            .context("Failed to build HTTP client for artifact editor")?;

        let base_url = std::env::var("GROQ_API_BASE_URL")
            .unwrap_or_else(|_| "https://api.groq.com".to_string());
        let model = std::env::var("GROQ_ARTIFACT_MODEL")
            .unwrap_or_else(|_| DEFAULT_ARTIFACT_MODEL.to_string());
        let temperature = std::env::var("GROQ_ARTIFACT_TEMPERATURE")
            .ok()
            .and_then(|val| val.parse::<f32>().ok())
            .unwrap_or(DEFAULT_ARTIFACT_TEMPERATURE);
        let max_tokens = std::env::var("GROQ_ARTIFACT_MAX_TOKENS")
            .ok()
            .and_then(|val| val.parse::<u32>().ok())
            .unwrap_or(DEFAULT_ARTIFACT_MAX_TOKENS);

        Ok(Some(Self {
            http,
            base_url,
            api_key,
            model,
            system_prompt: prompt,
            temperature,
            max_tokens,
        }))
    }

    pub fn propose(&self, input: &ArtifactEditorInput<'_>) -> Result<Option<ArtifactEditorResponse>> {
        let payload_text = build_editor_payload(input);
        let body = json!({
            "model": self.model,
            "messages": [
                {"role": "system", "content": self.system_prompt},
                {"role": "user", "content": payload_text}
            ],
            "temperature": self.temperature,
            "max_tokens": self.max_tokens,
            "stream": false
        });

        let url = format!(
            "{}/openai/v1/chat/completions",
            self.base_url.trim_end_matches('/')
        );

        let response = self
            .http
            .post(url)
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .context("Artifact editor request failed")?;

        let response = response
            .error_for_status()
            .context("Artifact editor returned an error status")?;

        let payload: ChatCompletionResponse = response
            .json()
            .context("Failed to parse artifact editor response")?;

        let content = payload
            .choices
            .into_iter()
            .find_map(|choice| choice.message.content)
            .unwrap_or_default();

        if content.trim().is_empty() {
            return Ok(None);
        }

        let parsed = parse_editor_response(&content)?;
        Ok(Some(parsed))
    }
}

impl ArtifactManager {
    pub fn new(api_key: String) -> Result<Self> {
        let store = ArtifactStore::new()?;
        let editor = ArtifactEditor::from_environment(api_key.clone())?;
        let disabled_reason = if editor.is_some() {
            None
        } else {
            Some("Artifact editor prompt not found; skipping artifact updates.".to_string())
        };

        Ok(Self {
            store,
            editor,
            disabled_reason,
        })
    }

    pub fn disabled_reason(&self) -> Option<&str> {
        self.disabled_reason.as_deref()
    }

    pub fn process_turn(
        &self,
        user_transcript: &str,
        assistant_reply: &str,
    ) -> Result<Option<ArtifactUpdateOutcome>> {
        let editor = match &self.editor {
            Some(editor) => editor,
            None => return Ok(None),
        };

        if user_transcript.trim().is_empty() || assistant_reply.trim().is_empty() {
            return Ok(None);
        }

        let description = self.store.read_description()?;
        let phasing = self.store.read_phasing()?;

        let input = ArtifactEditorInput {
            user_transcript,
            assistant_reply,
            description_md: &description,
            phasing_md: &phasing,
        };

        let Some(response) = editor.propose(&input)? else {
            return Ok(None);
        };

        if response.patches.is_empty() {
            return Ok(Some(ArtifactUpdateOutcome {
                rationale: response.rationale,
                applied: Vec::new(),
                rejected: Vec::new(),
                total_patches: 0,
                phasing_updated: false,
            }));
        }

        let report = self.store.apply_patches(&response.patches)?;
        let phasing_updated = if report.phasing_changed {
            self.store.refresh_phasing_index()?;
            true
        } else {
            false
        };

        Ok(Some(ArtifactUpdateOutcome {
            rationale: response.rationale,
            applied: report.applied,
            rejected: report.rejected,
            total_patches: response.patches.len(),
            phasing_updated,
        }))
    }
}

impl ArtifactStore {
    pub fn new() -> Result<Self> {
        let root = PathBuf::from(ARTIFACTS_DIR);
        fs::create_dir_all(&root).context("Failed to create artifacts directory")?;

        Self::ensure_seed_file(&root, DESCRIPTION_FILE, "# Walkcoach Description\n\n")?;
        Self::ensure_seed_file(&root, PHASING_FILE, "# Walkcoach Phasing\n\n")?;

        Ok(Self { root })
    }

    pub fn read_description(&self) -> Result<String> {
        self.read_artifact(DESCRIPTION_FILE)
    }

    pub fn read_phasing(&self) -> Result<String> {
        self.read_artifact(PHASING_FILE)
    }

    pub fn load_phasing_index(&self) -> Result<PhasingIndex> {
        let index_path = self.root.join(PHASING_INDEX_FILE);
        if !index_path.exists() {
            return Ok(PhasingIndex::default());
        }

        let contents = fs::read_to_string(&index_path)
            .with_context(|| format!("Failed to read phasing index at {}", index_path.display()))?;

        let index: PhasingIndex = serde_json::from_str(&contents)
            .with_context(|| format!("Failed to parse phasing index at {}", index_path.display()))?;

        Ok(index)
    }

    pub fn write_phasing_index(&self, index: &PhasingIndex) -> Result<()> {
        let path = self.root.join(PHASING_INDEX_FILE);
        let json = serde_json::to_string_pretty(index)
            .context("Failed to serialize phasing index")?;
        write_atomic(&path, json.as_bytes())
    }

    pub fn apply_patches(&self, patches: &[ArtifactPatch]) -> Result<AppliedPatchReport> {
        if patches.is_empty() {
            return Ok(AppliedPatchReport {
                applied: Vec::new(),
                rejected: Vec::new(),
                phasing_changed: false,
            });
        }

        let mut applied = Vec::new();
        let mut rejected = Vec::new();
        let mut phasing_changed = false;

        for patch in patches {
            let target = self.normalize_patch_path(&patch.path)?;

            match patch.kind {
                ArtifactPatchType::UnifiedDiff => match self.apply_unified_diff(&target, &patch.data) {
                    Ok(changed) => {
                        if changed {
                            if Self::is_phasing_file(&target) {
                                phasing_changed = true;
                            }
                            applied.push(target);
                        }
                    }
                    Err(err) => {
                        let reject_path = self.write_reject_file(&target, &patch.data)?;
                        rejected.push(RejectedPatch {
                            path: target,
                            reason: err.to_string(),
                            reject_path,
                        });
                    }
                },
                ArtifactPatchType::YamlMerge => match self.apply_yaml_merge(&target, &patch.data) {
                    Ok(changed) => {
                        if changed {
                            applied.push(target);
                        }
                    }
                    Err(err) => {
                        let reject_path = self.write_reject_file(&target, &patch.data)?;
                        rejected.push(RejectedPatch {
                            path: target,
                            reason: err.to_string(),
                            reject_path,
                        });
                    }
                },
            }
        }

        Ok(AppliedPatchReport {
            applied,
            rejected,
            phasing_changed,
        })
    }

    pub fn refresh_phasing_index(&self) -> Result<PhasingIndex> {
        let phasing_path = self.root.join(PHASING_FILE);
        let contents = fs::read_to_string(&phasing_path)
            .with_context(|| format!("Failed to read {}", phasing_path.display()))?;

        let mut index = parse_phasing(&contents)?;

        let mut previous_map = HashMap::new();
        if let Ok(previous) = self.load_phasing_index() {
            for phase in previous.phases {
                previous_map.insert((phase.number, phase.hash.clone()), phase);
            }
        }

        for entry in &mut index.phases {
            if let Some(prev) = previous_map.get(&(entry.number, entry.hash.clone())) {
                entry.audio_path = prev.audio_path.clone();
            }
        }

        index.updated_at = Some(Local::now().to_rfc3339());
        self.write_phasing_index(&index)?;
        Ok(index)
    }

    fn read_artifact(&self, name: &str) -> Result<String> {
        let path = self.root.join(name);
        let contents = fs::read_to_string(&path)
            .with_context(|| format!("Failed to read artifact {}", path.display()))?;
        Ok(contents)
    }

    fn ensure_seed_file(root: &Path, name: &str, stub: &str) -> Result<PathBuf> {
        let path = root.join(name);
        if !path.exists() {
            write_atomic(&path, stub.as_bytes())?;
        }
        Ok(path)
    }

    fn normalize_patch_path(&self, path: &str) -> Result<PathBuf> {
        let candidate = Path::new(path);
        let resolved = if candidate.is_absolute() {
            candidate.to_path_buf()
        } else if path.starts_with("./") {
            self.root.join(path.trim_start_matches("./"))
        } else if path.starts_with(ARTIFACTS_DIR) {
            PathBuf::from(path)
        } else {
            self.root.join(path)
        };

        if !resolved.starts_with(&self.root) {
            return Err(anyhow!("Patch path {path} escapes artifacts directory"));
        }

        Ok(resolved)
    }

    fn apply_unified_diff(&self, target: &Path, diff: &str) -> Result<bool> {
        let (original, existed, lock) = self.read_for_modify(target)?;

        let patch = Patch::from_str(diff).context("Failed to parse unified diff patch")?;
        let updated = diffy::apply(&original, &patch).context("Failed to apply unified diff patch")?;

        if updated == original {
            lock.unlock().ok();
            return Ok(false);
        }

        self.write_backup(target, existed, original.as_bytes())?;
        write_via_temp(target, updated.as_bytes())?;
        lock.unlock().ok();
        Ok(true)
    }

    fn apply_yaml_merge(&self, target: &Path, patch: &str) -> Result<bool> {
        let (original, existed, lock) = self.read_for_modify(target)?;

        let mut base: YamlValue = if original.trim().is_empty() {
            YamlValue::Mapping(Default::default())
        } else {
            serde_yaml::from_str(&original)
                .with_context(|| format!("Failed to parse YAML at {}", target.display()))?
        };

        let patch_value: YamlValue = serde_yaml::from_str(patch)
            .context("Failed to parse yaml_merge patch data")?;

        let changed = merge_yaml(&mut base, &patch_value);

        if !changed {
            lock.unlock().ok();
            return Ok(false);
        }

        let serialized = serde_yaml::to_string(&base).context("Failed to serialize merged YAML")?;
        self.write_backup(target, existed, original.as_bytes())?;
        write_via_temp(target, serialized.as_bytes())?;
        lock.unlock().ok();
        Ok(true)
    }

    fn read_for_modify(&self, target: &Path) -> Result<(String, bool, fs::File)> {
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("Failed to create parent directory {}", parent.display()))?;
        }

        let lock = acquire_lock(target)?;
        let existed = target.exists();

        let contents = if existed {
            fs::read_to_string(target)
                .with_context(|| format!("Failed to read {}", target.display()))?
        } else {
            String::new()
        };

        Ok((contents, existed, lock))
    }

    fn write_backup(&self, target: &Path, existed: bool, data: &[u8]) -> Result<()> {
        if !existed {
            return Ok(());
        }

        let timestamp = Local::now().format("%Y%m%d-%H%M%S");
        let backup_name = sidecar_name(target, "bak", &timestamp.to_string());
        let backup_path = target
            .parent()
            .map(|parent| parent.join(&backup_name))
            .unwrap_or_else(|| PathBuf::from(&backup_name));
        fs::write(&backup_path, data)
            .with_context(|| format!("Failed to write backup file {}", backup_path.display()))?;
        Ok(())
    }

    fn write_reject_file(&self, target: &Path, patch: &str) -> Result<PathBuf> {
        let timestamp = Local::now().format("%Y%m%d-%H%M%S");
        let reject_name = sidecar_name(target, "reject", &timestamp.to_string());
        let reject_path = target
            .parent()
            .map(|parent| parent.join(&reject_name))
            .unwrap_or_else(|| PathBuf::from(&reject_name));
        fs::write(&reject_path, patch.as_bytes()).with_context(|| {
            format!("Failed to write reject file {}", reject_path.display())
        })?;
        Ok(reject_path)
    }

    fn is_phasing_file(target: &Path) -> bool {
        target
            .file_name()
            .and_then(|name| name.to_str())
            .map(|name| name == PHASING_FILE)
            .unwrap_or(false)
    }
}

fn load_editor_prompt() -> Result<Option<String>> {
    if let Ok(path) = std::env::var(ARTIFACT_PROMPT_ENV) {
        let trimmed = path.trim();
        if trimmed.is_empty() {
            return Ok(None);
        }
        let path = PathBuf::from(trimmed);
        if !path.exists() {
            return Err(anyhow!(
                "Artifact editor prompt path {} does not exist",
                path.display()
            ));
        }
        let prompt = fs::read_to_string(&path)
            .with_context(|| format!("Failed to read artifact prompt from {}", path.display()))?;
        return Ok(Some(prompt));
    }

    let default = PathBuf::from(DEFAULT_PROMPT_PATH);
    if !default.exists() {
        return Ok(None);
    }

    let prompt = fs::read_to_string(&default)
        .with_context(|| format!("Failed to read artifact prompt from {}", default.display()))?;
    Ok(Some(prompt))
}

fn build_editor_payload(input: &ArtifactEditorInput<'_>) -> String {
    let mut text = String::new();
    let _ = writeln!(&mut text, "Latest turn");
    let _ = writeln!(&mut text, "-----------");
    let _ = writeln!(&mut text, "User transcript:");
    let _ = writeln!(&mut text, "{}", input.user_transcript.trim());
    let _ = writeln!(&mut text);
    let _ = writeln!(&mut text, "Assistant reply:");
    let _ = writeln!(&mut text, "{}", input.assistant_reply.trim());
    let _ = writeln!(&mut text);
    let _ = writeln!(&mut text, "Artifacts snapshot");
    let _ = writeln!(&mut text, "------------------");
    let _ = writeln!(&mut text, "[description.md]");
    let _ = writeln!(&mut text, "{}", input.description_md.trim());
    let _ = writeln!(&mut text);
    let _ = writeln!(&mut text, "[phasing.md]");
    let _ = writeln!(&mut text, "{}", input.phasing_md.trim());
    text
}

fn parse_editor_response(content: &str) -> Result<ArtifactEditorResponse> {
    let trimmed = content.trim();

    if let Ok(parsed) = serde_json::from_str::<ArtifactEditorResponse>(trimmed) {
        return Ok(parsed);
    }

    if let Some(json_block) = extract_json_block(trimmed) {
        let parsed: ArtifactEditorResponse = serde_json::from_str(&json_block)
            .context("Failed to parse artifact editor JSON block")?;
        return Ok(parsed);
    }

    Err(anyhow!("Artifact editor response was not valid JSON"))
}

fn extract_json_block(content: &str) -> Option<String> {
    let trimmed = content.trim();
    if trimmed.starts_with("```") {
        let mut lines = trimmed.lines();
        let fence = lines.next()?;
        let fence_language = fence.trim_start_matches("```").trim();
        if !fence_language.is_empty() && fence_language != "json" && fence_language != "JSON" {
            // Still attempt to parse contents even if language is different.
        }
        let mut buffer = String::new();
        for line in lines {
            if line.trim_start().starts_with("```") {
                break;
            }
            if !buffer.is_empty() {
                buffer.push('\n');
            }
            buffer.push_str(line);
        }
        if buffer.trim().is_empty() {
            None
        } else {
            Some(buffer)
        }
    } else {
        let start = trimmed.find('{')?;
        let end = trimmed.rfind('}')?;
        if end <= start {
            return None;
        }
        Some(trimmed[start..=end].to_string())
    }
}

fn acquire_lock(target: &Path) -> Result<fs::File> {
    let file_name = target
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("artifact");
    let lock_name = format!(".{}.lock", file_name);
    let lock_path = target
        .parent()
        .map(|parent| parent.join(&lock_name))
        .unwrap_or_else(|| PathBuf::from(&lock_name));

    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .open(&lock_path)
        .with_context(|| format!("Failed to open lock file {}", lock_path.display()))?;

    file.lock_exclusive()
        .with_context(|| format!("Failed to lock {}", target.display()))?;

    Ok(file)
}

fn write_via_temp(target: &Path, data: &[u8]) -> Result<()> {
    let parent = target
        .parent()
        .map(|parent| parent.to_path_buf())
        .unwrap_or_else(|| PathBuf::from("."));
    fs::create_dir_all(&parent)
        .with_context(|| format!("Failed to create directory {}", parent.display()))?;
    let mut temp = NamedTempFile::new_in(&parent)
        .with_context(|| format!("Failed to create temp file in {}", parent.display()))?;
    temp.write_all(data)
        .context("Failed to write temp artifact content")?;
    temp.flush().context("Failed to flush temp artifact content")?;
    temp.persist(target)
        .with_context(|| format!("Failed to replace artifact {}", target.display()))?;
    Ok(())
}

fn write_atomic(path: &Path, data: &[u8]) -> Result<()> {
    write_via_temp(path, data)
}

fn sidecar_name(target: &Path, kind: &str, timestamp: &str) -> String {
    let file_name = target
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("artifact");
    format!("{}.{}-{}", file_name, kind, timestamp)
}

fn merge_yaml(base: &mut YamlValue, patch: &YamlValue) -> bool {
    match (base, patch) {
        (YamlValue::Mapping(base_map), YamlValue::Mapping(patch_map)) => {
            let mut changed = false;
            for (key, value) in patch_map {
                match base_map.get_mut(key) {
                    Some(existing) => {
                        if merge_yaml(existing, value) {
                            changed = true;
                        }
                    }
                    None => {
                        base_map.insert(key.clone(), value.clone());
                        changed = true;
                    }
                }
            }
            changed
        }
        (YamlValue::Sequence(base_seq), YamlValue::Sequence(patch_seq)) => {
            if *base_seq != *patch_seq {
                *base_seq = patch_seq.clone();
                true
            } else {
                false
            }
        }
        (base_slot, patch_value) => {
            if *base_slot != *patch_value {
                *base_slot = patch_value.clone();
                true
            } else {
                false
            }
        }
    }
}

fn parse_phasing(contents: &str) -> Result<PhasingIndex> {
    let mut phases = Vec::new();
    let mut current: Option<PhaseBuilder> = None;

    for line in contents.lines() {
        if let Some((number, title)) = parse_phase_header(line) {
            if let Some(builder) = current.take() {
                phases.push(builder.finish());
            }
            current = Some(PhaseBuilder::new(number, title));
        } else if let Some(builder) = current.as_mut() {
            builder.push_line(line);
        }
    }

    if let Some(builder) = current.take() {
        phases.push(builder.finish());
    }

    Ok(PhasingIndex {
        phases,
        updated_at: None,
    })
}

struct PhaseBuilder {
    number: u32,
    title: String,
    lines: Vec<String>,
}

impl PhaseBuilder {
    fn new(number: u32, title: String) -> Self {
        Self {
            number,
            title,
            lines: Vec::new(),
        }
    }

    fn push_line(&mut self, line: &str) {
        self.lines.push(line.to_string());
    }

    fn finish(self) -> PhasingEntry {
        let talk_track = self
            .lines
            .join("\n")
            .trim()
            .to_string();
        make_phase_entry(self.number, self.title, talk_track)
    }
}

fn make_phase_entry(number: u32, title: String, talk_track: String) -> PhasingEntry {
    let mut hasher = Sha256::new();
    hasher.update(talk_track.as_bytes());
    let digest = hasher.finalize();
    let mut short = String::new();
    for byte in digest.iter().take(4) {
        let _ = write!(&mut short, "{:02x}", byte);
    }

    PhasingEntry {
        number,
        title,
        talk_track,
        hash: short,
        audio_path: None,
    }
}

fn parse_phase_header(line: &str) -> Option<(u32, String)> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Some((left, right)) = split_header(trimmed) {
        let lower = left.to_ascii_lowercase();
        if !lower.starts_with("phase ") {
            return None;
        }
        let number_token = left[6..].trim();
        let number = parse_phase_number(number_token)?;
        return Some((number, right.trim().to_string()));
    }

    None
}

fn split_header(line: &str) -> Option<(&str, &str)> {
    if let Some(index) = line.find('—') {
        let (left, right) = line.split_at(index);
        let right = &right['—'.len_utf8()..];
        return Some((left.trim(), right.trim()));
    }

    if let Some(index) = line.find('-') {
        let (left, right) = line.split_at(index);
        let right = &right[1..];
        return Some((left.trim(), right.trim()));
    }

    None
}

fn parse_phase_number(token: &str) -> Option<u32> {
    if let Ok(value) = token.parse::<u32>() {
        return Some(value);
    }

    let normalized = token
        .to_ascii_lowercase()
        .replace('-', " ")
        .replace('_', " ")
        .trim()
        .to_string();

    let words: Vec<&str> = normalized.split_whitespace().collect();
    words_to_number(&words)
}

fn words_to_number(words: &[&str]) -> Option<u32> {
    if words.is_empty() {
        return None;
    }

    let lookup: HashMap<&str, u32> = [
        ("zero", 0),
        ("one", 1),
        ("two", 2),
        ("three", 3),
        ("four", 4),
        ("five", 5),
        ("six", 6),
        ("seven", 7),
        ("eight", 8),
        ("nine", 9),
        ("ten", 10),
        ("eleven", 11),
        ("twelve", 12),
        ("thirteen", 13),
        ("fourteen", 14),
        ("fifteen", 15),
        ("sixteen", 16),
        ("seventeen", 17),
        ("eighteen", 18),
        ("nineteen", 19),
        ("twenty", 20),
        ("thirty", 30),
        ("forty", 40),
        ("fifty", 50),
        ("sixty", 60),
    ]
    .into_iter()
    .collect();

    let mut total = 0u32;
    let mut current = 0u32;

    for &word in words {
        if word == "and" {
            continue;
        }

        if word == "hundred" {
            if current == 0 {
                current = 1;
            }
            current *= 100;
            continue;
        }

        let value = *lookup.get(word)?;

        if value >= 20 && value % 10 == 0 {
            current += value;
        } else if current >= 20 && current % 10 == 0 {
            current += value;
        } else {
            current += value;
        }
    }

    total += current;
    Some(total)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_phase_headers() {
        let header = "phase six — living artifacts";
        let parsed = parse_phase_header(header).expect("should parse");
        assert_eq!(parsed.0, 6);
        assert_eq!(parsed.1, "living artifacts");

        let header_dash = "phase 7 - voice navigation";
        let parsed_dash = parse_phase_header(header_dash).expect("should parse dash");
        assert_eq!(parsed_dash.0, 7);
        assert_eq!(parsed_dash.1, "voice navigation");
    }

    #[test]
    fn hash_is_short() {
        let entry = make_phase_entry(1, "title".into(), "talk".into());
        assert_eq!(entry.hash.len(), 8);
    }
}
