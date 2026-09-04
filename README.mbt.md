# tryandrun/fast_qr_moonbit

基于 [MoonBit](https://www.moonbitlang.cn/) 的高性能二维码（QR Code）生成库。

## 功能特性

- 纯 MoonBit 实现，无外部依赖
- 支持 wasm / native 多后端
- 快速生成符合 ISO/IEC 18004 标准的二维码

## 快速开始

### 安装 MoonBit 工具链

```bash
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
```

### 构建

```bash
moon build
```

### 运行 CLI

```bash
moon run cmd/main
```

### 测试

```bash
moon test
```

## 项目结构

```
├── moon.mod              # MoonBit 模块配置
├── moon.pkg              # 根包描述
├── cmd/main/             # CLI 可执行入口
│   ├── main.mbt
│   └── moon.pkg
├── fast_qr_moonbit.mbt   # 库代码
├── fast_qr_moonbit_test.mbt  # 库测试
└── docs/                 # 项目文档
```
