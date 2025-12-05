# FM vs FFM 模型文件结构对比

## 核心区别：维度增加

**你的理解完全正确**！FFM 相比 FM，参数维度确实增加了，体现在模型文件结构上。

## 实际对比

### 测试配置
- 数据：10 个样本（`test_data.txt`）
- 隐向量维度 k = 4
- 特征数量：7 个（sex, age, f1, f2, f3, f5, f8）

### FM 模型结构

```
=== FM 模型文件 ===
行数: 8 行（1行bias + 7行特征）

第1行（bias）:
bias wi w_ni w_zi
字段数: 4

第2行（特征，如 f3）:
f3 wi v[0] v[1] v[2] v[3] w_ni w_zi v_ni[0] v_ni[1] v_ni[2] v_ni[3] v_zi[0] v_zi[1] v_zi[2] v_zi[3]
字段数: 16 = 1(名) + 1(wi) + 4(vi) + 2(w_ni,w_zi) + 4(v_ni) + 4(v_zi)
```

**FM 结构说明**：
```
每个特征的参数:
- 特征名
- wi (1个一阶权重)
- vi (k个隐向量，统一的)
- w_ni, w_zi (FTRL参数)
- v_ni (k个)
- v_zi (k个)

总参数: 1 + 1 + k + 2 + k + k = 4 + 3k
k=4时: 4 + 12 = 16 个字段
```

### FFM 模型结构

```
=== FFM 模型文件 ===
行数: 9 行（1行FIELDS + 1行bias + 7行特征）

第1行（FIELDS 列表）:
FIELDS sex age f1 f3 f2 f5 f8
字段数: 8 (关键字FIELDS + 7个field名)

第2行（bias）:
bias wi w_ni w_zi
字段数: 4

第3行（特征，如 sex）:
sex wi vi,sex[0..3] vi,age[0..3] vi,f1[0..3] ... w_ni w_zi v_ni,sex[0..3] v_ni,age[0..3] ... v_zi,sex[0..3] ...
字段数: 88 = 1(名) + 1(wi) + 7×4(vi) + 2(w_ni,w_zi) + 7×4(v_ni) + 7×4(v_zi)
```

**FFM 结构说明**：
```
每个特征的参数:
- 特征名
- wi (1个一阶权重)
- vi,field1, vi,field2, ..., vi,fieldF (针对每个field的k维隐向量)
- w_ni, w_zi (FTRL参数)
- v_ni,field1, ..., v_ni,fieldF (针对每个field的k维FTRL参数)
- v_zi,field1, ..., v_zi,fieldF (针对每个field的k维FTRL参数)

总参数: 1 + 1 + F×k + 2 + F×k + F×k = 4 + 3Fk
F=7, k=4时: 4 + 84 = 88 个字段
```

## 参数量公式

### FM 每个特征的参数
```
参数 = 1(wi) + k(vi) + 1(w_ni) + 1(w_zi) + k(v_ni) + k(v_zi)
     = 3 + 3k

k=4: 3 + 12 = 15 个参数（加上特征名=16个字段）
k=8: 3 + 24 = 27 个参数
```

### FFM 每个特征的参数
```
参数 = 1(wi) + F×k(vi) + 1(w_ni) + 1(w_zi) + F×k(v_ni) + F×k(v_zi)
     = 3 + 3Fk

F=7, k=4: 3 + 84 = 87 个参数（加上特征名=88个字段）
F=7, k=8: 3 + 168 = 171 个参数
```

### 参数量对比

| 配置 | FM参数 | FFM参数 | FFM/FM |
|------|--------|---------|--------|
| k=4, F=7 | 15 | 87 | 5.8x |
| k=8, F=7 | 27 | 171 | 6.3x |
| k=4, F=10 | 15 | 123 | 8.2x |
| k=8, F=10 | 27 | 243 | 9.0x |

**结论**：FFM 的参数量约为 FM 的 **F 倍**（F 为 field 数量）

## 模型文件大小对比

