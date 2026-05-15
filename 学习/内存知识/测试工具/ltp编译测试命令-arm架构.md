ltp:

1.安装LTP所需依赖
sudo apt install autoconf automake autotools-dev m4 gcc libssl-dev libaio-dev flex bison libcap-dev libregf-dev libdts-dev libdtools-ocaml-dev libnuma-dev libacl1-dev automake autoconf dma libmm-dev jfsutils libselinux1-dev xfslibs-dev netconfd numactl numad rpcbind nfs-kernel-server rsh-server sysstat
2.解压LTP源码包
tar -jxvf ltp-full-20200930.tar.bz2
3.执行编译
cd ltp-full-20200930
make autotools
./configure
make -j$(nproc)
sudo make install
4.执行测试
sudo /opt/ltp/runltp -p -l ~/ltp_result.log -d /tmp -o ~/ltp_output.log -t 2h
