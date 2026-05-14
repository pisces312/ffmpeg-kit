# Cppcheck 扫描结果摘要

> 日期：2026-05-14
> 扫描范围：ffmpeg-kit/android/ffmpeg-kit-android-lib/src/main/cpp/*.c
> 工具：Cppcheck（--enable=all --inconclusive --std=c11）

---

## 统计

| 级别 | 数量 | 说明 |
|------|------|------|
| **error** | 2 | 需要关注 |
| **warning** | 3 | 需要关注 |
| **style** | ~160 | 代码风格问题，可忽略 |
| **information** | 大量 | 主要是 missingInclude，可忽略 |

---

## 需要关注的问题

### 1. Error: 未初始化结构体成员

```
fftools_ffmpeg_enc.c:220:35: error: Uninitialized struct member: fd.frame_rate_filter [uninitStructMember]
```

**风险**：中。`fd` 结构体未完全初始化，可能导致编码时使用了未定义的值。

### 2. Error: 未知宏

```
fftools_opt_common.c:206:45: error: There is an unknown macro here somewhere... FFMPEG_CONFIGURATION [unknownMacro]
```

**风险**：低。这是配置宏，Cppcheck 无法解析，不影响实际运行。

### 3. Warning: 空指针解引用

```
fftools_ffmpeg_enc.c:474:50: warning: Possible null pointer dereference: pkt [nullPointer]
fftools_ffmpeg_enc.c:475:44: warning: Possible null pointer dereference: pkt [nullPointer]
fftools_ffmpeg_enc.c:482:37: warning: Possible null pointer dereference: pkt [nullPointer]
```

**风险**：中。`pkt` 可能为 NULL 但被解引用，但 FFmpeg 内部通常有前置检查。

---

## 结论

Cppcheck 没有发现**严重的内存泄漏或全局状态问题**。主要问题集中在：

1. **未初始化结构体成员**（`fftools_ffmpeg_enc.c:220`）— 建议检查
2. **空指针解引用**（`fftools_ffmpeg_enc.c:474-482`）— 建议加 NULL 检查
3. 大量 style 问题和 unusedFunction — 可忽略

**与连续执行崩溃相关的全局状态问题**，Cppcheck 没有检测出来（因为静态分析难以追踪跨调用的全局变量生命周期），这正是我们通过 tombstone + addr2line 手动定位的原因。

---

## 已修复的问题

| 问题 | 文件 | 修复 | 时间 |
|------|------|------|------|
| 全局数组计数器未重置 | `fftools_ffmpeg.c` | `ffmpeg_cleanup()` 中加 `nb_* = 0` | 2026-05-14 |

---

## 待 follow up

- [ ] 修复 `fftools_ffmpeg_enc.c:220` 未初始化结构体成员
- [ ] 修复 `fftools_ffmpeg_enc.c:474-482` 空指针解引用
- [ ] 检查 `transcode_init_done`、`ffmpeg_exited` 等 static 变量是否需要重置
- [ ] 考虑用 ASan 编译检测版本做运行时验证

---

## 参考

- 完整报告：`cppcheck_report.txt`
- [Native 层内存问题排查指南](./native-memory-check-guide.md)
- [StreamClip Native Crash 抓取指南](../../StreamClip/docs/capture-native-crash-log.md)
