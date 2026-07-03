## 测试指令集
当前所有测试工具均放在home/hzxc/tools文件夹中
### 1、Lmbench
测试流程：
cd lmbench-3.0-a9   `进入Lm..文件夹`
make results             `执行测试（会先进入测试）`
./lat_mem_rd -P 1 -N 5 10240 512（使用步长512进行测试）

**测试的报告生成在** ··/lmbench-3.0-a9/results/ x86_64-linux-gnu 目录中

### 2、LTP
sudo /opt/ltp/runltp -p -l ~/ltp_result.log -d /tmp -o ~/ltp_output.log -t 30m
（可以1-59m，也可以1、2、3…h，如需测试如4.5小时需要用270m即用分钟来定义时间，小时h只能适用于整数，如2个小时可以用2h）
这条命令的作用是：**以 root 权限运行 LTP 测试套件，持续 30 分钟**。在测试期间，它会生成人类可读的日志，并将详细的测试结果和运行输出分别保存到 ~/ltp_result.log 和 ~/ltp_output.log 两个文件中.

![[Pasted image 20260528181159.png]]


### 3、Stream （待考究）

流程：
cd Stream
./stream > stream_log.txt    `测试结果保存为日志文件`

### 4、Stressapptest(待考究)

流程：
cd Stressapptest
stressapptest -s 360 -M 2048 -m 4 -W -l sat_log.txt

**参数详细解释**
  **-s 360**：测试时长 360 秒（6分钟），保证测试充分且不会耗时过长
  **-M 2048**：占用 2048MB 内存进行压力测试，适配虚拟机内存配置，避免卡死
  **-m 4**：开启4个测试线程，匹配4核CPU，压测效果均匀
  **-W**：开启严格写校验模式，每一次读写都做数据比对，精准检测内存错误
 **-l sat_log.txt**：将全部测试过程与最终结果保存到日志文件

## 基础指令集
### 1. 📁 文件与目录操作（每日必用）

| 指令      | 核心用途   | 高频示例                                               |
| ------- | ------ | -------------------------------------------------- |
| `ls`    | 列出文件   | `ls -lhrt` (按时间排序+人类可读大小)                          |
| `cd`    | 切换目录   | `cd -` (返回上一个目录), `cd ~` (回主目录)                    |
| `pwd`   | 显示当前路径 | `pwd`                                              |
| `cp`    | 复制     | `cp -r src/ dst/` (递归复制目录)                         |
| `mv`    | 移动/重命名 | `mv old.txt new.txt`                               |
| `rm`    | 删除     | `rm -rf dir/` (⚠️慎用，建议先`ls`确认)                     |
| `mkdir` | 创建目录   | `mkdir -p /a/b/c` (递归创建多级目录)                       |
| `touch` | 创建空文件  | `touch file.txt`                                   |
| `find`  | 查找文件   | `find /var/log -name "*.log" -mtime -1` (1天内修改的日志) |
| `ln`    | 创建链接   | `ln -s /real/path /link/path` (软链接)                |

### 2. 📄 文件内容查看与编辑


```
# 实时追踪日志（排障第一命令）
tail -f /var/log/syslog
tail -n 100 app.log          # 查看最后100行

# 分页查看大文件
less largefile.log           # q退出, /搜索, n下一个匹配

# 快速查看头部/尾部
head -20 config.yaml
tail -20 config.yaml

# 文本搜索
grep -i "error" app.log      # 忽略大小写
grep -rn "TODO" ./src        # 递归搜索+显示行号
grep -v "DEBUG" app.log      # 反向匹配（排除）

# 编辑文件
vim file.txt                 # i进入编辑, Esc退出编辑, :wq保存退出
nano file.txt                # 新手友好编辑器
```

### 3. 💻 系统状态速查

```
# 资源概览
top                          # 实时进程/CPU/内存 (P按CPU排序, M按内存排序)
free -h                      # 内存使用量
df -h                        # 磁盘空间
uptime                       # 运行时长 + 负载均值

# 系统与内核
uname -a                     # 内核版本
cat /etc/os-release          # 发行版信息
hostnamectl                  # 主机名+系统版本
dmesg | tail                 # 最近内核消息（硬件/OOM排查）

# 用户与会话
whoami                       # 当前用户
id                           # UID/GID/组信息
w                            # 在线用户+负载
history                      # 命令历史 (!编号 可快速重执行)
```

