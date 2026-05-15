> STREAM测试主要用于评估‌**DIMM的内存带宽性能**‌，**尤其关注其在持续高负载下的实际数据传输能力**

### 1.下载地址

```shell
git clone https://github.com/jeffhammond/STREAM.git
或者wget https://github.com/jeffhammond/STREAM/archive/refs/heads/master.zip
unzip master.zip
mv master stream
```

### 2.安装编译依赖

```shell
# Ubuntu/Debian
sudo apt update
sudo apt install gcc gfortran  
 # CentOS/RHEL
sudo yum install gcc gfortran            
```

### 3.编译安装

```shell
cd stream
vim stream.c

#ifndef STREAM_ARRAY_SIZE
#   define STREAM_ARRAY_SIZE	10000000     #修改为200000000
#endif

/*  2) STREAM runs each kernel "NTIMES" times and reports the *best* result
 *         for any iteration after the first, therefore the minimum value
 *         for NTIMES is 2.
 *      There are no rules on maximum allowable values for NTIMES, but
 *         values larger than the default are unlikely to noticeably
 *         increase the reported performance.
 *      NTIMES can also be set on the compile line without changing the source
 *         code using, for example, "-DNTIMES=7".
 */
#ifdef NTIMES
#if NTIMES<=1
#   define NTIMES	10      #修改为30
#endif
#endif
#ifndef NTIMES
#   define NTIMES	10      #修改为30
#endif

#清理编译环境
make clean
#执行编译
make all
```

> 参数详解：
>
> STREAM_ARRAY_SIZE：数组元素数
>
> NTIMES：测试迭代次数
>
> DSTREAM_ARRAY_SIZE计算公式：
>
> 数组大小需 ‌**远大于CPU缓存**‌（最高级缓存(MB)×1024×1024×4.1×CPU核数/8）‌。
>*示例*：16MB缓存+8核CPU -> 16×1024×1024×4.1×8/8≈68786585
> 
>最高缓存可通过 lscpu 或 sudo dmidecode -t cache 查询；

### 4.执行测试

```shell
# 清空系统缓存
echo 3 | sudo tee /proc/sys/vm/drop_caches
 
# 执行测试
sudo ./stream_c.exe 
```

### 5.结果分析

```shell
STREAM测试输出四个关键操作的带宽值（单位MB/s），反映实际内存性能：
Copy：纯内存复制（1次读 + 1次写），带宽最高
Scale：内存复制加标量乘法（1次读 + 1次写 + 1次浮点运算）
Add：内存加法（2次读 + 1次写 + 1次浮点加法），访存压力增大
Triad：混合运算（2次读 + 1次写 + 2次浮点运算），带宽通常最低，暴露时序瓶颈
```

> **判断DIMM是否正常**

```shell
计算理论带宽：
内存条数量*频率*64/8/1024 (单位：GB/S)
(1 x 3200 × 64) / 8 / 1024 = 25.6GB/s

通过比较STREAM实际带宽与理论值，进行诊断：
正常范围：
Copy操作带宽应达理论带宽的60-80%（如理论25.6 GB/s，实际应 ≥15.4-20.5 GB/s）；
Triad操作因计算开销，带宽约为Copy的2/3（例如Copy为20 GB/s时，Triad应 ≥13.3 GB/s）；
若在此范围内，DIMM工作正常；

异常信号（可能故障）：
显著偏低（低于理论值60%）：例如理论25.6 GB/s，但Copy <15.4 GB/s，提示DIMM性能不足；
操作间差异大：如Copy正常但Triad骤降，可能因时序延迟或信号完整性问题；
测试结果不稳定：运行时出现蓝屏（错误代码如0x00000124）或应用程序崩溃，结合带宽异常，需排查硬件故障；
```

