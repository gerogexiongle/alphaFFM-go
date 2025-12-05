# alphaFFM-go 实现说明

## 项目概述

alphaFFM-go 是基于 alphaFM-go 项目实现的 FFM (Field-aware Factorization Machines) 算法版本。本项目完全保持了 alphaFM-go 的架构和技术路线，唯一的核心区别是实现了 FFM 算法。

## 与 alphaFM-go 的对比

### 相同部分（100%复用）

| 组件 | 说明 | 文件 |
|------|------|------|
| 训练框架 | 生产者-消费者多线程框架 | `pkg/frame/pc_frame.go` |
| 锁管理 | 特征级细粒度锁池 | `pkg/lock/lock_pool.go` |
| 内存池 | 内存分配优化 | `pkg/mem/mem_pool.go` |
| 工具函数 | 随机数、符号函数等 | `pkg/utils/utils.go` |
| SIMD优化 | 向量化计算加速 | `pkg/simd/*` |
| FTRL优化 | 在线学习算法 | 训练器中的FTRL逻辑 |
| 命令行解析 | 参数处理 | `cmd/*/main.go` |
| 构建系统 | Makefile编译配置 | `Makefile` |

### 不同部分（核心算法）

#### 1. 数据结构

**FM (alphaFM-go)**:
```go
type FTRLModelUnit struct {
    Wi   float64      // 一阶权重
    WNi  float64      // w的累积参数
    WZi  float64      // w的z参数
    Vi   []float64    // 隐向量（统一的）
    VNi  []float64    // v的n参数
    VZi  []float64    // v的z参数
}
```

**FFM (alphaFFM-go)**:
```go
type FFMModelUnit struct {
    Wi   float64                 // 一阶权重
    WNi  float64                 // w的累积参数
    WZi  float64                 // w的z参数
    // FFM核心：针对每个field的隐向量映射
    ViMap  map[string][]float64  // field -> 隐向量
    VNiMap map[string][]float64  // field -> v的n参数
    VZiMap map[string][]float64  // field -> v的z参数
}
```

**关键区别**: FFM 中每个特征针对不同的 field 有不同的隐向量，而 FM 只有一个统一的隐向量。

#### 2. 预测公式

**FM**:
```
y = w0 + Σwi*xi + ΣΣ<vi, vj>*xi*xj
```
- 特征 i 和特征 j 的交互使用 vi 和 vj 的内积
- 所有交互共享同一套隐向量

**FFM**:
```
y = w0 + Σwi*xi + ΣΣ<vi,fj, vj,fi>*xi*xj
```
- 特征 i 针对特征 j 的 field (fj) 有专门的隐向量 vi,fj
- 特征 j 针对特征 i 的 field (fi) 有专门的隐向量 vj,fi
- 更细粒度的特征交互建模

#### 3. 代码实现对比

**FM 预测** (`alphaFM-go/pkg/model/ftrl_model.go`):
```go
// 二阶交互项
for f := 0; f < m.FactorNum; f++ {
    sumF := 0.0
    sumSqr := 0.0
    for i := 0; i < len(x); i++ {
        d := theta[i].Vi[f] * x[i].Value
        sumF += d
        sumSqr += d * d
    }
    result += 0.5 * (sumF*sumF - sumSqr)
}
```

**FFM 预测** (`alphaFFM-go/pkg/model/ffm_model.go`):
```go
// 二阶交互项（FFM）
for i := 0; i < len(x); i++ {
    for j := i + 1; j < len(x); j++ {
        // 获取特征i针对特征j的field的隐向量
        vi := theta[i].GetOrInitVi(x[j].Field, m.FactorNum, m.InitMean, m.InitStdev)
        // 获取特征j针对特征i的field的隐向量
        vj := theta[j].GetOrInitVi(x[i].Field, m.FactorNum, m.InitMean, m.InitStdev)
        
        // 计算内积
        innerProduct := 0.0
        for f := 0; f < m.FactorNum; f++ {
            innerProduct += vi[f] * vj[f]
        }
        
        result += innerProduct * x[i].Value * x[j].Value
    }
}
```

#### 4. 样本格式

**FM 样本格式**:
```
label feature1:value1 feature2:value2 ...
```
例如:
```
1 sex:1 age:0.3 f1:1 f3:0.9
```

**FFM 样本格式** (支持两种):
```
# 格式1: field:feature:value (推荐)
1 user:u123:1 item:i456:1 price:p1:0.5

# 格式2: feature:value (自动从feature名提取field)
1 sex:1 age:0.3 f1:1 f3:0.9
```

