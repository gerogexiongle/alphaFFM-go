# FM vs FFM 字段详解

## 配置
- 隐向量维度 k = 4
- Field 数量 F = 7 (sex, age, f1, f3, f2, f5, f8)

## FM 特征行：16 个字段

### 结构
```
特征名 wi vi[0] vi[1] vi[2] vi[3] w_ni w_zi v_ni[0] v_ni[1] v_ni[2] v_ni[3] v_zi[0] v_zi[1] v_zi[2] v_zi[3]
```

### 详细分解（16个字段）
```
位置  | 内容      | 数量 | 说明
------|-----------|------|------------------
1     | 特征名    | 1    | 如 "sex", "age", "f1"
2     | wi        | 1    | 一阶权重
3-6   | vi[0..3]  | 4    | 隐向量（统一的，所有交互共用）
7     | w_ni      | 1    | FTRL参数（w的累积梯度平方和）
8     | w_zi      | 1    | FTRL参数（w的z参数）
9-12  | v_ni[0..3]| 4    | FTRL参数（v的累积梯度平方和）
13-16 | v_zi[0..3]| 4    | FTRL参数（v的z参数）

总计：1 + 1 + 4 + 1 + 1 + 4 + 4 = 16
```

### 示例（特征 sex）
```
sex 0.0347 0 -0.0018 0 0 1.4774 -1.3055 0.0227 0.0034 0.0025 0.0077 -0.0518 0.1468 -0.0568 0.0343
 ^    ^     ^   ^     ^  ^   ^      ^       ^      ^      ^      ^       ^       ^       ^       ^
 名   wi    vi[0] vi[1] vi[2] vi[3] w_ni   w_zi  v_ni[0] v_ni[1] v_ni[2] v_ni[3] v_zi[0] v_zi[1] v_zi[2] v_zi[3]
 1    2      3     4     5     6     7      8      9       10      11      12      13      14      15      16
```

## FFM 特征行：88 个字段

### 结构
```
特征名 wi 
  vi,sex[0..3] vi,age[0..3] vi,f1[0..3] vi,f3[0..3] vi,f2[0..3] vi,f5[0..3] vi,f8[0..3]
  w_ni w_zi
  v_ni,sex[0..3] v_ni,age[0..3] v_ni,f1[0..3] v_ni,f3[0..3] v_ni,f2[0..3] v_ni,f5[0..3] v_ni,f8[0..3]
  v_zi,sex[0..3] v_zi,age[0..3] v_zi,f1[0..3] v_zi,f3[0..3] v_zi,f2[0..3] v_zi,f5[0..3] v_zi,f8[0..3]
```

### 详细分解（88个字段）
```
位置    | 内容                  | 数量      | 说明
--------|----------------------|----------|----------------------------------
1       | 特征名               | 1        | 如 "sex", "age", "f1"
2       | wi                   | 1        | 一阶权重
3-30    | vi,field1..7[0..3]   | 7×4=28   | 针对每个field的隐向量
31      | w_ni                 | 1        | FTRL参数（w的累积梯度平方和）
32      | w_zi                 | 1        | FTRL参数（w的z参数）
33-60   | v_ni,field1..7[0..3] | 7×4=28   | 针对每个field的FTRL参数
61-88   | v_zi,field1..7[0..3] | 7×4=28   | 针对每个field的FTRL参数

总计：1 + 1 + 28 + 1 + 1 + 28 + 28 = 88
```

### 更详细的拆解（每个部分）

#### 第一部分：特征名 + wi（2个字段）
```
位置 1: 特征名（如 "sex"）
位置 2: wi（一阶权重）
```

#### 第二部分：针对7个field的隐向量（28个字段）
```
位置 3-6:   vi,sex[0] vi,sex[1] vi,sex[2] vi,sex[3]     (针对sex field)
位置 7-10:  vi,age[0] vi,age[1] vi,age[2] vi,age[3]     (针对age field)
位置 11-14: vi,f1[0]  vi,f1[1]  vi,f1[2]  vi,f1[3]      (针对f1 field)
位置 15-18: vi,f3[0]  vi,f3[1]  vi,f3[2]  vi,f3[3]      (针对f3 field)
位置 19-22: vi,f2[0]  vi,f2[1]  vi,f2[2]  vi,f2[3]      (针对f2 field)
位置 23-26: vi,f5[0]  vi,f5[1]  vi,f5[2]  vi,f5[3]      (针对f5 field)
位置 27-30: vi,f8[0]  vi,f8[1]  vi,f8[2]  vi,f8[3]      (针对f8 field)

小计：7 fields × 4 维 = 28 个字段
```

#### 第三部分：FTRL参数 w_ni, w_zi（2个字段）
```
位置 31: w_ni（w的累积梯度平方和）
位置 32: w_zi（w的z参数）
```

