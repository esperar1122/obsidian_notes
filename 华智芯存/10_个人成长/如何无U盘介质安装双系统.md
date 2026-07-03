1.首先下载Grub2Win，已存在附件库中
2.下载要安装的系统镜像，如Linux：Ubuntu 18.04 LTS.ISO
3.要安装系统的空间必须要是完全的“未分配空间”，不能建盘
4.以下操作以Ubuntu为例

#### 第一步：
进入Grub的首页点击`Manage Boot Menu`配置菜单界面后点击`Add A New Entry`
![[Manage Menu.png]]
#### 第二步
进入Add a new Entry界面后，Type选择ISO Boot，该选项为`镜像启动`，直接加载配置模板“Load Sample Code”
![[Grub2 boot Menu.png]]
#### 第三步
加载模板之后，选择`Select ISO File`将已安装好的ISO镜像加载进去（实则是自动映射ISO路径）
![[ISOBoot Interface.png]]
此处要填写kernelpath（内核）与initrdpath（临时根文件）的路径
![[ISOBoot Edit code.png]]
#### 第四步
配置完成之后Apply，点击`Click To Reboot Your Machine`进入EFI固件安装页面，选择`Boot An ISO file`开始进行镜像启动安装
![[Configuration complete Interface.png]]

![[Boot Menu Interface.png]]
#### 第五步
进入安装类型界面后选择`Something else`进行手动分区，不要Erase disk清除整个磁盘

在磁盘的 free space（空闲空间）上手动创建分区，建议至少创建一个挂载点为 / 的 ext4 分区（建议 100G），并可根据需求创建 swap 交换分区和 /home 分区。

在 UEFI 模式下，将启动引导器（boot loader）的安装位置指定为整块硬盘（如 /dev/sda），安装程序会自动识别并配置 Windows Server 2019 的双系统引导菜单。

服务器特别注意：在安装前请务必进入 BIOS 关闭 Secure Boot（安全启动），若未使用硬 RAID 建议将磁盘模式改为 AHCI，并确保 Ubuntu 与 Windows Server 2019 均采用统一的 UEFI 引导模式。