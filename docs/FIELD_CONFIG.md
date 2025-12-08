# Field Configuration 域配置文档

## 概述

alphaFFM-go 支持三种样本输入格式：

1. **FFM 格式（显式域名）**: `label field1:feature1:value1 field2:feature2:value2 ...`
   - 例如: `1 user:sex:1 user:age:0.3 item:f1:1 item:f3:0.9`

2. **FM 格式（无域名）**: `label feature1:value1 feature2:value2 ...`
   - 例如: `1 sex:1 age:0.3 f1:1 f3:0.9`

3. **混合格式**: 两种格式可以在同一行混用

4. **数字特征编码格式**: 大数字特征（>= 2^32）自动提取高32位作为域ID
   - 例如: `1 51539607553:1 55834574849:1 sex:1 age:0.3`
   - `51539607553` (0x0000000C00000001) → 域ID = 12 → 域名 `field_12`

当使用 FM 格式时，系统需要将特征映射到域（field）。有三种映射模式：

## 映射模式

### 特殊规则：数字特征自动域提取（优先级最高）

**业务规范**: 当特征名是全数字且 >= 2^32 (4294967296) 时，自动提取高32位作为域ID。

**编码规则**:
- 特征编码 = (域ID << 32) | 特征ID
- 高32位：域ID
- 低32位：特征ID

**示例**:
```
特征: 51539607553
二进制: 0x0000000C00000001
域ID (高32位): 12
特征ID (低32位): 1
域名: field_12
```

**常见特征编码**:
| 特征值 | 域ID | 特征ID | 域名 |
|--------|------|--------|------|
| 51539607553 | 12 | 1 | field_12 |
| 55834574849 | 13 | 1 | field_13 |
| 60129542145 | 14 | 1 | field_14 |
| 64 | 0 | 64 | 使用配置映射 |

**优势**:
- 无需配置，自动提取
- 支持海量域（2^32 个域）
- 与业务特征编码规范完美匹配

### 1. Auto 模式（默认）

不使用配置文件时的默认行为：
- 如果特征名包含下划线，提取第一部分作为域名
  - 例如: `user_id` → field = `user`, `item_category` → field = `item`
- 否则，特征名本身作为域名
  - 例如: `sex` → field = `sex`, `age` → field = `age`

**优点**: 无需配置，简单快速  
**缺点**: 对于简单特征名（如 f1, f2），每个特征都是独立的域，参数量大

### 2. Explicit 模式

样本中显式包含域名信息（标准 FFM 格式）：
```
1 user:sex:1 user:age:0.3 item:f1:1 item:f3:0.9
```

**优点**: 最灵活，完全控制  
**缺点**: 样本文件体积大，需要显式构造域名

### 3. Config 模式（推荐）

使用配置文件将特征映射到域，支持 FM 格式样本：
```
1 sex:1 age:0.3 f1:1 f3:0.9
```

**优点**: 
- 样本文件简洁（FM 格式）
- 灵活控制特征到域的映射
- 减少参数量，提高训练效率

**缺点**: 需要额外的配置文件

## 配置文件格式

### 文本格式（推荐）

简单易读的文本格式：

```
# field_config.txt
# 格式: feature_prefix field_name

# 用户特征 -> user 域
sex user
age user
user_id user

# 商品特征 -> item 域
f1 item
f2 item
f3 item

# 上下文特征 -> context 域
f5 context
f8 context
```

**规则**:
- 每行一个映射规则：`feature_prefix field_name`
- `#` 开头的行为注释
- 支持前缀匹配：`user_` 可以匹配 `user_id`, `user_age` 等

### JSON 格式

更灵活的 JSON 格式：

```json
{
  "mode": "config",
  "use_prefix": true,
  "default_field": "other",
  "feature_to_field": {
    "sex": "user",
    "age": "user",
    "user_": "user",
    "f1": "item",
    "f2": "item",
    "f3": "item",
    "item_": "item",
    "f5": "context",
    "f8": "context"
  }
}
```

**参数说明**:
- `mode`: 模式，可选值 `auto`, `explicit`, `config`
- `use_prefix`: 是否使用前缀匹配（true: 前缀匹配, false: 完全匹配）
- `default_field`: 默认域名（当特征无法匹配时使用，空字符串表示降级到 auto 模式）
- `feature_to_field`: 特征到域的映射字典

## 使用方法

### 训练时使用配置文件

