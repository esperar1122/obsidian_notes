
> 目标环境：openEuler + 华为 XFusion 服务器（iBMC）
> 双轨输出：完整测试报告.log（过滤摘要）+ 完整测试日志.log（原始全量 + # CMD: 审计标记）
> BMC 采集方式：SSH 登录 iBMC + ipmcget 命令

---

## 目录

1. [脚本整体架构与执行流程](#1-脚本整体架构与执行流程)
2. [开机网络稳定延时（第1-5行）](#2-开机网络稳定延时第1-5行)
3. [自启动服务自动部署（第7-47行）](#3-自启动服务自动部署第7-47行)
4. [全局配置变量区（第49-59行）](#4-全局配置变量区第49-59行)
5. [轮次管理与临时文件管理（第61-92行）](#5-轮次管理与临时文件管理第61-92行)
6. [输出函数体系：print_step / print_text / print_data（第94-119行）](#6-输出函数体系print_step--print_text--print_data第94-119行)
7. [轮次分隔头（第121-126行）](#7-轮次分隔头第121-126行)
8. [第0节：连通性自检（第128-179行）](#8-第0节连通性自检第128-179行)
9. [第1节：OS & BIOS基础信息（第181-192行）](#9-第1节os--bios基础信息第181-192行)
10. [第2节：完整内存硬件识别信息（第194-204行）](#10-第2节完整内存硬件识别信息第194-204行)
11. [第3节：当前系统内存占用（第206-210行）](#11-第3节当前系统内存占用第206-210行)
12. [第4节：ECC内存纠错 & BMC内存传感器（第212-285行）](#12-第4节ecc内存纠错--bmc内存传感器第212-285行)
13. [第5节：内存压力测试 stress-ng（第287-346行）](#13-第5节内存压力测试stress-ng第287-346行)
14. [第5.1节：压测后报错采集与前后对比（第348-428行）](#14-第51节压测后报错采集与前后对比第348-428行)
15. [第6节：远程iBMC硬件信息采集（第430-481行）](#15-第6节远程ibmc硬件信息采集第430-481行)
16. [第7节：轮次判断+重启逻辑（第483-514行）](#16-第7节轮次判断重启逻辑第483-514行)
17. [双轨日志架构详解](#17-双轨日志架构详解)
18. [iBMC ipmcget 命令参考手册](#18-ibmc-ipmcget-命令参考手册)
19. [常见修改指南](#19-常见修改指南)
20. [关键设计决策记录](#20-关键设计决策记录)
21. [故障排查指南](#21-故障排查指南)

---

## 1. 脚本整体架构与执行流程

### 1.1 执行流程图

```
开机 → systemd 拉起 mem_test.service → 脚本启动
  │
  ├─ sleep 15（等待网络就绪）
  ├─ 自动部署 systemd service（首次运行）
  ├─ 读取 current_loop.flag 确定当前轮次
  │
  ├─ 第0节：自检（工具/BMC网络/BMC SSH）
  │    └─ 失败（工具缺/网络不通）→ exit 1
  │    └─ BMC SSH失败 → 软警告，继续
  │
  ├─ 第1节：OS/BIOS基础信息
  ├─ 第2节：内存硬件识别（dmidecode）
  ├─ 第3节：内存占用（free -g）
  │
  ├─ 第4节：压测前快照
  │    ├─ ECC纠错计数（rasdaemon）
  │    ├─ dmesg错误快照
  │    └─ BMC SEL快照
  │
  ├─ 第5节：stress-ng 压测
  │    ├─ 动态计算90%内存
  │    ├─ 后台启动 + 存活校验
  │    ├─ available列占用率校验
  │    └─ wait等待结束
  │
  ├─ 第5.1节：压测后采集 + 前后对比
  │    ├─ dmesg 新增错误
  │    ├─ ECC CE计数变化
  │    ├─ rasdaemon错误记录新增
  │    └─ BMC SEL新增
  │
  ├─ 第6节：iBMC硬件信息采集（6条ipmcget命令）
  │
  └─ 第7节：轮次判断
       ├─ 未跑完 → 轮次+1 → reboot
       └─ 跑完 → 清理service → exit 0
```

### 1.2 文件结构总览

| 行号范围 | 功能模块 |
|----------|----------|
| 1-5      | 开机网络稳定延时 |
| 7-47     | 自启动服务自动部署 |
| 49-59    | 全局配置变量区 |
| 61-92    | 轮次管理 + 临时文件管理 |
| 94-126   | 输出函数定义 + 轮次分隔头 |
| 128-179  | 第0节：连通性自检 |
| 181-192  | 第1节：OS/BIOS信息 |
| 194-204  | 第2节：内存硬件识别 |
| 206-210  | 第3节：内存占用 |
| 212-285  | 第4节：ECC纠错 + dmesg快照 + SEL快照 |
| 287-346  | 第5节：内存压力测试 |
| 348-428  | 第5.1节：压测后报错采集与前后对比 |
| 430-481  | 第6节：远程iBMC硬件信息采集 |
| 483-514  | 第7节：轮次判断+重启逻辑 |

---

## 2. 开机网络稳定延时（第1-5行）

### 代码

```bash
#!/bin/bash

# --------------------------开机网络稳定延时--------------------------
# 确保 Systemd 开机拉起服务时，网卡已完全获取 IP 且网络协议栈就绪
sleep 15
```

### 代码意义

服务器开机后，systemd 会按照依赖关系拉起服务。虽然 service 文件里写了 `After=network-online.target`，但 `network-online.target` 只表示"网络栈已初始化"，不代表网卡已经拿到 IP 地址。如果脚本在网卡拿到 IP 之前就执行 ping BMC 或 SSH 登录，会直接失败。

`sleep 15` 是一个简单粗暴但可靠的兜底措施：开机后强制等15秒，确保 DHCP/静态IP 已分配完成。

### 修改方法

- 如果你的环境网络初始化特别慢（比如跨 VLAN 的 DHCP），可以增大到 30 或 60
- 如果网络是静态 IP 且初始化很快，可以减小到 5
- 不建议删除：删掉后可能出现"偶尔开机第一次 ping BMC 失败"的间歇性问题

---

## 3. 自启动服务自动部署（第7-47行）

### 3.1 脚本路径获取与换行符修复（第9-16行）

```bash
SELF_PATH=$(readlink -f "$0")
chmod +x "${SELF_PATH}"

if grep -rl $'\r' "${SELF_PATH}" &>/dev/null; then
    sed -i 's/\r$//' "${SELF_PATH}"
    echo "[部署] 检测到 Windows 换行符，已自动转换为 LF"
fi
```

### 代码意义

- `readlink -f "$0"`：获取脚本的绝对路径。`$0` 是脚本自身的路径，但可能是相对路径（如 `./mem_reboot_auto.sh`），`readlink -f` 会解析成绝对路径（如 `/root/mem_reboot_auto.sh`）。后续 service 文件需要绝对路径。
- `chmod +x`：赋予执行权限
- `grep -rl $'\r'`：检测文件中是否包含 Windows 换行符 `\r\n`。从 Windows 上传到 Linux 的脚本经常带 `\r`，会导致 bash 报错 `'\r': command not found`
- `sed -i 's/\r$//'`：原地删除每行末尾的 `\r`，转换为 Unix 换行符 `\n`

### 修改方法

- 这段代码不需要修改，是自动适配逻辑
- 如果你知道环境永远是 Linux 原生文件，可以删除换行符检测部分，但不建议

### 3.2 Systemd Service 文件创建（第17-37行）

```bash
SERVICE_FILE="/etc/systemd/system/mem_test.service"
if [ ! -f "${SERVICE_FILE}" ]; then
    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Memory Reboot Auto Test
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash ${SELF_PATH}
TimeoutStartSec=0
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable mem_test.service 2>/dev/null
fi
```

### 代码意义

**首次运行自动创建 service 文件**。脚本第一次执行时检测到 service 文件不存在，自动写入、daemon-reload、enable。后续每次运行检测到已存在则跳过。

service 文件各字段含义：

| 字段 | 值 | 说明 |
|------|-----|------|
| `After=network-online.target` | - | 在网络就绪后启动 |
| `Wants=network-online.target` | - | 拉起网络就绪目标 |
| `Type=oneshot` | - | 一次性任务，执行完即退出。适合"跑一轮测试然后重启"的场景 |
| `ExecStart=/bin/bash ${SELF_PATH}` | - | 显式用 /bin/bash 调用脚本。如果不写 /bin/bash，systemd 会用默认 shell（可能是 /bin/sh），在某些系统上会导致 bash 语法不支持 |
| `TimeoutStartSec=0` | - | 不限制超时。压测可能跑几小时，如果设默认值90秒会被 systemd 强杀 |
| `RemainAfterExit=no` | - | 退出后不保持 active 状态。如果设 yes，脚本退出后 systemd 会认为服务还在运行，reboot 时可能有问题 |
| `WantedBy=multi-user.target` | - | 开机自动启动（多用户模式，即命令行模式） |

### 修改方法

- **修改开机启动行为**：改 `[Install]` 部分的 `WantedBy`
- **修改超时**：`TimeoutStartSec=0` 改成具体秒数（如 `3600`），但一般不需要
- **修改 service 名称**：把 `mem_test.service` 改成你想要的名字，注意脚本里所有引用都要一起改（第17、35、498-500行）

### 3.3 Service 文件换行符修复 + SELinux（第39-47行）

```bash
if grep -q $'\r' "${SERVICE_FILE}" 2>/dev/null; then
    sed -i 's/\r$//' "${SERVICE_FILE}"
    systemctl daemon-reload
fi

restorecon "${SERVICE_FILE}" "${SELF_PATH}" 2>/dev/null
chmod +x "${SELF_PATH}"
```

### 代码意义

- service 文件也可能带 Windows 换行符，同样需要修复
- `restorecon`：恢复 SELinux 安全上下文。openEuler 默认开启 SELinux，如果 service 文件的 SELinux 标签不对，systemd 会拒绝执行。`restorecon` 会自动修正标签
- 最后再 `chmod +x` 一次，确保权限正确

### 为什么不用 `nohup` 或 `crontab`？

| 方式 | 优势 | 劣势 |
|------|------|------|
| **systemd service**（本脚本） | 开机自动拉起、重启后自动继续、超时可控、日志可追溯 | 需要 root 权限 |
| nohup | 简单 | 重启后不会自动继续，需要手动再跑 |
| crontab @reboot | 开机自动启动 | 无法精确控制执行顺序，不适合"跑完→重启→再跑"的循环场景 |

本脚本的核心需求是"跑完一轮 → reboot → 开机自动跑下一轮"，systemd service 是唯一合适的方案。

---

## 4. 全局配置变量区（第49-59行）

```bash
BMC_IP="10.50.0.201"
BMC_USER="Administrator"
BMC_PWD="Admin@9000"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
STRESS_CHECK_WAIT=15   # 压测启动后等待校验时长（秒）
STRESS_DURATION=30    # 内存压力总运行时长（秒）
MAX_LOOP=1             # 总共执行5轮完整测试
LOG_DIR="/root/test_log"
LOOP_FLAG="${LOG_DIR}/current_loop.flag"
mkdir -p ${LOG_DIR}
```

### 代码意义

这是用户最需要关注的区域——所有可配置参数集中在这里。

| 变量 | 当前值 | 说明 |
|------|--------|------|
| `BMC_IP` | 10.50.0.201 | iBMC 管理网口 IP 地址 |
| `BMC_USER` | Administrator | iBMC SSH 登录账号 |
| `BMC_PWD` | Admin@9000 | iBMC SSH 登录密码 |
| `SSH_OPTS` | -o ... | SSH 选项：跳过主机密钥检查 + 不写 known_hosts + 10秒连接超时 |
| `STRESS_CHECK_WAIT` | 15 | 压测启动后等多少秒再校验内存占用是否达标 |
| `STRESS_DURATION` | 30 | 每轮压测运行时长（秒） |
| `MAX_LOOP` | 1 | 总测试轮次 |
| `LOG_DIR` | /root/test_log | 日志输出目录 |
| `LOOP_FLAG` | .../current_loop.flag | 轮次计数器文件路径 |

### SSH_OPTS 参数详解

| 参数 | 作用 |
|------|------|
| `StrictHostKeyChecking=no` | 不检查远程主机密钥，避免首次连接时交互式询问 yes/no |
| `UserKnownHostsFile=/dev/null` | 不写入 known_hosts 文件，避免 BMC 重装后密钥变化导致连接失败 |
| `ConnectTimeout=10` | 连接超时10秒，避免 BMC 不可达时无限等待 |

### 修改方法

**必改项（根据实际环境）**：
- `BMC_IP`：改成你的 iBMC IP
- `BMC_USER` / `BMC_PWD`：改成你的 BMC 账号密码
- `STRESS_DURATION`：实际测试建议设 300（5分钟）或更长
- `MAX_LOOP`：实际测试建议设 5（5轮重启循环）

**选改项**：
- `STRESS_CHECK_WAIT`：如果内存很大（>256G），stress-ng 填充内存需要更长时间，可以增大到 30
- `LOG_DIR`：如果不想用 /root/test_log，可以改成其他路径

### 代码中注释与实际值不一致的说明

第56行注释写的是"总共执行5轮完整测试"，但实际值是 `MAX_LOOP=1`。这是因为当前是调试阶段只跑1轮，注释保留的是生产环境的推荐值。上线时把值改回5即可。

---

## 5. 轮次管理与临时文件管理（第61-92行）

### 5.1 轮次计数器（第61-70行）

```bash
if [ ! -f ${LOOP_FLAG} ];then
    echo 1 > ${LOOP_FLAG}
fi
CUR_LOOP=$(cat ${LOOP_FLAG} 2>/dev/null)
if ! [[ "${CUR_LOOP}" =~ ^[0-9]+$ ]] || [ "${CUR_LOOP}" -lt 1 ]; then
    CUR_LOOP=1
    echo 1 > ${LOOP_FLAG}
fi
```

### 代码意义

**轮次持久化机制**：脚本通过文件 `current_loop.flag` 记录当前是第几轮。每次 reboot 后脚本重新启动，从这个文件读取轮次。

执行逻辑：
1. 文件不存在 → 创建并写入 1（第一轮）
2. 文件存在 → 读取内容
3. 内容不是正整数（文件损坏/被误编辑）→ 重置为 1

**为什么不用环境变量？** 因为 reboot 后环境变量会丢失，文件是唯一能跨重启持久化的方式。

### `[[ "${CUR_LOOP}" =~ ^[0-9]+$ ]]` 详解

- `[[ ]]`：bash 的条件判断，比 `[ ]` 更强大
- `=~`：正则匹配运算符（只有 `[[ ]]` 支持，`[ ]` 不支持）
- `^[0-9]+$`：从开头到结尾全是数字

这是防御性编程：如果有人手动编辑 flag 文件写入了字母或空行，脚本不会崩溃，而是自动重置为第1轮。

### 修改方法

- 如果想从第3轮开始测试（跳过前2轮）：`echo 3 > /root/test_log/current_loop.flag`
- 如果想重新从第1轮开始：`rm /root/test_log/current_loop.flag`，下次运行自动创建
- 如果想增加轮次数：改 `MAX_LOOP` 变量，不需要改这段代码

### 5.2 双轨日志文件定义（第71-73行）

```bash
CUR_LOG="${LOG_DIR}/完整测试报告.log"
RAW_LOG="${LOG_DIR}/完整测试日志.log"
```

### 代码意义

| 文件 | 内容 | 用途 |
|------|------|------|
| 完整测试报告.log | 经 grep/awk 过滤的关键信息摘要 | 快速查看测试结论，给客户看的 |
| 完整测试日志.log | 未经任何过滤的完整原始数据 + `# CMD:` 命令标记 | 问题追溯、debug、审计取证 |

两份文件都是**多轮追加写入**，轮次之间以空行分隔。

### 修改方法

- 想改文件名：直接改这两个变量的值
- 想每轮分开文件（旧模式）：改回 `CUR_LOG="${LOG_DIR}/第${CUR_LOOP}轮_$(date +%Y%m%d_%H%M%S).log"`

### 5.3 临时快照文件（第75-81行）

```bash
PRE_ERR="${LOG_DIR}/pre_err_${CUR_LOOP}.tmp"    # 压测前 dmesg 错误快照
POST_ERR="${LOG_DIR}/post_err_${CUR_LOOP}.tmp"  # 压测后 dmesg 错误快照
PRE_SEL="${LOG_DIR}/pre_sel_${CUR_LOOP}.tmp"    # 压测前 SEL 快照
POST_SEL="${LOG_DIR}/post_sel_${CUR_LOOP}.tmp"  # 压测后 SEL 快照
PRE_RAS="${LOG_DIR}/pre_ras_${CUR_LOOP}.tmp"   # 压测前 rasdaemon 记录快照
POST_RAS="${LOG_DIR}/post_ras_${CUR_LOOP}.tmp" # 压测后 rasdaemon 记录快照
```

### 代码意义

这些是**压测前后的"快照"文件**，用于 diff 对比。文件名带 `${CUR_LOOP}` 是为了防止多轮并行时文件冲突（虽然本脚本不会并行，但这是防御性设计）。

| 文件对 | 存什么 | 对比方式 |
|--------|--------|----------|
| PRE_ERR / POST_ERR | dmesg 过滤后的错误行 | diff 取新增行 |
| PRE_SEL / POST_SEL | BMC SEL 日志完整输出 | diff 取新增行 |
| PRE_RAS / POST_RAS | rasdaemon --errors 过滤后的错误记录 | diff 取新增行 + 行数对比 |
| PRE_ERR.ras | rasdaemon --error-count 数值 | grep 提取CE数字做数值对比 |

### 5.4 清理与 trap 兜底（第82-92行）

```bash
rm -f ${LOG_DIR}/pre_err_${CUR_LOOP}.tmp ... 2>/dev/null

TMP_CLEANUP_LIST="${PRE_ERR} ${POST_ERR} ..."
trap 'rm -f ${TMP_CLEANUP_LIST} 2>/dev/null' EXIT
```

### 代码意义

两层清理：
1. **开头清理**：删除可能存在的上轮残留文件（防止上轮异常退出遗留）
2. **trap EXIT**：脚本退出时（不管正常退出还是异常退出）自动清理本轮临时文件

`trap '...' EXIT` 是 bash 的信号捕获机制。EXIT 信号在脚本以任何方式退出时都会触发（正常 exit、被 kill、被 OOM 杀死除外）。这确保临时文件不会堆积。

### 修改方法

- 如果调试时需要查看临时文件内容：把 `trap` 那行注释掉，临时文件就不会被清理
- 如果新增了临时文件：把文件路径加到 `TMP_CLEANUP_LIST` 变量里

---

## 6. 输出函数体系：print_step / print_text / print_data（第94-119行）

这是整个脚本的**输出基础设施**。所有输出都通过这三个函数，确保屏幕显示和文件记录同步。

### 6.1 print_step（第95-100行）

```bash
print_step(){
    local title="$1"
    echo -e "\n==================== ${title} ===================="
    echo -e "\n==================== ${title} ====================" >> ${CUR_LOG}
    echo -e "\n==================== ${title} ====================" >> ${RAW_LOG}
}
```

### 代码意义

输出步骤标题分隔线，同时写入屏幕、报告、日志三个目标。

- `local title="$1"`：`local` 声明局部变量，避免污染全局命名空间
- `echo -e`：`-e` 启用转义解释，`\n` 表示先输出一个空行再输出标题
- 三行 echo 分别写屏幕、CUR_LOG、RAW_LOG

### 6.2 print_text（第102-114行）

```bash
print_text(){
    if [ "$1" = "-e" ]; then
        shift
        echo -e "$*"
        echo -e "$*" >> ${CUR_LOG}
        echo -e "$*" >> ${RAW_LOG}
    else
        echo "$*"
        echo "$*" >> ${CUR_LOG}
        echo "$*" >> ${RAW_LOG}
    fi
}
```

### 代码意义

输出文本内容。兼容 `-e` 参数：
- `print_text "普通文本"` → 不解释转义
- `print_text -e "\n带换行的文本"` → 解释转义

- `shift`：去掉第一个参数（-e），剩余参数用 `$*` 输出
- `$*`：所有参数合并成一个字符串

### 为什么不统一用 echo -e？

因为有些输出内容包含反斜杠（如文件路径 `\`），如果统一用 `-e`，反斜杠会被误解释。所以需要区分：需要转义的用 `-e`，不需要的不加。

### 6.3 print_data（第116-119行）

```bash
print_data(){
    echo "# CMD: $*" >> ${RAW_LOG}
    "$@" | tee -a ${CUR_LOG} ${RAW_LOG}
}
```

### 代码意义

**最重要的函数**。执行命令并捕获输出。

- `echo "# CMD: $*" >> ${RAW_LOG}`：在日志中写入命令审计标记。`$*` 展开为所有参数（即完整命令）
- `"$@"`：执行传入的命令。`"$@"` 会保留参数边界（比 `$*` 更安全）
- `tee -a ${CUR_LOG} ${RAW_LOG}`：`-a` 追加模式，同时写入报告和日志

### $* vs "$@" 的区别

```bash
# 假设调用：print_data grep -E "Size:|Type:" /tmp/file

# $* → "grep -E Size:|Type: /tmp/file"（参数合并，空格分隔的字符串）
#    用于 echo "# CMD: $*" 时方便阅读

# "$@" → "grep" "-E" "Size:|Type:" "/tmp/file"（保持参数边界）
#   用于 "$@" 执行命令时不会把带空格的参数拆散
```

### 调用示例

```bash
print_data free -g
# 屏幕输出：free -g 的结果
# 报告写入：free -g 的结果
# 日志写入：# CMD: free -g \n free -g 的结果

print_data dmidecode -t memory
# 日志写入：# CMD: dmidecode -t memory \n dmidecode 完整输出
```

### 修改方法

- 如果想让 print_data 也写入屏幕（当前已有 tee 到屏幕）：不需要改，tee 默认就输出到屏幕
- 如果想增加第三个输出目标（比如发送到远程）：在 tee 后面加文件名

---

## 7. 轮次分隔头（第121-126行）

```bash
# 多轮日志写入同一文件，轮次之间用空行分隔
echo "" >> ${CUR_LOG} 2>/dev/null
echo "" >> ${RAW_LOG} 2>/dev/null
print_text "==================== 第${CUR_LOOP}轮 完整测试开始 时间：$(date) ===================="
print_text "完整测试报告：${CUR_LOG}"
print_text "完整测试日志：${RAW_LOG}"
```

### 代码意义

每轮开始前：
1. 在两个文件末尾各写一个空行（视觉分隔）
2. 输出轮次标题（含当前轮次和时间戳）
3. 输出两个文件的路径（方便用户查看）

`$(date)` 会展开为当前系统时间，如 `2026年 06月 24日 星期三 11:08:49 CST`。

### 效果预览

```
（空行）

==================== 第1轮 完整测试开始 时间：2026年 06月 24日 星期三 11:08:49 CST ====================
完整测试报告：/root/test_log/完整测试报告.log
完整测试日志：/root/test_log/完整测试日志.log
==================== 0. 开始连通性自检（共3项） ====================
...
```

---

## 8. 第0节：连通性自检（第128-179行）

### 8.1 自检1/3：依赖工具校验（第133-144行）

```bash
CHECK_PASS=1
TOOL_LIST=("stress-ng" "sshpass" "dmidecode" "free")

for tool in ${TOOL_LIST[@]}
do
    if ! command -v $tool &> /dev/null;then
        print_text "【FAIL】缺失工具：$tool"
        CHECK_PASS=0
    else
        print_text "【OK】工具正常：$tool"
    fi
done
```

### 代码意义

检查四个必需工具是否安装：

| 工具 | 用途 | 安装命令 |
|------|------|----------|
| stress-ng | 内存压力测试 | `yum install stress-ng` |
| sshpass | SSH 自动输入密码 | `yum install sshpass` |
| dmidecode | 读取硬件信息（SMBIOS） | `yum install dmidecode` |
| free | 查看内存占用 | 通常已预装（procps-ng 包） |

- `command -v $tool`：检查命令是否存在（比 `which` 更标准）
- `&> /dev/null`：丢弃输出（只关心退出码）
- `TOOL_LIST=(...)`：bash 数组语法，`${TOOL_LIST[@]}` 展开全部元素

### 修改方法

- 如果新增了依赖工具（如 `ipmitool`）：加到 `TOOL_LIST` 数组里
- 如果想改成软警告（缺工具不终止）：把 `CHECK_PASS=0` 改成 `print_text "【WARN】..."`

### 8.2 自检2/3：BMC网络连通性（第146-152行）

```bash
if ping -c3 ${BMC_IP} &>/dev/null;then
    print_text "【OK】BMC网络连通正常"
else
    print_text "【FAIL】无法ping通BMC ${BMC_IP}，网络异常"
    CHECK_PASS=0
fi
```

### 代码意义

`ping -c3` 发送3个 ICMP 包。ping 不通说明 BMC 网络不可达，设 CHECK_PASS=0 终止测试。

### 修改方法

- 如果 BMC 禁用了 ICMP（某些安全加固环境）：可以改成用 `nc -z ${BMC_IP} 22` 检测 SSH 端口
- 如果 BMC 在不同网段需要指定源接口：`ping -c3 -I eth0 ${BMC_IP}`

### 8.3 自检3/3：BMC SSH登录验证（第154-168行）

```bash
BMC_SSH_OK=0

SSH_ERR=$(sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d version" 2>&1)
SSH_RET=$?
if [ ${SSH_RET} -eq 0 ]; then
    print_text "【OK】BMC SSH登录校验通过"
    BMC_SSH_OK=1
else
    print_text "【WARN】BMC SSH登录失败（退出码${SSH_RET}），远程采集将跳过，但不终止测试"
    print_text "  错误信息：${SSH_ERR}"
    print_text "  压测+报错对比不依赖BMC SSH，将正常执行"
fi
```

### 代码意义

用 `ipmcget -d version` 作为连通性测试命令（既能验证 SSH 登录，又能验证 ipmcget 可用）。

**关键设计：BMC SSH 失败是软警告**，不设 `CHECK_PASS=0`，不终止测试。原因：核心压测和 dmesg 对比不依赖 BMC，即使 BMC 不可用也应该继续跑。

- `2>&1`：标准错误重定向到标准输出，捕获错误信息到 SSH_ERR 变量
- `$?`：上一条命令的退出码。0=成功，非0=失败

### 修改方法

- 如果想让 BMC SSH 失败也终止测试：在 else 分支加 `CHECK_PASS=0`
- 如果想改测试命令：把 `ipmcget -d version` 改成其他 ipmcget 子命令

### 8.4 自检结果汇总（第170-179行）

```bash
if [ ${CHECK_PASS} -ne 1 ];then
    print_text "########## 自检存在异常，终止本轮测试 ##########"
    exit 1
fi
if [ ${BMC_SSH_OK} -eq 1 ]; then
    print_text "全部连通校验通过，进入正式信息采集流程"
else
    print_text "基础校验通过（工具OK、网络通），BMC SSH不可用，继续执行核心压测流程"
fi
```

### 代码意义

两级判断：
1. CHECK_PASS=0（工具缺或网络不通）→ exit 1 终止
2. CHECK_PASS=1 + BMC_SSH_OK=0 → 继续执行，但跳过所有 BMC 相关采集

---

## 9. 第1节：OS & BIOS基础信息（第181-192行）

```bash
print_step "1. 采集OS & BIOS基础信息"
print_text "1.1 OpenEuler系统版本："
print_data cat /etc/openEuler-release

print_text "1.2 系统内核 uname -a："
print_data uname -a

print_text "1.3 BIOS固件版本号："
print_data dmidecode -s bios-version
```

### 代码意义

三条基础信息采集命令：

| 命令 | 输出内容 | 为什么需要 |
|------|----------|------------|
| `cat /etc/openEuler-release` | openEuler 版本号 | 不同版本的内核行为可能不同 |
| `uname -a` | 内核版本、架构、编译信息 | 内核版本影响 dmesg 输出格式、EDAC 驱动行为 |
| `dmidecode -s bios-version` | BIOS 固件版本 | BIOS 版本影响内存训练参数、ECC 报告方式 |

全部通过 `print_data` 执行，日志中会记录 `# CMD:` 标记。

### dmidecode -s vs dmidecode -t

- `dmidecode -s bios-version`：只输出 BIOS 版本号（一个字符串）
- `dmidecode -t memory`：输出所有内存相关的 SMBIOS 信息（详细的多段文本）

`-s` 用于取单个值，`-t` 用于取一类信息。

---

## 10. 第2节：完整内存硬件识别信息（第194-204行）

### 2.1 内存槽位摘要（第199-201行）

```bash
echo "# CMD: dmidecode -t memory" >> ${RAW_LOG}
dmidecode -t memory | tee -a ${RAW_LOG} | grep -E "Size:|Type:|Speed:|Locator:|Manufacturer:|Part Number:" | grep -v "No Module\|Unknown" | tee -a ${CUR_LOG}
```

### 代码意义

**双轨管道**的经典实现：

```
dmidecode -t memory（完整输出）
    │
    ├─ tee -a ${RAW_LOG} ──→ 完整输出写入日志（全量原始数据）
    │
    └─ grep -E "Size:|..." ──→ 只保留关键字段行
         │
         └─ grep -v "No Module\|Unknown" ──→ 排除空槽位
              │
              └─ tee -a ${CUR_LOG} ──→ 摘要写入报告
```

- 第一层 grep：从 dmidecode 输出中提取 Size（容量）、Type（类型）、Speed（速率）、Locator（槽位）、Manufacturer（厂商）、Part Number（型号）这几行
- 第二层 grep -v：排除 "No Module Installed"（空槽）和 "Unknown"（未知类型），只显示已安装的内存条

### 修改方法

- 想增加显示字段：在第一个 grep -E 里加，如 `"Serial Number:"`
- 想显示空槽位：删除 `grep -v "No Module\|Unknown"` 部分
- 想改过滤逻辑：修改 grep 模式

### 2.2 完整 dmidecode 原始输出（第203-204行）

```bash
print_text "2.2 完整 dmidecode 原始输出："
print_data dmidecode -t memory
```

通过 print_data 再次输出完整 dmidecode。注意 RAW_LOG 中会有两份完整 dmidecode 输出（一份来自 2.1 的 tee，一份来自 2.2 的 print_data），这是设计上的冗余，确保原始数据不会丢失。

---

## 11. 第3节：当前系统内存占用（第206-210行）

```bash
print_step "3. 当前系统内存占用 free -g"
print_data free -g
```

### 代码意义

`free -g`：以 GB 为单位显示内存占用。记录压测前的系统内存基线状态。

### free 命令输出解读

```
              total        used        free      shared  buff/cache   available
Mem:            123          1         120           0            2         120
Swap:             0          0           0
```

| 列 | 含义 | 本脚本用途 |
|----|------|------------|
| total | 物理内存总量 | 第5节计算压测分配量 |
| used | 已用内存（含cache/buffer） | 不用（含干扰） |
| free | 完全空闲内存 | 不用（不含可回收cache） |
| buff/cache | 缓冲/缓存 | 不用 |
| **available** | **可用内存（含可回收cache）** | **第5节校验压测效果** |

---

## 12. 第4节：ECC内存纠错 & BMC内存传感器（第212-285行）

### 12.1 ECC工具检测（第217-233行）

```bash
ECC_TOOL="none"
if command -v ras-mc-ctl &>/dev/null; then
    if ! systemctl is-active rasdaemon &>/dev/null; then
        systemctl start rasdaemon 2>/dev/null
        sleep 2
    fi
    if systemctl is-active rasdaemon &>/dev/null; then
        ECC_TOOL="rasdaemon"
        print_text "【OK】ECC监控工具：rasdaemon（服务运行中）"
    else
        print_text "【WARN】ras-mc-ctl 已安装但 rasdaemon 服务启动失败"
    fi
else
    print_text "【WARN】未安装 rasdaemon，ECC 纠错计数将跳过"
    print_text "  安装：yum install rasdaemon && systemctl enable --now rasdaemon"
fi
```

### 代码意义

**仅使用 rasdaemon**，不使用 edac-util。

检测逻辑（三层）：
1. `ras-mc-ctl` 命令是否安装 → 没装就跳过
2. `rasdaemon` 服务是否运行 → 没运行就尝试启动
3. 启动后再确认是否运行 → 确认成功才设 ECC_TOOL="rasdaemon"

`sleep 2`：启动服务后等2秒，确保 daemon 完全就绪。

### 为什么不用 edac-util？

- edac-util 在新内核上经常无法读取 ECC 信息（EDAC 驱动兼容性问题）
- rasdaemon 是 openEuler 官方推荐的 ECC 监控工具
- rasdaemon 基于内核 tracepoint 机制，比 edac-util 更可靠

### 修改方法

- 如果环境用 edac-util：需要替换整个 ECC 检测和采集逻辑（不建议）
- 如果 rasdaemon 启动慢：增大 sleep 时间

### 12.2 内存传感器SDR信息（第235-236行）

```bash
print_text "4.1 内存传感器SDR信息："
print_data ipmitool sdr type Memory
```

### 代码意义

从 **OS 侧**通过 `ipmitool` 查询内存类型传感器。注意这条命令是在 OS 上执行的 ipmitool（通过 IPMI 协议端口623查询 BMC），不是 SSH 登录 BMC 执行的。

### 12.3 压测前 ECC纠错计数快照（第238-254行）

```bash
if [ "${ECC_TOOL}" = "rasdaemon" ]; then
    echo "# CMD: ras-mc-ctl --error-count" >> ${RAW_LOG}
    ras-mc-ctl --error-count 2>/dev/null | tee -a ${CUR_LOG} ${RAW_LOG}
    ras-mc-ctl --error-count 2>/dev/null > "${PRE_ERR}.ras"
    ras-mc-ctl --errors 2>/dev/null | grep -viE "^$|no .*error|:$" > ${PRE_RAS}
    PRE_RAS_COUNT=$(wc -l < ${PRE_RAS} | tr -d ' ')
    print_text "压测前 rasdaemon 错误记录条数：${PRE_RAS_COUNT}"
else
    echo "no ecc tool" > "${PRE_ERR}.ras"
    > ${PRE_RAS}
fi
```

### 代码意义

采集**两个维度的 ECC 快照**：

| 命令 | 存入 | 用途 |
|------|------|------|
| `ras-mc-ctl --error-count` | PRE_ERR.ras | 数值对比：压测后 CE 数字是否增长 |
| `ras-mc-ctl --errors` | PRE_RAS | 记录对比：压测后是否有新的错误记录 |

- `--error-count`：输出 CE/UE 的数字计数（如 "CE count: 0"）
- `--errors`：输出详细的错误记录（有时间戳、地址、类型等）
- `grep -viE "^$|no .*error|:$"`：过滤空行、"No xxx errors" 占位行、纯冒号标题行

### `--errors` vs `--records`

- `--records`：输出所有 rasdaemon 记录（含非错误记录），行数多但噪音大
- `--errors`：只输出错误记录，更精确

本脚本使用 `--errors` 避免非错误行导致的计数误报。

### 12.4 dmesg精确筛选规则（第256-261行）

```bash
DMESG_ERR_PATTERN='hardware error|corrected error|uncorrected error|ECC.*(error|fail)|EDAC.*: [0-9]+ (CE|UE)|mce.*(error|exception|overflow)|memory.*(error|fail|fault|corrupt|poison|degrad)|page allocation failure|out of memory|oom-kill|bad ram|DIMM.*(error|fail|fault)|ras:.*(error|event)'
```

### 代码意义

这是 dmesg 错误筛选的**核心正则表达式**。用 `|` 分隔多个模式，匹配任意一个即命中。

| 模式 | 匹配什么 | 为什么这样写 |
|------|----------|------------|
| `hardware error` | 硬件错误 | 通用硬件报错前缀 |
| `corrected error` | 已纠正错误 | ECC CE 的常见描述 |
| `uncorrected error` | 未纠正错误 | ECC UE 的常见描述 |
| `ECC.*(error\|fail)` | ECC 相关错误/失败 | 必须搭配 error/fail，避免匹配 "ECC enabled" |
| `EDAC.*: [0-9]+ (CE\|UE)` | EDAC 报告格式 | "EDAC MC0: 1 CE" 这种格式，不裸匹配 CE |
| `mce.*(error\|exception\|overflow)` | MCE 错误 | Machine Check Exception |
| `memory.*(error\|fail\|fault\|corrupt\|poison\|degrad)` | 内存相关错误 | 必须搭配错误上下文 |
| `page allocation failure` | 页面分配失败 | 内存不足时的内核报错 |
| `out of memory` | OOM | 内核 OOM killer |
| `oom-kill` | OOM 杀进程 | OOM killer 的行动记录 |
| `bad ram` | 坏内存 | 内核标记的坏内存区域 |
| `DIMM.*(error\|fail\|fault)` | DIMM 错误 | 内存条级别的报错 |
| `ras:.*(error\|event)` | rasdaemon 事件 | rasdaemon 在 dmesg 中的记录 |

### 核心原则

1. **CE/UE 只在 EDAC 报告格式中匹配**，不做裸子串匹配。如果裸匹配 "CE"，会误中 "device"、"queue" 等无关词
2. **memory/ECC/mce 必须搭配 error/fail/fault 等错误上下文**，避免匹配 "ECC enabled"、"memory size" 等正常信息

### 修改方法

- 想增加匹配关键词：在模式末尾加 `|新关键词`
- 想减少误报：给关键词加更多上下文限制，如 `ECC.*(error|fail)` 改成 `ECC.*(error|fail) on (DIMM|memory|MC)`
- `grep -Ei`：`-E` 扩展正则，`-i` 忽略大小写

### 12.5 压测前 dmesg 错误快照（第263-274行）

```bash
echo "# CMD: dmesg" >> ${RAW_LOG}
dmesg | tee -a ${RAW_LOG} | grep -Ei "${DMESG_ERR_PATTERN}" > ${PRE_ERR} 2>/dev/null
PRE_ERR_COUNT=$(wc -l < ${PRE_ERR})
```

### 代码意义

**双轨管道**：dmesg 完整输出 → tee 写入日志 → grep 过滤 → 存入 PRE_ERR 临时文件。

- `PRE_ERR_COUNT`：压测前已存在的错误行数。如果不为0，说明开机前就有错误（可能是上次压测遗留或硬件本身有问题）

### 12.6 压测前 BMC SEL 快照（第276-285行）

```bash
if [ ${BMC_SSH_OK} -eq 1 ]; then
    sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d sel" > ${PRE_SEL} 2>/dev/null
    PRE_SEL_COUNT=$(wc -l < ${PRE_SEL} 2>/dev/null | tr -d ' ' || echo 0)
else
    > ${PRE_SEL}
fi
```

### 代码意义

SSH 登录 BMC 执行 `ipmcget -d sel` 获取 SEL 日志，存入临时文件。SSH 不可用时创建空文件（保证后续 diff 不报错）。

- `tr -d ' '`：删除 wc 输出中的空格（某些系统的 wc 输出带前导空格）
- `|| echo 0`：wc 失败时返回0（防御性编程）

---

## 13. 第5节：内存压力测试 stress-ng（第287-346行）

### 13.1 内存分配计算（第290-294行）

```bash
MEM_TOTAL=$(free -g | awk '/Mem:/{print $2}')
STRESS_MEM=$(( MEM_TOTAL * 9 / 10 ))
print_text "整机总内存${MEM_TOTAL}G，压测分配内存${STRESS_MEM}G"
```

### 代码意义

- `free -g | awk '/Mem:/{print $2}'`：从 free 输出中提取 Mem 行的第2列（total），单位 GB
- `$(( MEM_TOTAL * 9 / 10 ))`：bash 算术运算，计算总内存的 90%

**动态变量**：MEM_TOTAL 和 STRESS_MEM 是运行时动态计算的。插4根条时 free 读到 123，算出 110；插16根条时 free 读到 512，算出 460。不是写死的。

### awk 语法解读

- `/Mem:/`：匹配包含 "Mem:" 的行
- `{print $2}`：输出第2列（以空格分隔）
- free -g 输出：`Mem: 123 1 120 0 2 120`，$2 就是 123

### 13.2 启动压测（第296-300行）

```bash
echo "# CMD: stress-ng --vm 1 --vm-bytes ${STRESS_MEM}G --vm-keep --vm-populate --timeout ${STRESS_DURATION}" >> ${RAW_LOG}
stress-ng --vm 1 --vm-bytes ${STRESS_MEM}G --vm-keep --vm-populate --timeout ${STRESS_DURATION} &
STRESS_PID=$!
```

### 代码意义

| 参数 | 作用 |
|------|------|
| `--vm 1` | 启动1个 vm（virtual memory）worker |
| `--vm-bytes ${STRESS_MEM}G` | 每个worker分配的内存量（动态计算） |
| `--vm-keep` | 持续占用内存不释放（不是分配后立即释放） |
| `--vm-populate` | 立即物理分配内存页（不是懒分配）。不加这个参数的话内核可能只分配虚拟地址空间，不真正占用物理内存 |
| `--timeout ${STRESS_DURATION}` | 运行指定秒数后自动退出 |
| `&` | 后台运行 |
| `STRESS_PID=$!` | `$!` 获取上一个后台进程的 PID |

### 为什么用 --vm-populate？

不加 `--vm-populate` 时，stress-ng 分配的内存只是虚拟地址空间映射，内核采用延迟分配（demand paging），只有实际写入的页才占用物理内存。这会导致内存占用率远低于预期。

加了 `--vm-populate` 后，stress-ng 会立即触犯所有页的物理分配，确保真实达到 90% 占用。

### 修改方法

- 想改内存占用比例：把 `* 9 / 10`（90%）改成 `* 95 / 100`（95%）等
- 想用多个 worker：`--vm 4`（4个worker分摊分配）
- 想加 CPU 压力：加 `--cpu 4`（4个CPU压力worker）

### 13.3 进程存活校验（第302-307行）

```bash
sleep 3
if ! ps -p ${STRESS_PID} > /dev/null; then
    print_text "【ERROR】stress-ng 进程启动失败或已被系统立即终止！"
    exit 1
fi
```

### 代码意义

启动后等3秒，检查 stress-ng 是否还活着。如果被系统立即杀死（OOM killer），说明物理内存无法承受 90% 分配。

- `ps -p ${STRESS_PID}`：检查指定 PID 的进程是否存在

### 13.4 内存占用校验（第309-334行）

```bash
MEM_AVAIL_PRE=$(free -m | awk '/Mem:/{print $7}')
sleep $((STRESS_CHECK_WAIT - 3))
MEM_AVAIL_POST=$(free -m | awk '/Mem:/{print $7}')
MEM_TOTAL_MB=$((MEM_TOTAL * 1024))
MEM_AVAIL_RATIO=$((MEM_AVAIL_POST * 100 / MEM_TOTAL_MB))
if [ ${MEM_AVAIL_RATIO} -gt 50 ]; then
    print_text "【ERROR】stress-ng 实际占用内存不足目标值一半"
    kill -9 ${STRESS_PID} 2>/dev/null
    exit 1
else
    print_text "【OK】内存压力已成功打满 90%"
fi
```

### 代码意义

**使用 free -m 第7列（available）校验压测效果**。

校验逻辑：
1. 记录压测前 available 基线（MEM_AVAIL_PRE）
2. 等待 stress-ng 填充内存（STRESS_CHECK_WAIT - 3 秒，减3是因为前面已经 sleep 3）
3. 记录压测后 available（MEM_AVAIL_POST）
4. 计算 available 占总内存的百分比
5. 如果 available 剩余超过 50% → 压测失效，终止

### 为什么用 available 而不是 used 或 RSS？

| 指标 | 问题 |
|------|------|
| used | 包含 cache/buffer，会误判（cache 可回收但算在 used 里） |
| RSS（Resident Set Size） | stress-ng 子进程层级深，pgrep 找不到所有子进程，RSS 统计不准 |
| **available** | **不含 cache/buffer/slab 干扰，是内核认为"真正可用"的内存量，最可靠** |

`free -m`：以 MB 为单位输出。第7列就是 available 列。

### 13.5 等待压测结束 + 退出码判断（第336-346行）

```bash
wait ${STRESS_PID}
STRESS_EXIT=$?
if [ ${STRESS_EXIT} -ne 0 ]; then
    print_text "【WARN】stress-ng 非正常退出（退出码${STRESS_EXIT}）"
else
    print_text "【OK】stress-ng 正常退出"
fi
```

### 代码意义

- `wait ${STRESS_PID}`：阻塞等待后台 stress-ng 进程结束
- `$?`：wait 的退出码就是 stress-ng 的退出码
- 退出码 0 = 正常结束（timeout 到期），非 0 = 异常

---

## 14. 第5.1节：压测后报错采集与前后对比（第348-428行）

这一节是测试的**核心判断逻辑**——通过前后对比判断压测是否引发了新的错误。

### 14.1 压测后 dmesg 错误快照（第353-360行）

```bash
echo "# CMD: dmesg" >> ${RAW_LOG}
dmesg | tee -a ${RAW_LOG} | grep -Ei "${DMESG_ERR_PATTERN}" > ${POST_ERR} 2>/dev/null
POST_ERR_COUNT=$(wc -l < ${POST_ERR})
cat ${POST_ERR} | tee -a ${CUR_LOG} ${RAW_LOG}
```

与压测前使用相同的 DMESG_ERR_PATTERN，采集后存入 POST_ERR。

### 14.2 dmesg 前后差异对比（第362-372行）

```bash
NEW_ERR=$(diff ${PRE_ERR} ${POST_ERR} | grep "^>" | sed 's/^> //')
NEW_ERR_COUNT=$(echo "${NEW_ERR}" | grep -c . 2>/dev/null || echo 0)

if [ -z "${NEW_ERR}" ] || [ ${NEW_ERR_COUNT} -eq 0 ]; then
    print_text "【OK】压测后无新增 dmesg 内存报错"
else
    print_text "【FAIL】压测后新增 ${NEW_ERR_COUNT} 条 dmesg 内存报错："
    echo "${NEW_ERR}" | tee -a ${CUR_LOG} ${RAW_LOG}
fi
```

### 代码意义

**diff 对比逻辑**：

```
diff PRE_ERR POST_ERR
```

diff 输出格式：
- `< 开头`的行：只在 PRE_ERR 中存在（压测前的旧错误）
- `> 开头`的行：只在 POST_ERR 中存在（压测后的新增错误）← 我们要的
- 无前缀的行：两边都有（未变化）

```bash
grep "^>"         # 只取 > 开头的行（新增错误）
sed 's/^> //'     # 去掉 "> " 前缀，还原原始内容
```

- `grep -c .`：统计非空行数（`.` 匹配任意字符，空行不匹配）
- `|| echo 0`：grep 无匹配时返回非0退出码，用 || 兜底返回0

### 14.3 ECC计数前后对比（第374-405行）

**两层对比**：

#### 层1：rasdaemon --errors 记录行数对比

```bash
ras-mc-ctl --errors 2>/dev/null | grep -viE "^$|no .*error|:$" > ${POST_RAS}
POST_RAS_COUNT=$(wc -l < ${POST_RAS} | tr -d ' ')
RAS_DIFF=$((POST_RAS_COUNT - PRE_RAS_COUNT))
if [ ${RAS_DIFF} -gt 0 ]; then
    print_text "【FAIL】rasdaemon 新增 ${RAS_DIFF} 条硬件错误记录："
    diff ${PRE_RAS} ${POST_RAS} 2>/dev/null | tee -a ${RAW_LOG} | grep "^>" | sed 's/^> //' | tee -a ${CUR_LOG}
fi
```

行数差值 > 0 说明有新增错误记录。再用 diff 提取具体新增内容。

#### 层2：rasdaemon --error-count CE数值对比

```bash
PRE_CE=$(grep -iE "correct|\bCE\b" "${PRE_ERR}.ras" 2>/dev/null | grep -oE '[0-9]+' | awk '{s+=$1}END{print s+0}')
POST_CE=$(ras-mc-ctl --error-count 2>/dev/null | grep -iE "correct|\bCE\b" | grep -oE '[0-9]+' | awk '{s+=$1}END{print s+0}')
PRE_CE=${PRE_CE:-0}; POST_CE=${POST_CE:-0}
if [ ${POST_CE} -gt ${PRE_CE} ]; then
    print_text "【FAIL】ECC CE 计数增加：${PRE_CE} → ${POST_CE}（新增 $((POST_CE - PRE_CE))）"
fi
```

### 代码意义

从 `--error-count` 输出中提取 CE（Corrected Error）的数字值，做数值对比。

**管道分解**：
```bash
grep -iE "correct|\bCE\b"    # 匹配含 "correct" 或 "CE" 的行
grep -oE '[0-9]+'            # 只提取数字部分
awk '{s+=$1}END{print s+0}'  # 求和
```

- `\bCE\b`：`\b` 是单词边界，确保匹配独立的 "CE" 而不是 "device" 中的 "ce"
- `${PRE_CE:-0}`：如果变量为空（grep 没匹配到），设为0

### 兼容性设计

rasdaemon 不同版本的 `--error-count` 输出格式有差异：
- 有的用 `CE count:` 缩写
- 有的用 `Corrected Error Count:` 全写

`grep -iE "correct|\bCE\b"` 同时搜索两种写法，确保兼容。

### 14.4 BMC SEL前后对比（第407-425行）

```bash
if [ ${BMC_SSH_OK} -eq 1 ]; then
    sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d sel" > ${POST_SEL} 2>/dev/null
    NEW_SEL=$(diff ${PRE_SEL} ${POST_SEL} 2>/dev/null | grep "^>" | sed 's/^> //')
    if [ -z "${NEW_SEL}" ]; then
        print_text "【OK】压测后 BMC SEL 无新增故障日志"
    else
        NEW_SEL_COUNT=$(echo "${NEW_SEL}" | grep -c . 2>/dev/null || echo 0)
        print_text "【FAIL】压测后 BMC SEL 新增 ${NEW_SEL_COUNT} 条故障日志："
        echo "${NEW_SEL}" | tee -a ${CUR_LOG} ${RAW_LOG}
    fi
else
    > ${POST_SEL}
fi
```

与 dmesg 对比逻辑相同：diff → grep "^>" → sed 去前缀 → 统计行数。

### 14.5 清理临时快照文件（第427-428行）

```bash
rm -f ${PRE_ERR} ${POST_ERR} ${PRE_ERR}.ras ${PRE_SEL} ${POST_SEL} ${PRE_RAS} ${POST_RAS} 2>/dev/null
```

对比完成后立即清理快照文件（trap EXIT 也会兜底清理）。

---

## 15. 第6节：远程iBMC硬件信息采集（第430-481行）

### 15.1 iBMC CLI 限制说明

**iBMC SSH 登录后进入的是受限 CLI shell**，与标准 Linux shell 有本质区别：

| 特性 | 标准 Linux shell | iBMC CLI |
|------|-------------------|----------|
| ipmitool | 可用 | 不可用（COMMAND NOT SUPPORTED） |
| echo | 可用 | 不可用 |
| printf | 可用 | 不可用 |
| grep/awk/sed | 可用 | 不可用 |
| ipmcget | 不可用 | 可用 |
| ipmcset | 不可用 | 可用 |

**因此**：
- 不能用 heredoc 把 echo 和 ipmcget 混在一起发送
- 标题（echo）必须在 OS 侧执行
- 数据通过 SSH 逐条采集
- 过滤（awk/grep）必须在 OS 侧做

### 15.2 采集逻辑（第440-467行）

整体结构是一个 `{ }` 分组，所有命令的输出统一通过 `} | tee` 写入文件。

```bash
{
    echo "==== BMC 固件版本信息 ====" | tee -a ${RAW_LOG}
    echo "# CMD: ssh ${BMC_USER}@${BMC_IP} \"ipmcget -d version\"" >> ${RAW_LOG}
    sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d version" | tee -a ${RAW_LOG}
    ...
} 2>/dev/null | tee ${BMC_OUTPUT_FILE} | tee -a ${CUR_LOG}
```

### 分组结构详解

```
{                                    ← 分组开始
  echo 标题 | tee -a RAW_LOG         ← 标题写日志
  echo "# CMD: ..." >> RAW_LOG       ← 命令标记写日志
  sshpass ... "ipmcget ..."           ← SSH 执行命令
    | tee -a RAW_LOG                 ← 原始输出写日志
                                      （对 sensor 命令还有 awk 过滤）
} 2>/dev/null                        ← 分组结束，stderr 丢弃
  | tee ${BMC_OUTPUT_FILE}           ← 过滤后输出写临时文件（用于空值检查）
  | tee -a ${CUR_LOG}                ← 过滤后输出写报告
```

### 6条采集命令

| 序号 | 命令 | 说明 | 过滤方式 |
|------|------|------|----------|
| 1 | `ipmcget -d version` | BMC固件版本 | 无过滤 |
| 2 | `ipmcget -t sensor -d list` | 全量传感器（100+条） | awk 按地址过滤（17个） |
| 3 | `ipmcget -d health` | BMC健康状态 | 无过滤 |
| 4 | `ipmcget -d healthevents` | BMC健康事件 | 无过滤 |
| 5 | `ipmcget -d healthevents` | BMC健康事件 | 无过滤 |
| 6 | `ipmcget -d sel -v list` | SEL故障日志 | head -n 10（报告）+ 完整（日志） |

### 15.3 传感器数据过滤（第448-450行）

```bash
sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -t sensor -d list" \
  | tee -a ${RAW_LOG} \
  | awk -F'|' '{gsub(/ /,"",$1)} $1=="0x1"||$1=="0x2"||$1=="0xe"||...||$1=="0x40"'
```

### awk 语法详解

```bash
awk -F'|' '{gsub(/ /,"",$1)} $1=="0x1"||$1=="0x2"||...||$1=="0x40"'
```

| 部分 | 作用 |
|------|------|
| `-F'|'` | 以 `\|` 作为字段分隔符（ipmcget 输出以 `\|` 分隔列） |
| `gsub(/ /,"",$1)` | 把第1列（地址）中的所有空格删除 |
| `$1=="0x1"\|\|...` | 第1列精确匹配指定地址则输出该行 |

### 为什么需要 gsub？

ipmcget 输出的地址列带空格对齐：`0x1       | Inlet Temp`。如果不 gsub 去空格，`$1` 会是 `"0x1       "`（带尾随空格），与 `"0x1"` 不相等。gsub 后变成 `"0x1"`，可以精确匹配。

### 为什么用 `==` 而不是 `~`？

- `==`：精确匹配（整个字符串相等）
- `~`：正则匹配（包含即匹配）

用 `==` 是为了防止 `0x1` 误匹配 `0x10`、`0x11` 等。

### 选中的17个地址

| 地址 | 名称 | 说明 |
|------|------|------|
| 0x1  | Inlet Temp | 进风口温度（环境温度） |
| 0x2  | Outlet Temp | 出风口温度 |
| 0xe  | CPU1 MEM Temp | CPU1侧内存温度 |
| 0xf  | CPU2 MEM Temp | CPU2侧内存温度 |
| 0x13 | CPU Power | CPU功耗 |
| 0x14 | MEM Power | 内存功耗 |
| 0x33 | FAN1 Speed | 风扇1转速 |
| 0x34 | FAN2 Speed | 风扇2转速 |
| 0x35 | FAN3 Speed | 风扇3转速 |
| 0x36 | FAN4 Speed | 风扇4转速 |
| 0x3a | CPU1 DDR VDDQ | CPU1 DDR电压 |
| 0x3b | CPU1 DDR VDDQ2 | CPU1 DDR电压2 |
| 0x3c | CPU2 DDR VDDQ | CPU2 DDR电压 |
| 0x3d | CPU2 DDR VDDQ2 | CPU2 DDR电压2 |
| 0x3e | CPU1 VDDQ Temp | CPU1 VDDQ温度 |
| 0x3f | CPU2 VDDQ Temp | CPU2 VDDQ温度 |
| 0x40 | CPU1 VRD Temp | CPU1 VRD温度 |

### 修改方法

- 想增加监控地址：在 awk 条件里加 `||$1=="0x新地址"`
- 想查看全部传感器（不过滤）：删除 `| awk ...` 部分
- 想改用名称模糊匹配：把 `$1=="0xe"` 改成 `$2 ~ /MEM Temp/`

### 15.4 SEL日志采集（第460-466行）

```bash
SEL_TMP="${LOG_DIR}/sel_full_${CUR_LOOP}.tmp"
timeout 15 bash -c "yes '' 2>/dev/null | sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} 'ipmcget -d sel -v list'" 2>/dev/null > ${SEL_TMP}
cat ${SEL_TMP} >> ${RAW_LOG}
head -n 10 ${SEL_TMP}
rm -f ${SEL_TMP}
```

### 代码意义

**临时文件方案**，避免 head -10 导致 SIGPIPE 截断原始日志。

| 步骤 | 代码 | 作用 |
|------|------|------|
| 1 | `timeout 15 bash -c "yes '' \| sshpass ..."` | 执行 SEL 查询，完整输出存入临时文件 |
| 2 | `cat ${SEL_TMP} >> ${RAW_LOG}` | 完整 SEL 写入日志 |
| 3 | `head -n 10 ${SEL_TMP}` | 前10条写入报告（通过分组 tee） |
| 4 | `rm -f ${SEL_TMP}` | 清理临时文件 |

### 为什么用 `yes ''` 管道？

iBMC CLI 有分页器（`--More--`），输出超过一页会暂停等待用户按回车。`yes ''` 持续输出空行（相当于按回车），自动翻页直到输出结束。

### 为什么用临时文件而不是直接管道？

如果直接 `sshpass ... | head -n 10`：
- head 读完10行后退出
- SSH 管道收到 SIGPIPE 信号被截断
- RAW_LOG 中的完整输出也会被截断

临时文件方案先把完整输出存文件，再分别处理，避免管道截断问题。

### 为什么用 `timeout 15`？

SEL 日志可能很长（几百条），`yes` 管道在某些 BMC 固件上可能卡住不退出。15秒超时确保不会无限等待。

### 修改方法

- 想看更多 SEL 条数：`head -n 10` 改成 `head -n 50` 或 `head -n 100`
- 想看全部 SEL：删掉 `head -n 10`，直接 `cat ${SEL_TMP}`
- 想改超时时间：`timeout 15` 改成 `timeout 30`

### 15.5 采集结果空值检查（第469-476行）

```bash
BMC_RAW_LINES=$(wc -l < ${BMC_OUTPUT_FILE} 2>/dev/null | tr -d ' ' || echo 0)
if [ ${BMC_RAW_LINES} -lt 3 ]; then
    print_text "【WARN】iBMC 已连接但采集结果为空（${BMC_RAW_LINES}行）"
fi
```

BMC_OUTPUT_FILE 包含全部6条命令的过滤后输出。行数 < 3 说明采集基本失败（可能是 ipmcget 不可用或 SSH 返回空）。

---

## 16. 第7节：轮次判断+重启逻辑（第483-514行）

### 16.1 全部完成（第491-504行）

```bash
if [ ${CUR_LOOP} -ge ${MAX_LOOP} ];then
    print_text "==================== 全部${MAX_LOOP}轮测试执行完成 ===================="
    print_text "所有轮次完整测试报告：${CUR_LOG}"
    print_text "所有轮次完整测试日志：${RAW_LOG}"

    print_step "8. 测试完成，自动关闭开机自启服务"
    systemctl disable mem_test.service &>> ${CUR_LOG}
    rm -f /etc/systemd/system/mem_test.service &>> ${CUR_LOG}
    systemctl daemon-reload &>> ${CUR_LOG}

    rm -f ${LOOP_FLAG} ${TMP_CLEANUP_LIST} 2>/dev/null
    exit 0
fi
```

### 代码意义

**测试完成后的自动清理**：
1. `systemctl disable`：禁用开机自启
2. `rm -f service文件`：删除 service 文件
3. `systemctl daemon-reload`：重载 systemd 配置
4. `rm -f ${LOOP_FLAG}`：删除轮次计数器（下次运行从第1轮开始）
5. `rm -f ${TMP_CLEANUP_LIST}`：清理临时文件
6. `exit 0`：正常退出

`&>> ${CUR_LOG}`：stdout 和 stderr 都追加写入报告（记录清理过程的日志）。

### 16.2 进入下一轮（第505-514行）

```bash
NEXT_LOOP=$((CUR_LOOP + 1))
echo ${NEXT_LOOP} > ${LOOP_FLAG}
print_text "即将重启服务器，开始第${NEXT_LOOP}轮完整测试"
rm -f ${TMP_CLEANUP_LIST} 2>/dev/null
sync
sleep 2
reboot
```

### 代码意义

1. 轮次+1写入标记文件（重启后脚本读取这个值）
2. 清理临时文件
3. `sync`：将文件系统缓冲区写入磁盘（确保标记文件不会因重启丢失）
4. `sleep 2`：给 sync 2秒时间完成
5. `reboot`：重启服务器

### 为什么先 sync 再 reboot？

reboot 会直接断电重启，如果标记文件还在内存缓冲区没写入磁盘，重启后文件内容会丢失或损坏。sync 强制把缓冲区写入磁盘，确保数据持久化。

---

## 17. 双轨日志架构详解

### 17.1 设计理念

| 文件 | 内容 | 目标读者 | 用途 |
|------|------|----------|------|
| 完整测试报告.log | 过滤后的关键信息摘要 | 测试工程师、客户 | 快速查看测试结论 |
| 完整测试日志.log | 未经过滤的完整原始数据 + # CMD: 审计标记 | 开发工程师、问题追溯 | debug、取证、防扯皮 |

### 17.2 数据流总览

#### 报告（CUR_LOG）数据流

```
命令输出 → [grep/awk过滤] → tee → 完整测试报告.log
```

#### 日志（RAW_LOG）数据流

```
命令输出 → tee → 完整测试日志.log（原始全量）
         → [grep/awk过滤] → 完整测试报告.log（摘要）
```

### 17.3 # CMD: 审计标记

每条原始采集命令执行前，在 RAW_LOG 中写入一行 `# CMD: <命令>`，记录这条数据是用什么命令产生的。

**目的**：避免与客户扯皮。当客户质疑数据来源时，直接打开日志文件，每条数据前面都有命令记录，白纸黑字。

### 12处 CMD 标记位置

| 行号 | 命令 | 标记内容 |
|------|------|----------|
| 117 | print_data 函数自动 | `# CMD: $*` |
| 200 | dmidecode -t memory | `# CMD: dmidecode -t memory` |
| 241 | ras-mc-ctl --error-count（压测前） | `# CMD: ras-mc-ctl --error-count` |
| 265 | dmesg（压测前） | `# CMD: dmesg` |
| 298 | stress-ng | `# CMD: stress-ng --vm 1 --vm-bytes 110G ...` |
| 354 | dmesg（压测后） | `# CMD: dmesg` |
| 377 | ras-mc-ctl --error-count（压测后） | `# CMD: ras-mc-ctl --error-count` |
| 387 | diff rasdaemon | `# CMD: diff rasdaemon pre/post errors` |
| 443 | ssh ipmcget -d version | `# CMD: ssh Administrator@10.50.0.201 "ipmcget -d version"` |
| 447 | ssh ipmcget -t sensor | `# CMD: ssh Administrator@10.50.0.201 "ipmcget -t sensor -d list"` |
| 453 | ssh ipmcget -d health | `# CMD: ssh Administrator@10.50.0.201 "ipmcget -d health"` |
| 457 | ssh ipmcget -d healthevents | `# CMD: ssh Administrator@10.50.0.201 "ipmcget -d healthevents"` |
| 461 | ssh ipmcget -d sel | `# CMD: ssh Administrator@10.50.0.201 "ipmcget -d sel -v list"` |

### 17.4 日志文件效果预览

```
（空行）

==================== 第1轮 完整测试开始 时间：2026年 06月 24日 星期三 11:08:49 CST ====================
完整测试报告：/root/test_log/完整测试报告.log
完整测试日志：/root/test_log/完整测试日志.log

==================== 1. 采集OS & BIOS基础信息 ====================
1.1 OpenEuler系统版本：
# CMD: cat /etc/openEuler-release
openEuler release 22.03 (LTS-SP3)
...

==================== 2. 完整内存硬件识别信息（核对槽位、容量）====================
2.1 内存槽位摘要（仅显示已安装条目）：
# CMD: dmidecode -t memory
（dmidecode 完整原始输出，含所有字段所有槽位）

==== BMC 固件版本信息 ====
# CMD: ssh Administrator@10.50.0.201 "ipmcget -d version"
（ipmcget -d version 完整原始输出）

==== 传感器信息（温度/电压/风扇/内存）====
# CMD: ssh Administrator@10.50.0.201 "ipmcget -t sensor -d list"
（ipmcget -t sensor -d list 完整原始输出，100+条全量传感器）
```

---

## 18. iBMC ipmcget 命令参考手册

### 18.1 本脚本使用的 ipmcget 子命令

| 子命令 | 作用 | 输出格式 |
|--------|------|----------|
| `ipmcget -d version` | BMC固件版本信息 | 文本段落 |
| `ipmcget -t sensor -d list` | 全量传感器列表 | 管道符分隔的表格 |
| `ipmcget -d health` | BMC健康状态 | 文本段落 |
| `ipmcget -d healthevents` | BMC健康事件 | 文本段落 |
| `ipmcget -d sel` | SEL故障日志 | 编号列表 |
| `ipmcget -d sel -v list` | SEL详细列表 | 详细编号列表 |
| `ipmcget -d faninfo` | 风扇信息 | 表格 |
| `ipmcget -d fruinfo` | FRU产品信息 | 文本段落 |

### 18.2 传感器输出格式

```
sensor id  | sensor name      | value      | unit         | status | lnr  | lc  | lnc  | unc  | uc  | unr  | phys  | nhys  | lun
0x1        | Inlet Temp       | 34.000     | degrees C    | ok     | na   | na  | na   | 46.0 | 48.0| na   | 2.000 | 2.000 | 0
```

| 列 | 含义 |
|----|------|
| sensor id | 传感器地址（十六进制） |
| sensor name | 传感器名称 |
| value | 当前值 |
| unit | 单位 |
| status | 状态（ok/na/discrete） |
| lnr/lc/lnc | Lower Non-Recoverable / Critical / Non-Critical 阈值 |
| unc/uc/unr | Upper Non-Critical / Critical / Non-Recoverable 阈值 |
| phys/nhys | 物理值 / 滞后值 |
| lun | 逻辑单元号 |

### 18.3 discrete 类型传感器

某些传感器（如 DIMM 状态、CPU 状态）的类型是 `discrete`，值是十六进制状态码：

| 状态码 | 含义 |
|--------|------|
| 0x8000 | 正常 |
| 0x8001 | 状态位1被置起 |
| 0x8040 | 有告警位被置起 |
| 0x8080 | 有严重告警位被置起 |

需要按 IPMI discrete sensor 的位定义解读。

---

## 19. 常见修改指南

### 19.1 修改压测参数

```bash
# 第55行：压测时长
STRESS_DURATION=30    # 改成 300（5分钟）或 600（10分钟）

# 第293行：内存占用比例
STRESS_MEM=$(( MEM_TOTAL * 9 / 10 ))   # 90%，改成 * 95 / 100 = 95%
```

### 19.2 修改测试轮次

```bash
# 第56行
MAX_LOOP=1    # 改成 5（5轮重启循环）
```

### 19.3 修改 BMC 连接信息

```bash
# 第50-52行
BMC_IP="10.50.0.201"        # 改成你的 BMC IP
BMC_USER="Administrator"    # 改成你的账号
BMC_PWD="Admin@9000"        # 改成你的密码
```

### 19.4 增加监控的传感器地址

```bash
# 第450行 awk 条件中追加
||$1=="0x新地址"
```

### 19.5 修改 SEL 显示条数

```bash
# 第465行
head -n 10 ${SEL_TMP}    # 改成 head -n 50
```

### 19.6 修改 dmesg 筛选规则

```bash
# 第261行 DMESG_ERR_PATTERN 中追加
|新关键词
```

### 19.7 增加新的 BMC 采集命令

在 `{ }` 分组内（第441-466行之间）添加：

```bash
echo -e "\n==== 新标题 ====" | tee -a ${RAW_LOG}
echo "# CMD: ssh ${BMC_USER}@${BMC_IP} \"ipmcget -d 新子命令\"" >> ${RAW_LOG}
sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d 新子命令" | tee -a ${RAW_LOG}
```

### 19.8 从第N轮开始测试

```bash
# 手动设置轮次
echo 3 > /root/test_log/current_loop.flag
# 然后运行脚本，会从第3轮开始
```

### 19.9 重置测试

```bash
# 删除轮次计数器，下次从第1轮开始
rm /root/test_log/current_loop.flag
# 删除旧日志
rm /root/test_log/完整测试报告.log /root/test_log/完整测试日志.log
```

---

## 20. 关键设计决策记录

1. **BMC采集方式**：SSH 登录 iBMC + ipmcget（非 ipmitool -I lanplus）。原因：iBMC CLI 是受限 shell，只有 ipmcget/ipmcset，不支持 ipmitool/echo。从 OS 侧用 ipmitool -I lanplus 也可行但需额外开启 IPMI-over-LAN（端口623）。

2. **ECC监控**：仅使用 rasdaemon（ras-mc-ctl --errors / --error-count），不使用 edac-util。原因：edac-util 在新内核上经常无法读取 ECC 信息，rasdaemon 基于 tracepoint 机制更可靠。

3. **内存占用校验**：使用 free -m 第7列（available），不用 used 或 RSS。原因：available 不含 cache/buffer/slab 干扰，used 含 cache 会误判，RSS 因 stress-ng 子进程层级深无法准确统计。

4. **dmesg筛选**：精确匹配 DMESG_ERR_PATTERN，不做裸子串匹配。原因：裸匹配 "CE" 会误中 "device"、"queue" 等无关词。

5. **自检3/3（BMC SSH）**：软警告，不终止测试。原因：核心压测和 dmesg 对比不依赖 BMC，即使 BMC 不可用也应继续执行。

6. **Systemd服务**：Type=oneshot、TimeoutStartSec=0、RemainAfterExit=no、ExecStart=/bin/bash 显式调用。原因：oneshot 适合一次性任务，TimeoutStartSec=0 避免长压测被 systemd 强杀，/bin/bash 避免 203/EXEC 错误。

7. **双轨日志**：报告（过滤摘要）+ 日志（原始全量 + # CMD: 审计标记）。原因：分离设计便于快速查看结论和深度追溯，CMD 标记用于审计取证防扯皮。

8. **SEL采集**：临时文件方案 + yes管道翻页 + timeout超时。原因：避免 head -10 导致 SIGPIPE 截断原始日志，yes 管道自动翻页，timeout 防止卡死。

9. **传感器过滤**：awk 按地址精确匹配（gsub去空格后比较）。原因：避免 0x1 误匹配 0x10，gsub 解决地址列空格对齐问题。

10. **轮次计数器**：current_loop.flag 文件持久化，非数字自动重置，测试完成后自动删除。原因：跨重启持久化轮次，防御性编程防止文件损坏导致崩溃。

11. **stress-ng --vm-populate**：立即物理分配内存。原因：不加此参数内核采用延迟分配，内存占用率远低于预期，压测失效。

12. **rasdaemon --errors vs --records**：使用 --errors。原因：--records 含非错误记录（噪音大），--errors 只输出真正的错误记录。

---

## 21. 故障排查指南

### 21.1 脚本无法启动

| 症状 | 原因 | 解决 |
|------|------|------|
| `bash: \r: command not found` | Windows 换行符 | 脚本会自动修复，或手动 `dos2unix` |
| `permission denied` | 无执行权限 | `chmod +x mem_reboot_auto.sh` |
| `/bin/bash: bad interpreter` | 路径不对 | 确认第一行是 `#!/bin/bash` |

### 21.2 自检失败

| 症状 | 原因 | 解决 |
|------|------|------|
| 缺失工具 | 未安装依赖 | `yum install stress-ng sshpass dmidecode` |
| ping BMC 不通 | 网络不通 | 检查 BMC IP、网线、VLAN |
| BMC SSH 失败 | 账号密码错/SSH未开启 | 检查 iBMC Web 界面 SSH 设置 |

### 21.3 压测失败

| 症状 | 原因 | 解决 |
|------|------|------|
| stress-ng 立即被杀 | 物理内存不足90% | 减小压测比例（如80%） |
| available 剩余>50% | --vm-populate 未生效 | 确认 stress-ng 版本支持此参数 |
| stress-ng 非正常退出 | 系统资源不足 | 检查 dmesg 是否有 OOM |

### 21.4 BMC 采集失败

| 症状 | 原因 | 解决 |
|------|------|------|
| COMMAND NOT SUPPORTED | 在 iBMC CLI 执行了非 ipmcget 命令 | 确认所有 BMC 命令都是 ipmcget 子命令 |
| 采集结果为空 | ipmcget 子命令不可用 | 检查 iBMC 固件版本 |
| SEL 采集超时 | SEL 日志过长或 yes 管道卡住 | 增大 timeout 值 |

### 21.5 日志文件问题

| 症状 | 原因 | 解决 |
|------|------|------|
| 报告为空 | print_text/print_data 未正确写入 | 检查 CUR_LOG 变量路径 |
| 日志缺少 CMD 标记 | 新增命令未加 echo "# CMD:" | 参照现有命令添加标记 |
| 临时文件堆积 | trap 未执行（被 kill -9） | 手动 `rm /root/test_log/*.tmp` |

### 21.6 重启循环问题

| 症状 | 原因 | 解决 |
|------|------|------|
| 重启后从第1轮重新开始 | flag 文件丢失 | 确保脚本执行了 sync 再 reboot |
| 无限重启 | MAX_LOOP 设太大或 flag 文件不更新 | `rm /root/test_log/current_loop.flag` 重置 |
| 测试完成但仍重启 | 轮次判断逻辑错误 | 检查 MAX_LOOP 和 CUR_LOOP 的值 |
| service 未清理 | exit 0 前的清理代码未执行 | 手动 `systemctl disable mem_test.service && rm /etc/systemd/system/mem_test.service` |
