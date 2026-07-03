## 概述

根据指定的测试参数模拟生成 ATE 机台 Excel 数据，再基于该数据自动渲染 Word 测试报告。 Word 报告基于固定模板填空，不从零创建。

---

## 文件路径

- Excel 输出：/mnt/c/Users/Win10/Desktop/DDR4 3200 {N}颗 颗粒测试原始数据.xlsx
    
- Word 模板：/mnt/c/Users/Win10/Desktop/DDR4-3200 内存颗粒高低温四角拉偏暨电气测试报告模板.docx
    
- Word 输出：另存到目标目录，文件名中颗数必须同步为实际 SAMPLE_SIZE 格式：`DDR4-3200 {SAMPLE_SIZE}颗 {报告类型}.docx` 示例：SAMPLE_SIZE=1056 → `DDR4-3200 1056颗 内存颗粒高低温四角拉偏暨电气测试报告.docx` 禁止文件名中出现与实际颗数不符的数字（如 500颗文件名包含300颗数据）
    

---

## PHASE 0：ATE 测试日志仿真

### 0.1 配置参数

|参数|默认值|说明|
|---|---|---|
|SAMPLE_SIZE|100|唯一物理芯片总数，LT 和 HT 各测一次（Detailed_Data 共 200 行）|
|TARGET_YIELD|90.00%|综合去重良率目标，失效芯片数 = SAMPLE_SIZE × (1 - TARGET_YIELD)|
|SITES|4|测试站点数，芯片均匀分配（如 100/4 = 25 颗/站）|
|DUT_NUMBERING|顺序编号|从 1 开始递增（1, 2, 3, ...），上限 512|
|RETEST|false|是否包含 Retest 行（默认仅 Initial）|

### 0.2 失效分布规则（基于 DRAM FT 行业经验比例）

失效芯片总数 = SAMPLE_SIZE × (1 - TARGET_YIELD)，向下取整。

|失效大类|行业比例范围|中间值|对应测试项列|根因说明|
|---|---|---|---|---|
|AC 动态与稳定性 (Move Inversion)|45%~55%|50%|T415-T423 (col 16-24) 选 1-2 项|高频下 SI/PI 压边，SSN，绝对大头|
|存储单元电荷与刷新 (Row Hammer)|25%~35%|30%|T424-T426 (col 25-27) 选 1 项|工艺微缩电容变小，邻行干扰翻转|
|AC 基础时序与逻辑 (Timing)|10%~15%|12.5%|T200-T202 (col 13-15) 选 1 项|DLL 温漂逃逸|
|DC 参数与物理接口 (Contact/Leakage)|5%~10%|7.5%|T100-T106 (col 6-12) 选 1 项|WAT/CP 已拦截大部分，FT 残存极少|

**颗数分配算法**：

1. 取各比例中间值 × 失效芯片总数，四舍五入得到各类初始颗数
    
2. 若初始颗数之和 ≠ 失效芯片总数，差额在最大类(MI)上增减补齐
    
3. 任何类别最小为 0（不允许负数）
    
4. 示例：10 颗失效 → MI=5, RH=3, Timing=1, Contact=1（合计=10）
    

**复合失效规则**：

- 允许同一芯片跨类复合失效（如 MI + Row Hammer），该芯片在两个测试项均标 'F'，但只算 1 颗失效芯片
    
- 复合失效优先在 MI 与 Row Hammer 之间产生（两者均为压力测试，物理机理相关）
    
- 复合失效不超过总失效数的 10%（避免失真）
    

**LT/HT 失效分配**：

- 低温(-40°C)应力更强，分配总失效的 80%~90%
    
- 高温(+85°C)分配 10%~20%
    
- LT 和 HT 的失效芯片必须是不重叠的 DUT（同一物理芯片不能在两个温度都失效，除非显式指定）
    
- 示例：10 颗失效 → LT=8~9 颗, HT=1~2 颗
    

**随机性要求**：

- 失效芯片在 Site 间随机分布（不集中在同一 Site）
    
- 同一大类内的具体测试项随机选取（如 MI 类可能在 T421 或 T423 失效）
    
- 每次执行结果不同（非固定种子），但总量和比例恒定
    

