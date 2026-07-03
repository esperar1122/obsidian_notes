#!/bin/bash

# --------------------------开机网络稳定延时--------------------------
# 确保 Systemd 开机拉起服务时，网卡已完全获取 IP 且网络协议栈就绪
sleep 15

# --------------------------自启动服务自动部署--------------------------

SELF_PATH=$(readlink -f "$0")

chmod +x "${SELF_PATH}"

if grep -rl $'\r' "${SELF_PATH}" &>/dev/null; then
    sed -i 's/\r$//' "${SELF_PATH}"
    echo "[部署] 检测到 Windows 换行符，已自动转换为 LF"
fi
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
    echo "[部署] 已自动创建并启用 ${SERVICE_FILE}（ExecStart=${SELF_PATH}）"
fi

if grep -q $'\r' "${SERVICE_FILE}" 2>/dev/null; then
    sed -i 's/\r$//' "${SERVICE_FILE}"
    systemctl daemon-reload
    echo "[部署] 已修复 service 文件中的 Windows 换行符"
fi

restorecon "${SERVICE_FILE}" "${SELF_PATH}" 2>/dev/null

chmod +x "${SELF_PATH}"

# --------------------------全局配置变量区(根据实际情况配置)--------------------------
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

# 初始化/读取当前轮次
if [ ! -f ${LOOP_FLAG} ];then
    echo 1 > ${LOOP_FLAG}
fi
CUR_LOOP=$(cat ${LOOP_FLAG} 2>/dev/null)
# 校验轮次是否为合法正整数，非数字则重置为第1轮（防止标记文件损坏导致脚本崩溃）
if ! [[ "${CUR_LOOP}" =~ ^[0-9]+$ ]] || [ "${CUR_LOOP}" -lt 1 ]; then
    CUR_LOOP=1
    echo 1 > ${LOOP_FLAG}
fi
# 日志文件名：直接"第X轮_时间.log"
CUR_LOG="${LOG_DIR}/完整测试报告.log"
RAW_LOG="${LOG_DIR}/完整测试日志.log"

# ========== 报错快照临时文件 ==========
PRE_ERR="${LOG_DIR}/pre_err_${CUR_LOOP}.tmp"    # 压测前 dmesg 错误快照
POST_ERR="${LOG_DIR}/post_err_${CUR_LOOP}.tmp"  # 压测后 dmesg 错误快照
PRE_SEL="${LOG_DIR}/pre_sel_${CUR_LOOP}.tmp"    # 压测前 SEL 快照
POST_SEL="${LOG_DIR}/post_sel_${CUR_LOOP}.tmp"  # 压测后 SEL 快照
PRE_RAS="${LOG_DIR}/pre_ras_${CUR_LOOP}.tmp"   # 压测前 rasdaemon 记录快照
POST_RAS="${LOG_DIR}/post_ras_${CUR_LOOP}.tmp" # 压测后 rasdaemon 记录快照

# 清理可能存在的上轮残留（防止上轮异常退出遗留同名文件）
rm -f ${LOG_DIR}/pre_err_${CUR_LOOP}.tmp ${LOG_DIR}/post_err_${CUR_LOOP}.tmp \
      ${LOG_DIR}/pre_err_${CUR_LOOP}.tmp.ras ${LOG_DIR}/pre_sel_${CUR_LOOP}.tmp \
      ${LOG_DIR}/post_sel_${CUR_LOOP}.tmp ${LOG_DIR}/bmc_raw_${CUR_LOOP}.tmp \
      ${LOG_DIR}/sel_full_${CUR_LOOP}.tmp \
      ${LOG_DIR}/pre_ras_${CUR_LOOP}.tmp ${LOG_DIR}/post_ras_${CUR_LOOP}.tmp 2>/dev/null

# 退出时自动清理本轮临时文件（正常退出/异常退出均兜底，不会堆积）
TMP_CLEANUP_LIST="${PRE_ERR} ${POST_ERR} ${PRE_ERR}.ras ${PRE_SEL} ${POST_SEL} ${LOG_DIR}/bmc_raw_${CUR_LOOP}.tmp ${LOG_DIR}/sel_full_${CUR_LOOP}.tmp ${PRE_RAS} ${POST_RAS}"
trap 'rm -f ${TMP_CLEANUP_LIST} 2>/dev/null' EXIT