### 实际测试结果
```bash
$ ls -lh *_model_compare.txt
-rw-r--r-- 1 user user  876 Dec  5 fm_model_compare.txt   (FM)
-rw-r--r-- 1 user user 7.1K Dec  5 ffm_model_compare.txt  (FFM)

FFM 模型大小 ≈ 8倍 FM
```

## 模型文件格式详解

### FM 模型格式

```
行1: bias wi w_ni w_zi
行2: feature1 wi vi[0] vi[1] ... vi[k-1] w_ni w_zi v_ni[0] ... v_ni[k-1] v_zi[0] ... v_zi[k-1]
行3: feature2 wi vi[0] vi[1] ... vi[k-1] w_ni w_zi v_ni[0] ... v_ni[k-1] v_zi[0] ... v_zi[k-1]
...
```

**示例**（k=4）：
```
bias 0.008376 2.47517 -0.0694
f3 0.0187 -0.0015 0.00002 0 -0.0028 0.5697 -1.1912 0.0037 0.0014 0.00008 0.0018 0.1404 -0.1005 0.0166 0.1744
      ^^^^  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^  ^^^^^^^^^^^^^  ^^^^^^^^^^^^^^^^^^^^^^^^^^  ^^^^^^^^^^^^^^^^^^^^^^^^^^
      wi    vi[0]  vi[1]  vi[2]  vi[3]    w_ni   w_zi    v_ni[0] ... v_ni[3]       v_zi[0] ... v_zi[3]
```

### FFM 模型格式

```
行1: FIELDS field1 field2 ... fieldF
行2: bias wi w_ni w_zi
行3: feature1 wi vi,f1[0..k-1] vi,f2[0..k-1] ... vi,fF[0..k-1] w_ni w_zi v_ni,f1[0..k-1] ... v_zi,fF[0..k-1]
行4: feature2 wi vi,f1[0..k-1] vi,f2[0..k-1] ... vi,fF[0..k-1] w_ni w_zi v_ni,f1[0..k-1] ... v_zi,fF[0..k-1]
...
```

**示例**（k=4, F=7，fields: sex age f1 f3 f2 f5 f8）：
```
FIELDS sex age f1 f3 f2 f5 f8
bias 0.0085 2.4666 -0.0781
sex 0.0346 [vi,sex的4维] [vi,age的4维] [vi,f1的4维] [vi,f3的4维] [vi,f2的4维] [vi,f5的4维] [vi,f8的4维] ...
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
           特征sex针对每个field都有独立的4维隐向量，共7×4=28个隐向量参数
```

## 为什么 FFM 参数更多？

### FM 的隐向量

```
特征 sex 有一个统一的隐向量:
v_sex = [0.1, 0.2, 0.3, 0.4]  (k=4)

所有交互都用这个向量:
sex × age:  <v_sex, v_age>
sex × f1:   <v_sex, v_f1>
sex × f2:   <v_sex, v_f2>
```

### FFM 的隐向量（field-aware）

```
特征 sex 针对不同 field 有不同的隐向量:
v_sex,age = [0.1, 0.2, 0.3, 0.4]  (针对 age 的 field)
v_sex,f1  = [0.5, 0.6, 0.7, 0.8]  (针对 f1 的 field)
v_sex,f2  = [0.9, 1.0, 1.1, 1.2]  (针对 f2 的 field)
...

不同交互用不同的向量:
sex × age:  <v_sex,age的field, v_age,sex的field>
sex × f1:   <v_sex,f1的field, v_f1,sex的field>
sex × f2:   <v_sex,f2的field, v_f2,sex的field>
```

## 代码验证

### FM 模型输出（ftrl_model.go）

```go
// FM: 每个特征一个隐向量
func (u *FTRLModelUnit) String() string {
    parts := []string{fmt.Sprintf("%.6g", u.Wi)}
    
    // vi (k个)
    for _, v := range u.Vi {
        parts = append(parts, fmt.Sprintf("%.6g", v))
    }
    
    // w_ni, w_zi
    parts = append(parts, fmt.Sprintf("%.6g", u.WNi))
    parts = append(parts, fmt.Sprintf("%.6g", u.WZi))
    
    // v_ni (k个)
    for _, vn := range u.VNi {
        parts = append(parts, fmt.Sprintf("%.6g", vn))
    }
    
    // v_zi (k个)
    for _, vz := range u.VZi {
        parts = append(parts, fmt.Sprintf("%.6g", vz))
    }
    
    return strings.Join(parts, " ")
}
```