### 0.3 Detailed_Data 结构

**列定义（27列，1-indexed）**：

- A(1): Source = "Initial"
    
- B(2): Site = "Site1"~"Site4"
    
- C(3): TD = 测试日期
    
- D(4): DUT = 芯片编号（1, 2, 3, ... 顺序递增，上限 512）
    
- E(5): SortBin = 1(PASS) 或 4(FAIL)
    
- F-L(6-12): T100~T106（Contact/Leakage/IDD）
    
- M-O(13-15): T200~T202（Timing Training）
    
- P-X(16-24): T415~T423（MOVE INVERSION）
    
- Y-AA(25-27): T424~T426（ROW HAMMER）
    

**标记规范**：

- PASS 芯片：所有测试项 = 'P'（绿色字体）
    
- FAIL 芯片：失效项 = 'F'（红色字体），其余 = 'P'（绿色字体）
    

**列头说明**： Detailed_Data 第2行列头可能被截断为 20 字符（如 'T421_MOVE INVERSI...'）。 这是原文件固有特征，不影响数据逻辑。Bin_Analysis 中的测试项名称应使用完整名称。

**区块结构**：

- 行1：合并单元格 "-40℃ 低温场景"
    
- 行2：Header
    
- 行3~(N+2)：LT 数据（N=SAMPLE_SIZE）
    
- 行(N+3)：空行
    
- 行(N+4)：合并单元格 "+85℃ 高温场景下颗粒"
    
- 行(N+5)：Header（同 LT）
    
- 行(N+6)~(2N+5)：HT 数据（同 N 颗芯片，相同 DUT 编号）
    

### 0.4 Bin_Analysis 结构

**Bin 分布统计**（按唯一物理芯片去重）：

- SortBin 1：通过两温测试的去重芯片数
    
- SortBin 4：任一温度失效的去重芯片数
    
- 总计 = SAMPLE_SIZE
    
- "测试总数"列 = 去重失效芯片总数（不是行数）
    

**各 Bin 测试项目 Fail 统计**：

- 仅列出有 'F' 标记的测试项
    
- Fail 数量 = 该测试项在所有行中出现 'F' 的次数（跨 LT+HT）
    
- 测试总数 = 去重失效芯片总数
    
- Fail 比例 = Fail数量 / 失效芯片总数
    
- Pass 比例 = 1 - Fail比例
    

---

## PHASE 1：变量计算

从 PHASE 0 的模拟数据中计算以下变量：

|变量|计算方式|
|---|---|
|TEST_QTY|SAMPLE_SIZE|
|LT_PASS_QTY / LT_FAIL_QTY|LT 区块 SortBin=1 / SortBin=4 的行数|
|LT_PASS_RATE|LT_PASS_QTY / SAMPLE_SIZE × 100%|
|HT_PASS_QTY / HT_FAIL_QTY|HT 区块同上|
|HT_PASS_RATE|HT_PASS_QTY / SAMPLE_SIZE × 100%|
|TEMP_DROP|abs(LT_PASS_RATE - HT_PASS_RATE)|
|TOTAL_FAIL_CHIPS|LT失效 ∪ HT失效 的去重芯片数|
|TOTAL_PASS_RATE|(SAMPLE_SIZE - TOTAL_FAIL_CHIPS) / SAMPLE_SIZE × 100%|
|FAIL_MOVE_INV_QTY|MI类失效去重芯片数|
|FAIL_MOVE_INV_PCT|FAIL_MOVE_INV_QTY / TOTAL_FAIL_CHIPS × 100%|
|FAIL_CONTACT_QTY|Contact类失效去重芯片数|
|FAIL_CONTACT_PCT|FAIL_CONTACT_QTY / TOTAL_FAIL_CHIPS × 100%|
|FAIL_TIMING_QTY|Timing类失效去重芯片数|
|FAIL_TIMING_PCT|FAIL_TIMING_QTY / TOTAL_FAIL_CHIPS × 100%|
|FAIL_ROW_HAMMER_QTY|RowHammer类失效去重芯片数|
|FAIL_ROW_HAMMER_PCT|FAIL_ROW_HAMMER_QTY / TOTAL_FAIL_CHIPS × 100%|
|MI_LT / MI_HT|MI类在 LT / HT 的失效颗数|
|CONTACT_LT / CONTACT_HT|Contact类在 LT / HT 的失效颗数|
|TIMING_LT / TIMING_HT|Timing类在 LT / HT 的失效颗数|
|RH_LT / RH_HT|RowHammer类在 LT / HT 的失效颗数|

