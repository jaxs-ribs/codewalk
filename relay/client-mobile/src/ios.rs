use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Arc;

#[repr(C)]
pub struct RelayCallback {
    pub context: *mut std::ffi::c_void,
    pub callback: extern "C" fn(*mut std::ffi::c_void, *const c_char),
}

unsafe impl Send for RelayCallback {}
unsafe impl Sync for RelayCallback {}

impl RelayCallback {
    fn call(&self, message: &str) {
        if let Ok(c_str) = CString::new(message) {
            unsafe {
                (self.callback)(self.context, c_str.as_ptr());
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn relay_connect_with_qr(
    qr_data: *const c_char,
    on_message: RelayCallback,
    on_error: RelayCallback,
    on_status: RelayCallback,
) -> i32 {
    let qr_str = unsafe {
        if qr_data.is_null() {
            return -1;
        }
        CStr::from_ptr(qr_data).to_string_lossy().into_owned()
    };
    
    let on_message = Arc::new(on_message);
    let on_error = Arc::new(on_error);
    let on_status = Arc::new(on_status);
    
    let on_msg = {
        let cb = on_message.clone();
        Arc::new(move |msg: String| cb.call(&msg))
    };
    
    let on_err = {
        let cb = on_error.clone();
        Arc::new(move |err: String| cb.call(&err))
    };
    
    let on_stat = {
        let cb = on_status.clone();
        Arc::new(move |status: String| cb.call(&status))
    };
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        match rt.block_on(crate::connect_with_qr(qr_str, on_msg, on_err, on_stat)) {
            Ok(()) => {},
            Err(e) => on_error.call(&e),
        }
    });
    
    0
}

#[no_mangle]
pub extern "C" fn relay_send_message(message: *const c_char) -> i32 {
    let msg_str = unsafe {
        if message.is_null() {
            return -1;
        }
        CStr::from_ptr(message).to_string_lossy().into_owned()
    };
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let _ = rt.block_on(crate::send_message(msg_str));
    });
    
    0
}

#[no_mangle]
pub extern "C" fn relay_disconnect() -> i32 {
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let _ = rt.block_on(crate::disconnect());
    });
    
    0
}

#[no_mangle]
pub extern "C" fn relay_free_string(s: *mut c_char) {
    unsafe {
        if !s.is_null() {
            let _ = CString::from_raw(s);
        }
    }
}