### FFM 模型输出（ffm_model.go）

```go
// FFM: 每个特征针对每个field一个隐向量
func (u *FFMModelUnit) String(fieldNames []string, factorNum int) string {
    parts := []string{fmt.Sprintf("%.6g", u.Wi)}

    // 按field顺序输出vi（每个field有k个参数）
    for _, field := range fieldNames {
        if vi, exists := u.ViMap[field]; exists {
            for _, v := range vi {
                parts = append(parts, fmt.Sprintf("%.6g", v))
            }
        } else {
            // field不存在，输出零向量
            for f := 0; f < factorNum; f++ {
                parts = append(parts, "0")
            }
        }
    }

    // w_ni, w_zi
    parts = append(parts, fmt.Sprintf("%.6g", u.WNi))
    parts = append(parts, fmt.Sprintf("%.6g", u.WZi))

    // 按field顺序输出v_ni
    for _, field := range fieldNames {
        if vni, exists := u.VNiMap[field]; exists {
            for _, vn := range vni {
                parts = append(parts, fmt.Sprintf("%.6g", vn))
            }
        } else {
            for f := 0; f < factorNum; f++ {
                parts = append(parts, "0")
            }
        }
    }

    // 按field顺序输出v_zi
    for _, field := range fieldNames {
        if vzi, exists := u.VZiMap[field]; exists {
            for _, vz := range vzi {
                parts = append(parts, fmt.Sprintf("%.6g", vz))
            }
        } else {
            for f := 0; f < factorNum; f++ {
                parts = append(parts, "0")
            }
        }
    }

    return strings.Join(parts, " ")
}
```

## 模型文件正确性验证

### ✅ FM 模型正确
```
bias行: 4个字段 ✓
特征行: 16个字段 = 1+1+4+2+4+4 ✓
```

### ✅ FFM 模型正确
```
FIELDS行: 8个字段 (关键字+7个field) ✓
bias行: 4个字段 ✓
特征行: 88个字段 = 1+1+28+2+28+28 ✓
       其中 28 = 7(fields) × 4(k)
```

## 手动计算验证

### 给定配置
- 隐向量维度 k = 4
- Field数量 F = 7（sex, age, f1, f3, f2, f5, f8）

### FM 特征行字段数
```
1(特征名) + 1(wi) + 4(vi) + 2(w_ni,w_zi) + 4(v_ni) + 4(v_zi)
= 1 + 1 + 4 + 2 + 4 + 4
= 16 ✓
```

### FFM 特征行字段数
```
1(特征名) + 1(wi) + 7×4(vi,每个field) + 2(w_ni,w_zi) + 7×4(v_ni,每个field) + 7×4(v_zi,每个field)
= 1 + 1 + 28 + 2 + 28 + 28
= 88 ✓
```

## 总结

### 模型文件结构差异

| 项目 | FM | FFM |
|------|----|----|
| 第一行 | bias行 | FIELDS行（新增） |
| Bias参数 | wi, w_ni, w_zi | wi, w_ni, w_zi（相同） |
| 特征参数 | 1套隐向量(k维) | F套隐向量(每套k维) |
| 字段数(k=4) | 16 | 88 (F=7时) |
| 参数倍数 | 1x | F倍 |

### 关键差异

1. **FFM多了FIELDS行**：记录所有field的名称
2. **FFM特征参数更多**：每个特征针对每个field都有独立的隐向量
3. **参数量增长**：FFM = FM × F倍（F为field数量）

### 你的理解正确！

✅ FFM 确实是**参数多了维度**（field维度）
✅ 模型文件结构**完全正确**反映了这一点
✅ 88个字段 vs 16个字段，差距5.5倍，符合预期（7个field）

这就是为什么 FFM 效果更好但训练更慢的原因——它学习了更细粒度的特征交互模式！