**3.3 汇总表通过率计算（按芯片去重）**： 对每个温度区分别计算各类通过率：

- LT DC通过率 = (LT区无F标记的T100-T106芯片数) / SAMPLE_SIZE × 100%
    
- LT Timing通过率 = (LT区无F标记的T200-T202芯片数) / SAMPLE_SIZE × 100%
    
- LT MI通过率 = (LT区无F标记的T415-T423芯片数) / SAMPLE_SIZE × 100%
    
- LT RH通过率 = (LT区无F标记的T424-T426芯片数) / SAMPLE_SIZE × 100%
    
- LT 全项通过率 = LT_PASS_QTY / SAMPLE_SIZE × 100%
    
- HT 同上，基于 HT 区数据
    
- 综合良率 = TOTAL_PASS_RATE
    

---

## PHASE 2：技术定性

根据 TOTAL_PASS_RATE 自动锁定整篇报告的技术调性与结论话术：

|良率区间|定性|结论话术|
|---|---|---|
|< 80%|共性系统性物理边际不足、系统性边界崩溃|判定不合格，建议退回批次，供应商工艺未达标|
|80%~94.99%|单点边缘性不良/局部偶发性异常|常/高温工艺成熟度极高，整体性能可控，具备量产筛选准入条件，量产时需将特定压力项固化为必测项|
|≥ 95%|极其稳健，表现优异|完全满足宽温工业级大批量产标准，建议直接导入|

---

## PHASE 3：Word 报告渲染

基于桌面模板文件，按以下精确定位表填充/替换数据。 定位方式：段落按文本匹配（搜索关键短语），表格按行列索引。

### 3.0 字体格式规范（强制）

所有通过脚本替换/填充的文本（段落替换、表格单元格填充、5.1节全量重写）统一使用以下字体格式：

- 中文字体：微软雅黑（通过 `w:eastAsia` 设置）
    
- 西文字体：微软雅黑（通过 `w:ascii` / `w:hAnsi` 设置）
    
- 字号：小四（12pt）
    
- 适用范围：仅限脚本修改的部分；模板原有未修改文本保持原格式不变
    

#### 实现要点

**核心函数**（必须定义并使用，不得遗漏）：

from docx.shared import Pt  
from docx.oxml.ns import qn  
​  
def set_run_font(run, font_name='微软雅黑', font_size=Pt(12)):  
    """设置 run 的中西文字体 + 字号，确保 Word 正确渲染。"""  
    run.font.size = font_size  
    run.font.name = font_name          # 设置 w:ascii / w:hAnsi  
    # 设置东亚字体（关键：不设置则中文仍显示为宋体）  
    rPr = run._element.get_or_add_rPr()  
    rFonts = rPr.find(qn('w:rFonts'))  
    if rFonts is None:  
        rFonts = run._element.makeelement(qn('w:rFonts'), {})  
        rPr.insert(0, rFonts)  
    rFonts.set(qn('w:eastAsia'), font_name)

**段落替换**：替换文本后，对段落中所有 run 调用 `set_run_font()`：

def replace_para_text(para, new_text):  
    if not para.runs:  
        para.add_run(new_text)  
        return  
    first_run = para.runs[0]  
    for run in para.runs:  
        run.text = ''  
    first_run.text = new_text  
    for run in para.runs:  
        set_run_font(run)

**表格单元格**：填充文本后，遍历单元格内所有段落和 run：

def set_cell_font(cell):  
    for para in cell.paragraphs:  
        for run in para.runs:  
            set_run_font(run)

**调用时机**：每次对段落或单元格完成文本替换后，立即调用字体设置函数，不要推迟到末尾统一处理。

### 3.1 段落填充映射表