#### 第四部分：针对7个field的v_ni（28个字段）
```
位置 33-36: v_ni,sex[0..3]  (针对sex field的FTRL参数)
位置 37-40: v_ni,age[0..3]  (针对age field的FTRL参数)
位置 41-44: v_ni,f1[0..3]   (针对f1 field的FTRL参数)
位置 45-48: v_ni,f3[0..3]   (针对f3 field的FTRL参数)
位置 49-52: v_ni,f2[0..3]   (针对f2 field的FTRL参数)
位置 53-56: v_ni,f5[0..3]   (针对f5 field的FTRL参数)
位置 57-60: v_ni,f8[0..3]   (针对f8 field的FTRL参数)

小计：7 fields × 4 维 = 28 个字段
```

#### 第五部分：针对7个field的v_zi（28个字段）
```
位置 61-64: v_zi,sex[0..3]  (针对sex field的FTRL参数)
位置 65-68: v_zi,age[0..3]  (针对age field的FTRL参数)
位置 69-72: v_zi,f1[0..3]   (针对f1 field的FTRL参数)
位置 73-76: v_zi,f3[0..3]   (针对f3 field的FTRL参数)
位置 77-80: v_zi,f2[0..3]   (针对f2 field的FTRL参数)
位置 81-84: v_zi,f5[0..3]   (针对f5 field的FTRL参数)
位置 85-88: v_zi,f8[0..3]   (针对f8 field的FTRL参数)

小计：7 fields × 4 维 = 28 个字段
```

## 为什么是 88 不是 16？

### FM（16个字段）
```
特征 sex 只有：
- 1个一阶权重 wi
- 1套隐向量 vi[4维]
- FTRL参数

所有交互都用同一套隐向量：
sex × age: <v_sex, v_age>
sex × f1:  <v_sex, v_f1>
sex × f2:  <v_sex, v_f2>
```

### FFM（88个字段）
```
特征 sex 有：
- 1个一阶权重 wi
- 7套隐向量（每个field一套，每套4维）
  - v_sex,sex[4维]：与sex field交互时用
  - v_sex,age[4维]：与age field交互时用
  - v_sex,f1[4维]：与f1 field交互时用
  - v_sex,f3[4维]：与f3 field交互时用
  - v_sex,f2[4维]：与f2 field交互时用
  - v_sex,f5[4维]：与f5 field交互时用
  - v_sex,f8[4维]：与f8 field交互时用
- FTRL参数（针对每套隐向量）

不同交互用不同的隐向量：
sex × age: <v_sex,age的field, v_age,sex的field>
sex × f1:  <v_sex,f1的field, v_f1,sex的field>
sex × f2:  <v_sex,f2的field, v_f2,sex的field>
```

## 计算公式

### FM 字段数
```
字段数 = 1(名) + 1(wi) + k(vi) + 2(w_ni,w_zi) + k(v_ni) + k(v_zi)
       = 1 + 1 + k + 2 + k + k
       = 4 + 3k
       
k=4时: 4 + 3×4 = 16 ✓
```

### FFM 字段数
```
字段数 = 1(名) + 1(wi) + F×k(vi) + 2(w_ni,w_zi) + F×k(v_ni) + F×k(v_zi)
       = 1 + 1 + F×k + 2 + F×k + F×k
       = 4 + 3Fk
       
F=7, k=4时: 4 + 3×7×4 = 4 + 84 = 88 ✓
```

## 核心差异

| 项目 | FM | FFM |
|------|----|----|
| 隐向量数量 | 1套 | F套（7套） |
| 每套维度 | k=4 | k=4 |
| 隐向量参数 | 4 | 7×4=28 |
| FTRL参数 | 8 | 2+7×4+7×4=58 |
| 总字段 | 16 | 88 |
| 倍数 | 1x | 5.5x |

## 实际意义

### FM 的隐向量
```
特征 sex 的 vi = [0.1, 0.2, 0.3, 0.4]

这4个数字用于所有交互：
- 和 age 交互
- 和 f1 交互
- 和 f2 交互
...
```

### FFM 的隐向量
```
特征 sex 有7套隐向量（因为有7个field）：

vi,sex = [a1, a2, a3, a4]  用于和 sex field 的特征交互
vi,age = [b1, b2, b3, b4]  用于和 age field 的特征交互
vi,f1  = [c1, c2, c3, c4]  用于和 f1 field 的特征交互
vi,f3  = [d1, d2, d3, d4]  用于和 f3 field 的特征交互
vi,f2  = [e1, e2, e3, e4]  用于和 f2 field 的特征交互
vi,f5  = [f1, f2, f3, f4]  用于和 f5 field 的特征交互
vi,f8  = [g1, g2, g3, g4]  用于和 f8 field 的特征交互

总共 7×4 = 28 个数字
```

## 总结

88 个字段 = 1(名称) + 1(wi) + 28(7套隐向量) + 2(FTRL) + 28(7套v_ni) + 28(7套v_zi)

**关键**：FFM 的 field 数量（7个）决定了参数倍增，每增加1个field，每个特征的参数就增加3k个（k=4时增加12个）。

