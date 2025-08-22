mod components;
mod confirmation;
mod layout;
mod styles;

use ratatui::Frame;

use crate::app::App;
use components::{HelpPane, InputLine, OutputPane, PlanOverlay};
use confirmation::ConfirmationDialog;
use layout::LayoutManager;

pub struct UI;

impl UI {
    pub fn draw(frame: &mut Frame, app: &App) {
        let chunks = LayoutManager::create_main_layout(frame.area());
        
        OutputPane::render(frame, &chunks.output, app);
        HelpPane::render(frame, &chunks.help, app);
        InputLine::render(frame, &chunks.input, app);
        
        if app.plan.is_pending() {
            PlanOverlay::render(frame, app);
        }
        
        // Render confirmation dialog if in confirmation mode
        ConfirmationDialog::render(frame, app);
        
        Self::set_cursor(frame, app, &chunks.input);
    }
    
    fn set_cursor(frame: &mut Frame, app: &App, input_area: &ratatui::layout::Rect) {
        if app.can_edit_input() {
            let cursor_x = (2 + app.input.len()) as u16;
            let cursor_y = input_area.y;
            
            if cursor_x < input_area.x + input_area.width {
                frame.set_cursor_position((input_area.x + cursor_x, cursor_y));
            }
        }
    }
}