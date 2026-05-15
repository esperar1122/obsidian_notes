stressapptest：
1.安装依赖
sudo apt install -y git build-essential autoconf automake libtool libaio-dev
2.解压源码包
tar -zxvf stressapptest-1.0.11.tar.gz
cd stressapptest-1.0.11
3.编译安装
./configure
make -j$(nproc)
sudo make install
4.测试命令
sudo stressapptest  -M 15000 -s 7200 2>&1 | tee ~/lttest.txt


