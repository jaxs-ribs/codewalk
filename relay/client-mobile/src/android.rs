use jni::JNIEnv;
use jni::objects::{JClass, JObject, JString, JValue};
use jni::sys::{jint, jlong};
use std::sync::Arc;

struct JavaCallback {
    vm: jni::JavaVM,
    callback: jni::objects::GlobalRef,
}

unsafe impl Send for JavaCallback {}
unsafe impl Sync for JavaCallback {}

impl JavaCallback {
    fn call(&self, message: &str) {
        if let Ok(mut env) = self.vm.attach_current_thread() {
            if let Ok(msg) = env.new_string(message) {
                let _ = env.call_method(
                    &self.callback,
                    "onMessage",
                    "(Ljava/lang/String;)V",
                    &[JValue::Object(&JObject::from(msg))],
                );
            }
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_com_relay_RelayClient_nativeConnect(
    mut env: JNIEnv,
    _class: JClass,
    qr_data: JString,
    on_message: JObject,
    on_error: JObject,
    on_status: JObject,
) -> jint {
    let qr_str: String = match env.get_string(&qr_data) {
        Ok(s) => s.into(),
        Err(_) => return -1,
    };
    
    let vm = match env.get_java_vm() {
        Ok(vm) => vm,
        Err(_) => return -1,
    };
    
    let on_message_ref = match env.new_global_ref(on_message) {
        Ok(r) => r,
        Err(_) => return -1,
    };
    
    let on_error_ref = match env.new_global_ref(on_error) {
        Ok(r) => r,
        Err(_) => return -1,
    };
    
    let on_status_ref = match env.new_global_ref(on_status) {
        Ok(r) => r,
        Err(_) => return -1,
    };
    
    let on_msg_cb = Arc::new(JavaCallback {
        vm: vm.clone(),
        callback: on_message_ref,
    });
    
    let on_err_cb = Arc::new(JavaCallback {
        vm: vm.clone(),
        callback: on_error_ref,
    });
    
    let on_stat_cb = Arc::new(JavaCallback {
        vm,
        callback: on_status_ref,
    });
    
    let on_msg = {
        let cb = on_msg_cb.clone();
        Arc::new(move |msg: String| cb.call(&msg))
    };
    
    let on_err = {
        let cb = on_err_cb.clone();
        Arc::new(move |err: String| cb.call(&err))
    };
    
    let on_stat = {
        let cb = on_stat_cb.clone();
        Arc::new(move |status: String| cb.call(&status))
    };
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        match rt.block_on(crate::connect_with_qr(qr_str, on_msg, on_err, on_stat)) {
            Ok(()) => {},
            Err(e) => on_err_cb.call(&e),
        }
    });
    
    0
}

#[no_mangle]
pub extern "system" fn Java_com_relay_RelayClient_nativeSendMessage(
    mut env: JNIEnv,
    _class: JClass,
    message: JString,
) -> jint {
    let msg_str: String = match env.get_string(&message) {
        Ok(s) => s.into(),
        Err(_) => return -1,
    };
    
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let _ = rt.block_on(crate::send_message(msg_str));
    });
    
    0
}

#[no_mangle]
pub extern "system" fn Java_com_relay_RelayClient_nativeDisconnect(
    _env: JNIEnv,
    _class: JClass,
) -> jint {
    std::thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let _ = rt.block_on(crate::disconnect());
    });
    
    0
}