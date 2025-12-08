# alphaFFM-go

> Go语言实现的Field-aware Factorization Machines (FFM) 算法库，基于FTRL优化

[![Go Version](https://img.shields.io/badge/Go-1.18+-00ADD8?style=flat&logo=go)](https://go.dev/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 📖 简介

**alphaFFM-go** 是基于 alphaFM-go 项目架构实现的 FFM 算法版本。

- 🎯 **用途**: 二分类问题（CTR预估、推荐系统等）
- 🧮 **算法**: Field-aware Factorization Machines (FFM)
- 🚀 **优化**: FTRL (Follow The Regularized Leader)
- 💻 **语言**: Go 1.18+
- 📊 **特点**: 单机多线程、流式处理、工业级性能

### FFM vs FM

FFM (Field-aware Factorization Machines) 是 FM 的增强版本：

**FM (Factorization Machines)**:
- 每个特征有一个隐向量 v_i
- 交互项: Σ<v_i, v_j> * x_i * x_j

**FFM (Field-aware Factorization Machines)**:
- 每个特征针对不同field有不同的隐向量 v_{i,f_j}
- 交互项: Σ<v_{i,f_j}, v_{j,f_i}> * x_i * x_j
- 更细粒度的特征交互建模
- 通常在CTR预估任务上比FM效果更好（AUC提升0.1%-0.5%）

## ✨ 核心特性

| 特性 | 说明 | 状态 |
|------|------|------|
| FFM模型 | Field-aware二阶特征交互 | ✅ |
| FTRL优化 | 在线学习算法 | ✅ |
| 多线程训练 | 生产者-消费者模式 | ✅ |
| 流式处理 | 支持超大数据集 | ✅ |
| SIMD优化 | 向量化计算加速 | ✅ |
| L1/L2正则 | 防止过拟合 | ✅ |

## 🚀 快速开始

### 安装

```bash
# 克隆项目
git clone https://github.com/gerogexiongle/alphaFFM-go.git
cd alphaFFM-go

# 编译
make

# 查看可执行文件
ls bin/
# ffm_train  ffm_predict
```

### 数据格式

FFM支持多种数据格式：

**格式1: Field:Feature:Value（FFM显式域名格式）**
```
1 user:u123:1 item:i456:1 price:p1:0.5
0 user:u456:1 item:i789:1 price:p2:0.8
```

**格式2: Feature:Value（FM格式，自动提取field）**
```
1 sex:1 age:0.3 f1:1 f3:0.9
0 sex:0 age:0.7 f2:0.4 f5:0.8
```

**格式3: Feature:Value + 配置文件（推荐）**

使用FM格式样本 + 配置文件指定特征到域的映射，既保持了样本的简洁性，又能灵活控制域的划分。

配置文件示例 (`field_config.txt`):
```
# 用户特征 -> user域
sex user
age user

# 商品特征 -> item域
f1 item
f2 item
f3 item

# 上下文特征 -> context域
f5 context
f8 context
```

**格式4: 数字特征编码（自动域提取）**

当特征名是大数字（>= 2^32）时，自动提取高32位作为域ID：

```
1 51539607553:1 55834574849:1 60129542145:0.5 sex:1 age:0.3
```

特征编码规则：
- 高32位 = 域ID
- 低32位 = 特征ID
- `51539607553` (0x0000000C00000001) → 域ID=12 → 域名=`field_12`

这种方式完美支持业务中的特征编码规范，大数字特征无需配置即可自动提取域！

详细说明请参考: [域配置文档](docs/FIELD_CONFIG.md)

### 训练模型

**基础训练**:
```bash
cat train_data.txt | ./bin/ffm_train \
    -m model.txt \
    -dim 1,1,8 \
    -init_stdev 0.1 \
    -w_alpha 0.05 -w_beta 1.0 -w_l1 0.1 -w_l2 5.0 \
    -v_alpha 0.05 -v_beta 1.0 -v_l1 0.1 -v_l2 5.0 \
    -core 4
```

**使用配置文件训练（推荐）**:
```bash
# FM格式样本 + 配置文件
cat train_data_fm.txt | ./bin/ffm_train \
    -m model.txt \
    -field_config field_config.txt \
    -dim 1,1,8 \
    -core 4
```

### 预测

**基础预测**:
```bash
cat test_data.txt | ./bin/ffm_predict \
    -m model.txt \
    -dim 8 \
    -out predictions.txt \
    -core 4
```

**使用配置文件预测**:
```bash
# 必须使用与训练时相同的配置文件
cat test_data_fm.txt | ./bin/ffm_predict \
    -m model.txt \
    -field_config field_config.txt \
    -dim 8 \
    -out predictions.txt \
    -core 4
```

## 📊 命令行参数

### 训练参数 (ffm_train)

| 参数 | 说明 | 默认值 |
|------|------|--------|
| -m | 输出模型路径 | 必填 |
| -mf | 模型格式(txt/bin) | txt |
| -dim | k0,k1,k2 (bias,1阶,2阶维度) | 1,1,8 |
| -init_stdev | 隐向量初始化标准差 | 0.1 |
| -w_alpha | w学习率参数α | 0.05 |
| -w_beta | w学习率参数β | 1.0 |
| -w_l1 | w的L1正则 | 0.1 |
| -w_l2 | w的L2正则 | 5.0 |
| -v_alpha | v学习率参数α | 0.05 |
| -v_beta | v学习率参数β | 1.0 |
| -v_l1 | v的L1正则 | 0.1 |
| -v_l2 | v的L2正则 | 5.0 |
| -core | 线程数 | 1 |
| -simd | SIMD优化(scalar/blas) | scalar |
| -field_config | 域配置文件路径 | 空（使用auto模式） |

### 预测参数 (ffm_predict)

| 参数 | 说明 | 默认值 |
|------|------|--------|
| -m | 模型路径 | 必填 |
| -mf | 模型格式(txt/bin) | txt |
| -dim | 隐向量维度 | 8 |
| -out | 输出预测结果路径 | 必填 |
| -core | 线程数 | 1 |
| -simd | SIMD优化(scalar/blas) | scalar |
| -field_config | 域配置文件路径 | 空（使用auto模式） |

## 🏗️ 项目结构

```
alphaFFM-go/
├── cmd/                    # 可执行程序入口
│   ├── ffm_train/         # 训练程序
│   └── ffm_predict/       # 预测程序
├── pkg/                    # 核心包
│   ├── model/             # FFM模型实现
│   │   ├── ffm_model.go         # FFM模型结构
│   │   ├── ffm_trainer.go       # FTRL训练器
│   │   └── ffm_predictor.go     # 预测器
│   ├── config/            # 域配置管理
│   │   └── field_config.go      # 特征到域的映射配置
│   ├── frame/             # 多线程框架
│   ├── sample/            # 样本解析
│   ├── lock/              # 锁管理
│   ├── mem/               # 内存池
│   ├── simd/              # SIMD优化
│   └── utils/             # 工具函数
├── docs/                  # 文档
│   └── FIELD_CONFIG.md   # 域配置文档
├── bin/                   # 编译输出
├── field_config_example.txt   # 配置文件示例（文本格式）
├── field_config_example.json  # 配置文件示例（JSON格式）
├── go.mod                 # Go模块定义
├── Makefile              # 编译配置
└── README.md             # 本文件
```

## 🔬 算法原理

### FFM预测公式

```
y = w_0 + Σw_i*x_i + ΣΣ<v_{i,f_j}, v_{j,f_i}>*x_i*x_j
```

其中：
- `w_0`: bias项
- `w_i`: 一阶权重
- `v_{i,f_j}`: 特征i针对field f_j的隐向量
- `<v_{i,f_j}, v_{j,f_i}>`: 内积

### FTRL更新规则

**权重更新**:
```
w_i = -1 / (α + β + √n_i) * (z_i - sign(z_i)*λ_1)  if |z_i| > λ_1
w_i = 0                                              otherwise
```

**梯度累积**:
```
n_i = n_i + g_i^2
z_i = z_i + g_i - σ_i*w_i
σ_i = (√(n_i + g_i^2) - √n_i) / α
```

## 🎯 与 alphaFM-go 的关系

alphaFFM-go 完全基于 alphaFM-go 的架构：

| 组件 | 继承关系 |
|------|----------|
| 训练框架 | ✅ 完全相同 |
| 数据加载 | ✅ 完全相同（扩展支持field） |
| FTRL优化 | ✅ 完全相同 |
| 多线程 | ✅ 完全相同 |
| SIMD优化 | ✅ 完全相同 |
| **核心区别** | **FM单向量 → FFM多向量（field-aware）** |

## 📈 性能优化

- **SIMD加速**: 支持BLAS向量化操作
- **多线程**: 生产者-消费者并行训练
- **内存池**: 减少GC压力
- **锁池**: 细粒度特征级锁

启用SIMD优化：
```bash
# 训练时启用BLAS加速
cat train.txt | ./bin/ffm_train -m model.txt -simd blas -core 4

# 预测时启用BLAS加速
cat test.txt | ./bin/ffm_predict -m model.txt -out pred.txt -simd blas -core 4
```

## 🔍 模型文件格式

FFM模型文件格式（文本）：

```
FIELDS field1 field2 field3 ...
bias 0.1 0.0 0.0
feature1 0.5 v1,f1[0] v1,f1[1] ... v1,f2[0] v1,f2[1] ... w_n w_z v_n... v_z...
feature2 0.3 v2,f1[0] v2,f1[1] ... v2,f2[0] v2,f2[1] ... w_n w_z v_n... v_z...
...
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

## 🙏 致谢

- 基于 [alphaFM-go](https://github.com/gerogexiongle/alphaFM-go.git) 项目架构
- FFM算法参考论文: [Field-aware Factorization Machines for CTR Prediction](https://www.csie.ntu.edu.tw/~cjlin/papers/ffm.pdf)