|定位文本（段落中搜索）|原文中的占位符|替换为变量|
|---|---|---|
|"本次测试共抽取有效受试样品总量"|xxx 颗|{TEST_QTY} 颗|
|"本次测试共完成" (3.1正文)|xxx 颗颗粒|{TEST_QTY} 颗颗粒|
|同上|通过率为 xx.xx%|通过率为 {LT_PASS_RATE}|
|同上|xx 颗通过，xx 颗失效 (第一组)|{LT_PASS_QTY} 颗通过，{LT_FAIL_QTY} 颗失效|
|同上|通过率为 xx.xx% (第二组)|通过率为 {HT_PASS_RATE}|
|同上|xx 颗通过，xx颗失效 (第二组)|{HT_PASS_QTY} 颗通过，{HT_FAIL_QTY}颗失效|
|"信号翻转干扰类（MOVE INVERSION）"|xx 颗（低温xx颗，高温xx颗）|{FAIL_MOVE_INV_QTY} 颗（低温{MI_LT}颗，高温{MI_HT}颗）|
|"接触 / 开短路类"|xx 颗（xx颗低温）|{FAIL_CONTACT_QTY} 颗（{CONTACT_LT}颗低温）|
|"时序训练 / 漏电流类"|xx 颗（xx颗低温）|{FAIL_TIMING_QTY} 颗（{TIMING_LT}颗低温）|
|"相邻行干扰（Row Hammer）类"|xx 颗（低温xx颗）|{FAIL_ROW_HAMMER_QTY} 颗（低温{RH_LT}颗）|
|3.2 MI "失效数量：xx 颗"|xx 颗（-40°C低温下xx颗，+85°C高温下xx颗）|{FAIL_MOVE_INV_QTY} 颗（-40°C低温下{MI_LT}颗，+85°C高温下{MI_HT}颗）|
|3.2 Contact "失效数量：xx 颗"|xx 颗|{FAIL_CONTACT_QTY} 颗|
|3.2 Timing "失效数量：xx 颗"|xx 颗|{FAIL_TIMING_QTY} 颗|
|3.2 Row Hammer "失效数量：xx 颗"|xx 颗|{FAIL_ROW_HAMMER_QTY} 颗|
|3.2 各小节"结论：xxx"|xxx|根据 PHASE 2 话术 + 该类失效的根因说明动态生成|
|3.2 各小节"失效条件：xxx"|xxx|从模拟数据中提取实际电压/温度/时序参数|
|3.2 各小节"典型失效：xxx"|xxx|列出实际失效的测试项全称（如 Item 421（MOVE INVERSION_3200U_1.26V））|

### 3.2 零失效类别处理规则（强制）

当某大类失效颗数为 0 时，该小节必须填充以下标准文本，不得保留模板占位符：

典型失效：无  
失效数量：0 颗  
失效条件：无  
结论：全部芯片在{大类名称}全系列用例下表现稳健，无失效。

**四类标准结论文本**：

|大类|0失效结论文本|
|---|---|
|MOVE INVERSION|全部芯片在MOVE INVERSION全系列用例下表现稳健，无失效。|
|接触/开短路|全部芯片在DC Contact/Leakage全系列用例下表现稳健，无接触可靠性问题。|
|时序训练/漏电流|全部芯片在AC Timing全系列用例下表现稳健，时序训练初始化正常。|
|Row Hammer|全部芯片在ROW HAMMER全系列用例下表现稳健，抗行干扰能力充足。|

**注意**：0失效类别不仅填充"无/0颗"，还必须填充"结论"行——模板中的"结论：xxx"占位符必须替换为上述标准结论文本，不得保留xxx。 | "5. 高低温对照组表现" | xxx | 根据 HT 数据动态生成高温表现评述 | | "最终判定：" (3.3末尾) | xxx | 根据 PHASE 2 话术生成判定段落 | | "附件A：《DDR4 3200" | xxx颗 | {TEST_QTY}颗 | | "本报告结果仅对本次所测的" | xxx颗 | {TEST_QTY}颗 |

### 3.2 表格填充映射表（3.2 关键用例失效分析）

**通用规则**：每类失效（MI / Contact / Timing / Row Hammer）各有 4 行需要填充： 典型失效 / 失效数量 / 失效条件 / 结论。当该类失效颗数 > 0 时填入实际数据，= 0 时按 3.2 零失效规则填充。

