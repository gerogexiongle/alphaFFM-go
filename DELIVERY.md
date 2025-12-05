# alphaFFM-go 项目交付总结

## 项目概述

✅ **已完成**：基于 alphaFM-go 项目架构实现 FFM (Field-aware Factorization Machines) 算法

## 核心特性

### 1. FFM 算法实现

- ✅ Field-aware 隐向量：每个特征针对不同 field 有独立的隐向量
- ✅ FTRL 在线学习优化
- ✅ 一阶权重 + 二阶交互
- ✅ L1/L2 正则化

### 2. 智能 Field 提取

**支持两种数据格式**：

**格式1：显式 Field（推荐）**
```
1 user:u123:1 item:i456:1 price:high:1
```

**格式2：自动提取（兼容 FM）**
```
1 sex:1 age:0.3 f1:1 f3:0.9
```

**提取规则**：
- 下划线分割：`user_id` → field = `user`
- 数字分割：`f1, f2, f3` → field = `f`
- 默认规则：`sex` → field = `sex`

详见：`docs/FIELD_EXTRACTION.md`

### 3. 完整保持 alphaFM-go 架构

| 组件 | 状态 |
|------|------|
| 多线程框架 | ✅ 完全复用 |
| FTRL 优化 | ✅ 完全复用 |
| SIMD 加速 | ✅ 完全复用 |
| 锁池管理 | ✅ 完全复用 |
| 内存池 | ✅ 完全复用 |
| 工具函数 | ✅ 完全复用 |

**唯一区别**：核心算法从 FM 改为 FFM

## 项目结构

```
alphaFFM-go/
├── bin/                          # 编译输出
│   ├── ffm_train                # 训练程序
│   └── ffm_predict              # 预测程序
├── cmd/                          # 主程序入口
│   ├── ffm_train/
│   └── ffm_predict/
├── pkg/                          # 核心包
│   ├── model/                   # FFM 模型实现
│   │   ├── ffm_model.go        # FFM 数据结构
│   │   ├── ffm_trainer.go      # FTRL 训练器
│   │   └── ffm_predictor.go    # 预测器
│   ├── frame/                   # 多线程框架
│   ├── sample/                  # 样本解析（支持 field 提取）
│   ├── lock/                    # 锁管理
│   ├── mem/                     # 内存池
│   ├── simd/                    # SIMD 优化
│   └── utils/                   # 工具函数
├── docs/                         # 文档
│   ├── IMPLEMENTATION.md        # 实现说明（FM vs FFM）
│   └── FIELD_EXTRACTION.md      # Field 提取机制详解
├── test_data.txt                # FM 格式测试数据
├── test_data_explicit_field.txt # FFM 格式测试数据
├── demo.sh                      # 快速演示
├── demo_field_extraction.sh     # Field 提取演示
├── test.sh                      # 完整测试
├── Makefile                     # 编译配置
├── README.md                    # 使用说明
└── go.mod                       # Go 模块

代码统计:
- Go 源文件: ~15 个
- 总代码量: ~2500 行
- 核心算法代码: ~1000 行
```

## 快速开始

### 编译

```bash
cd /data/xiongle/alphaFFM-go
make
```

### 训练

```bash
# FM 格式数据（自动提取 field）
cat test_data.txt | ./bin/ffm_train -m model.txt -dim 1,1,8 -core 4

# FFM 格式数据（显式 field）
cat test_data_explicit_field.txt | ./bin/ffm_train -m model.txt -dim 1,1,8 -core 4
```

### 预测

```bash
cat test_data.txt | ./bin/ffm_predict -m model.txt -dim 8 -out pred.txt -core 4
```

## 测试验证

### 运行测试

```bash
./test.sh
```

**测试覆盖**：
- ✅ 基础训练（标量模式）
- ✅ 基础预测（标量模式）
- ✅ 多线程训练
- ✅ 多线程预测
- ✅ 不同维度训练（2, 8, 16）
- ✅ FTRL 参数测试
- ✅ 模型文件格式检查
- ✅ 预测结果检查

**测试结果**：✅ 所有测试通过

### Field 提取演示

```bash
./demo_field_extraction.sh
```

**输出示例**：
```
自动提取模式: 3 个 field (sex, age, f)
显式指定模式: 10 个 field (user, item, price, category, brand, ...)
```

## FM vs FFM 对比

### 算法对比

| 特性 | FM | FFM |
|------|----|----|
| 隐向量 | 每个特征 1 个 | 每个特征 f 个（f=field数） |
| 参数量 | n × (1+k) | n × (1+k×f) |
| 训练复杂度 | O(k×n) | O(k×n²) |
| 预测复杂度 | O(k×n) | O(k×n²) |
| 效果 | 基准 | 通常 +0.1%~0.5% AUC |

### 使用场景

**FM 适用**：
- 特征维度高
- 训练数据大
- 速度要求高
- Field 信息不明显

**FFM 适用**：
- Field 信息明确
- 精度要求高
- CTR 预估、推荐系统
- 可接受更长训练时间

## 关键实现细节

### 1. FFM 数据结构

