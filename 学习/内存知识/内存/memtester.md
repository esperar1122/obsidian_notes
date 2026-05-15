> memtester 是一款专注于 ‌**DIMM 内存访问可靠性和稳定性**‌测试的工具，核心目标是检测内存硬件是否存在潜在的物理缺陷或信号完整性问题，确保其在持续读写压力下稳定运行;它**不关注速度指标**‌，专注硬件层错误检测‌；通过模拟多种极端内存访问模式，对 DIMM 进行压力测试；

### 1.下载地址

```shell
wget http://pyropus.ca/software/memtester/old-versions/memtester-4.3.0.tar.gz
wget https://download.csdn.net/detail/moqi_7/9784210 -O memtester-4.3.0.tar.gz
```

### 2.安装memtester工具

> 1.包管理器安装

```shell
# Ubuntu/Debian
sudo apt update
sudo apt install memtester
# CentOS/RHEL
sudo makecache
sudo yum install memtester
```

> 2.手动编译安装

```shell
wget https://pyropus.ca./software/memtester/old-versions/memtester-4.3.0.tar.gz
tar -xzvf memtester-4.3.0.tar.gz
cd memtester-4.3.0
make && sudo make install
```

### 3.执行测试

> 基础命令格式：

```shell
sudo memtester  <mem>[B|K|M|G] [loops]
                                                <内存大小>   <循环次数>            
```

> 实例：

```shell
# 测试6GB内存，连续运行5次
sudo memtester 6G 5
sudo memtester 80% 72  # 测试80%内存，持续72小时
```

> 关键参数说明：

```shell
内存大小：
建议测试≥80% 物理内存，需预留部分内存供系统使用（如总内存 8GB 则测试不超过 7GB）
支持单位：B（字节）、K（KB）、M（MB）、G（GB）
循环次数：
建议至少 3-5 次以覆盖潜在间歇性错误
长期测试可设为更高（如 24 小时连续测试），默认无限循环 
测试结果：
正常输出：所有测试项标记为 ok（如 Random Value: ok）。
错误提示：出现 FAILURE 表明内存存在缺陷（如 Stuck Address: FAILURE）
```

> 测试项解读

```shell
测试类型                  检测目标
随机值写入校验	         物理坏块（卡死位）
异或(XOR)运算	       相邻单元信号串扰
算术运算（加减乘除）	   内存与CPU协同计算错误
地址线边界扰动	         地址译码电路故障
逻辑运算（AND/OR）	  时序延迟导致的逻辑异常
```

