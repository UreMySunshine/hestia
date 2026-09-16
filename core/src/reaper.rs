//! 强杀兜底。
//!
//! 正常退出走 `RunEvent::Exit` → `kill_all_now`。但那条路覆盖不了信号终止：
//! `kill`、活动监视器的「退出」、终端 Ctrl-C 送来的是 SIGTERM/SIGINT/SIGHUP，
//! 而「强制退出」送的是 SIGKILL，进程根本没有执行任何代码的机会。
//!
//! 这里做两层：
//! 1. 为可捕获的信号装处理函数，就地回收进程组；
//! 2. 把运行中的进程组落盘，下次启动时回收上一轮残留——这层覆盖 SIGKILL 与崩溃。
//!
//! 信号处理函数里只能调异步信号安全的函数，因此不用锁、不分配内存，
//! 只读一组原子量并调用 `kill`，两者都是安全的。

use std::sync::atomic::{AtomicI32, Ordering};

const MAX_TRACKED: usize = 64;

static PGIDS: [AtomicI32; MAX_TRACKED] = [const { AtomicI32::new(0) }; MAX_TRACKED];

pub fn track(pgid: i32) {
    if pgid <= 0 {
        return;
    }
    for slot in &PGIDS {
        if slot
            .compare_exchange(0, pgid, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
        {
            return;
        }
    }
}

pub fn untrack(pgid: i32) {
    if pgid <= 0 {
        return;
    }
    for slot in &PGIDS {
        let _ = slot.compare_exchange(pgid, 0, Ordering::AcqRel, Ordering::Acquire);
    }
}

extern "C" fn on_signal(sig: i32) {
    for slot in &PGIDS {
        let pgid = slot.load(Ordering::Acquire);
        if pgid > 0 {
            unsafe { libc::kill(-pgid, libc::SIGTERM) };
        }
    }
    // 恢复默认处理再重新抛出，保持正常的退出语义
    unsafe {
        libc::signal(sig, libc::SIG_DFL);
        libc::raise(sig);
    }
}

pub fn install() {
    for sig in [libc::SIGTERM, libc::SIGINT, libc::SIGHUP] {
        let h = on_signal as extern "C" fn(i32) as *const () as libc::sighandler_t;
        unsafe { libc::signal(sig, h) };
    }
}
