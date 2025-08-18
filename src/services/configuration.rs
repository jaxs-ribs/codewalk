use anyhow::{Result, anyhow};
use crate::interfaces::ConfigurationProvider;
use crate::constants::{ENV_FILE_PATH, ENV_API_KEY};
use std::collections::HashMap;

pub struct EnvironmentConfigProvider {
    cache: HashMap<String, String>,
}

impl EnvironmentConfigProvider {
    pub fn new() -> Result<Self> {
        let mut provider = Self {
            cache: HashMap::new(),
        };
        provider.load_configuration()?;
        Ok(provider)
    }

    fn load_configuration(&mut self) -> Result<()> {
        EnvFileLoader::load(ENV_FILE_PATH);
        self.cache_environment_variables();
        Ok(())
    }

    fn cache_environment_variables(&mut self) {
        for (key, value) in std::env::vars() {
            self.cache.insert(key, value);
        }
    }
}

impl ConfigurationProvider for EnvironmentConfigProvider {
    fn get_api_key(&self) -> Result<String> {
        self.get_setting(ENV_API_KEY)
            .ok_or_else(|| anyhow!("{} not found. Please set it in {} file", ENV_API_KEY, ENV_FILE_PATH))
    }

    fn get_setting(&self, key: &str) -> Option<String> {
        self.cache.get(key).cloned()
    }
}

struct EnvFileLoader;

impl EnvFileLoader {
    fn load(path: &str) {
        if let Ok(content) = std::fs::read_to_string(path) {
            EnvParser::parse(&content);
        }
    }
}

struct EnvParser;

impl EnvParser {
    fn parse(content: &str) {
        content
            .lines()
            .filter(|line| Self::is_valid_line(line))
            .filter_map(|line| Self::parse_line(line))
            .for_each(|(key, value)| Self::set_if_unset(key, value));
    }

    fn is_valid_line(line: &str) -> bool {
        let trimmed = line.trim();
        !trimmed.is_empty() && !trimmed.starts_with('#')
    }

    fn parse_line(line: &str) -> Option<(String, String)> {
        let mut parts = line.trim().splitn(2, '=');
        let key = parts.next()?.trim();
        let raw_value = parts.next()?.trim();
        
        if key.is_empty() {
            return None;
        }
        
        let value = Self::clean_value(raw_value);
        Some((key.to_string(), value))
    }

    fn clean_value(raw: &str) -> String {
        raw.trim_matches('"')
           .trim_matches('\'')
           .to_string()
    }

    fn set_if_unset(key: String, value: String) {
        if std::env::var(&key).is_err() {
            std::env::set_var(key, value);
        }
    }
}