FFM 的样本解析器 (`pkg/sample/sample.go`) 增加了 field 提取逻辑。

#### 5. 模型文件格式

**FM 模型文件**:
```
bias wi w_ni w_zi
feature1 wi vi[0] vi[1] ... w_ni w_zi v_ni[0] ... v_zi[0] ...
```

**FFM 模型文件**:
```
FIELDS field1 field2 field3 ...
bias wi w_ni w_zi
feature1 wi vi,f1[0] vi,f1[1] ... vi,f2[0] ... w_ni w_zi v_ni,f1[0] ... v_zi,f1[0] ...
```

FFM 模型文件第一行包含所有 field 的列表，每个特征保存针对所有 field 的隐向量。

## 算法复杂度对比

### 参数量

- **FM**: 特征数 × (1 + k)，其中 k 是隐向量维度
- **FFM**: 特征数 × (1 + k × f)，其中 f 是 field 数量

FFM 的参数量是 FM 的 f 倍。

### 训练时间复杂度

- **FM**: O(k × n)，其中 n 是样本中非零特征数
- **FFM**: O(k × n²)

FFM 需要计算所有特征对的交互，复杂度更高。

### 预测时间复杂度

- **FM**: O(k × n)
- **FFM**: O(k × n²)

## 性能优化

两个版本都实现了相同的优化技术：

1. **多线程训练**: 生产者-消费者模式，支持多核并行
2. **特征级锁**: 细粒度锁定，减少锁竞争
3. **SIMD加速**: 向量化计算，加速内积运算
4. **内存池**: 减少内存分配开销
5. **流式处理**: 支持任意大小的数据集

## 使用场景

### FM 适用场景
- 特征维度较高
- 训练数据较大
- 对训练速度要求高
- Field 信息不明显

### FFM 适用场景
- Field 信息明确（如user field、item field等）
- 对预测精度要求高（通常AUC提升0.1%-0.5%）
- 可以接受更长的训练时间
- CTR预估、推荐系统等场景

## 测试结果

使用相同的测试数据 `test_data.txt`（10个样本）：

### FM 结果 (alphaFM-go)
```bash
cat test_data.txt | ./bin/fm_train -m fm_model.txt -dim 1,1,4 -core 1
cat test_data.txt | ./bin/fm_predict -m fm_model.txt -dim 4 -out fm_pred.txt -core 1
```

### FFM 结果 (alphaFFM-go)
```bash
cat test_data.txt | ./bin/ffm_train -m ffm_model.txt -dim 1,1,4 -core 1
cat test_data.txt | ./bin/ffm_predict -m ffm_model.txt -dim 4 -out ffm_pred.txt -core 1
```

两个版本都能正常训练和预测，输出格式一致。

## 项目结构对比

```
alphaFM-go/                    alphaFFM-go/
├── cmd/                       ├── cmd/
│   ├── fm_train/             │   ├── ffm_train/        ← 名称改变
│   └── fm_predict/           │   └── ffm_predict/      ← 名称改变
├── pkg/                       ├── pkg/
│   ├── model/                 │   ├── model/
│   │   ├── ftrl_model.go    │   │   ├── ffm_model.go      ← 核心算法变化
│   │   ├── ftrl_trainer.go  │   │   ├── ffm_trainer.go    ← 核心算法变化
│   │   └── ftrl_predictor.go│   │   └── ffm_predictor.go  ← 核心算法变化
│   ├── frame/  (相同)        │   ├── frame/  (相同)
│   ├── sample/ (扩展)        │   ├── sample/ (扩展field支持)
│   ├── lock/   (相同)        │   ├── lock/   (相同)
│   ├── mem/    (相同)        │   ├── mem/    (相同)
│   ├── simd/   (相同)        │   ├── simd/   (相同)
│   └── utils/  (相同)        │   └── utils/  (相同)
└── ...                        └── ...
```

## 总结

alphaFFM-go 完全基于 alphaFM-go 的架构实现，保持了：
- ✅ 相同的技术栈（Go 1.18+）
- ✅ 相同的优化技术（多线程、SIMD、内存池等）
- ✅ 相同的工程质量（代码风格、错误处理等）
- ✅ 相同的使用方式（命令行参数、数据格式等）

唯一的核心区别是：
- ❗ FM: 每个特征一个统一的隐向量
- ❗ FFM: 每个特征针对每个field有不同的隐向量

这使得 FFM 在 CTR 预估等任务上通常能获得更好的效果，代价是更高的计算复杂度和参数量。

