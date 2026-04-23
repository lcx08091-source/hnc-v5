# HNC v5.0.0-beta.4 hotfix4: BPF_BTF_LOAD log_buf 诊断

## 目的
hotfix3 让 LSM init 走通 step1-5,但 step6 BPF_BTF_LOAD 报 EINVAL,
没有具体原因。本 hotfix 让 kernel 把 BTF 校验失败的精确原因写到日志。

## 修改
单点改动:`load_btf()` 加 `log_buf / log_size / log_level` attr,
失败时 fprintf BTF verifier log。

```c
static int load_btf(const void *btf_data, uint32_t btf_size,
                    char *log_buf, uint32_t log_buf_size)
{
    union bpf_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.btf      = (uint64_t)(uintptr_t)btf_data;
    attr.btf_size = btf_size;
    if (log_buf && log_buf_size) {
        attr.btf_log_buf  = (uint64_t)(uintptr_t)log_buf;
        attr.btf_log_size = log_buf_size;
        attr.btf_log_level = 1;
        log_buf[0] = 0;
    }
    long fd = sys_bpf(BPF_BTF_LOAD, &attr, sizeof(attr));
    return (int)fd;
}
```

调用点改:
```c
static char btf_log_buf[16 * 1024];
int prog_btf_fd = load_btf(btf_data, btf_size, btf_log_buf, sizeof(btf_log_buf));
if (prog_btf_fd < 0) {
    if (btf_log_buf[0]) {
        fprintf(stderr, "[lsm] BTF verifier log:\n%s\n", btf_log_buf);
    }
    set_fail("BPF_BTF_LOAD: %s", strerror(errno));
    ...
}
```

## 装机
```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_0_0-beta4-hotfix4.zip .
unzip -o HNC-v5_0_0-beta4-hotfix4.zip
rm HNC-v5_0_0-beta4-hotfix4.zip
git add -A
git commit -m "v5.0.0-beta.4 hotfix4: BPF_BTF_LOAD log_buf for diagnosis

Add btf_log_buf/size/level to BPF_BTF_LOAD attr so kernel can report
the specific BTF type kind / field that caused EINVAL. Without log
we're blind on whether the issue is:
  - BTF_KIND_DECL_TAG (clang 18, kernel may reject)
  - BTF_KIND_TYPE_TAG (newer)
  - BTF_KIND_ENUM64 (newer)
  - .rel.BTF unresolved name_off
  - BTF DATASEC referencing absent map definition
  - or something else specific to OPPO ColorOS BPF subsystem"
git push

# 等 CI → 装 → 重启 → 等 30 秒
su -c "grep -iE 'lsm|FAIL|BTF' /data/local/hnc/logs/hotspotd.log | tail -60"
```

## 期望日志
```
[lsm] step6: BPF_BTF_LOAD
[lsm] BTF verifier log:
<...kernel 报的具体原因, 比如 "Unsupported BTF_KIND" 或 "Invalid name_off"...>
[lsm] FAIL: BPF_BTF_LOAD: Invalid argument
[sched] BPF LSM guard FAILED, fallback to passive disable
```

把 BTF verifier log 那一段全贴回来,我决定下一步:
- 如果只 1-2 个 incompatible kind → 我给 BPF 程序加 -mllvm flag 禁用,或手撸 BTF strip
- 如果一大堆问题 → 上 libbpf 静态链接(evaluation AI 推荐)