|定位文本（段落中搜索）|原文占位符|替换为（>0失效）|替换为（=0失效）|
|---|---|---|---|
|3.2 MI "典型失效"|xxx(Item...)|Item xxx（{实际失效项全称}）|无|
|3.2 MI "失效数量"|xx 颗（-40℃低温下xx颗...）|{FAIL_MOVE_INV_QTY} 颗（-40℃低温下{MI_LT}颗，+85℃高温下{MI_HT}颗）|0 颗|
|3.2 MI "失效条件"|xxx(...)|{从数据提取的电压/温度条件}|无|
|3.2 MI "结论"|xxx(...)|{PHASE2话术+根因}|全部芯片在MOVE INVERSION全系列用例下表现稳健，无失效。|
|3.2 Contact "典型失效"|xxx(Item...)|Item xxx（{实际失效项全称}）|无|
|3.2 Contact "失效数量"|xx 颗|{FAIL_CONTACT_QTY} 颗|0 颗|
|3.2 Contact "失效条件"|xxx(...)|{从数据提取的条件}|无|
|3.2 Contact "结论"|xxx(...)|{PHASE2话术+根因}|全部芯片在DC Contact/Leakage全系列用例下表现稳健，无接触可靠性问题。|
|3.2 Timing "典型失效"|xxx(Item...)|Item xxx（{实际失效项全称}）|无|
|3.2 Timing "失效数量"|xx 颗|{FAIL_TIMING_QTY} 颗|0 颗|
|3.2 Timing "失效条件"|xxx(...)|{从数据提取的条件}|无|
|3.2 Timing "结论"|xxx(...)|{PHASE2话术+根因}|全部芯片在AC Timing全系列用例下表现稳健，时序训练初始化正常。|
|3.2 RH "典型失效"|xxx(Item...)|Item xxx（{实际失效项全称}）|无|
|3.2 RH "失效数量"|xx 颗|{FAIL_ROW_HAMMER_QTY} 颗|0 颗|
|3.2 RH "失效条件"|xxx(...)|{从数据提取的条件}|无|
|3.2 RH "结论"|xxx(...)|{PHASE2话术+根因}|全部芯片在ROW HAMMER全系列用例下表现稳健，抗行干扰能力充足。|

**Table 0（报告基本信息表）**：

|单元格|原文占位符|替换为|
|---|---|---|
|R5C2|xxx 颗|{TEST_QTY} 颗|

**Table 1（3.3 用例通过率汇总表）**：

|行|列2(-40℃通过率)|列3(+85℃通过率)|列4(备注)|
|---|---|---|---|
|R1: DC Parametric (100-106)|{LT_DC_RATE}|{HT_DC_RATE}|该大类失效颗数说明|
|R2: AC Timing (200-202)|{LT_TIMING_RATE}|{HT_TIMING_RATE}|同上|
|R3: AC Functional MI (415-423)|{LT_MI_RATE}|{HT_MI_RATE}|同上|
|R4: AC Functional RH (424-426)|{LT_RH_RATE}|{HT_RH_RATE}|同上|
|R5: 全项综合通过率|{LT_PASS_RATE}|{HT_PASS_RATE}|综合整体良率{TOTAL_PASS_RATE}|

### 3.3 五、5.1 测试结论全量重写

5.1 节包含 9 个段落（P098~P106），需全量重写（模板中预填的数值全部替换为实际变量）：

**段落1（基础功能）**： "1、基础功能：+85℃高温下读写、随机访问正常，全项通过率 {HT_PASS_RATE}，符合 DDR4 规范。"

**段落2（低温性能）**： "2、低温性能：-40℃极限低温下整体良率为 {LT_PASS_RATE}（{LT_PASS_QTY} 颗通过，{LT_FAIL_QTY} 颗失效），高低温通过率落差仅为 {TEMP_DROP}。{PHASE2定性话术}。"

**段落3（失效特征总述）**： "3、失效特征：本次测试的失效颗粒{分散/集中}（总计 {TOTAL_FAIL_CHIPS} 颗缺陷芯片），{PHASE2定性}。在总计 {TOTAL_FAIL_CHIPS} 颗失效颗粒中，具体失效分布如下（部分颗粒存在多项复合报错）："