### 4. 🌐 网络基础诊断

```
# 连通性
ping -c 4 host               # ICMP测试
curl -I http://host          # HTTP响应头/状态码
wget -q --spider URL         # 静默检查URL可达性

# 端口与连接
ss -tulnp                    # 监听端口+对应进程 ⭐(替代netstat)
ss -s                        # 连接统计摘要
telnet host port             # TCP端口连通性测试

# DNS与路由
dig +short domain            # DNS解析
ip addr                      # 网卡IP (替代ifconfig)
ip route                     # 路由表
mtr host                     # 路由追踪+丢包分析 ⭐
```

### 5. ⚙️ 服务与权限管理

```
# Systemd 服务管理
systemctl status nginx       # 查看状态
systemctl restart nginx      # 重启
systemctl enable nginx       # 开机自启
journalctl -u nginx -n 50    # 查看服务最近50条日志

# 权限与归属
chmod 755 script.sh          # rwxr-xr-x
chmod 644 config.conf        # rw-r--r--
chown user:group file        # 修改归属
chown -R user:group dir/     # 递归修改

# 提权
sudo command                 # 以root执行
su - username                # 切换用户并加载环境
```

### 6. 实用管道组合技（效率倍增）

```
# 统计文件中各关键词出现次数
grep "ERROR" app.log | sort | uniq -c | sort -rn | head -10

# 找出占用磁盘最大的前10个目录
du -sh /* 2>/dev/null | sort -rh | head -10

# 实时监控某个进程的资源消耗
watch -n 1 'ps aux | grep java | grep -v grep'

# 批量替换文件内容
sed -i 's/old_port/new_port/g' /etc/nginx/conf.d/*.conf

# 解压/压缩
tar -xzf archive.tar.gz      # 解压
tar -czf backup.tar.gz dir/  # 压缩
unzip file.zip               # 解压zip

# 安全地清空大日志文件（不中断写入中的进程）
> /var/log/huge.log
truncate -s 0 /var/log/huge.log
```

### 高效习惯：
1. **Tab 补全**：永远不要手打完整路径/命令，按一次 Tab 补全，两次 Tab 列出候选项。
2. **Ctrl+R 反向搜索**：输入关键字即可从历史命令中模糊匹配，比反复按上箭头快 10 倍。
3. **别名设置**：将高频长命令写入 `~/.bashrc`


## 运维指令集
### 1.系统资源监控 （性能排查）

| 指令           | 用途          | 关键参数                                   |
| ------------ | ----------- | -------------------------------------- |
| `top/htop`   | 实时进程监控      | `top -c` 显示完整命令                        |
| `vmstat`     | CPU/内存/IO概览 | `vmstat 1 5` 关注 si/so/wa               |
| `iostat`     | 磁盘IO分析      | `iostat -xz 1` 关注 %util/await          |
| `free`       | 内存使用        | `free -h` 重点看 available                |
| `sar`        | 历史数据        | `sar -u 1 3` 需装 sysstat                |
| `dmesg`      | 内核日志        | `dmesg -T \| tail -50`                 |
| `journalctl` | 服务日志        | `journalctl -u nginx --since "1h ago"` |

### 2. 文件与磁盘

```
df -hT | grep -v tmpfs                    # 磁盘空间
du -ahx . | sort -rh | head -10           # Top10大文件
grep -rnw '/var/log/' -e 'ERROR'          # 内容搜索
find /data -name "*.log" -mtime +7 -delete # 清理旧日志
chown -R www-data:www-data /var/www/html   # 归属修改
chmod 644 config.yaml                      # 权限(文件644/目录755)
```

### 3. 网络诊断

```
ss -tulnp                    # 端口监听(替代netstat)
ss -s                        # 连接统计
curl -I https://example.com  # HTTP状态码
mtr --report target_ip       # 路由追踪+丢包率
dig +short example.com A     # DNS解析
sudo ufw status verbose      # 防火墙

```
