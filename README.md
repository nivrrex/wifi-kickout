# wifi-kickout
OpenWrt 弱信号剔除 wifi-kickout ，使用 lua 和 ubus 实现

# 功能
* 定时遍历所有连接的 wifi 终端，如果低于一定值，则强制踢出该终端。
* 可以分别针对 2.4G 和 5G 终端设置不同的信号限值
* 如果 2.4G 信号过强，且未连接 5G 网络，则可以强制踢出，让其重新连接至 5G 网络

# 备注
前期使用 io.popen 调用 shell ，性能较差，本版本直接调用 ubus 的 lua 接口，性能有较大提升
