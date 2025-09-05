use anyhow::Result;
use std::sync::Arc;
use tokio::sync::mpsc;
use protocol::Message;
use orchestrator_core::OrchestratorCore;
use orchestrator_tui::TuiState;
use control_center::ControlCenter;

/// Thin coordination layer between core, TUI, and adapters
/// Target: ~200 lines
pub struct App {
    // Core orchestrator
    pub core: Arc<OrchestratorCore<
        crate::core_bridge::RouterAdapter,
        crate::core_bridge::ExecutorAdapter,
        crate::core_bridge::OutboundChannel
    >>,
    
    // TUI state (if feature enabled)
    #[cfg(feature = "tui")]
    pub tui: Option<TuiState>,
    
    // Control center for executor management
    pub center: ControlCenter,
    
    // Channels for message passing
    pub core_in_tx: mpsc::Sender<Message>,
    pub core_out_rx: mpsc::Receiver<Message>,
    pub cmd_tx: mpsc::Sender<crate::core_bridge::AppCommand>,
    pub cmd_rx: mpsc::Receiver<crate::core_bridge::AppCommand>,
    
    // Settings
    pub settings: crate::settings::AppSettings,
}

impl App {
    pub async fn new() -> Result<Self> {
        // Create control center
        let center = ControlCenter::new().await;
        
        // Create command channels
        let (cmd_tx, cmd_rx) = mpsc::channel(32);
        
        // Create core with adapters
        let exec_adapter = crate::core_bridge::ExecutorAdapter::new(cmd_tx.clone());
        let system = crate::core_bridge::start_core_with_executor(exec_adapter);
        
        // Load settings
        let settings = crate::settings::AppSettings::load()?;
        
        // Create TUI if feature enabled
        #[cfg(feature = "tui")]
        let tui = if settings.enable_tui {
            Some(TuiState::new(system.handles.inbound_tx.clone()))
        } else {
            None
        };
        
        Ok(Self {
            core: system.core,
            #[cfg(feature = "tui")]
            tui,
            center,
            core_in_tx: system.handles.inbound_tx,
            core_out_rx: system.handles.outbound_rx,
            cmd_tx,
            cmd_rx,
            settings,
        })
    }
    
    /// Main event loop
    pub async fn run(&mut self) -> Result<()> {
        // Initialize relay client if configured
        self.initialize_relay().await;
        
        loop {
            tokio::select! {
                // Handle messages from core
                Some(msg) = self.core_out_rx.recv() => {
                    self.handle_core_message(msg).await?;
                }
                
                // Handle commands from adapters
                Some(cmd) = self.cmd_rx.recv() => {
                    self.handle_command(cmd).await?;
                }
                
                // Handle TUI events if enabled
                #[cfg(feature = "tui")]
                _ = self.handle_tui_events() => {
                    // TUI event handled
                }
                
                // Handle control-C
                _ = tokio::signal::ctrl_c() => {
                    break;
                }
            }
        }
        
        Ok(())
    }
    
    async fn handle_core_message(&mut self, msg: Message) -> Result<()> {
        match msg {
            Message::PromptConfirmation(pc) => {
                self.handle_prompt_confirmation(pc).await?;
            }
            Message::Status(status) => {
                self.handle_status(status).await?;
            }
            _ => {
                // Other messages handled by TUI or logged
                #[cfg(feature = "tui")]
                if let Some(ref mut tui) = self.tui {
                    tui.append_output(format!("{:?}", msg));
                }
            }
        }
        Ok(())
    }
    
    async fn handle_command(&mut self, cmd: crate::core_bridge::AppCommand) -> Result<()> {
        use crate::core_bridge::AppCommand;
        
        match cmd {
            AppCommand::LaunchExecutor { prompt } => {
                self.launch_executor(&prompt).await?;
            }
            AppCommand::QueryExecutorStatus { reply_tx } => {
                let status = self.get_executor_status().await;
                let _ = reply_tx.send(status);
            }
        }
        Ok(())
    }
    
    async fn handle_prompt_confirmation(&mut self, pc: protocol::PromptConfirmation) -> Result<()> {
        // Show confirmation in TUI
        #[cfg(feature = "tui")]
        if let Some(ref mut tui) = self.tui {
            tui.append_output(format!("Confirm: {} for {}?", pc.prompt, pc.executor));
        }
        
        // In non-interactive mode, auto-confirm based on settings
        if !self.settings.require_executor_confirmation {
            let response = protocol::ConfirmResponse {
                v: pc.v,
                id: pc.id,
                for_: pc.for_,
                accept: true,
            };
            self.core_in_tx.send(Message::ConfirmResponse(response)).await?;
        }
        
        Ok(())
    }
    
    async fn handle_status(&mut self, status: protocol::Status) -> Result<()> {
        #[cfg(feature = "tui")]
        if let Some(ref mut tui) = self.tui {
            tui.append_output(format!("[{}] {}", status.level, status.text));
        }
        
        // Also log to stderr for non-TUI mode
        eprintln!("[{}] {}", status.level, status.text);
        
        Ok(())
    }
    
    async fn launch_executor(&mut self, prompt: &str) -> Result<()> {
        let config = control_center::ExecutorConfig::default();
        self.center.launch(prompt, Some(config)).await?;
        
        // Notify core of active session
        self.core.set_active_session("Claude".to_string());
        
        Ok(())
    }
    
    async fn get_executor_status(&self) -> String {
        // Check if executor is running
        if self.center.is_running().await {
            "Claude Code is running".to_string()
        } else {
            "No active session".to_string()
        }
    }
    
    #[cfg(feature = "tui")]
    async fn handle_tui_events(&mut self) -> Result<()> {
        // This would integrate with crossterm events
        // For now, just a placeholder
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
        Ok(())
    }
    
    async fn initialize_relay(&self) {
        // Initialize relay client if configured
        // Simplified version - details would be in relay adapter
        if let Ok(_config) = crate::relay_client::load_config_from_env() {
            // Relay initialization would happen here
        }
    }
}