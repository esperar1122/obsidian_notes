 说明：本文件包含ARM架构Linux系统中lmbench3.tar工具的完整安装、编译及测试命令
 适配系统：X86架构Linux（32位/64位通用，64位需注意部分参数调整）

一、安装前准备（安装编译依赖）

# 安装核心依赖（CentOS 7/RHEL 7）
sudo yum install -y glibc glibc-devel libgcc make which glibc.x86_64 libstdc++.x86_64

# 安装RPMForge仓库（EL7 x86_64）
sudo yum install -y https://download.fedoraproject.org/pub/epel/7/x86_64/Packages/r/rpmforge-release-0.5.3-1.el7.rf.x86_64.rpm

# 验证仓库是否生效
yum repolist | grep rpmforge

若仓库安装失败，可先安装 epel-release 作为基础：sudo yum install -y epel-release

二、安装命令

# 方式1：直接通过yum安装该RPM包
sudo yum install -y lmbench-3.0-0.a7.1.el7.rf.x86_64

# 方式2：假设RPM包在当前目录，手动安装（需先装完上述依赖）
sudo rpm -ivh lmbench-3.0-0.a7.1.el7.rf.x86_64.rpm
# 若提示依赖缺失，用--force --nodeps强制安装（仅应急，不推荐）
sudo rpm -ivh --force --nodeps lmbench-3.0-0.a7.1.el7.rf.x86_64.rpm

三、执行测试命令

# lmbench的lat_mem_rd延迟测试工具使用步长512来测试，具体测试命令如下：
./lat_mem_rd -P 1 -N 5 10240 512

# 命令解释
-P: 设置并行度为1；
-N: 重复测试次数为5；
10240：内存测试的大小，这个按照实际内存大小自行设置；
512：步长值设置为512，模拟稀疏访问模式，尽可能避免缓存命中；