**段落3a（MI分布）**： "信号翻转干扰类（MOVE INVERSION）：{FAIL_MOVE_INV_QTY} 颗（占失效总量 {FAIL_MOVE_INV_PCT}），集中在高压高频边界。"

**段落3b（Contact分布）**： "接触 / 开短路类（DC Contact）：{FAIL_CONTACT_QTY} 颗（占失效总量 {FAIL_CONTACT_PCT}），主要受低温治具物理收缩影响。"

**段落3c（Row Hammer分布）**： "相邻行干扰（Row Hammer）类：{FAIL_ROW_HAMMER_QTY} 颗（占失效总量 {FAIL_ROW_HAMMER_PCT}），表现为紧时序下的微量扰动。"

**段落3d（Timing分布+高温对照）**： "时序训练 / 漏电流类：{FAIL_TIMING_QTY} 颗（占失效总量 {FAIL_TIMING_PCT}）。高温对照组的全项通过率高达 {HT_PASS_RATE}，仅出现 {HT_FAIL_QTY} 颗的微量随机失效，证实了该批次颗粒在常/高温下的极高工艺成熟度。"

**段落4（批次质量）**： "4、批次质量：本批次高温及标称工况下表现优异（通过率 {HT_PASS_RATE}），低温稳定性{基本可控/存在风险}（通过率 {LT_PASS_RATE}）。{PHASE2结论话术}。"

**注意**：段落3中的"分散/集中"和段落4中的"基本可控/存在风险"根据 PHASE 2 良率区间动态选择：

- 良率 ≥ 80%：分散 / 基本可控
    
- 良率 < 80%：集中 / 存在风险
    

---

## PHASE 4：验证检查清单（强制执行）

完成所有修改后，必须运行以下校验：

**Excel 数据校验**： □ LT pass + LT fail = SAMPLE_SIZE □ HT pass + HT fail = SAMPLE_SIZE □ LT 失效芯片 ∪ HT 失效芯片 = TOTAL_FAIL_CHIPS（去重） □ TOTAL_PASS_RATE = (SAMPLE_SIZE - TOTAL_FAIL_CHIPS) / SAMPLE_SIZE □ 各失效大类颗数之和 ≥ TOTAL_FAIL_CHIPS（复合失效允许大于） □ Bin_Analysis 总计 = SAMPLE_SIZE □ Bin_Analysis SortBin1 + SortBin4 = SAMPLE_SIZE □ 所有失效行的 'F' 标记位置与失效分配表一致 □ 所有 PASS 行的 22 个测试项全为 'P'（绿色） □ 所有 FAIL 项为 'F'（红色）

**Word 报告校验**： □ 模板中所有 xxx/xx 占位符已替换，无残留 □ 报告中所有 "xx颗" / "xxx 颗" / "xx.xx%" 等占位符已替换为实际数值，无残留 □ 文件名中的颗数与报告内 SAMPLE_SIZE 一致（如文件名含"500颗"则报告数据必须是500颗） □ 3.3 汇总表 5行×3列数据格全部填充 □ 5.1 节 9 个段落全部重写，无模板预填值残留 □ 所有百分比数值与 PHASE 1 变量表一致 □ 3.2 节各小节失效数量与 3.1 节大类统计一致 □ 5.1 节百分比与 3.1 节大类统计一致（级联一致性） □ 附件清单和免责声明的颗数与 TEST_QTY 一致

**交叉一致性校验**： □ Excel Bin_Analysis 失效项统计 = Word 3.2 节失效数量 □ Excel Bin_Analysis SortBin1/4 = Word 5.1 节综合良率 □ Word 3.3 表各行通过率 + 对应失效颗数 = SAMPLE_SIZE

---

## 文件安全规则

- 修改前必须备份原文件（带时间戳 .bak_YYYYMMDD_HHMMSS）
    
- 在 /tmp 副本上操作，验证通过后再覆盖桌面原文件
    
- 覆盖前用 md5sum 确认文件确实变更
    
- Word 模板文件不修改，另存为新文件输出
    
- 禁止使用 /tmp 旧副本作为数据源覆盖桌面文件（必须以桌面当前文件为源）