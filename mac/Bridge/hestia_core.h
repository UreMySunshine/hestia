#ifndef HESTIA_CORE_H
#define HESTIA_CORE_H

/// 核心侧的主动通知：(事件名, JSON 负载)。指针仅在回调期间有效
typedef void (*hestia_event_cb)(const char *name, const char *payload);

/// 取回登录 shell 的 PATH 写入本进程。必须在起任何线程之前调用
void hestia_bootstrap(void);

void hestia_init(const char *config_dir, hestia_event_cb cb);

/// 返回 JSON，调用方负责用 hestia_free 释放
char *hestia_call(const char *method, const char *args);

void hestia_free(char *p);

#endif
