# Sing-Box 一键安装管理脚本

一个适用于各种 Linux 发行版的 sing-box 一键安装和管理脚本。

## 功能特点

- 支持多种 Linux 发行版（Ubuntu/Debian/CentOS/RockyLinux/Alpine 等）
- 自动检测系统环境并安装依赖
- 一键安装 sing-box 及管理脚本
- 自动配置 sing-box 及管理脚本
- 支持启动、停止、重启、重载 sing-box
- 查看 sing-box 日志
- 支持更新和卸载 sing-box 和管理脚本
- 支持 Clash 订阅地址转换
- 定时自动更新订阅内容
- 备份和恢复配置
- 网络诊断工具集成

## 安装方法

### 一键安装

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/randyhong/sing-box-linux/main/install.sh)"
```

### 手动安装

```bash
git clone https://github.com/randyhong/sing-box-linux.git
cd sing-box-linux
chmod +x install.sh
./install.sh
```

## 使用方法

安装完成后，可以通过 `sbctl` 命令来管理 sing-box。

### 命令行模式

```bash
sbctl [command]
```

可用命令：
- `install`: 安装或更新 sing-box
- `uninstall`: 卸载 sing-box
- `start`: 启动 sing-box 服务
- `stop`: 停止 sing-box 服务
- `restart`: 重启 sing-box 服务
- `status`: 查看 sing-box 服务状态
- `reload`: 重载 sing-box 配置
- `log`: 查看 sing-box 日志
- `check`: 检查配置文件语法
- `update`: 更新 sing-box 到最新版本
- `subscribe`: 管理 Clash 订阅
- `backup`: 备份配置
- `restore`: 从备份恢复配置
- `test`: 运行网络诊断
- `version`: 显示版本信息

### 交互式菜单

直接运行 `sbctl` 命令，将显示交互式菜单。

## 订阅管理

### 添加订阅

```bash
sbctl subscribe add [URL] [NAME]
```

### 更新订阅

```bash
sbctl subscribe update
```

### 列出所有订阅

```bash
sbctl subscribe list
```

### 删除订阅

```bash
sbctl subscribe remove [URL]
```

## 备份和恢复

### 创建备份

```bash
sbctl backup create [NAME]
```

### 列出所有备份

```bash
sbctl backup list
```

### 从备份恢复

```bash
sbctl backup restore [NAME]
```

## 网络诊断

### 系统信息

```bash
sbctl test system
```

### Sing-box 安装检查

```bash
sbctl test singbox
```

### 网络连通性测试

```bash
sbctl test network
```

### 路由追踪

```bash
sbctl test traceroute [TARGET]
```

### 速度测试

```bash
sbctl test speed
```

### 检查开放端口

```bash
sbctl test ports
```

### 运行所有测试

```bash
sbctl test all
```

## 配置文件

- 主配置文件: `/etc/sing-box/config.json`
- 订阅目录: `/etc/sing-box/subscriptions`
- 备份目录: `/etc/sing-box/backups`
- 日志目录: `/var/log/sing-box`

## 许可证

MIT License