# 输出函数：屏幕+日志双写
print_step(){
    local title="$1"
    echo -e "\n==================== ${title} ===================="
    echo -e "\n==================== ${title} ====================" >> ${CUR_LOG}
    echo -e "\n==================== ${title} ====================" >> ${RAW_LOG}
}

print_text(){
    # 兼容调用处传入 -e 参数：若首个参数为 -e 则启用转义解释
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

print_data(){
    echo "# CMD: $*" >> ${RAW_LOG}
    "$@" | tee -a ${CUR_LOG} ${RAW_LOG}
}

# 多轮日志写入同一文件，轮次之间用空行分隔
echo "" >> ${CUR_LOG} 2>/dev/null
echo "" >> ${RAW_LOG} 2>/dev/null
print_text "==================== 第${CUR_LOOP}轮 完整测试开始 时间：$(date) ===================="
print_text "完整测试报告：${CUR_LOG}"
print_text "完整测试日志：${RAW_LOG}"

###########################################################################
# 0. 开机连通性自检
###########################################################################
print_step "0. 开始连通性自检（共3项）"
CHECK_PASS=1
TOOL_LIST=("stress-ng" "sshpass" "dmidecode" "free")

print_text "【自检1/3】校验依赖工具是否存在"
for tool in ${TOOL_LIST[@]}
do
    if ! command -v $tool &> /dev/null;then
        print_text "【FAIL】缺失工具：$tool"
        CHECK_PASS=0
    else
        print_text "【OK】工具正常：$tool"
    fi
done

print_text -e "\n【自检2/3】Ping BMC地址 ${BMC_IP}"
if ping -c3 ${BMC_IP} &>/dev/null;then
    print_text "【OK】BMC网络连通正常"
else
    print_text "【FAIL】无法ping通BMC ${BMC_IP}，网络异常"
    CHECK_PASS=0
fi

print_text -e "\n【自检3/3】SSH登录BMC验证账号密码"
BMC_SSH_OK=0

SSH_ERR=$(sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d version" 2>&1)
SSH_RET=$?
if [ ${SSH_RET} -eq 0 ]; then
    print_text "【OK】BMC SSH登录校验通过"
    BMC_SSH_OK=1
else
    print_text "【WARN】BMC SSH登录失败（退出码${SSH_RET}），远程采集将跳过，但不终止测试"
    print_text "  错误信息：${SSH_ERR}"
    print_text "  常见原因：账号密码错误 / SSH服务端口非22 / BMC禁用SSH / 防火墙拦截"
    print_text "  压测+报错对比不依赖BMC SSH，将正常执行"
    # 不再设 CHECK_PASS=0，不终止测试
fi

if [ ${CHECK_PASS} -ne 1 ];then
    print_text -e "\n########## 自检存在异常（工具缺失或网络不通），终止本轮测试 ##########"
    print_text "完整日志路径：${CUR_LOG}"
    exit 1
fi
if [ ${BMC_SSH_OK} -eq 1 ]; then
    print_text "全部连通校验通过，进入正式信息采集流程"
else
    print_text "基础校验通过（工具OK、网络通），BMC SSH不可用，继续执行核心压测流程"
fi

###########################################################################
# 1. 采集OS & BIOS基础信息
###########################################################################
print_step "1. 采集OS & BIOS基础信息"
print_text "1.1 OpenEuler系统版本："
print_data cat /etc/openEuler-release

print_text "1.2 系统内核 uname -a："
print_data uname -a

print_text "1.3 BIOS固件版本号："
print_data dmidecode -s bios-version

###########################################################################
# 2. 完整内存硬件识别信息
###########################################################################
print_step "2. 完整内存硬件识别信息（核对槽位、容量）"
# dmidecode -t memory 原始输出过长，增加关键字段筛选摘要
print_text "2.1 内存槽位摘要（仅显示已安装条目）："
echo "# CMD: dmidecode -t memory" >> ${RAW_LOG}
dmidecode -t memory | tee -a ${RAW_LOG} | grep -E "Size:|Type:|Speed:|Locator:|Manufacturer:|Part Number:" | grep -v "No Module\|Unknown" | tee -a ${CUR_LOG}

print_text "2.2 完整 dmidecode 原始输出："
print_data dmidecode -t memory

###########################################################################
# 3. 当前系统内存占用 free -g
###########################################################################
print_step "3. 当前系统内存占用 free -g"
print_data free -g

###########################################################################
# 4. ECC内存纠错 & BMC内存传感器
###########################################################################
print_step "4. ECC内存纠错信息 & BMC内存传感器"

# ECC 工具检测：rasdaemon（openEuler 官方支持）
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
        print_text "【WARN】ras-mc-ctl 已安装但 rasdaemon 服务启动失败，ECC 计数将不可用"
    fi
else
    print_text "【WARN】未安装 rasdaemon，ECC 纠错计数将跳过"
    print_text "  安装：yum install rasdaemon && systemctl enable --now rasdaemon"
fi

print_text "4.1 内存传感器SDR信息：" 
print_data ipmitool sdr type Memory

# 压测前 ECC 纠错计数快照（rasdaemon）
print_text "4.2 压测前 ECC纠错计数快照："
if [ "${ECC_TOOL}" = "rasdaemon" ]; then
    echo "# CMD: ras-mc-ctl --error-count" >> ${RAW_LOG}
    ras-mc-ctl --error-count 2>/dev/null | tee -a ${CUR_LOG} ${RAW_LOG}
    ras-mc-ctl --error-count 2>/dev/null > "${PRE_ERR}.ras"
    # 用 --errors 替代 --records，只输出真正的错误记录，不含冗余行/表头/分隔线
    # 避免因非错误行的计数导致的误报
    # --errors 无错误时仍输出分类标题行和 "No xxx errors" 占位行，需过滤掉
    ras-mc-ctl --errors 2>/dev/null | grep -viE "^$|no .*error|:$" > ${PRE_RAS}
    PRE_RAS_COUNT=$(wc -l < ${PRE_RAS} | tr -d ' ')
    print_text "压测前 rasdaemon 错误记录条数：${PRE_RAS_COUNT}"
else
    print_text "（无 ECC 监控工具，跳过快照）"
    echo "no ecc tool" > "${PRE_ERR}.ras"
    > ${PRE_RAS}
fi

# ========== dmesg 内存/硬件错误精确筛选规则 ==========
# 核心原则：
#   1) CE/UE 只在 EDAC 报告格式 "EDAC MC*: N CE/UE" 中匹配，不做裸子串匹配
#   2) memory/ECC/mce 必须搭配 error/fail/fault/corrupt 等错误上下文
# 如需扩展，在 DMESG_ERR_PATTERN 中追加 |关键词 即可
DMESG_ERR_PATTERN='hardware error|corrected error|uncorrected error|ECC.*(error|fail)|EDAC.*: [0-9]+ (CE|UE)|mce.*(error|exception|overflow)|memory.*(error|fail|fault|corrupt|poison|degrad)|page allocation failure|out of memory|oom-kill|bad ram|DIMM.*(error|fail|fault)|ras:.*(error|event)'

# 压测前 dmesg 内存/ECC错误快照
print_text "4.3 压测前 dmesg 内存错误快照（已过滤启动噪音）："
echo "# CMD: dmesg" >> ${RAW_LOG}
dmesg | tee -a ${RAW_LOG} | grep -Ei "${DMESG_ERR_PATTERN}" > ${PRE_ERR} 2>/dev/null
PRE_ERR_COUNT=$(wc -l < ${PRE_ERR})
print_text "压测前 dmesg 内存/硬件错误行数：${PRE_ERR_COUNT}"
if [ ${PRE_ERR_COUNT} -eq 0 ]; then
    print_text "【OK】压测前 dmesg 无内存/硬件相关报错"
else
    print_text "【WARN】压测前 dmesg 已存在 ${PRE_ERR_COUNT} 条可疑错误（详见下方明细）："
    cat ${PRE_ERR} | tee -a ${CUR_LOG} ${RAW_LOG}
fi

# 压测前 BMC SEL 快照（SSH不可用则跳过，PRE_SEL置空文件保证后续diff不报错）
print_text "4.4 压测前 BMC SEL 故障日志快照："
if [ ${BMC_SSH_OK} -eq 1 ]; then
    sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d sel" > ${PRE_SEL} 2>/dev/null
    PRE_SEL_COUNT=$(wc -l < ${PRE_SEL} 2>/dev/null | tr -d ' ' || echo 0)
    print_text "压测前 SEL 日志条数：${PRE_SEL_COUNT}"
else
    print_text "（BMC SSH不可用，跳过 SEL 快照）"
    > ${PRE_SEL}
fi

###########################################################################
# 5. 内存压力测试（每轮执行）
###########################################################################
print_step "5. 执行${STRESS_DURATION}秒内存压力测试 stress-ng"
MEM_TOTAL=$(free -g | awk '/Mem:/{print $2}')
# 严格限制：必须占用整机 90% 的物理内存
STRESS_MEM=$(( MEM_TOTAL * 9 / 10 ))
print_text "整机总内存${MEM_TOTAL}G，压测分配内存${STRESS_MEM}G"

print_text "后台启动压测..."
# 增加 --vm-populate 参数让内存立刻物理分配，确保真实达到 90% 水平
echo "# CMD: stress-ng --vm 1 --vm-bytes ${STRESS_MEM}G --vm-keep --vm-populate --timeout ${STRESS_DURATION}" >> ${RAW_LOG}
stress-ng --vm 1 --vm-bytes ${STRESS_MEM}G --vm-keep --vm-populate --timeout ${STRESS_DURATION} &
STRESS_PID=$!

# 快速校验：等待 3 秒，确认压测进程没有因为系统过载机制而被立即杀死
sleep 3
if ! ps -p ${STRESS_PID} > /dev/null; then
    print_text "【ERROR】stress-ng 进程启动失败或已被系统立即终止！物理内存可能无法承受 90% 压力分配。"
    exit 1
fi

# 在压测填充内存之前记录可用内存基线（available 列）
# 放到 wait 之前，确保 pre 值采集及时，不被 sleep 延后影响差值
MEM_AVAIL_PRE=$(free -m | awk '/Mem:/{print $7}')
print_text "压测前可用内存基线：${MEM_AVAIL_PRE}MB（总内存 ${MEM_TOTAL}GB），等待${STRESS_CHECK_WAIT}秒后校验内存占用..."

print_text "压测后台运行正常，等待${STRESS_CHECK_WAIT}秒后校验实际内存占用..."
sleep $((STRESS_CHECK_WAIT - 3))

# 校验压测是否生效：直接用 available 剩余量判断
# 压测打满 111GB 后，available 应该只剩 total 的 10% 左右
# 如果 available 剩余还超过 total 的 50%，说明压测没生效（未达到预期占用）
MEM_TOTAL_MB=$((MEM_TOTAL * 1024))
MEM_AVAIL_POST=$(free -m | awk '/Mem:/{print $7}')
MEM_DROP=$((MEM_AVAIL_PRE - MEM_AVAIL_POST))
MEM_DROP_GB=$(awk -v mb="${MEM_DROP}" 'BEGIN{printf "%.1f", mb/1024}')
print_text "压测${STRESS_CHECK_WAIT}s后可用内存：${MEM_AVAIL_POST}MB，下降：${MEM_DROP_GB}GB（预期至少 $((${STRESS_MEM} / 2))GB 被占用）"

# 校验：压测后 available 剩余超过 total 一半，说明 stress-ng 没真正吃掉足够内存
MEM_AVAIL_RATIO=$((MEM_AVAIL_POST * 100 / MEM_TOTAL_MB))
if [ ${MEM_AVAIL_RATIO} -gt 50 ]; then
    print_text "【ERROR】stress-ng 实际占用内存不足目标值一半（可用内存剩余 ${MEM_AVAIL_RATIO}%，预期只有 10%），压力测试失效！测试强行终止。"
    kill -9 ${STRESS_PID} 2>/dev/null
    exit 1
else
    print_text "【OK】内存压力已成功打满 90%"
fi

# 阻塞等待压测完全结束
wait ${STRESS_PID}
STRESS_EXIT=$?
print_text "${STRESS_DURATION}秒内存压力测试全部执行完成，stress-ng 退出码：${STRESS_EXIT}"

# 压测后 stress-ng 退出码判断
if [ ${STRESS_EXIT} -ne 0 ]; then
    print_text "【WARN】stress-ng 非正常退出（退出码${STRESS_EXIT}），可能存在压力异常"
else
    print_text "【OK】stress-ng 正常退出"
fi

###########################################################################
# 5.1 压测后报错采集 + 前后对比
###########################################################################
print_step "5.1 压测后内存/ECC报错采集与前后对比"

# 压测后 dmesg 错误快照（使用与压测前相同的精确筛选规则）
echo "# CMD: dmesg" >> ${RAW_LOG}
dmesg | tee -a ${RAW_LOG} | grep -Ei "${DMESG_ERR_PATTERN}" > ${POST_ERR} 2>/dev/null
POST_ERR_COUNT=$(wc -l < ${POST_ERR})
print_text "压测后 dmesg 内存/硬件错误行数：${POST_ERR_COUNT}"

print_text "--- 压测后 dmesg 错误明细 ---"
cat ${POST_ERR} | tee -a ${CUR_LOG} ${RAW_LOG}

# 压测前后 dmesg 差异对比
print_text "--- 压测前后 dmesg 错误差异对比（新增报错） ---"
NEW_ERR=$(diff ${PRE_ERR} ${POST_ERR} | grep "^>" | sed 's/^> //')
NEW_ERR_COUNT=$(echo "${NEW_ERR}" | grep -c . 2>/dev/null || echo 0)

if [ -z "${NEW_ERR}" ] || [ ${NEW_ERR_COUNT} -eq 0 ]; then
    print_text "【OK】压测后无新增 dmesg 内存报错"
else
    print_text "【FAIL】压测后新增 ${NEW_ERR_COUNT} 条 dmesg 内存报错："
    echo "${NEW_ERR}" | tee -a ${CUR_LOG} ${RAW_LOG}
fi

# 压测后 ECC 计数对比（rasdaemon）
print_text "--- 压测前后 ECC 纠错计数对比 ---"
if [ "${ECC_TOOL}" = "rasdaemon" ]; then
    echo "# CMD: ras-mc-ctl --error-count" >> ${RAW_LOG}
    ras-mc-ctl --error-count 2>/dev/null | tee -a ${CUR_LOG} ${RAW_LOG}
    ras-mc-ctl --errors 2>/dev/null | grep -viE "^$|no .*error|:$" > ${POST_RAS}
    POST_RAS_COUNT=$(wc -l < ${POST_RAS} | tr -d ' ')
    print_text "压测后 rasdaemon 错误记录条数：${POST_RAS_COUNT}"
    # records 行数对比
    RAS_DIFF=$((POST_RAS_COUNT - PRE_RAS_COUNT))
    if [ ${RAS_DIFF} -gt 0 ]; then
        print_text "【FAIL】rasdaemon 新增 ${RAS_DIFF} 条硬件错误记录："
        # 提取新增记录（diff > 开头的行）
        echo "# CMD: diff rasdaemon pre/post errors" >> ${RAW_LOG}
        diff ${PRE_RAS} ${POST_RAS} 2>/dev/null | tee -a ${RAW_LOG} | grep "^>" | sed 's/^> //' | tee -a ${CUR_LOG}
    else
        print_text "【OK】rasdaemon 无新增硬件错误记录（${PRE_RAS_COUNT} → ${POST_RAS_COUNT}）"
    fi
    # error-count 数字对比
    # rasdaemon --error-count 输出格式不同版本有差异：有的用 "CE count:" 缩写，有的用 "Corrected Error Count:" 全写
    # 两个关键字都搜，确保缩写和全写都能匹配到
    PRE_CE=$(grep -iE "correct|\bCE\b" "${PRE_ERR}.ras" 2>/dev/null | grep -oE '[0-9]+' | awk '{s+=$1}END{print s+0}')
    POST_CE=$(ras-mc-ctl --error-count 2>/dev/null | grep -iE "correct|\bCE\b" | grep -oE '[0-9]+' | awk '{s+=$1}END{print s+0}')
    PRE_CE=${PRE_CE:-0}; POST_CE=${POST_CE:-0}
    if [ ${POST_CE} -gt ${PRE_CE} ]; then
        print_text "【FAIL】ECC CE 计数增加：${PRE_CE} → ${POST_CE}（新增 $((POST_CE - PRE_CE))）"
    else
        print_text "【OK】ECC CE 计数无变化：${PRE_CE} → ${POST_CE}"
    fi
else
    print_text "（无 ECC 监控工具，跳过 ECC 计数对比）"
fi

# 压测后 BMC SEL 对比
print_text "--- 压测前后 BMC SEL 日志对比 ---"
if [ ${BMC_SSH_OK} -eq 1 ]; then
    sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d sel" > ${POST_SEL} 2>/dev/null
    POST_SEL_COUNT=$(wc -l < ${POST_SEL} 2>/dev/null | tr -d ' ' || echo 0)
    print_text "压测后 SEL 日志条数：${POST_SEL_COUNT}"

    NEW_SEL=$(diff ${PRE_SEL} ${POST_SEL} 2>/dev/null | grep "^>" | sed 's/^> //')
    if [ -z "${NEW_SEL}" ]; then
        print_text "【OK】压测后 BMC SEL 无新增故障日志"
    else
        NEW_SEL_COUNT=$(echo "${NEW_SEL}" | grep -c . 2>/dev/null || echo 0)
        print_text "【FAIL】压测后 BMC SEL 新增 ${NEW_SEL_COUNT} 条故障日志："
        echo "${NEW_SEL}" | tee -a ${CUR_LOG} ${RAW_LOG}
    fi
else
    print_text "（BMC SSH不可用，跳过 SEL 前后对比）"
    > ${POST_SEL}
fi

# 清理临时快照文件
rm -f ${PRE_ERR} ${POST_ERR} ${PRE_ERR}.ras ${PRE_SEL} ${POST_SEL} ${PRE_RAS} ${POST_RAS} 2>/dev/null

###########################################################################
# 6. 远程iBMC硬件信息采集（优化：增加连接判断）
###########################################################################
print_step "6. 远程iBMC硬件信息采集 BMC_IP:${BMC_IP}"

# 先判断 SSH 能否正常连接 BMC，连接失败则明确报错并跳过
print_text "6.0 检测 iBMC SSH 连接状态..."
if [ ${BMC_SSH_OK} -eq 1 ]; then
    print_text "【OK】iBMC SSH 连接正常（自检阶段已验证），开始采集硬件信息"
    BMC_OUTPUT_FILE="${LOG_DIR}/bmc_raw_${CUR_LOOP}.tmp"
    # iBMC CLI 无 echo 命令，标题在 OS 侧输出，数据通过 SSH 逐条采集
    {
    echo "==== BMC 固件版本信息 ====" | tee -a ${RAW_LOG}
    echo "# CMD: ssh ${BMC_USER}@${BMC_IP} \"ipmcget -d version\"" >> ${RAW_LOG}
    sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d version" | tee -a ${RAW_LOG}

    echo -e "\n==== 传感器信息（温度/电压/风扇/内存）====" | tee -a ${RAW_LOG}
    echo "# CMD: ssh ${BMC_USER}@${BMC_IP} \"ipmcget -t sensor -d list\"" >> ${RAW_LOG}
    sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -t sensor -d list" \
      | tee -a ${RAW_LOG} \
      | awk -F'|' '{gsub(/ /,"",$1)} $1=="0x1"||$1=="0x2"||$1=="0xe"||$1=="0xf"||$1=="0x13"||$1=="0x14"||$1=="0x33"||$1=="0x34"||$1=="0x35"||$1=="0x36"||$1=="0x3a"||$1=="0x3b"||$1=="0x3c"||$1=="0x3d"||$1=="0x3e"||$1=="0x3f"||$1=="0x40"'

    echo -e "\n==== BMC 健康状态 ====" | tee -a ${RAW_LOG}
    echo "# CMD: ssh ${BMC_USER}@${BMC_IP} \"ipmcget -d health\"" >> ${RAW_LOG}
    sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d health" | tee -a ${RAW_LOG}

    echo -e "\n==== BMC 健康事件 ====" | tee -a ${RAW_LOG}
    echo "# CMD: ssh ${BMC_USER}@${BMC_IP} \"ipmcget -d healthevents\"" >> ${RAW_LOG}
    sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} "ipmcget -d healthevents" | tee -a ${RAW_LOG}

    echo -e "\n==== BMC SEL 故障日志（仅前10条）====" | tee -a ${RAW_LOG}
    echo "# CMD: ssh ${BMC_USER}@${BMC_IP} \"ipmcget -d sel -v list\"" >> ${RAW_LOG}
    SEL_TMP="${LOG_DIR}/sel_full_${CUR_LOOP}.tmp"
    timeout 15 bash -c "yes '' 2>/dev/null | sshpass -p ${BMC_PWD} ssh ${SSH_OPTS} ${BMC_USER}@${BMC_IP} 'ipmcget -d sel -v list'" 2>/dev/null > ${SEL_TMP}
    cat ${SEL_TMP} >> ${RAW_LOG}
    head -n 10 ${SEL_TMP}
    rm -f ${SEL_TMP}
    } 2>/dev/null | tee ${BMC_OUTPUT_FILE} | tee -a ${CUR_LOG}

    # 判断采集结果是否为空
    BMC_RAW_LINES=$(wc -l < ${BMC_OUTPUT_FILE} 2>/dev/null | tr -d ' ' || echo 0)
    if [ ${BMC_RAW_LINES} -lt 3 ]; then
        print_text "【WARN】iBMC 已连接但采集结果为空（${BMC_RAW_LINES}行），请检查 ipmcget 命令是否可用"
    else
        print_text "【OK】iBMC 信息采集完成，共 ${BMC_RAW_LINES} 行"
    fi
    rm -f ${BMC_OUTPUT_FILE} 2>/dev/null
else
    print_text "【FAIL】iBMC SSH 连接失败！无法采集远程硬件信息。"
    print_text "可能原因：网络不通 / 账号密码错误 / BMC 服务异常 / 防火墙拦截"
    print_text "跳过本节远程采集，继续后续流程..."
fi

###########################################################################
# 7. 轮次判断+重启逻辑
###########################################################################
print_step "7. 第${CUR_LOOP}轮全部采集流程执行完毕"
print_text "完整测试报告：${CUR_LOG}"
print_text "完整测试日志：${RAW_LOG}"

# 判断是否跑完5轮
if [ ${CUR_LOOP} -ge ${MAX_LOOP} ];then
    print_text "==================== 全部${MAX_LOOP}轮测试执行完成 ===================="
    print_text "所有轮次完整测试报告：${CUR_LOG}"
    print_text "所有轮次完整测试日志：${RAW_LOG}"
    # --- 测试完成后自动关闭并清理自启服务 ---
    print_step "8. 测试完成，自动关闭开机自启服务"
    print_text "正在停止并禁用 mem_test.service ..."
    systemctl disable mem_test.service &>> ${CUR_LOG}
    rm -f /etc/systemd/system/mem_test.service &>> ${CUR_LOG}
    systemctl daemon-reload &>> ${CUR_LOG}
    print_text "【OK】mem_test.service 已禁用并清理完毕，下次重启不再自动运行。"

    rm -f ${LOOP_FLAG} ${TMP_CLEANUP_LIST} 2>/dev/null
    exit 0
else
    # 轮次+1，写入标记文件，重启进入下一轮
    NEXT_LOOP=$((CUR_LOOP + 1))
    echo ${NEXT_LOOP} > ${LOOP_FLAG}
    print_text "即将重启服务器，开始第${NEXT_LOOP}轮完整测试"
    rm -f ${TMP_CLEANUP_LIST} 2>/dev/null
    sync
    sleep 2
    reboot
fi
