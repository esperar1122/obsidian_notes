> STREAM测试主要用于评估‌**DIMM的内存带宽性能**‌，**尤其关注其在持续高负载下的实际数据传输能力**

### 1.下载地址

```shell
git clone https://github.com/jeffhammond/STREAM
或者通过网盘分享的文件：stream-5.9-1.tar.bz2
链接: https://pan.baidu.com/s/1icTt8-0_5HAT7IhaF69gSg?pwd=uj86 提取码: uj86
tar -jxvf stream-5.9-1.tar.bz2
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
cd stream-5.9-1
gcc -O3 -fopenmp -DSTREAM_ARRAY_SIZE=100000000 -DNTIMES=10 stream.c -o stream
```

> 参数详解：
>
> -O3：编译器优化级别，最大化性能‌
>
> -fopenmp：启用多线程支持‌
>
> -DSTREAM_ARRAY_SIZE：数组元素数
>
> -DNTIMES：测试迭代次数
>
> DSTREAM_ARRAY_SIZE计算公式：
>
> 数组大小需 ‌**远大于CPU缓存**‌（最高级缓存(MB)×1024×1024×4.1×CPU核数/8）‌。
> *示例*：16MB缓存+8核CPU -> 16×1024×1024×4.1×8/8≈68786585
>
> 最高缓存可通过 lscpu 或 sudo dmidecode -t cache 查询；

### 4.执行测试

```shell
# 清空系统缓存
echo 3 | sudo tee /proc/sys/vm/drop_caches
# x为你想设置的线程数
export OMP_NUM_THREADS=8   
# 执行测试
sudo ./stream 
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