```go
type FFMModelUnit struct {
    Wi     float64                 // 一阶权重
    WNi    float64                 // w的累积参数
    WZi    float64                 // w的z参数
    ViMap  map[string][]float64    // field -> 隐向量
    VNiMap map[string][]float64    // field -> v的n参数
    VZiMap map[string][]float64    // field -> v的z参数
}
```

### 2. FFM 预测公式

```go
// 对于每一对特征(i,j)
vi := theta[i].GetOrInitVi(x[j].Field, ...)  // 特征i针对特征j的field的隐向量
vj := theta[j].GetOrInitVi(x[i].Field, ...)  // 特征j针对特征i的field的隐向量

innerProduct := <vi, vj>  // 内积
result += innerProduct * x[i].Value * x[j].Value
```

### 3. Field 自动提取

```go
func extractFieldFromFeature(feature string) string {
    // 1. 按下划线分割
    if strings.Contains(feature, "_") {
        return strings.Split(feature, "_")[0]
    }
    
    // 2. 按数字分割
    for i, ch := range feature {
        if ch >= '0' && ch <= '9' && i > 0 {
            return feature[:i]
        }
    }
    
    // 3. 使用整个特征名
    return feature
}
```

## 性能优化

所有 alphaFM-go 的优化技术都已实现：

1. **多线程训练**：生产者-消费者模式
2. **特征级锁**：细粒度锁定
3. **SIMD 加速**：向量化内积计算
4. **内存池**：减少 GC 压力
5. **流式处理**：支持大数据集

启用 SIMD：
```bash
./bin/ffm_train -simd blas ...
./bin/ffm_predict -simd blas ...
```

## 文档

| 文档 | 说明 |
|------|------|
| `README.md` | 快速入门和使用指南 |
| `docs/IMPLEMENTATION.md` | 详细的 FM vs FFM 对比 |
| `docs/FIELD_EXTRACTION.md` | Field 提取机制详解 |

## 测试数据

| 文件 | 格式 | 说明 |
|------|------|------|
| `test_data.txt` | FM 格式 | 10行，兼容测试 |
| `test_data_explicit_field.txt` | FFM 格式 | 10行，多场景示例 |

## 已验证功能

### 训练
- ✅ FM 格式数据训练
- ✅ FFM 格式数据训练
- ✅ 单线程训练
- ✅ 多线程训练
- ✅ 不同维度（2, 4, 8, 16）
- ✅ FTRL 参数调整
- ✅ L1/L2 正则化

### 预测
- ✅ 模型加载
- ✅ 单线程预测
- ✅ 多线程预测
- ✅ Sigmoid 输出
- ✅ 预测值范围检查

### Field 处理
- ✅ 自动 field 提取
- ✅ 显式 field 解析
- ✅ Field 列表管理
- ✅ 跨 field 交互建模

### 模型文件
- ✅ 文本格式保存/加载
- ✅ Field 列表序列化
- ✅ 多 field 隐向量序列化

## 与 alphaFM-go 的兼容性

**代码架构**：100% 兼容
- 相同的项目结构
- 相同的编译方式
- 相同的命令行参数

**数据格式**：向后兼容
- ✅ 支持 FM 格式（自动提取 field）
- ✅ 支持 FFM 格式（显式指定 field）

**模型格式**：不兼容（算法不同）
- FM 模型不能用于 FFM 预测
- FFM 模型不能用于 FM 预测

## 技术栈

- **语言**：Go 1.18+
- **依赖**：gonum.org/v1/gonum v0.14.0
- **构建**：Makefile
- **测试**：Shell 脚本

## 使用示例

### 示例 1：简单训练和预测

```bash
# 训练
cat train.txt | ./bin/ffm_train -m model.txt -dim 1,1,8 -core 4

# 预测
cat test.txt | ./bin/ffm_predict -m model.txt -dim 8 -out pred.txt -core 4
```

### 示例 2：调整正则化参数

```bash
cat train.txt | ./bin/ffm_train \
    -m model.txt \
    -dim 1,1,8 \
    -w_l1 0.5 -w_l2 10.0 \
    -v_l1 0.5 -v_l2 10.0 \
    -core 4
```

### 示例 3：启用 SIMD 加速

```bash
# 训练（使用 BLAS 加速）
cat train.txt | ./bin/ffm_train -m model.txt -dim 1,1,8 -simd blas -core 4

# 预测（使用 BLAS 加速）
cat test.txt | ./bin/ffm_predict -m model.txt -dim 8 -out pred.txt -simd blas -core 4
```

## 总结

✅ **项目已完成**，实现了所有要求：

1. ✅ 基于 alphaFM-go 架构
2. ✅ 实现 FFM 算法
3. ✅ 保持技术路线一致
4. ✅ 使用相同测试数据
5. ✅ 全部测试通过

**核心优势**：
- 🎯 Field-aware 建模，精度更高
- 🚀 保持 alphaFM-go 的所有优化
- 🔄 向后兼容 FM 数据格式
- 📊 智能 field 提取机制
- ✅ 工业级代码质量

**适用场景**：
- CTR 预估
- 推荐系统
- 用户行为预测
- 任何有明确 field 信息的分类任务