```bash
cat train_data.txt | ./ffm_train \
  -m model.txt \
  -field_config field_config.txt \
  -dim 1,1,8
```

### 预测时使用配置文件

```bash
cat test_data.txt | ./ffm_predict \
  -m model.txt \
  -out predictions.txt \
  -field_config field_config.txt \
  -dim 8
```

**注意**: 训练和预测必须使用相同的配置文件！

## 实际案例

### 案例 1: CTR 预测

**样本格式** (FM 格式):
```
1 user_123:1 age_25:1 item_456:1 category_electronics:1 hour_14:1
0 user_456:1 age_35:1 item_789:1 category_books:1 hour_9:1
```

**配置文件**:
```
user_ user
age_ user
item_ item
category_ item
hour_ context
day_ context
```

**效果**:
- `user_123`, `age_25` → `user` 域
- `item_456`, `category_electronics` → `item` 域
- `hour_14` → `context` 域

### 案例 2: 推荐系统

**样本格式** (FM 格式):
```
1 sex:1 age:0.3 f1:1 f3:0.9 f5:0.8
```

**配置文件**:
```
sex user
age user
f1 item
f2 item
f3 item
f5 context
f8 context
```

**效果**:
- `sex`, `age` → `user` 域
- `f1`, `f3` → `item` 域
- `f5` → `context` 域

### 案例 3: 数字特征编码（推荐）

**样本格式** (混合格式):
```
1 51539607553:1 55834574849:1 60129542145:0.5 sex:1 age:0.3
0 51539607554:1 55834574850:1 f1:1 f2:0.4
```

**配置文件** (仅配置小特征):
```
sex user
age user
f1 item
f2 item
```

**效果**:
- `51539607553` → `field_12` (自动提取)
- `55834574849` → `field_13` (自动提取)
- `60129542145` → `field_14` (自动提取)
- `sex`, `age` → `user` 域 (配置映射)
- `f1`, `f2` → `item` 域 (配置映射)

**优势**:
- 大数字特征无需配置，自动提取域ID
- 小特征灵活配置
- 完美支持业务编码规范

## 最佳实践

1. **域的设计原则**:
   - 按特征的语义分组（用户、商品、上下文等）
   - 同一域内的特征应该具有相似的语义
   - 域的数量建议在 3-10 个之间

2. **前缀匹配 vs 完全匹配**:
   - 前缀匹配：适合有规律命名的特征（如 `user_id`, `user_age`）
   - 完全匹配：适合特征名较短或无规律的情况

3. **默认域的使用**:
   - 设置 `default_field` 可以捕获未明确映射的特征
   - 留空则降级到 auto 模式

4. **训练和预测一致性**:
   - 训练和预测必须使用完全相同的配置文件
   - 建议将配置文件与模型文件放在一起

## 性能对比

| 模式 | 参数量 | 训练速度 | 样本大小 | 适用场景 |
|------|--------|----------|----------|----------|
| Auto | 大 | 慢 | 小 | 快速实验 |
| Explicit | 中 | 中 | 大 | 完全控制 |
| Config | 小 | 快 | 小 | 生产环境（推荐）|

**参数量说明**: 
- 假设有 n 个特征，k 个域
- Auto 模式: 每个特征是独立的域，参数量 ≈ O(n² × d)，其中 d 是隐向量维度
- Config 模式: 特征映射到 k 个域，参数量 ≈ O(n × k × d)
- 当 k << n 时，Config 模式可以大幅减少参数量

## 故障排查

### 问题 1: 配置文件加载失败

**错误信息**: `Warning: failed to load field config`

**解决方法**:
1. 检查文件路径是否正确
2. 检查文件格式（JSON 或文本格式）
3. 对于 JSON 格式，检查语法是否正确

### 问题 2: 训练和预测结果不一致

**原因**: 训练和预测使用了不同的配置文件或配置不一致

**解决方法**:
1. 确保训练和预测使用相同的配置文件
2. 将配置文件与模型一起保存

### 问题 3: 参数量过大

**原因**: 使用 Auto 模式或域的数量设置过多

**解决方法**:
1. 使用 Config 模式合理分组特征
2. 减少域的数量，合并语义相似的域

## 总结

推荐使用 **Config 模式 + 文本配置文件** 的组合：
1. 样本文件使用简洁的 FM 格式
2. 通过配置文件灵活控制特征到域的映射
3. 减少参数量，提高训练和预测效率
4. 保持样本文件的简洁性和可读性

